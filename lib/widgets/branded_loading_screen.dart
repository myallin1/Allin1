// ================================================================
// branded_loading_screen.dart
// The one "please wait" look used everywhere the customer app needs
// to show something while real async work (env/map init, auth check,
// first-launch check) completes. Previously there were 3 different
// loading designs shown back-to-back on cold start (web CSS splash,
// SplashSetupScreen's pink screen, _CustomerHomeGate's white "made
// love with erode" screen) — this makes it look like ONE continuous
// screen instead of several different ones flashing by in sequence.
// ================================================================
import 'package:flutter/material.dart';

class BrandedLoadingScreen extends StatelessWidget {
  final String statusText;

  const BrandedLoadingScreen({
    this.statusText = 'made love ❤ with erode',
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 94,
                  height: 94,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [
                      BoxShadow(
                        color: Color(0x24FF4FA3),
                        blurRadius: 24,
                        offset: Offset(0, 14),
                      ),
                    ],
                  ),
                  child: const Center(
                    child: SizedBox(
                      width: 34,
                      height: 34,
                      child: CircularProgressIndicator(
                        strokeWidth: 3.2,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          Colors.white,
                        ),
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                const Text(
                  "That'll Bapx NJ Tech",
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: Color(0xFF4A1236),
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 10),
                Text(
                  statusText,
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
    );
  }
}
