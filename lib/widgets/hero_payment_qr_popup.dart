// ================================================================
// hero_payment_qr_popup.dart — the "Self" payment popup
// ================================================================
// NEW (Aug 12 2026 — Nizam's exact flow: "hero app la self nu button
// thottaruna hero upload panni vachurukka avar qr 2sec generate vanthu
// popup ah kaatanum customer atha scan panni pay pannuvaru... hero antha
// popup qr la iruka right corner close dialog press panni close
// pannitu ride complete nu kuduthutu customer ta marakama rating poda
// sollitu kelambiruvaru"):
//
// Call HeroPaymentQrPopup.show(context) from wherever the "Self"
// payment-collection button lives. Deliberately a single reusable
// static entry point — not copy-pasted per screen — so taxi/food/
// parcel/service completion flows can all trigger the exact same popup.
//
// Reads the hero's own locally-saved QR via HeroPaymentQrService (never
// Cloudinary, never Firestore — see that file). If the hero never
// uploaded one, shows a clear "set it up in Settings" message instead
// of a blank/broken popup.
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../services/hero_payment_qr_service.dart';

const Color _kBg = Color(0xFF141420);
const Color _kBorder = Color(0xFF262636);
const Color _kText = Color(0xFFEEEEF5);
const Color _kMuted = Color(0xFF9999BB);
const Color _kPink = Color(0xFFFF4FA3);

class HeroPaymentQrPopup {
  HeroPaymentQrPopup._();

  static Future<void> show(BuildContext context) {
    return showDialog<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black87,
      builder: (_) => const _HeroPaymentQrDialog(),
    );
  }
}

class _HeroPaymentQrDialog extends StatefulWidget {
  const _HeroPaymentQrDialog();

  @override
  State<_HeroPaymentQrDialog> createState() => _HeroPaymentQrDialogState();
}

class _HeroPaymentQrDialogState extends State<_HeroPaymentQrDialog> {
  Uint8List? _qrBytes;
  bool _loading = true;
  bool _checkedOnce = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    // FIX intent: "2 sec la QR popup varanum" — the actual local read is
    // near-instant (no network involved), so a bare instant swap would
    // read as a glitch rather than "generating". A short, deliberate
    // minimum display time on the loading state gives the popup the
    // calm "preparing your QR" feel that was asked for, without ever
    // making the hero wait longer than that even on a slow device.
    final results = await Future.wait([
      HeroPaymentQrService.instance.loadQr(),
      Future<void>.delayed(const Duration(milliseconds: 1200)),
    ]);
    if (!mounted) return;
    setState(() {
      _qrBytes = results[0] as Uint8List?;
      _loading = false;
      _checkedOnce = true;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.all(24),
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: _kBg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _kBorder),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Expanded(
                  child: Text(
                    'Show this to your customer',
                    style: TextStyle(
                      color: _kText,
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                    ),
                  ),
                ),
                // Right-corner close — exactly the tap Nizam described
                // ("right corner close dialog press panni close
                // pannitu ride complete nu kuduthutu") once the
                // customer has actually paid.
                InkWell(
                  borderRadius: BorderRadius.circular(20),
                  onTap: () => Navigator.of(context).pop(),
                  child: const Padding(
                    padding: EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, color: _kMuted, size: 22),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            _buildBody(context),
          ],
        ),
      ),
    );
  }

  Widget _buildBody(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircularProgressIndicator(color: _kPink, strokeWidth: 2.5),
            SizedBox(height: 16),
            Text(
              'Generating your QR…',
              style: TextStyle(color: _kMuted, fontSize: 13),
            ),
          ],
        ),
      );
    }

    if (_checkedOnce && _qrBytes == null) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.qr_code_2_rounded, color: _kMuted, size: 40),
            const SizedBox(height: 12),
            const Text(
              "You haven't uploaded a payment QR yet.",
              textAlign: TextAlign.center,
              style: TextStyle(color: _kText, fontSize: 13.5),
            ),
            const SizedBox(height: 6),
            const Text(
              'Add one from Settings → Payment QR, then this popup will show it here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: _kMuted, fontSize: 11.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              onPressed: () => Navigator.of(context).pop(),
              style: OutlinedButton.styleFrom(
                side: const BorderSide(color: _kBorder),
                foregroundColor: _kText,
              ),
              child: const Text('OK'),
            ),
          ],
        ),
      );
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: Container(
        color: Colors.white,
        padding: const EdgeInsets.all(16),
        child: Image.memory(
          _qrBytes!,
          width: 220,
          height: 220,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
