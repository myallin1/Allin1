// ================================================================
// pwa_cache_platform_web.dart
// Web implementation — Flutter 3.22+ compatible
// Uses package:web instead of deprecated dart:html
// ================================================================

import 'dart:async';
import 'dart:js_interop';

import 'package:web/web.dart' as web;

class PwaCachePlatform {
  /// Unregisters all service workers and hard-reloads the page.
  /// Safe to call only on web — stub does nothing on mobile.
  Future<void> clearAndReload() async {
    try {
      // Step 1: Unregister all service worker registrations
      final registrations =
          await web.window.navigator.serviceWorker.getRegistrations().toDart;
      for (final reg in registrations.toDart) {
        await reg.unregister().toDart;
      }

      // Step 2: Clear all Cache Storage caches
      final cacheKeys = await web.window.caches.keys().toDart;
      for (final key in cacheKeys.toDart) {
        await web.window.caches.delete(key.toDart).toDart;
      }
    } catch (_) {
      // Silently continue — reload even if cache clear fails
    }

    // Step 3: Hard reload
    web.window.location.reload();
  }
}
