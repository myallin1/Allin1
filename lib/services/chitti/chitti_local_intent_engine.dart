// ================================================================
// chitti_local_intent_engine.dart — Tier 1: resolve what the user
// wants ON DEVICE, before spending an API call.
// ================================================================
// WHY (Aug 28 2026 — Nizam asked whether an offline LLM could live
// inside the app, using the app's own knowledge).
//
// The honest answer was no, and the reason is worth writing down so
// nobody re-opens it every six months:
//   • the smallest usable LLM (Gemma 3 1B int4) is ~550MB against an
//     APK currently around 50-80MB;
//   • the customer app ships primarily as a PWA, and on-device
//     inference on web needs WebGPU, ~1GB of browser memory and
//     cross-origin isolation — a non-starter on mobile data in Erode;
//   • a 1B model produces exactly the stiff, bookish Tamil the system
//     prompt already had to be rewritten to avoid;
//   • and it would have to pick correctly from ~27 tools, which small
//     models do badly.
//
// But an LLM is a tool for OPEN-ENDED language, and Chitti's job is
// not open-ended. It is a CLOSED set: 27 tools and 56 sections. A
// closed intent set is a matching problem, not a generation problem —
// and matching is something a phone can do in under a millisecond,
// offline, for free.
//
// So this is not a small language model. It is a scored intent
// matcher over the same registries the cloud path uses, and it exists
// to answer the question Nizam actually cared about: "api key limit
// theenthurum". Every request this resolves is a request that never
// reaches Groq.
//
// WHAT IT DELIBERATELY DOES NOT HANDLE
// Anything needing a free-text SLOT pulled out of a sentence —
// create_service_request ("2 plate biryani from Sagar Mess"),
// report_app_bug (needs a written summary),
// seller_set_item_availability (needs a menu item matched by name).
// Those go to the model, which is genuinely better at them. Guessing
// a slot wrong here would place a wrong order; falling through to the
// model costs a few hundred milliseconds. That trade is not close.
//
// CONFIDENCE, NOT CLEVERNESS
// The engine returns a score with every match, and the caller only
// acts on it above [confidenceThreshold]. Below that it stays quiet
// and the cloud path runs exactly as before. A miss here must cost
// latency, never correctness — an unrecognised sentence still gets a
// good answer, just a slower one.
import 'package:flutter/foundation.dart';

import '../../config/app_variant.dart';
import '../chitti_memory_service.dart';
import '../voice_booking_intent_service.dart';
import 'chitti_section_registry.dart';
import 'chitti_tool_registry.dart';

/// A locally-resolved tool call.
@immutable
class ChittiLocalIntent {
  const ChittiLocalIntent({
    required this.args,
    required this.confidence,
    required this.matched,
  });

  /// Same shape `GuruApiService.extractAgentAction` returns, so the
  /// executors need no special case: `{'action': ..., ...slots}`.
  final Map<String, dynamic> args;

  /// 0..1. Above [ChittiLocalIntentEngine.confidenceThreshold] the
  /// caller may execute without asking the model.
  final double confidence;

  /// The phrase that won, for debugging and for the analytics event —
  /// without this, tuning the tables is guesswork.
  final String matched;

  String? get action => args['action'] as String?;
}

/// One alias group: the phrases that mean a particular action.
@immutable
class _IntentRule {
  const _IntentRule({
    required this.action,
    required this.variants,
    required this.phrases,
    this.slots = const <String, dynamic>{},
    this.requiresCommandTone = false,
  });

  final String action;
  final Set<String> variants;

  /// Trigger phrases. English, Tanglish (Tamil typed in Latin — how
  /// most people actually type here) and Tamil script, because
  /// speech_to_text with a ta-IN locale returns Tamil script while the
  /// same person typing returns Tanglish.
  final List<String> phrases;

  /// Fixed arguments this rule implies (e.g. `online: true`).
  final Map<String, dynamic> slots;

