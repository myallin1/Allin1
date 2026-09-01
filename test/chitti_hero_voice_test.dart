// ================================================================
// chitti_hero_voice_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: Chitti is the hero's "dude" in the hero
// app, and the hero's advocate in the customer app).
//
// The riskiest thing in this feature is not a crash — it is tone. A
// line meant as "your hero worked hard, give from the heart" becomes a
// surcharge the moment it names an amount, and becomes an excuse the
// moment it is shown while the customer is still waiting. Those two
// boundaries are what these tests hold.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_hero_voice.dart';
import 'package:erode_superapp/services/tamil_transliteration.dart';

void main() {
  group('Chitti is the hero\'s dude', () {
    test('every language gets a pep line', () {
      for (final lang in ['en', 'ta', 'tg']) {
        for (var seed = 0; seed < 8; seed++) {
          expect(
            ChittiHeroVoice.heroPep(lang, seed: seed).trim(),
            isNotEmpty,
            reason: '$lang/$seed',
          );
        }
      }
    });

    test('English calls the rider "boss", as asked', () {
      final anyBoss = List.generate(8, (i) => ChittiHeroVoice.heroPep('en', seed: i))
          .any((l) => l.toLowerCase().contains('boss'));
      expect(anyBoss, isTrue);
    });

    test('it reassures about money rather than demanding numbers', () {
      // "kavala padatheenga, nalla sambaringa" — reassurance. A rider
      // who is behind on earnings does not need a target quoted at them.
      final all = List.generate(8, (i) => ChittiHeroVoice.heroPep('en', seed: i));
      for (final line in all) {
        expect(RegExp(r'₹\s*\d').hasMatch(line), isFalse, reason: line);
      }
    });

    test('Thanglish pep carries no Tamil script', () {
      for (var seed = 0; seed < 8; seed++) {
        expect(
          TamilTransliteration.hasTamil(
            ChittiHeroVoice.heroPep('tg', seed: seed),
          ),
          isFalse,
        );
      }
    });

    test('but the SPOKEN Thanglish pep is Tamil, so it pronounces', () {
      expect(
        TamilTransliteration.hasTamil(
          ChittiHeroVoice.spokenHeroPep('tg', seed: 0),
        ),
        isTrue,
      );
    });

    test('the seed wraps instead of throwing', () {
      expect(() => ChittiHeroVoice.heroPep('en', seed: 9999), returnsNormally);
      expect(() => ChittiHeroVoice.heroPep('en', seed: -3), returnsNormally);
    });
  });

  group('Chitti speaks for the hero, at the right moment only', () {
    test('nothing is said when no hero is working', () {
      // Before booking, this would just be an advertisement.
      expect(
        ChittiHeroVoice.advocateForHero('en', moment: HeroMoment.idle),
        isNull,
      );
      expect(ChittiHeroVoice.isGoodMomentToAdvocate(HeroMoment.idle), isFalse);
    });

    test('mid-delivery it reassures, it does not ask', () {
      // Asking for generosity while the customer is still waiting reads
      // as the app excusing a delay.
      expect(
        ChittiHeroVoice.isGoodMomentToAdvocate(HeroMoment.onTheWay),
        isFalse,
      );
      final line =
          ChittiHeroVoice.advocateForHero('en', moment: HeroMoment.onTheWay);
      expect(line, isNotNull);
      expect(line!.toLowerCase(), isNot(contains('give')));
    });

    test('after completion it advocates', () {
      expect(
        ChittiHeroVoice.isGoodMomentToAdvocate(HeroMoment.completed),
        isTrue,
      );
      final line =
          ChittiHeroVoice.advocateForHero('en', moment: HeroMoment.completed);
      expect(line, isNotNull);
      expect(line!.trim(), isNotEmpty);
    });
  });

  group('advocacy never becomes a charge', () {
    // Nizam asked for "kanakku pakkama mulu manasoda" — wholehearted,
    // uncounted. That is a request to the conscience. The moment a line
    // names a figure or a percentage it is a surcharge, and goodwill
    // turns into resentment.
    final lines = <String>[
      for (var seed = 0; seed < 6; seed++)
        for (final lang in ['en', 'ta', 'tg'])
          ChittiHeroVoice.advocateForHero(
            lang,
            moment: HeroMoment.completed,
            seed: seed,
          )!,
    ];

    // The wording assertions below can only read English. Thanglish is
    // Latin script but Tamil words, so it passes a hasTamil() filter
    // while containing none of the English terms — filtering on script
    // alone would silently assert nothing about it.
    final english = <String>[
      for (var seed = 0; seed < 6; seed++)
        ChittiHeroVoice.advocateForHero(
          'en',
          moment: HeroMoment.completed,
          seed: seed,
        )!,
    ];

    test('no line names an amount', () {
      for (final l in lines) {
        expect(RegExp(r'₹\s*\d|\b\d+\s*%|\brupees?\s*\d').hasMatch(l), isFalse,
            reason: l);
      }
    });

    test('no line demands, it only invites', () {
      for (final l in english) {
        final low = l.toLowerCase();
        expect(low, isNot(contains('you must')), reason: l);
        expect(low, isNot(contains('you should')), reason: l);
        expect(low, isNot(contains('required')), reason: l);
      }
    });

    test('every line credits the hero\'s effort', () {
      for (final l in english) {
        final low = l.toLowerCase();
        expect(
          low.contains('hero') ||
              low.contains('hard') ||
              low.contains('effort') ||
              low.contains('family') ||
              low.contains('they'),
          isTrue,
          reason: l,
        );
      }
    });
  });

  group('the customer is spoken to in THEIR language', () {
    // Nizam: "customer entha language use pandraro antha language la
    // heros ah promote pannanum".
    test('Tamil customers get Tamil script', () {
      expect(
        TamilTransliteration.hasTamil(
          ChittiHeroVoice.advocateForHero('ta',
              moment: HeroMoment.completed)!,
        ),
        isTrue,
      );
    });

    test('Thanglish customers get Latin, and hear Tamil', () {
      final shown = ChittiHeroVoice.advocateForHero('tg',
          moment: HeroMoment.completed)!;
      final spoken = ChittiHeroVoice.spokenAdvocateForHero('tg',
          moment: HeroMoment.completed)!;
      expect(TamilTransliteration.hasTamil(shown), isFalse, reason: shown);
      expect(TamilTransliteration.hasTamil(spoken), isTrue);
    });

    test('English customers get English', () {
      expect(
        TamilTransliteration.hasTamil(
          ChittiHeroVoice.advocateForHero('en',
              moment: HeroMoment.completed)!,
        ),
        isFalse,
      );
    });

    test('the three languages really are different strings', () {
      final en =
          ChittiHeroVoice.advocateForHero('en', moment: HeroMoment.completed);
      final ta =
          ChittiHeroVoice.advocateForHero('ta', moment: HeroMoment.completed);
      final tg =
          ChittiHeroVoice.advocateForHero('tg', moment: HeroMoment.completed);
      expect(en, isNot(ta));
      expect(en, isNot(tg));
      expect(ta, isNot(tg));
    });
  });
}
