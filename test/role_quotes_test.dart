// ================================================================
// role_quotes_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: "daily customer, seller, hero, admin ku
// pudhusa theriyanum, but avangavanga role ku nalla motivator ah
// irukanum").
//
// Two failures these guard against, neither of which crashes:
//   1. A role quietly sharing another role's pool — a seller deciding
//      whether to stay open being told to "support a local shop today".
//   2. A pool small enough that the same line comes back within a week,
//      which turns a daily habit into wallpaper.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/daily_quote_service.dart';
import 'package:erode_superapp/services/tamil_transliteration.dart';

void main() {
  final svc = DailyQuoteService.instance;

  group('every role has its own pool, deep enough to stay fresh', () {
    test('all four roles are populated', () {
      final sizes = DailyQuoteService.poolSizes;
      expect(sizes.keys, containsAll(['customer', 'hero', 'seller', 'admin']));
      for (final e in sizes.entries) {
        // Three slots a day, so 60 lines is ~20 days before a repeat.
        expect(e.value, greaterThanOrEqualTo(60),
            reason: '${e.key} pool is only ${e.value} lines');
      }
    });

    test('roles do not share the same line on the same day', () {
      final at = DateTime(2026, 9, 1, 8);
      final seen = <String>{};
      for (final role in ['customer', 'hero', 'seller', 'admin']) {
        final q = svc.forRole(role, 'en', now: at);
        expect(seen.add(q), isTrue,
            reason: '$role repeated another role\'s line: $q');
      }
    });

    test('an unknown variant falls back to the customer pool', () {
      final at = DateTime(2026, 9, 1, 8);
      expect(
        svc.forRole('something_new', 'en', now: at),
        svc.forCustomer('en', now: at),
      );
    });
  });

  group('a role never sees a full cycle repeat too soon', () {
    for (final role in ['customer', 'hero', 'seller', 'admin']) {
      test('$role stays fresh for two weeks', () {
        final seen = <String>{};
        var day = DateTime(2026, 9, 1, 8);
        for (var i = 0; i < 14; i++) {
          seen.add(svc.forRole(role, 'en', now: day));
          day = day.add(const Duration(days: 1));
        }
        // Fourteen mornings, fourteen different lines.
        expect(seen.length, 14, reason: role);
      });
    }
  });

  group('every role speaks every language', () {
    final at = DateTime(2026, 9, 1, 8);

    for (final role in ['customer', 'hero', 'seller', 'admin']) {
      test('$role has Tamil, Thanglish and English', () {
        final en = svc.forRole(role, 'en', now: at);
        final ta = svc.forRole(role, 'ta', now: at);
        final tg = svc.forRole(role, 'tg', now: at);

        expect(en.trim(), isNotEmpty);
        expect(TamilTransliteration.hasTamil(ta), isTrue, reason: role);
        // Thanglish is Latin script but the Tamil line.
        expect(TamilTransliteration.hasTamil(tg), isFalse, reason: tg);
        expect(tg, isNot(en), reason: 'tg fell back to English for $role');
      });

      test('$role Thanglish is READ in Latin but SPOKEN in Tamil', () {
        expect(
          TamilTransliteration.hasTamil(svc.forRole(role, 'tg', now: at)),
          isFalse,
        );
        expect(
          TamilTransliteration.hasTamil(
            svc.spokenForRole(role, 'tg', now: at),
          ),
          isTrue,
        );
      });
    }
  });

  group('the pools say role-appropriate things', () {
    // Not an exhaustive tone check — just enough that a pool swapped by
    // mistake would be caught. Sampled across a month.
    List<String> month(String role) {
      var day = DateTime(2026, 9, 1, 8);
      return [
        for (var i = 0; i < 30; i++)
          () {
            final q = svc.forRole(role, 'en', now: day);
            day = day.add(const Duration(days: 1));
            return q;
          }(),
      ];
    }

    test('the hero pool talks to a rider', () {
      final all = month('hero').join(' ').toLowerCase();
      expect(
        all.contains('ride') || all.contains('trip') || all.contains('road'),
        isTrue,
      );
    });

    test('the seller pool talks to a shop', () {
      final all = month('seller').join(' ').toLowerCase();
      expect(
        all.contains('shop') || all.contains('customer') || all.contains('stock'),
        isTrue,
      );
    });

    test('the admin pool talks to an owner', () {
      final all = month('admin').join(' ').toLowerCase();
      expect(
        all.contains('queue') ||
            all.contains('data') ||
            all.contains('platform') ||
            all.contains('decision'),
        isTrue,
      );
    });
  });

  group('no quote is malformed', () {
    test('nothing is empty or a leaked placeholder, in any language', () {
      var day = DateTime(2026, 9, 1, 8);
      for (var i = 0; i < 40; i++) {
        for (final role in ['customer', 'hero', 'seller', 'admin']) {
          for (final lang in ['en', 'ta', 'tg']) {
            final q = svc.forRole(role, lang, now: day);
            expect(q.trim(), isNotEmpty, reason: '$role/$lang');
            expect(q, isNot(contains(r'$')), reason: q);
            expect(q.toLowerCase(), isNot(contains('null')), reason: q);
          }
        }
        day = day.add(const Duration(days: 1));
      }
    });
  });
}
