// ================================================================
// chitti_call_screen.dart — a full-screen voice call with Chitti,
// entirely inside the app
// ================================================================
// NEW (Sep 5 2026 — Nizam: "customer app-la irukka 'Call us' button
// ... app-kulla oru Chitti voice call aarambikanum. Full-screen call UI,
// ringtone, timer, mute — paakka call maadhirye irukkum, aana audio
// cellular path-ai thodave illa").
//
// WHY THIS AVOIDS THE PROBLEM A REAL CALL HAS
// A real cellular call cannot carry Chitti's voice to the far end
// without an acoustic bridge — see ChittiCallVoice.kt's header for why:
// Android has no API to inject audio into a call's uplink, and Android's
// own Acoustic Echo Cancellation kills the speaker-to-mic path any app
// tries to use as a workaround. This screen never touches a cellular
// call at all. It is ordinary in-app TTS played through the phone's
// normal speaker and ordinary in-app STT listening through the normal
// mic — for which AEC is not a wall, because there is no far end to
// cancel echo for. Same reason a video call app's own mute button works
// fine while a Bluetooth headset's mute button does not always reach it.
//
// WHY THIS REUSES ChittiConversationController RATHER THAN THE CHAT
// SCREEN'S OWN VOICE LOOP
// guru_chat_screen.dart's hands-free loop builds a live, word-by-word
// caption into a TextField as the customer speaks — necessary there
// because the customer can SEE that field. A call has no such field: it
// shows a face, not a transcript, so segment-by-segment preview text has
// nothing to write into and nothing to gain by existing. This screen
// therefore listens for one FINAL result per turn instead of an
// accumulating stream of partials — simpler, and there is nothing this
// screen needs from the added complexity that produced.
//
// What it does share, on purpose, is [ChittiConversationController] —
// no Flutter, no plugins, unit-tested (test/chitti_conversation_
// controller_test.dart) — for the actual turn-taking decisions: the
// echo guard, barge-in, and the stop-word list in four languages plus
// the Tanglish people actually speak. That logic is proven in
// production already; duplicating it here by hand, blind to how it
// behaves on a real device, is exactly the kind of "looked fine, wasn't"
// bug a voice feature is hardest to catch.
//
// ChittiConversationMode.call is used specifically because it was
// already built for this: "stays open like a phone call until the user
// stops it" — the mode existed before this screen did, and this is the
// first place that actually asks for it.
//
// WHAT CANNOT BE UNIT TESTED, AND WHY THAT IS SAID OUT LOUD HERE
// speech_to_text and flutter_tts are real hardware/OS integrations.
// Their timing, permission prompts, and failure modes (a TTS completion
// callback that "can simply never fire" on some platforms — see
// guru_chat_screen.dart's own comment on the identical pattern) cannot
// be exercised by a test run on a CI machine with no microphone. Every
// plugin call here is wrapped exactly as defensively as the chat
// screen's proven version — timeouts, mounted checks, try/catch — but
// the honest status of this screen is "needs an on-device call" before
// it ships, the same status the browser and alarm features shipped
// under.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;

import '../services/chitti/chitti_call_service_log.dart';
import '../services/chitti/chitti_conversation_controller.dart';
import '../services/chitti/chitti_voice_service.dart';
import '../services/guru_api_service.dart';
import '../services/localization_service.dart';
import '../widgets/ai_bot_avatar.dart';

/// Where the call ended up, for the caller to react to (e.g. show a
/// "call Chitti again?" prompt after a very short accidental call).
enum ChittiCallOutcome {
  /// The customer tapped "End call".
  endedByUser,

  /// The customer said a stop word ("bye", "podhum", ...).
  endedBySpeech,

  /// The mic or TTS engine could not be reached at all — reported
  /// rather than left as a silent, permanently "Connecting..." screen.
  failedToStart,
}

