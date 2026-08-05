// ================================================================
// GeminiApiService — the "Deep Reasoning" / vision half of the
// Multi-Agent Orchestration & Handoff Architecture.
// ================================================================
// NEW (CTO mandate — Multi-Agent Orchestration & Handoff Architecture).
// Groq (GuruApiService / GuruAdminApiService) stays the fast
// tool-calling orchestrator on both the customer and admin sides —
// nothing about their existing tool-calling paths changes here. This
// file adds Gemini as the second agent: used (a) directly by the admin
// toggle in admin_quick_task_service.dart when the CTO switches to
// "Gemini (Deep Reasoning)" for plain conversation, and (b) as the
// vision specialist Groq hands screenshots off to for the DMart "I
// Need This" flow (see dmart_screen.dart and guru_api_service.dart's
// new `analyze_screen_with_vision` tool).
//
// Shares the exact same "additive, degrade-clean" conventions as every
// other AI service file in this app: resolveApiKey() mirrors
// GuruApiService/GuruAdminApiService's own env-var-then-SharedPreferences
// pattern, every public method returns null/a plain-text failure
// message on any error rather than throwing into the UI, and this file
// performs zero Firestore writes of any kind.
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GeminiApiService {
  GeminiApiService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 25);

  final http.Client _client;
  final Duration _timeout;

  static const String _apiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'GEMINI_API_KEY_HERE',
  );
  static const String _savedApiKeyPrefsKey = 'personal_gemini_api_key';
  static const String _model = 'gemini-2.0-flash';
  static Uri _endpointFor(String apiKey) => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=$apiKey',
      );

  /// Plain conversational reply — used by the Admin "Gemini (Deep
  /// Reasoning)" toggle. Deliberately no tool-calling here: per the
  /// CTO's own framing, Groq stays the "Fast Logic" tool-calling agent;
  /// Gemini is the "Deep Reasoning" conversational + vision agent. If
  /// tool-calling parity for Gemini is wanted later, that is a separate
  /// mandate, not silently folded into this toggle.
  Future<String> sendMessage({
    required String message,
    required String apiKey,
    List<Map<String, String>> history = const <Map<String, String>>[],
  }) async {
    final input = message.trim();
    if (input.isEmpty) return 'Tell me what you need.';
    if (apiKey.trim().isEmpty) {
      return 'Gemini agent is not configured yet — add GEMINI_API_KEY before switching to it.';
    }
    try {
      // Gemini's REST "contents" shape uses role user/model, not
      // user/assistant — translated here so callers can keep passing
      // the same {role, content} history shape used everywhere else in
      // this app (GuruAdminApiService.sendMessage's own history param).
      final contents = <Map<String, dynamic>>[
        for (final turn in history.reversed.take(10).toList().reversed)
          {
            'role': turn['role'] == 'assistant' ? 'model' : 'user',
            'parts': [
              {'text': turn['content'] ?? ''},
            ],
          },
        {
          'role': 'user',
          'parts': [
            {'text': input},
          ],
        },
      ];
      final response = await _client
          .post(
            _endpointFor(apiKey.trim()),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({'contents': contents}),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[GeminiApiService] sendMessage failed: ${response.statusCode} ${response.body}');
        return 'Gemini agent is temporarily unavailable. Please try again shortly.';
      }
      final text = _extractText(response.body);
      return (text == null || text.isEmpty) ? 'Gemini agent replied with an empty response.' : text;
    } catch (e) {
      debugPrint('[GeminiApiService] sendMessage error: $e');
      return 'Gemini agent is temporarily unavailable. Please try again shortly.';
    }
  }

  /// The vision-handoff step (CTO mandate steps 3-4): given a
  /// screenshot, extract EVERY product visible (not just one, unlike
  /// GuruApiService.extractGroceryItemFromImage's single-item design)
  /// and return a clean numbered list as structured data. Returns null
  /// on any failure/empty read — same "never a crash, never a guessed
  /// item" contract as every vision method in this app.
  Future<List<Map<String, String>>?> analyzeGroceryScreenshot({
    required Uint8List imageBytes,
    required String apiKey,
  }) async {
    if (apiKey.trim().isEmpty) return null;
    try {
      final response = await _client
          .post(
            _endpointFor(apiKey.trim()),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode({
              'contents': [
                {
                  'role': 'user',
                  'parts': [
                    {
                      'text':
                          'This is a photo of a grocery product or shopping app screen. '
                          'Identify EVERY distinct product visible — there may be one or '
                          'several. For each, note the quantity/pack size if visible. '
                          'Respond with ONLY strict JSON, no other text, no markdown '
                          'fences: {"items": [{"item": "<product name>", "quantity": '
                          '"<quantity/pack size, empty string if not visible>"}, ...]}. '
                          'If nothing is clearly identifiable, respond with {"items": []}.',
                    },
                    {
                      'inline_data': {
                        'mime_type': 'image/jpeg',
                        'data': base64Encode(imageBytes),
                      },
                    },
                  ],
                },
              ],
              'generationConfig': {'temperature': 0, 'maxOutputTokens': 500},
            }),
          )
          .timeout(_timeout);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[GeminiApiService] vision analysis failed: ${response.statusCode} ${response.body}');
        return null;
      }
      final text = _extractText(response.body);
      if (text == null || text.isEmpty) return null;
      final cleaned = text.replaceAll(RegExp(r'```json|```'), '').trim();
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      final rawItems = parsed['items'] as List<dynamic>? ?? const [];
      final items = <Map<String, String>>[];
      for (final raw in rawItems) {
        if (raw is! Map<String, dynamic>) continue;
        final item = (raw['item'] as String?)?.trim() ?? '';
        if (item.isEmpty) continue;
        items.add({'item': item, 'quantity': (raw['quantity'] as String?)?.trim() ?? ''});
      }
      return items;
    } catch (e) {
      debugPrint('[GeminiApiService] analyzeGroceryScreenshot error: $e');
      return null;
    }
  }

  static String? _extractText(String responseBody) {
    try {
      final body = jsonDecode(responseBody) as Map<String, dynamic>;
      final candidates = body['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) return null;
      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      if (parts.isEmpty) return null;
      return (parts.first as Map<String, dynamic>)['text'] as String?;
    } catch (e) {
      debugPrint('[GeminiApiService] response parse error: $e');
      return null;
    }
  }

  Future<String> resolveApiKey() async {
    if (_apiKey.trim().isNotEmpty && _apiKey != 'GEMINI_API_KEY_HERE') {
      return _apiKey.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedApiKeyPrefsKey)?.trim() ?? '';
  }

  void dispose() {
    _client.close();
  }
}
