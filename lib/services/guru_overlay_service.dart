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
import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../app_navigator.dart';
import '../screens/bike_taxi/bike_booking_screen.dart';
import '../screens/car_wash_screen.dart';
import '../screens/food_hub_screen.dart';
import '../screens/grocery_order_screen.dart';
import '../screens/nj_tech_service_screen.dart';
import '../screens/play_zone_screen.dart';
import '../screens/printing_service_screen.dart';
import '../screens/rewards_screen.dart';
import '../screens/settings_screen.dart';
import '../screens/sos_screen.dart';
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

class GuruChatTurn {
  const GuruChatTurn({required this.role, required this.text, this.suggestions = const []});
  final String role; // 'user' | 'assistant'
  final String text;
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
  bool _ttsReady = false;
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
  final List<GuruChatTurn> messages = [];
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
      await _tts.setLanguage(locale);
      _ttsReady = true;
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[GuruOverlayService] TTS failed: $e');
    }
  }

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
  void show() {
    if (_entry != null) {
      if (_minimized) {
        _minimized = false;
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
    notifyListeners();
  }

  /// Shows the CTO-mandated confirmation dialog, then removes the entry
  /// only if the customer confirms.
  Future<void> requestClose() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      _forceClose();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Close Guru?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to close Guru?',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
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
  }

  void _forceClose() {
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
      messages.add(GuruChatTurn(role: 'assistant', text: parsed.text, suggestions: parsed.suggestions));
      unawaited(_speak(parsed.text));
    } catch (e) {
      messages.add(
        const GuruChatTurn(
          role: 'assistant',
          text: 'Guru AI is temporarily unavailable. Please try again shortly.',
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
  Future<bool> _tryAgentActionFromText(String input, String apiKey) async {
    if (input.isEmpty) return false;
    Map<String, dynamic>? args;
    try {
      args = await _api.extractAgentAction(message: input, apiKeyOverride: apiKey);
    } catch (e) {
      debugPrint('[GuruOverlayService] extractAgentAction failed: $e');
    }
    if (args == null) return false;
    final action = args['action'] as String?;
    if (action != 'book_transport' &&
        action != 'navigate_to_section' &&
        action != 'check_and_update_app') {
      return false;
    }

    _pendingAgentAction = args;
    unawaited(_logGuruAnalyticsEvent(
      eventType: 'intent_requested',
      action: action,
      args: args,
    ));
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
        return "I'm ready to open ${_sectionLabel(args['section'] as String?)} for you — should I proceed?";
      case 'check_and_update_app':
        return "I'm ready to check for an app update — should I proceed?";
      default:
        return 'Should I proceed?';
    }
  }

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
    }
  }

  // NEW (CTO mandate — Final Overlay Tool Wiring): the actual
  // Navigator.push execution, via navigatorKey (this service has no
  // BuildContext of its own) — same "prefill, never auto-dispatch"
  // safety net as guru_chat_screen.dart's booking flow: this only ever
  // opens BikeBookingScreen with fields pre-filled, the customer still
  // has to tap Confirm there.
  void _actOnBookingAction(Map<String, dynamic> args) {
    final service = _voiceServiceFromKey(args['service'] as String?);
    if (service == null) return;
    final navState = navigatorKey.currentState;
    if (navState == null) return;

    final destinationRaw = (args['destination'] as String?)?.trim();
    final intent = VoiceBookingIntent(
      service: service,
      destinationQuery: (destinationRaw != null && destinationRaw.isNotEmpty) ? destinationRaw : null,
    );

    messages.add(
      GuruChatTurn(
        role: 'assistant',
        text: intent.service == VoiceService.sos
            ? "I've opened SOS for you — please confirm there so we can get you help right away."
            : "I've got it! Setting up your ${intent.displayName} booking now — review the details and press Confirm to book your Hero.",
      ),
    );
    notifyListeners();

    if (intent.service == VoiceService.sos) {
      unawaited(navState.push(MaterialPageRoute<void>(builder: (_) => const SosScreen())));
      return;
    }
    unawaited(_navigateForBookingIntent(intent, navState));
  }

  Future<void> _navigateForBookingIntent(VoiceBookingIntent intent, NavigatorState navState) async {
    if (intent.destinationQuery == null) {
      unawaited(navState.push(MaterialPageRoute<void>(
        builder: (_) => BikeBookingScreen(initialCategory: intent.categoryKey),
      ),),);
      return;
    }
    final resolved = await _voiceIntent.resolve(intent);
    unawaited(navState.push(MaterialPageRoute<void>(
      builder: (_) => BikeBookingScreen(
        initialCategory: intent.categoryKey,
        initialDropLocation: resolved.destination,
      ),
    ),),);
  }

  void _actOnNavigateAction(Map<String, dynamic> args) {
    final section = args['section'] as String?;
    final target = _screenForSection(section);
    final navState = navigatorKey.currentState;
    if (target == null || navState == null) return;

    messages.add(
      GuruChatTurn(role: 'assistant', text: 'Sure! Opening ${_sectionLabel(section)} for you now.'),
    );
    notifyListeners();
    unawaited(navState.push(MaterialPageRoute<void>(builder: (_) => target)));
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
      default:
        return null;
    }
  }

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
}

