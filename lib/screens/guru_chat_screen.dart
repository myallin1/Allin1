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
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart' show ScrollDirection;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image/image.dart' as img;
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:url_launcher/url_launcher.dart';

// GUEST MODE (Aug 11 2026): requireRealAuth() guard on the submit action.
import '../services/ai_activation_service.dart';
import '../services/chitti_chat_history_service.dart';
import '../services/chitti/chitti_action_executor.dart';
import '../services/chitti/chitti_screen_advisor.dart';
import '../services/chitti/chitti_conversation_controller.dart';
import 'mobiles/listing_video_player.dart';
import '../services/chitti/chitti_backup_service.dart';
import '../services/chitti/chitti_buddy.dart';
import '../services/chitti/chitti_chat_intents.dart';
import '../services/chitti/chitti_video_service.dart';
import '../services/chitti/chitti_local_answer_service.dart';
import '../services/chitti/chitti_local_intent_engine.dart';
import '../services/chitti/chitti_screen_tracker.dart';
import '../services/chitti/chitti_voice_service.dart';
import '../services/chitti/chitti_tool_registry.dart';
import '../services/gemini_api_service.dart';
import '../services/grocery_ai_notes_service.dart';
import '../services/guru_api_service.dart';
import '../services/guru_suggestion_parser.dart';
import '../services/localization_service.dart';
import '../widgets/chitti_history_sheet.dart';
import '../widgets/chitti_typewriter_text.dart';
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
import '../services/theme_context_extensions.dart';

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

class _GuruChatScreenState extends State<GuruChatScreen> with WidgetsBindingObserver {
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

  // NEW (Aug 25 2026 — "recognize my FULL sentence, not just the first
  // segment"). See the long comment on _startVoiceSegment() for why
  // this exists: the Android recognizer ends a session on its OWN
  // endpoint detector well before speech_to_text's pauseFor timer would
  // ever fire, so a single .listen() call structurally cannot capture a
  // full sentence with any natural pause in it. This buffers text
  // across multiple auto-restarted segments so the customer experiences
  // one continuous listen, exactly like Google's own Voice Typing.
  String _accumulatedVoiceText = '';
  Timer? _voiceSilenceTimer;
  // True only while WE (not the plugin) intend to keep the mic session
  // going — checked before auto-restarting a segment so a manual stop
  // (tapping the mic again) or dispose() can never race a restart back
  // on.
  bool _voiceSessionActive = false;
  // NEW (Aug 28 2026 — hands-free conversation). The loop's state
  // machine lives in ChittiConversationController, which has no Flutter
  // in it and is unit-tested; this widget only drives the mic and the
  // TTS engine on its instructions.
  final ChittiConversationController _conversation =
      ChittiConversationController();
  // Kept so a resumed listening turn uses the same recogniser
  // locale the session started with.
  String? _conversationLocaleId;
  // The recogniser's other candidate transcriptions for the current
  // segment, and how many segments this session produced — see
  // _handleVoiceUtterance for what they are for.
  List<String> _voiceAlternates = const <String>[];
  int _voiceSegmentCount = 0;

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

