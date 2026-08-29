// ================================================================
// ChittiCompanion — the floating robot that follows the customer
// Allin1 (Aug 19 2026)
// ================================================================
// Nizam's brief: Chitti should feel like "an intelligent man" living
// inside the app — always animated, flying to whatever section he's
// been asked about, floating alongside the customer until the service
// finishes, and dancing when it's done.
//
// ANDROID-ONLY, BY INSTRUCTION AND BY PHYSICS
//   Gated behind `ChittiCompanion.isSupported`. Two reasons, and the
//   second matters more than the first:
//     1. Nizam scoped this to the Android app explicitly.
//     2. This runs a permanent repeating animation on a root overlay.
//        On the PWA that means the browser can never idle the tab's
//        compositor, which on a low-end phone shows up as heat and
//        battery drain on a page the customer isn't even looking at.
//        Native Flutter can drive this on the raster thread cheaply;
//        a web canvas cannot.
//
// WHY NO GAME ENGINE, AND NO LOTTIE HERE
//   Nizam offered both. Neither is needed for what this actually does,
//   and both cost more than they return:
//     - A game engine (Flame/Unity) would add megabytes to the APK and
//       a second render loop competing with Flutter's, to animate one
//       sprite. That is the wrong order of magnitude of tool.
//     - Lottie is the right tool *when there is an artist-authored
//       animation file to play*. There isn't one — what we have is
//       assets/ai/ai_robot.webp, an animated WebP (192px, 63 frames,
//       already size-reduced from a 7.7 MB GIF; see ai_bot_avatar.dart
//       for that whole story). Lottie cannot play a WebP, and
//       converting raster frames to vector is not a thing. So the
//       ADDITIONAL motion is composed here from transforms, layered
//       over the asset's own idle loop.
//
//   Swap to Lottie the day an artist delivers a real .json — the mood
//   API here would not need to change.
//
// PERFORMANCE CONTRACT
//   ONE AnimationController drives everything. Every visual — bob,
//   sway, tilt, glow, dance — is a cheap function of that single
//   value. This matters: a controller per effect would mean four
//   independent tickers waking the engine on different frames.
//
//   The asset is decoded at a bounded cacheWidth rather than at its
//   native size — without that, all 63 frames are held as full-size
//   bitmaps for what is drawn as a 62dp badge, which is the exact
//   memory trap documented in ai_bot_avatar.dart.
//
//   Nothing in the per-frame path allocates: the image subtree is
//   passed as AnimatedBuilder's `child`, so it is built once and only
//   re-positioned thereafter.
// ================================================================

import 'dart:math' as math;

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';

/// What Chitti is doing right now. Drives motion, not layout.
enum ChittiMood {
  /// Default. Gentle bob and sway, as if hovering.
  idle,

  /// Travelling to a section the customer asked about — leans into the
  /// direction of travel like something with momentum.
  flying,

  /// Attached to a live service. Alert, tighter motion, brighter glow.
  working,

  /// Service finished. The celebration Nizam asked for.
  dancing,
}

/// How much energy Chitti is allowed to spend right now.
///
/// This is the battery answer, and it is deliberately separate from
/// [ChittiMood]: mood is what he's DOING, activity is how hard the
/// device is working to show it. A dancing Chitti in a backgrounded app
/// should cost nothing.
enum ChittiActivity {
  /// Full frame rate. Robot's own WebP loop plays, transforms run.
  active,

  /// Alive but calm — transforms only, at a third of the speed.
  resting,

  /// Frozen. No ticker at all. See the TickerMode note in build().
  sleeping,
}

class ChittiCompanion extends StatefulWidget {
  final ChittiMood mood;
  final ChittiActivity activity;
  final double size;
  final VoidCallback? onTap;

  /// Shown in a small bubble beside him. Null hides the bubble.
  final String? caption;

  const ChittiCompanion({
    super.key,
    this.mood = ChittiMood.idle,
    this.activity = ChittiActivity.active,
    this.size = 62,
    this.onTap,
    this.caption,
  });

  /// Android native only — see the header. Checked via
  /// defaultTargetPlatform rather than Platform.isAndroid because the
  /// latter throws on web, which is exactly the case being excluded.
  /// kIsWeb is checked FIRST and matters: on web,
  /// defaultTargetPlatform reports android for a Chrome-on-Android
  /// browser, so testing the platform alone would switch this on for
  /// every PWA user on an Android phone — precisely the population the
  /// gate exists to protect.
  static bool get isSupported =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  @override
  State<ChittiCompanion> createState() => _ChittiCompanionState();
}

