// ================================================================
// pwa_fallback_sw.js
//
// A deliberately minimal service worker whose ONLY job is to satisfy
// Chrome's PWA installability criteria when Flutter's own
// flutter_service_worker.js is missing from the deployed build.
//
// Background: a build/deploy went out without manifest.json or
// flutter_service_worker.js. Firebase Hosting's catch-all rewrite then
// served index.html for both paths, so the browser got HTML where it
// expected JSON/JS. Result: the manifest failed to parse, the service
// worker failed to register with a MIME-type SecurityError, and Chrome
// therefore never fired 'beforeinstallprompt' — no "Install" prompt on
// a fresh phone, and "Add to Home screen" produced a plain bookmark
// shortcut instead of a standalone app window.
//
// index.html registers Flutter's real service worker first and only
// falls back to this file if that registration fails. So on a correct
// build this file is never used.
//
// IMPORTANT — this worker intentionally does NO caching. It installs a
// fetch listener (required for installability) that simply lets every
// request go to the network untouched: it never calls respondWith().
// That makes it impossible for this file to serve stale content or
// shadow a future correct deploy, which a precaching worker could.
// ================================================================

self.addEventListener('install', () => {
  // Take over immediately rather than waiting for existing tabs to close.
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', () => {
  // Intentionally empty. Registering the listener is what Chrome checks
  // for; not calling event.respondWith() means the browser handles the
  // request normally, exactly as if no service worker existed.
});

self.addEventListener('message', (event) => {
  // Kept for parity with flutter_service_worker.js's message contract.
  // Nothing in the app sends this any more — update detection moved to
  // web_version_checker.dart, which compares /version.json and never
  // talks to a service worker — but a stray message shouldn't be an
  // unhandled event.
  if (event.data && event.data.action === 'skipWaiting') {
    self.skipWaiting();
  }
});
