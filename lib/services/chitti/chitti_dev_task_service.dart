// ================================================================
// chitti_dev_task_service.dart — Chitti's bridge to the Claude Code
// GitHub App integration.
// ================================================================
// NEW (Aug 31 2026 — Nizam: "namma chitty AI valiyavum Claude Code
// develop panna structure build pannamudiyuma... chitty ana screen ku
// pogamudiyungrathunala avana vachu intha plan implement pannanum").
//
// Once the Claude GitHub App is installed on a repo (a one-time human
// setup — see the terminal `/install-github-app` flow), anything that
// creates a GitHub issue mentioning "@claude" triggers Claude Code to
// pick it up automatically, via the same GitHub Actions workflow used
// when a person types the issue by hand. This service is the ONLY new
// piece that ask needed: a way for Chitti to place that issue on
// Nizam's behalf, using his own spoken request as the description.
//
// SECURITY — why this is flutter_secure_storage from the FIRST line,
// not plaintext-then-migrate-later.
// This session has already found (and fixed) more than one plaintext
// SharedPreferences key holding something sensitive, each time as a
// follow-up fix after the fact. A GitHub token with repo write access
// is squarely in that category — arguably worse, since it can be used
// to push code, not just read a balance. There is no "migrate later"
// version of this file; it starts secure.
//
// The token itself should be a GitHub *fine-grained* personal access
// token scoped to ONLY this one repository with ONLY "Issues: Write"
// permission — that scoping is a human step (done on github.com when
// generating the token), not something this code can enforce, but it
// is what keeps a leaked token from being able to do anything beyond
// "open an issue," regardless of how it leaks.
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

@immutable
class ChittiDevTaskResult {
  const ChittiDevTaskResult({
    required this.success,
    this.issueTitle,
    this.issueUrl,
    this.issueNumber,
    this.error,
  });

  final bool success;
  final String? issueTitle;
  final String? issueUrl;
  final int? issueNumber;
  final String? error;
}

@immutable
class ChittiDevCommentResult {
  const ChittiDevCommentResult({
    required this.success,
    this.error,
  });

  final bool success;
  final String? error;
}

@immutable
class ChittiDevPlanReport {
  const ChittiDevPlanReport({
    required this.found,
    this.body,
    this.author,
    this.postedAt,
    this.error,
  });

  final bool found;
  final String? body;
  final String? author;
  final DateTime? postedAt;
  final String? error;
}

// NEW (Sep 17 2026 — Nizam: "admin app la enaku anti gravity and claude
// 2um namma app kulla varanum, namma chitti itha vachu namma
// solddrathayum vachu app develop pannanum"). A THIRD coding engine
// alongside Claude, wired through the exact same "issue -> agent -> PR"
// shape — see .github/workflows/antigravity_coder.yml (@agy) and
// gemini_coder.yml (@gemini). Only the @mention tag differs; the admin
// picks which one by name (or Chitti defaults to Claude when not asked).
enum ChittiDevEngine { claude, gemini, antigravity }

extension ChittiDevEngineTag on ChittiDevEngine {
  /// The exact @mention each engine's GitHub Actions workflow triggers
  /// on — claude.yml (@claude), gemini_coder.yml (@gemini),
  /// antigravity_coder.yml (@agy).
  String get mention {
    switch (this) {
      case ChittiDevEngine.claude:
        return '@claude';
      case ChittiDevEngine.gemini:
        return '@gemini';
      case ChittiDevEngine.antigravity:
        return '@agy';
    }
  }

  String get label {
    switch (this) {
      case ChittiDevEngine.claude:
        return 'Claude';
      case ChittiDevEngine.gemini:
        return 'Gemini';
      case ChittiDevEngine.antigravity:
        return 'Antigravity';
    }
  }

  static ChittiDevEngine fromName(String? name) {
    switch (name?.toLowerCase().trim()) {
      case 'gemini':
        return ChittiDevEngine.gemini;
      case 'antigravity':
      case 'agy':
        return ChittiDevEngine.antigravity;
      case 'claude':
      default:
        return ChittiDevEngine.claude;
    }
  }
}

