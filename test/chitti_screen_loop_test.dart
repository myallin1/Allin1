// ================================================================
// chitti_screen_loop_test.dart
// ================================================================
// The parser is the sharp edge of the screen loop: it turns a model's
// free-text reply into an instruction to touch something on a real
// phone. Every wrong parse is a tap on the wrong element, so the two
// behaviours pinned hardest here are the ones that decide that —
// tolerating the formatting models actually produce, and refusing
// anything it cannot read cleanly rather than half-guessing.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_screen_loop.dart';

void main() {
  group('parsing what models really return', () {
    test('plain JSON', () {
      final step = ChittiScreenStep.parse(
        '{"action":"click","target":"Gallery","done":false}',
      );
      expect(step, isNotNull);
      expect(step!.action, 'click');
      expect(step.target, 'Gallery');
      expect(step.done, isFalse);
    });

    test('JSON wrapped in a ```json fence', () {
      final step = ChittiScreenStep.parse('''
```json
{"action":"click","target":"Settings"}
```''');
      expect(step, isNotNull);
      expect(step!.target, 'Settings');
    });

    test('JSON wrapped in a bare fence', () {
      final step = ChittiScreenStep.parse('```\n{"action":"scroll"}\n```');
      expect(step?.action, 'scroll');
    });

    test('JSON with the model chatting before it', () {
      final step = ChittiScreenStep.parse(
        'Sure! Here is the next step:\n{"action":"click","target":"Photos"}',
      );
      expect(step?.target, 'Photos');
    });

    test('action is normalised to lower case', () {
      final step = ChittiScreenStep.parse('{"action":"CLICK","target":"OK"}');
      expect(step?.action, 'click');
    });

    test('a done reply needs no action', () {
      final step = ChittiScreenStep.parse('{"done":true}');
      expect(step, isNotNull);
      expect(step!.done, isTrue);
    });
  });

  group('refusing to guess — every one of these must return null', () {
    test('empty reply', () {
      expect(ChittiScreenStep.parse(''), isNull);
      expect(ChittiScreenStep.parse('   '), isNull);
    });

    test('prose with no JSON at all', () {
      // The dangerous case: a chatty model that forgot the format.
      // Guessing an action out of this sentence would tap something.
      expect(
        ChittiScreenStep.parse('I think you should tap the Gallery icon.'),
        isNull,
      );
    });

    test('malformed JSON', () {
      expect(ChittiScreenStep.parse('{"action":"click", "target"'), isNull);
    });

    test('valid JSON that is not an object', () {
      expect(ChittiScreenStep.parse('["click","Gallery"]'), isNull);
    });

    test('an object with no action and not done', () {
      // Nothing to do and no completion signal — ambiguous, so stop.
      expect(ChittiScreenStep.parse('{"target":"Gallery"}'), isNull);
      expect(ChittiScreenStep.parse('{"action":"","done":false}'), isNull);
    });
  });

  group('the step cap is a real number, not a suggestion', () {
    test('kMaxSteps is the CTO-approved 8', () {
      // Pinned deliberately: this is the only thing stopping a
      // confused model from wandering across the whole phone.
      expect(ChittiScreenLoop.kMaxSteps, 8);
    });
  });

  group('endings explain themselves', () {
    test('every ending produces a non-empty line to speak', () {
      // The loop runs hands-free; an ending Chitti cannot describe
      // leaves the admin staring at a phone that just stopped.
      for (final ending in ChittiLoopEnding.values) {
        final result = ChittiLoopResult(
          ending: ending,
          stepsTaken: 2,
          pendingReason: 'because that button spends money',
        );
        expect(result.summaryFor(), isNotEmpty, reason: ending.name);
        expect(result.summaryFor(isTamil: true), isNotEmpty, reason: ending.name);
      }
    });

    test('a confirmation stop reports the gate\'s own reason', () {
      const result = ChittiLoopResult(
        ending: ChittiLoopEnding.awaitingConfirmation,
        stepsTaken: 3,
        pendingReason: '"Pay Now" looks like it does something irreversible.',
      );
      expect(result.summaryFor(), contains('Pay Now'));
    });

    test('hitting the cap does not claim success', () {
      const result = ChittiLoopResult(
        ending: ChittiLoopEnding.stepLimit,
        stepsTaken: 8,
      );
      expect(result.summaryFor().toLowerCase(), contains("couldn't finish"));
    });
  });
}
