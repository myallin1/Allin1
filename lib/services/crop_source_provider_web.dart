// ================================================================
// crop_source_provider_web.dart — Web implementation
// ================================================================
// Same job as crop_source_provider_stub.dart's native version, but
// there's no real filesystem on web for image_cropper's cropperjs
// backend to open. Same technique already used successfully in
// qr_image_saver_web.dart: wrap the bytes in a Blob and hand cropperjs
// a `blob:` object URL, which behaves like a normal image src as far as
// the browser (and therefore cropperjs) is concerned.
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

class CropSourceProvider {
  Future<String> sourcePathFor(Uint8List bytes) async {
    final blob = web.Blob(
      <JSUint8Array>[bytes.toJS].toJS,
      web.BlobPropertyBag(type: 'image/png'),
    );
    return web.URL.createObjectURL(blob);
  }
}
