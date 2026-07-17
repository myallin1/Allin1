// lib/screens/admin/admin_taxi_rides_screen.dart
// ================================================================
// AdminTaxiRidesScreen — focused "Taxi" monitoring view
// Live Firestore: all `rides` docs across every vehicle category
// (bike/auto/car/parcel/mini_truck/lorry/emergency_manpower) — "Taxi"
// is the umbrella for all vehicle-based rides, not filtered further.
//
// Adapted from AdminDashboardScreen's existing _buildRidesList() tab
// (same query, same row rendering, same helpers, same UTR-verify
// dialog) rather than a shared extraction, so admin_dashboard_screen.dart
// stays completely untouched — see Commit 2 plan discussion. Any
// future fix to this rendering logic needs to be mirrored manually in
// both places; that duplication is the accepted tradeoff for this
// commit's "don't touch the other screen" constraint.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

class AdminTaxiRidesScreen extends StatelessWidget {
  const AdminTaxiRidesScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'Taxi',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
      ),
      body: _buildRidesList(context),
    );
  }

  // ── Rides list — same query/rendering as AdminDashboardScreen's
  // "Rides" tab (_buildRidesList), copied verbatim (not extracted) so
  // that screen is left completely untouched per the approved plan.
  Widget _buildRidesList(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _gold));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyCard('No rides found', '🏍️');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data()! as Map<String, dynamic>;
            final status = d['status'] as String? ?? 'unknown';
            final pickup = d['pickup'] as String? ??
                d['pickupAddress'] as String? ?? '—';
            final drop = d['drop'] as String? ??
                d['dropAddress'] as String? ?? '—';
            final fare = (d['fare'] as num?)?.toInt() ?? 0;
            final tip = (d['tipAmount'] as num?)?.toInt() ?? 0;
            final finalFare = (d['finalFare'] as num?)?.toInt() ?? (fare + tip);
            final rating = (d['customerRating'] as num?)?.toInt();
            final captain = d['captainName'] as String? ??
                d['heroName'] as String? ?? '—';
            final cust = d['customerName'] as String? ?? '—';
            final ts = d['createdAt'] as Timestamp?;
            final time = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month} '
                    '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                : '—';
            final rawCategory =
                (d['category'] as String? ?? d['vehicleType'] as String? ?? '')
                    .trim()
                    .toLowerCase();
            final categoryEmoji = _categoryEmoji(rawCategory);
            final categoryLabel = _categoryLabel(rawCategory);
            final color = _statusColor(status);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🟢 $pickup',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '🔴 $drop',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _statusBadge(status, color),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _pill('👤 $cust', _muted),
                      const SizedBox(width: 6),
                      _pill('🏍️ $captain', _muted),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹$finalFare',
                            style: const TextStyle(
                              fontSize: 14,
                              color: _gold,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (tip > 0)
                            Text(
                              'Fare: ₹$fare + Tip: ₹$tip',
                              style: const TextStyle(
                                fontSize: 9,
                                color: _muted,
                              ),
                            ),
                          if (rating != null && rating > 0)
                            Text(
                              '⭐' * rating,
                              style: const TextStyle(fontSize: 9),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _purple.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '$categoryEmoji $categoryLabel',
                          style: const TextStyle(
                            fontSize: 9,
                            color: _purple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: (d['paymentStatus'] as String? ?? 'pending') == 'confirmed'
                              ? _green.withValues(alpha: 0.12)
                              : _red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: (d['paymentStatus'] as String? ?? 'pending') == 'confirmed'
                                ? _green.withValues(alpha: 0.3)
                                : _red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '💳 ${(d['paymentStatus'] as String? ?? 'pending').toUpperCase()}',
                          style: TextStyle(
                            fontSize: 9,
                            color: (d['paymentStatus'] as String? ?? 'pending') == 'confirmed' ? _green : _red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if ((d['paymentStatus'] as String? ?? 'pending') == 'pending')
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: TextButton(
                            onPressed: () => _showUtrDialog(context, doc.id, cust, (d['finalFare'] as num?)?.toDouble() ?? 0),
                            style: TextButton.styleFrom(
                              backgroundColor: _purple.withValues(alpha: 0.12),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Verify UTR',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _purple),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ID: ${doc.id.substring(0, 12)}…  •  $time',
                          style: const TextStyle(fontSize: 9, color: _muted),
                        ),
                      ),
                      if (rating != null && rating > 0)
                        Text(
                          '⭐ $rating/5',
                          style: const TextStyle(fontSize: 9, color: _muted),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── UTR verification dialog — copied as-is from AdminDashboardScreen's
  // _showUtrDialog; self-contained (own StatefulBuilder), only needs
  // BuildContext + the ride's docId/customerName/amount.
  Future<void> _showUtrDialog(BuildContext context, String rideDocId, String customerName, double amount) async {
    final TextEditingController utrController = TextEditingController();
    bool isLoading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2A),
          title: const Text(
            '✅ Verify Payment',
            style: TextStyle(color: Color(0xFFFFBB00), fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Customer: $customerName\nAmount: ₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFEEEEF5)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: utrController,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Color(0xFFEEEEF5)),
                decoration: InputDecoration(
                  labelText: '📋 UTR Number (Transaction ID)',
                  hintText: 'e.g., 123456789012',
                  labelStyle: const TextStyle(color: Color(0xFF7777A0)),
                  filled: true,
                  fillColor: const Color(0xFF0A0A12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF7777A0))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C853)),
              onPressed: isLoading ? null : () async {
                final utr = utrController.text.trim();
                if (utr.isEmpty || utr.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('⚠️ Enter a valid UTR number (min 6 chars)'), backgroundColor: Color(0xFFFF5252)),
                  );
                  return;
                }
                setDialogState(() => isLoading = true);
                try {
                  await FirebaseFirestore.instance.collection('rides').doc(rideDocId).update({
                    'paymentStatus': 'confirmed',
                    'utrNumber': utr,
                    'confirmedAt': FieldValue.serverTimestamp(),
                    'confirmedBy': FirebaseAuth.instance.currentUser?.uid ?? 'admin',
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Payment confirmed!'), backgroundColor: Color(0xFF00C853)),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('❌ Error: ${e.toString()}'), backgroundColor: Color(0xFFFF5252)),
                    );
                  }
                } finally {
                  setDialogState(() => isLoading = false);
                }
              },
              child: isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirm Payment ✅', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  // ── Category / status helpers — copied as-is from AdminDashboardScreen.
  String _categoryEmoji(String category) {
    switch (category) {
      case 'auto':       return '🛺';
      case 'car':
      case 'cab':        return '🚘';
      case 'parcel':     return '📦';
      case 'mini_truck': return '🚚';
      case 'lorry':      return '🚛';
      case 'emergency_manpower':
      case 'manpower':   return '🚨';
      case 'bike':
      default:           return '🏍️';
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'auto':             return 'Auto';
      case 'car':
      case 'cab':              return 'Cab/Mini';
      case 'parcel':           return 'Parcel';
      case 'mini_truck':       return 'Mini Truck';
      case 'lorry':            return 'Lorry';
      case 'emergency_manpower':
      case 'manpower':         return 'Emergency';
      case 'bike':
      default:                 return 'Bike';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return _green;
      case 'accepted':
      case 'arriving':
      case 'in_progress':
        return _orange;
      case 'searching':
        return _gold;
      case 'cancelled':
      case 'cancelled_by_captain':
        return _red;
      default:
        return _muted;
    }
  }

  Widget _statusBadge(String status, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          status.toUpperCase().replaceAll('_', ' '),
          style:
              TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w800),
        ),
      );

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9, color: color),
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _emptyCard(String msg, String emoji) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(msg, style: const TextStyle(fontSize: 13, color: _muted)),
          ],
        ),
      );
}

const Color _orange = Color(0xFFFF6B35);
const Color _border = Color(0x1AFFFFFF);
