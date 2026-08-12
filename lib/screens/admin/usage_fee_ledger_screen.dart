// ================================================================
// usage_fee_ledger_screen.dart — Admin: Platform Usage-Fee Ledger
// ================================================================
// Built per Nizam's explicit "Phase 2" revenue-tracking audit request
// (Aug 11 2026): a real-time, chronological feed of every infra
// usage-fee deduction charged to a hero's prepaid wallet
// (hero_wallets/{heroId}/transactions, type == 'infra_usage_fee' —
// see HeroWalletService.flushUsageCost() and HeroWalletTxnType). Before
// this screen, that data was written correctly but had ZERO admin-side
// visibility anywhere in the app — see the Aug 11 2026 payment/
// commission audit for the full findings.
//
// Mirrors payments_received_screen.dart's established pattern exactly:
// a single fetch-on-demand read, client-side range filter, a running total
// header, and a simple list — deliberately no server-side date-range
// query or composite index, same reasoning as that screen (avoids
// needing an index build/propagation this close to the Aug 15 launch).
//
// Uses a `collectionGroup('transactions')` query (deliberately with NO
// .where()/.orderBy() clauses — a collection-group query with filters
// needs a composite index that doesn't exist yet; a plain, unfiltered
// collection-group read needs none) to read across EVERY hero's
// transactions subcollection in one listener, then filters to
// type == 'infra_usage_fee' and sorts by createdAt client-side. Grepped
// firestore.rules first to confirm `hero_wallets/{heroId}/transactions`
// is the ONLY collection in this codebase literally named
// "transactions" — so this collectionGroup query can't accidentally
// pull in unrelated data from some other feature.
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
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

class UsageFeeLedgerScreen extends StatefulWidget {
  const UsageFeeLedgerScreen({super.key});

  @override
  State<UsageFeeLedgerScreen> createState() => _UsageFeeLedgerScreenState();
}

class _UsageFeeLedgerScreenState extends State<UsageFeeLedgerScreen> {
  // Shared preset ranges replace the old month-only picker, so fees can
  // be totalled over the last 60 minutes right through to all time —
  // all filtered client-side over one fetched snapshot (zero extra reads).
  AnalyticsRange _range = AnalyticsRange.thisMonth;