  /// When true, a question-shaped sentence will NOT trigger this rule.
  ///
  /// This matters in one direction only. "Is auto available right now?"
  /// must not silently book an auto. But "என் balance என்ன?" is a
  /// question AND is exactly how someone asks for their balance — so
  /// reads must NOT carry this flag. Getting that backwards would make
  /// the reads unreachable, which is the failure mode this whole
  /// change exists to remove.
  final bool requiresCommandTone;
}

class ChittiLocalIntentEngine {
  ChittiLocalIntentEngine._();

  /// Act locally at or above this score; otherwise fall through to the
  /// model. Tuned deliberately high — a wrong local action is far more
  /// annoying than a slightly slower correct one.
  static const double confidenceThreshold = 0.62;

  static final VoiceBookingIntentService _voiceIntent =
      VoiceBookingIntentService();

  /// Question markers across the four languages the app supports.
  /// Kept broader than VoiceBookingIntentService's own list because
  /// this engine covers far more than booking.
  static final RegExp _questionMarkers = RegExp(
    r'\?|\b(what|which|how|why|when|where|can i|is there|are there|do you|'
    'yenna|enna|epdi|eppadi|yeppadi|yen|yeppo|enga|engaya|evlo|evvalavu|'
    r'irukka|irukkuma|mudiyuma|kudukka)\b|'
    r'\b(is|are|does|will|should|could|can)\b.{0,30}\b'
    r'(available|open|working|possible|allowed|free|ready|later)\b|'
    '(என்ன|எப்படி|ஏன்|எங்க|எவ்வளவு|முடியுமா|இருக்கா)',
    caseSensitive: false,
  );

