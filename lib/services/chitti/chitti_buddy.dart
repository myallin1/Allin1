// ================================================================
// chitti_buddy.dart — the half of Chitti that is not useful, and is
// supposed to be.
// ================================================================
// NEW (Aug 28 2026 — CEO: "namma Myallin1 app mattum ilama Chittya
// avangaluku pidikanum ... avanga kuda oru buddy-a avangala sirikka
// vaikanum ... namma Chitti nala namma app oru fun and joyful featured
// app-a irukanum").
//
// Everything else in this folder makes Chitti CAPABLE. Capability is
// not the same as likeable, and a customer who finds an assistant
// useful still closes the app the moment it stops being needed. The
// ask here is a different one: give people a reason to open it.
//
// THREE RULES THIS FILE IS BUILT AROUND
//
// 1. EARN IT FIRST. A quip lands after Chitti has actually done
//    something. The same line before the work reads as stalling. So
//    these attach to completed actions and to the daily greeting —
//    never to an error, never to a wait.
//
// 2. NEVER AT THE CUSTOMER'S EXPENSE, AND NEVER ON A BAD DAY. Money,
//    an emergency, a cancellation, a complaint, a failure — those get
//    a straight answer and nothing else. A joke next to someone's SOS
//    is not a personality, it is a bug. [isSafeMoment] is the gate,
//    and it is deliberately pessimistic.
//
// 3. NOT EVERY TIME. Humour that fires on every single action stops
//    being humour by the third one and becomes noise you have to read
//    past. These surface roughly one time in three, and never twice in
//    a row.
//
// All of it is offline: no key, no network, no tokens. The model, when
// there is one, is funnier — this is the floor, not the ceiling.
import '../../config/app_variant.dart';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../daily_quote_service.dart';

class ChittiBuddy {
  ChittiBuddy._();

  static final Random _random = Random();
  static String? _lastQuip;

  /// Topics that switch the personality off entirely.
  ///
  /// Matched against whatever Chitti is about to say AND what the
  /// customer said, because either side can make the moment wrong.
  static final RegExp _seriousTopic = RegExp(
    r'\b(sos|emergency|accident|police|hospital|ambulance|'
    'cancel|cancelled|refund|failed|error|problem|complaint|missing|'
    'lost|wrong|charge|charged|payment|paid|money|balance|owe|due|'
    r'kyc|verify|verification)\b|'
    // A failure is almost always phrased POLITELY, not with the word
    // "failed" — "I couldn't place that order just now" contains none
    // of the words above. Caught by the tests, and it is the worst
    // possible moment for a quip: the customer has just been told
    // something did not work.
    r"\b(couldn't|could not|cannot|can't|unable|sorry|didn't|"
    r'did not|went wrong|try again|no luck)\b|'
    '(அவசர|விபத்து|காவல்|மருத்துவ|ரத்து|பணம்|தவறு|புகார்)',
    caseSensitive: false,
  );

  /// Whether a light line is appropriate right now.
  ///
  /// Pessimistic on purpose: when in doubt, say nothing funny. The cost
  /// of a missed joke is zero; the cost of a joke next to a lost
  /// payment is a customer who never trusts the assistant again.
  static bool isSafeMoment({String? saying, String? userSaid}) {
    if (saying != null && _seriousTopic.hasMatch(saying)) return false;
    if (userSaid != null && _seriousTopic.hasMatch(userSaid)) return false;
    return true;
  }

  /// A short line to add after Chitti has finished something.
  ///
  /// Returns null most of the time — see rule 3. Callers should append
  /// it to their own reply rather than sending it alone; a quip with no
  /// answer attached is exactly the "bot" behaviour this is meant to
  /// avoid.
  static String? quipAfterAction({
    required String languageCode,
    String? saying,
    String? userSaid,
    /// Test seam — forces the line instead of leaving it to chance.
    bool always = false,
  }) {
    if (!isSafeMoment(saying: saying, userSaid: userSaid)) return null;
    if (!always && _random.nextInt(3) != 0) return null;

    final pool = _quipsFor(languageCode);
    if (pool.isEmpty) return null;

    // Never the same line twice running — repetition is what makes a
    // canned personality feel canned.
    final choices = pool.length > 1
        ? pool.where((q) => q != _lastQuip).toList(growable: false)
        : pool;
    final pick = choices[_random.nextInt(choices.length)];
    _lastQuip = pick;
    return pick;
  }

  /// Today's motivational line, in the customer's own language.
  ///
  /// CEO's explicit ask: Chitti reads it out when the app opens. Uses
  /// the existing DailyQuoteService rather than a second list, so the
  /// line Chitti speaks is the same one the app shows — hearing one
  /// quote and reading a different one would be worse than silence.
  /// Today's quote as it should be SPOKEN.
  ///
  /// For 'tg' this is the Tamil original, not the transliteration —
  /// see tamil_transliteration.dart. Everything else matches
  /// [dailyQuote].
  static String? spokenDailyQuote(String languageCode, {String? variant}) {
    try {
      final service = DailyQuoteService.instance;
      final text = service.spokenForRole(
        variant ?? currentAppVariant,
        languageCode,
      );
      return text.trim().isEmpty ? null : text.trim();
    } catch (e) {
      debugPrint('[ChittiBuddy] spoken daily quote failed: $e');
      return null;
    }
  }

