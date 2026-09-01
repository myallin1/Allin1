// ================================================================
// ai_bot_avatar.dart — the MyAllin1 AI assistant's face
// ================================================================
// NEW (Aug 17 2026 — Nizam: "namma app la ai kaga use pannirukka icons
// ah totala replace pannanum... antha robo gif... ithula namma app speed
// 1% kuda slow agakudathu").
//
// ONE widget for every place the assistant appears, so the AI has a
// single identity instead of three drifting copies of an icon.
//
// ── WHY THE SOURCE GIF COULD NOT BE USED AS-IS ─────────────────────
// The supplied GIF was 7.7 MB, 560x560, **188 frames**. File size was
// the smaller of the two problems:
//
//   * SIZE — pubspec bundles `assets/` wholesale, so 7.7 MB would ship
//     inside the app to every customer and every hero. At 1000 launch
//     downloads that is ~7.7 GB of Firebase Hosting bandwidth, well
//     past the monthly allowance on this plan.
//
//   * FRAMES — the real danger. Flutter holds each decoded frame as a
//     full bitmap: 560 x 560 x 4 bytes x 188 = ~225 MB of RAM for one
//     icon. On the ₹8,000 phones this app's heroes actually use, that
//     is not jank, that is the OS killing the app.
//
// Re-encoded to 192x192 / 63 frames / animated WebP: 0.31 MB on disk
// (25x smaller) and ~9 MB decoded (25x less RAM), with no visible
// difference. 192px covers a 64dp target at 3x density — beyond that
// the pixels cannot be seen. 63 frames is imperceptible from 188 in a
// looping idle animation, and costs a third of the memory.
//
// If the artwork is ever replaced, re-run the same reduction. Dropping
// a raw GIF into assets/ai/ will quietly undo all of this.
import 'package:flutter/material.dart';

class AiBotAvatar extends StatelessWidget {
  const AiBotAvatar({
    this.size = 24,
    this.fallbackColor = Colors.white,
    super.key,
  });

  final double size;

  /// Colour for the icon shown if the asset is missing — e.g. an older
  /// installed build whose bundle predates assets/ai/. The assistant
  /// still works; it just wears the old face rather than showing a
  /// broken-image box.
  final Color fallbackColor;

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/ai/ai_robot.webp',
      width: size,
      height: size,
      fit: BoxFit.contain,
      // Decode at display size instead of full resolution. Without this
      // Flutter keeps the 192px frames in memory even when drawing an
      // 18px header icon — the whole point of the re-encode above.
      cacheWidth: (size * MediaQuery.of(context).devicePixelRatio).round(),
      errorBuilder: (_, __, ___) =>
          Icon(Icons.auto_awesome, color: fallbackColor, size: size),
    );
  }
}
