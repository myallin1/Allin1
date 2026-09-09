// ================================================================
// chitti_live_call_service.dart — In-App Customer ↔ Admin Live Calling & Takeover
// ================================================================
// Manages real-time live calling between Customer App and Admin App
// using Firebase Realtime Database `active_calls` sessions (signaling
// & state sync).
//
// WHY RTDB, NOT FIRESTORE (migrated Sep 2026 — Nizam's call)
// This node changes many times a second during a live conversation
// (every transcript turn, every status flip) and is read by up to two
// simultaneous listeners (customer + admin) the whole time a call is
// open. Firestore bills every one of those as a counted read/write
// against a daily quota; RTDB bills on bandwidth, not operation count,
// and its WebSocket transport has materially lower round-trip latency
// for exactly this "many small updates, low latency" shape — the same
// reason online_heroes/hero_pings (live bike-taxi radar) already live
// on RTDB rather than Firestore. Permanent records (the actual call
// log) still go to Firestore via ChittiCallServiceLog.logCall() — RTDB
// is for what's happening right now, Firestore is for what happened.
//
// Key Capabilities:
// 1. Customer initiates in-app call -> status: 'ringing'.
// 2. Admin receives live incoming call alert with ringtone & full-screen UI.
// 3. Admin can:
//    - Answer (Direct live voice mode)
//    - Let Chitti Handle (AI receptionist mode with live transcript stream)
//    - Take Over (Barge-in mid-call and take the microphone)
// 4. Zero recurring server cost: uses RTDB streams and Google's free
//    STUN network.
// ================================================================

import 'dart:async';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';

class ChittiLiveCallState {
  const ChittiLiveCallState({
    required this.callId,
    required this.callerId,
    required this.callerName,
    required this.callerPhone,
    required this.status,
    required this.handlingMode,
    required this.createdAt,
    this.acceptedBy,
    this.liveTranscript = const <String>[],
    this.lastSpokenText,
  });

  final String callId;
  final String callerId;
  final String callerName;
  final String callerPhone;
  final String status; // 'ringing', 'connected', 'chitti_handling', 'ended'
  final String handlingMode; // 'human', 'chitti'
  final DateTime createdAt;
  final String? acceptedBy;
  final List<String> liveTranscript;
  final String? lastSpokenText;

  /// Builds state from an RTDB snapshot at `active_calls/{callId}`.
  ///
  /// The transcript is stored as a CHILD MAP of push-generated keys ->
  /// text, not an array field: RTDB has no Firestore-style
  /// `arrayUnion`, so appending to an array field would mean reading
  /// the whole array, appending locally, and writing it back — a race
  /// between the customer's and admin's own writes. A push() key is
  /// server-assigned, collision-free, and (by construction) sorts
  /// chronologically as a plain string, so children.entries sorted by
  /// key reproduce turn order without ever reading-before-writing.
  factory ChittiLiveCallState.fromSnapshot(DataSnapshot snap) =>
      ChittiLiveCallState.fromRtdbData(snap.key ?? 'unknown', snap.value);

  /// The actual parsing logic, split out from `fromSnapshot` so it can
  /// be unit-tested directly on a plain Map — firebase_database's
  /// `DataSnapshot` is a concrete platform-backed type with no fake/mock
  /// package in this project (unlike cloud_firestore's fakeable
  /// DocumentSnapshot), so a test can't construct one without a real
  /// Firebase app. This factory takes exactly what `snap.key` and
  /// `snap.value` would hand it, so the test below exercises the real
  /// parsing rules, not a stand-in for them.
  factory ChittiLiveCallState.fromRtdbData(String callId, Object? rawValue) {
    final data = rawValue is Map
        ? Map<Object?, Object?>.from(rawValue)
        : <Object?, Object?>{};

    DateTime parseTimestamp(Object? value) {
      if (value is int) return DateTime.fromMillisecondsSinceEpoch(value);
      return DateTime.now();
    }

    final rawTranscript = data['liveTranscript'];
    final List<String> transcript = [];
    if (rawTranscript is Map) {
      final entries = rawTranscript.entries.toList()
        ..sort((a, b) => a.key.toString().compareTo(b.key.toString()));
      transcript.addAll(entries.map((e) => e.value.toString()));
    }

    return ChittiLiveCallState(
      callId: callId,
      callerId: data['callerId'] as String? ?? 'unknown',
      callerName: data['callerName'] as String? ?? 'Customer',
      callerPhone: data['callerPhone'] as String? ?? '',
      status: data['status'] as String? ?? 'ringing',
      handlingMode: data['handlingMode'] as String? ?? 'chitti',
      createdAt: parseTimestamp(data['createdAt']),
      acceptedBy: data['acceptedBy'] as String?,
      liveTranscript: transcript,
      lastSpokenText: data['lastSpokenText'] as String?,
    );
  }
}

