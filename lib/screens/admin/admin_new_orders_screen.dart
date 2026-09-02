// ================================================================
// admin_new_orders_screen.dart — Broadcast Order System: Admin
// Live list of service_requests where status == 'admin_review'
// (i.e. broadcast timed out after 90s with no hero accepting).
// Lifecycle-aware listener pattern mirrors admin_hero_dispatch_screen.dart
// exactly: pause the Firestore stream when backgrounded, resume on
// foreground.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/hero_skill_catalog.dart';
import '../../models/service_request_model.dart';
import '../../services/admin_deletion_service.dart';
import '../../services/service_request_service.dart';
import '../../services/service_requests_listener.dart';
import '../../widgets/admin/admin_selection_mixin.dart';
import '../../widgets/order_photo_gallery.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _pink = Color(0xFFFF4FA3);
const Color _border = Color(0x1AFFFFFF);
const Color _amber = Color(0xFFFFA726);

// Public — also used by admin_service_requests_screen.dart's
// type-filtered lists. Keep the two files sharing this single mapping.
String requestTypeLabel(String requestType) {
  switch (requestType) {
    case 'hero_booking':
      return 'Hero Booking';
    case 'custom_order':
      return 'Custom Order';
    case 'custom_food_order':
      return 'Food Order';
    case 'grocery_order':
      return 'Grocery Order';
    case 'electronics_service':
      return 'Electronics Service';
    // NEW (CTO mandate — Custom Hotel Ordering & Checkout Pipeline):
    // one added case, everything else in this shared function
    // untouched — same reasoning as every other requestType label here.
    case 'custom_hotel_order':
      return 'Custom Hotel Order';
    default:
      return 'Service Request';
  }
}

// NEW: shared helper — details['items'] may now be a structured
// List<Map> of {sNo, name, qty} line items (see
// quick_order_line_items.dart), replacing the old free-text paragraph
// fields on grocery/custom_food/hero_booking. Renders them as
// "qty name, qty name, ..." Returns null (not empty string) when
// details['items'] isn't a List, so callers can fall back to whatever
// legacy string field that request type used to use.
String? _itemsListSummary(Map<String, dynamic> details) {
  final raw = details['items'];
  if (raw is! List) return null;
  final joined = raw
      .whereType<Map>()
      .map((it) => [
            // 'qty' for the {sNo, name, qty} shape (grocery/custom_food/
            // hero_booking); 'quantity' for the priced-cart shape
            // ({itemId, name, price, quantity, total}) used by
            // catalog_food_order and custom_hotel_order — handle both
            // so this one summary helper works for every requestType.
            (it['qty'] ?? it['quantity'] ?? '').toString().trim(),
            (it['name'] ?? '').toString().trim(),
          ].where((s) => s.isNotEmpty).join(' '))
      .where((s) => s.isNotEmpty)
      .join(', ');
  return joined;
}

// Public — also used by admin_service_requests_screen.dart.
String requestSummary(String requestType, Map<String, dynamic> details) {
  switch (requestType) {
    case 'hero_booking':
      final itemsSummary = _itemsListSummary(details);
      if (itemsSummary != null && itemsSummary.isNotEmpty) return itemsSummary;
      return (details['taskDescription'] as String?) ?? '';
    case 'custom_order':
      return (details['orderDescription'] as String?) ?? '';
    case 'custom_food_order':
      final itemsSummary = _itemsListSummary(details);
      final items = itemsSummary ?? (details['items'] as String?) ?? '';
      final pref = (details['restaurantOrPreference'] as String?) ?? '';
      return [if (pref.isNotEmpty) 'From: $pref', if (items.isNotEmpty) items].join(' — ');
    case 'grocery_order':
      final itemsSummary = _itemsListSummary(details);
      final text = (itemsSummary != null && itemsSummary.isNotEmpty)
          ? itemsSummary
          : (details['listText'] as String?) ?? '';
      final hasImage = (details['listImageUrl'] as String?)?.isNotEmpty ?? false;
      return [if (text.isNotEmpty) text, if (hasImage) '📷 Photo list attached'].join(' — ');
    case 'electronics_service':
      final catLabel = (details['categoryLabel'] as String?) ?? '';
      final issue = (details['issue'] as String?) ?? '';
      return [if (catLabel.isNotEmpty) catLabel, if (issue.isNotEmpty) issue].join(' — ');
    // NEW (Custom Hotel Order consistency pass): details['items'] is
    // the same priced-cart List shape catalog_food_order uses — reuse
    // _itemsListSummary (now quantity/price-aware, see above) rather
    // than the old plain-String 'items' field this requestType used to
    // write before this pass.
    case 'custom_hotel_order':
      final itemsSummary = _itemsListSummary(details);
      final hotelName = (details['hotelName'] as String?) ?? '';
      final items = (itemsSummary != null && itemsSummary.isNotEmpty)
          ? itemsSummary
          : (details['items'] as String?) ?? '';
      return [if (hotelName.isNotEmpty) 'From: $hotelName', if (items.isNotEmpty) items].join(' — ');
    default:
      return '';
  }
}

