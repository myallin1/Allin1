// ================================================================
// chitti_buddy_comfort_test.dart
// ================================================================
// NEW (Aug 29 2026 -- Nizam: "customeroda sogam feelinglam
// purinjukuttu behave pandra oru personal buddy"). isSafeMoment()
// already silences JOKES on a setback -- correctly, per this file's
// own rule 2. What was missing is what replaces the silence:
// comfortAfterSetback() is that replacement, and these pin the two
// boundaries that matter -- it must fire on ordinary setbacks, and it
// must NOT fire on true emergencies, where a canned warm line would
// read as tone-deaf.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_buddy.dart';

void main() {
  group('comfort fires on an ordinary setback', () {
    test('a cancelled order gets acknowledged', () {
      final c = ChittiBuddy.comfortAfterSetback(
        languageCode: 'en',
        saying: 'Your order has been cancelled.',
      );
      expect(c, isNotNull);
      expect(c!.trim(), isNotEmpty);
    });

    test('a politely-phrased failure still counts', () {
      // "couldn't place that order" has none of the obvious keywords
      // (failed/error/cancel) -- same trap _seriousTopic itself
      // documents.
      final c = ChittiBuddy.comfortAfterSetback(
        languageCode: 'en',
        saying: "I couldn't place that order just now.",
      );
      expect(c, isNotNull);
    });

    test('Tamil setbacks get a Tamil comfort line', () {
      final c = ChittiBuddy.comfortAfterSetback(
        languageCode: 'ta',
        saying: 'Order ரத்து ஆகிடுச்சு.',
      );
      expect(c, isNotNull);
    });
  });

  group('comfort NEVER fires on a genuine emergency', () {
    for (final word in ['sos', 'accident', 'ambulance', 'hospital', 'police']) {
      test('$word stays silent', () {
        final c = ChittiBuddy.comfortAfterSetback(
          languageCode: 'en',
          saying: 'This is an $word situation, calling for help.',
        );
        expect(c, isNull, reason: word);
      });
    }
  });

  group('comfort stays out of the way on ordinary replies', () {
    test('a plain factual answer gets no comfort line', () {
      final c = ChittiBuddy.comfortAfterSetback(
        languageCode: 'en',
        saying: 'Your wallet balance is 250 rupees.',
      );
      expect(c, isNull);
    });
  });
}
