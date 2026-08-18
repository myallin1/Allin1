// ================================================================
// SellerGroceryDashboardScreen
//
// DECISION (confirmed): Grocery stays broadcast-only — no per-seller
// digital catalog. Customers place a grocery order via the existing
// "Order from ANY Shop" text/photo broadcast flow (grocery_order_screen.dart
// -> service_requests, requestType 'grocery_order'), which is not tied
// to a specific registered seller at all — any online hero can fulfill
// it. So there is deliberately no menu/inventory UI to build here; this
// screen just confirms the seller's registration and explains why.
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

class SellerGroceryDashboardScreen extends StatefulWidget {
  const SellerGroceryDashboardScreen({super.key});

  @override
  State<SellerGroceryDashboardScreen> createState() =>
      _SellerGroceryDashboardScreenState();
}

class _SellerGroceryDashboardScreenState
    extends State<SellerGroceryDashboardScreen> {
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

  // NEW (Aug 18 2026 — Turbo App navigation audit, per Nizam + Gemini
  // cross-check): this screen becomes a grocery seller's literal APP
  // ROOT — seller_dashboard_screen.dart's own initState detects
  // businessVertical == 'grocery' and Navigator.pushReplacement()s
  // straight here, replacing the app's own root route. With zero
  // PopScope of its own, a back-press here had nothing to fall back
  // on and hit Flutter's default un-intercepted last-route behaviour —
  // a silent, instant SystemNavigator.pop() (real app close), never a
  // dialog, never a chance to minimize instead. Every grocery seller
  // hit this on literally any back-press from their home screen. Same
  // AppMinimizer pattern as the 4 main dashboard roots; no tabs here to
  // reset first (this screen has none), so it goes straight to
  // minimize/web-hint.
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
          _seller?.name ?? 'Grocery Store',
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
                  const Text('🛒', style: TextStyle(fontSize: 40)),
                  const SizedBox(height: 12),
                  Text(
                    "You're registered — no menu setup needed",
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 18,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Grocery orders on Allin1 work as a broadcast request — '
                    'a customer types or photographs their shopping list, and '
                    'any available hero picks it up and shops for them. '
                    "There's no digital catalog to manage on your end — your "
                    'registration just helps us list your store as a nearby '
                    'option.',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_seller != null) ...[
              _infoRow(Icons.store, 'Store Name', _seller!.name),
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
