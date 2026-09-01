// notify-admin-build.js — sends one FCM topic push telling the admin
// app a new test build is ready.
//
// NEW (Sep 1 2026 — automation pipeline, Nizam: "namma automation work
// ah fullfill ah mudi"). Called from .github/workflows/ci-cd.yml's
// publish_admin_test_build job, right after that job publishes the
// "latest-admin-test" GitHub Release. The admin app subscribes to the
// same 'chitti_dev_builds' topic in main_admin.dart, so this is the
// other half of that wire — CI pushes, the app was already listening.
//
// Uses firebase-admin (installed by the workflow step just before this
// runs) rather than a hand-rolled OAuth+HTTP v1 call: signing the JWT
// and exchanging it for an access token by hand in a CI script is where
// this kind of integration usually breaks silently, and firebase-admin
// already does it correctly.
const admin = require('firebase-admin');

const serviceAccountJson = process.env.FIREBASE_SERVICE_ACCOUNT;
const releaseUrl = process.env.RELEASE_URL;
const shortSha = process.env.SHORT_SHA || '';

if (!serviceAccountJson) {
  console.log('FIREBASE_SERVICE_ACCOUNT not set — skipping build notification.');
  process.exit(0);
}

let serviceAccount;
try {
  serviceAccount = JSON.parse(serviceAccountJson);
} catch (e) {
  console.error('FIREBASE_SERVICE_ACCOUNT is not valid JSON:', e.message);
  process.exit(1);
}

admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });

const message = {
  topic: 'chitti_dev_builds',
  notification: {
    title: 'New Chitti test build ready',
    body: `Build ${shortSha} finished — tap to open the release.`,
  },
  data: {
    type: 'dev_build_ready',
    releaseUrl: releaseUrl || '',
    shortSha,
  },
  android: {
    priority: 'high',
    // Deliberately no custom channelId: that would need a matching
    // NotificationChannel registered natively in the app first, or
    // Android silently drops the notification instead of falling back.
    // The app's existing default FCM channel already handles this.
  },
};

admin
  .messaging()
  .send(message)
  .then((id) => console.log('Sent build notification:', id))
  .catch((err) => {
    // A failed push should not fail the whole CI run — the release is
    // already published and reachable from Development Monitor either
    // way, so this is best-effort.
    console.error('Failed to send build notification:', err.message);
    process.exit(0);
  });
