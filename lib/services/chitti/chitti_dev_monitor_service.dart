// ================================================================
// chitti_dev_monitor_service.dart — read-only GitHub status feed for
// the admin app's Development Monitor screen.
// ================================================================
// NEW (Sep 1 2026 — Nizam: "laptop ilamaye claude codes and bugs edit
// panni atha gemini audit panni... apk generate panni githubla upload
// panni namaku antha link... athuku thani monitoring ui namma admin
// app la irukanum nan multitasking pandren so nan kulappamillama
// understand").
//
// The pipeline this watches ALREADY EXISTS end to end — nothing here
// creates or triggers it:
//   - ChittiDevTaskService opens a "@claude" issue (Chitti, by voice)
//   - .github/workflows/ci-cd.yml builds the APK and publishes a
//     GitHub Release with the .apk attached
//   - .github/workflows/gemini_cto_review.yml runs the Gemini audit
// What was missing is a way for ONE person running all of this from a
// phone to SEE where a change currently is without opening GitHub and
// reading three different pages. That is all this service does: three
// read-only GitHub API calls, no writes, no triggering.
//
// Deliberately reuses ChittiDevTaskService's existing secure token and
// repo settings rather than adding a second copy of either — the token
// is already scoped by the admin on github.com, and a second storage
// key would just be another thing that can drift out of sync.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'chitti_dev_task_service.dart';

/// One CI run (a GitHub Actions workflow run).
@immutable
class DevWorkflowRun {
  const DevWorkflowRun({
    required this.name,
    required this.status,
    required this.conclusion,
    required this.branch,
    required this.url,
    required this.updatedAt,
  });

  final String name;

  /// queued | in_progress | completed
  final String status;

  /// success | failure | cancelled | null (still running)
  final String? conclusion;
  final String branch;
  final String url;
  final DateTime? updatedAt;

  bool get isRunning => status != 'completed';
  bool get isSuccess => conclusion == 'success';
  bool get isFailure => conclusion == 'failure' || conclusion == 'timed_out';
}

/// One dev task Chitti (or Nizam) opened as a GitHub issue.
@immutable
class DevTaskIssue {
  const DevTaskIssue({
    required this.number,
    required this.title,
    required this.state,
    required this.url,
    required this.updatedAt,
  });

  final int number;
  final String title;

  /// open | closed
  final String state;
  final String url;
  final DateTime? updatedAt;
}

/// One installable APK sitting on the rolling admin-test release.
///
/// NEW (Sep 4 2026 — Nizam: "suppose lastversion problem iruntha admin
/// previous versionuku poi switch panni pathukuramari set
/// pannnamuidyuma?"). The publish job tags every build
/// `latest-admin-test` and uploads `allin1-admin-<shortsha>.apk`, so
/// the release ACCUMULATES one asset per build rather than replacing
/// it — every previous version is already sitting there, and this type
/// is what finally exposes them to the admin instead of throwing all
/// but one away.
@immutable
class DevApkAsset {
  const DevApkAsset({
    required this.name,
    required this.downloadUrl,
    required this.sizeBytes,
    required this.updatedAt,
  });

  final String name;
  final String downloadUrl;
  final int sizeBytes;
  final DateTime? updatedAt;

  /// A human-readable label for this build.
  ///
  /// Handles both naming schemes the publish job has used:
  ///   allin1-admin-448ec5e3.apk                          -> `448ec5e3`
  ///   allin1-admin-b0044-v1.0.9+279-20260904-3649788f.apk -> `Build 0044 · v1.0.9+279`
  ///
  /// The second form exists because a page of eight identical-looking
  /// hex names was genuinely unreadable — see the "Rename with version
  /// + build number" step in ci-cd.yml. Old assets keep working, so
  /// rolling back to a pre-rename build still shows something useful.
  String get shortSha {
    final versioned =
        RegExp(r'allin1-admin-b(\d+)-v([^-]+)-').firstMatch(name);
    if (versioned != null) {
      return 'Build ${versioned.group(1)} · v${versioned.group(2)}';
    }
    final legacy = RegExp(r'allin1-admin-([0-9a-f]+)\.apk').firstMatch(name);
    return legacy?.group(1) ?? '';
  }

  String get sizeLabel => '${(sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB';
}

/// The newest published build the admin can install.
@immutable
class DevRelease {
  const DevRelease({
    required this.tag,
    required this.name,
    required this.htmlUrl,
    required this.apkUrl,
    required this.publishedAt,
    this.apkAssets = const [],
  });

  final String tag;
  final String name;
  final String htmlUrl;

  /// Direct .apk asset link for the NEWEST build on this release.
  ///
  /// FIX (Sep 4 2026 — Nizam: "new app build aiduchu but ... download
  /// link varala"). This used to be whichever .apk the GitHub API
  /// happened to list first, and since the release accumulates one
  /// asset per build, that was a MONTHS-old file, not the build just
  /// made. The admin downloaded, installed, and saw none of the new
  /// work — which read as "the build didn't happen". Now explicitly
  /// the most recently uploaded asset.
  final String? apkUrl;
  final DateTime? publishedAt;

  /// Every APK on this release, newest first — see [DevApkAsset].
  final List<DevApkAsset> apkAssets;
}

@immutable
class DevMonitorSnapshot {
  const DevMonitorSnapshot({
    required this.runs,
    required this.issues,
    required this.latestRelease,
    this.error,
  });

  final List<DevWorkflowRun> runs;
  final List<DevTaskIssue> issues;
  final DevRelease? latestRelease;
  final String? error;

  bool get hasError => error != null;
}

class ChittiDevMonitorService {
  ChittiDevMonitorService._();

  static const String _apiBase = 'https://api.github.com';

