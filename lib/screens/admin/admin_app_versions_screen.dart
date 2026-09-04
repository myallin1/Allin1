// ================================================================
// admin_app_versions_screen.dart — every admin build ever published,
// with the one you're running marked, and any of them installable.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "suppose lastversion problem iruntha admin
// previous versionuku poi switch panni pathukuramari set
// pannnamuidyuma?").
//
// This needed no new infrastructure. The publish job already tags
// every build `latest-admin-test` and uploads a separate
// `allin1-admin-<shortsha>.apk`, so GitHub has been accumulating one
// asset per build all along — five of them by the time this screen was
// written. Nothing was ever throwing old versions away; the app simply
// only ever showed one, and (before the fix in
// ChittiDevMonitorService) showed the WRONG one.
//
// So this screen is a reader, not a new pipeline: list what's on the
// release, newest first, say which one is installed, and let the admin
// install any of them. Rolling back is just installing an older APK
// over the current one — same signing key, so Android treats it as a
// normal reinstall and app data survives.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/chitti/chitti_dev_monitor_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF16162A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);

class AdminAppVersionsScreen extends StatefulWidget {
  const AdminAppVersionsScreen({super.key, required this.release});

  final DevRelease release;

  @override
  State<AdminAppVersionsScreen> createState() => _AdminAppVersionsScreenState();
}

class _AdminAppVersionsScreenState extends State<AdminAppVersionsScreen> {
  String? _installedVersion;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
  }

  Future<void> _loadInstalled() async {
    try {
      final info = await PackageInfo.fromPlatform();
      if (!mounted) return;
      setState(() => _installedVersion = '${info.version}+${info.buildNumber}');
    } catch (_) {
      // Version banner is a nice-to-have; the list is the point.
    }
  }

  Future<void> _install(DevApkAsset asset) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // Hands off to the browser/download manager, which then hands the
      // .apk to Android's package installer — the same path the Dev
      // tab's existing "Download APK & Test" button uses. Deliberately
      // not an in-app installer: that needs REQUEST_INSTALL_PACKAGES
      // plumbing this screen doesn't otherwise justify.
      final ok = await launchUrl(
        Uri.parse(asset.downloadUrl),
        mode: LaunchMode.externalApplication,
      );
      if (!ok) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('Could not start the download.')),
        );
      }
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final assets = widget.release.apkAssets;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'App versions',
          style: GoogleFonts.outfit(
              color: _text, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: Column(
        children: [
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Currently installed',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
                const SizedBox(height: 4),
                Text(
                  _installedVersion ?? 'Checking…',
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 16, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 8),
                Text(
                  'Installing an older build over this one is a normal '
                  'reinstall — same signing key, so your app data stays.',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          ),
          Expanded(
            child: assets.isEmpty
                ? Center(
                    child: Text(
                      'No builds published yet.',
                      style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 20),
                    itemCount: assets.length,
                    itemBuilder: (context, i) {
                      final a = assets[i];
                      final isNewest = i == 0;
                      return Container(
                        margin: const EdgeInsets.only(bottom: 10),
                        padding: const EdgeInsets.all(14),
                        decoration: BoxDecoration(
                          color: _card,
                          borderRadius: BorderRadius.circular(14),
                          border: isNewest
                              ? Border.all(color: _green.withValues(alpha: 0.5))
                              : null,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        a.shortSha.isEmpty ? a.name : a.shortSha,
                                        style: GoogleFonts.outfit(
                                            color: _text,
                                            fontSize: 15,
                                            fontWeight: FontWeight.w700),
                                      ),
                                      if (isNewest) ...[
                                        const SizedBox(width: 8),
                                        Container(
                                          padding: const EdgeInsets.symmetric(
                                              horizontal: 7, vertical: 2),
                                          decoration: BoxDecoration(
                                            color:
                                                _green.withValues(alpha: 0.18),
                                            borderRadius:
                                                BorderRadius.circular(6),
                                          ),
                                          child: Text('LATEST',
                                              style: GoogleFonts.outfit(
                                                  color: _green,
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w700)),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    '${_when(a.updatedAt)} · ${a.sizeLabel}',
                                    style: GoogleFonts.outfit(
                                        color: _muted, fontSize: 11.5),
                                  ),
                                ],
                              ),
                            ),
                            TextButton.icon(
                              onPressed: () => _install(a),
                              icon: Icon(
                                isNewest
                                    ? Icons.download_rounded
                                    : Icons.history_rounded,
                                color: isNewest ? _green : _purple,
                                size: 18,
                              ),
                              label: Text(
                                isNewest ? 'Install' : 'Roll back',
                                style: GoogleFonts.outfit(
                                    color: isNewest ? _green : _purple,
                                    fontSize: 12.5,
                                    fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }

  static String _when(DateTime? dt) {
    if (dt == null) return 'unknown date';
    final local = dt.toLocal();
    final diff = DateTime.now().difference(local);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${local.day}/${local.month}/${local.year}';
  }
}
