import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _kGold = Color(0xFFFFBB00);
const Color _kMuted = Color(0xFF9999BB);
const Color _kSurface = Color(0xFFF8F8FF);

/// Inline star-rating + optional feedback widget shown after a
/// completed ride/order (e.g. below the payment summary).
///
/// On submit it:
///  1. Writes `customerRating` (and `customerFeedback`, if any) onto
///     `completionCollection/docId`.
///  2. If `rateeCollection` + `rateeId` are supplied, recomputes and
///     stores the ratee's average rating — mirroring the exact
///     aggregate pattern used by `_HeroRatingSheet` in
///     ride_tracking_screen.dart (query completions by `<ratee>Id`,
///     average `customerRating`, write `<ratee>Rating` on the ratee doc).
///  3. Calls `onSubmitted(rating)`.
class RatingFeedbackSheet extends StatefulWidget {
  final String completionCollection;
  final String docId;
  final String? rateeCollection;
  final String? rateeId;
  final ValueChanged<int> onSubmitted;

  const RatingFeedbackSheet({
    required this.completionCollection, required this.docId, required this.onSubmitted, super.key,
    this.rateeCollection,
    this.rateeId,
  });

  @override
  State<RatingFeedbackSheet> createState() => _RatingFeedbackSheetState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('completionCollection', completionCollection));
    properties.add(StringProperty('docId', docId));
    properties.add(StringProperty('rateeCollection', rateeCollection));
    properties.add(StringProperty('rateeId', rateeId));
    properties.add(ObjectFlagProperty<ValueChanged<int>>.has('onSubmitted', onSubmitted));
  }
}

class _RatingFeedbackSheetState extends State<RatingFeedbackSheet> {
  int _rating = 0;
  bool _submitting = false;
  final _feedbackCtrl = TextEditingController();

  @override
  void dispose() {
    _feedbackCtrl.dispose();
    super.dispose();
  }

  String get _rateeSingular {
    final c = widget.rateeCollection ?? '';
    return c.endsWith('s') ? c.substring(0, c.length - 1) : c;
  }

  Future<void> _submit() async {
    if (_rating == 0 || _submitting) return;
    setState(() => _submitting = true);
    try {
      await FirebaseFirestore.instance
          .collection(widget.completionCollection)
          .doc(widget.docId)
          .set({
        'customerRating': _rating,
        'ratedAt': FieldValue.serverTimestamp(),
        if (_feedbackCtrl.text.trim().isNotEmpty)
          'customerFeedback': _feedbackCtrl.text.trim(),
      }, SetOptions(merge: true),);

      final rateeCollection = widget.rateeCollection;
      final rateeId = widget.rateeId;
      if (rateeCollection != null && rateeId != null && rateeId.isNotEmpty) {
        await updateRateeRatingAverage(
          completionCollection: widget.completionCollection,
          rateeCollection: rateeCollection,
          rateeId: rateeId,
          rateeSingular: _rateeSingular,
          newRating: _rating,
        );
      }
    } catch (e) {
      debugPrint('[RatingFeedbackSheet] Save failed: $e');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
    widget.onSubmitted(_rating);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final starIndex = i + 1;
              return IconButton(
                onPressed: _submitting
                    ? null
                    : () => setState(() => _rating = starIndex),
                icon: Icon(
                  starIndex <= _rating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _kGold,
                  size: 32,
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _feedbackCtrl,
            enabled: !_submitting,
            maxLines: 2,
            style: const TextStyle(fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Any feedback? (optional)',
              hintStyle: TextStyle(color: _kMuted.withValues(alpha: 0.6), fontSize: 13),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _kGold,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              onPressed: (_rating == 0 || _submitting) ? null : _submit,
              child: _submitting
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : Text('Submit Rating', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ],
      ),
    );
  }
}

// FIX (database-wastage audit, Sep 2026): shared by RatingFeedbackSheet
// above and ride_tracking_screen.dart's hero-rating flow — both used to
// independently re-fetch EVERY prior completion doc for a ratee
// (`where(idField).where('customerRating', > 0).get()`) on every single
// new rating, just to recompute an average. Cost grew unbounded with
// the ratee's entire rating history, forever, and the exact same wasteful
// query was duplicated in two places. This now maintains running
// `<rateeSingular>RatingSum`/`<rateeSingular>RatingCount` totals on the
// ratee doc — one extra doc read (the ratee doc itself, inside a
// transaction) per rating instead of N historical-completion reads.
//
// CORRECTNESS (why this can't just start both counters at 0): a ratee
// rated before this fix shipped already has a correct
// `<rateeSingular>Rating` average on their doc, computed from real
// history — but no stored sum/count to resume from. Starting fresh at 0
// would silently overwrite months of real rating history with "just
// this one rating" the moment their next rating comes in. So the FIRST
// rating after this fix for any given ratee pays the same one-time
// full-history scan the old code always paid (seeding sum/count
// correctly from real data); every rating after that for the same
// ratee is cheap.
Future<void> updateRateeRatingAverage({
  required String completionCollection,
  required String rateeCollection,
  required String rateeId,
  required String rateeSingular,
  required int newRating,
}) async {
  final rateeRef =
      FirebaseFirestore.instance.collection(rateeCollection).doc(rateeId);
  final sumField = '${rateeSingular}RatingSum';
  final countField = '${rateeSingular}RatingCount';
  final ratingField = '${rateeSingular}Rating';

  // Peek once, outside the transaction, to decide whether a one-time
  // seed scan is needed. The transaction below re-checks this itself
  // before trusting the seed, so a second rating racing in during this
  // peek can't cause double-seeding.
  final peek = await rateeRef.get();
  double? seedSum;
  int? seedCount;
  if (peek.data()?[countField] == null) {
    final idField = '${rateeSingular}Id';
    final snap = await FirebaseFirestore.instance
        .collection(completionCollection)
        .where(idField, isEqualTo: rateeId)
        .where('customerRating', isGreaterThan: 0)
        .get();
    seedSum = snap.docs.fold<double>(
        0, (s, d) => s + ((d.data()['customerRating'] as num?)?.toDouble() ?? 0),);
    seedCount = snap.docs.length;
  }

  await FirebaseFirestore.instance.runTransaction((tx) async {
    final rateeSnap = await tx.get(rateeRef);
    final data = rateeSnap.data();
    final double sum;
    final int count;
    if (data?[countField] != null) {
      sum = (data![sumField] as num?)?.toDouble() ?? 0;
      count = (data[countField] as num?)?.toInt() ?? 0;
    } else {
      // Still unseeded at transaction time — use the values found
      // during the peek above (or 0/0 if this ratee genuinely has no
      // prior ratings at all).
      sum = seedSum ?? 0;
      count = seedCount ?? 0;
    }
    final newSum = sum + newRating;
    final newCount = count + 1;
    tx.set(rateeRef, {
      sumField: newSum,
      countField: newCount,
      ratingField: newSum / newCount,
    }, SetOptions(merge: true),);
  });
}
