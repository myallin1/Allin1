// ================================================================
// chitti_screen_guide.dart — "இந்த screen-ல என்ன பண்ணலாம்?"
// ================================================================
// NEW (Aug 28 2026 — Nizam: "all screen voice guidance tamil",
// answered as ON DEMAND: "kettaa mattum pesanum").
//
// WHY ON DEMAND AND NOT ON EVERY SCREEN ENTRY
// This was a real fork and the quieter side won. An owner opens fifty
// screens a day; a voice explaining each one becomes noise by the
// second morning, and the first thing they do is turn the whole
// feature off — including the times it would have helped. Asked for,
// it is help. Volunteered fifty times, it is an obstacle.
//
// WHY IT IS NOT THE LLM
// A screen explanation is the same every time and must be right when
// there is no API key and no signal. Sending it to a model would mean
// paying tokens for a constant, waiting on a network round-trip to
// answer "what is this page", and getting a plausible invention on the
// screens the model has never heard of. The registry already knows
// every screen; this reads from it.
//
// SPOKEN vs SHOWN
// Follows the app-wide rule (tamil_transliteration.dart): Tamil script
// is what gets spoken, Thanglish readers see Latin. A Thanglish string
// handed to a ta-IN engine is unintelligible.
library;

import '../tamil_transliteration.dart';
import 'chitti_section_registry.dart';

/// A screen explanation, in the two forms every caller needs.
class ChittiGuidance {
  const ChittiGuidance({required this.shown, required this.spoken});

  /// What goes on screen.
  final String shown;

  /// What goes to the TTS engine. Differs from [shown] only for
  /// Thanglish — see the file header.
  final String spoken;
}

class ChittiScreenGuide {
  ChittiScreenGuide._();

  /// Tamil guidance for the screens an owner actually works in.
  ///
  /// Keyed by the section key, so a screen added to the registry
  /// without a line here degrades to a generated sentence rather than
  /// to silence — see [_fallback].
  static const Map<String, ({String ta, String en})> _lines = {
    'admin_dashboard': (
      ta: 'இது உங்க முதன்மை திரை. இங்க இன்னைக்கு எத்தனை ஆர்டர், '
          'எத்தனை பேர் அப்ரூவலுக்கு காத்திருக்காங்கனு தெரியும். '
          'மேல வலது பக்கம் மெனுவை அமுத்தினா மத்த எல்லா பகுதிக்கும் போகலாம்.',
      en: 'This is your main screen. It shows today\'s orders and who is '
          'waiting for approval. The menu at the top right opens every '
          'other section.',
    ),
    'admin_new_orders': (
      ta: 'இங்க உங்க முடிவுக்காக காத்திருக்கிற புது ஆர்டர்கள் இருக்கும். '
          'பத்து நிமிஷத்துக்கு மேல ஒரு ஆர்டரை நீங்க பாக்கலைனா, ஹீரோக்கள் '
          'அதை தாங்களே எடுத்துக்குவாங்க — வாடிக்கையாளர் காத்திருக்க மாட்டார்.',
      en: 'New orders waiting for your decision. If one sits more than ten '
          'minutes, heroes can release it themselves so the customer is '
          'not left waiting.',
    ),
    'admin_hero_approvals': (
      ta: 'ஆவணங்கள் சரிபார்ப்புக்காக காத்திருக்கிற ஹீரோக்கள். ஒவ்வொருத்தரையும் '
          'அமுத்தி ஆவணங்களை பாருங்க, அப்புறம் ஒப்புங்க அல்லது மறுங்க. '
          'சீக்கிரம் முடிச்சா அவங்க இன்னைக்கே வேலைக்கு போகலாம்.',
      en: 'Heroes waiting for document verification. Tap one to see the '
          'documents, then approve or reject. The sooner you finish, the '
          'sooner they can work.',
    ),
    'admin_seller_approvals': (
      ta: 'பதிவு செஞ்ச கடைகள் ஒப்புதலுக்கு காத்திருக்காங்க. ஒப்புகிறதுக்கு '
          'முன்னாடி கடையோட விவரங்களை சரிபாருங்க — ஒப்புனதும் அவங்க '
          'வாடிக்கையாளருக்கு தெரிய ஆரம்பிப்பாங்க.',
      en: 'Shops waiting for approval. Check their details before you '
          'approve — once approved they become visible to customers.',
    ),
    'chitti_enquiries': (
      ta: 'சிட்டியால விலை சொல்ல முடியாத வாடிக்கையாளர் கேள்விகள் இங்க வரும். '
          'ஒவ்வொண்ணுலயும் அவங்க ஃபோன் நம்பர் இருக்கும். சீக்கிரம் கூப்பிடுங்க — '
          'நாளைக்கு பதில் சொன்னா வேற கடை ஏற்கனவே சொல்லியிருக்கும்.',
      en: 'Customer price questions Chitti could not answer. Each one has '
          'their phone number. Call soon — tomorrow, another shop has '
          'already answered.',
    ),
    'admin_dispatch': (
      ta: 'ஹீரோக்கள் எங்க இருக்காங்க, யாரு இப்போ வேலையில இருக்காங்கனு '
          'இங்க நேரடியா தெரியும். ஒரு ஆர்டரை கையால ஒதுக்கணும்னா இங்கிருந்து '
          'செய்யலாம்.',
      en: 'Live view of where your heroes are and who is busy. Assign an '
          'order by hand from here.',
    ),
  };

