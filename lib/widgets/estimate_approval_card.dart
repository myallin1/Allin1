// ================================================================
// estimate_approval_card.dart — Customer-approval-of-estimate card
// ================================================================
// Shared across every customer-facing tracking screen that shows a
// hero-quoted estimate: hero_booking_tracking_screen.dart AND
// service_request_tracking_screen.dart (the shared tracking screen for
// custom_food_order / catalog_food_order / grocery / hero_booking —
// added Aug 20 2026 after the audit found the food/grocery pipelines
// had NO customer approve/negotiate UI, so the hero's "Start" action
// deadlocked forever on estimateApprovedByCustomer == true).
//
// Shown while the hero has quoted an estimate but the customer hasn't
// responded yet (estimateApprovedByCustomer == null). Approving
// unblocks the hero's "Start" button (see _ServiceRequestStatusCard in
// hero_home_screen.dart); "Negotiate" clears the estimate and sends a
// customer counter-offer back so the hero can submit a revised quote.
//
// This was extracted from hero_booking_tracking_screen.dart's private
// _EstimateApprovalCard so the two screens can never drift apart —
// keep a single source of truth here, mirror the exact visuals.
// ================================================================
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_palette.dart';
import '../services/service_request_service.dart';

class EstimateApprovalCard extends StatefulWidget {
  final String requestId;
  final double amount;
  const EstimateApprovalCard({
    required this.requestId,
    required this.amount,
    super.key,
  });

  @override
  State<EstimateApprovalCard> createState() => _EstimateApprovalCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(DoubleProperty('amount', amount));
  }
}

class _EstimateApprovalCardState extends State<EstimateApprovalCard> {
  bool _submitting = false;

  // "Reject" is "Negotiate" — instead of just clearing the estimate with
  // no context, this asks the customer what amount they'd rather pay and
  // sends that back to the hero as a counter-offer, so the hero knows
  // exactly what to aim for on their revised quote.
  Future<void> _negotiate() async {
    final counter = await _promptForCounterOffer(context, widget.amount);
    if (counter == null || !mounted) return; // cancelled
    setState(() => _submitting = true);
    try {
      await ServiceRequestService()
          .rejectEstimate(widget.requestId, counterOffer: counter);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not send your offer: $e'),
              backgroundColor: Colors.red,),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  Future<void> _respond(bool approve) async {
    setState(() => _submitting = true);
    try {
      if (approve) {
        await ServiceRequestService().approveEstimate(widget.requestId);
      } else {
        await ServiceRequestService().rejectEstimate(widget.requestId);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not record response: $e'),
              backgroundColor: Colors.red,),
        );
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: kPink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kPink.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Hero quoted an estimate',
              style: GoogleFonts.outfit(
                  color: kText, fontSize: 13, fontWeight: FontWeight.w700,),),
          const SizedBox(height: 6),
          Text('₹${widget.amount.toStringAsFixed(0)}',
              style: GoogleFonts.outfit(
                  color: kPink, fontSize: 26, fontWeight: FontWeight.w900,),),
          const SizedBox(height: 4),
          // NOTE: kMuted is a theme-reactive (non-const) palette global
          // from app_palette.dart, so this Text cannot be `const`.
          Text(
            "Approve to let your Hero start the task, or negotiate if you'd like a lower price.",
            style: TextStyle(color: kMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : _negotiate,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: kPink,
                    side: BorderSide(color: kPink),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),),
                  ),
                  child: const Text('Negotiate'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : () => _respond(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kPink,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),),
                  ),
                  child: _submitting
                      ? const SizedBox(width: 16, height: 16,
                          child: CircularProgressIndicator(
                              color: Colors.white, strokeWidth: 2,),)
                      : Text('Approve',
                          style: GoogleFonts.outfit(
                              color: Colors.white, fontWeight: FontWeight.w700,),),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Small dialog letting the customer type the amount they'd rather pay
/// when tapping "Negotiate" — optional, defaults pre-filled just below
/// the hero's quoted amount as a reasonable starting suggestion.
Future<double?> _promptForCounterOffer(
  BuildContext context,
  double currentAmount,
) async {
  final suggested = (currentAmount * 0.85).roundToDouble();
  final controller = TextEditingController(
    text: suggested > 0 ? suggested.toStringAsFixed(0) : '',
  );
  return showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: const Text('What amount would you like to offer?'),
      content: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        autofocus: true,
        decoration: const InputDecoration(prefixText: '₹ '),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        ElevatedButton(
          onPressed: () {
            final value = double.tryParse(controller.text.trim());
            if (value == null || value <= 0) return;
            Navigator.pop(ctx, value);
          },
          style: ElevatedButton.styleFrom(backgroundColor: kPink),
          child: const Text('Send Offer', style: TextStyle(color: Colors.white)),
        ),
      ],
    ),
  );
}
