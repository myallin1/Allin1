// ================================================================
// cached_analytics_view.dart — Admin analytics: fetch-on-demand shell
// ================================================================
// Built per Nizam's explicit architecture instruction (Aug 11 2026):
//
//   "continuous database usage panni live stream la ... vendam ... screen
//    mela fetch nu oru button vachalam ... app open pannumbothulam intha
//    analytics kaga poi database ah read panite irukakudathu ... lasta
//    namma fetch panni paatha detail namma admin ku show aganum app oda
//    hive cache la irunthu ... fetch button tap pannuna apo than
//    uptodate analytics fetch aganum"
//
// i.e. analytics screens must NEVER read Firestore just because a screen
// was opened. They render the LAST FETCHED snapshot out of Hive, and only
// go to the network when the admin explicitly taps Fetch.
//
// WHY THIS MATTERS (the whole point): every one of these screens used to
// be a live StreamBuilder. A live listener bills for every document it
// delivers AND re-bills on every subsequent change, for as long as the
// screen is open — so an admin leaving the Payments tab open on a busy
// evening could quietly consume thousands of reads from a 50K/day Spark
// budget while doing nothing at all. Fetch-on-demand makes the cost
// bounded and, crucially, PREDICTABLE: reads happen only when a human
// asks for them.
//
// This widget owns the caching/refresh/timestamp mechanics so each
// analytics screen only has to supply (a) a cache key, (b) a fetch
// function, and (c) a builder that renders the data. Keeping it in one
// place is deliberate — the previous attempt at cache coverage stalled
// because every screen hand-rolled its own get/check/fetch/put dance.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/hive_cache.dart';

const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

/// [T] must be a Hive-serializable shape — in practice a `List`/`Map` of
/// primitives. Firestore snapshot objects are NOT serializable (they hold
/// live references), so each screen's [fetch] is responsible for
/// flattening documents into plain maps before returning them.
class CachedAnalyticsView<T> extends StatefulWidget {
  const CachedAnalyticsView({
    required this.cacheKey,
    required this.fetch,
    required this.builder,
    this.emptyMessage = 'No data yet. Tap Fetch to load.',
    this.extraActions,
    this.externalData,
    super.key,
  });

  /// Hive key this screen's last snapshot is stored under.
  final String cacheKey;

  /// Pulls a fresh snapshot from Firestore. Called ONLY on an explicit
  /// Fetch tap — never on screen open.
  final Future<T> Function() fetch;

  final Widget Function(BuildContext context, T data) builder;
  final String emptyMessage;

  /// Optional extra controls rendered next to the Fetch button (e.g. a
  /// filter chip row, or Customer Demand's one-time backfill action).
  final List<Widget>? extraActions;

  /// NEW (Test Data Cleanup, Aug 11 2026) — optional escape hatch so a
  /// screen can patch the in-memory/cached snapshot after a local
  /// mutation (e.g. a test-record delete) WITHOUT that counting as a
  /// fresh Fetch. Screens that don't need this (every existing
  /// analytics screen) simply never pass it — fully backward
  /// compatible. When a screen assigns `externalData.value = newList`,
  /// this widget adopts that value as its own `_data`, re-renders, and
  /// re-persists it to Hive under the same cacheKey so a deleted row
  /// doesn't resurrect on the next cold load.
  final ValueNotifier<T?>? externalData;

  @override
  State<CachedAnalyticsView<T>> createState() => _CachedAnalyticsViewState<T>();
}

