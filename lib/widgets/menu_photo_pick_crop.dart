// ================================================================
// menu_photo_pick_crop.dart — shared "pick from gallery, crop tight"
// flow for a seller's dish/menu photo.
// ================================================================
// NEW (Aug 18 2026 — bandwidth audit, per Nizam: "seller ad panni vaikura
// menu image yenna size and image seller add pannumbothu round cut
// baground image cut pannivaikura custom options irukka... customer big
// size image vachchutta namma bandwith theenthurum... clarity kurayama
// 100kb range la pakka clarity oda varramari namma plan pannanum").
//
// ROOT CAUSE: seller_home_kitchen_menu_screen.dart's _pickImage() went
// straight from FilePicker to state with zero crop step — whatever
// aspect ratio and framing the seller's raw camera/gallery photo
// happened to have shipped straight to Cloudinary (then compressed to
// the DEFAULT 150KB target, not the ~100KB Nizam asked for specifically
// on dish photos). No "cut the background/center the dish" control at
// all.
//
// Mirrors hero_qr_pick_crop.dart's proven pattern (same
// CropSourceProvider web/native split, same "crop is an optional
// enhancement — if it fails or is cancelled, fall back to the picked
// bytes rather than silently doing nothing" contract).
//
// ── SHAPE (Aug 18 2026, CTO review — Nizam: "circle and square 2ume")
// The seller chooses Circle or Square per photo, and that choice is
// STORED on the menu item so the customer-facing card renders the same
// shape (ClipOval vs ClipRRect). That pairing is the whole point: a
// circular crop guide rendered into a rounded-SQUARE card means the
// seller carefully frames the dish inside a circle, then the app shows
// the corners they deliberately left empty. Shape is a contract
// between the crop UI and the card, never a crop-only decoration.
//
// ── cropStyle API NOTE (this is what broke the web build once already)
// image_cropper REMOVED the top-level `cropStyle:` argument from
// cropImage() in v9. In v12 (this project's pin) it lives on
// AndroidUiSettings — verified against image_cropper_platform_interface
// 8.0.0's AndroidUiSettings constructor, which declares
// `CropStyle cropStyle = CropStyle.rectangle`.
//
// It is set on ANDROID ONLY, deliberately:
//   * WebUiSettings (cropperjs) exposes no cropStyle equivalent, so the
//     PWA crop UI stays rectangular regardless. Cosmetic only — the
//     saved bytes are identical either way, and the stored imageShape
//     still drives how the customer sees it.
//   * IOSUiSettings is left untouched because this project ships
//     Android APKs + web PWAs only; adding an unverified parameter
//     there would risk another build break for zero benefit.
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image_cropper/image_cropper.dart';

import '../services/crop_source_provider_stub.dart'
    if (dart.library.html) '../services/crop_source_provider_web.dart';

const Color _kMenuPink = Color(0xFFFF4FA3);

/// How the photo should be framed AND displayed. Persisted on the menu
/// item — see this file's header for why the two must agree.
enum MenuPhotoShape { square, circle }

extension MenuPhotoShapeX on MenuPhotoShape {
  /// Stored in Firestore. Kept as a short stable string rather than an
  /// index so reordering the enum can never silently reinterpret
  /// existing data.
  String get storageValue =>
      this == MenuPhotoShape.circle ? 'circle' : 'square';

  static MenuPhotoShape fromStorage(String? value) =>
      value == 'circle' ? MenuPhotoShape.circle : MenuPhotoShape.square;
}

/// Result of the pick+crop flow: the image bytes plus the shape the
/// seller framed for.
class MenuPhotoResult {
  final Uint8List bytes;
  final MenuPhotoShape shape;

  const MenuPhotoResult({required this.bytes, required this.shape});
}

