// ================================================================
// chitti_wakeword_service.dart — "Hey Chitti" background wake-word
// (Admin app only)
// ================================================================
// NEW (Sep 22 2026 — Nizam: "hey chitti nu nan kupta mattum chitti
// wake agi sollunga boss nan yenna pannanum nu kekkanum", chose
// "app background-layum (like Google Assistant)... venumna mattum
// on/off panni battery wastage kurachalam").
//
// WHY PORCUPINE AND NOT JUST speech_to_text LEFT RUNNING
// speech_to_text is a full recognition engine — running it
// continuously in the background to catch one phrase would cost
// exactly the battery Nizam asked to avoid. Picovoice's Porcupine is a
// dedicated wake-word ENGINE, built for always-on listening at ~1-2mW
// (the same class of tech behind "Hey Google"/"Alexa"): it does almost
// nothing until the specific trained phrase is heard, then hands off
// to the real assistant (here, GuruOverlayService).
//
// A REAL EXTERNAL STEP NIZAM STILL HAS TO DO
// "Hey Chitti" is not one of Porcupine's built-in wake words — it
// needs a custom `.ppn` model file, trained per platform, via the free
// Picovoice Console (console.picovoice.ai): sign in, type "Hey
// Chitti", download the Android/iOS model files, and generate an
// AccessKey. That is a web-console action only Nizam can do (an
// account signup), not something this code can do for him. Until
// those real files replace the placeholders below and
// PICOVOICE_ACCESS_KEY is set in .env, this service fails safe (see
// start() below) — no crash, just an inactive toggle.
//
// WHY THE GREETING IS SEQUENTIAL, NOT PARALLEL WITH THE MIC
// See GuruOverlayService.wakeAndGreet()'s own header — speaks the
// greeting to completion BEFORE the mic starts, so there is no window
// where the mic could hear Chitti's own "Sollunga boss" and treat it
// as the customer's first request.
import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:porcupine_flutter/porcupine_manager.dart';
import 'package:provider/provider.dart';

import '../app_navigator.dart';
import 'guru_overlay_service.dart';
import 'localization_service.dart';

class ChittiWakeWordService {
  ChittiWakeWordService._();
  static final ChittiWakeWordService instance = ChittiWakeWordService._();

  // Placeholders — see this file's header. Nizam replaces these with
  // the real Picovoice Console downloads for "Hey Chitti".
  static const String _androidKeywordAsset =
      'assets/wakeword/chitti_wakeword_android.ppn';
  static const String _iosKeywordAsset =
      'assets/wakeword/chitti_wakeword_ios.ppn';

  PorcupineManager? _manager;
  bool _starting = false;

  bool get isActive => _manager != null;

  /// Non-fatal by design, same contract as every other Chitti
  /// background service in this app (ChittiDevWatchService,
  /// ChittiErrorWatchService): a missing AccessKey, missing model
  /// file, or denied mic permission must never crash the app or block
  /// sign-in — it just leaves the wake-word feature quietly inactive.
  Future<void> start() async {
    if (_manager != null || _starting) return;
    _starting = true;
    try {
      final accessKey = dotenv.env['PICOVOICE_ACCESS_KEY']?.trim() ?? '';
      if (accessKey.isEmpty) {
        debugPrint(
          '[ChittiWakeWordService] PICOVOICE_ACCESS_KEY not set in .env — '
          'wake-word stays inactive until Nizam adds one from '
          'console.picovoice.ai.',
        );
        return;
      }
      final keywordAsset = Platform.isIOS ? _iosKeywordAsset : _androidKeywordAsset;
      _manager = await PorcupineManager.fromKeywordPaths(
        accessKey,
        [keywordAsset],
        _onWakeWordDetected,
        errorCallback: (error) {
          debugPrint('[ChittiWakeWordService] runtime error: ${error.message}');
        },
      );
      await _manager!.start();
      debugPrint('[ChittiWakeWordService] Listening for Hey Chitti.');
    } catch (e) {
      // Covers: invalid/expired AccessKey, missing or corrupt .ppn
      // asset, mic permission denied — all real possibilities before
      // Nizam has finished the Picovoice Console setup, none of them
      // should ever be fatal.
      debugPrint('[ChittiWakeWordService] start() failed (non-fatal): $e');
      _manager = null;
    } finally {
      _starting = false;
    }
  }

  Future<void> stop() async {
    final manager = _manager;
    _manager = null;
    if (manager == null) return;
    try {
      await manager.stop();
      await manager.delete();
      debugPrint('[ChittiWakeWordService] Stopped.');
    } catch (e) {
      debugPrint('[ChittiWakeWordService] stop() failed (non-fatal): $e');
    }
  }

  void _onWakeWordDetected(int keywordIndex) {
    final isTamil = _currentLanguageIsTamil();
    final greeting = isTamil
        ? 'சொல்லுங்க பாஸ், நான் என்ன பண்ணனும்?'
        : 'Sollunga boss, what should I do?';
    unawaited(GuruOverlayService.instance.wakeAndGreet(greeting));
  }

  /// Reads the app's current language outside any widget context —
  /// LocalizationService is a Provider-scoped ChangeNotifier, not a
  /// global singleton, and this callback fires from a native platform
  /// channel with no BuildContext of its own. navigatorKey's own
  /// context is the app's root, which sits inside the same Provider
  /// tree every screen does.
  bool _currentLanguageIsTamil() {
    try {
      final ctx = navigatorKey.currentContext;
      if (ctx == null) return false;
      return ctx.read<LocalizationService>().languageCode == 'ta';
    } catch (_) {
      return false;
    }
  }
}
