// ================================================================
// CloudinaryUploadService — shared image upload helper
// Allin1 Super App — replaces Firebase Storage across the app.
//
// WHY: Firebase Storage now requires the Blaze (pay-as-you-go) plan to
// even create a bucket — new Storage buckets are no longer available
// on the Spark (free) plan. Since Allin1 is staying on Spark, every
// image-upload call site (seller dish photos, hero KYC documents,
// grocery order list photos, etc.) needs to move off firebase_storage
// and onto a free alternative. Cloudinary's free tier (25 GB
// storage / 25 GB bandwidth per month) covers this without billing.
//
// This uses Cloudinary's UNSIGNED upload flow — no API secret is ever
// needed (or safe) on the client. You only need two values from your
// Cloudinary dashboard:
//   1. Cloud name        — shown on your Cloudinary dashboard home page.
//   2. Upload preset name — Settings → Upload → Upload presets →
//      "Add upload preset" → set "Signing Mode" to **Unsigned** → Save.
//      Copy the preset's name (not any key/secret) into
//      kCloudinaryUploadPreset below.
//
// Fill in both constants below before any upload will work — until
// then, upload calls will throw a clear "not configured" error rather
// than silently failing.
// ================================================================
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Your Cloudinary cloud name, e.g. 'dxyz1234a'. Find it on your
/// Cloudinary dashboard home page (console.cloudinary.com).
const String kCloudinaryCloudName = 'qx5zvm4w';

/// An UNSIGNED upload preset name created under
/// Cloudinary Console → Settings → Upload → Upload presets.
const String kCloudinaryUploadPreset = 'Myallin1-preset';

class CloudinaryUploadService {
  factory CloudinaryUploadService() => _instance;
  CloudinaryUploadService._internal();
  static final CloudinaryUploadService _instance =
      CloudinaryUploadService._internal();

  bool get isConfigured =>
      kCloudinaryCloudName != 'YOUR_CLOUD_NAME' &&
      kCloudinaryUploadPreset != 'YOUR_UNSIGNED_UPLOAD_PRESET';

  /// Starting width/height (in pixels) a compressed image is allowed to
  /// keep — the longer side is downscaled to this if it exceeds it.
  /// Images are never upscaled. Stepped down further below if the
  /// image is still over [_targetBytes] at this size.
  static const int _startDimension = 1280;

  /// FIX (root cause, per Nizam's request): the old single-pass
  /// compressor always used a fixed quality=75 at a fixed 1280px cap —
  /// that's a reasonable size for a simple photo, but a detailed
  /// document photo (ID card text, fine print) can still land well
  /// above the ~100KB target Nizam asked for, because quality/
  /// dimension were never actually adjusted to HIT a size budget —
  /// only ever ONE attempt was made. With 1000s of heroes and SOS KYC
  /// submissions each uploading 3 document photos, uncontrolled sizes
  /// eat into Cloudinary's free-tier 25GB storage/bandwidth fast. Now
  /// iterates quality first, then dimension, until the result is under
  /// [_targetBytes] or the quality/size floor is hit — so output size
  /// is actually bounded, not just "usually smaller than the original".
  static const int _defaultTargetBytes = 100 * 1024; // ~100KB
  static const List<int> _qualitySteps = [75, 60, 45, 35, 25];
  static const List<int> _dimensionSteps = [1280, 1024, 800, 640, 480];

  // FIX (root cause, confirmed via a hero's actual 8.35MB document
  // upload reaching Cloudinary untouched): the previous version of
  // this method fell back to the ORIGINAL raw bytes whenever
  // img.decodeImage() failed or threw — meaning a PNG/format pure-Dart
  // couldn't decode was silently shipped at full size instead of being
  // blocked or retried. With 1000s of heroes/customers each uploading
  // 3 document photos, even a handful of these silently-uncompressed
  // multi-MB files can burn through Cloudinary's free-tier 25GB fast.
  // Fixed by THROWING instead of silently falling back to raw bytes —
  // the caller's existing try/catch (see hero_register_screen.dart /
  // sos_kyc_verification_screen.dart's per-doc upload loop) already
  // treats a failed single-doc upload as non-fatal and logs it, but now
  // the hero/customer actually sees why (via debugPrint) instead of an
  // oversized file slipping through unnoticed.

  /// Decodes + downscales + re-encodes [bytes] as a JPEG before upload,
  /// stepping quality/dimension down until the result is at or under
  /// [targetBytes] (or the floor of both step lists is reached — at
  /// that point the smallest attempt made is used, since further
  /// shrinking would make the document illegible).
  Uint8List _compress(Uint8List bytes, {required int targetBytes}) {
    final decoded = img.decodeImage(bytes);
    if (decoded == null) {
      throw Exception(
        'Could not read this image (unsupported or corrupt format). '
        'Please try a different photo (JPEG works best).',
      );
    }

    Uint8List? best;

    for (final dimension in _dimensionSteps) {
      img.Image resized = decoded;
      if (decoded.width > dimension || decoded.height > dimension) {
        resized = decoded.width >= decoded.height
            ? img.copyResize(decoded, width: dimension)
            : img.copyResize(decoded, height: dimension);
      }

      for (final quality in _qualitySteps) {
        final jpg = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
        if (best == null || jpg.length < best.length) best = jpg;
        if (jpg.length <= targetBytes) {
          return jpg;
        }
      }
    }

    // Quality/dimension floor reached without hitting the target —
    // still use the smallest attempt made (a genuine best-effort, not
    // a silent no-op) so document text stays as legible as possible
    // rather than being crushed further.
    return best!;
  }

  /// Uploads raw image bytes to Cloudinary and returns the resulting
  /// `secure_url`. [folder] is optional and just organizes uploads in
  /// the Cloudinary media library (e.g. 'home_kitchen_menu/{sellerId}').
  /// Bytes are compressed client-side first — see [_compress].
  ///
  /// [targetBytes] defaults to ~100KB (fine for casual photos like menu
  /// items). Pass a higher value (e.g. 180-220KB) for KYC/ID document
  /// photos — a little more room keeps small printed text legible for
  /// admin verification, per Nizam's explicit request, while still
  /// being nowhere near the multi-MB raw camera files this replaces.
  Future<String> uploadImageBytes(
    Uint8List bytes, {
    required String fileName,
    String? folder,
    int targetBytes = _defaultTargetBytes,
  }) async {
    if (!isConfigured) {
      throw Exception(
        'Cloudinary is not configured yet. Set kCloudinaryCloudName and '
        'kCloudinaryUploadPreset in cloudinary_upload_service.dart.',
      );
    }

    final compressed = _compress(bytes, targetBytes: targetBytes);

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/image/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = kCloudinaryUploadPreset
      ..files.add(
          http.MultipartFile.fromBytes('file', compressed, filename: fileName),);

    if (folder != null && folder.isNotEmpty) {
      request.fields['folder'] = folder;
    }

    final streamedResponse = await request.send();
    final response = await http.Response.fromStream(streamedResponse);

    if (response.statusCode != 200) {
      throw Exception(
        'Cloudinary upload failed (${response.statusCode}): ${response.body}',
      );
    }

    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final secureUrl = data['secure_url'] as String?;
    if (secureUrl == null || secureUrl.isEmpty) {
      throw Exception('Cloudinary response missing secure_url: ${response.body}');
    }
    return secureUrl;
  }
}
