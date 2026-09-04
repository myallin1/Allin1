// ================================================================
// premium_theme.dart — Allin1's premium surface design system
// ================================================================
// NEW (Aug 18 2026 — Founder's "Apple Store meets CRED" brief for the
// Mobile Hub + Rewards polish phase).
//
// PORTED TO THE LIVE THEME (Sep 5 2026 — Nizam: "port the premium_theme
// to it, and fix the dark-mode gap in the same pass").
//
// WHAT WAS WRONG
// This file was a complete design system with zero Theme.of in it —
// every value a hardcoded const, including the card background
// (kPremiumWhite) and the body text colour (kPremiumInk, a near-black).
// It therefore ignored the five-way theme switcher entirely: in
// dark_purple and system_dark the Mobile Hub, Erode Offers and the
// video-link fields rendered as a bright white slab with black text in
// an otherwise dark app. Nothing crashed and nothing looked broken
// enough to get reported — it just looked unfinished, in two of the
// five themes, for months.
//
// WHAT CHANGED, AND THE LINE BETWEEN THE TWO KINDS OF TOKEN
// The fix is NOT "make everything dynamic". Two genuinely different
// things were mixed together here:
//
//   * BRAND constants — the pink, the video red, the verified green,
//     the corner radii. These mean something on their own: pink is
//     Allin1, red is "this has a video", green is "verified". They are
//     the same in every theme by definition, and they stay const. The
//     signature Hot Pink and White look is not diluted by this change;
//     it IS the light theme, unaltered.
//
//   * SURFACE and TEXT colours — card background, ink, muted text,
//     hairline borders, the card wash, the elevation shadow. These are
//     only ever "whatever reads correctly against the current
//     background", which is precisely what a theme is for. These now
//     come from the live ColorScheme via `context.premium`, and the
//     card shell delegates to ClaySurface so it is literally the same
//     material as the 3D clay icons.
//
// THE PERFORMANCE RULES STILL HOLD — they are the reason this file
// existed as one shared place to begin with. This app runs on budget
// Android phones across Erode, so:
//   * No BackdropFilter blur in list rows. Real glassmorphism forces an
//     offscreen render pass PER blurred widget, which is exactly the
//     scroll jank we removed by virtualizing these lists. GlassChip
//     fakes the glass look with a translucent fill + hairline highlight
//     border, which costs nothing. Genuine blur is reserved for ONE
//     full-screen element at a time (the video modal's scrim), where a
//     single pass is affordable.
//   * Shadows are layered but low-spread. A large blurRadius with a big
//     spread is one of the cheapest ways to make a list stutter.
// ================================================================

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'clay_icon.dart';
import 'clay_theme.dart';

// ── Brand tokens (theme-independent, by definition) ──────────────
/// The signature brand pink. Matches _kBrandPink used by the taxi
/// catalog and the dashboard mega-cards — one pink, app-wide.
const Color kPremiumPink = Color(0xFFFF4FA3);
const Color kPremiumPinkDeep = Color(0xFFBE2A7A);
const Color kPremiumGreen = Color(0xFF00C853);
const Color kVideoRed = Color(0xFFFF0000);

/// Corner radii, per the brief's 16–24 range.
const double kRadiusSm = 14;
const double kRadiusMd = 20;
const double kRadiusLg = 24;

// ── Surface + text tokens (theme-derived) ───────────────────────
/// The surface half of this design system, read from the active theme.
///
/// Deliberately a thin layer over the existing `context.colors` rather
/// than a parallel set of names: this app already had two design systems
/// that disagreed, and adding a third with its own opinion of what
/// "muted text" means would be the same mistake again. Everything here
/// maps onto the ColorScheme that ThemeService already gets right.
class PremiumSurface {
  const PremiumSurface(this._context);
  final BuildContext _context;

  ColorScheme get _scheme => Theme.of(_context).colorScheme;

  /// Card / sheet background. A barely-pink white in the light themes —
  /// the signature look, unchanged — and the theme's own raised surface
  /// in the dark ones.
  Color get card => _context.clay.neutralBase(_context);

  /// Primary body text. Was a hardcoded near-black.
  Color get ink => _scheme.onSurface;

  /// Secondary text, captions, inactive icons.
  Color get muted => _scheme.onSurface.withValues(alpha: 0.6);

  /// Hairline dividers, thumbnail placeholders, input borders.
  Color get hairline => _scheme.outline;

  /// The signature ultra-soft card wash. Still pink-to-white in light
  /// themes; in dark themes the same gradient shape computed against a
  /// dark body, so cards keep their subtle curvature instead of turning
  /// into flat rectangles.
  Gradient get wash => _context.clay.fill(card);

  /// The layered elevation. Now the same lift the clay icons use, so a
  /// card and an icon on the same screen are lit from the same place.
  List<BoxShadow> shadow({double opacity = 1}) =>
      _context.clay.lift(level: opacity);
}

extension PremiumThemeContext on BuildContext {
  /// `context.premium` — same shape as `context.colors` and
  /// `context.clay`.
  PremiumSurface get premium => PremiumSurface(this);
}

// ── Gradients ───────────────────────────────────────────────────
/// Stronger brand gradient for hero/CTA surfaces only — never behind
/// body text. Brand, so const.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kPremiumPink, kPremiumPinkDeep],
);

