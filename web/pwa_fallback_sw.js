// ================================================================
// pwa_fallback_sw.js
// ================================================================
// FIX (Aug 8 2026 — Nizam's request: "namma pwa vayum mobile app mari
// pannanum... net ilana open agamattingithu"): this file used to be
// deliberately a no-op (see the OLD comment history below, kept for
// context) — it registered a fetch listener but never called
// respondWith(), so the PWA had ZERO offline capability: no internet,
// no app at all, unlike a real installed mobile app.
//
// That was a deliberate trade-off at the time, made to kill a WORSE
// bug: Flutter's own generated flutter_service_worker.js precaches
// main.dart.js and then self-unregisters + force-reloads every
// controlled client on activate — combined with a stale worker
// surviving on a device from before a fix, that caused main.dart.js to
// be served from an ancient precache FOREVER, immune to rebuilds,
// redeploys, and even manual hard-reloads (the multi-day
// MissingPluginException saga earlier this session traced back to
// exactly this). Registering nothing but an inert worker was the
// simplest way to guarantee that could never happen again.
//
// This version restores real offline capability (WhatsApp-style: the
// app SHELL opens with no network at all) WITHOUT reintroducing either
// of the two bug classes above:
//
//   1. "stale JS served forever, ignoring redeploys" — avoided by using
//      a NETWORK-FIRST strategy for every same-origin GET request. As
//      long as the device is online, the freshest file is always
//      fetched from the network FIRST and returned to the page; the
//      cache is only ever consulted when that network fetch actually
//      fails. So on every normal online visit, behavior is IDENTICAL
//      to today (Firebase Hosting's no-cache headers + a fresh fetch
//      every time) — nothing can go stale-while-online the way
//      flutter_service_worker.js's precache-then-serve-forever
//      approach did.
//   2. "force-reload interrupts mid-boot" — this worker never
//      navigates, reloads, or messages any client to reload. New
//      versions of THIS FILE (if it's ever edited again) take over via
//      skipWaiting()/clients.claim() below, same as before — but that
//      only changes which worker handles the NEXT fetch, it does not
//      reload any already-open tab.
//
// CACHE VERSIONING: bump CACHE_VERSION only when the PRECACHE_URLS list
// itself changes — NOT on every app deploy (that's already handled by
// the network-first strategy above, independent of this version).
// Bumping it deletes the previous cache entirely on activate so old
// and new cache entries can never mix.
// ================================================================

// ================================================================
// CACHE_VERSION — STAMPED PER FLAVOR + PER DEPLOY by deploy_web.ps1
// ================================================================
// FIX (Aug 11 2026 — Nizam: "customer app build pannalum admin app than
// open aguthu", still happening AFTER a correct rebuild+redeploy):
//
// ROOT CAUSE — a poisoned cache, not a bad deploy. When the wrong build
// once shipped to the customer URL, that origin's cache stored ADMIN's
// main.dart.js. Because heavy bundles now use stale-while-revalidate
// (added the same day), the service worker serves that CACHED bundle
// instantly on every launch and only refreshes in the background. And
// since CACHE_VERSION was a hardcoded constant, a fresh deploy reused
// the very same cache — so the customer kept booting into Admin no
// matter how many times the correct build was deployed. The deploy was
// fine; the browser never looked at it.
//
// FIX: deploy_web.ps1 rewrites the placeholder below with
// "<flavor>-<timestamp>" for every build. Two guarantees follow:
//   1. Different flavor  => different cache name => a bundle from
//      another app can NEVER be served under this origin.
//   2. Every deploy      => new cache name => activate() purges the old
//      one (see the keys().filter() sweep further down), so a fresh
//      deploy is picked up on the FIRST launch, not the second.
//
// The literal fallback keeps this file valid if it is ever loaded
// unstamped (e.g. `flutter run` locally, without the deploy script).
const CACHE_VERSION = '__ALLIN1_CACHE_VERSION__'.indexOf('__') === 0
  ? 'allin1-dev-local'
  : '__ALLIN1_CACHE_VERSION__';

// Minimum set precached on install so the app SHELL can paint with
// zero network — deliberately small (large/rarely-needed assets like
// the splash video, per-flavor manifest, and fonts are cached
// opportunistically by the fetch handler below on first real visit
// instead), so install can never fail or slow down because one of
// these 404s on a given flavor's deployment.
const PRECACHE_URLS = [
  '/',
  '/index.html',
  '/flutter_bootstrap.js',
  '/flutter.js',
  '/manifest.json',
  '/favicon.png',
  // ADDED (Aug 11 2026 — Nizam's offline-first requirement): without
  // main.dart.js in the cache the app CANNOT boot offline at all. The
  // shell would load, then die waiting for the engine.
  //
  // It was previously left to opportunistic caching on first fetch,
  // which is *usually* fine — but "usually" is not an offline
  // guarantee: a customer who first-loads on a flaky connection could
  // end up with a cached shell and no engine, i.e. a permanently blank
  // app the next time they open it with no signal. Precaching it makes
  // offline boot deterministic.
  //
  // Note this makes install heavier (~5.9 MB). That is the correct
  // trade for an offline-first app, and the per-URL cache.add() below
  // means a failure here still can't break the whole install.
  '/main.dart.js',
];

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE_VERSION).then((cache) => {
      // Per-URL add (not cache.addAll) so one missing/renamed asset on
      // a given flavor's deploy can never fail the whole precache.
      return Promise.all(
        PRECACHE_URLS.map((url) =>
          cache.add(url).catch((err) => {
            console.warn('[pwa_fallback_sw] precache skip:', url, err);
          })
        )
      );
    })
  );
  // Take over immediately rather than waiting for existing tabs to
  // close — same as this file did before. This does NOT reload any
  // open tab; it only means this worker starts handling the NEXT
  // fetch from any client sooner.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    Promise.all([
      // Drop any cache from a previous CACHE_VERSION so stale and
      // fresh entries never coexist.
      caches.keys().then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_VERSION)
            .map((key) => caches.delete(key))
        )
      ),
      self.clients.claim(),
    ])
  );
});

