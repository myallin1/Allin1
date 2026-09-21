// ================================================================
// chitti_error_watch_service.dart — Chitti's proactive error-log
// watcher.
// ================================================================
// NEW (Sep 21 2026 — Nizam: "3 errors vanthuchu, issue pottutuma"
// example, part of "is Chitti a real autonomous agent" question).
// AppErrorLogService already captures every FlutterError/PlatformDispatcher
// crash on-device, and the "Fix with Chitti" button on
// AdminAppErrorLogScreen already turns one into a GitHub plan issue —
// but only once the admin thought to open that screen. This is what
// makes the FIRST half proactive: Chitti notices new severe errors on
// its own and tells the admin, in one summary, instead of the admin
// having to remember to go looking.
//
// Deliberately does NOT auto-file a dev task by itself — filing a plan
// issue is already a requiresConfirmation-gated action for good reason
// (see AGENTS.md's Chitti tool contracts), and an autonomous trigger
// acting on a raw error with no human framing is exactly the "wrong
// fix masking the real regression" risk create_dev_task_from_error's
// own plan-first design already guards against. This service's whole
// job stops at "tell the admin something happened" — the admin still
// taps "Fix with Chitti" themselves from the screen this opens.
//
// NOISE DISCIPLINE: one summary notification per poll, never one per
// error — a crash loop must not turn into a notification storm. Only
// CRITICAL/ERROR severities count; WARNING is deliberately excluded,
// same reasoning as every other "don't cry wolf" gate in this app
// (ChittiBuddy.isSafeMoment, the dev-watch service's success-run
// silence). The very first check after a fresh install/reinstall
// records a baseline and alerts on nothing — otherwise every
// historical error already in the box would look "new" the instant
// this starts.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_alert_notification_service.dart';
import '../app_error_log_service.dart';

class ChittiErrorWatchService {
  ChittiErrorWatchService._();
  static final ChittiErrorWatchService instance = ChittiErrorWatchService._();

  // Longer than ChittiDevWatchService's 5 minutes on purpose — errors
  // are already captured the instant they happen (this only decides
  // how often to SUMMARIZE them), and a tighter interval would mean
  // more, smaller notifications for the same underlying problem.
  static const Duration _pollInterval = Duration(minutes: 15);
  static const String _lastCheckedKey = 'chitti_error_watch_last_checked';

  Timer? _timer;
  bool _checking = false;

  /// Call once the admin is signed in. Safe to call repeatedly.
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_check()));
    unawaited(_check());
  }

  /// Call on logout.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _check() async {
    if (_checking) return;
    _checking = true;
    try {
      final prefs = await SharedPreferences.getInstance();
      final lastCheckedRaw = prefs.getString(_lastCheckedKey);
      final lastChecked =
          lastCheckedRaw != null ? DateTime.tryParse(lastCheckedRaw) : null;
      final now = DateTime.now();
      await prefs.setString(_lastCheckedKey, now.toIso8601String());

      if (lastChecked == null) return; // first run — baseline only

      final recent = await AppErrorLogService.getRecentLogs(limit: 200);
      final newSevere = recent.where((e) {
        final t = DateTime.tryParse(e.timestamp);
        return t != null &&
            t.isAfter(lastChecked) &&
            (e.severity == 'CRITICAL' || e.severity == 'ERROR');
      }).toList();
      if (newSevere.isEmpty) return;

      final criticalCount =
          newSevere.where((e) => e.severity == 'CRITICAL').length;
      final errorCount = newSevere.length - criticalCount;
      final parts = <String>[
        if (criticalCount > 0) '$criticalCount critical',
        if (errorCount > 0) '$errorCount error${errorCount > 1 ? 's' : ''}',
      ];

      await AdminAlertNotificationService.showForegroundAlert(
        title:
            '⚠️ ${newSevere.length} new app error${newSevere.length > 1 ? 's' : ''}',
        body: '${parts.join(', ')} since your last check — tap to review.',
        payloadId: 'chitti_error_${now.millisecondsSinceEpoch}',
        type: 'chitti_error_alert',
      );
    } catch (e) {
      debugPrint('[ChittiErrorWatchService] check failed (non-fatal): $e');
    } finally {
      _checking = false;
    }
  }
}
