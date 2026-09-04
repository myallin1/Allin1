// ================================================================
// app_update_checker.dart
// Automatic version-check + one-tap download+install for the native
// Android APKs (hero / customer), distributed via GitHub Releases.
//
// This is separate from, and complements, Shorebird OTA
// (see shorebird.yaml) — Shorebird already silently patches
// Dart-code-level changes in the background on every launch, no UI
// needed for that. This checker only matters for the rarer case
// Shorebird can't patch (native/Android-level changes, new
// permissions, new plugins) where the customer genuinely needs a
// fresh APK. Before this, that only ever reached anyone if an admin
// manually sent an FCM push notification (see update_service.dart +
// notifications_screen.dart) — this makes the app find out on its
// own, and installs it with a single tap via OpenFilex instead of
// sending the customer to a browser download + file manager.
// ================================================================
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:open_filex/open_filex.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path_provider/path_provider.dart';

import 'update_service.dart';

class AppUpdateChecker {
  static final AppUpdateChecker _instance = AppUpdateChecker._internal();
  factory AppUpdateChecker() => _instance;
  AppUpdateChecker._internal();

  static const String _latestReleaseApiUrl =
      'https://api.github.com/repos/myallin1/Allin1-update-release/releases/latest';

  final Dio _dio = Dio();
  bool _isDownloading = false;
  bool get isDownloading => _isDownloading;

  /// Best-effort, fail-silent check: compares the installed app's
  /// version against the latest GitHub release tag. Returns true only
  /// when it's confident the remote version is newer — any network
  /// error, malformed tag, timeout, etc. returns false, so nobody ever
  /// sees a false "update available" prompt.
  Future<bool> isUpdateAvailable() async {
    if (kIsWeb) return false; // web/PWA uses its own service-worker flow
    try {
      final response = await http
          .get(Uri.parse(_latestReleaseApiUrl))
          .timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return false;

      final data = json.decode(response.body) as Map<String, dynamic>;
      final tag = (data['tag_name'] as String?)?.trim() ?? '';
      final remote = _parseVersion(tag);
      if (remote == null) return false;

      final packageInfo = await PackageInfo.fromPlatform();
      final local = _parseVersion(packageInfo.version);
      if (local == null) return false;

      return _isNewer(remote, local);
    } catch (e) {
      debugPrint('[AppUpdateChecker] version check failed: $e');
      return false;
    }
  }

  /// Downloads the correct APK for [appVariant] ('customer' or 'hero')
  /// and hands it straight to Android's installer — no browser
  /// download, no manual file-manager hunt. Reuses UpdateService's
  /// already-published GitHub release APK URLs.
  Future<void> downloadAndInstall({
    required String appVariant,
    void Function(double progress)? onProgress,
  }) async {
    if (_isDownloading) return;
    _isDownloading = true;
    try {
      final apkUrl = UpdateService().fallbackApkUrl(appVariant);
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/${appVariant}_update.apk';

      await _dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      await OpenFilex.open(filePath);
    } finally {
      _isDownloading = false;
    }
  }

  /// Downloads an APK from an EXPLICIT url and hands it to Android's
  /// installer — the same path as [downloadAndInstall], but for a
  /// specific build rather than "whatever is newest for this variant".
  ///
  /// NEW (Sep 4 2026 — Nizam: "admin app vittu veliya pogama admin app
  /// laye embedded ah open aganum apo admin download panni angiruthu
  /// update panniklam and again pannuna update la problema iruntha
  /// again old version ku switch pannikuramari irukanum").
  ///
  /// The admin's App versions screen used to hand each build to the
  /// browser, which meant leaving the app, finding the file, and
  /// tapping through a download manager. This keeps all of it inside
  /// the app. Android still shows its own install confirmation — that
  /// is an OS security boundary and cannot be skipped by any app — but
  /// nothing before it needs a browser.
  ///
  /// Works for rolling BACKWARD too: an older APK signed with the same
  /// key installs over a newer one as an ordinary reinstall, so the
  /// same method covers "update" and "go back".
  Future<void> downloadAndInstallUrl({
    required String apkUrl,
    required String fileName,
    void Function(double progress)? onProgress,
  }) async {
    if (_isDownloading) return;
    _isDownloading = true;
    try {
      final dir = await getTemporaryDirectory();
      final filePath = '${dir.path}/$fileName';

      await _dio.download(
        apkUrl,
        filePath,
        onReceiveProgress: (received, total) {
          if (total > 0) onProgress?.call(received / total);
        },
        options: Options(
          responseType: ResponseType.bytes,
          followRedirects: true,
          receiveTimeout: const Duration(minutes: 5),
        ),
      );

      await OpenFilex.open(filePath);
    } finally {
      _isDownloading = false;
    }
  }

  List<int>? _parseVersion(String raw) {
    final cleaned = raw.trim().replaceFirst(RegExp('^[vV]'), '');
    if (cleaned.isEmpty) return null;
    final parts = cleaned.split('.');
    final nums = <int>[];
    for (final p in parts) {
      final digitsOnly = p.replaceAll(RegExp('[^0-9]'), '');
      if (digitsOnly.isEmpty) return null;
      final n = int.tryParse(digitsOnly);
      if (n == null) return null;
      nums.add(n);
    }
    return nums.isEmpty ? null : nums;
  }

  bool _isNewer(List<int> remote, List<int> local) {
    final len = remote.length > local.length ? remote.length : local.length;
    for (var i = 0; i < len; i++) {
      final r = i < remote.length ? remote[i] : 0;
      final l = i < local.length ? local[i] : 0;
      if (r != l) return r > l;
    }
    return false;
  }
}
