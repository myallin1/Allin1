// ================================================================
// AppMinimizer — "System Back Button Overhaul" (all 4 apps)
// ================================================================
// NEW (Aug 12 2026 — CTO mandate): the shared helper every root Home
// screen (DashboardScreen, HeroDashboardShell, SellerDashboardScreen,
// SuperAdminHomeScreen) now calls instead of SystemNavigator.pop() when
// the system back button is pressed on the Home tab. Previously that
// call FINISHED the Activity (a close, not a minimize) — this is the
// direct fix for "app terminates / blank display on PWA / full
// cold-boot rebuild on reopen".
//
// Native (Android): talks to the small MethodChannel registered in
// MainActivity.kt, which calls Android's moveTaskToBack(true) directly
// — the app is sent to the background exactly like tapping the OS Home
// button, Flutter's engine/state stays alive in memory, and reopening
// from the launcher/recents resumes instantly with zero cold boot.
//
// Web/PWA: there is NO API a browser tab can call to minimize itself to
// the OS home screen — that would be a serious sandboxing violation if
// it existed (a webpage forcing itself out of view), so no browser
// exposes one. consumeWebHintOnce() below is the fallback: root screens
// show a one-time-per-session SnackBar telling the customer to use
// their device's own Home button, then swallow further back-presses
// silently for the rest of the session so it never nags.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/services.dart';

class AppMinimizer {
  AppMinimizer._();

  static const MethodChannel _channel = MethodChannel('com.njtech.allin1/minimize');

  /// Session-scoped (plain static bool, not persisted to Hive/prefs) —
  /// deliberately resets on every fresh app/tab launch, so a customer
  /// who closes and reopens the PWA sees the hint again exactly once,
  /// rather than never again on that device.
  static bool _webHintShown = false;

  /// Sends the app to the background on native Android via
  /// moveTaskToBack(true). No-ops on web — see the class comment above
  /// for why a browser tab genuinely cannot do this.
  static Future<void> moveToBackground() async {
    if (kIsWeb) return;
    try {
      await _channel.invokeMethod<void>('moveTaskToBack');
    } catch (_) {
      // Best-effort — a failed minimize should never crash or block the
      // back gesture; worst case that one press is a no-op and the
      // customer just tries again.
    }
  }

  /// Returns true exactly ONCE per app session — the caller uses this
  /// to decide whether to show the web-only "press your device's Home
  /// button to minimize" SnackBar. Every call after the first returns
  /// false, so repeated back-presses on web are silently swallowed
  /// instead of spamming the SnackBar.
  static bool consumeWebHintOnce() {
    if (_webHintShown) return false;
    _webHintShown = true;
    return true;
  }
}
