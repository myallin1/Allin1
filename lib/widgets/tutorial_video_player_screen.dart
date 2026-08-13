// ================================================================
// tutorial_video_player_screen.dart — generic in-app tutorial video
// player for a bundled asset, with simple playback controls.
// ================================================================
// NEW (Aug 12 2026 — Nizam: "hero booking page la oru onboarding
// tutorial video vaikkanum... video innum illa, UI slot mattum vaikku"):
// video_player is already a dependency (used by the app-splash video),
// so this reuses that same package instead of adding a new one. Only
// handles a bundled asset — a plain http(s) link (e.g. a YouTube URL,
// which video_player cannot play directly) is opened in the device's
// own browser/YouTube app via url_launcher instead of being embedded,
// which needs no extra package and works for literally any link Nizam
// hands over later.
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class TutorialVideoPlayerScreen extends StatefulWidget {
  final String assetPath;
  final String title;

  const TutorialVideoPlayerScreen({
    required this.assetPath,
    this.title = 'How it works',
    super.key,
  });

  @override
  State<TutorialVideoPlayerScreen> createState() => _TutorialVideoPlayerScreenState();
}

class _TutorialVideoPlayerScreenState extends State<TutorialVideoPlayerScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    final controller = VideoPlayerController.asset(widget.assetPath);
    _controller = controller;
    controller.initialize().then((_) {
      if (!mounted) return;
      setState(() => _ready = true);
      controller
        ..setLooping(false)
        ..play();
    }).catchError((Object e) {
      if (!mounted) return;
      setState(() => _error = 'Could not load the video: $e');
    });
    controller.addListener(() => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(widget.title, style: const TextStyle(color: Colors.white)),
      ),
      body: Center(
        child: _error != null
            ? Padding(
                padding: const EdgeInsets.all(24),
                child: Text(_error!, style: const TextStyle(color: Colors.white70), textAlign: TextAlign.center),
              )
            : !_ready
                ? const CircularProgressIndicator(color: Colors.white)
                : AspectRatio(
                    aspectRatio: _controller!.value.aspectRatio,
                    child: Stack(
                      alignment: Alignment.bottomCenter,
                      children: [
                        VideoPlayer(_controller!),
                        GestureDetector(
                          onTap: () => setState(() {
                            _controller!.value.isPlaying ? _controller!.pause() : _controller!.play();
                          }),
                          child: Container(color: Colors.transparent),
                        ),
                        VideoProgressIndicator(_controller!, allowScrubbing: true, padding: const EdgeInsets.all(8)),
                        if (!_controller!.value.isPlaying)
                          const Icon(Icons.play_circle_fill_rounded, color: Colors.white70, size: 64),
                      ],
                    ),
                  ),
      ),
    );
  }
}
