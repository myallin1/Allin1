// ================================================================
// admin_qr_generator_screen.dart — Poster/Flex QR Generator
// ================================================================
// NEW (Aug 12 2026 — "Zero-Budget Escape Hatch" follow-up, per Nizam's
// explicit instruction: "Proceed with building the QR Generator in the
// Admin App... but hardcode it to generate our current default Firebase
// URL"). No QR-generation code existed anywhere in this repo before this
// — every poster/flex QR up to now was made by hand outside the app,
// which is exactly the "is this even pointed at the right link" risk
// that started this whole conversation.
//
// The URL below is hardcoded on purpose (not read from Firestore/config)
// — Nizam explicitly canceled the custom-domain and external-fallback
// plans and confirmed the launch sticks to the default `my-allin1.web.app`
// Firebase Hosting URL. `?source=poster_campaign` is NOT new tracking:
// it's the exact query param web/index.html and landing_page/index.html
// already increment `poster_qr_pwa_installs` / `poster_qr_scans` for
// (see those files) — reusing it here means every QR this screen
// generates feeds the analytics that already exist, instead of creating
// a second, disconnected tracking convention.
//
// UPDATED (Aug 12 2026 — Nizam: "namma app kullayum ithemari customised
// ah qr generate pandra feautures venum but ithunala appa slow
// agakudathu"): added design customization — foreground color presets,
// square/rounded module shape, and an optional center logo badge — all
// via qr_flutter's own vector rendering (same package already in use,
// zero extra network calls, zero extra native code), so none of this
// adds any startup/runtime cost to the rest of the app. Deliberately did
// NOT add a raster-image logo-upload feature or a full custom color
// picker like the reference site (app.qr-code-generator.com) — no brand
// logo PNG asset exists anywhere in this repo yet, and a full color
// picker is a much heavier dependency for a feature only this one screen
// uses. Background is intentionally locked to white — letting an admin
// pick a low-contrast QR/background combo can silently produce a QR that
// fails to scan on a printed poster, which is the exact risk this whole
// feature exists to prevent.
//
// Also added (per the same message): Share button using share_plus so
// the generated PNG can be handed straight to the OS share sheet
// (WhatsApp included, if installed) instead of only being saved/opened
// locally.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:share_plus/share_plus.dart';

import '../../services/qr_image_saver_stub.dart'
    if (dart.library.html) '../../services/qr_image_saver_web.dart';

const Color _bg = Color(0xFF0A0A12);
const Color _card = Color(0xFF141420);
const Color _border = Color(0xFF262636);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _pink = Color(0xFFFF4FA3);

// Single source of truth for the poster/flex QR target. Change this ONE
// line if the canonical launch URL is ever revisited later — every QR
// this screen has ever generated for print stays pointed at whatever was
// hardcoded here at print time, which is expected (a printed poster
// can't retroactively update itself either way).
const String kPosterQrTargetUrl =
    'https://my-allin1.web.app/?source=poster_campaign';

// Preset foreground-color swatches. Background is deliberately NOT
// customizable here (stays pure white) — see the header comment above
// for why. Every option below still keeps enough contrast against white
// to scan reliably at typical poster/flex print sizes.
const List<Color> _kColorPresets = [
  Colors.black,
  _pink,
  Color(0xFF6C3CE9), // brand purple
  Color(0xFF0A2540), // dark navy
];

class AdminQrGeneratorScreen extends StatefulWidget {
  const AdminQrGeneratorScreen({super.key});

  @override
  State<AdminQrGeneratorScreen> createState() =>
      _AdminQrGeneratorScreenState();
}

class _AdminQrGeneratorScreenState extends State<AdminQrGeneratorScreen> {
  final GlobalKey _qrBoundaryKey = GlobalKey();
  bool _busy = false;
  String? _statusMessage;

  Color _fgColor = Colors.black;
  bool _roundedShape = false;
  bool _showLogoBadge = true;

  Future<void> _copyLink() async {
    await Clipboard.setData(const ClipboardData(text: kPosterQrTargetUrl));
    if (!mounted) return;
    setState(() => _statusMessage = 'Link copied to clipboard.');
  }

  /// Shared by Save and Share — captures the RepaintBoundary at
  /// print-quality resolution (pixelRatio 6, well past the 240px on-screen
  /// size) and returns raw PNG bytes.
  Future<Uint8List> _capturePngBytes() async {
    final boundary = _qrBoundaryKey.currentContext?.findRenderObject()
        as RenderRepaintBoundary?;
    if (boundary == null) {
      throw StateError('QR widget not ready yet.');
    }
    final image = await boundary.toImage(pixelRatio: 6);
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    if (byteData == null) {
      throw StateError('Could not encode QR image.');
    }
    return byteData.buffer.asUint8List();
  }

