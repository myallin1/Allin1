// ================================================================
// FoodHubScreen — Landing page shown when a customer taps "Food
// Delivery" from the home dashboard.
// ================================================================
// Per Nizam's request: top-left tile is "Custom Order" (the existing
// free-text order form, unchanged), and a second tile "Subway" opens
// a dedicated in-app Subway menu (subway_menu_screen.dart) — the
// whole ordering flow stays inside the app, never links out.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'custom_food_order_screen.dart';
import 'subway_menu_screen.dart';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kPink = Color(0xFFFF4FA3);
const Color _kPinkDark = Color(0xFFBE2A7A);
const Color _kSubwayGreen = Color(0xFF008938);

class FoodHubScreen extends StatelessWidget {
  const FoodHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('🍛 Food Delivery', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What would you like to order?', style: GoogleFonts.outfit(color: _kMuted, fontSize: 13)),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: _HubTile(
                    label: 'Custom Order',
                    subtitle: 'Order from any shop in Erode',
                    icon: Icons.restaurant_menu_rounded,
                    gradient: const [_kPink, _kPinkDark],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const CustomFoodOrderScreen()),
                    ),
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: _HubTile(
                    label: 'Subway',
                    subtitle: 'Order your favourite sub',
                    icon: Icons.lunch_dining_rounded,
                    gradient: const [_kSubwayGreen, Color(0xFF00612A)],
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => const SubwayMenuScreen()),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _HubTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final IconData icon;
  final List<Color> gradient;
  final VoidCallback onTap;

  const _HubTile({
    required this.label,
    required this.subtitle,
    required this.icon,
    required this.gradient,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        constraints: const BoxConstraints(minHeight: 150),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
              child: Icon(icon, color: gradient.last, size: 22),
            ),
            const Spacer(),
            Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w900)),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5)),
          ],
        ),
      ),
    );
  }
}
