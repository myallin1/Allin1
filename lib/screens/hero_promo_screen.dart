import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dashboard_screen.dart' show kPink, kBg, kText, kMuted, kSurface, kPinkDark;

class HeroPromoScreen extends StatelessWidget {
  const HeroPromoScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kBg,
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        leading: const BackButton(color: Color(0xFFFF4FA3)),
        title: Text(
          'Join as a Hero',
          style: GoogleFonts.outfit(
            color: kText,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // User's Uploaded Image
            ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: Image.asset(
                'assets/images/hero_promo_poster.png',
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Container(
                  height: 200,
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: kMuted.withValues(alpha: 0.2)),
                  ),
                  alignment: Alignment.center,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.image_rounded, size: 48, color: kMuted),
                      const SizedBox(height: 8),
                      Text(
                        'Upload your poster image here\n(assets/images/hero_promo_poster.png)',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: kMuted, fontSize: 12),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),

            // Benefits
            Text(
              'Hero Benefits',
              style: GoogleFonts.outfit(
                color: kText,
                fontWeight: FontWeight.w800,
                fontSize: 20,
              ),
            ),
            const SizedBox(height: 16),

            _BenefitPoint(
              icon: Icons.account_balance_wallet_rounded,
              title: '100% வருமானமும் உங்களுக்கே!',
              subtitle: 'உழைப்பவருக்கே முழு வருமானம்.',
            ),
            _BenefitPoint(
              icon: Icons.local_taxi_rounded,
              title: 'Taxi, Auto, Delivery & Transport Services',
              subtitle: 'August 15 முதல் ஈரோட்டிற்கு சுதந்திரம்.',
            ),
            _BenefitPoint(
              icon: Icons.engineering_rounded,
              title: 'Manpower & Other Services',
              subtitle: 'அனைத்து விதமான சேவைகளும்.',
            ),
            
            const SizedBox(height: 40),
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: ElevatedButton(
            // FIX (Aug 18 2026, wiring this screen into the customer
            // drawer): this used to be gated behind
            // `if (await canLaunchUrl(url))` with NO else branch — the
            // same silent no-op already diagnosed and fixed on the APK
            // buttons in dashboard_screen.dart. canLaunchUrl() can
            // return false in an installed-PWA / standalone display
            // mode even for a perfectly valid https link, and when it
            // did, this button did nothing at all: no error, no
            // feedback. On the app's main "become a Hero" call to
            // action that reads as broken and silently costs signups.
            // Now it always attempts the launch and reports a failure.
            onPressed: () async {
              final messenger = ScaffoldMessenger.of(context);
              final url = Uri.parse('https://hero-allin1.web.app/');
              var launched = false;
              try {
                launched =
                    await launchUrl(url, mode: LaunchMode.externalApplication);
              } catch (_) {
                launched = false;
              }
              if (!launched) {
                // NOT const: kPinkDark is a MUTABLE top-level variable
                // (dashboard_screen.dart:76) that gets reassigned to
                // cs.secondary when a dynamic theme is applied, so it can
                // never appear inside a const expression. Marking this
                // SnackBar const is what broke the customer web build
                // ("Invalid constant value").
                messenger.showSnackBar(
                  SnackBar(
                    content: const Text(
                      'Could not open the Hero app. Please visit '
                      'hero-allin1.web.app in your browser.',
                    ),
                    backgroundColor: kPinkDark,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: kPink,
              foregroundColor: Colors.white,
              elevation: 0,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              'Join Now & Download App',
              style: GoogleFonts.outfit(
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BenefitPoint extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;

  const _BenefitPoint({
    required this.icon,
    required this.title,
    required this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: kPink.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Icon(icon, color: kPink, size: 24),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: GoogleFonts.outfit(
                    color: kMuted,
                    fontWeight: FontWeight.w500,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
