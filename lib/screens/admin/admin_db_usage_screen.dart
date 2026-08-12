// ================================================================
// AdminDbUsageScreen — per-app Firestore usage monitor ("DB Monitor")
// ================================================================
// Per Nizam's request after a ~1k reads/hr spike showed up in the
// Firebase project-wide Usage tab: "app admina app kulla database
// yepdi reads use pannithu... admin app la oru database usage
// monitoration pannanum" — since Firebase's own Usage tab has no
// per-app breakdown (and Cloud Functions/BigQuery export aren't
// available on this project's Spark plan), this reads the
// db_usage_stats collection that DbUsageTracker (lib/services/
// db_usage_tracker.dart) writes to from each of the 4 apps
// (customer/hero/admin/seller), showing reads+writes per app.
//
// UPDATE (per Nizam's request): the old version only supported
// 1/7/30-day rollups, which matches Firebase's own console (which
// offers Last 60 min / Last 24 hours / a specific day). DbUsageTracker
// now writes one doc per HOUR bucket (not per day) with a sortable
// `dateHour` field ("yyyy-MM-dd_HH"), so this screen can run a single
// range query on that one field (isGreaterThanOrEqualTo + isLessThan
// OrEqualTo — both on the SAME field, so no composite index needed)
// instead of fetching the entire collection and filtering client-side.
// This keeps the monitor itself cheap even as history piles up over
// months — the exact thing Nizam asked for: don't let the monitoring
// system become its own source of database load.
//
// Same "manual Generate, no live listener" design as
// AdminUsageBillingScreen / AdminLocationDemandScreen — this is a
// periodic diagnostic report, not something that needs to update
// live.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/hive_cache.dart';

// ── Firebase Spark (free) plan daily ceilings ──────────────────────
// Hardcoded because they're a property of the PLAN, not of our data —
// there is no API that reports remaining quota, so the only way to give
// the admin real visibility (Nizam's "100% visibility into our Spark
// plan limits") is to compare our own tracked counts against the
// published limits. Update these if we ever move to Blaze.
const int kSparkDailyReads = 50000;
const int kSparkDailyWrites = 20000;

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _pink = Color(0xFFFF4FA3);
const Color _pinkLight = Color(0xFFFF92C8);
const Color _gold = Color(0xFFF5C542);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

enum _RangeType { last60Min, last24Hours, today, last7Days, last30Days, pickDay }

class AdminDbUsageScreen extends StatefulWidget {
  const AdminDbUsageScreen({super.key});

  @override
  State<AdminDbUsageScreen> createState() => _AdminDbUsageScreenState();
}

// 'all' shows every app's rows side by side (existing behaviour);
// picking a specific app filters down to just that one.
const List<String> _kAppFilterOptions = ['all', 'customer', 'hero', 'admin', 'seller'];

class _AdminDbUsageScreenState extends State<AdminDbUsageScreen> {
  _RangeType _range = _RangeType.last24Hours;
  DateTime _pickedDay = DateTime.now();
  String _selectedApp = 'all';
  bool _isLoading = false;
  bool _hasGenerated = false;
  List<_AppUsageRow> _rows = [];
  int _totalReads = 0;
  int _totalWrites = 0;
  String _rangeCaption = '';
  DateTime? _lastFetchedAt;
  /// Ranked "which screen burned the most reads/writes" lists — the
  /// actionable half of this report.
  ///
  /// UPGRADED (Aug 12 2026 — Nizam: "high read/write volumes but cannot
  /// pinpoint exactly which specific queries or actions are causing
  /// them"): each entry now also carries a per-action breakdown (see
  /// DbUsageTracker's new 'screen::action' composite key), so a screen
  /// with several listeners no longer collapses into one indistinguishable
  /// number — you can expand a screen and see exactly which query is the
  /// runaway one. Writes get the same breakdown now too — previously
  /// screenWrites was tracked by DbUsageTracker but never read by this
  /// screen at all.
  List<_ScreenUsageEntry> _topScreensReads = <_ScreenUsageEntry>[];
  List<_ScreenUsageEntry> _topScreensWrites = <_ScreenUsageEntry>[];