class AdminNewOrdersScreen extends StatefulWidget {
  const AdminNewOrdersScreen({super.key});

  @override
  State<AdminNewOrdersScreen> createState() => _AdminNewOrdersScreenState();
}

class _AdminNewOrdersScreenState extends State<AdminNewOrdersScreen>
    with WidgetsBindingObserver, AdminSelectionMixin {
  // FIX (CTO mandate — Final UI Migration Sweep): typed models instead
  // of raw QueryDocumentSnapshots — screens/widgets below now read
  // request.requestType / request.customerName / etc. instead of
  // doc.data()['key']. The underlying Firestore queries/subscriptions
  // are unchanged; only what gets stored in state is now mapped
  // through ServiceRequestModel.fromFirestore().
  List<ServiceRequestModel> _pendingReview = [];
  List<ServiceRequestModel> _adminManagedActive = [];
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pendingReviewSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _adminManagedSub;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _listenToNewOrders();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pendingReviewSub?.cancel();
    _adminManagedSub?.cancel();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        _pendingReviewSub?.cancel();
        _adminManagedSub?.cancel();
        debugPrint('[AdminNewOrders] Backgrounded — stopped service_requests listeners');
        break;
      case AppLifecycleState.resumed:
        debugPrint('[AdminNewOrders] Resumed — restarting service_requests listeners');
        _listenToNewOrders();
        break;
    }
  }

  void _listenToNewOrders() {
    _pendingReviewSub?.cancel();
    // Sourced from the shared singleton (see service_requests_listener.dart)
    // instead of opening its own .where('status', isEqualTo: 'admin_review')
    // .orderBy('createdAt') listener -- this is the SAME real Firestore
    // listener SuperAdminHomeScreen already has open (this screen is pushed
    // on top of it, which stays alive underneath). The shared stream is a
    // broadcast stream that stays live regardless of this subscriber's
    // pause state, but this screen's OWN .listen() subscription below is
    // still cancelled/restarted on lifecycle changes exactly as before, so
    // nothing leaks while backgrounded.
    //
    // Filtering to admin_review and sorting by createdAt both move
    // client-side here since the shared stream can't carry either
    // constraint server-side without narrowing it back down to a
    // single-screen-specific query (the whole point of sharing it).
    _pendingReviewSub =
        ServiceRequestsListener.instance.waitingAndReviewStream.listen(
      (snapshot) {
        final filtered = snapshot.docs
            .where((d) => d.data()['status'] == 'admin_review')
            .map((d) => ServiceRequestModel.fromFirestore(d.data(), d.id))
            .toList()
          ..sort((a, b) {
            final aTs = a.createdAt;
            final bTs = b.createdAt;
            if (aTs == null && bTs == null) return 0;
            if (aTs == null) return 1;
            if (bTs == null) return -1;
            return bTs.compareTo(aTs);
          });
        if (mounted) setState(() => _pendingReview = filtered);
      },
      onError: (Object e) {
        debugPrint('[AdminNewOrders] Pending-review listener error: $e');
      },
    );

    // Requests the admin manually assigned — shown here too so the
    // manual status-advance control stays reachable even after the
    // request leaves 'admin_review' status.
    _adminManagedSub?.cancel();
    _adminManagedSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('assignmentMethod', isEqualTo: 'admin_manual')
        .where('status', whereIn: ['hero_assigned', 'in_progress', 'nearing_completion'])
        .trackedSnapshots()
        .listen(
      (snapshot) {
        final models = snapshot.docs
            .map((d) => ServiceRequestModel.fromFirestore(d.data(), d.id))
            .toList();
        if (mounted) setState(() => _adminManagedActive = models);
      },
      onError: (Object e) {
        debugPrint('[AdminNewOrders] Admin-managed listener error: $e');
      },
    );
  }

  Future<void> _call(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    // Test Data Cleanup (Aug 11 2026): client-side filter on the
    // already-loaded lists — same phone-filter contract as the other
    // cleanup-enabled screens, no extra query.
    final pendingVisible =
        _pendingReview.where((r) => matchesPhoneFilter(r.customerPhone)).toList();
    final activeVisible = _adminManagedActive
        .where((r) => matchesPhoneFilter(r.customerPhone))
        .toList();
    final totalCount = pendingVisible.length + activeVisible.length;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text('New Orders', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800)),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.4)),
            ),
            child: Text('${_pendingReview.length + _adminManagedActive.length} Pending', style: const TextStyle(color: _red, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
            child: buildSelectionToolbar(
              context: context,
              visibleIds: [
                ...pendingVisible.map((r) => r.requestId),
                ...activeVisible.map((r) => r.requestId),
              ],
              onFilterChanged: () {},
            ),
          ),
        ),
      ),
      body: totalCount == 0
          ? Center(
              child: Text(
                (_pendingReview.isEmpty && _adminManagedActive.isEmpty)
                    ? 'No orders awaiting review'
                    : 'No matches for that number',
                style: const TextStyle(color: _muted),
              ),)
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (pendingVisible.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('AWAITING ASSIGNMENT', style: GoogleFonts.outfit(color: _muted, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  ...pendingVisible.map(_buildPendingReviewCard),
                  const SizedBox(height: 16),
                ],
                if (activeVisible.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text('MANUALLY ASSIGNED — IN PROGRESS', style: GoogleFonts.outfit(color: _muted, fontSize: 11, fontWeight: FontWeight.w800)),
                  ),
                  ...activeVisible.map(_buildAdminManagedCard),
                ],
              ],
            ),
      bottomNavigationBar: buildDeleteBar(
        subjectPlural: 'Test Requests',
        onDelete: () => _deleteSelected([...pendingVisible, ...activeVisible]),
      ),
    );
  }

  // ── Test Data Cleanup (Aug 11 2026) ──────────────────────────────
  Future<void> _deleteOne(ServiceRequestModel request) async {
    final confirmed = await confirmSingleDelete(context, subject: 'Test Request');
    if (!confirmed || !mounted) return;
    await AdminDeletionService.instance.deleteServiceRequest(
      DeletableRequest(id: request.requestId, assignedHeroId: request.assignedHeroId),
    );
    // No local removal — both lists are fed by live .snapshots()
    // listeners (see _listen-style subs at the top of this class), so
    // the delete's own snapshot event updates them automatically.
  }

  Future<void> _deleteSelected(List<ServiceRequestModel> visible) async {
    final targets = visible.where((r) => selectedIds.contains(r.requestId)).toList();
    if (targets.isEmpty) return;
    final confirmed = await confirmBulkDelete(
      context,
      count: targets.length,
      subjectPlural: 'Test Requests',
    );
    if (!confirmed || !mounted) return;
    await AdminDeletionService.instance.bulkDeleteServiceRequests(
      targets
          .map((r) => DeletableRequest(id: r.requestId, assignedHeroId: r.assignedHeroId))
          .toList(),
    );
    clearSelection();
  }

  Widget _buildPendingReviewCard(ServiceRequestModel request) {
    final requestType = request.requestType.isNotEmpty ? request.requestType : 'hero_booking';
    final customerName = request.customerName.isNotEmpty ? request.customerName : 'Customer';
    final customerPhone = request.customerPhone;
    final details = request.rawDetails;

    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _border)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectMode) buildSelectionCheckbox(request.requestId),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _pink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(requestTypeLabel(requestType), style: const TextStyle(color: _pink, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _call(customerPhone),
                  icon: const Icon(Icons.call_rounded, color: _green, size: 20),
                ),
                // Test Data Cleanup (Aug 11 2026): a hard, permanent
                // delete — distinct from the existing "Cancel" action
                // below (_confirmAndCancel), which is a normal
                // operational status change, not data removal.
                IconButton(
                  onPressed: () => unawaited(_deleteOne(request)),
                  tooltip: 'Delete this request',
                  icon: const Icon(Icons.delete_outline_rounded, color: _red, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(customerName, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 14)),
            if (customerPhone.isNotEmpty)
              Text(customerPhone, style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(height: 6),
            Text(requestSummary(requestType, details), style: const TextStyle(color: _muted, fontSize: 12)),
            // NEW (per Nizam's DMart-cart-screenshot workflow): admin
            // needs the same visual evidence a hero sees, in case admin
            // ends up assigning/fulfilling this order manually.
            if (requestType == 'grocery_order' && orderPhotoUrlsFromDetails(details).isNotEmpty) ...[
              const SizedBox(height: 8),
              OrderPhotoGallery(imageUrls: orderPhotoUrlsFromDetails(details)),
            ],
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(backgroundColor: _pink),
                    // FIX (Sep 2 2026 — service-booking flow audit): this
                    // screen is exactly the "auto-dispatch already failed"
                    // fallback (see file header — status only reaches
                    // 'admin_review' after a 90s broadcast with nobody
                    // accepting), so the admin had ZERO way to tell which
                    // online hero actually knows the trade — the sheet
                    // listed every hero with no skill info at all. A
                    // plumber job could be handed to a bike-taxi hero by
                    // mistake. Now passes the required skill through so
                    // the sheet can badge/sort by qualification.
                    onPressed: () => _showAssignSheet(
                      context,
                      request.requestId,
                      customerName,
                      requestType == 'electronics_service'
                          ? (details[kSkillRequestCategoryKey] as String?)
                          : null,
                    ),
                    child: const Text('Assign to Hero', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                  ),
                ),
                const SizedBox(width: 8),
                OutlinedButton(
                  onPressed: () => _confirmAndCancel(context, request.requestId),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _red,
                    side: const BorderSide(color: _red),
                  ),
                  child: const Text('Cancel'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminManagedCard(ServiceRequestModel request) {
    final requestType = request.requestType.isNotEmpty ? request.requestType : 'hero_booking';
    final customerName = request.customerName.isNotEmpty ? request.customerName : 'Customer';
    final customerPhone = request.customerPhone;
    final assignedHeroName = request.assignedHeroName ?? 'Hero';
    final status = request.status.isNotEmpty ? request.status : 'hero_assigned';

    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: _border)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (selectMode) buildSelectionCheckbox(request.requestId),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _pink.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(requestTypeLabel(requestType), style: const TextStyle(color: _pink, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(color: _green.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(8)),
                  child: Text(status.replaceAll('_', ' '), style: const TextStyle(color: _green, fontSize: 10, fontWeight: FontWeight.bold)),
                ),
                IconButton(
                  onPressed: () => _call(customerPhone),
                  icon: const Icon(Icons.call_rounded, color: _green, size: 20),
                ),
                IconButton(
                  onPressed: () => unawaited(_deleteOne(request)),
                  tooltip: 'Delete this request',
                  icon: const Icon(Icons.delete_outline_rounded, color: _red, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(customerName, style: const TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 14)),
            Text('Hero: $assignedHeroName', style: const TextStyle(color: _muted, fontSize: 11)),
            const SizedBox(height: 10),
            ServiceRequestManualStatusControl(requestId: request.requestId, currentStatus: status),
            const SizedBox(height: 8),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: () => _confirmAndCancel(context, request.requestId),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: const BorderSide(color: _red),
                ),
                child: const Text('Cancel Task'),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Admin cancellation is allowed at any pre-'completed' stage (both
  // card sections above only ever show admin_review/hero_assigned/
  // in_progress/nearing_completion — never 'completed' — so no extra
  // status gating is needed here beyond which cards show a Cancel
  // button at all). Trusted as a human-mediated judgment call after
  // the admin has already spoken to the customer by phone, unlike the
  // stricter customer self-service eligibility rule.
  Future<void> _confirmAndCancel(BuildContext context, String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Cancel this request?', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800)),
        content: const Text(
          'This will permanently delete the request. This cannot be undone.',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _red),
            child: const Text('Cancel Request'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ServiceRequestService().cancelServiceRequest(requestId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request cancelled.')),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e'), backgroundColor: _red),
        );
      }
    }
  }

  void _showAssignSheet(
    BuildContext context,
    String requestId,
    String customerName, [
    String? requiredSkill,
  ]) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AssignHeroSheet(
        requestId: requestId,
        customerName: customerName,
        requiredSkill: requiredSkill,
      ),
    );
  }
}

