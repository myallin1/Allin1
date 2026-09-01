import 'dart:async';
import 'package:flutter/material.dart';

class AutoWidgetSlider extends StatefulWidget {
  final List<Widget> children;
  final double width;
  final double height;
  final Duration duration;

  const AutoWidgetSlider({
    super.key,
    required this.children,
    this.width = 32,
    this.height = 32,
    this.duration = const Duration(seconds: 3),
  });

  @override
  State<AutoWidgetSlider> createState() => _AutoWidgetSliderState();
}

class _AutoWidgetSliderState extends State<AutoWidgetSlider> {
  int _currentIndex = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(widget.duration, (timer) {
      if (mounted && widget.children.isNotEmpty) {
        setState(() {
          _currentIndex = (_currentIndex + 1) % widget.children.length;
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
    if (widget.children.isEmpty) return SizedBox(width: widget.width, height: widget.height);
    if (widget.children.length == 1) {
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: widget.children.first,
      );
    }
    
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 1200), // Smooth crossfade
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
        child: SizedBox(
          key: ValueKey<int>(_currentIndex),
          width: widget.width,
          height: widget.height,
          child: FittedBox(
            fit: BoxFit.contain,
            child: widget.children[_currentIndex],
          ),
        ),
      ),
    );
  }
}
