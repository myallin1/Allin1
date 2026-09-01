// ================================================================
// image_compressor_web.dart — Web/PWA implementation
// ================================================================
// Swapped in for image_compressor_stub.dart on web builds via the
// `if (dart.library.html)` conditional import in
// cloudinary_upload_service.dart — same convention already used by
// crop_source_provider_stub.dart / crop_source_provider_web.dart and
// qr_image_saver_stub.dart / qr_image_saver_web.dart elsewhere in this
// codebase.
//
// WHY THIS FILE EXISTS (Nizam, Aug 12 2026): the previous web
// compression path ran the pure-Dart `image` package's decode/resize/
// JPEG-encode ladder through compute() — but compute() has no real
// isolate to move to on web, so it fell back to running that (up to
// ~9x repeated) pixel-loop encode directly on the SAME thread that
// draws the UI, which froze the "Setting up your Hero account…"
// overlay for however long that took on a given phone/browser.
//
// This file replaces that with the browser's own native <canvas>
// JPEG encoder (HTMLCanvasElement.toDataURL) instead of a pure-Dart
// one. That native encoder is implemented in the browser's own
// C++/Rust codec, not interpreted Dart, so a single resize+encode pass
// is dramatically faster than the old ladder even including a few
// quality retries — fast enough that it no longer visibly freezes the
// spinner overlay. `await Future.delayed(Duration.zero)` right before
// the heavy step below yields one frame back to the browser first, so
// the "Processing image…" spinner is guaranteed to have painted before
// any encode work starts.
//
// Still protects Cloudinary bandwidth exactly like the native path:
// same dimension/quality ladder shape, same ~500KB (KYC docs) / ~320KB
// (casual photos) target via [targetBytes], stepping down until the
// result fits or the floor is reached.
import 'dart:convert';
import 'dart:js_interop';
import 'dart:typed_data';

import 'package:web/web.dart' as web;

const List<int> _dimensionSteps = [1920, 1600, 1280, 1080];
const List<double> _qualitySteps = [0.88, 0.82, 0.75, 0.68, 0.60];

Future<Uint8List> compressImage(
  Uint8List bytes, {
  required int targetBytes,
}) async {
  // FIX (Aug 12 2026 — pre-build audit catch): this used to hard-code
  // `type: 'image/jpeg'` on the source Blob regardless of what the hero
  // actually picked. A blob: URL's declared MIME type is what the
  // browser trusts when the URL is assigned to <img>.src — so labelling
  // a PNG (or WebP/HEIC) as JPEG can make decode() reject the image
  // outright, which would surface as "Could not read this image" on
  // perfectly valid files. Nizam's own test uploads in the screenshot
  // are .png, so this was a live failure path, not a theoretical one.
  // Sniffed from the file's magic bytes instead of guessed.
  final blob = web.Blob(
    <JSUint8Array>[bytes.toJS].toJS,
    web.BlobPropertyBag(type: _sniffMimeType(bytes)),
  );
  final objectUrl = web.URL.createObjectURL(blob);
  try {
    final imgEl = web.HTMLImageElement()..src = objectUrl;
    await imgEl.decode().toDart;

    final naturalWidth = imgEl.naturalWidth;
    final naturalHeight = imgEl.naturalHeight;
    if (naturalWidth == 0 || naturalHeight == 0) {
      throw Exception(
        'Could not read this image (unsupported or corrupt format). '
        'Please try a different photo (JPEG works best).',
      );
    }

    // Yield one frame so the caller's loading spinner actually paints
    // before the (fast, but not instant) encode work below runs.
    await Future<void>.delayed(Duration.zero);

    Uint8List? best;
    for (final dimension in _dimensionSteps) {
      int w = naturalWidth;
      int h = naturalHeight;
      if (w > dimension || h > dimension) {
        if (w >= h) {
          h = (h * dimension / w).round();
          w = dimension;
        } else {
          w = (w * dimension / h).round();
          h = dimension;
        }
      }

      final canvas = web.document.createElement('canvas') as web.HTMLCanvasElement
        ..width = w
        ..height = h;
      final ctx = canvas.getContext('2d') as web.CanvasRenderingContext2D;
      ctx.drawImage(imgEl, 0, 0, w, h);

      for (final quality in _qualitySteps) {
        final dataUrl = canvas.toDataURL('image/jpeg', quality.toJS);
        final out = _dataUrlToBytes(dataUrl);
        if (best == null || out.length < best.length) best = out;
        if (out.length <= targetBytes) return out;
      }
    }
    return best!;
  } finally {
    web.URL.revokeObjectURL(objectUrl);
  }
}

/// Detects the real image type from the leading magic bytes, so the
/// source Blob is labelled honestly. Falls back to 'image/jpeg' only
/// when nothing matches (the browser will still content-sniff in most
/// cases; this just stops us from actively lying about the type).
String _sniffMimeType(Uint8List b) {
  if (b.length >= 8 &&
      b[0] == 0x89 && b[1] == 0x50 && b[2] == 0x4E && b[3] == 0x47) {
    return 'image/png';
  }
  if (b.length >= 3 && b[0] == 0xFF && b[1] == 0xD8 && b[2] == 0xFF) {
    return 'image/jpeg';
  }
  if (b.length >= 12 &&
      b[0] == 0x52 && b[1] == 0x49 && b[2] == 0x46 && b[3] == 0x46 &&
      b[8] == 0x57 && b[9] == 0x45 && b[10] == 0x42 && b[11] == 0x50) {
    return 'image/webp';
  }
  if (b.length >= 6 && b[0] == 0x47 && b[1] == 0x49 && b[2] == 0x46) {
    return 'image/gif';
  }
  // HEIC/HEIF ('ftyp' box at offset 4) — Safari/iOS can decode these.
  if (b.length >= 12 &&
      b[4] == 0x66 && b[5] == 0x74 && b[6] == 0x79 && b[7] == 0x70) {
    return 'image/heic';
  }
  return 'image/jpeg';
}

Uint8List _dataUrlToBytes(String dataUrl) {
  final comma = dataUrl.indexOf(',');
  return base64Decode(dataUrl.substring(comma + 1));
}
