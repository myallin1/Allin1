// ================================================================
// bug_reports_screen.dart — Admin: AI Bug Report Queue
// ================================================================
// Built per Nizam's request (Aug 11 2026) as the admin-side half of the
// AI Bug Reporting feature. The customer app's AI agent files reports
// into `app_bug_reports` (see guru_chat_screen.dart's _actOnReportBug);
// this is where they get read and triaged.
//
// ARCHITECTURE: fetch-on-demand via CachedAnalyticsView, same as every
// other admin analytics screen — the last fetched queue renders from
// Hive on open, and Firestore is only touched when the admin taps
// Fetch. A live listener here would be a particularly bad idea: bug
// reports arrive unpredictably, so a stream left open on a busy day
// would bill continuously for data the admin isn't looking at.
//
// FILTERING is client-side over the fetched snapshot (severity +
// status), so changing filters costs ZERO extra reads and needs no
// Firestore composite index — the same reasoning as payments_received
// and usage_fee_ledger.
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
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

class BugReportsScreen extends StatefulWidget {
  const BugReportsScreen({super.key});

  @override
  State<BugReportsScreen> createState() => _BugReportsScreenState();
}

class _BugReportsScreenState extends State<BugReportsScreen> {
  /// null = all severities.
  String? _severity;
  /// Defaults to showing only open reports — that's the actionable
  /// queue. Resolved ones are one tap away but shouldn't be the noise
  /// an admin wades through first.
  bool _showResolved = false;

