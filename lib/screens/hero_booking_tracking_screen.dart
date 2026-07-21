// ================================================================
// hero_booking_tracking_screen.dart — Broadcast Order System:
// Hero Booking detail tracking screen.
//
// Unlike service_request_tracking_screen.dart (keyed by a single
// requestId passed in by the caller), this screen is keyed by the
// current customer: it queries their most recent, not-yet-completed
// hero_booking request live, the same way the dashboard's
// _ActiveHeroBookingCard resolves which request to show. This means
// it stays correct even if a newer hero-booking request is created
// while this screen is open, and callers never need to already know
// a requestId to open it (e.g. reachable directly from the dashboard
// card with zero extra reads beyond what the card itself already
// does to render).
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/service_request_service.dart';
import '../utils/service_request_labels.dart';
import '../widgets/rating_feedback_sheet.dart';
import '../widgets/stage_progress_tracker.dart';
import 'service_request_live_map_screen.dart';
import 'service_request_payment_screen.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kSurface = Color(0xFFF8F8FF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kGreen = Color(0xFF00C853);
const Color _kBorder = Color(0xFFEEEEF5);

class HeroBookingTrackingScreen extends StatelessWidget {
  /// Which booking to show.
  ///
  /// Null keeps the original behaviour — track whichever hero_booking is
  /// the customer's most recent not-yet-finished one. That was fine when
  /// a customer could only ever have one live booking, but they can book
  /// several tasks at once, and then "most recent" is the wrong answer
  /// for every card except the newest. The booking list now passes the
  /// specific id it was tapped on.
  final String? requestId;

