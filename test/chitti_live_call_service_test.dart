import 'package:erode_superapp/services/chitti/chitti_live_call_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ChittiLiveCallState', () {
    test('constructs correctly with properties', () {
      final now = DateTime.now();
      final state = ChittiLiveCallState(
        callId: 'call_abc_123',
        callerId: 'user_456',
        callerName: 'Priya',
        callerPhone: '9876543210',
        status: 'ringing',
        handlingMode: 'chitti',
        createdAt: now,
        liveTranscript: const ['Chitti: வணக்கம்', 'Customer: போன் டிஸ்பிளே உடைஞ்சிருச்சு'],
      );

      expect(state.callId, 'call_abc_123');
      expect(state.callerName, 'Priya');
      expect(state.status, 'ringing');
      expect(state.handlingMode, 'chitti');
      expect(state.liveTranscript.length, 2);
    });
  });

  group('ChittiLiveCallState.fromRtdbData (RTDB migration)', () {
    test('parses a call node the shape RTDB actually stores', () {
      // Shaped exactly like what ChittiLiveCallService writes:
      // ServerValue.timestamp resolves to an int (ms since epoch) once
      // committed, and liveTranscript is a child map of push() keys ->
      // text, not an array — RTDB has no arrayUnion.
      final state = ChittiLiveCallState.fromRtdbData('call_xyz', {
        'callerId': 'user_789',
        'callerName': 'Kavya',
        'callerPhone': '9000012345',
        'status': 'chitti_handling',
        'handlingMode': 'chitti',
        'createdAt': 1735689600000,
        'liveTranscript': {
          '-Nabc002': 'Chitti: வணக்கம் பாஸ்',
          '-Nabc001': 'Customer: போன் டிஸ்பிளே உடைஞ்சிருச்சு',
        },
      });

      expect(state.callId, 'call_xyz');
      expect(state.callerName, 'Kavya');
      expect(state.status, 'chitti_handling');
      expect(state.createdAt, DateTime.fromMillisecondsSinceEpoch(1735689600000));
      // Push keys sort chronologically as strings — the earlier turn
      // (-Nabc001) must come first regardless of Map insertion order.
      expect(state.liveTranscript, [
        'Customer: போன் டிஸ்பிளே உடைஞ்சிருச்சு',
        'Chitti: வணக்கம் பாஸ்',
      ]);
    });

    test('falls back to defaults when the node is missing or empty', () {
      final missing = ChittiLiveCallState.fromRtdbData('call_gone', null);
      expect(missing.status, 'ringing');
      expect(missing.handlingMode, 'chitti');
      expect(missing.liveTranscript, isEmpty);

      final empty = ChittiLiveCallState.fromRtdbData('call_empty', <Object?, Object?>{});
      expect(empty.callerName, 'Customer');
      expect(empty.liveTranscript, isEmpty);
    });
  });
}
