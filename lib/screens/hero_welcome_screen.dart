// ================================================================
// HeroWelcomeScreen — one-time celebratory screen shown the instant
// a hero's registration is approved, before landing on the dashboard.
// ================================================================
// NEW (Aug 12 2026 — Nizam: "apdi approval admin kuduthathum onboarding
// animation la irunthu 'our respectable hero welcome to allin1' nu
// screen la kaati hero home page kulla kutitu poguthanu theriyanum"):
// HeroPendingScreen already listens LIVE to heroes/{uid}.approvalStatus
// and auto-navigates the instant admin approves — that part already
// worked. What was missing was this exact screen: previously approval
// jumped straight from the pending tracker into HeroDashboardShell with
// no distinct "you're in!" moment. HeroPendingScreen now routes here
// first; this screen plays a short celebratory animation, then
// auto-continues into HeroDashboardShell on its own — the hero never
// has to tap anything.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/theme_service.dart';
import 'bike_taxi/hero_dashboard_shell.dart';

class HeroWelcomeScreen extends StatefulWidget {
  const HeroWelcomeScreen({super.key});

  @override
  State<HeroWelcomeScreen> createState() => _HeroWelcomeScreenState();
}

class _HeroWelcomeScreenState extends State<HeroWelcomeScreen> {
  Timer? _autoContinueTimer;

  @override
  void initState() {
    super.initState();
    // Auto-advances on its own after the animation has had time to play
    // — matches HeroPendingScreen's "no need to reopen/tap anything"
    // promise. A hero who taps the button below just gets there sooner.
    _autoContinueTimer = Timer(const Duration(milliseconds: 3200), _continue);
  }

  @override
  void dispose() {
    _autoContinueTimer?.cancel();
    super.dispose();
  }

  void _continue() {
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute<void>(builder: (_) => const HeroDashboardShell()),
    );
  }

  @override
  Widget build(BuildContext context) {
    Color primary = const Color(0xFFFF4FA3);
    Color secondary = const Color(0xFFBE2A7A);
    Color bg = const Color(0xFFFFF6FA);
    Color text = const Color(0xFF201A22);
    Color muted = const Color(0xFF8C7A88);
    try {
      final ts = Provider.of<ThemeService>(context);
      final cs = ts.currentTheme.colorScheme;
      primary = cs.primary;
      secondary = cs.secondary;
      bg = ts.currentTheme.scaffoldBackgroundColor;
      text = cs.onSurface;
      muted = cs.onSurface.withValues(alpha: 0.6);
    } catch (_) {
      // ThemeService not found — fall back to the defaults above,
      // same defensive pattern hero_pending_screen.dart already uses.
    }

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(28),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(colors: [primary, secondary]),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: primary.withValues(alpha: 0.4), blurRadius: 36, spreadRadius: 4),
                    ],
                  ),
                  child: const Icon(Icons.emoji_events_rounded, color: Colors.white, size: 60),
                )
                    .animate()
                    .scale(
                      begin: const Offset(0.4, 0.4),
                      end: const Offset(1, 1),
                      duration: 550.ms,
                      curve: Curves.elasticOut,
                    )
                    .then()
                    .shimmer(duration: 1200.ms, color: Colors.white.withValues(alpha: 0.6)),
                const SizedBox(height: 32),
                Text(
                  'Welcome, Hero! 🎉',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 28, fontWeight: FontWeight.w900, color: text),
                ).animate().fadeIn(delay: 300.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
                const SizedBox(height: 10),
                Text(
                  'Our respectable hero, welcome to Allin1 —\nyou are officially approved and ready to earn!',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 14.5, color: muted, height: 1.5),
                ).animate().fadeIn(delay: 500.ms, duration: 400.ms).slideY(begin: 0.2, end: 0),
                const SizedBox(height: 36),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _continue,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: primary,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      'Go to My Dashboard',
                      style: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w800),
                    ),
                  ),
                ).animate().fadeIn(delay: 900.ms, duration: 400.ms),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
