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
    final data = rawValue is Map ? Map<Object?, Object?>.from(rawValue) : <Object?, Object?>{};

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

    _currentCallId = callId;
    debugPrint('[ChittiLiveCall] Started outgoing call: $callId');
    return callId;
  }

  /// Listens to a specific active call's state changes
  Stream<ChittiLiveCallState?> watchCall(String callId) {
    return _calls.child(callId).onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists) return null;
      return ChittiLiveCallState.fromSnapshot(snap);
    });
  }

  /// Listens for incoming ringing calls (Used in Admin App)
  Stream<List<ChittiLiveCallState>> watchIncomingRingingCalls() {
    return _calls.orderByChild('status').equalTo('ringing').onValue.map((event) {
      final snap = event.snapshot;
      if (!snap.exists) return <ChittiLiveCallState>[];
      return snap.children.map(ChittiLiveCallState.fromSnapshot).toList();
    });
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
  Future<void> answerCallChitti(String callId, {required String adminId}) async {
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
    try {
      final callRef = _calls.child(callId);
      await callRef.child('liveTranscript').push().set(speakerAndText);
      await callRef.update({
        'lastSpokenText': speakerAndText,
        'updatedAt': ServerValue.timestamp,
      });
    } catch (e) {
      debugPrint('[ChittiLiveCall] Failed to append transcript: $e');
    }
  }

  /// Ends an active call
  Future<void> endCall(String callId) async {
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
}
