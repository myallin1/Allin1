// ================================================================
// web_version_checker.dart
//
// Tells the app when a newer web build has been deployed, so the pink
// UPDATE button can appear.
//
// ── Why not the service worker ──────────────────────────────────────
// This used to rely on service-worker update events. That no longer
// works, for two independent reasons, both verified on the live site:
//
//   1. The service worker Flutter now emits UNREGISTERS ITSELF the
//      moment it activates (its activate handler calls
//      self.registration.unregister() and it has no fetch handler).
//      A worker that deletes itself can never report an update.
//   2. `flutter build web --pwa-strategy` prints "deprecated and will
//      be removed in a future Flutter release", so building anything
//      on top of service-worker caching is building on sand.
//
// The console said as much: "[PWA] update check failed:
// InvalidStateError: Failed to update a ServiceWorker".
//
// ── What this does instead ──────────────────────────────────────────
// Flutter writes build/web/version.json on every single build:
//
//   {"app_name":"erode_superapp","version":"1.0.1","build_number":"5",...}
//
// Capture that value once at startup, then re-fetch it periodically. If
// the number on the server no longer matches the one this tab loaded
// with, a new build is live. No service worker involved, nothing
// deprecated, works the same on every Flutter version.
//
// IMPORTANT: this only fires if the number actually changes between
// deploys. deploy_web.ps1 bumps the pubspec build number automatically
// for exactly that reason — otherwise every build would report the same
// value and no update would ever be detected.
// ================================================================
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class WebVersionChecker {
  WebVersionChecker._();
  static final WebVersionChecker instance = WebVersionChecker._();

  /// The build this tab is actually running. Captured once, never
  /// updated — that's the whole point of the comparison.
  String? _loadedVersion;

  bool _updateAvailable = false;
  bool get isUpdateAvailable => _updateAvailable;

  Timer? _pollTimer;

  /// Starts watching for new deployments. Safe to call more than once.
  ///
  /// Native builds return immediately: they update through Shorebird and
  /// AppUpdateChecker, and version.json isn't served to them anyway.
  ///
  /// 30 minutes, not 1: deploys happen maybe once a day, so polling
  /// every minute meant ~1440 requests per session to learn something
  /// that changes once. The request that actually matters is the one on
  /// resume (see checkNow() callers) — that's when a deploy is most
  /// likely to have happened while the customer was away. The timer is
  /// just a backstop for someone who leaves the app open for hours.
  Future<void> start({
    Duration interval = const Duration(minutes: 30),
  }) async {
    if (!kIsWeb) return;
    if (_pollTimer != null) return;

    _loadedVersion = await _fetchVersion();
    debugPrint('[VersionCheck] running build: $_loadedVersion');

    // If the very first read failed (offline at launch, say), there's
    // nothing to compare against later — try again on the next tick
    // rather than giving up for the whole session.
    _pollTimer = Timer.periodic(interval, (_) => unawaited(checkNow()));
  }

  /// One immediate check. Call this when the app returns to the
  /// foreground — the most likely moment for a deploy to have happened
  /// while the customer was elsewhere.
  Future<void> checkNow() async {
    if (!kIsWeb || _updateAvailable) return;

    final latest = await _fetchVersion();
    if (latest == null) return;

    if (_loadedVersion == null) {
      // First successful read; treat it as the baseline.
      _loadedVersion = latest;
      return;
    }

    if (latest != _loadedVersion) {
      debugPrint(
        '[VersionCheck] update available: $_loadedVersion -> $latest',
      );
      _updateAvailable = true;
      _pollTimer?.cancel();
      _pollTimer = null;
    }
  }

  Future<String?> _fetchVersion() async {
    try {
      // Cache-buster is essential. Without it the browser happily
      // serves the version.json it cached at launch, which by
      // definition always matches and would mean no update is ever
      // seen.
      final url = Uri.parse(
        '/version.json?t=${DateTime.now().millisecondsSinceEpoch}',
      );
      final response = await http
          .get(url, headers: {'cache-control': 'no-cache'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) return null;

      final body = json.decode(response.body);
      if (body is! Map) return null;

      // Compare build_number AND version so a version bump without a
      // build-number bump still counts as a new release.
      final build = body['build_number']?.toString() ?? '';
      final version = body['version']?.toString() ?? '';
      if (build.isEmpty && version.isEmpty) return null;
      return '$version+$build';
    } catch (e) {
      // Offline, mid-deploy, whatever — silently skip this round.
      debugPrint('[VersionCheck] check failed: $e');
      return null;
    }
  }

  void dispose() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }
}
