// ================================================================
// clay_theme.dart — 3D Claymorphism, derived from the live theme
// ================================================================
// NEW (Sep 5 2026 — Nizam: "build the clay icons on context.colors,
// port the premium_theme to it, and fix the dark-mode gap in the same
// pass ... ensure that our signature Hot Pink and White theme remains
// the primary star, but make sure the 3D claymorphism seamlessly
// adapts to dark mode").
//
// WHAT CLAYMORPHISM ACTUALLY IS, AND WHY IT CANNOT BE HARDCODED
// A clay object reads as 3D because of exactly three things: a body
// colour, a highlight where the light hits it, and a shadow where the
// light does not. Those are not decoration — they ARE the effect. Fix
// them to constants and the icon stops being clay the moment the
// background changes: a white rim-light that looks like sunlight on a
// white app looks like a scratch on a near-black one, and a soft grey
// drop shadow that gives depth on white is invisible on #0A0A1A.
//
// This is the exact failure premium_theme.dart already had — a full
// design system with zero Theme.of in it, so its cards render as a
// bright white slab in dark_purple and system_dark. Building the icons
// the same way would have repeated it at a much larger scale, because
// icons appear on every screen and those cards appear on five.
//
// DERIVED, NOT REGISTERED
// ClayTokens is a ThemeExtension, but ThemeService does NOT have to
// register it: [ClayTokens.of] derives a correct set from whatever
// ColorScheme is active, and only uses a registered extension if a
// theme chooses to override one. That means all five themes — and any
// sixth added later — get working clay for free, and nobody can ship a
// new theme that silently has no clay tokens. A theme that wants a
// different light direction or a deeper look still can; it just is not
// obliged to.
//
// PERFORMANCE, ON PURPOSE
// The rule premium_theme.dart set still holds and matters more here,
// because icons appear in scrolling grids on budget Erode phones:
//   * No BackdropFilter, no ImageFilter, no saveLayer. Real clay
//     tutorials reach for blurred inset shadows; Flutter has no inset
//     BoxShadow, so the usual workaround is a blur pass PER ICON. In a
//     20-icon grid that is 20 offscreen passes and visible jank.
//   * The rim light here is a single gradient-shaded stroke instead —
//     light at the top-left, shadow at the bottom-right, one draw call,
//     no filter. It reads as the same rounded edge and costs nothing.
//   * Outer depth uses BoxShadow on the parent, which Skia has a fast
//     path for, with spreadRadius kept at 0.
import 'package:flutter/material.dart';

/// Nudges a colour lighter/darker in HSL, which keeps the hue intact.
/// Blending toward white/black instead would wash the brand pink out to
/// a dusty rose on the highlight side.
Color _shift(Color c, double amount) {
  final hsl = HSLColor.fromColor(c);
  return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
}

@immutable
class ClayTokens extends ThemeExtension<ClayTokens> {
  const ClayTokens({
    required this.brightness,
    required this.highlight,
    required this.shadow,
    required this.ambient,
    required this.depth,
  });

  final Brightness brightness;

  /// The light-source colour. Light themes get near-white because the
  /// light is the room; dark themes get a low-alpha white, because on a
  /// dark surface a full-strength white rim reads as a hard edge rather
  /// than as light falling on something soft.
  final Color highlight;

  /// The occlusion colour — the contact shadow directly under the
  /// object.
  final Color shadow;

  /// The wide, soft shadow further out. Tinted with the brand colour in
  /// light themes (this is what makes pink-on-white feel warm rather
  /// than grey and cheap) and pure black in dark ones, where a tinted
  /// shadow only muddies.
  final Color ambient;

  /// Global multiplier on how far things lift off the surface. Dark
  /// themes need slightly more, because a dark shadow on a dark
  /// background carries less information than a grey one on white.
  final double depth;

  bool get isDark => brightness == Brightness.dark;

