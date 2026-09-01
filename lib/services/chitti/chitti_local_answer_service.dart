// ================================================================
// chitti_local_answer_service.dart — Tier 1.5: ANSWER questions about
// the app with no API call.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "voice la pesumbothu ilama customer Chitti
// kita text pannunalum namma app oda a to z details solliruvanla ...
// ithuku munnadi varayum Chitti network issue nu sonna").
//
// Tier 1 (chitti_local_intent_engine.dart) resolves what to DO. It has
// nothing to say when the customer asks a QUESTION — "what is this
// page?", "how do I cancel?", "what can you do?" — and those fell
// straight through to the model. With no key, or on a bad Erode
// connection, the reply was "Chitti AI is having a short network
// pause", which is both useless and untrue: the answer was sitting in
// the app's own registries the whole time.
//
// This closes that. The app already carries a complete, structured
// description of itself:
//   • kChittiSections — 56 screens, each with a label and a one-line
//     description of what it is for;
//   • kChittiTools    — 25 capabilities, each with a description
//     written for a model but perfectly readable by a person;
//   • ChittiMemoryService.currentScreen — where the customer is
//     standing right now.
// A question about the app is a lookup against those, not a language
// problem. So it runs on device, instantly, for free.
//
// WHERE IT SITS
// After the intent engine (doing beats explaining) and BEFORE the
// "network pause" apology. When a key IS available and the network is
// fine, the model still handles anything this cannot — this is a floor
// under the experience, not a replacement for it.
//
// WHAT IT WILL NOT DO
// It never guesses. If the question is not about a section, a
// capability, or the current screen, it returns null and lets the
// caller carry on. A confidently wrong answer about the customer's own
// app is worse than "I could not reach the full AI for that one".
import 'package:flutter/foundation.dart';

import '../../config/app_variant.dart';
import '../chitti_memory_service.dart';
import 'chitti_chat_intents.dart';
import 'chitti_enquiry_service.dart';
import 'chitti_market_answer_service.dart';
import 'chitti_screen_advisor.dart';
import 'chitti_section_registry.dart';
import 'chitti_tool_registry.dart';
import 'chitti_video_service.dart';

/// An answer, plus the chips that should sit under it.
@immutable
class ChittiLocalAnswer {
  const ChittiLocalAnswer(
    this.text, {
    this.suggestions = const <String>[],
    this.videoId,
  });

  final String text;
  final List<String> suggestions;

  /// A YouTube video to show under the reply, as a tappable card.
  ///
  /// NEW (Aug 28 2026 — Nizam: "suppose Chitti yethachum video-va
  /// reference kudukanumna, YouTube la irunthu antha link reward
  /// maariye screen la stretch agi play aganum customer ku Chitti chat
  /// section-laye").
  ///
  /// Deliberately just an ID on a data object: the chat layer decides
  /// how to render it, so this file stays free of widgets and the
  /// overlay and the full screen can present it differently without a
  /// second source of truth.
  final String? videoId;
}

class ChittiLocalAnswerService {
  ChittiLocalAnswerService._();

  /// Answers [question] from the app's own registries, or returns null.
  ///
  /// Synchronous, so it can be called from anywhere. For a reply that
  /// also reads the LIVE screen (fields still blank, buttons actually
  /// on the page), use [answerWithScreen] instead — that one is worth
  /// the extra frame.
  static ChittiLocalAnswer? answer(String question, {String? variant, String languageCode = 'en'}) {
    final v = variant ?? currentAppVariant;
    final q = _normalize(question);
    if (q.isEmpty) return null;
    final ta = languageCode == 'ta' || languageCode == 'tg';

    // Order matters: the most specific interpretation first. "What can
    // I do here" is about the screen; "what can you do" is about
    // Chitti; a bare section name is a lookup. Checking the broad one
    // first would swallow the narrow ones.
    return _aboutCurrentScreen(q, v, ta) ??
        // Identity BEFORE capability: "who are you" is a personal
        // question first, not a request for the tool list — checked
        // ahead of _aboutChitti so it does not get swallowed by the
        // broader capability regex those two phrasings also match.
        _aboutIdentity(q, ta) ??
        _aboutChitti(q, v, ta) ??
        _howDoI(q, v, ta) ??
        _aboutSection(q, v, ta);
  }


  // ── "how are you / who are you / who made you / where are you from"
  // ─────────────────────────────────────────────────────────────────
  //
  // These are questions about CHITTI, not about the app, and they
  // needed a fixed answer for the same reason a receptionist gives the
  // same answer twice: a customer who asks "who are you" and gets a
  // different improvised answer each time reads as broken, not
  // charming. Kept in the "naughty Chitti" voice (see guru_api_service
  // .dart's persona text) rather than a corporate boilerplate line.

