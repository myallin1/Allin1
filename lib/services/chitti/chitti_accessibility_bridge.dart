import 'dart:convert';
import 'package:flutter/services.dart';

import 'chitti_call_screening_service.dart';

class ChittiAccessibilityBridge {
  ChittiAccessibilityBridge._();

  static final instance = ChittiAccessibilityBridge._();

  static const _channel = MethodChannel('com.njtech.allin1/accessibility');

  // Callback to handle incoming voice commands from the floating bubble
  void Function(String)? onVoiceCommandReceived;

  /// Fires when the system's assistant gesture (power-button long-press,
  /// home-swipe) invokes ChittiVoiceInteractionSession — including from
  /// the lock screen. No spoken text comes with this one: it means "the
  /// admin wants Chitti, open the panel and start listening now."
  void Function()? onAssistTriggered;

  /// Callback when a new SMS arrives via SmsReceiver
  void Function(String sender, String body)? onSmsReceived;

  /// NEW (Sep 1 2026 — in-call screen): fires when the admin taps the
  /// ongoing-call notification, so the app can open the live call UI.
  void Function()? onOpenInCallScreen;

  /// NEW (Sep 2 2026 — launcher "Dialer" shortcut): fires when the
  /// admin taps the static shortcut on the app icon.
  void Function()? onOpenDialerScreen;

  /// NEW (Sep 1 2026 — native call-voice TTS): fires with "START",
  /// "DONE", or "ERROR..." as ChittiCallVoice's native TextToSpeech
  /// instance progresses through speaking — see [speakOnCallStream].
  void Function(String event)? onCallVoiceEvent;

