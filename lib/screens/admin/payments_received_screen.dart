// ================================================================
// payments_received_screen.dart — Admin: MyAllin1 UPI Payments +
// Payment Disputes
// ================================================================
// Per Nizam's "Self vs MyAllin1" payment-collection split
// (hero_ride_screen.dart's _markPaymentReceived): when a hero marks
// "PAID TO MYALLIN1 (UPI)", the money already sits in the company's
// own UPI account (never touched the hero's wallet) — this screen is
// where Admin verifies/reconciles those collections, filterable by
// day/month.
//
// Also surfaces the PRE-EXISTING "Payment Not Received" dispute flow
// (hero_ride_screen.dart's _reportPaymentIssue / hero_history_screen.
// dart's _reportPaymentIssue — both already write `paymentDispute:
// true` + `adminAlertRequired: true` to the ride doc) — that data had
// zero admin-side visibility anywhere in the app before this screen;
// heroes could flag a ride as unpaid and it just sat in Firestore with
// nobody looking at it.
//
// Deliberately simple client-side month filtering (stream the most
// recent N docs ordered by timestamp, filter in memory) rather than a
// server-side date-range query — avoids needing a new Firestore
// composite index before the Aug 15 launch, and N=300 is already far
// more than a realistic month of either collection for this stage.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/db_usage_tracker.dart';
import '../../widgets/admin/cached_analytics_view.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

class PaymentsReceivedScreen extends StatefulWidget {
  const PaymentsReceivedScreen({super.key});

  @override
  State<PaymentsReceivedScreen> createState() =>
      _PaymentsReceivedScreenState();
}

