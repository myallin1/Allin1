// ================================================================
// crop_source_provider_stub.dart — Android/iOS implementation
// ================================================================
// image_cropper's cropImage() needs a real file `sourcePath`, but
// file_picker (withData: true) only hands back raw bytes — no path is
// guaranteed to exist for a freshly-picked file. Writing the bytes to a
// throwaway temp file gives image_cropper something real to open; the
// temp file is never referenced again after crop, and the OS is free to
// reclaim its temp directory on its own schedule.
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

class CropSourceProvider {
  Future<String> sourcePathFor(Uint8List bytes) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/hero_qr_crop_src_${DateTime.now().millisecondsSinceEpoch}.png',
    );
    await file.writeAsBytes(bytes, flush: true);
    return file.path;
  }
}
