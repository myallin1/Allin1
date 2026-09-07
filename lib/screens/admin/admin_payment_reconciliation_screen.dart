// ================================================================
// admin_payment_reconciliation_screen.dart — Admin: PhonePe payment_orders
// ================================================================
// FIX (re-audit, Sep 2026 — closes a real gap found while auditing the
// food-section PhonePe wiring): payment_orders is where every PhonePe
// checkout attempt actually lands — including the `cascadeFailed` case
// where PhonePe genuinely took a customer's money but the linked order
// doc no longer existed (cancelled mid-payment) so nothing else in the
// app got updated. Before this screen, NOTHING in the app ever read
// payment_orders — that "manual reconciliation" a code comment promised
// had no UI backing it at all. This screen is that UI.
//
// Follows the same fetch-on-demand CachedAnalyticsView pattern as every
// other admin analytics screen (see payments_received_screen.dart) —
// no live listeners, reads only happen on an explicit Fetch tap.
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
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

class AdminPaymentReconciliationScreen extends StatefulWidget {
  const AdminPaymentReconciliationScreen({super.key});

  @override
  State<AdminPaymentReconciliationScreen> createState() =>
      _AdminPaymentReconciliationScreenState();
}

class _AdminPaymentReconciliationScreenState
    extends State<AdminPaymentReconciliationScreen> {
  AnalyticsRange _range = AnalyticsRange.today;

  /// One bounded query per Fetch tap — see CachedAnalyticsView.
  Future<List<dynamic>> _fetchPaymentOrders() async {
    final snap = await FirebaseFirestore.instance
        .collection('payment_orders')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .get();
    DbUsageTracker.instance.recordRead(
      snap.docs.length,
      'admin_payment_reconciliation',
      'fetch_payment_orders',
    );
    // Flattened to plain maps (epoch millis instead of Timestamp) so the
    // snapshot can be stored in Hive.
    return snap.docs.map((d) {
      final data = d.data();
      return <String, dynamic>{
        'id': d.id,
        'requestId': data['requestId'] ?? '',
        'sourceCollection': data['sourceCollection'] ?? 'service_requests',
        'customerId': data['customerId'] ?? '',
        'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
        'status': data['status'] ?? 'created',
        'failureReason': data['failureReason'] ?? '',
        'cascadeFailed': data['cascadeFailed'] == true,
        'cascadeFailedReason': data['cascadeFailedReason'] ?? '',
        'gatewayTransactionId': data['gatewayTransactionId'] ?? '',
        'createdAtMs':
            (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _inRange(List<dynamic> raw) {
    final now = DateTime.now();
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) {
          final ms = (m['createdAtMs'] as num?)?.toInt() ?? 0;
          if (ms == 0) return _range == AnalyticsRange.all;
          return _range.contains(DateTime.fromMillisecondsSinceEpoch(ms), now: now);
        })
        .toList()
      ..sort((a, b) => ((b['createdAtMs'] as num?) ?? 0)
          .compareTo((a['createdAtMs'] as num?) ?? 0));
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'paid':
        return _green;
      case 'failed':
        return _red;
      default:
        return _gold; // 'created' — still pending/in-flight
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'PhonePe Payment Reconciliation',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
      ),
      body: CachedAnalyticsView<List<dynamic>>(
        cacheKey: 'admin_payment_orders',
        fetch: _fetchPaymentOrders,
        emptyMessage: 'No payment orders loaded yet.',
        extraActions: [
          Expanded(
            child: AnalyticsRangeChips(
              selected: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
          ),
        ],
        builder: (context, raw) {
          final docs = _inRange(raw);

          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No PhonePe payment orders in "${_range.label}".',
                style: GoogleFonts.outfit(color: _muted),
              ),
            );
          }

          final cascadeFailedCount =
              docs.where((d) => d['cascadeFailed'] == true).length;
          double totalPaid = 0;
          for (final d in docs) {
            if (d['status'] == 'paid') {
              totalPaid += (d['amount'] as num?)?.toDouble() ?? 0;
            }
          }

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                  border: cascadeFailedCount > 0
                      ? Border.all(color: _red.withValues(alpha: 0.5))
                      : null,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          '${docs.length} orders • ${_range.label}',
                          style: GoogleFonts.outfit(
                              color: _muted, fontWeight: FontWeight.w600),
                        ),
                        if (cascadeFailedCount > 0)
                          Padding(
                            padding: const EdgeInsets.only(top: 4),
                            child: Text(
                              '$cascadeFailedCount need manual reconciliation',
                              style: GoogleFonts.outfit(
                                  color: _red,
                                  fontWeight: FontWeight.w700,
                                  fontSize: 11.5),
                            ),
                          ),
                      ],
                    ),
                    Text(
                      '₹${totalPaid.toStringAsFixed(2)} paid',
                      style: GoogleFonts.outfit(
                        color: _green,
                        fontWeight: FontWeight.w900,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(horizontal: 14),
                  itemCount: docs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = docs[index];
                    final tsMs = (data['createdAtMs'] as num?)?.toInt() ?? 0;
                    final ts = tsMs == 0
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(tsMs);
                    final status = data['status'] as String? ?? 'created';
                    final cascadeFailed = data['cascadeFailed'] == true;

                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                        border: cascadeFailed
                            ? Border.all(color: _red.withValues(alpha: 0.6))
                            : null,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  'Order ${data['requestId']}',
                                  style: GoogleFonts.outfit(
                                      color: _text, fontWeight: FontWeight.w700),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 3),
                                decoration: BoxDecoration(
                                  color: _statusColor(status).withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  status.toUpperCase(),
                                  style: GoogleFonts.outfit(
                                    color: _statusColor(status),
                                    fontWeight: FontWeight.w800,
                                    fontSize: 10.5,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '₹${(data['amount'] as num?)?.toStringAsFixed(2) ?? '0.00'} • '
                            '${data['sourceCollection']} • '
                            '${ts != null ? '${ts.day}/${ts.month}/${ts.year} ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}' : '—'}',
                            style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                          ),
                          if ((data['gatewayTransactionId'] as String?)
                                  ?.isNotEmpty ==
                              true)
                            Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                'Gateway txn: ${data['gatewayTransactionId']}',
                                style: GoogleFonts.outfit(color: _muted, fontSize: 10),
                              ),
                            ),
                          if (status == 'failed' &&
                              (data['failureReason'] as String?)?.isNotEmpty ==
                                  true)
                            Padding(
                              padding: const EdgeInsets.only(top: 4),
                              child: Text(
                                'Failure: ${data['failureReason']}',
                                style: GoogleFonts.outfit(color: _red, fontSize: 11),
                              ),
                            ),
                          if (cascadeFailed)
                            Container(
                              margin: const EdgeInsets.only(top: 8),
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: _red.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                children: [
                                  const Icon(Icons.warning_amber_rounded,
                                      color: _red, size: 16),
                                  const SizedBox(width: 6),
                                  Expanded(
                                    child: Text(
                                      'Money collected but not linked — '
                                      '${data['cascadeFailedReason']}',
                                      style: GoogleFonts.outfit(
                                          color: _red,
                                          fontSize: 10.5,
                                          fontWeight: FontWeight.w600),
                                    ),
                                  ),
                                ],
                              ),
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
