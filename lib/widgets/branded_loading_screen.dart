// ================================================================
// branded_loading_screen.dart
// The one "please wait" look used everywhere the customer app needs
// to show something while real async work (env/map init, auth check,
// first-launch check) completes.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class BrandedLoadingScreen extends StatefulWidget {
  final String statusText;

  const BrandedLoadingScreen({
    this.statusText = 'made love ❤ with erode',
    super.key,
  });

  @override
  State<BrandedLoadingScreen> createState() => _BrandedLoadingScreenState();
}

class _BrandedLoadingScreenState extends State<BrandedLoadingScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // A slow, pulsing animation that won't drop frames.
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 3500),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Stack(
        children: [
          // Background Smoke Glow Animation (Saffron and Green)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, child) {
              final val = _controller.value;
              return Stack(
                children: [
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(-0.2 + (val * 0.1), -0.1),
                          radius: 0.9 + (val * 0.3),
                          colors: [
                            const Color(0xFFFF9933).withValues(alpha: 0.18), // Saffron
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const [0.1, 1.0],
                        ),
                      ),
                    ),
                  ),
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0.2 - (val * 0.1), 0.1),
                          radius: 0.9 + ((1 - val) * 0.3),
                          colors: [
                            const Color(0xFF138808).withValues(alpha: 0.12), // Green
                            Colors.white.withValues(alpha: 0.0),
                          ],
                          stops: const [0.1, 1.0],
                        ),
                      ),
                    ),
                  ),
                ],
              );
            },
          ),
          // Foreground Content
          SafeArea(
            child: Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    // "App loading" label ABOVE the logo, per explicit
                    // request (Aug 19 2026) — user wants the loading
                    // text visible before/in-front-of the logo image,
                    // not only below the spinner.
                    const Text(
                      'MyAllin1 SuperApp Loading...',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(0xFF8A4E72),
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 14),
                    // New Logo
                    //
                    // WEBP switch (Aug 19 2026): the source PNG was
                    // 832x1024 / ~625 KB. Re-encoded to WEBP at the same
                    // resolution (no quality loss visible at 160px
                    // display size) drops it to ~41 KB — a ~15x
                    // reduction in bytes that must be fetched/decoded
                    // on the very first screen of the app.
                    //
                    // cacheWidth kept (added earlier same day): the
                    // source is still 832x1024 and was being decoded at
                    // full resolution to draw a 160px box — roughly
                    // 3.4 MB of bitmap (832 x 1024 x 4 bytes) held in
                    // memory for something 160px wide.
                    //
                    // This is the FIRST screen of the app, on the
                    // ₹8,000 phones most of Erode uses, at the exact
                    // moment Firebase and Hive are also initialising.
                    // Decoding at 480px (3x the display size, enough
                    // for any density) drops that to ~0.9 MB and takes
                    // the decode itself off the critical boot path.
                    // Same trap documented in ai_bot_avatar.dart.
                    Image.asset(
                      'assets/images/myallin1_splash_logo.webp',
                      width: 160,
                      height: 160,
                      cacheWidth: 480,
                      fit: BoxFit.contain,
                    ),
                    const SizedBox(height: 32),
                    // Loading Spinner
                    const SizedBox(
                      width: 32,
                      height: 32,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF4FA3), // Keeping brand pink
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                    // Status Text
                    Text(
                      widget.statusText,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Color(0xFF8A4E72),
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('statusText', widget.statusText));
  }
}