/// Asks the seller which shape they want, opens the gallery/file
/// picker, then a 1:1 crop UI. Returns the cropped bytes plus the
/// chosen shape, or the originally-picked bytes if cropping fails or is
/// cancelled, or null if the seller backed out of the picker itself.
/// [askShape] controls whether the seller is offered the Circle/Square
/// choice. Food/menu photos pass true (the default). Non-food callers —
/// mobile listings, sell-your-phone enquiries — pass false: a phone is
/// always shown in a rectangular card, so asking would be a pointless
/// extra tap offering a shape that screen can't render.
Future<MenuPhotoResult?> pickAndCropMenuPhoto(
  BuildContext context, {
  bool askShape = true,
}) async {
  MenuPhotoShape shape = MenuPhotoShape.square;
  if (askShape) {
    final chosen = await _askShape(context);
    if (chosen == null) return null; // seller dismissed the shape sheet
    shape = chosen;
    if (!context.mounted) return null;
  }

  final result = await FilePicker.platform.pickFiles(
    type: FileType.image,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final picked = result.files.first;
  final bytes = picked.bytes;
  if (bytes == null || bytes.isEmpty) return null;

  Uint8List? croppedBytes;
  try {
    final sourcePath = await CropSourceProvider().sourcePathFor(bytes);
    if (!context.mounted) {
      return MenuPhotoResult(bytes: bytes, shape: shape);
    }

    final cropped = await ImageCropper().cropImage(
      sourcePath: sourcePath,
      compressFormat: ImageCompressFormat.jpg,
      compressQuality: 90, // final size is still governed by uploadImageBytes()'s own budget-aware compressor
      // Always 1:1. Both shapes are square-bounded — a circle is drawn
      // INSIDE a square box, so one aspect ratio serves both, and the
      // stored bytes stay a normal square image in either case (a hard
      // alpha-punched circle PNG would look broken against a card
      // background colour; the round LOOK comes from ClipOval at
      // render time instead).
      aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
      uiSettings: [
        AndroidUiSettings(
          toolbarTitle: shape == MenuPhotoShape.circle
              ? 'Crop Dish Photo (Round)'
              : 'Crop Dish Photo',
          toolbarColor: _kMenuPink,
          toolbarWidgetColor: Colors.white,
          lockAspectRatio: true,
          hideBottomControls: false,
          // See the header: valid on AndroidUiSettings in v12, NOT as a
          // top-level cropImage() argument.
          cropStyle: shape == MenuPhotoShape.circle
              ? CropStyle.circle
              : CropStyle.rectangle,
        ),
        IOSUiSettings(
          title: 'Crop Dish Photo',
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
    debugPrint('[MenuPhotoPickCrop] crop failed, using uncropped image: $e');
  }

  return MenuPhotoResult(bytes: croppedBytes ?? bytes, shape: shape);
}

/// Small shape chooser shown before the picker. Deliberately first: the
/// seller should decide the framing BEFORE they are staring at the crop
/// box, and it lets us set the right cropStyle on the way in.
Future<MenuPhotoShape?> _askShape(BuildContext context) {
  return showModalBottomSheet<MenuPhotoShape>(
    context: context,
    backgroundColor: const Color(0xFF141420),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (ctx) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'How should this photo look?',
              style: TextStyle(
                color: Color(0xFFEEEEF5),
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'Customers will see it in this exact shape.',
              style: TextStyle(color: Color(0xFF7777A0), fontSize: 12),
            ),
            const SizedBox(height: 18),
            Row(
              children: [
                Expanded(
                  child: _ShapeOption(
                    label: 'Square',
                    subtitle: 'Best for most dishes',
                    isCircle: false,
                    onTap: () => Navigator.pop(ctx, MenuPhotoShape.square),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _ShapeOption(
                    label: 'Round',
                    subtitle: 'Great for bowls & plates',
                    isCircle: true,
                    onTap: () => Navigator.pop(ctx, MenuPhotoShape.circle),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
}

class _ShapeOption extends StatelessWidget {
  final String label;
  final String subtitle;
  final bool isCircle;
  final VoidCallback onTap;

  const _ShapeOption({
    required this.label,
    required this.subtitle,
    required this.isCircle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A28),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: const Color(0x267B6FE0)),
        ),
        child: Column(
          children: [
            // Live preview of the actual shape, so the choice is
            // obvious without reading anything.
            Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                color: _kMenuPink.withValues(alpha: 0.15),
                border: Border.all(color: _kMenuPink, width: 2),
                shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
                borderRadius: isCircle ? null : BorderRadius.circular(12),
              ),
              child: const Icon(Icons.restaurant_rounded,
                  color: _kMenuPink, size: 24),
            ),
            const SizedBox(height: 10),
            Text(
              label,
              style: const TextStyle(
                color: Color(0xFFEEEEF5),
                fontSize: 14,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              subtitle,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Color(0xFF7777A0), fontSize: 10.5),
            ),
          ],
        ),
      ),
    );
  }
}
