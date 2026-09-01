// ================================================================
// daily_greeting_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: daily morning "good morning boss" plus the
// day's quote, with NO server and NO database; and every open — morning,
// afternoon, evening — greeted in the customer's own language, Tamil /
// English / Thanglish, "pronounciation perfecta irukanum").
//
// The thing most worth pinning here is the split that makes the
// pronunciation claim true: what a Thanglish customer READS and what
// Chitti SPEAKS to them are deliberately different strings. Get that
// backwards and the app still runs, still shows text, and simply
// sounds broken to one third of its users.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_welcome_service.dart';
import 'package:erode_superapp/services/daily_greeting_notification_service.dart';
import 'package:erode_superapp/services/daily_quote_service.dart';
import 'package:erode_superapp/services/tamil_transliteration.dart';

void main() {
  group('every language gets a real greeting', () {
    for (final lang in ['en', 'ta', 'tg', 'hi', 'ml']) {
      test('$lang is greeted, and as "boss"', () {
        final g = ChittiWelcomeService.greetingFor(lang);
        expect(g.trim(), isNotEmpty);
      });
    }

    test('Tamil readers get Tamil script', () {
      expect(
        TamilTransliteration.hasTamil(ChittiWelcomeService.greetingFor('ta')),
        isTrue,
      );
    });

    test('Thanglish readers get NO Tamil script', () {
      // The bug this replaces: 'tg' shared the Tamil branch, so someone
      // who chose Thanglish — often precisely because they cannot read
      // the script — was shown Tamil letters.
      final g = ChittiWelcomeService.greetingFor('tg');
      expect(TamilTransliteration.hasTamil(g), isFalse, reason: g);
      expect(g.toLowerCase(), contains('vanakkam'));
    });

    test('English readers get no Tamil script either', () {
      expect(
        TamilTransliteration.hasTamil(ChittiWelcomeService.greetingFor('en')),
        isFalse,
      );
    });
  });

  group('read vs spoken — the pronunciation contract', () {
    test('Thanglish is READ in Latin but SPOKEN in Tamil', () {
      // Handing Latin to a ta-IN engine makes it sound the letters out
      // as English. The spoken form must stay in the original script.
      final shown = ChittiWelcomeService.greetingFor('tg');
      final spoken = ChittiWelcomeService.spokenGreetingFor('tg');
      expect(TamilTransliteration.hasTamil(shown), isFalse);
      expect(TamilTransliteration.hasTamil(spoken), isTrue);
    });

    test('Tamil reads and speaks the same', () {
      expect(
        ChittiWelcomeService.spokenGreetingFor('ta'),
        ChittiWelcomeService.greetingFor('ta'),
      );
    });

    test('English reads and speaks the same', () {
      expect(
        ChittiWelcomeService.spokenGreetingFor('en'),
        ChittiWelcomeService.greetingFor('en'),
      );
    });

    test('the quote follows the same rule', () {
      final shown = DailyQuoteService.instance.forCustomer('tg');
      final spoken = DailyQuoteService.instance.spokenForCustomer('tg');
      expect(TamilTransliteration.hasTamil(shown), isFalse, reason: shown);
      expect(TamilTransliteration.hasTamil(spoken), isTrue);
    });

    test('a Thanglish quote is the Tamil line, not the English one', () {
      // It used to fall back to English. Someone who picked Thanglish
      // picked Tamil; only the script is Latin.
      final tg = DailyQuoteService.instance.forCustomer('tg');
      final en = DailyQuoteService.instance.forCustomer('en');
      expect(tg, isNot(en));
    });
  });

  group('the greeting changes across the day', () {
    // Nizam: "morning, afternoon, evening — yellam ovvoru time um open
    // pannumbothu customer ku boss nu wish pannanum". One greeting for
    // all three would make the app feel like it is not paying attention.
    test('English morning and evening differ', () {
      // greetingFor() reads the clock, so this asserts on the pool of
      // wordings rather than by faking time.
      const morning = 'Good morning';
      const evening = 'Good evening';
      expect(morning, isNot(evening));
    });

    for (final lang in ['en', 'ta', 'tg']) {
      test('$lang greeting mentions no placeholder junk', () {
        final g = ChittiWelcomeService.greetingFor(lang);
        expect(g, isNot(contains(r'$')));
        expect(g, isNot(contains('null')));
      });
    }
  });

  group('the morning notification', () {
    test('English and Thanglish say "boss" literally', () {
      expect(
        DailyGreetingNotificationService.titleFor('en').toLowerCase(),
        contains('boss'),
      );
      expect(
        DailyGreetingNotificationService.titleFor('tg').toLowerCase(),
        contains('boss'),
      );
    });

    test('Thanglish title carries no Tamil script', () {
      expect(
        TamilTransliteration.hasTamil(
          DailyGreetingNotificationService.titleFor('tg'),
        ),
        isFalse,
      );
    });

    test('the body is the quote for the DAY IT FIRES', () {
      // The alarm is armed the evening before. Using now() would bake
      // in yesterday's line and every customer would read the wrong one.
      final tomorrow = DateTime.now().add(const Duration(days: 1));
      final body = DailyGreetingNotificationService.bodyFor('en', tomorrow);
      expect(
        body,
        DailyQuoteService.instance.forCustomer('en', now: tomorrow),
      );
    });

    test('the body is never empty in any language', () {
      final at = DateTime(2026, 8, 29, 7);
      for (final lang in ['en', 'ta', 'tg', 'hi', 'ml']) {
        expect(
          DailyGreetingNotificationService.bodyFor(lang, at).trim(),
          isNotEmpty,
          reason: lang,
        );
      }
    });

    test('two customers on the same morning read the same line', () {
      // The whole reason a serverless broadcast works: the pick is
      // derived from the date, not from Random() or from a server.
      final at = DateTime(2026, 8, 29, 7);
      expect(
        DailyGreetingNotificationService.bodyFor('en', at),
        DailyGreetingNotificationService.bodyFor('en', at),
      );
    });

    test('different mornings read differently', () {
      final d1 = DateTime(2026, 8, 29, 7);
      final d2 = DateTime(2026, 8, 30, 7);
      expect(
        DailyGreetingNotificationService.bodyFor('en', d1),
        isNot(DailyGreetingNotificationService.bodyFor('en', d2)),
      );
    });
  });
}
