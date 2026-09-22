// ================================================================
// signature_feedback_dialog.dart — 5-Star Customer Rating & Review Modal
// ================================================================
// Appears after delivery to capture customer satisfaction:
// - 1 to 5 Star Interactive Rating
// - Quick compliment tags (Fast Delivery, Original Product, Good Packaging, Polite Rider)
// - Review comments input
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/signature_mobile_service.dart';

const Color _bg = Color(0xFF131326);
const Color _card = Color(0xFF1C1C36);
const Color _gold = Color(0xFFFFD600);
const Color _pink = Color(0xFFFF4FA3);
const Color _green = Color(0xFF00E676);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF8888AA);

class SignatureFeedbackDialog extends StatefulWidget {
  final String orderId;
  final String productName;

  const SignatureFeedbackDialog({
    super.key,
    required this.orderId,
    required this.productName,
  });

  static Future<void> show(BuildContext context, {required String orderId, required String productName}) {
    return showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => SignatureFeedbackDialog(orderId: orderId, productName: productName),
    );
  }

  @override
  State<SignatureFeedbackDialog> createState() => _SignatureFeedbackDialogState();
}

class _SignatureFeedbackDialogState extends State<SignatureFeedbackDialog> {
  int _selectedRating = 5;
  final TextEditingController _commentController = TextEditingController();
  final Set<String> _selectedTags = {'⚡ Fast Delivery', '✨ 100% Genuine'};
  bool _isSubmitting = false;

  final List<String> _availableTags = [
    '⚡ Fast Delivery',
    '✨ 100% Genuine',
    '📦 Safe Packaging',
    '🤝 Friendly Service',
    '🔋 Great Battery',
    '💰 Best Price in Erode',
  ];

  @override
  void dispose() {
    _commentController.dispose();
    super.dispose();
  }

  Future<void> _submitFeedback() async {
    setState(() => _isSubmitting = true);
    try {
      await SignatureMobileService.instance.submitFeedback(
        orderId: widget.orderId,
        rating: _selectedRating,
        feedback: _commentController.text.trim(),
        tags: _selectedTags.toList(),
      );

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🎉 Thank you for your valuable feedback!'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not submit feedback: $e'), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        left: 20,
        right: 20,
        top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 24,
      ),
      decoration: const BoxDecoration(
        color: _bg,
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: _muted.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'Rate Your Experience',
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 18,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            widget.productName,
            style: GoogleFonts.inter(
              color: _pink,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 16),

          // Star Rating Selector
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (index) {
              final star = index + 1;
              return IconButton(
                onPressed: () => setState(() => _selectedRating = star),
                icon: Icon(
                  star <= _selectedRating ? Icons.star_rounded : Icons.star_outline_rounded,
                  color: _gold,
                  size: 38,
                ),
              );
            }),
          ),

          const SizedBox(height: 14),

          // Quick compliment tags
          Wrap(
            spacing: 8,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: _availableTags.map((tag) {
              final isSelected = _selectedTags.contains(tag);
              return FilterChip(
                backgroundColor: _card,
                selectedColor: _pink.withValues(alpha: 0.2),
                side: BorderSide(
                  color: isSelected ? _pink : _muted.withValues(alpha: 0.2),
                ),
                label: Text(
                  tag,
                  style: GoogleFonts.inter(
                    color: isSelected ? _pink : _text,
                    fontSize: 11,
                    fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
                  ),
                ),
                selected: isSelected,
                onSelected: (selected) {
                  setState(() {
                    if (selected) {
                      _selectedTags.add(tag);
                    } else {
                      _selectedTags.remove(tag);
                    }
                  });
                },
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Optional comment
          TextField(
            controller: _commentController,
            maxLines: 2,
            style: GoogleFonts.inter(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Add a comment (e.g. "Amazing display and condition!")...',
              hintStyle: GoogleFonts.inter(color: _muted, fontSize: 12),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(14),
                borderSide: BorderSide.none,
              ),
              contentPadding: const EdgeInsets.all(12),
            ),
          ),

          const SizedBox(height: 18),

          // Submit Button
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitFeedback,
              style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: _isSubmitting
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : Text(
                      'Submit Feedback',
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w700),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}
