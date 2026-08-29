// ================================================================
// chitti_hero_voice.dart — Chitti speaking FOR the Hero, on both sides.
// ================================================================
// NEW (Aug 28 2026 — Nizam, two halves of one idea):
//
//   HERO SIDE  "heros kita boss naan unga dude iruken, neenga kavala
//              padatheenga, nalla sambaringanu drivers ah apopo
//              motivate panni, customer ah mathinganu sollanum"
//
//   CUSTOMER   "customer kita hero ungalukkaga romba ulaikkuraru, so
//   SIDE       avaruku kanakku pakkama mulu manasoda amount kudunga...
//              customer entha language use pandraro antha language la
//              heros ah promote pannanum"
//
// WHY THE TWO HALVES BELONG IN ONE FILE
// They are the same intention pointed in opposite directions, and they
// have to stay consistent. If the hero app promises "treat the customer
// well and it comes back to you" while the customer app says nothing
// about the hero, the promise is false. Splitting them across two files
// is how they would quietly drift apart.
//
// THE HARD CONSTRAINT: THIS IS ADVOCACY, NOT A CHARGE
// Nizam's words are "kanakku pakkama mulu manasoda amount kudunga" —
// give wholeheartedly, without counting. That is a request to the
// customer's conscience, NOT a surcharge, a default tip, or a
// pre-ticked box. Chitti may say the hero worked hard; it may never
// move money on the customer's behalf, and it must never make someone
// feel watched for saying no. Anything that reads as pressure would
// turn goodwill into resentment and cost NJ Tech the customer AND the
// hero's next trip.
//
// TIMING IS PART OF THE DESIGN
// The customer line belongs AFTER a completed trip, when there is a
// real person to be grateful to. Said before booking it is a sales
// pitch; said during a delay it is an excuse. See [isGoodMomentToAdvocate].
//
// LANGUAGE
// Both sides follow the app-wide rule: Tamil readers get Tamil script,
// Thanglish readers get Latin, and what is SPOKEN is always the Tamil
// original so pronunciation stays correct. See tamil_transliteration.dart.
library;

import '../tamil_transliteration.dart';

/// Where the Hero currently is, as far as the customer is concerned.
enum HeroMoment {
  /// Nothing running — advocacy would be an advertisement.
  idle,

  /// A hero is on the way. Reassure, do not ask for anything.
  onTheWay,

  /// Delivered. This is the moment gratitude is real.
  completed,
}

class ChittiHeroVoice {
  ChittiHeroVoice._();

  // ── HERO SIDE ───────────────────────────────────────────────────

  /// "Boss, I am your dude" — Chitti checking in on a rider.
  ///
  /// Deliberately not a performance review. A rider reading this is
  /// often tired, often mid-shift, and a number they are falling short
  /// of is the last thing that helps. Reassurance first, and the
  /// customer-care reminder framed as what earns the NEXT trip rather
  /// than as an instruction.
  static const List<({String en, String ta})> _heroPep = [
    (
      en: "Boss, I am your dude — do not worry. Keep going, the earnings "
          "will come.",
      ta: 'பாஸ், நான் உங்க தோஸ்த் — கவலைப்படாதீங்க. தொடர்ந்து போங்க, '
          'வருமானம் வரும்.',
    ),
    (
      en: "Boss, treat the customer well today. That is what brings "
          "tomorrow's trip.",
      ta: 'பாஸ், இன்னைக்கு வாடிக்கையாளரை நல்லா கவனிங்க — அதுதான் நாளைய '
          'டிரிப்பை கொண்டு வரும்.',
    ),
    (
      en: 'Boss, a smile at the door costs nothing and pays every week.',
      ta: 'பாஸ், வாசல்ல ஒரு புன்னகை — செலவே இல்லை, ஒவ்வொரு வாரமும் '
          'பலன் தரும்.',
    ),
    (
      en: "Boss, slow day? Do not lose heart. The road always pays back.",
      ta: 'பாஸ், இன்னைக்கு வேலை குறைவா? மனசு தளராதீங்க — ரோடு எப்பவும் '
          'திருப்பி தரும்.',
    ),
    (
      en: "Boss, you are earning well because people trust you. Keep "
          "that trust.",
      ta: 'பாஸ், மக்கள் நம்புறதாலதான் நீங்க நல்லா சம்பாதிக்கிறீங்க — '
          'அந்த நம்பிக்கையை காப்பாத்துங்க.',
    ),
    (
      en: "Boss, I am watching your numbers so you do not have to worry "
          "about them.",
      ta: 'பாஸ், உங்க கணக்கை நான் பாத்துக்கறேன் — நீங்க கவலைப்பட '
          'வேண்டாம்.',
    ),
    (
      en: 'Boss, ride safe. Money can wait; you cannot be replaced.',
      ta: 'பாஸ், பத்திரமா ஓட்டுங்க. காசு காத்திருக்கும் — உங்களுக்கு '
          'பதிலா யாரும் இல்ல.',
    ),
    (
      en: "Boss, one good word to the customer and they will ask for you "
          "next time.",
      ta: 'பாஸ், வாடிக்கையாளர்கிட்ட ஒரு நல்ல வார்த்தை — அடுத்த முறை '
          'உங்களையே கேட்பாங்க.',
    ),
  ];

  /// A pep line for the Hero app, in [languageCode].
  ///
  /// [seed] picks which one — pass something that changes slowly (the
  /// day, a trip count) so it does not flicker on every rebuild.
  static String heroPep(String languageCode, {int seed = 0}) {
    final q = _heroPep[seed.abs() % _heroPep.length];
    return _render(q.en, q.ta, languageCode);
  }

