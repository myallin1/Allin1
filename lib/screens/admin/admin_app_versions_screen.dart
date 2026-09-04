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
import '../../services/app_update_checker.dart';

import '../../services/app_changelog_service.dart';
import '../../services/chitti/chitti_dev_monitor_service.dart';
import 'admin_whats_new_sheet.dart';

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
  AppChangelog? _changelog;

  /// Which asset is downloading, and how far along. Only one at a
  /// time — AppUpdateChecker guards that internally too.
  String? _downloadingName;
  double _progress = 0;

  @override
  void initState() {
    super.initState();
    _loadInstalled();
    _loadChangelog();
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

  Future<void> _loadChangelog() async {
    final log = await AppChangelogService.load();
    if (!mounted) return;
    setState(() => _changelog = log);
  }

  /// Downloads INSIDE the app and hands the file straight to Android's
  /// installer.
  ///
  /// CHANGED (Sep 4 2026 — Nizam: "admin app vittu veliya pogama admin
  /// app laye embedded ah open aganum"). This used to launchUrl() the
  /// asset, which threw him out to a browser and a download manager.
  /// Reuses AppUpdateChecker, which the hero and customer apps have
  /// been using for exactly this since August — no second "how do we
  /// install an update" implementation.
  ///
  /// Android's own install confirmation still appears. That is an OS
  /// security boundary, not something an app is allowed to skip.
  Future<void> _install(DevApkAsset asset) async {
    if (_downloadingName != null) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    setState(() {
      _downloadingName = asset.name;
      _progress = 0;
    });
    try {
      await AppUpdateChecker().downloadAndInstallUrl(
        apkUrl: asset.downloadUrl,
        fileName: asset.name,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
    } catch (e) {
      messenger?.showSnackBar(SnackBar(content: Text('Download failed: $e')));
    } finally {
      if (mounted) {
        setState(() {
          _downloadingName = null;
          _progress = 0;
        });
      }
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
          // NEW (Sep 4 2026 — Nizam: "setting la version ku keela
          // yennena feautures add pannirukomnu list kaatanum"). The
          // startup popup is dismissible, and a record you can only see
          // once is not a record — this is the permanent copy, sitting
          // directly under the version it describes.
          if (_changelog != null && !_changelog!.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: AdminWhatsNewSheet(log: _changelog!, embedded: true),
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
                                        a.shortSha.isEmpty
                                            ? a.name
                                            : a.shortSha,
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
                            if (_downloadingName == a.name)
                              // Progress replaces the button rather than
                              // sitting next to it — a disabled button
                              // beside a spinner reads as "stuck", and the
                              // percentage is the only thing worth looking
                              // at while a 118 MB file comes down.
                              SizedBox(
                                width: 74,
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    LinearProgressIndicator(
                                      value: _progress == 0 ? null : _progress,
                                      minHeight: 4,
                                      backgroundColor: _bg,
                                      valueColor:
                                          const AlwaysStoppedAnimation(_green),
                                    ),
                                    const SizedBox(height: 5),
                                    Text(
                                      '${(_progress * 100).toStringAsFixed(0)}%',
                                      style: GoogleFonts.outfit(
                                          color: _muted, fontSize: 11),
                                    ),
                                  ],
                                ),
                              )
                            else
                              TextButton.icon(
                                onPressed: _downloadingName == null
                                    ? () => _install(a)
                                    : null,
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
