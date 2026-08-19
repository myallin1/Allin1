// ================================================================
// GuruChatScreen — "MyAllin1 Super Hero" — Allin1 Super App
// ================================================================
// OVERHAUL (per Nizam's explicit request): full context-aware, premium
// AI assistant rebuild.
// 1. UI/UX: dark, glowing gradient look (Gemini/Claude mobile-app style)
//    instead of the old light off-white theme — modern chat bubbles, a
//    dynamic glowing voice button, and a structured empty state showing
//    the app's services as capability chips.
// 2. Context Injection: system prompt (see guru_api_service.dart) now
//    fully describes every Allin1 service (Bike, Auto, Cab, Parcel, Mini
//    Truck, Lorry, SOS, Food Genie, NJ Tech repair, etc.) so the AI can
//    answer any customer query about the app.
// 3. Freemium model: Free tier = text chat, gated only on
//    AiActivationService.isAiActivated (an admin-provisioned key — see
//    _SuperHeroActivationScreen below). Pro tier = Voice-to-Order; tapping
//    the mic without AiActivationService.isProUnlocked shows a paywall
//    sheet instead of starting voice capture.
// 4. Activation/Onboarding: if the AI isn't activated yet for this
//    customer, the whole screen becomes a beautiful "Unlock your Super
//    Hero" screen instructing them to contact Admin Support, instead of
//    showing (or gating inline inside) the chat itself.
// 5. Voice Intent Parsing + Auto-Navigation (per Nizam's explicit
//    follow-up): a Pro customer's voice command is no longer just sent
//    to the AI as text. VoiceBookingIntentService parses it locally for
//    a service keyword (Bike/Auto/Cab/Parcel/Mini Truck/Lorry/SOS) and a
//    destination phrase, resolves the destination via the same
//    MapService search pipeline the booking screen's own address search
//    uses, then this screen pushes BikeBookingScreen directly with that
//    category + destination pre-filled (or SosScreen for SOS) — the
//    customer lands one tap from confirming, no manual re-typing. Only
//    utterances with no recognizable service keyword fall back to the
//    normal AI text reply.
import 'dart:async';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

// GUEST MODE (Aug 11 2026): requireRealAuth() guard on the submit action.
import '../services/auth_prompt_service.dart';
import '../services/ai_activation_service.dart';
import '../services/gemini_api_service.dart';
import '../services/grocery_ai_notes_service.dart';
import '../services/guru_api_service.dart';
import '../services/guru_suggestion_parser.dart';
import '../services/localization_service.dart';
import '../widgets/ai_loading_dialog.dart';
// NEW (CTO mandate — AI Autonomous App Updating): reuses the exact same
// web-only cache-clear-and-cache-busted-reload path dashboard_screen.dart's
// update button already calls, via the same stub/web conditional-import
// split, so there is only ever one real implementation of "apply the
// update" in the codebase.
import '../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../services/pwa_cache_platform_web.dart';
import '../services/voice_booking_intent_service.dart';
import '../services/web_version_checker.dart';
import '../widgets/server_busy_dialog.dart' show kCallCenterNumberIntl;
import 'bike_taxi/bike_booking_screen.dart';
import 'car_wash_screen.dart';
import 'food_hub_screen.dart';
import 'grocery_order_screen.dart';
import 'hero_booking_screen.dart';
import 'nj_tech_service_screen.dart';
import 'play_zone_screen.dart';
import 'printing_service_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';
import 'ride_history_screen.dart';
import 'settings_screen.dart';
import 'sos_screen.dart';
import '../services/theme_context_extensions.dart';
import '../services/auth_service.dart';
import '../services/service_request_service.dart';

// ---- FIX (CTO mandate — Batch 1 Theme Retrofit): this used to be a
// fixed "Dark, glowing Super Hero palette" of top-level const Colors —
// meaning this whole screen never once reacted to a theme change,
// regardless of what ThemeService/the app's MaterialApp said. Removed
// entirely; every build() method below that used one of these now
// declares its own local `final` bindings from context.colors right
// at the top (e.g. `final ink = context.colors.text;`), computed fresh
// on every rebuild — so a theme switch now genuinely repaints this
// screen. Mapping kept 1:1 with the old names' INTENT, not their old
// fixed hex value: _bg->background, _surface->surface,
// _surfaceElevated->elevatedSurface, _ink->text, _muted->mutedText,
// _border->border, _accentA(violet)->accentSecondary,
// _accentB(pink)->accent, _accentC(cyan)->accentTertiary,
// _userBubble->subtleFill. See theme_context_extensions.dart for what
// each of those actually resolves to per theme.

const List<_Capability> _capabilities = <_Capability>[
  _Capability('Bike', Icons.two_wheeler_rounded),
  _Capability('Auto', Icons.electric_rickshaw_rounded),
  _Capability('Cab', Icons.local_taxi_rounded),
  _Capability('Parcel', Icons.local_shipping_outlined),
  _Capability('Mini Truck', Icons.fire_truck_rounded),
  _Capability('Lorry', Icons.local_shipping_rounded),
  _Capability('SOS', Icons.sos_rounded),
];

const List<String> _suggestedPrompts = <String>[
  'Book a bike taxi in Erode',
  'Send a parcel across town',
  'Which service fits shifting furniture?',
  'How does the wallet work?',
];

class GuruChatScreen extends StatefulWidget {
  const GuruChatScreen({super.key});

  @override
  State<GuruChatScreen> createState() => _GuruChatScreenState();
}

class _GuruChatScreenState extends State<GuruChatScreen> {
  final GuruApiService _api = GuruApiService();
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final List<_GuruMessage> _messages = <_GuruMessage>[];
  final stt.SpeechToText _speech = stt.SpeechToText();
  final VoiceBookingIntentService _voiceIntent = VoiceBookingIntentService();
  // NEW (CTO mandate — Text-to-Speech): one shared FlutterTts instance
  // for this screen's lifetime, mirrored in GuruOverlayService for the
  // floating panel.
  final FlutterTts _tts = FlutterTts();
  bool _ttsReady = false;

  bool _isTyping = false;
  bool _isListening = false;
  bool _speechReady = false;
  // Guards against a stray extra speech_to_text onResult firing after
  // we've already actioned the finalResult once (dispatched an intent or
  // sent a fallback chat message) for this listening session.
  bool _voiceResultHandled = false;

  // NEW (CTO mandate — Text-to-Speech): auto-speak toggle, on by
  // default per the mandate ("it should automatically speak"); the
  // header speaker icon flips this.
  bool _autoSpeak = true;

  // NEW (CTO mandate — Co-work Style Confirmation): the tool-call
  // args Groq extracted but hasn't been executed yet, pending the
  // customer's explicit yes/no. Cleared once actioned or cancelled.
  Map<String, dynamic>? _pendingAgentAction;

  // NEW (Chitti AI upgrade, Task 2 — Vision): the screenshot the customer
  // has picked but not yet sent — shown as a small removable preview
  // chip above the input bar, cleared once _sendMessage() ships it.
  Uint8List? _pendingImageBytes;
  bool _pickingImage = false;

  @override
  void dispose() {
    _api.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    if (_isListening) {
      unawaited(_speech.stop());
    }
    unawaited(_tts.stop());
    super.dispose();
  }

  // NEW (CTO mandate — Deep Language Sync): maps the app's in-app
  // language selection to (a) a plain-English label to inject into the
  // Groq system prompt, and (b) a BCP-47 locale for flutter_tts'
  // setLanguage. Tanglish ('tg') is spoken content in Tamil, so it maps
  // to the Tamil locale/label same as 'ta' — there's no separate
  // "Tanglish" TTS voice on any platform.
  ({String label, String ttsLocale}) _languageInfo(BuildContext context) {
    final code = context.read<LocalizationService>().languageCode;
    switch (code) {
      case 'ta':
      case 'tg':
        return (label: 'Tamil', ttsLocale: 'ta-IN');
      case 'hi':
        return (label: 'Hindi', ttsLocale: 'hi-IN');
      case 'ml':
        return (label: 'Malayalam', ttsLocale: 'ml-IN');
      default:
        return (label: 'English', ttsLocale: 'en-IN');
    }
  }

  Future<void> _ensureTtsReady(String locale) async {
    try {
      await _tts.setLanguage(locale);
      await _tts.setSpeechRate(0.48);
      await _tts.setPitch(1.0);
      _ttsReady = true;
    } catch (e) {
      debugPrint('[GuruChatScreen] TTS setup failed: $e');
    }
  }

  Future<void> _speak(String text) async {
    if (!_autoSpeak || text.trim().isEmpty) return;
    try {
      final locale = _languageInfo(context).ttsLocale;
      await _ensureTtsReady(locale);
      if (!_ttsReady) return;
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[GuruChatScreen] TTS speak failed: $e');
    }
  }

  Future<void> _sendMessage([String? presetText]) async {
    final input = (presetText ?? _inputController.text).trim();
    final pendingImage = _pendingImageBytes;
    // NEW (Chitti AI upgrade, Task 2 — Vision): a message can now be
    // image-only (customer attaches a screenshot with no typed text) —
    // only block sending when BOTH are empty.
    if ((input.isEmpty && pendingImage == null) || _isTyping) return;

    setState(() {
      _messages.add(_GuruMessage(role: 'user', text: input, imageBytes: pendingImage));
      _isTyping = true;
      _inputController.clear();
      _pendingImageBytes = null;
    });
    _scrollToBottom();

    AiLoadingDialog.show(context);
    try {
      await _doSendMessage(input, pendingImage);
    } finally {
      if (mounted) {
        AiLoadingDialog.hide(context);
        if (_isTyping) setState(() => _isTyping = false);
      }
    }
  }

