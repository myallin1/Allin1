// ================================================================
// premium_theme.dart — Allin1's premium surface design system
// ================================================================
// NEW (Aug 18 2026 — Founder's "Apple Store meets CRED" brief for the
// Mobile Hub + Rewards polish phase).
//
// WHY A SHARED FILE AND NOT PER-SCREEN STYLING: the brief covers three
// separate surfaces (Mobile Hub cards, Rewards offer cards, and the
// seller/admin video-link inputs). Hand-styling each one is how design
// systems rot — six months later the pink on Rewards is a shade off
// the pink on Mobiles and nobody knows which is right. Every token and
// shell below is defined ONCE here; the screens compose them.
//
// PERFORMANCE NOTE, deliberately baked into these choices:
// this app runs on budget Android phones across Erode. So:
//   * No BackdropFilter blur in list rows. Real glassmorphism forces
//     an offscreen render pass PER blurred widget, which is exactly
//     the scroll jank we just removed by virtualizing these lists.
//     kGlassSurface fakes the glass look with a translucent fill +
//     hairline highlight border, which costs nothing. Genuine blur is
//     reserved for ONE full-screen element at a time (the video
//     modal's scrim), where a single pass is affordable.
//   * Shadows are layered but low-spread. A large blurRadius with a
//     big spread is one of the cheapest ways to make a list stutter.
// ================================================================

import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// ── Brand tokens ────────────────────────────────────────────────
/// The signature brand pink. Matches _kBrandPink used by the taxi
/// catalog and the dashboard mega-cards — one pink, app-wide.
const Color kPremiumPink = Color(0xFFFF4FA3);
const Color kPremiumPinkDeep = Color(0xFFBE2A7A);
const Color kPremiumInk = Color(0xFF121A3D);
const Color kPremiumMuted = Color(0xFF7A8199);
const Color kPremiumHairline = Color(0xFFEDEFF5);
const Color kPremiumWhite = Color(0xFFFFFFFF);
const Color kPremiumGreen = Color(0xFF00C853);
const Color kVideoRed = Color(0xFFFF0000);

/// Corner radii, per the brief's 16–24 range.
const double kRadiusSm = 14;
const double kRadiusMd = 20;
const double kRadiusLg = 24;

// ── Gradients ───────────────────────────────────────────────────
/// The signature "ultra-soft pink-to-white" card wash. Deliberately
/// subtle: the pink is barely there at the top and gone by 40%, so
/// content sits on near-white and stays readable.
const LinearGradient kSoftPinkWash = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFFFFF3F8), kPremiumWhite, kPremiumWhite],
  stops: [0.0, 0.45, 1.0],
);

/// Stronger brand gradient for hero/CTA surfaces only — never behind
/// body text.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [kPremiumPink, kPremiumPinkDeep],
);

/// Bottom-up scrim so white text stays legible over any poster image,
/// no matter how bright the photo is.
const LinearGradient kImageScrim = LinearGradient(
  begin: Alignment.bottomCenter,
  end: Alignment.topCenter,
  colors: [Color(0xE6000000), Color(0x66000000), Color(0x00000000)],
  stops: [0.0, 0.45, 1.0],
);

// ── Elevation ───────────────────────────────────────────────────
/// Two-layer shadow: a tight contact shadow plus a wide soft one. That
/// pairing is what reads as "premium depth" rather than a flat drop
/// shadow — and both layers keep spreadRadius at 0 to stay cheap.
List<BoxShadow> premiumShadow({double opacity = 1}) => [
      BoxShadow(
        color: kPremiumInk.withValues(alpha: 0.05 * opacity),
        blurRadius: 4,
        offset: const Offset(0, 2),
      ),
      BoxShadow(
        color: kPremiumPink.withValues(alpha: 0.10 * opacity),
        blurRadius: 22,
        offset: const Offset(0, 10),
      ),
    ];

/// Glow used behind the video badge and other "look at me" chips.
List<BoxShadow> glowShadow(Color color, {double strength = 1}) => [
      BoxShadow(
        color: color.withValues(alpha: 0.45 * strength),
        blurRadius: 14,
        offset: const Offset(0, 3),
      ),
    ];

// ── Text ────────────────────────────────────────────────────────
TextStyle premiumTitle({double size = 15, Color color = kPremiumInk}) =>
    GoogleFonts.outfit(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w800,
      height: 1.2,
      letterSpacing: -0.2,
    );

TextStyle premiumBody({double size = 12, Color color = kPremiumMuted}) =>
    GoogleFonts.outfit(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w500,
      height: 1.35,
    );

TextStyle premiumPrice({double size = 17, Color color = kPremiumPink}) =>
    GoogleFonts.outfit(
      color: color,
      fontSize: size,
      fontWeight: FontWeight.w900,
      letterSpacing: -0.5,
    );

// ================================================================
// Shells
// ================================================================

/// The standard premium card shell: soft pink-to-white wash, hairline
/// border, layered shadow, generous radius. Everything that should
/// read as "a card" in the Mobile Hub or Rewards uses this, so the
/// look is defined in exactly one place.
class PremiumCard extends StatelessWidget {
  final Widget child;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry? padding;
  final double radius;
  final bool dimmed;

  const PremiumCard({
    super.key,
    required this.child,
    this.onTap,
    this.padding,
    this.radius = kRadiusLg,
    this.dimmed = false,
  });

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: padding,
      decoration: BoxDecoration(
        gradient: kSoftPinkWash,
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: kPremiumPink.withValues(alpha: 0.14)),
        boxShadow: premiumShadow(opacity: dimmed ? 0.4 : 1),
      ),
      clipBehavior: Clip.antiAlias,
      child: child,
    );

    if (onTap == null) return card;
    // Material+InkWell over the top so the tap ripple is clipped to the
    // same radius as the card — a square ripple on a 24px-radius card
    // is the kind of detail that makes an app feel unfinished.
    return Stack(
      children: [
        card,
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              splashColor: kPremiumPink.withValues(alpha: 0.08),
              highlightColor: kPremiumPink.withValues(alpha: 0.04),
              onTap: onTap,
            ),
          ),
        ),
      ],
    );
  }
}

/// Frosted-looking chip WITHOUT a real blur pass — see this file's
/// performance note. Used for badges that sit on top of photos.
class GlassChip extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color tint;

  const GlassChip({
    super.key,
    required this.child,
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
/// affordances — a customer should learn it once.
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

/// Small pill for discounts, condition grades, stock state, etc.
class PremiumPill extends StatelessWidget {
  final String text;
  final Color color;
  final bool solid;

  const PremiumPill({
    super.key,
    required this.text,
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
  const PremiumModalScrim({super.key, required this.child});

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