/// Bottom-up scrim so white text stays legible over any poster image, no
/// matter how bright the photo is. Photos are photos in every theme, so
/// this stays const too.
const LinearGradient kImageScrim = LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [Color(0xE6000000), Color(0x66000000), Color(0x00000000)],
  stops: [0.0, 0.45, 1.0],
);

// ── Elevation ───────────────────────────────────────────────────
/// Glow used behind the video badge and other "look at me" chips. Takes
/// its colour from the caller, so it needs no theme of its own.
List<BoxShadow> glowShadow(Color color, {double strength = 1}) => [
      BoxShadow(
        color: color.withValues(alpha: 0.45 * strength),
        blurRadius: 14,
        offset: const Offset(0, 3),
      ),
    ];

// ── Text ────────────────────────────────────────────────────────
// These now take a BuildContext. That is a deliberate breaking change
// rather than an optional named argument: an optional context is exactly
// how a file ends up half-migrated, with two call sites still painting
// black text on a dark sheet and nobody noticing for another six months.
// There were eight call sites; all eight are updated in this same pass.

TextStyle premiumTitle(BuildContext context,
        {double size = 15, Color? color}) =>
    GoogleFonts.outfit(
      color: color ?? context.premium.ink,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: -0.2,
    );

TextStyle premiumBody(BuildContext context, {double size = 12, Color? color}) =>
    GoogleFonts.outfit(
      color: color ?? context.premium.muted,
      fontSize: size,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );

/// Prices stay the brand accent in every theme — a price is a call to
/// action, not body copy.
TextStyle premiumPrice(BuildContext context,
        {double size = 17, Color? color}) =>
    GoogleFonts.outfit(
      color: color ?? Theme.of(context).colorScheme.primary,
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
    );

// ================================================================
// Shells
// ================================================================

/// The standard premium card shell: soft wash, hairline rim, layered
/// shadow, generous radius.
///
/// Now a thin wrapper over [ClaySurface] rather than its own Container.
/// Keeping two implementations of "an elevated rounded panel" is how the
/// pink on Rewards ends up a shade off the pink on Mobiles — the exact
/// rot this file was written to prevent. One material, and this name
/// stays only so the existing call sites keep reading naturally.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool dimmed;

  const PremiumCard({
    required this.child,
    super.key,
    this.onTap,
    this.padding,
    this.radius = kRadiusLg,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) => ClaySurface(
        padding: padding,
        radius: radius,
        level: dimmed ? 0.4 : 1,
        onTap: onTap,
        child: child,
      );
}

/// Frosted-looking chip WITHOUT a real blur pass — see this file's
/// performance note.
///
/// Stays white-on-translucent in every theme on purpose: this sits on
/// top of product PHOTOS, not on the app background, and a photo is
/// equally bright whichever theme is active. Tinting it to the theme
/// would make it unreadable on half the listings.
class GlassChip extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color tint;

  const GlassChip({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
    this.tint = Colors.white,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: padding,
      decoration: BoxDecoration(
        color: tint.withValues(alpha: 0.22),
        borderRadius: BorderRadius.circular(kRadiusSm),
        border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
      ),
      child: child,
    );
  }
}

/// The glowing "▶ VIDEO" badge from the brief. One widget so the Mobile
/// Hub and Rewards can never end up with two different video
/// affordances — a customer should learn it once. Red is the meaning
/// here, so it does not follow the theme.
class VideoGlowBadge extends StatelessWidget {
  final String label;
  final bool compact;

  const VideoGlowBadge({
    super.key,
    this.label = 'VIDEO',
    this.compact = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 8 : 12,
        vertical: compact ? 4 : 7,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFF2D2D), kVideoRed],
        ),
        borderRadius: BorderRadius.circular(kRadiusSm),
        boxShadow: glowShadow(kVideoRed),
        border: Border.all(color: Colors.white.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.play_arrow_rounded,
              color: Colors.white, size: compact ? 12 : 16),
          SizedBox(width: compact ? 2 : 5),
          Text(
            label,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: compact ? 9 : 11.5,
              fontWeight: FontWeight.w900,
              letterSpacing: 0.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Small pill for discounts, condition grades, stock state, etc. The
/// caller supplies the colour, which is always a meaning (green =
/// verified, pink = offer), so this needs no theme of its own.
class PremiumPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool solid;

  const PremiumPill({
    required this.text,
    super.key,
    this.color = kPremiumPink,
    this.solid = true,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: solid ? color : color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        boxShadow: solid ? glowShadow(color, strength: 0.5) : null,
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(
          color: solid ? Colors.white : color,
          fontSize: 9.5,
          fontWeight: FontWeight.w900,
          letterSpacing: 0.3,
        ),
      ),
    );
  }
}

/// Full-screen scrim for modals. This is the ONE place a real blur is
/// used — a single pass over a single surface, only while a modal is
/// open, which is affordable where a per-row blur would not be.
class PremiumModalScrim extends StatelessWidget {
  final Widget child;
  const PremiumModalScrim({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    return BackdropFilter(
      filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
      child: Container(
        color: Colors.black.withValues(alpha: 0.45),
        child: child,
      ),
    );
  }
}
