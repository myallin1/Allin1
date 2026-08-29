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
  static ChittiLocalAnswer? answer(String question, {String? variant}) {
    final v = variant ?? currentAppVariant;
    final q = _normalize(question);
    if (q.isEmpty) return null;

    // Order matters: the most specific interpretation first. "What can
    // I do here" is about the screen; "what can you do" is about
    // Chitti; a bare section name is a lookup. Checking the broad one
    // first would swallow the narrow ones.
    return _aboutCurrentScreen(q, v) ??
        _aboutChitti(q, v) ??
        _howDoI(q, v) ??
        _aboutSection(q, v);
  }

  // ── "what is this page?" ─────────────────────────────────────────

  static final RegExp _thisScreenAsk = RegExp(
    r'\b(this (page|screen|section)|here|current (page|screen))\b|'
    '(இந்த (பக்கம்|பேஜ்|ஸ்கிரீன்)|இங்க)',
  );

  static ChittiLocalAnswer? _aboutCurrentScreen(String q, String v) {
    if (!_thisScreenAsk.hasMatch(q)) return null;

    final screen = ChittiMemoryService.instance.currentScreen;
    if (screen == null || screen.isEmpty) {
      return const ChittiLocalAnswer(
        "I can't tell which page you're on right now. Tell me what you're "
        'trying to do and I will take you there.',
        suggestions: <String>['Order food', 'Book a ride', 'My orders'],
      );
    }

    // currentScreen is a LABEL (set by ChittiScreenObserver), so match
    // on label rather than key — the observer never sees keys.
    final section = _sectionByLabel(screen, v);
    if (section == null) {
      return ChittiLocalAnswer(
        "You're on $screen. Tell me what you want to do here and I'll "
        'handle it.',
        suggestions: const <String>['What can you do?', 'Go somewhere else'],
      );
    }

    return ChittiLocalAnswer(
      "You're on ${section.label}. ${section.description} "
      'Tell me what you need and I will do it from here.',
      suggestions: _chipsForSection(section),
    );
  }

  // ── "what can you do?" ───────────────────────────────────────────

  static final RegExp _capabilityAsk = RegExp(
    r'\b(what can you do|what do you do|what are you|who are you|'
    r'help me|what can i ask|your features|what all)\b|'
    '(என்ன பண்ணுவ|என்ன செய்வ|உன்னால என்ன|நீ யாரு)',
  );

  static ChittiLocalAnswer? _aboutChitti(String q, String v) {
    if (!_capabilityAsk.hasMatch(q)) return null;

    // Grouped by domain rather than listed flat: twenty-five tool names
    // in a row is not an answer, it is a data dump.
    final byDomain = <ChittiDomain, List<String>>{};
    for (final tool in kChittiTools) {
      if (!tool.variants.contains(v)) continue;
      byDomain.putIfAbsent(tool.domain, () => <String>[]).add(tool.name);
    }

    final lines = <String>[];
    void add(ChittiDomain d, String text) {
      if (byDomain.containsKey(d)) lines.add('• $text');
    }

    add(ChittiDomain.transport,
        'Book a bike, auto, cab, parcel, mini truck or lorry',);
    add(ChittiDomain.ordering,
        'Place food, grocery and Hero orders — and cancel or repeat them',);
    add(ChittiDomain.navigation,
        'Open any of the ${chittiSectionsFor(v).length} sections in the app',);
    add(ChittiDomain.account,
        'Check your wallet, coins, order status, past orders and profile',);
    add(ChittiDomain.hero,
        'Take you online or offline, and read your earnings and current job',);
    add(ChittiDomain.seller,
        'Show pending orders, open or close your shop, and read your sales',);
    add(ChittiDomain.support,
        'Report a problem, check for app updates, and read screenshots',);

    return ChittiLocalAnswer(
      "Quite a lot, boss:\n${lines.join('\n')}\n"
      'Most of it works even with no internet. Just tell me what you '
      'want — no need for exact words.',
      suggestions: const <String>[
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

  static ChittiLocalAnswer? _howDoI(String q, String v) {
    if (!_howWhereAsk.hasMatch(q)) return null;
    final section = _bestSectionMatch(q, v);
    if (section == null) return null;
    return ChittiLocalAnswer(
      '${section.description} It is under ${section.label} — say "open '
      '${section.label}" and I will take you straight there.',
      suggestions: <String>['Open ${section.label}', 'Something else'],
    );
  }

  // ── a bare section name ──────────────────────────────────────────

  static ChittiLocalAnswer? _aboutSection(String q, String v) {
    // Only for short messages. A section word buried in a long sentence
    // is far more likely to be part of a real question the model should
    // answer than a request for the section's description.
    if (q.split(' ').length > 4) return null;
    final section = _bestSectionMatch(q, v);
    if (section == null) return null;
    return ChittiLocalAnswer(
      '${section.label}: ${section.description}',
      suggestions: <String>['Open ${section.label}', 'What else can you do?'],
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
    final plain = answer(question, variant: variant);
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
