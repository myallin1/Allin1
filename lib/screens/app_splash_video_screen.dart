// ================================================================
// app_splash_video_screen.dart — shared every-launch video splash for
// ALL 4 apps (Customer / Hero / Seller / Admin).
// ================================================================
// NEW (per Nizam's request — replace the old muted 5s Customer-only
// clip with the new video he sent, WITH audio, stretched full-screen,
// and rolled out to all 4 apps consistently).
//
// Deliberately a single shared widget (not 4 copies) so all 4 apps
// play the exact same assets/videos/app_splash.mp4 the exact same way.
// Each app's main_*.dart just wraps its own existing "next" widget —
// this screen never owns or blocks any app-specific warm-up/auth
// logic; it is a purely visual layer on top of whatever each app was
// already going to show first.
//
// Non-blocking guarantee (same contract as the old VideoSplashScreen):
// navigation to nextScreen fires on whichever comes first — the video
// finishing, or a hard safety timer — so a slow/broken video can never
// add more than that ceiling to app startup. Audio is unmuted per the
// request; browsers that block unmuted autoplay will still show the
// video (silently) and the hard timer still guarantees progress.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class AppSplashVideoScreen extends StatefulWidget {
  final Widget nextScreen;
  final String assetPath;
  final Duration maxDuration;

  const AppSplashVideoScreen({
    required this.nextScreen,
    this.assetPath = 'assets/videos/app_splash.mp4',
    this.maxDuration = const Duration(seconds: 11),
    super.key,
  });

  @override
  State<AppSplashVideoScreen> createState() => _AppSplashVideoScreenState();
}

class _AppSplashVideoScreenState extends State<AppSplashVideoScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _navigated = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();

    // Hard ceiling regardless of video/network state — mirrors the
    // proven pattern from the old video_splash_screen.dart /
    // intro_video_screen.dart.
    _safetyTimer = Timer(widget.maxDuration, _goNext);

    try {
      final controller = VideoPlayerController.asset(widget.assetPath);
      _controller = controller;
      controller.addListener(_onTick);
      controller.initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        // Unmuted per request. If a browser's autoplay policy silently
        // blocks unmuted playback, the video simply plays without
        // sound (or waits for a user gesture) — the safety timer above
        // still guarantees the app opens on time either way.
        controller.setVolume(1.0).then((_) => controller.play()).catchError((Object e) {
          debugPrint('[AppSplashVideo] play() failed: $e');
        });
      }).catchError((Object e) {
        debugPrint('[AppSplashVideo] initialize() failed: $e');
      });
    } catch (e) {
      debugPrint('[AppSplashVideo] controller construction failed: $e');
    }
  }

  void _onTick() {
    final value = _controller?.value;
    if (value == null) return;
    if (value.isInitialized &&
        !value.isPlaying &&
        value.duration > Duration.zero &&
        value.position >= value.duration) {
      _goNext();
    }
  }

  void _goNext() {
    if (_navigated || !mounted) return;
    _navigated = true;
    _safetyTimer?.cancel();
    setState(() {});
  }

  @override
  void dispose() {
    _safetyTimer?.cancel();
    _controller?.removeListener(_onTick);
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_navigated) {
      return widget.nextScreen;
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: _ready && _controller != null
          ? SizedBox.expand(
              // Fills the ENTIRE screen (per request: "full screen kum
              // video stretch agi irukanum") rather than
              // letterboxing/cropping-to-fit like BoxFit.cover would —
              // deliberately stretches to the exact device aspect
              // ratio.
              child: FittedBox(
                fit: BoxFit.fill,
                child: SizedBox(
                  width: _controller!.value.size.width,
                  height: _controller!.value.size.height,
                  child: VideoPlayer(_controller!),
                ),
              ),
            )
          : const SizedBox.shrink(),
    );
  }
}