  Future<void> _doSendMessage(String input, Uint8List? pendingImage) async {

    // FIX (AI State Mismatch bug): pass the activated key straight from
    // AiActivationService (secure storage) instead of letting
    // GuruApiService re-resolve it from its own legacy/stale fallback.
    final apiKey = context.read<AiActivationService>().apiKey;
    final languageLabel = _languageInfo(context).label;

    // NEW (CTO mandate — Co-work Style Confirmation): if there's an
    // action awaiting the customer's yes/no, this message IS the
    // answer — never re-run agent-action extraction on it.
    if (_pendingAgentAction != null) {
      final decision = _voiceIntent.classifyYesNo(input);
      final pending = _pendingAgentAction!;
      if (decision == VoiceYesNo.yes) {
        _pendingAgentAction = null;
        unawaited(_logGuruAnalyticsEvent(
          eventType: 'intent_resolved',
          action: pending['action'] as String?,
          args: pending,
          resolved: true,
        ));
        await _executePendingAction(pending);
        if (mounted) setState(() => _isTyping = false);
        return;
      } else if (decision == VoiceYesNo.no) {
        _pendingAgentAction = null;
        unawaited(_logGuruAnalyticsEvent(
          eventType: 'intent_resolved',
          action: pending['action'] as String?,
          args: pending,
          resolved: false,
        ));
        if (!mounted) return;
        setState(() {
          _messages.add(const _GuruMessage(role: 'assistant', text: 'Okay, cancelled — let me know if you need anything else.'));
          _isTyping = false;
        });
        _scrollToBottom();
        return;
      }
      // Unclear -- drop the stale pending action and fall through to
      // treat this as a fresh message (the customer likely re-said
      // their request instead of answering yes/no).
      _pendingAgentAction = null;
    }

    // NEW (CTO mandate — Autonomous Agent, Option 3 w/ human-in-the-loop
    // safety net, + Dynamic PWA Guided Tour navigation tool): before
    // falling back to plain chat, ask Groq whether this text is a
    // clear booking request OR a "where/how do I do X" navigation
    // request. Skipped for image-attached messages (a screenshot is a
    // troubleshooting request, not either of these) and for the
    // voice-fallback '🎙 ...' text this same method also handles when
    // the local regex parser already found nothing — Groq gets one
    // honest shot per genuinely-new message.
    // NEW (CTO mandate — Multi-Agent Orchestration & Handoff
    // Architecture): an attached image no longer unconditionally skips
    // tool-calling. Groq still gets first look even with an image
    // attached — if the customer's text + the fact that an image is
    // attached clearly means "identify this product for my grocery
    // list", Groq calls analyze_screen_with_vision (see
    // GuruApiService.extractAgentAction's hasAttachedImage param) and
    // this handles it via the Gemini handoff below. If Groq calls
    // nothing (e.g. the text is an unrelated troubleshooting question),
    // this falls through exactly as before to the existing
    // screenshot-troubleshooting reply further down, image bytes intact.
    if (input.isNotEmpty) {
      final acted = await _tryAgentActionFromText(input, apiKey, imageBytes: pendingImage);
      if (acted) {
        if (mounted) setState(() => _isTyping = false);
        return;
      }
      if (!mounted) return;
    }

    final history = _messages
        .where((m) => m.role == 'user' || m.role == 'assistant')
        .map((m) => <String, String>{'role': m.role, 'content': m.text})
        .toList();

    final rawReply = await _api.sendMessage(
      message: input,
      history: history,
      apiKeyOverride: apiKey,
      imageBytes: pendingImage,
      languageLabel: languageLabel,
    );

    if (!mounted) return;

    // NEW (CTO mandate — Suggestion Chips): strip the [SUGGESTIONS: ...]
    // tag out of the displayed bubble and keep the options separately so
    // the UI can render them as tappable chips right below the message.
    final parsed = GuruSuggestionParser.parse(rawReply);

    setState(() {
      _messages.add(_GuruMessage(role: 'assistant', text: parsed.text, suggestions: parsed.suggestions));
      _isTyping = false;
    });
    _scrollToBottom();
    unawaited(_speak(parsed.text));
  }

  // NEW (CTO mandate — Co-work Style Confirmation): actually dispatches
  // a previously-confirmed tool call. Mirrors the same switch
  // _tryAgentActionFromText used to run immediately, just deferred
  // until the customer said yes.
  Future<void> _executePendingAction(Map<String, dynamic> args) async {
    switch (args['action'] as String?) {
      case 'book_transport':
        _actOnBookingAction(args);
        break;
      case 'navigate_to_section':
        _actOnNavigateAction(args);
        break;
      case 'check_and_update_app':
        await _actOnUpdateAction();
        break;
      case 'add_to_grocery_cart':
        _actOnGroceryAction(args);
        break;
      case 'create_service_request':
        await _actOnCreateServiceRequest(args);
        break;
      case 'report_app_bug':
        await _actOnReportBug(args);
        break;
    }
  }

  // NEW (Aug 11 2026 — Nizam's "AI Bug Reporting").
  //
  // Writes to `app_bug_reports`. Attaches device/app context the customer
  // could never be expected to provide (platform, app version, the screen
  // they were on, their uid) — that context is usually the difference
  // between a reproducible report and "it didn't work".
  //
  // Guarded against duplicate filing within one chat session: an agent
  // that re-files the same bug each time the customer re-describes it
  // would flood the admin queue with noise and make real reports harder
  // to spot.
  bool _bugReportFiledThisSession = false;