class _PaymentsReceivedScreenState extends State<PaymentsReceivedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;

  // FIX (Nizam's request, Aug 11 2026 — "year wise filter than iruku,
  // datewise, within 24 hours, 60 minutes filter vaikalam, and filter
  // pannura total timing la varra amount ah total pottu kaatatum"):
  // the old month-picker is replaced by the shared AnalyticsRange preset
  // set (60 min / 24 h / Today / This month / This year / All time).
  // Filtering runs CLIENT-SIDE over the already-fetched snapshot, so
  // switching ranges costs ZERO additional reads — the admin can flip
  // freely between 60-minute and year views without touching Firestore
  // ("database ah unwanted ah waste pannama").
  AnalyticsRange _range = AnalyticsRange.today;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  /// One bounded query per Fetch tap (not per screen open, not per
  /// change) — see CachedAnalyticsView.
  Future<List<dynamic>> _fetchCompanyPayments() async {
    final snap = await FirebaseFirestore.instance
        .collection('company_payments_received')
        .orderBy('collectedAt', descending: true)
        .limit(500)
        .trackedGet();
    DbUsageTracker.instance.recordRead(snap.docs.length, 'payments_received', 'fetch_company_payments');
    // Flattened to plain maps (epoch millis instead of Timestamp) so the
    // snapshot can be stored in Hive.
    return snap.docs.map((d) {
      final data = d.data();
      return <String, dynamic>{
        'id': d.id,
        'heroName': data['heroName'] ?? '',
        'heroId': data['heroId'] ?? '',
        'amount': (data['amount'] as num?)?.toDouble() ?? 0.0,
        'verified': data['verified'] == true,
        'collectedAtMs':
            (data['collectedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
      };
    }).toList();
  }

  Future<List<dynamic>> _fetchDisputes() async {
    // Single-field equality filter only — deliberately no .orderBy() on a
    // different field, which would demand a composite index that doesn't
    // exist (this exact combination is what originally broke this tab).
    final snap = await FirebaseFirestore.instance
        .collection('rides')
        .where('paymentDispute', isEqualTo: true)
        .limit(300)
        .trackedGet();
    DbUsageTracker.instance.recordRead(snap.docs.length, 'payments_received', 'fetch_disputes');
    return snap.docs.map((d) {
      final data = d.data();
      return <String, dynamic>{
        'id': d.id,
        'heroName': data['acceptedHeroName'] ?? data['heroName'] ?? '',
        'disputeReason': data['disputeReason'] ?? '',
        'amount': ((data['finalFare'] ?? data['estimatedFare'] ?? data['fare'])
                    as num?)
                ?.toDouble() ??
            0.0,
        // Matches the write performed by "Mark Resolved" below — the
        // dispute is considered handled once the admin alert is cleared.
        'resolved': data['adminAlertRequired'] == false,
        'raisedAtMs':
            (data['disputeRaisedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _inRange(List<dynamic> raw, String tsField) {
    final now = DateTime.now();
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .where((m) {
          final ms = (m[tsField] as num?)?.toInt() ?? 0;
          if (ms == 0) return _range == AnalyticsRange.all;
          return _range.contains(DateTime.fromMillisecondsSinceEpoch(ms),
              now: now,);
        })
        .toList()
      ..sort((a, b) => ((b[tsField] as num?) ?? 0)
          .compareTo((a[tsField] as num?) ?? 0));
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // REMOVED (Aug 11 2026): _pickMonth / _monthName / _inSelectedMonth.
  // The month-only picker was replaced by the shared AnalyticsRange
  // presets (60 min / 24 h / Today / This month / This year / All time)
  // per Nizam's request — see the _range field above.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'Payments Received',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _purple,
          labelColor: _text,
          unselectedLabelColor: _muted,
          tabs: const [
            Tab(text: 'MyAllin1 UPI'),
            Tab(text: 'Disputes'),
          ],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCompanyPaymentsTab(),
          _buildDisputesTab(),
        ],
      ),
    );
  }

  Widget _buildCompanyPaymentsTab() {
    return CachedAnalyticsView<List<dynamic>>(
      cacheKey: 'admin_company_payments',
      fetch: _fetchCompanyPayments,
      emptyMessage: 'No collections loaded yet.',
      extraActions: [
        Expanded(
          child: AnalyticsRangeChips(
            selected: _range,
            onChanged: (r) => setState(() => _range = r),
          ),
        ),
      ],
      builder: (context, raw) {
        final docs = _inRange(raw, 'collectedAtMs');

        double totalAmount = 0;
        for (final d in docs) {
          totalAmount += (d['amount'] as num?)?.toDouble() ?? 0;
        }

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No MyAllin1 UPI collections in "${_range.label}".',
              style: GoogleFonts.outfit(color: _muted),
            ),
          );
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
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        '${docs.length} collections',
                        style: GoogleFonts.outfit(
                            color: _muted, fontWeight: FontWeight.w600),
                      ),
                      Text(
                        'Total collected • ${_range.label}',
                        style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
                      ),
                    ],
                  ),
                  Text(
                    '₹${totalAmount.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(
                      color: _green,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
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
                  final tsMs = (data['collectedAtMs'] as num?)?.toInt() ?? 0;
                  final ts = tsMs == 0
                      ? null
                      : DateTime.fromMillisecondsSinceEpoch(tsMs);
                  final verified = data['verified'] == true;
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
                              Text(
                                data['heroName']?.toString().isNotEmpty == true
                                    ? data['heroName'].toString()
                                    : 'Hero ${data['heroId']}',
                                style: GoogleFonts.outfit(
                                    color: _text, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ts != null
                                    ? '${ts.day}/${ts.month}/${ts.year} • ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
                                    : '—',
                                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${(data['amount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: GoogleFonts.outfit(
                              color: _gold, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 10),
                        if (!verified)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: const BorderSide(color: _green),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            // Writes by document id — the cached snapshot
                            // holds plain maps now, not DocumentSnapshots,
                            // so there's no `.reference` to use. Updates
                            // local state optimistically too, since there
                            // is no live listener to push the change back.
                            onPressed: () async {
                              final id = data['id'] as String? ?? '';
                              if (id.isEmpty) return;
                              await FirebaseFirestore.instance
                                  .collection('company_payments_received')
                                  .doc(id)
                                  .trackedUpdate({
                                'verified': true,
                                'verifiedAt': FieldValue.serverTimestamp(),
                              });
                              if (context.mounted) {
                                setState(() => data['verified'] = true);
                              }
                            },
                            child: const Text('Verify'),
                          )
                        else
                          const Icon(Icons.verified_rounded, color: _green, size: 20),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDisputesTab() {
    // FIX (root cause of the Firestore error on this screen): combining
    // a `.where('paymentDispute', isEqualTo: true)` filter with
    // `.orderBy('disputeRaisedAt', ...)` on a DIFFERENT field requires
    // a Firestore composite index, and none exists for this pair in
    // firestore.indexes.json — Firestore throws
    // "FAILED_PRECONDITION: The query requires an index" instead of
    // just running slower. Rather than add a composite index and wait
    // for it to build/propagate this close to the Aug 15 launch, this
    // now does the equality filter ONLY (no composite index needed for
    // a single-field equality filter) and sorts by disputeRaisedAt
    // client-side after fetching — genuine unpaid-ride disputes are a
    // small collection, so client-side sort is not a real cost here.
    return CachedAnalyticsView<List<dynamic>>(
      cacheKey: 'admin_payment_disputes',
      fetch: _fetchDisputes,
      emptyMessage: 'No disputes loaded yet.',
      extraActions: [
        Expanded(
          child: AnalyticsRangeChips(
            selected: _range,
            onChanged: (r) => setState(() => _range = r),
          ),
        ),
      ],
      builder: (context, raw) {
        final docs = _inRange(raw, 'raisedAtMs');

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No unpaid-ride disputes in "${_range.label}".',
              style: GoogleFonts.outfit(color: _muted),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index];
            final tsMs = (data['raisedAtMs'] as num?)?.toInt() ?? 0;
            final ts =
                tsMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(tsMs);
            final fare = data['amount'] as num?;
            final resolved = data['resolved'] == true;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _red.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.report_problem_outlined, color: _red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ride ${data['id']}',
                          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${fare?.toStringAsFixed(0) ?? '—'} • ${ts != null ? '${ts.day}/${ts.month}/${ts.year}' : '—'}',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (!resolved)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gold,
                        side: const BorderSide(color: _gold),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      // Writes by id (cached snapshot holds plain maps,
                      // no `.reference`), with an optimistic local update
                      // since there's no live listener to echo it back.
                      onPressed: () async {
                        final id = data['id'] as String? ?? '';
                        if (id.isEmpty) return;
                        await FirebaseFirestore.instance
                            .collection('rides')
                            .doc(id)
                            .trackedUpdate({
                          'adminAlertRequired': false,
                          'disputeResolvedAt': FieldValue.serverTimestamp(),
                        });
                        if (context.mounted) {
                          setState(() => data['resolved'] = true);
                        }
                      },
                      child: const Text('Mark Resolved'),
                    )
                  else
                    const Icon(Icons.check_circle, color: _green, size: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
