// ================================================================
// SellerEarningsScreen — Earnings, Profit & Wallet Ledger
// Allin1 Super App — Seller-Earnings Audit, Phase 2
// ================================================================
// Reads sellers/{sellerId} directly (live) for the three metric cards
// and sellers/{sellerId}/wallet_transactions (the immutable ledger
// written atomically alongside every walletBalance/pendingPayouts
// mutation by ServiceRequestService — see advanceSellerStage() and
// _completeAndCreditSeller()) for the passbook below it. Nothing here
// writes anything — this screen is read-only by design, since the
// whole point of Phase 1's rules hardening was to make the wallet
// fields un-writable from a normal client write in the first place.

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../models/food_models.dart';
import '../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFFF7FAF8);
const Color _card = Color(0xFFFFFFFF);
const Color _teal = Color(0xFF11998E);
const Color _text = Color(0xFF1A1A1A);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0x1A11998E);
const Color _green = Color(0xFF2E9E63);
const Color _red = Color(0xFFD64545);
const Color _gold = Color(0xFFC79200);
const Color _orange = Color(0xFFE07A00);

class SellerEarningsScreen extends StatefulWidget {
  const SellerEarningsScreen({required this.seller, super.key});

  final SellerModel seller;

  @override
  State<SellerEarningsScreen> createState() => _SellerEarningsScreenState();
}

class _SellerEarningsScreenState extends State<SellerEarningsScreen> {
  static const int _pageSize = 20;

  final List<QueryDocumentSnapshot<Map<String, dynamic>>> _olderTxns = [];
  bool _loadingMore = false;
  bool _hasMore = true;

  // FIX (regression audit — "Pagination UI Jank & Read Cost Leak"): both
  // streams used to be constructed INLINE inside build()/_buildLedger(),
  // i.e. re-created on every rebuild. `.snapshots()` returns a brand-new
  // Stream object every time it's called, and StreamBuilder compares its
  // `stream:` parameter by identity in didUpdateWidget — a "new" stream
  // (even one querying the exact same data) is torn down and
  // re-subscribed from scratch. That happened on every unrelated
  // rebuild: _loadMore()'s own setState() (ironically, triggered by
  // tapping "Load older"), any wallet-field update landing on the
  // metrics stream, anything else touching this State. Each
  // resubscription re-fires the initial `.limit(20)` read batch — a
  // real, wasted Firestore read against the same zero-cost budget this
  // whole engagement protects, plus a visible flash back to the loading
  // spinner.
  //
  // Fix: both streams are now created exactly ONCE, in initState(), and
  // held in `late final` fields. build()/_buildLedger() reference these
  // fields directly rather than calling .snapshots() themselves, so
  // their object identity never changes across a normal rebuild —
  // StreamBuilder correctly treats it as "the same stream" and just
  // keeps its existing subscription, appending whatever _loadMore()
  // adds to `_olderTxns` without touching the live top-20 subscription
  // at all.
  late final Stream<DocumentSnapshot<Map<String, dynamic>>> _sellerStream;
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _ledgerStream;

  CollectionReference<Map<String, dynamic>> get _ledgerRef =>
      FirebaseFirestore.instance
          .collection('sellers')
          .doc(widget.seller.id)
          .collection('wallet_transactions');

  @override
  void initState() {
    super.initState();
    _initStreams();
  }

  void _initStreams() {
    _sellerStream = FirebaseFirestore.instance
        .collection('sellers')
        .doc(widget.seller.id)
        .trackedSnapshots();
    _ledgerStream = _ledgerRef
        .orderBy('createdAt', descending: true)
        .limit(_pageSize)
        .trackedSnapshots();
  }

