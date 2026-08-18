// ================================================================
// SellerElectronicsDashboardScreen
//
// DECISION (confirmed): Electronics stays repair/service-booking only
// — no product-catalog/retail listing. Customers book a repair via NJ
// Tech Store -> electronics_service service_requests (nj_tech_store_screen.dart),
// which — same as Grocery — is not tied to a specific registered
// seller; any available hero can pick up the job. So there is
// deliberately no catalog UI to build here.
// ================================================================
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_models.dart';
import '../services/app_minimizer_service.dart';
import '../services/food_seller_service.dart';

const Color _bg = Color(0xFF08080F);
const Color _card = Color(0xFF141420);
const Color _teal = Color(0xFF11998E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

class SellerElectronicsDashboardScreen extends StatefulWidget {
  const SellerElectronicsDashboardScreen({super.key});

  @override
  State<SellerElectronicsDashboardScreen> createState() =>
      _SellerElectronicsDashboardScreenState();
}

class _SellerElectronicsDashboardScreenState
    extends State<SellerElectronicsDashboardScreen> {
  final FoodSellerService _service = FoodSellerService();
  SellerModel? _seller;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final seller = await _service.getSeller(uid);
    if (mounted) {
      setState(() {
        _seller = seller;
        _loading = false;
      });
    }
  }

  // NEW (Aug 18 2026 — Turbo App navigation audit): same fix as
  // seller_grocery_dashboard_screen.dart — this screen becomes a literal
  // app root for electronics sellers via seller_dashboard_screen.dart's
  // Navigator.pushReplacement(), and had zero PopScope of its own.
  void _handleBackPress() {
    if (kIsWeb) {
      if (AppMinimizer.consumeWebHintOnce()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Press your device's Home button to minimize"),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    unawaited(AppMinimizer.moveToBackground());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _teal)),
      );
    }
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        title: Text(
          _seller?.name ?? 'Electronics Shop',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: _muted),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(color: _border),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('💻', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    "You're registered — no catalog setup needed",
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Electronics on Allin1 works as repair/service bookings — '
                    'a customer requests a repair or install through NJ Tech '
                    "Store, and any available hero handles it. There's no "
                    'product catalog to manage on your end — your '
                    'registration just helps us list your shop as a nearby '
                    'option.',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_seller != null) ...[
              _infoRow(Icons.store, 'Shop Name', _seller!.name),
              _infoRow(Icons.phone, 'Phone', _seller!.phone),
              _infoRow(Icons.location_on, 'Address', _seller!.address),
            ],
          ],
        ),
      ),
    );
  }

  Widget _infoRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _teal, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11),),
                Text(value.isEmpty ? '—' : value,
                    style: GoogleFonts.outfit(color: _text, fontSize: 14),),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
