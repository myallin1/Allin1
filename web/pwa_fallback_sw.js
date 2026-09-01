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

// ================================================================
// FIREBASE HOSTING LIMIT FALLBACK (503/402 ERROR HANDLER)
// ================================================================
// When Firebase Hosting quota is exceeded, Firebase returns a 503 or 402 error.
// Instead of showing the generic Firebase error page, we intercept it and show 
// this inline HTML page prompting them to download the MyAllin1 Turbo App.
function getTurboAppFallbackHTML() {
  return `
    <!DOCTYPE html>
    <html lang="ta">
    <head>
      <meta charset="UTF-8">
      <meta name="viewport" content="width=device-width, initial-scale=1.0, maximum-scale=1.0, user-scalable=no">
      <title>MyAllin1 - System Upgrade</title>
      <link rel="preconnect" href="https://fonts.googleapis.com">
      <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
      <link href="https://fonts.googleapis.com/css2?family=Baloo+Thambi+2:wght@500;700;800;900&family=Noto+Sans+Tamil:wght@500;700;800;900&display=swap" rel="stylesheet">
      <link rel="stylesheet" href="https://mmgrapik.github.io/myallin1/css/style.css">
      <style>
        body { background: #fdf8fb; margin: 0; padding: 0; }
        .fallback-hero { padding: 4rem 1.5rem; text-align: center; display: flex; flex-direction: column; align-items: center; justify-content: center; min-height: 80vh; }
        .video-box { max-width: 300px; width: 100%; margin: 1rem auto; border-radius: 24px; overflow: hidden; box-shadow: 0 20px 40px rgba(255, 79, 163, 0.2); border: 4px solid #fff; background: #000; }
        .video-box video { width: 100%; display: block; border-radius: 20px; }
        .fallback-title { font-family: 'Baloo Thambi 2', cursive; font-size: 2.2rem; color: #b81d66; line-height: 1.2; margin-bottom: 1rem; }
        .fallback-sub { font-family: 'Noto Sans Tamil', sans-serif; font-size: 1.1rem; color: #6B7280; margin-bottom: 2.5rem; max-width: 400px; }
        .btn-download { display: inline-flex; align-items: center; justify-content: center; background: linear-gradient(135deg, #FF4FA3 0%, #FF92C8 100%); color: white; text-decoration: none; padding: 16px 32px; border-radius: 50px; font-weight: 800; font-size: 1.2rem; box-shadow: 0 10px 25px rgba(255, 79, 163, 0.3); transition: transform 0.2s; font-family: 'Noto Sans Tamil', sans-serif; }
        .btn-download:active { transform: scale(0.96); }
        .btn-download svg { margin-right: 10px; }
        .app-header { background: rgba(255,255,255,0.9); backdrop-filter: blur(10px); padding: 12px 20px; position: fixed; top: 0; width: 100%; z-index: 100; box-shadow: 0 2px 15px rgba(0,0,0,0.05); box-sizing: border-box; }
        .brand-container { display: flex; align-items: center; justify-content: center; }
        .brand-mark-box { background: linear-gradient(135deg, #FF4FA3 0%, #FF92C8 100%); width: 36px; height: 36px; border-radius: 10px; display: flex; align-items: center; justify-content: center; }
        .brand-mark-box svg { width: 20px; height: 20px; }
      </style>
    </head>
    <body>
      <header class="app-header">
        <div class="brand-container">
          <span class="brand-mark-box"><svg viewBox="0 0 24 24" fill="none"><path d="M4 12L12 4L20 12L12 20L4 12Z" stroke="#fff" stroke-width="2.2"/><circle cx="12" cy="12" r="3.2" fill="#fff"/></svg></span>
          <span style="font-weight: 900; font-size: 1.4rem; color: #b81d66; margin-left: 8px; font-family: 'Baloo Thambi 2', cursive;">myallin1</span>
        </div>
      </header>
      
      <main>
        <section class="fallback-hero">
          <h1 class="fallback-title">நாங்கள் அப்கிரேடு செய்து வருகிறோம்! 🚀</h1>
          <p class="fallback-sub">தடையற்ற சிறப்பான சேவைக்கு, நமது <b>MyAllin1 Turbo App</b>-ஐ உடனே டவுன்லோட் செய்து தொடர்ந்து பயன்படுத்துங்கள்.</p>
          
          <a href="https://github.com/myallin1/Allin1-update-release/releases/latest/download/allin1-customer.apk" class="btn-download">
            <svg viewBox="0 0 24 24" width="22" height="22" fill="none" stroke="currentColor" stroke-width="2.5"><path d="M4 16v1a3 3 0 003 3h10a3 3 0 003-3v-1m-4-4l-4 4m0 0l-4-4m4 4V4"/></svg>
            Download Turbo App
          </a>
          
          <div style="margin-top: 3.5rem; width: 100%;">
            <p style="font-family: 'Noto Sans Tamil', sans-serif; font-weight: 800; color: #b81d66; font-size: 1.1rem; margin-bottom: 0;">எப்படி Install செய்வது? (Video Guide 👇)</p>
            <div class="video-box">
              <video src="https://res.cloudinary.com/qx5zvm4w/video/upload/v1787918846/uianf2uyimhk1dszvaaz.mp4" autoplay loop muted playsinline controls></video>
            </div>
          </div>
        </section>
      </main>
    </body>
    </html>
  `;
}

