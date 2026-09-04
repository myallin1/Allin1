// ================================================================
// app_changelog_service.dart — what actually changed in the build the
// admin is holding right now.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "ovvoru pr merge pannunana app la athula
// Yenna merge panni new update pannirukomnu admin app open pannumbothe
// antha app la Yenna feauture add pannirukonu admin ku pop kaatanum ...
// apo than version ah correcta understand panni pr merge la main la
// conrrecta agirukkanu theriyum").
//
// The real need behind that sentence is verification, not release
// notes. He merges a PR, installs an APK, and has no way to confirm
// the thing he merged is actually in the app in his hand — which had
// already bitten him twice: once when the Dev tab served a months-old
// APK, and once when a PR was closed instead of merged and he was told
// it had landed. A list of what shipped, generated from the commits
// themselves, is the check.
//
// READS A BUNDLED ASSET, NOT THE GITHUB API
//   The file is written by CI into assets/release_notes/changelog.txt
//   and compiled into the apk (see the "Generate changelog for this
//   build" step). So it works with no network, no GitHub token, and no
//   rate limit — and it describes THIS binary rather than whatever is
//   newest on the server, which is the only thing that can honestly
//   answer "what is in the app I'm holding".
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class AppChangelog {
  const AppChangelog({
    required this.buildNumber,
    required this.sha,
    required this.date,
    required this.changes,
  });

  /// CI run number, or 'local' for a developer build.
  final String buildNumber;
  final String sha;
  final String date;

  /// One line per commit that landed since the previous published
  /// build, newest first.
  final List<String> changes;

  bool get isFromCi => buildNumber != 'local' && buildNumber.isNotEmpty;
  bool get isEmpty => changes.isEmpty;

  static const AppChangelog none =
      AppChangelog(buildNumber: '', sha: '', date: '', changes: []);
}

class AppChangelogService {
  AppChangelogService._();

  static const String _assetPath = 'assets/release_notes/changelog.txt';
  static const String _kLastSeenBuild = 'changelog_last_seen_build';

  static AppChangelog? _cached;

  /// Never throws — a missing or malformed changelog must not stop the
  /// app from starting, since this is informational.
  static Future<AppChangelog> load() async {
    final cached = _cached;
    if (cached != null) return cached;
    try {
      final raw = await rootBundle.loadString(_assetPath);
      final parsed = _parse(raw);
      _cached = parsed;
      return parsed;
    } catch (_) {
      _cached = AppChangelog.none;
      return AppChangelog.none;
    }
  }

  static AppChangelog _parse(String raw) {
    var buildNumber = '';
    var sha = '';
    var date = '';
    final changes = <String>[];
    var inChanges = false;

    for (final line in raw.split('\n')) {
      final t = line.trim();
      if (t.isEmpty) continue;
      if (!inChanges) {
        if (t == '---') {
          inChanges = true;
        } else if (t.startsWith('build=')) {
          buildNumber = t.substring(6).trim();
        } else if (t.startsWith('sha=')) {
          sha = t.substring(4).trim();
        } else if (t.startsWith('date=')) {
          date = t.substring(5).trim();
        }
        continue;
      }
      changes.add(t);
    }
    return AppChangelog(
      buildNumber: buildNumber,
      sha: sha,
      date: date,
      changes: changes,
    );
  }

  /// True the first time this particular build is opened. Keyed on the
  /// build number rather than a "have I shown it" boolean, so a
  /// downgrade (rolling back via the App versions screen) correctly
  /// shows that older build's notes again instead of staying silent.
  static Future<bool> shouldShowWhatsNew() async {
    final log = await load();
    if (!log.isFromCi || log.isEmpty) return false;
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getString(_kLastSeenBuild) != log.buildNumber;
    } catch (_) {
      // Fail CLOSED: if prefs are unreadable, staying quiet is better
      // than showing the same popup on every single launch.
      return false;
    }
  }

  static Future<void> markSeen() async {
    try {
      final log = await load();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_kLastSeenBuild, log.buildNumber);
    } catch (_) {
      // Worst case the popup appears once more next launch.
    }
  }

  /// Commit subjects are written for other developers, not for Nizam
  /// at 6am. Strips the conventional-commit prefix and the trailing
  /// PR number so the line reads as a sentence.
  ///
  /// Deliberately light-touch: it does NOT try to rewrite or summarise
  /// the message. A cleaned-up real commit subject is still the truth;
  /// a paraphrase would be one more place for the app to tell him
  /// something that isn't quite what shipped.
  static String prettify(String commitSubject) {
    var s = commitSubject.trim();
    s = s.replaceFirst(RegExp(r'^(feat|fix|chore|docs|refactor|test|ci|build|perf|style)(\([^)]*\))?:\s*'), '');
    s = s.replaceFirst(RegExp(r'\s*\(#\d+\)\s*$'), '');
    if (s.isEmpty) return commitSubject.trim();
    return s[0].toUpperCase() + s.substring(1);
  }
}