/// Opens the call screen and returns how it ended.
Future<ChittiCallOutcome?> openChittiCallScreen(BuildContext context) {
  return Navigator.of(context, rootNavigator: true).push<ChittiCallOutcome>(
    MaterialPageRoute(
      builder: (_) => const ChittiCallScreen(),
      fullscreenDialog: true,
    ),
  );
}

class ChittiCallScreen extends StatefulWidget {
  const ChittiCallScreen({super.key});

  // @visibleForTesting rather than const: a widget test that wants to
  // exercise the timeout path honestly (see chitti_call_screen_test.
  // dart) needs to let it actually fire within the test body, and
  // pumping 12 real seconds forward is the wrong way to buy that —
  // flutter_test's strict "no pending Timer at test end" check trips on
  // ANY unresolved Future.timeout() Timer regardless of whether the
  // widget was disposed, so the only clean way to test this path is to
  // let the real timeout elapse on a short duration, not skip the wait.
  @visibleForTesting
  static Duration initTimeout = const Duration(seconds: 12);

  @override
  State<ChittiCallScreen> createState() => _ChittiCallScreenState();
}

enum _CallPhase { connecting, listening, thinking, speaking, muted, failed }

class _ChittiCallScreenState extends State<ChittiCallScreen>
    with SingleTickerProviderStateMixin {
  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  late final ChittiConversationController _conversation;

  bool _speechReady = false;
  bool _ttsReady = false;
  bool _muted = false;
  bool _disposed = false;
  _CallPhase _phase = _CallPhase.connecting;

  /// The full exchange so far, sent as context on every turn — the same
  /// shape guru_chat_screen.dart builds, kept short because a call is a
  /// live conversation, not a document Chitti needs to re-read in full.
  final List<Map<String, String>> _history = [];

  /// Every tool call Chitti made during this call, in order. Handed to
  /// ChittiCallServiceLog when the call ends — see that file's header
  /// for why this is a pass-through of what extractAgentAction already
  /// decided, not a second classification pass.
  final List<ChittiCallIntent> _capturedIntents = [];

  Timer? _elapsedTimer;
  Duration _elapsed = Duration.zero;
  DateTime? _connectedAt;

  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _conversation = ChittiConversationController(
      mode: ChittiConversationMode.call,
    );
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);
    unawaited(_connect());
  }

  String get _languageCode {
    try {
      return context.read<LocalizationService>().languageCode;
    } catch (_) {
      return 'en';
    }
  }

  String get _ttsLocale {
    try {
      return context.read<LocalizationService>().languageCode == 'ta'
          ? 'ta-IN'
          : 'en-US';
    } catch (_) {
      return 'en-US';
    }
  }

  String get _sttLocale => _languageCode == 'ta' ? 'ta_IN' : 'en_US';

  /// Both plugin calls below sit on top of real OS permission prompts
  /// and hardware. Neither has ever been observed to hang in this app's
  /// production use — but neither had a bounded worst case before this
  /// screen existed either, because guru_chat_screen.dart's own version
  /// of this init only ever runs after the mic permission is already
  /// granted (the FAB that opens it is gated behind PermissionService
  /// upstream). This screen can be reached directly, so it cannot make
  /// that assumption: a customer who denies (or is silently never asked
  /// for) the mic permission must land on the "failed" screen and its
  /// working End button, not an unbounded wait with a spinner-less
  /// "Connecting..." that never resolves either way.
  Future<void> _connect() async {
    try {
      _speechReady = await _speech
          .initialize(
            onStatus: (status) {
              // Mirrors guru_chat_screen.dart's own handling:
              // 'notListening'/'done' fire between turns constantly and
              // are not a real failure — only react to them by falling
              // through to the next listen, which _handleFinalResult
              // already schedules.
              if (status == 'notListening' || status == 'done') return;
            },
            onError: (error) {
              debugPrint('[ChittiCall] speech error: ${error.errorMsg}');
            },
          )
          .timeout(ChittiCallScreen.initTimeout, onTimeout: () => false);
    } catch (e) {
      debugPrint('[ChittiCall] speech init failed: $e');
      _speechReady = false;
    }

    try {
      await ChittiVoiceService.apply(_tts, _ttsLocale)
          .timeout(ChittiCallScreen.initTimeout);
      _ttsReady = true;
    } catch (e) {
      debugPrint('[ChittiCall] tts init failed: $e');
      _ttsReady = false;
    }

    if (!mounted) return;

    if (!_speechReady || !_ttsReady) {
      setState(() => _phase = _CallPhase.failed);
      return;
    }

    _conversation.start();
    _connectedAt = DateTime.now();
    _elapsedTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted || _connectedAt == null) return;
      setState(() => _elapsed = DateTime.now().difference(_connectedAt!));
    });

    final greeting = _languageCode == 'ta'
        ? 'வணக்கம் பாஸ், சொல்லுங்க, நான் கேட்டுக்கிட்டு இருக்கேன்.'
        : "Hi, I'm listening — go ahead.";
    await _speak(greeting);
  }

  Future<void> _listen() async {
    if (!mounted || !_conversation.isActive || _disposed) return;
    if (_muted) {
      setState(() => _phase = _CallPhase.muted);
      return;
    }
    setState(() => _phase = _CallPhase.listening);
    try {
      await _speech.listen(
        onResult: (result) {
          if (!result.finalResult) return;
          unawaited(_handleFinalResult(result.recognizedWords.trim()));
        },
        listenOptions: stt.SpeechListenOptions(
          localeId: _sttLocale,
          listenFor: const Duration(seconds: 30),
          pauseFor: const Duration(seconds: 4),
        ),
      );
    } catch (e) {
      debugPrint('[ChittiCall] listen failed: $e');
      // A single failed listen attempt should not end the call — retry
      // once the current UI frame settles rather than looping tightly.
      if (mounted && _conversation.isActive) {
        Future.delayed(const Duration(seconds: 1), _listen);
      }
    }
  }

  Future<void> _handleFinalResult(String heard) async {
    if (!mounted || !_conversation.isActive) return;
    if (heard.isEmpty) {
      // Nothing usable — let the controller's own empty-turn counter
      // decide whether that means "walked away" (it never does in call
      // mode, which is the point of call mode) and just listen again.
      final step = _conversation.onUserSaid(
        '',
        resolvedAnIntent: false,
        awaitingReply: false,
      );
      if (step == ChittiConversationStep.stop) {
        _endCall(ChittiCallOutcome.endedBySpeech);
      } else {
        unawaited(_listen());
      }
      return;
    }

    // ECHO GUARD / BARGE-IN — identical reasoning to guru_chat_screen.
    // dart's twin: the mic stays open while Chitti talks so the customer
    // can cut in, which means it also hears the TTS. Anything that
    // substantially overlaps what Chitti just said is discarded as
    // self-echo; a genuine interruption shares almost no words with it.
    if (_conversation.isSpeaking) {
      if (_conversation.isSelfEcho(heard)) {
        unawaited(_listen());
        return;
      }
      if (_conversation.isStopRequest(heard)) {
        await _tts.stop();
        _conversation.markSpokenDone();
        _endCall(ChittiCallOutcome.endedBySpeech);
        return;
      }
      _conversation.queuePendingTopic(heard);
      return;
    }

    if (_conversation.isStopRequest(heard)) {
      _conversation.stop();
      _endCall(ChittiCallOutcome.endedBySpeech);
      return;
    }

    setState(() => _phase = _CallPhase.thinking);
    _history.add({'role': 'user', 'content': heard});

    // NEW (Sep 2026 — Nizam: "customer oru intent or avanga requirement
    // ah chitti kitta sonnangana apo chitti antha call ah namma
    // customer app pesi mudichathum namma admin app ku varanum").
    //
    // The SAME extraction the full chat screen uses to actually act on
    // a request — not a second opinion about what the customer meant.
    // Fire-and-forget on purpose: a slow or failed tool-call check must
    // never delay the spoken reply the customer is waiting for, and a
    // customer who only wanted to chat should never notice this ran at
    // all. Collected here; _endCall decides whether any of it is worth
    // writing down.
    unawaited(
      GuruApiService().extractAgentAction(message: heard).then((action) {
        if (action == null) return;
        final actionType = action['action'] as String?;
        if (actionType == null) return;
        final detail = Map<String, dynamic>.from(action)..remove('action');
        _capturedIntents.add(
          ChittiCallIntent(actionType: actionType, detail: detail),
        );
      }).catchError((Object e) {
        debugPrint('[ChittiCall] extractAgentAction failed: $e');
      }),
    );

    String reply;
    try {
      reply = await GuruApiService().sendMessage(
        message: heard,
        history: _history,
        languageLabel: _languageCode == 'ta' ? 'Tamil' : 'English',
      );
    } catch (e) {
      debugPrint('[ChittiCall] sendMessage failed: $e');
      reply = _languageCode == 'ta'
          ? 'மன்னிக்கணும், இப்போ கேக்கல. மறுபடி சொல்றீங்களா?'
          : "Sorry, I didn't catch that — could you say it again?";
    }
    _history.add({'role': 'assistant', 'content': reply});
    // A call is a live conversation, not a transcript Chitti has to
    // re-read in full on every turn — keep the last few exchanges only.
    if (_history.length > 12) {
      _history.removeRange(0, _history.length - 12);
    }

    if (_conversation.hasPendingTopic) {
      final pending = _conversation.popPendingTopic();
      if (pending != null) {
        _history.add({'role': 'user', 'content': pending.text});
      }
    }

    // onUserSaid's resolvedAnIntent/awaitingReply distinction barely
    // matters in call mode: onUserSaid only uses them to decide whether
    // to auto-stop, and call mode never auto-stops on its own — see the
    // controller's own header. Passing false/false here is therefore not
    // a shortcut, it is the correct input for a mode that keeps the line
    // open regardless.
    final step = _conversation.onUserSaid(
      heard,
      resolvedAnIntent: false,
      awaitingReply: false,
    );
    if (step == ChittiConversationStep.stop) {
      _endCall(ChittiCallOutcome.endedBySpeech);
      return;
    }
    await _speak(reply);
  }

  Future<void> _speak(String text) async {
    if (!mounted || text.trim().isEmpty) return;
    setState(() => _phase = _CallPhase.speaking);
    _conversation.markSpeaking(text);
    try {
      await _tts.stop();
      // See guru_chat_screen.dart's identical comment: on some platforms
      // the completion callback can simply never fire. The timeout is
      // what keeps a stuck TTS engine from freezing the whole call.
      await _tts.awaitSpeakCompletion(true);
      try {
        await _tts.speak(text).timeout(const Duration(seconds: 20));
      } on TimeoutException {
        debugPrint('[ChittiCall] TTS completion never fired — continuing.');
        await _tts.stop();
      }
    } catch (e) {
      debugPrint('[ChittiCall] speak failed: $e');
    }
    if (!mounted) return;
    final step = _conversation.afterSpeaking();
    if (step == ChittiConversationStep.listen) {
      unawaited(_listen());
    } else {
      _endCall(ChittiCallOutcome.endedBySpeech);
    }
  }

  void _toggleMute() {
    setState(() => _muted = !_muted);
    if (_muted) {
      unawaited(_speech.stop());
      setState(() => _phase = _CallPhase.muted);
    } else if (_conversation.isActive && !_conversation.isSpeaking) {
      unawaited(_listen());
    }
  }

  bool _ended = false;

  void _endCall(ChittiCallOutcome outcome) {
    if (_disposed || _ended) return;
    _ended = true;
    _conversation.stop();
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    _elapsedTimer?.cancel();
    final connectedAt = _connectedAt;
    if (connectedAt != null) {
      unawaited(
        ChittiCallServiceLog.logCall(
          intents: _capturedIntents,
          callStartedAt: connectedAt,
          callEndedAt: DateTime.now(),
        ),
      );
    }
    if (mounted) Navigator.of(context).pop(outcome);
  }

  @override
  void dispose() {
    _disposed = true;
    _elapsedTimer?.cancel();
    _pulse.dispose();
    unawaited(_speech.stop());
    unawaited(_tts.stop());
    super.dispose();
  }

  String get _statusText {
    final ta = _languageCode == 'ta';
    return switch (_phase) {
      _CallPhase.connecting => ta ? 'இணைக்கிறேன்...' : 'Connecting...',
      _CallPhase.listening => ta ? 'கேட்டுக்கிட்டு இருக்கேன்...' : 'Listening...',
      _CallPhase.thinking => ta ? 'யோசிக்கிறேன்...' : 'Thinking...',
      _CallPhase.speaking => ta ? 'பேசுறேன்...' : 'Speaking...',
      _CallPhase.muted => ta ? 'மியூட் ஆகியிருக்கு' : 'Muted',
      _CallPhase.failed => ta
          ? 'மைக் அல்லது குரல் இப்போ ரீச் ஆகல'
          : 'Could not reach the mic or voice engine',
    };
  }

  static String _formatElapsed(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _endCall(ChittiCallOutcome.endedByUser);
      },
      child: Scaffold(
        backgroundColor: const Color(0xFF0E0E1A),
        body: SafeArea(
          child: Column(
            children: [
              const SizedBox(height: 28),
              AnimatedBuilder(
                animation: _pulse,
                builder: (context, child) {
                  final scale = _phase == _CallPhase.listening ||
                          _phase == _CallPhase.speaking
                      ? 1.0 + (_pulse.value * 0.06)
                      : 1.0;
                  return Transform.scale(scale: scale, child: child);
                },
                child: const AiBotAvatar(
                  size: 128,
                  fallbackColor: Color(0xFFFF4FA3),
                ),
              ),
              const SizedBox(height: 22),
              Text(
                'Chitti',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                _statusText,
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.65),
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              if (_phase != _CallPhase.connecting &&
                  _phase != _CallPhase.failed) ...[
                const SizedBox(height: 4),
                Text(
                  _formatElapsed(_elapsed),
                  style: GoogleFonts.outfit(
                    color: Colors.white.withValues(alpha: 0.4),
                    fontSize: 12.5,
                    fontFeatures: const [FontFeature.tabularFigures()],
                  ),
                ),
              ],
              const Spacer(),
              if (_phase == _CallPhase.failed)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    _languageCode == 'ta'
                        ? 'மைக் அல்லது ஸ்பீக்கர் அனுமதி வேணும். Settings-ல் சரி பண்ணிட்டு மறுபடி முயற்சி பண்ணுங்க.'
                        : 'Chitti needs microphone access to take this call. '
                            'Check your permission settings and try again.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.6),
                      fontSize: 12.5,
                      height: 1.4,
                    ),
                  ),
                ),
              const SizedBox(height: 36),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  _CallActionButton(
                    icon: _muted ? Icons.mic_off_rounded : Icons.mic_rounded,
                    label: _muted ? 'Unmute' : 'Mute',
                    background: Colors.white.withValues(alpha: 0.12),
                    iconColor: Colors.white,
                    onTap: _phase == _CallPhase.failed ? null : _toggleMute,
                  ),
                  const SizedBox(width: 28),
                  _CallActionButton(
                    icon: Icons.call_end_rounded,
                    label: 'End',
                    background: const Color(0xFFE53935),
                    iconColor: Colors.white,
                    large: true,
                    onTap: () => _endCall(ChittiCallOutcome.endedByUser),
                  ),
                ],
              ),
              const SizedBox(height: 48),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.label,
    required this.background,
    required this.iconColor,
    required this.onTap,
    this.large = false,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color iconColor;
  final VoidCallback? onTap;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final size = large ? 68.0 : 56.0;
    return Column(
      children: [
        Material(
          color: background,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(
              width: size,
              height: size,
              child: Icon(icon, color: iconColor, size: large ? 30 : 24),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: Colors.white.withValues(alpha: 0.7),
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