class ChittiLiveCallService {
  ChittiLiveCallService._();
  static final ChittiLiveCallService instance = ChittiLiveCallService._();

  DatabaseReference get _calls => FirebaseDatabase.instance.ref('active_calls');

  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  StreamSubscription<DatabaseEvent>? _callSub;

  // FIX (Sep 6 2026 audit — "zombie call resurrects the admin lock-
  // screen alert"): cleanupCall() removes the whole `active_calls/
  // {callId}` node, but a still-in-flight appendTranscript() (or any
  // other update() call queued from an earlier turn) can land AFTER
  // that remove() completes — RTDB has no ordering guarantee between
  // two independent async calls from the same client once both are in
  // flight. A .update()/.child().set() on a path that no longer exists
  // simply CREATES it fresh, with only whatever few fields that one
  // write touched — no `status`, so ChittiLiveCallState.fromRtdbData
  // defaults it to 'ringing', which the admin app's incoming-call
  // watchers treat as a brand-new call and alert on.
  //
  // Tracking ended call ids locally (this is a singleton within one
  // app process, and cleanupCall/appendTranscript for one call are
  // always called from the SAME process — the customer app that owns
  // that call) means every mutating method below can check "did I
  // already tear this call down?" before writing, and simply skip if
  // so, instead of resurrecting a corpse.
  final Set<String> _endedCallIds = <String>{};

  bool _isEnded(String callId) => _endedCallIds.contains(callId);

  /// Starts a new outgoing in-app call from Customer to Admin
  Future<String> startOutgoingCall({
    required String callerId,
    required String callerName,
    String? callerPhone,
  }) async {
    final ref = _calls.push();
    final callId = ref.key!;
    await ref.set({
      'callerId': callerId,
      'callerName': callerName,
      'callerPhone': callerPhone ?? '',
      'status': 'ringing',
      'handlingMode': 'chitti',
      'createdAt': ServerValue.timestamp,
    });

    // FIX (Sep 8 2026 — database wastage/leakage audit): cleanupCall()
    // is the ONLY thing that ever deletes this node, and it has exactly
    // ONE call site in the whole app — chitti_call_screen.dart's
    // _logCallAndCleanup(), reached only through the graceful
    // _endCall() path. If the app is force-closed, crashes, or the OS
    // kills it mid-call, dispose() runs at most (and often not even
    // that, on a hard kill) — cleanupCall() never fires, and this node
    // (plus every liveTranscript child appendTranscript() wrote for it)
    // sits in RTDB forever. No Cloud Function exists in this project to
    // sweep it later (Spark plan). onDisconnect() is the Firebase-native
    // answer to exactly this: the SERVER removes this node the moment
    // it detects the client's connection actually dropped, with no
    // client code needing to run at all. Safe to hard-remove here (not
    // just mark 'ended' the way endCall() does): a client that has
    // truly disconnected can never call logCall() to persist the
    // transcript anyway, so there is nothing left to protect by
    // deferring the delete — same trade-off any client-only signaling
    // node accepts.
    unawaited(ref.onDisconnect().remove());

    _currentCallId = callId;
    debugPrint('[ChittiLiveCall] Started outgoing call: $callId');
    return callId;
  }

