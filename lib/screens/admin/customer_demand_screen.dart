// ================================================================
// customer_demand_screen.dart — Admin: What Customers Actually Want
// ================================================================
// Built per Nizam's request (Aug 11 2026): "customer athigama search
// panni pora place, athigama order podura hotel names, athigama use
// pandra transport vehicles" — surface real customer demand so the
// business can put supply (heroes, vendor tie-ups, vehicle mix) where
// the demand actually is, instead of guessing.
//
// COST DESIGN — this is why it reads ONE document, on demand only:
// every counter lives as a nested map inside
// app_usage_stats/customer_demand (written by UsageTrackingService's
// atomic FieldValue.increment calls). So this entire screen — all four
// ranked lists, however many thousands of events they represent —
// costs exactly ONE document read, and stays at one read forever as
// volume grows. On the Spark plan (50K reads/day) that matters: a
// naive "query all bookings and count them client-side" version of
// this screen would cost one read PER BOOKING every time an admin
// opened it, and could plausibly burn the whole daily quota alone.
//
// Ranking/sorting is done client-side on the already-fetched map,
// which needs no Firestore index and no extra reads.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/db_usage_tracker.dart';
import '../../services/usage_tracking_service.dart';
import '../../widgets/admin/cached_analytics_view.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _cyan = Color(0xFF00B8D4);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

class CustomerDemandScreen extends StatefulWidget {
  const CustomerDemandScreen({super.key});

  @override
  State<CustomerDemandScreen> createState() => _CustomerDemandScreenState();
}

class _CustomerDemandScreenState extends State<CustomerDemandScreen> {
  bool _backfilling = false;

  /// One document read per Fetch tap — see CachedAnalyticsView.
  Future<Map<String, dynamic>> _fetchDemand() async {
    final snap = await FirebaseFirestore.instance
        .collection('app_usage_stats')
        .doc('customer_demand')
        .get();
    // Report this read so the DB Usage Monitor stays accurate — an
    // un-instrumented read is invisible there, which would make the
    // Spark-headroom bars under-report.
    DbUsageTracker.instance.recordRead(1, 'customer_demand', 'fetch_demand');
    final data = snap.data() ?? <String, dynamic>{};
    // Strip non-counter fields and flatten to plain maps so the snapshot
    // is Hive-serializable (Timestamps are not).
    return <String, dynamic>{
      for (final k in ['places', 'hotels', 'vehicles', 'services'])
        if (data[k] is Map)
          k: Map<String, dynamic>.from(data[k] as Map)
              .map((key, v) => MapEntry(key, (v as num?)?.toInt() ?? 0)),
    };
  }