  /// The tokens for the currently active theme.
  ///
  /// Prefers an explicitly registered [ClayTokens] extension; falls back
  /// to deriving one from the ColorScheme, which is what all five
  /// current themes use. See the header for why that fallback is the
  /// default rather than an afterthought.
  factory ClayTokens.of(BuildContext context) {
    final theme = Theme.of(context);
    final registered = theme.extension<ClayTokens>();
    if (registered != null) return registered;

    final dark = theme.brightness == Brightness.dark;
    return ClayTokens(
      brightness: theme.brightness,
      highlight: dark
          ? Colors.white.withValues(alpha: 0.16)
          : Colors.white.withValues(alpha: 0.92),
      shadow: dark
          ? Colors.black.withValues(alpha: 0.55)
          : theme.colorScheme.onSurface.withValues(alpha: 0.14),
      ambient: dark
          ? Colors.black.withValues(alpha: 0.45)
          // The signature pink, at a whisper. This is the single line
          // that keeps "Hot Pink and White" the star: every elevated
          // thing in a light theme sits in a faintly pink pool of shadow
          // instead of a grey one.
          : theme.colorScheme.primary.withValues(alpha: 0.16),
      depth: dark ? 1.15 : 1.0,
    );
  }

  /// The body of a clay object: lighter where the light hits (top-left)
  /// and deeper on the far side. The spread is tight on purpose — a wide
  /// gradient reads as a painted button, a tight one reads as a curved
  /// surface.
  LinearGradient fill(Color base) => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          _shift(base, isDark ? 0.07 : 0.09),
          base,
          _shift(base, isDark ? -0.06 : -0.07),
        ],
        stops: const [0.0, 0.55, 1.0],
      );

  /// The rim light — the whole trick, in one stroke. Bright along the lit
  /// edge, dark along the shaded one, so the eye reads a rounded solid
  /// without a single blur pass.
  LinearGradient rim() => LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [
          highlight,
          highlight.withValues(alpha: highlight.a * 0.15),
          shadow.withValues(alpha: shadow.a * 0.55),
        ],
        stops: const [0.0, 0.45, 1.0],
      );

  /// Two layers: a tight contact shadow saying the object is touching
  /// the surface, and a wide soft one saying how far it is lifted. Both
  /// keep spreadRadius at 0 — a spread on a wide blur is one of the
  /// cheapest ways to make a list stutter.
  List<BoxShadow> lift({double level = 1}) {
    final d = depth * level;
    return [
      BoxShadow(
        color: shadow,
        blurRadius: 5 * d,
        offset: Offset(0, 2 * d),
      ),
      BoxShadow(
        color: ambient,
        blurRadius: 20 * d,
        offset: Offset(0, 9 * d),
      ),
      // The counter-light from above. Light themes only: on a dark
      // background this reads as a glow around the object rather than as
      // light coming from somewhere.
      if (!isDark)
        BoxShadow(
          color: Colors.white.withValues(alpha: 0.85),
          blurRadius: 10 * d,
          offset: Offset(-3 * d, -4 * d),
        ),
    ];
  }

  /// A clay body colour for callers with no brand colour in mind (a
  /// neutral tile, a disabled state). Derived from the theme's own
  /// surface so it sits ON the background rather than fighting it.
  Color neutralBase(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return isDark
        ? Color.alphaBlend(Colors.white.withValues(alpha: 0.07), scheme.surface)
        : Color.alphaBlend(
            scheme.primary.withValues(alpha: 0.05),
            Colors.white,
          );
  }

  @override
  ClayTokens copyWith({
    Brightness? brightness,
    Color? highlight,
    Color? shadow,
    Color? ambient,
    double? depth,
  }) =>
      ClayTokens(
        brightness: brightness ?? this.brightness,
        highlight: highlight ?? this.highlight,
        shadow: shadow ?? this.shadow,
        ambient: ambient ?? this.ambient,
        depth: depth ?? this.depth,
      );

  @override
  ClayTokens lerp(ThemeExtension<ClayTokens>? other, double t) {
    if (other is! ClayTokens) return this;
    return ClayTokens(
      brightness: t < 0.5 ? brightness : other.brightness,
      highlight: Color.lerp(highlight, other.highlight, t)!,
      shadow: Color.lerp(shadow, other.shadow, t)!,
      ambient: Color.lerp(ambient, other.ambient, t)!,
      depth: depth + (other.depth - depth) * t,
    );
  }
}

extension ClayContext on BuildContext {
  /// `context.clay` — deliberately the same shape as the existing
  /// `context.colors`, so there is one habit to learn, not two.
  ClayTokens get clay => ClayTokens.of(this);
}