  static final RegExp _howAreYouAsk = RegExp(
    r'\bhow (are|r) (you|u|ya)\b|how.?s it going|how do you feel|'
    r'(எப்படி இருக்க|எப்படி இருக்கீங்க|சௌக்கியமா)',
  );

  static final RegExp _whoAreYouAsk = RegExp(
    r'\bwho (are|r) (you|u)\b|\bwhat are you\b|introduce yourself|'
    r'(நீ யாரு|உன் பேரு என்ன|நீங்க யாரு)',
  );

  static final RegExp _ownerAsk = RegExp(
    r"\bwho.?s your (owner|creator|boss|maker)\b|who made you|"
    r'who built you|who created you|who owns you|'
    r'(உன்ன யாரு உருவாக்கின|உன் முதலாளி யாரு|உன்ன யாரு பண்ணாங்க)',
  );

  static final RegExp _birthAsk = RegExp(
    r"\b(your )?birth ?place\b|where (were|are) you (born|from|made)|"
    r'\bwhere do you live\b|'
    r'(உன் பிறந்த இடம்|எங்க பொறந்த|எங்க உருவானே)',
  );

  static ChittiLocalAnswer? _aboutIdentity(String q, bool ta) {
    if (_howAreYouAsk.hasMatch(q)) {
      return ChittiLocalAnswer(
        ta
            ? 'செம்மயா இருக்கேன் பாஸ்! சூப்பரா வேலை செய்ய ரெடி. இன்னைக்கு உங்களுக்கு என்ன பண்ணனும் சொல்லுங்க?'
            : 'Superb, boss — running fast and ready to work. What do you need?',
        suggestions: ta
            ? const <String>['நீ என்ன பண்ணுவ?', 'வண்டி புக் பண்ணு', 'என் ஆர்டர்']
            : const <String>['What can you do?', 'Book a ride', 'My orders'],
      );
    }
    if (_ownerAsk.hasMatch(q)) {
      return ChittiLocalAnswer(
        ta
            ? 'நம்ம ஈரோடு NJ Tech தான் என்ன உருவாக்கினாங்க. நான் நம்ம Allin1 அசிஸ்டெண்ட். வேற யாரும் எனக்கு சொந்தம் இல்லை பாஸ்!'
            : 'NJ Tech built me — I work for MyAllin1, right here in Erode. Nobody else owns a piece of me.',
        suggestions: ta
            ? const <String>['நீ என்ன பண்ணுவ?', 'NJ Tech பற்றி சொல்லு']
            : const <String>['What can you do?', 'Tell me about NJ Tech'],
      );
    }
    if (_birthAsk.hasMatch(q)) {
      return ChittiLocalAnswer(
        ta
            ? 'நான் நம்ம ஈரோட்டுல இந்த ஆப்-குள்ள தான் பொறந்தேன் பாஸ். ஹாஸ்பிடல் எல்லாம் கிடையாது, வெறும் கோடிங் தான்!'
            : 'I was born right here in this app, in Erode — no hospital, just code and a lot of coffee for whoever built me.',
        suggestions: ta
            ? const <String>['யாரு உன்ன பண்ணாங்க?', 'நீ என்ன பண்ணுவ?']
            : const <String>['Who made you?', 'What can you do?'],
      );
    }
    if (_whoAreYouAsk.hasMatch(q)) {
      return ChittiLocalAnswer(
        ta
            ? 'நான் தான் உங்க சிட்டி பாஸ்! நம்ம Allin1 ஆப்போட சொந்த அசிஸ்டெண்ட். உங்க வண்டியை புக் பண்றது, வாலெட்டை பாத்துக்கிறது எல்லாமே நான் செய்வேன்!'
            : 'I\'m Chitti — MyAllin1\'s own AI, boss. Half assistant, half troublemaker. I book your rides, watch your wallet, and keep you company while I\'m at it.',
        suggestions: ta
            ? const <String>['நீ என்ன பண்ணுவ?', 'என் வாலெட் பேலன்ஸ்']
            : const <String>['What can you do?', 'My wallet balance'],
      );
    }
    return null;
  }

  // ── "what is this page?" ─────────────────────────────────────────

  static final RegExp _thisScreenAsk = RegExp(
    r'\b(this (page|screen|section)|here|current (page|screen))\b|'
    '(இந்த (பக்கம்|பேஜ்|ஸ்கிரீன்)|இங்க)',
  );

