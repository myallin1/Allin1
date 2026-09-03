// ================================================================
// admin_chitti_lens_screen.dart — point the camera, Chitti looks it
// up on the web, YOU decide whether it speaks.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "chittiku camara on pannuna udanede athu net
// la google lens open aguramari namma app kulla vachcharlam athula
// chitti kandupichuruvan athukullaye cm details varum atha vachu
// solliruvan"). Built for a CM/ministers meeting the next morning.
//
// THE ONE DESIGN DECISION THAT MATTERS HERE
//   The obvious build is: capture -> identify -> Chitti immediately
//   announces the name out loud. That is also the build that can
//   embarrass Nizam in front of the Chief Minister, because
//   WEB_DETECTION returns a GUESS (see ChittiLensService's header) and
//   a guess spoken aloud to the person's face cannot be taken back.
//
//   So the result lands on SCREEN first, hedged ("looks like"), and
//   Chitti stays silent until Nizam taps. He reads it in a second, and
//   the greeting only happens if it's right. The magic survives; the
//   failure mode becomes a quiet shrug instead of a public one.
//
//   `autoSpeak` exists for when he wants the hands-free version
//   anyway — his call, not a default.
import 'dart:typed_data';

import 'package:camera/camera.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/chitti/chitti_lens_service.dart';
import '../../services/chitti/chitti_accessibility_bridge.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF16162A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFFB020);

class AdminChittiLensScreen extends StatefulWidget {
  const AdminChittiLensScreen({super.key, this.languageCode = 'ta'});

  final String languageCode;

  @override
  State<AdminChittiLensScreen> createState() => _AdminChittiLensScreenState();
}

class _AdminChittiLensScreenState extends State<AdminChittiLensScreen> {
  CameraController? _camera;
  bool _initializing = true;
  bool _busy = false;
  String? _cameraError;
  LensResult? _result;
  bool _autoSpeak = false;

  @override
  void initState() {
    super.initState();
    _initCamera();
  }

  @override
  void dispose() {
    _camera?.dispose();
    super.dispose();
  }

  Future<void> _initCamera() async {
    try {
      final cameras = await availableCameras();
      if (cameras.isEmpty) {
        setState(() {
          _cameraError = 'No camera found on this phone.';
          _initializing = false;
        });
        return;
      }
      // Back camera by default — this is pointed at other people, not
      // used as a selfie tool.
      final back = cameras.firstWhere(
        (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );
      final controller = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
      );
      await controller.initialize();
      if (!mounted) {
        await controller.dispose();
        return;
      }
      setState(() {
        _camera = controller;
        _initializing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _cameraError = 'Could not open the camera: $e';
        _initializing = false;
      });
    }
  }

  Future<void> _capture() async {
    final cam = _camera;
    if (cam == null || _busy) return;
    setState(() {
      _busy = true;
      _result = null;
    });
    try {
      final shot = await cam.takePicture();
      final Uint8List bytes = await shot.readAsBytes();
      final result = await ChittiLensService.identify(bytes);
      if (!mounted) return;
      setState(() => _result = result);

      if (_autoSpeak && !result.hasError && !result.isEmpty) {
        await _speak(ChittiLensService.spokenLine(
          result,
          languageCode: widget.languageCode,
        ));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _result = LensResult(
            bestGuess: '',
            entities: const [],
            pageTitles: const [],
            error: '$e',
          ));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _speak(String text) async {
    // Reuses the same native call-voice TTS path Chitti already speaks
    // through, so the voice is identical to the one on calls.
    await ChittiAccessibilityBridge.instance.speakOnCallStream(
      text,
      widget.languageCode == 'ta' ? 'ta-IN' : 'en-US',
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('Chitti Lens',
            style: GoogleFonts.outfit(
                color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            tooltip: 'Vision API key',
            icon: const Icon(Icons.key_rounded, color: _muted, size: 20),
            onPressed: _openKeySheet,
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(child: _preview()),
          _resultPanel(),
          _controls(),
        ],
      ),
    );
  }

  Widget _preview() {
    if (_initializing) {
      return const Center(child: CircularProgressIndicator(color: _purple));
    }
    final err = _cameraError;
    if (err != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(err,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _amber, fontSize: 13)),
        ),
      );
    }
    final cam = _camera;
    if (cam == null) return const SizedBox.shrink();
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: CameraPreview(cam),
      ),
    );
  }

  Widget _resultPanel() {
    final r = _result;
    if (_busy) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: _purple)),
            const SizedBox(width: 10),
            Text('Chitti is looking this up…',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12.5)),
          ],
        ),
      );
    }
    if (r == null) {
      return Padding(
        padding: const EdgeInsets.all(16),
        child: Text(
          'Point at a person or an object and tap the button.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
        ),
      );
    }

    if (r.hasError) {
      return _panel(
        color: _amber,
        title: 'Could not look this up',
        body: r.error!,
      );
    }
    if (r.isEmpty) {
      return _panel(
        color: _muted,
        title: 'Not recognised',
        body: "Chitti couldn't match this to anything on the web.",
      );
    }

    final label = r.topLabel;
    final pct = (r.confidence * 100).clamp(0, 100).toStringAsFixed(0);
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _green.withValues(alpha: 0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // "Looks like", never "This is" — see the header.
          Text('Looks like  ·  $pct% match',
              style: GoogleFonts.outfit(color: _muted, fontSize: 11.5)),
          const SizedBox(height: 3),
          Text(label,
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 19, fontWeight: FontWeight.w700)),
          if (r.pageTitles.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(r.pageTitles.take(2).join('  ·  '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
          ],
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _speak(ChittiLensService.greetingLine(
                    label,
                    languageCode: widget.languageCode,
                  )),
                  icon: const Icon(Icons.volume_up_rounded, size: 17),
                  label: const Text('Greet them'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _speak(ChittiLensService.spokenLine(
                    r,
                    languageCode: widget.languageCode,
                  )),
                  icon: const Icon(Icons.record_voice_over_rounded, size: 17),
                  label: const Text('Say what it is'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _purple,
                    side: const BorderSide(color: _purple),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _panel(
      {required Color color, required String title, required String body}) {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: GoogleFonts.outfit(
                  color: color, fontSize: 14, fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body,
              style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
        ],
      ),
    );
  }

  Widget _controls() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 18),
      child: Column(
        children: [
          Row(
            children: [
              Switch(
                value: _autoSpeak,
                activeThumbColor: _purple,
                onChanged: (v) => setState(() => _autoSpeak = v),
              ),
              Expanded(
                child: Text(
                  'Speak automatically (off = you check the name first)',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (_camera == null || _busy) ? null : _capture,
              icon: const Icon(Icons.camera_alt_rounded, size: 20),
              label: const Text('Identify'),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(13)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openKeySheet() async {
    final controller = TextEditingController(
      text: await ChittiLensService.readApiKey() ?? '',
    );
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          MediaQuery.of(sheetContext).viewInsets.bottom + 18,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Google Cloud Vision API key',
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(
              'Enable "Cloud Vision API" in Google Cloud Console, create an '
              'API key under Credentials, and paste it here. Stored on this '
              'phone only.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: controller,
              obscureText: true,
              style: GoogleFonts.outfit(color: _text, fontSize: 13),
              decoration: InputDecoration(
                hintText: 'AIza…',
                hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () async {
                  await ChittiLensService.saveApiKey(controller.text);
                  if (sheetContext.mounted) Navigator.of(sheetContext).pop();
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Save key'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
