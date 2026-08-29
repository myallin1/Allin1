// ================================================================
// tamil_transliteration_test.dart
// ================================================================
// These pin the rules that are easy to get wrong and hard to notice:
// the voicing alternation (one Tamil letter, several Latin sounds) and
// the doubled-consonant case. A regression here does not crash — it
// just makes every Thanglish reader's app look slightly illiterate.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/tamil_transliteration.dart';

void main() {
  String t(String s) => TamilTransliteration.toLatin(s);

  group('the words this app actually says', () {
    test('vanakkam — doubled consonant stays hard', () {
      // The trap: naive doubling gives "vanakkkam", and naive voicing
      // gives "vanaggam". Both are wrong.
      expect(t('வணக்கம்'), 'vanakkam');
    });

    test('boss, in Tamil script', () {
      expect(t('பாஸ்'), 'paas');
    });

    test('Chitti says its own name correctly', () {
      expect(t('சிட்டி'), 'chitti');
    });
  });

  group('voicing alternation', () {
    test('hard at the start of a word', () {
      expect(t('கடை'), startsWith('k'));
    });

    test('voiced after its own class nasal', () {
      // ங + க → "ng" + "g", never "ng" + "k".
      expect(t('தங்கம்'), 'thangam');
    });

    test('voiced between vowels', () {
      expect(t('பகல்'), 'pagal');
    });
  });

  group('what must pass through untouched', () {
    test('plain English is returned as-is', () {
      expect(t('Good morning boss'), 'Good morning boss');
    });

    test('mixed strings keep their Latin half', () {
      expect(t('வணக்கம் boss!'), 'vanakkam boss!');
    });

    test('an empty string is safe', () {
      expect(t(''), '');
    });

    test('digits and punctuation survive', () {
      expect(t('₹500'), '₹500');
    });
  });

  group('hasTamil', () {
    test('detects Tamil', () {
      expect(TamilTransliteration.hasTamil('வணக்கம்'), isTrue);
    });

    test('does not false-positive on English', () {
      expect(TamilTransliteration.hasTamil('vanakkam boss'), isFalse);
    });
  });

  group('output is always readable Latin', () {
    // The contract every caller depends on: whatever goes in, no Tamil
    // codepoint comes out. A leaked glyph would render as a box on a
    // device with no Tamil font — the exact reason someone picked
    // Thanglish in the first place.
    const samples = <String>[
      'தினமும் ஒரு சிறு அடி, வாழ்க்கையை பெரிதாக்கும்.',
      'காலை வணக்கம் பாஸ்! நான் தான் சிட்டி.',
      'இன்னைக்கு எவ்வளவு சம்பாதிச்சேன்?',
      'உங்க உழைப்பு தான் நாளைய நிம்மதி.',
      'கடை ஓபன் ஆ இருக்கா?',
    ];

    for (final s in samples) {
      test('no Tamil survives: ${s.substring(0, 12)}…', () {
        final out = t(s);
        expect(TamilTransliteration.hasTamil(out), isFalse, reason: out);
        expect(out.trim(), isNotEmpty);
      });
    }
  });
}