  static ChittiLocalAnswer? _aboutCurrentScreen(String q, String v, bool ta) {
    if (!_thisScreenAsk.hasMatch(q)) return null;

    final screen = ChittiMemoryService.instance.currentScreen;
    if (screen == null || screen.isEmpty) {
      return ChittiLocalAnswer(
        ta
            ? 'நீங்க எந்த பக்கத்துல இருக்கீங்கன்னு என்னால கண்டுபிடிக்க முடியல பாஸ். நீங்க என்ன பண்ணனும்னு சொன்னா அங்க கூட்டிட்டு போறேன்.'
            : "I can't tell which page you're on right now. Tell me what you're trying to do and I will take you there.",
        suggestions: ta
            ? const <String>['சாப்பாடு ஆர்டர்', 'வண்டி புக் பண்ணு', 'என் ஆர்டர்']
            : const <String>['Order food', 'Book a ride', 'My orders'],
      );
    }

    // currentScreen is a LABEL (set by ChittiScreenObserver), so match
    // on label rather than key — the observer never sees keys.
    final section = _sectionByLabel(screen, v);
    if (section == null) {
      return ChittiLocalAnswer(
        ta
            ? 'நீங்க $screen பக்கத்துல இருக்கீங்க. இங்க என்ன பண்ணனும் சொல்லுங்க, நான் பாத்துக்கறேன் பாஸ்!'
            : "You're on $screen. Tell me what you want to do here and I'll handle it.",
        suggestions: ta
            ? const <String>['நீ என்ன பண்ணுவ?', 'வேற எங்காவது போ']
            : const <String>['What can you do?', 'Go somewhere else'],
      );
    }

    return ChittiLocalAnswer(
      ta
          ? 'நீங்க ${section.label} பக்கத்துல இருக்கீங்க. ${section.description} உங்களுக்கு என்ன வேணும்னு சொல்லுங்க பாஸ்!'
          : "You're on ${section.label}. ${section.description} Tell me what you need and I will do it from here.",
      suggestions: _chipsForSection(section),
    );
  }

  // ── "what can you do?" ───────────────────────────────────────────

  static final RegExp _capabilityAsk = RegExp(
    r'\b(what can you do|what do you do|what are you|who are you|'
    r'help me|what can i ask|your features|what all)\b|'
    '(என்ன பண்ணுவ|என்ன செய்வ|உன்னால என்ன|நீ யாரு)',
  );

  static ChittiLocalAnswer? _aboutChitti(String q, String v, bool ta) {
    if (!_capabilityAsk.hasMatch(q)) return null;

    // Grouped by domain rather than listed flat: twenty-five tool names
    // in a row is not an answer, it is a data dump.
    final byDomain = <ChittiDomain, List<String>>{};
    for (final tool in kChittiTools) {
      if (!tool.variants.contains(v)) continue;
      byDomain.putIfAbsent(tool.domain, () => <String>[]).add(tool.name);
    }

    final lines = <String>[];
    void add(ChittiDomain d, String text, String textTa) {
      if (byDomain.containsKey(d)) lines.add(ta ? '• $textTa' : '• $text');
    }

    add(ChittiDomain.transport,
        'Book a bike, auto, cab, parcel, mini truck or lorry',
        'பைக், ஆட்டோ, கார், பார்சல் அல்லது லாரி புக் செய்யலாம்',);
    add(ChittiDomain.ordering,
        'Place food, grocery and Hero orders — and cancel or repeat them',
        'சாப்பாடு, மளிகை மற்றும் ஹீரோ ஆர்டர் செய்யலாம் — கேன்சலும் பண்ணலாம்',);
    add(ChittiDomain.navigation,
        'Open any of the ${chittiSectionsFor(v).length} sections in the app',
        'ஆப்பில் உள்ள ${chittiSectionsFor(v).length} பிரிவுகளில் எதை வேண்டுமானாலும் திறக்கலாம்',);
    add(ChittiDomain.account,
        'Check your wallet, coins, order status, past orders and profile',
        'உங்க வாலெட் பேலன்ஸ், காயின்கள் மற்றும் ஆர்டர் விபரங்களை அறியலாம்',);
    add(ChittiDomain.hero,
        'Take you online or offline, and read your earnings and current job',
        'உங்களை ஆன்லைன்/ஆஃப்லைன் செய்ய முடியும், வருமானத்தையும் அறியலாம்',);
    add(ChittiDomain.seller,
        'Show pending orders, open or close your shop, and read your sales',
        'ஆர்டர்களைப் பார்க்க, கடையை ஓபன்/குளோஸ் செய்ய, மற்றும் விற்பனையை அறியலாம்',);
    add(ChittiDomain.support,
        'Report a problem, check for app updates, and read screenshots',
        'பிரச்சனைகளைப் புகார் செய்ய மற்றும் ஆப் அப்டேட்டைச் சரிபார்க்கலாம்',);

    return ChittiLocalAnswer(
      ta
          ? "நிறைய வேலைகளைச் செய்வேன் பாஸ்:\n${lines.join('\n')}\n"
              "நெட்வொர்க் இல்லை என்றாலும் கூட பேசிக் வேலைகள் நடக்கும். உங்களுக்கு என்ன வேணும்னு சும்மா கேளுங்க பாஸ்!"
          : "Quite a lot, boss:\n${lines.join('\n')}\n"
              "Most of it works even with no internet. Just tell me what you "
              "want — no need for exact words.",
      suggestions: ta
          ? const <String>['இந்த பக்கம் என்ன?', 'என் வாலெட் பேலன்ஸ்', 'என் ஆர்டர்']
          : const <String>[
              'What is this page?',
              'My wallet balance',
              'My orders',
            ],
    );
  }

