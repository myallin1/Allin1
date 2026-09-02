import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chitti_accessibility_bridge.dart';
import 'chitti_summarizer.dart';
import '../guru_admin_api_service.dart';

class ChittiCallScreeningService {
  ChittiCallScreeningService._();
  static final ChittiCallScreeningService instance = ChittiCallScreeningService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final GuruAdminApiService _api = GuruAdminApiService();

  bool _isScreening = false;
  bool get isScreening => _isScreening && !_pausedForManualRecording;
  String _callerNumber = '';
  final List<String> _conversation = [];
  int _turnCount = 0;
  static const int _maxTurns = 5;

  // NEW (Sep 2 2026 — Nizam: manual "Record" button on the in-call
  // screen and Chitti's own speech recognizer both want the single
  // microphone Android grants to one caller at a time; pressing Record
  // while Chitti is mid-conversation silently starved Chitti's STT
  // (customer speech never reached it), with no indication why. Rather
  // than let both fight for the mic, the admin's explicit manual
  // recording wins: Chitti's listening pauses for as long as manual
  // recording is on, and resumes cleanly once it's switched off.
  bool _pausedForManualRecording = false;

  void pauseForManualRecording() {
    if (!_isScreening || _pausedForManualRecording) return;
    _pausedForManualRecording = true;
    try {
      _speech.stop();
    } catch (_) {}
    _log('[ChittiCallScreeningService] Paused listening — admin started manual recording');
  }

  void resumeAfterManualRecording() {
    if (!_isScreening || !_pausedForManualRecording) return;
    _pausedForManualRecording = false;
    _log('[ChittiCallScreeningService] Resuming listening — manual recording stopped');
    _listenLoop();
  }

  String _languageCode = 'en';

  String get _locale => switch (_languageCode) {
        'ta' => 'ta-IN',
        'hi' => 'hi-IN',
        'ml' => 'ml-IN',
        _ => 'en-US',
      };

  Timer? _screeningTimeoutTimer;
  int _errorRetryCount = 0;

  // NEW (Aug 31 2026 — Nizam: "oru time nadakura process oru name la
  // irukanum, antha time la yenna nadanthuchu-nu antha log paatha
  // theriyanum"). Every log line used to carry only `caller`, which is
  // 'unknown' for almost every screened call — so the debug screen
  // grouped by caller had nothing to group ON and rendered each single
  // line as its own "1 step" card. This session id is generated once
  // per call and stamped on every line of that call (including the
  // Bridge's own lines, via [currentSessionId]), so one call reads as
  // one named block.
  static String? _sessionId;
  static String? _sessionLabel;

  /// The active call's session id, or null between calls. Read by
  /// ChittiAccessibilityBridge so its own connected/ended log lines
  /// land in the same group as this service's.
  static String? get currentSessionId => _sessionId;
  static String? get currentSessionLabel => _sessionLabel;

  static void beginSession(String callerNumber) {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    _sessionId = 'call_${now.millisecondsSinceEpoch}';
    final who = callerNumber.trim().isEmpty ? 'Unknown caller' : callerNumber.trim();
    _sessionLabel = '$who · ${two(now.day)}/${two(now.month)} ${two(now.hour)}:${two(now.minute)}:${two(now.second)}';
  }

  static void endSession() {
    _sessionId = null;
    _sessionLabel = null;
  }

  Future<void> _log(String msg) async {
    debugPrint(msg);
    await writeLog(msg, callerNumber: _callerNumber);
  }

