// ================================================================
// hero_earnings_screen.dart — Hero Earnings & Online Time Monitor
// ================================================================
// NEW (Aug 11 2026, per Nizam — Business Analytics & Dynamic Billing
// Upgrade, Tasks 4/5). Shows a hero their own Total Earnings and Total
// Online Time, with Today/This Month/Custom Date filters.
//
// ── QUOTA ARCHITECTURE (read before changing anything here) ──
// Same fetch-on-demand contract as the admin analytics screens built
// earlier this session: no live .snapshots() listener, ever. On open
// this renders the last Hive-cached snapshot; Firestore is touched
// only on an explicit Fetch tap — and per Nizam's explicit spec, that
// tap ALSO deducts a small micro-fee from the hero's wallet
// (HeroWalletService.chargeMonitorRefreshFee()) to cover the read
// cost, exactly the same "activity = cost" philosophy as the infra
// usage fee.
//
// ── WHY THE QUERIES ARE SHAPED THIS WAY (audited before writing this) ──
// wallet_transactions is a SHARED top-level collection also written by
// the customer coin ledger (wallet_service.dart, field `createdAt`)
// and customer fare debits (payment_screen.dart, field `createdAt`,
// `userId`) — hero-earning docs use DIFFERENT field names (`timestamp`,
// `heroId`; see hero_ride_screen.dart:1133-1146 / payment_screen.dart
// :328-335). Filtering on `heroId` (not present on customer docs at
// all) keeps this query from ever touching those unrelated docs.
//
// Both queries here use a SINGLE equality filter only (`heroId ==
// uid`), no `.orderBy()`/range filter combined with it, and a bounded
// `.limit(500)` — this deliberately avoids needing a new Firestore
// composite index (per Nizam's approved plan), matching the exact
// pattern usage_fee_ledger_screen.dart already uses for the same
// reason. The Today/This Month/Custom date filter is applied
// CLIENT-SIDE over the already-fetched rows, so switching the filter
// chip costs zero extra reads.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/hero_wallet_service.dart';
import '../../widgets/admin/cached_analytics_view.dart';

const Color _bg = Color(0xFFFFF7FB);
const Color _card = Colors.white;
const Color _pink = Color(0xFFFF4FA3);
const Color _text = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF8F5A78);
const Color _green = Color(0xFF00C853);

enum _DateMode { today, thisMonth, custom }

class HeroEarningsScreen extends StatefulWidget {
  const HeroEarningsScreen({super.key});

  @override
  State<HeroEarningsScreen> createState() => _HeroEarningsScreenState();
}

class _HeroEarningsScreenState extends State<HeroEarningsScreen> {
  _DateMode _mode = _DateMode.today;
  DateTime _customStart = DateTime.now().subtract(const Duration(days: 7));
  DateTime _customEnd = DateTime.now();

  ({DateTime from, DateTime to}) get _window {
    final now = DateTime.now();
    switch (_mode) {
      case _DateMode.today:
        final start = DateTime(now.year, now.month, now.day);
        return (from: start, to: start.add(const Duration(days: 1)));
      case _DateMode.thisMonth:
        final start = DateTime(now.year, now.month);
        return (from: start, to: DateTime(now.year, now.month + 1));
      case _DateMode.custom:
        final start =
            DateTime(_customStart.year, _customStart.month, _customStart.day);
        final end = DateTime(_customEnd.year, _customEnd.month, _customEnd.day)
            .add(const Duration(days: 1));
        return (from: start, to: end);
    }
  }