self.addEventListener('fetch', (event) => {
  const req = event.request;

  // Only ever handle GET — POST/PUT (Firestore/RTDB SDK calls, any
  // REST API call) are never intercepted, exactly as before.
  if (req.method !== 'GET') return;

  // Only ever cache THIS origin's own app-shell files — Firebase,
  // Cloudinary, Ola Maps, Google Fonts, and every other third-party
  // request is left completely untouched, same as before.
  const url = new URL(req.url);
  if (url.origin !== self.location.origin) return;

  // ================================================================
  // PURE CACHE-FIRST for the big immutable bundles ("Extreme Bandwidth
  // Caching" — zero-budget escape hatch, Aug 12 2026)
  // ================================================================
  // FIX (Aug 11 2026 — Nizam: "app open pannuna 5 to 8 sec white display
  // va ninnu than open aguthu"): originally fixed with stale-while-
  // revalidate — serve the cached copy immediately, but still fire a
  // background fetch every single launch to refresh it for next time.
  // That solved the white-screen delay, but it means a RETURNING
  // customer's device still downloads the full ~5.9 MB main.dart.js
  // (plus fonts/canvaskit) on every single app open, just silently in
  // the background — real Hosting bandwidth spent for zero visible
  // benefit on a Spark plan with a hard monthly cap.
  //
  // UPGRADED (Aug 12 2026 — CTO mandate, "Extreme Bandwidth Caching":
  // "Ensure the PWA Service Worker is aggressively caching... so that
  // returning users consume absolutely 0 bytes of Firebase Hosting
  // bandwidth"): now pure cache-first — if a cached copy exists, serve
  // it and NEVER touch the network for it, full stop. Only a true cache
  // miss (first-ever visit under this CACHE_VERSION) reaches the
  // network.
  //
  // This is safe against ever serving stale JS forever (the exact bug
  // this file's network-first design originally existed to prevent) for
  // a reason that did NOT exist when stale-while-revalidate was chosen:
  // CACHE_VERSION is now stamped "<flavor>-<timestamp>" by
  // deploy_web.ps1 on every single deploy (see the CACHE_VERSION
  // comment above), so a real redeploy always gets a brand-new, empty
  // cache — there is nothing to cache-first-serve stale bytes FROM.
  // Every redeploy still forces exactly one fresh download per file,
  // same as before; only the "N background refreshes between deploys"
  // cost is what's being eliminated here.
  //
  // Deliberately scoped to the heavy, content-addressed bundles only.
  // index.html and version.json stay network-first below (see the fetch
  // handler's default branch), so web_version_checker.dart's update
  // DETECTION is completely unaffected by this change.
  const isHeavyBundle =
    url.pathname.endsWith('/main.dart.js') ||
    url.pathname.endsWith('.otf') ||
    url.pathname.endsWith('.ttf') ||
    url.pathname.includes('/canvaskit/');

  if (isHeavyBundle) {
    event.respondWith(
      caches.match(req).then((cached) => {
        if (cached) {
          // Cache hit — the whole point of this branch. Zero bytes over
          // the network for this file on this launch.
          return cached;
        }
        // Cache miss — first time this exact file has been requested
        // under the current CACHE_VERSION (fresh install, or the first
        // launch right after a redeploy). Fetch once and cache it so
        // every subsequent launch until the next deploy is a pure hit.
        return fetch(req).then((res) => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_VERSION).then((cache) => cache.put(req, clone));
          }
          return res;
        });
      })
    );
    return;
  }

  event.respondWith(
    fetch(req)
      .then((networkResponse) => {
        // Network succeeded — the common/online case. Opportunistically
        // refresh the cache with this response so the offline fallback
        // stays reasonably recent, without ever delaying or altering
        // the response actually returned to the page.
        if (networkResponse && networkResponse.status === 200) {
          const clone = networkResponse.clone();
          caches.open(CACHE_VERSION).then((cache) => cache.put(req, clone));
        }
        return networkResponse;
      })
      .catch(() => {
        // Network failed — genuinely offline, or a dropped connection.
        // Fall back to whatever this origin's cache already has for
        // this exact request...
        return caches.match(req).then((cached) => {
          if (cached) return cached;
          // ...and if this specific file was never cached (e.g. a deep
          // link never visited before going offline), fall back to the
          // cached app shell itself for navigation requests, so the
          // app still OPENS — same as a real installed app — instead
          // of the browser's own "no internet" error page.
          if (req.mode === 'navigate') {
            return caches.match('/').then((shell) => {
              return shell || new Response('', { status: 504, statusText: 'Offline' });
            });
          }
          return new Response('', { status: 504, statusText: 'Offline' });
        });
      })
  );
});

self.addEventListener('message', (event) => {
  // Kept for parity with flutter_service_worker.js's message contract.
  // Nothing in the app sends this any more — update detection lives in
  // web_version_checker.dart, which compares /version.json and never
  // talks to a service worker — but a stray message shouldn't be an
  // unhandled event.
  if (event.data && event.data.action === 'skipWaiting') {
    self.skipWaiting();
  }
});
