// ================================================================
// admin_service_requests_screen.dart — Broadcast Order System: Admin
// Type-filtered live list of ALL service_requests of one requestType
// (e.g. 'hero_booking' for the "Hero Needs" button, or
// 'electronics_service' for the "Electronics" button on
// super_admin_home_screen.dart). Unlike admin_new_orders_screen.dart
// (which shows only escalated admin_review requests across ALL
// types), this shows every request of ONE type at every status —
// so 10 simultaneous customer requests appear as 10 cards, newest
// first.
//
// Tapping a card opens the SAME graphical step tracking screen the
// customer sees (service_request_tracking_screen.dart — it's fully
// read-only, so safe to reuse for admin). Requests no hero has
// accepted yet (pending / admin_review) also get an "Assign to Hero"
// action reusing AssignHeroSheet from admin_new_orders_screen.dart.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/service_request_model.dart';
import '../../services/admin_deletion_service.dart';
import '../../utils/service_request_labels.dart';
import '../../widgets/admin/admin_selection_mixin.dart';
import '../../widgets/order_photo_gallery.dart';
import '../service_request_tracking_screen.dart';
import 'admin_new_orders_screen.dart' show AssignHeroSheet, requestSummary;
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _pink = Color(0xFFFF4FA3);
const Color _border = Color(0x1AFFFFFF);

class AdminServiceRequestsScreen extends StatefulWidget {
  /// The single requestType this list shows ('hero_booking',
  /// 'electronics_service', ...).
  final String requestType;

  /// Screen title, e.g. 'Hero Needs' or 'Electronics Requests'.
  final String title;

  const AdminServiceRequestsScreen({
    required this.requestType,
    required this.title,
    super.key,
  });

  @override
  State<AdminServiceRequestsScreen> createState() =>
      _AdminServiceRequestsScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestType', requestType));
    properties.add(StringProperty('title', title));
  }
}

