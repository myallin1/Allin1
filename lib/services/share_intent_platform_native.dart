// ================================================================
// share_intent_platform_native.dart
//
// Android/iOS build of the incoming-share reader. Kept in its own file
// so that `import 'package:receive_sharing_intent/...'` — which has no
// web implementation — never reaches a web compile. See the stub
// alongside this file and the conditional import in main_customer.dart.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

class ShareIntentPlatform {
  const ShareIntentPlatform();

  /// Delivers the text of any share that arrives, to [onText].
  ///
  /// Two cases, and missing either makes the feature look broken half
  /// the time:
  ///   getInitialMedia() — the share COLD-STARTED the app; the intent
  ///     is already waiting by the time Dart boots.
  ///   getMediaStream()  — the app was already running when the share
  ///     arrived.
  Future<void> listen(void Function(String text) onText) async {
    void handle(List<SharedMediaFile> files) {
      if (files.isEmpty) return;
      // Text and URL shares arrive with the payload in `path` — the
      // plugin reuses the same field it uses for real file paths.
      final text = files
          .where((f) =>
              f.type == SharedMediaType.text || f.type == SharedMediaType.url,)
          .map((f) => f.path)
          .where((s) => s.trim().isNotEmpty)
          .join(' ');
      if (text.trim().isEmpty) return;
      onText(text);
    }

    try {
      ReceiveSharingIntent.instance.getMediaStream().listen(
            handle,
            onError: (Object e) =>
                debugPrint('[ShareIntent] stream error: $e'),
          );

      handle(await ReceiveSharingIntent.instance.getInitialMedia());
      // Tell the plugin we've consumed it, so it isn't replayed on the
      // next resume.
      ReceiveSharingIntent.instance.reset();
    } catch (e) {
      debugPrint('[ShareIntent] setup failed: $e');
    }
  }
}
