// ================================================================
// FoodHubScreen — Landing page shown when a customer taps "Food
// Delivery" from the home dashboard.
// ================================================================
// Per Nizam's updated plan: top tile is "Custom Order" (free-text
// order form, unchanged). Below it is a grid of partner-shop tiles
// (Subway, Domino's, KFC, Taj Hotel, A2B, Jameen Restaurant, ...) —
// each shop already has its own online ordering site, so tapping a
// shop opens PartnerShopOrderScreen, which links out to that site for
// the actual order + payment, then hands the customer back into our
// existing CustomFoodOrderScreen for pickup + delivery by an Allin1
// hero. New shops only need to be added to kPartnerShops.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';
import 'custom_food_order_screen.dart';
import 'partner_shop_order_screen.dart';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kPink = Color(0xFFFF4FA3);
const Color _kPinkDark = Color(0xFFBE2A7A);

class FoodHubScreen extends StatelessWidget {
  const FoodHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _kText),
        title: Text('🍛 ${t('food_delivery_title')}', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(t('food_hub_prompt'), style: GoogleFonts.outfit(color: _kMuted, fontSize: 13)),
          const SizedBox(height: 16),
          _HubTile(
            key: const Key('food_hub_custom_order_tile'),
            label: t('custom_order_title'),
            subtitle: t('food_hub_custom_subtitle'),
            icon: Icons.restaurant_menu_rounded,
            gradient: const [_kPink, _kPinkDark],
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomFoodOrderScreen()),
            ),
          ),
          const SizedBox(height: 20),
          Text(t('food_hub_shops_heading'), style: GoogleFonts.outfit(color: _kText, fontSize: 14.5, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text(t('food_hub_shops_subheading'), style: GoogleFonts.outfit(color: _kMuted, fontSize: 12)),
          const SizedBox(height: 14),
          GridView.count(
            key: const Key('food_hub_partner_shops_grid'),
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 14,
            mainAxisSpacing: 14,
            childAspectRatio: 1.35,
            children: kPartnerShops
                .map(
                  (shop) => _HubTile(
                    label: shop.name,
                    subtitle: shop.subtitle,
                    icon: Icons.storefront_rounded,
                    gradient: shop.gradient,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => PartnerShopOrderScreen(shop: shop)),
                    ),
                  ),
                )
                .toList(),
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
            Text(label, style: GoogleFonts.outfit(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w900), maxLines: 1, overflow: TextOverflow.ellipsis),
            const SizedBox(height: 4),
            Text(subtitle, style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.85), fontSize: 11), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(IterableProperty<Color>('gradient', gradient));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