  // ── "how do I X?" / "where is X?" ────────────────────────────────

  static final RegExp _howWhereAsk = RegExp(
    r'\b(how (do|can) i|how to|where (is|are|can i)|i want to|i need to)\b|'
    '(எப்படி|எங்க இருக்கு|எங்கே)',
  );

  static ChittiLocalAnswer? _howDoI(String q, String v, bool ta) {
    if (!_howWhereAsk.hasMatch(q)) return null;
    final section = _bestSectionMatch(q, v);
    if (section == null) return null;
    return ChittiLocalAnswer(
      ta
          ? '${section.description} இது "${section.label}" பிரிவின் கீழ் உள்ளது பாஸ். "${section.label} ஓபன் பண்ணு" என்று சொன்னால் உடனே கூட்டிட்டு போயிடுவேன்.'
          : '${section.description} It is under ${section.label} — say "open '
              '${section.label}" and I will take you straight there.',
      suggestions: ta
          ? <String>['${section.label} ஓபன் பண்ணு', 'வேற ஏதாவது']
          : <String>['Open ${section.label}', 'Something else'],
    );
  }

  // ── a bare section name ──────────────────────────────────────────

  static ChittiLocalAnswer? _aboutSection(String q, String v, bool ta) {
    // Only for short messages. A section word buried in a long sentence
    // is far more likely to be part of a real question the model should
    // answer than a request for the section's description.
    if (q.split(' ').length > 4) return null;
    final section = _bestSectionMatch(q, v);
    if (section == null) return null;
    return ChittiLocalAnswer(
      '${section.label}: ${section.description}',
      suggestions: ta
          ? <String>['${section.label} ஓபன் பண்ணு', 'வேற என்ன பண்ணுவ?']
          : <String>['Open ${section.label}', 'What else can you do?'],
    );
  }

  // ── helpers ──────────────────────────────────────────────────────

  static ChittiSection? _sectionByLabel(String label, String variant) {
    final needle = _normalize(label);
    for (final s in chittiSectionsFor(variant)) {
      if (_normalize(s.label) == needle) return s;
    }
    return null;
  }

  /// Longest alias wins — "car wash" must beat "wash", and "bike taxi"
  /// must beat "bike".
  static ChittiSection? _bestSectionMatch(String q, String variant) {
    ChittiSection? best;
    var bestLen = 0;
    for (final s in chittiSectionsFor(variant)) {
      for (final alias in [s.label, ...s.aliases]) {
        final a = _normalize(alias);
        if (a.length < 3 || !q.contains(a)) continue;
        if (a.length > bestLen) {
          bestLen = a.length;
          best = s;
        }
      }
    }
    return best;
  }

  static List<String> _chipsForSection(ChittiSection section) {
    // Screen-specific next steps where they are obvious, and a safe
    // generic pair everywhere else. Guessing an action that does not
    // apply to the screen is worse than offering nothing clever.
    switch (section.key) {
      case 'food':
      case 'grocery':
      case 'dmart':
        return const <String>['Order the same as last time', 'My orders'];
      case 'wallet':
      case 'rewards':
      case 'earn':
        return const <String>['My wallet balance', 'My coins'];
      case 'my_orders':
      case 'ride_history':
        return const <String>['Where is my order?', 'Cancel my order'];
      case 'safety':
      case 'sos_kyc':
        return const <String>['Is my SOS ready?', 'Open SOS KYC'];
      default:
        return const <String>['What can you do?', 'Take me somewhere else'];
    }
  }

