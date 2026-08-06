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
import '../services/service_request_service.dart';
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
  bool _submitting = false;

  Future<void> _pay(String method) async {
    setState(() => _submitting = true);
    try {
      await ServiceRequestService()
          .markServiceRequestPaid(widget.requestId, method: method);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment recorded. Thank you!')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record payment: $e'),
              backgroundColor: Colors.red,),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  // FIX (payment-trust audit, per Nizam's request): the hero's own
  // "Mark Payment Received (Cash)" button (hero_home_screen.dart) now
  // only writes the interim paymentStatus:'hero_marked_paid' — it can no
  // longer unlock rating by itself. The customer must explicitly confirm
  // here before this becomes the real 'paid' status. "No" just leaves
  // the task in this state; the customer can still pick Cash/UPI
  // themselves below if the hero's claim was wrong.
  Future<void> _confirmHeroMarkedPaid() async {
    setState(() => _submitting = true);
    try {
      await ServiceRequestService()
          .markServiceRequestPaid(widget.requestId, method: 'cash');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Payment confirmed. Thank you!')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not confirm payment: $e'),
              backgroundColor: Colors.red,),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

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
          // Hero claimed cash was received but the customer hasn't
          // confirmed it yet — see FIX comment on
          // markServiceRequestPaymentReceived() in service_request_service.dart.
          final isHeroMarkedPaid = paymentStatus == 'hero_marked_paid';
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
                if (isHeroMarkedPaid) ...[
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFFF6E0),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: const Color(0xFFFFD980)),
                    ),
                    child: Column(
                      children: [
                        Text(
                          'Your hero marked this task as Cash paid. '
                          'Did you actually pay ₹${amount.toStringAsFixed(0)}?',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                              color: _kText,
                              fontSize: 13,
                              fontWeight: FontWeight.w700,),
                        ),
                        const SizedBox(height: 14),
                        SizedBox(
                          width: double.infinity,
                          height: 48,
                          child: ElevatedButton(
                            onPressed:
                                _submitting ? null : _confirmHeroMarkedPaid,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _kGreen,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),),
                            ),
                            child: Text('Yes, I paid this',
                                style: GoogleFonts.outfit(
                                    fontWeight: FontWeight.w800,),),
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'No? Pick how you actually paid below.',
                          style: GoogleFonts.outfit(
                              color: _kMuted, fontSize: 11,),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
                if ((!isPaid && !isHeroMarkedPaid) &&
                    finalAmount != null) ...[
                  Text('Choose how you paid',
                      style: GoogleFonts.outfit(
                          color: _kText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,),),
                  const SizedBox(height: 10),
                  _payMethodButton('UPI', Icons.qr_code_rounded, 'upi'),
                  const SizedBox(height: 10),
                  _payMethodButton('Cash', Icons.payments_rounded, 'cash'),
                ] else if (!isPaid && isHeroMarkedPaid && finalAmount != null) ...[
                  Text('Or choose how you paid',
                      style: GoogleFonts.outfit(
                          color: _kText,
                          fontSize: 14,
                          fontWeight: FontWeight.w700,),),
                  const SizedBox(height: 10),
                  _payMethodButton('UPI', Icons.qr_code_rounded, 'upi'),
                  const SizedBox(height: 10),
                  _payMethodButton('Cash', Icons.payments_rounded, 'cash'),
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

  Widget _payMethodButton(String label, IconData icon, String method) {
    return SizedBox(
      width: double.infinity,
      height: 52,
      child: OutlinedButton.icon(
        onPressed: _submitting ? null : () => _pay(method),
        icon: Icon(icon, color: _kPink),
        label: Text(label,
            style: GoogleFonts.outfit(
                color: _kText, fontWeight: FontWeight.w700,),),
        style: OutlinedButton.styleFrom(
          side: const BorderSide(color: _kBorder),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
          ),
        ),
      ),
    );
  }
}
