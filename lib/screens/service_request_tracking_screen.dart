// ================================================================
// service_request_tracking_screen.dart — Broadcast Order System
// Single shared tracking screen for all 4 request categories.
// `requestType` only picks which label set to display — the
// underlying status enum (pending/hero_assigned/in_progress/
// nearing_completion/completed) is identical for every category and
// is read live from Firestore, whether the update came from the
// hero's app or an admin manual override.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../utils/service_request_labels.dart';

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
    super.key,
    required this.requestId,
    required this.requestType,
  });

  @override
  Widget build(BuildContext context) {
    final labels = serviceRequestLabelsFor(requestType);

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
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('service_requests').doc(requestId).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _kPink));
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(child: Text('Request not found.', style: TextStyle(color: _kMuted)));
          }

          final data = snapshot.data!.data()!;
          final status = data['status'] as String? ?? 'pending';
          final currentIndex = serviceRequestStatusIndex(status);
          final isAdminReview = status == 'admin_review';
          final heroName = data['assignedHeroName'] as String?;
          final heroPhone = data['assignedHeroPhone'] as String?;

          return SingleChildScrollView(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
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
        },
      ),
    );
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
}
