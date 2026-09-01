// ================================================================
// hero_payment_qr_service.dart — Hero's own UPI/payment QR, stored
// LOCALLY ONLY (never Cloudinary, never Firestore).
// ================================================================
// NEW (Aug 12 2026 — Nizam: "hero upload pandra qr code namma cloudinary
// la kuda upload panna kuda thevayilla, hero phone laye offline la save
// agiratum"): every other hero-uploaded image in this app (license,
// Aadhaar, PAN, live selfie — see hero_register_screen.dart) goes to
// Cloudinary because admin needs to review it remotely. This one is the
// opposite: it's shown to CUSTOMERS on THIS hero's own device seconds
// after a ride/task completes, so there's no reason for it to ever
// leave the phone — keeping it fully local is both simpler and exactly
// what was asked for.
//
// PLATFORM SPLIT (explicit CTO instruction — heroes use either the
// Android APK or the PWA, and the storage method must not crash on
// either):
//   - Native (Android/iOS): a real .png file via path_provider's
//     application-documents directory. Survives app restarts, works
//     fully offline, no size practical limit.
//   - Web (installed PWA or plain browser tab): Hive (hive_flutter),
//     which this app already depends on and already initializes for
//     exactly this kind of offline data (see hive_cache.dart,
//     local_sync_service.dart). On web, Hive transparently persists to
//     IndexedDB — this is a safer choice than hand-rolling raw
//     IndexedDB/JS-interop code, since Hive's web backing is already
//     proven elsewhere in this codebase.
// A runtime `kIsWeb` check picks the branch; `dart:io`'s File class is
// imported directly (same precedent as services/api_service.dart —
// dart:io compiles fine for web, it simply must never be executed
// there, which the kIsWeb guards below ensure).
import 'dart:io';
import 'dart:typed_data';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:path_provider/path_provider.dart';

class HeroPaymentQrService {
  HeroPaymentQrService._();
  static final HeroPaymentQrService instance = HeroPaymentQrService._();

  static const String _hiveBoxName = 'hero_payment_qr_box';
  static const String _hiveKey = 'qr_png_base64';
  static const String _nativeFileName = 'hero_payment_qr.png';

  Future<Box> _openBox() async {
    if (Hive.isBoxOpen(_hiveBoxName)) return Hive.box(_hiveBoxName);
    // Idempotent — safe even if another entrypoint already called this
    // (see HiveCache._box()'s identical reasoning).
    await Hive.initFlutter();
    return Hive.openBox(_hiveBoxName);
  }

  Future<File> _nativeFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File('${dir.path}/$_nativeFileName');
  }

  /// Saves the cropped QR PNG bytes locally. Overwrites any previously
  /// saved QR (a hero only ever has one active payment QR at a time).
  Future<void> saveQr(Uint8List pngBytes) async {
    if (kIsWeb) {
      final box = await _openBox();
      await box.put(_hiveKey, base64Encode(pngBytes));
    } else {
      final file = await _nativeFile();
      await file.writeAsBytes(pngBytes, flush: true);
    }
  }

  /// Returns the saved QR's PNG bytes, or null if the hero has never
  /// uploaded one yet.
  Future<Uint8List?> loadQr() async {
    try {
      if (kIsWeb) {
        final box = await _openBox();
        final b64 = box.get(_hiveKey) as String?;
        if (b64 == null || b64.isEmpty) return null;
        return base64Decode(b64);
      } else {
        final file = await _nativeFile();
        if (!await file.exists()) return null;
        return await file.readAsBytes();
      }
    } catch (e) {
      debugPrint('[HeroPaymentQrService] loadQr failed: $e');
      return null;
    }
  }

  Future<bool> hasQr() async {
    final bytes = await loadQr();
    return bytes != null && bytes.isNotEmpty;
  }

  /// Lets a hero remove/replace their QR (used by the Settings screen's
  /// "Remove" action before re-uploading a new one).
  Future<void> deleteQr() async {
    try {
      if (kIsWeb) {
        final box = await _openBox();
        await box.delete(_hiveKey);
      } else {
        final file = await _nativeFile();
        if (await file.exists()) await file.delete();
      }
    } catch (e) {
      debugPrint('[HeroPaymentQrService] deleteQr failed (non-fatal): $e');
    }
  }
}
