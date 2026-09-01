// ================================================================
// DeepSeekApiService — third agent for the ADMIN app only.
// ================================================================
// NEW (Aug 11 2026 — Nizam: "admin app ku mattum one new power ...
// deepseek api ... gemini, groq limit mudinjuthuna admin apo deepseek
// use panikramari plan").
//
// SCOPE: Admin only, deliberately. The customer app stays on Groq
// (fast tool-calling) + Gemini (vision) — adding a third provider there
// would mean a third key for every customer install to go wrong, for no
// customer-visible benefit. Admin is a single operator (Nizam), so an
// extra fallback there is pure upside.
//
// WHY THIS FILE IS SHORT: DeepSeek's API is OpenAI-compatible — the same
// POST /chat/completions shape Groq already uses (see
// GuruAdminApiService). So this is deliberately a near-copy of that
// request shape rather than a new abstraction: less code to go wrong,
// and anyone who understands the Groq path already understands this one.
//
// Conventions match every other AI service in this app: resolveApiKey()
// does env-var-then-SharedPreferences, no method ever throws into the
// UI, and this file performs zero Firestore writes.
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'admin_ai_tools_schema.dart';

class DeepSeekApiService {
  DeepSeekApiService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 30);

  final http.Client _client;
  final Duration _timeout;

  static const String _apiKey = String.fromEnvironment(
    'DEEPSEEK_API_KEY',
    defaultValue: 'DEEPSEEK_API_KEY_HERE',
  );

  /// Matches the naming of 'personal_ai_api_key' (Groq) and
  /// 'personal_gemini_api_key' so admin_ai_settings_screen.dart can save
  /// all three the same way.
  static const String _savedApiKeyPrefsKey = 'personal_deepseek_api_key';

  static final Uri _endpoint =
      Uri.parse('https://api.deepseek.com/chat/completions');

  /// Default model: updated to v4-flash per user's IDE alignment.
  static const String _model = 'deepseek-v4-flash';

  // NEW (Aug 12 2026 — Nizam: per-key model selection): mirrors the
  // same _modelPrefsKey/_resolveModel pattern added to
  // GuruAdminApiService and GeminiApiService. Falls back to
  // deepseek-chat when the CTO hasn't picked anything yet.
  static const String _modelPrefsKey = 'personal_deepseek_model';

  Future<String> _resolveModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modelPrefsKey)?.trim();
    return (saved == null || saved.isEmpty) ? _model : saved;
  }

  /// Public wrapper so admin_ai_settings_screen.dart can show the
  /// currently-active model as the dropdown's initial value.
  Future<String> resolveModel() => _resolveModel();

  Future<String> sendMessage({
    required String message,
    required String apiKey,
    List<Map<String, String>> history = const <Map<String, String>>[],
  }) async {
    final input = message.trim();
    if (input.isEmpty) return 'Tell me what you need.';
    if (apiKey.trim().isEmpty) {
      return 'DeepSeek agent is not configured yet — add the key in '
          'Admin AI Configuration before switching to it.';
    }
    try {
      // Same {role, content} history shape used by Groq and translated
      // for Gemini — OpenAI-compatible, so it passes straight through.
      final messages = <Map<String, String>>[
        for (final turn in history.reversed.take(10).toList().reversed)
          {
            'role': turn['role'] == 'assistant' ? 'assistant' : 'user',
            'content': turn['content'] ?? '',
          },
        {'role': 'user', 'content': input},
      ];

      final response = await _client
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode(<String, dynamic>{
              'model': await _resolveModel(),
              'messages': messages,
              'temperature': 0.6,
              // Bounded like the Groq path — an admin chat reply that
              // runs long is a cost problem, not a feature.
              'max_tokens': 600,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[DeepSeekApiService] sendMessage failed: '
          '${response.statusCode} ${response.body}',
        );
        // Real, actionable errors — same reasoning as the Gemini fix on
        // Aug 11 2026: a single generic "unavailable" string made a bad
        // key, an empty balance and a rate limit indistinguishable, which
        // is exactly what left the Gemini problem unfixed for so long.
        return _explainFailure(response);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) return 'DeepSeek replied with an empty response.';
      final msg =
          (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final text = (msg?['content'] as String?)?.trim() ?? '';
      return text.isEmpty ? 'DeepSeek replied with an empty response.' : text;
    } catch (e) {
      debugPrint('[DeepSeekApiService] sendMessage error: $e');
      return 'DeepSeek agent is temporarily unavailable ($e).';
    }
  }

  // NEW (Aug 12 2026 — Nizam: "apdi set pannuna model than quick task
  // la enaku full and full yennoda assistanta ah irukanum"): DeepSeek
  // is OpenAI-compatible, so this reuses the exact same shared tool
  // schema and system prompt as Groq (admin_ai_tools_schema.dart) and
  // the same request/response shape — {'type': 'function', ...} tools
  // array in, choices[0].message.tool_calls out. Mirrors
  // GuruAdminApiService.extractAgentAction's contract exactly: returns
  // null when no tool matched or on any failure, otherwise
  // {'action': name, ...args}.
  Future<Map<String, dynamic>?> extractAgentAction({
    required String message,
    required String apiKey,
  }) async {
    final input = message.trim();
    if (apiKey.trim().isEmpty || input.isEmpty) return null;
    try {
      final response = await _client
          .post(
            _endpoint,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${apiKey.trim()}',
            },
            body: jsonEncode(<String, dynamic>{
              'model': await _resolveModel(),
              'messages': <Map<String, String>>[
                {'role': 'system', 'content': kAdminToolSystemPrompt},
                {'role': 'user', 'content': input},
              ],
              'tools': kAdminOpenAiTools(),
              'tool_choice': 'auto',
              'temperature': 0,
              'max_tokens': 200,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          '[DeepSeekApiService] extractAgentAction failed: '
          '${response.statusCode} ${response.body}',
        );
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) return null;

      final choiceMessage =
          (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final toolCalls = choiceMessage?['tool_calls'] as List<dynamic>?;
      if (toolCalls == null || toolCalls.isEmpty) return null;

      final function =
          (toolCalls.first as Map<String, dynamic>)['function'] as Map<String, dynamic>?;
      final functionName = function?['name'] as String?;
      if (function == null || !kAdminKnownActions.contains(functionName)) return null;

      final argumentsRaw = function['arguments'] as String?;
      if (functionName == 'audit_ui_sections' || functionName == 'run_ux_audit') {
        return {'action': functionName};
      }
      if (argumentsRaw == null || argumentsRaw.trim().isEmpty) return null;
      final args = jsonDecode(argumentsRaw) as Map<String, dynamic>;
      return {'action': functionName, ...args};
    } catch (e) {
      debugPrint('[DeepSeekApiService] extractAgentAction error: $e');
      return null;
    }
  }

  static String _explainFailure(http.Response res) {
    String detail = '';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error']['message'] as String?)?.trim() ?? '';
      }
    } catch (_) {/* body wasn't JSON */}

    switch (res.statusCode) {
      case 401:
        return 'DeepSeek rejected this API key (401). Re-paste it in Admin '
            'AI Configuration.${detail.isEmpty ? '' : '\n\n$detail'}';
      case 402:
        // DeepSeek is prepaid — this is its "you are out of credit" code,
        // and the single most likely failure in normal use.
        return 'DeepSeek account has insufficient balance (402). Top up '
            'credit at platform.deepseek.com.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
      case 429:
        return 'DeepSeek rate limit hit (429). Wait a moment and retry.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
      default:
        return 'DeepSeek error ${res.statusCode}.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
    }
  }

  Future<String> resolveApiKey() async {
    final baked = _apiKey.trim();
    if (baked.isNotEmpty && baked != 'DEEPSEEK_API_KEY_HERE' && baked != 'DEEPSEEK_API_KEY') {
      return baked;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_savedApiKeyPrefsKey)?.trim() ?? '';
    debugPrint('[DeepSeekApiService] resolved DeepSeek key length: ${stored.length}');
    return stored;
  }

  void dispose() {
    _client.close();
  }
}
