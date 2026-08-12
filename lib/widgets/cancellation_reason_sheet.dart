// ================================================================
// cancellation_reason_sheet.dart — Cancellation Reason Analytics
// ================================================================
// NEW (Aug 11 2026, per Nizam — "we are losing valuable business data
// on WHY customers cancel"). Shared bottom sheet used by every
// customer-side cancel action (ride search cancel, active-ride cancel,
// service-request cancel) so the reason list/wording/behavior is
// identical everywhere instead of three copies drifting apart.
//
// Contract: returns the selected reason String, or null if the
// customer dismissed the sheet without picking one. Callers MUST treat
// null as "do not cancel" — per Nizam's explicit spec, tapping Cancel
// no longer cancels immediately; the reason pick IS the confirmation.
// ================================================================
import 'package:flutter/material.dart';

const List<String> kCancellationReasons = <String>[
  'Driver is too far',
  'Changed my mind',
  'Wait time is too long',
  'Booked by mistake',
  'Other',
];

const Color _bg = Colors.white;
const Color _pink = Color(0xFFFF4FA3);
const Color _text = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF8F5A78);
const Color _red = Color(0xFFFF5252);

/// Shows the reason picker. Returns the picked reason, or null if the
/// customer backed out without picking (caller should NOT cancel).
Future<String?> showCancellationReasonSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: _bg,
    isDismissible: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (context) => const _CancellationReasonSheet(),
  );
}

class _CancellationReasonSheet extends StatefulWidget {
  const _CancellationReasonSheet();

  @override
  State<_CancellationReasonSheet> createState() =>
      _CancellationReasonSheetState();
}

class _CancellationReasonSheetState extends State<_CancellationReasonSheet> {
  String? _selected;
  final _otherController = TextEditingController();

  @override
  void dispose() {
    _otherController.dispose();
    super.dispose();
  }

  void _confirm(String reason) {
    Navigator.of(context).pop(reason);
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: EdgeInsets.only(
          left: 20,
          right: 20,
          top: 16,
          bottom: MediaQuery.of(context).viewInsets.bottom + 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Why are you cancelling?',
              style: TextStyle(
                color: _text,
                fontSize: 16,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 4),
            const Text(
              'This helps us improve — pick the closest reason.',
              style: TextStyle(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            for (final reason in kCancellationReasons)
              if (reason == 'Other')
                _OtherRow(
                  selected: _selected == 'Other',
                  controller: _otherController,
                  onTap: () => setState(() => _selected = 'Other'),
                  onSubmit: () {
                    final text = _otherController.text.trim();
                    _confirm(text.isEmpty ? 'Other' : 'Other: $text');
                  },
                )
              else
                _ReasonRow(
                  label: reason,
                  onTap: () => _confirm(reason),
                ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text("Don't cancel",
                  style: TextStyle(color: _muted, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}

class _ReasonRow extends StatelessWidget {
  const _ReasonRow({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        decoration: BoxDecoration(
          color: const Color(0xFFFFF1F8),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: _pink.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Expanded(
              child: Text(
                label,
                style: const TextStyle(
                  color: _text,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 20),
          ],
        ),
      ),
    );
  }
}

class _OtherRow extends StatelessWidget {
  const _OtherRow({
    required this.selected,
    required this.controller,
    required this.onTap,
    required this.onSubmit,
  });
  final bool selected;
  final TextEditingController controller;
  final VoidCallback onTap;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    if (!selected) {
      return _ReasonRow(label: 'Other', onTap: onTap);
    }
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF1F8),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _pink.withValues(alpha: 0.4)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('Other',
              style: TextStyle(
                  color: _text, fontSize: 13.5, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          TextField(
            controller: controller,
            autofocus: true,
            maxLines: 2,
            style: const TextStyle(color: _text, fontSize: 13),
            decoration: InputDecoration(
              isDense: true,
              hintText: 'Tell us a bit more (optional)',
              hintStyle: const TextStyle(color: _muted, fontSize: 12),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide.none,
              ),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSubmit,
              style: ElevatedButton.styleFrom(
                backgroundColor: _red,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10),
                ),
              ),
              child: const Text('Confirm Cancellation'),
            ),
          ),
        ],
      ),
    );
  }
}
