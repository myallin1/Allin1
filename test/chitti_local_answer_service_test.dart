// ================================================================
// chitti_local_answer_service_test.dart
// ================================================================
// Tier 1 does things. This answers questions — and the reason it
// exists is that "what is this page?" used to come back as "Chitti AI
// is having a short network pause", which was never true. The answer
// was in kChittiSections the whole time.
//
// The important property is restraint, not coverage: it must answer
// what it genuinely knows and return null for everything else, so the
// model still gets its turn. A confidently wrong answer about the
// customer's own app is worse than no answer.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/config/app_variant.dart';
import 'package:erode_superapp/services/chitti/chitti_local_answer_service.dart';
import 'package:erode_superapp/services/chitti_memory_service.dart';

void main() {
  final original = currentAppVariant;

  setUp(() => currentAppVariant = 'customer');
  tearDown(() {
    currentAppVariant = original;
    ChittiMemoryService.instance.setCurrentScreen(null);
  });

  group('what can you do', () {
    test('answers with real capabilities, not a shrug', () {
      final a = ChittiLocalAnswerService.answer('what can you do?');
      expect(a, isNotNull);
      expect(a!.text.toLowerCase(), contains('book'));
      expect(a.suggestions, isNotEmpty);
    });

    test('is variant-aware — a customer is not offered Hero abilities', () {
      final a = ChittiLocalAnswerService.answer('what can you do?');
      expect(a!.text.toLowerCase(), isNot(contains('online or offline')));
    });

    test('a Hero hears Hero abilities', () {
      currentAppVariant = 'hero';
      final a = ChittiLocalAnswerService.answer('what can you do?');
      expect(a!.text.toLowerCase(), contains('earnings'));
    });

    test('answers the Tamil phrasing too', () {
      expect(ChittiLocalAnswerService.answer('நீ என்ன பண்ணுவ'), isNotNull);
    });
  });

  group('what is this page', () {
    test('describes the screen the customer is actually on', () {
      ChittiMemoryService.instance.setCurrentScreen('Food Genie');
      final a = ChittiLocalAnswerService.answer('what is this page?');
      expect(a, isNotNull);
      expect(a!.text, contains('Food Genie'));
      // The registry's own description, so it matches what Chitti says
      // when IT opens the same screen.
      expect(a.text.toLowerCase(), contains('erode hotels'));
    });

    test('says so honestly when it does not know the screen', () {
      final a = ChittiLocalAnswerService.answer('what can I do here?');
      expect(a, isNotNull);
      expect(a!.text.toLowerCase(), contains("can't tell"));
      expect(a.suggestions, isNotEmpty);
    });

    test('handles a screen that is not a known section', () {
      ChittiMemoryService.instance.setCurrentScreen('Nj Tech Broadband');
      final a = ChittiLocalAnswerService.answer('what is this screen');
      expect(a!.text, contains('Nj Tech Broadband'));
    });
  });

  group('how do I / where is', () {
    test('points at the right section', () {
      final a = ChittiLocalAnswerService.answer('how do i order food');
      expect(a, isNotNull);
      expect(a!.text, contains('Food Genie'));
      expect(a.suggestions.first, contains('Open'));
    });

    test('finds the longest alias, not the first', () {
      // "car wash" must beat a bare "wash".
      final a = ChittiLocalAnswerService.answer('where is car wash');
      expect(a!.text, contains('Car Wash'));
    });

    test('returns null when no section matches', () {
      expect(
        ChittiLocalAnswerService.answer('how do i become a millionaire'),
        isNull,
      );
    });
  });

  group('restraint', () {
    test('a bare section name gets its description', () {
      final a = ChittiLocalAnswerService.answer('rewards');
      expect(a, isNotNull);
      expect(a!.text, contains('Rewards'));
    });

    test('a long sentence containing a section word is left to the model', () {
      // This is the guard that stops the answerer hijacking real
      // questions it cannot actually answer.
      expect(
        ChittiLocalAnswerService.answer(
          'my friend told me the rewards on this app are better than the '
          'other one is that true',
        ),
        isNull,
      );
    });

    test('unrelated chatter returns null', () {
      expect(ChittiLocalAnswerService.answer('hello there'), isNull);
      expect(ChittiLocalAnswerService.answer(''), isNull);
    });
  });
}
