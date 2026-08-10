// ================================================================
// WebPushConfig — VAPID key for Firebase Cloud Messaging on web
// ================================================================
// FIX (root cause of "Hero PWA never receives background ride pings"):
// FirebaseMessaging.instance.getToken() on Flutter WEB requires a
// `vapidKey` argument — without one it fails (silently, since every
// call site here wraps it in try/catch) and no fcmToken is ever saved
// for a PWA user, so the server-side send path has nothing to deliver
// push notifications to. Native Android/iOS builds don't need this at
// all (ignored there), which is exactly why this only ever broke on
// web and was invisible on native testing.
//
// HOW TO GET THE REAL VALUE (Nizam — one-time, from Firebase Console):
//   1. https://console.firebase.google.com/project/erode-super-app/settings/cloudmessaging
//   2. Under "Web configuration" -> "Web Push certificates"
//   3. If none exists yet, click "Generate key pair"
//   4. Copy the "Key pair" string (starts with a long base64-looking
//      string, ~87 characters) and paste it below, replacing the
//      placeholder.
//
// Until a real key is pasted in, getToken() on web will keep failing
// exactly as it does today — this file alone does not fix anything by
// itself, the placeholder below MUST be replaced with your project's
// real VAPID key.
class WebPushConfig {
  WebPushConfig._();

  static const String vapidKey =
      'BM4VRVPiu49lKIkf12OCA7FqGaCWuVHag9eVBP1n0zh9tJ4Qa4FSJt7QosU5jkH_kPtGHM0ipvVp5SwyDyxTVBQ';

  static bool get isConfigured =>
      vapidKey != 'REPLACE_WITH_YOUR_FIREBASE_WEB_PUSH_VAPID_KEY' &&
      vapidKey.trim().isNotEmpty;
}
