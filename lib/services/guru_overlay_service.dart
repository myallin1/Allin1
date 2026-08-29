// ================================================================
// GuruOverlayService — Global "Quick Task" floating AI assistant
// ================================================================
// NEW (CTO mandate — "Quick Task Global AI Overlay / Masterstroke UX"):
// Guru used to live only inside GuruChatScreen, a full-screen route that
// disappears the moment the customer navigates away. This service keeps
// a compact chat panel alive as a single root-level OverlayEntry so it
// travels with the customer across every screen (Home, Grocery, Bike
// Booking, etc.) exactly like the CTO described a "Cowork/Quick Task"
// assistant should.
//
// Architecture (reported to Nizam before this was written, per his
// explicit request):
//   - Singleton ChangeNotifier holding the entry + chat state, so state
//     survives even if the overlay widget itself gets rebuilt/replaced.
//   - Inserted via the app's existing root `navigatorKey`
//     (app_navigator.dart) — `navigatorKey.currentState!.overlay!` gives
//     a real OverlayState with zero BuildContext plumbing required from
//     wherever `show()` is called (a FAB living in MaterialApp.builder
//     sits ABOVE the Navigator in the tree, so it has no Overlay
//     ancestor of its own — going through navigatorKey sidesteps that
//     entirely, same trick the update-flow dialogs already use via
//     `Navigator.of(context, rootNavigator: true)`).
//   - `rootOverlay` is implicit here since navigatorKey's own overlay
//     IS the root app overlay (this app has no nested Navigators above
//     it), so the entry always renders above every pushed screen.
//   - Reuses GuruApiService.sendMessage directly (not the full
//     GuruChatScreen widget, which is tightly coupled to voice capture,
//     image attachment, and full-screen layout) for a lightweight
//     text-only compact experience, matching the "compact, floating
//     panel, not full screen" requirement.
//   - Close button always confirms via a dialog before removing the
//     entry, exactly per the CTO's specified copy.
import 'dart:async' show Timer, TimeoutException, unawaited;

import 'chitti_chat_history_service.dart';
import '../widgets/chitti_history_sheet.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../app_navigator.dart';
// NOTE (Aug 27 2026): the thirteen screen imports that used to sit
// here went with _screenForSection(). Navigation targets now live in
// chitti_section_registry.dart, so this service no longer has to import
// every screen Chitti might open — which is also why adding a section
// no longer means touching this file.
// currentAppVariant — GlobalGuruFab gates Chitti's visibility on it.
import '../config/app_variant.dart';
import 'ai_activation_service.dart';
import 'guru_api_service.dart';
import 'guru_suggestion_parser.dart';
import 'localization_service.dart';
// NEW (CTO mandate — Final Overlay Tool Wiring): same conditional
// stub/web import used everywhere else in the codebase so the overlay's
// own check_and_update_app execution reuses the exact one real
// implementation instead of a second copy.
import 'pwa_cache_platform_stub.dart'
    if (dart.library.html) 'pwa_cache_platform_web.dart';
import 'voice_booking_intent_service.dart';
import 'web_version_checker.dart';
import '../screens/mobiles/listing_video_player.dart';
import '../widgets/ai_bot_avatar.dart';
import '../widgets/chitti_companion.dart';
import 'chitti/chitti_action_executor.dart';
import 'chitti/chitti_conversation_controller.dart';
import 'chitti/chitti_buddy.dart';
import 'chitti/chitti_chat_intents.dart';
import 'chitti/chitti_video_service.dart';
import 'chitti/chitti_local_answer_service.dart';
import 'chitti/chitti_local_intent_engine.dart';
import 'chitti/chitti_screen_tracker.dart';
import 'chitti/chitti_voice_service.dart';
import 'chitti/chitti_tool_registry.dart';

/// The floating panel's fixed size. Named because the positioning
/// clamp has to agree with the actual box — they were two independent
/// magic numbers before, which is how the clamp came to be wrong.
const double _kPanelWidth = 320;
const double _kPanelHeight = 420;

class GuruChatTurn {
  const GuruChatTurn({
    required this.role,
    required this.text,
    this.suggestions = const [],
    this.videoId,
  });
  final String role; // 'user' | 'assistant'
  final String text;

  /// A YouTube video referenced by this reply — rendered as a tappable
  /// card that opens the same modal player the Rewards page uses.
  final String? videoId;
  // NEW (CTO mandate — Suggestion Chips): quick-reply options parsed
  // out of an assistant reply's [SUGGESTIONS: ...] tag.
  final List<String> suggestions;
}

class GuruOverlayService extends ChangeNotifier {
  GuruOverlayService._();
  static final GuruOverlayService instance = GuruOverlayService._();

  final GuruApiService _api = GuruApiService();
  // NEW (CTO mandate — Text-to-Speech): shared TTS engine for the
  // overlay panel, mirroring guru_chat_screen.dart's own instance.
  final FlutterTts _tts = FlutterTts();
  // NEW (CTO mandate — Final Overlay Tool Wiring): the same
  // regex-based service/destination parser guru_chat_screen.dart uses,
  // reused here purely for its VoiceService display-name helpers and
  // classifyYesNo() — not for local voice parsing, since the overlay's
  // mic goes straight into the same Groq tool-calling path as typed
  // text (see _GuruOverlayPanelState._onMicResult below).
  final VoiceBookingIntentService _voiceIntent = VoiceBookingIntentService();
  // NEW: the tool-call args Groq extracted but hasn't been executed
  // yet, pending the customer's explicit yes/no — exact same
  // human-in-the-loop gate as guru_chat_screen.dart's
  // _pendingAgentAction, just living on the service instead of a
  // State so it survives across screens like everything else here.
  Map<String, dynamic>? _pendingAgentAction;

  /// Guards against stacked close confirmations — see [requestClose].
  bool _closeDialogOpen = false;

  // NEW (Aug 28 2026 — hands-free conversation in the bubble too).
  //
  // The controller sits on the SERVICE rather than the panel widget on
  // purpose: this bubble is global and survives navigation, and a
  // conversation that ended because the customer happened to change
  // screens mid-sentence would be exactly the wrong behaviour.
  //
  // It also has to live here because TTS lives here while the mic lives
  // in the panel — the "Chitti finished speaking, reopen the mic"
  // handoff crosses that boundary, and [onConversationWantsMic] is how.
  final ChittiConversationController conversation =
      ChittiConversationController();

  /// Set by the panel while it is mounted. Null means there is no mic
  /// to reopen, which is a normal state (bubble minimised or closed),
  /// not an error.
  VoidCallback? onConversationWantsMic;
  final List<GuruChatTurn> messages = [];

  // ── CONTINUE / NEW / HISTORY (Aug 28 2026 — Nizam: "chitti ku
  // customer app mari admin kum continue & new chat option kudu") ──
  //
  // The overlay is what the ADMIN, HERO and SELLER builds actually
  // use — the full chat screen is customer-only. It never persisted
  // anything, so closing the panel destroyed the conversation
  // outright: an admin who worked through a problem with Chitti and
  // then closed the bubble had no way back to any of it. The full
  // chat screen has had continue-or-new since launch; these three
  // builds simply never got it.
  //
  // Same store as the customer screen, so a conversation looks the
  // same wherever it is opened from and rides the Drive backup once.

  bool _restoredThisSession = false;

