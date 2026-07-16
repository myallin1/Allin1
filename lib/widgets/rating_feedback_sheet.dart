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
    super.key,
    required this.completionCollection,
    required this.docId,
    this.rateeCollection,
    this.rateeId,
    required this.onSubmitted,
  });

  @override
  State<RatingFeedbackSheet> createState() => _RatingFeedbackSheetState();
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
      }, SetOptions(merge: true));

      final rateeCollection = widget.rateeCollection;
      final rateeId = widget.rateeId;
      if (rateeCollection != null && rateeId != null && rateeId.isNotEmpty) {
        final idField = '${_rateeSingular}Id';
        final ratingField = '${_rateeSingular}Rating';
        final snap = await FirebaseFirestore.instance
            .collection(widget.completionCollection)
            .where(idField, isEqualTo: rateeId)
            .where('customerRating', isGreaterThan: 0)
            .get();
        final avg = snap.docs.fold<double>(0, (s, d) {
              final r = (d.data()['customerRating'] as num?)?.toDouble() ?? 0;
              return s + r;
            }) /
            (snap.docs.isNotEmpty ? snap.docs.length : 1);
        await FirebaseFirestore.instance
            .collection(rateeCollection)
            .doc(rateeId)
            .set({ratingField: avg}, SetOptions(merge: true));
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
