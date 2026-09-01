// ================================================================
// tamil_transliteration.dart — Tamil script → Thanglish (Latin).
// ================================================================
// NEW (Aug 28 2026 — Nizam: "tamil la vachurukanvangalukku thappillama
// tamil layu, english vachurukkavangalukku english layum, thanglish
// vachurukanvangaluku thanglish layum welcome and guidance pannanum...
// language all pronounciation perfecta irukanum").
//
// THE RULE THAT MAKES THIS SAFE: DISPLAY ONLY, NEVER SPEECH.
// Thanglish is a way of READING Tamil, not a way of pronouncing it.
// Handing "Kaalai vanakkam" to a ta-IN TTS voice produces garbage,
// because the engine is expecting Tamil script and gets Latin letters
// it will sound out as English. So every caller pairs this with the
// original Tamil string: the Latin goes on screen, the Tamil goes to
// the voice. Pronunciation is then perfect by construction rather than
// by the quality of this file — which is the whole reason it is
// acceptable to transliterate mechanically at all.
//
// WHY MECHANICAL, RATHER THAN 56 HAND-WRITTEN LINES
// The quote pool is 56 entries and grows. Hand-writing a third variant
// for each means three strings to keep in sync forever, and the
// Thanglish one silently rots first because nobody proofreads the
// script they do not read. Tamil is close to phonetic, so a rule set
// gets the whole pool — and everything added later — for free.
//
// THE HARD PART: TAMIL HAS NO SEPARATE VOICED LETTERS
// க is "k" in கடை (kadai... actually "kadai" starts hard: "k") but "g"
// in தங்கம் (thangam). ப is "p" in பால் (paal) and "b" in அம்பு (ambu).
// One letter, several sounds, decided by position. The classical rule,
// which this implements:
//   • word-initial, or doubled (கக, பப, ...)  → hard   (k, ch, t, th, p)
//   • immediately after its own class nasal    → voiced (g, j, d, dh, b)
//   • between vowels                           → voiced/fricative
// This is what makes "வணக்கம்" come out "vanakkam" and "தங்கம்" come
// out "thangam" from the same table.
//
// It will not be perfect on loanwords and proper nouns. That is an
// accepted cost: a slightly odd spelling is readable, and the spoken
// form — the part Nizam called out — never passes through here.
library;

/// Tamil script → Latin, for readers who chose Thanglish.
///
/// Display only. See the file header: never send the result to TTS.
class TamilTransliteration {
  TamilTransliteration._();

  // ── vowels ────────────────────────────────────────────────────
  // Independent forms (word-initial).
  static const Map<String, String> _vowels = <String, String>{
    'அ': 'a', 'ஆ': 'aa', 'இ': 'i', 'ஈ': 'ee', 'உ': 'u', 'ஊ': 'oo',
    'எ': 'e', 'ஏ': 'ae', 'ஐ': 'ai', 'ஒ': 'o', 'ஓ': 'oa', 'ஔ': 'au',
  };

  // Dependent forms (the sign that follows a consonant).
  static const Map<String, String> _signs = <String, String>{
    'ா': 'aa', 'ி': 'i', 'ீ': 'ee', 'ு': 'u', 'ூ': 'oo',
    'ெ': 'e', 'ே': 'ae', 'ை': 'ai', 'ொ': 'o', 'ோ': 'oa', 'ௌ': 'au',
  };

  /// Pulli / virama — kills the inherent 'a' on a consonant.
  static const String _virama = '்';

  // ── consonants ────────────────────────────────────────────────
  // hard  = word-initial or doubled; soft = voiced (after a nasal, or
  // between vowels). Where a letter has only one sound, both are equal.
  static const Map<String, (String hard, String soft)> _consonants =
      <String, (String, String)>{
    'க': ('k', 'g'),
    'ங': ('ng', 'ng'),
    'ச': ('ch', 'j'),
    'ஞ': ('nj', 'nj'),
    'ட': ('t', 'd'),
    'ண': ('n', 'n'),
    'த': ('th', 'dh'),
    'ந': ('n', 'n'),
    'ப': ('p', 'b'),
    'ம': ('m', 'm'),
    'ய': ('y', 'y'),
    'ர': ('r', 'r'),
    'ல': ('l', 'l'),
    'வ': ('v', 'v'),
    'ழ': ('zh', 'zh'),
    'ள': ('l', 'l'),
    'ற': ('tr', 'tr'),
    'ன': ('n', 'n'),
    // Grantha — used for Sanskrit and English loanwords.
    'ஜ': ('j', 'j'),
    'ஷ': ('sh', 'sh'),
    'ஸ': ('s', 's'),
    'ஹ': ('h', 'h'),
    'க்ஷ': ('ksh', 'ksh'),
    'ஶ': ('sh', 'sh'),
  };

