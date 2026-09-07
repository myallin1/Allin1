// ================================================================
// admin_seller_payouts_screen.dart — Admin: Settle seller payouts
// ================================================================
// FIX (food-seller re-audit, Sep 2026 — real, confirmed gap): every
// completed order credits sellers/{sellerId}.pendingPayouts (see
// ServiceRequestService._completeAndCreditSeller), but NOTHING in the
// app ever wrote sellers/{sellerId}.totalSettled — confirmed by
// grepping the whole codebase: the field is only ever read (Seller
// Earnings screen, Seller Dashboard) and initialised to 0 at seller
// creation. So even when an admin actually pays a seller their money
// offline (bank transfer / UPI), there was no way to RECORD that —
// pendingPayouts grew forever and totalSettled stayed frozen at
// ₹0.00, making the "Pending vs Settled" split on the seller's own
// earnings screen permanently misleading.
//
// This screen is the missing settlement action. It does NOT move any
// real money — an admin still pays the seller manually via bank/UPI
// exactly as before — it only lets the admin RECORD that payout,
// moving the amount from pendingPayouts to totalSettled in one
// transaction so the seller's dashboard reflects reality.
//
// firestore.rules already grants isAdminAny() unrestricted write
// access to sellers/{sellerId} (Clause B on the `update` rule), so no
// rules change is needed — this was purely a missing client action.
//
// Fetch-on-demand CachedAnalyticsView pattern, same as every other
// admin analytics screen (see payments_received_screen.dart /
// admin_payment_reconciliation_screen.dart).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/db_usage_tracker.dart';
import '../../widgets/admin/cached_analytics_view.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFF6C63FF);

class AdminSellerPayoutsScreen extends StatefulWidget {
  const AdminSellerPayoutsScreen({super.key});

  @override
  State<AdminSellerPayoutsScreen> createState() =>
      _AdminSellerPayoutsScreenState();
}

class _AdminSellerPayoutsScreenState extends State<AdminSellerPayoutsScreen> {
  /// One bounded query per Fetch tap — see CachedAnalyticsView. Pulls
  /// every seller with money owed; sellers who are fully settled
  /// (pendingPayouts == 0) never appear here, which also means a
  /// brand-new seller with no completed orders yet costs nothing to
  /// exclude — this only reads accounts that actually owe something.
  Future<List<dynamic>> _fetchOwedSellers() async {
    final snap = await FirebaseFirestore.instance
        .collection('sellers')
        .where('pendingPayouts', isGreaterThan: 0)
        .limit(200)
        .get();
    DbUsageTracker.instance.recordRead(
      snap.docs.length,
      'admin_seller_payouts',
      'fetch_owed_sellers',
    );
    return snap.docs.map((d) {
      final data = d.data();
      return <String, dynamic>{
        'id': d.id,
        'name': data['name'] ?? data['shopName'] ?? 'Unnamed seller',
        'city': data['city'] ?? '',
        'pendingPayouts': (data['pendingPayouts'] as num?)?.toDouble() ?? 0.0,
        'totalSettled': (data['totalSettled'] as num?)?.toDouble() ?? 0.0,
      };
    }).toList()
      ..sort((a, b) => (b['pendingPayouts'] as double)
          .compareTo(a['pendingPayouts'] as double));
  }

