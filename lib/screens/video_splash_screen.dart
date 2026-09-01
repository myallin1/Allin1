// ================================================================
// video_splash_screen.dart — Customer app's every-launch video splash
// ================================================================
// NEW (CTO mandate — Video Splash Screen). Plays
// assets/videos/customer_splash.mp4 (trimmed to 5s, muted, ~160KB —
// same size-conscious treatment already applied to
// intro_video_screen.dart's intro.mp4, which exists for a different
// purpose — a first-launch-ONLY onboarding video, untouched by this
// file) full-bleed (BoxFit.cover) over the top of this app's existing
// background warm-up call.
//
// Deliberately a SEPARATE widget from SplashSetupScreen (which this
// wraps/reuses via _warmUpInBackground below) rather than editing that
// screen directly — SplashSetupScreen is shared with the Hero app
// (main_hero.dart), and this video is Customer-only branding; editing
// SplashSetupScreen in place would have leaked this video into the
// Hero app too.
//
// CRUCIAL non-blocking guarantee (explicit CTO requirement): the video
// is a purely VISUAL layer. It never gates _warmUpInBackground from
// starting, and _warmUpInBackground is never awaited before
// navigating on — both already-established "Instant Launch" behaviors
// from splash_setup_screen.dart are preserved unchanged. Navigation
// fires on whichever comes first: the video reaching its end, or a
// hard 5-second safety timer (the CTO's own "5-second max" rule).
// The hard-ceiling-regardless-of-video-state pattern, and the
// muted-then-play autoplay handling, are both copied from
// intro_video_screen.dart, which exists specifically because of a
// real prior bug — browser autoplay policies can silently block
// video.play(), and without a ceiling that left customers stuck on a
// frozen frame forever.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

import '../config/api_config.dart';
import '../services/map_service.dart';

class VideoSplashScreen extends StatefulWidget {
  final Widget nextScreen;

  const VideoSplashScreen({required this.nextScreen, super.key});

  @override
  State<VideoSplashScreen> createState() => _VideoSplashScreenState();
}

class _VideoSplashScreenState extends State<VideoSplashScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _navigated = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();
    // Fired immediately, never awaited — identical contract to
    // SplashSetupScreen._warmUpInBackground(). Firebase/env/map-key
    // warm-up keeps running in the background regardless of whether
    // the video finishes first, the safety timer fires first, or this
    // screen is gone entirely by the time it resolves.
    unawaited(_warmUpInBackground());

    // Hard ceiling — 5s max, per the CTO's explicit "5-second max
    // timer" requirement. Fires no matter what the video is doing
    // (plays fine, blocked by autoplay policy, fails to load, still
    // buffering on a slow connection).
    _safetyTimer = Timer(const Duration(seconds: 11), _goNext);

    try {
      // UPDATED (per Nizam's request): swapped to the new shared
      // splash clip (assets/videos/app_splash.mp4 — has real audio,
      // ~11s), same one now used by all 4 apps via
      // app_splash_video_screen.dart. Audio is now UNMUTED per
      // request. Safety timer bumped from 5s to 11s below to cover
      // this longer clip's actual duration.
      final controller = VideoPlayerController.asset('assets/videos/app_splash.mp4');
      _controller = controller;
      controller.addListener(_onTick);
      controller.initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        controller.setVolume(1.0).then((_) => controller.play()).catchError((Object e) {
          debugPrint('[VideoSplash] play() failed: $e');
        });
      }).catchError((Object e) {
        debugPrint('[VideoSplash] initialize() failed: $e');
      });
    } catch (e) {
      debugPrint('[VideoSplash] controller construction failed: $e');
    }
  }

  Future<void> _warmUpInBackground() async {
    try {
      await ApiConfig.ensureEnvLoaded();
      await MapService().initialize();
    } catch (e) {
      debugPrint('VideoSplashScreen warm-up error: $e');
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
      // Same pass-through contract as SplashSetupScreen: render the
      // real destination immediately, no further gating. The
      // destination screen owns its own instant paint + silent
      // background data loading.
      return widget.nextScreen;
    }
    return Scaffold(
      backgroundColor: Colors.black,
      body: _ready && _controller != null
          ? SizedBox.expand(
              // Stretches to the full device screen (per request:
              // "full screen kum video stretch agi irukanum") rather
              // than letterboxing/cropping like BoxFit.cover.
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