  String get _windowLabel {
    switch (_mode) {
      case _DateMode.today:
        return 'Today';
      case _DateMode.thisMonth:
        return 'This month';
      case _DateMode.custom:
        return '${_fmtDate(_customStart)} → ${_fmtDate(_customEnd)}';
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ── Fetch (ONLY runs on an explicit Fetch tap) ─────────────────
  Future<Map<String, dynamic>> _fetch() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return {'earnings': <dynamic>[], 'sessions': <dynamic>[]};

    // FIX (per Nizam's spec — "deduct a minimal micro-fee for the
    // server read cost" on every manual Fetch tap): non-fatal by
    // design, wrapped separately so a fee-charge hiccup never blocks
    // the hero from seeing their own data.
    try {
      await HeroWalletService().chargeMonitorRefreshFee(uid);
    } catch (e) {
      debugPrint('[HeroEarningsScreen] Monitor refresh fee charge failed (non-fatal): $e');
    }

    final earningsSnap = await FirebaseFirestore.instance
        .collection('wallet_transactions')
        .where('heroId', isEqualTo: uid)
        .limit(500)
        .get();
    final earnings = earningsSnap.docs.map((doc) {
      final d = doc.data();
      final ts = d['timestamp'];
      return <String, dynamic>{
        'amount': (d['amount'] as num?)?.toDouble() ?? 0.0,
        'type': d['type'] as String? ?? '',
        'timestampMs': ts is Timestamp ? ts.millisecondsSinceEpoch : null,
      };
    }).toList();

    final sessionsSnap = await FirebaseFirestore.instance
        .collection('hero_sessions')
        .where('heroId', isEqualTo: uid)
        .limit(500)
        .get();
    final sessions = sessionsSnap.docs.map((doc) {
      final d = doc.data();
      final ts = d['startedAt'];
      return <String, dynamic>{
        'durationMinutes': (d['durationMinutes'] as num?)?.toDouble() ?? 0.0,
        'startedAtMs': ts is Timestamp ? ts.millisecondsSinceEpoch : null,
      };
    }).toList();

    return {'earnings': earnings, 'sessions': sessions};
  }

  List<Map<String, dynamic>> _rowsOf(dynamic raw) =>
      (raw as List).map((e) => Map<String, dynamic>.from(e as Map)).toList();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Earnings & Online Time',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w800,
            fontSize: 18,
          ),
        ),
      ),
      // Deliberately NOT keyed by the date window (unlike
      // service_flow_monitor_screen.dart) — one Fetch pulls this
      // hero's full recent history once, and every date chip below
      // just re-filters the SAME cached rows client-side, so there's
      // no reason to force a remount/reload per chip tap.
      body: CachedAnalyticsView<Map<String, dynamic>>(
        cacheKey: 'hero_earnings_monitor',
        fetch: _fetch,
        emptyMessage: 'No data loaded yet. Tap Fetch to load '
            '(a small fee applies per fetch).',
        extraActions: [_buildDateControls()],
        builder: (context, data) {
          final earnings =
              _rowsOf(data['earnings'] ?? const []).where((r) {
            final ms = r['timestampMs'] as int?;
            if (ms == null) return false;
            final t = DateTime.fromMillisecondsSinceEpoch(ms);
            return !t.isBefore(_window.from) && t.isBefore(_window.to);
          }).toList();
          final sessions =
              _rowsOf(data['sessions'] ?? const []).where((r) {
            final ms = r['startedAtMs'] as int?;
            if (ms == null) return false;
            final t = DateTime.fromMillisecondsSinceEpoch(ms);
            return !t.isBefore(_window.from) && t.isBefore(_window.to);
          }).toList();

          final totalEarnings = earnings
              .where((r) => (r['amount'] as double? ?? 0) > 0)
              .fold<double>(0, (sum, r) => sum + (r['amount'] as double? ?? 0));
          final totalOnlineMinutes = sessions.fold<double>(
              0, (sum, r) => sum + (r['durationMinutes'] as double? ?? 0));

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              Row(
                children: [
                  Expanded(
                    child: _statCard(
                      label: 'Total Earnings',
                      value: '₹${totalEarnings.toStringAsFixed(2)}',
                      color: _green,
                      icon: Icons.payments_rounded,
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: _statCard(
                      label: 'Online Time',
                      value: _fmtDuration(totalOnlineMinutes),
                      color: _pink,
                      icon: Icons.timer_rounded,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              Text(
                'RECENT EARNINGS (${earnings.length})',
                style: GoogleFonts.outfit(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              if (earnings.isEmpty)
                Text('Nothing in this window.',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12))
              else
                for (final r in earnings.take(50)) _earningRow(r),
            ],
          );
        },
      ),
    );
  }

  static String _fmtDuration(double minutes) {
    final totalMin = minutes.round();
    final h = totalMin ~/ 60;
    final m = totalMin % 60;
    if (h == 0) return '${m}m';
    return '${h}h ${m}m';
  }

  Widget _statCard({
    required String label,
    required String value,
    required Color color,
    required IconData icon,
  }) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: color.withValues(alpha: 0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: color, size: 22),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 20,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.outfit(color: _muted, fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _earningRow(Map<String, dynamic> r) {
    final amount = (r['amount'] as double?) ?? 0;
    final ms = r['timestampMs'] as int?;
    final when = ms == null
        ? '—'
        : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms))
            .format(context);
    final positive = amount > 0;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(color: _pink.withValues(alpha: 0.12)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(
              positive ? 'Ride/task earning' : 'Wallet debit',
              style: GoogleFonts.outfit(color: _text, fontSize: 12.5),
            ),
          ),
          Text(when, style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
          const SizedBox(width: 10),
          Text(
            '${positive ? '+' : ''}₹${amount.toStringAsFixed(2)}',
            style: GoogleFonts.outfit(
              color: positive ? _green : _muted,
              fontWeight: FontWeight.w800,
              fontSize: 12.5,
            ),
          ),
        ],
      ),
    );
  }

  // ── Date controls ───────────────────────────────────────────────
  Widget _buildDateControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _modeChip(_DateMode.today, 'Today'),
              _modeChip(_DateMode.thisMonth, 'This month'),
              _modeChip(_DateMode.custom, 'Custom range'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Showing: $_windowLabel',
          style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _modeChip(_DateMode mode, String label) {
    final selected = _mode == mode;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: () => _onModeTap(mode),
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            color: selected ? _pink : _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
              color: selected ? _pink : _muted.withValues(alpha: 0.3),
            ),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: selected ? Colors.white : _muted,
              fontWeight: FontWeight.w700,
              fontSize: 12.5,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onModeTap(_DateMode mode) async {
    if (mode == _DateMode.custom) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2025),
        lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _customStart, end: _customEnd),
      );
      if (picked == null) return;
      setState(() {
        _mode = mode;
        _customStart = picked.start;
        _customEnd = picked.end;
      });
      return;
    }
    setState(() => _mode = mode);
  }
}