  Future<void> _actOnReportBug(Map<String, dynamic> args) async {
    final summary = (args['summary'] as String?)?.trim() ?? '';
    final details = (args['details'] as String?)?.trim() ?? '';
    if (summary.isEmpty && details.isEmpty) return;

    // GUEST MODE (Aug 11 2026): app_bug_reports is now isRealUser()-gated
    // too — a report filed under an anonymous uid gives admin nobody to
    // follow up with, and the collection would otherwise be a free,
    // unlimited write target. Asked here rather than silently failing so
    // the customer knows their report actually went somewhere.
    if (!await requireRealAuth(
      context,
      reason: 'Sign in so our team can follow up on what you found',
    )) {
      if (!mounted) return;
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: 'Noted. Sign in whenever you like and I’ll pass this to the team.',
        ),);
      });
      return;
    }
    if (!mounted) return;

    if (_bugReportFiledThisSession) {
      if (!mounted) return;
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: "I've already sent a report for this session — the team has "
              'it. If this is a different problem, tell me and I\'ll add it.',
        ),);
      });
      return;
    }

    try {
      final user = FirebaseAuth.instance.currentUser;
      String appVersion = 'unknown';
      try {
        final info = await PackageInfo.fromPlatform();
        appVersion = '${info.version}+${info.buildNumber}';
      } catch (_) {/* version is a nice-to-have, never block the report */}

      await FirebaseFirestore.instance.collection('app_bug_reports').add({
        'summary': summary.isEmpty ? details : summary,
        'details': details,
        'screen': (args['screen'] as String?)?.trim() ?? '',
        'severity': (args['severity'] as String?)?.trim() ?? 'medium',
        'source': 'ai_agent',
        'app': 'customer',
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'appVersion': appVersion,
        'reportedBy': user?.uid ?? '',
        'reporterName': user?.displayName ?? '',
        'status': 'open',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _bugReportFiledThisSession = true;

      if (!mounted) return;
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: "Reported — I've sent this to the team with your app details "
              'attached. Thanks for flagging it.',
        ),);
      });
    } catch (e) {
      debugPrint('[GuruChat] report_app_bug failed: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: "I couldn't send the report just now. Please try again in a "
              'moment.',
        ),);
      });
    }
  }

  static String _requestTypeLabel(String? type) => switch (type) {
        'custom_food_order' => 'food order',
        'grocery_order' => 'grocery order',
        'hero_booking' => 'hero booking',
        _ => 'order',
      };

  // NEW (Aug 11 2026 — Nizam: the agent must PLACE orders end-to-end).
  //
  // Runs the SAME ServiceRequestService.createServiceRequest() path that
  // hero_booking_screen / grocery_order_screen / custom_food_order_screen
  // already use — deliberately not a parallel implementation, so the
  // hero broadcast, admin alerting, usage-fee flush and every rule that
  // depends on that document shape all behave identically whether the
  // order came from a form or from the agent.
  //
  // Only reached AFTER the customer has explicitly confirmed the
  // preview in _confirmationTextFor — the agent never places an order
  // off its own judgement.
  Future<void> _actOnCreateServiceRequest(Map<String, dynamic> args) async {
    // GUEST MODE (Aug 11 2026 — this one is a genuine behaviour change,
    // not just an added guard). The `currentUser == null` check below
    // used to be the real gate, but every guest is now signed in
    // ANONYMOUSLY, so that check silently started passing. Without
    // requireRealAuth() here, the AI agent would happily file orders
    // under an anonymous uid that carries no phone number — nobody could
    // ring the customer back, and firestore.rules' isRealUser() would
    // reject the write anyway, leaving the agent to apologise for a
    // failure it could have prevented. The null check is kept below as a
    // safety net only.
    if (!await requireRealAuth(
      context,
      reason: 'Sign in and I’ll place this order for you right away',
    )) {
      if (!mounted) return;
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: 'No problem — sign in whenever you’re ready and I’ll place it for you.',
        ),);
      });
      return;
    }
    if (!mounted) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) return;
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: 'Please sign in first — I need an account to place the order under.',
        ),);
      });
      return;
    }

    final requestType = (args['request_type'] as String?)?.trim();
    final items = (args['items'] as String?)?.trim() ?? '';
    if (requestType == null || requestType.isEmpty || items.isEmpty) {
      if (!mounted) return;
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: "I didn't catch what to order. Tell me the item and I'll place it.",
        ),);
      });
      return;
    }

    try {
      // Signature is resolveCustomerPhone(User) — it takes the User
      // object itself (it needs the Auth phoneNumber as a fallback), not
      // a uid string.
      final phone = await AuthService().resolveCustomerPhone(user);
      final details = <String, dynamic>{
        'items': items,
        'placedByAi': true,
        if ((args['vendor'] as String?)?.trim().isNotEmpty ?? false)
          'hotelName': (args['vendor'] as String).trim(),
        if ((args['address'] as String?)?.trim().isNotEmpty ?? false)
          'dropAddress': (args['address'] as String).trim(),
        if ((args['note'] as String?)?.trim().isNotEmpty ?? false)
          'note': (args['note'] as String).trim(),
      };

      await ServiceRequestService().createServiceRequest(
        requestType: requestType,
        customerId: user.uid,
        customerName: user.displayName?.trim().isNotEmpty ?? false
            ? user.displayName!.trim()
            : 'Customer',
        customerPhone: phone,
        details: details,
      );

      if (!mounted) return;
      setState(() {
        _messages.add(_GuruMessage(
          role: 'assistant',
          text: 'Done — your ${_requestTypeLabel(requestType)} is placed and '
              'sent to nearby Heroes. You can track it under Booking Status.',
        ),);
      });
    } catch (e) {
      debugPrint('[GuruChat] create_service_request failed: $e');
      if (!mounted) return;
      setState(() {
        _messages.add(_GuruMessage(
          role: 'assistant',
          text: "I couldn't place that order just now ($e). Please try again, "
              'or use the normal booking screen.',
        ),);
      });
    }
  }

  // NEW (CTO mandate — Dual-Mode Grocery Cart, Mode 2): notes the item
  // via GroceryAiNotesService — NOT a Firestore write, NOT a
  // navigation. The existing GroceryOrderScreen picks this up next
  // time it opens and pre-fills its own, completely unmodified
  // `_listCtrl` text field, exactly as if the customer had typed it.
  void _actOnGroceryAction(Map<String, dynamic> args) {
    final item = (args['item'] as String?)?.trim() ?? '';
    if (item.isEmpty) return;
    final quantity = (args['quantity'] as String?)?.trim();
    GroceryAiNotesService.instance.addItem(item, quantity: quantity);

    if (!mounted) return;
    final label = (quantity != null && quantity.isNotEmpty) ? '$quantity $item' : item;
    setState(() {
      _messages.add(
        _GuruMessage(
          role: 'assistant',
          text: 'Added "$label" to your grocery list — open Grocery Order to review and submit.',
        ),
      );
    });
    _scrollToBottom();
  }

  // NEW (CTO mandate — Multi-Agent Orchestration & Handoff Architecture,
  // "The Magic"): the actual handoff. Groq (orchestrator) already
  // decided to call this; this method wakes up Gemini (the vision
  // specialist) with the real image bytes, gets back a clean numbered
  // list of products, and then — exactly like the CTO's step 5 — Groq's
  // OWN add_to_grocery_cart execution path (_actOnGroceryAction's core
  // logic, GroceryAiNotesService.addItem) runs automatically for every
  // item Gemini found. No re-confirmation per item — this whole flow is
  // a non-write, reversible list-note, same safety class as every other
  // instant action in this method.
  Future<void> _actOnVisionHandoffAction(Uint8List imageBytes) async {
    if (!mounted) return;
    setState(() {
      _messages.add(const _GuruMessage(role: 'assistant', text: 'Let me take a closer look at that photo...'));
    });
    _scrollToBottom();

    final geminiKey = await GeminiApiService().resolveApiKey();
    final items = await GeminiApiService().analyzeGroceryScreenshot(
      imageBytes: imageBytes,
      apiKey: geminiKey,
    );

    if (!mounted) return;
    if (items == null || items.isEmpty) {
      setState(() {
        _messages.add(const _GuruMessage(
          role: 'assistant',
          text: "I couldn't clearly identify a product in that photo — please try a "
              'clearer photo, or just type the item into the chat.',
        ));
      });
      _scrollToBottom();
      return;
    }

    // Groq's add_to_grocery_cart execution, run once per Gemini-found
    // item — same GroceryAiNotesService.instance.addItem call
    // _actOnGroceryAction uses for a single manually-typed item.
    for (final entry in items) {
      final item = entry['item'] ?? '';
      if (item.isEmpty) continue;
      final quantity = entry['quantity'];
      GroceryAiNotesService.instance.addItem(item, quantity: (quantity?.isEmpty ?? true) ? null : quantity);
    }

    final numbered = items.asMap().entries.map((e) {
      final n = e.key + 1;
      final item = e.value['item'] ?? '';
      final quantity = e.value['quantity'];
      final label = (quantity != null && quantity.isNotEmpty) ? '$quantity $item' : item;
      return '$n. $label';
    }).join('\n');

    setState(() {
      _messages.add(_GuruMessage(
        role: 'assistant',
        text: 'Found these in your photo and added them to your grocery list:\n$numbered\n\n'
            'Open Grocery Order to review and submit.',
      ));
    });
    _scrollToBottom();
    unawaited(_speak('I found ${items.length} item${items.length == 1 ? '' : 's'} in your photo and added '
        '${items.length == 1 ? 'it' : 'them'} to your grocery list.'));
  }

  // NEW (CTO mandate — Co-work Style Confirmation): a customer tapping
  // a suggestion chip sends its exact label back as their next message,
  // same as if they'd typed it.
  void _onSuggestionTapped(String suggestion) {
    unawaited(_sendMessage(suggestion));
  }

  // NEW (Chitti AI upgrade, Task 2 — Vision): reuses file_picker (already
  // a project dependency — see grocery_order_screen.dart's DMart
  // cart-screenshot upload) instead of adding image_picker as a second,
  // redundant image-selection package for the same job.
  Future<void> _pickAttachment() async {
    if (_pickingImage) return;
    setState(() => _pickingImage = true);
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.image,
        withData: true,
      );
      final bytes = result?.files.single.bytes;
      if (bytes != null && mounted) {
        // FIX (Nizam's report — screenshot upload to Guru "olaruthu"/
        // fails): raw phone-screenshot PNGs (often 1-4MB) were being
        // base64-encoded and sent as-is, mislabeled as image/jpeg —
        // both likely over Groq's base64 payload ceiling AND a
        // format/MIME mismatch. Downscale + re-encode as real JPEG
        // (already have the `image` package as a dependency, just
        // wasn't wired into this flow) before it ever leaves the
        // device — this also makes uploads noticeably faster on
        // mobile data.
        final compressed = _compressForVision(bytes);
        setState(() => _pendingImageBytes = compressed ?? bytes);
      }
    } catch (e) {
      debugPrint('[GuruChatScreen] image pick failed: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open the screenshot. Please try again.')),
        );
      }
    } finally {
      if (mounted) setState(() => _pickingImage = false);
    }
  }

  void _clearAttachment() {
    setState(() => _pendingImageBytes = null);
  }

  // NEW (Chitti AI upgrade, Task 2 — Vision, screenshot-upload fix): decode,
  // downscale to a max 800px longest edge, and re-encode as heavily
  // compressed JPEG (quality 70) — plenty for the AI to read UI
  // text/buttons, screenshots don't need full resolution. FIX (per
  // Nizam's explicit ask): used the `image` package instead of adding
  // `flutter_image_compress` as a second dependency doing the same job —
  // `image` was already a pubspec dependency, is pure-Dart (no extra
  // native platform channel/plugin surface to maintain), and does
  // exactly this decode/resize/re-encode job synchronously with no
  // external process. Happy to switch to flutter_image_compress instead
  // if there's a specific reason to prefer it (e.g. its native
  // encoders are meaningfully faster on very large images), just say
  // the word. Runs synchronously on the UI isolate — screenshots are
  // small enough (a few MB) that this is a brief, one-time cost per
  // attachment, not worth a background isolate for this flow. Returns
  // null (caller falls back to the original bytes) if decoding fails
  // for any reason, e.g. an unsupported/corrupt file — never blocks
  // the customer from sending.
  Uint8List? _compressForVision(Uint8List rawBytes) {
    try {
      final decoded = img.decodeImage(rawBytes);
      if (decoded == null) return null;
      final resized = decoded.width > 800 || decoded.height > 800
          ? img.copyResize(
              decoded,
              width: decoded.width >= decoded.height ? 800 : null,
              height: decoded.height > decoded.width ? 800 : null,
            )
          : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 70));
    } catch (e) {
      debugPrint('[GuruChatScreen] Screenshot compression failed: $e');
      return null;
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      unawaited(
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent + 160,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOutCubic,
        ),
      );
    });
  }

  void _startNewChat() {
    setState(() {
      _messages.clear();
      _inputController.clear();
    });
  }

  // -- Voice-to-Order (Pro) ------------------------------------------------

  Future<void> _onMicTapped() async {
    final activation = context.read<AiActivationService>();
    if (!activation.isAiActivated) {
      return;
    }

    // NEW (Chitti AI upgrade — "Claim My Free Voice Access"): voice is
    // still free for every activated customer, but the first tap now
    // shows a quick claim sheet instead of unlocking silently — a
    // deliberate small engagement moment, not a real paywall (see
    // AiActivationService.claimFreeVoiceAccess(), persisted locally
    // once tapped). isProUnlocked returns true immediately for anyone
    // who's already claimed it (or been admin-granted real Pro), so
    // this only ever shows once per device.
    if (!activation.isProUnlocked) {
      final claimed = await _showVoiceClaimSheet();
      if (claimed != true || !mounted) {
        return;
      }
    }

    if (_isListening) {
      await _speech.stop();
      if (mounted) setState(() => _isListening = false);
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        onStatus: (status) {
          if (status == 'notListening' || status == 'done') {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('[GuruChatScreen] speech error: $error');
          if (mounted) setState(() => _isListening = false);
        },
      );
    }

    if (!_speechReady) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Microphone not available on this device.'),
        ),
      );
      return;
    }

    // FIX (Nizam's report — Tamil voice input garbled/stuttering,
    // e.g. "ErodeErode busErode bus stand..."): the old listen() call
    // never passed a localeId at all, so speech_to_text fell back to
    // the PHONE's system-level input language — commonly en-IN even on
    // devices where the customer is speaking Tamil to the app itself.
    // Forcing English acoustic/language recognition onto Tamil speech
    // is exactly what produces this kind of fragmented, re-guessed
    // stutter. Resolve the actual device-reported Tamil locale (never
    // hardcode a guessed string like 'ta-IN' — casing/separator varies
    // by OEM) and use it whenever the customer's in-app language
    // (Settings → Language) is Tamil or Tanglish.
    final languageCode = context.read<LocalizationService>().languageCode;
    String? localeId;
    if (languageCode == 'ta' || languageCode == 'tg') {
      try {
        final locales = await _speech.locales();
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().startsWith('ta')) {
            localeId = locale.localeId;
            break;
          }
        }
      } catch (e) {
        debugPrint('[GuruChatScreen] Could not resolve Tamil locale: $e');
      }
      // FIX (per Nizam's explicit ask for a 'ta-IN' fallback): if the
      // device's own locale list came back empty/failed to enumerate
      // (rare, but seen on some OEM builds with a stripped-down speech
      // service), don't silently fall through to the system default —
      // try the standard Android/iOS Tamil locale ID directly as a
      // last resort before giving up on the locale hint entirely.
      localeId ??= 'ta-IN';
    }

    setState(() {
      _isListening = true;
      _voiceResultHandled = false;
    });
    unawaited(
      _speech.listen(
        onResult: (result) {
          _inputController.text = result.recognizedWords;
          _inputController.selection = TextSelection.collapsed(
            offset: _inputController.text.length,
          );
          final words = result.recognizedWords.trim();
          // FIX (CTO mandate — AI Voice Misfire): guards against a
          // "final" result the plugin returns after only a word or two
          // (a real speech_to_text behavior on some Android devices when
          // background noise briefly interrupts listening) getting
          // actioned as if the customer had actually finished their
          // sentence. Single common words like "hi"/"ok" are allowed
          // through (>=1 word), but requires at least 2 characters so a
          // stray single-letter noise blip never fires an action.
          final looksLikeRealUtterance = words.length >= 2;
          if (result.finalResult &&
              looksLikeRealUtterance &&
              !_voiceResultHandled) {
            _voiceResultHandled = true;
            setState(() => _isListening = false);
            unawaited(_handleVoiceUtterance(words));
          }
        },
        localeId: localeId,
        // FIX (same report): partial (interim) results were left on
        // the plugin's default. Independently of the locale, streaming
        // partial hypotheses being repeatedly re-guessed is a second,
        // separate source of the "word word word" stutter pattern.
        // Only firing onResult once, on the final transcript, removes
        // that whole accumulating-hypothesis path outright.
        listenOptions: stt.SpeechListenOptions(
          partialResults: false,
          cancelOnError: true,
        ),
        // FIX (CTO QA — "mic stops and sends after one or two words";
        // CTO mandate — AI Voice Misfire "acts before customer finishes
        // speaking"): widened again, 5s -> 8s. 3s was already found too
        // aggressive once; 5s can still read as "done talking" during a
        // longer natural pause (recalling an address, street name,
        // item name mid-sentence) — that premature pauseFor cutoff is
        // the most likely real cause of "acts before I finish talking"
        // for a customer speaking slowly or in a second language.
        // listenFor unchanged — still gives 30s of total room before
        // the plugin gives up regardless of pauses.
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 8),
      ),
    );
  }

  // Execute the action, don't just describe it: parse the transcribed
  // utterance for a service + destination and, when recognized, push the
  // real booking screen with everything pre-filled — falling back to a
  // normal AI chat reply only when no service keyword is understood at
  // all. See voice_booking_intent_service.dart for the parsing rules.
  Future<void> _handleVoiceUtterance(String utterance) async {
    final intent = _voiceIntent.parse(utterance);
    if (intent == null) {
      // Nothing service-shaped in there — treat it as a normal question.
      unawaited(_sendMessage('🎙 $utterance'));
      return;
    }
    unawaited(_navigateForBookingIntent(intent));
  }

  // NEW (CTO mandate — Autonomous Agent, Option 3 with the mandatory
  // human-in-the-loop safety net): shared navigate-and-prefill action,
  // extracted so BOTH the local regex-based voice parser above AND the
  // Groq function-calling text-intent path below (_tryAgentActionFromText)
  // drive the exact same "programmatic navigation" behavior. Critically,
  // this method NEVER calls a ride-creation/dispatch API itself — it
  // only pushes BikeBookingScreen with fields pre-filled. The actual
  // booking still requires the customer to review and tap Confirm on
  // that screen, completely unchanged — that's the safety net, and it
  // costs nothing extra to guarantee because it's simply reusing the
  // existing screen rather than bypassing it.
  Future<void> _navigateForBookingIntent(VoiceBookingIntent intent) async {
    if (intent.service == VoiceService.sos) {
      _showVoiceToast('Opening SOS...');
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(builder: (_) => const SosScreen()),
        ),
      );
      return;
    }

    if (intent.destinationQuery == null) {
      // Heard/typed a service ("book an auto") but no destination at
      // all — still take the customer straight to that service's
      // booking screen rather than making them repeat themselves.
      _showVoiceToast('Opening ${intent.displayName} booking...');
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BikeBookingScreen(initialCategory: intent.categoryKey),
          ),
        ),
      );
      return;
    }

    _showVoiceToast('Finding "${intent.destinationQuery}"...');
    final resolved = await _voiceIntent.resolve(intent);
    if (!mounted) return;

    if (resolved.destination == null) {
      // Recognized the service but couldn't geocode the spoken place —
      // don't silently fail; open the booking screen with the category
      // already selected so the customer only has to type/search the
      // destination once, and say plainly why.
      _showVoiceToast(
        'Couldn\'t find "${intent.destinationQuery}" — opening ${intent.displayName} so you can search it.',
      );
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => BikeBookingScreen(initialCategory: intent.categoryKey),
          ),
        ),
      );
      return;
    }

    _showVoiceToast(
      'Opening ${intent.displayName} to ${resolved.destination!['name'] ?? intent.destinationQuery}...',
    );
    unawaited(
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => BikeBookingScreen(
            initialCategory: intent.categoryKey,
            initialDropLocation: resolved.destination,
          ),
        ),
      ),
    );
  }

  // NEW (CTO mandate — Admin AI Co-Pilot Foundation, Option 1: Analytics
  // Logging): fire-and-forget structured event log of WHAT customers ask
  // Guru to do — never the raw chat text (privacy + cost) — so a future
  // Admin AI can read `guru_analytics` and see usage patterns (which
  // services get asked for, confirm-vs-cancel rates, language split,
  // peak times) without touching conversation content. Two events per
  // agent action: 'intent_requested' when confirmation chips are shown,
  // 'intent_resolved' when the customer answers yes/no. Wrapped in its
  // own try/catch and always called via `unawaited` by its callers, so a
  // Firestore hiccup (or being offline) can never block or break the
  // existing chat/booking flow — this is purely additive, analytics-only,
  // and does not alter any existing function's behavior or signature.
  Future<void> _logGuruAnalyticsEvent({
    required String eventType,
    String? action,
    Map<String, dynamic>? args,
    bool? resolved,
  }) async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      final languageLabel = mounted ? _languageInfo(context).label : null;
      await FirebaseFirestore.instance.collection('guru_analytics').add(<String, dynamic>{
        'customerId': uid,
        'source': 'chat_screen',
        'eventType': eventType,
        'intent': action,
        if (args?['section'] != null) 'section': args!['section'],
        if (args?['service'] != null) 'serviceType': args!['service'],
        if (resolved != null) 'resolved': resolved,
        if (languageLabel != null && languageLabel.isNotEmpty)
          'languageUsed': languageLabel,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[GuruChatScreen] analytics log failed: $e');
    }
  }

  // NEW (CTO mandate — Autonomous Agent "brain" + Dynamic PWA Guided
  // Tour): asks Groq (via function/tool calling, see
  // GuruApiService.extractAgentAction) if this TYPED message is a
  // clear booking request OR a navigation ("where/how do I...")
  // request. Returns true and takes over (posts a confirming assistant
  // message + navigates) only when the model actually called one of
  // the two tools; returns false — meaning the caller should fall
  // through to a normal chat reply — for every other case (declined by
  // the model, network/parse failure, unrecognized key). A failure
  // here is never user-visible as an error; it just silently becomes
  // "ask the AI normally" instead.
  Future<bool> _tryAgentActionFromText(
    String input,
    String apiKey, {
    Uint8List? imageBytes,
  }) async {
    Map<String, dynamic>? args;
    try {
      args = await _api.extractAgentAction(
        message: input,
        apiKeyOverride: apiKey,
        hasAttachedImage: imageBytes != null,
      );
    } catch (e) {
      debugPrint('[GuruChatScreen] extractAgentAction failed: $e');
    }
    if (args == null) return false;
    // FIX (compiler error — "argument type Map<String, dynamic>? can't
    // be assigned to Map<String, dynamic>"): `args` is a mutable local,
    // so the `args == null` check above doesn't stay promoted to
    // non-null once it's captured inside the setState() closure below —
    // Dart can't prove the variable is still non-null by the time the
    // closure actually runs. Copying it into a new `final` local carries
    // the non-null type through the closure with no such ambiguity.
    final resolvedArgs = args;
    final action = resolvedArgs['action'] as String?;
    if (action != 'book_transport' &&
        action != 'navigate_to_section' &&
        action != 'check_and_update_app' &&
        action != 'add_to_grocery_cart' &&
        action != 'analyze_screen_with_vision' &&
        // Aug 11 2026: without this the new order-placement tool would be
        // silently rejected here and never reach _executePendingAction.
        action != 'create_service_request' &&
        action != 'report_app_bug') {
      return false;
    }

    // NEW (CTO mandate — Multi-Agent Orchestration & Handoff
    // Architecture): the vision handoff needs the actual image bytes,
    // which never travel through extractAgentAction's text-only call —
    // Groq only ever sees the fact that AN image is attached (via
    // hasAttachedImage), never the pixels themselves. If Groq still
    // called this tool with no image actually attached client-side
    // (shouldn't happen given the system prompt, but never trust a
    // model's tool call blindly), degrade to a plain reply instead of
    // calling Gemini with nothing.
    if (action == 'analyze_screen_with_vision') {
      if (imageBytes == null) return false;
      if (!mounted) return true;
      unawaited(_logGuruAnalyticsEvent(eventType: 'intent_requested', action: action, args: resolvedArgs));
      await _actOnVisionHandoffAction(imageBytes);
      unawaited(_logGuruAnalyticsEvent(eventType: 'intent_resolved', action: action, args: resolvedArgs, resolved: true));
      return true;
    }

    // NEW (CTO mandate — "Autonomous Interaction Rule"): confirmation
    // gates are now REMOVED for every tool action except two scenarios
    // — (A) final payment/order/booking confirmation, and (B) genuine
    // ambiguity, handled via suggestion chips in the plain-chat
    // fallback below, not this gate. None of this screen's 4 tools are
    // Scenario A: book_transport/navigate_to_section only push a
    // screen (optionally pre-filled); check_and_update_app and
    // add_to_grocery_cart don't spend money or finalize anything
    // either. Scenario A itself — the actual booking/payment — still
    // lives entirely on the destination screen's own Confirm button
    // and SOS's separate KYC gate, both completely untouched by this
    // change. The block below this comment is kept as a defensive
    // fallback for any FUTURE tool that DOES need Scenario-A gating —
    // it's simply unreached by today's 4 actions, not deleted, so a
    // later write-type tool has a gate ready to opt into.
    if (action == 'navigate_to_section' ||
        action == 'book_transport' ||
        action == 'check_and_update_app' ||
        action == 'add_to_grocery_cart' ||
        // Aug 11 2026: filing a bug report costs nothing and reverses
        // nothing, so gating it behind a Yes/No adds friction to the one
        // moment the customer is ALREADY frustrated. Auto-execute; the
        // reply confirms it was sent. (create_service_request stays
        // gated below — that one commits real money.)
        action == 'report_app_bug') {
      if (!mounted) return true;
      unawaited(_logGuruAnalyticsEvent(
        eventType: 'intent_requested',
        action: action,
        args: resolvedArgs,
      ));
      unawaited(_logGuruAnalyticsEvent(
        eventType: 'intent_resolved',
        action: action,
        args: resolvedArgs,
        resolved: true,
      ));
      await _executePendingAction(resolvedArgs);
      return true;
    }

    // NEW (CTO mandate — Co-work Style Confirmation & Suggestions,
    // "Human-in-the-Loop"): don't execute yet. Store the parsed args and
    // ask the customer to confirm first, with Yes/No suggestion chips —
    // the next message they send is interpreted as that answer (see the
    // top of _sendMessage).
    if (!mounted) return true;
    _pendingAgentAction = resolvedArgs;
    unawaited(_logGuruAnalyticsEvent(
      eventType: 'intent_requested',
      action: action,
      args: resolvedArgs,
    ));
    setState(() {
      _messages.add(
        _GuruMessage(
          role: 'assistant',
          text: _confirmationTextFor(resolvedArgs),
          suggestions: const ['Yes, proceed', 'No, cancel'],
        ),
      );
    });
    _scrollToBottom();
    unawaited(_speak(_confirmationTextFor(resolvedArgs)));
    return true;
  }

  // NEW (CTO mandate — Co-work Style Confirmation): plain-language
  // preview of what's about to happen, shown before any tool actually
  // runs.
  String _confirmationTextFor(Map<String, dynamic> args) {
    switch (args['action'] as String?) {
      case 'book_transport':
        final service = _voiceServiceFromKey(args['service'] as String?);
        final dest = (args['destination'] as String?)?.trim();
        final serviceName = service != null
            ? VoiceBookingIntent(service: service).displayName
            : 'ride';
        return dest != null && dest.isNotEmpty
            ? "I'm ready to book a $serviceName to $dest — should I proceed?"
            : "I'm ready to open $serviceName booking for you — should I proceed?";
      case 'navigate_to_section':
        final section = args['section'] as String?;
        return "I'm ready to open ${_sectionLabel(section)} for you — should I proceed?";
      case 'check_and_update_app':
        return "I'm ready to check for an app update — should I proceed?";
      case 'add_to_grocery_cart':
        final item = (args['item'] as String?)?.trim() ?? 'that item';
        final quantity = (args['quantity'] as String?)?.trim();
        final label = (quantity != null && quantity.isNotEmpty) ? '$quantity $item' : item;
        return "I'll add \"$label\" to your grocery list — should I proceed?";
      // NEW (Aug 11 2026): this one PLACES a real order and dispatches it
      // to Heroes, so the confirmation names exactly what will be ordered
      // and from where — this is the last checkpoint before money and a
      // real hero's time are committed.
      case 'create_service_request':
        final items = (args['items'] as String?)?.trim() ?? 'your request';
        final vendor = (args['vendor'] as String?)?.trim();
        final label = _requestTypeLabel(args['request_type'] as String?);
        return vendor != null && vendor.isNotEmpty
            ? "I'll place a $label for \"$items\" from $vendor and send it to "
                'nearby Heroes — should I proceed?'
            : "I'll place a $label for \"$items\" and send it to nearby "
                'Heroes — should I proceed?';
      default:
        return 'Should I proceed?';
    }
  }

  // NEW (CTO mandate — AI Autonomous App Updating): runs the same safe
  // PWA update flow the dashboard's Update button/drawer tile use.
  // Native builds get an honest "not supported yet" reply instead of a
  // silent no-op, since AppUpdateChecker's native flow needs a
  // BuildContext-driven download/install dialog this chat bubble isn't
  // set up to host.
  Future<bool> _actOnUpdateAction() async {
    if (!mounted) return true;
    if (!kIsWeb) {
      setState(() {
        _messages.add(
          const _GuruMessage(
            role: 'assistant',
            text: "You're on the app store build — updates install "
                'automatically in the background, nothing to trigger here.',
          ),
        );
      });
      _scrollToBottom();
      return true;
    }

    setState(() {
      _messages.add(
        const _GuruMessage(role: 'assistant', text: 'Checking for an update...'),
      );
    });
    _scrollToBottom();

    try {
      await WebVersionChecker.instance.checkNow();
    } catch (e) {
      debugPrint('[GuruChatScreen] update check failed: $e');
    }

    if (!mounted) return true;

    if (!WebVersionChecker.instance.isUpdateAvailable) {
      setState(() {
        _messages.add(
          const _GuruMessage(
            role: 'assistant',
            text: "You're already on the latest version!",
          ),
        );
      });
      _scrollToBottom();
      return true;
    }

    setState(() {
      _messages.add(
        const _GuruMessage(
          role: 'assistant',
          text: 'Found a new version — updating now, the app will refresh in a moment...',
        ),
      );
    });
    _scrollToBottom();

    try {
      // The page navigates away on success, so nothing after this needs
      // to run in the happy path.
      await PwaCachePlatform().clearAndReload();
    } catch (e) {
      debugPrint('[GuruChatScreen] update apply failed: $e');
      if (!mounted) return true;
      setState(() {
        _messages.add(
          const _GuruMessage(
            role: 'assistant',
            text: "The update didn't go through — please try again from the side menu.",
          ),
        );
      });
      _scrollToBottom();
    }
    return true;
  }

  bool _actOnBookingAction(Map<String, dynamic> args) {
    final service = _voiceServiceFromKey(args['service'] as String?);
    if (service == null) return false;

    final destinationRaw = (args['destination'] as String?)?.trim();
    final intent = VoiceBookingIntent(
      service: service,
      destinationQuery: (destinationRaw != null && destinationRaw.isNotEmpty) ? destinationRaw : null,
    );

    if (!mounted) return true;
    setState(() {
      _messages.add(
        _GuruMessage(
          role: 'assistant',
          text: intent.service == VoiceService.sos
              ? "I've opened SOS for you — please confirm there so we can get you help right away."
              : "I've got it! Setting up your ${intent.displayName} booking now — review the details and press Confirm to book your Hero.",
        ),
      );
    });
    _scrollToBottom();
    unawaited(_navigateForBookingIntent(intent));
    return true;
  }

  // NEW (CTO mandate — "Dynamic PWA Guided Tour"): maps the section key
  // Groq extracted to a real screen and pushes it directly, exactly
  // the same Navigator.push pattern _navigateForBookingIntent already
  // uses for booking screens — no dashboard tab-index plumbing needed
  // (DashboardScreen's bottom-nav tabs are private State, unreachable
  // from a screen pushed on top of it; every non-tab section in this
  // codebase is already a plain pushed route, so this is consistent
  // with the existing architecture, not a special case).
  bool _actOnNavigateAction(Map<String, dynamic> args) {
    final section = args['section'] as String?;
    final target = _screenForSection(section);
    if (target == null) return false;

    if (!mounted) return true;
    setState(() {
      _messages.add(
        _GuruMessage(role: 'assistant', text: "Sure! Opening ${_sectionLabel(section!)} for you now."),
      );
    });
    _scrollToBottom();
    unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => target)));
    return true;
  }

  Widget? _screenForSection(String? section) {
    switch (section) {
      case 'food':
        return const FoodHubScreen();
      case 'grocery':
        return const GroceryOrderScreen();
      case 'electronics':
        return const NjTechServiceScreen();
      case 'rewards':
        return const RewardsScreen();
      case 'game_zone':
        return const PlayZoneScreen();
      case 'safety':
        return const SosScreen();
      case 'settings':
        return const SettingsScreen();
      case 'car_wash':
        return const CarWashScreen();
      case 'printing':
        return const PrintingServiceScreen();
      case 'hero_needs':
        return const HeroBookingScreen();
      case 'profile':
        return const ProfileScreen();
      case 'ride_history':
        return const RideHistoryScreen();
      default:
        return null;
    }
  }

  // FIX (compiler error — "String? can't be assigned to String"):
  // widened to accept null since _confirmationTextFor above only has a
  // nullable `section` to hand it (the args map doesn't guarantee the
  // key exists) — the switch's own default case already reads fine as
  // "that section" for a null input.
  String _sectionLabel(String? section) {
    switch (section) {
      case 'food':
        return 'Food Genie';
      case 'grocery':
        return 'Grocery';
      case 'electronics':
        return 'Electronics service';
      case 'rewards':
        return 'Rewards';
      case 'game_zone':
        return 'Game Zone';
      case 'safety':
        return 'Safety';
      case 'settings':
        return 'Settings';
      case 'car_wash':
        return 'Car Wash';
      case 'printing':
        return 'Printing';
      case 'hero_needs':
        return 'Hero Booking';
      case 'profile':
        return 'your Profile';
      case 'ride_history':
        return 'Ride History';
      default:
        return 'that section';
    }
  }

  VoiceService? _voiceServiceFromKey(String? key) {
    switch (key) {
      case 'bike':
        return VoiceService.bike;
      case 'auto':
        return VoiceService.auto;
      case 'cab':
        return VoiceService.cab;
      case 'parcel':
        return VoiceService.parcel;
      case 'mini_truck':
        return VoiceService.miniTruck;
      case 'lorry':
        return VoiceService.lorry;
      case 'sos':
        return VoiceService.sos;
      default:
        return null;
    }
  }

  void _showVoiceToast(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: context.colors.elevatedSurface,
        behavior: SnackBarBehavior.floating,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  Future<bool?> _showVoiceClaimSheet() {
    return showModalBottomSheet<bool>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => const _VoiceClaimSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final activation = context.watch<AiActivationService>();
    // NEW (Batch 1 Theme Retrofit) — local, per-build theme binding
    // replacing the old fixed top-level palette. See the file-header
    // comment for the full name mapping. (The other palette colors are
    // bound locally inside _buildAppBar/_buildWelcomeState/
    // _buildInputBar instead — each is a separate method, not part of
    // build()'s own scope, so build() only needs what it uses itself.)
    final bg = context.colors.background;

    return Scaffold(
      backgroundColor: bg,
      body: !activation.isAiActivated
          ? const _SuperHeroActivationScreen()
          : SafeArea(
              child: Stack(
                children: [
                  const _GlowBackdrop(),
                  Column(
                    children: [
                      _buildAppBar(context, activation),
                      Expanded(
                        child: _messages.isEmpty
                            ? _buildWelcomeState()
                            : _buildMessages(),
                      ),
                      if (_isTyping) const _GuruTypingIndicator(),
                      _buildInputBar(),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildAppBar(BuildContext context, AiActivationService activation) {
    final ink = context.colors.text;
    final muted = context.colors.mutedText;
    final accentC = context.colors.accentTertiary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 4, 10, 4),
      child: Row(
        children: [
          IconButton(
            onPressed: () => Navigator.of(context).maybePop(),
            icon: Icon(Icons.arrow_back_rounded, color: ink),
          ),
          const _GuruAvatar(size: 30),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'MyAllin1 Super Hero',
                  style: GoogleFonts.outfit(
                    color: ink,
                    fontSize: 16,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                // FIX (Pro Mode Voice Bypass mandate): voice is no longer
                // Pro-gated, so this badge shouldn't imply it is —
                // always reflects that chat + voice are both unlocked
                // once the customer has activated their own key.
                Text(
                  'Voice unlocked',
                  style: GoogleFonts.outfit(
                    color: accentC,
                    fontSize: 11.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          // NEW (CTO mandate — Text-to-Speech): lets the customer turn
          // off auto-speak without losing anything else — chat still
          // works exactly the same, Guru just stays silent.
          IconButton(
            onPressed: () {
              setState(() => _autoSpeak = !_autoSpeak);
              if (!_autoSpeak) unawaited(_tts.stop());
            },
            tooltip: _autoSpeak ? 'Mute Chitti' : 'Unmute Chitti',
            icon: Icon(
              _autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: muted,
            ),
          ),
          IconButton(
            onPressed: _startNewChat,
            tooltip: 'New chat',
            icon: Icon(Icons.add_comment_outlined, color: muted),
          ),
        ],
      ),
    );
  }

  Widget _buildWelcomeState() {
    final muted = context.colors.mutedText;
    final accentA = context.colors.accentSecondary;
    final accentB = context.colors.accent;
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const _GuruAvatar(size: 64, glow: true),
            const SizedBox(height: 18),
            ShaderMask(
              shaderCallback: (bounds) => LinearGradient(
                colors: [accentB, accentA],
              ).createShader(bounds),
              child: Text(
                "Vanakkam! I'm your Super Hero.",
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ask me anything about rides, deliveries, or services in Erode.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: muted, fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              alignment: WrapAlignment.center,
              children: _capabilities
                  .map((c) => _CapabilityChip(capability: c))
                  .toList(),
            ),
            const SizedBox(height: 22),
            Wrap(
              spacing: 10,
              runSpacing: 10,
              alignment: WrapAlignment.center,
              children: _suggestedPrompts
                  .map((p) => _PromptChip(label: p, onTap: () => unawaited(_sendMessage(p))))
                  .toList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMessages() {
    return ListView.builder(
      controller: _scrollController,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
      itemCount: _messages.length,
      itemBuilder: (context, index) => _GuruMessageBubble(
        message: _messages[index],
        onSuggestionTap: _onSuggestionTapped,
      ),
    );
  }

  Widget _buildInputBar() {
    final ink = context.colors.text;
    final muted = context.colors.mutedText;
    final border = context.colors.border;
    final accentA = context.colors.accentSecondary;
    final accentB = context.colors.accent;
    final surfaceElevated = context.colors.elevatedSurface;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // NEW (Chitti AI upgrade, Task 2 — Vision): preview of the
            // screenshot picked but not yet sent, with a quick remove.
            if (_pendingImageBytes != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Stack(
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: Image.memory(
                        _pendingImageBytes!,
                        width: 72,
                        height: 72,
                        fit: BoxFit.cover,
                      ),
                    ),
                    Positioned(
                      top: -6,
                      right: -6,
                      child: GestureDetector(
                        onTap: _clearAttachment,
                        child: Container(
                          padding: const EdgeInsets.all(3),
                          decoration: BoxDecoration(color: surfaceElevated, shape: BoxShape.circle),
                          child: Icon(Icons.close_rounded, color: muted, size: 16),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                // NEW (Chitti AI upgrade, Task 2 — Vision): attachment
                // button so the customer can send a screenshot of an
                // app issue for Guru to troubleshoot.
                IconButton(
                  onPressed: _pickingImage ? null : () => unawaited(_pickAttachment()),
                  icon: _pickingImage
                      ? SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: muted),
                        )
                      : Icon(Icons.attach_file_rounded, color: muted),
                ),
                _VoiceMicButton(
                  isListening: _isListening,
                  // FIX (Pro Mode Voice Bypass mandate): voice is unlocked
                  // for every activated customer now, not just
                  // isProUnlocked ones — pass true so the mic always shows
                  // its active/unlocked styling instead of the old muted
                  // "locked" look.
                  isPro: true,
                  onTap: () => unawaited(_onMicTapped()),
                ),
                const SizedBox(width: 8),
                Expanded(
              child: Container(
                constraints: const BoxConstraints(minHeight: 48, maxHeight: 140),
                decoration: BoxDecoration(
                  color: surfaceElevated,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: border),
                ),
                child: TextField(
                  controller: _inputController,
                  minLines: 1,
                  maxLines: 5,
                  onSubmitted: (_) => unawaited(_sendMessage()),
                  textInputAction: TextInputAction.send,
                  style: GoogleFonts.notoSansTamil(color: ink, fontWeight: FontWeight.w500, fontSize: 14.5),
                  decoration: InputDecoration(
                    hintText: _isListening ? 'Listening...' : 'Message your Super Hero...',
                    hintStyle: GoogleFonts.outfit(color: muted, fontWeight: FontWeight.w500),
                    border: InputBorder.none,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 44,
              height: 44,
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: [accentB, accentA]),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  onPressed: _isTyping ? null : () => unawaited(_sendMessage()),
                  icon: const Icon(Icons.arrow_upward_rounded, color: Colors.white, size: 20),
                  padding: EdgeInsets.zero,
                ),
              ),
            ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Activation / Onboarding — "Unlock your Super Hero"
// ================================================================
// Shown instead of the chat whenever AiActivationService.isAiActivated
// is false. Per Nizam's request: no API-key form here anymore — the
// customer is told to contact Admin Support, who provisions the key on
// the backend/via ai_settings_screen; once that happens this screen
// swaps to the real chat automatically (AiActivationService notifies
// listeners on refresh).
class _SuperHeroActivationScreen extends StatelessWidget {
  const _SuperHeroActivationScreen();

  Future<void> _contactAdmin(BuildContext context) async {
    final message = Uri.encodeComponent(
      "Hi NJ Tech! I'd like to unlock MyAllin1 Super Hero (AI Assistant) on my account.",
    );
    final uri = Uri.parse('https://wa.me/$kCallCenterNumberIntl?text=$message');
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open WhatsApp. Please call Admin Support directly.')),
      );
    }
  }

  Future<void> _callAdmin(BuildContext context) async {
    final uri = Uri.parse('tel:+$kCallCenterNumberIntl');
    final launched = await launchUrl(uri);
    if (!launched && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not start the call.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.text;
    final muted = context.colors.mutedText;
    final border = context.colors.border;
    final accentA = context.colors.accentSecondary;
    final accentB = context.colors.accent;
    final accentC = context.colors.accentTertiary;
    final surface = context.colors.surface;
    return Stack(
      children: [
        const _GlowBackdrop(),
        SafeArea(
          child: Column(
            children: [
              Align(
                alignment: Alignment.topLeft,
                child: IconButton(
                  onPressed: () => Navigator.of(context).maybePop(),
                  icon: Icon(Icons.arrow_back_rounded, color: ink),
                ),
              ),
              Expanded(
                child: Center(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 28),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const _GuruAvatar(size: 84, glow: true),
                        const SizedBox(height: 26),
                        ShaderMask(
                          shaderCallback: (bounds) => LinearGradient(
                            colors: [accentB, accentA],
                          ).createShader(bounds),
                          child: Text(
                            'Unlock your Super Hero',
                            textAlign: TextAlign.center,
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 26,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'MyAllin1 Super Hero is your always-on assistant for '
                          'Bike, Auto, Cab, Parcel, Mini Truck, Lorry, and SOS — '
                          'plus every other service in the app.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(color: muted, fontSize: 14, height: 1.5),
                        ),
                        const SizedBox(height: 26),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          alignment: WrapAlignment.center,
                          children: _capabilities
                              .map((c) => _CapabilityChip(capability: c))
                              .toList(),
                        ),
                        const SizedBox(height: 30),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: surface,
                            borderRadius: BorderRadius.circular(22),
                            border: Border.all(color: border),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.all(10),
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(colors: [accentA, accentC]),
                                      borderRadius: BorderRadius.all(Radius.circular(14)),
                                    ),
                                    child: const Icon(Icons.support_agent_rounded, color: Colors.white),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Text(
                                      'Call or WhatsApp Admin Support to claim your access. '
                                      'Once activated, your full chat unlocks instantly.',
                                      style: GoogleFonts.outfit(
                                        color: ink,
                                        fontWeight: FontWeight.w600,
                                        fontSize: 13,
                                        height: 1.4,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 16),
                              Row(
                                children: [
                                  Expanded(
                                    child: OutlinedButton.icon(
                                      onPressed: () => unawaited(_callAdmin(context)),
                                      icon: const Icon(Icons.call_rounded, size: 18),
                                      label: const Text('Call'),
                                      style: OutlinedButton.styleFrom(
                                        foregroundColor: ink,
                                        side: BorderSide(color: border),
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    child: ElevatedButton.icon(
                                      onPressed: () => unawaited(_contactAdmin(context)),
                                      icon: const Icon(Icons.chat_rounded, size: 18),
                                      label: const Text('WhatsApp'),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: const Color(0xFF25D366),
                                        foregroundColor: Colors.white,
                                        padding: const EdgeInsets.symmetric(vertical: 14),
                                        shape: RoundedRectangleBorder(
                                          borderRadius: BorderRadius.circular(16),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

// ================================================================
// Pro paywall — shown when a Free-tier customer taps the mic.
// ================================================================
// NEW (Chitti AI upgrade — "Claim My Free Voice Access"): replaced the old
// WhatsApp-upgrade paywall sheet with an honest, one-tap unlock. FIX
// (deliberately NOT built as originally specced): the brief asked for a
// struck-through "₹2000" reference price next to "FREE FOR YOU" — a
// fabricated original price that was never actually charged is a
// deceptive-pricing dark pattern (and risks a real Play Store policy
// strike / Consumer Protection E-Commerce Rules issue in India). This
// version keeps the same "surprise and delight, one big claim button"
// energy without inventing a price that never existed.
class _VoiceClaimSheet extends StatefulWidget {
  const _VoiceClaimSheet();

  @override
  State<_VoiceClaimSheet> createState() => _VoiceClaimSheetState();
}

class _VoiceClaimSheetState extends State<_VoiceClaimSheet> {
  bool _claiming = false;

  Future<void> _claim(BuildContext context) async {
    setState(() => _claiming = true);
    await context.read<AiActivationService>().claimFreeVoiceAccess();
    if (context.mounted) {
      Navigator.of(context).pop(true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.text;
    final muted = context.colors.mutedText;
    final border = context.colors.border;
    final accentA = context.colors.accentSecondary;
    final accentB = context.colors.accent;
    final accentC = context.colors.accentTertiary;
    final surface = context.colors.surface;
    return SafeArea(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(22),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(28),
          border: Border.all(color: border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: [accentC, accentA]),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.mic_rounded, color: Colors.white, size: 30),
            ),
            const SizedBox(height: 16),
            Text(
              'Voice Mode',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: ink, fontSize: 19, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              'Speak your booking — "Book an auto to the railway station" — and '
              'let Super Hero understand and place it for you. It\'s completely '
              'free, one tap away.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: muted, fontSize: 13.5, height: 1.5),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: accentC.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(999),
              ),
              child: Text(
                'FREE • No card, no catch',
                style: GoogleFonts.outfit(color: accentC, fontWeight: FontWeight.w800, fontSize: 12.5),
              ),
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _claiming ? null : () => unawaited(_claim(context)),
                icon: _claiming
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                      )
                    : const Icon(Icons.mic_rounded),
                label: const Text('Claim My Free Voice Access'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentB,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
                ),
              ),
            ),
            const SizedBox(height: 8),
            TextButton(
              onPressed: () => Navigator.of(context).maybePop(),
              child: Text('Maybe later', style: GoogleFonts.outfit(color: muted, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// Small presentational widgets
// ================================================================

class _Capability {
  const _Capability(this.label, this.icon);
  final String label;
  final IconData icon;
}

class _CapabilityChip extends StatelessWidget {
  const _CapabilityChip({required this.capability});
  final _Capability capability;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.text;
    final border = context.colors.border;
    final accentC = context.colors.accentTertiary;
    final surfaceElevated = context.colors.elevatedSurface;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: surfaceElevated,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(capability.icon, size: 15, color: accentC),
          const SizedBox(width: 6),
          Text(
            capability.label,
            style: GoogleFonts.outfit(color: ink, fontSize: 12.5, fontWeight: FontWeight.w700),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_Capability>('capability', capability));
  }
}

class _PromptChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;
  const _PromptChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.text;
    final border = context.colors.border;
    final surface = context.colors.surface;
    return InkWell(
      borderRadius: BorderRadius.circular(20),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
        decoration: BoxDecoration(
          color: surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: border),
        ),
        child: Text(label, style: GoogleFonts.outfit(color: ink, fontSize: 13, fontWeight: FontWeight.w600)),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _VoiceMicButton extends StatefulWidget {
  const _VoiceMicButton({
    required this.isListening,
    required this.isPro,
    required this.onTap,
  });

  final bool isListening;
  final bool isPro;
  final VoidCallback onTap;

  @override
  State<_VoiceMicButton> createState() => _VoiceMicButtonState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('isListening', isListening));
    properties.add(DiagnosticsProperty<bool>('isPro', isPro));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _VoiceMicButtonState extends State<_VoiceMicButton> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1100),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.text;
    final muted = context.colors.mutedText;
    final border = context.colors.border;
    final accentB = context.colors.accent;
    final accentC = context.colors.accentTertiary;
    final surfaceElevated = context.colors.elevatedSurface;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, child) {
        final glow = widget.isListening ? 0.35 + _pulse.value * 0.45 : 0.0;
        return Container(
          width: 46,
          height: 46,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: widget.isListening ? accentC.withValues(alpha: 0.18) : surfaceElevated,
            border: Border.all(
              color: widget.isListening ? accentC : border,
              width: widget.isListening ? 1.6 : 1,
            ),
            boxShadow: widget.isListening
                ? [
                    BoxShadow(
                      color: accentC.withValues(alpha: glow),
                      blurRadius: 18,
                      spreadRadius: 2,
                    ),
                  ]
                : null,
          ),
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                onPressed: widget.onTap,
                icon: Icon(
                  widget.isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                  color: widget.isListening ? accentC : (widget.isPro ? ink : muted),
                  size: 20,
                ),
                padding: EdgeInsets.zero,
              ),
              if (!widget.isPro)
                Positioned(
                  right: 2,
                  top: 2,
                  child: Icon(Icons.workspace_premium_rounded, size: 11, color: accentB),
                ),
            ],
          ),
        );
      },
    );
  }
}

// Assistant replies render as plain text with a small avatar, no
// bubble chrome — matches Claude's mobile-app message style, on the
// new dark backdrop.
class _GuruMessageBubble extends StatelessWidget {
  const _GuruMessageBubble({required this.message, this.onSuggestionTap});

  final _GuruMessage message;
  // NEW (CTO mandate — Suggestion Chips): null for messages rendered
  // where chip taps don't make sense (there are none today, but keeping
  // this optional avoids a required-param ripple if this widget is ever
  // reused read-only elsewhere).
  final ValueChanged<String>? onSuggestionTap;

  @override
  Widget build(BuildContext context) {
    final ink = context.colors.text;
    final border = context.colors.border;
    final surfaceElevated = context.colors.elevatedSurface;
    final userBubble = context.colors.subtleFill;
    final isUser = message.role == 'user';
    if (isUser) {
      return Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(bottom: 18),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 320),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: userBubble,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                // NEW (Chitti AI upgrade, Task 2 — Vision): show the
                // screenshot the customer attached to this message.
                if (message.imageBytes != null) ...[
                  ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: Image.memory(
                      message.imageBytes!,
                      width: 180,
                      fit: BoxFit.cover,
                    ),
                  ),
                  if (message.text.isNotEmpty) const SizedBox(height: 8),
                ],
                if (message.text.isNotEmpty)
                  Text(
                    message.text,
                    style: GoogleFonts.notoSansTamil(color: ink, fontWeight: FontWeight.w500, fontSize: 14.5, height: 1.4),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 22),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GuruAvatar(size: 26),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.text,
                  style: GoogleFonts.notoSansTamil(color: ink, fontWeight: FontWeight.w500, fontSize: 14.5, height: 1.5),
                ),
                // NEW (CTO mandate — Suggestion Chips): clickable quick
                // replies parsed out of the model's [SUGGESTIONS: ...]
                // tag, rendered right below the message they belong to.
                if (message.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 10),
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: message.suggestions
                        .map(
                          (s) => ActionChip(
                            label: Text(s, style: GoogleFonts.outfit(fontSize: 12.5, fontWeight: FontWeight.w600)),
                            backgroundColor: surfaceElevated,
                            side: BorderSide(color: border),
                            labelStyle: TextStyle(color: ink),
                            onPressed: onSuggestionTap == null ? null : () => onSuggestionTap!(s),
                          ),
                        )
                        .toList(),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_GuruMessage>('message', message));
  }
}

class _GuruTypingIndicator extends StatefulWidget {
  const _GuruTypingIndicator();

  @override
  State<_GuruTypingIndicator> createState() => _GuruTypingIndicatorState();
}

class _GuruTypingIndicatorState extends State<_GuruTypingIndicator>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accentC = context.colors.accentTertiary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
      child: Row(
        children: [
          const _GuruAvatar(size: 26),
          const SizedBox(width: 10),
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              return Row(
                mainAxisSize: MainAxisSize.min,
                children: List.generate(3, (index) {
                  final phase = (_controller.value + index * 0.22) % 1;
                  final scale = 0.7 + (phase < 0.5 ? phase : 1 - phase) * 0.8;
                  return Transform.scale(
                    scale: scale,
                    child: Container(
                      width: 6,
                      height: 6,
                      margin: const EdgeInsets.symmetric(horizontal: 2.5),
                      decoration: BoxDecoration(
                        color: accentC.withValues(alpha: 0.5 + scale * 0.3),
                        shape: BoxShape.circle,
                      ),
                    ),
                  );
                }),
              );
            },
          ),
        ],
      ),
    );
  }
}

class _GuruAvatar extends StatelessWidget {
  const _GuruAvatar({required this.size, this.glow = false});

  final double size;
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final accentA = context.colors.accentSecondary;
    final accentB = context.colors.accent;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(
          colors: [accentB, accentA],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: glow
            ? [
                BoxShadow(color: accentA.withValues(alpha: 0.45), blurRadius: 34, spreadRadius: 4),
                BoxShadow(color: accentB.withValues(alpha: 0.3), blurRadius: 18, spreadRadius: 1),
              ]
            : null,
      ),
      child: Icon(Icons.auto_awesome_rounded, color: Colors.white, size: size * 0.5),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('size', size));
    properties.add(FlagProperty('glow', value: glow, ifTrue: 'glow'));
  }
}

// Soft, blurred gradient orbs behind the whole screen — the "glowing
// gradient" backdrop Nizam asked for, Gemini/Claude-app style. Static
// (no animation) to keep it cheap on low-end devices.
class _GlowBackdrop extends StatelessWidget {
  const _GlowBackdrop();

  @override
  Widget build(BuildContext context) {
    final accentA = context.colors.accentSecondary;
    final accentB = context.colors.accent;
    final accentC = context.colors.accentTertiary;
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: -90,
            left: -60,
            child: _GlowOrb(color: accentA, size: 260, opacity: 0.22),
          ),
          Positioned(
            top: 120,
            right: -80,
            child: _GlowOrb(color: accentB, size: 220, opacity: 0.16),
          ),
          Positioned(
            bottom: -100,
            left: 40,
            child: _GlowOrb(color: accentC, size: 240, opacity: 0.14),
          ),
        ],
      ),
    );
  }
}

class _GlowOrb extends StatelessWidget {
  const _GlowOrb({required this.color, required this.size, required this.opacity});

  final Color color;
  final double size;
  final double opacity;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          colors: [color.withValues(alpha: opacity), color.withValues(alpha: 0)],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ColorProperty('color', color));
    properties.add(DoubleProperty('size', size));
    properties.add(DoubleProperty('opacity', opacity));
  }
}

class _GuruMessage {
  const _GuruMessage({
    required this.role,
    required this.text,
    this.imageBytes,
    this.suggestions = const [],
  });

  final String role;
  final String text;
  // NEW (Chitti AI upgrade, Task 2 — Vision): the screenshot the customer
  // attached to THIS message, if any — kept only for local bubble
  // display, never re-sent on later turns (see GuruApiService.sendMessage,
  // which only attaches the image on the request it was picked for).
  final Uint8List? imageBytes;
  // NEW (CTO mandate — Suggestion Chips): quick-reply options parsed out
  // of an assistant reply's [SUGGESTIONS: ...] tag (see
  // guru_suggestion_parser.dart). Always empty for user messages.
  final List<String> suggestions;
}

