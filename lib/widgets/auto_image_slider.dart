import 'dart:async';
import 'package:flutter/material.dart';

class AutoImageSlider extends StatefulWidget {
  final List<String> imagePaths;
  final double width;
  final double height;
  final Duration duration;

  const AutoImageSlider({
    super.key,
    required this.imagePaths,
    this.width = 24,
    this.height = 24,
    this.duration = const Duration(seconds: 3),
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
          fit: BoxFit.cover,
        ),
      ),
    );
  }
}