  /// Shared writer so the Bridge's own lines carry the same session
  /// stamp — one call, one group, in order.
  static Future<void> writeLog(String msg, {String? callerNumber}) async {
    try {
      await FirebaseFirestore.instance.collection('chitti_screening_debug_logs').add({
        'caller': (callerNumber == null || callerNumber.trim().isEmpty) ? 'unknown' : callerNumber.trim(),
        'sessionId': _sessionId ?? 'no_session',
        'sessionLabel': _sessionLabel ?? 'Outside a call',
        'message': msg,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  Future<void> startScreening(String callerNumber) async {
    if (_isScreening) return;
    _isScreening = true;
    _callerNumber = callerNumber;
    // FIX (Sep 1 2026 — Nizam: "oru call la nadantha yella log um orey
    // section la iruntha namma monitor panna easy"). This used to call
    // beginSession() unconditionally, overwriting the session the
    // Bridge had ALREADY opened on the 'connected' event moments
    // earlier — so the Bridge's own two connected lines ended up in one
    // orphan "2 steps" group and everything after them in a second
    // group, splitting a single call across two cards in the debug
    // screen (visible in the 14:02:20 / 14:02:21 pair). Only start a
    // session here if one isn't already open for this call.
    if (currentSessionId == null) {
      beginSession(callerNumber);
    }
    _conversation.clear();
    _turnCount = 0;
    _errorRetryCount = 0;
    _screeningTimeoutTimer?.cancel();
    _screeningTimeoutTimer = Timer(const Duration(seconds: 45), () {
      _log('[ChittiCallScreeningService] Auto-stopping screening after 45s inactivity.');
      stopScreening();
    });

    // NEW (per Nizam's request, Aug 31 2026): "chitti pesurathuku late
    // aguthu" — full-conversation mode's STT init + live AI network
    // round-trip per turn was making the customer wait audibly. Added a
    // second, much faster mode as a reliability backup while the full
    // conversation flow is still being tuned: play one fixed greeting
    // (no AI call, no speech-recognition engine spun up at all) and let
    // the native call recording already running (see PhoneCallService.
    // onCallConnected) capture whatever the caller says, for Nizam to
    // listen back to later via the Dialer/File Manager when free.
    String mode = 'quick_record';
    try {
      final prefs = await SharedPreferences.getInstance();
      final isEnabled = prefs.getBool('kChittiCallAssistantEnabled') ?? true;
      if (!isEnabled) {
        await _log('[ChittiCallScreeningService] Call Assistant is disabled in settings. Skipping screening.');
        stopScreening();
        return;
      }
      _languageCode = prefs.getString('customer_language_code') ?? 'ta';
      mode = prefs.getString('kChittiCallAnsweringMode') ?? 'quick_record';
    } catch (e) {
      _log('[ChittiCallScreeningService] language pref read failed: $e');
      _languageCode = 'ta';
    }

    await _log('[ChittiCallScreeningService] Starting offline call screening for: $callerNumber (language: $_languageCode, mode: $mode)');

    if (mode == 'quick_record') {
      await _runQuickGreetingAndRecord();
      return;
    }

    // ── Full Chitti Conversation mode ────────────────────────────────
    // Initialize speech once at startup
    try {
      final hasSpeech = await _speech.initialize(
        onError: (errorNotification) {
          _log('[ChittiCallScreeningService] Speech recognizer error: ${errorNotification.errorMsg}');
          _errorRetryCount++;
          if (_isScreening && _errorRetryCount <= 3) {
            Future.delayed(const Duration(seconds: 2), () {
              if (_isScreening) _listenLoop();
            });
          } else if (_errorRetryCount > 3) {
            _log('[ChittiCallScreeningService] Max retries reached. Stopping mic.');
            stopScreening();
          }
        },
      );
      if (!hasSpeech) {
        _log('[ChittiCallScreeningService] Speech recognizer initialization returned false');
      }
    } catch (e) {
      _log('[ChittiCallScreeningService] Speech recognizer initialization threw error: $e');
    }

    // Wait 1.5 seconds for call audio routing setup to complete on the device speaker
    await Future.delayed(const Duration(milliseconds: 1500));

    final greeting = _languageCode == 'ta'
        ? "வணக்கம், பாஸ் பிஸியா இருக்காரு. நான் அவரோட அசிஸ்டெண்ட் சிட்டி பேசுறேன். இந்த அழைப்பு பதிவு செய்யப்படுகிறது. உங்களுக்கு என்ன வேணும்னு சொல்லுங்க பாஸ்."
        : "Hello, Nizam is busy right now. This is Chitti, his assistant. "
            "This call is being recorded. Please tell me what you need.";
    _conversation.add('Assistant: $greeting');
    await _speak(greeting);

    _listenLoop();
  }

  // NEW (backup mode, Aug 31 2026): fixed one-line greeting, then hands
  // off entirely to the native call recorder for the rest of the call —
  // no speech-recognition engine, no AI network call, so nothing here
  // can add latency the caller would notice. stopScreening() (fired on
  // the native "ended" event) attaches the recording path to the saved
  // appointment exactly like full mode does.
  Future<void> _runQuickGreetingAndRecord() async {
    // No _screeningTimeoutTimer needed — there is no interactive loop
    // that could hang, and native recording should keep running for the
    // whole call, not just the first 45 seconds of it.
    _screeningTimeoutTimer?.cancel();
    _screeningTimeoutTimer = null;

    // Wait 1.5 seconds for call audio routing setup to complete on the device speaker
    await Future.delayed(const Duration(milliseconds: 1500));

    // STRENGTHENED (Sep 2 2026 — Nizam: "quick greeting ah innum
    // konjam storng pannuvom"). Names the business, states this is a
    // one-way recording (not a back-and-forth Chitti will reply to),
    // and tells the caller explicitly to wait for the beep — voicemail
    // phrasing on purpose, since that is exactly the mental model this
    // mode uses.
    //
    // NEW (Sep 2 2026 — Nizam: "chitti sollavendiya intro change
    // panniklam"). An admin-set custom greeting (Dialer settings
    // sheet, kChittiCustomGreeting) overrides this default when
    // non-empty; blank means keep using it.
    String? customGreeting;
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString('kChittiCustomGreeting')?.trim();
      if (saved != null && saved.isNotEmpty) customGreeting = saved;
    } catch (_) {}
    final greeting = customGreeting ??
        (_languageCode == 'ta'
            ? "வணக்கம், இது NJ Tech, Erode. பாஸ் நிஜாம் இப்போ பிஸியா இருக்காரு, "
                "உங்க கால் கனெக்ட் பண்ண முடியாம இருக்கு. பீப் சத்தத்துக்கு அப்புறம், "
                "உங்க பெயர், தேவை, தொடர்பு விவரம் தெளிவா சொல்லுங்க — இது ரெக்கார்ட் "
                "ஆகி பாஸ்கிட்ட நேரடியா போகும்."
            : "Hello, this is NJ Tech, Erode. Nizam is busy right now and "
                "couldn't take this call. After the beep, please clearly say "
                "your name, what you need, and how to reach you — this is "
                "being recorded and will go straight to Nizam.");
    _conversation.add('Assistant: $greeting');
    await _speak(greeting);
    await ChittiAccessibilityBridge.instance.playCallBeep();
    await _log('[ChittiCallScreeningService] Quick-greeting mode: greeting + beep played. No live conversation '
        'loop — the native call recorder is now the only thing capturing the rest of this call.');
  }

  /// True when an AI reply is really a developer/config message rather
  /// than something a customer should ever hear. Deliberately broad —
  /// on a live call, wrongly falling back to a warm generic line costs
  /// nothing, while wrongly reading out an API-key error (which is what
  /// happened on the 16:03 call) is a real business embarrassment.
  static bool _looksLikeSystemError(String reply) {
    final r = reply.trim();
    if (r.isEmpty) return true;
    final lower = r.toLowerCase();
    const markers = [
      'api_key',
      'api key',
      'not configured',
      'not switched on',
      'could not reach',
      'full ai',
      'unauthorized',
      'quota',
      'rate limit',
      'exception',
      'error:',
      'failed',
      'null',
    ];
    return markers.any(lower.contains);
  }

  Future<void> _speak(String text) async {
    try {
      final speakerDiag = await ChittiAccessibilityBridge.instance.enableSpeakerphone();
      await _log('[ChittiCallScreeningService] SPEAKER ROUTE: $speakerDiag');

      // NEW (Sep 1 2026 — CTO/Gemini diagnosis, confirmed logically
      // sound): switched from flutter_tts to a native TTS instance
      // configured with AudioAttributes.USAGE_VOICE_COMMUNICATION (see
      // ChittiCallVoice.kt) instead of flutter_tts's hardcoded
      // USAGE_ASSISTANCE_NAVIGATION_GUIDANCE — the earlier attribute
      // plays through the ordinary media/speaker path, which this
      // session confirmed Android's own Acoustic Echo Cancellation
      // silences before it reaches the caller even though
      // setAudioRoute(SPEAKER) itself genuinely succeeds.
      final completer = Completer<void>();
      ChittiAccessibilityBridge.instance.onCallVoiceEvent = (event) {
        _log('[ChittiCallScreeningService] Native call-voice TTS event: $event');
        if ((event == 'DONE' || event.startsWith('ERROR')) && !completer.isCompleted) {
          completer.complete();
        }
      };

      await _log('[ChittiCallScreeningService] Calling speakOnCallStream() now, locale=$_locale, textLen=${text.length}');
      final accepted = await ChittiAccessibilityBridge.instance.speakOnCallStream(text, _locale);
      await _log('[ChittiCallScreeningService] speakOnCallStream() accepted: $accepted');

      if (accepted) {
        await completer.future.timeout(
          const Duration(seconds: 15),
          onTimeout: () => _log('[ChittiCallScreeningService] Native call-voice TTS timed out waiting for DONE.'),
        );
      }
      ChittiAccessibilityBridge.instance.onCallVoiceEvent = null;
    } catch (e) {
      await _log('[ChittiCallScreeningService] speak failed: $e');
    }
  }

  void _listenLoop() async {
    if (!_isScreening || _pausedForManualRecording) return;

    try {
      _speech.listen(
        onResult: (result) async {
          if (result.finalResult) {
            final text = result.recognizedWords.trim();
            if (text.isNotEmpty) {
              _errorRetryCount = 0;
              await _log('[ChittiCallScreeningService] Caller said: $text');
              _conversation.add('Caller: $text');
              await _handleCallerMessage(text);
            }
          }
        },
        // ROOT-CAUSE FIX (Sep 1 2026 — Nizam: "namma soldrattha avan
        // purinjukuramari therila"). localeId was never passed, so the
        // recognizer always listened in the DEVICE's default language
        // (English here) while the caller speaks Tamil — producing
        // error_speech_timeout / error_no_match over and over, exactly
        // the "mic turns on but Chitti doesn't understand" symptom. The
        // TTS side was already given ta-IN (see _locale, used by
        // speakOnCallStream); the listening side simply never was.
        localeId: _locale,
        // Also lengthened: 8s/3s cut a caller off mid-sentence, and a
        // truncated phrase is another way to get no_match. A real
        // caller answering "what do you need?" usually needs longer.
        listenFor: const Duration(seconds: 20),
        pauseFor: const Duration(seconds: 5),
      );
      await _log('[ChittiCallScreeningService] Listening for caller speech '
          '(localeId=$_locale, listenFor=20s, pauseFor=5s)');
    } catch (e) {
      _log('[ChittiCallScreeningService] listenLoop error: $e');
      _errorRetryCount++;
      if (_isScreening && _errorRetryCount <= 3) {
        Future.delayed(const Duration(seconds: 2), () {
          if (_isScreening) _listenLoop();
        });
      }
    }
  }

  Future<void> _handleCallerMessage(String message) async {
    try {
      await _speech.stop();
    } catch (_) {}

    _turnCount++;
    if (_turnCount >= _maxTurns) {
      await _log('[ChittiCallScreeningService] Reached max turns ($_maxTurns). Terminating gracefully.');
      final closing = _languageCode == 'ta'
          ? "சரிங்க பாஸ், உங்களோட செய்தியை நான் சேவ் பண்ணிட்டேன். பாஸ் உங்களை கூப்பிடுவாரு. நன்றி!"
          : "Alright, I've saved your message. Nizam will call you back. Thank you!";
      _conversation.add('Assistant: $closing');
      await _speak(closing);
      await _saveAppointment();
      stopScreening();
      return;
    }

    try {
      final languageInstruction = _languageCode == 'ta'
          ? 'Tamil or Thanglish'
          : _languageCode == 'hi'
              ? 'Hindi'
              : _languageCode == 'ml'
                  ? 'Malayalam'
                  : 'English';
      final prompt = "You are Chitti, Nizam's AI call assistant. "
          "The caller says: '$message'. "
          "Reply in one warm, natural, human-like $languageInstruction sentence saying Nizam is busy, "
          "and ask if they want to leave a message or book an appointment.";

      var reply = await _api.sendMessage(message: prompt);
      // FIX (Sep 1 2026 — found in the call logs, not guessed): this
      // guard used to match four hardcoded fragments ('not switched
      // on', 'could not reach', 'Full AI', empty). The real message the
      // API layer returns when no key is set is "Admin AI is not
      // configured yet — add GROQ_API_KEY before this can respond." —
      // which matches NONE of them, so a raw English developer error
      // was read aloud to a customer verbatim (visible at 16:03:34 in
      // the debug logs). Matching on the shape of a config/error
      // message instead of four exact phrases keeps the next such
      // message from leaking the same way.
      if (_looksLikeSystemError(reply)) {
        await _log('[ChittiCallScreeningService] AI reply looked like a system/config '
            'error — substituting the natural fallback. Raw was: $reply');
        reply = _languageCode == 'ta'
            ? "சரிங்க பாஸ், உங்க செய்தியை நான் குறித்துக்கொண்டேன். பாஸ் உங்களை உடனே தொடர்புகொள்வார்."
            : "Alright, I've noted down your message. Nizam will call you back soon.";
      }
      await _log('[ChittiCallScreeningService] Chitti reply: $reply');

      _conversation.add('Assistant: $reply');
      await _speak(reply);
    } catch (e) {
      final fallbackReply = _languageCode == 'ta'
          ? "சரிங்க பாஸ், உங்க செய்தியை நான் சேவ் பண்ணிக்கிறேன். பாஸ் உங்ககிட்ட பேசுவார்."
          : "Alright, I'll save your message. Nizam will get back to you.";
      _conversation.add('Assistant: $fallbackReply');
      await _speak(fallbackReply);
    }

    final lowerMsg = message.toLowerCase();
    final wantsToEnd = lowerMsg.contains('thank') || 
                      lowerMsg.contains('நன்றி') || 
                      lowerMsg.contains('bye') || 
                      lowerMsg.contains('ok') || 
                      lowerMsg.contains('சரி');

    if (wantsToEnd) {
      await _saveAppointment();
      stopScreening();
    } else {
      if (_isScreening) {
        _listenLoop();
      }
    }
  }

  /// Asks the AI for a short, admin-readable summary of what the caller
  /// actually wanted. Falls back to the offline heuristic summarizer
  /// whenever the AI is unreachable or answers with a config/system
  /// error — the transcript is worth saving either way, and a call
  /// summary that says "add GROQ_API_KEY" would be worse than useless.
  Future<String> _buildConversationSummary(String transcript) async {
    final heuristic = ChittiSummarizer.heuristicSummary(
      sender: _callerNumber,
      message: transcript,
      isTamil: _languageCode == 'ta',
    );
    if (_conversation.length < 2) return heuristic;

    try {
      final languageName = _languageCode == 'ta' ? 'Tamil' : 'English';
      final prompt = 'Summarize this phone call for the business owner in '
          'ONE short $languageName sentence. Say what the caller wanted and '
          'anything they need done. Do not add greetings or commentary.\n\n'
          '$transcript';
      final aiSummary = await _api.sendMessage(message: prompt);
      if (_looksLikeSystemError(aiSummary)) {
        await _log('[ChittiCallScreeningService] AI summary unavailable — using offline summary.');
        return heuristic;
      }
      return aiSummary.trim();
    } catch (e) {
      await _log('[ChittiCallScreeningService] AI summary failed ($e) — using offline summary.');
      return heuristic;
    }
  }

  Future<void> _saveAppointment({String? recordingPath}) async {
    try {
      final transcript = _conversation.join('\n');
      final summary = await _buildConversationSummary(transcript);
      String? localTranscriptPath;

      // NEW (Sep 1 2026 — Nizam: "conversation end la customer and
      // chitti yenna pandrangalo atha summerize panni admin phone la
      // text ah store pannirlam").
      //
      // The transcript file used to be written ONLY when a recording
      // existed, because its path was derived from the .m4a filename.
      // Full-conversation mode now deliberately runs WITHOUT the
      // recorder (SpeechRecognizer needs the microphone — see
      // PhoneCallService.onCallConnected), so that condition would have
      // meant the one mode that actually produces a conversation saves
      // no local text at all. The file now always gets written, using
      // the recording's name when there is one and its own timestamped
      // name when there isn't.
      try {
        String transcriptPath;
        if (recordingPath != null && recordingPath.isNotEmpty) {
          transcriptPath = recordingPath.replaceAll(
            RegExp(r'\.m4a$', caseSensitive: false),
            '_transcript.txt',
          );
        } else {
          final dir = await _transcriptDirectory();
          final now = DateTime.now();
          String two(int n) => n.toString().padLeft(2, '0');
          final stamp = '${now.year}${two(now.month)}${two(now.day)}_'
              '${two(now.hour)}${two(now.minute)}${two(now.second)}';
          final who = _callerNumber.replaceAll(RegExp('[^0-9+]'), '');
          transcriptPath = '$dir/Call_${who.isEmpty ? 'unknown' : who}_${stamp}_transcript.txt';
        }

        final transcriptFile = File(transcriptPath);
        await transcriptFile.parent.create(recursive: true);
        final now = DateTime.now();

        final content = StringBuffer()
          ..writeln('==================================================')
          ..writeln('Allin1 AI Call Assistant Transcript')
          ..writeln('==================================================')
          ..writeln('Caller: ${_callerNumber.isEmpty ? 'Unknown' : _callerNumber}')
          ..writeln('Date: ${now.toIso8601String()}')
          ..writeln('Summary: $summary')
          ..writeln('Audio File: ${recordingPath ?? '(not recorded — conversation mode)'}')
          ..writeln('--------------------------------------------------')
          ..writeln('Full Conversation:')
          ..writeln(transcript.isEmpty ? '(no speech captured)' : transcript)
          ..writeln('==================================================');

        await transcriptFile.writeAsString(content.toString());
        localTranscriptPath = transcriptPath;
        await _log('[ChittiCallScreeningService] Saved transcript to: $transcriptPath');
      } catch (e) {
        await _log('[ChittiCallScreeningService] Failed to write transcript file: $e');
      }

      await FirebaseFirestore.instance.collection('chitti_appointments').add({
        'name': 'Phone Caller',
        'phone': _callerNumber,
        // `summary` is now the one-line AI/heuristic summary an admin can
        // scan; the raw back-and-forth moved to its own field so the
        // Conversations screen can show both without re-parsing.
        'summary': summary,
        'transcript': transcript,
        'turnCount': _conversation.length,
        'localAudioPath': recordingPath,
        'localTranscriptPath': localTranscriptPath,
        'isRecorded': recordingPath != null,
        'timestamp': FieldValue.serverTimestamp(),
      });
      await _log('[ChittiCallScreeningService] Saved appointment to Firestore');
    } catch (e) {
      await _log('[ChittiCallScreeningService] Failed to save appointment: $e');
    }
  }

  /// Same Allin1_Calls/yyyy/MM folder the native recorder writes into,
  /// so transcripts and recordings stay together in the file manager.
  Future<String> _transcriptDirectory() async {
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final base = Platform.isAndroid
        ? '/storage/emulated/0/Android/data/com.njtech.admininallin1/files'
        : (await getApplicationDocumentsDirectory()).path;
    return '$base/Allin1_Calls/${now.year}/${two(now.month)}';
  }

  void stopScreening({String? recordingPath}) {
    _isScreening = false;
    _screeningTimeoutTimer?.cancel();
    _screeningTimeoutTimer = null;
    _errorRetryCount = 0;
    try {
      if (_speech.isListening) {
        _speech.stop();
      }
      _speech.cancel();
      ChittiAccessibilityBridge.instance.stopCallVoice();
      ChittiAccessibilityBridge.instance.resetAudioMode();
    } catch (_) {}
    if (_conversation.isNotEmpty) {
      _saveAppointment(recordingPath: recordingPath);
    }
    // Session is closed only AFTER this final line is written, so
    // "Call screening finished" still lands inside this call's group
    // rather than starting an orphan one.
    _log('[ChittiCallScreeningService] Call screening finished')
        .whenComplete(endSession);
  }
}
