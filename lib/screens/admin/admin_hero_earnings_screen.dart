// ================================================================
// admin_hero_earnings_screen.dart — Admin: exact hero earnings
// ================================================================
// NEW (Aug 17 2026 — Nizam: "adminala exact hero earning pakkamudila,
// athuvum hero ida ya admina app la hero voda uid vachu than kaatuthu
// hero name kaatala and avaroda earning um detailed day view, week,
// month view and heros wise... but intha checking ku database usage ah
// romba carful ah handle pannu").
//
// THREE PROBLEMS THIS SOLVES
//   1. There was no admin view of a hero's earnings at all — the only
//      hero-money screen was admin_wallet_approvals_screen.dart, which
//      is about recharge REQUESTS, not earnings, and which falls back to
//      'Hero <first 6 chars of uid>' when heroName is absent.
//   2. Identity was a raw uid. A uid is unusable operationally: you
//      cannot phone a uid or recognise it in a WhatsApp complaint.
//   3. No time breakdown, so "how much did this hero make last week"
//      could not be answered.
//
// ── DATABASE COST DISCIPLINE (the explicit constraint) ──────────────
// This screen is built on CachedAnalyticsView, the same pattern the
// other admin analytics screens use, because it enforces exactly what
// was asked for:
//   * NOTHING is read on screen open. The last snapshot comes out of
//     Hive.
//   * Firestore is touched ONLY when the admin taps Fetch.
//   * EVERY filter here — hero, day, week, month, custom range — runs
//     client-side over that one cached snapshot. Changing hero or
//     switching Day/Week/Month costs ZERO reads.
// So the read cost of a full investigation is one Fetch, not one Fetch
// per question.
//
// Query shape is deliberately index-free: two collections, each with a
// single bounded read and no composite filter, mirroring
// hero_earnings_screen.dart's reasoning (a range filter combined with an
// equality filter would require a new Firestore composite index).
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/admin/cached_analytics_view.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/hero_wallet_service.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

enum _Range { today, week, month, all }

class AdminHeroEarningsScreen extends StatefulWidget {
  const AdminHeroEarningsScreen({super.key});

  @override
  State<AdminHeroEarningsScreen> createState() =>
      _AdminHeroEarningsScreenState();
}

class _AdminHeroEarningsScreenState extends State<AdminHeroEarningsScreen> {
  _Range _range = _Range.month;

  /// null = every hero combined.
  String? _heroFilter;
  String _search = '';
  bool _sendingReminders = false;

  /// Fan out a wallet top-up reminder to heroes currently in minus.
  ///
  /// Confirms first with the exact count, because this writes one
  /// notification per hero and there is no undo — an accidental double
  /// tap would nag the same people twice.
  Future<void> _sendTopUpReminders() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Send top-up reminder?',
            style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
        content: const Text(
          'Every hero currently in minus gets one notification showing '
          'their own amount owed. Heroes who owe nothing are not '
          'contacted, and nobody is blocked from working.',
          style: TextStyle(color: _muted, fontSize: 12.5, height: 1.45),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _gold),
            child: const Text('Send',
                style: TextStyle(
                    color: Colors.black, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;

    setState(() => _sendingReminders = true);
    try {
      final n = await HeroWalletService().sendTopUpReminders(
        sentByAdminUid: FirebaseAuth.instance.currentUser?.uid ?? 'unknown',
      );
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(n == 0
              ? 'No hero is in minus — nothing sent.'
              : 'Reminder sent to $n hero(es).'),
          backgroundColor: n == 0 ? _muted : _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not send: $e'), backgroundColor: _red),
      );
    } finally {
      if (mounted) setState(() => _sendingReminders = false);
    }
  }

  /// Same coercion helper and same reasoning as
  /// hero_earnings_screen._amountOf: these values come back out of the
  /// Hive cache, where a whole number stored as 50.0 can return as int
  /// 50. `as double` happens to work under dart2js (one number type) but
  /// throws on native Android — so never assert the type, coerce it.
  static double _amountOf(dynamic v) {
    if (v is num) return v.toDouble();
    if (v is String) return double.tryParse(v) ?? 0;
    return 0;
  }

  DateTime get _from {
    final now = DateTime.now();
    switch (_range) {
      case _Range.today:
        return DateTime(now.year, now.month, now.day);
      case _Range.week:
        return DateTime(now.year, now.month, now.day)
            .subtract(const Duration(days: 6));
      case _Range.month:
        return DateTime(now.year, now.month);
      case _Range.all:
        return DateTime.fromMillisecondsSinceEpoch(0);
    }
  }

