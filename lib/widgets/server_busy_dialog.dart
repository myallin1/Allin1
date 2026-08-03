import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/theme_service.dart';

/// Shown whenever a customer-facing booking/order write fails (e.g. Firestore
/// quota/limit exceeded, network drop, etc). Instead of a generic error
/// SnackBar, this gives the customer an immediate way to still get help:
/// call the NJ TECH call center directly, or open WhatsApp to the same
/// number. Matches the app's pink brand theme.
///
/// Usage: `showServerBusyDialog(context);` from any booking/order catch
/// block when the write to Firestore/RTDB fails.
const String kCallCenterNumber = '8681869091';
const String kCallCenterNumberIntl = '918681869091'; // for wa.me (needs country code, no +/spaces)

Future<void> showServerBusyDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    barrierDismissible: true,
    builder: (dialogContext) => const _ServerBusyDialogContent(),
  );
}

class _ServerBusyDialogContent extends StatelessWidget {
  const _ServerBusyDialogContent();

  static const Color kWhatsApp = Color(0xFF25D366);

  Future<void> _callCenter(BuildContext context) async {
    final uri = Uri(scheme: 'tel', path: kCallCenterNumber);
    if (!await launchUrl(uri)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open dialer. Please dial $kCallCenterNumber manually.')),
        );
      }
    }
  }

  Future<void> _openWhatsApp(BuildContext context) async {
    final uri = Uri.parse('https://wa.me/$kCallCenterNumberIntl');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Could not open WhatsApp. Please message $kCallCenterNumber manually.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // FIX (Nizam's full Option 2 rollout): was a hardcoded static const
    // pink regardless of selected theme. Reads the live theme's primary
    // color instead, falling back to the original pink if this dialog
    // is ever shown somewhere ThemeService isn't provided.
    Color pink = const Color(0xFFFF4FA3);
    try {
      pink = Provider.of<ThemeService>(context, listen: false).currentTheme.colorScheme.primary;
    } catch (_) {
      // keep default
    }
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: Container(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          boxShadow: [
            BoxShadow(color: pink.withValues(alpha: 0.2), blurRadius: 30, offset: const Offset(0, 12)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: pink.withValues(alpha: 0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(Icons.cloud_off_rounded, color: pink, size: 32),
            ),
            const SizedBox(height: 18),
            Text(
              'Server Busy',
              style: GoogleFonts.outfit(fontSize: 19, fontWeight: FontWeight.w800, color: const Color(0xFF1A1A26)),
            ),
            const SizedBox(height: 8),
            Text(
              // FIX (per Nizam's request): replaced the mixed
              // Tamil+English text with plain English, consistent with
              // the rest of the app's dialogs.
              'Our server is busy right now and your booking couldn\'t go through.\nPlease contact our call center — we\'ll help you right away.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(fontSize: 13.5, color: const Color(0xFF6B6B80), height: 1.5),
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () => _callCenter(context),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: const Text('Call Center'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: pink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: () => _openWhatsApp(context),
                icon: const Icon(Icons.chat_rounded, size: 18),
                label: const Text('WhatsApp Now'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: kWhatsApp,
                  side: const BorderSide(color: kWhatsApp, width: 1.5),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  textStyle: GoogleFonts.outfit(fontSize: 14.5, fontWeight: FontWeight.w700),
                ),
              ),
            ),
            const SizedBox(height: 6),
            TextButton(
              onPressed: () => Navigator.of(context).pop(),
              child: Text('Close', style: GoogleFonts.outfit(color: const Color(0xFF9999AA), fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      ),
    );
  }
}
