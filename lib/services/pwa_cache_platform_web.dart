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
  /// reloading, and that was reverted at the time because it caused a
  /// blank screen — but the failure mode described below is now stale.
  /// It was written back when Flutter's OWN deployed
  /// flutter_service_worker.js was still in play, which unregisters
  /// ITSELF on activate and navigates its clients to reload — so
  /// unregistering it from here at the same moment set off two
  /// teardown-and-reload sequences racing each other. That worker is no
  /// longer registered by this app AT ALL (see web/index.html — only
  /// pwa_fallback_sw.js and firebase-messaging-sw.js are registered now,
  /// confirmed neither of them self-navigates or force-reloads any
  /// client). So the specific race this comment used to warn about
  /// cannot happen with the workers this app actually runs today.
  ///
  /// FIX (Aug 12 2026 — Nizam: "customers are stuck on older cached
  /// versions of the PWA"): ROOT CAUSE — pwa_fallback_sw.js serves
  /// main.dart.js with a stale-while-revalidate strategy (see that
  /// file's `isHeavyBundle` branch): it returns whatever is in Cache
  /// Storage IMMEDIATELY and only refreshes it in the background for
  /// NEXT time. Clearing Cache Storage here is not enough on its own,
  /// because the reload triggered below still gets INTERCEPTED by that
  /// same still-active service worker instance — and depending on the
  /// exact timing of the cache-clear promise vs. the browser issuing the
  /// reload's fetch, the very request meant to fetch the new build could
  /// still be served by the worker before its own cache is confirmed
  /// empty. Explicitly unregistering every registration before reloading
  /// removes the worker from the picture entirely for this one
  /// navigation — there is nothing left to intercept it with, so the
  /// reload is guaranteed to hit the network. index.html's own
  /// `navigator.serviceWorker.register(...)` call on `load` re-installs
  /// a fresh worker (matching the new deploy's stamped CACHE_VERSION)
  /// right after, so offline support comes back on the very next load.
  ///
  /// Clearing Cache Storage AND unregistering the worker together is
  /// what guarantees fresh assets; a plain reload then picks up the new
  /// build.
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
      // See the class-level comment above for why this is safe now (it
      // was not, for a different worker, when it was removed before).
      final regs = await web.window.navigator.serviceWorker.getRegistrations().toDart;
      for (final reg in regs.toDart) {
        await reg.unregister().toDart;
      }
    } catch (_) {
      // Non-fatal — the cache clear + cache-busted URL below still force
      // a fresh network fetch even if this step fails for any reason
      // (e.g. an older browser without the API).
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
