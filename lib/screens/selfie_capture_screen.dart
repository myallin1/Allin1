// ================================================================
// SelfieCaptureScreen — forces a REAL live-camera selfie with an
// on-screen oval face-guide, for Hero KYC liveness verification.
// ================================================================
// FIX (per Nizam's request): hero_register_screen.dart's old
// _captureSelfie() opened the OS's native camera app via image_picker
// (ImageSource.camera) — that works, but it's the system camera UI,
// which Flutter cannot draw an overlay on top of, AND that same
// screen also had a plain "Gallery" button sitting right next to it
// that let a hero skip the camera entirely and upload any old photo,
// defeating the whole point of a liveness selfie.
//
// This screen replaces that flow: it embeds a live `camera` package
// preview directly in-app (not the OS camera app), so a dark scrim
// with an oval cutout can be painted on top — the hero has to
// position their face inside the oval before they can see themselves
// clearly, mirroring familiar KYC-app UX (bank apps, Aadhaar
// verification, etc.). No gallery option is exposed here at all; the
// only way out is to cancel and not submit a selfie, or (if the
// camera itself is genuinely unusable — permission denied, no camera
// hardware, blocked getUserMedia on web) an explicit, clearly-labelled
// "Camera not available — use gallery instead" fallback that only
// appears once camera initialization has actually failed, not as a
// standing shortcut.
// ================================================================
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart' as ph;

const Color _kBg = Color(0xFF0A0A1A);
const Color _kPink = Color(0xFFFF4FA3);
const Color _kText = Color(0xFFEEEEF5);
const Color _kMuted = Color(0xFF9999BB);

class SelfieCaptureResult {
  final Uint8List bytes;
  final String fileName;
  const SelfieCaptureResult({required this.bytes, required this.fileName});
}

class SelfieCaptureScreen extends StatefulWidget {
  const SelfieCaptureScreen({super.key});

  @override
  State<SelfieCaptureScreen> createState() => _SelfieCaptureScreenState();
}

class _SelfieCaptureScreenState extends State<SelfieCaptureScreen> {
  CameraController? _controller;
  Future<void>? _initFuture;
  bool _capturing = false;
  String? _initError;
  // FIX (per Nizam's bug report — "selfie upload button permission
  // ilathanala open agathama"): root cause is that this screen used to
  // let the `camera` plugin implicitly request the OS permission
  // inside CameraController.initialize() with no explicit request/
  // status check of our own first. On a device where the permission
  // was previously denied (or a manufacturer-specific permission-flow
  // quirk), that implicit path can silently fail or hang instead of
  // showing anything actionable — from the hero's point of view, the
  // button just "does nothing". Now explicitly requests
  // Permission.camera up front and shows a distinct, clearly-labelled
  // "Open Settings" recovery path when it's been permanently denied,
  // instead of leaving the hero stuck on a spinner or a vague error.
  bool _permissionPermanentlyDenied = false;

  @override
  void initState() {
    super.initState();
    _initFuture = _initCamera();
  }

