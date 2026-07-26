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
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../utils/service_request_labels.dart';
import '../service_request_tracking_screen.dart';
import 'admin_new_orders_screen.dart' show AssignHeroSheet, requestSummary;

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
}

class _AdminServiceRequestsScreenState extends State<AdminServiceRequestsScreen>
    with WidgetsBindingObserver {
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _requests = [];
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
        .snapshots()
        .listen(
      (snapshot) {
        if (mounted) setState(() => _requests = snapshot.docs);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(widget.title,
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800)),
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
                    color: _pink, fontSize: 12, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
      body: _requests.isEmpty
          ? const Center(
              child: Text('No requests yet', style: TextStyle(color: _muted)))
          : ListView.builder(
              padding: const EdgeInsets.all(12),
              itemCount: _requests.length,
              itemBuilder: (context, i) => _buildCard(_requests[i]),
            ),
    );
  }

  Widget _buildCard(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final customerName = data['customerName'] as String? ?? 'Customer';
    final customerPhone = data['customerPhone'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final assignedHeroName = data['assignedHeroName'] as String?;
    final details = Map<String, dynamic>.from(data['details'] as Map? ?? {});
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel(widget.requestType, status);
    // No hero has this yet — offer the manual-assign path.
    final needsAssignment = status == 'pending' || status == 'admin_review';
    final summary = requestSummary(widget.requestType, details);

    return Card(
      color: _card,
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: const BorderSide(color: _border)),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Tap anywhere on the card → the same graphical step tracker
        // the customer sees for this request.
        onTap: () => _openTracking(doc.id),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                        color: statusColor.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8)),
                    child: Text(statusLabel,
                        style: TextStyle(
                            color: statusColor,
                            fontSize: 10,
                            fontWeight: FontWeight.bold)),
                  ),
                  const Spacer(),
                  IconButton(
                    onPressed: () => _call(customerPhone),
                    icon: const Icon(Icons.call_rounded,
                        color: _green, size: 20),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(customerName,
                  style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w700,
                      fontSize: 14)),
              if (customerPhone.isNotEmpty)
                Text(customerPhone,
                    style: const TextStyle(color: _muted, fontSize: 11)),
              if (assignedHeroName != null && assignedHeroName.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text('Hero: $assignedHeroName',
                    style: const TextStyle(color: _muted, fontSize: 11)),
              ],
              if (summary.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(summary,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: _muted, fontSize: 12)),
              ],
              const SizedBox(height: 10),
              Row(
                children: [
                  if (needsAssignment)
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(backgroundColor: _pink),
                        onPressed: () =>
                            _showAssignSheet(doc.id, customerName),
                        child: const Text('Assign to Hero',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold)),
                      ),
                    )
                  else
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => _openTracking(doc.id),
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