  // ── verb/intent phrases ──────────────────────────────────────────
  //
  // Sections (the NOUNS — "grocery", "wallet", "rewards") live in
  // chitti_section_registry.dart's `aliases`. This table holds the
  // VERBS and the tool-level phrasings. Keeping the split that way
  // means adding a section does not mean editing this file too.
  static const List<_IntentRule> _rules = <_IntentRule>[
    // ── how people ACTUALLY ask (Aug 28 2026) ─────────────────────
    //
    // Every rule below this point was command syntax: a verb and an
    // object. Real customers state a NEED or a FEELING and expect the
    // assistant to work out the rest — "enaku pasikuthu", "veetuku
    // poganum", "phone odanjiduchu". None of those name a service, so
    // none of them matched anything at all.
    //
    // Deliberately multi-word and specific. A bare "pasi" would fire on
    // half the sentences in Tamil; "pasikuthu" is unambiguous, and that
    // specificity is what keeps false positives down as this grows.
    _IntentRule(
      action: 'navigate_to_section',
      variants: {'customer'},
      slots: {'section': 'food'},
      phrases: [
        'pasikuthu', 'pasikkuthu', 'pasikithu', 'i am hungry', 'im hungry',
        'sapida venum', 'sapdanum', 'saapdanum', 'food venum',
        'something to eat',
        'பசிக்குது', 'பசிக்கிறது', 'சாப்பிடணும்', 'சாப்பாடு வேணும்',
      ],
    ),
    _IntentRule(
      action: 'navigate_to_section',
      variants: {'customer'},
      slots: {'section': 'grocery'},
      phrases: [
        'veetuku saman', 'veettuku saman', 'grocery venum', 'maligai saman',
        'provisions venum', 'saman theenthiduchu',
        'மளிகை', 'சாமான் வேணும்',
      ],
    ),
    _IntentRule(
      action: 'navigate_to_section',
      variants: {'customer'},
      slots: {'section': 'electronics'},
      phrases: [
        'phone odanjiduchu', 'phone udanjiduchu', 'mobile odanjiduchu',
        'screen odanjiduchu', 'my phone is broken', 'phone not working',
        'laptop repair venum', 'ac work agala', 'fridge work agala',
        'போன் ஒடஞ்சிடுச்சு', 'போன் வேலை செய்யல', 'ரிப்பேர் பண்ணனும்',
      ],
    ),
    _IntentRule(
      action: 'navigate_to_section',
      variants: {'customer'},
      slots: {'section': 'game_zone'},
      phrases: [
        'bore adikuthu', 'boradikuthu', 'i am bored', 'im bored',
        'விளையாடணும்', 'போர் அடிக்குது',
      ],
    ),
    _IntentRule(
      action: 'navigate_to_section',
      variants: {'customer'},
      slots: {'section': 'offers'},
      phrases: [
        'ethachum offer', 'offer irukka', 'any discount', 'ethavathu offer',
        'ஏதாவது ஆஃபர்', 'தள்ளுபடி இருக்கா',
      ],
    ),
    _IntentRule(
      action: 'check_wallet_balance',
      variants: {'customer'},
      phrases: [
        'panam iruka', 'panam irukka', 'kasu irukka', 'kaasu irukka',
        'do i have money', 'காசு இருக்கா', 'பணம் இருக்கா',
      ],
    ),
    _IntentRule(
      action: 'book_transport',
      variants: {'customer'},
      slots: {'service': 'bike'},
      phrases: [
        'veetuku poganum', 'veettuku poganum', 'veetuku pogonum',
        'drop me home', 'take me home',
        'வீட்டுக்கு போகணும்', 'வீட்டுக்கு போணும்',
      ],
      requiresCommandTone: true,
    ),
    _IntentRule(
      action: 'check_order_status',
      variants: {'customer'},
      phrases: [
        'innum varala', 'inum varala', 'still not come', 'late aaguthu',
        'eppo varum', 'இன்னும் வரல', 'எப்போ வரும்',
      ],
    ),

    // ── customer reads ────────────────────────────────────────────
    _IntentRule(
      action: 'check_wallet_balance',
      variants: {'customer'},
      phrases: [
        'wallet balance', 'my balance', 'how much balance', 'how much money',
        'balance check', 'wallet la evlo', 'evlo panam', 'panam evlo',
        'balance evlo', 'என் பணம்', 'பணம் எவ்வளவு', 'வாலட்', 'பேலன்ஸ்',
      ],
    ),
    _IntentRule(
      action: 'check_rewards_balance',
      variants: {'customer'},
      phrases: [
        'my coins', 'how many coins', 'my points', 'reward points',
        'nj coins', 'cashback balance', 'coins evlo', 'point evlo',
        'காயின்', 'பாயின்ட்', 'ரிவார்ட்',
      ],
    ),
    _IntentRule(
      action: 'check_order_status',
      variants: {'customer'},
      phrases: [
        'where is my hero', 'where is my order', 'where is my ride',
        'track my order', 'track my ride', 'order status', 'my ride status',
        'is my ride here', 'hero enga', 'order enga', 'vandhutaanga',
        'vanthutangala', 'order status enna', 'எங்க இருக்கு', 'ஆர்டர் எங்க',
        'ஹீரோ எங்க',
      ],
    ),
    _IntentRule(
      action: 'list_recent_orders',
      variants: {'customer'},
      phrases: [
        'past orders', 'my old orders', 'previous orders', 'order history',
        'what did i order', 'how much did i spend', 'munnadi order',
        'pazhaya order', 'பழைய ஆர்டர்', 'முன்னாடி ஆர்டர்',
      ],
    ),
    _IntentRule(
      action: 'check_notifications',
      variants: {'customer'},
      phrases: [
        'my notifications', 'any notification', 'anything new', 'new messages',
        'unread', 'notification irukka', 'ஏதாவது புதுசா', 'நோட்டிபிகேஷன்',
      ],
    ),
    _IntentRule(
      action: 'check_profile_summary',
      variants: {'customer'},
      phrases: [
        'my profile', 'my details', 'my address', 'my phone number',
        'my account details', 'kyc status', 'sos verified', 'en address',
        'என் முகவரி', 'என் விவரம்',
      ],
    ),

    // ── customer actions ──────────────────────────────────────────
    _IntentRule(
      action: 'repeat_last_order',
      variants: {'customer'},
      phrases: [
        'same as last time', 'order it again', 'repeat my order',
        'my usual', 'book my usual', 'same order', 'marupadiyum same',
        'antha maari', 'pazhaya maari', 'அதே மாதிரி', 'மறுபடியும்',
      ],
      requiresCommandTone: true,
    ),
    _IntentRule(
      action: 'cancel_order',
      variants: {'customer'},
      phrases: [
        'cancel my order', 'cancel the order', 'cancel my booking',
        'cancel it', 'i dont want it', 'stop the order', 'order cancel',
        'cancel pannu', 'vendaam', 'venaam', 'வேண்டாம்', 'கேன்சல்',
      ],
      requiresCommandTone: true,
    ),
    _IntentRule(
      action: 'share_referral',
      variants: {'customer'},
      phrases: [
        'invite friend', 'invite my friend', 'refer a friend', 'share the app',
        'referral code', 'my referral', 'friend ku share', 'ரெஃபர்',
        'நண்பருக்கு',
      ],
    ),
    _IntentRule(
      action: 'check_and_update_app',
      variants: {'customer', 'hero', 'seller', 'admin'},
      phrases: [
        'update the app', 'check for update', 'is there a new version',
        'new version', 'app update', 'update pannu', 'ஆப் அப்டேட்',
        'அப்டேட் பண்ணு',
      ],
    ),

    // ── language ──────────────────────────────────────────────────
    _IntentRule(
      action: 'set_app_language',
      variants: {'customer', 'hero', 'seller'},
      slots: {'language': 'ta'},
      phrases: [
        'speak in tamil', 'change to tamil', 'tamil la pesu', 'tamil please',
        'தமிழ்ல பேசு', 'தமிழில் பேசு',
      ],
    ),
    _IntentRule(
      action: 'set_app_language',
      variants: {'customer', 'hero', 'seller'},
      slots: {'language': 'en'},
      phrases: [
        'speak in english', 'change to english', 'english la pesu',
        'english please', 'ஆங்கிலத்தில் பேசு',
      ],
    ),
    _IntentRule(
      action: 'set_app_language',
      variants: {'customer', 'hero', 'seller'},
      slots: {'language': 'hi'},
      phrases: ['speak in hindi', 'change to hindi', 'hindi please'],
    ),
    _IntentRule(
      action: 'set_app_language',
      variants: {'customer', 'hero', 'seller'},
      slots: {'language': 'ml'},
      phrases: ['speak in malayalam', 'change to malayalam', 'malayalam please'],
    ),

    // ── hero ──────────────────────────────────────────────────────
    _IntentRule(
      action: 'hero_set_online_status',
      variants: {'hero'},
      slots: {'online': true},
      phrases: [
        'go online', 'take me online', 'start work', 'start duty',
        'i am starting', 'online pannu', 'duty start', 'velai start',
        'ஆன்லைன் பண்ணு', 'வேலை ஆரம்பம்',
      ],
      requiresCommandTone: true,
    ),
    _IntentRule(
      action: 'hero_set_online_status',
      variants: {'hero'},
      slots: {'online': false},
      phrases: [
        'go offline', 'take me offline', 'stop work', 'i am going home',
        'take a break', 'offline pannu', 'veetuku poren', 'duty over',
        'ஆஃப்லைன் பண்ணு', 'வீட்டுக்கு போறேன்',
      ],
      requiresCommandTone: true,
    ),
    _IntentRule(
      action: 'hero_today_earnings',
      variants: {'hero'},
      phrases: [
        'how much did i earn', 'my earnings', 'today earning', 'today income',
        'evlo sambadichen', 'inniku evlo', 'sambalam evlo',
        'இன்னைக்கு எவ்வளவு', 'சம்பாத்தியம்',
      ],
    ),
    _IntentRule(
      action: 'hero_active_job_status',
      variants: {'hero'},
      phrases: [
        'my current job', 'active job', 'current ride', 'which pickup',
        'ippo enna job', 'இப்போ என்ன வேலை', 'நடக்குற ரைடு',
      ],
    ),
    _IntentRule(
      action: 'hero_wallet_balance',
      variants: {'hero'},
      phrases: [
        'my wallet', 'wallet balance', 'how much balance', 'recharge balance',
        'wallet la evlo', 'என் வாலட்',
      ],
    ),

    _IntentRule(
      action: 'hero_pending_work',
      variants: {'hero'},
      phrases: [
        'how many jobs are still open', 'still open', 'pending work',
        'what is left', 'jobs left', 'bakki vela', 'enna vela bakki',
        'mudikala', 'பாக்கி வேலை', 'என்ன வேலை பாக்கி',
      ],
    ),

    // ── seller ────────────────────────────────────────────────────
    _IntentRule(
      action: 'seller_pending_orders',
      variants: {'seller'},
      phrases: [
        'pending orders', 'new orders', 'what orders', 'waiting orders',
        'order irukka', 'ethana order', 'எத்தனை ஆர்டர்', 'புது ஆர்டர்',
      ],
    ),
    _IntentRule(
      action: 'seller_today_earnings',
      variants: {'seller'},
      phrases: [
        'today sales', 'today earning', 'how much sales', 'today revenue',
        'inniku vyabaram', 'இன்னைக்கு வியாபாரம்', 'இன்னைக்கு சேல்ஸ்',
      ],
    ),
    _IntentRule(
      action: 'seller_set_shop_open',
      variants: {'seller'},
      slots: {'open': false},
      phrases: [
        'close the shop', 'shop close', 'closing now', 'stop orders',
        'kadai moodu', 'கடை மூடு', 'கடையை மூடு',
      ],
      requiresCommandTone: true,
    ),
    _IntentRule(
      action: 'seller_set_shop_open',
      variants: {'seller'},
      slots: {'open': true},
      phrases: [
        'open the shop', 'shop open', 'start taking orders', 'reopen',
        'kadai thora', 'கடை திற', 'கடையை திற',
      ],
      requiresCommandTone: true,
    ),
    _IntentRule(
      action: 'seller_shop_status',
      variants: {'seller'},
      phrases: [
        'is my shop open', 'shop open ah', 'shop status', 'is the shop closed',
        'am i open', 'kadai open ah', 'கடை ஓபனா', 'கடை நிலை',
      ],
    ),

    // ── admin ─────────────────────────────────────────────────────
    //
    // NEW (Aug 28 2026 — Nizam: "admin, seller, hero app la iruka
    // chittikum intha customer app mari power kudu").
    //
    // Declaring the tools in the registry was not enough on its own:
    // the registry is what the MODEL sees, and the admin build is the
    // one most likely to be opened with no API key configured. Without
    // rules here, an owner offline would still get nothing — which is
    // the same silence the rework existed to remove.
    _IntentRule(
      action: 'admin_pending_approvals',
      variants: {'admin'},
      phrases: [
        'how many are waiting for approval', 'pending approval',
        'waiting for approval', 'approval queue', 'who is waiting',
        'new heroes', 'new sellers', 'approve panna', 'எத்தனை அப்ரூவல்',
        'அப்ரூவல் வெயிட்டிங்',
      ],
    ),
    _IntentRule(
      action: 'admin_today_activity',
      variants: {'admin'},
      phrases: [
        'how many orders today', 'orders today', 'today business',
        'today activity', 'how is today', 'inniku evlo order',
        'இன்னைக்கு எத்தனை ஆர்டர்', 'இன்னைக்கு வியாபாரம்',
      ],
    ),
    _IntentRule(
      action: 'admin_open_bugs',
      variants: {'admin'},
      phrases: [
        'any open bug reports', 'open bugs', 'bug reports', 'any bugs',
        'unresolved bugs', 'crash reports', 'bug irukka', 'பக் ரிப்போர்ட்',
      ],
    ),
    _IntentRule(
      action: 'admin_open_enquiries',
      variants: {'admin', 'seller'},
      phrases: [
        'any customer enquiries waiting', 'open enquiries', 'enquiries',
        'customer enquiry', 'price questions', 'waiting for a price',
        'rate kekuranga', 'என்குயரி', 'ரேட் கேட்குறாங்க',
      ],
    ),
    // ── screen guidance (Aug 28 2026) ─────────────────────────────
    //
    // Every variant, and deliberately the most offline-capable rule
    // here: the answer comes from the section registry, so "what is
    // this page" works with no key and no signal — which is exactly
    // when someone is most likely to be lost.
    _IntentRule(
      action: 'explain_this_screen',
      variants: {'customer', 'hero', 'seller', 'admin'},
      phrases: [
        'what can i do on this screen', 'what can i do here',
        'what is this screen', 'what is this page', 'explain this screen',
        'explain this page', 'guide me', 'help me here', 'how does this work',
        'idhu enna', 'inga enna pannalam', 'enna pannalam', 'eppadi pannanum',
        'இது என்ன', 'இங்க என்ன பண்ணலாம்', 'என்ன பண்ணலாம்', 'எப்படி பண்ணனும்',
      ],
    ),
  ];

