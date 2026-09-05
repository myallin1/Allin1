// ================================================================
// admin_apk_download_progress_sheet.dart — the in-app APK install flow
// ================================================================
// NEW (Sep 2026 — CTO architectural review of PR #61): tapping a .apk
// link inside GitHubEmbeddedScreen or AdminWebBrowserScreen used to
// navigate the WebView itself to the raw binary, which Android's
// WebView cannot render — the practical result was handing the link to
// an external browser (or a blank page) instead of ever installing
// anything. This is the UI half of the fix: both screens' navigation
// delegates now intercept a .apk URL, prevent the WebView from ever
// touching it, and call [showApkDownloadProgressSheet] instead, which
// drives the exact same AppUpdateChecker.downloadAndInstallUrl() the
// admin's own App Versions screen already uses for rollback — one
// download+install code path, not a second one invented for this.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_update_checker.dart';

/// Downloads [apkUrl] with a progress sheet, then hands it to Android's
/// installer. Never throws to the caller — a failed download is shown
/// in the sheet itself with a Close button, not an exception the
/// WebView's navigation delegate would have to handle.
Future<void> showApkDownloadProgressSheet(
  BuildContext context, {
  required String apkUrl,
  required String fileName,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isDismissible: false,
    enableDrag: false,
    backgroundColor: const Color(0xFF1A1A2E),
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ApkDownloadSheet(apkUrl: apkUrl, fileName: fileName),
  );
}

class _ApkDownloadSheet extends StatefulWidget {
  const _ApkDownloadSheet({required this.apkUrl, required this.fileName});

  final String apkUrl;
  final String fileName;

  @override
  State<_ApkDownloadSheet> createState() => _ApkDownloadSheetState();
}

class _ApkDownloadSheetState extends State<_ApkDownloadSheet> {
  double _progress = 0;
  String? _error;
  bool _done = false;

  @override
  void initState() {
    super.initState();
    unawaited(_start());
  }

  Future<void> _start() async {
    try {
      await AppUpdateChecker().downloadAndInstallUrl(
        apkUrl: widget.apkUrl,
        fileName: widget.fileName,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      // Reaching here means the APK is on the phone and Android's
      // installer has already been handed the file (downloadAndInstallUrl
      // calls OpenFilex.open internally) — the install itself is the
      // admin's to confirm at the system dialog, same as every other
      // in-app update path in this codebase.
      if (mounted) setState(() => _done = true);
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Download failed. Check your connection '
            'and try again.\n\n$e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const Icon(Icons.android_rounded,
                    color: Color(0xFF3DDC84), size: 22),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    widget.fileName,
                    overflow: TextOverflow.ellipsis,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                      fontSize: 14,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (_error != null) ...[
              Text(
                _error!,
                style: GoogleFonts.outfit(
                  color: Colors.redAccent.shade100,
                  fontSize: 12,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: Text('Close',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ] else if (_done) ...[
              Row(
                children: [
                  const Icon(Icons.check_circle_rounded,
                      color: Color(0xFF3DDC84), size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Downloaded — tap Install on the next screen',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.85),
                      fontSize: 12.5,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: TextButton.styleFrom(
                    backgroundColor: Colors.white.withValues(alpha: 0.08),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(11),
                    ),
                  ),
                  child: Text('Done',
                      style: GoogleFonts.outfit(
                          color: Colors.white, fontWeight: FontWeight.w700)),
                ),
              ),
            ] else ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: LinearProgressIndicator(
                  minHeight: 6,
                  value: _progress > 0 ? _progress : null,
                  backgroundColor: Colors.white.withValues(alpha: 0.12),
                  color: const Color(0xFFFF4FA3),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                _progress > 0
                    ? '${(_progress * 100).toStringAsFixed(0)}%'
                    : 'Starting download...',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.6),
                  fontSize: 11.5,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// True when [url] is a direct APK download — either the file itself,
/// or a GitHub release asset download link. GitHub release download
/// URLs (`/releases/download/<tag>/<file>.apk`) do carry the .apk
/// extension in the path already, so a plain suffix check on the path
/// (not the full URL, which may carry a query string after it) covers
/// both shapes without needing a GitHub-specific pattern.
bool isApkDownloadUrl(String url) {
  final path = Uri.tryParse(url)?.path ?? '';
  return path.toLowerCase().endsWith('.apk');
}

/// The filename Android's installer should see, taken from the last
/// path segment; falls back to a generic name if the URL has none (an
/// edge case, not the common path, but downloadAndInstallUrl needs
/// *some* filename to write to disk).
String apkFileNameFromUrl(String url) {
  final segments = Uri.tryParse(url)?.pathSegments ?? const <String>[];
  final last = segments.isEmpty ? '' : segments.last;
  return last.toLowerCase().endsWith('.apk') ? last : 'update.apk';
}
