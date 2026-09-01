// ================================================================
// image_compressor_stub.dart — Android/iOS (native) implementation
// ================================================================
// Swapped in for image_compressor_web.dart on native builds via the
// `if (dart.library.html)` conditional import in
// cloudinary_upload_service.dart — same convention as
// crop_source_provider_stub.dart / crop_source_provider_web.dart.
//
// On native, Flutter's compute() spins up a REAL background isolate,
// so this pure-Dart quality/dimension ladder (using the `image`
// package) never touches the UI thread in the first place — nothing
// here needed the Canvas-based rewrite that image_compressor_web.dart
// has. This is exactly the logic that used to live directly inside
// cloudinary_upload_service.dart before Nizam's Aug 12 2026 request to
// split the web path onto a non-blocking browser-native Canvas
// implementation.
import 'dart:typed_data';

import 'package:flutter_image_compress/flutter_image_compress.dart';

const List<int> _qualitySteps = [88, 82, 75, 68, 60];
const List<int> _dimensionSteps = [1920, 1600, 1280, 1080];

Future<Uint8List> compressImage(
  Uint8List bytes, {
  required int targetBytes,
}) async {
  Uint8List? best;

  for (final dimension in _dimensionSteps) {
    final floorQuality = _qualitySteps.last;
    
    final floorJpg = await FlutterImageCompress.compressWithList(
      bytes,
      minWidth: dimension,
      minHeight: dimension,
      quality: floorQuality,
      format: CompressFormat.jpeg,
    );

    if (best == null || floorJpg.length < best.length) best = floorJpg;
    if (floorJpg.length > targetBytes) continue;

    for (final quality in _qualitySteps) {
      if (quality == floorQuality) return floorJpg;
      final jpg = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: dimension,
        minHeight: dimension,
        quality: quality,
        format: CompressFormat.jpeg,
      );
      if (jpg.length <= targetBytes) return jpg;
    }
    return floorJpg;
  }

  if (best == null || best.isEmpty) {
    throw Exception(
      'Could not read this image (unsupported or corrupt format). '
      'Please try a different photo (JPEG works best).',
    );
  }

  return best;
}
