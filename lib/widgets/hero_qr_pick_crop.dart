// ================================================================
// hero_qr_pick_crop.dart — shared "pick from gallery, crop to a tight
// square" flow for a hero's payment QR.
// ================================================================
// NEW (Aug 12 2026 — Nizam: "customer oda qr code ah alaga gallery
// kulla poitu athayum extra gapes crop panni exact ah qr set panni
// panni form la upload pandramari plan pannanum"): used identically by
// both hero_register_screen.dart (new hero sign-up) and
// hero_payment_qr_screen.dart (Settings → Payment QR, existing heroes
// changing their QR) — one crop flow, one place to fix if it ever needs
// changing, instead of two copies drifting apart.
//
// Locked to a 1:1 aspect ratio — a real UPI/payment QR is always
// square, so this removes an unnecessary decision from the hero and
// guarantees the saved image is exactly the QR with no stray
// background/gaps, matching the "extra gaps crop pannu" request.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../services/crop_source_provider_stub.dart'
    if (dart.library.html) '../services/crop_source_provider_web.dart';

const Color _kPink = Color(0xFFFF4FA3);

/// Opens the gallery/file picker, then the crop UI locked to a square
/// aspect ratio. Returns the final cropped PNG bytes, or null if the
/// hero cancelled at any step.
Future<Uint8List?> pickAndCropPaymentQr(BuildContext context) async {
  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final picked = result.files.first;
  final bytes = picked.bytes;
  if (bytes == null || bytes.isEmpty) return null;

  // FIX (Aug 12 2026 — Nizam: "qr upload mattum than upload panniyum
  // upload agathamari kaatuthu"): ROOT CAUSE of the QR tile staying on
  // its empty "Add your payment QR (optional)" state even after the
  // hero picked an image. Every other document on this form goes
  // straight from FilePicker into state, but the QR alone routes
  // through image_cropper first — and on web that means cropperjs
  // inside a dialog, which can fail or be dismissed and simply returns
  // null. The old code treated null as "hero cancelled" and returned
  // null silently, so the caller's setState never ran and nothing
  // visibly happened. That's indistinguishable from a dead button.
  //
  // Now: the crop is treated as an OPTIONAL enhancement, not a hard
  // requirement. If cropping throws or returns null we fall back to the
  // originally-picked bytes, so picking an image ALWAYS produces a
  // saved QR. Worst case the hero's QR has some extra background around
  // it (still perfectly scannable); best case they get the tight square
  // crop as before. A silent no-op is never an outcome anymore.
  Uint8List? croppedBytes;
  try {
    final sourcePath = await CropSourceProvider().sourcePathFor(bytes);
    if (!context.mounted) return bytes;

    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.png,
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: 'Crop Payment QR',
          toolbarColor: _kPink,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
        ),
        IOSUiSettings(
          title: 'Crop Payment QR',
          aspectRatioLockEnabled: true,
          resetAspectRatioEnabled: false,
        ),
        WebUiSettings(
          context: context,
          presentStyle: WebPresentStyle.dialog,
        ),
      ],
    );
    if (cropped != null) croppedBytes = await cropped.readAsBytes();
  } catch (e) {
    debugPrint('[HeroQrPickCrop] crop failed, using uncropped image: $e');
  }

  return croppedBytes ?? bytes;
}