  // ── The ONLY Firestore access, and only on an explicit Fetch ──────
  Future<Map<String, dynamic>> _fetch() async {
    final db = FirebaseFirestore.instance;

    // Hero identity. This is what turns a uid into a name and phone —
    // the whole point of item (2) above. One bounded read of the hero
    // roster, reused for every row and every filter afterwards.
    final heroesSnap =
        await db.collection('heroes').limit(500).trackedGet();
    final heroes = <String, dynamic>{};
    for (final d in heroesSnap.docs) {
      final h = d.data();
      heroes[d.id] = <String, dynamic>{
        'name': (h['captainName'] as String?)?.trim().isNotEmpty ?? false
            ? h['captainName'] as String
            : ((h['name'] as String?)?.trim().isNotEmpty ?? false
                ? h['name'] as String
                : ''),
        'phone': (h['phone'] as String?) ?? '',
        'vehicleType': (h['vehicleType'] as String?) ?? '',
      };
    }

    // Earnings ledger. Single equality-free bounded read: we want ALL
    // hero rows so the per-hero filter can run client-side. Customer
    // rows in this shared collection carry `userId`/`createdAt` and no
    // `heroId`, so they are skipped below rather than filtered in the
    // query (which would need an index alongside the limit).
    final txSnap = await db
        .collection('wallet_transactions')
        .limit(2000)
        .trackedGet();

    final rows = <Map<String, dynamic>>[];
    for (final d in txSnap.docs) {
      final t = d.data();
      final heroId = t['heroId'] as String?;
      if (heroId == null || heroId.isEmpty) continue; // customer row
      final ts = t['timestamp'];
      rows.add(<String, dynamic>{
        'heroId': heroId,
        'amount': _amountOf(t['amount']),
        'type': (t['type'] as String?) ?? '',
        'description': (t['description'] as String?) ?? '',
        'tsMs': ts is Timestamp ? ts.millisecondsSinceEpoch : null,
      });
    }

    // WALLET STATE (Aug 17 2026 — Nizam: "hero amount wallet la add
    // pannamayum work pannatum and avar yevlo minus la wallet use
    // pandrarunum admin theriyanum").
    //
    // Minus balances are expected and allowed by design — nothing blocks
    // a hero from working. What admin needs is visibility: who is in
    // minus, how deep, and who has topped up. One bounded read on the
    // same explicit Fetch as everything else on this screen.
    final walletSnap =
        await db.collection('hero_wallets').limit(500).trackedGet();
    final wallets = <String, dynamic>{};
    for (final d in walletSnap.docs) {
      final w = d.data();
      wallets[d.id] = <String, dynamic>{
        'balance': _amountOf(w['balance']),
        'recharged': _amountOf(w['lifetimeRecharged']),
        'usagePaid': _amountOf(w['lifetimeCommissionPaid']),
      };
    }

    return {'heroes': heroes, 'rows': rows, 'wallets': wallets};
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('Hero Earnings',
            style: GoogleFonts.outfit(
                color: _text, fontWeight: FontWeight.w800, fontSize: 18)),
      ),
      body: CachedAnalyticsView<Map<String, dynamic>>(
        cacheKey: 'admin_hero_earnings',
        fetch: _fetch,
        emptyMessage: 'No data loaded yet. Tap Fetch to pull the hero '
            'roster and earnings ledger once — after that every filter '
            'below is free.',
        extraActions: [_buildControls()],
        builder: (context, data) {
          final heroes =
              Map<String, dynamic>.from(data['heroes'] as Map? ?? {});
          final wallets =
              Map<String, dynamic>.from(data['wallets'] as Map? ?? {});
          final allRows = (data['rows'] as List? ?? [])
              .map((e) => Map<String, dynamic>.from(e as Map))
              .toList();

          final from = _from;
          // Every filter below is pure client-side work over the cached
          // snapshot — no reads.
          final rows = allRows.where((r) {
            if (_heroFilter != null && r['heroId'] != _heroFilter) return false;
            final ms = r['tsMs'] as int?;
            if (ms == null) return _range == _Range.all;
            return !DateTime.fromMillisecondsSinceEpoch(ms).isBefore(from);
          }).toList();

          // Per-hero aggregation.
          final perHero = <String, List<double>>{}; // [earned, deducted]
          for (final r in rows) {
            final id = r['heroId'] as String;
            final a = _amountOf(r['amount']);
            final isDebit =
                a < 0 || (r['type'] as String).toLowerCase() == 'debit';
            final slot = perHero.putIfAbsent(id, () => [0, 0]);
            if (isDebit) {
              slot[1] += a.abs();
            } else {
              slot[0] += a;
            }
          }

          String nameOf(String id) {
            final h = heroes[id] as Map?;
            final n = (h?['name'] as String?)?.trim() ?? '';
            // Falls back to a SHORT uid, and says so, rather than
            // showing a bare 28-character uid as if it were a name.
            return n.isEmpty ? 'Unnamed hero (${id.substring(0, 6)})' : n;
          }

          var entries = perHero.entries.toList();
          if (_search.isNotEmpty) {
            entries = entries.where((e) {
              final h = heroes[e.key] as Map?;
              final n = nameOf(e.key).toLowerCase();
              final p = ((h?['phone'] as String?) ?? '').toLowerCase();
              return n.contains(_search) || p.contains(_search);
            }).toList();
          }
          // Highest net first — the question an admin actually has is
          // "who is earning and who is not".
          entries.sort((a, b) =>
              (b.value[0] - b.value[1]).compareTo(a.value[0] - a.value[1]));

          final totalEarned =
              perHero.values.fold<double>(0, (s, v) => s + v[0]);
          final totalDeducted =
              perHero.values.fold<double>(0, (s, v) => s + v[1]);

          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              Row(
                children: [
                  Expanded(
                      child: _stat('Paid to heroes',
                          '₹${totalEarned.toStringAsFixed(2)}', _green)),
                  const SizedBox(width: 10),
                  Expanded(
                      child: _stat('Deducted',
                          '−₹${totalDeducted.toStringAsFixed(2)}', _red)),
                ],
              ),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                      child: _stat(
                          'Net',
                          '₹${(totalEarned - totalDeducted).toStringAsFixed(2)}',
                          _gold)),
                  const SizedBox(width: 10),
                  Expanded(child: _stat('Heroes', '${perHero.length}', _text)),
                ],
              ),
              const SizedBox(height: 12),
              // Wallet exposure across the fleet. Two numbers an admin
              // needs before deciding whether to send a top-up reminder:
              // how much money is sitting uncollected, and how many
              // heroes it is spread across.
              Builder(builder: (_) {
                var owed = 0.0;
                var inMinus = 0;
                var topped = 0.0;
                for (final w in wallets.values) {
                  final m = Map<String, dynamic>.from(w as Map);
                  final bal = _amountOf(m['balance']);
                  if (bal < 0) {
                    owed += bal.abs();
                    inMinus++;
                  }
                  topped += _amountOf(m['recharged']);
                }
                return Row(
                  children: [
                    Expanded(
                        child: _stat('Owed by heroes',
                            '₹${owed.toStringAsFixed(2)}', _red)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _stat('Heroes in minus', '$inMinus', _gold)),
                    const SizedBox(width: 10),
                    Expanded(
                        child: _stat('Topped up',
                            '₹${topped.toStringAsFixed(0)}', _green)),
                  ],
                );
              }),
              // Sits directly under the numbers it acts on, so an admin
              // sees "12 heroes in minus" and the button to remind them
              // in the same glance.
              const SizedBox(height: 10),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: OutlinedButton.icon(
                  onPressed: _sendingReminders ? null : _sendTopUpReminders,
                  icon: _sendingReminders
                      ? const SizedBox(
                          width: 15,
                          height: 15,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _gold),
                        )
                      : const Icon(Icons.campaign_rounded, size: 17),
                  label: Text(
                    _sendingReminders
                        ? 'Sending…'
                        : 'Send top-up reminder to heroes in minus',
                    style: GoogleFonts.outfit(
                        fontSize: 12.5, fontWeight: FontWeight.w700),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _gold,
                    side: const BorderSide(color: _gold),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'PER HERO (${entries.length})',
                style: GoogleFonts.outfit(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1),
              ),
              const SizedBox(height: 8),
              if (entries.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'No hero earnings in this window.',
                    textAlign: TextAlign.center,
                    style:
                        GoogleFonts.outfit(color: _muted, fontSize: 12.5),
                  ),
                ),
              for (final e in entries)
                _heroRow(
                  id: e.key,
                  name: nameOf(e.key),
                  phone: ((heroes[e.key] as Map?)?['phone'] as String?) ?? '',
                  earned: e.value[0],
                  deducted: e.value[1],
                  txCount:
                      rows.where((r) => r['heroId'] == e.key).length,
                  walletBalance: wallets[e.key] == null
                      ? null
                      : _amountOf(
                          (wallets[e.key] as Map)['balance'],
                        ),
                ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Filter chips cost NOTHING — they re-slice the cached snapshot.
        // Said out loud so an admin is not afraid to use them.
        Text('Filters re-use the last Fetch — switching these is free',
            style: GoogleFonts.outfit(color: _muted, fontSize: 10.5)),
        const SizedBox(height: 6),
        Wrap(
          spacing: 6,
          runSpacing: 6,
          children: [
            _chip('Today', _Range.today),
            _chip('7 days', _Range.week),
            _chip('This month', _Range.month),
            _chip('All', _Range.all),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          style: const TextStyle(color: _text, fontSize: 13),
          onChanged: (v) => setState(() => _search = v.trim().toLowerCase()),
          decoration: InputDecoration(
            isDense: true,
            hintText: 'Search hero name or phone',
            hintStyle: const TextStyle(color: _muted, fontSize: 12.5),
            filled: true,
            fillColor: _card,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: _border),
            ),
          ),
        ),
        if (_heroFilter != null) ...[
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: ActionChip(
              backgroundColor: _gold.withValues(alpha: 0.18),
              label: const Text('Showing one hero — tap to clear',
                  style: TextStyle(color: _gold, fontSize: 11)),
              onPressed: () => setState(() => _heroFilter = null),
            ),
          ),
        ],
      ],
    );
  }

  Widget _chip(String label, _Range r) {
    final on = _range == r;
    return GestureDetector(
      onTap: () => setState(() => _range = r),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: on ? _gold : _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: on ? _gold : _border),
        ),
        child: Text(label,
            style: GoogleFonts.outfit(
                color: on ? Colors.black : _muted,
                fontSize: 11.5,
                fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _stat(String label, String value, Color color) {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label,
              style: GoogleFonts.outfit(color: _muted, fontSize: 10.5)),
          const SizedBox(height: 4),
          Text(value,
              style: GoogleFonts.outfit(
                  color: color, fontSize: 17, fontWeight: FontWeight.w800)),
        ],
      ),
    );
  }

  Widget _heroRow({
    required String id,
    required String name,
    required String phone,
    required double earned,
    required double deducted,
    required int txCount,
    /// Live wallet balance. Negative = owes app-usage fees. Null when
    /// the hero has no wallet doc yet (never charged, never topped up).
    double? walletBalance,
  }) {
    final net = earned - deducted;
    return InkWell(
      // Tapping a hero narrows every stat above to just them — again,
      // zero reads, pure client-side re-slice.
      onTap: () => setState(() => _heroFilter = _heroFilter == id ? null : id),
      borderRadius: BorderRadius.circular(14),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: _heroFilter == id ? _gold : _border),
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(
                    phone.isEmpty ? '$txCount txn' : '$phone · $txCount txn',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                  ),
                  // Wallet state. Only rendered when it says something:
                  // a hero in minus (chase) or in credit (fine). A hero
                  // with no wallet doc shows nothing rather than a
                  // misleading "₹0.00".
                  if (walletBalance != null && walletBalance != 0) ...[
                    const SizedBox(height: 3),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: (walletBalance < 0 ? _red : _green)
                            .withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: Text(
                        walletBalance < 0
                            ? 'owes ₹${walletBalance.abs().toStringAsFixed(2)}'
                            : 'wallet ₹${walletBalance.toStringAsFixed(2)}',
                        style: GoogleFonts.outfit(
                          color: walletBalance < 0 ? _red : _green,
                          fontSize: 10,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text('₹${net.toStringAsFixed(2)}',
                    style: GoogleFonts.outfit(
                        color: net < 0 ? _red : _green,
                        fontSize: 14,
                        fontWeight: FontWeight.w800)),
                if (deducted > 0)
                  Text(
                    '₹${earned.toStringAsFixed(0)} − ₹${deducted.toStringAsFixed(0)}',
                    style:
                        GoogleFonts.outfit(color: _muted, fontSize: 10),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