  /// Listens to a specific active call's state changes.
  ///
  /// NEW (Sep 10 2026 — Nizam: "rtdb la live listening vacha quota
  /// mudinjurum ... same database bandwith ah carefula waste agama
  /// handle pananum"). The old version was one `.onValue` on the whole
  /// call node — RTDB's `.onValue` re-sends the ENTIRE current value on
  /// every single write, and `liveTranscript` only ever grows during a
  /// call, so a 10-turn call re-downloaded turn 1's text nine more
  /// times, turn 2's text eight more times, and so on. Every open
  /// `watchCall` (customer + admin, for the whole call) paid that cost.
  ///
  /// This splits the one expensive listener into three cheap ones and
  /// merges them into the same local snapshot in memory:
  ///   - `status` alone (tiny field) — also the ended/removed signal,
  ///     since a listener on a child of a deleted node reports
  ///     non-existence same as any other.
  ///   - the other scalar fields via `onChildChanged`/`onChildAdded` on
  ///     the call node, skipping the `liveTranscript` key (handled
  ///     below) so those events never carry the growing transcript.
  ///   - `liveTranscript` via `onChildAdded` on ITS OWN path — RTDB
  ///     delivers exactly the one new entry per event, never the
  ///     entries already seen, which is the actual fix: turn N's text
  ///     is downloaded once, not N more times as the call goes on.
  Stream<ChittiLiveCallState?> watchCall(String callId) {
    final controller = StreamController<ChittiLiveCallState?>.broadcast();
    final callRef = _calls.child(callId);
    final fields = <String, Object?>{};
    final transcript = <String, String>{};
    var initialized = false;
    var ended = false;
    final subs = <StreamSubscription<DatabaseEvent>>[];

    void emit() {
      if (controller.isClosed || !initialized) return;
      if (ended) {
        controller.add(null);
        return;
      }
      controller.add(
        ChittiLiveCallState.fromRtdbData(
            callId, {...fields, 'liveTranscript': transcript}),
      );
    }

    () async {
      final snap = await callRef.get();
      if (!snap.exists) {
        initialized = true;
        ended = true;
        emit();
        return;
      }
      final data = Map<Object?, Object?>.from(snap.value as Map);
      final rawTranscript = data.remove('liveTranscript');
      if (rawTranscript is Map) {
        rawTranscript
            .forEach((k, v) => transcript[k.toString()] = v.toString());
      }
      fields.addAll(data.map((k, v) => MapEntry(k.toString(), v)));
      initialized = true;
      emit();

      subs.add(callRef.child('status').onValue.listen((event) {
        if (!event.snapshot.exists) {
          ended = true;
          emit();
          return;
        }
        fields['status'] = event.snapshot.value;
        emit();
      }));

      void onScalarChange(DatabaseEvent event) {
        final key = event.snapshot.key;
        if (key == null || key == 'liveTranscript' || key == 'status') return;
        fields[key] = event.snapshot.value;
        emit();
      }

      subs.add(callRef.onChildChanged.listen(onScalarChange));
      subs.add(callRef.onChildAdded.listen(onScalarChange));

      subs.add(callRef.child('liveTranscript').onChildAdded.listen((event) {
        final key = event.snapshot.key;
        if (key == null) return;
        transcript[key] = event.snapshot.value.toString();
        emit();
      }));
    }();

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      await controller.close();
    };
    return controller.stream;
  }

  /// Listens for active incoming calls (ringing or being handled by
  /// Chitti, used in Admin App).
  ///
  /// NEW (Sep 10 2026 — same bandwidth audit as watchCall() above):
  /// `.onValue` on the WHOLE `active_calls` collection meant any single
  /// change to any one call — a new transcript turn on a call the
  /// admin isn't even looking at — re-downloaded every OTHER active
  /// call's full data too. `onChildAdded`/`onChildChanged`/
  /// `onChildRemoved` each carry only the ONE call node that actually
  /// changed; a local cache is kept and re-filtered/re-emitted on every
  /// event so callers still see the full current list each time.
  Stream<List<ChittiLiveCallState>> watchIncomingRingingCalls() {
    final controller = StreamController<List<ChittiLiveCallState>>.broadcast();
    final cache = <String, ChittiLiveCallState>{};
    final subs = <StreamSubscription<DatabaseEvent>>[];

    void emit() {
      if (controller.isClosed) return;
      controller.add(
        cache.values
            .where(
                (s) => s.status == 'ringing' || s.status == 'chitti_handling')
            .toList(),
      );
    }

    void upsert(DatabaseEvent event) {
      final key = event.snapshot.key;
      if (key == null) return;
      cache[key] = ChittiLiveCallState.fromSnapshot(event.snapshot);
      emit();
    }

    () async {
      final snap = await _calls.get();
      if (snap.exists) {
        for (final child in snap.children) {
          final key = child.key;
          if (key == null) continue;
          cache[key] = ChittiLiveCallState.fromSnapshot(child);
        }
      }
      emit();

      subs.add(_calls.onChildAdded.listen(upsert));
      subs.add(_calls.onChildChanged.listen(upsert));
      subs.add(_calls.onChildRemoved.listen((event) {
        final key = event.snapshot.key;
        if (key == null) return;
        cache.remove(key);
        emit();
      }));
    }();

    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      await controller.close();
    };
    return controller.stream;
  }

  /// Admin answers the call directly in human voice mode
  Future<void> answerCallHuman(String callId, {required String adminId}) async {
    await _calls.child(callId).update({
      'status': 'connected',
      'handlingMode': 'human',
      'acceptedBy': adminId,
      'answeredAt': ServerValue.timestamp,
    });
    debugPrint('[ChittiLiveCall] Admin answered call in HUMAN mode: $callId');
  }

  /// Admin assigns the call to Chitti AI automated receptionist
  Future<void> answerCallChitti(String callId,
      {required String adminId}) async {
    await _calls.child(callId).update({
      'status': 'chitti_handling',
      'handlingMode': 'chitti',
      'acceptedBy': adminId,
      'answeredAt': ServerValue.timestamp,
    });
    debugPrint('[ChittiLiveCall] Admin assigned call to CHITTI mode: $callId');
  }

  /// Admin takes over a call that Chitti is currently handling
  Future<void> takeOverCall(String callId, {required String adminId}) async {
    await _calls.child(callId).update({
      'status': 'connected',
      'handlingMode': 'human',
      'acceptedBy': adminId,
      'tookOverAt': ServerValue.timestamp,
    });
    debugPrint('[ChittiLiveCall] Admin took over call from Chitti: $callId');
  }

  /// Appends a dialogue turn to the live transcript stream
  Future<void> appendTranscript(String callId, String speakerAndText) async {
    if (_isEnded(callId)) return;
    try {
      final callRef = _calls.child(callId);
      await callRef.child('liveTranscript').push().set(speakerAndText);
      // FIX (Sep 6 2026 re-re-audit): the entry check above only closes
      // the race where cleanupCall() already ran BEFORE this method
      // started. It does nothing for cleanupCall() landing DURING the
      // gap between these two awaits — the push().set() above can
      // itself resurrect the node (writing to a nested RTDB path
      // recreates any missing ancestor), and this second write would
      // then still go through even though the call was torn down a
      // moment ago. Re-checking right before this write closes that
      // narrower window too.
      if (_isEnded(callId)) return;
      await callRef.update({
        'lastSpokenText': speakerAndText,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[ChittiLiveCall] Failed to append transcript: $e');
    }
  }

  /// Ends an active call
  ///
  /// This only WRITES a status — it does not delete the node. That
  /// distinction matters: this is the signal the OTHER party's
  /// `watchCall` listener reacts to (e.g. admin rejecting a call is the
  /// only way the customer's own screen finds out and runs its own
  /// logCall + cleanupCall, since only the customer's device holds the
  /// transcript/intents to log). Deleting here would remove the node
  /// before whichever side still needs to read it has had the chance.
  Future<void> endCall(String callId) async {
    _endedCallIds.add(callId);
    try {
      await _calls.child(callId).update({
        'status': 'ended',
        'endedAt': ServerValue.timestamp,
      });
      if (_currentCallId == callId) {
        _currentCallId = null;
      }
      unawaited(_callSub?.cancel());
      _callSub = null;
      debugPrint('[ChittiLiveCall] Call ended: $callId');
    } catch (e) {
      debugPrint('[ChittiLiveCall] Error ending call: $e');
    }
  }

  /// Marks that Chitti itself has started actively handling the call —
  /// called the moment the customer's own voice engine is confirmed
  /// ready, BEFORE the greeting is spoken. Purely informational RTDB
  /// status for anything watching the live call; a distinct path from
  /// answerCallChitti(), which is an ADMIN action with an adminId —
  /// this one has no admin behind it at all.
  Future<void> markChittiAutoAnswered(String callId) async {
    if (_isEnded(callId)) return;
    // FIX (Sep 6 2026 audit — "out-of-order network delivery can revert
    // an admin takeover"): this used to be a bare `.update()`, fired
    // unawaited right after startOutgoingCall() returns. RTDB does not
    // order writes from two different client connections by wall-clock
    // time, only by arrival at the server — so on a slow customer
    // connection, this write can arrive AFTER an admin's
    // takeOverCall()/answerCallHuman() write and silently stomp
    // `status`/`handlingMode` back to Chitti, even though a human is
    // already on the line. A `runTransaction` makes this compare-and-
    // swap: it only ever applies when the node is still exactly what
    // this call expects to be overwriting (freshly created, nobody has
    // acted on it yet) — any state written by an admin action in the
    // meantime is left alone.
    try {
      await _calls.child(callId).runTransaction((Object? current) {
        final data =
            current is Map ? Map<Object?, Object?>.from(current) : null;
        final status = data?['status'] as String?;
        // Only advance from the pre-answer state this call expects.
        // 'ringing' (brand new) or already 'chitti_handling' (e.g. a
        // retry of this exact call) are both fine to (re)stamp; anything
        // else means an admin action already moved the call on, and
        // this write must not touch it.
        if (status != null &&
            status != 'ringing' &&
            status != 'chitti_handling') {
          return Transaction.success(current);
        }
        return Transaction.success({
          ...?data,
          'status': 'chitti_handling',
          'handlingMode': 'chitti',
          'answeredAt': ServerValue.timestamp,
        });
      });
    } catch (e) {
      debugPrint('[ChittiLiveCall] Error marking Chitti auto-answered: $e');
    }
  }

  /// Permanently deletes the ephemeral signaling node. Call ONLY after
  /// the permanent record (ChittiCallServiceLog.logCall) has already
  /// completed — this is the actual RTDB storage reclaim; endCall()
  /// above only ever writes a status, it never removes anything.
  Future<void> cleanupCall(String callId) async {
    _endedCallIds.add(callId);
    try {
      final ref = _calls.child(callId);
      // Hygiene: this call is being torn down through the normal,
      // graceful path — cancel the onDisconnect() armed in
      // startOutgoingCall() so it doesn't sit registered on the server
      // for a node that's about to be gone anyway. Harmless either way
      // (removing an already-gone path is a no-op), but leaving a
      // fired-and-forgotten disconnect hook armed past the point it's
      // needed is exactly the kind of loose end this audit is for.
      unawaited(ref.onDisconnect().cancel());
      await ref.remove();
      if (_currentCallId == callId) {
        _currentCallId = null;
      }
      debugPrint('[ChittiLiveCall] Cleaned up call node: $callId');
    } catch (e) {
      debugPrint('[ChittiLiveCall] Error cleaning up call node: $e');
    }
  }
}
