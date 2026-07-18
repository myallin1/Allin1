// Full ride history for logged-in customer
// Shows past rides with: date, pickup, drop, fare, rating, status

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

// Theme Constants
const Color kBg = Color(0xFF08080F);
const Color kSurface = Color(0xFF111118);
const Color kCard = Color(0xFF1A1A26);
const Color kCard2 = Color(0xFF20202E);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x2E7B6FE0);

class RideHistoryScreen extends StatelessWidget {
  const RideHistoryScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // AppBar with back button
            _buildHeader(context),
            // StreamBuilder on rides where customerPhone == uid
            Expanded(
              child: StreamBuilder<QuerySnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('rides')
                    .where(
                      'userId',
                      isEqualTo: FirebaseAuth.instance.currentUser?.uid,
                    )
                    .orderBy('createdAt', descending: true)
                    .limit(20)
                    .snapshots(),
                builder: (ctx, snap) {
                  if (snap.connectionState == ConnectionState.waiting) {
                    return const Center(
                      child: CircularProgressIndicator(color: kGold),
                    );
                  }
                  final docs = snap.data?.docs ?? [];
                  if (docs.isEmpty) {
                    return _emptyState();
                  }
                  return ListView.builder(
                    padding: const EdgeInsets.all(16),
                    itemCount: docs.length,
                    itemBuilder: (_, i) {
                      final d = docs[i].data()! as Map<String, dynamic>;
                      return _RideHistoryCard(data: d);
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: kBorder),
              ),
              child:
                  const Icon(Icons.arrow_back_ios_new, size: 14, color: kMuted),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Ride History',
            style: GoogleFonts.notoSansTamil(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bike, size: 50, color: kMuted),
            const SizedBox(height: 16),
            Text(
              'No rides yet!',
              style: GoogleFonts.inter(fontSize: 16, color: kText),
            ),
            const SizedBox(height: 6),
            const Text(
              'Book your first ride!',
              style: TextStyle(fontSize: 12, color: kMuted),
            ),
          ],
        ),
      );
}

class _RideHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RideHistoryCard({required this.data});

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return kGreen;
      case 'accepted':
        return kGold;
      case 'cancelled':
        return kOrange;
      default:
        return kMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fare = data['fare'] as num? ?? 0;
    final pickup = data['pickup'] as String? ?? '';
    final drop = data['drop'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final rating = data['customerRating'] as int? ?? 0;
    final rideType = data['rideType'] as String? ?? 'Bike';
    final ts = data['createdAt'] as Timestamp?;
    final date = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rideType == 'Auto'
                    ? Icons.local_taxi
                    : rideType == 'Parcel'
                        ? Icons.local_shipping
                        : Icons.directions_bike,
                size: 20,
                color: kGold,
              ),
              const SizedBox(width: 8),
              Text(date, style: const TextStyle(fontSize: 11, color: kMuted)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _statusColor(status).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 8,
                    color: _statusColor(status),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${fare.toInt()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    const BoxDecoration(color: kGreen, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pickup,
                  style: const TextStyle(fontSize: 12, color: kText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 2,
              height: 10,
              color: kBorder,
              margin: const EdgeInsets.symmetric(vertical: 2),
            ),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  drop,
                  style: const TextStyle(fontSize: 12, color: kText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (rating > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < rating ? Icons.star : Icons.star_border,
                  size: 14,
                  color: kGold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
  }
}