  /// [answer], but allowed to look at the screen first.
  ///
  /// The screen reader knows things no registry can: which fields are
  /// still blank, and what this particular page can actually do right
  /// now. That is what turns "Food Genie lets you order food" into
  /// "your delivery address is still empty — where am I sending it?".
  ///
  /// Falls back to the registry answer whenever the screen has nothing
  /// useful to add, so it is never worse than [answer].
  static Future<ChittiLocalAnswer?> answerWithScreen(
    String question, {
    String? variant,
    String languageCode = 'en',
  }) async {
    // TALK first. These phrases are short and would otherwise be
    // mis-read by the layers below — "cancel this booking" contains
    // "cancel" and would fire the real cancel_order tool on an order
    // that has not been placed yet.
    final talk = ChittiChatIntents.handle(
      question,
      languageCode: languageCode,
      variant: variant,
    );
    if (talk != null) return talk;

    // A published clip, when one genuinely matches. Loaded once per
    // app run and matched strictly — see ChittiVideoService for why
    // restraint is the point.
    await ChittiVideoService.ensureLoaded();
    final video = ChittiVideoService.findFor(question);

    // MARKET questions (a price, or what to buy) are neither a section
    // lookup nor a screen question, and they are the one kind Chitti
    // genuinely cannot answer from its own registries. Handled here so
    // the reply is still a real answer plus an enquiry, rather than
    // "I could not reach the full AI".
    if (ChittiMarketAnswerService.handles(question)) {
      final market = await ChittiMarketAnswerService.answer(question);
      final outcome = await ChittiEnquiryService.submit(
        question: question,
        kind: market.model.isEmpty
            ? ChittiEnquiryKind.general
            : ChittiEnquiryKind.displayRepair,
        model: market.model,
        marketReference: market.marketReference,
      );
      return ChittiLocalAnswer(
        _renderMarketAnswer(market, outcome: outcome),
        suggestions: const <String>[
          'Book a repair',
          'Show me mobiles',
          'Ask something else',
        ],
      );
    }

    final q = _normalize(question);
    if (_thisScreenAsk.hasMatch(q) || _capabilityAsk.hasMatch(q)) {
      final advised = await ChittiScreenAdvisor.adviseOnCurrentScreen(
        variant: variant,
      );
      if (advised != null) return _withVideo(advised, video);
    }
    final plain = answer(question, variant: variant, languageCode: languageCode);
    return plain == null ? null : _withVideo(plain, video);
  }

  /// Lays the three tiers out as boxes.
  ///
  /// Drawn with box characters rather than a custom widget on purpose:
  /// the chat bubble already renders text in the app's own font and
  /// colours, so this inherits the styling automatically and switches
  /// with the theme. A bespoke widget would have needed its own copy of
  /// the palette, which is exactly the kind of thing that drifts.
  static String _renderMarketAnswer(
    ChittiMarketAnswer market, {
    required ChittiEnquiryOutcome outcome,
  }) {
    final buffer = StringBuffer()..writeln(market.headline)..writeln();

    for (final tier in market.tiers) {
      buffer
        ..writeln('┌─ ${tier.name}  ·  ${tier.price}')
        ..writeln('└─ ${tier.blurb}')
        ..writeln();
    }

    if (market.sources.isNotEmpty) {
      // Provenance, so the figure never reads as an NJ Tech quote.
      buffer.writeln('Market reference from ${market.sources.join(", ")}.');
    }

    buffer.write(
      switch (outcome) {
        ChittiEnquiryOutcome.sent =>
          'I have sent your question to NJ Tech — they will confirm the '
              'exact rate and the best offer for you shortly.',
        ChittiEnquiryOutcome.needsSignIn =>
          'Sign in and I will send this to NJ Tech for the exact rate and '
              'the best offer.',
        // Never "sign in" here: they already are, and saying otherwise
        // reads as broken while hiding the real cause.
        ChittiEnquiryOutcome.failed =>
          "I couldn't send that to NJ Tech just now. Try again in a moment, "
              'or call the shop directly for the exact rate.',
      },
    );
    return buffer.toString().trim();
  }

  /// Attaches [video] to [answer] without disturbing anything else it
  /// carries. A no-op when there is no good match, which is the common
  /// case by design.
  static ChittiLocalAnswer _withVideo(
    ChittiLocalAnswer answer,
    ChittiVideo? video,
  ) {
    if (video == null) return answer;
    return ChittiLocalAnswer(
      answer.text,
      suggestions: answer.suggestions,
      videoId: video.videoId,
    );
  }

  static String _normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s஀-௿ऀ-ॿഀ-ൿ]'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
