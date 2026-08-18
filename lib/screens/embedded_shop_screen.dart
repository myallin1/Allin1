import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../widgets/dmart_embedded_view_web.dart'
    if (dart.library.io) '../widgets/dmart_embedded_view_native.dart';
import 'custom_food_order_screen.dart';
import 'partner_shop_order_screen.dart'; // To get the PartnerShop model

const Color _kBg = Color(0xFFFFFFFF);

class EmbeddedShopScreen extends StatefulWidget {
  final PartnerShop shop;
  const EmbeddedShopScreen({required this.shop, super.key});

  @override
  State<EmbeddedShopScreen> createState() => _EmbeddedShopScreenState();
}

class _EmbeddedShopScreenState extends State<EmbeddedShopScreen> {
  Future<void> _openInBrowser(BuildContext context) async {
    final uri = Uri.parse(widget.shop.orderUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not open ${widget.shop.name}. Check your connection.')),
      );
    }
  }

  void _goToDeliveryForm() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomFoodOrderScreen(initialShop: widget.shop.name),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: widget.shop.gradient.first,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          widget.shop.name,
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white, size: 20),
            tooltip: 'Open in browser',
            onPressed: () => _openInBrowser(context),
          ),
        ],
      ),
      // Reuse the same WebView/IFrame implementation used by DMart
      body: DmartEmbeddedView(url: widget.shop.orderUrl),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToDeliveryForm,
        backgroundColor: widget.shop.gradient.first,
        icon: const Icon(Icons.delivery_dining_rounded, color: Colors.white),
        label: Text(
          "I've Ordered - Book Delivery",
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ),
    );
  }
}
