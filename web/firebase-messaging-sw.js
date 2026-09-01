// ================================================================
// firebase-messaging-sw.js — Web Push receiver for the Hero PWA
// ================================================================
// FIX (root cause, Aug 10 2026 — "Hero PWA doesn't show ride requests
// when the tab is backgrounded/minimized"): this file did not exist
// anywhere in the repo. FirebaseMessaging.instance.getToken() was
// being called on web (main_hero.dart / hero_home_screen.dart) with
// no service worker registered to receive push messages and no
// vapidKey — so getToken() silently failed on every Hero PWA session,
// no fcmToken was ever saved for PWA heroes, and the server-side send
// path had nothing to deliver to. This is that missing receiver.
//
// Uses the Firebase JS "compat" SDK (loaded via importScripts) because
// service workers cannot use ES module imports the way the rest of
// the Flutter web app does — this is the standard, Google-documented
// pattern for Flutter/FlutterFire web push and is independent of the
// main app's Dart-compiled JS.
//
// Config values below are copied verbatim from lib/firebase_options.dart's
// `web` FirebaseOptions block — same project, same web app, so this
// MUST be kept in sync if that config ever changes (e.g. the app is
// moved to a different Firebase project).
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/10.12.2/firebase-messaging-compat.js');

firebase.initializeApp({
  apiKey: 'AIzaSyDipnXQFpwR1Zm4L3-XebKVgc1oPJhReME',
  appId: '1:357526153693:web:3a220b09b185f2ef4aee34',
  messagingSenderId: '357526153693',
  projectId: 'erode-super-app',
  authDomain: 'erode-super-app.firebaseapp.com',
  storageBucket: 'erode-super-app.firebasestorage.app',
});

const messaging = firebase.messaging();

// Fires when a push arrives while the PWA tab/app is NOT in the
// foreground (backgrounded, minimized, or the browser itself is
// closed but the OS/browser keeps the service worker alive briefly).
// This is the exact gap that made background ride/service/food/
// grocery pings invisible on Hero PWA — the app-side FCM background
// handler (used on native Android/iOS) has no web equivalent; this
// listener IS the web equivalent.
messaging.onBackgroundMessage((payload) => {
  const title = (payload.notification && payload.notification.title) ||
    (payload.data && payload.data.title) || 'New request — Allin1 Hero';
  const body = (payload.notification && payload.notification.body) ||
    (payload.data && payload.data.body) || 'Tap to view and accept.';

  self.registration.showNotification(title, {
    body,
    icon: '/icons/Icon-192.png',
    badge: '/icons/Icon-192.png',
    data: payload.data || {},
    // Vibration + requireInteraction: a ride ping is time-sensitive
    // (90s broadcast window) — it should not silently auto-dismiss
    // the way a normal web notification does after a few seconds.
    requireInteraction: true,
    vibrate: [200, 100, 200],
  });
});

// Tapping the notification focuses/opens the Hero PWA instead of just
// dismissing the notification with nothing happening — mirrors the
// native "notification tap opens accept popup" flow fixed earlier
// this session, now covered on web too.
self.addEventListener('notificationclick', (event) => {
  event.notification.close();
  event.waitUntil(
    self.clients.matchAll({ type: 'window', includeUncontrolled: true }).then((clientList) => {
      for (const client of clientList) {
        if ('focus' in client) {
          return client.focus();
        }
      }
      if (self.clients.openWindow) {
        return self.clients.openWindow('/');
      }
    }),
  );
});
