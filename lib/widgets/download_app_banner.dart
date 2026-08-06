// ================================================================
// download_app_banner.dart — Universal Side Tray Banner
// ================================================================
// NEW (CTO mandate — Universal Side Tray Banner). Replicates the
// Customer app's "Download App 10x Faster" side-drawer CTA
// (dashboard_screen.dart's inline "Growth Hack: Download App CTA",
// lines ~1928-1969) as a single shared, reusable widget so Admin,
// Hero, and Seller drawers can all show the exact same component
// instead of copy-pasting the gradient Container 3 more times.
// Strictly additive — the Customer app's own inline version is left
// untouched; this widget is new and only wired into the 3 apps that
// didn't have this banner yet.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show Clipboard, ClipboardData;
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/localization_service.dart';
import '../services/update_service.dart';

/// Same visual language as the Customer app's drawer CTA (purple
/// gradient card, rocket emoji, download pill) — tapping it downloads
/// this app's OWN APK (via UpdateService().fallbackApkUrl(appVariant)),
/// since each app (admin/hero/seller) only needs to promote itself,
/// unlike the Customer sheet which offers a choice of Customer+Hero.
class DownloadAppBanner extends StatelessWidget {
  const DownloadAppBanner({super.key, required this.appVariant});

  /// 'admin' | 'hero' | 'seller' — matches UpdateService.fallbackApkUrl's
  /// switch cases.
  final String appVariant;

  static const Color _kPurple = Color(0xFF6C63FF);

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () => unawaited(_downloadApk(context)),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [_kPurple, Color(0xFF5A50C8)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(color: _kPurple.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4)),
            ],
          ),
          child: Row(
            children: [
              const Text('🚀', style: TextStyle(fontSize: 32)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      t('drawer_download_app_title'),
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      t('drawer_download_app_subtitle'),
                      style: const TextStyle(color: Colors.white70, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                child: const Icon(Icons.download_rounded, color: Colors.white, size: 16),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _downloadApk(BuildContext context) async {
    if (context.mounted) Navigator.of(context).maybePop(); // close the drawer first
    final url = UpdateService().fallbackApkUrl(appVariant);
    final uri = Uri.parse(url);
    try {
      final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched && context.mounted) {
        _showDownloadFailedDialog(context, url);
      }
    } catch (_) {
      if (context.mounted) {
        _showDownloadFailedDialog(context, url);
      }
    }
  }

  void _showDownloadFailedDialog(BuildContext context, String url) {
    final t = context.read<LocalizationService>().t;
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(t('download_failed_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t('download_failed_body'), style: const TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 12),
            SelectableText(url, style: const TextStyle(color: Colors.white, fontSize: 12)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: url));
              if (ctx.mounted) {
                ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(t('link_copied_snack'))));
              }
            },
            child: Text(t('copy_link_label'), style: const TextStyle(color: Colors.white70)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(t('close_label'), style: const TextStyle(color: Colors.white38)),
          ),
        ],
      ),
    );
  }
}
