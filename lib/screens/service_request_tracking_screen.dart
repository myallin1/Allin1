// ================================================================
// service_request_tracking_screen.dart — Broadcast Order System
// Single shared tracking screen for all 4 request categories.
// `requestType` only picks which label set to display — the
// underlying status enum (pending/hero_assigned/in_progress/
// nearing_completion/completed) is identical for every category and
// is read live from Firestore, whether the update came from the
// hero's app or an admin manual override.
// ================================================================
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../models/service_request_model.dart';
import '../services/service_request_service.dart';
import '../utils/service_request_labels.dart';
import '../widgets/delivery_challan_card.dart';
import '../widgets/estimate_approval_card.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kGreen = Color(0xFF00C853);
const Color _kBorder = Color(0xFFEEEEF5);

// Status→label and status→index mappings now live in
// utils/service_request_labels.dart (single source of truth shared with
// the "My Orders" list on the food page).

class ServiceRequestTrackingScreen extends StatelessWidget {
  final String requestId;
  final String requestType;
  const ServiceRequestTrackingScreen({
    required this.requestId, required this.requestType, super.key,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Track Request', style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 18)),
        centerTitle: true,
      ),
      body: StreamBuilder<ServiceRequestModel?>(
        stream: ServiceRequestService().streamRequest(requestId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _kPink));
          }
          if (!snapshot.hasData || snapshot.data == null) {
            return const Center(child: Text('Request not found.', style: TextStyle(color: _kMuted)));
          }

          final model = snapshot.data!;
          final firestoreStatus = model.status;
          final heroName = model.assignedHeroName;
          final heroPhone = model.assignedHeroPhone;

          // FIX (Phase 4b — WhatsApp/Uber transient model): 'in_progress'
          // and 'nearing_completion' are now written ONLY to
          // active_service_requests/{requestId} in RTDB, not Firestore
          // (see advanceStatus() in service_request_service.dart) — a
          // pure Firestore listener would never show those two steps
          // live anymore. Overlay a second, nested RTDB listener and
          // prefer its status while the node exists (and its status is
          // one of those two transient values); Firestore remains the
          // fallback for every other state, including after the node is
          // deleted on completion — same merge rule already proven for
          // rides in ride_tracking_screen.dart's _listenActiveRideStatus.
          return StreamBuilder<rtdb.DatabaseEvent>(
            stream: rtdb.FirebaseDatabase.instance
                .ref('active_service_requests/$requestId')
                .onValue,
            builder: (context, rtdbSnapshot) {
              String status = firestoreStatus;
              final raw = rtdbSnapshot.data?.snapshot.value;
              if (raw is Map) {
                final rtdbStatus = raw['status'] as String?;
                if (rtdbStatus == 'in_progress' ||
                    rtdbStatus == 'nearing_completion') {
                  status = rtdbStatus!;
                }
              }
              final currentIndex = serviceRequestStatusIndex(status);
              final isAdminReview = status == 'admin_review';

              // Merge the live (possibly RTDB-overlaid) status into the
              // model handed to DeliveryChallanCard so its embedded
              // TrackingTimeline reflects the same status this screen's
              // own stepper shows, not a stale Firestore-only value.
              final mergedModel = model.copyWith(status: status);

              return _buildBody(
                context,
                isAdminReview: isAdminReview,
                heroName: heroName,
                heroPhone: heroPhone,
                currentIndex: currentIndex,
                requestModel: mergedModel,
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildBody(
    BuildContext context, {
    required bool isAdminReview,
    required String? heroName,
    required String? heroPhone,
    required int currentIndex,
    required ServiceRequestModel requestModel,
  }) {
    final labels = serviceRequestLabelsFor(requestType);
    return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                DeliveryChallanCard(request: requestModel),
                // FIX (Aug 20 2026 audit HIGH-3 — estimate deadlock):
                // the hero's "Start" action is gated on
                // estimateApprovedByCustomer == true (see
                // _ServiceRequestStatusCard in hero_home_screen.dart),
                // but the ONLY customer approve/negotiate UI lived in
                // hero_booking_tracking_screen.dart — so food/grocery
                // orders tracking here deadlocked at 'hero_assigned'
                // forever. Show the shared EstimateApprovalCard whenever
                // an unapproved estimate is outstanding.
                if (requestModel.status == 'hero_assigned' &&
                    requestModel.estimatedAmount != null &&
                    requestModel.estimateApprovedByCustomer != true)
                  EstimateApprovalCard(
                    requestId: requestModel.requestId,
                    amount: requestModel.estimatedAmount!.toDouble(),
                  ),
                if (isAdminReview)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(14),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: Colors.orange.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'Our team is personally arranging a Hero for you — this may take a little longer than usual.',
                      style: TextStyle(color: Colors.orange, fontSize: 12, fontWeight: FontWeight.w600),
                    ),
                  ),
                if (heroName != null && heroName.isNotEmpty)
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    margin: const EdgeInsets.only(bottom: 20),
                    decoration: BoxDecoration(
                      color: _kSurface,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _kBorder),
                    ),
                    child: Row(
                      children: [
                        CircleAvatar(
                          radius: 22,
                          backgroundColor: _kPink.withValues(alpha: 0.15),
                          child: Text(heroName.isNotEmpty ? heroName[0].toUpperCase() : 'H', style: const TextStyle(color: _kPink, fontWeight: FontWeight.w800)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(heroName, style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 14)),
                              const Text('Your assigned Hero', style: TextStyle(color: _kMuted, fontSize: 11)),
                            ],
                          ),
                        ),
                        if (heroPhone != null && heroPhone.isNotEmpty)
                          IconButton(
                            onPressed: () async {
                              final uri = Uri.parse('tel:$heroPhone');
                              if (await canLaunchUrl(uri)) await launchUrl(uri);
                            },
                            icon: const Icon(Icons.call_rounded, color: _kGreen),
                          ),
                      ],
                    ),
                  ),
                _StatusStepper(labels: labels, currentIndex: currentIndex),
              ],
            ),
          );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(StringProperty('requestType', requestType));
  }
}