  /// Whether the "continue or new?" prompt has already been answered.
  ///
  /// Deliberately separate from [_restoredThisSession]. They used to
  /// be one flag, and startNewChat() resets that one — which "Start
  /// New" on the prompt itself calls. So answering the prompt re-armed
  /// it, and the next panel rebuild asked again, and again.
  bool _resumePromptAnswered = false;

  /// Whether an earlier conversation is waiting to be resumed.
  Future<bool> hasSavedChat() => ChittiChatHistoryService.hasSavedChat();

  /// Writes the current conversation to disk.
  ///
  /// Fire-and-forget by contract: a save failure must never interrupt
  /// a reply that has already been shown.
  void persist() {
    unawaited(
      ChittiChatHistoryService.saveChat(
        messages
            .map((m) => <String, dynamic>{
                  'role': m.role,
                  'text': m.text,
                  'suggestions': m.suggestions,
                  if (m.videoId != null) 'videoId': m.videoId,
                })
            .toList(),
      ),
    );
  }

  /// Loads the saved conversation into the panel.
  Future<void> restoreSavedChat() async {
    final saved = await ChittiChatHistoryService.loadSavedChat();
    if (saved.isEmpty) return;
    messages
      ..clear()
      ..addAll(saved.map(_turnFromMap));
    _restoredThisSession = true;
    notifyListeners();
  }

  /// Files the current conversation away and clears the panel.
  ///
  /// Archives rather than deletes — see chitti_history_sheet.dart.
  Future<void> startNewChat() async {
    persist();
    await ChittiChatHistoryService.archiveCurrentAndStartNew();
    messages.clear();
    _restoredThisSession = false;
    notifyListeners();
  }

  /// Makes an archived conversation the live one.
  void applySession(List<Map<String, dynamic>> turns) {
    if (turns.isEmpty) return;
    messages
      ..clear()
      ..addAll(turns.map(_turnFromMap));
    notifyListeners();
  }

  /// True once the resume prompt has been answered, so it is not
  /// offered twice.
  bool get alreadyRestored => _resumePromptAnswered;

  /// Marks the resume prompt as answered, whichever way it went.
  void markResumeHandled() => _resumePromptAnswered = true;

  static GuruChatTurn _turnFromMap(Map<String, dynamic> m) => GuruChatTurn(
        role: (m['role'] as String?) ?? 'assistant',
        text: (m['text'] as String?) ?? '',
        suggestions: (m['suggestions'] as List?)?.cast<String>() ?? const [],
        videoId: m['videoId'] as String?,
      );
  OverlayEntry? _entry;
  bool _sending = false;
  bool _minimized = false;
  bool _autoSpeak = true;
  Offset _position = const Offset(16, 120);

  bool get isShowing => _entry != null;
  bool get isSending => _sending;
  bool get isMinimized => _minimized;
  bool get autoSpeak => _autoSpeak;
  Offset get position => _position;

  // NEW (per Nizam's request — "AI button single tap ku mic connect
  // pannividu"): one-shot flag consumed by _GuruOverlayPanelState right
  // after it mounts, so a single tap on the FAB both opens the panel
  // AND starts listening immediately — no second tap on the inner mic
  // icon needed. Reset back to false the instant it's consumed.
  bool _autoStartMicOnOpen = false;
  bool consumeAutoStartMic() {
    final value = _autoStartMicOnOpen;
    _autoStartMicOnOpen = false;
    return value;
  }

  void toggleAutoSpeak() {
    _autoSpeak = !_autoSpeak;
    if (!_autoSpeak) unawaited(_tts.stop());
    notifyListeners();
  }

  // NEW (CTO mandate — Deep Language Sync): same label/locale mapping
  // as guru_chat_screen.dart's _languageInfo(), duplicated rather than
  // shared since this service has no BuildContext of its own except
  // via navigatorKey.currentContext, and the mapping is a couple of
  // lines either way.
  ({String label, String ttsLocale}) _languageInfo() {
    final ctx = navigatorKey.currentContext;
    String code = 'en';
    if (ctx != null) {
      try {
        code = ctx.read<LocalizationService>().languageCode;
      } catch (_) {
        // Provider not reachable -- fall back to English.
      }
    }
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

  Future<void> _speak(String text) async {
    if (!_autoSpeak || text.trim().isEmpty) return;
    try {
      final locale = _languageInfo().ttsLocale;
      await ChittiVoiceService.apply(_tts, locale);
      await _tts.stop();
      // In a hands-free session the mic reopens only once playback has
      // genuinely finished — awaitSpeakCompletion is what makes the
      // future wait for that. Reopening earlier would put the mic over
      // Chitti's own voice, which is the loop the echo guard exists to
      // prevent (see chitti_conversation_controller.dart).
      if (conversation.isActive) {
        conversation.markSpeaking(text);
        // FIX (Aug 28 2026 — Nizam: "voice typing la ... hang aguran").
        //
        // awaitSpeakCompletion(true) makes speak() resolve only when
        // playback finishes, which is what the loop needs. But on web
        // flutter_tts does not reliably fire that completion, and when
        // it does not, this future NEVER resolves — the mic is never
        // reopened and the whole conversation freezes with no error.
        // That is the hang, and it only appears on the PWA, which is
        // why it looked intermittent.
        //
        // The timeout is a ceiling, not a guess at speech length:
        // Chitti's replies are capped at two short sentences, so 20s is
        // far beyond any real utterance. Whatever happens, the mic
        // reopens.
        await _tts.awaitSpeakCompletion(true);
        try {
          await _tts.speak(text).timeout(const Duration(seconds: 20));
        } on TimeoutException {
          debugPrint('[GuruOverlayService] TTS completion never fired — '
              'continuing the conversation anyway.');
          await _tts.stop();
        }
        if (conversation.afterSpeaking() == ChittiConversationStep.listen) {
          onConversationWantsMic?.call();
        }
        return;
      }
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[GuruOverlayService] TTS failed: $e');
    }
  }

  // REMOVED (Aug 28 2026): _applyChittiMaleVoice() lived here AND in
  // the other Chitti surface, and both copies searched voice names for
  // the substring "male" — which Google's Android/Chrome voices never
  // contain, so both always fell through to pitching the same female
  // voice down. Voice selection and tone now live in
  // ChittiVoiceService, where the device voice tables, the saved
  // override and the tone profiles are one implementation.

  void setPosition(Offset offset) {
    _position = offset;
    notifyListeners();
  }

  void toggleMinimized() {
    _minimized = !_minimized;
    notifyListeners();
  }

  /// Inserts the single global overlay entry. Safe to call repeatedly —
  /// a second call while already showing just brings it back from
  /// minimized instead of inserting a duplicate entry.
  void show({bool autoStartMic = false}) {
    if (autoStartMic) _autoStartMicOnOpen = true;
    if (_entry != null) {
      if (_minimized) {
        _minimized = false;
        // Re-open from minimised is exactly when something else has
        // usually been shown on top in the meantime.
        bringToFront();
      } else if (autoStartMic) {
        // Already open and expanded — still honor the mic request by
        // notifying so the panel's build picks up consumeAutoStartMic().
        notifyListeners();
      }
      return;
    }
    _entry = OverlayEntry(
      builder: (_) => const _GuruOverlayPanel(),
    );
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      // Navigator not mounted yet (very early cold boot) -- give up
      // quietly rather than throw; the FAB simply won't have opened
      // anything this tap, and the next tap will work once it's ready.
      _entry = null;
      return;
    }
    overlay.insert(_entry!);
    // Offer to pick up where they left off (Aug 28 2026 — Nizam:
    // "admin kum continue & new chat option kudu").
    //
    // Fired HERE, from show(), and not from the panel's initState.
    // The panel is rebuilt whenever the overlay entry is lifted, so an
    // initState trigger fires again on every lift — and since the
    // dialog is itself a route, opening it caused a lift, which
    // rebuilt the panel, which opened it again. That was the stack of
    // prompts that could not be dismissed. show() runs exactly once
    // per open, which is what "per panel session" actually means.
    unawaited(_offerToResume());
    // Re-lift on every subsequent route push, so the panel does not end
    // up underneath a screen or dialog opened while it is showing.
    ChittiOverlayLift.onRoutePushed = () {
      if (_entry != null && !_minimized) bringToFront();
    };
    notifyListeners();
  }