  /// One collection-group query per explicit Fetch tap.
  ///
  /// NOTE: this query is authorized by the `match /{path=**}/transactions/
  /// {txnId}` rule added to firestore.rules on Aug 11 2026 — a collection
  /// GROUP query is NOT covered by the nested hero_wallets rule, which is
  /// exactly why this screen originally returned permission-denied.
  Future<List<dynamic>> _fetchLedger() async {
    final snap = await FirebaseFirestore.instance
        .collectionGroup('transactions')
        .limit(500)
        .get();
    // Report the real document count so the DB Usage Monitor reflects
    // what this query actually cost (a collection-group read bills per
    // document returned, not per query).
    DbUsageTracker.instance.recordRead(snap.docs.length, 'usage_fee_ledger', 'fetch_ledger');
    // Flatten to Hive-serializable maps, keeping only fee entries.
    return snap.docs
        .map((d) => d.data())
        .where((data) => data['type'] == 'infra_usage_fee')
        .map((data) => <String, dynamic>{
              'heroId': data['heroId'] ?? '',
              'heroName': data['heroName'] ?? '',
              'amount': ((data['amount'] as num?)?.toDouble() ?? 0).abs(),
              'balanceAfter': (data['balanceAfter'] as num?)?.toDouble(),
              'activeMinutes': (data['activeMinutes'] as num?)?.toDouble(),
              'ridesHandled': (data['ridesHandled'] as num?)?.toInt(),
              'createdAtMs':
                  (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
            })
        .toList();
  }

  // REMOVED (Aug 11 2026): _pickMonth / _monthName / _inSelectedMonth —
  // superseded by the shared AnalyticsRange preset chips.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'Usage Fee Ledger',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
      ),
      // FETCH-ON-DEMAND: was a live collectionGroup .snapshots() listener
      // spanning EVERY hero's wallet ledger — easily the most expensive
      // listener in the admin app. Now reads only on an explicit Fetch.
      body: CachedAnalyticsView<List<dynamic>>(
        cacheKey: 'admin_usage_fee_ledger',
        fetch: _fetchLedger,
        emptyMessage: 'No usage-fee data loaded yet.',
        extraActions: [
          Expanded(
            child: AnalyticsRangeChips(
              selected: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
          ),
        ],
        builder: (context, raw) {
          final now = DateTime.now();
          final feeDocs = raw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((m) {
                final ms = (m['createdAtMs'] as num?)?.toInt() ?? 0;
                if (ms == 0) return _range == AnalyticsRange.all;
                return _range.contains(
                    DateTime.fromMillisecondsSinceEpoch(ms),
                    now: now,);
              })
              .toList()
            ..sort((a, b) => ((b['createdAtMs'] as num?) ?? 0)
                .compareTo((a['createdAtMs'] as num?) ?? 0));

          double totalCollected = 0;
          for (final d in feeDocs) {
            // Stored negative (a debit) on infra_usage_fee entries; the
            // fetch above already absolutes it.
            totalCollected += (d['amount'] as num?)?.toDouble() ?? 0;
          }

          if (feeDocs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No usage fees deducted in "${_range.label}".',
                  style: GoogleFonts.outfit(color: _muted),
                  textAlign: TextAlign.center,
                ),
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
                          '${feeDocs.length} deductions',
                          style: GoogleFonts.outfit(
                              color: _muted, fontWeight: FontWeight.w600),
                        ),
                        Text(
                          'Total collected • ${_range.label}',
                          style:
                              GoogleFonts.outfit(color: _muted, fontSize: 10.5),
                        ),
                      ],
                    ),
                    Text(
                      '₹${totalCollected.toStringAsFixed(2)}',
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
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  itemCount: feeDocs.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, index) {
                    final data = feeDocs[index];
                    final tsMs = (data['createdAtMs'] as num?)?.toInt() ?? 0;
                    final ts = tsMs == 0
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(tsMs);
                    final heroId = data['heroId'] as String? ?? '';
                    final heroName = data['heroName'] as String?;
                    final amount = (data['amount'] as num?)?.toDouble() ?? 0;
                    final activeMinutes = (data['activeMinutes'] as num?)?.toDouble();
                    final ridesHandled = (data['ridesHandled'] as num?)?.toInt();
                    final balanceAfter = (data['balanceAfter'] as num?)?.toDouble();
                    return Container(
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: _red.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: const Icon(Icons.bolt_rounded, color: _red, size: 20),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  (heroName?.trim().isNotEmpty ?? false)
                                      ? heroName!.trim()
                                      : 'Hero $heroId',
                                  style: GoogleFonts.outfit(
                                      color: _text, fontWeight: FontWeight.w700),
                                ),
                                const SizedBox(height: 3),
                                Text(
                                  [
                                    if (ts != null)
                                      '${ts.day}/${ts.month}/${ts.year} • '
                                          '${ts.hour}:${ts.minute.toString().padLeft(2, '0')}',
                                    if (ridesHandled != null && ridesHandled > 0)
                                      '$ridesHandled task${ridesHandled == 1 ? '' : 's'}',
                                    if (activeMinutes != null && activeMinutes > 0)
                                      '${activeMinutes.toStringAsFixed(0)} min online',
                                  ].join(' • '),
                                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                                ),
                                if (balanceAfter != null) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    'Wallet balance after: ₹${balanceAfter.toStringAsFixed(2)}',
                                    style: GoogleFonts.outfit(
                                      color: balanceAfter < 0 ? _red : _muted,
                                      fontSize: 10.5,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                          Text(
                            '-₹${amount.toStringAsFixed(2)}',
                            style: GoogleFonts.outfit(
                                color: _gold, fontWeight: FontWeight.w800),
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
