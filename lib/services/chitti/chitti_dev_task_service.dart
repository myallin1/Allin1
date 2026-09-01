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

@immutable
class ChittiDevTaskResult {
  const ChittiDevTaskResult({
    required this.success,
    this.issueTitle,
    this.issueUrl,
    this.error,
  });

  final bool success;
  final String? issueTitle;
  final String? issueUrl;
  final String? error;
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

    final body = '$description\n\n@claude please implement this.';

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
        return ChittiDevTaskResult(
          success: true,
          issueTitle: title,
          issueUrl: decoded['html_url'] as String?,
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
}