class ChittiDevTaskService {
  ChittiDevTaskService._();

  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  static const String _tokenKey = 'chitti_github_pat_secure';
  static const String _repoOwnerKey = 'chitti_github_repo_owner_secure';
  static const String _repoNameKey = 'chitti_github_repo_name_secure';

  /// Never logged, never returned in any tool result text — only ever
  /// read here to build the Authorization header.
  static Future<void> saveToken(String token) async {
    final trimmed = token.trim();
    if (trimmed.isEmpty) {
      await _secureStorage.delete(key: _tokenKey);
      return;
    }
    await _secureStorage.write(key: _tokenKey, value: trimmed);
  }

  static Future<String?> readToken() => _secureStorage.read(key: _tokenKey);

  static Future<bool> hasToken() async {
    final token = await readToken();
    return token != null && token.isNotEmpty;
  }

  static Future<void> saveRepo({
    required String owner,
    required String name,
  }) async {
    await _secureStorage.write(key: _repoOwnerKey, value: owner.trim());
    await _secureStorage.write(key: _repoNameKey, value: name.trim());
  }

  static Future<({String owner, String name})> readRepo() async {
    final owner = await _secureStorage.read(key: _repoOwnerKey) ?? '';
    final name = await _secureStorage.read(key: _repoNameKey) ?? '';
    return (owner: owner, name: name);
  }

  // NEW (Sep 16 2026 — Nizam: "chitti admin oda intent purinjukutu...
  // plan sollitu... git la oru issue create pannum claude ku, claude
  // audit panni plan solluvan, apo boss discuss pannitu execute panna
  // solluvom"). Not sensitive, so plain SharedPreferences: just the
  // number of the most recent plan-review issue, so a later "go ahead,
  // implement it" command knows which issue to comment on without the
  // admin having to repeat the number out loud.
  static const String _lastPlanIssueKey = 'chitti_last_plan_issue_number';
  // Stored alongside the issue number so postApprovalComment() posts
  // "@gemini proceed" / "@agy proceed" — not always "@claude proceed" —
  // without the caller having to remember which engine drafted the plan.
  static const String _lastPlanEngineKey = 'chitti_last_plan_issue_engine';
  // FIX (Sep 18 2026 — Gemini-engine audit, round 2): _lastPlanEngineKey
  // alone only remembers the MOST RECENT plan's engine. If the admin
  // drafts plan #10 with Claude, then later drafts plan #12 with
  // Antigravity, then says "approve plan #10", postApprovalComment used
  // to still post "@agy proceed" on issue #10 — the wrong engine for
  // that specific issue. This map keeps every plan issue's own engine,
  // keyed by issue number, so an explicit issueNumber always resolves
  // to the engine that actually drafted THAT plan.
  static const String _planEngineByIssueKey = 'chitti_plan_issue_engine_map';

  static Future<void> _rememberPlanIssue(
    int number, {
    required ChittiDevEngine engine,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_lastPlanIssueKey, number);
    await prefs.setString(_lastPlanEngineKey, engine.name);
    final map = await _readPlanEngineMap(prefs);
    map[number.toString()] = engine.name;
    await prefs.setString(_planEngineByIssueKey, jsonEncode(map));
  }

  static Future<Map<String, dynamic>> _readPlanEngineMap(
    SharedPreferences prefs,
  ) async {
    final raw = prefs.getString(_planEngineByIssueKey);
    if (raw == null || raw.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(raw) as Map<String, dynamic>;
    } catch (_) {
      return <String, dynamic>{};
    }
  }

