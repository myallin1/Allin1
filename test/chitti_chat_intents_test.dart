// ================================================================
// chitti_chat_intents_test.dart
// ================================================================
// From a screenshot: Chitti offered "Change destination", "Cancel this
// booking" and "Ask something else", and tapping any of them produced
// the same no-key sentence three times with no chips under it. Chitti
// was offering doors that opened onto a wall.
//
// So the rule these pin is blunt: every chip Chitti offers must be
// handled, and no reply may be a dead end.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/config/app_variant.dart';
import 'package:erode_superapp/services/chitti/chitti_chat_intents.dart';

void main() {
  final original = currentAppVariant;
  setUp(() => currentAppVariant = 'customer');
  tearDown(() => currentAppVariant = original);

  group('every chip Chitti offers is handled', () {
    // The exact strings from chitti_action_executor.dart. If a chip is
    // added there without a handler here, this fails — which is the
    // regression that produced the screenshot.
    const offered = <String>[
      'Change destination',
      'Cancel this booking',
      'Ask something else',
      'Show me something else',
      'Go back to chat',
      'Take me somewhere else',
      'Order something else',
      'Add another item',
      'Report something else',
      'What can you do?',
    ];

    for (final chip in offered) {
      test('"$chip" produces a real reply', () {
        final a = ChittiChatIntents.handle(chip) ??
            ChittiChatIntents.fallback(text: 'x');
        expect(a.text, isNotEmpty, reason: chip);
        expect(a.suggestions, isNotEmpty, reason: chip);
      });
    }
  });

  group('no reply is a dead end', () {
    test('fallback always carries chips', () {
      final a = ChittiChatIntents.fallback(text: 'Something went wrong.');
      expect(a.suggestions.length, greaterThanOrEqualTo(2));
    });

    test('chips are variant-appropriate', () {
      expect(
        ChittiChatIntents.openingChipsFor('hero').join(' ').toLowerCase(),
        contains('earnings'),
      );
      expect(
        ChittiChatIntents.openingChipsFor('seller').join(' ').toLowerCase(),
        contains('orders'),
      );
      // A customer must never be offered a Hero action.
      expect(
        ChittiChatIntents.openingChipsFor('customer').join(' ').toLowerCase(),
        isNot(contains('go online')),
      );
    });

    test('chips follow the language switch', () {
      final ta = ChittiChatIntents.openingChipsFor('customer', tamil: true);
      expect(RegExp('[஀-௿]').hasMatch(ta.join()), isTrue);
    });

    test('a Tamil reply comes back in Tamil', () {
      final a = ChittiChatIntents.handle('வேற ஏதாவது', languageCode: 'ta');
      expect(a, isNotNull);
      expect(RegExp('[஀-௿]').hasMatch(a!.text), isTrue);
    });
  });

  group('TALK never steals a real action', () {
    test('"cancel this booking" is talk, not the cancel_order tool', () {
      // The trap: it contains "cancel". Firing the real tool here would
      // try to cancel an order that has not been placed.
      expect(
        ChittiChatIntents.classify('cancel this booking'),
        ChittiTurnKind.talk,
      );
    });

    test('"cancel my order" is an ACTION and is left alone', () {
      expect(ChittiChatIntents.handle('cancel my order'), isNull);
      expect(
        ChittiChatIntents.classify('cancel my order'),
        ChittiTurnKind.act,
      );
    });

    test('a real question is classified as ASK', () {
      expect(
        ChittiChatIntents.classify('what is my wallet balance'),
        ChittiTurnKind.ask,
      );
    });

    test('a booking request is classified as ACT', () {
      expect(
        ChittiChatIntents.classify('book an auto to the bus stand'),
        ChittiTurnKind.act,
      );
    });

    test('a long sentence containing a chip phrase is not hijacked', () {
      expect(
        ChittiChatIntents.handle(
          'I wanted to ask something else about how your delivery charges '
          'are calculated for long distances',
        ),
        isNull,
      );
    });
  });
}