class _AdminServiceRequestsScreenState extends State<AdminServiceRequestsScreen>
    with WidgetsBindingObserver, AdminSelectionMixin {
  // FIX (CTO mandate — Final UI Migration Sweep): typed models instead
  // of raw QueryDocumentSnapshots — same pattern already applied to
  // admin_new_orders_screen.dart and hero_home_screen.dart. Query/
  // subscription itself unchanged.
  List<ServiceRequestModel> _requests = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _sub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sub?.cancel();
    super.dispose();
  }

  // Same lifecycle-aware listener pattern as admin_new_orders_screen:
  // stop the stream when backgrounded, resume on foreground.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _sub?.cancel();
        break;
      case AppLifecycleState.resumed:
        _listen();
        break;
    }
  }

  void _listen() {
    _sub?.cancel();
    _sub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('requestType', isEqualTo: widget.requestType)
        .orderBy('createdAt', descending: true)
        // FIX (read-spike follow-up from the IndexedStack fix): this
        // query used to be unbounded, re-reading this request type's
        // ENTIRE history on every listen. Admin only ever needs to
        // work the recent/active queue here, not months of completed
        // history — 100 most-recent covers that with room to spare.
        // Picked a safe default rather than blocking on a product
        // decision; raise this if 100 ever turns out to be too few.
        .limit(100)
        .trackedSnapshots()
        .listen(
      (snapshot) {
        final models = snapshot.docs
            .map((d) => ServiceRequestModel.fromFirestore(d.data(), d.id))
            .toList();
        if (mounted) setState(() => _requests = models);
      },
      onError: (Object e) {
        debugPrint('[AdminServiceRequests] listener error: $e');
      },
    );
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  void _openTracking(String requestId) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => ServiceRequestTrackingScreen(
          requestId: requestId,
          requestType: widget.requestType,
        ),
      ),
    );
  }

  void _showAssignSheet(String requestId, String customerName) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          AssignHeroSheet(requestId: requestId, customerName: customerName),
    );
  }

  // ── Test Data Cleanup (Aug 11 2026) ──────────────────────────────
  Future<void> _deleteOne(ServiceRequestModel request) async {
    final confirmed = await confirmSingleDelete(context, subject: 'Test Request');
    if (!confirmed || !mounted) return;
    await AdminDeletionService.instance.deleteServiceRequest(
      DeletableRequest(
        id: request.requestId,
        assignedHeroId: request.assignedHeroId,
      ),
    );
    // No local removal needed — this screen is a live .snapshots()
    // listener (see _listen()), so the delete's own snapshot event
    // updates _requests automatically. A manual removal here would
    // just race that event.
  }

  Future<void> _deleteSelected(List<ServiceRequestModel> visible) async {
    final targets =
        visible.where((r) => selectedIds.contains(r.requestId)).toList();
    if (targets.isEmpty) return;
    final confirmed = await confirmBulkDelete(
      context,
      count: targets.length,
      subjectPlural: 'Test Requests',
    );
    if (!confirmed || !mounted) return;
    await AdminDeletionService.instance.bulkDeleteServiceRequests(
      targets
          .map((r) => DeletableRequest(
                id: r.requestId,
                assignedHeroId: r.assignedHeroId,
              ),)
          .toList(),
    );
    clearSelection();
  }

  @override
  Widget build(BuildContext context) {
    // Test Data Cleanup (Aug 11 2026): client-side filter on the
    // already-loaded, already-paid-for page — never a second query.
    final visible = _requests
        .where((r) => matchesPhoneFilter(r.customerPhone))
        .toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(widget.title,
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _pink.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _pink.withValues(alpha: 0.4)),
            ),
            child: Text('${_requests.length} Total',
                style: const TextStyle(
                    color: _pink, fontSize: 12, fontWeight: FontWeight.bold,),),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: buildSelectionToolbar(
              context: context,
              visibleIds: visible.map((r) => r.requestId).toList(),
              onFilterChanged: () {},
            ),
          ),
        ),
      ),
      body: visible.isEmpty
          ? Center(
              child: Text(
                _requests.isEmpty ? 'No requests yet' : 'No matches for that number',
                style: const TextStyle(color: _muted),
              ),)
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: visible.length,
              itemBuilder: (context, i) => _buildCard(visible[i]),
            ),
      bottomNavigationBar: buildDeleteBar(
        subjectPlural: 'Test Requests',
        onDelete: () => _deleteSelected(visible),
      ),
    );
  }

  Widget _buildCard(ServiceRequestModel request) {
    final customerName = request.customerName.isNotEmpty ? request.customerName : 'Customer';
    final customerPhone = request.customerPhone;
    final firestoreStatus = request.status.isNotEmpty ? request.status : 'pending';
    final assignedHeroName = request.assignedHeroName;
    // Legacy fallback respected here too: rawDetails preserves every
    // field an older document wrote (listText/items-as-String/
    // taskDescription/etc.) even though the model doesn't declare a
    // named property for each one — requestSummary() already knows how
    // to fall back to those for pre-Quick-Order documents.
    final details = request.rawDetails;
    final summary = requestSummary(widget.requestType, details);

    // TASK 2 (Aug 8 2026) — Database Cost Control / lazy loading.
    // This used to be a StreamBuilder opening a LIVE RTDB listener on
    // active_service_requests/{requestId} for every single rendered
    // card — N cards on screen meant N permanently-open RTDB
    // connections just to catch the 'in_progress'/'nearing_completion'
    // transient states that only exist in RTDB, not Firestore. Per
    // Nizam's explicit spec ("just show the basic list/notification,
    // only fetch full live data when admin taps in to monitor"), the
    // list now shows only the cheap Firestore-derived status (already
    // covered by the one shared, capped `.limit(100)` listener in
    // _listen() above) and does NOT open any per-card RTDB connection.
    // Tapping a card still opens ServiceRequestTrackingScreen via
    // _openTracking(), which is where the real live
    // in_progress/nearing_completion RTDB merge already correctly
    // happens, now scoped to exactly the one request the admin is
    // actually monitoring.
    final status = firestoreStatus;
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel(widget.requestType, status);
    // No hero has this yet — offer the manual-assign path.
    final needsAssignment = status == 'pending' || status == 'admin_review';

    return _buildCardContent(
      request: request,
      requestId: request.requestId,
      customerName: customerName,
      customerPhone: customerPhone,
      assignedHeroName: assignedHeroName,
      summary: summary,
      details: details,
      statusColor: statusColor,
      statusLabel: statusLabel,
      needsAssignment: needsAssignment,
    );
  }

  Widget _buildCardContent({
    required ServiceRequestModel request,
    required String requestId,
    required String customerName,
    required String customerPhone,
    required String? assignedHeroName,
    required String summary,
    required Map<String, dynamic> details,
    required Color statusColor,
    required String statusLabel,
    required bool needsAssignment,
  }) {
    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _border),),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Test Data Cleanup (Aug 11 2026): in select mode, tapping the
        // card toggles its checkbox instead of opening tracking — a
        // customer-support-shaped screen suddenly turning into a bulk
        // deletion tool the moment select mode is on is exactly the
        // "don't clutter existing UI" risk Nizam flagged; toggling
        // selection on tap (matching the checkbox itself) keeps the
        // normal tap behaviour fully intact the rest of the time.
        onTap: selectMode
            ? () => toggleItemSelected(requestId)
            : () => _openTracking(requestId),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (selectMode)
                Row(
                  children: [
                    buildSelectionCheckbox(requestId),
                    const Text('Select this request',
                        style: TextStyle(color: _muted, fontSize: 11.5),),
                  ],
                ),
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4,),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),),
                    child: Text(statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold,),),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _call(customerPhone),
                    icon: const Icon(Icons.call_rounded,
                        color: _green, size: 20,),
                  ),
                  // Test Data Cleanup (Aug 11 2026): individual delete,
                  // always available regardless of select mode — a
                  // single stray test record shouldn't require entering
                  // select mode just to remove it.
                  IconButton(
                    onPressed: () => unawaited(_deleteOne(request)),
                    tooltip: 'Delete this request',
                    icon: const Icon(Icons.delete_outline_rounded,
                        color: Color(0xFFFF5252), size: 20,),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(customerName,
                  style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14,),),
              if (customerPhone.isNotEmpty)
                Text(customerPhone,
                    style: const TextStyle(color: _muted, fontSize: 11),),
              if (assignedHeroName != null && assignedHeroName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Hero: $assignedHeroName',
                    style: const TextStyle(color: _muted, fontSize: 11),),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12),),
              ],
              // NEW (per Nizam's DMart-cart-screenshot workflow): same
              // photo evidence shown to the hero, so admin can review it
              // without opening the tracking screen.
              if (widget.requestType == 'grocery_order' &&
                  orderPhotoUrlsFromDetails(details).isNotEmpty) ...[
                const SizedBox(height: 8),
                OrderPhotoGallery(imageUrls: orderPhotoUrlsFromDetails(details)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (needsAssignment)
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _pink),
                        onPressed: () =>
                            _showAssignSheet(requestId, customerName),
                        child: const Text('Assign to Hero',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,),),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openTracking(requestId),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _pink,
                          side: const BorderSide(color: _pink),
                        ),
                        icon: const Icon(Icons.timeline_rounded, size: 16),
                        label: const Text('View Progress'),
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