  static Future<int?> readLastPlanIssueNumber() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_lastPlanIssueKey);
  }

  static Future<ChittiDevEngine> readLastPlanEngine() async {
    final prefs = await SharedPreferences.getInstance();
    return ChittiDevEngineTag.fromName(prefs.getString(_lastPlanEngineKey));
  }

  /// The engine that drafted [issueNumber]'s own plan, if known — falls
  /// back to the most recent plan's engine (the old global behavior)
  /// when that specific issue was never recorded, e.g. a plan created
  /// before this per-issue map existed.
  static Future<ChittiDevEngine> readEngineForIssue(int? issueNumber) async {
    final prefs = await SharedPreferences.getInstance();
    if (issueNumber != null) {
      final map = await _readPlanEngineMap(prefs);
      final stored = map[issueNumber.toString()] as String?;
      if (stored != null) return ChittiDevEngineTag.fromName(stored);
    }
    return ChittiDevEngineTag.fromName(prefs.getString(_lastPlanEngineKey));
  }

  /// Creates a GitHub issue tagging @claude, so the already-installed
  /// Claude Code GitHub App picks it up the same way it would a
  /// hand-typed issue.
  ///
  /// Never throws — a failed request comes back as
  /// [ChittiDevTaskResult.success] == false with a human-readable
  /// [ChittiDevTaskResult.error], the same "never let the caller crash
  /// into an exception" contract every other Chitti tool follows.
  static Future<ChittiDevTaskResult> createIssue({
    required String title,
    required String description,
    ChittiDevEngine engine = ChittiDevEngine.claude,
  }) async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      return const ChittiDevTaskResult(
        success: false,
        error: 'No GitHub token configured yet. Add one in AI Settings '
            'under Developer Automation first.',
      );
    }
    final repo = await readRepo();
    if (repo.owner.isEmpty || repo.name.isEmpty) {
      return const ChittiDevTaskResult(
        success: false,
        error: 'No GitHub repository configured yet. Add the owner and '
            'repo name in AI Settings first.',
      );
    }

    final body = '$description\n\n${engine.mention} please implement this.';

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://api.github.com/repos/${repo.owner}/${repo.name}/issues',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
            body: jsonEncode(<String, String>{
              'title': title,
              'body': body,
            }),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        // Deliberately NOT remembered as the "last plan issue" — this
        // path tells Claude to implement immediately, with no plan
        // posted to review. Sharing that pointer with createPlanIssue
        // would let a later "check the plan" / "proceed" land on an
        // issue that was never asked for a plan in the first place.
        return ChittiDevTaskResult(
          success: true,
          issueTitle: title,
          issueUrl: decoded['html_url'] as String?,
          issueNumber: decoded['number'] as int?,
        );
      }

      // GitHub's own error body — never the token, which is only ever
      // sent in the request header above, never echoed back.
      debugPrint(
        '[ChittiDevTaskService] GitHub issue creation failed: '
        '${response.statusCode}',
      );
      return ChittiDevTaskResult(
        success: false,
        error: response.statusCode == 401 || response.statusCode == 403
            ? 'GitHub rejected the token — check it is still valid and has '
                'Issues: Write permission on this repo.'
            : 'GitHub returned an error (${response.statusCode}). Please '
                'try again in a moment.',
      );
    } catch (e) {
      debugPrint('[ChittiDevTaskService] createIssue failed: $e');
      return const ChittiDevTaskResult(
        success: false,
        error: "Couldn't reach GitHub — check your connection and try again.",
      );
    }
  }

  /// Same GitHub issue as [createIssue], but the body asks Claude Code
  /// to come back with an AUDIT + IMPLEMENTATION PLAN first, and
  /// explicitly not to open a PR yet. This is phase 1 of the
  /// plan-then-execute flow: boss's idea -> Chitti drafts intent ->
  /// this issue -> Claude posts a plan as a comment -> boss reviews it
  /// with Chitti -> [postApprovalComment] tells Claude to actually
  /// build it.
  static Future<ChittiDevTaskResult> createPlanIssue({
    required String title,
    required String description,
    ChittiDevEngine engine = ChittiDevEngine.claude,
  }) async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      return const ChittiDevTaskResult(
        success: false,
        error: 'No GitHub token configured yet. Add one in AI Settings '
            'under Developer Automation first.',
      );
    }
    final repo = await readRepo();
    if (repo.owner.isEmpty || repo.name.isEmpty) {
      return const ChittiDevTaskResult(
        success: false,
        error: 'No GitHub repository configured yet. Add the owner and '
            'repo name in AI Settings first.',
      );
    }

    final mention = engine.mention;
    final body = '$description\n\n'
        '$mention please review this request. Reply with your audit and a '
        'concrete implementation plan (approach, files likely touched, '
        'risks/tradeoffs) as a comment on this issue. **Do not open a pull '
        'request or write any code yet** — the admin will review your plan '
        'first and reply here with "$mention proceed" once approved.';

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://api.github.com/repos/${repo.owner}/${repo.name}/issues',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
            body: jsonEncode(<String, String>{'title': title, 'body': body}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 201) {
        final decoded = jsonDecode(response.body) as Map<String, dynamic>;
        final number = decoded['number'] as int?;
        if (number != null) {
          await _rememberPlanIssue(number, engine: engine);
        }
        return ChittiDevTaskResult(
          success: true,
          issueTitle: title,
          issueUrl: decoded['html_url'] as String?,
          issueNumber: number,
        );
      }
      debugPrint(
        '[ChittiDevTaskService] plan issue creation failed: '
        '${response.statusCode}',
      );
      return ChittiDevTaskResult(
        success: false,
        error: response.statusCode == 401 || response.statusCode == 403
            ? 'GitHub rejected the token — check it is still valid and has '
                'Issues: Write permission on this repo.'
            : 'GitHub returned an error (${response.statusCode}). Please '
                'try again in a moment.',
      );
    } catch (e) {
      debugPrint('[ChittiDevTaskService] createPlanIssue failed: $e');
      return const ChittiDevTaskResult(
        success: false,
        error: "Couldn't reach GitHub — check your connection and try again.",
      );
    }
  }

  /// Posts "@claude proceed with the plan..." as a comment on an
  /// existing issue — phase 2, after the admin has reviewed the plan
  /// Claude posted in phase 1 and told Chitti to go ahead. Defaults to
  /// the most recently created plan issue when no number is given, and
  /// — when [engine] itself isn't given — to whichever engine actually
  /// drafted that plan (via [readLastPlanEngine]), so this never posts
  /// "@claude proceed" under a plan Gemini or Antigravity wrote.
  static Future<ChittiDevCommentResult> postApprovalComment({
    int? issueNumber,
    String? extraNote,
    ChittiDevEngine? engine,
  }) async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      return const ChittiDevCommentResult(
        success: false,
        error: 'No GitHub token configured yet.',
      );
    }
    final repo = await readRepo();
    if (repo.owner.isEmpty || repo.name.isEmpty) {
      return const ChittiDevCommentResult(
        success: false,
        error: 'No GitHub repository configured yet.',
      );
    }
    final number = issueNumber ?? await readLastPlanIssueNumber();
    if (number == null) {
      return const ChittiDevCommentResult(
        success: false,
        error: "I don't have an open plan issue to approve — ask me to "
            'draft the plan first.',
      );
    }
    final mention = (engine ?? await readEngineForIssue(number)).mention;

    final body = '$mention proceed with the plan above — the admin has '
        'reviewed and approved it. Please implement it now and open a '
        'pull request.'
        '${extraNote != null && extraNote.trim().isNotEmpty ? '\n\nAdditional note from the admin: ${extraNote.trim()}' : ''}';

    try {
      final response = await http
          .post(
            Uri.parse(
              'https://api.github.com/repos/${repo.owner}/${repo.name}/issues/$number/comments',
            ),
            headers: {
              'Authorization': 'Bearer $token',
              'Accept': 'application/vnd.github+json',
              'X-GitHub-Api-Version': '2022-11-28',
            },
            body: jsonEncode(<String, String>{'body': body}),
          )
          .timeout(const Duration(seconds: 20));

      if (response.statusCode == 201) {
        return const ChittiDevCommentResult(success: true);
      }
      debugPrint(
        '[ChittiDevTaskService] postApprovalComment failed: '
        '${response.statusCode}',
      );
      return ChittiDevCommentResult(
        success: false,
        error: response.statusCode == 404
            ? "Couldn't find issue #$number on this repo."
            : 'GitHub returned an error (${response.statusCode}).',
      );
    } catch (e) {
      debugPrint('[ChittiDevTaskService] postApprovalComment failed: $e');
      return const ChittiDevCommentResult(
        success: false,
        error: "Couldn't reach GitHub — check your connection and try again.",
      );
    }
  }

  /// Reads back the most recent comment on the plan issue that looks
  /// like it came from whichever coding engine's bot picked it up
  /// (Claude, Gemini or Antigravity), so Chitti can relay the
  /// audit/plan to the admin in-app instead of them having to open
  /// GitHub themselves.
  static Future<ChittiDevPlanReport> fetchLatestPlanReport({
    int? issueNumber,
  }) async {
    final token = await readToken();
    if (token == null || token.isEmpty) {
      return const ChittiDevPlanReport(
        found: false,
        error: 'No GitHub token configured yet.',
      );
    }
    final repo = await readRepo();
    if (repo.owner.isEmpty || repo.name.isEmpty) {
      return const ChittiDevPlanReport(
        found: false,
        error: 'No GitHub repository configured yet.',
      );
    }
    final number = issueNumber ?? await readLastPlanIssueNumber();
    if (number == null) {
      return const ChittiDevPlanReport(
        found: false,
        error: "I don't have a plan issue to check yet.",
      );
    }

    try {
      final response = await http.get(
        Uri.parse(
          'https://api.github.com/repos/${repo.owner}/${repo.name}/issues/$number/comments?per_page=100',
        ),
        headers: {
          'Authorization': 'Bearer $token',
          'Accept': 'application/vnd.github+json',
          'X-GitHub-Api-Version': '2022-11-28',
        },
      ).timeout(const Duration(seconds: 20));

      if (response.statusCode != 200) {
        return ChittiDevPlanReport(
          found: false,
          error: 'GitHub returned an error (${response.statusCode}).',
        );
      }
      final list = jsonDecode(response.body) as List<dynamic>;
      for (final entry in list.reversed) {
        final comment = entry as Map<String, dynamic>;
        final login =
            (comment['user'] as Map<String, dynamic>?)?['login'] as String? ??
                '';
        // FIX (Sep 18 2026 — Gemini-engine audit): this used to check
        // only .contains('claude'). claude-code-action posts under a
        // GitHub App identity whose login genuinely contains "claude",
        // but gemini_coder.yml and antigravity_coder.yml both post via
        // the plain GITHUB_TOKEN, whose login is always
        // "github-actions[bot]" regardless of which engine ran — so
        // every Gemini/Antigravity plan comment was invisible here and
        // check_dev_plan always reported "no plan yet" for those two
        // engines, even after they had genuinely posted one.
        final loginLower = login.toLowerCase();
        final looksLikeAnEngineBot = loginLower.contains('claude') ||
            loginLower.contains('gemini') ||
            loginLower.contains('antigravity') ||
            loginLower.contains('agy') ||
            loginLower == 'github-actions[bot]';
        // FIX (Sep 18 2026 — Gemini-engine audit, round 2): claude.yml's
        // own failure-fallback step posts "@gemini please implement
        // this instead" via plain GITHUB_TOKEN too, so it also matches
        // 'github-actions[bot]' above. Without this exclusion that
        // routing notification — not a plan — would be shown to the
        // admin as "here's what Gemini posted."
        final body = comment['body'] as String? ?? '';
        final isEngineHandoffNotice =
            body.contains('the Claude engine failed on this task');
        if (looksLikeAnEngineBot && !isEngineHandoffNotice) {
          return ChittiDevPlanReport(
            found: true,
            body: comment['body'] as String?,
            author: login,
            postedAt: DateTime.tryParse(
              comment['created_at'] as String? ?? '',
            ),
          );
        }
      }
      return const ChittiDevPlanReport(
        found: false,
        error: "The coding engine hasn't replied on that issue yet — try "
            'again in a bit.',
      );
    } catch (e) {
      debugPrint('[ChittiDevTaskService] fetchLatestPlanReport failed: $e');
      return const ChittiDevPlanReport(
        found: false,
        error: "Couldn't reach GitHub — check your connection and try again.",
      );
    }
  }
}
