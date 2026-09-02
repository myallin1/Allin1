// ================================================================
// grocery_store_list_screen.dart — customer-facing list of grocery
// sellers running a real digital catalog (Sep 2026 universal catalog
// build). Deliberately a NEW, separate screen rather than routing
// through category_screen.dart's existing food-shop list — that
// screen hardcodes its "tap a seller" push to SellerDetailScreen
// (food-specific), and branching that well-audited, live food path on
// category risked regressions to a working revenue flow for no
// benefit. This one is small and grocery-only.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/category_gateway_service.dart';
import 'grocery_seller_detail_screen.dart';

const Color _bg = Color(0xFFFFFFFF);
const Color _text = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF9999BB);
const Color _teal = Color(0xFF11998E);
const Color _tealDark = Color(0xFF0D7A6E);

class GroceryStoreListScreen extends StatefulWidget {
  const GroceryStoreListScreen({super.key});

  @override
  State<GroceryStoreListScreen> createState() => _GroceryStoreListScreenState();
}

class _GroceryStoreListScreenState extends State<GroceryStoreListScreen> {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _sellers = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool forceRefresh = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      _sellers = forceRefresh
          ? await CategoryGatewayService().forceRefreshCategory(Category.grocery)
          : await CategoryGatewayService().loadCategoryData(Category.grocery);
    } catch (e) {
      _error = 'Could not load grocery stores. Please try again.';
      debugPrint('[GroceryStoreList] load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('🛒 Grocery Stores', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _error != null
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(_error!, style: GoogleFonts.outfit(color: _muted)),
                      const SizedBox(height: 12),
                      ElevatedButton(onPressed: () => _load(forceRefresh: true), child: const Text('Retry')),
                    ],
                  ),
                )
              : _sellers.isEmpty
                  ? Center(
                      child: Text('No grocery stores nearby yet.', style: GoogleFonts.outfit(color: _muted)),
                    )
                  : RefreshIndicator(
                      onRefresh: () => _load(forceRefresh: true),
                      child: ListView.builder(
                        padding: const EdgeInsets.all(16),
                        itemCount: _sellers.length,
                        itemBuilder: (context, i) => _buildStoreCard(_sellers[i]),
                      ),
                    ),
    );
  }

  Widget _buildStoreCard(Map<String, dynamic> seller) {
    final name = (seller['name'] as String?) ?? (seller['shopName'] as String?) ?? 'Grocery Store';
    final address = (seller['address'] as String?) ?? '';
    final isOpen = (seller['isOpen'] as bool?) ?? true;
    final rating = (seller['rating'] as num?)?.toDouble() ?? 0.0;
    final sellerId = seller['id'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _teal.withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: _teal.withValues(alpha: 0.06), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: sellerId == null
            ? null
            : () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => GrocerySellerDetailScreen(sellerId: sellerId, sellerName: name),
                  ),
                ),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                width: 52, height: 52,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_teal, _tealDark]),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: const Icon(Icons.storefront_rounded, color: Colors.white, size: 26),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(name, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 15)),
                    if (address.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(address, maxLines: 1, overflow: TextOverflow.ellipsis, style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
                    ],
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Icon(Icons.star_rounded, size: 14, color: rating > 0 ? Colors.amber : _muted),
                        const SizedBox(width: 2),
                        Text(rating > 0 ? rating.toStringAsFixed(1) : 'New', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
                        const SizedBox(width: 10),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: (isOpen ? _teal : Colors.grey).withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(isOpen ? 'Open' : 'Closed',
                              style: GoogleFonts.outfit(color: isOpen ? _teal : Colors.grey, fontSize: 10, fontWeight: FontWeight.w700),),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: _muted),
            ],
          ),
        ),
      ),
    );
  }
}