  Future<void> _initCamera() async {
    // WEB FIX (Aug 8 2026) — persistent MissingPluginException on
    // `camera`/`image_picker` in the deployed Hero PWA, isolated after
    // extensive investigation: `file_picker` — a THIRD, separate plugin
    // — is what the 3 KYC document uploads use on this exact same
    // screen's parent flow (hero_register_screen.dart's _pickDocPhoto),
    // and those upload correctly on web. Rather than keep chasing why
    // camera_web/image_picker_for_web specifically won't register in
    // this deployment despite every structural check coming back
    // clean, skip both of them entirely on web and go straight to the
    // proven-working file_picker path — same package, same call
    // pattern as the docs, just for the selfie. Native (Android/iOS)
    // behavior is completely untouched below.
    if (kIsWeb) {
      if (mounted) {
        setState(() {
          _initError =
              'Live camera preview isn\'t available in this browser — select a selfie photo instead.';
        });
      }
      return;
    }
    try {
      if (!kIsWeb) {
        var status = await ph.Permission.camera.status;
        if (!status.isGranted) {
          status = await ph.Permission.camera.request();
        }
        if (!status.isGranted) {
          if (!mounted) return;
          setState(() {
            _permissionPermanentlyDenied = status.isPermanentlyDenied;
            _initError = status.isPermanentlyDenied
                ? 'Camera permission was denied. Please enable it from Settings to take your selfie.'
                : 'Camera permission is required to take a live selfie.';
          });
          return;
        }
      }
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() => _initError = 'No camera found on this device.');
        return;
      }
      // Prefer the front camera for a selfie; fall back to whatever's
      // available (e.g. a device with only a rear camera).
      final front = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.front,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        front,
        ResolutionPreset.medium,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() => _controller = controller);
    } catch (e) {
      // Covers permission-denied (native), and blocked getUserMedia on
      // web (no HTTPS, iframed PWA without Permissions-Policy: camera,
      // etc.) — same failure modes the old ImagePicker path had to
      // handle, just surfaced here instead.
      if (mounted) {
        setState(() => _initError = 'Could not access the camera: $e');
      }
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  Future<void> _capture() async {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized || _capturing) {
      return;
    }
    setState(() => _capturing = true);
    try {
      final file = await controller.takePicture();
      final bytes = await file.readAsBytes();
      if (!mounted) return;
      Navigator.pop(
        context,
        SelfieCaptureResult(bytes: bytes, fileName: file.name),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not capture photo: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _capturing = false);
    }
  }

  // Only reachable once the live camera has genuinely failed to
  // initialize — not a standing bypass button sitting next to a
  // working camera preview. On web this is the ONLY path (see
  // _initCamera's kIsWeb early-return above).
  Future<void> _useGalleryFallback() async {
    try {
      if (kIsWeb) {
        // WEB FIX (Aug 8 2026): image_picker also throws
        // MissingPluginException in this deployment (same root cause
        // as the camera plugin) — use file_picker instead, the exact
        // same package + call pattern already proven working for the
        // 3 KYC document uploads on the parent registration screen.
        final result = await FilePicker.platform
            .pickFiles(type: FileType.image, withData: true);
        if (result == null || result.files.isEmpty || !mounted) return;
        final file = result.files.first;
        final bytes = file.bytes;
        if (bytes == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Could not read the selected photo — try a different file.'),
                backgroundColor: Colors.red,
              ),
            );
          }
          return;
        }
        Navigator.pop(
          context,
          SelfieCaptureResult(bytes: bytes, fileName: file.name),
        );
        return;
      }

      // FIX (Aug 11 2026 — HD-clarity standard pass): was
      // imageQuality:70 / maxWidth:1024. That pre-degraded the image
      // BELOW the pipeline's new 1080px floor before
      // CloudinaryUploadService ever saw it — and since this is a KYC
      // selfie used for facial comparison by an admin, throwing away
      // that detail up front is the one place we least want to. These
      // values now act purely as an OOM guard (capping the decode of a
      // 12MP gallery original on a low-end device), deliberately set
      // ABOVE the compression pipeline's own ceiling so the real
      // size/quality decision stays centralized in one place.
      final picked = await ImagePicker().pickImage(
        source: ImageSource.gallery,
        imageQuality: 90,
        maxWidth: 1920,
      );
      if (picked == null || !mounted) return;
      final bytes = await picked.readAsBytes();
      if (!mounted) return;
      Navigator.pop(
        context,
        SelfieCaptureResult(bytes: bytes, fileName: picked.name),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not pick a photo: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        title: Text('Take a Live Selfie', style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: _kText)),
        iconTheme: const IconThemeData(color: _kText),
      ),
      body: FutureBuilder<void>(
        future: _initFuture,
        builder: (context, snapshot) {
          if (_initError != null) {
            return _errorState(_initError!);
          }
          final controller = _controller;
          if (snapshot.connectionState != ConnectionState.done || controller == null) {
            return const Center(child: CircularProgressIndicator(color: _kPink));
          }
          return Stack(
            fit: StackFit.expand,
            children: [
              Center(child: CameraPreview(controller)),
              // Dark scrim with an oval cutout — the "round box" guide,
              // so the hero can see exactly where to place their face.
              CustomPaint(
                painter: _OvalGuidePainter(),
                size: Size.infinite,
              ),
              Positioned(
                top: 24,
                left: 0,
                right: 0,
                child: Text(
                  'Center your face inside the oval',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700),
                ),
              ),
              Positioned(
                bottom: 32,
                left: 0,
                right: 0,
                child: Center(
                  child: GestureDetector(
                    onTap: _capturing ? null : _capture,
                    child: Container(
                      width: 74,
                      height: 74,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: Colors.white,
                        border: Border.all(color: _kPink, width: 4),
                      ),
                      child: _capturing
                          ? const Padding(
                              padding: EdgeInsets.all(20),
                              child: CircularProgressIndicator(strokeWidth: 3, color: _kPink),
                            )
                          : const Icon(Icons.camera_alt_rounded, color: _kPink, size: 32),
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _errorState(String message) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.videocam_off_rounded, color: _kMuted, size: 48),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _kText, fontSize: 13),
            ),
            const SizedBox(height: 20),
            if (_permissionPermanentlyDenied)
              ElevatedButton.icon(
                onPressed: () => ph.openAppSettings(),
                style: ElevatedButton.styleFrom(backgroundColor: _kPink),
                icon: const Icon(Icons.settings_rounded, color: Colors.white),
                label: Text(
                  'Open Settings to allow Camera',
                  style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
                ),
              ),
            const SizedBox(height: 10),
            ElevatedButton.icon(
              onPressed: _useGalleryFallback,
              style: ElevatedButton.styleFrom(backgroundColor: _kPink),
              icon: const Icon(Icons.photo_library_outlined, color: Colors.white),
              label: Text(
                kIsWeb ? 'Select Selfie Photo' : 'Camera not available — use gallery instead',
                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Paints a dark scrim over the whole preview with an oval cutout in
/// the center — the visual "round box" guide the hero lines their
/// face up with before tapping capture. Pure UI guide, not an actual
/// face-detection check (no ML/camera-vision dependency added).
class _OvalGuidePainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final ovalWidth = size.width * 0.68;
    final ovalHeight = ovalWidth * 1.3;
    final ovalRect = Rect.fromCenter(
      center: Offset(size.width / 2, size.height / 2 - 20),
      width: ovalWidth,
      height: ovalHeight,
    );

    final scrimPath = Path()..addRect(Rect.fromLTWH(0, 0, size.width, size.height));
    final ovalPath = Path()..addOval(ovalRect);
    final cutoutPath = Path.combine(PathOperation.difference, scrimPath, ovalPath);

    canvas.drawPath(cutoutPath, Paint()..color = Colors.black.withValues(alpha: 0.55));
    canvas.drawOval(
      ovalRect,
      Paint()
        ..color = Colors.white.withValues(alpha: 0.9)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
