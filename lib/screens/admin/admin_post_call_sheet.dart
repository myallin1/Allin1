// ================================================================
// admin_post_call_sheet.dart — the three follow-up actions offered
// the moment a call ends.
// ================================================================
// NEW (Sep 3 2026 — Nizam: "namma admin app dialer la call atten
// pannitu line cut anathum 3 popup shortcuts....1.messege, 2.redial to
// same person, 3.whatsapp button").
//
// Why a sheet and not a screen: the admin is usually mid-something
// else when a call drops, and the useful window for "message them
// back / call again / WhatsApp them" is a few seconds long. A modal
// bottom sheet keeps whatever they were doing underneath and costs one
// tap to dismiss.
//
// Deliberately does NOT appear for every call the app merely observed
// — see the caller in main_admin.dart, which only shows this while the
// admin app is actually in the foreground with a navigator available.
// Popping a sheet over another app's UI would be intrusive and, on
// modern Android, mostly impossible anyway.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

const Color _card = Color(0xFF16162A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);
const Color _whatsapp = Color(0xFF25D366);

/// Shows the post-call actions for [number]. Safe to call with an
/// empty/garbage number — it simply does nothing, so callers don't
/// need to guard.
Future<void> showAdminPostCallSheet(BuildContext context, String number) {
  final trimmed = number.trim();
  if (trimmed.isEmpty) return Future<void>.value();
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: _card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _PostCallSheet(number: trimmed),
  );
}

class _PostCallSheet extends StatelessWidget {
  const _PostCallSheet({required this.number});

  final String number;

  /// WhatsApp's wa.me links only accept digits (with country code and
  /// no +), so a number stored as "+91 98765 43210" has to be reduced
  /// before it will resolve. Assumes India when no country code is
  /// present, which is true for every number this app deals with.
  String get _whatsappDigits {
    var digits = number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits';
    return digits;
  }

  Future<void> _launch(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    final navigator = Navigator.of(context);
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Nothing on this phone can open $uri')),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Could not open: $e')));
    }
    if (navigator.canPop()) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 14, 20, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: _muted.withValues(alpha: 0.4),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Call ended',
              style: GoogleFonts.outfit(
                  color: _muted, fontSize: 12.5, fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 4),
            Text(
              number,
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 20, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _Action(
                  icon: Icons.message_rounded,
                  color: _purple,
                  label: 'Message',
                  onTap: () => _launch(context, Uri.parse('sms:$number')),
                ),
                _Action(
                  icon: Icons.call_rounded,
                  color: _green,
                  label: 'Redial',
                  onTap: () => _launch(context, Uri.parse('tel:$number')),
                ),
                _Action(
                  icon: Icons.chat_rounded,
                  color: _whatsapp,
                  label: 'WhatsApp',
                  onTap: () => _launch(
                      context, Uri.parse('https://wa.me/$_whatsappDigits')),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _Action extends StatelessWidget {
  const _Action({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color.withValues(alpha: 0.15),
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Icon(icon, color: color, size: 26),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
              color: _text, fontSize: 12.5, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