// Content caches: keyed by immutable, versionless upstream URLs, so a
// deploy can never invalidate them. Deliberately NOT versioned and
// deliberately survive activate() — see the filter in that handler.
const CONTENT_CACHES = new Set(['cloudinary-cache-v1', 'map-tile-cache-v1']);

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
      //
      // BUG FIX (Aug 28 2026 — Nizam: "image and map yethume once open
      // panita again network recall pogama"): this filter used to keep
      // ONLY CACHE_VERSION, which meant every deploy also deleted
      // cloudinary-cache-v1 — every product photo the customer had
      // already downloaded, thrown away for a reason that has nothing to
      // do with photos. (And it would have done the same to the new
      // map-tile-cache-v1.) The app-shell cache is versioned because a
      // deploy genuinely invalidates it: index.html and main.dart.js
      // change. CONTENT caches are the opposite — a Cloudinary asset and
      // a z/x/y map tile live at immutable, versionless URLs, so a
      // deploy cannot invalidate them and re-downloading is pure waste
      // of the customer's data.
      //
      // Now only stale APP-SHELL caches are purged; content buckets are
      // explicitly preserved. Any bucket added later must be listed here
      // too, or it silently inherits the old delete-on-every-deploy
      // behaviour.
      caches.keys().then((keys) =>
        Promise.all(
          keys
            .filter((key) => key !== CACHE_VERSION && !CONTENT_CACHES.has(key))
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

  const url = new URL(req.url);

  // ================================================================
  // CACHE-FIRST FOR CLOUDINARY IMAGES (Offline Mode + Bandwidth Saver)
  // ================================================================
  if (url.hostname === 'res.cloudinary.com') {
    event.respondWith(
      caches.match(req).then((cached) => {
        if (cached) return cached;
        // Cache miss: fetch from network and store in the "cloudinary-cache"
        return fetch(req).then((res) => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open('cloudinary-cache-v1').then((cache) => cache.put(req, clone));
          }
          return res;
        }).catch(() => {
          // Fallback if offline and not in cache
          return new Response('', { status: 504, statusText: 'Offline' });
        });
      })
    );
    return;
  }

  // ================================================================
  // CACHE-FIRST FOR MAP TILES (Aug 28 2026 — Nizam: "image and map
  // yethume once open panita again network recall pogama full and full
  // offline la irukanum")
  // ================================================================
  // THE GAP: Cloudinary images were already cache-first (branch above),
  // but map tiles fell straight through to the
  // `url.origin !== self.location.origin` bail-out below and were
  // therefore NEVER cached — every single pan, zoom and re-open of a
  // booking screen re-downloaded the same PNGs. On a bike-taxi flow the
  // user opens the map repeatedly, so this was both the slowest screen
  // and the biggest data cost in the app, and it broke completely with
  // no network.
  //
  // Same cache-first shape as the Cloudinary branch, deliberately: a
  // map tile at a given z/x/y is immutable content at a versionless URL,
  // so once it is in the cache there is no reason to ever ask again.
  //
  // Separate cache bucket from cloudinary-cache-v1 and from the
  // app-shell CACHE_VERSION, so a deploy purging the shell does NOT
  // throw away tiles the user has already paid to download.
  //
  // Covers the OSM raster tiles used by flutter_map's TileLayer
  // (tile.openstreetmap.org, and the a/b/c subdomain form) plus the Ola
  // vector-tile host, which allin1_map_widget.dart also renders through.
  if (/(^|\.)tile\.openstreetmap\.org$/.test(url.hostname) ||
      /(^|\.)basemaps\.cartocdn\.com$/.test(url.hostname) ||
      /(^|\.)olamaps\.io$/.test(url.hostname)) {
    event.respondWith(
      caches.match(req).then((cached) => {
        if (cached) return cached;
        return fetch(req).then((res) => {
          // Tile CDNs answer cross-origin requests as opaque responses
          // (type 'opaque', status 0) unless CORS is negotiated. Those
          // are still perfectly replayable from Cache Storage, so accept
          // them as well as clean 200s — refusing them would silently
          // cache nothing at all, which is the trap this branch exists
          // to avoid.
          if (res && (res.status === 200 || res.type === 'opaque')) {
            const clone = res.clone();
            caches.open('map-tile-cache-v1').then((cache) => cache.put(req, clone));
          }
          return res;
        }).catch(() => new Response('', { status: 504, statusText: 'Offline' }));
      })
    );
    return;
  }

  // Only ever cache THIS origin's own app-shell files (bypassing other third-parties)
  if (url.origin !== self.location.origin) return;

  // ================================================================
  // ALWAYS NETWORK-FIRST: /version.json
  // ================================================================
  // FIX (Aug 20 2026 — Zero-bandwidth repeat-open architecture):
  // version.json is the ONLY file that MUST bypass cache every time.
  // It is tiny (~200 bytes) and is the "is there an update?" sentinel.
  // The JS version check in index.html's <head> fetches it once on
  // every boot with a cache-buster; if the version matches what's
  // stored in localStorage, every other file is served from cache
  // (zero bandwidth). If it differs, the JS purges all caches and
  // reloads once to pick up the fresh deploy.
  //
  // Everything else — including index.html and flutter_bootstrap.js —
  // is now cache-first (see the isAppShell branch below). This means
  // returning customers pay ZERO hosting bandwidth between deploys.
  if (url.pathname === '/version.json' || url.pathname.includes('/version.json')) {
    // Always go to network; never respond from cache.
    // Don't even opportunistically cache it — the cache-buster query
    // string means every version.json fetch has a unique URL anyway.
    return; // fall through to browser default (network fetch)
  }

  // ================================================================
  // PURE CACHE-FIRST: app shell + heavy bundles
  // ("Zero-Bandwidth Repeat-Open" architecture — Aug 20 2026)
  // ================================================================
  // FIX (Aug 12 2026 — CTO mandate): main.dart.js, fonts, canvaskit
  // were already cache-first. But index.html, flutter_bootstrap.js,
  // and flutter.js were still in the network-first default branch —
  // meaning they hit Firebase Hosting on EVERY app open, eating
  // bandwidth even when nothing changed.
  //
  // FIX (Aug 20 2026 — Nizam: "ovvoru time pwa open pannumbothu
  // hosting la irunthu download pannuchuna namma hosting bandwith
  // theenthurum"): Extend the cache-first guard to ALL same-origin
  // app-shell files. The update detection now works through a JS check
  // in index.html's <head> that fetches ONLY /version.json (tiny,
  // ~200 bytes) with a cache-buster. If version matches -> 100% cache.
  // If version differs -> purge all caches + reload once. So:
  //   - No update between deploys  -> ZERO hosting bytes for the shell
  //   - Update deployed            -> ONE fresh download (same as before)
  //
  // CACHE_VERSION is stamped per-flavor per-deploy by deploy_web.ps1,
  // so a new deploy always starts with an empty cache on activate().
  // There is nothing stale to serve; stale-forever can only happen when
  // the same cache name persists across deploys, which it no longer does.
  const isAppShell =
    url.pathname === '/' ||
    url.pathname === '/index.html' ||
    url.pathname.endsWith('/flutter_bootstrap.js') ||
    url.pathname.endsWith('/flutter.js') ||
    url.pathname.endsWith('/main.dart.js') ||
    url.pathname.endsWith('/manifest.json') ||
    url.pathname.endsWith('/favicon.png') ||
    url.pathname.endsWith('.otf') ||
    url.pathname.endsWith('.ttf') ||
    url.pathname.includes('/canvaskit/');

  if (isAppShell) {
    event.respondWith(
      caches.match(req).then((cached) => {
        if (cached) {
          // Cache hit — zero bytes over the network for this launch.
          return cached;
        }
        // Cache miss — fresh install or first launch after a redeploy
        // (deploy_web.ps1 stamped a new CACHE_VERSION, activate()
        // deleted the old one, so we're starting clean). Fetch once
        // and populate the cache for every subsequent launch.
        return fetch(req).then((res) => {
          if (res && res.status === 200) {
            const clone = res.clone();
            caches.open(CACHE_VERSION).then((cache) => cache.put(req, clone));
          }
          // Intercept Firebase Hosting quota exceeded (503/402/429) for navigations
          if (res && (res.status === 503 || res.status === 402 || res.status === 429) && req.mode === 'navigate') {
            return new Response(getTurboAppFallbackHTML(), {
              headers: { 'Content-Type': 'text/html; charset=utf-8' }
            });
          }
          return res;
        }).catch(() => {
          // Offline and not yet cached (should be rare — precache in
          // install() covers the critical shell files). For navigation
          // requests fall back to the root shell so the app opens at all.
          if (req.mode === 'navigate') {
            return caches.match('/').then((shell) =>
              shell || new Response('', { status: 504, statusText: 'Offline' })
            );
          }
          return new Response('', { status: 504, statusText: 'Offline' });
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
        // Intercept Firebase Hosting quota exceeded (503/402/429) for navigations
        if (networkResponse && (networkResponse.status === 503 || networkResponse.status === 402 || networkResponse.status === 429) && req.mode === 'navigate') {
          return new Response(getTurboAppFallbackHTML(), {
            headers: { 'Content-Type': 'text/html; charset=utf-8' }
          });
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
