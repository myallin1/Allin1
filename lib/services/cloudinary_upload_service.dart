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

import 'package:flutter/foundation.dart' show compute;
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
  /// [targetBytes] or the quality/size floor is hit — so output size
  /// is actually bounded, not just "usually smaller than the original".
  ///
  /// UPDATED (Aug 11 2026 — "Silicon Valley standard" HD-clarity pass,
  /// Nizam's Phase 2): the previous budget (100KB @ 1280px, quality
  /// floor 25, dimension floor 480px) optimized size so hard that a
  /// detailed image could legitimately end up at 480px/q25 — nowhere
  /// near the "HD clarity" requirement. Rebalanced to a genuine 1080p
  /// standard: dimension ladder now STARTS at 1920 (so a modern phone
  /// photo keeps real detail) and never floors below 1080, and the
  /// quality ladder never floors below 60 — below that, printed text on
  /// an ID document turns to mush, which defeats the entire purpose of
  /// collecting KYC photos. Byte budgets were raised to match (see
  /// [kPhotoTargetBytes] / [kDocumentTargetBytes]); the delivery-side
  /// f_auto/q_auto transforms added in [optimizedUrl] more than pay
  /// back the extra stored bytes on bandwidth, which is the metric that
  /// actually scales with users.
  static const int kPhotoTargetBytes = 320 * 1024; // ~320KB — menu/profile
  // UPDATED (Aug 11 2026 — Nizam's call): raised 400KB -> 500KB for hero
  // KYC/ID photos. Rationale for tuning THIS number rather than removing
  // the cap: heroes upload 3 documents each at registration, so at 1000
  // heroes this line alone decides ~1.5GB of Cloudinary storage. 500KB
  // buys noticeably more legible fine print for admin verification while
  // still being ~20x smaller than a raw camera original. If document text
  // still looks soft after testing, raise this constant again — it's the
  // single knob for every KYC upload path in the app.
  static const int kDocumentTargetBytes = 500 * 1024; // ~500KB — KYC/ID
  static const int _defaultTargetBytes = kPhotoTargetBytes;
  static const List<int> _qualitySteps = [88, 82, 75, 68, 60];
  static const List<int> _dimensionSteps = [1920, 1600, 1280, 1080];

  // ── Delivery-side optimization ──────────────────────────────────
  /// Rewrites a Cloudinary `secure_url` to request an
  /// automatically-optimized variant at DELIVERY time.
  ///
  /// This is the single highest-leverage bandwidth win available to us:
  /// an upload happens ONCE, but every stored image is then downloaded
  /// by every viewer, on every screen, forever — so delivery is what
  /// actually consumes Cloudinary's free-tier 25GB/month bandwidth, not
  /// upload. Previously the raw stored URL was rendered directly, so
  /// every view pulled the full-size JPEG.
  ///
  ///   * `f_auto` — Cloudinary serves WebP/AVIF to browsers that
  ///     support it and falls back to JPEG for those that don't,
  ///     automatically. Typically 30-50% smaller at identical visual
  ///     quality. This is also WHY we don't need to encode WebP
  ///     ourselves on the client (the pure-Dart `image` package has no
  ///     usable WebP encoder, and `flutter_image_compress` is
  ///     native-only, which would break the web PWA).
  ///   * `q_auto` — per-image perceptual quality selection.
  ///   * `w_<width>` — optional hard width cap, so a 200x200 avatar
  ///     slot never downloads a 1920px original.
  ///
  /// Safe on any input: non-Cloudinary URLs, empty strings, and URLs
  /// that already carry a transform are returned unchanged rather than
  /// being double-transformed into something invalid.
  static String optimizedUrl(String url, {int? width}) {
    if (url.isEmpty) return url;
    if (!url.contains('res.cloudinary.com')) return url;
    const marker = '/image/upload/';
    final idx = url.indexOf(marker);
    if (idx == -1) return url;

    final head = url.substring(0, idx + marker.length);
    final tail = url.substring(idx + marker.length);

    // Already transformed by a previous call — don't stack transforms.
    if (tail.startsWith('f_auto') || tail.contains('/f_auto')) return url;

    final transform =
        width != null ? 'f_auto,q_auto,w_$width,c_limit/' : 'f_auto,q_auto/';
    return '$head$transform$tail';
  }

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
  /// Runs [_compressSync] on a background isolate.
  ///
  /// FIX (Aug 11 2026 — "Silicon Valley standard" pass): compression
  /// used to run synchronously on the MAIN isolate. Decoding a 12MB
  /// camera photo and then re-encoding it (up to 25 times, in the old
  /// nested loop) froze the entire UI for several seconds on every
  /// upload — by far the most user-visible defect in this pipeline.
  /// `compute()` moves the whole thing to a background isolate on
  /// native. On web, where real isolates aren't available, `compute()`
  /// degrades to running inline — but the loop rewrite below cuts the
  /// worst case from ~25 full JPEG encodes to ~9, so even the web path
  /// is substantially faster than before.
  Future<Uint8List> _compress(Uint8List bytes, {required int targetBytes}) {
    return compute(
      _compressInIsolate,
      _CompressRequest(bytes: bytes, targetBytes: targetBytes),
    );
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

    final compressed = await _compress(bytes, targetBytes: targetBytes);

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

/// Payload for [_compressInIsolate] — `compute()` accepts exactly one
/// argument, so the two inputs are bundled here.
class _CompressRequest {
  const _CompressRequest({required this.bytes, required this.targetBytes});

  final Uint8List bytes;
  final int targetBytes;
}

/// Top-level (required by `compute()` — it cannot take a closure or an
/// instance method) isolate entry point for image compression.
Uint8List _compressInIsolate(_CompressRequest request) {
  final decoded = img.decodeImage(request.bytes);
  if (decoded == null) {
    // Deliberately throws instead of falling back to the original raw
    // bytes. See the class-level comment: a silent raw-bytes fallback is
    // exactly how an 8.35MB document once reached Cloudinary untouched.
    throw Exception(
      'Could not read this image (unsupported or corrupt format). '
      'Please try a different photo (JPEG works best).',
    );
  }

  final targetBytes = request.targetBytes;
  Uint8List? best;

  // OPTIMIZED LOOP (Aug 11 2026): the old version tried every
  // quality at every dimension — up to 5x5 = 25 full JPEG encodes,
  // each one costing real CPU on a large image. This version probes
  // each dimension ONCE at the lowest permitted quality first: if even
  // that is over budget, no higher quality at this dimension could
  // possibly fit, so we skip straight to the next (smaller) dimension
  // after a single encode instead of five wasted ones. Only once a
  // dimension is known to be viable do we step quality downward from
  // the top to find the BEST quality that still fits. Worst case drops
  // from 25 encodes to ~9, and the common case (a normal phone photo,
  // which fits at the very first dimension) is 2-3.
  //
  // Preference order is deliberate and unchanged: a larger dimension at
  // slightly lower quality beats a smaller dimension at higher quality,
  // because detail/legibility (especially printed text on an ID) tracks
  // pixel dimensions far more than it tracks JPEG quality.
  for (final dimension in CloudinaryUploadService._dimensionSteps) {
    img.Image resized = decoded;
    if (decoded.width > dimension || decoded.height > dimension) {
      resized = decoded.width >= decoded.height
          ? img.copyResize(decoded, width: dimension)
          : img.copyResize(decoded, height: dimension);
    }

    final qualities = CloudinaryUploadService._qualitySteps;

    // Cheap viability probe at the quality floor.
    final floorQuality = qualities.last;
    final floorJpg =
        Uint8List.fromList(img.encodeJpg(resized, quality: floorQuality));
    if (best == null || floorJpg.length < best.length) best = floorJpg;
    if (floorJpg.length > targetBytes) {
      // Even the floor doesn't fit at this size — go smaller.
      continue;
    }

    // This dimension IS viable. Find the highest quality that fits.
    for (final quality in qualities) {
      if (quality == floorQuality) return floorJpg; // already computed
      final jpg = Uint8List.fromList(img.encodeJpg(resized, quality: quality));
      if (jpg.length <= targetBytes) return jpg;
    }
    return floorJpg;
  }

  // Dimension floor reached without hitting the target — use the
  // smallest attempt made (a genuine best-effort, not a silent no-op)
  // so document text stays as legible as possible rather than being
  // crushed further. Note the floors are now 1080px/q60, so even this
  // worst case is still a legitimately HD result.
  return best!;
}
