// ================================================================
// AnimatedMeterFare - Allin1 Super App
// ================================================================
// Reusable "auto-meter settling" number animation. Ticks from
// whatever value it last displayed to a new [value] over a short,
// decelerating animation, like a real taxi meter settling on a final
// fare rather than the number instantly snapping.
//
// Display-only — has no knowledge of rides, categories, or Firestore.
// Any screen that already has a fare number to show (customer payment
// screens, category-specific completion views, etc.) can drop this in
// with just a value + style, whenever that number changes over time
// (e.g. an estimate updating to a hero-calculated final fare via an
// existing Firestore listener). It does not fetch anything itself.
// ================================================================

import 'package:flutter/material.dart';

class AnimatedMeterFare extends StatefulWidget {
  /// The fare value to display. Changing this (via didUpdateWidget)
  /// triggers a tween from the previously-displayed value to this one.
  final double value;

  /// Text style applied to the rendered number, e.g. the existing
  /// gold/₹ fare-card style already used on payment_screen.dart.
  final TextStyle? style;

  /// How long the settle animation takes for a value change.
  final Duration duration;

  /// Currency/prefix symbol shown before the number. Defaults to ₹.
  final String prefix;

  /// Decimal places shown, e.g. 0 for "₹40" or 2 for "₹40.00".
  final int fractionDigits;

  const AnimatedMeterFare({
    required this.value,
    this.style,
    this.duration = const Duration(milliseconds: 1200),
    this.prefix = '₹',
    this.fractionDigits = 0,
    super.key,
  });

  @override
  State<AnimatedMeterFare> createState() => _AnimatedMeterFareState();
}

class _AnimatedMeterFareState extends State<AnimatedMeterFare>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late Animation<double> _tween;
  double _displayedValue = 0;

  @override
  void initState() {
    super.initState();
    _displayedValue = widget.value;
    _controller = AnimationController(vsync: this, duration: widget.duration);
    _tween = AlwaysStoppedAnimation<double>(widget.value);
  }

  @override
  void didUpdateWidget(covariant AnimatedMeterFare oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value == widget.value) {
      return;
    }
    // Tween from whatever is currently on screen (which may itself be
    // mid-animation) to the new target — avoids a visual jump if a
    // second update arrives before the first settle finishes.
    _tween = Tween<double>(begin: _displayedValue, end: widget.value).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller
      ..duration = widget.duration
      ..forward(from: 0);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _tween,
      builder: (context, _) {
        _displayedValue = _tween.value;
        return Text(
          '${widget.prefix}${_displayedValue.toStringAsFixed(widget.fractionDigits)}',
          style: widget.style,
        );
      },
    );
  }
}