  void initialize() {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onVoiceCommand') {
        final args = call.arguments as Map?;
        final command = args?['command'] as String?;
        if (command != null && onVoiceCommandReceived != null) {
          onVoiceCommandReceived!(command);
        }
      } else if (call.method == 'onAssistTriggered') {
        onAssistTriggered?.call();
      } else if (call.method == 'onSmsReceived') {
        final args = call.arguments as Map?;
        final sender = args?['sender'] as String? ?? 'Unknown';
        final body = args?['body'] as String? ?? '';
        onSmsReceived?.call(sender, body);
      } else if (call.method == 'onOpenInCallScreen') {
        onOpenInCallScreen?.call();
      } else if (call.method == 'onOpenDialerScreen') {
        onOpenDialerScreen?.call();
      } else if (call.method == 'onCallVoiceEvent') {
        final args = call.arguments as Map?;
        final event = args?['event'] as String? ?? 'unknown';
        onCallVoiceEvent?.call(event);
      } else if (call.method == 'onCallStateChanged') {
        final args = call.arguments as Map?;
        final event = args?['event'] as String?;
        final number = args?['number'] as String?;
        final recordingPath = args?['recordingPath'] as String?;
        // A 'connected' event is the START of a call — open the session
        // BEFORE logging, so this line lands inside the new call's group
        // rather than trailing the previous call's.
        if (event == 'connected' && ChittiCallScreeningService.currentSessionId == null) {
          ChittiCallScreeningService.beginSession(number ?? '');
        }
        await ChittiCallScreeningService.writeLog(
          '[Bridge] Received onCallStateChanged event: $event, rec: $recordingPath',
          callerNumber: number,
        );
        if (event == 'connected') {
          await ChittiCallScreeningService.instance.startScreening(number ?? '');
        } else if (event == 'ended') {
          ChittiCallScreeningService.instance.stopScreening(recordingPath: recordingPath);
        }
      }
      return null;
    });

    // Cold-start pull check: request the current active call state right after registration
    // to see if we missed the call connected event during engine boot
    Future.microtask(() async {
      try {
        final activeState = await _channel.invokeMapMethod<String, String>('getActiveCallState');
        final event = activeState?['event'];
        final number = activeState?['number'];
        if (event == 'connected' && number != null && ChittiCallScreeningService.currentSessionId == null) {
          ChittiCallScreeningService.beginSession(number);
        }
        await ChittiCallScreeningService.writeLog(
          '[Bridge] Cold-start pull completed. activeState=$event, number=$number',
          callerNumber: number,
        );
        if (event == 'connected' && number != null) {
          await ChittiCallScreeningService.instance.startScreening(number);
        }
      } catch (_) {}
    });
  }

  Future<bool> isPermissionGranted() async {
    try {
      final res = await _channel.invokeMethod<bool>('isPermissionGranted');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> checkOverlayPermission() async {
    try {
      final res = await _channel.invokeMethod<bool>('checkOverlayPermission');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> requestOverlayPermission() async {
    try {
      await _channel.invokeMethod<void>('requestOverlayPermission');
    } catch (_) {}
  }

  Future<void> requestCallPermissions() async {
    try {
      await _channel.invokeMethod<void>('requestCallPermissions');
    } catch (_) {}
  }

  Future<Map<String, bool>> checkCallPermissions() async {
    try {
      final res = await _channel.invokeMapMethod<String, bool>('checkCallPermissions');
      return Map<String, bool>.from(res ?? {});
    } catch (_) {
      return {};
    }
  }

  // NEW (Aug 31 2026 — Option A, default-dialer role): confirmed by
  // real-device testing on both Oppo Reno7 Pro and Lenovo K9 that
  // AudioManager alone cannot route a real SIM call to the speaker —
  // only the app holding RoleManager.ROLE_DIALER can. See
  // ChittiInCallService's header (native side) for the full reasoning.
  Future<bool> isDefaultDialer() async {
    try {
      final res = await _channel.invokeMethod<bool>('isDefaultDialer');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Opens the OS "set default Phone app" dialog (or, if that path isn't
  /// available on this device, the OS's own Default Apps settings list
  /// as a fallback). Returns what actually happened — e.g. "role
  /// request dialog launched", "ROLE_DIALER not available on this
  /// device — opened Default Apps settings instead" — so the button
  /// never looks like a silent no-op again (Sep 1 2026 — Nizam: "button
  /// tap pannamudida athu dummy-ya than iruku"). The final grant/deny
  /// still isn't returned directly (it's a system dialog) — poll
  /// [isDefaultDialer] again after the admin returns to this screen.
  Future<String> requestDefaultDialerRole() async {
    try {
      final res = await _channel.invokeMethod<String>('requestDefaultDialerRole');
      return res ?? 'no outcome returned';
    } catch (e) {
      return 'requestDefaultDialerRole threw: $e';
    }
  }

  Future<void> openSettings() async {
    try {
      await _channel.invokeMethod<void>('openSettings');
    } catch (_) {}
  }

  Future<bool> clickElement(String text) async {
    try {
      final res = await _channel.invokeMethod<bool>('clickElement', {'text': text});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> inputText(String label, String text) async {
    try {
      final res = await _channel.invokeMethod<bool>('inputText', {
        'label': label,
        'text': text,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> scroll(String direction) async {
    try {
      final res = await _channel.invokeMethod<bool>('scroll', {'direction': direction});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> goBack() async {
    try {
      final res = await _channel.invokeMethod<bool>('goBack');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<bool> goHome() async {
    try {
      final res = await _channel.invokeMethod<bool>('goHome');
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<String> readScreen() async {
    try {
      final res = await _channel.invokeMethod<String>('readScreen');
      return res ?? 'Screen is empty';
    } catch (e) {
      return 'Could not read screen: $e';
    }
  }

  Future<bool> launchApp(String label) async {
    try {
      final res = await _channel.invokeMethod<bool>('launchApp', {'label': label});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  /// Returns the native side's speaker-route diagnostics string, e.g.
  /// "isDefaultDialer=true, inCallServiceBound=true, hasLiveTelecomCall=true,
  /// setAudioRoute(SPEAKER)=true" — logged straight into the call debug
  /// logs by ChittiCallScreeningService so a failure says WHICH of the
  /// four prerequisites was missing instead of just going quiet.
  Future<String> enableSpeakerphone() async {
    try {
      final res = await _channel.invokeMethod<String>('enableSpeakerphone');
      return res ?? 'no diagnostics returned';
    } catch (e) {
      return 'enableSpeakerphone threw: $e';
    }
  }

  Future<void> resetAudioMode() async {
    try {
      await _channel.invokeMethod<void>('resetAudioMode');
    } catch (_) {}
  }

  /// NEW (Sep 1 2026 — CTO/Gemini diagnosis): speaks [text] through a
  /// native TextToSpeech instance with AudioAttributes.
  /// USAGE_VOICE_COMMUNICATION (ChittiCallVoice.kt on the native side)
  /// instead of flutter_tts's hardcoded media-usage attributes, which
  /// Android's Acoustic Echo Cancellation was silencing before it
  /// reached the caller. Fire-and-forget on this call — the actual
  /// START/DONE/ERROR progress arrives via [onCallVoiceEvent].
  Future<bool> speakOnCallStream(String text, String locale) async {
    try {
      final res = await _channel.invokeMethod<bool>('speakOnCallStream', {'text': text, 'locale': locale});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> stopCallVoice() async {
    try {
      await _channel.invokeMethod<void>('stopCallVoice');
    } catch (_) {}
  }

  /// Voicemail-style beep on the call's own audio stream — see
  /// ChittiCallVoice.playBeep. Used right after the quick-greeting so
  /// the caller gets a clear cue it's their turn to speak.
  Future<void> playCallBeep() async {
    try {
      await _channel.invokeMethod<bool>('playCallBeep');
    } catch (_) {}
  }

  // ── Minimal dialer (Sep 1 2026) ────────────────────────────────────
  // Needed because holding ROLE_DIALER makes Android stop showing its
  // own phone UI — see admin_dialer_screen.dart's header.

  /// Places a call via TelecomManager. Returns a human-readable outcome
  /// (the same "say what happened" convention as
  /// [requestDefaultDialerRole]) rather than a bare bool, so a refused
  /// permission shows up as a message instead of silence.
  Future<String> placeCall(String number) async {
    try {
      final res = await _channel.invokeMethod<String>('placeCall', {'number': number});
      return res ?? 'No response from the dialer.';
    } catch (e) {
      return 'Could not place the call: $e';
    }
  }

  Future<void> hangUpCall() async {
    try {
      await _channel.invokeMethod<void>('hangUpCall');
    } catch (_) {}
  }

  /// Starts or stops call recording mid-call. Returns whether recording
  /// is actually running afterwards — not just what was requested, so
  /// the in-call screen can't show "recording" when the recorder failed
  /// to start (the microphone may already be held by speech
  /// recognition in full-conversation mode).
  Future<bool> setCallRecording(bool enabled) async {
    try {
      final res = await _channel.invokeMethod<bool>('setCallRecording', {'enabled': enabled});
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<void> toggleSpeaker() async {
    try {
      await _channel.invokeMethod<void>('toggleSpeaker');
    } catch (_) {}
  }

  /// The live Telecom call (number/state/speakerOn), or null when there
  /// is none — distinct from [getActiveCallState], which reports the
  /// screening pipeline's own cached state.
  Future<Map<String, dynamic>?> getActiveCallInfo() async {
    try {
      final res = await _channel.invokeMapMethod<String, dynamic>('getActiveCallInfo');
      return res;
    } catch (_) {
      return null;
    }
  }

  Future<bool> sendSms(String number, String message) async {
    try {
      final res = await _channel.invokeMethod<bool>('sendSms', {
        'number': number,
        'message': message,
      });
      return res ?? false;
    } catch (_) {
      return false;
    }
  }

  Future<List<Map<String, dynamic>>> getRecentSms() async {
    try {
      final rawJson = await _channel.invokeMethod<String>('getRecentSms');
      if (rawJson == null || rawJson.isEmpty) return [];
      final decoded = jsonDecode(rawJson) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }
}
