// ================================================================
// FoodOrderStatusScreen — "Order Status" button destination
// ================================================================
// Per Nizam's request: the Food Genie page bottom is split into two
// buttons — "Order Food" (place a new order) and "Order Status" (jump
// straight here instead of scrolling down to "My Orders"). Shows every
// food order this customer has placed, from BOTH pipelines that exist
// in this app: the free-text 'custom_food_order' ("tell us what you
// want") and the catalog/menu-based 'catalog_food_order' (ordering
// directly off a seller's menu via seller_detail_screen.dart) — a
// single where-in query covers both, so nothing is missed regardless
// of which flow the customer used. Tapping any order opens the same
// graphical step tracker (ServiceRequestTrackingScreen) already used
// elsewhere in the app.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/service_request_labels.dart';
import 'service_request_tracking_screen.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);

const List<String> _kFoodOrderRequestTypes = ['custom_food_order', 'catalog_food_order'];

class FoodOrderStatusScreen extends StatelessWidget {
  const FoodOrderStatusScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Order Status', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: user == null
          ? Center(
              child: Text('Please sign in to see your orders.', style: GoogleFonts.outfit(color: _kMuted)),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // NOTE: deliberately no .orderBy('createdAt') here — an
              // equality/whereIn filter combined with orderBy on a
              // DIFFERENT field needs a Firestore composite index (the
              // exact "requires an index" crash already root-caused and
              // fixed once this session in usage_billing_service.dart).
              // Sorted client-side below instead, on what's normally a
              // small per-customer result set.
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .where('customerId', isEqualTo: user.uid)
                  .where('requestType', whereIn: _kFoodOrderRequestTypes)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _kPink));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load your orders.', style: GoogleFonts.outfit(color: _kMuted)),
                  );
                }
                final docs = (snapshot.data?.docs ?? []).toList()
                  ..sort((a, b) {
                    final at = a.data()['createdAt'] as Timestamp?;
                    final bt = b.data()['createdAt'] as Timestamp?;
                    if (at == null || bt == null) return 0;
                    return bt.compareTo(at);
                  });
                if (docs.isEmpty) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text('🍽️', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text('No food orders yet', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text('Orders you place will show up here with live status.',
                              textAlign: TextAlign.center,
                              style: GoogleFonts.outfit(color: _kMuted, fontSize: 13)),
                        ],
                      ),
                    ),
                  );
                }
                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 12),
                  itemBuilder: (context, i) => _FoodOrderStatusCard(doc: docs[i]),
                );
              },
            ),
    );
  }
}

class _FoodOrderStatusCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _FoodOrderStatusCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final requestType = (data['requestType'] as String?) ?? 'custom_food_order';
    final details = (data['details'] as Map<String, dynamic>?) ?? const {};
    final status = (data['status'] as String?) ?? 'pending';
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel(requestType, status);

    // The two pipelines shape `details` differently — this renders
    // whichever shape is present without assuming one or the other.
    String title;
    String subtitle;
    if (requestType == 'catalog_food_order') {
      title = (details['sellerName'] as String?)?.trim().isNotEmpty == true
          ? details['sellerName'] as String
          : 'Shop order';
      final items = (details['items'] as List<dynamic>?) ?? [];
      subtitle = items
          .whereType<Map>()
          .map((it) => '${it['quantity'] ?? 1} × ${it['name'] ?? 'Item'}')
          .join(', ');
    } else {
      final shop = (details['restaurantOrPreference'] as String?)?.trim();
      title = (shop != null && shop.isNotEmpty) ? shop : 'Custom food order';
      subtitle = (details['items'] as String?)?.trim() ?? '';
    }

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: doc.id,
            requestType: requestType,
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: const Color(0xFFEEEEF5)),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: GoogleFonts.outfit(color: _kText, fontSize: 14, fontWeight: FontWeight.w700),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (subtitle.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(subtitle, style: const TextStyle(color: _kMuted, fontSize: 12), maxLines: 2, overflow: TextOverflow.ellipsis),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(statusLabel, style: TextStyle(color: statusColor, fontSize: 11, fontWeight: FontWeight.w700)),
            ),
          ],
        ),
      ),
    );
  }
}
