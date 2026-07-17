import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class HeroPremiumLoader extends StatefulWidget {
  const HeroPremiumLoader({
    super.key,
    this.title = 'Preparing Hero Dashboard',
    this.subtitle = 'Syncing your ride radar and premium Hero workspace',
    this.compact = false,
    this.icon = Icons.two_wheeler_rounded,
  });

  final String title;
  final String subtitle;
  final bool compact;
  final IconData icon;

  @override
  State<HeroPremiumLoader> createState() => _HeroPremiumLoaderState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('title', title))
      ..add(StringProperty('subtitle', subtitle))
      ..add(DiagnosticsProperty<bool>('compact', compact))
      ..add(DiagnosticsProperty<IconData>('icon', icon));
  }
}

class _HeroPremiumLoaderState extends State<HeroPremiumLoader>
    with SingleTickerProviderStateMixin {
  late final AnimationController _animationController;
  late final Animation<double> _pulseScale;
  late final Animation<double> _pulseGlow;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2800),
    )..repeat(reverse: true);
    _pulseScale = Tween<double>(begin: 0.94, end: 1.06).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
    _pulseGlow = Tween<double>(begin: 0.32, end: 0.82).animate(
      CurvedAnimation(parent: _animationController, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _animationController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bool compact = widget.compact;
    final Widget loaderCard = AnimatedBuilder(
      animation: _animationController,
      builder: (context, child) {
        final double streakX = -1.25 + (_animationController.value * 2.5);
        return ClipRRect(
          borderRadius: BorderRadius.circular(compact ? 28 : 36),
          child: Container(
            constraints: BoxConstraints(
              minHeight: compact ? 220 : 420,
            ),
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[
                  Color(0xFFFF4FA3),
                  Color(0xFFFF87C2),
                  Color(0xFFFFD3E7),
                  Color(0xFFFFFFFF),
                ],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              boxShadow: <BoxShadow>[
                BoxShadow(
                  color: const Color(0x66FF4FA3).withValues(
                    alpha: 0.30 + (_pulseGlow.value * 0.24),
                  ),
                  blurRadius: compact ? 24 : 34,
                  spreadRadius: compact ? 2 : 4,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Stack(
              children: <Widget>[
                Positioned.fill(
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: <Color>[
                          Colors.white.withValues(alpha: 0.22),
                          Colors.transparent,
                          Colors.white.withValues(alpha: 0.12),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                    ),
                  ),
                ),
                Align(
                  alignment: Alignment(streakX, -0.15),
                  child: Transform.rotate(
                    angle: -math.pi / 7,
                    child: Container(
                      width: compact ? 52 : 72,
                      height: compact ? 220 : 320,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: <Color>[
                            Colors.white.withValues(alpha: 0),
                            Colors.white.withValues(alpha: 0.50),
                            Colors.white.withValues(alpha: 0),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 20 : 28,
                    vertical: compact ? 22 : 34,
                  ),
                  child: Column(
                    mainAxisSize: compact ? MainAxisSize.min : MainAxisSize.max,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: <Widget>[
                      Transform.scale(
                        scale: _pulseScale.value,
                        child: Container(
                          width: compact ? 82 : 118,
                          height: compact ? 82 : 118,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: <Color>[
                                Color(0xFFFFFFFF),
                                Color(0xFFFFE4F2),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.80),
                              width: 2,
                            ),
                            boxShadow: <BoxShadow>[
                              BoxShadow(
                                color: const Color(0x66FF4FA3).withValues(
                                  alpha: 0.28 + (_pulseGlow.value * 0.30),
                                ),
                                blurRadius: compact ? 18 : 28,
                                spreadRadius: compact ? 4 : 8,
                              ),
                            ],
                          ),
                          child: Icon(
                            widget.icon,
                            color: const Color(0xFFFF4FA3),
                            size: compact ? 38 : 54,
                          ),
                        ),
                      ),
                      SizedBox(height: compact ? 18 : 26),
                      Text(
                        widget.title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: compact ? 17 : 24,
                          fontWeight: FontWeight.w800,
                          color: const Color(0xFF5A1036),
                          letterSpacing: 0.2,
                        ),
                      ),
                      SizedBox(height: compact ? 8 : 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 360),
                        child: Text(
                          widget.subtitle,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                            fontSize: compact ? 12 : 14,
                            height: 1.45,
                            fontWeight: FontWeight.w600,
                            color: const Color(0xFF7A214B),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );

    if (compact) {
      return Padding(
        padding: const EdgeInsets.all(24),
        child: Center(child: loaderCard),
      );
    }

    return Material(
      color: Colors.transparent,
      child: DecoratedBox(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            colors: <Color>[
              Color(0xFFFF4FA3),
              Color(0xFFFF7BBB),
              Color(0xFFFFD9EA),
              Color(0xFFFFFFFF),
            ],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
        ),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 520),
                child: loaderCard,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