  /// Resolves [utterance] locally, or returns null to defer to the
  /// cloud model.
  ///
  /// [fromVoice] relaxes the question guard: someone who tapped the mic
  /// and said "auto" is giving a command, even though the utterance is
  /// a bare noun. Typed text gets the stricter treatment, because a
  /// typed sentence is far more often a genuine question.
  static ChittiLocalIntent? resolve(
    String utterance, {
    String? variant,
    bool fromVoice = false,
  }) {
    final v = variant ?? currentAppVariant;
    final text = _normalize(utterance);
    if (text.isEmpty) return null;

    // Checked against the RAW input as well as the normalised form.
    // FIX (caught by the engine's own tests): checking only the
    // normalised text meant "is auto available right now?" sailed
    // past this guard and booked an auto — _normalize() strips
    // punctuation, so the "?" that made it a question was gone
    // before the guard could see it.
    final rawLower = utterance.toLowerCase();
    final isQuestion = !fromVoice &&
        (_questionMarkers.hasMatch(rawLower) ||
            _questionMarkers.hasMatch(text));

    ChittiLocalIntent? best;

    // 1. Verb/tool rules.
    for (final rule in _rules) {
      if (!rule.variants.contains(v)) continue;
      if (!ChittiToolRegistry.isAllowedFor(rule.action, v)) continue;
      if (rule.requiresCommandTone && isQuestion) continue;

      for (final phrase in rule.phrases) {
        final normalized = _normalize(phrase);
        if (normalized.isEmpty || !text.contains(normalized)) continue;
        final score = _score(normalized, text);
        if (best == null || score > best.confidence) {
          best = ChittiLocalIntent(
            args: <String, dynamic>{'action': rule.action, ...rule.slots},
            confidence: score,
            matched: phrase,
          );
        }
      }
    }

    // 2. Transport, via the parser that already exists and is already
    //    trusted in production — no second copy of those 25 patterns.
    if (!isQuestion && ChittiToolRegistry.isAllowedFor('book_transport', v)) {
      final intent = _voiceIntent.parse(utterance);
      if (intent != null) {
        // Slightly under a strong verb match: a bare service word
        // ("auto") appearing inside a sentence about something else is
        // a real false-positive risk, which is why the app already
        // guards this path with looksLikeQuestion().
        const score = 0.72;
        if (best == null || score > best.confidence) {
          best = ChittiLocalIntent(
            args: <String, dynamic>{
              'action': 'book_transport',
              'service': intent.categoryKey,
              if (intent.destinationQuery != null)
                'destination': intent.destinationQuery,
            },
            confidence: score,
            matched: intent.categoryKey,
          );
        }
      }
    }

    // 3. Sections, from the registry's own aliases — this is what
    //    makes "show me my orders" or "ரிவார்ட் காட்டு" work without a
    //    second noun table living here.
    if (ChittiToolRegistry.isAllowedFor('navigate_to_section', v)) {
      for (final section in chittiSectionsFor(v)) {
        for (final alias in section.aliases) {
          final normalized = _normalize(alias);
          if (normalized.isEmpty || !text.contains(normalized)) continue;
          var score = _score(normalized, text);
          // An explicit "open/show/kaattu" makes this unambiguous;
          // a bare noun on its own is weaker evidence.
          if (_navigationVerb.hasMatch(text)) {
            score = (score + 0.2).clamp(0.0, 1.0);
          } else {
            score *= 0.8;
          }
          if (best == null || score > best.confidence) {
            best = ChittiLocalIntent(
              args: <String, dynamic>{
                'action': 'navigate_to_section',
                'section': section.key,
              },
              confidence: score,
              matched: alias,
            );
          }
        }
      }
    }

    // SCREEN CONTEXT (Aug 28 2026 — Nizam: Chitti should follow the
    // customer to whatever screen they are on and finish the job from
    // there).
    //
    // "book it", "order this", "do it" name nothing at all, so nothing
    // above can match them. But a customer standing on Food Genie who
    // says "order this" is not being vague — they are being normal, and
    // the screen is the missing half of the sentence.
    //
    // Only consulted when nothing else matched, and only for a SHORT
    // deictic phrase. A long message that happens to contain "it" is a
    // real sentence for the model, not a pointer at the screen.
    if (best == null && !isQuestion) {
      final onScreen = _fromCurrentScreen(text, v);
      if (onScreen != null) return onScreen;
    }

    if (best == null) return null;
    if (best.confidence < confidenceThreshold) {
      debugPrint(
        '[ChittiLocalIntent] "${best.matched}" scored '
        '${best.confidence.toStringAsFixed(2)} — deferring to the model.',
      );
      return null;
    }
    return best;
  }

