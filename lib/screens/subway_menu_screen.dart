// ================================================================
// SubwayMenuScreen — In-App Subway Ordering
// ================================================================
// Per Nizam's request: Erode Subway shared their QR/menu so customers
// can order directly through Allin1 instead of a third-party link —
// this entire flow stays inside the app (PWA or native), same as
// every other food order. Reuses CustomFoodOrderScreen's already-
// working order pipeline (writes to service_requests, dispatches to a
// hero) by pre-filling the shop name and a summary of selected items;
// the customer still confirms/edits their delivery address and name
// on that screen before submitting.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'custom_food_order_screen.dart';

const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kSubwayGreen = Color(0xFF008938);
const Color _kSubwayYellow = Color(0xFFFFC600);

class _SubwayItem {
  final String name;
  final String description;
  final double price;
  const _SubwayItem(this.name, this.description, this.price);
}

const List<_SubwayItem> _subs = [
  _SubwayItem('Veggie Delite', 'Fresh veggies loaded on your choice of bread', 149),
  _SubwayItem('Paneer Tikka', 'Grilled paneer tikka with veggies', 189),
  _SubwayItem('Chicken Teriyaki', 'Grilled chicken in teriyaki sauce', 219),
  _SubwayItem('Chicken Tikka', 'Spicy chicken tikka with veggies', 209),
  _SubwayItem('Egg Mayo', 'Boiled egg with mayo and fresh veggies', 169),
];

const List<_SubwayItem> _sidesAndDrinks = [
  _SubwayItem('Cookies (2 pc)', 'Freshly baked Subway cookies', 79),
  _SubwayItem('Chips', 'Crunchy potato chips', 49),
  _SubwayItem('Coke (regular)', 'Chilled soft drink', 60),
];

class SubwayMenuScreen extends StatefulWidget {
  const SubwayMenuScreen({super.key});

  @override
  State<SubwayMenuScreen> createState() => _SubwayMenuScreenState();
}

class _SubwayMenuScreenState extends State<SubwayMenuScreen> {
  final Map<String, int> _cart = {};

  int get _cartCount => _cart.values.fold(0, (a, b) => a + b);
  double get _cartTotal {
    double total = 0;
    for (final entry in _cart.entries) {
      final item = [..._subs, ..._sidesAndDrinks].firstWhere((i) => i.name == entry.key);
      total += item.price * entry.value;
    }
    return total;
  }

  void _add(String name) => setState(() => _cart[name] = (_cart[name] ?? 0) + 1);
  void _remove(String name) {
    setState(() {
      final current = _cart[name] ?? 0;
      if (current <= 1) {
        _cart.remove(name);
      } else {
        _cart[name] = current - 1;
      }
    });
  }

  void _goToOrderForm() {
    if (_cart.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Add at least one item to continue')),
      );
      return;
    }
    final summary = _cart.entries.map((e) => '${e.value} x ${e.key}').join(', ');
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CustomFoodOrderScreen(
          initialShop: 'Subway (Erode)',
          initialItems: summary,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kSubwayGreen,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text('Subway', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: Column(
        children: [
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
              children: [
                _sectionHeader('Subs'),
                const SizedBox(height: 8),
                ..._subs.map(_buildItemTile),
                const SizedBox(height: 20),
                _sectionHeader('Sides & Drinks'),
                const SizedBox(height: 8),
                ..._sidesAndDrinks.map(_buildItemTile),
              ],
            ),
          ),
        ],
      ),
      bottomNavigationBar: _cartCount == 0
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(14),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _goToOrderForm,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _kSubwayGreen,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    ),
                    child: Text(
                      '$_cartCount item${_cartCount > 1 ? 's' : ''} · ₹${_cartTotal.toStringAsFixed(0)} — Continue',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                  ),
                ),
              ),
            ),
    );
  }

  Widget _sectionHeader(String label) => Text(
        label,
        style: GoogleFonts.outfit(color: _kText, fontSize: 17, fontWeight: FontWeight.w900),
      );

  Widget _buildItemTile(_SubwayItem item) {
    final qty = _cart[item.name] ?? 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x1A008938)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(item.name, style: GoogleFonts.outfit(color: _kText, fontSize: 14.5, fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text(item.description, style: GoogleFonts.outfit(color: _kMuted, fontSize: 11.5)),
                const SizedBox(height: 6),
                Text('₹${item.price.toStringAsFixed(0)}', style: GoogleFonts.outfit(color: _kSubwayGreen, fontSize: 14, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
          const SizedBox(width: 10),
          qty == 0
              ? OutlinedButton(
                  onPressed: () => _add(item.name),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _kSubwayGreen,
                    side: const BorderSide(color: _kSubwayGreen, width: 1.4),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                  ),
                  child: const Text('ADD', style: TextStyle(fontWeight: FontWeight.w800)),
                )
              : Container(
                  decoration: BoxDecoration(
                    color: _kSubwayGreen,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        onPressed: () => _remove(item.name),
                        icon: const Icon(Icons.remove, color: Colors.white, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                      Text('$qty', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                      IconButton(
                        onPressed: () => _add(item.name),
                        icon: const Icon(Icons.add, color: Colors.white, size: 18),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
                      ),
                    ],
                  ),
                ),
        ],
      ),
    );
  }
}
