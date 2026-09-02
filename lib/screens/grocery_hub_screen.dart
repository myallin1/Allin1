// ================================================================
// grocery_hub_screen.dart — landing page for the "Grocery" dashboard
// tile. Mirrors food_hub_screen.dart's own "top tile is free-form,
// grid below is real stores" shape.
// ================================================================
// Sep 2026 — universal catalog build. Purely additive: the existing
// free-text broadcast flow (grocery_order_screen.dart) is unchanged
// and still the first tile here — "Browse Grocery Stores" is a NEW
// second option for stores that have set up a real digital catalog,
// not a replacement.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'grocery_order_screen.dart';
import 'grocery_store_list_screen.dart';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kTeal = Color(0xFF11998E);
const Color _kTealDark = Color(0xFF0D7A6E);
const Color _kGold = Color(0xFFC79200);

class GroceryHubScreen extends StatelessWidget {
  const GroceryHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('🛒 Grocery', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text('How would you like to shop?', style: GoogleFonts.outfit(color: _kMuted, fontSize: 13)),
          const SizedBox(height: 16),
          _HubTile(
            key: const Key('grocery_hub_browse_stores_tile'),
            label: 'Browse Grocery Stores',
            subtitle: 'Pick items from a store\'s live catalog with prices & stock',
            icon: Icons.storefront_rounded,
            gradient: const [_kTeal, _kTealDark],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const GroceryStoreListScreen()),
            ),
          ),
          const SizedBox(height: 14),
          _HubTile(
            key: const Key('grocery_hub_quick_list_tile'),
            label: 'Quick List (Free Text)',
            subtitle: 'Type or photograph your shopping list — any hero shops for you',
            icon: Icons.checklist_rounded,
            gradient: const [_kGold, Color(0xFFA67200)],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(builder: (_) => const GroceryOrderScreen()),
            ),
          ),
        ],
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
    super.key,
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
        constraints: const BoxConstraints(minHeight: 110),
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
          borderRadius: BorderRadius.circular(20),
          boxShadow: [BoxShadow(color: gradient.first.withValues(alpha: 0.28), blurRadius: 16, offset: const Offset(0, 8))],
        ),
        child: Row(
          children: [
            Icon(icon, color: Colors.white, size: 32),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
                  const SizedBox(height: 4),
                  Text(subtitle, style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 11.5)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
