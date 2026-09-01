// ================================================================
// MobileStatusTab — "Order & Service Status"
// ================================================================
// Everything the customer has going with the Mobile Hub in one list:
// purchase enquiries, repair bookings, and sell-your-phone enquiries.
//
// All three are 'electronics_service' requests carrying
// details.category == 'mobile', so this is ONE equality-filtered query
// (customerId + requestType) with a client-side category filter — no
// composite index, no second query, no new collection.
//
// One-shot .get() with pull-to-refresh rather than a live listener:
// a customer checking status doesn't need sub-second updates, and the
// per-request tracking screen (which they open to actually watch
// progress) already attaches a live listener for the one request they
// care about.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/db_usage_tracker.dart';
import '../service_request_tracking_screen.dart';
import 'mobile_hub_screen.dart';

class MobileStatusTab extends StatefulWidget {
  const MobileStatusTab({super.key});

  @override
  State<MobileStatusTab> createState() => _MobileStatusTabState();
}

class _MobileStatusTabState extends State<MobileStatusTab>
    with AutomaticKeepAliveClientMixin {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _docs = const [];
  bool _loading = true;
  String? _error;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() {
          _loading = false;
          _docs = const [];
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }

    try {
      // Equality filters only, no orderBy — avoids needing a composite
      // index (same convention as streamCustomerRequests). Sorted below.
      final snap = await FirebaseFirestore.instance
          .collection('service_requests')
          .where('customerId', isEqualTo: user.uid)
          .where('requestType', isEqualTo: 'electronics_service')
          .get();

      DbUsageTracker.instance
          .recordRead(snap.docs.length, 'mobile_hub', 'my_status');

      // Keep only the Mobile Hub's own requests — an NJ Tech Store
      // laptop/TV booking is also 'electronics_service' and belongs in
      // that screen's status tab, not here.
      final mobileDocs = snap.docs.where((d) {
        final details = d.data()['details'];
        if (details is! Map) return false;
        return details['category'] == 'mobile';
      }).toList();

      mobileDocs.sort((a, b) {
        final at = a.data()['createdAt'];
        final bt = b.data()['createdAt'];
        if (at is! Timestamp && bt is! Timestamp) return 0;
        if (at is! Timestamp) return 1;
        if (bt is! Timestamp) return -1;
        return bt.compareTo(at);
      });

      if (!mounted) return;
      setState(() {
        _docs = mobileDocs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Could not load your orders. Pull down to retry.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        MobileHubHeader(
          title: 'Order & Service Status',
          subtitle: 'Your purchases, repairs and sell enquiries',
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kMobPink, strokeWidth: 2),
      );
    }

    if (FirebaseAuth.instance.currentUser == null) {
      return _emptyState(
        Icons.lock_outline_rounded,
        'Sign in to see your mobile orders and repairs.',
      );
    }

    if (_docs.isEmpty) {
      return RefreshIndicator(
        color: kMobPink,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 60),
            _emptyState(
              _error != null
                  ? Icons.cloud_off_rounded
                  : Icons.receipt_long_rounded,
              _error ??
                  'Nothing here yet.\nYour phone orders and repairs will show up here.',
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: kMobPink,
      onRefresh: _load,
      child: ListView.builder(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        itemCount: _docs.length,
        itemBuilder: (context, i) => _buildCard(_docs[i]),
      ),
    );
  }

  Widget _emptyState(IconData icon, String message) {
    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Icon(icon, color: kMobMuted, size: 54),
        const SizedBox(height: 14),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 40),
          child: Text(
            message,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: kMobMuted, fontSize: 13),
          ),
        ),
      ],
    );
  }

  Widget _buildCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final details =
        (data['details'] is Map) ? data['details'] as Map : const {};
    final intent = (details['intent'] as String?) ?? '';
    final status = (data['status'] as String?) ?? 'pending';
    final ts = data['createdAt'];
    final when = ts is Timestamp
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : '';

    final meta = _intentMeta(intent);
    final statusColor = _statusColor(status);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => ServiceRequestTrackingScreen(
              requestId: doc.id,
              requestType: 'electronics_service',
            ),
          ),
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: kMobBg,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kMobBorder),
          ),
          child: Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: meta.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(meta.icon, color: meta.color, size: 21),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      meta.label,
                      style: GoogleFonts.outfit(
                        color: kMobText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      (details['phoneModel'] as String?)?.trim().isNotEmpty ==
                              true
                          ? details['phoneModel'] as String
                          : ((details['issue'] as String?) ?? '')
                              .split('\n')
                              .first,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          GoogleFonts.outfit(color: kMobMuted, fontSize: 11.5),
                    ),
                    if (when.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        when,
                        style:
                            GoogleFonts.outfit(color: kMobMuted, fontSize: 10),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  _statusLabel(status),
                  style: GoogleFonts.outfit(
                    color: statusColor,
                    fontSize: 9.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  _IntentMeta _intentMeta(String intent) {
    switch (intent) {
      case 'buy_new_mobile':
        return const _IntentMeta(
            'New phone purchase', Icons.smartphone_rounded, kMobPink);
      case 'buy_used_mobile':
        return const _IntentMeta(
            'Used phone purchase', Icons.autorenew_rounded, kMobBlue);
      case 'sell_used_mobile':
        return const _IntentMeta(
            'Sell your phone', Icons.sell_rounded, kMobGold);
      case 'mobile_repair':
        return const _IntentMeta(
            'Mobile repair', Icons.build_circle_outlined, kMobGreen);
      default:
        return const _IntentMeta(
            'Mobile request', Icons.smartphone_rounded, kMobMuted);
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return kMobGreen;
      case 'cancelled':
        return kMobRed;
      case 'pending':
      case 'admin_review':
        return kMobGold;
      default:
        return kMobBlue;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'pending':
        return 'PENDING';
      case 'admin_review':
        return 'IN REVIEW';
      case 'hero_assigned':
        return 'ASSIGNED';
      case 'in_progress':
        return 'IN PROGRESS';
      case 'nearing_completion':
        return 'ALMOST DONE';
      case 'completed':
        return 'COMPLETED';
      case 'cancelled':
        return 'CANCELLED';
      default:
        return status.toUpperCase().replaceAll('_', ' ');
    }
  }
}

class _IntentMeta {
  final String label;
  final IconData icon;
  final Color color;
  const _IntentMeta(this.label, this.icon, this.color);
}