  Future<void> _saveQrImage() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final pngBytes = await _capturePngBytes();
      final savedPath = await QrImageSaver().saveAndOpen(
        pngBytes,
        'allin1_poster_qr.png',
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Saved: $savedPath';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not save the QR image: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _shareQrImage() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _statusMessage = null;
    });
    try {
      final pngBytes = await _capturePngBytes();
      final result = await SharePlus.instance.share(
        ShareParams(
          files: [
            XFile.fromData(
              pngBytes,
              mimeType: 'image/png',
              name: 'allin1_poster_qr.png',
            ),
          ],
          text: 'Scan to open the Allin1 App: $kPosterQrTargetUrl',
        ),
      );
      if (!mounted) return;
      setState(() {
        _statusMessage = result.status == ShareResultStatus.success
            ? 'Shared.'
            : null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _statusMessage = 'Could not open the share sheet: $e';
      });
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _buildColorSwatch(Color color) {
    final selected = _fgColor.toARGB32() == color.toARGB32();
    return GestureDetector(
      onTap: () => setState(() => _fgColor = color),
      child: Container(
        width: 34,
        height: 34,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(
            color: selected ? Colors.white : _border,
            width: selected ? 2.5 : 1,
          ),
          boxShadow: selected
              ? [BoxShadow(color: color.withValues(alpha: 0.5), blurRadius: 8)]
              : null,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final qrEyeShape =
        _roundedShape ? QrEyeShape.circle : QrEyeShape.square;
    final qrModuleShape =
        _roundedShape ? QrDataModuleShape.circle : QrDataModuleShape.square;
    const double qrSize = 240;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: const Text(
          'Poster / Flex QR Generator',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        iconTheme: const IconThemeData(color: _text),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  children: [
                    const Text(
                      'This QR is hardcoded to our default Firebase '
                      'Hosting URL for the launch. It uses the same '
                      '?source=poster_campaign tag already tracked by '
                      'poster_qr_scans / poster_qr_pwa_installs, so '
                      'scans from printed posters/flex boards show up in '
                      'existing analytics automatically.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: _muted, fontSize: 12.5, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    RepaintBoundary(
                      key: _qrBoundaryKey,
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        color: Colors.white,
                        child: Stack(
                          alignment: Alignment.center,
                          children: [
                            QrImageView(
                              data: kPosterQrTargetUrl,
                              version: QrVersions.auto,
                              size: qrSize,
                              backgroundColor: Colors.white,
                              // High error-correction so the center logo
                              // badge below can cover part of the code
                              // without breaking scans (badge is only
                              // ~16% of the QR's area, well under the ~30%
                              // damage tolerance level H allows for).
                              errorCorrectionLevel: QrErrorCorrectLevel.H,
                              eyeStyle: QrEyeStyle(
                                eyeShape: qrEyeShape,
                                color: _fgColor,
                              ),
                              dataModuleStyle: QrDataModuleStyle(
                                dataModuleShape: qrModuleShape,
                                color: _fgColor,
                              ),
                            ),
                            if (_showLogoBadge)
                              Container(
                                width: qrSize * 0.16,
                                height: qrSize * 0.16,
                                decoration: BoxDecoration(
                                  color: Colors.white,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: _fgColor, width: 2),
                                ),
                                child: Center(
                                  child: Container(
                                    width: qrSize * 0.12,
                                    height: qrSize * 0.12,
                                    decoration: BoxDecoration(
                                      color: _fgColor,
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(
                                      Icons.bolt_rounded,
                                      color: Colors.white,
                                      size: 16,
                                    ),
                                  ),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    SelectableText(
                      kPosterQrTargetUrl,
                      textAlign: TextAlign.center,
                      style: const TextStyle(color: _text, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: _border),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'CUSTOMIZE',
                      style: TextStyle(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text('Color', style: TextStyle(color: _text.withValues(alpha: 0.8), fontSize: 12.5)),
                    const SizedBox(height: 8),
                    Row(
                      children: _kColorPresets
                          .map((c) => Padding(
                                padding: const EdgeInsets.only(right: 10),
                                child: _buildColorSwatch(c),
                              ),)
                          .toList(),
                    ),
                    const SizedBox(height: 18),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _roundedShape,
                      onChanged: (v) => setState(() => _roundedShape = v),
                      activeThumbColor: _pink,
                      title: const Text('Rounded dots', style: TextStyle(color: _text, fontSize: 13.5)),
                      subtitle: const Text('Square looks crisper on small prints',
                          style: TextStyle(color: _muted, fontSize: 11.5),),
                    ),
                    SwitchListTile(
                      contentPadding: EdgeInsets.zero,
                      value: _showLogoBadge,
                      onChanged: (v) => setState(() => _showLogoBadge = v),
                      activeThumbColor: _pink,
                      title: const Text('Allin1 logo badge', style: TextStyle(color: _text, fontSize: 13.5)),
                      subtitle: const Text('Small centered badge — high error-correction keeps it scannable',
                          style: TextStyle(color: _muted, fontSize: 11.5),),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _copyLink,
                      icon: const Icon(Icons.copy_rounded, color: _text, size: 18),
                      label: const Text('Copy Link', style: TextStyle(color: _text)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: _busy ? null : _shareQrImage,
                      icon: const Icon(Icons.share_rounded, color: _text, size: 18),
                      label: const Text('Share', style: TextStyle(color: _text)),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _border),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              ElevatedButton.icon(
                onPressed: _busy ? null : _saveQrImage,
                icon: _busy
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.download_rounded, size: 18),
                label: Text(_busy ? 'Working…' : 'Save HD QR Image'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              if (_statusMessage != null) ...[
                const SizedBox(height: 14),
                Text(
                  _statusMessage!,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: _muted, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