  /// Fetches CI runs, open dev-task issues, and the latest release in
  /// one pass. Returns a snapshot carrying [DevMonitorSnapshot.error]
  /// rather than throwing — this feeds a status screen, and a screen
  /// that shows "why it couldn't load" is far more useful to someone
  /// debugging from a phone than one that just renders empty.
  static Future<DevMonitorSnapshot> fetch({int limit = 10}) async {
    const empty = DevMonitorSnapshot(runs: [], issues: [], latestRelease: null);

    final token = await ChittiDevTaskService.readToken();
    if (token == null || token.trim().isEmpty) {
      return const DevMonitorSnapshot(
        runs: [],
        issues: [],
        latestRelease: null,
        error: 'No GitHub token saved yet — add it in Admin AI Configuration '
            '(Developer Automation) first.',
      );
    }

    final repo = await ChittiDevTaskService.readRepo();
    if (repo.owner.trim().isEmpty || repo.name.trim().isEmpty) {
      return const DevMonitorSnapshot(
        runs: [],
        issues: [],
        latestRelease: null,
        error: 'GitHub owner/repo not set — add them in Admin AI Configuration.',
      );
    }

    final headers = {
      'Authorization': 'Bearer $token',
      'Accept': 'application/vnd.github+json',
      'X-GitHub-Api-Version': '2022-11-28',
    };
    final base = '$_apiBase/repos/${repo.owner}/${repo.name}';

    try {
      final results = await Future.wait([
        http.get(Uri.parse('$base/actions/runs?per_page=$limit'), headers: headers),
        http.get(Uri.parse('$base/issues?state=all&per_page=$limit'), headers: headers),
        http.get(Uri.parse('$base/releases/latest'), headers: headers),
      ]);

      final runsRes = results[0];
      final issuesRes = results[1];
      final releaseRes = results[2];

      if (runsRes.statusCode == 401 || runsRes.statusCode == 403) {
        return DevMonitorSnapshot(
          runs: const [],
          issues: const [],
          latestRelease: null,
          error: 'GitHub rejected the token (${runsRes.statusCode}). It may be '
              'expired, or missing the Actions/Contents read permission.',
        );
      }
      if (runsRes.statusCode == 404) {
        return DevMonitorSnapshot(
          runs: const [],
          issues: const [],
          latestRelease: null,
          error: 'Repo ${repo.owner}/${repo.name} not found, or the token '
              "can't see it. Check the owner/repo values.",
        );
      }

      final runs = <DevWorkflowRun>[];
      if (runsRes.statusCode == 200) {
        final body = jsonDecode(runsRes.body) as Map<String, dynamic>;
        for (final r in (body['workflow_runs'] as List<dynamic>? ?? [])) {
          final m = r as Map<String, dynamic>;
          runs.add(DevWorkflowRun(
            name: (m['name'] as String?) ?? 'Workflow',
            status: (m['status'] as String?) ?? 'unknown',
            conclusion: m['conclusion'] as String?,
            branch: (m['head_branch'] as String?) ?? '',
            url: (m['html_url'] as String?) ?? '',
            updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
          ));
        }
      }

      final issues = <DevTaskIssue>[];
      if (issuesRes.statusCode == 200) {
        for (final i in (jsonDecode(issuesRes.body) as List<dynamic>)) {
          final m = i as Map<String, dynamic>;
          // GitHub's issues endpoint returns pull requests too; they
          // carry a "pull_request" key. Filtering them keeps this list
          // to actual dev tasks, which is what this screen is for.
          if (m.containsKey('pull_request')) continue;
          issues.add(DevTaskIssue(
            number: (m['number'] as num?)?.toInt() ?? 0,
            title: (m['title'] as String?) ?? '(untitled)',
            state: (m['state'] as String?) ?? 'open',
            url: (m['html_url'] as String?) ?? '',
            updatedAt: DateTime.tryParse((m['updated_at'] as String?) ?? ''),
          ));
        }
      }

      DevRelease? latest;
      // 404 here just means "no release published yet" — a normal state,
      // not an error worth surfacing.
      if (releaseRes.statusCode == 200) {
        final m = jsonDecode(releaseRes.body) as Map<String, dynamic>;
        // See DevRelease.apkUrl: collect ALL apks and sort newest
        // first, rather than taking whichever one the API listed first.
        final apks = <DevApkAsset>[];
        for (final a in (m['assets'] as List<dynamic>? ?? [])) {
          final asset = a as Map<String, dynamic>;
          final name = (asset['name'] as String?) ?? '';
          final url = asset['browser_download_url'] as String?;
          if (url == null || !name.toLowerCase().endsWith('.apk')) continue;
          apks.add(DevApkAsset(
            name: name,
            downloadUrl: url,
            sizeBytes: (asset['size'] as num?)?.toInt() ?? 0,
            updatedAt: DateTime.tryParse((asset['updated_at'] as String?) ?? ''),
          ));
        }
        apks.sort((a, b) {
          final at = a.updatedAt;
          final bt = b.updatedAt;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });
        latest = DevRelease(
          tag: (m['tag_name'] as String?) ?? '',
          name: (m['name'] as String?) ?? (m['tag_name'] as String?) ?? 'Release',
          htmlUrl: (m['html_url'] as String?) ?? '',
          apkUrl: apks.isEmpty ? null : apks.first.downloadUrl,
          publishedAt: DateTime.tryParse((m['published_at'] as String?) ?? ''),
          apkAssets: apks,
        );
      }

      return DevMonitorSnapshot(runs: runs, issues: issues, latestRelease: latest);
    } catch (e) {
      return DevMonitorSnapshot(
        runs: empty.runs,
        issues: empty.issues,
        latestRelease: null,
        error: 'Could not reach GitHub: $e',
      );
    }
  }
}