  // NEW (Aug 25 2026 — "customer's chat gets deleted on app switch" fix).
  // See chitti_chat_history_service.dart for the full root-cause writeup.
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) => _offerToResumeSavedChat());
  }

  /// Fires on foreground<->background transitions (NOT just app close) —
  /// this is the one hook that reliably runs BEFORE Android has a chance
  /// to kill the process, which dispose() cannot guarantee since a
  /// killed process never runs it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive ||
        state == AppLifecycleState.hidden) {
      _persistChatHistory();
      // Backgrounding is the right moment: the customer is done, the
      // device is least busy, and the chat we just persisted is the
      // freshest thing worth carrying to a new phone. Silent and at
      // most once a day — see maybeAutoBackup.
      unawaited(ChittiBackupService.instance.maybeAutoBackup());
    }
  }

  void _persistChatHistory() {
    if (_messages.isEmpty) return;
    unawaited(ChittiChatHistoryService.saveChat(
      _messages
          .map((m) => <String, dynamic>{
                'role': m.role,
                'text': m.text,
                'suggestions': m.suggestions,
                if (m.videoId != null) 'videoId': m.videoId,
              })
          .toList(),
    ));
  }

  /// Checked once, right after this screen's first frame. Only prompts
  /// when there's a real saved conversation AND the customer hasn't
  /// already started typing/sending in THIS fresh session (covers the
  /// case where GuruChatScreen is kept alive in a background tab via
  /// KeepAliveTab — see dashboard_screen.dart — so this never interrupts
  /// an already-visible, already-in-progress chat).
  Future<void> _offerToResumeSavedChat() async {
    if (!mounted || _messages.isNotEmpty) return;
    final hasSaved = await ChittiChatHistoryService.hasSavedChat();
    if (!hasSaved || !mounted || _messages.isNotEmpty) return;

    final resume = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Continue your chat?'),
        content: const Text(
          "You have a chat with Chitti AI from before you left the app. "
          "Would you like to continue it, or start a new one?",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Start New'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    if (!mounted) return;

    if (resume == true) {
      final saved = await ChittiChatHistoryService.loadSavedChat();
      if (!mounted || saved.isEmpty) return;
      setState(() {
        _messages.addAll(saved.map((m) => _GuruMessage(
              role: m['role'] as String? ?? 'assistant',
              text: m['text'] as String? ?? '',
              suggestions: (m['suggestions'] as List?)?.cast<String>() ?? const [],
              videoId: m['videoId'] as String?,
            )));
      });
      _scrollToBottom();
    } else {
      // Either explicit "Start New" or the dialog was dismissed — either
      // way, don't leave a stale conversation waiting to re-prompt next
      // time the customer opens Chitti.
      unawaited(ChittiChatHistoryService.clear());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _persistChatHistory();
    _api.dispose();
    _inputController.dispose();
    _scrollController.dispose();
    // FIX (Aug 25 2026 — segment chaining): must flip this off BEFORE
    // stopping the mic, or a segment's onResult racing the teardown
    // could still see _voiceSessionActive true and fire
    // _startVoiceSegment() on a disposed screen.
    _voiceSessionActive = false;
    _voiceSilenceTimer?.cancel();
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
      // Language, voice, rate and pitch are all applied together by
      // ChittiVoiceService — they have to be, because on Android a
      // language switch silently drops the selected voice, and on web
      // the engine can reset between utterances.
      await ChittiVoiceService.apply(_tts, locale);
      _ttsReady = true;
    } catch (e) {
      debugPrint('[GuruChatScreen] TTS setup failed: $e');
    }
  }

  // REMOVED (Aug 28 2026): _applyChittiMaleVoice() lived here AND in
  // the other Chitti surface, and both copies searched voice names for
  // the substring "male" — which Google's Android/Chrome voices never
  // contain, so both always fell through to pitching the same female
  // voice down. Voice selection and tone now live in
  // ChittiVoiceService, where the device voice tables, the saved
  // override and the tone profiles are one implementation.

  /// The active language code, or English when the provider is not
  /// reachable — a quip in the wrong language is worse than none.
  String _languageCodeOrEnglish() {
    try {
      return context.read<LocalizationService>().languageCode;
    } catch (_) {
      return 'en';
    }
  }

  Future<void> _speak(String text) async {
    if (!_autoSpeak || text.trim().isEmpty) return;
    try {
      final locale = _languageInfo(context).ttsLocale;
      await _ensureTtsReady(locale);
      if (!_ttsReady) return;
      await _tts.stop();
      // The controller needs to know WHAT is being said (for the echo
      // guard) and WHEN it finishes (to reopen the mic). Without
      // awaitSpeakCompletion the speak() future returns the moment
      // playback starts, and the mic would reopen over Chitti's own
      // voice — the exact loop the echo guard exists to prevent.
      if (_conversation.isActive) {
        _conversation.markSpeaking(text);
        // See guru_overlay_service.dart's twin for the full reasoning:
        // on web the TTS completion callback can simply never fire, and
        // an un-timed await there freezes the conversation loop with no
        // error to show for it.
        await _tts.awaitSpeakCompletion(true);
        try {
          await _tts.speak(text).timeout(const Duration(seconds: 20));
        } on TimeoutException {
          debugPrint('[GuruChatScreen] TTS completion never fired — '
              'continuing the conversation anyway.');
          await _tts.stop();
        }
        if (_conversation.afterSpeaking() == ChittiConversationStep.listen) {
          if (_conversation.hasPendingTopic) {
            final pending = _conversation.popPendingTopic();
            if (pending != null && mounted) {
              final isTamil = context.read<LocalizationService>().languageCode == 'ta';
              final bridgeText = isTamil
                  ? "பாஸ், நீங்க பேசும்போது இன்னொன்னு கேட்டீங்களே: '${pending.text}' — அதை இப்போ பார்க்கிறேன்..."
                  : "Boss, you also asked: '${pending.text}' — checking that now...";
              setState(() {
                _messages.add(_GuruMessage(role: 'assistant', text: bridgeText));
              });
              unawaited(_sendMessage(pending.text));
              return;
            }
          }
          unawaited(_resumeConversationListening());
        }
        return;
      }
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
    // TIER 1 — the on-device intent engine (Aug 28 2026).
    //
    // This replaces the old pre-router, which only understood BOOKING
    // ("book a bike", "auto to Chamunda Spares") and sent everything
    // else to Groq. ChittiLocalIntentEngine covers navigation to all 56
    // sections, every read, cancellations, language switches and the
    // hero/seller toggles too — matched against the same registries the
    // cloud path uses, scored, and acted on only above its confidence
    // threshold.
    //
    // Why this matters beyond speed: it is the answer to "api key limit
    // theenthurum". Everything resolved here costs zero tokens, works
    // with no network, and returns in under a millisecond. Anything it
    // is not sure about falls through to Groq exactly as before — a
    // miss costs latency, never correctness.
    if (pendingImage == null && input.isNotEmpty) {
      final local = ChittiLocalIntentEngine.resolve(input);
      if (local != null) {
        debugPrint(
          '[Chitti] local intent "${local.action}" via "${local.matched}" '
          '(${local.confidence.toStringAsFixed(2)}) — no API call.',
        );
        final acted =
            await _dispatchAgentAction(local.args, source: 'local_engine');
        if (acted) {
          if (mounted) setState(() => _isTyping = false);
          return;
        }
      }
    }

    // TIER 1.5 — answer from the app's own registries (Aug 28 2026).
    //
    // Runs after the intent engine (doing beats explaining) but BEFORE
    // the model, and only when there is no key to reach anyway. With a
    // key, the model handles questions better and gets first refusal.
    //
    // Without one, this is the difference between "what is this page?"
    // getting a real answer and getting "Chitti AI is having a short
    // network pause" — which was never true: the answer was in
    // kChittiSections the whole time.
    // TALK turns are handled whether or not a key exists: a chip Chitti
    // itself offered must always work, and sending "Ask something else"
    // to a language model is a waste of a call either way.
    // Loads once per app run; every later call is a no-op. Needed here
    // so the model path can attach a clip too.
    unawaited(ChittiVideoService.ensureLoaded());

    if (pendingImage == null && input.isNotEmpty) {
      final talk = ChittiChatIntents.handle(
        input,
        languageCode: _languageCodeOrEnglish(),
      );
      if (talk != null) {
        if (!mounted) return;
        setState(() {
          _messages.add(
            _GuruMessage(
              role: 'assistant',
              text: talk.text,
              suggestions: talk.suggestions,
              videoId: talk.videoId,
            ),
          );
          _isTyping = false;
        });
        _scrollToBottom();
        unawaited(_speak(talk.text));
        return;
      }
    }

    if (pendingImage == null && input.isNotEmpty && apiKey.trim().isEmpty) {
      // answerWithScreen, not answer: it is allowed to read the live
      // semantics tree first, which is what lets the reply name the
      // field they still have to fill instead of describing the page
      // back to someone already looking at it.
      final local = await ChittiLocalAnswerService.answerWithScreen(
        input,
        languageCode: _languageCodeOrEnglish(),
      );
      if (local != null) {
        if (!mounted) return;
        setState(() {
          _messages.add(
            _GuruMessage(
              role: 'assistant',
              text: local.text,
              suggestions: local.suggestions,
              videoId: local.videoId,
            ),
          );
          _isTyping = false;
        });
        _scrollToBottom();
        unawaited(_speak(local.text));
        return;
      }
    }

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
      // A reply with no chips is a dead end, and the screenshot Nizam
      // sent was three of them in a row. When the model (or the no-key
      // path) returns none, fall back to the variant's opening chips so
      // there is always a way forward.
      final replySuggestions = parsed.suggestions.isNotEmpty
          ? parsed.suggestions
          : ChittiChatIntents.fallback(
              text: parsed.text,
              languageCode: _languageCodeOrEnglish(),
            ).suggestions;
      // FIX (re-audit): a published clip belongs under a model reply
      // just as much as under a local one. Looking it up only on the
      // no-key path meant the video feature disappeared the moment a
      // customer was activated.
      _messages.add(_GuruMessage(
        role: 'assistant',
        text: parsed.text,
        suggestions: replySuggestions,
        videoId: ChittiVideoService.findFor(input)?.videoId,
      ),);
      _isTyping = false;
    });
    _scrollToBottom();
    unawaited(_speak(parsed.text));
  }

  // NEW (CTO mandate — Co-work Style Confirmation): actually dispatches
  // a previously-confirmed tool call. Mirrors the same switch
  // _tryAgentActionFromText used to run immediately, just deferred
  // until the customer said yes.
  // REWRITTEN (Aug 27 2026): this switch was one of the two places
  // every Chitti tool had to be implemented, and the overlay's copy had
  // already fallen behind it — the overlay could book a ride but not
  // place an order. Everything shared now runs through
  // ChittiActionExecutor, and this method keeps only what is specific
  // to this screen: rendering into _GuruMessage + setState, speaking,
  // scrolling, and pushing on this screen's own Navigator.
  //
  // check_and_update_app and analyze_screen_with_vision stay local —
  // the update flow needs this screen's PWA/native branch mid-flight,
  // and vision needs the attached image bytes that only exist here.
  Future<void> _executePendingAction(Map<String, dynamic> args) async {
    final action = args['action'] as String?;

    if (action == 'check_and_update_app') {
      await _actOnUpdateAction();
      return;
    }
    if (!mounted) return;

    final result = await ChittiActionExecutor.execute(args, context: context);
    if (!mounted) return;

    if (result.text.isNotEmpty) {
      // A light line AFTER the work, sometimes, and never on a serious
      // topic — see chitti_buddy.dart for why the gate is pessimistic.
      final quip = ChittiBuddy.quipAfterAction(
        languageCode: _languageCodeOrEnglish(),
        saying: result.text,
      );
      // The other half of that gate (Aug 29 2026 — Nizam:
      // "customeroda sogam feelinglam purinjukuttu behave pandra
      // buddy"): where the joke gate goes silent, this fills in with
      // warmth instead — a setback still gets acknowledged, never a
      // real emergency.
      final comfort = quip ??
          ChittiBuddy.comfortAfterSetback(
            languageCode: _languageCodeOrEnglish(),
            saying: result.text,
          );
      final text = comfort == null ? result.text : '${result.text} $comfort';
      setState(() {
        _messages.add(
          _GuruMessage(
            role: 'assistant',
            text: text,
            suggestions: result.suggestions,
            videoId: result.videoId,
          ),
        );
      });
      _scrollToBottom();
      // Speak the override when the tool supplied one. Only Thanglish
      // needs it today: the reader sees Latin, but a ta-IN engine can
      // only pronounce the Tamil source — see
      // tamil_transliteration.dart.
      unawaited(_speak(result.spokenTextOverride ?? text));
    }

    // A tool that resolved into another tool still needing a yes
    // (repeat_last_order → create_service_request). Reuses the same
    // confirmation path rather than a second bespoke prompt.
    final pending = result.pendingConfirmAction;
    if (pending != null) {
      _pendingAgentAction = pending;
      final confirmText = _confirmationTextFor(pending);
      setState(() {
        _messages.add(
          _GuruMessage(
            role: 'assistant',
            text: confirmText,
            suggestions: const ['Yes, proceed', 'No, cancel'],
          ),
        );
      });
      _scrollToBottom();
      unawaited(_speak(confirmText));
      return;
    }

    final open = result.openScreen;
    if (open != null && mounted) {
      // Named, so the observer records where Chitti just took them.
      // Unnamed, Chitti would open Food Genie and then not know the
      // customer was on Food Genie — see chitti_screen_tracker.dart.
      unawaited(
        Navigator.of(context).push(
          ChittiNav.routeForBuilder<void>(open, result.openScreenLabel),
        ),
      );
      // NEW (Aug 29 2026 — Nizam: "AI kita command kuduththa antha
      // page ku konduvanthu vittaan, athukapram andha page la yenna
      // pannanum nu next step kettu guidance pannamattranga").
      //
      // ChittiScreenAdvisor already existed to answer exactly this —
      // it reads the live screen (blank fields, buttons, a "GPS slow,
      // set pickup manually" banner) and turns it into a real next
      // step. It was only ever wired to fire when the customer
      // explicitly ASKED "what is this page" — never automatically
      // after Chitti's OWN navigation, which is the one moment it
      // matters most: Chitti put them here, so Chitti owes them the
      // next step, not silence.
      unawaited(_offerScreenGuidanceAfterNavigation());
    }
  }

  /// Speaks (and leaves as a chat message) a proactive next step for
  /// whatever screen Chitti just navigated the customer to.
  ///
  /// Deliberately fire-and-forget and silent on null: most screens
  /// have nothing worth remarking on, and ChittiScreenAdvisor already
  /// returns null for those — see its own restraint reasoning.
  Future<void> _offerScreenGuidanceAfterNavigation() async {
    // Give the new screen a beat to finish building — and, for a
    // screen like bike booking, for its own live state (GPS lock, a
    // pickup banner) to settle, so what gets read is what the
    // customer is actually looking at, not a half-built frame.
    await Future.delayed(const Duration(milliseconds: 900));
    if (!mounted) return;
    final advice = await ChittiScreenAdvisor.adviseOnCurrentScreen();
    if (advice == null || !mounted) return;
    setState(() {
      _messages.add(
        _GuruMessage(
          role: 'assistant',
          text: advice.text,
          suggestions: advice.suggestions,
        ),
      );
    });
    _scrollToBottom();
    unawaited(_speak(advice.text));
  }

  // REMOVED (Aug 27 2026): _actOnBookingAction, _actOnNavigateAction,
  // _actOnGroceryAction, _actOnCreateServiceRequest, _actOnReportBug,
  // _actOnCheckWalletBalance, _actOnCheckOrderStatus, _requestTypeLabel,
  // _screenForSection, _sectionLabel and _voiceServiceFromKey all moved
  // into ChittiActionExecutor / the chitti registries. Every one of them
  // had a near-identical twin in guru_overlay_service.dart, and the two
  // sets had already drifted apart — that drift is what made the
  // floating bubble unable to place orders.

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
      // FIX (Aug 29 2026 — Nizam: "konja chats pannita apram screen
      // top laye iruku, chatscreen swipe pannuna mela pogala").
      //
      // This is called from ~25 places — every send, every reply,
      // every suggestion tap. With no guard, ANY of those firing while
      // someone had scrolled up to reread something yanked them back
      // to the bottom mid-gesture, which feels exactly like "swiping
      // up does nothing". Skipping the auto-scroll while the user's
      // finger is actually on the list lets a real swipe finish
      // instead of being fought by a programmatic one.
      if (_scrollController.position.userScrollDirection !=
          ScrollDirection.idle) {
        return;
      }
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
    // Archive, do NOT clear (Aug 28 2026 — Nizam: "chat ah pakka
    // history oru button"). This used to call clear(), which deleted
    // the conversation outright — so the app whose whole premise is
    // that Chitti remembers you threw that away every time anyone
    // tapped New chat.
    unawaited(ChittiChatHistoryService.archiveCurrentAndStartNew());
  }

  /// Opens the past-chats sheet and, if one is picked, makes it live.
  Future<void> _openHistory() async {
    final picked = await showChittiHistorySheet(context);
    if (!mounted || picked == null || picked.isEmpty) return;
    setState(() {
      _messages
        ..clear()
        ..addAll(picked.map((m) => _GuruMessage(
              role: m['role'] as String? ?? 'assistant',
              text: m['text'] as String? ?? '',
              suggestions:
                  (m['suggestions'] as List?)?.cast<String>() ?? const [],
              videoId: m['videoId'] as String?,
            )));
    });
    _scrollToBottom();
  }

  // -- Voice-to-Order (Pro) ------------------------------------------------

  Future<void> _onMicTapped() async {
    final activation = context.read<AiActivationService>();
    // CHANGED (Aug 28 2026): this used to `return` outright when no API
    // key was activated, so the mic did nothing at all. That is now
    // wrong — since Tier 1, most of what people say by voice
    // ("cancel my order", "wallet balance evlo", "open my orders")
    // resolves entirely on device with no key involved. Typed input
    // already worked without one; the mic being the only gated surface
    // was an inconsistency, not a policy.
    //
    // Anything the local engine cannot handle still needs the model and
    // will say so through the normal reply path, which is the honest
    // place for that message.
    if (!activation.isAiActivated) {
      debugPrint('[GuruChatScreen] no API key — voice runs on Tier 1 only.');
    }

    // NEW (Chitti AI upgrade — "Claim My Free Voice Access"): voice is
    // still free for every activated customer, but the first tap now
    // shows a quick claim sheet instead of unlocking silently — a
    // deliberate small engagement moment, not a real paywall (see
    // AiActivationService.claimFreeVoiceAccess(), persisted locally
    // once tapped). isProUnlocked returns true immediately for anyone
    // who's already claimed it (or been admin-granted real Pro), so
    // this only ever shows once per device.
    // CHANGED (Aug 28 2026): this claim sheet used to block the mic
    // outright until tapped through. Voice now runs on the same
    // on-device engine as typing — gating one input method and not the
    // other was an inconsistency, not a policy. The sheet is still
    // shown once (it is a deliberate engagement moment, per its own
    // note below), but declining it no longer costs the customer the
    // microphone.
    if (!activation.isProUnlocked) {
      // AWAITED, not fire-and-forget (fixed in the Aug 28 re-audit).
      // Unawaited, the mic started listening BEHIND the modal sheet the
      // customer was still reading — recording while they had not even
      // seen the screen yet. The result is ignored on purpose: that is
      // what makes this an engagement moment rather than a gate.
      await _showVoiceClaimSheet();
      if (!mounted) return;
    }
    if (!mounted) return;

    // Manual stop — the customer's own "I'm done" signal, so process
    // whatever was accumulated across segments so far rather than
    // discarding it.
    //
    // In a hands-free session a second tap means "end the whole
    // conversation", not "finish this one sentence" — otherwise the
    // loop would immediately reopen the mic and the tap would look
    // broken.
    if (_isListening) {
      if (_conversation.isActive) {
        _conversation.stop();
        unawaited(_tts.stop());
      }
      _finishVoiceInput();
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        // FIX (Aug 25 2026 — segment chaining): 'notListening'/'done'
        // now fires BETWEEN segments constantly — that's the whole
        // point of auto-restarting, not a real stop. Only reflect it in
        // the UI once we've genuinely finished (_voiceSessionActive
        // false), otherwise the mic icon would flicker off every few
        // seconds even while still actively capturing speech.
        onStatus: (status) {
          if ((status == 'notListening' || status == 'done') &&
              !_voiceSessionActive) {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('[GuruChatScreen] speech error: $error');
          final msg = (error.errorMsg).toLowerCase();
          final isRecoverable = msg.contains('no_match') ||
              msg.contains('timeout') ||
              msg.contains('speech_timeout') ||
              msg.contains('network_timeout') ||
              msg.contains('error_audio') ||
              msg.contains('busy');
          if (isRecoverable && _voiceSessionActive && mounted) {
            debugPrint('[GuruChatScreen] transient speech error "$msg" — auto-recovering listening session');
            Future.delayed(const Duration(milliseconds: 400), () {
              if (_voiceSessionActive && mounted) {
                unawaited(_startVoiceSegment(_conversationLocaleId));
              }
            });
            return;
          }
          _finishVoiceInput();
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
    // REWRITTEN (Aug 28 2026 — Tanglish voice accuracy).
    //
    // Two things were wrong here. First, 'ta' and 'tg' were treated
    // identically and both forced a Tamil recogniser — but 'tg' is
    // TANGLISH, and a customer who picked it has explicitly told us
    // they mix English in ("Bike book pannu", "Wallet balance evlo").
    // A Tamil-constrained model mangles exactly those English words.
    //
    // Second, the previous attempt at a fix set the FALLBACK to 'en-IN'
    // while leaving the loop above it picking the first `ta*` locale.
    // On any device that enumerates its locales — nearly all of them —
    // the loop wins and the fallback never runs, so it changed almost
    // nothing in practice; and on the rare device where it DID fire, it
    // put pure-Tamil speakers onto an English recogniser, which is the
    // bug the comment above was written about.
    //
    // The correct shape is a SPLIT, not a flip: 'ta' keeps Tamil, 'tg'
    // gets Indian English, everyone else keeps the device default. That
    // decision now lives in ChittiVoiceService.speechLocaleFor(), so
    // both Chitti surfaces share it. Device locale ids are still looked
    // up rather than hardcoded — the exact string varies by OEM.
    final languageCode = context.read<LocalizationService>().languageCode;
    String? localeId;
    try {
      final locales = await _speech.locales();
      localeId = ChittiVoiceService.speechLocaleFor(
        languageCode,
        locales.map((l) => l.localeId).toList(growable: false),
      );
    } catch (e) {
      debugPrint('[GuruChatScreen] Could not resolve speech locale: $e');
      localeId =
          ChittiVoiceService.speechLocaleFor(languageCode, const <String>[]);
    }

    // Tapping the mic opens a CONVERSATION, not a single utterance —
    // Chitti keeps listening between its own replies until the job is
    // done, the customer says stop, or (in auto-stop mode) the room
    // goes quiet. See ChittiConversationController.
    _conversation
      ..mode = await ChittiConversationPrefs.load()
      ..start();
    _conversationLocaleId = localeId;

    setState(() {
      _isListening = true;
      _voiceResultHandled = false;
      _accumulatedVoiceText = '';
      _voiceAlternates = const <String>[];
      _voiceSegmentCount = 0;
    });
    _voiceSessionActive = true;
    unawaited(_startVoiceSegment(localeId));
  }

  // FIX (Aug 25 2026 — "Chitti only recognizes ~3.5s, not my full
  // sentence, unlike Google Voice Typing"). ROOT CAUSE, verified against
  // the installed speech_to_text 7.3.0 package source: pauseFor's OWN
  // silence-tracking is implemented correctly (it resets on every real
  // speech event, partial or final — see _notifyResults in that
  // package). The actual limit is one level BELOW this plugin: the
  // native Android speech recognizer has its own built-in endpoint
  // detector that decides "the user stopped talking" and ends the
  // recognition session on its own — often well before our pauseFor
  // duration is ever reached. No pauseFor/listenFor number can fix
  // that, because the OS is the one ending the session, not our timer.
  // Google's own Voice Typing doesn't hit this because it's a
  // first-party component with access to deeper platform APIs this
  // plugin doesn't expose.
  //
  // FIX: when the OS ends a segment early, immediately start another
  // one and stitch the text together — the customer experiences one
  // continuous listen, and OUR OWN _voiceSilenceTimer (reset on every
  // segment's final result) is what actually decides when they're
  // genuinely done, not the OS's shorter per-segment endpointer.
  Future<void> _startVoiceSegment(String? localeId) async {
    if (!mounted || !_voiceSessionActive) return;
    unawaited(
      _speech.listen(
        onResult: (result) {
          if (!_voiceSessionActive) return;
          final words = result.recognizedWords.trim();
          // Live preview of the CURRENT segment appended after whatever
          // was already accumulated, so the customer sees continuous
          // text building up, matching the Google Voice Typing
          // comparison — not just silence until the final chunk lands.
          final preview = _accumulatedVoiceText.isEmpty
              ? words
              : '$_accumulatedVoiceText $words';
          _inputController.text = preview;
          _inputController.selection = TextSelection.collapsed(offset: preview.length);

          if (!result.finalResult) return;

          // ECHO GUARD / BARGE-IN (Aug 28 2026). While Chitti is
          // speaking the mic stays open so the customer can cut in —
          // which also means the mic hears the TTS. Anything that comes
          // back overlapping what Chitti is saying is discarded;
          // anything genuinely different stops Chitti mid-sentence and
          // is treated as the next turn.
          if (_conversation.isSpeaking) {
            if (_conversation.isSelfEcho(words)) return;
            if (_conversation.isStopRequest(words)) {
              unawaited(_tts.stop());
              _conversation.markSpokenDone();
              _finishVoiceInput();
              return;
            }
            _conversation.queuePendingTopic(words);
          }
          if (words.isNotEmpty) {
            _accumulatedVoiceText =
                _accumulatedVoiceText.isEmpty ? words : '$_accumulatedVoiceText $words';
            _voiceSegmentCount++;
            // Keep the recogniser's OTHER candidates for this segment.
            // They are thrown away today, and they are the cheapest
            // accuracy win available: the recogniser ranks by acoustic
            // likelihood and has no idea "wallet balance evlo" is a far
            // more probable sentence in this app than whatever else
            // sounded similar. Only kept for a single-segment utterance
            // — stitching alternates across several segments multiplies
            // out into nonsense, and short commands (which is what these
            // almost always are) arrive in one segment anyway.
            _voiceAlternates = result.alternates
                .map((a) => a.recognizedWords.trim())
                .where((w) => w.isNotEmpty)
                .toList(growable: false);
          }
          // This segment ended (the OS's own endpointer, not genuine
          // "customer is done") — reset OUR silence timer and open the
          // next segment immediately so the mic never actually stops
          // from the customer's perspective.
          _resetVoiceSilenceTimer(localeId);
          if (_voiceSessionActive) {
            unawaited(_startVoiceSegment(localeId));
          }
        },
        localeId: localeId,
        // Unchanged from the original fix: partial results stay off on
        // the PUBLIC API surface (avoids the "word word word" stutter
        // this was fixed for before) — the live preview above is built
        // from final-per-segment results only, not raw partials.
        listenOptions: stt.SpeechListenOptions(
          partialResults: false,
          cancelOnError: true,
          // Stated explicitly (it is already the default) because it is
          // load-bearing and easy to flip by accident: false means the
          // NETWORKED Google recogniser — the same engine Gboard's mic
          // uses. Setting it true would drop us to the on-device model,
          // which is genuinely worse at Tanglish.
          onDevice: false,
        ),
        // Short PER-SEGMENT caps on purpose — we WANT the OS to hand
        // control back to us quickly so we can restart and keep the
        // overall session going; _voiceSilenceTimer below is what
        // actually enforces the customer-facing silence threshold now.
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 6),
      ),
    );
  }

  /// The REAL customer-facing "are they actually done" timer — reset on
  /// every segment's final result, fires only when no new segment has
  /// produced anything for 3.5s straight, which (unlike a single
  /// native session) genuinely spans across the OS's own early cutoffs.
  void _resetVoiceSilenceTimer(String? localeId) {
    _voiceSilenceTimer?.cancel();
    _voiceSilenceTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || !_voiceSessionActive) return;
      _finishVoiceInput();
    });
  }

  /// Guards against a stray extra segment firing after we've already
  /// finished (mirrors the old _voiceResultHandled guard, now scoped to
  /// the whole chained session instead of one .listen() call).
  /// Reopens the mic for the next turn of a hands-free conversation.
  ///
  /// A fresh capture, not a resumed one: the accumulators and the
  /// one-shot _voiceResultHandled guard all have to be cleared or the
  /// second turn would be discarded as a duplicate of the first.
  Future<void> _resumeConversationListening() async {
    if (!mounted || !_conversation.isActive) return;
    setState(() {
      _isListening = true;
      _voiceResultHandled = false;
      _accumulatedVoiceText = '';
      _voiceAlternates = const <String>[];
      _voiceSegmentCount = 0;
    });
    _voiceSessionActive = true;
    await _startVoiceSegment(_conversationLocaleId);
  }

  /// Ends a hands-free session and puts the mic UI back to idle.
  void _endConversation() {
    _conversation.stop();
    _voiceSessionActive = false;
    _voiceSilenceTimer?.cancel();
    unawaited(_speech.stop());
    if (mounted && _isListening) setState(() => _isListening = false);
  }

  void _finishVoiceInput() {
    if (_voiceResultHandled) return;
    _voiceResultHandled = true;
    _voiceSessionActive = false;
    _voiceSilenceTimer?.cancel();
    unawaited(_speech.stop());
    if (mounted) setState(() => _isListening = false);

    final text = _accumulatedVoiceText.trim();
    final alternates = _voiceSegmentCount == 1
        ? _voiceAlternates
        : const <String>[];
    _accumulatedVoiceText = '';
    _voiceAlternates = const <String>[];
    // In a hands-free session even an EMPTY turn matters — two silent
    // turns in a row is one of the ways auto-stop mode ends, so the
    // controller has to see it. Outside a session, the original
    // noise-blip guard applies unchanged.
    if (_conversation.isActive) {
      unawaited(_handleVoiceUtterance(text, alternates: alternates));
      return;
    }
    if (text.length >= 2) {
      unawaited(_handleVoiceUtterance(text, alternates: alternates));
    }
  }

  // REWRITTEN (Aug 28 2026 — Tanglish voice accuracy + Tier 1 for voice).
  //
  // Two problems with the old version. It used _voiceIntent.parse(),
  // which only understands BOOKING — so none of the 56 sections, none
  // of the reads, no cancel and no language switch were reachable by
  // voice at all, only by typing. And it judged the recogniser's first
  // guess alone, discarding the alternates.
  //
  // Now every candidate transcription is tested against the full intent
  // engine and the best confident match wins. Per Nizam's decision, a
  // confident match runs immediately; anything else is left in the
  // input box for the customer to read, fix and send — which is the
  // real advantage Gboard's mic has, and it costs us nothing to match.
  Future<void> _handleVoiceUtterance(
    String utterance, {
    List<String> alternates = const <String>[],
  }) async {
    // Recogniser order, best first, with no duplicates.
    final candidates = <String>[
      utterance,
      ...alternates.where((a) => a != utterance),
    ];

    final intent = ChittiLocalIntentEngine.resolveBest(
      candidates,
      // Someone who tapped the mic and spoke is commanding, not asking
      // — the question guard is for typed text, where a genuine
      // question is far more likely.
      fromVoice: true,
    );

    // A stop word ends the session before anything else is considered —
    // "stop" must work even mid-question, especially mid-question.
    if (_conversation.isActive && _conversation.isStopRequest(utterance)) {
      _endConversation();
      if (!mounted) return;
      setState(() {
        _messages.add(
          const _GuruMessage(role: 'assistant', text: 'Okay boss, stopping.'),
        );
      });
      _scrollToBottom();
      return;
    }

    if (intent != null) {
      debugPrint(
        '[Chitti] voice intent "${intent.action}" via "${intent.matched}" '
        '(${intent.confidence.toStringAsFixed(2)}) from '
        '${candidates.length} candidate(s).',
      );
      _inputController.clear();
      await _dispatchAgentAction(intent.args, source: 'local_engine_voice');
      _continueConversation(utterance, resolvedAnIntent: true);
      return;
    }

    // Nothing matched. In a hands-free session the transcript is sent
    // to the model rather than parked in the input box — the customer
    // is not looking at the screen, so "fix it first" is not an option
    // they can act on. Outside a session, the editable path below
    // stands.
    if (_conversation.isActive) {
      if (utterance.trim().length >= 2) {
        await _sendMessage(utterance);
      }
      _continueConversation(utterance, resolvedAnIntent: false);
      return;
    }

    // Not confident. Leave the transcript in the input box rather than
    // sending it — a wrong transcript sent automatically wastes an API
    // call AND gives the customer an answer to a question they never
    // asked, with no way to see what went wrong.
    if (!mounted) return;
    _inputController.text = utterance;
    _inputController.selection =
        TextSelection.collapsed(offset: utterance.length);
    setState(() {
      _messages.add(
        _GuruMessage(
          role: 'assistant',
          text: 'I heard: "$utterance" — send it, or fix it first.',
          suggestions: const ['Send it', 'Try again'],
        ),
      );
    });
    _scrollToBottom();
  }

  /// Asks the controller what to do after a turn, and does it.
  ///
  /// The "speak" step needs no action here: _speak() already reopens
  /// the mic when it finishes, which is the only correct moment — doing
  /// it from here would race the TTS and reopen the mic over Chitti's
  /// own voice. This exists to cover the turns where Chitti says
  /// nothing at all (a silent navigation, an empty result), which would
  /// otherwise leave a hands-free session hanging with the mic shut.
  void _continueConversation(
    String utterance, {
    required bool resolvedAnIntent,
  }) {
    if (!_conversation.isActive) return;

    final step = _conversation.onUserSaid(
      utterance,
      resolvedAnIntent: resolvedAnIntent,
      // A pending confirmation means Chitti asked something and is
      // waiting — the session must not end underneath that.
      awaitingReply: _pendingAgentAction != null,
    );

    switch (step) {
      case ChittiConversationStep.stop:
        _endConversation();
      case ChittiConversationStep.listen:
        unawaited(_resumeConversationListening());
      case ChittiConversationStep.speak:
        // If Chitti is (or is about to be) speaking, _speak() owns the
        // handoff back to listening. If it never speaks, nothing else
        // would reopen the mic, so do it here.
        if (!_conversation.isSpeaking) {
          unawaited(_resumeConversationListening());
        }
    }
  }

  // REMOVED (Aug 28 2026): _navigateForBookingIntent() was the
  // voice path's own booking-only navigation. Voice now goes through
  // ChittiLocalIntentEngine and the shared dispatcher like everything
  // else, so booking is handled by ChittiActionExecutor with no second
  // copy of the prefill logic.

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
  // ONE WRITE PER ACTIVITY (Aug 28 2026 — Nizam's WhatsApp model:
  // "customer ovvoru interaction um 2 place ah record agum ... one time
  // nadantha activity ah ... summa adikadi database disturb
  // pannakudathu").
  //
  // This used to fire TWICE per action: `intent_requested` the moment
  // Chitti decided, then `intent_resolved` when it finished — two
  // documents for one thing that happened. A thousand customers using
  // Chitti twenty times a day is 40,000 writes against a 20,000/day
  // free quota, and it fired even for the purely on-device Tier 1
  // actions, so the cheapest path in the app was the one paying the
  // database bill.
  //
  // An activity is now recorded ONCE, on completion. That is the record
  // admin needs for history and demand analytics, and the same event
  // the customer's own copy is built from.
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
    return _dispatchAgentAction(args, source: 'groq', imageBytes: imageBytes);
  }

  /// Runs one resolved tool call, wherever it came from.
  ///
  /// NEW (Aug 28 2026 — Tier 1 local intent engine). This used to be
  /// the tail of _tryAgentActionFromText, reachable only after a Groq
  /// round trip. Splitting it out is what lets the on-device engine
  /// feed the SAME confirmation gate, the same executor and the same
  /// analytics — so a locally-resolved action behaves identically to a
  /// model-resolved one, and there is no second code path to keep in
  /// sync. [source] is logged so the local engine's real-world hit rate
  /// is measurable instead of guessed at.
  Future<bool> _dispatchAgentAction(
    Map<String, dynamic> args, {
    required String source,
    Uint8List? imageBytes,
  }) async {
    final resolvedArgs = args;
    final action = resolvedArgs['action'] as String?;
    // REPLACED (Aug 27 2026): a hand-maintained allow-list that had to
    // be extended for every new tool, in this file AND again in
    // guru_overlay_service.dart. The registry is now the one place that
    // decides what is real and what this app variant may run.
    if (!ChittiToolRegistry.isKnownAction(action) ||
        !ChittiToolRegistry.isAllowedFor(action)) {
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
      await _actOnVisionHandoffAction(imageBytes);
      unawaited(_logGuruAnalyticsEvent(
        eventType: 'intent_resolved',
        action: action,
        args: <String, dynamic>{...resolvedArgs, 'source': source},
        resolved: true,
      ));
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
    // Confirm-or-not is now a property of the tool itself
    // (ChittiTool.requiresConfirmation) rather than a list of names
    // repeated here and in the overlay. Per Nizam: confirm ONLY for
    // money and cancellations — everything else, including bug reports
    // and every read, runs immediately.
    if (!ChittiToolRegistry.requiresConfirmation(action)) {
      if (!mounted) return true;
      unawaited(_logGuruAnalyticsEvent(
        eventType: 'intent_resolved',
        action: action,
        args: <String, dynamic>{...resolvedArgs, 'source': source},
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
  // REWRITTEN (Aug 27 2026): only reached for tools the registry marks
  // requiresConfirmation — money and cancellations. Every other action
  // now executes immediately, so the old per-action previews for
  // navigation, grocery notes and update checks were dead text.
  //
  // The wording names exactly what is about to happen, because this is
  // the last checkpoint before a real charge or an irreversible cancel.
  String _confirmationTextFor(Map<String, dynamic> args) {
    switch (args['action'] as String?) {
      case 'create_service_request':
        final items = (args['items'] as String?)?.trim() ?? 'your request';
        final vendor = (args['vendor'] as String?)?.trim();
        final label = ChittiActionExecutor.requestTypeLabel(
          args['request_type'] as String?,
        );
        return vendor != null && vendor.isNotEmpty
            ? 'I\'ll place a $label for "$items" from $vendor and send it to '
                'nearby Heroes — should I proceed?'
            : 'I\'ll place a $label for "$items" and send it to nearby '
                'Heroes — should I proceed?';
      case 'cancel_order':
        return 'I\'ll cancel your current order — this cannot be undone. '
            'Should I go ahead?';
      case 'book_transport':
        final dest = (args['destination'] as String?)?.trim();
        return dest != null && dest.isNotEmpty
            ? 'Shall I set up that booking to $dest again?'
            : 'Shall I set up that booking again?';
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
      // CHANGED (Aug 28 2026 — Nizam: "offline Chitti setting la
      // kaaturan but avana use pannapona call admin nu varuthu").
      //
      // This used to replace the ENTIRE chat with the "contact Admin
      // Support" screen whenever no API key was provisioned. That made
      // sense when Chitti could do nothing without a key. Since Tier 1
      // it is simply false: 20 of the 25 tools — all navigation, every
      // balance and status read, cancel, repeat, language — resolve on
      // device with no key and no network call at all. Blocking the
      // whole screen hid a working assistant behind a phone number.
      //
      // The activation flow is NOT deleted (Nizam: "feature remove
      // pannama"). _SuperHeroActivationScreen is still routed, now from
      // the banner below, so anyone who wants the full model-backed
      // Chitti can still reach it in one tap.
      body: SafeArea(
              child: Stack(
                children: [
                  const _GlowBackdrop(),
                  Column(
                    children: [
                      _buildAppBar(context, activation),
                      if (!activation.isAiActivated) _buildOfflineBanner(),
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
          // Sits next to New chat on purpose: New chat is what files a
          // conversation away, so this is where someone looks for it.
          IconButton(
            onPressed: _openHistory,
            tooltip: 'Past chats',
            icon: Icon(Icons.history_rounded, color: muted),
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

  /// Shown when no API key is provisioned.
  ///
  /// Deliberately a slim banner and not a wall: everything Tier 1
  /// handles works right now, and the honest message is "most of this
  /// works, here is how to unlock the rest" — not "call an admin before
  /// you may use the app".
  Widget _buildOfflineBanner() {
    final accent = context.colors.accent;
    final muted = context.colors.mutedText;
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 4, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: accent.withValues(alpha: 0.22)),
      ),
      child: Row(
        children: [
          Icon(Icons.offline_bolt_rounded, size: 18, color: accent),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Running on-device. Bookings, balances and navigation all '
              'work. Unlock full AI chat for the rest.',
              style: GoogleFonts.outfit(
                fontSize: 11.5,
                height: 1.35,
                color: muted,
              ),
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const _SuperHeroActivationScreen(),
              ),
            ),
            child: Text(
              'Unlock',
              style: GoogleFonts.outfit(
                fontSize: 12,
                fontWeight: FontWeight.w800,
                color: accent,
              ),
            ),
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
        key: ValueKey('guru_msg_$index'),
        message: _messages[index],
        onSuggestionTap: _onSuggestionTapped,
        animateReveal: index == _messages.length - 1 && !_isTyping,
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
            const SizedBox(height: 6),
            Text(
              'Chitti can make mistakes — double-check anything important.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: muted,
                fontSize: 10.5,
                height: 1.2,
              ),
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
  const _GuruMessageBubble({
    super.key,
    required this.message,
    this.onSuggestionTap,
    this.animateReveal = false,
  });

  final _GuruMessage message;
  // NEW (CTO mandate — Suggestion Chips): null for messages rendered
  // where chip taps don't make sense (there are none today, but keeping
  // this optional avoids a required-param ripple if this widget is ever
  // reused read-only elsewhere).
  final ValueChanged<String>? onSuggestionTap;

  /// True only for the reply that just arrived (Aug 29 2026 — Nizam:
  /// "ovvoru work ah type aguramari"). Every other bubble — history
  /// loaded on resume, older messages scrolled back to — shows its
  /// full text immediately; nobody wants to watch yesterday's answer
  /// "type" itself out again.
  final bool animateReveal;

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
          // REDESIGNED (Aug 31 2026 — Nizam: "chitti chat section
          // cute-a detailed-a venum", referencing the Claude mobile
          // app's own layout).
          //
          // The Aug 29 pass shrank everything to fix "huge-a iruku",
          // and overshot: 13.5px at 1.4 line-height in a 280px box is
          // dense to read, especially in Tamil where glyphs are taller
          // than Latin. The Claude app's chat reads well because it is
          // ROOMY, not because it is small — generous padding, a soft
          // radius, and type sized for actual reading. That is what
          // these numbers copy. Still safe across mobile/web/PWA for
          // the same reason as before: Text wraps within the available
          // width, and maxWidth stays a constraint, so nothing here
          // can overflow a narrow screen.
          padding: const EdgeInsets.only(bottom: 20),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 300),
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
            decoration: BoxDecoration(
              color: userBubble,
              // Claude's user bubble is a soft pill, not a card — no
              // hard outline competing with the text inside it.
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: border.withValues(alpha: 0.5)),
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
                    style: GoogleFonts.notoSansTamil(
                      color: ink,
                      // w500 rather than w600: at this size the heavier
                      // weight reads as shouting, and Tamil glyphs are
                      // already visually denser than Latin at the same
                      // weight.
                      fontWeight: FontWeight.w500,
                      fontSize: 15,
                      height: 1.5,
                    ),
                  ),
              ],
            ),
          ),
        ),
      );
    }

    return Padding(
      // CHANGED (Aug 29 2026 — Nizam: "fonts, text, chat box yellame
      // huge ah iruku, cute ah ila"). Trimmed the avatar, spacing and
      // font down a notch. Shrinking is the safe direction across
      // mobile/web/PWA — Text already wraps within the available
      // width, so a smaller font only ever reduces overflow risk.
      padding: const EdgeInsets.only(bottom: 24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const _GuruAvatar(size: 28),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Typewriter reveal — only the reply that just
                // arrived; see the `animateReveal` note above.
                ChittiTypewriterText(
                  message.text,
                  animate: animateReveal,
                  // Chitti's own replies are the longest text on this
                  // screen and the most likely to be read while
                  // walking or riding, so they get the roomiest
                  // line-height of anything here.
                  style: GoogleFonts.notoSansTamil(
                    color: ink,
                    fontWeight: FontWeight.w500,
                    fontSize: 15,
                    height: 1.6,
                  ),
                ),
                // NEW (CTO mandate — Suggestion Chips): clickable quick
                // replies parsed out of the model's [SUGGESTIONS: ...]
                // tag, rendered right below the message they belong to.
                // NEW (Aug 28 2026): a video Chitti referenced, shown
                // the same way Rewards shows one — a stretched
                // thumbnail with a play badge, opening the shared modal
                // player on tap.
                //
                // A THUMBNAIL, not an inline iframe, and that is
                // deliberate. The player is a platform view; under
                // CanvasKit (this app's web renderer) every platform
                // view splits the compositing scene, and putting one
                // inside a scrolling chat list would do that on every
                // frame of every scroll. The Rewards page already made
                // this call for the same reason — see the lazy-player
                // note in rewards_hub_screen.dart.
                if (message.videoId != null) ...[
                  const SizedBox(height: 10),
                  _ChittiVideoCard(videoId: message.videoId!),
                ],
                if (message.suggestions.isNotEmpty) ...[
                  const SizedBox(height: 14),
                  Wrap(
                    spacing: 9,
                    runSpacing: 9,
                    children: message.suggestions
                        .map(
                          (s) => ActionChip(
                            label: Text(s, style: GoogleFonts.outfit(fontSize: 13, fontWeight: FontWeight.w600)),
                            backgroundColor: surfaceElevated,
                            side: BorderSide(color: border.withValues(alpha: 0.6)),
                            labelStyle: TextStyle(color: ink),
                            // Softer pill + a real touch target: these
                            // are tapped one-handed, often in motion.
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(18),
                            ),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 8,
                            ),
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
// gradient" backdrop Nizam asked for, Gemini/Claude-app style.
//
// CHANGED (Aug 29 2026 — Nizam: "background la color animation la run
// agitrukatum but battery waste agama cache la run pannavachuru"). This
// used to be fully static — a deliberate choice at the time to keep it
// cheap on low-end devices. The brief now explicitly asks for it to
// move, WITHOUT paying for that in battery, so the shape of the fix
// matters as much as the motion itself:
//
//   - ONE AnimationController for the whole backdrop — one Ticker, not
//     three.
//   - Each orb is built ONCE (the three `final` widgets below, built
//     outside the animated builder) and wrapped in a RepaintBoundary.
//     That is the actual "cache": the expensive part — a large blurred
//     radial gradient — is rasterised to its own GPU layer a single
//     time, and every subsequent frame only recomposites that existing
//     layer at a new offset via Transform.translate. No gradient is
//     ever redrawn per frame.
//   - A slow 14s period and a small 14-20px drift radius mean each
//     frame's real work is a sub-pixel offset change on an already-
//     cached layer — the cheapest form of "alive" this backdrop can be.
class _GlowBackdrop extends StatefulWidget {
  const _GlowBackdrop();

  @override
  State<_GlowBackdrop> createState() => _GlowBackdropState();
}

class _GlowBackdropState extends State<_GlowBackdrop>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 14),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  static Widget _cached(Widget orb) => RepaintBoundary(child: orb);

  @override
  Widget build(BuildContext context) {
    final orbA = _cached(
      _GlowOrb(color: context.colors.accentSecondary, size: 260, opacity: 0.22),
    );
    final orbB = _cached(
      _GlowOrb(color: context.colors.accent, size: 220, opacity: 0.16),
    );
    final orbC = _cached(
      _GlowOrb(color: context.colors.accentTertiary, size: 240, opacity: 0.14),
    );

    return IgnorePointer(
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          // Each orb drifts on its own phase/radius so the three never
          // move in lockstep — that is what reads as "alive" rather
          // than as one thing sliding.
          final t = _controller.value * 2 * math.pi;
          Offset drift(double phase, double radius) => Offset(
                math.cos(t + phase) * radius,
                math.sin(t + phase) * radius * 0.6,
              );

          return Stack(
            children: [
              Positioned(
                top: -90,
                left: -60,
                child: Transform.translate(offset: drift(0, 18), child: orbA),
              ),
              Positioned(
                top: 120,
                right: -80,
                child: Transform.translate(offset: drift(2.1, 16), child: orbB),
              ),
              Positioned(
                bottom: -100,
                left: 40,
                child: Transform.translate(offset: drift(4.2, 20), child: orbC),
              ),
            ],
          );
        },
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

/// A video Chitti referenced, as a tappable card in the chat.
///
/// Styled from `context.colors` rather than hard-coded values so it
/// follows the app's theme and the pink/white switch automatically.
class _ChittiVideoCard extends StatelessWidget {
  const _ChittiVideoCard({required this.videoId});

  final String videoId;

  @override
  Widget build(BuildContext context) {
    final border = context.colors.border;
    return GestureDetector(
      onTap: () => showPremiumVideoModal(
        context,
        videoId: videoId,
        title: 'Chitti suggests',
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(14),
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: border),
            borderRadius: BorderRadius.circular(14),
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                // The free hqdefault endpoint — no API key, one image,
                // cached by the browser/OS. Same source Rewards uses.
                VideoThumbnail(videoId: videoId),
                Container(color: Colors.black.withValues(alpha: 0.25)),
                Center(
                  child: Container(
                    width: 46,
                    height: 46,
                    decoration: const BoxDecoration(
                      color: Color(0xFFFF0000),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.play_arrow_rounded,
                      color: Colors.white,
                      size: 30,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GuruMessage {
  const _GuruMessage({
    required this.role,
    required this.text,
    this.imageBytes,
    this.suggestions = const [],
    this.videoId,
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

  /// A YouTube video referenced by this reply, shown as a tappable
  /// card. Tapping opens the SAME modal player the Rewards page uses —
  /// one player, one set of playback bugs, one place to fix them.
  final String? videoId;
}

