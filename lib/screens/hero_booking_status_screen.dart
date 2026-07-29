// ================================================================
// HeroBookingStatusScreen — "Booking Status" button destination
// ================================================================
// Per Nizam's correction: hero_booking, custom_food_order,
// electronics_service and grocery_order must all use the SAME bottom
// page-split pattern already proven for Food Genie (custom_food_
// order_screen.dart) and NJ Tech (nj_tech_store_screen.dart) — a
// "Book" button on one side, a "Booking Status" button on the other
// that opens a LIST of the customer's past + current tasks. Tapping a
// list item opens that task's own detail/tracking page. This is
// deliberately NOT an auto-redirect on tile tap — the customer always
// lands on the form first and chooses to check status themselves,
// exactly like Food Genie's "Order Status" button.
//
// Mirrors food_order_status_screen.dart's structure. Shows every
// hero_booking request (old + active) — not just the still-open ones
// the inline _ActiveHeroBookingCard used to show — so nothing from a
// customer's history goes missing. Tapping opens
// HeroBookingTrackingScreen(requestId), the richer tracker with
// task-details, estimate-approval, payment and rating UI.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../utils/service_request_labels.dart';
import 'hero_booking_tracking_screen.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);

class HeroBookingStatusScreen extends StatelessWidget {
  const HeroBookingStatusScreen({super.key});

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
        title: Text('Booking Status', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: user == null
          ? Center(
              child: Text('Please sign in to see your bookings.', style: GoogleFonts.outfit(color: _kMuted)),
            )
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // No .orderBy('createdAt') — combining it with the two
              // equality filters below needs a composite index. Sorted
              // client-side instead, same pattern as
              // food_order_status_screen.dart.
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .where('customerId', isEqualTo: user.uid)
                  .where('requestType', isEqualTo: 'hero_booking')
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(child: CircularProgressIndicator(color: _kPink));
                }
                if (snapshot.hasError) {
                  return Center(
                    child: Text('Could not load your bookings.', style: GoogleFonts.outfit(color: _kMuted)),
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
                          const Text('🦸', style: TextStyle(fontSize: 48)),
                          const SizedBox(height: 12),
                          Text('No Hero Bookings yet', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w700, fontSize: 16)),
                          const SizedBox(height: 6),
                          Text('Tasks you book will show up here with live status.',
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
                  itemBuilder: (context, i) => _HeroBookingStatusCard(doc: docs[i]),
                );
              },
            ),
    );
  }
}

class _HeroBookingStatusCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;

  const _HeroBookingStatusCard({required this.doc});

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final details = (data['details'] as Map<String, dynamic>?) ?? const {};
    final status = (data['status'] as String?) ?? 'pending';
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel('hero_booking', status);

    final category = (details['category'] as String?)?.trim();
    final title = (category != null && category.isNotEmpty)
        ? category.replaceAll('_', ' ')
        : 'Hero Booking';
    final subtitle = (details['taskDescription'] as String?)?.trim() ?? '';

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => HeroBookingTrackingScreen(requestId: doc.id),
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
