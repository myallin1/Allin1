import 'dart:async';
import 'package:flutter/material.dart';

class AutoImageSlider extends StatefulWidget {
  final List<String> imagePaths;
  final double width;
  final double height;
  final Duration duration;

  /// How each image fills its box.
  ///
  /// Defaults to BoxFit.cover, which is what Food Delivery needs — a
  /// photo of a dish should fill the circle edge to edge, and cropping
  /// the corners of a plate costs nothing.
  ///
  /// Vehicles are the opposite case: they are cut-out PNGs on
  /// transparent backgrounds, wider than they are tall. `cover` on
  /// those crops the front and back of the car away and leaves a
  /// zoomed-in slab of roof. Pass BoxFit.contain for those — see the
  /// Taxi mega card.
  final BoxFit fit;

  const AutoImageSlider({
    super.key,
    required this.imagePaths,
    this.width = 24,
    this.height = 24,
    this.duration = const Duration(seconds: 3),
    this.fit = BoxFit.cover,
  });

  @override
  State<AutoImageSlider> createState() => _AutoImageSliderState();
}

class _AutoImageSliderState extends State<AutoImageSlider> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(widget.duration, (timer) {
      if (mounted && widget.imagePaths.isNotEmpty) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.imagePaths.length;
        });
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.imagePaths.isEmpty) return SizedBox(width: widget.width, height: widget.height);
    
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1200), // Slower animation
        switchInCurve: Curves.easeInOutCubic,
        switchOutCurve: Curves.easeInOutCubic,
        transitionBuilder: (Widget child, Animation<double> animation) {
          final slideAnim = Tween<Offset>(
            begin: const Offset(0.05, 0.0), // Slight horizontal slide
            end: Offset.zero,
          ).animate(animation);

          return FadeTransition(
            opacity: animation,
            child: SlideTransition(
              position: slideAnim,
              child: child,
            ),
          );
        },
        child: Image.asset(
          widget.imagePaths[_currentIndex],
          key: ValueKey<int>(_currentIndex),
          width: widget.width,
          height: widget.height,
          fit: widget.fit,
          // Decode at ~3x the display box rather than at the source
          // resolution. These vehicle PNGs are up to 2600px wide; at
          // full size five of them held as bitmaps would be tens of MB
          // of RAM for icons drawn at 34px. Same trap documented in
          // ai_bot_avatar.dart.
          cacheWidth: (widget.width * 3).round(),
          // A missing asset must never become a red error box in the
          // middle of the home screen — it degrades to empty space.
          errorBuilder: (_, __, ___) =>
              SizedBox(width: widget.width, height: widget.height),
        ),
      ),
    );
  }
}
