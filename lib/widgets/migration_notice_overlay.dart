// ================================================================
// MigrationGate / MigrationNoticeOverlay — "Zero-Budget Escape Hatch"
// ================================================================
// NEW (Aug 12 2026 — CTO mandate): wraps the `child` each of the 4
// apps' MaterialApp `builder:` already passes through (same slot the
// customer app's GlobalGuruFab already lives in — see main_customer.dart)
// and, the instant MigrationGateService reports a non-empty
// migrationUrl, throws the real app away entirely and shows this
// full-screen notice instead. Deliberately NOT an overlay stacked on
// top of the real app (a Stack with the notice as a top layer) — the
// CTO's own wording is "lock the UI", and a customer should not be able
// to see/interact with anything underneath once this fires.
//
// No nested MaterialApp here on purpose: `builder:` already runs INSIDE
// the enclosing MaterialApp's Localizations/Directionality/MediaQuery/
// Theme context, so a plain Scaffold is enough and avoids the Navigator/
// Overlay conflicts a second nested MaterialApp can cause.
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/migration_gate_service.dart';

class MigrationGate extends StatelessWidget {
  const MigrationGate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: MigrationGateService.instance,
      builder: (context, _) {
        final url = MigrationGateService.instance.migrationUrl;
        if (url == null || url.isEmpty) return child;
        return _MigrationNoticeScreen(url: url);
      },
    );
  }
}

class _MigrationNoticeScreen extends StatelessWidget {
  const _MigrationNoticeScreen({required this.url});

  final String url;

  Future<void> _openNewApp(BuildContext context) async {
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    try {
      // Web: navigate the SAME tab away permanently ('_self') — this is
      // the actual "redirect", not a new-tab popup a customer could
      // accidentally leave open alongside the dead old app. Native: the
      // app itself can't navigate to a URL in-place (it's a compiled
      // binary, not a page), so hand off to the system browser instead.
      await launchUrl(
        uri,
        mode: kIsWeb ? LaunchMode.platformDefault : LaunchMode.externalApplication,
        webOnlyWindowName: kIsWeb ? '_self' : null,
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not open the link automatically. Please visit: $url')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A1A),
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 84,
                  height: 84,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(24),
                    boxShadow: const [
                      BoxShadow(color: Color(0x66FF4FA3), blurRadius: 30, offset: Offset(0, 12)),
                    ],
                  ),
                  child: const Icon(Icons.rocket_launch_rounded, color: Colors.white, size: 40),
                ),
                const SizedBox(height: 26),
                const Text(
                  "We've upgraded our systems!",
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 10),
                const Text(
                  'For a faster experience, please continue on our new app.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.45),
                ),
                const SizedBox(height: 30),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: () => _openNewApp(context),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF4FA3),
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: const Text(
                      'Continue to New App',
                      style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 15),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  url,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white38, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
