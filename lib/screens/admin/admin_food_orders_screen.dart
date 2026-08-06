// ================================================================
// AdminFoodOrdersScreen — manage food orders from the admin app
// ================================================================
// Per Nizam's explicit instruction for this tab: "auto listener
// oodama reload button vacharlam" — no live Firestore listener here,
// a manual round-refresh button instead (same ManualRefreshHeader
// pattern already used on the Taxi Overview page this session).
//
// Covers BOTH food-order pipelines that exist in this app: the
// free-text 'custom_food_order' (Food Genie) and the catalog/menu-
// based 'catalog_food_order' (seller_detail_screen.dart checkout) —
// a single whereIn query on requestType covers both.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../utils/service_request_labels.dart';
import '../../widgets/manual_refresh_header.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _pink = Color(0xFFFF4FA3);
const Color _gold = Color(0xFFF5C542);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

const List<String> _kFoodOrderRequestTypes = ['custom_food_order', 'catalog_food_order'];

class AdminFoodOrdersScreen extends StatefulWidget {
  const AdminFoodOrdersScreen({super.key});

  @override
  State<AdminFoodOrdersScreen> createState() => _AdminFoodOrdersScreenState();
}

class _AdminFoodOrdersScreenState extends State<AdminFoodOrdersScreen> {
  bool _loading = false;
  DateTime? _syncedAt;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _orders = [];

  @override
  void initState() {
    super.initState();
    _fetch();
  }

  Future<void> _fetch() async {
    setState(() => _loading = true);
    try {
      // No .orderBy() paired with the whereIn filter — a different-field
      // orderBy + whereIn combo needs a composite index (same root cause
      // fixed once already this session in usage_billing_service.dart).
      // Sorted client-side below instead.
      //
      // FIX (CTO mandate — Phase 2 "Cache-First" audit): this is an
      // admin browse/history list of food orders, not a decision-gating
      // read — cache-first here, falling back to a real server read if
      // nothing is cached yet on this device.
      var snap = await FirebaseFirestore.instance
          .collection('service_requests')
          .where('requestType', whereIn: _kFoodOrderRequestTypes)
          .limit(200)
          .get(const GetOptions(source: Source.cache));
      if (snap.docs.isEmpty) {
        snap = await FirebaseFirestore.instance
            .collection('service_requests')
            .where('requestType', whereIn: _kFoodOrderRequestTypes)
            .limit(200)
            .get();
      }
      final docs = snap.docs.toList()
        ..sort((a, b) {
          final at = a.data()['createdAt'] as Timestamp?;
          final bt = b.data()['createdAt'] as Timestamp?;
          if (at == null || bt == null) return 0;
          return bt.compareTo(at);
        });
      if (mounted) {
        setState(() {
          _orders = docs;
          _loading = false;
          _syncedAt = DateTime.now();
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _loading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to load food orders: $e'), backgroundColor: const Color(0xFFFF5252)),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Text('Food Orders', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ManualRefreshHeader(
              lastSyncedAt: _syncedAt,
              loading: _loading,
              onRefresh: _fetch,
              textColor: _muted,
            ),
            const SizedBox(height: 12),
            Text(
              '${_orders.length} order(s) loaded (Food Genie + shop menu orders combined)',
              style: GoogleFonts.outfit(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            Expanded(
              child: _loading && _orders.isEmpty
                  ? const Center(child: CircularProgressIndicator(color: _pink))
                  : _orders.isEmpty
                      ? Center(
                          child: Text('No food orders yet.', style: GoogleFonts.outfit(color: _muted, fontSize: 13)),
                        )
                      : ListView.builder(
                          itemCount: _orders.length,
                          itemBuilder: (context, i) => _orderTile(_orders[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _orderTile(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final requestType = (data['requestType'] as String?) ?? 'custom_food_order';
    final details = (data['details'] as Map<String, dynamic>?) ?? const {};
    final status = (data['status'] as String?) ?? 'pending';
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel(requestType, status);
    final customerName = (data['customerName'] as String?) ?? 'Customer';

    String shopLabel;
    String itemsLabel;
    if (requestType == 'catalog_food_order') {
      shopLabel = (details['sellerName'] as String?)?.trim().isNotEmpty ?? false
          ? details['sellerName'] as String
          : 'Shop order';
      final items = (details['items'] as List<dynamic>?) ?? [];
      itemsLabel = items.whereType<Map>().map((it) => '${it['quantity'] ?? 1} × ${it['name'] ?? 'Item'}').join(', ');
    } else {
      final shop = (details['restaurantOrPreference'] as String?)?.trim();
      shopLabel = (shop != null && shop.isNotEmpty) ? shop : 'Custom food order';
      // details['items'] may be the new structured List<Map>
      // {sNo, name, qty} shape (see quick_order_line_items.dart) or the
      // legacy plain String — handle both so old documents still render.
      final itemsRaw = details['items'];
      if (itemsRaw is List) {
        itemsLabel = itemsRaw
            .whereType<Map>()
            .map((it) => '${it['qty'] ?? 1} × ${it['name'] ?? 'Item'}')
            .join(', ');
      } else {
        itemsLabel = (itemsRaw as String?)?.trim() ?? '';
      }
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(shopLabel,
                    style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('Customer: $customerName', style: GoogleFonts.outfit(color: _muted, fontSize: 11.5)),
          if (itemsLabel.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(itemsLabel, style: GoogleFonts.outfit(color: _muted, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
          ],
          const SizedBox(height: 6),
          Text(
            requestType == 'catalog_food_order' ? 'Shop menu order' : 'Food Genie (free-text) order',
            style: GoogleFonts.outfit(color: _gold, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
