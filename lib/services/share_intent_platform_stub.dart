// ================================================================
// share_intent_platform_stub.dart
//
// Web/default build of the incoming-share reader.
//
// The real implementation uses receive_sharing_intent, which ships
// Android and iOS only — it has NO web implementation, so importing it
// from main_customer.dart directly broke `flutter build web` outright
// ("Failed to compile application for the Web"). A kIsWeb check does
// not help: that runs at runtime, while the import is resolved at
// compile time.
//
// So the import is switched per-platform instead (see the conditional
// import in main_customer.dart), and this file is what web gets: a
// no-op. Web doesn't need it anyway — the PWA receives shares through
// "share_target" in web/manifest.json, which
// SharedLocationInbox.captureFromLaunchUrl() reads off the launch URL.
// ================================================================

class ShareIntentPlatform {
  const ShareIntentPlatform();

  /// No-op on web. [onText] is never called.
  Future<void> listen(void Function(String text) onText) async {}
}
