import 'package:flutter/material.dart';

class PulseGlowText extends StatefulWidget {
  const PulseGlowText({
    required this.text,
    required this.style,
    this.glowColor,
    this.maxLines,
    this.overflow,
    super.key,
  });

  final String text;
  final TextStyle style;
  final Color? glowColor;
  final int? maxLines;
  final TextOverflow? overflow;

  @override
  State<PulseGlowText> createState() => _PulseGlowTextState();
}

class _PulseGlowTextState extends State<PulseGlowText>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _scaleAnimation;
  late Animation<double> _opacityAnimation;
  late Animation<double> _blurAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _scaleAnimation = Tween<double>(begin: 1.0, end: 1.04).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _opacityAnimation = Tween<double>(begin: 0.75, end: 1.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );

    _blurAnimation = Tween<double>(begin: 0.0, end: 12.0).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeInOutSine),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return Transform.scale(
          scale: _scaleAnimation.value,
          alignment: Alignment.centerLeft,
          child: Opacity(
            opacity: _opacityAnimation.value,
            child: Text(
              widget.text,
              maxLines: widget.maxLines,
              overflow: widget.overflow,
              style: widget.style.copyWith(
                shadows: [
                  Shadow(
                    color: (widget.glowColor ??
                            widget.style.color ??
                            Colors.white)
                        .withValues(alpha: 0.6),
                    blurRadius: _blurAnimation.value,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