  Future<void> _runBackfill() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Rebuild from history?',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800)),
        content: Text(
          'This scans your existing rides and service requests ONCE and '
          'seeds the demand counters from them.\n\n'
          'It is the only read-heavy action in this screen (roughly one '
          'read per historical booking), so it is meant to be run once. '
          'After that, new bookings update the counts automatically.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _green),
            child: const Text('Run backfill'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _backfilling = true);
    try {
      final result = await UsageTrackingService.instance.backfillFromHistory();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(result.message),
          backgroundColor: result.skipped ? _gold : _green,
          duration: const Duration(seconds: 6),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Backfill failed: $e'), backgroundColor: _red),
      );
    } finally {
      if (mounted) setState(() => _backfilling = false);
    }
  }

  /// Turns a `{key: count}` map into a descending-ranked list.
  /// Defensive about types: counts arrive from Firestore as `num`, and a
  /// malformed/legacy entry should be skipped rather than crash the
  /// whole screen.
  static List<MapEntry<String, int>> _ranked(Object? raw) {
    if (raw is! Map) return const [];
    final entries = <MapEntry<String, int>>[];
    raw.forEach((key, value) {
      if (key is! String) return;
      final count = (value as num?)?.toInt();
      if (count == null || count <= 0) return;
      entries.add(MapEntry(key, count));
    });
    entries.sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }

  static String _titleCase(String s) => s
      .split(' ')
      .where((w) => w.isNotEmpty)
      .map((w) => w[0].toUpperCase() + w.substring(1))
      .join(' ');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'Customer Demand',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
      ),
      // FETCH-ON-DEMAND (Nizam's architecture instruction, Aug 11 2026):
      // was a live .snapshots() listener that re-read on every change for
      // as long as the screen stayed open. Now renders the last fetched
      // snapshot from Hive on open and only touches Firestore when the
      // admin taps Fetch — see CachedAnalyticsView for the full rationale.
      body: CachedAnalyticsView<Map<String, dynamic>>(
        cacheKey: 'admin_customer_demand',
        fetch: _fetchDemand,
        emptyMessage: 'No demand data loaded yet.',
        extraActions: [
          Expanded(
            child: OutlinedButton.icon(
              onPressed: _backfilling ? null : _runBackfill,
              style: OutlinedButton.styleFrom(
                foregroundColor: _gold,
                side: const BorderSide(color: _gold),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              icon: _backfilling
                  ? const SizedBox(
                      width: 14,
                      height: 14,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: _gold),
                    )
                  : const Icon(Icons.history_rounded, size: 16),
              label: Text(
                _backfilling ? 'Rebuilding…' : 'Rebuild from history (once)',
                style: const TextStyle(fontSize: 12),
              ),
            ),
          ),
        ],
        builder: (context, data) {
          final places = _ranked(data['places']);
          final hotels = _ranked(data['hotels']);
          final vehicles = _ranked(data['vehicles']);
          final services = _ranked(data['services']);

          if (places.isEmpty &&
              hotels.isEmpty &&
              vehicles.isEmpty &&
              services.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.insights_rounded, color: _muted, size: 48),
                    const SizedBox(height: 14),
                    Text(
                      'No demand data yet.',
                      style: GoogleFonts.outfit(
                          color: _text, fontWeight: FontWeight.w700, fontSize: 16),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      'New bookings update these counts automatically. '
                      'To include your EXISTING ride and order history, tap '
                      '"Rebuild from history" above — that scans past records '
                      'once and seeds the counters from them.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            );
          }

          return ListView(
            padding: const EdgeInsets.all(14),
            children: [
              _section(
                title: 'Most Requested Places',
                subtitle: 'Where customers are travelling to and from',
                icon: Icons.place_rounded,
                accent: _cyan,
                entries: places,
              ),
              _section(
                title: 'Most Ordered From',
                subtitle: 'Hotels / stores customers order from most',
                icon: Icons.storefront_rounded,
                accent: _gold,
                entries: hotels,
              ),
              _section(
                title: 'Most Used Vehicles',
                subtitle: 'Which transport types customers actually book',
                icon: Icons.two_wheeler_rounded,
                accent: _green,
                entries: vehicles,
              ),
              _section(
                title: 'Most Used Services',
                subtitle: 'Taxi vs food vs grocery vs hero booking',
                icon: Icons.apps_rounded,
                accent: _purple,
                entries: services,
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _section({
    required String title,
    required String subtitle,
    required IconData icon,
    required Color accent,
    required List<MapEntry<String, int>> entries,
  }) {
    if (entries.isEmpty) return const SizedBox.shrink();
    // Top 10 keeps the screen readable; the underlying doc holds them all.
    final top = entries.take(10).toList();
    final maxCount = top.first.value;
    final total = entries.fold<int>(0, (sum, e) => sum + e.value);

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: accent, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                          color: _text, fontWeight: FontWeight.w800, fontSize: 15),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Text(
                '$total',
                style: GoogleFonts.outfit(
                    color: accent, fontWeight: FontWeight.w900, fontSize: 18),
              ),
            ],
          ),
          const SizedBox(height: 14),
          ...top.map((e) {
            final fraction = maxCount == 0 ? 0.0 : e.value / maxCount;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          _titleCase(e.key),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                              color: _text,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '${e.value}',
                        style: GoogleFonts.outfit(
                            color: _muted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: LinearProgressIndicator(
                      value: fraction,
                      minHeight: 6,
                      color: accent,
                      backgroundColor: accent.withValues(alpha: 0.12),
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }
}
