// ================================================================
// clay_icon.dart — the 3D clay icon, and the surfaces that match it
// ================================================================
// NEW (Sep 5 2026 — the 3D Claymorphism icon set).
//
// Every colour, highlight and shadow here comes from ClayTokens, which
// is derived from the live theme — see clay_theme.dart's header for why
// that is not optional for this effect. Nothing in this file is a
// hardcoded hex.
//
// HOW THE 3D IS BUILT (and what it deliberately is not)
// A clay icon is four things stacked, cheapest first:
//   1. an outer lift  — BoxShadow on the container, Skia fast path
//   2. a body         — a tight top-left-to-bottom-right gradient
//   3. a rim light    — ONE gradient-shaded stroke, no blur
//   4. the glyph      — with a soft own-shadow so it sits IN the clay
//                       rather than floating on a coloured square
// What it is NOT is a blurred inset shadow. Flutter has no inset
// BoxShadow, so the standard trick is an ImageFilter per icon; in a
// scrolling grid on a ₹8,000 phone that is one offscreen pass per icon
// and the jank is immediately visible. The gradient stroke gives the
// same read of a rounded edge for a single draw call.
//
// SQUIRCLE, NOT CIRCLE
// The corner radius is a fixed fraction of the size, so a 40px icon and
// an 88px icon look like the same material rather than two different
// shapes. Clay reads as clay because the corners are generous but not
// round — a full circle loses the light/shade split that carries the
// depth.
import 'package:flutter/material.dart';

import 'clay_theme.dart';

/// Corner radius as a fraction of the icon's size. 0.30 is the point
/// where it still reads as a rounded square rather than a blob.
const double _kSquircle = 0.30;

/// The 3D clay icon tile.
///
/// ```dart
/// ClayIcon(icon: Icons.local_taxi_rounded, onTap: _openTaxi)
/// ```
///
/// Pass [color] to give the tile its own hue (a service category, a
/// status). Leave it off and it takes the theme's primary — which in
/// pink_white is the signature hot pink, and in every other theme is
/// that theme's own star colour.
class ClayIcon extends StatefulWidget {
  const ClayIcon({
    required this.icon,
    super.key,
    this.color,
    this.size = 56,
    this.iconSize,
    this.onTap,
    this.selected = false,
    this.enabled = true,
    this.label,
    this.semanticLabel,
  });

  final IconData icon;

  /// The clay body colour. Defaults to the theme's primary.
  final Color? color;

  /// Edge length of the tile. The glyph, corner radius and depth all
  /// scale from this, so callers set one number.
  final double size;

  /// Overrides the glyph size. Defaults to 46% of [size], which keeps
  /// enough clay visible around the glyph for the rim light to read.
  final double? iconSize;

  final VoidCallback? onTap;

  /// Lifts the tile higher and strengthens the rim — for the active tab
  /// or the current filter.
  final bool selected;

  /// A disabled tile keeps its shape but loses its colour and most of
  /// its lift, so it still looks like the same object, just inert.
  final bool enabled;

  /// Optional caption underneath, styled from the theme's own text
  /// scale.
  final String? label;

  final String? semanticLabel;

  @override
  State<ClayIcon> createState() => _ClayIconState();
}

class _ClayIconState extends State<ClayIcon> {
  bool _pressed = false;

  void _setPressed(bool v) {
    if (_pressed == v || !mounted) return;
    setState(() => _pressed = v);
  }