class _ChittiCompanionState extends State<ChittiCompanion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    // 2.4s is slow enough to read as "hovering" rather than "vibrating".
    // The dance speeds this up by sampling the same controller faster
    // rather than by changing its duration, so there is never a jump
    // when the mood switches mid-cycle.
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2400),
    )..repeat();
  }

  @override
  void didUpdateWidget(ChittiCompanion old) {
    super.didUpdateWidget(old);
    if (old.activity != widget.activity) _applyActivity();
  }

  /// Resting slows the SAME controller rather than swapping to a
  /// different one, so the motion decelerates instead of snapping to a
  /// new phase mid-bob.
  void _applyActivity() {
    switch (widget.activity) {
      case ChittiActivity.active:
        _c.duration = const Duration(milliseconds: 2400);
        if (!_c.isAnimating) _c.repeat();
      case ChittiActivity.resting:
        _c.duration = const Duration(milliseconds: 7200);
        if (!_c.isAnimating) _c.repeat();
      case ChittiActivity.sleeping:
        // stop() rather than a slower repeat: a stopped controller is
        // removed from the scheduler entirely, so Flutter can let the
        // whole frame pipeline go idle. A "very slow" animation still
        // requests a frame 60 times a second — it just moves less. That
        // distinction is the entire battery saving.
        _c.stop();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// Vertical bob. A full sine over the cycle so it eases naturally at
  /// the top and bottom with no curve object needed.
  double _bob(double t) {
    switch (widget.mood) {
      case ChittiMood.idle:
        return math.sin(t * 2 * math.pi) * 4.0;
      case ChittiMood.working:
        return math.sin(t * 2 * math.pi) * 2.0;
      case ChittiMood.flying:
        return math.sin(t * 4 * math.pi) * 2.5;
      case ChittiMood.dancing:
        // Double-time, bigger throw, plus a small hop offset so it
        // reads as bouncing off a floor rather than floating.
        return math.sin(t * 6 * math.pi).abs() * -9.0 + 4.0;
    }
  }

  /// Horizontal sway. Only idle and dancing drift sideways; a working
  /// Chitti holding station next to live content should not wander.
  double _sway(double t) {
    switch (widget.mood) {
      case ChittiMood.idle:
        return math.sin(t * 2 * math.pi + math.pi / 3) * 2.5;
      case ChittiMood.dancing:
        return math.sin(t * 4 * math.pi) * 7.0;
      case ChittiMood.working:
      case ChittiMood.flying:
        return 0;
    }
  }

  /// Body tilt in radians.
  double _tilt(double t) {
    switch (widget.mood) {
      case ChittiMood.idle:
        return math.sin(t * 2 * math.pi) * 0.05;
      case ChittiMood.working:
        return 0;
      case ChittiMood.flying:
        // A constant forward lean — the posture of something moving,
        // not something bobbing in place.
        return -0.22;
      case ChittiMood.dancing:
        return math.sin(t * 4 * math.pi) * 0.30;
    }
  }

  Color get _glowColor {
    switch (widget.mood) {
      case ChittiMood.idle:
        return const Color(0xFF6C63FF);
      case ChittiMood.working:
        return const Color(0xFF00C853);
      case ChittiMood.flying:
        return const Color(0xFF00B0FF);
      case ChittiMood.dancing:
        return const Color(0xFFFFBB00);
    }
  }

  @override
  Widget build(BuildContext context) {
    // ── THE BATTERY MECHANISM ──────────────────────────────────
    // TickerMode is doing the heavy lifting, and it is doing something
    // that stopping the AnimationController alone cannot.
    //
    // The single biggest cost in this widget was never the transforms
    // — it is ai_robot.webp, an ANIMATED WebP with 63 frames. Flutter
    // decodes those frames continuously for as long as the image is on
    // screen, on the UI thread, forever. That is real CPU burning in
    // the background of a 20-minute ride, and no amount of animation
    // tuning on our side touches it.
    //
    // Flutter's MultiFrameImageStreamCompleter checks TickerMode, so
    // disabling it here halts the image's own frame decoding AND every
    // controller in this subtree in one move. Chitti genuinely freezes
    // rather than merely moving slowly.
    //
    // RepaintBoundary keeps his repaints off whatever screen he happens
    // to be floating over — without it, every bob would mark the page
    // underneath dirty too.
    return RepaintBoundary(
      child: TickerMode(
        enabled: widget.activity != ChittiActivity.sleeping,
        child: _buildBody(),
      ),
    );
  }

  Widget _buildBody() {
    return GestureDetector(
      onTap: widget.onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedBuilder(
        animation: _c,
        // The image and caption are passed as `child` so they are built
        // ONCE and merely re-positioned every frame. Rebuilding an
        // Image widget 60 times a second is the classic way this kind
        // of effect quietly becomes expensive.
        child: _buildRobot(),
        builder: (context, child) {
          final t = _c.value;
          final glowT = (math.sin(t * 2 * math.pi) + 1) / 2;
          return Transform.translate(
            offset: Offset(_sway(t), _bob(t)),
            child: Transform.rotate(
              angle: _tilt(t),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: _glowColor.withValues(
                        alpha: 0.18 + glowT * 0.30,
                      ),
                      blurRadius: 18 + glowT * 12,
                      spreadRadius: 1 + glowT * 3,
                    ),
                  ],
                ),
                child: child,
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRobot() {
    final s = widget.size;
    // CHANGED (Aug 25 2026 — "full body + dancing" request): the
    // earlier HEAD CROP (Nizam's original "robot oda head mattum" ask)
    // is gone — the badge now shows the same full, unclipped,
    // continuously-animated ai_robot.webp AiBotAvatar shows on PWA, so
    // the companion and the web FAB read as the same character instead
    // of two different-looking Chittis. Dropped the circular
    // ClipOval/background fill for the same reason: a full-body sprite
    // centered in a small solid circle read cramped in review — the rim
    // light alone (kept, via the glow BoxShadow already applied one
    // level up in _buildBody()) is enough to keep him reading as "lit
    // from within" without a hard circular crop.
    return SizedBox(
      width: s,
      height: s,
      child: Image.asset(
        'assets/ai/ai_robot.webp',
        // Decoded once at roughly twice the display size — enough for
        // a crisp result on 3x screens without holding a 329 KB
        // full-resolution bitmap in memory.
        cacheWidth: (s * 2.4).round(),
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => Icon(
          Icons.smart_toy_rounded,
          color: _glowColor,
          size: s * 0.7,
        ),
      ),
    );
  }
}
