// ================================================================
// SellerVerticalPickerScreen — first screen a brand-new seller sees.
//
// Added because "seller" used to mean ONE thing: a hotel/restaurant.
// SellerModel/FoodSellerService/seller_onboarding_screen.dart are all
// shaped entirely around that (menu items, food sub-categories, veg/
// non-veg type) — there was no way for a seller to be anything else.
// Nizam wants real Hotel/Grocery/Electronics seller verticals, each
// with its own onboarding and dashboard. This screen is the fork
// point: pick a vertical here, and everything downstream (onboarding
// form, dashboard) is vertical-specific from that point on.
//
// Hotel keeps using the existing, fully-built, already-tested
// SellerOnboardingScreen + SellerDashboardScreen completely unchanged.
// Grocery and Electronics are NEW and intentionally minimal right now
// — see the onboarding/dashboard screens for those verticals for why.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'seller_electronics_onboarding_screen.dart';
import 'seller_grocery_onboarding_screen.dart';
import 'seller_mobile_onboarding_screen.dart';
import 'seller_onboarding_screen.dart';

const Color _bg = Color(0xFFF7FAF8);
const Color _card = Color(0xFFFFFFFF);
const Color _card2 = Color(0xFFF1F6F3);
const Color _teal = Color(0xFF11998E);
const Color _tealLight = Color(0xFF38EF7D);
const Color _text = Color(0xFF1A1A1A);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0x1A11998E);

class SellerVerticalPickerScreen extends StatelessWidget {
  const SellerVerticalPickerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const SizedBox(height: 20),
              Text(
                'Welcome to Allin1 Partner!',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 22,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'What kind of business are you registering?',
                style: GoogleFonts.outfit(color: _muted, fontSize: 14),
              ),
              const SizedBox(height: 28),
              _VerticalTile(
                emoji: '🍽️',
                title: 'Hotel / Restaurant',
                subtitle: 'Menu items, food orders, veg & non-veg',
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SellerOnboardingScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _VerticalTile(
                emoji: '🛒',
                title: 'Grocery Store',
                subtitle: 'Coming soon — basic profile only for now',
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SellerGroceryOnboardingScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              // NEW (Aug 18 2026 — Mobile Hub). Unlike Grocery and
              // Electronics above, this vertical is fully built: a
              // mobile shop gets a real stock catalog (list new/used
              // phones with prices), because customers browse specific
              // phones rather than sending a broadcast request.
              _VerticalTile(
                emoji: '📱',
                title: 'Mobile Shop',
                subtitle: 'List new & used phones with your own prices',
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SellerMobileOnboardingScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              _VerticalTile(
                emoji: '💻',
                title: 'Electronics Shop',
                subtitle: 'Coming soon — basic profile only for now',
                onTap: () => Navigator.pushReplacement(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const SellerElectronicsOnboardingScreen(),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _VerticalTile extends StatelessWidget {
  final String emoji;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  const _VerticalTile({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Container(
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _card2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(emoji, style: const TextStyle(fontSize: 24)),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios_rounded,
                color: _tealLight, size: 16,),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('emoji', emoji));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