  @override
  Widget build(BuildContext context) {
    final clay = context.clay;
    final scheme = Theme.of(context).colorScheme;
    final interactive = widget.enabled && widget.onTap != null;

    // A disabled tile drops to the neutral body rather than a greyed-out
    // version of its colour: grey-on-brand looks like a rendering bug,
    // whereas plain clay looks intentionally switched off.
    final base = !widget.enabled
        ? clay.neutralBase(context)
        : (widget.color ?? scheme.primary);

    // Pressing pushes the tile INTO the surface. Depth drops rather than
    // the tile merely darkening, because a real clay button gets closer
    // to the page when you push it — that is the whole affordance.
    final level = !widget.enabled
        ? 0.35
        : _pressed
            ? 0.4
            : widget.selected
                ? 1.5
                : 1.0;

    final radius = BorderRadius.circular(widget.size * _kSquircle);
    final glyphSize = widget.iconSize ?? widget.size * 0.46;

    // White glyph on saturated clay, dark glyph on pale clay. Computed
    // from the body colour's own luminance rather than from the theme,
    // because the caller can pass any colour they like and a fixed
    // choice would be unreadable on half of them.
    final glyphColor = !widget.enabled
        ? scheme.onSurface.withValues(alpha: 0.35)
        : base.computeLuminance() > 0.62
            ? scheme.onSurface.withValues(alpha: 0.82)
            : Colors.white;

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      width: widget.size,
      height: widget.size,
      decoration: BoxDecoration(
        borderRadius: radius,
        gradient: clay.fill(base),
        boxShadow: clay.lift(level: level),
      ),
      child: CustomPaint(
        painter: _ClayRimPainter(
          gradient: clay.rim(),
          radius: widget.size * _kSquircle,
          // The rim thickens with the tile so a large icon does not end
          // up looking like a small one that was scaled up.
          strokeWidth: (widget.size * 0.03).clamp(1.0, 2.4),
          // Pressed-in clay catches almost no light along its top edge.
          opacity: _pressed ? 0.35 : (widget.enabled ? 1.0 : 0.5),
        ),
        child: Center(
          child: Icon(
            widget.icon,
            size: glyphSize,
            color: glyphColor,
            semanticLabel: widget.semanticLabel,
            // The glyph's own soft shadow is what stops it looking like
            // a sticker on a coloured square — it sits in the material.
            shadows: widget.enabled
                ? [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.22),
                      blurRadius: glyphSize * 0.18,
                      offset: Offset(0, glyphSize * 0.055),
                    ),
                  ]
                : null,
          ),
        ),
      ),
    );

    // AnimatedScale on top of the depth change. The two together are
    // what read as "pressed"; either alone reads as a colour flicker.
    final animated = AnimatedScale(
      scale: _pressed ? 0.94 : 1.0,
      duration: const Duration(milliseconds: 130),
      curve: Curves.easeOut,
      child: tile,
    );

    final body = widget.label == null
        ? animated
        : Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              animated,
              SizedBox(height: widget.size * 0.14),
              SizedBox(
                width: widget.size * 1.55,
                child: Text(
                  widget.label!,
                  textAlign: TextAlign.center,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: widget.enabled
                            ? scheme.onSurface
                            : scheme.onSurface.withValues(alpha: 0.45),
                        fontWeight: FontWeight.w700,
                        height: 1.15,
                      ),
                ),
              ),
            ],
          );

    if (!interactive) {
      return Semantics(
        label: widget.semanticLabel ?? widget.label,
        enabled: widget.enabled,
        child: body,
      );
    }

    // A raw GestureDetector rather than InkWell on purpose: a Material
    // ripple spreading across the tile fights the light source and
    // flattens the whole effect. The scale-and-sink IS the feedback.
    return Semantics(
      button: true,
      label: widget.semanticLabel ?? widget.label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        onTap: widget.onTap,
        child: body,
      ),
    );
  }
}

/// Strokes the rim light. Separate painter so the gradient shader is
/// built once per paint and never allocates a layer.
class _ClayRimPainter extends CustomPainter {
  const _ClayRimPainter({
    required this.gradient,
    required this.radius,
    required this.strokeWidth,
    required this.opacity,
  });

  final Gradient gradient;
  final double radius;
  final double strokeWidth;
  final double opacity;

  @override
  void paint(Canvas canvas, Size size) {
    if (opacity <= 0) return;
    // Inset by half the stroke so the line sits ON the edge rather than
    // straddling it and being half-clipped by the parent's border
    // radius.
    final rect = Offset.zero & size;
    final inset = rect.deflate(strokeWidth / 2);
    final rrect = RRect.fromRectAndRadius(
      inset,
      Radius.circular(radius - strokeWidth / 2),
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..shader = gradient.createShader(rect);
    if (opacity < 1) {
      paint.color = paint.color.withValues(alpha: opacity);
    }
    canvas.drawRRect(rrect, paint);
  }

  @override
  bool shouldRepaint(_ClayRimPainter old) =>
      old.gradient != gradient ||
      old.radius != radius ||
      old.strokeWidth != strokeWidth ||
      old.opacity != opacity;
}

/// A clay panel — the same material at card scale.
///
/// This is what a screen should reach for instead of hand-rolling a
/// Container with a guessed shadow, and it is what the ported
/// PremiumCard now uses underneath.
class ClaySurface extends StatelessWidget {
  const ClaySurface({
    required this.child,
    super.key,
    this.padding,
    this.radius = 20,
    this.color,
    this.level = 1,
    this.onTap,
  });

  final Widget child;
  final EdgeInsetsGeometry? padding;
  final double radius;

  /// Body colour. Defaults to the theme-derived neutral clay, which is
  /// a barely-pink white in light themes and a lifted charcoal in dark
  /// ones.
  final Color? color;

  final double level;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final clay = context.clay;
    final base = color ?? clay.neutralBase(context);

    final panel = Container(
      padding: padding,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        gradient: clay.fill(base),
        boxShadow: clay.lift(level: level),
      ),
      child: CustomPaint(
        painter: _ClayRimPainter(
          gradient: clay.rim(),
          radius: radius,
          strokeWidth: 1.2,
          opacity: 1,
        ),
        child: child,
      ),
    );

    if (onTap == null) return panel;

    // At card scale a ripple is expected and does not fight the light
    // the way it does on a 56px tile, so cards keep theirs — clipped to
    // the same radius, because a square ripple on a rounded card is the
    // kind of detail that makes an app feel unfinished.
    return Stack(
      children: [
        panel,
        Positioned.fill(
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(radius),
              splashColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.08),
              highlightColor:
                  Theme.of(context).colorScheme.primary.withValues(alpha: 0.04),
              onTap: onTap,
            ),
          ),
        ),
      ],
    );
  }
}