  Future<void> _loadMore(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> liveDocs,
  ) async {
    if (_loadingMore || !_hasMore) return;
    setState(() => _loadingMore = true);
    try {
      // Cursor is whichever doc is currently the OLDEST one on screen —
      // the live top-page's last doc on the very first "Load older" tap,
      // or the last doc of the previously-appended page on every tap
      // after that.
      final cursor = _olderTxns.isNotEmpty
          ? _olderTxns.last
          : (liveDocs.isNotEmpty ? liveDocs.last : null);
      if (cursor == null) {
        setState(() => _hasMore = false);
        return;
      }
      final snap = await _ledgerRef
          .orderBy('createdAt', descending: true)
          .startAfterDocument(cursor)
          .limit(_pageSize)
          .get();
      if (!mounted) return;
      // NOTE: this setState only ever mutates _olderTxns/_hasMore —
      // never _ledgerStream/_sellerStream — so the StreamBuilders below
      // keep the exact same stream object across this rebuild and never
      // resubscribe. This is the crux of the fix: pagination growing the
      // list must never be able to touch the live subscription's identity.
      setState(() {
        _olderTxns.addAll(snap.docs);
        _hasMore = snap.docs.length == _pageSize;
      });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Could not load more transactions: $e'),
            backgroundColor: _red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _loadingMore = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          'Earnings & Wallet',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w600, color: _text),
        ),
        backgroundColor: _card,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
      ),
      // Metrics cards are driven by a live doc snapshot (not the
      // `widget.seller` snapshot the screen was opened with) so a
      // credit/debit landing while this screen is open updates the
      // numbers immediately — no pull-to-refresh needed to see them.
      // `_sellerStream` is the hoisted, initState()-created stream — see
      // its field comment for why that matters.
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: _sellerStream,
        builder: (context, sellerSnap) {
          final sellerData = sellerSnap.data?.data();
          final pending = (sellerData?['pendingPayouts'] as num?)?.toDouble() ??
              widget.seller.pendingPayouts;
          final settled = (sellerData?['totalSettled'] as num?)?.toDouble() ??
              widget.seller.totalSettled;
          final fees = (sellerData?['totalFeesDeducted'] as num?)?.toDouble() ??
              widget.seller.totalFeesDeducted;

          return RefreshIndicator(
            color: _teal,
            // Only clears the LOCAL pagination state ("Load older" results
            // collapse back to just the live top-20) — deliberately does
            // NOT touch _sellerStream/_ledgerStream. The metrics card and
            // the top-20 ledger entries are already always live via their
            // stream subscriptions; a pull-to-refresh doesn't need to (and
            // must not) tear those down and re-read them to "do something"
            // — clearing the appended older pages is the only stale state
            // this screen actually has.
            onRefresh: () async {
              setState(() {
                _olderTxns.clear();
                _hasMore = true;
              });
            },
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildMetricsRow(pending, settled, fees),
                  const SizedBox(height: 24),
                  Text(
                    'Transaction History',
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _text,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Every credit and debit to your wallet, most recent first.',
                    style: GoogleFonts.outfit(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 12),
                  _buildLedger(),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildMetricsRow(double pending, double settled, double fees) {
    return Row(
      children: [
        _metricCard(
          label: 'Pending Payouts',
          sublabel: 'Money owed to you',
          amount: pending,
          color: _orange,
          icon: Icons.hourglass_top_rounded,
        ),
        const SizedBox(width: 10),
        _metricCard(
          label: 'Total Settled',
          sublabel: 'Lifetime paid out',
          amount: settled,
          color: _green,
          icon: Icons.account_balance_wallet_outlined,
        ),
        const SizedBox(width: 10),
        _metricCard(
          label: 'Platform Fees',
          sublabel: 'Lifetime deducted',
          amount: fees,
          color: _red,
          icon: Icons.receipt_long_outlined,
          amountPrefix: '-',
        ),
      ],
    );
  }

  Widget _metricCard({
    required String label,
    required String sublabel,
    required double amount,
    required Color color,
    required IconData icon,
    String amountPrefix = '',
  }) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: color, size: 20),
            const SizedBox(height: 10),
            Text(
              '$amountPrefix₹${amount.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(
                fontSize: 15,
                fontWeight: FontWeight.w800,
                color: _text,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: _text,
              ),
            ),
            Text(
              sublabel,
              style: GoogleFonts.outfit(fontSize: 9.5, color: _muted),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLedger() {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _ledgerStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return _ledgerMessage(
            Icons.error_outline_rounded,
            'Could not load your transaction history.',
            _red,
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(
              child: CircularProgressIndicator(color: _teal, strokeWidth: 2.5),
            ),
          );
        }

        final liveDocs = snapshot.data?.docs ?? [];
        if (liveDocs.isEmpty && _olderTxns.isEmpty) {
          return _ledgerMessage(
            Icons.receipt_long_outlined,
            'No transactions yet — this fills up as orders come in.',
            _muted,
          );
        }

        final allDocs = [...liveDocs, ..._olderTxns];

        return Column(
          children: [
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: allDocs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 8),
              itemBuilder: (context, i) => _buildLedgerTile(allDocs[i].data()),
            ),
            const SizedBox(height: 12),
            if (_hasMore)
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: _loadingMore ? null : () => _loadMore(liveDocs),
                  icon: _loadingMore
                      ? const SizedBox(
                          width: 14,
                          height: 14,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _teal,
                          ),
                        )
                      : const Icon(Icons.expand_more_rounded, size: 18, color: _teal),
                  label: Text(
                    _loadingMore ? 'Loading…' : 'Load older transactions',
                    style: GoogleFonts.outfit(color: _teal, fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _ledgerMessage(IconData icon, String text, Color color) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 36, horizontal: 20),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        children: [
          Icon(icon, size: 36, color: color.withValues(alpha: 0.6)),
          const SizedBox(height: 10),
          Text(
            text,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: _muted, fontSize: 13),
          ),
        ],
      ),
    );
  }

  Widget _buildLedgerTile(Map<String, dynamic> data) {
    final type = data['type'] as String? ?? '';
    final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
    final requestId = data['requestId'] as String? ?? '';
    final shortId = requestId.length > 8
        ? requestId.substring(0, 8).toUpperCase()
        : requestId.toUpperCase();
    final createdAt = data['createdAt'];
    final dateLabel = createdAt is Timestamp
        ? DateFormat('dd MMM, hh:mm a').format(createdAt.toDate())
        : 'Just now';

    final isCredit = type == 'order_credit';
    final chipColor = isCredit ? _green : (type == 'platform_fee' ? _red : _gold);
    final title = isCredit
        ? 'Order payment received'
        : type == 'platform_fee'
            ? 'Platform usage fee'
            : type;
    final amountLabel =
        '${amount >= 0 ? '+' : '-'}₹${amount.abs().toStringAsFixed(2)}';

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              isCredit ? Icons.arrow_downward_rounded : Icons.arrow_upward_rounded,
              color: chipColor,
              size: 16,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontWeight: FontWeight.w600,
                    fontSize: 13,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  requestId.isNotEmpty ? 'Order #$shortId • $dateLabel' : dateLabel,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: chipColor.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              amountLabel,
              style: GoogleFonts.outfit(
                color: chipColor,
                fontWeight: FontWeight.w800,
                fontSize: 12,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
