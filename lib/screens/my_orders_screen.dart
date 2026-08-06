// ================================================================
// my_orders_screen.dart — Unified Customer "My Orders" list. A single
// vertical feed across ALL 4 service_requests categories (Hero
// Booking / Custom Order / Custom Food Order / Grocery Order) instead
// of the per-type status screens (GroceryOrderStatusScreen,
// FoodOrderStatusScreen, HeroBookingStatusScreen) — additive, does NOT
// replace those existing entry points.
//
// FIX (query pattern — same composite-index bug class already fixed
// in erode_offers_section.dart): a `.where('customerId', ...)`
// combined with `.orderBy('createdAt', ...)` on a different field
// needs a Firestore composite index that doesn't exist here. Query
// with just the `.where()` filter and sort client-side instead.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/theme_context_extensions.dart';
import '../utils/service_request_labels.dart';
import 'service_request_tracking_screen.dart';

class MyOrdersScreen extends StatelessWidget {
  const MyOrdersScreen({super.key});

  static const Map<String, IconData> _typeIcons = {
    'hero_booking': Icons.bolt_rounded,
    'custom_order': Icons.shopping_bag_outlined,
    'custom_food_order': Icons.restaurant_rounded,
    'grocery_order': Icons.local_grocery_store_rounded,
    'electronics_service': Icons.build_rounded,
  };

  static const Map<String, String> _typeLabels = {
    'hero_booking': 'Hero Booking',
    'custom_order': 'Custom Order',
    'custom_food_order': 'Food Order',
    'grocery_order': 'Grocery Order',
    'electronics_service': 'Electronics Service',
  };

  String _firstItemLabel(Map<String, dynamic> details) {
    final raw = details['items'];
    if (raw is List && raw.isNotEmpty) {
      final first = raw.first;
      if (first is Map) {
        final name = (first['name'] ?? '').toString().trim();
        if (name.isNotEmpty) return name;
      }
    }
    final listText = (details['listText'] as String?)?.trim();
    if (listText != null && listText.isNotEmpty) return listText;
    if (raw is String && raw.trim().isNotEmpty) return raw.trim();
    final taskDesc = (details['taskDescription'] as String?)?.trim();
    if (taskDesc != null && taskDesc.isNotEmpty) return taskDesc;
    final pref = (details['restaurantOrPreference'] as String?)?.trim();
    if (pref != null && pref.isNotEmpty) return pref;
    return 'No details';
  }

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      backgroundColor: colors.background,
      appBar: AppBar(
        backgroundColor: colors.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new_rounded, color: colors.text, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('My Orders', style: GoogleFonts.outfit(color: colors.text, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: user == null
          ? Center(
              child: Text('Please sign in to see your orders.', style: TextStyle(color: colors.mutedText)),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .where('customerId', isEqualTo: user.uid)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return Center(child: CircularProgressIndicator(color: colors.accent));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load your orders.', style: TextStyle(color: colors.mutedText)),
                  );
                }
                final docs = [...(snapshot.data?.docs ?? <QueryDocumentSnapshot<Map<String, dynamic>>>[])];
                // Client-side sort — see FIX note above.
                docs.sort((a, b) {
                  final aTs = a.data()['createdAt'];
                  final bTs = b.data()['createdAt'];
                  if (aTs is! Timestamp || bTs is! Timestamp) return 0;
                  return bTs.compareTo(aTs);
                });

                if (docs.isEmpty) {
                  return Center(
                    child: Text('No orders yet.', style: TextStyle(color: colors.mutedText, fontSize: 13)),
                  );
                }

                return ListView.separated(
                  padding: const EdgeInsets.all(16),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) => _orderCard(context, docs[i]),
                );
              },
            ),
    );
  }

  Widget _orderCard(BuildContext context, QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final colors = context.colors;
    final data = doc.data();
    final requestType = (data['requestType'] as String?) ?? 'hero_booking';
    final details = (data['details'] as Map<String, dynamic>?) ?? const {};
    final status = (data['status'] as String?) ?? 'pending';
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel(requestType, status);
    final createdAt = data['createdAt'];
    String dateLabel = '';
    if (createdAt is Timestamp) {
      final dt = createdAt.toDate();
      dateLabel = '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}';
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
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: colors.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: colors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 40,
              height: 40,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: colors.accent.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Icon(_typeIcons[requestType] ?? Icons.receipt_long_rounded, color: colors.accent, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _typeLabels[requestType] ?? 'Service Request',
                          style: GoogleFonts.outfit(color: colors.text, fontSize: 13.5, fontWeight: FontWeight.w800),
                        ),
                      ),
                      if (dateLabel.isNotEmpty)
                        Text(dateLabel, style: TextStyle(color: colors.mutedText, fontSize: 10.5)),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    _firstItemLabel(details),
                    style: TextStyle(color: colors.mutedText, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                    decoration: BoxDecoration(
                      color: statusColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      statusLabel,
                      style: TextStyle(color: statusColor, fontSize: 10.5, fontWeight: FontWeight.w700),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