  /// Records that [amount] has been paid to this seller offline —
  /// moves it from pendingPayouts to totalSettled in a single
  /// transaction. Re-reads the doc inside the transaction so two
  /// admins settling the same seller back-to-back can never push
  /// pendingPayouts negative.
  Future<void> _settle(String sellerId, double amount) async {
    final ref = FirebaseFirestore.instance.collection('sellers').doc(sellerId);
    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(ref);
      final current = (snap.data()?['pendingPayouts'] as num?)?.toDouble() ?? 0.0;
      final settled = (snap.data()?['totalSettled'] as num?)?.toDouble() ?? 0.0;
      final clamped = amount > current ? current : amount;
      tx.update(ref, {
        'pendingPayouts': current - clamped,
        'totalSettled': settled + clamped,
        'updatedAt': FieldValue.serverTimestamp(),
      });
    });
  }

  Future<void> _confirmAndSettle(
    BuildContext context,
    Map<String, dynamic> seller,
    ValueNotifier<List<dynamic>?> externalData,
    List<dynamic> currentRaw,
  ) async {
    final owed = seller['pendingPayouts'] as double;
    final controller = TextEditingController(text: owed.toStringAsFixed(2));

    final amount = await showDialog<double>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: _card,
        title: Text('Settle ${seller['name']}',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Owed: ₹${owed.toStringAsFixed(2)}',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
            const SizedBox(height: 10),
            TextField(
              controller: controller,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              style: GoogleFonts.outfit(color: _text),
              decoration: const InputDecoration(
                labelText: 'Amount actually paid (₹)',
                labelStyle: TextStyle(color: _muted),
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'Pay the seller via bank/UPI FIRST — this only records it.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _green),
            onPressed: () {
              final parsed = double.tryParse(controller.text.trim());
              if (parsed == null || parsed <= 0) return;
              Navigator.pop(dialogContext, parsed);
            },
            child: const Text('Confirm Settlement'),
          ),
        ],
      ),
    );

    if (amount == null || !context.mounted) return;

    try {
      await _settle(seller['id'] as String, amount);
      final clamped = amount > owed ? owed : amount;
      final updated = currentRaw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      final idx = updated.indexWhere((s) => s['id'] == seller['id']);
      if (idx != -1) {
        updated[idx]['pendingPayouts'] = owed - clamped;
        updated[idx]['totalSettled'] =
            (updated[idx]['totalSettled'] as double) + clamped;
        if ((updated[idx]['pendingPayouts'] as double) <= 0) {
          updated.removeAt(idx);
        }
      }
      externalData.value = updated;
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Recorded ₹${clamped.toStringAsFixed(2)} settled')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Settlement failed: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final externalData = ValueNotifier<List<dynamic>?>(null);
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'Seller Payouts',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
      ),
      body: CachedAnalyticsView<List<dynamic>>(
        cacheKey: 'admin_seller_payouts',
        fetch: _fetchOwedSellers,
        emptyMessage: 'No sellers loaded yet.',
        externalData: externalData,
        builder: (context, raw) {
          externalData.value ??= raw;
          final docs = (externalData.value ?? raw)
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((s) => (s['pendingPayouts'] as double) > 0)
              .toList()
            ..sort((a, b) => (b['pendingPayouts'] as double)
                .compareTo(a['pendingPayouts'] as double));

          if (docs.isEmpty) {
            return Center(
              child: Text('No sellers currently owed a payout.',
                  style: GoogleFonts.outfit(color: _muted)),
            );
          }

          double totalOwed = 0;
          for (final d in docs) {
            totalOwed += d['pendingPayouts'] as double;
          }

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('${docs.length} sellers owed',
                        style: GoogleFonts.outfit(
                            color: _muted, fontWeight: FontWeight.w600)),
                    Text('₹${totalOwed.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                            color: _gold, fontWeight: FontWeight.w900, fontSize: 20)),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final seller = docs[index];
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(seller['name'] as String,
                                    style: GoogleFonts.outfit(
                                        color: _text, fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                  '${seller['city']} • Settled so far: ₹${(seller['totalSettled'] as double).toStringAsFixed(2)}',
                                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                                ),
                              ],
                            ),
                          ),
                          Text(
                            '₹${(seller['pendingPayouts'] as double).toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                                color: _gold, fontWeight: FontWeight.w800),
                          ),
                          const SizedBox(width: 10),
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _purple,
                              padding: const EdgeInsets.symmetric(horizontal: 12),
                            ),
                            onPressed: () => _confirmAndSettle(
                                context, seller, externalData, docs),
                            child: const Text('Settle'),
                          ),
                        ],
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}
