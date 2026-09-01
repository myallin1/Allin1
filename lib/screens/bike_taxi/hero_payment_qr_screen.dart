// ================================================================
// hero_payment_qr_screen.dart — Settings → Payment QR
// ================================================================
// NEW (Aug 12 2026 — Nizam: "Hero app setting kulla payment qr nu oru
// new option create pannu, athula hero poi avar recieve panna vendiya
// qr change panna anga switch option kudukalam, anga poi hero vera qr
// upload pannunalum angayum qr image perusa iruntha hero crop panni set
// panni vaikurathukum anga facility pannikudu"): lets an ALREADY
// registered hero view, replace, or remove their saved payment QR at
// any time — same pick+crop flow as the registration form (see
// hero_qr_pick_crop.dart), same local-only storage (see
// hero_payment_qr_service.dart), so a hero never has to go back through
// the whole registration form just to update their QR.
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/hero_payment_qr_service.dart';
import '../../widgets/hero_qr_pick_crop.dart';

class HeroPaymentQrScreen extends StatefulWidget {
  const HeroPaymentQrScreen({super.key});

  @override
  State<HeroPaymentQrScreen> createState() => _HeroPaymentQrScreenState();
}

class _HeroPaymentQrScreenState extends State<HeroPaymentQrScreen> {
  static const Color _bg = Color(0xFFFFFBFE);
  static const Color _surface = Colors.white;
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _border = Color(0xFFF0D6E4);

  Uint8List? _qrBytes;
  bool _loading = true;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final bytes = await HeroPaymentQrService.instance.loadQr();
    if (!mounted) return;
    setState(() {
      _qrBytes = bytes;
      _loading = false;
    });
  }

  Future<void> _pickNew() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final cropped = await pickAndCropPaymentQr(context);
      if (cropped == null || !mounted) return;
      await HeroPaymentQrService.instance.saveQr(cropped);
      if (!mounted) return;
      setState(() => _qrBytes = cropped);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment QR updated.'),
          backgroundColor: _pink,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _remove() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Remove payment QR?'),
        content: const Text(
          "Customers won't be able to see a QR from you until you upload a new one.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Remove', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await HeroPaymentQrService.instance.deleteQr();
    if (!mounted) return;
    setState(() => _qrBytes = null);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _text),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Payment QR',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: _loading
              ? const Padding(
                  padding: EdgeInsets.symmetric(vertical: 60),
                  child: Center(child: CircularProgressIndicator(color: _pink)),
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'This is the QR customers scan when they pay you '
                      'directly after a ride/task. Saved on this device '
                      'only — never uploaded anywhere.',
                      style: GoogleFonts.outfit(color: _muted, fontSize: 12.5, height: 1.5),
                    ),
                    const SizedBox(height: 20),
                    Center(
                      child: Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: _surface,
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(color: _border),
                        ),
                        child: _qrBytes != null
                            ? ClipRRect(
                                borderRadius: BorderRadius.circular(12),
                                child: Image.memory(
                                  _qrBytes!,
                                  width: 220,
                                  height: 220,
                                  fit: BoxFit.contain,
                                ),
                              )
                            : Container(
                                width: 220,
                                height: 220,
                                alignment: Alignment.center,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    const Icon(Icons.qr_code_2_rounded, color: _muted, size: 48),
                                    const SizedBox(height: 12),
                                    Text(
                                      'No QR uploaded yet',
                                      style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                                    ),
                                  ],
                                ),
                              ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _busy ? null : _pickNew,
                        icon: _busy
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                              )
                            : const Icon(Icons.upload_rounded, size: 18),
                        label: Text(_qrBytes != null ? 'Replace QR' : 'Upload QR'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _pink,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                    if (_qrBytes != null) ...[
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _busy ? null : _remove,
                          icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                          label: const Text('Remove QR', style: TextStyle(color: Colors.red)),
                          style: OutlinedButton.styleFrom(
                            side: const BorderSide(color: _border),
                            padding: const EdgeInsets.symmetric(vertical: 14),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
        ),
      ),
    );
  }
}