  /// Picks the best of several candidate transcriptions.
  ///
  /// NEW (Aug 28 2026 — Tanglish voice accuracy).
  ///
  /// `speech_to_text` does not return one transcript, it returns a
  /// ranked list of candidates (`SpeechRecognitionResult.alternates`).
  /// Until now the app took `recognizedWords` — the top-ranked one —
  /// and threw the rest away. That is a real loss, because the
  /// recogniser ranks by acoustic likelihood, and it has no idea this
  /// is a super app where "wallet balance evlo" is a far more probable
  /// sentence than whatever else sounded similar.
  ///
  /// We DO know that. So instead of arguing with the recogniser about
  /// which candidate is right, we test each one against the intent
  /// tables and take the first that resolves confidently. The
  /// recogniser supplies the possibilities; the app supplies the
  /// context. This costs nothing, needs no API, and is only possible
  /// because Tier 1 exists — without a matcher there is no way to
  /// judge one candidate against another.
  ///
  /// [candidates] should be in the recogniser's own confidence order,
  /// best first, so ties resolve the way it intended.
  static ChittiLocalIntent? resolveBest(
    List<String> candidates, {
    String? variant,
    bool fromVoice = false,
  }) {
    ChittiLocalIntent? best;
    for (final candidate in candidates) {
      final intent = resolve(candidate, variant: variant, fromVoice: fromVoice);
      if (intent == null) continue;
      if (best == null || intent.confidence > best.confidence) {
        best = intent;
        // A near-perfect match will not be beaten by a lower-ranked
        // candidate, and every extra candidate is wasted work.
        if (intent.confidence >= 0.95) break;
      }
    }
    return best;
  }