class _CachedAnalyticsViewState<T> extends State<CachedAnalyticsView<T>> {
  T? _data;
  DateTime? _lastFetchedAt;
  bool _loading = true;
  bool _fetching = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadFromCache();
    widget.externalData?.addListener(_onExternalDataChanged);
  }

  @override
  void dispose() {
    widget.externalData?.removeListener(_onExternalDataChanged);
    super.dispose();
  }

  /// A screen patched its own copy of the data (e.g. removed a deleted
  /// test record) and pushed it through [CachedAnalyticsView.externalData].
  /// Adopt it as our own snapshot and re-persist so a cold reload of this
  /// screen doesn't resurrect the deleted row from the old Hive copy.
  Future<void> _onExternalDataChanged() async {
    final next = widget.externalData!.value;
    if (!mounted) return;
    setState(() => _data = next);
    if (next != null) {
      await HiveCache.put(widget.cacheKey, next, ttl: const Duration(days: 7));
    }
  }

  /// Screen-open path: Hive only. Deliberately does NOT touch Firestore —
  /// that is the entire point of this widget.
  Future<void> _loadFromCache() async {
    final cached = await HiveCache.get<T>(widget.cacheKey);
    final ts = await HiveCache.get<int>('${widget.cacheKey}__fetched_at');
    if (!mounted) return;
    setState(() {
      _data = cached;
      _lastFetchedAt =
          ts == null ? null : DateTime.fromMillisecondsSinceEpoch(ts);
      _loading = false;
    });
  }

  Future<void> _fetchFresh() async {
    if (_fetching) return;
    setState(() {
      _fetching = true;
      _error = null;
    });
    try {
      final fresh = await widget.fetch();
      final now = DateTime.now();
      // Long TTL: freshness here is governed by the admin's explicit
      // Fetch taps, not by a clock. The TTL only exists so a snapshot
      // can't live forever if the screen is never opened again.
      await HiveCache.put(widget.cacheKey, fresh,
          ttl: const Duration(days: 7),);
      await HiveCache.put(
        '${widget.cacheKey}__fetched_at',
        now.millisecondsSinceEpoch,
        ttl: const Duration(days: 7),
      );
      if (!mounted) return;
      setState(() {
        _data = fresh;
        _lastFetchedAt = now;
        _fetching = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _fetching = false;
      });
    }
  }

  String _agoLabel(DateTime then) {
    final diff = DateTime.now().difference(then);
    if (diff.inSeconds < 60) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          color: _surface,
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          _lastFetchedAt == null
                              ? 'Never fetched'
                              : 'Updated ${_agoLabel(_lastFetchedAt!)}',
                          style: GoogleFonts.outfit(
                            color: _text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13,
                          ),
                        ),
                        Text(
                          _lastFetchedAt == null
                              ? 'Showing nothing yet — tap Fetch'
                              : 'Showing your last fetched snapshot (offline copy)',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
                        ),
                      ],
                    ),
                  ),
                  ElevatedButton.icon(
                    onPressed: _fetching ? null : _fetchFresh,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _purple,
                      foregroundColor: Colors.white,
                      disabledBackgroundColor: _purple.withValues(alpha: 0.4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    icon: _fetching
                        ? const SizedBox(
                            width: 15,
                            height: 15,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.white,
                            ),
                          )
                        : const Icon(Icons.cloud_download_rounded, size: 17),
                    label: Text(_fetching ? 'Fetching…' : 'Fetch'),
                  ),
                ],
              ),
              if (widget.extraActions != null) ...[
                const SizedBox(height: 10),
                Row(children: widget.extraActions!),
              ],
            ],
          ),
        ),
        if (_error != null)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.4)),
            ),
            child: Text(
              'Fetch failed: $_error',
              style: GoogleFonts.outfit(color: _red, fontSize: 11.5),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator(color: _purple))
              : (_data == null
                  ? _emptyState()
                  : widget.builder(context, _data as T)),
        ),
      ],
    );
  }

  Widget _emptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(28),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.cloud_off_rounded, color: _muted, size: 46),
            const SizedBox(height: 14),
            Text(
              widget.emptyMessage,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                  color: _text, fontWeight: FontWeight.w700, fontSize: 15),
            ),
            const SizedBox(height: 8),
            Text(
              'Nothing is read from the database until you tap Fetch — '
              'this keeps our free-tier read budget under control.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
            ),
          ],
        ),
      ),
    );
  }
}

/// Time-range presets shared by the analytics screens (Nizam's request:
/// "datewise, within 24 hours, 60 minutes ... filter pannura total timing
/// la varra amount ah total pottu kaatatum").
///
/// Filtering is applied CLIENT-SIDE over an already-fetched snapshot, so
/// changing the filter costs ZERO extra reads — the admin can flip
/// between 60 minutes and This Year freely without touching Firestore.
enum AnalyticsRange { last60Min, last24Hours, today, thisMonth, thisYear, all }

extension AnalyticsRangeX on AnalyticsRange {
  String get label => switch (this) {
        AnalyticsRange.last60Min => '60 min',
        AnalyticsRange.last24Hours => '24 hours',
        AnalyticsRange.today => 'Today',
        AnalyticsRange.thisMonth => 'This month',
        AnalyticsRange.thisYear => 'This year',
        AnalyticsRange.all => 'All time',
      };

  /// Inclusive lower bound; `null` means unbounded (All time).
  DateTime? startFrom(DateTime now) => switch (this) {
        AnalyticsRange.last60Min => now.subtract(const Duration(minutes: 60)),
        AnalyticsRange.last24Hours => now.subtract(const Duration(hours: 24)),
        AnalyticsRange.today => DateTime(now.year, now.month, now.day),
        AnalyticsRange.thisMonth => DateTime(now.year, now.month),
        AnalyticsRange.thisYear => DateTime(now.year),
        AnalyticsRange.all => null,
      };

  bool contains(DateTime? when, {DateTime? now}) {
    if (when == null) return false;
    final from = startFrom(now ?? DateTime.now());
    return from == null || !when.isBefore(from);
  }
}

/// Horizontal filter chips for [AnalyticsRange]. Purely local state —
/// selecting a range never triggers a network read.
class AnalyticsRangeChips extends StatelessWidget {
  const AnalyticsRangeChips({
    required this.selected,
    required this.onChanged,
    super.key,
  });

  final AnalyticsRange selected;
  final ValueChanged<AnalyticsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 34,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: AnalyticsRange.values.length,
        separatorBuilder: (_, __) => const SizedBox(width: 7),
        itemBuilder: (context, i) {
          final range = AnalyticsRange.values[i];
          final isSelected = range == selected;
          return GestureDetector(
            onTap: () => onChanged(range),
            child: Container(
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: isSelected ? _green : _card,
                borderRadius: BorderRadius.circular(18),
                border: Border.all(
                  color: isSelected ? _green : _muted.withValues(alpha: 0.3),
                ),
              ),
              child: Text(
                range.label,
                style: GoogleFonts.outfit(
                  color: isSelected ? Colors.white : _muted,
                  fontWeight: FontWeight.w700,
                  fontSize: 12,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