  static const String _cacheKey = 'admin_db_usage_report';

  @override
  void initState() {
    super.initState();
    // Hive ONLY — deliberately no Firestore read on open, per the
    // fetch-on-demand architecture. Restores the last generated report so
    // reopening this screen costs nothing.
    _restoreCachedReport();
  }

  Future<void> _restoreCachedReport() async {
    final cached = await HiveCache.get<Map>(_cacheKey);
    if (cached == null || !mounted) return;
    final rows = (cached['rows'] as List?)
            ?.map((e) => Map<String, dynamic>.from(e as Map))
            .map((m) => _AppUsageRow(
                  app: m['app'] as String? ?? '',
                  reads: (m['reads'] as num?)?.toInt() ?? 0,
                  writes: (m['writes'] as num?)?.toInt() ?? 0,
                ),)
            .toList() ??
        <_AppUsageRow>[];
    setState(() {
      _rows = rows;
      _totalReads = (cached['totalReads'] as num?)?.toInt() ?? 0;
      _totalWrites = (cached['totalWrites'] as num?)?.toInt() ?? 0;
      _rangeCaption = cached['caption'] as String? ?? '';
      _hasGenerated = rows.isNotEmpty;
      _topScreensReads = _decodeScreenEntries(cached['topScreensReads']);
      _topScreensWrites = _decodeScreenEntries(cached['topScreensWrites']);
      final ms = (cached['fetchedAtMs'] as num?)?.toInt();
      _lastFetchedAt =
          ms == null ? null : DateTime.fromMillisecondsSinceEpoch(ms);
    });
  }

  static List<_ScreenUsageEntry> _decodeScreenEntries(Object? raw) {
    if (raw is! List) return <_ScreenUsageEntry>[];
    return raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .map((m) => _ScreenUsageEntry(
              screenKey: m['screenKey'] as String? ?? '',
              actions: (Map<String, dynamic>.from(m['actions'] as Map? ?? const {}))
                  .map((k, v) => MapEntry(k, (v as num?)?.toInt() ?? 0)),
            ))
        .toList();
  }

  Future<void> _persistReport(String caption) async {
    await HiveCache.put(
      _cacheKey,
      <String, dynamic>{
        'rows': _rows
            .map((r) => <String, dynamic>{
                  'app': r.app,
                  'reads': r.reads,
                  'writes': r.writes,
                })
            .toList(),
        'totalReads': _totalReads,
        'totalWrites': _totalWrites,
        'caption': caption,
        'topScreensReads': _topScreensReads
            .map((e) => <String, dynamic>{'screenKey': e.screenKey, 'actions': e.actions})
            .toList(),
        'topScreensWrites': _topScreensWrites
            .map((e) => <String, dynamic>{'screenKey': e.screenKey, 'actions': e.actions})
            .toList(),
        'fetchedAtMs': DateTime.now().millisecondsSinceEpoch,
      },
      ttl: const Duration(days: 7),
    );
  }

  String _hourKey(DateTime dt) {
    final y = dt.year.toString().padLeft(4, '0');
    final m = dt.month.toString().padLeft(2, '0');
    final d = dt.day.toString().padLeft(2, '0');
    final h = dt.hour.toString().padLeft(2, '0');
    return '$y-$m-${d}_$h';
  }

