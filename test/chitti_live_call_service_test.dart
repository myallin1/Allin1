import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_live_call_service.dart';

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
}
