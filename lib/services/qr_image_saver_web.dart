// ================================================================
// qr_image_saver_web.dart — Web (PWA) implementation
// ================================================================
// Swapped in for qr_image_saver_stub.dart on web builds via the
// `if (dart.library.html)` conditional import in
// admin_qr_generator_screen.dart. Same package:web + dart:js_interop
// convention already established in pwa_cache_platform_web.dart: builds
// a Blob from the PNG bytes, points a throwaway <a download> at it via
// createObjectURL, and clicks it programmatically — the standard
// browser-download recipe, no server round-trip and no extra package.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class QrImageSaver {
  Future<String> saveAndOpen(Uint8List pngBytes, String fileName) async {
    final blob = web.Blob(
      <JSUint8Array>[pngBytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    final url = web.URL.createObjectURL(blob);
    final anchor = web.document.createElement('a') as web.HTMLAnchorElement
      ..href = url
      ..download = fileName;
    web.document.body?.appendChild(anchor);
    anchor.click();
    anchor.remove();
    web.URL.revokeObjectURL(url);
    return fileName;
  }
}
