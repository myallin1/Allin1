// ================================================================
// chitti_dev_watch_service.dart — Chitti's proactive dev-pipeline
// watcher.
// ================================================================
// NEW (Sep 21 2026 — Nizam: "admin app la namma chitti end to end
// pakkava oru authonoumous agent aitana ila avanuku knowledge or tool
// calling innum vera add pananuma"). One concrete gap this closes:
// Chitti could ALREADY create a dev task, check a plan, check a PR —
// but only when the admin explicitly asked. After filing an issue, an
// admin had to keep coming back to Dev Monitor and tapping refresh to
// find out a PR was ready or a build failed. This is what makes that
// proactive instead of pull-only.
//
// ARCHITECTURE — reuses what already exists, adds nothing new:
//   - ChittiDevMonitorService.fetch()/fetchPullRequests() are the SAME
//     read-only GitHub calls the Dev Monitor screen already makes by
//     hand — this just calls them on a Timer instead of a tap.
//   - AdminAlertNotificationService.showForegroundAlert() is the SAME
//     loud-alert channel every other admin alert (new ride, new order,
//     incoming call) already uses — a dev-pipeline update gets the
//     same visibility, not a second notification system.
//   - Started/stopped alongside AdminLiveAlertService/AdminForegroundService
//     in main_admin.dart's auth-state listener, so it only ever runs
//     while an admin is actually signed in, and the SAME foreground
//     service that already keeps the process alive for those also
//     keeps this Timer alive in the background.
//
// COST DISCIPLINE: a 5-minute poll is 288 GitHub API calls/day at
// most — nowhere near the 5,000/hour authenticated-PAT rate limit,
// and this skips the poll entirely (no request at all) whenever no
// GitHub token is configured, so an admin who has never touched
// Developer Automation pays nothing for this existing silently.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../admin_alert_notification_service.dart';
import 'chitti_dev_monitor_service.dart';
import 'chitti_dev_task_service.dart';

class ChittiDevWatchService {
  ChittiDevWatchService._();
  static final ChittiDevWatchService instance = ChittiDevWatchService._();

  static const Duration _pollInterval = Duration(minutes: 5);

  // Keyed by a stable identity per item so a repeat poll never re-fires
  // the same alert — see _checkRuns/_checkPullRequests/_checkRelease
  // for what goes into each key.
  static const String _seenRunsKey = 'chitti_dev_watch_seen_runs';
  static const String _seenPrsKey = 'chitti_dev_watch_seen_prs';
  static const String _seenReleaseKey = 'chitti_dev_watch_seen_release_tag';

  Timer? _timer;
  bool _polling = false;

  /// Call once the admin is signed in. Safe to call repeatedly — a
  /// second start() while already running is a no-op, same contract as
  /// AdminForegroundService.start().
  void start() {
    if (_timer != null) return;
    _timer = Timer.periodic(_pollInterval, (_) => unawaited(_poll()));
    // Also check once immediately rather than waiting a full interval
    // after the admin signs in — the first sign-in of the day is
    // exactly when a build finished overnight and is worth surfacing
    // right away.
    unawaited(_poll());
  }

  /// Call on logout.
  void stop() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _poll() async {
    // Re-entrancy guard: a slow GitHub response from one tick should
    // never overlap with the next timer firing.
    if (_polling) return;
    _polling = true;
    try {
      final token = await ChittiDevTaskService.readToken();
      if (token == null || token.trim().isEmpty) return;
      final repo = await ChittiDevTaskService.readRepo();
      if (repo.owner.trim().isEmpty || repo.name.trim().isEmpty) return;

      final snapshot = await ChittiDevMonitorService.fetch(limit: 15);
      if (!snapshot.hasError) {
        await _checkRuns(snapshot.runs);
        await _checkRelease(snapshot.latestRelease);
      }

      final prResult = await ChittiDevMonitorService.fetchPullRequests(limit: 10);
      if (prResult.error == null) {
        await _checkPullRequests(prResult.pullRequests);
      }
    } catch (e) {
      debugPrint('[ChittiDevWatchService] poll failed (non-fatal): $e');
    } finally {
      _polling = false;
    }
  }

  Future<void> _checkRuns(List<DevWorkflowRun> runs) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(_seenRunsKey) ?? <String>[]).toSet();
    final stillRelevant = <String>{};
    for (final run in runs) {
      // Only a FINISHED run is worth alerting on — "queued"/"in_progress"
      // will come back around on a later poll once it completes.
      if (run.isRunning) continue;
      final key = '${run.url}::${run.conclusion}';
      stillRelevant.add(key);
      if (seen.contains(key)) continue;
      if (run.isFailure) {
        await _notify(
          title: '❌ Build failed: ${run.name}',
          body: 'Branch ${run.branch} — tap to open Dev Monitor.',
        );
      }
      // Deliberately silent on success here — a passing CI check on
      // every push would be noise; the release/PR checks below already
      // surface the outcomes an admin actually cares about (a real
      // build to install, a PR ready to review).
    }
    // Cap stored history the same way app_error_log_service.dart caps
    // entries — an old completed run's key has no future use once a
    // newer run for the same workflow exists.
    final merged = {...seen, ...stillRelevant}.toList();
    final capped = merged.length > 200
        ? merged.sublist(merged.length - 200)
        : merged;
    await prefs.setStringList(_seenRunsKey, capped);
  }

  Future<void> _checkPullRequests(List<DevPullRequest> prs) async {
    final prefs = await SharedPreferences.getInstance();
    final seen = (prefs.getStringList(_seenPrsKey) ?? <String>[]).toSet();
    final current = <String>{};
    for (final pr in prs) {
      final key = '${pr.number}::${pr.merged ? 'merged' : pr.state}';
      current.add(key);
      if (seen.contains(key)) continue;
      if (pr.merged) {
        await _notify(
          title: '✅ PR #${pr.number} merged',
          body: pr.title,
        );
      } else if (pr.isOpen && !pr.isDraft) {
        await _notify(
          title: '🔀 New PR ready: #${pr.number}',
          body: pr.title,
        );
      }
    }
    final merged = {...seen, ...current}.toList();
    final capped = merged.length > 200
        ? merged.sublist(merged.length - 200)
        : merged;
    await prefs.setStringList(_seenPrsKey, capped);
  }

  Future<void> _checkRelease(DevRelease? release) async {
    if (release == null) return;
    final prefs = await SharedPreferences.getInstance();
    final lastTag = prefs.getString(_seenReleaseKey);
    if (lastTag == release.tag) return;
    await prefs.setString(_seenReleaseKey, release.tag);
    // First-ever poll on a fresh install has no "last tag" to compare
    // against — every release would look "new". Only alert once a
    // baseline has actually been recorded once.
    if (lastTag == null) return;
    await _notify(
      title: '📦 New build published: ${release.tag}',
      body: 'A fresh APK is ready to install from Dev Monitor.',
    );
  }

  Future<void> _notify({required String title, required String body}) {
    return AdminAlertNotificationService.showForegroundAlert(
      title: title,
      body: body,
      payloadId: 'chitti_dev_${DateTime.now().millisecondsSinceEpoch}',
      type: 'chitti_dev_update',
    );
  }
}