  /// The same line, in the form a TTS engine can pronounce.
  static String spokenHeroPep(String languageCode, {int seed = 0}) {
    final q = _heroPep[seed.abs() % _heroPep.length];
    return _spoken(q.en, q.ta, languageCode);
  }

  // ── CUSTOMER SIDE ───────────────────────────────────────────────

  /// Chitti putting in a word for the Hero who did the work.
  ///
  /// Every line names the effort and stops. None of them asks for a
  /// specific amount, and none implies the customer is being judged —
  /// see the file header on why that boundary is not negotiable.
  static const List<({String en, String ta})> _advocacy = [
    (
      en: 'Your hero worked really hard for this one. If you can, give '
          'wholeheartedly — it reaches a real family.',
      ta: 'உங்க ஹீரோ இதுக்காக ரொம்ப உழைச்சிருக்கார். முடிஞ்சா மனசார '
          'கொடுங்க — அது ஒரு குடும்பத்தை சேரும்.',
    ),
    (
      en: 'That hero rode through the traffic for you. A little extra, '
          'given from the heart, means a lot to them.',
      ta: 'அந்த ஹீரோ உங்களுக்காக ட்ராஃபிக்கை கடந்து வந்திருக்கார். '
          'மனசார கொஞ்சம் அதிகமா கொடுத்தா அவருக்கு ரொம்ப பெரிசு.',
    ),
    (
      en: 'Heroes like yours are why this app works. Do not count too '
          'closely — give what feels right.',
      ta: 'இந்த மாதிரி ஹீரோக்கள்தான் இந்த ஆப்பை ஓட வைக்கிறாங்க. '
          'கணக்கு பாக்காம, மனசுக்கு சரினு படுறதை கொடுங்க.',
    ),
    (
      en: 'Your hero showed up in this weather so you did not have to. '
          'A kind word or a little extra — both count.',
      ta: 'நீங்க வெளியே வர வேண்டாம்னு உங்க ஹீரோ இந்த வானிலையிலயும் '
          'வந்தார். ஒரு நல்ல வார்த்தை, கொஞ்சம் அதிகம் — ரெண்டுமே பெரிசு.',
    ),
    (
      en: 'They finished your work with full effort. If it deserves it, '
          'give with a full heart.',
      ta: 'உங்க வேலையை முழு உழைப்போட முடிச்சிருக்கார். தகுதி இருந்தா '
          'முழு மனசோட கொடுங்க.',
    ),
    (
      en: 'Behind that delivery is somebody supporting a family. Give '
          'without counting, if you can.',
      ta: 'அந்த டெலிவரிக்கு பின்னாடி ஒரு குடும்பத்தை காப்பாத்துற '
          'ஒருத்தர் இருக்கார். முடிஞ்சா கணக்கு பாக்காம கொடுங்க.',
    ),
  ];

  /// Reassurance while the Hero is still on the way.
  ///
  /// Separate from the advocacy lines on purpose: asking for generosity
  /// while the customer is still waiting reads as an excuse for the
  /// delay, not as gratitude.
  static const List<({String en, String ta})> _onTheWay = [
    (
      en: 'Your hero is on the way and working hard to reach you soon.',
      ta: 'உங்க ஹீரோ வந்துட்டு இருக்கார் — சீக்கிரம் வர கஷ்டப்படுறார்.',
    ),
    (
      en: 'Someone is riding out there for you right now. Almost there.',
      ta: 'இப்போ ஒருத்தர் உங்களுக்காக ரோட்ல இருக்கார். கிட்டத்தட்ட '
          'வந்துட்டார்.',
    ),
  ];

  /// A line promoting the Hero to the customer, in THEIR language.
  ///
  /// Returns null when this is not the moment for it — see
  /// [isGoodMomentToAdvocate]. A null here is a feature: a customer who
  /// is told about the hero's effort at the wrong time hears an excuse.
  static String? advocateForHero(
    String languageCode, {
    required HeroMoment moment,
    int seed = 0,
  }) {
    switch (moment) {
      case HeroMoment.idle:
        return null;
      case HeroMoment.onTheWay:
        final q = _onTheWay[seed.abs() % _onTheWay.length];
        return _render(q.en, q.ta, languageCode);
      case HeroMoment.completed:
        final q = _advocacy[seed.abs() % _advocacy.length];
        return _render(q.en, q.ta, languageCode);
    }
  }

  /// The spoken form of [advocateForHero].
  static String? spokenAdvocateForHero(
    String languageCode, {
    required HeroMoment moment,
    int seed = 0,
  }) {
    switch (moment) {
      case HeroMoment.idle:
        return null;
      case HeroMoment.onTheWay:
        final q = _onTheWay[seed.abs() % _onTheWay.length];
        return _spoken(q.en, q.ta, languageCode);
      case HeroMoment.completed:
        final q = _advocacy[seed.abs() % _advocacy.length];
        return _spoken(q.en, q.ta, languageCode);
    }
  }

  /// Whether now is a moment where speaking up for the hero helps.
  ///
  /// Only after the work is done. Before booking it is a sales pitch;
  /// mid-delay it sounds like the app making excuses for itself.
  static bool isGoodMomentToAdvocate(HeroMoment moment) =>
      moment == HeroMoment.completed;

  // ── shared rendering ────────────────────────────────────────────

  static String _render(String en, String ta, String languageCode) =>
      switch (languageCode) {
        'ta' => ta,
        // Display only — never hand this to TTS. See _spoken.
        'tg' => TamilTransliteration.toLatin(ta),
        _ => en,
      };

  static String _spoken(String en, String ta, String languageCode) =>
      (languageCode == 'ta' || languageCode == 'tg') ? ta : en;
}