  /// "book it" / "order this" — the object is the screen they are on.
  static final RegExp _deictic = RegExp(
    r'\b(book|order|do|get|send|start|place)\b.{0,12}'
    r'\b(it|this|that|here)\b|'
    r'\b(this one|same|idhu|ithu|inga)\b|'
    '(இதை|இது|இங்க)',
    caseSensitive: false,
  );

  static ChittiLocalIntent? _fromCurrentScreen(String text, String variant) {
    // Four words is the ceiling on purpose: "book it" and "order this"
    // pass, "can you tell me whether it is possible to order this from
    // another shop" does not.
    if (text.split(' ').length > 4) return null;
    if (!_deictic.hasMatch(text)) return null;

    final screen = ChittiMemoryService.instance.currentScreen;
    if (screen == null || screen.isEmpty) return null;

    ChittiSection? section;
    for (final s in chittiSectionsFor(variant)) {
      if (s.label.toLowerCase() == screen.toLowerCase()) {
        section = s;
        break;
      }
    }
    if (section == null) return null;

    // Navigating to the screen they are already on would be absurd, so
    // this only fires for a screen Chitti was NOT the one to open —
    // and even then it re-opens it, which for a booking screen is the
    // action ("start the booking"), not a no-op.
    return ChittiLocalIntent(
      args: <String, dynamic>{
        'action': 'navigate_to_section',
        'section': section.key,
      },
      // Deliberately just over the bar: the screen is strong evidence,
      // but it is still an inference about an ambiguous sentence.
      confidence: 0.7,
      matched: 'screen:${section.key}',
    );
  }

