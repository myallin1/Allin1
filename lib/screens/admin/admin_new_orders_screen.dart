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

import '../../services/service_request_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _pink = Color(0xFFFF4FA3);
const Color _border = Color(0x1AFFFFFF);

String _requestTypeLabel(String requestType) {
  switch (requestType) {
    case 'hero_booking':
      return 'Hero Booking';
    case 'custom_order':
      return 'Custom Order';
    case 'custom_food_order':
      return 'Food Order';
    case 'grocery_order':
      return 'Grocery Order';
    default:
      return 'Service Request';
  }
}

String _requestSummary(String requestType, Map<String, dynamic> details) {
  switch (requestType) {
    case 'hero_booking':
      return (details['taskDescription'] as String?) ?? '';
    case 'custom_order':
      return (details['orderDescription'] as String?) ?? '';
    case 'custom_food_order':
      final items = (details['items'] as String?) ?? '';
      final pref = (details['restaurantOrPreference'] as String?) ?? '';
      return [if (pref.isNotEmpty) 'From: $pref', if (items.isNotEmpty) items]
          .join(' — ');
    case 'grocery_order':
      final text = (details['listText'] as String?) ?? '';
      final hasImage =
          (details['listImageUrl'] as String?)?.isNotEmpty ?? false;
      return [if (text.isNotEmpty) text, if (hasImage) '📷 Photo list attached']
          .join(' — ');
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
    with WidgetsBindingObserver {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _pendingReview = [];
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _adminManagedActive = [];
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
        debugPrint(
          '[AdminNewOrders] Backgrounded — stopped service_requests listeners',
        );
        break;
      case AppLifecycleState.resumed:
        debugPrint(
          '[AdminNewOrders] Resumed — restarting service_requests listeners',
        );
        _listenToNewOrders();
        break;
    }
  }

  void _listenToNewOrders() {
    _pendingReviewSub?.cancel();
    _pendingReviewSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('status', isEqualTo: 'admin_review')
        .orderBy('createdAt', descending: true)
        .snapshots()
        .listen(
      (snapshot) {
        if (mounted) setState(() => _pendingReview = snapshot.docs);
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
        .where(
          'status',
          whereIn: ['hero_assigned', 'in_progress', 'nearing_completion'],
        )
        .snapshots()
        .listen(
          (snapshot) {
            if (mounted) setState(() => _adminManagedActive = snapshot.docs);
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
    final totalCount = _pendingReview.length + _adminManagedActive.length;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'New Orders',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        actions: [
          Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: _red.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _red.withValues(alpha: 0.4)),
            ),
            child: Text(
              '$totalCount Pending',
              style: const TextStyle(
                color: _red,
                fontSize: 12,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
        ],
      ),
      body: totalCount == 0
          ? const Center(
              child: Text(
                'No orders awaiting review',
                style: TextStyle(color: _muted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_pendingReview.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text(
                      'AWAITING ASSIGNMENT',
                      style: GoogleFonts.outfit(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ..._pendingReview.map(_buildPendingReviewCard),
                  const SizedBox(height: 16),
                ],
                if (_adminManagedActive.isNotEmpty) ...[
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, left: 4),
                    child: Text(
                      'MANUALLY ASSIGNED — IN PROGRESS',
                      style: GoogleFonts.outfit(
                        color: _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  ..._adminManagedActive.map(_buildAdminManagedCard),
                ],
              ],
            ),
    );
  }

  Widget _buildPendingReviewCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final requestType = data['requestType'] as String? ?? 'hero_booking';
    final customerName = data['customerName'] as String? ?? 'Customer';
    final customerPhone = data['customerPhone'] as String? ?? '';
    final details = Map<String, dynamic>.from(data['details'] as Map? ?? {});

    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _pink.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _requestTypeLabel(requestType),
                    style: const TextStyle(
                      color: _pink,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () => _call(customerPhone),
                  icon: const Icon(Icons.call_rounded, color: _green, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              customerName,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            if (customerPhone.isNotEmpty)
              Text(
                customerPhone,
                style: const TextStyle(color: _muted, fontSize: 11),
              ),
            const SizedBox(height: 6),
            Text(
              _requestSummary(requestType, details),
              style: const TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: _pink),
                onPressed: () =>
                    _showAssignSheet(context, doc.id, customerName),
                child: const Text(
                  'Assign to Hero',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAdminManagedCard(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final requestType = data['requestType'] as String? ?? 'hero_booking';
    final customerName = data['customerName'] as String? ?? 'Customer';
    final customerPhone = data['customerPhone'] as String? ?? '';
    final assignedHeroName = data['assignedHeroName'] as String? ?? 'Hero';
    final status = data['status'] as String? ?? 'hero_assigned';

    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: const BorderSide(color: _border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _pink.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    _requestTypeLabel(requestType),
                    style: const TextStyle(
                      color: _pink,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    status.replaceAll('_', ' '),
                    style: const TextStyle(
                      color: _green,
                      fontSize: 10,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  onPressed: () => _call(customerPhone),
                  icon: const Icon(Icons.call_rounded, color: _green, size: 20),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              customerName,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.w700,
                fontSize: 14,
              ),
            ),
            Text(
              'Hero: $assignedHeroName',
              style: const TextStyle(color: _muted, fontSize: 11),
            ),
            const SizedBox(height: 10),
            ServiceRequestManualStatusControl(
              requestId: doc.id,
              currentStatus: status,
            ),
          ],
        ),
      ),
    );
  }

  void _showAssignSheet(
    BuildContext context,
    String requestId,
    String customerName,
  ) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) =>
          _AssignHeroSheet(requestId: requestId, customerName: customerName),
    );
  }
}

// ── Hero picker sheet — reuses the online_heroes RTDB read pattern
// from admin_hero_dispatch_screen.dart (same fields, same source of
// truth), but assigns directly instead of opening a dispatch dialog:
// admin has already confirmed with the hero by phone, per the CEO's
// workflow — no broadcast ping needed here.
class _AssignHeroSheet extends StatefulWidget {
  final String requestId;
  final String customerName;
  const _AssignHeroSheet({required this.requestId, required this.customerName});

  @override
  State<_AssignHeroSheet> createState() => _AssignHeroSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(StringProperty('customerName', customerName));
  }
}

class _AssignHeroSheetState extends State<_AssignHeroSheet> {
  List<Map<String, dynamic>> _onlineHeroes = [];
  StreamSubscription<DatabaseEvent>? _heroesSub;
  bool _assigning = false;

  @override
  void initState() {
    super.initState();
    _heroesSub =
        FirebaseDatabase.instance.ref('online_heroes').onValue.listen((event) {
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
          });
        }
      });
      if (mounted) setState(() => _onlineHeroes = heroes);
    });
  }

  @override
  void dispose() {
    _heroesSub?.cancel();
    super.dispose();
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
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.7),
      padding: const EdgeInsets.all(20),
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Assign Hero for ${widget.customerName}',
            style: GoogleFonts.outfit(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'Confirm with the hero by phone before assigning.',
            style: TextStyle(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 16),
          Flexible(
            child: _onlineHeroes.isEmpty
                ? const Padding(
                    padding: EdgeInsets.all(20),
                    child: Text(
                      'No heroes online',
                      style: TextStyle(color: _muted),
                    ),
                  )
                : ListView.builder(
                    shrinkWrap: true,
                    itemCount: _onlineHeroes.length,
                    itemBuilder: (ctx, i) {
                      final hero = _onlineHeroes[i];
                      final isAvailable = hero['isAvailable'] == true;
                      return Card(
                        color: _card,
                        margin: const EdgeInsets.symmetric(vertical: 4),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: ListTile(
                          enabled: !_assigning,
                          onTap: () => _assign(hero),
                          leading: CircleAvatar(
                            backgroundColor: isAvailable
                                ? _green.withValues(alpha: 0.2)
                                : _red.withValues(alpha: 0.2),
                            child: Text(
                              ((hero['name'] as String).isNotEmpty
                                      ? hero['name'] as String
                                      : 'H')[0]
                                  .toUpperCase(),
                              style: TextStyle(
                                color: isAvailable ? _green : _red,
                              ),
                            ),
                          ),
                          title: Text(
                            hero['name'] as String,
                            style: const TextStyle(color: _text),
                          ),
                          subtitle: Text(
                            '${hero['vehicleType']}${isAvailable ? '' : ' · on a task'}',
                            style: const TextStyle(color: _muted, fontSize: 11),
                          ),
                          trailing: _assigning
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: _pink,
                                  ),
                                )
                              : null,
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
    required this.requestId,
    required this.currentStatus,
    super.key,
  });

  @override
  State<ServiceRequestManualStatusControl> createState() =>
      _ServiceRequestManualStatusControlState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(StringProperty('currentStatus', currentStatus));
  }
}

class _ServiceRequestManualStatusControlState
    extends State<ServiceRequestManualStatusControl> {
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
    final currentIndex =
        kServiceRequestAdvanceOrder.indexOf(widget.currentStatus);
    final nextStatus = currentIndex >= 0 &&
            currentIndex < kServiceRequestAdvanceOrder.length - 1
        ? kServiceRequestAdvanceOrder[currentIndex + 1]
        : null;
    if (nextStatus == null) return const SizedBox.shrink();

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(backgroundColor: _pink),
        onPressed: _updating ? null : () => _advanceTo(nextStatus),
        child: _updating
            ? const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : Text(
                _buttonLabelFor(nextStatus),
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
      ),
    );
  }
}