class _StatusStepper extends StatelessWidget {
  final List<String> labels;
  final int currentIndex;
  const _StatusStepper({required this.labels, required this.currentIndex});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: List.generate(labels.length, (i) {
        final isCompleted = i < currentIndex;
        final isCurrent = i == currentIndex;
        final isLast = i == labels.length - 1;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  _StepCircle(isCompleted: isCompleted, isCurrent: isCurrent),
                  if (!isLast)
                    Expanded(
                      child: Container(
                        width: 2,
                        color: isCompleted ? _kGreen : _kBorder,
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 28, top: 2),
                  child: Text(
                    labels[i],
                    style: GoogleFonts.outfit(
                      color: isCurrent ? _kText : (isCompleted ? _kText : _kMuted),
                      fontSize: 14,
                      fontWeight: isCurrent ? FontWeight.w800 : FontWeight.w600,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<String>('labels', labels));
    properties.add(IntProperty('currentIndex', currentIndex));
  }
}

class _StepCircle extends StatelessWidget {
  final bool isCompleted;
  final bool isCurrent;
  const _StepCircle({required this.isCompleted, required this.isCurrent});

  @override
  Widget build(BuildContext context) {
    if (isCompleted) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(color: _kGreen, shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, color: Colors.white, size: 18),
      );
    }
    if (isCurrent) {
      return Container(
        width: 28,
        height: 28,
        decoration: const BoxDecoration(color: _kPink, shape: BoxShape.circle),
        child: const Icon(Icons.person_rounded, color: Colors.white, size: 16),
      );
    }
    return Container(
      width: 28,
      height: 28,
      decoration: BoxDecoration(
        color: Colors.transparent,
        shape: BoxShape.circle,
        border: Border.all(color: _kBorder, width: 2),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('isCompleted', isCompleted));
    properties.add(DiagnosticsProperty<bool>('isCurrent', isCurrent));
  }
}
