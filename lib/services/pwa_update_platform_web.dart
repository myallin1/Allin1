// ================================================================
// pwa_update_platform_web.dart
// Reads the real PWA update-available flag set by web/index.html's
// service-worker registration script (window.allin1UpdateAvailable),
// and applies the update by calling window.allin1ApplyUpdate() —
// which tells the waiting service worker to skipWaiting(). That
// triggers index.html's existing `controllerchange` listener, which
// reloads the page once the new worker takes control.
//
// This is the real signal — it only fires when a genuinely new
// deploy has been installed and is waiting. It replaces the old
// dashboard_screen.dart behaviour of showing the "UPDATE" button
// unconditionally on web, whether or not an update actually existed.
// ================================================================
import 'dart:js_interop';

@JS('allin1UpdateAvailable')
external JSBoolean? get _allin1UpdateAvailableJS;

@JS('allin1ApplyUpdate')
external void _allin1ApplyUpdateJS();

class PwaUpdatePlatform {
  /// True only when web/index.html's service-worker script has detected
  /// a genuinely new, installed-and-waiting version.
  bool get isUpdateAvailable => _allin1UpdateAvailableJS?.toDart ?? false;

  /// Tells the waiting service worker to activate. index.html's
  /// `controllerchange` listener reloads the page once it takes over.
  void applyUpdate() => _allin1ApplyUpdateJS();
}