  (String start, String end, String caption) _computeRangeKeys() {
    final now = DateTime.now();
    switch (_range) {
      case _RangeType.last60Min:
        return (
          _hourKey(now.subtract(const Duration(minutes: 60))),
          _hourKey(now),
          'Approx. last 60 minutes (rounded to hour buckets)',
        );
      case _RangeType.last24Hours:
        return (
          _hourKey(now.subtract(const Duration(hours: 24))),
          _hourKey(now),
          'Last 24 hours',
        );
      case _RangeType.today:
        final midnight = DateTime(now.year, now.month, now.day);
        return (_hourKey(midnight), _hourKey(now), 'Today so far');
      case _RangeType.last7Days:
        return (
          _hourKey(now.subtract(const Duration(days: 7))),
          _hourKey(now),
          'Last 7 days',
        );
      case _RangeType.last30Days:
        return (
          _hourKey(now.subtract(const Duration(days: 30))),
          _hourKey(now),
          'Last 30 days',
        );
      case _RangeType.pickDay:
        final y = _pickedDay.year.toString().padLeft(4, '0');
        final m = _pickedDay.month.toString().padLeft(2, '0');
        final d = _pickedDay.day.toString().padLeft(2, '0');
        return (
          '$y-$m-${d}_00',
          '$y-$m-${d}_23',
          '${_pickedDay.day}/${_pickedDay.month}/${_pickedDay.year}',
        );
    }
  }

