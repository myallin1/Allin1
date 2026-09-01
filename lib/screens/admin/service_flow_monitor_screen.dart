// ================================================================
// service_flow_monitor_screen.dart — Admin "Service Flow Monitor"
// ================================================================
// NEW (Aug 11 2026, per Nizam): one page that answers "did every
// customer request actually reach a hero?" across EVERY category —
// bike/auto/car/parcel/mini-truck/lorry rides, hero bookings, custom
// orders, food orders, grocery orders, catalog orders.
//
// ── QUOTA ARCHITECTURE (read before changing anything here) ──
// This screen NEVER opens a listener. No StreamBuilder, no .snapshots(),
// nothing that reads on mount. It follows the same fetch-on-demand
// contract as every other admin analytics screen (AGENTS.md §4): on open
// it renders the LAST snapshot out of Hive, and Firestore is touched
// only when the admin taps Fetch. That is a deliberate Spark-plan
// decision — a live monitor over two collections would burn the daily
// quota by lunchtime.
//
// Two more quota details that matter:
//   1. Every query is bounded by the selected date window, so a fetch
//      costs only the documents in that window — never the collection.
//   2. Queries filter and order on the SAME field (createdAt), so they
//      need no composite index. This codebase has been bitten before by
//      .where() on one field + .orderBy() on another throwing
//      failed-precondition; category and status filtering is therefore
//      done client-side on the already-fetched rows, which costs nothing
//      extra because those rows are already paid for.
//
// ── DELIVERY HEALTH ──
// The most important column here is not the count, it's whether the
// request ever reached a hero. The Aug 11 outage (customer books, hero
// PWA shows nothing, no error anywhere) was invisible precisely because
// nothing in admin showed dispatch outcome. A request that is still
// unassigned well past the dispatch window is now surfaced as FAILED,
// not quietly listed as "pending".
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/admin_deletion_service.dart';
import '../../widgets/admin/admin_selection_mixin.dart';
import '../../widgets/admin/cached_analytics_view.dart';

const Color _bg = Color(0xFF0A0A12);
const Color _card = Color(0xFF141420);
const Color _border = Color(0xFF262636);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _amber = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _pink = Color(0xFFFF4FA3);

/// How long a request may sit unassigned before we call the dispatch a
/// failure. The broadcast window is 90s (kServiceRequestPingExpirySeconds
/// in service_request_service.dart); 5 minutes gives generous headroom
/// for a hero to accept late without flagging healthy traffic.
const Duration kDispatchFailureAfter = Duration(minutes: 5);

/// Which date window the admin is looking at.
enum MonitorDateMode { today, thisMonth, specificDate, customRange }

class ServiceFlowMonitorScreen extends StatefulWidget {
  const ServiceFlowMonitorScreen({super.key});

  @override
  State<ServiceFlowMonitorScreen> createState() =>
      _ServiceFlowMonitorScreenState();
}