  Future<List<dynamic>> _fetchReports() async {
    // Single-field orderBy only — no composite index required.
    final snap = await FirebaseFirestore.instance
        .collection('app_bug_reports')
        .orderBy('createdAt', descending: true)
        .limit(300)
        .trackedGet();
    DbUsageTracker.instance.recordRead(snap.docs.length, 'bug_reports', 'fetch_reports');
    // Flattened to Hive-serializable primitives (Timestamps are not).
    return snap.docs.map((d) {
      final data = d.data();
      return <String, dynamic>{
        'id': d.id,
        'summary': data['summary'] ?? '',
        'details': data['details'] ?? '',
        'screen': data['screen'] ?? '',
        'severity': (data['severity'] as String?) ?? 'medium',
        'status': (data['status'] as String?) ?? 'open',
        'platform': data['platform'] ?? '',
        'appVersion': data['appVersion'] ?? '',
        'reportedBy': data['reportedBy'] ?? '',
        'reporterName': data['reporterName'] ?? '',
        'source': data['source'] ?? '',
        'createdAtMs':
            (data['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0,
      };
    }).toList();
  }

  static Color _severityColor(String s) => switch (s) {
        'high' => _red,
        'low' => _muted,
        _ => _gold,
      };

  Future<void> _setResolved(Map<String, dynamic> report, bool resolved) async {
    final id = report['id'] as String? ?? '';
    if (id.isEmpty) return;
    try {
      await FirebaseFirestore.instance
          .collection('app_bug_reports')
          .doc(id)
          .trackedUpdate({
        'status': resolved ? 'resolved' : 'open',
        'resolvedAt': resolved ? FieldValue.serverTimestamp() : null,
      });
      // Optimistic local update — there's no live listener to echo the
      // change back, by design.
      if (mounted) {
        setState(() => report['status'] = resolved ? 'resolved' : 'open');
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not update: $e'), backgroundColor: _red),
      );
    }
  }

  void _showDetail(Map<String, dynamic> r) {
    final ms = (r['createdAtMs'] as num?)?.toInt() ?? 0;
    final ts = ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.92,
        builder: (ctx, scrollCtrl) => SingleChildScrollView(
          controller: scrollCtrl,
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                r['summary']?.toString() ?? '',
                style: GoogleFonts.outfit(
                    color: _text, fontWeight: FontWeight.w800, fontSize: 17),
              ),
              const SizedBox(height: 14),
              _kv('What the customer said', r['details']?.toString() ?? '—'),
              _kv('Screen', (r['screen'] as String?)?.isNotEmpty ?? false
                  ? r['screen'].toString()
                  : 'not specified',),
              _kv('Severity', (r['severity'] ?? '').toString().toUpperCase()),
              _kv('Status', (r['status'] ?? '').toString().toUpperCase()),
              const Divider(color: _muted, height: 28),
              // Diagnostic block — the context the customer could never
              // be expected to give, attached automatically at file time.
              _kv('Platform', r['platform']?.toString() ?? '—'),
              _kv('App version', r['appVersion']?.toString() ?? '—'),
              _kv('Reported by',
                  (r['reporterName'] as String?)?.isNotEmpty ?? false
                      ? '${r['reporterName']} (${r['reportedBy']})'
                      : (r['reportedBy']?.toString() ?? '—'),),
              _kv('Source', r['source']?.toString() ?? '—'),
              _kv(
                'Reported at',
                ts == null
                    ? '—'
                    : '${ts.day}/${ts.month}/${ts.year} '
                        '${ts.hour.toString().padLeft(2, '0')}:'
                        '${ts.minute.toString().padLeft(2, '0')}',
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  style: ElevatedButton.styleFrom(
                    backgroundColor:
                        r['status'] == 'resolved' ? _muted : _green,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),),
                  ),
                  onPressed: () {
                    _setResolved(r, r['status'] != 'resolved');
                    Navigator.pop(ctx);
                  },
                  icon: Icon(r['status'] == 'resolved'
                      ? Icons.undo_rounded
                      : Icons.check_circle_rounded,),
                  label: Text(r['status'] == 'resolved'
                      ? 'Reopen this bug'
                      : 'Mark as Resolved',),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _kv(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(k,
                style: GoogleFonts.outfit(
                    color: _muted, fontSize: 10.5, fontWeight: FontWeight.w700),),
            const SizedBox(height: 2),
            Text(v,
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 13, height: 1.35),),
          ],
        ),
      );

  Widget _filterChip(String label, bool selected, VoidCallback onTap,
      {Color? accent,}) {
    final c = accent ?? _green;
    return Padding(
      padding: const EdgeInsets.only(right: 7),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 7),
          decoration: BoxDecoration(
            color: selected ? c : _card,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(
                color: selected ? c : _muted.withValues(alpha: 0.3),),
          ),
          child: Text(
            label,
            style: GoogleFonts.outfit(
              color: selected ? Colors.white : _muted,
              fontWeight: FontWeight.w700,
              fontSize: 12,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'Bug Reports',
          // FIX (UI standardization, Aug 11 2026): explicit 18sp,
          // matching the app-bar title convention app-wide.
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 18),
        ),
      ),
      body: CachedAnalyticsView<List<dynamic>>(
        cacheKey: 'admin_bug_reports',
        fetch: _fetchReports,
        emptyMessage: 'No bug reports loaded yet.',
        extraActions: [
          Expanded(
            child: SizedBox(
              height: 32,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  _filterChip('All', _severity == null,
                      () => setState(() => _severity = null),),
                  _filterChip('High', _severity == 'high',
                      () => setState(() => _severity = 'high'), accent: _red,),
                  _filterChip('Medium', _severity == 'medium',
                      () => setState(() => _severity = 'medium'), accent: _gold,),
                  _filterChip('Low', _severity == 'low',
                      () => setState(() => _severity = 'low'), accent: _muted,),
                  const SizedBox(width: 10),
                  _filterChip(
                    _showResolved ? 'Showing resolved' : 'Open only',
                    _showResolved,
                    () => setState(() => _showResolved = !_showResolved),
                  ),
                ],
              ),
            ),
          ),
        ],
        builder: (context, raw) {
          final reports = raw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((r) {
            if (_severity != null && r['severity'] != _severity) return false;
            final isResolved = r['status'] == 'resolved';
            return _showResolved ? isResolved : !isResolved;
          }).toList();

          if (reports.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  _showResolved
                      ? 'No resolved reports match this filter.'
                      : 'No open bug reports. ',
                  style: GoogleFonts.outfit(color: _muted),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final openHigh = raw
              .map((e) => Map<String, dynamic>.from(e as Map))
              .where((r) => r['severity'] == 'high' && r['status'] != 'resolved')
              .length;

          return Column(
            children: [
              Container(
                margin: const EdgeInsets.all(14),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      '${reports.length} shown',
                      style: GoogleFonts.outfit(
                          color: _muted, fontWeight: FontWeight.w600),
                    ),
                    Text(
                      '$openHigh high-severity open',
                      style: GoogleFonts.outfit(
                        color: openHigh > 0 ? _red : _green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                  itemCount: reports.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    final r = reports[i];
                    final sev = (r['severity'] ?? 'medium').toString();
                    final ms = (r['createdAtMs'] as num?)?.toInt() ?? 0;
                    final ts = ms == 0
                        ? null
                        : DateTime.fromMillisecondsSinceEpoch(ms);
                    return InkWell(
                      onTap: () => _showDetail(r),
                      borderRadius: BorderRadius.circular(12),
                      child: Container(
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: _severityColor(sev).withValues(alpha: 0.45),
                          ),
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 8,
                              height: 42,
                              decoration: BoxDecoration(
                                color: _severityColor(sev),
                                borderRadius: BorderRadius.circular(4),
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    r['summary']?.toString() ?? '',
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(
                                        color: _text,
                                        fontWeight: FontWeight.w700,
                                        fontSize: 13.5,),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    [
                                      sev.toUpperCase(),
                                      if ((r['screen'] as String?)?.isNotEmpty ??
                                          false)
                                        r['screen'].toString(),
                                      if (ts != null)
                                        '${ts.day}/${ts.month} '
                                            '${ts.hour.toString().padLeft(2, '0')}:'
                                            '${ts.minute.toString().padLeft(2, '0')}',
                                    ].join('  •  '),
                                    style: GoogleFonts.outfit(
                                        color: _muted, fontSize: 10.5),
                                  ),
                                ],
                              ),
                            ),
                            const Icon(Icons.chevron_right_rounded,
                                color: _muted,),
                          ],
                        ),
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
