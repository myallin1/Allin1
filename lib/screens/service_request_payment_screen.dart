// ================================================================
// service_request_payment_screen.dart — Unified Hero Task System:
// customer-facing final-bill display + payment for a completed
// service_requests task (hero_booking / custom_order /
// custom_food_order / grocery_order).
//
// Deliberately a SEPARATE screen from payment_screen.dart rather than
// a retrofit of it — payment_screen.dart is hardcoded throughout to
// the `rides` collection (collection('rides').doc(rideDocId) appears
// at ~6 call sites: wallet debit transaction, hero payout, dispute
// recheck, etc.). Branching that already-live, already-tested ride
// payment flow on a collection name risked real regressions to a
// working revenue path for no benefit — this screen instead reuses
// the same visual language (AnimatedMeterFare, premium pink/white)
// and a deliberately narrower feature set: no wallet-balance debit
// flow, no dispute-recovery banner (neither concept exists yet for
// service_requests) — just live final-amount display + a manual
// "mark as paid" action, matching v1's scope (manual entry, no
// payment-gateway integration, per the Unified Hero Task System
// design decision).
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/service_request_model.dart';
import '../widgets/animated_meter_fare.dart';
import '../widgets/rating_feedback_sheet.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kGreen = Color(0xFF00C853);
const Color _kBorder = Color(0xFFEEEEF5);

class ServiceRequestPaymentScreen extends StatefulWidget {
  final String requestId;
  const ServiceRequestPaymentScreen({required this.requestId, super.key});

  @override
  State<ServiceRequestPaymentScreen> createState() =>
      _ServiceRequestPaymentScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
  }
}

class _ServiceRequestPaymentScreenState
    extends State<ServiceRequestPaymentScreen> {
  // FIX (per Nizam's explicit request — reversing the earlier
  // "customer confirms" design): the customer used to be able to tap
  // "UPI"/"Cash" here and unilaterally set the task to 'paid' — closing
  // it and unlocking their own rating screen with zero confirmation
  // from the hero, which let a customer walk away without ever paying.
  // The self-attest buttons and their handlers (_pay,
  // _confirmHeroMarkedPaid) are removed entirely; only the hero's own
  // "Payment Received" action (hero_home_screen.dart ->
  // markServiceRequestPaymentReceived) can now set 'paid'. This screen
  // is now read-only for the customer until that happens.

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _kText, size: 20,),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Task Bill',
            style: GoogleFonts.outfit(
                color: _kText, fontWeight: FontWeight.w800, fontSize: 18,),),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('service_requests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _kPink),);
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
                child: Text('Task not found.',
                    style: TextStyle(color: _kMuted),),);
          }

          final request = ServiceRequestModel.fromFirestore(
              snapshot.data!.data()!, snapshot.data!.id,);
          final finalAmount = request.finalAmount?.toDouble();
          final estimatedAmount = request.estimatedAmount?.toDouble();
          final paymentStatus = request.paymentStatus ?? '';
          final isPaid = paymentStatus == 'paid';
          final amount = finalAmount ?? estimatedAmount ?? 0;
          final assignedHeroId = request.assignedHeroId;
          // Not yet rated — RatingFeedbackSheet itself has no
          // "already submitted" awareness, so this doc-level check is
          // what keeps it from reappearing after the customer rates.
          // customerRating has no model field (root-level, not covered
          // by rawDetails, which is scoped to the `details` submap) —
          // read it directly off the raw doc, same pattern used in
          // hero_booking_tracking_screen.dart.
          final needsRating = isPaid &&
              snapshot.data!.data()!['customerRating'] == null;

          return Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Container(
                  padding: const EdgeInsets.all(24),
                  decoration: BoxDecoration(
                    color: _kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _kBorder),
                  ),
                  child: Column(
                    children: [
                      Text(
                        finalAmount != null ? 'Final Bill' : 'Estimated Amount',
                        style: GoogleFonts.outfit(
                            color: _kMuted,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,),
                      ),
                      const SizedBox(height: 8),
                      AnimatedMeterFare(
                        value: amount,
                        style: GoogleFonts.outfit(
                            color: _kText,
                            fontSize: 40,
                            fontWeight: FontWeight.w900,),
                      ),
                      if (isPaid) ...[
                        const SizedBox(height: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6,),
                          decoration: BoxDecoration(
                            color: _kGreen.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(999),
                          ),
                          child: Text(
                            'Paid',
                            style: GoogleFonts.outfit(
                                color: _kGreen,
                                fontSize: 12,
                                fontWeight: FontWeight.w800,),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const Spacer(),
                // FIX (per Nizam's explicit request): this screen is now
                // read-only for the customer regarding payment — only
                // the hero's own "Payment Received" action
                // (hero_home_screen.dart) can set paymentStatus:'paid'.
                // No self-attest buttons here anymore.
                if (!isPaid && finalAmount != null) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFD980)),
                    ),
                    child: Text(
                      'Please pay your hero ₹${amount.toStringAsFixed(0)} '
                      'directly (Cash or UPI). This task will close and '
                      'your rating page will appear as soon as your hero '
                      'confirms the payment was received.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: _kText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,),
                    ),
                  ),
                ] else if (!isPaid) ...[
                  const Text(
                    'Waiting for the hero to complete the task and generate the final bill.',
                    style: TextStyle(color: _kMuted, fontSize: 12),
                    textAlign: TextAlign.center,
                  ),
                ] else if (needsRating) ...[
                  Text('Rate your Hero',
                      style: GoogleFonts.outfit(
                          color: _kText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,),),
                  const SizedBox(height: 10),
                  RatingFeedbackSheet(
                    completionCollection: 'service_requests',
                    docId: widget.requestId,
                    rateeCollection: assignedHeroId != null ? 'heroes' : null,
                    rateeId: assignedHeroId,
                    onSubmitted: (_) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Thanks for rating your Hero!'),),
                        );
                      }
                    },
                  ),
                ],
              ],
            ),
          );
        },
      ),
    );
  }

}