  /// Guidance for [sectionKey] in [languageCode].
  ///
  /// Never returns null: a screen with no written line still gets a
  /// usable sentence built from the registry, because "I don't know
  /// what this screen is" from the app's own assistant is worse than a
  /// plain one.
  static ChittiGuidance forSection(
    String? sectionKey,
    String languageCode, {
    String? variant,
  }) {
    final entry = _lines[sectionKey];
    final ta = entry?.ta ?? _fallback(sectionKey, variant, tamil: true);
    final en = entry?.en ?? _fallback(sectionKey, variant, tamil: false);

    return switch (languageCode) {
      'ta' => ChittiGuidance(shown: ta, spoken: ta),
      // Thanglish READS Latin but HEARS Tamil, so the engine gets
      // something it can pronounce.
      'tg' => ChittiGuidance(
          shown: TamilTransliteration.toLatin(ta),
          spoken: ta,
        ),
      _ => ChittiGuidance(shown: en, spoken: en),
    };
  }

  /// A sentence built from what the registry already knows.
  static String _fallback(String? key, String? variant, {required bool tamil}) {
    final section = key == null
        ? null
        : chittiSectionByKey(key, variant ?? 'admin');
    if (section == null) {
      return tamil
          ? 'இந்த திரையை பத்தி என்கிட்ட விவரம் இல்ல. என்ன பண்ணனும்னு '
              'சொல்லுங்க, நான் பாத்துக்கறேன்.'
          : "I don't have a description for this screen. Tell me what you "
              'need and I will do it.';
    }
    return tamil
        ? 'இது ${section.label}. ${section.description} '
            'என்ன பண்ணனும்னு சொல்லுங்க.'
        : 'This is ${section.label}. ${section.description} '
            'Tell me what you need.';
  }

  /// The section key for whatever screen is showing right now.
  ///
  /// The tracker records a human LABEL, not a key — it has to, because
  /// most of the app pushes screens without a route name. So this maps
  /// back through the registry by label. Returns null when the screen
  /// is not a registered section, and [forSection] handles that.
  static String? currentSectionKey(String? screenLabel, String variant) {
    final label = screenLabel?.trim().toLowerCase();
    if (label == null || label.isEmpty) return null;
    for (final s in chittiSectionsFor(variant)) {
      if (s.label.toLowerCase() == label) return s.key;
    }
    // Aliases second, and only as a whole-word match: a substring
    // check here would map "New Orders" onto "orders" and explain the
    // wrong screen with total confidence.
    for (final s in chittiSectionsFor(variant)) {
      if (s.aliases.any((a) => a.toLowerCase() == label)) return s.key;
    }
    return null;
  }

  /// Whether a hand-written line exists for this screen.
  ///
  /// Used by the test that stops the written set silently shrinking as
  /// screens are renamed.
  static bool hasWrittenLine(String sectionKey) =>
      _lines.containsKey(sectionKey);

  /// Every screen with a hand-written line.
  static Iterable<String> get writtenSections => _lines.keys;
}