class _ServiceFlowMonitorScreenState extends State<ServiceFlowMonitorScreen>
    with AdminSelectionMixin {
  MonitorDateMode _mode = MonitorDateMode.today;
  DateTime _specificDate = DateTime.now();
  DateTime _rangeStart = DateTime.now().subtract(const Duration(days: 7));
  DateTime _rangeEnd = DateTime.now();

  /// null = all categories.
  String? _categoryFilter;

  // ── Test Data Cleanup (Aug 11 2026) ─────────────────────────────
  // This screen is fetch-on-demand + Hive-cached (NOT a live listener —
  // see the file-level quota comment), so a delete here does not
  // auto-refresh like the other three admin cleanup screens. We keep
  // our own copy of the last-rendered raw rows and push edits through
  // this notifier, which CachedAnalyticsView adopts as its new
  // in-memory + Hive snapshot without that counting as a real Fetch.
  final ValueNotifier<List<dynamic>?> _dataNotifier =
      ValueNotifier<List<dynamic>?>(null);
  List<dynamic>? _rawData;

  @override
  void dispose() {
    _dataNotifier.dispose();
    super.dispose();
  }

  void _patchCache(Set<String> removedIds) {
    final raw = _rawData;
    if (raw == null) return;
    final next =
        _rowsOf(raw).where((r) => !removedIds.contains(r['id'])).toList();
    _rawData = next;
    _dataNotifier.value = next;
  }

  Future<void> _deleteOne(Map<String, dynamic> row) async {
    final confirmed =
        await confirmSingleDelete(context, subject: 'Test Request');
    if (!confirmed) return;
    final id = row['id'] as String;
    final source = row['source'] as String;
    final heroId = (row['heroId'] as String?) ?? '';
    if (source == 'rides') {
      await AdminDeletionService.instance.deleteRide(id);
    } else {
      await AdminDeletionService.instance.deleteServiceRequest(
        DeletableRequest(
          id: id,
          assignedHeroId: heroId.trim().isEmpty ? null : heroId,
        ),
      );
    }
    if (!mounted) return;
    _patchCache({id});
  }

  Future<void> _deleteSelected() async {
    if (selectedIds.isEmpty) return;
    final confirmed = await confirmBulkDelete(
      context,
      count: selectedIds.length,
      subjectPlural: 'test records',
    );
    if (!confirmed) return;
    final raw = _rawData;
    if (raw == null) return;
    final toDelete =
        _rowsOf(raw).where((r) => selectedIds.contains(r['id'])).toList();

    final serviceItems = toDelete
        .where((r) => r['source'] != 'rides')
        .map((r) {
          final heroId = (r['heroId'] as String?) ?? '';
          return DeletableRequest(
            id: r['id'] as String,
            assignedHeroId: heroId.trim().isEmpty ? null : heroId,
          );
        })
        .toList();
    final rideIds = toDelete
        .where((r) => r['source'] == 'rides')
        .map((r) => r['id'] as String)
        .toList();

    if (serviceItems.isNotEmpty) {
      await AdminDeletionService.instance
          .bulkDeleteServiceRequests(serviceItems);
    }
    if (rideIds.isNotEmpty) {
      await AdminDeletionService.instance.bulkDeleteRides(rideIds);
    }
    if (!mounted) return;
    final removed = toDelete.map((r) => r['id'] as String).toSet();
    _patchCache(removed);
    clearSelection();
  }

  // ── Date window ────────────────────────────────────────────────
  ({DateTime from, DateTime to}) get _window {
    final now = DateTime.now();
    switch (_mode) {
      case MonitorDateMode.today:
        final start = DateTime(now.year, now.month, now.day);
        return (from: start, to: start.add(const Duration(days: 1)));
      case MonitorDateMode.thisMonth:
        final start = DateTime(now.year, now.month);
        return (from: start, to: DateTime(now.year, now.month + 1));
      case MonitorDateMode.specificDate:
        final start = DateTime(
          _specificDate.year,
          _specificDate.month,
          _specificDate.day,
        );
        return (from: start, to: start.add(const Duration(days: 1)));
      case MonitorDateMode.customRange:
        final start =
            DateTime(_rangeStart.year, _rangeStart.month, _rangeStart.day);
        final end = DateTime(_rangeEnd.year, _rangeEnd.month, _rangeEnd.day)
            .add(const Duration(days: 1));
        return (from: start, to: end);
    }
  }

  /// Part of the Hive cache key, so each window keeps its OWN last
  /// snapshot. Switching back to a window you already fetched shows
  /// instantly with zero reads instead of forcing a refetch.
  String get _windowKey {
    final w = _window;
    return '${w.from.toIso8601String().substring(0, 10)}_'
        '${w.to.toIso8601String().substring(0, 10)}';
  }

  String get _windowLabel {
    switch (_mode) {
      case MonitorDateMode.today:
        return 'Today';
      case MonitorDateMode.thisMonth:
        return 'This month';
      case MonitorDateMode.specificDate:
        return _fmtDate(_specificDate);
      case MonitorDateMode.customRange:
        return '${_fmtDate(_rangeStart)} → ${_fmtDate(_rangeEnd)}';
    }
  }

  static String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/'
      '${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ── Fetch (ONLY runs on an explicit Fetch tap) ─────────────────
  Future<List<dynamic>> _fetch() async {
    final w = _window;
    final db = FirebaseFirestore.instance;
    final rows = <Map<String, dynamic>>[];

    // Range + order on the SAME field — no composite index required.
    final serviceSnap = await db
        .collection('service_requests')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(w.from))
        .where('createdAt', isLessThan: Timestamp.fromDate(w.to))
        .orderBy('createdAt', descending: true)
        .get();

    for (final doc in serviceSnap.docs) {
      final d = doc.data();
      rows.add(_flatten(
        id: doc.id,
        source: 'service_requests',
        category: (d['requestType'] as String?) ?? 'unknown',
        status: (d['status'] as String?) ?? 'pending',
        customerName: (d['customerName'] as String?) ?? '',
        customerPhone: (d['customerPhone'] as String?) ?? '',
        heroId: (d['assignedHeroId'] as String?) ?? '',
        heroName: (d['assignedHeroName'] as String?) ?? '',
        createdAt: d['createdAt'],
        updatedAt: d['updatedAt'],
      ));
    }

    final ridesSnap = await db
        .collection('rides')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(w.from))
        .where('createdAt', isLessThan: Timestamp.fromDate(w.to))
        .orderBy('createdAt', descending: true)
        .get();

    for (final doc in ridesSnap.docs) {
      final d = doc.data();
      rows.add(_flatten(
        id: doc.id,
        source: 'rides',
        // Rides carry the vehicle key ('bike'/'auto'/...) in `category`.
        category: (d['category'] as String?) ?? 'bike',
        status: (d['status'] as String?) ?? 'searching',
        customerName: (d['customerName'] as String?) ?? '',
        customerPhone: (d['customerPhone'] as String?) ?? '',
        heroId: (d['heroId'] as String?) ?? '',
        heroName: (d['heroName'] as String?) ?? '',
        createdAt: d['createdAt'],
        updatedAt: d['updatedAt'],
      ));
    }

    rows.sort((a, b) =>
        ((b['createdAtMs'] as int?) ?? 0).compareTo((a['createdAtMs'] as int?) ?? 0));
    return rows;
  }

  /// Firestore snapshots hold live references and are NOT Hive-
  /// serializable, so every document is flattened to primitives here
  /// before it can be cached (see CachedAnalyticsView's doc comment).
  Map<String, dynamic> _flatten({
    required String id,
    required String source,
    required String category,
    required String status,
    required String customerName,
    required String customerPhone,
    required String heroId,
    required String heroName,
    required Object? createdAt,
    required Object? updatedAt,
  }) {
    int? ms(Object? v) => v is Timestamp ? v.millisecondsSinceEpoch : null;
    return <String, dynamic>{
      'id': id,
      'source': source,
      'category': category,
      'status': status,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'heroId': heroId,
      'heroName': heroName,
      'createdAtMs': ms(createdAt),
      'updatedAtMs': ms(updatedAt),
    };
  }

  // ── Derived views (all client-side, zero extra reads) ──────────
  bool _reachedHero(Map<String, dynamic> r) =>
      ((r['heroId'] as String?) ?? '').trim().isNotEmpty;

  bool _dispatchFailed(Map<String, dynamic> r) {
    if (_reachedHero(r)) return false;
    final status = (r['status'] as String? ?? '').toLowerCase();
    if (status == 'cancelled' || status == 'completed') return false;
    final ms = r['createdAtMs'] as int?;
    if (ms == null) return false;
    final age = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(ms));
    return age > kDispatchFailureAfter;
  }

  /// Hive hands rows back as `Map<dynamic, dynamic>` while a fresh fetch
  /// returns `Map<String, dynamic>`. Normalising here means every
  /// consumer below can assume one shape, and a cached render can never
  /// crash with a cast error the fresh render doesn't hit.
  List<Map<String, dynamic>> _rowsOf(List<dynamic> raw) =>
      raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  List<Map<String, dynamic>> _visible(List<dynamic> raw) {
    var rows = _rowsOf(raw);
    if (_categoryFilter != null) {
      rows = rows.where((r) => r['category'] == _categoryFilter).toList();
    }
    rows = rows
        .where((r) => matchesPhoneFilter((r['customerPhone'] as String?) ?? ''))
        .toList();
    return rows;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Service Flow Monitor',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w800,
            fontSize: 18, // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
          ),
        ),
      ),
      body: CachedAnalyticsView<List<dynamic>>(
        // Window is part of the key so each window keeps its own cached
        // snapshot — switching back is instant and costs nothing.
        key: ValueKey('monitor_$_windowKey'),
        cacheKey: 'admin_service_flow_$_windowKey',
        fetch: _fetch,
        emptyMessage:
            'No data loaded for $_windowLabel yet. Tap Fetch to load.',
        extraActions: [_buildDateControls()],
        externalData: _dataNotifier,
        builder: (context, data) {
          _rawData = data;
          final rows = _visible(data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: buildSelectionToolbar(
                  context: context,
                  visibleIds: rows.map((r) => r['id'] as String).toList(),
                  onFilterChanged: () => setState(() {}),
                ),
              ),
              _buildHealthBanner(rows),
              const SizedBox(height: 14),
              _buildCategoryChart(data),
              const SizedBox(height: 14),
              _buildStatusBreakdown(rows),
              const SizedBox(height: 14),
              _buildRequestList(rows),
            ],
          );
        },
      ),
      bottomNavigationBar: buildDeleteBar(
        subjectPlural: 'test records',
        onDelete: _deleteSelected,
      ),
    );
  }

  // ── Date + category controls ───────────────────────────────────
  Widget _buildDateControls() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 34,
          child: ListView(
            scrollDirection: Axis.horizontal,
            children: [
              _modeChip(MonitorDateMode.today, 'Today'),
              _modeChip(MonitorDateMode.thisMonth, 'This month'),
              _modeChip(MonitorDateMode.specificDate, 'Pick date'),
              _modeChip(MonitorDateMode.customRange, 'Custom range'),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Showing: $_windowLabel  •  tap Fetch after changing this',
          style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
        ),
      ],
    );
  }

  Widget _modeChip(MonitorDateMode mode, String label) {
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

  Future<void> _onModeTap(MonitorDateMode mode) async {
    if (mode == MonitorDateMode.specificDate) {
      final picked = await showDatePicker(
        context: context,
        initialDate: _specificDate,
        firstDate: DateTime(2025),
        lastDate: DateTime.now(),
      );
      if (picked == null) return;
      setState(() {
        _mode = mode;
        _specificDate = picked;
      });
      return;
    }
    if (mode == MonitorDateMode.customRange) {
      final picked = await showDateRangePicker(
        context: context,
        firstDate: DateTime(2025),
        lastDate: DateTime.now(),
        initialDateRange: DateTimeRange(start: _rangeStart, end: _rangeEnd),
      );
      if (picked == null) return;
      setState(() {
        _mode = mode;
        _rangeStart = picked.start;
        _rangeEnd = picked.end;
      });
      return;
    }
    setState(() => _mode = mode);
  }

  // ── Delivery health ────────────────────────────────────────────
  Widget _buildHealthBanner(List<Map<String, dynamic>> rows) {
    final total = rows.length;
    final reached = rows.where(_reachedHero).length;
    final failed = rows.where(_dispatchFailed).length;
    final pending = total - reached - failed;

    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          // The border itself is the alarm: red the moment any request
          // in this window never reached a hero.
          color: failed > 0 ? _red : _border,
          width: failed > 0 ? 1.6 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'DELIVERY HEALTH',
            style: GoogleFonts.outfit(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _healthStat('Total', total, _text),
              _healthStat('Reached hero', reached, _green),
              _healthStat('Waiting', pending < 0 ? 0 : pending, _amber),
              _healthStat('Never dispatched', failed, _red),
            ],
          ),
          if (failed > 0) ...[
            const SizedBox(height: 10),
            Text(
              '$failed request(s) sat unassigned for more than '
              '${kDispatchFailureAfter.inMinutes} minutes. That usually means '
              'the ping never reached a hero — check hero presence and the '
              'customer write path, not just hero availability.',
              style: GoogleFonts.outfit(
                color: _red,
                fontSize: 11.5,
                height: 1.45,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _healthStat(String label, int value, Color color) {
    return Expanded(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '$value',
            style: GoogleFonts.outfit(
              color: color,
              fontSize: 21,
              fontWeight: FontWeight.w900,
            ),
          ),
          Text(
            label,
            style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
          ),
        ],
      ),
    );
  }

  // ── Category counts (visual) ───────────────────────────────────
  Widget _buildCategoryChart(List<dynamic> raw) {
    // Deliberately the UNFILTERED set: the chart is how you pick a
    // category, so it must keep showing every category even while one
    // of them is selected.
    final all = _rowsOf(raw);
    final counts = <String, int>{};
    for (final r in all) {
      final key = (r['category'] as String?) ?? 'unknown';
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));
    final max = entries.isEmpty ? 1 : entries.first.value;

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
              Text(
                'BY CATEGORY',
                style: GoogleFonts.outfit(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const Spacer(),
              if (_categoryFilter != null)
                GestureDetector(
                  onTap: () => setState(() => _categoryFilter = null),
                  child: Text(
                    'Clear filter',
                    style: GoogleFonts.outfit(color: _pink, fontSize: 11.5),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 12),
          if (entries.isEmpty)
            Text(
              'Nothing in this window.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 12),
            ),
          // Tapping a bar filters the list below — client-side only, so
          // it never costs a read.
          for (final e in entries) _categoryBar(e.key, e.value, max),
        ],
      ),
    );
  }

  Widget _categoryBar(String category, int value, int max) {
    final selected = _categoryFilter == category;
    return Padding(
      padding: const EdgeInsets.only(bottom: 9),
      child: GestureDetector(
        onTap: () => setState(
          () => _categoryFilter = selected ? null : category,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    _prettyCategory(category),
                    style: GoogleFonts.outfit(
                      color: selected ? _pink : _text,
                      fontSize: 12.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
                Text(
                  '$value',
                  style: GoogleFonts.outfit(
                    color: _muted,
                    fontSize: 12.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 5),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: max == 0 ? 0 : value / max,
                minHeight: 6,
                backgroundColor: _bg,
                valueColor: AlwaysStoppedAnimation<Color>(
                  selected ? _pink : _green,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _prettyCategory(String key) {
    switch (key) {
      case 'bike':
        return 'Bike Taxi';
      case 'auto':
        return 'Auto';
      case 'car':
        return 'Cab / Car';
      case 'parcel':
        return 'Parcel';
      case 'mini_truck':
        return 'Mini Truck';
      case 'lorry':
        return 'Lorry';
      case 'emergency_manpower':
        return 'Emergency Manpower';
      case 'hero_booking':
        return 'Hero Booking';
      case 'custom_order':
        return 'Custom Order';
      case 'custom_food_order':
        return 'Food Order';
      case 'grocery_order':
        return 'Grocery Order';
      case 'catalog_food_order':
        return 'Catalog Food Order';
      case 'custom_hotel_order':
        return 'Hotel Order';
      default:
        return key.replaceAll('_', ' ');
    }
  }

  // ── Status breakdown ───────────────────────────────────────────
  Widget _buildStatusBreakdown(List<Map<String, dynamic>> rows) {
    final counts = <String, int>{};
    for (final r in rows) {
      final key = ((r['status'] as String?) ?? 'unknown').toLowerCase();
      counts[key] = (counts[key] ?? 0) + 1;
    }
    final entries = counts.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

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
          Text(
            'BY STATUS',
            style: GoogleFonts.outfit(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              if (entries.isEmpty)
                Text(
                  'Nothing in this window.',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                ),
              for (final e in entries)
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 11, vertical: 6),
                  decoration: BoxDecoration(
                    color: _statusColor(e.key).withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(9),
                    border: Border.all(
                      color: _statusColor(e.key).withValues(alpha: 0.5),
                    ),
                  ),
                  child: Text(
                    '${e.key}  ${e.value}',
                    style: GoogleFonts.outfit(
                      color: _statusColor(e.key),
                      fontSize: 11.5,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  static Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return _green;
      case 'accepted':
      case 'assigned':
        return _green;
      case 'cancelled':
      case 'timeout':
        return _red;
      case 'pending':
      case 'searching':
        return _amber;
      default:
        return _muted;
    }
  }

  // ── Request list ───────────────────────────────────────────────
  Widget _buildRequestList(List<Map<String, dynamic>> rows) {
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
          Text(
            'REQUESTS (${rows.length})',
            style: GoogleFonts.outfit(
              color: _muted,
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          if (rows.isEmpty)
            Text(
              'Nothing in this window.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 12),
            ),
          for (final r in rows) _requestRow(r),
        ],
      ),
    );
  }

  Widget _requestRow(Map<String, dynamic> r) {
    final failed = _dispatchFailed(r);
    final reached = _reachedHero(r);
    final ms = r['createdAtMs'] as int?;
    final time = ms == null
        ? '—'
        : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms))
            .format(context);
    final phone = (r['customerPhone'] as String?) ?? '';
    final id = r['id'] as String;

    return GestureDetector(
      onTap: selectMode ? () => toggleItemSelected(id) : null,
      child: Container(
      margin: const EdgeInsets.only(bottom: 9),
      padding: const EdgeInsets.all(11),
      decoration: BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.circular(11),
        border: Border.all(
          color: failed ? _red.withValues(alpha: 0.6) : _border,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (selectMode) ...[
                buildSelectionCheckbox(id),
                const SizedBox(width: 4),
              ],
              Expanded(
                child: Text(
                  _prettyCategory((r['category'] as String?) ?? ''),
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Text(
                time,
                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
              ),
              IconButton(
                icon: const Icon(Icons.delete_outline_rounded,
                    color: _red, size: 19),
                visualDensity: VisualDensity.compact,
                tooltip: 'Delete test record',
                onPressed: () => _deleteOne(r),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            '${(r['customerName'] as String?)?.isNotEmpty ?? false ? r['customerName'] : 'Customer'}'
            '${phone.isEmpty ? '  •  no phone on file' : '  •  $phone'}',
            style: GoogleFonts.outfit(
              // A missing number is itself a problem worth seeing —
              // nobody can follow this order up.
              color: phone.isEmpty ? _red : _muted,
              fontSize: 11.5,
            ),
          ),
          const SizedBox(height: 7),
          Row(
            children: [
              _pill(
                (r['status'] as String?) ?? '',
                _statusColor(((r['status'] as String?) ?? '').toLowerCase()),
              ),
              const SizedBox(width: 7),
              if (failed)
                _pill('NEVER REACHED A HERO', _red)
              else if (reached)
                _pill(
                  'Hero: ${(r['heroName'] as String?)?.isNotEmpty ?? false ? r['heroName'] : 'assigned'}',
                  _green,
                )
              else
                _pill('Dispatching…', _amber),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _pill(String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: GoogleFonts.outfit(
          color: color,
          fontSize: 10.5,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
