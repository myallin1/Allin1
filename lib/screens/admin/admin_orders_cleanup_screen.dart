// ================================================================
// admin_orders_cleanup_screen.dart — Test Data Cleanup: `orders`
// ================================================================
// NEW (Aug 11 2026, per Nizam — Test Data Cleanup System). The `orders`
// collection (written by cart_screen.dart's catalog checkout flow) had
// NO admin screen at all before this — confirmed by audit that nothing
// under lib/screens/admin/ reads it. Nizam confirmed he has test junk
// in there too ("Yes — I have test junk there too"), so this is a
// minimal, purpose-built screen: list + individual/multi-select delete
// only. It is deliberately NOT a full order-management screen (no
// status changes, no assignment) — that would be scope creep beyond
// "clean up my test data."
//
// Firestore-only delete: `orders` has no RTDB involvement anywhere
// (verified against every field cart_screen.dart writes into it), so
// AdminDeletionService.deleteOrder/bulkDeleteOrders never touch RTDB.
//
// Fetch-on-demand, same as every other admin analytics/cleanup screen
// in this app (AGENTS.md §4) — no live .snapshots() listener, so
// opening this screen never bills the Spark read quota on its own.
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

class AdminOrdersCleanupScreen extends StatefulWidget {
  const AdminOrdersCleanupScreen({super.key});

  @override
  State<AdminOrdersCleanupScreen> createState() =>
      _AdminOrdersCleanupScreenState();
}

class _AdminOrdersCleanupScreenState extends State<AdminOrdersCleanupScreen>
    with AdminSelectionMixin {
  // Same externalData-patch pattern used in service_flow_monitor_screen.dart
  // — this screen is fetch-on-demand + Hive-cached, not a live listener, so
  // a delete must explicitly patch the cached snapshot or the row will
  // reappear until the next manual Fetch.
  final ValueNotifier<List<dynamic>?> _dataNotifier =
      ValueNotifier<List<dynamic>?>(null);
  List<dynamic>? _rawData;

  @override
  void dispose() {
    _dataNotifier.dispose();
    super.dispose();
  }

  Future<List<dynamic>> _fetch() async {
    // Most-recent-first, capped so a stale dev environment with years of
    // test orders can't turn one Fetch tap into a huge read bill. 500 is
    // generous headroom above any real cleanup session's needs.
    final snap = await FirebaseFirestore.instance
        .collection('orders')
        .orderBy('createdAt', descending: true)
        .limit(500)
        .get();
    return snap.docs.map((doc) {
      final d = doc.data();
      final createdAt = d['createdAt'];
      return <String, dynamic>{
        'id': doc.id,
        'customerName': (d['customerName'] as String?) ?? '',
        'customerPhone': (d['customerPhone'] as String?) ?? '',
        'status': (d['status'] as String?) ?? 'unknown',
        'total': d['total'],
        'createdAtMs':
            createdAt is Timestamp ? createdAt.millisecondsSinceEpoch : null,
      };
    }).toList();
  }

  List<Map<String, dynamic>> _rowsOf(List<dynamic> raw) =>
      raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();

  List<Map<String, dynamic>> _visible(List<dynamic> raw) {
    return _rowsOf(raw)
        .where((r) => matchesPhoneFilter((r['customerPhone'] as String?) ?? ''))
        .toList();
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
        await confirmSingleDelete(context, subject: 'Test Order');
    if (!confirmed) return;
    final id = row['id'] as String;
    await AdminDeletionService.instance.deleteOrder(id);
    if (!mounted) return;
    _patchCache({id});
  }

  Future<void> _deleteSelected() async {
    if (selectedIds.isEmpty) return;
    final confirmed = await confirmBulkDelete(
      context,
      count: selectedIds.length,
      subjectPlural: 'test orders',
    );
    if (!confirmed) return;
    final ids = selectedIds.toList();
    await AdminDeletionService.instance.bulkDeleteOrders(ids);
    if (!mounted) return;
    _patchCache(ids.toSet());
    clearSelection();
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
          'Orders Cleanup',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w800,
            fontSize: 18, // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
          ),
        ),
      ),
      body: CachedAnalyticsView<List<dynamic>>(
        cacheKey: 'admin_orders_cleanup',
        fetch: _fetch,
        emptyMessage: 'No orders loaded yet. Tap Fetch to load.',
        externalData: _dataNotifier,
        builder: (context, data) {
          _rawData = data;
          final rows = _visible(data);
          return ListView(
            padding: const EdgeInsets.fromLTRB(14, 4, 14, 24),
            children: [
              buildSelectionToolbar(
                context: context,
                visibleIds: rows.map((r) => r['id'] as String).toList(),
                onFilterChanged: () => setState(() {}),
              ),
              const SizedBox(height: 10),
              Text(
                'ORDERS (${rows.length})',
                style: GoogleFonts.outfit(
                  color: _muted,
                  fontSize: 11,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.1,
                ),
              ),
              const SizedBox(height: 8),
              if (rows.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(
                    'Nothing loaded. Tap Fetch above.',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                  ),
                ),
              for (final r in rows) _orderRow(r),
            ],
          );
        },
      ),
      bottomNavigationBar: buildDeleteBar(
        subjectPlural: 'test orders',
        onDelete: _deleteSelected,
      ),
    );
  }

  Widget _orderRow(Map<String, dynamic> r) {
    final id = r['id'] as String;
    final phone = (r['customerPhone'] as String?) ?? '';
    final name = (r['customerName'] as String?) ?? '';
    final total = r['total'];
    final ms = r['createdAtMs'] as int?;
    final time = ms == null
        ? '—'
        : TimeOfDay.fromDateTime(DateTime.fromMillisecondsSinceEpoch(ms))
            .format(context);

    return GestureDetector(
      onTap: selectMode ? () => toggleItemSelected(id) : null,
      child: Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.all(11),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(11),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            if (selectMode) ...[
              buildSelectionCheckbox(id),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name.isEmpty ? 'Customer' : name,
                    style: GoogleFonts.outfit(
                      color: _text,
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    '${phone.isEmpty ? 'no phone on file' : phone}  •  '
                    '${(r['status'] as String?) ?? ''}'
                    '${total != null ? '  •  ₹$total' : ''}',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                  ),
                ],
              ),
            ),
            Text(time, style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
            IconButton(
              icon: const Icon(Icons.delete_outline_rounded,
                  color: Color(0xFFFF5252), size: 19),
              visualDensity: VisualDensity.compact,
              tooltip: 'Delete test order',
              onPressed: () => _deleteOne(r),
            ),
          ],
        ),
      ),
    );
  }
}