  /// Today's line for whoever is running this build.
  ///
  /// CHANGED (Aug 28 2026 — Nizam: "daily customer, seller, hero, admin
  /// ku pudhusa theriyanum, but avangavanga role ku nalla motivator ah
  /// irukanum"). This used to be a bool: hero, or everyone else. So a
  /// seller deciding whether to stay open another hour was told to
  /// "support a local shop today" — the customer pool talking to the
  /// shop. Four pools now, routed by variant.
  static String? dailyQuote(String languageCode, {String? variant}) {
    try {
      final service = DailyQuoteService.instance;
      final text = service.forRole(
        variant ?? currentAppVariant,
        languageCode,
      );
      return text.trim().isEmpty ? null : text.trim();
    } catch (e) {
      debugPrint('[ChittiBuddy] daily quote failed: $e');
      return null;
    }
  }

  /// Topics serious enough that even WARMTH is the wrong response --
  /// only a straight, calm answer helps here. A "so sorry to hear
  /// that" bolted onto an SOS alert or a hospital run reads as the app
  /// not taking it seriously.
  static final RegExp _emergencyTopic = RegExp(
    r'\b(sos|emergency|accident|police|hospital|ambulance|kyc|verify|'
    r'verification)\b|'
    '(அவசர|விபத்து|காவல்|மருத்துவ)',
    caseSensitive: false,
  );

  /// A short, genuine line of comfort for a setback that is real but
  /// not an emergency -- a cancelled order, a failed payment, a
  /// complaint, something that went wrong.
  ///
  /// This is the other half of [isSafeMoment]: that gate correctly
  /// turns the JOKE layer off here, because rule 2 in this file's
  /// header is "never at the customer's expense". But going quiet is
  /// not the same as sounding like someone who noticed. This fills
  /// that gap -- offline, no API key needed, same as the rest of this
  /// file.
  ///
  /// Returns null for anything that is not actually a setback (a
  /// plain factual reply needs no comfort bolted onto it) and for true
  /// emergencies (see [_emergencyTopic]), where a canned warm line
  /// would be the wrong tone entirely.
  /// Genuinely negative-outcome language -- narrower than
  /// [_seriousTopic] on purpose. That gate also matches plain money
  /// words ("balance", "due") so the JOKE layer stays off near
  /// anything financial; reusing it here would make a completely
  /// ordinary "your wallet balance is 250 rupees" reply get a
  /// "that's frustrating" line stapled onto it, which is worse than
  /// no comfort layer at all.
  static final RegExp _setbackTopic = RegExp(
    r'\b(cancel|cancelled|refund|failed|error|complaint|missing|lost|'
    r"wrong|couldn't|could not|cannot|can't|unable|sorry|didn't|"
    r'did not|went wrong|try again|no luck)\b|'
    '(ரத்து|தவறு|புகார்|கிடைக்கல)',
    caseSensitive: false,
  );

  static String? comfortAfterSetback({
    required String languageCode,
    String? saying,
    String? userSaid,
  }) {
    final text = '${saying ?? ''} ${userSaid ?? ''}';
    if (_emergencyTopic.hasMatch(text)) return null;
    if (!_setbackTopic.hasMatch(text)) return null;

    final pool = _comfortLinesFor(languageCode);
    if (pool.isEmpty) return null;
    final choices = pool.length > 1
        ? pool.where((q) => q != _lastComfort).toList(growable: false)
        : pool;
    final pick = choices[_random.nextInt(choices.length)];
    _lastComfort = pick;
    return pick;
  }

  static String? _lastComfort;

  // Deliberately plain, not jokey -- this is the ONE place in the file
  // that is not supposed to be funny. Short, because it is read aloud
  // too.
  static List<String> _comfortLinesFor(String code) => switch (code) {
        'ta' || 'tg' => const <String>[
            'கவலைப்படாதீங்க, நான் இருக்கேன் — சரி பண்றோம்.',
            'இது நடந்ததுக்கு வருத்தம். உடனே பாத்துக்கறேன்.',
            'புரியுது, சரிசெய்ய பாக்கிறேன் — நீங்க தனியா இல்ல.',
          ],
        _ => const <String>[
            "That's frustrating, I know. Let's sort it out.",
            "Sorry this happened — I'm on it with you.",
            "I hear you. You're not alone in this, let's fix it.",
          ],
      };

  // Short on purpose. These are spoken aloud as well as shown, and a
  // long joke read by a TTS engine at 0.5x rate is not funny.
  static List<String> _quipsFor(String code) => switch (code) {
        'ta' || 'tg' => const <String>[
            'இந்த மாதிரி வேலைக்கு நான் தான் பாஸ்.',
            'ரெண்டு விநாடி. மனுஷன் ஆனா ஒரு காபி குடிச்சிருப்பான்.',
            'சொல்லுங்க பாஸ், இன்னும் ஏதாவது இருக்கா?',
            'நான் ஓய்வே எடுக்க மாட்டேன், பேட்டரி மட்டும் தான் பிரச்சனை.',
            'இதுக்கு எனக்கு ஒரு தேநீர் கூட வேணாம்.',
          ],
        'hi' => const <String>[
            'दो सेकंड में। इंसान होता तो चाय पी रहा होता।',
            'और कुछ, बॉस?',
            'मैं थकता नहीं हूँ, बस चार्ज खत्म होता है।',
          ],
        'ml' => const <String>[
            'രണ്ട് സെക്കൻഡ്. ഇനി എന്ത് വേണം ബോസ്?',
            'എനിക്ക് ക്ഷീണം ഇല്ല, ചാർജ് മാത്രം തീരും.',
          ],
        _ => const <String>[
            'Two seconds. A human would still be looking for the button.',
            "Anything else, boss? I'm not exactly busy.",
            'I never get tired. The battery does, but I do not.',
            'Filed, done, dusted.',
            "That's what I'm here for — and I don't even drink tea.",
          ],
      };

  @visibleForTesting
  static void resetForTesting() => _lastQuip = null;
}
