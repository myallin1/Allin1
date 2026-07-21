// ================================================================
// intro_video_screen.dart
// First-launch-only intro video (assets/videos/intro.mp4). Shown
// exactly once per customer — see _IntroGate in main_customer.dart,
// which checks a shared_preferences flag before ever building this
// screen. Skippable, and auto-advances once the video finishes.
//
// Hardened against a real bug seen on first test: web browsers can
// silently block programmatic video.play() (autoplay policy,
// especially for video with audio, without a prior tap/click). When
// that happens the video never actually starts, so the old
// "advance when the video reaches its end" logic never fired and the
// customer was stuck on a frozen/blank frame forever — the app
// looked like it wouldn't open. Two fixes: (1) a hard safety timer
// that always moves on after a fixed ceiling no matter what the video
// is doing, (2) every failure path (construction, initialize, play)
// now falls through to _goNext() instead of silently doing nothing.
// ================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class IntroVideoScreen extends StatefulWidget {
  final Widget next;

  const IntroVideoScreen({required this.next, super.key});

  @override
  State<IntroVideoScreen> createState() => _IntroVideoScreenState();
}

class _IntroVideoScreenState extends State<IntroVideoScreen> {
  VideoPlayerController? _controller;
  bool _ready = false;
  bool _navigated = false;
  Timer? _safetyTimer;

  @override
  void initState() {
    super.initState();

    // Absolute ceiling — the video is ~10s, this gives it a few extra
    // seconds for network/decoder startup. Whatever happens with the
    // video (plays fine, blocked by autoplay policy, fails to load),
    // the customer is guaranteed to reach the real app within this
    // window instead of being stuck indefinitely.
    _safetyTimer = Timer(const Duration(seconds: 15), _goNext);

    try {
      final controller = VideoPlayerController.asset(
        'assets/videos/intro.mp4',
      );
      _controller = controller;
      controller.addListener(_onTick);
      controller.initialize().then((_) {
        if (!mounted) return;
        setState(() => _ready = true);
        // Muted autoplay is allowed by every major browser without a
        // user gesture; unmuted autoplay with audio often isn't. Start
        // muted so playback reliably begins, then un-mute — if the
        // un-mute itself gets blocked the video still plays (silently)
        // instead of never starting at all.
        controller.setVolume(0).then((_) => controller.play()).then((_) {
          controller.setVolume(1).catchError((Object e) {
            debugPrint('[IntroVideo] setVolume(1) failed (non-fatal): $e');
          });
        }).catchError((Object e) {
          debugPrint('[IntroVideo] play() failed: $e');
          _goNext();
        });
      }).catchError((Object e) {
        debugPrint('[IntroVideo] initialize() failed: $e');
        _goNext();
      });
    } catch (e) {
      debugPrint('[IntroVideo] controller construction failed: $e');
      // Avoid calling Navigator synchronously inside initState.
      WidgetsBinding.instance.addPostFrameCallback((_) => _goNext());
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
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.next),
    );
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
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          if (_ready && _controller != null)
            FittedBox(
              fit: BoxFit.cover,
              child: SizedBox(
                width: _controller!.value.size.width,
                height: _controller!.value.size.height,
                child: VideoPlayer(_controller!),
              ),
            )
          else
            const Center(
              child: CircularProgressIndicator(color: Colors.white),
            ),
          Positioned(
            top: 12,
            right: 12,
            child: SafeArea(
              child: TextButton(
                onPressed: _goNext,
                style: TextButton.styleFrom(
                  backgroundColor: Colors.black.withValues(alpha: 0.38),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                ),
                child: const Text('Skip'),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
