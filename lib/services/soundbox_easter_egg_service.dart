// ================================================================
// soundbox_easter_egg_service.dart
// 33 taps → permanent hide via SharedPreferences
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class SoundboxEasterEggService extends ChangeNotifier {
  static const String _kHiddenKey = 'soundbox_egg_hidden_forever';
  static const String _kTapKey = 'soundbox_egg_tap_count';
  static const int _kTargetTaps = 33;

  int _tapCount = 0;
  bool _isHiddenGlobally = false;
  bool _initialized = false;

  int get tapCount => _tapCount;
  bool get isHiddenGlobally => _isHiddenGlobally;
  bool get initialized => _initialized;

  // ── Call once at app startup (e.g., in main.dart or ChangeNotifierProvider) ─
  Future<void> init() async {
    if (_initialized) {
      return;
    }
    final prefs = await SharedPreferences.getInstance();
    _isHiddenGlobally = prefs.getBool(_kHiddenKey) ?? false;
    _tapCount = prefs.getInt(_kTapKey) ?? 0;
    _initialized = true;
    notifyListeners();
  }

  // ── Called every time the bouncing button is tapped ──────────────
  Future<void> registerTap() async {
    if (_isHiddenGlobally) return; // already permanently hidden

    _tapCount += 1;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    // Persist running count so partial progress survives restarts
    await prefs.setInt(_kTapKey, _tapCount);

    if (_tapCount >= _kTargetTaps) {
      await hideGlobally();
    }
  }

  // ── Permanently hide — writes to SharedPreferences ───────────────
  Future<void> hideGlobally() async {
    if (_isHiddenGlobally) {
      return;
    }
    _isHiddenGlobally = true;
    notifyListeners();

    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kHiddenKey, true);
    // Keep tap count stored for audit/debug, but button is gone forever
  }

  // ── Dev/debug reset (remove before production if not needed) ─────
  Future<void> debugReset() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kHiddenKey);
    await prefs.remove(_kTapKey);
    _tapCount = 0;
    _isHiddenGlobally = false;
    notifyListeners();
  }
}
