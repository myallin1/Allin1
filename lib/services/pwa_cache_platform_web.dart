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
  Future<void> clearAndReload() async {
    try {
      final cacheKeys = await web.window.caches.keys().toDart;
      for (final key in cacheKeys.toDart) {
        await web.window.caches.delete(key.toDart).toDart;
      }
    } catch (_) {
      // Reload even if the cache clear fails.
    }

    web.window.location.reload();
  }
}
