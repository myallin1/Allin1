// ================================================================
// admin_webview_power.dart — stop a hidden WebView from working
// ================================================================
// NEW (Sep 5 2026 — Nizam: "app unwanted heating and mobile battery
// consumption ah maximum ah disturb pannatha architecture build
// pannalam").
//
// THE PROBLEM THIS SOLVES, AND WHY FLUTTER ALONE CANNOT
// Keeping a WebView alive so a tab stays exactly where the admin left
// it has a cost that is invisible until the phone gets warm: the PAGE
// keeps running. GitHub's own JavaScript polls for live updates,
// animations keep ticking, setInterval keeps firing. None of that
// stops when the tab is covered, and none of it stops when the widget
// is unmounted either — unmounting frees the compositing surface, not
// the page.
//
// webview_flutter exposes no pause API of any kind (checked against
// webview_flutter_android 4.14.1: setBackgroundColor and permission
// handlers, nothing for lifecycle). So this goes native.
//
// WHY A THROWAWAY WebView IN KOTLIN IS THE RIGHT TRICK, NOT A HACK
// Android's WebView.pauseTimers() is documented as global: "Pauses all
// layout, parsing, and JavaScript timers for all WebViews. This is a
// global requests, not restricted to this WebView." It is an instance
// method that happens to act process-wide. That means we do not need a
// handle on the plugin's WebView at all — any instance will do, so the
// native side keeps one hidden throwaway and calls through it. This is
// why the feature needs ~20 lines of Kotlin rather than a fork of the
// plugin.
//
// NOT A TIMER, AND NOT A POLL. Every call here is edge-triggered by a
// tab becoming visible or hidden, or by the app being backgrounded. A
// power-saving feature that costs a periodic wakeup would be self-
// defeating.
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class AdminWebViewPower {
  AdminWebViewPower._();

  static const MethodChannel _channel =
      MethodChannel('com.njtech.allin1/webview_power');

  /// Tracks what the native side already believes, so repeated calls
  /// with the same value (a rebuild, a tab switch that lands back where
  /// it started) cost nothing.
  static bool? _active;

  static bool get _supported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// `true` when a WebView is on screen and should keep running;
  /// `false` when every WebView is hidden or the app is backgrounded.
  ///
  /// Never throws: failing to pause a WebView is a battery cost, not a
  /// correctness problem, and must not take a screen down with it.
  static Future<void> setActive({required bool active}) async {
    if (!_supported || _active == active) return;
    _active = active;
    try {
      await _channel.invokeMethod<void>(active ? 'resume' : 'pause');
    } catch (e) {
      // An older build without the native handler, or a detached
      // engine during teardown. Reset so a later call retries rather
      // than being suppressed by the cache above.
      _active = null;
      debugPrint('[AdminWebViewPower] ${active ? 'resume' : 'pause'}: $e');
    }
  }
}