// ================================================================
// Global "Ask Guru" trigger — a subtle FAB meant to be laid over
// MaterialApp's `child` via its `builder:` callback so it appears on
// every screen with zero per-screen wiring.
// ================================================================
class GlobalGuruFab extends StatelessWidget {
  const GlobalGuruFab({super.key});

  @override
  Widget build(BuildContext context) {
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
            child: FloatingActionButton(
              heroTag: 'guru_global_fab',
              backgroundColor: const Color(0xFFB44CFF),
              onPressed: () => GuruOverlayService.instance.show(),
              child: const Icon(Icons.auto_awesome, color: Colors.white),
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

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    if (_isListening) {
      unawaited(_speech.stop());
    }
    super.dispose();
  }

  Future<void> _onMicTapped() async {
    final service = GuruOverlayService.instance;
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
          debugPrint('[GuruOverlayService] speech error: $error');
          if (mounted) setState(() => _isListening = false);
        },
      );
    }
    if (!_speechReady || !mounted) return;

    String? localeId;
    try {
      final code = context.read<LocalizationService>().languageCode;
      if (code == 'ta' || code == 'tg') {
        final locales = await _speech.locales();
        for (final locale in locales) {
          if (locale.localeId.toLowerCase().startsWith('ta')) {
            localeId = locale.localeId;
            break;
          }
        }
        localeId ??= 'ta-IN';
      }
    } catch (e) {
      debugPrint('[GuruOverlayService] locale resolve failed: $e');
    }

    setState(() {
      _isListening = true;
      _voiceResultHandled = false;
    });
    unawaited(
      _speech.listen(
        onResult: (result) {
          if (result.finalResult &&
              result.recognizedWords.trim().isNotEmpty &&
              !_voiceResultHandled) {
            _voiceResultHandled = true;
            if (mounted) setState(() => _isListening = false);
            unawaited(service.sendMessage(result.recognizedWords.trim()));
          }
        },
        localeId: localeId,
        listenOptions: stt.SpeechListenOptions(partialResults: false, cancelOnError: true),
        listenFor: const Duration(seconds: 30),
        pauseFor: const Duration(seconds: 5),
      ),
    );
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
                child: Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A26),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: Colors.black.withValues(alpha: 0.3), blurRadius: 12),
                    ],
                  ),
                  child: const Icon(Icons.auto_awesome, color: Color(0xFFB44CFF)),
                ),
              ),
            ),
          );
        }

        final left = service.position.dx.clamp(0.0, size.width - 320);
        final top = service.position.dy.clamp(0.0, size.height - 420);

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
                decoration: BoxDecoration(
                  color: const Color(0xFF15151F),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: const Color(0xFF2A2A3B)),
                  boxShadow: [
                    BoxShadow(color: Colors.black.withValues(alpha: 0.4), blurRadius: 24, offset: const Offset(0, 10)),
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
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: const BoxDecoration(
        gradient: LinearGradient(colors: [Color(0xFFB44CFF), Color(0xFFFF4FA3)]),
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Row(
        children: [
          const Icon(Icons.auto_awesome, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text('Guru', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 14)),
          const Spacer(),
          // NEW (CTO mandate — Text-to-Speech): overlay header mute
          // toggle, same intent as the full chat screen's speaker icon.
          IconButton(
            icon: Icon(
              service.autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded,
              color: Colors.white,
              size: 18,
            ),
            tooltip: service.autoSpeak ? 'Mute Guru' : 'Unmute Guru',
            onPressed: service.toggleAutoSpeak,
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
          child: Text(
            'Ask me anything about Allin1 — I stay with you as you move around the app.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: Colors.white54, fontSize: 12.5),
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
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFB44CFF)),
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
                  color: isUser ? const Color(0xFFB44CFF) : const Color(0xFF1C1C29),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(m.text, style: GoogleFonts.outfit(color: Colors.white, fontSize: 12.5, height: 1.35)),
              ),
              // NEW (CTO mandate — Suggestion Chips): tapping one sends
              // that exact text back to Guru as the next message.
              if (m.suggestions.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: m.suggestions
                        .map(
                          (s) => ActionChip(
                            label: Text(s, style: GoogleFonts.outfit(fontSize: 11, color: Colors.white)),
                            backgroundColor: const Color(0xFF1C1C29),
                            side: const BorderSide(color: Color(0xFF2A2A3B)),
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
      child: Row(
        children: [
          Expanded(
            child: TextField(
              controller: _controller,
              style: GoogleFonts.outfit(color: Colors.white, fontSize: 12.5),
              decoration: InputDecoration(
                hintText: 'Ask Guru...',
                hintStyle: GoogleFonts.outfit(color: Colors.white38, fontSize: 12.5),
                filled: true,
                fillColor: const Color(0xFF1C1C29),
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
                color: _isListening ? const Color(0xFFFF4FA3) : const Color(0xFF1C1C29),
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
              decoration: const BoxDecoration(color: Color(0xFFB44CFF), shape: BoxShape.circle),
              child: const Icon(Icons.send, color: Colors.white, size: 16),
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
