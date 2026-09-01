// ================================================================
// chitti_identity_answers_test.dart
// ================================================================
// NEW (Aug 29 2026 -- Nizam: "customer chitty kita how r u, who r u,
// whose ur owner and whats ur birth place nu yenna kettalum chitty
// therilanu sollama answer pannanum"). These were previously
// unanswered -- either a dead-end "I don't know" or an inconsistent
// improvised reply from the cloud model each time. Fixed answers now,
// answered offline, with no API key needed.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_local_answer_service.dart';

void main() {
  group('identity questions never fall through', () {
    test('how are you', () {
      final a = ChittiLocalAnswerService.answer('how are you');
      expect(a, isNotNull);
      expect(a!.text.trim(), isNotEmpty);
    });

    test('who are you', () {
      final a = ChittiLocalAnswerService.answer('who are you');
      expect(a, isNotNull);
      expect(a!.text.toLowerCase(), contains('chitti'));
    });

    test("who's your owner", () {
      final a = ChittiLocalAnswerService.answer("who's your owner");
      expect(a, isNotNull);
      expect(a!.text.toLowerCase(), contains('nj tech'));
    });

    test('who made you', () {
      final a = ChittiLocalAnswerService.answer('who made you');
      expect(a, isNotNull);
      expect(a!.text.toLowerCase(), contains('nj tech'));
    });

    test('birth place', () {
      final a = ChittiLocalAnswerService.answer('what is your birth place');
      expect(a, isNotNull);
      expect(a!.text.toLowerCase(), contains('erode'));
    });

    test('unrelated questions are unaffected', () {
      final a = ChittiLocalAnswerService.answer('where is my order');
      // Not an identity question -- must not be swallowed by the new
      // handler.
      expect(a?.text.toLowerCase().contains('nj tech'), isNot(true));
    });
  });
}
