// ================================================================
// PartnerShopOrderScreen — external-catalog partner ordering flow
// ================================================================
// Nizam's updated plan (replaces the earlier in-app Subway cart):
// Subway (and other Erode shops with their own online ordering site —
// Domino's, KFC, Taj Hotel, A2B, Jameen Restaurant, etc.) already have
// a digital menu/checkout of their own. So instead of rebuilding their
// catalog inside Allin1, we just link out to their ordering site for
// the customer to browse + pay there. Once they've placed that order,
// they come back here and tap "I've Ordered — Book Pickup & Delivery",
// which reuses the existing, already-working CustomFoodOrderScreen
// pipeline (writes to service_requests, gets picked up by a nearby
// bike hero) — with the shop name pre-filled so the customer only has
// to describe what they ordered + confirm their delivery address.
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import 'custom_food_order_screen.dart';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);

class PartnerShop {
  final String name;
  final String subtitle;
  final String logoText; // short brand initials/text shown on the badge
  final String orderUrl;
  final List<Color> gradient;
  final String? imageAsset; // Custom image asset for the button
  final bool embedded; // Whether to open in-app via embedded WebView

  const PartnerShop({
    required this.name,
    required this.subtitle,
    required this.logoText,
    required this.orderUrl,
    required this.gradient,
    this.imageAsset,
    this.embedded = false,
  });
}

// Central registry of partner shops with their own online ordering
// site. Adding a new shop here is enough to show it on the food page —
// no other code changes needed.
const List<PartnerShop> kPartnerShops = [
  PartnerShop(
    name: 'Subway',
    subtitle: 'Order your favourite sub',
    logoText: 'SUBWAY',
    orderUrl: 'https://eversub.dotpe.in/store/939/1/999',
    gradient: [Color(0xFF008938), Color(0xFF00612A)],
    imageAsset: 'assets/images/subway_logo.png',
    embedded: true,
  ),
  PartnerShop(
    name: "Domino's Pizza",
    subtitle: 'Pizzas, sides & more',
    logoText: "DOMINO'S",
    orderUrl: 'https://www.dominos.co.in',
    gradient: [Color(0xFF0F5AA6), Color(0xFF0A3D73)],
    imageAsset: 'assets/images/dominos_logo.png',
    embedded: true,
  ),
  PartnerShop(
    name: 'KFC',
    subtitle: "Finger lickin' good",
    logoText: 'KFC',
    orderUrl: 'https://online.kfc.co.in',
    gradient: [Color(0xFFC8102E), Color(0xFF8E0B20)],
    imageAsset: 'assets/images/kfc_logo.png',
    embedded: true,
  ),
  PartnerShop(
    name: 'Taj Hotel',
    subtitle: "Erode's premium dining",
    logoText: 'TAJ',
    orderUrl: 'https://www.tajhotels.com',
    gradient: [Color(0xFF8A6D3B), Color(0xFF5C4626)],
    // FIX (Nizam: "Hotels la konjam hotel embedded ah open aagala,
    // veliya browser la open aaguthu") — this entry had no `embedded:
    // true`, so it defaulted to false and routed through
    // PartnerShopOrderScreen's external launchUrl() instead of the
    // in-app DmartEmbeddedView/EmbeddedShopScreen every other partner
    // shop already uses. Same ordinary https:// site as the rest, so
    // there's no technical reason to special-case it.
    embedded: true,
  ),
  PartnerShop(
    name: 'A2B',
    subtitle: 'Adyar Ananda Bhavan',
    logoText: 'A2B',
    orderUrl: 'https://www.aabsweets.com/order/',
    gradient: [Color(0xFFE0A800), Color(0xFFA87900)],
    imageAsset: 'assets/images/a2b_logo.png',
    embedded: true,
  ),
  PartnerShop(
    name: 'Jameen Restaurant',
    subtitle: 'Local Erode favourite',
    logoText: 'JAMEEN',
    orderUrl: 'https://www.zomato.com',
    gradient: [Color(0xFF6C63FF), Color(0xFF3D3494)],
    // Same fix as Taj Hotel above — was missing `embedded: true`.
    embedded: true,
  ),
];

class PartnerShopOrderScreen extends StatelessWidget {
  final PartnerShop shop;
  const PartnerShopOrderScreen({required this.shop, super.key});

  Future<void> _openShopSite(BuildContext context) async {
    final uri = Uri.parse(shop.orderUrl);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && context.mounted) _showLinkFailedDialog(context);
    } catch (_) {
      if (context.mounted) _showLinkFailedDialog(context);
    }
  }

  void _showLinkFailedDialog(BuildContext context) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Could not open link'),
        content: SelectableText(shop.orderUrl),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
        ],
      ),
    );
  }

  // NEW (Aug 19 2026 — WhatsApp deep link share): 'pshop' route matches
  // dashboard_screen.dart's _parseDeepLinkPath() and main_customer.dart's
  // '/partner_shop_detail' onGenerateRoute case, which looks the shop up
  // by name in the static kPartnerShops list — so shop.name must match
  // exactly (Uri.encodeComponent handles spaces/special chars in transit).
  void _shareShop() {
    final deepLink =
        'https://my-allin1.web.app/pshop/${Uri.encodeComponent(shop.name)}';
    SharePlus.instance.share(
      ShareParams(
        text: 'Order from ${shop.name} on MyAllin1 Erode! 🍽️\n$deepLink',
      ),
    );
  }

  void _goToDeliveryForm(BuildContext context) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomFoodOrderScreen(initialShop: shop.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: shop.gradient.first,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(shop.name, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
        actions: [
          IconButton(
            icon: const Icon(Icons.ios_share_rounded, color: Colors.white),
            onPressed: _shareShop,
          ),
        ],
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(vertical: 36),
                decoration: BoxDecoration(
                  gradient: LinearGradient(colors: shop.gradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Center(
                  child: Text(
                    shop.logoText,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w900, letterSpacing: 1),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text('How this works', style: GoogleFonts.outfit(color: _kText, fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 12),
              _stepTile(1, "Tap below to open ${shop.name}'s own ordering site and place your order there (pay directly to them)."),
              _stepTile(2, 'Once your order is confirmed, come back here and tell us your delivery address.'),
              _stepTile(3, 'One of our nearby Allin1 heroes will pick it up from ${shop.name} and deliver it to you.'),
              const Spacer(),
              ElevatedButton(
                onPressed: () => _openShopSite(context),
                style: ElevatedButton.styleFrom(
                  backgroundColor: shop.gradient.first,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: Text('🔗  Open ${shop.name} to Order', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15)),
              ),
              const SizedBox(height: 12),
              OutlinedButton(
                onPressed: () => _goToDeliveryForm(context),
                style: OutlinedButton.styleFrom(
                  foregroundColor: shop.gradient.first,
                  side: BorderSide(color: shop.gradient.first, width: 1.4),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                ),
                child: const Text("✅  I've Ordered — Book Pickup & Delivery", style: TextStyle(fontWeight: FontWeight.w800, fontSize: 14.5)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _stepTile(int num, String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 24,
            height: 24,
            margin: const EdgeInsets.only(top: 1),
            decoration: BoxDecoration(color: shop.gradient.first, shape: BoxShape.circle),
            child: Center(child: Text('$num', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12))),
          ),
          const SizedBox(width: 10),
          Expanded(child: Text(text, style: GoogleFonts.outfit(color: _kMuted, fontSize: 13, height: 1.4))),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<PartnerShop>('shop', shop));
  }
}
