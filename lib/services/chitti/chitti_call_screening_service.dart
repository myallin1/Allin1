import 'dart:async';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:speech_to_text/speech_to_text.dart' as stt;
import 'package:flutter_tts/flutter_tts.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'chitti_voice_service.dart';
import 'chitti_accessibility_bridge.dart';
import 'chitti_summarizer.dart';
import '../guru_admin_api_service.dart';

class ChittiCallScreeningService {
  ChittiCallScreeningService._();
  static final ChittiCallScreeningService instance = ChittiCallScreeningService._();

  final stt.SpeechToText _speech = stt.SpeechToText();
  final FlutterTts _tts = FlutterTts();
  final GuruAdminApiService _api = GuruAdminApiService();

  bool _isScreening = false;
  String _callerNumber = '';
  final List<String> _conversation = [];
  int _turnCount = 0;
  static const int _maxTurns = 5;

  String _languageCode = 'en';

  String get _locale => switch (_languageCode) {
        'ta' => 'ta-IN',
        'hi' => 'hi-IN',
        'ml' => 'ml-IN',
        _ => 'en-US',
      };

  Timer? _screeningTimeoutTimer;
  int _errorRetryCount = 0;

  bool _ttsHandlersWired = false;

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

  void _wireTtsDebugHandlers() {
    if (_ttsHandlersWired) return;
    _ttsHandlersWired = true;
    _tts.setStartHandler(() {
      _log('[ChittiCallScreeningService] TTS engine reported START (it began speaking).');
    });
    _tts.setCompletionHandler(() {
      _log('[ChittiCallScreeningService] TTS engine reported COMPLETE.');
    });
    _tts.setErrorHandler((msg) {
      _log('[ChittiCallScreeningService] TTS engine reported ERROR: $msg');
    });
    _tts.setCancelHandler(() {
      _log('[ChittiCallScreeningService] TTS engine reported CANCEL.');
    });
  }

  Future<void> startScreening(String callerNumber) async {
    if (_isScreening) return;
    _isScreening = true;
    _callerNumber = callerNumber;
    beginSession(callerNumber);
    _conversation.clear();
    _turnCount = 0;
    _errorRetryCount = 0;
    _screeningTimeoutTimer?.cancel();
    _screeningTimeoutTimer = Timer(const Duration(seconds: 45), () {
      _log('[ChittiCallScreeningService] Auto-stopping screening after 45s inactivity.');
      stopScreening();
    });
    _wireTtsDebugHandlers();

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

    final greeting = _languageCode == 'ta'
        ? "வணக்கம், பாஸ் பிஸியா இருக்காரு. உங்க இம்போர்ட்டன்ட் தேவையை சொல்லுங்க, நான் பாஸ்கிட்ட இன்ஃபார்ம் பண்றேன்."
        : "Hello, Boss is busy right now. Please tell me your important need, I'll inform Boss.";
    _conversation.add('Assistant: $greeting');
    await _speak(greeting);
    await _log('[ChittiCallScreeningService] Quick-greeting mode: greeting played. No live conversation loop — '
        'the native call recorder is now the only thing capturing the rest of this call.');
  }

  Future<void> _speak(String text) async {
    try {
      final speakerDiag = await ChittiAccessibilityBridge.instance.enableSpeakerphone();
      await _log('[ChittiCallScreeningService] SPEAKER ROUTE: $speakerDiag');
      await ChittiVoiceService.apply(_tts, _locale, forceGoogleTts: true);
      await _log('[ChittiCallScreeningService] Calling tts.speak() now, locale=$_locale, textLen=${text.length}');
      final result = await _tts.speak(text);
      await _log('[ChittiCallScreeningService] tts.speak() returned: $result (1 = engine accepted it)');
      await _tts.awaitSpeakCompletion(true);
      await _log('[ChittiCallScreeningService] awaitSpeakCompletion finished.');
    } catch (e) {
      await _log('[ChittiCallScreeningService] speak failed: $e');
    }
  }

  void _listenLoop() async {
    if (!_isScreening) return;

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
        listenFor: const Duration(seconds: 8),
        pauseFor: const Duration(seconds: 3),
      );
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
      if (reply.contains('not switched on') || reply.contains('could not reach') || reply.contains('Full AI') || reply.trim().isEmpty) {
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

  Future<void> _saveAppointment({String? recordingPath}) async {
    try {
      final summary = _conversation.join('\n');
      String? localTranscriptPath;

      // 1. Create a clean .txt transcript file alongside the recording
      if (recordingPath != null && recordingPath.isNotEmpty) {
        try {
          final transcriptPath = recordingPath.replaceAll(
            RegExp(r'\.m4a$', caseSensitive: false),
            '_transcript.txt',
          );
          final transcriptFile = File(transcriptPath);
          final now = DateTime.now();
          final oneLine = ChittiSummarizer.heuristicSummary(
            sender: _callerNumber,
            message: summary,
            isTamil: _languageCode == 'ta',
          );

          final content = StringBuffer()
            ..writeln('==================================================')
            ..writeln('Allin1 AI Call Assistant Transcript')
            ..writeln('==================================================')
            ..writeln('Caller: $_callerNumber')
            ..writeln('Date: ${now.toIso8601String()}')
            ..writeln('Summary: $oneLine')
            ..writeln('Audio File: $recordingPath')
            ..writeln('--------------------------------------------------')
            ..writeln('Full Conversation:')
            ..writeln(summary)
            ..writeln('==================================================');

          await transcriptFile.writeAsString(content.toString());
          localTranscriptPath = transcriptPath;
          await _log('[ChittiCallScreeningService] Saved transcript to: $transcriptPath');
        } catch (e) {
          await _log('[ChittiCallScreeningService] Failed to write transcript file: $e');
        }
      }

      await FirebaseFirestore.instance.collection('chitti_appointments').add({
        'name': 'Phone Caller',
        'phone': _callerNumber,
        'summary': summary,
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
      _tts.stop();
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
