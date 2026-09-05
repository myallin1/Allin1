// ================================================================
// chitti_live_call_service.dart — In-App Customer ↔ Admin Live Calling & Takeover
// ================================================================
// Manages real-time live calling between Customer App and Admin App
// using Firestore `active_calls` sessions (signaling & state sync).
//
// Key Capabilities:
// 1. Customer initiates in-app call -> status: 'ringing'.
// 2. Admin receives live incoming call alert with ringtone & full-screen UI.
// 3. Admin can:
//    - Answer (Direct live voice mode)
//    - Let Chitti Handle (AI receptionist mode with live transcript stream)
//    - Take Over (Barge-in mid-call and take the microphone)
// 4. Zero recurring server cost: uses Firestore snapshot streams and
//    Google's free STUN network.
// ================================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  static ChittiLiveCallState fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? <String, dynamic>{};
    final rawTs = data['createdAt'];
    DateTime dt = DateTime.now();
    if (rawTs is Timestamp) {
      dt = rawTs.toDate();
    }

    final rawList = data['liveTranscript'];
    final List<String> transcript = rawList is List ? rawList.map((e) => e.toString()).toList() : <String>[];

    return ChittiLiveCallState(
      callId: doc.id,
      callerId: data['callerId'] as String? ?? 'unknown',
      callerName: data['callerName'] as String? ?? 'Customer',
      callerPhone: data['callerPhone'] as String? ?? '',
      status: data['status'] as String? ?? 'ringing',
      handlingMode: data['handlingMode'] as String? ?? 'chitti',
      createdAt: dt,
      acceptedBy: data['acceptedBy'] as String?,
      liveTranscript: transcript,
      lastSpokenText: data['lastSpokenText'] as String?,
    );
  }
}

class ChittiLiveCallService {
  ChittiLiveCallService._();
  static final ChittiLiveCallService instance = ChittiLiveCallService._();

  CollectionReference<Map<String, dynamic>> get _calls =>
      FirebaseFirestore.instance.collection('active_calls');

  String? _currentCallId;
  String? get currentCallId => _currentCallId;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _callSub;

  /// Starts a new outgoing in-app call from Customer to Admin
  Future<String> startOutgoingCall({
    required String callerId,
    required String callerName,
    String? callerPhone,
  }) async {
    final docRef = await _calls.add({
      'callerId': callerId,
      'callerName': callerName,
      'callerPhone': callerPhone ?? '',
      'status': 'ringing',
      'handlingMode': 'chitti',
      'createdAt': FieldValue.serverTimestamp(),
      'liveTranscript': <String>[],
      'lastSpokenText': null,
    });

    _currentCallId = docRef.id;
    debugPrint('[ChittiLiveCall] Started outgoing call: ${docRef.id}');
    return docRef.id;
  }

  /// Listens to a specific active call's state changes
  Stream<ChittiLiveCallState?> watchCall(String callId) {
    return _calls.doc(callId).snapshots().map((doc) {
      if (!doc.exists) return null;
      return ChittiLiveCallState.fromDoc(doc);
    });
  }

  /// Listens for incoming ringing calls (Used in Admin App)
  Stream<List<ChittiLiveCallState>> watchIncomingRingingCalls() {
    return _calls
        .where('status', isEqualTo: 'ringing')
        .snapshots()
        .map((snapshot) {
      return snapshot.docs.map((doc) => ChittiLiveCallState.fromDoc(doc)).toList();
    });
  }

  /// Admin answers the call directly in human voice mode
  Future<void> answerCallHuman(String callId, {required String adminId}) async {
    await _calls.doc(callId).update({
      'status': 'connected',
      'handlingMode': 'human',
      'acceptedBy': adminId,
      'answeredAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[ChittiLiveCall] Admin answered call in HUMAN mode: $callId');
  }

  /// Admin assigns the call to Chitti AI automated receptionist
  Future<void> answerCallChitti(String callId, {required String adminId}) async {
    await _calls.doc(callId).update({
      'status': 'chitti_handling',
      'handlingMode': 'chitti',
      'acceptedBy': adminId,
      'answeredAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[ChittiLiveCall] Admin assigned call to CHITTI mode: $callId');
  }

  /// Admin takes over a call that Chitti is currently handling
  Future<void> takeOverCall(String callId, {required String adminId}) async {
    await _calls.doc(callId).update({
      'status': 'connected',
      'handlingMode': 'human',
      'acceptedBy': adminId,
      'tookOverAt': FieldValue.serverTimestamp(),
    });
    debugPrint('[ChittiLiveCall] Admin took over call from Chitti: $callId');
  }

  /// Appends a dialogue turn to the live transcript stream
  Future<void> appendTranscript(String callId, String speakerAndText) async {
    try {
      await _calls.doc(callId).update({
        'liveTranscript': FieldValue.arrayUnion([speakerAndText]),
        'lastSpokenText': speakerAndText,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ChittiLiveCall] Failed to append transcript: $e');
    }
  }

  /// Ends an active call
  Future<void> endCall(String callId) async {
    try {
      await _calls.doc(callId).update({
        'status': 'ended',
        'endedAt': FieldValue.serverTimestamp(),
      });
      if (_currentCallId == callId) {
        _currentCallId = null;
      }
      _callSub?.cancel();
      _callSub = null;
      debugPrint('[ChittiLiveCall] Call ended: $callId');
    } catch (e) {
      debugPrint('[ChittiLiveCall] Error ending call: $e');
    }
  }
}