// ── Hero picker sheet — reuses the online_heroes RTDB read pattern
// from admin_hero_dispatch_screen.dart (same fields, same source of
// truth), but assigns directly instead of opening a dispatch dialog:
// admin has already confirmed with the hero by phone, per the CEO's
// workflow — no broadcast ping needed here.
class AssignHeroSheet extends StatefulWidget {
  final String requestId;
  final String customerName;
  /// Non-null only for an 'electronics_service' request — the skill key
  /// (see hero_skill_catalog.dart) the customer actually needs. Null for
  /// every other requestType, where any online hero is a valid target,
  /// same as before this fix.
  final String? requiredSkill;
  const AssignHeroSheet({
    required this.requestId,
    required this.customerName,
    this.requiredSkill,
    super.key,
  });

  @override
  State<AssignHeroSheet> createState() => AssignHeroSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(StringProperty('customerName', customerName));
    properties.add(StringProperty('requiredSkill', requiredSkill));
  }
}

class AssignHeroSheetState extends State<AssignHeroSheet> {
  List<Map<String, dynamic>> _onlineHeroes = [];
  StreamSubscription<DatabaseEvent>? _heroesSub;
  bool _assigning = false;
  // Optional — the hero's own "before Start" gate (hero_home_screen
  // .dart's _ServiceRequestStatusCard) is the primary mechanism for
  // setting this; this field just lets the admin pre-fill it if
  // pricing already came up on the resolution phone call.
  final _estimateCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _heroesSub = FirebaseDatabase.instance.ref('online_heroes').onValue.listen((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) {
        if (mounted) setState(() => _onlineHeroes = []);
        return;
      }
      final heroes = <Map<String, dynamic>>[];
      raw.forEach((key, value) {
        if (value is Map) {
          heroes.add({
            'heroId': key,
            'name': (value['name'] as String?) ?? 'Hero',
            'phone': (value['phone'] as String?) ?? '',
            'vehicleType': (value['vehicleType'] as String?) ?? 'bike',
            'isAvailable': (value['isAvailable'] as bool?) ?? true,
            // FIX (Sep 2 2026 — audit): needed to badge/sort by
            // qualification below. online_heroes/{uid} already mirrors
            // this (hero_home_screen.dart's presence writes), just never
            // read here before.
            'qualified': widget.requiredSkill == null ||
                heroHasSkill(Map<String, dynamic>.from(value), widget.requiredSkill!),
          });
        }
      });
      // Qualified heroes first — this screen is the auto-dispatch
      // FAILURE fallback (see file header), so unqualified heroes are
      // deliberately kept visible, not hidden, in case the admin needs
      // to override for a real reason; they're just no longer the ones
      // an admin's thumb lands on first for a plumber/electrician/
      // acting_driver job.
      heroes.sort((a, b) =>
          (b['qualified'] as bool ? 1 : 0) - (a['qualified'] as bool ? 1 : 0));
      if (mounted) setState(() => _onlineHeroes = heroes);
    });
  }

  @override
  void dispose() {
    _heroesSub?.cancel();
    _estimateCtrl.dispose();
    super.dispose();
  }

  // FIX (Sep 2 2026 — audit): does not block the assign entirely — this
  // screen only shows up after auto-dispatch already found nobody
  // qualified within range, so a hard block could leave the admin with
  // no way to resolve the request at all. It just makes the mismatch
  // impossible to tap past by accident.
  Future<void> _confirmUnqualifiedThenAssign(Map<String, dynamic> hero) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Not a registered specialist', style: TextStyle(color: _text)),
        content: Text(
          '${hero['name']} is not registered as ${heroSkillLabel(widget.requiredSkill)}. '
          'Assign anyway only if you have confirmed by phone that they can do this job.',
          style: const TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: _amber),
            child: const Text('Assign Anyway'),
          ),
        ],
      ),
    );
    if (confirmed == true) await _assign(hero);
  }

  Future<void> _assign(Map<String, dynamic> hero) async {
    setState(() => _assigning = true);
    try {
      await ServiceRequestService().adminAssignHero(
        requestId: widget.requestId,
        heroId: hero['heroId'] as String,
        heroName: hero['name'] as String,
        heroPhone: hero['phone'] as String,
      );
      // Optional pre-fill — if the admin typed an amount, save it.
      // Non-blocking: assignment already succeeded above regardless
      // of whether this parses; the hero's own gate still applies if
      // this is left blank.
      final typed = double.tryParse(_estimateCtrl.text.trim());
      if (typed != null && typed > 0) {
        try {
          await ServiceRequestService()
              .setEstimatedAmount(widget.requestId, typed);
        } catch (e) {
          debugPrint('[AssignHeroSheet] Optional estimate pre-fill failed: $e');
        }
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Assign failed: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _assigning = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Assign Hero for ${widget.customerName}', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 16)),
          const SizedBox(height: 4),
          const Text('Confirm with the hero by phone before assigning.', style: TextStyle(color: _muted, fontSize: 11)),
          const SizedBox(height: 12),
          TextField(
            controller: _estimateCtrl,
            keyboardType: const TextInputType.numberWithOptions(),
            style: const TextStyle(color: _text),
            decoration: const InputDecoration(
              labelText: 'Estimated amount (optional)',
              labelStyle: TextStyle(color: _muted, fontSize: 12),
              prefixText: '₹ ',
              border: OutlineInputBorder(),
              helperText: 'If pricing already came up on the call — the hero can also set this later.',
              helperStyle: TextStyle(color: _muted, fontSize: 10),
            ),
          ),
          const SizedBox(height: 12),
          Flexible(
            child: _onlineHeroes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text('No heroes online', style: TextStyle(color: _muted)),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _onlineHeroes.length,
                    itemBuilder: (ctx, i) {
                      final hero = _onlineHeroes[i];
                      final isAvailable = hero['isAvailable'] == true;
                      // FIX (Sep 2 2026 — audit): see build-time sort
                      // comment above. Only meaningful when the request
                      // actually needs a skill; null requiredSkill marks
                      // every hero qualified, so this row is unchanged
                      // for every non-skill requestType.
                      final qualified = hero['qualified'] == true;
                      return Card(
                        color: _card,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: qualified
                              ? BorderSide.none
                              : const BorderSide(color: _amber, width: 1),
                        ),
                        child: ListTile(
                          enabled: !_assigning,
                          onTap: () => qualified
                              ? _assign(hero)
                              : _confirmUnqualifiedThenAssign(hero),
                          leading: CircleAvatar(
                            backgroundColor: isAvailable ? _green.withValues(alpha: 0.2) : _red.withValues(alpha: 0.2),
                            child: Text(((hero['name'] as String).isNotEmpty ? hero['name'] as String : 'H')[0].toUpperCase(), style: TextStyle(color: isAvailable ? _green : _red)),
                          ),
                          title: Text(hero['name'] as String, style: const TextStyle(color: _text)),
                          subtitle: Text(
                            qualified
                                ? '${hero['vehicleType']}${isAvailable ? '' : ' · on a task'}'
                                : '${hero['vehicleType']} · ⚠ not registered as ${heroSkillLabel(widget.requiredSkill)}${isAvailable ? '' : ' · on a task'}',
                            style: TextStyle(color: qualified ? _muted : _amber, fontSize: 11),
                          ),
                          trailing: _assigning ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: _pink)) : null,
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}

// ── Manual status-advance widget — used from a service request's
// detail context. Writes the exact same status field the hero-driven
// flow writes; the customer tracking screen cannot tell them apart.
class ServiceRequestManualStatusControl extends StatefulWidget {
  final String requestId;
  final String currentStatus;
  const ServiceRequestManualStatusControl({
    required this.requestId, required this.currentStatus, super.key,
  });

  @override
  State<ServiceRequestManualStatusControl> createState() => _ServiceRequestManualStatusControlState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(StringProperty('currentStatus', currentStatus));
  }
}

class _ServiceRequestManualStatusControlState extends State<ServiceRequestManualStatusControl> {
  bool _updating = false;

  Future<void> _advanceTo(String newStatus) async {
    setState(() => _updating = true);
    try {
      await ServiceRequestService().advanceStatus(widget.requestId, newStatus);
    } catch (e) {
      debugPrint('[ServiceRequestManualStatusControl] advanceStatus error: $e');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  String _buttonLabelFor(String nextStatus) {
    switch (nextStatus) {
      case 'in_progress':
        return 'Start';
      case 'nearing_completion':
        return 'Nearing Completion';
      case 'completed':
        return 'Mark Complete';
      default:
        return 'Advance';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = kServiceRequestAdvanceOrder.indexOf(widget.currentStatus);
    final nextStatus = currentIndex >= 0 && currentIndex < kServiceRequestAdvanceOrder.length - 1
        ? kServiceRequestAdvanceOrder[currentIndex + 1]
        : null;
    if (nextStatus == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: _pink),
        onPressed: _updating ? null : () => _advanceTo(nextStatus),
        child: _updating
            ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
            : Text(_buttonLabelFor(nextStatus), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      ),
    );
  }
}
