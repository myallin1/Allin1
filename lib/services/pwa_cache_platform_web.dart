// ================================================================
// pwa_cache_platform_web.dart
// Web implementation — Flutter 3.22+ compatible
// Uses package:web instead of deprecated dart:html
// ================================================================

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class PwaCachePlatform {
  /// Clears cached assets and hard-reloads to the newest deploy.
  /// Safe to call only on web — the stub does nothing on mobile.
  ///
  /// The old version ALSO unregistered every service worker before
  /// reloading. That caused a blank screen: Flutter's deployed service
  /// worker unregisters ITSELF on activate and navigates its clients to
  /// reload, so unregistering it from here at the same moment set off
  /// two teardown-and-reload sequences racing each other, and the page
  /// came back empty.
  ///
  /// Clearing Cache Storage is enough to guarantee fresh assets on the
  /// next load; the service worker is left alone to manage its own
  /// lifecycle. Then a plain reload picks up the new build.
  // sessionStorage key set right before a self-triggered reload, so the
  // very next page load can show a one-time "Welcome to the new
  // version!" popup and then clear the flag. sessionStorage (not
  // localStorage) is deliberate: it survives exactly the one reload we
  // do here and nothing more, so a customer who closes the tab and
  // reopens days later never sees a stale "you're on the new version"
  // popup.
  static const String _justUpdatedKey = 'a1_pwa_just_updated';

  Future<void> clearAndReload() async {
    try {
      final cacheKeys = await web.window.caches.keys().toDart;
      for (final key in cacheKeys.toDart) {
        await web.window.caches.delete(key.toDart).toDart;
      }
    } catch (_) {
      // Reload even if the cache clear fails.
    }

    try {
      web.window.sessionStorage.setItem(_justUpdatedKey, '1');
    } catch (_) {
      // Non-fatal -- worst case the welcome-back popup just doesn't show.
    }

    // FIX (CTO QA — "infinite reload loop"): Cache Storage (cleared
    // above) is a completely different cache from the browser's normal
    // HTTP cache. A plain location.reload() can still be served a
    // stale index.html/main.dart.js straight out of HTTP cache, since
    // modern browsers dropped the old force-bypass-cache parameter on
    // Location.reload(). Navigating to a cache-busted URL instead
    // guarantees the browser treats this as a brand-new resource and
    // goes to the network, so the loop can't happen.
    final base = web.window.location.href.split('#').first.split('?').first;
    final bust = DateTime.now().millisecondsSinceEpoch;
    web.window.location.href = '$base?a1_upd=$bust';
  }

  /// Returns true (once) if the current page load happened right after
  /// this class triggered a self-update reload, then clears the flag so
  /// it never fires again until the next real update. Used to show the
  /// one-time "Welcome to the new version!" popup.
  bool consumeJustUpdatedFlag() {
    try {
      final was = web.window.sessionStorage.getItem(_justUpdatedKey) != null;
      if (was) {
        web.window.sessionStorage.removeItem(_justUpdatedKey);
      }
      return was;
    } catch (_) {
      return false;
    }
  }
}