  /// Lifts the panel back above anything inserted after it.
  ///
  /// FIX (Aug 28 2026 — Nizam: the popup "city popup ku mela kaatama
  /// ... kela kaathu"). Overlay entries stack in insertion order, and
  /// this one is inserted once, early. Every dialog and route shown
  /// afterwards goes in ABOVE it, so the panel ends up underneath them
  /// — which looks like it opened behind the app.
  ///
  /// Position was never the problem, so moving the panel would not have
  /// fixed it. Removing and re-inserting puts it back on top, which is
  /// the only thing that does.
  void bringToFront() {
    final entry = _entry;
    if (entry == null) return;
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) return;

    // Re-entrancy guard. remove()+insert() rebuilds the panel, whose
    // initState can open a dialog, which pushes a route, which lands
    // back here. Without this the recursion is unbounded — the
    // "multiple screens opening" and the stack of close prompts.
    if (_lifting) return;
    _lifting = true;
    try {
      entry.remove();
      overlay.insert(entry);
      notifyListeners();
    } finally {
      _lifting = false;
    }
  }

  /// True while a lift is in progress. See [bringToFront].
  bool _lifting = false;

  /// Shows the CTO-mandated confirmation dialog, then removes the entry
  /// only if the customer confirms.
  ///
  /// FIX (Aug 28 2026 — Nizam: "close amuthuna multiple close dialog
  /// open agite iruku"). showDialog() is awaited, but nothing stopped a
  /// SECOND call while the first was still open — and the close button
  /// sits under a person's thumb, so a double tap stacked two dialogs,
  /// a triple tap three. Dismissing one then revealed the next, which
  /// reads as the app refusing to close.
  /// "Continue your chat, or start new?" — the same choice the full
  /// customer chat screen has always offered.
  ///
  /// Only when the panel is genuinely empty: asking mid-conversation
  /// would be an interruption. Answered once per open, whichever way
  /// it goes.
  Future<void> _offerToResume() async {
    if (_resumePromptAnswered || messages.isNotEmpty) return;
    if (!await hasSavedChat()) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null || _entry == null) return;

    // Set BEFORE the await, not after: two lifts can land here in the
    // same frame, and both would pass a check made afterwards.
    _resumePromptAnswered = true;

    final resume = await showDialog<bool>(
      context: ctx,
      // Dismissable, unlike the customer screen's version. The panel
      // can be rebuilt underneath this, and a barrier that cannot be
      // tapped away turns any stray second dialog into a dead end.
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Continue your chat?',
          style: GoogleFonts.outfit(
            color: const Color(0xFF4A1236),
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Text(
          'You have an earlier chat with Chitti. Continue it, or start a '
          'new one? Either way the old chat is kept under Past chats.',
          style: GoogleFonts.outfit(
            color: const Color(0xFF8A4E72),
            fontSize: 13.5,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text(
              'Start New',
              style: TextStyle(color: Color(0xFF8A4E72)),
            ),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text(
              'Continue',
              style: TextStyle(color: Color(0xFFFF4FA3)),
            ),
          ),
        ],
      ),
    );

    if (resume == true) {
      await restoreSavedChat();
    } else if (resume == false) {
      // "Start new" ARCHIVES, never deletes — the dialog above
      // promises the old chat is kept. A dismissed dialog (null)
      // touches nothing.
      await startNewChat();
    }
  }

  Future<void> requestClose() async {
    if (_closeDialogOpen) return;
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      _forceClose();
      return;
    }
    _closeDialogOpen = true;
    try {
      final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Close Chitti AI?',
          style: GoogleFonts.outfit(color: const Color(0xFF4A1236), fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to close Chitti AI?',
          style: GoogleFonts.outfit(color: const Color(0xFF8A4E72), fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Color(0xFF8A4E72))),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Close', style: TextStyle(color: Color(0xFFFF4FA3))),
          ),
        ],
      ),
    );
      if (confirmed == true) {
        _forceClose();
      }
    } finally {
      // finally, not a plain assignment after the await: a dismissed
      // route or a torn-down context throws out of showDialog, and a
      // flag left true would disable the close button for good.
      _closeDialogOpen = false;
    }
  }

  void _forceClose() {
    // Closing the panel ends the session, so the next open may ask
    // again. Nothing else re-arms it.
    _resumePromptAnswered = false;
    ChittiOverlayLift.onRoutePushed = null;
    _entry?.remove();
    _entry = null;
    notifyListeners();
  }

  String _resolveApiKey() {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) return '';
    try {
      return ctx.read<AiActivationService>().apiKey;
    } catch (_) {
      return '';
    }
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    messages.add(GuruChatTurn(role: 'user', text: trimmed));
    _sending = true;
    notifyListeners();

    final apiKey = _resolveApiKey();

    // NEW (CTO mandate — Final Overlay Tool Wiring): if a tool call is
    // awaiting confirmation, this message IS the yes/no answer — never
    // re-run agent-action extraction on it. Exact same gate as
    // guru_chat_screen.dart's _sendMessage.
    if (_pendingAgentAction != null) {
      final decision = _voiceIntent.classifyYesNo(trimmed);
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
        _sending = false;
        notifyListeners();
        return;
      } else if (decision == VoiceYesNo.no) {
        _pendingAgentAction = null;
        unawaited(_logGuruAnalyticsEvent(
          eventType: 'intent_resolved',
          action: pending['action'] as String?,
          args: pending,
          resolved: false,
        ));
        messages.add(const GuruChatTurn(role: 'assistant', text: 'Okay, cancelled — let me know if you need anything else.'));
        _sending = false;
        notifyListeners();
        return;
      }
      // Unclear -- drop the stale pending action, fall through and
      // treat this as a brand-new message instead.
      _pendingAgentAction = null;
    }

    // TIER 1 — the on-device intent engine (Aug 28 2026).
    //
    // Mirrors guru_chat_screen.dart exactly; see that file for the
    // reasoning. This replaces the old pre-router, which understood
    // booking and nothing else. Anything resolved here costs zero
    // tokens and works with no network at all — which is most of what
    // the floating bubble gets asked to do.
    if (trimmed.isNotEmpty) {
      final local = ChittiLocalIntentEngine.resolve(trimmed);
      if (local != null) {
        debugPrint(
          '[Chitti] local intent "${local.action}" via "${local.matched}" '
          '(${local.confidence.toStringAsFixed(2)}) — no API call.',
        );
        final acted =
            await _dispatchAgentAction(local.args, source: 'local_engine');
        if (acted) {
          _sending = false;
          notifyListeners();
          return;
        }
      }
    }

    // TIER 1.5 — see guru_chat_screen.dart's twin for the reasoning.
    // Only when there is no key: with one, the model answers better.
    unawaited(ChittiVideoService.ensureLoaded());

    // TALK turns work with or without a key — see the twin in
    // guru_chat_screen.dart.
    final talk = ChittiChatIntents.handle(
      trimmed,
      languageCode: _languageInfo().label == 'Tamil' ? 'ta' : 'en',
    );
    if (talk != null) {
      messages.add(GuruChatTurn(
        role: 'assistant',
        text: talk.text,
        suggestions: talk.suggestions,
        videoId: talk.videoId,
      ),);
      _sending = false;
      notifyListeners();
      unawaited(_speak(talk.text));
      persist();
      return;
    }

    if (apiKey.trim().isEmpty) {
      final local = await ChittiLocalAnswerService.answerWithScreen(
        trimmed,
        languageCode: _languageInfo().label == 'Tamil' ? 'ta' : 'en',
      );
      if (local != null) {
        messages.add(
          GuruChatTurn(
            role: 'assistant',
            text: local.text,
            suggestions: local.suggestions,
          ),
        );
        _sending = false;
        notifyListeners();
        unawaited(_speak(local.text));
        persist();
        return;
      }
    }

    // NEW (CTO mandate — Final Overlay Tool Wiring): same Groq
    // function-calling attempt guru_chat_screen.dart makes before
    // falling back to plain chat, so the overlay can book rides and
    // navigate the app too, not just talk about them.
    final acted = await _tryAgentActionFromText(trimmed, apiKey);
    if (acted) {
      _sending = false;
      notifyListeners();
      return;
    }

    final history = messages
        .map((m) => {'role': m.role, 'content': m.text})
        .toList(growable: false);

    try {
      final rawReply = await _api.sendMessage(
        message: trimmed,
        history: history,
        apiKeyOverride: apiKey,
        languageLabel: _languageInfo().label,
      );
      final parsed = GuruSuggestionParser.parse(rawReply);
      final replySuggestions = parsed.suggestions.isNotEmpty
          ? parsed.suggestions
          : ChittiChatIntents.fallback(
              text: parsed.text,
              languageCode: _languageInfo().label == 'Tamil' ? 'ta' : 'en',
            ).suggestions;
      // See the twin in guru_chat_screen.dart: a clip belongs under a
      // model reply too, not only under a local one.
      messages.add(GuruChatTurn(
        role: 'assistant',
        text: parsed.text,
        suggestions: replySuggestions,
        videoId: ChittiVideoService.findFor(trimmed)?.videoId,
      ),);
      unawaited(_speak(parsed.text));
      persist();
    } catch (e) {
      messages.add(
        const GuruChatTurn(
          role: 'assistant',
          text: 'Chitti AI is temporarily unavailable. Please try again shortly.',
        ),
      );
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  // NEW (CTO mandate — Final Overlay Tool Wiring): asks Groq whether
  // this text is a clear booking/navigation/update request; if so,
  // stores it as the pending action and posts a confirmation message
  // with Yes/No chips instead of executing immediately. Mirrors
  // guru_chat_screen.dart's _tryAgentActionFromText exactly, adapted to
  // this service's ChangeNotifier-based state instead of setState.
  /// Whether a tool call is waiting on the customer's yes/no. The
  /// hands-free loop must never end while one is outstanding.
  bool get hasPendingAgentAction => _pendingAgentAction != null;

  /// Cuts Chitti off mid-sentence (barge-in), and tells the controller
  /// so the echo guard stops filtering.
  Future<void> stopSpeaking() async {
    conversation.markSpokenDone();
    await _tts.stop();
  }

  /// Runs a tool call the on-device engine resolved from speech.
  ///
  /// Separate from sendMessage() on purpose: the utterance never
  /// becomes a chat message and never reaches Groq, because the intent
  /// is already known. Exposed here because the voice capture lives in
  /// the panel widget, which has no access to the private dispatcher.
  Future<void> runVoiceIntent(Map<String, dynamic> args) =>
      _dispatchAgentAction(args, source: 'local_engine_voice');

  /// Posts an assistant turn from outside this class — used by the
  /// voice path to show a transcript the engine was not confident
  /// about, so the customer can correct it instead of having it sent
  /// blind.
  void addAssistantTurn(String text, {List<String> suggestions = const []}) {
    messages.add(
      GuruChatTurn(role: 'assistant', text: text, suggestions: suggestions),
    );
    notifyListeners();
  }

  Future<bool> _tryAgentActionFromText(String input, String apiKey) async {
    if (input.isEmpty) return false;
    Map<String, dynamic>? args;
    try {
      args = await _api.extractAgentAction(message: input, apiKeyOverride: apiKey);
    } catch (e) {
      debugPrint('[GuruOverlayService] extractAgentAction failed: $e');
    }
    if (args == null) return false;
    return _dispatchAgentAction(args, source: 'groq');
  }

  /// Runs one resolved tool call, wherever it came from — the local
  /// engine or Groq. Mirrors guru_chat_screen.dart's dispatcher; see
  /// that file for why this is split out. [source] is logged so the
  /// local engine's hit rate is measurable rather than guessed at.
  Future<bool> _dispatchAgentAction(
    Map<String, dynamic> args, {
    required String source,
  }) async {
    final action = args['action'] as String?;
    // REPLACED (Aug 27 2026 — Nizam: "a to z namma app la yenna
    // sonnalum avan panna therila").
    //
    // THIS LIST WAS THE BUG. It named six actions while the model was
    // being offered nine, so create_service_request, report_app_bug and
    // analyze_screen_with_vision were described to the model, correctly
    // called by it, and then dropped right here — the customer got a
    // paragraph instead of an order. book_transport happened to be in
    // the list, which is exactly why the agent felt like it only
    // understood taxi and transport.
    //
    // The allow-list now comes from ChittiToolRegistry, the same source
    // that builds the tool schemas, so the two can no longer disagree.
    if (!ChittiToolRegistry.isKnownAction(action) ||
        !ChittiToolRegistry.isAllowedFor(action)) {
      return false;
    }

    // NEW (CTO mandate — "Autonomous Interaction Rule"): mirrors
    // guru_chat_screen.dart's identical change exactly — confirmation
    // gates removed for every action except Scenario A (final
    // payment/booking confirmation, which lives entirely on the
    // destination screen's own Confirm button / SOS's KYC gate, both
    // untouched) and Scenario B (genuine ambiguity, handled via
    // suggestion chips in the plain-chat fallback, not this gate).
    //
    // UPDATED (Aug 27 2026): the confirm-or-not decision is now a
    // property of the tool itself (ChittiTool.requiresConfirmation)
    // rather than a list of action names repeated here and in
    // guru_chat_screen.dart. Per Nizam: confirm ONLY for money and for
    // cancellations — create_service_request and cancel_order today.
    // The Scenario-A path below is therefore genuinely reached now,
    // not dead defensive code.
    if (!ChittiToolRegistry.requiresConfirmation(action)) {
      final logArgs = <String, dynamic>{...args, 'source': source};
      unawaited(_logGuruAnalyticsEvent(eventType: 'intent_resolved', action: action, args: logArgs, resolved: true));
      await _executePendingAction(args);
      return true;
    }

    _pendingAgentAction = args;
    messages.add(
      GuruChatTurn(
        role: 'assistant',
        text: _confirmationTextFor(args),
        suggestions: const ['Yes, proceed', 'No, cancel'],
      ),
    );
    notifyListeners();
    unawaited(_speak(_confirmationTextFor(args)));
    return true;
  }

  // NEW (CTO mandate — Admin AI Co-Pilot Foundation, Option 1: Analytics
  // Logging): mirrors guru_chat_screen.dart's _logGuruAnalyticsEvent
  // exactly, adapted to this service having no BuildContext of its own
  // (uses the existing no-context _languageInfo() this service already
  // has, same as its languageLabel usage in sendMessage() above). Purely
  // additive — does not alter any existing method's behavior or
  // signature.
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
      final languageLabel = _languageInfo().label;
      await FirebaseFirestore.instance.collection('guru_analytics').add(<String, dynamic>{
        'customerId': uid,
        'source': 'overlay',
        'eventType': eventType,
        'intent': action,
        if (args?['section'] != null) 'section': args!['section'],
        if (args?['service'] != null) 'serviceType': args!['service'],
        if (resolved != null) 'resolved': resolved,
        if (languageLabel.isNotEmpty) 'languageUsed': languageLabel,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[GuruOverlayService] analytics log failed: $e');
    }
  }

  // Only reached for tools ChittiToolRegistry marks
  // requiresConfirmation — money and cancellations. The wording names
  // exactly what is about to happen, because this is the last checkpoint
  // before a real charge or an irreversible cancel.
  String _confirmationTextFor(Map<String, dynamic> args) {
    switch (args['action'] as String?) {
      case 'create_service_request':
        final items = (args['items'] as String?)?.trim() ?? 'your request';
        final vendor = (args['vendor'] as String?)?.trim();
        final label =
            ChittiActionExecutor.requestTypeLabel(args['request_type'] as String?);
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

  // REWRITTEN (Aug 27 2026): this switch used to be the overlay's own
  // half-copy of guru_chat_screen.dart's handlers, and every tool the
  // chat screen gained had to be remembered here separately — which is
  // exactly how the overlay ended up unable to place orders.
  //
  // Now every shared tool runs through ChittiActionExecutor, and this
  // method only does what is genuinely overlay-specific: render the
  // result into GuruChatTurns and push on navigatorKey. The single
  // exception is check_and_update_app, whose PWA-vs-native branch needs
  // this class's own message plumbing mid-flight.
  Future<void> _executePendingAction(Map<String, dynamic> args) async {
    final action = args['action'] as String?;

    if (action == 'check_and_update_app') {
      await _actOnUpdateAction();
      return;
    }

    final context = navigatorKey.currentContext;
    if (context == null) {
      // No mounted Navigator (very early cold boot). Saying nothing is
      // right here — the overlay is not visible yet either.
      debugPrint('[GuruOverlayService] no context for "$action"');
      return;
    }

    final result = await ChittiActionExecutor.execute(args, context: context);

    if (result.text.isNotEmpty) {
      final quip = ChittiBuddy.quipAfterAction(
        languageCode: _languageInfo().label == 'Tamil' ? 'ta' : 'en',
        saying: result.text,
      );
      final text = quip == null ? result.text : '${result.text} $quip';
      messages.add(
        GuruChatTurn(
          role: 'assistant',
          text: text,
          suggestions: result.suggestions,
          videoId: result.videoId,
        ),
      );
      notifyListeners();
      persist();
      // Same read-vs-speak split as the full chat screen: Thanglish is
      // shown in Latin but must be spoken in Tamil to pronounce.
      unawaited(_speak(result.spokenTextOverride ?? text));
    }

    // A tool that resolved into another tool needing a yes (today:
    // repeat_last_order → create_service_request). Routed through the
    // same confirmation path a directly-called write tool uses, rather
    // than a second bespoke prompt.
    final pending = result.pendingConfirmAction;
    if (pending != null) {
      _pendingAgentAction = pending;
      messages.add(
        GuruChatTurn(
          role: 'assistant',
          text: _confirmationTextFor(pending),
          suggestions: const ['Yes, proceed', 'No, cancel'],
        ),
      );
      notifyListeners();
      unawaited(_speak(_confirmationTextFor(pending)));
      return;
    }

    final open = result.openScreen;
    if (open != null) {
      final navState = navigatorKey.currentState;
      if (navState != null) {
        unawaited(navState.push(
          ChittiNav.routeForBuilder<void>(open, result.openScreenLabel),
        ),);
      }
    }
  }

  Future<void> _actOnUpdateAction() async {
    if (!kIsWeb) {
      messages.add(
        const GuruChatTurn(
          role: 'assistant',
          text: "You're on the app store build — updates install automatically in the background, nothing to trigger here.",
        ),
      );
      notifyListeners();
      return;
    }

    messages.add(const GuruChatTurn(role: 'assistant', text: 'Checking for an update...'));
    notifyListeners();

    try {
      await WebVersionChecker.instance.checkNow();
    } catch (e) {
      debugPrint('[GuruOverlayService] update check failed: $e');
    }

    if (!WebVersionChecker.instance.isUpdateAvailable) {
      messages.add(const GuruChatTurn(role: 'assistant', text: "You're already on the latest version!"));
      notifyListeners();
      return;
    }

    messages.add(const GuruChatTurn(role: 'assistant', text: 'Found a new version — updating now, the app will refresh in a moment...'));
    notifyListeners();

    try {
      await PwaCachePlatform().clearAndReload();
    } catch (e) {
      debugPrint('[GuruOverlayService] update apply failed: $e');
      messages.add(const GuruChatTurn(role: 'assistant', text: "The update didn't go through — please try again from the side menu."));
      notifyListeners();
    }
  }

  // REMOVED (Aug 27 2026): _screenForSection(), _sectionLabel() and
  // _voiceServiceFromKey() lived here as a 12-entry copy of the same
  // switches in guru_chat_screen.dart. Both are now single entries in
  // chitti_section_registry.dart / chitti_action_executor.dart, which is
  // what let the section list grow past those 12 without having to be
  // typed out three times.
}

// ================================================================
// Global "Ask Guru" trigger — a subtle FAB meant to be laid over
// MaterialApp's `child` via its `builder:` callback so it appears on
// every screen with zero per-screen wiring.
// ================================================================
class GlobalGuruFab extends StatelessWidget {
  const GlobalGuruFab({super.key});

  // FIX (Aug 25 2026 — "two Chitti icons on APK"). ChittiCompanion
  // (chitti_overlay_service.dart) is mounted unconditionally from
  // dashboard_screen.dart's initState for the customer app, and it
  // actually shows itself only when ChittiCompanion.isSupported
  // (Android native, never web — see that class's own gate and
  // reasoning). Nobody suppressed THIS fab when the companion was
  // added, so on Android both stacked on screen at once; on web only
  // this one ever rendered, since the companion no-ops there. Mirrors
  // the exact condition that determines whether the companion actually
  // shows, so hero/seller/admin (which never call
  // ChittiOverlayService.show() at all) are completely unaffected —
  // this only hides the FAB where the companion has genuinely taken
  // its place.
  static bool _chittiCompanionOwnsThisScreen() =>
      currentAppVariant == 'customer' && ChittiCompanion.isSupported;

  @override
  Widget build(BuildContext context) {
    if (_chittiCompanionOwnsThisScreen()) return const SizedBox.shrink();

    // REMOVED (Aug 28 2026): this hid the Chitti FAB completely in the
    // Hero and Seller apps whenever no API key was provisioned.
    //
    // Since Tier 1 that is backwards. A Hero's most-used requests —
    // today's earnings, go online/offline, active job, wallet balance —
    // are ALL resolved on device with no key and no network. Hiding the
    // button meant the one group who works out of the app all day, on
    // patchy mobile data, could not reach any of it.
    //
    // _isGatedApp() went with it — it had no other caller.

    return AnimatedBuilder(
      animation: GuruOverlayService.instance,
      builder: (context, _) {
        // Hide the launcher FAB while the panel itself is open/expanded
        // so they don't visually stack on top of each other.
        if (GuruOverlayService.instance.isShowing &&
            !GuruOverlayService.instance.isMinimized) {
          return const SizedBox.shrink();
        }
        return Positioned(
          right: 14,
          bottom: 90,
          child: SafeArea(
            child: GestureDetector(
              onTap: () => GuruOverlayService.instance.show(autoStartMic: true),
              child: const AiBotAvatar(
                // CHANGED (Aug 25 2026 — Super Chitti Phase 2, "Floating
                // Icon Size Bump"): 64 -> 66, exact +2.0pt per request.
                // AiBotAvatar drives both the image width/height AND its
                // fallback Icon's size off this one `size` param (see
                // ai_bot_avatar.dart), so this single change covers both.
                size: 66,
                fallbackColor: Color(0xFFFF4FA3),
              ),
            ),
          ),
        );
      },
    );
  }
}

// ================================================================
// The compact, draggable floating panel itself.
// ================================================================
class _GuruOverlayPanel extends StatefulWidget {
  const _GuruOverlayPanel();

  @override
  State<_GuruOverlayPanel> createState() => _GuruOverlayPanelState();
}

class _GuruOverlayPanelState extends State<_GuruOverlayPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();
  // NEW (CTO mandate — Final Overlay Tool Wiring, "tap the overlay mic"):
  // its own SpeechToText instance, same finalResult-only + 5s pauseFor
  // patience settings as guru_chat_screen.dart's mic (see task #155),
  // and the same language-locale resolution used there.
  final stt.SpeechToText _speech = stt.SpeechToText();
  bool _speechReady = false;
  bool _isListening = false;
  bool _voiceResultHandled = false;
  // NEW (Aug 25 2026 — segment chaining, mirrors guru_chat_screen.dart's
  // mic exactly; see that file's _startVoiceSegment() for the full
  // root-cause writeup on why a single .listen() call structurally
  // cannot capture one full sentence).
  String _accumulatedVoiceText = '';
  Timer? _voiceSilenceTimer;
  bool _voiceSessionActive = false;
  // Other candidate transcriptions for the current segment, and how
  // many segments this session produced — see _finishVoiceInput.
  List<String> _voiceAlternates = const <String>[];
  int _voiceSegmentCount = 0;
  // Reused so a resumed turn keeps the recogniser locale the
  // session started with.
  String? _conversationLocaleId;

  @override
  void initState() {
    super.initState();
    // FIX (per Nizam's request — single-tap-to-listen): if the FAB
    // requested auto-mic, kick off listening right after this panel's
    // first frame (can't call it synchronously in initState — mic
    // permission/speech init needs a real BuildContext + widget tree).
    if (GuruOverlayService.instance.consumeAutoStartMic()) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_onMicTapped());
      });
    }
    // The service owns the conversation loop and the TTS; the mic lives
    // here in the panel. This is the handoff back: when Chitti finishes
    // speaking, the service asks for the mic again.
    GuruOverlayService.instance.onConversationWantsMic = () {
      if (mounted) unawaited(_resumeConversationListening());
    };

  }

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    // Must flip off BEFORE stopping the mic — same ordering reason as
    // guru_chat_screen.dart's dispose().
    _voiceSessionActive = false;
    GuruOverlayService.instance
      ..onConversationWantsMic = null
      ..conversation.stop();
    _voiceSilenceTimer?.cancel();
    if (_isListening) {
      unawaited(_speech.stop());
    }
    super.dispose();
  }

  Future<void> _onMicTapped() async {
    // Manual stop — process whatever was accumulated rather than
    // discarding it. A second tap during a hands-free session means
    // "end the conversation", not "finish this sentence", or the loop
    // would reopen the mic and the tap would look broken.
    if (_isListening) {
      final service = GuruOverlayService.instance;
      if (service.conversation.isActive) {
        service.conversation.stop();
      }
      _finishVoiceInput();
      return;
    }

    if (!_speechReady) {
      _speechReady = await _speech.initialize(
        // FIX (Aug 25 2026 — segment chaining): only reflect
        // 'notListening'/'done' in the UI once genuinely finished — it
        // now fires between auto-restarted segments constantly.
        onStatus: (status) {
          if ((status == 'notListening' || status == 'done') &&
              !_voiceSessionActive) {
            if (mounted) setState(() => _isListening = false);
          }
        },
        onError: (error) {
          debugPrint('[GuruOverlayService] speech error: $error');
          _finishVoiceInput();
        },
      );
    }
    if (!_speechReady || !mounted) return;

    // UPDATED (Aug 28 2026): 'ta' and 'tg' used to be treated as the
    // same thing and both forced a Tamil recogniser — but 'tg' is
    // Tanglish, and a Tamil-only model mangles the English half of
    // "Bike book pannu". See ChittiVoiceService.speechLocaleFor() for
    // why this is a split and not a blanket switch to en-IN.
    String? localeId;
    try {
      final code = context.read<LocalizationService>().languageCode;
      final locales = await _speech.locales();
      localeId = ChittiVoiceService.speechLocaleFor(
        code,
        locales.map((l) => l.localeId).toList(growable: false),
      );
    } catch (e) {
      debugPrint('[GuruOverlayService] locale resolve failed: $e');
    }

    // Tapping the mic opens a conversation, not one utterance.
    GuruOverlayService.instance.conversation
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

  /// See guru_chat_screen.dart's _startVoiceSegment() for the full
  /// root-cause writeup — same mechanism, mirrored here.
  Future<void> _startVoiceSegment(String? localeId) async {
    if (!mounted || !_voiceSessionActive) return;
    unawaited(
      _speech.listen(
        onResult: (result) {
          if (!_voiceSessionActive) return;
          final words = result.recognizedWords.trim();
          if (!result.finalResult) return;

          // Echo guard / barge-in — see the matching block in
          // guru_chat_screen.dart and RULE 1 in
          // chitti_conversation_controller.dart.
          final convo = GuruOverlayService.instance.conversation;
          if (convo.isSpeaking) {
            if (convo.isSelfEcho(words)) return;
            unawaited(GuruOverlayService.instance.stopSpeaking());
          }
          if (words.isNotEmpty) {
            _accumulatedVoiceText =
                _accumulatedVoiceText.isEmpty ? words : '$_accumulatedVoiceText $words';
            _voiceSegmentCount++;
            // The recogniser's other candidates — see the matching
            // comment in guru_chat_screen.dart for why these are worth
            // keeping and why only single-segment utterances use them.
            _voiceAlternates = result.alternates
                .map((a) => a.recognizedWords.trim())
                .where((w) => w.isNotEmpty)
                .toList(growable: false);
          }
          _resetVoiceSilenceTimer();
          if (_voiceSessionActive) {
            unawaited(_startVoiceSegment(localeId));
          }
        },
        localeId: localeId,
        // onDevice: false is the default, stated explicitly because
        // it is load-bearing — false means the NETWORKED Google
        // recogniser, the same engine Gboard's mic uses. True would
        // drop to the on-device model, which is worse at Tanglish.
        listenOptions: stt.SpeechListenOptions(
          partialResults: false,
          cancelOnError: true,
          onDevice: false,
        ),
        // Short per-segment caps — see guru_chat_screen.dart's identical
        // comment: we WANT the OS to hand control back quickly so we can
        // restart; _voiceSilenceTimer is what enforces the real
        // customer-facing silence threshold now.
        listenFor: const Duration(seconds: 12),
        pauseFor: const Duration(seconds: 6),
      ),
    );
  }

  void _resetVoiceSilenceTimer() {
    _voiceSilenceTimer?.cancel();
    _voiceSilenceTimer = Timer(const Duration(milliseconds: 3500), () {
      if (!mounted || !_voiceSessionActive) return;
      _finishVoiceInput();
    });
  }

  void _finishVoiceInput() {
    if (_voiceResultHandled) return;
    _voiceResultHandled = true;
    _voiceSessionActive = false;
    _voiceSilenceTimer?.cancel();
    unawaited(_speech.stop());
    if (mounted) setState(() => _isListening = false);

    final text = _accumulatedVoiceText.trim();
    final alternates =
        _voiceSegmentCount == 1 ? _voiceAlternates : const <String>[];
    _accumulatedVoiceText = '';
    _voiceAlternates = const <String>[];

    final service = GuruOverlayService.instance;
    final convo = service.conversation;

    // A stop word ends the session before anything else is considered.
    if (convo.isActive && convo.isStopRequest(text)) {
      convo.stop();
      unawaited(service.stopSpeaking());
      service.addAssistantTurn('Okay boss, stopping.');
      return;
    }

    // In a hands-free session even an EMPTY turn matters — two silent
    // turns is one of the ways auto-stop mode ends.
    if (text.length < 2) {
      if (convo.isActive) _continueConversation(text, resolvedAnIntent: false);
      return;
    }

    // UPDATED (Aug 28 2026): the transcript used to go straight to
    // sendMessage(). Now every candidate transcription is tested
    // against the on-device intent engine first — a confident match
    // runs immediately, and anything else lands in the input box for
    // the customer to read and fix rather than being sent blind.
    final intent = ChittiLocalIntentEngine.resolveBest(
      <String>[text, ...alternates.where((a) => a != text)],
      fromVoice: true,
    );
    if (intent != null) {
      _controller.clear();
      unawaited(service.runVoiceIntent(intent.args));
      _continueConversation(text, resolvedAnIntent: true);
      return;
    }

    // Nothing matched. Hands-free, the customer is not looking at the
    // screen, so parking the text for them to fix is useless — send it
    // to the model instead. Outside a session, the editable path holds.
    if (convo.isActive) {
      unawaited(service.sendMessage(text));
      _continueConversation(text, resolvedAnIntent: false);
      return;
    }

    _controller.text = text;
    _controller.selection = TextSelection.collapsed(offset: text.length);
    service.addAssistantTurn(
      'I heard: "$text" — send it, or fix it first.',
      suggestions: const <String>['Send it', 'Try again'],
    );
  }

  /// Reopens the mic for the next turn.
  Future<void> _resumeConversationListening() async {
    if (!mounted || !GuruOverlayService.instance.conversation.isActive) return;
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

  /// Asks the controller what happens after a turn and does it. See the
  /// twin in guru_chat_screen.dart for why the "speak" step is a no-op
  /// here: _speak() owns the handoff back to listening.
  void _continueConversation(
    String utterance, {
    required bool resolvedAnIntent,
  }) {
    final service = GuruOverlayService.instance;
    final convo = service.conversation;
    if (!convo.isActive) return;

    final step = convo.onUserSaid(
      utterance,
      resolvedAnIntent: resolvedAnIntent,
      awaitingReply: service.hasPendingAgentAction,
    );

    switch (step) {
      case ChittiConversationStep.stop:
        convo.stop();
        _voiceSessionActive = false;
        _voiceSilenceTimer?.cancel();
        unawaited(_speech.stop());
        if (mounted && _isListening) setState(() => _isListening = false);
      case ChittiConversationStep.listen:
        unawaited(_resumeConversationListening());
      case ChittiConversationStep.speak:
        if (!convo.isSpeaking) unawaited(_resumeConversationListening());
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final service = GuruOverlayService.instance;
    final size = MediaQuery.of(context).size;

    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (service.isMinimized) {
          return Positioned(
            right: 14,
            bottom: 90,
            child: SafeArea(
              child: GestureDetector(
                onTap: service.toggleMinimized,
                child: const AiBotAvatar(
                  // CHANGED (Aug 25 2026 — Super Chitti Phase 2,
                  // "Floating Icon Size Bump"): 64 -> 66, exact +2.0pt.
                  size: 66,
                  fallbackColor: Color(0xFFFF4FA3),
                ),
              ),
            ),
          );
        }

        // FIX (Aug 28 2026 — latent crash). These were
        // `clamp(0.0, size.width - 320)`. Dart's num.clamp throws when
        // lowerLimit > upperLimit, so on any viewport shorter than the
        // panel — a phone in landscape is 360-400px tall, against a
        // 420px panel — `clamp(0.0, -60.0)` threw and took the whole
        // overlay down. Never reproduced on a portrait phone, which is
        // exactly why it survived.
        //
        // Clamping the LIMIT at zero first means a screen too small for
        // the panel pins it to the top-left corner instead of crashing.
        final maxLeft = (size.width - _kPanelWidth).clamp(0.0, double.infinity);
        final maxTop = (size.height - _kPanelHeight).clamp(0.0, double.infinity);
        final left = service.position.dx.clamp(0.0, maxLeft);
        final top = service.position.dy.clamp(0.0, maxTop);

        return Positioned(
          left: left,
          top: top,
          child: GestureDetector(
            // Dragging the header repositions the whole panel — makes it
            // a real "floating" assistant instead of pinned to one spot.
            onPanUpdate: (details) {
              service.setPosition(service.position + details.delta);
            },
            child: Material(
              color: Colors.transparent,
              child: Container(
                width: 320,
                height: 420,
                // HIGH-TECH POLISH (Aug 19 2026, Founder: "classy and
                // high-tech"). Three changes, each doing one job:
                //
                //  - A diagonal gradient instead of a flat fill. A
                //    single flat colour is what makes a panel read as a
                //    dialog box; a soft top-left-to-bottom-right ramp
                //    is most of what separates "Apple/CRED" from
                //    "Material default" at zero cost.
                //  - Radius 20 → 24. At 320px wide, 20 reads slightly
                //    boxy next to the app's cards; 24 matches them.
                //  - A coloured ambient shadow rather than plain black.
                //    The panel now sits in its own faint violet light,
                //    which is what makes it look like it's hovering
                //    above the screen instead of pasted onto it.
                // REPAINTED (Aug 28 2026 — Nizam: "chitti popup namma
                // white and pink la kaatama vera color la kaatughu").
                //
                // This panel was the last dark-violet surface left in a
                // pink-and-white app: a near-black gradient body with a
                // #B44CFF violet accent, which AGENTS.md §2 explicitly
                // rules out. It is now the same white surface and kPink
                // accent every card in the app uses.
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: const Color(0x33FF4FA3)),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.14),
                      blurRadius: 30,
                      offset: const Offset(0, 14),
                    ),
                    BoxShadow(
                      color: const Color(0xFFFF4FA3).withValues(alpha: 0.18),
                      blurRadius: 34,
                      spreadRadius: -10,
                      offset: const Offset(0, 10),
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    _buildHeader(service),
                    Expanded(child: _buildMessages(service)),
                    _buildInput(service),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildHeader(GuruOverlayService service) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          // Three stops, not two: the mid violet stops the purple→pink
          // ramp from passing through a muddy band in the middle, which
          // is the usual reason a two-colour gradient looks cheap.
          colors: [Color(0xFFFF4FA3), Color(0xFFFF6FB5), Color(0xFFFF9AC9)],
        ),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Row(
        children: [
          // Avatar sits in a soft glass disc so the robot's own dark
          // pixels don't disappear into the violet behind it.
          Container(
            padding: const EdgeInsets.all(4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
            ),
            child: const AiBotAvatar(size: 20),
          ),
          const SizedBox(width: 9),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Chitti',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                    fontSize: 14,
                    letterSpacing: 0.2,
                    height: 1.05,
                  ),),
              Text('your Allin1 buddy',
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.72),
                    fontWeight: FontWeight.w500,
                    fontSize: 9,
                    height: 1.15,
                  ),),
            ],
          ),
          const Spacer(),
          // NEW (CTO mandate — Text-to-Speech): overlay header mute
          // toggle, same intent as the full chat screen's speaker icon.
          IconButton(
            icon: Icon(
              service.autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: Colors.white,
              size: 18,
            ),
            tooltip: service.autoSpeak ? 'Mute Chitti AI' : 'Unmute Chitti AI',
            onPressed: service.toggleAutoSpeak,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          IconButton(
            icon: const Icon(Icons.history_rounded, color: Colors.white, size: 18),
            tooltip: 'Past chats',
            onPressed: () async {
              final picked = await showChittiHistorySheet(context);
              if (picked != null && picked.isNotEmpty) {
                service.applySession(picked);
              }
            },
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          IconButton(
            icon: const Icon(Icons.add_comment_outlined,
                color: Colors.white, size: 18),
            tooltip: 'New chat',
            onPressed: () => service.startNewChat(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          IconButton(
            icon: const Icon(Icons.remove, color: Colors.white, size: 18),
            tooltip: 'Minimize',
            onPressed: service.toggleMinimized,
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white, size: 18),
            tooltip: 'Close',
            onPressed: () => service.requestClose(),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 30, minHeight: 30),
          ),
        ],
      ),
    );
  }

  Widget _buildMessages(GuruOverlayService service) {
    if (service.messages.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Ask me anything',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 14.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 5),
              Text(
                'Book a ride, order food, track an order —\nI stay with you as you move around the app.',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.5),
                  fontSize: 11.5,
                  height: 1.45,
                ),
              ),
            ],
          ),
        ),
      );
    }
    _scrollToBottom();
    return ListView.builder(
      controller: _scroll,
      padding: const EdgeInsets.all(12),
      itemCount: service.messages.length + (service.isSending ? 1 : 0),
      itemBuilder: (context, i) {
        if (i >= service.messages.length) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 6),
            child: SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF4FA3)),
            ),
          );
        }
        final m = service.messages[i];
        final isUser = m.role == 'user';
        return Align(
          alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
          child: Column(
            crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
            children: [
              Container(
                margin: const EdgeInsets.symmetric(vertical: 4),
                constraints: const BoxConstraints(maxWidth: 240),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                decoration: BoxDecoration(
                  color: isUser ? const Color(0xFFFF4FA3) : const Color(0xFFFFF1F8),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(m.text, style: GoogleFonts.outfit(color: Colors.white, fontSize: 12.5, height: 1.35)),
              ),
              // NEW (CTO mandate — Suggestion Chips): tapping one sends
              // that exact text back to Guru as the next message.
              // Same video card as the full chat screen — a thumbnail
              // that opens the shared modal player. Nizam asked for it
              // in the popup too.
              if (m.videoId != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 6),
                  child: GestureDetector(
                    onTap: () {
                      final ctx = navigatorKey.currentContext;
                      if (ctx == null) return;
                      unawaited(showPremiumVideoModal(
                        ctx,
                        videoId: m.videoId!,
                        title: 'Chitti suggests',
                      ),);
                    },
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: AspectRatio(
                        aspectRatio: 16 / 9,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            VideoThumbnail(videoId: m.videoId!),
                            Container(
                              color: Colors.black.withValues(alpha: 0.25),
                            ),
                            const Center(
                              child: CircleAvatar(
                                radius: 18,
                                backgroundColor: Color(0xFFFF0000),
                                child: Icon(
                                  Icons.play_arrow_rounded,
                                  color: Colors.white,
                                  size: 24,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              if (m.suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: m.suggestions
                        .map(
                          (s) => ActionChip(
                            label: Text(s, style: GoogleFonts.outfit(fontSize: 11, color: const Color(0xFF4A1236))),
                            backgroundColor: const Color(0xFFFFF1F8),
                            side: const BorderSide(color: Color(0x33FF4FA3)),
                            onPressed: () => unawaited(service.sendMessage(s)),
                          ),
                        )
                        .toList(),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildInput(GuruOverlayService service) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: GoogleFonts.outfit(color: const Color(0xFF2B0F1F), fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Ask Chitti AI...',
                hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 12.5),
                filled: true,
                fillColor: const Color(0xFFFFF1F8),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(24),
                  borderSide: BorderSide.none,
                ),
              ),
              onSubmitted: (_) => _send(service),
            ),
          ),
          const SizedBox(width: 6),
          // NEW (CTO mandate — Final Overlay Tool Wiring): "tap the
          // overlay mic" — same finalResult-only speech flow as the
          // full chat screen, feeding straight into
          // GuruOverlayService.sendMessage() (which now runs the same
          // agent-action + confirmation gate typed text does).
          GestureDetector(
            onTap: _onMicTapped,
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: _isListening ? const Color(0xFFFF4FA3) : const Color(0xFFFFF1F8),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _isListening ? Icons.mic_rounded : Icons.mic_none_rounded,
                color: Colors.white,
                size: 16,
              ),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: () => _send(service),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(color: Color(0xFFFF4FA3), shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 16),
            ),
          ),
        ],
      ),
          const SizedBox(height: 4),
          // Same quiet line as the full chat screen. Under the input,
          // not on every bubble: repeated per reply it becomes
          // wallpaper, and it would crowd the message it warns about.
          Text(
            'Chitti can make mistakes — double-check anything important.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: const Color(0xFF8A4E72),
              fontSize: 9.5,
              height: 1.2,
            ),
          ),
        ],
      ),
    );
  }

  void _send(GuruOverlayService service) {
    final text = _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    unawaited(service.sendMessage(text));
  }
}