  Future<void> _generate() async {
    setState(() => _isLoading = true);
    try {
      final (startKey, endKey, caption) = _computeRangeKeys();

      // Single range query on ONE field (dateHour) — only two
      // inequalities on the same field, which Firestore's default
      // single-field index already covers, no composite index needed.
      // This only fetches the hour-bucket docs that actually fall in
      // the requested window, across all 4 apps, instead of the whole
      // db_usage_stats collection — the monitor stays cheap forever.
      //
      // NOTE on the app filter (customer/hero/admin/seller/all): we do
      // NOT add a second `.where('app', isEqualTo: ...)` clause to this
      // query — an equality filter on `app` combined with the range
      // filter on `dateHour` (a DIFFERENT field) would need a brand-new
      // Firestore composite index, exactly the same "requires an index"
      // crash we hit and fixed earlier in usage_billing_service.dart.
      // Instead we keep the ONE query exactly as before (still zero
      // extra reads — same doc count either way) and filter down to the
      // selected app client-side below, after the docs are already in
      // memory. Picking an app in the dropdown costs nothing extra.
      final snapshot = await FirebaseFirestore.instance
          .collection('db_usage_stats')
          .where('dateHour', isGreaterThanOrEqualTo: startKey)
          .where('dateHour', isLessThanOrEqualTo: endKey)
          .get();

      final perApp = <String, _AppUsageRow>{};
      // UPGRADED (Aug 12 2026 — deep granularity): keyed "app · screen",
      // each value is now a Map<action, count> instead of a flat count —
      // DbUsageTracker's new 'screen::action' composite key (see
      // db_usage_tracker.dart) is split back apart here so a screen with
      // several distinct queries/listeners shows each one separately
      // instead of one merged number. A read/write with no action
      // component lands under 'generic'. Writes get the exact same
      // treatment as reads now — previously screenWrites was tracked but
      // never surfaced in this UI at all.
      final perScreenReads = <String, Map<String, int>>{};
      final perScreenWrites = <String, Map<String, int>>{};
      var totalReads = 0;
      var totalWrites = 0;

      void accumulate(Map<String, Map<String, int>> target, String app, Object? raw) {
        if (raw is! Map) return;
        raw.forEach((rawKey, value) {
          final n = (value as num?)?.toInt() ?? 0;
          if (n <= 0) return;
          final parts = (rawKey as String).split('::');
          final screen = parts.first;
          final action = parts.length > 1 ? parts.sublist(1).join('::') : 'generic';
          final key = '$app · $screen';
          final bucket = target.putIfAbsent(key, () => <String, int>{});
          bucket[action] = (bucket[action] ?? 0) + n;
        });
      }

      for (final doc in snapshot.docs) {
        final data = doc.data();
        final app = data['app'] as String?;
        if (app == null) continue;
        if (_selectedApp != 'all' && app != _selectedApp) continue;

        final reads = (data['reads'] as num?)?.toInt() ?? 0;
        final writes = (data['writes'] as num?)?.toInt() ?? 0;

        final existing = perApp[app];
        if (existing == null) {
          perApp[app] = _AppUsageRow(app: app, reads: reads, writes: writes);
        } else {
          perApp[app] = _AppUsageRow(
            app: app,
            reads: existing.reads + reads,
            writes: existing.writes + writes,
          );
        }
        totalReads += reads;
        totalWrites += writes;

        accumulate(perScreenReads, app, data['screenReads']);
        accumulate(perScreenWrites, app, data['screenWrites']);
      }

      final rows = perApp.values.toList()
        ..sort((a, b) => (b.reads + b.writes).compareTo(a.reads + a.writes));

      List<_ScreenUsageEntry> rankEntries(Map<String, Map<String, int>> src) {
        final entries = src.entries
            .map((e) => _ScreenUsageEntry(screenKey: e.key, actions: e.value))
            .toList()
          ..sort((a, b) => b.total.compareTo(a.total));
        return entries.take(12).toList();
      }

      if (mounted) {
        setState(() {
          _rows = rows;
          _topScreensReads = rankEntries(perScreenReads);
          _topScreensWrites = rankEntries(perScreenWrites);
          _totalReads = totalReads;
          _totalWrites = totalWrites;
          _hasGenerated = true;
          _rangeCaption = caption;
          _lastFetchedAt = DateTime.now();
        });
        // Persist so reopening this screen shows the last report from
        // Hive instead of re-querying Firestore.
        await _persistReport(caption);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load usage report: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDay(BuildContext context) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _pickedDay,
      firstDate: DateTime(2025),
      lastDate: DateTime.now(),
    );
    if (picked != null) {
      setState(() {
        _pickedDay = picked;
        _range = _RangeType.pickDay;
        _hasGenerated = false;
      });
    }
  }

  String _rangeLabel(_RangeType r) {
    switch (r) {
      case _RangeType.last60Min:
        return 'Last 60 minutes';
      case _RangeType.last24Hours:
        return 'Last 24 hours';
      case _RangeType.today:
        return 'Today';
      case _RangeType.last7Days:
        return 'Last 7 days';
      case _RangeType.last30Days:
        return 'Last 30 days';
      case _RangeType.pickDay:
        return 'Pick a day (${_pickedDay.day}/${_pickedDay.month}/${_pickedDay.year})';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Text(
          'DB Monitor',
          // FIX (UI standardization, Aug 11 2026): explicit 18sp,
          // matching the app-bar title convention app-wide.
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Approximate Firestore reads/writes per app (customer, hero, '
              'admin, seller) — helps spot which app is driving usage. This '
              'only counts instrumented hotspots, not every SDK call, so '
              'treat it as a trend indicator, not an exact total.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            DropdownButtonFormField<String>(
              initialValue: _selectedApp,
              dropdownColor: _card,
              decoration: InputDecoration(
                filled: true,
                fillColor: _card,
                prefixIcon: const Icon(Icons.apps_outlined, color: _muted, size: 18),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14),
              ),
              items: _kAppFilterOptions
                  .map((a) => DropdownMenuItem(
                        value: a,
                        child: Text(
                          a == 'all' ? 'All apps' : _labelFor(a),
                          style: GoogleFonts.outfit(color: _text),
                        ),
                      ),)
                  .toList(),
              onChanged: (v) {
                if (v == null) return;
                setState(() {
                  _selectedApp = v;
                  _hasGenerated = false;
                });
              },
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<_RangeType>(
                    initialValue: _range,
                    dropdownColor: _card,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    items: _RangeType.values
                        .map((r) => DropdownMenuItem(
                              value: r,
                              child: Text(_rangeLabel(r),
                                  style: GoogleFonts.outfit(color: _text),),
                            ),)
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      if (v == _RangeType.pickDay) {
                        _pickDay(context);
                        return;
                      }
                      setState(() {
                        _range = v;
                        _hasGenerated = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isLoading ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,),
                        )
                      : const Text('Generate',
                          style: TextStyle(color: Colors.white),),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_hasGenerated && !_isLoading)
              Expanded(
                child: Center(
                  child: Text(
                    'Pick a range and tap Generate to see\n'
                    'per-app Firestore usage.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                  ),
                ),
              ),
            if (_hasGenerated) ...[
              Text(
                _rangeCaption,
                style: GoogleFonts.outfit(color: _pinkLight, fontSize: 12, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 4),
              Text(
                '$_totalReads reads · $_totalWrites writes across ${_rows.length} app(s)'
                '${_lastFetchedAt == null ? '' : '  ·  fetched ${_lastFetchedAt!.hour.toString().padLeft(2, '0')}:${_lastFetchedAt!.minute.toString().padLeft(2, '0')}'}',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              _sparkQuotaPanel(),
              const SizedBox(height: 10),
              if (_topScreensReads.isNotEmpty) ...[
                _screenBreakdownPanel(
                  title: 'Heaviest screens (reads)',
                  icon: Icons.bug_report_rounded,
                  entries: _topScreensReads,
                ),
                const SizedBox(height: 10),
              ],
              if (_topScreensWrites.isNotEmpty) ...[
                _screenBreakdownPanel(
                  title: 'Heaviest screens (writes)',
                  icon: Icons.edit_note_rounded,
                  entries: _topScreensWrites,
                ),
                const SizedBox(height: 10),
              ],
              Expanded(
                child: _rows.isEmpty
                    ? Center(
                        child: Text(
                          'No usage data logged in this range yet.',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (context, i) => _appTile(_rows[i]),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  /// Spark-plan headroom (Nizam's request: "100% visibility into our
  /// Spark plan limits").
  ///
  /// Only meaningful for a ONE-DAY window, since the published limits are
  /// per-day — so this hides itself for multi-day ranges rather than
  /// showing a percentage that compares (say) a week of reads against a
  /// single day's ceiling, which would look alarming and be wrong.
  ///
  /// IMPORTANT CAVEAT, stated in the UI too: these bars measure OUR OWN
  /// instrumented counters (DbUsageTracker.recordRead/recordWrite), not
  /// Firebase's authoritative billing meter. Any read path we forgot to
  /// instrument won't show up here. It's an early-warning indicator; the
  /// Firebase console stays the source of truth. A monitor that silently
  /// under-reports is worse than none, so the admin should know which
  /// number to trust when the two disagree.
  Widget _sparkQuotaPanel() {
    final isSingleDay = _range == _RangeType.last60Min ||
        _range == _RangeType.last24Hours ||
        _range == _RangeType.pickDay ||
        _range == _RangeType.today;
    if (!isSingleDay) return const SizedBox.shrink();

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
          Row(
            children: [
              const Icon(Icons.speed_rounded, color: _gold, size: 18),
              const SizedBox(width: 8),
              Text(
                'Spark free-tier headroom (per day)',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _quotaBar('Reads', _totalReads, kSparkDailyReads),
          const SizedBox(height: 10),
          _quotaBar('Writes', _totalWrites, kSparkDailyWrites),
          const SizedBox(height: 10),
          Text(
            'Measured from our own in-app counters, not Firebase billing. '
            'Un-instrumented reads are not included — treat this as an '
            'early warning and confirm in the Firebase console.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  Widget _quotaBar(String label, int used, int limit) {
    final fraction = limit == 0 ? 0.0 : (used / limit).clamp(0.0, 1.0);
    final pct = (fraction * 100);
    // Green under half, amber approaching, red once genuinely at risk —
    // on Spark, hitting the ceiling means the app STOPS SERVING until the
    // midnight-Pacific reset, so 80% deserves real visual urgency.
    final Color barColor = pct >= 80
        ? const Color(0xFFFF5252)
        : (pct >= 50 ? _gold : const Color(0xFF00C853));
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(
              label,
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 12, fontWeight: FontWeight.w700),
            ),
            Text(
              '$used / $limit  (${pct.toStringAsFixed(1)}%)',
              style: GoogleFonts.outfit(color: barColor, fontSize: 11.5,
                  fontWeight: FontWeight.w700,),
            ),
          ],
        ),
        const SizedBox(height: 5),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: fraction,
            minHeight: 7,
            color: barColor,
            backgroundColor: barColor.withValues(alpha: 0.15),
          ),
        ),
      ],
    );
  }

  // NEW (Aug 12 2026 — deep DB analytics): each row here is now
  // expandable — tapping it reveals exactly which query/action on that
  // screen is driving the number, instead of one opaque total. Deep
  // granularity is the whole point of this task ("hunt down and
  // optimize runaway queries"), so surfacing the per-action list is the
  // actual deliverable, not a nice-to-have.
  Widget _screenBreakdownPanel({
    required String title,
    required IconData icon,
    required List<_ScreenUsageEntry> entries,
  }) {
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
          Row(
            children: [
              Icon(icon, color: _pink, size: 18),
              const SizedBox(width: 8),
              Text(
                title,
                style: GoogleFonts.outfit(
                  color: _text,
                  fontWeight: FontWeight.w800,
                  fontSize: 13,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Tap a screen to see which action/query is driving it. '
            '"unattributed" = code paths not yet passing a screen name; '
            '"generic" = a screen name was passed but no specific action.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
          ),
          const SizedBox(height: 6),
          ...entries.map((e) => Theme(
                data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                child: ExpansionTile(
                  tilePadding: EdgeInsets.zero,
                  childrenPadding: const EdgeInsets.only(left: 14, bottom: 8),
                  iconColor: _muted,
                  collapsedIconColor: _muted,
                  title: Row(
                    children: [
                      Expanded(
                        child: Text(
                          e.screenKey,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(color: _text, fontSize: 12),
                        ),
                      ),
                      Text(
                        '${e.total}',
                        style: GoogleFonts.outfit(
                          color: _gold,
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                  children: (e.actions.entries.toList()
                        ..sort((a, b) => b.value.compareTo(a.value)))
                      .map((a) => Padding(
                            padding: const EdgeInsets.only(bottom: 4),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Text(
                                    a.key,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                                  ),
                                ),
                                Text(
                                  '${a.value}',
                                  style: GoogleFonts.outfit(
                                      color: _pinkLight, fontSize: 11.5, fontWeight: FontWeight.w700),
                                ),
                              ],
                            ),
                          ))
                      .toList(),
                ),
              )),
        ],
      ),
    );
  }

  Widget _appTile(_AppUsageRow row) {
    final total = row.reads + row.writes;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Icon(_iconFor(row.app), color: _gold, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              _labelFor(row.app),
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 14, fontWeight: FontWeight.w600,),
            ),
          ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                '$total total',
                style: GoogleFonts.outfit(
                    color: _pinkLight, fontSize: 13, fontWeight: FontWeight.w700,),
              ),
              Text(
                '${row.reads} reads · ${row.writes} writes',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              ),
            ],
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String app) {
    switch (app) {
      case 'customer':
        return Icons.shopping_bag_outlined;
      case 'hero':
        return Icons.two_wheeler_outlined;
      case 'admin':
        return Icons.admin_panel_settings_outlined;
      case 'seller':
        return Icons.storefront_outlined;
      default:
        return Icons.apps_outlined;
    }
  }

  String _labelFor(String app) {
    switch (app) {
      case 'customer':
        return 'Customer App';
      case 'hero':
        return 'Hero App';
      case 'admin':
        return 'Admin App';
      case 'seller':
        return 'Seller App';
      default:
        return app;
    }
  }
}

class _AppUsageRow {
  final String app;
  final int reads;
  final int writes;
  const _AppUsageRow({required this.app, required this.reads, required this.writes});
}

// NEW (Aug 12 2026 — deep DB analytics): one "app · screen" bucket with
// its per-action breakdown intact, instead of a single flattened count.
class _ScreenUsageEntry {
  final String screenKey;
  final Map<String, int> actions;
  const _ScreenUsageEntry({required this.screenKey, required this.actions});
  int get total => actions.values.fold(0, (a, b) => a + b);
}