  const HeroBookingTrackingScreen({this.requestId, super.key});

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

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
        title: Text('Hero Booking Status',
            style: GoogleFonts.outfit(
                color: _kText, fontWeight: FontWeight.w800, fontSize: 18,),),
        centerTitle: true,
      ),
      body: user == null
          ? const Center(
              child: Text('Please sign in to view your booking.',
                  style: TextStyle(color: _kMuted),),)
          : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              // Same 2-equality + orderBy(createdAt) shape already proven
              // in production by custom_food_order_screen.dart's
              // _buildMyOrders() — reuses that existing composite index,
              // no new index required. Limit 5 + client-side filter for
              // "not completed" avoids needing a 3rd inequality-filter
              // composite index just for this screen.
              stream: FirebaseFirestore.instance
                  .collection('service_requests')
                  .where('customerId', isEqualTo: user.uid)
                  .where('requestType', isEqualTo: 'hero_booking')
                  .orderBy('createdAt', descending: true)
                  // Was 5. A customer can queue up several tasks at
                  // once, and anything past the cap simply vanished.
                  .limit(20)
                  .snapshots(),
              builder: (context, snapshot) {
                if (snapshot.connectionState == ConnectionState.waiting) {
                  return const Center(
                      child: CircularProgressIndicator(color: _kPink),);
                }
                if (snapshot.hasError) {
                  return const Center(
                      child: Text('Could not load your booking.',
                          style: TextStyle(color: _kMuted),),);
                }

                final docs = snapshot.data?.docs ?? [];
                QueryDocumentSnapshot<Map<String, dynamic>>? active;

                // Caller named a specific booking — show exactly that
                // one, regardless of how many others are live.
                if (requestId != null) {
                  for (final doc in docs) {
                    if (doc.id == requestId) {
                      active = doc;
                      break;
                    }
                  }
                }

                for (final doc in docs) {
                  if (active != null) break;
                  final docData = doc.data();
                  final status = docData['status'] as String? ?? 'pending';
                  final paymentStatus = docData['paymentStatus'] as String?;
                  final customerRating = docData['customerRating'];
                  // A 'completed' task still counts as "active" here
                  // until it's actually paid — otherwise the customer
                  // could never reach the bill/pay step through this
                  // screen (Unified Hero Task System: completed tasks
                  // need a payment-collection phase before they're
                  // truly done, mirroring the ride flow's
                  // 'pending_collection' → 'paid' pattern). Also stays
                  // "active" once paid but not yet rated, so the rating
                  // prompt is reachable even on the cash-close path
                  // (hero's markServiceRequestPaymentReceived() never
                  // routes the customer through the payment screen, so
                  // this screen — which the customer is already on/
                  // returns to — is the only surface that can show it).
                  final fullyDone = status == 'completed' &&
                      paymentStatus == 'paid' &&
                      customerRating != null;
                  if (!fullyDone) {
                    active = doc;
                    break;
                  }
                }

                if (active == null) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24),
                      child: Text(
                        'No active Hero Booking right now.',
                        style: TextStyle(color: _kMuted, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final data = active.data();
                final status = data['status'] as String? ?? 'pending';
                final currentIndex = serviceRequestStatusIndex(status);
                final labels = serviceRequestLabelsFor('hero_booking');
                final etaLabel = heroBookingEtaLabel(status);
                final isAdminReview = status == 'admin_review';
                final heroName = data['assignedHeroName'] as String?;
                final heroPhone = data['assignedHeroPhone'] as String?;
                final details =
                    (data['details'] as Map<String, dynamic>?) ?? const {};
                final taskDescription =
                    (details['taskDescription'] as String?)?.trim();
                final categoryLabel =
                    heroBookingCategoryLabel(details['category'] as String?);
                final fromLocation =
                    (details['fromLocation'] as String?)?.trim();
                final location = (details['location'] as String?)?.trim();
                final specialInstructions =
                    (details['specialInstructions'] as String?)?.trim();
                final preferredTiming =
                    (details['preferredTiming'] as String?)?.trim();
                final scheduledLabel =
                    (preferredTiming != null && preferredTiming != 'asap')
                        ? DateTime.tryParse(preferredTiming)
                        : null;
                final createdAt = data['createdAt'] as Timestamp?;
                final bookedAtLabel = createdAt != null
                    ? DateFormat('d MMM yyyy, h:mm a')
                        .format(createdAt.toDate())
                    : null;
                final estimatedAmount =
                    (data['estimatedAmount'] as num?)?.toDouble();
                final finalAmount = (data['finalAmount'] as num?)?.toDouble();
                final paymentStatus = data['paymentStatus'] as String?;
                final needsPayment =
                    status == 'completed' && paymentStatus != 'paid';
                final assignedHeroId = data['assignedHeroId'] as String?;
                final estimateApprovedByCustomer =
                    data['estimateApprovedByCustomer'] as bool?;
                // Only relevant while the hero hasn't started yet — once
                // in_progress, the hero already got past the gate (see
                // hero_home_screen.dart's _advanceTo), so this card
                // stops being shown even if the field is somehow still
                // null/stale.
                final needsEstimateApproval = status == 'hero_assigned' &&
                    estimatedAmount != null &&
                    estimateApprovedByCustomer != true;
                // Covers the cash-close path: the hero's "Mark Payment
                // Received" action sets paymentStatus:'paid' directly
                // with no customer-facing screen involved, so this
                // screen (which the customer is already viewing, or
                // returns to) is what surfaces the rating prompt.
                final needsRating = status == 'completed' &&
                    paymentStatus == 'paid' &&
                    data['customerRating'] == null;

                // Subtitles are index-aligned with `labels`; only the
                // currently-active stage's subtitle is ever shown by
                // StageProgressTracker, so it's fine that the others
                // are null.
                final subtitles = List<String?>.filled(labels.length, null);
                if (currentIndex < subtitles.length) {
                  subtitles[currentIndex] = etaLabel;
                }

                return SingleChildScrollView(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // ── Task details — what the customer asked for ────
                      // Requirement 3: the detail screen must show both
                      // "what I asked for" and "what stage it's at", not
                      // just the stage tracker.
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        margin: const EdgeInsets.only(bottom: 20),
                        decoration: BoxDecoration(
                          color: _kSurface,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: _kBorder),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (categoryLabel != null) ...[
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 4,),
                                decoration: BoxDecoration(
                                  color: _kPink.withValues(alpha: 0.12),
                                  borderRadius: BorderRadius.circular(999),
                                ),
                                child: Text(
                                  categoryLabel,
                                  style: GoogleFonts.outfit(
                                      color: _kPink,
                                      fontSize: 11,
                                      fontWeight: FontWeight.w800,),
                                ),
                              ),
                              const SizedBox(height: 10),
                            ],
                            if (taskDescription != null &&
                                taskDescription.isNotEmpty) ...[
                              Text(
                                taskDescription,
                                style: GoogleFonts.outfit(
                                    color: _kText,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,),
                              ),
                              const SizedBox(height: 8),
                            ],
                            if (fromLocation != null &&
                                fromLocation.isNotEmpty)
                              _detailRow(Icons.trip_origin_rounded,
                                  'From', fromLocation,),
                            if (location != null && location.isNotEmpty)
                              _detailRow(Icons.place_rounded,
                                  fromLocation != null ? 'To' : 'Location',
                                  location,),
                            if (specialInstructions != null &&
                                specialInstructions.isNotEmpty)
                              _detailRow(Icons.notes_rounded,
                                  'Instructions', specialInstructions,),
                            if (scheduledLabel != null)
                              _detailRow(
                                Icons.schedule_rounded,
                                'Scheduled for',
                                DateFormat('d MMM, h:mm a')
                                    .format(scheduledLabel),
                              ),
                            // Unified Hero Task System: manually-entered
                            // amount, shown as soon as the hero (or admin)
                            // sets it — before that, nothing is shown here
                            // rather than a misleading ₹0.
                            if (finalAmount != null)
                              _detailRow(Icons.receipt_long_rounded,
                                  'Final bill', '₹${finalAmount.toStringAsFixed(0)}',)
                            else if (estimatedAmount != null)
                              _detailRow(Icons.payments_outlined,
                                  'Estimated', '₹${estimatedAmount.toStringAsFixed(0)}',),
                            if (bookedAtLabel != null) ...[
                              const SizedBox(height: 4),
                              Text(
                                'Booked on $bookedAtLabel',
                                style: const TextStyle(
                                    color: _kMuted, fontSize: 11,),
                              ),
                            ],
                          ],
                        ),
                      ),
                      if (needsEstimateApproval)
                        _EstimateApprovalCard(
                          requestId: active!.id,
                          amount: estimatedAmount!,
                        ),
                      if (needsPayment)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 20),
                          child: SizedBox(
                            width: double.infinity,
                            child: ElevatedButton.icon(
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ServiceRequestPaymentScreen(
                                    requestId: active!.id,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.payments_rounded,
                                  color: Colors.white,),
                              label: Text('View Bill & Pay',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w700,),),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: _kPink,
                                padding:
                                    const EdgeInsets.symmetric(vertical: 14),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      if (needsRating)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(16),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: _kSurface,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(color: _kBorder),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Rate your Hero',
                                  style: GoogleFonts.outfit(
                                      color: _kText,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w700,),),
                              const SizedBox(height: 10),
                              RatingFeedbackSheet(
                                completionCollection: 'service_requests',
                                docId: active!.id,
                                rateeCollection:
                                    assignedHeroId != null ? 'heroes' : null,
                                rateeId: assignedHeroId,
                                onSubmitted: (_) {
                                  if (context.mounted) {
                                    ScaffoldMessenger.of(context)
                                        .showSnackBar(
                                      const SnackBar(
                                          content: Text(
                                              'Thanks for rating your Hero!',),),
                                    );
                                  }
                                },
                              ),
                            ],
                          ),
                        ),
                      if (isAdminReview)
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(14),
                          margin: const EdgeInsets.only(bottom: 20),
                          decoration: BoxDecoration(
                            color: Colors.orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(
                                color: Colors.orange.withValues(alpha: 0.3),),
                          ),
                          child: const Text(
                            'Our team is personally arranging a Hero for you — this may take a little longer than usual.',
                            style: TextStyle(
                                color: Colors.orange,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,),
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
                                child: Text(
                                  heroName.isNotEmpty
                                      ? heroName[0].toUpperCase()
                                      : 'H',
                                  style: const TextStyle(
                                      color: _kPink,
                                      fontWeight: FontWeight.w800,),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment:
                                      CrossAxisAlignment.start,
                                  children: [
                                    Text(heroName,
                                        style: GoogleFonts.outfit(
                                            color: _kText,
                                            fontWeight: FontWeight.w800,
                                            fontSize: 14,),),
                                    const Text('Your assigned Hero',
                                        style: TextStyle(
                                            color: _kMuted, fontSize: 11,),),
                                  ],
                                ),
                              ),
                              if (heroPhone != null && heroPhone.isNotEmpty)
                                IconButton(
                                  onPressed: () async {
                                    final uri = Uri.parse('tel:$heroPhone');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  },
                                  icon: const Icon(Icons.call_rounded,
                                      color: _kGreen,),
                                ),
                            ],
                          ),
                        ),
                      if (status != 'completed' && status != 'admin_review')
                        Padding(
                          padding: const EdgeInsets.only(bottom: 16),
                          child: SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              onPressed: () => Navigator.push<void>(
                                context,
                                MaterialPageRoute<void>(
                                  builder: (_) => ServiceRequestLiveMapScreen(
                                    requestId: active!.id,
                                  ),
                                ),
                              ),
                              icon: const Icon(Icons.map_rounded,
                                  color: _kPink,),
                              label: Text('Open in Maps',
                                  style: GoogleFonts.outfit(
                                      color: _kPink,
                                      fontWeight: FontWeight.w700,),),
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(color: _kPink),
                                padding:
                                    const EdgeInsets.symmetric(vertical: 12),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(14),
                                ),
                              ),
                            ),
                          ),
                        ),
                      StageProgressTracker(
                        stages: labels,
                        currentIndex: currentIndex,
                        stageSubtitles: subtitles,
                        accentColor: _kPink,
                        completedColor: _kGreen,
                        mutedColor: _kMuted,
                        borderColor: _kBorder,
                        textColor: _kText,
                        compact: true,
                      ),
                      // Cancellable only up through 'hero_assigned' (index
                      // <= 1: pending/admin_review both map to 0, hero_
                      // assigned maps to 1) — once the hero has actually
                      // started (in_progress/nearing_completion), the
                      // customer can no longer self-cancel.
                      if (currentIndex <= 1) ...[
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: OutlinedButton(
                            onPressed: () =>
                                _confirmAndCancel(context, active!.id),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red,
                              side: const BorderSide(color: Colors.red),
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                            child: const Text('Cancel Task'),
                          ),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
    );
  }

  Future<void> _confirmAndCancel(BuildContext context, String requestId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Cancel this task?'),
        content: const Text(
          'This will cancel your Hero Booking request. This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Task'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Cancel Task'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      await ServiceRequestService().cancelServiceRequest(requestId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task cancelled.')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not cancel: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  // Requirement 4 support: small icon + label + value row used inside
  // the compact task-details card above.
  Widget _detailRow(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: _kMuted, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: '$label: ',
                    style: const TextStyle(
                        color: _kMuted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,),
                  ),
                  TextSpan(
                    text: value,
                    style: const TextStyle(color: _kText, fontSize: 12),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ── Customer-approval-of-estimate card ────────────────────────────
// Shown while the hero has quoted an estimate but the customer hasn't
// responded yet (estimateApprovedByCustomer == null). Approving
// unblocks the hero's "Start" button (see _ServiceRequestStatusCard
// in hero_home_screen.dart); rejecting clears the estimate so the
// hero can submit a revised one, re-showing this same card.
class _EstimateApprovalCard extends StatefulWidget {
  final String requestId;
  final double amount;
  const _EstimateApprovalCard({required this.requestId, required this.amount});

  @override
  State<_EstimateApprovalCard> createState() => _EstimateApprovalCardState();
}

class _EstimateApprovalCardState extends State<_EstimateApprovalCard> {
  bool _submitting = false;

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
        color: _kPink.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPink.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Your Hero quoted an estimate',
              style: GoogleFonts.outfit(
                  color: _kText, fontSize: 13, fontWeight: FontWeight.w700,),),
          const SizedBox(height: 6),
          Text('₹${widget.amount.toStringAsFixed(0)}',
              style: GoogleFonts.outfit(
                  color: _kPink, fontSize: 26, fontWeight: FontWeight.w900,),),
          const SizedBox(height: 4),
          const Text(
            'Approve to let your Hero start the task, or reject if the amount seems off.',
            style: TextStyle(color: _kMuted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting ? null : () => _respond(false),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    side: const BorderSide(color: Colors.red),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),),
                  ),
                  child: const Text('Reject'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton(
                  onPressed: _submitting ? null : () => _respond(true),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _kPink,
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