  static final RegExp _navigationVerb = RegExp(
    r'\b(open|show|go to|take me|goto|kaattu|kaatu|kaamikka|po|paaru)\b|'
    '(காட்டு|திற|போ)',
    caseSensitive: false,
  );

  /// How strongly [phrase] explains [text].
  ///
  /// Two signals, both cheap:
  ///   • how much of the sentence the phrase actually accounts for —
  ///     "cancel my order" matching a 3-word message is far stronger
  ///     evidence than the same phrase inside a 30-word paragraph;
  ///   • how specific the phrase is — a multi-word phrase matching is
  ///     much harder to hit by accident than a single common word.
  static double _score(String phrase, String text) {
    final coverage = phrase.length / text.length;
    final words = phrase.split(' ').where((w) => w.isNotEmpty).length;
    final specificity = switch (words) {
      >= 3 => 0.92,
      2 => 0.8,
      _ => phrase.length >= 6 ? 0.68 : 0.55,
    };
    // Coverage tops out quickly — past about half the sentence, more
    // coverage does not make the match meaningfully more certain.
    final coverageBoost = (coverage * 0.4).clamp(0.0, 0.2);
    return (specificity + coverageBoost).clamp(0.0, 1.0);
  }

  /// Lowercase, strip punctuation, collapse whitespace. Tamil script is
  /// left untouched — only Latin case-folds, and stripping non-Latin
  /// characters here would delete the Tamil aliases entirely.
  // Filler and VOCATIVES.
  //
  // NEW (Aug 28 2026 — Nizam: "command sollama Chitti kita dude nu
  // pesunalum avan antha velaya seiyanum").
  //
  // People do not talk to Chitti in command syntax. They say "dude
  // cancel pannu", "machan oru auto venum", "boss balance evlo da".
  // Every one of those failed to match a rule, because the rule is
  // "cancel pannu" and the sentence starts with a name.
  //
  // Stripping the way people address each other is the cheapest fix by
  // a wide margin: it turns a whole category of natural speech into
  // phrasing the tables already know, with no new aliases at all.
  // Removed anywhere in the sentence, not just at the front, because
  // Tamil puts them at the end just as often ("cancel pannu da").
  static final RegExp _fillerWords = RegExp(
    r'\b(a|an|the|please|pls|kindly|just|simply|actually|'
    'dude|bro|brother|boss|machan|machi|machaa|thala|thalaiva|'
    r'anna|akka|sir|madam|guru|chitti|hey|hi|hello|ok|okay)\b',
    caseSensitive: false,
  );

  // Tamil vocatives, handled separately: they are written as separate
  // words but a Latin-oriented word boundary does not apply cleanly to
  // Tamil script, so these are matched directly.
  static final RegExp _tamilSofteners = RegExp(
    '(மச்சான்|மச்சி|தல|பாஸ்|அண்ணா|அக்கா|சிட்டி|ப்ளீஸ்)',
  );

  static String _normalize(String input) => input
      .toLowerCase()
      .replaceAll(RegExp(r'[^\w\s஀-௿ऀ-ॿഀ-ൿ]'), ' ')
      .replaceAll(_fillerWords, ' ')
      .replaceAll(_tamilSofteners, ' ')
      // Trailing particles ("cancel pannu da", "venum ya")
      // carry no meaning for matching and break phrase
      // boundaries if left in.
      .replaceAll(
        RegExp(r'\b(da|daa|na|naa|ya)\b', caseSensitive: false),
        ' ',
      )
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
