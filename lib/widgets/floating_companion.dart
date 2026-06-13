import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class FloatingCompanion extends StatefulWidget {
  const FloatingCompanion({
    super.key,
    this.onTap,
  });

  final VoidCallback? onTap;

  @override
  State<FloatingCompanion> createState() => _FloatingCompanionState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<VoidCallback?>.has('onTap', onTap));
  }
}

class _FloatingCompanionState extends State<FloatingCompanion>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 10),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.sizeOf(context);

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value * 2 * math.pi;
        final horizontalFactor = (math.sin(t) + 1) / 2;
        final verticalFactor = (math.cos(t * 0.75) + 1) / 2;
        final left = 14 + (screenSize.width - 84) * horizontalFactor;
        final top = 96 + (screenSize.height - 248) * verticalFactor;

        return Positioned(
          left: left
              .clamp(14.0, math.max(14.0, screenSize.width - 70))
              .toDouble(),
          top: top
              .clamp(96.0, math.max(96.0, screenSize.height - 150))
              .toDouble(),
          child: GestureDetector(
            onTap: widget.onTap,
            child: Container(
              width: 62,
              height: 62,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Color(0xFFFFF2F8),
                    Color(0xFFFFD7EA),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: const Color(0xFFFF90C4).withValues(alpha: 0.72),
                  width: 1.4,
                ),
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFFF4FA3).withValues(alpha: 0.22),
                    blurRadius: 22,
                    spreadRadius: 1.5,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(6),
                child: ClipOval(
                  child: Image.asset(
                    'assets/images/robot_ai.gif',
                    fit: BoxFit.cover,
                    errorBuilder: (context, error, stackTrace) {
                      return DecoratedBox(
                        decoration: const BoxDecoration(
                          shape: BoxShape.circle,
                          gradient: LinearGradient(
                            colors: [
                              Color(0xFF071B4D),
                              Color(0xFFFF4FA3),
                              Color(0xFFFFD166),
                            ],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                        ),
                        child: Center(
                          child: Transform.scale(
                            scale: 0.94 + (math.sin(t * 2) * 0.05),
                            child: const Icon(
                              Icons.smart_toy_rounded,
                              color: Colors.white,
                              size: 34,
                            ),
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