  /// The nasal that voices each plosive class. தங்கம் → ng + க = "g".
  static const Map<String, String> _voicingNasal = <String, String>{
    'க': 'ங',
    'ச': 'ஞ',
    'ட': 'ண',
    'த': 'ந',
    'ப': 'ம',
  };

  static const String _aytham = 'ஃ';

  /// True if [s] contains any Tamil letter at all.
  static bool hasTamil(String s) {
    for (final rune in s.runes) {
      if (rune >= 0x0B80 && rune <= 0x0BFF) return true;
    }
    return false;
  }

  /// Transliterates Tamil script in [input] to Latin.
  ///
  /// Non-Tamil characters — spaces, punctuation, digits, and any Latin
  /// already present — pass through untouched, so a mixed string like
  /// "வணக்கம் boss!" comes out "vanakkam boss!".
  static String toLatin(String input) {
    if (input.isEmpty || !hasTamil(input)) return input;

    final chars = input.split('');
    final out = StringBuffer();

    // Whether the previous emitted unit was a vowel sound. Drives the
    // intervocalic voicing rule.
    var prevWasVowel = false;
    // The previous Tamil consonant, for the doubling and nasal checks.
    String? prevConsonant;

    for (var i = 0; i < chars.length; i++) {
      final c = chars[i];

      if (c == _virama) {
        // Handled when the consonant itself was emitted.
        continue;
      }

      if (_vowels.containsKey(c)) {
        out.write(_vowels[c]);
        prevWasVowel = true;
        prevConsonant = null;
        continue;
      }

      if (_signs.containsKey(c)) {
        out.write(_signs[c]);
        prevWasVowel = true;
        continue;
      }

      if (c == _aytham) {
        out.write('h');
        prevWasVowel = false;
        prevConsonant = null;
        continue;
      }

      final pair = _consonants[c];
      if (pair == null) {
        // Punctuation, Latin, digits, whitespace — pass through, and
        // treat whitespace as a word break so the next consonant is
        // treated as word-initial (hard).
        out.write(c);
        if (c.trim().isEmpty) {
          prevWasVowel = false;
          prevConsonant = null;
        }
        continue;
      }

      // Geminates (க்க, ட்ட, ப்ப) are HARD on both halves, and the
      // decision has to be made by looking AHEAD, not behind: by the
      // time the second half is reached the first has already been
      // emitted, and emitting it voiced gives "vanagkam".
      final isGeminate = prevConsonant == c ||
          (i + 2 < chars.length &&
              chars[i + 1] == _virama &&
              chars[i + 2] == c);

      // A class nasal directly before its own plosive drops to the
      // plain nasal: ங்க is "ng" as a whole (n + g), not "ng" + "g".
      // Without this தங்கம் comes out "thanggam".
      final nextIsOwnPlosive = i + 2 < chars.length &&
          chars[i + 1] == _virama &&
          _voicingNasal[chars[i + 2]] == c;

      if (nextIsOwnPlosive) {
        out.write(c == 'ங' || c == 'ஞ' ? 'n' : pair.$1);
      } else if (isGeminate) {
        out.write(pair.$1);
      } else {
        out.write(_shouldVoice(c, prevConsonant, prevWasVowel)
            ? pair.$2
            : pair.$1);
      }

      // Does an inherent 'a' follow? Only if the next character is
      // neither a virama nor a vowel sign.
      final next = i + 1 < chars.length ? chars[i + 1] : null;
      final hasInherentA =
          next != _virama && (next == null || !_signs.containsKey(next));
      if (hasInherentA) {
        out.write('a');
        prevWasVowel = true;
      } else {
        prevWasVowel = false;
      }
      prevConsonant = c;
    }

    return out.toString();
  }

  /// The voicing decision for one plosive.
  static bool _shouldVoice(
    String consonant,
    String? prevConsonant,
    bool prevWasVowel,
  ) {
    // Only the five plosive classes alternate at all.
    if (!_voicingNasal.containsKey(consonant)) return false;
    // Doubled → always hard (வணக்கம்).
    if (prevConsonant == consonant) return false;
    // After its own class nasal → voiced (தங்கம் → thangam).
    if (prevConsonant == _voicingNasal[consonant]) return true;
    // Between vowels → voiced (பகல் → pagal).
    if (prevWasVowel && prevConsonant != null) return true;
    return false;
  }
}
