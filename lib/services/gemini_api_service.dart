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

import 'admin_ai_tools_schema.dart';

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
  // FIX (Aug 11 2026 — Nizam: "gemini api key configure agi gemini model
  // work agala" while Groq works fine on both apps): a SINGLE hardcoded
  // model name is the most common way this breaks. Google rotates and
  // retires Gemini model IDs regularly, and a given AI Studio key may not
  // have access to every model — either case returns HTTP 404
  // ("model not found") or 403, which the old code swallowed into a
  // generic "temporarily unavailable" string (see sendMessage below), so
  // the real cause was invisible. Now we try a small ordered list of
  // known-good IDs and use the first that responds, which survives Google
  // renaming the current one out from under us.
  static const List<String> _modelCandidates = <String>[
    'gemini-2.0-flash',
    'gemini-2.0-flash-001',
    'gemini-1.5-flash',
    'gemini-flash-latest',
  ];

  /// Remembers which candidate actually worked, so we pay the fallback
  /// cost at most once per app session instead of on every message.
  static String? _workingModel;

  // NEW (Aug 12 2026 — Nizam: per-key model selection): when the CTO
  // has explicitly picked a model in admin_ai_settings_screen.dart,
  // that choice is tried FIRST, ahead of both the cached _workingModel
  // and the hardcoded fallback list — an explicit pick should win over
  // whatever happened to work last time. Falls straight through to the
  // existing fallback behavior when nothing has been picked.
  static const String _modelPrefsKey = 'personal_gemini_model';

  Future<String?> _preferredModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modelPrefsKey)?.trim();
    return (saved == null || saved.isEmpty) ? null : saved;
  }

  /// Public wrapper so admin_ai_settings_screen.dart can show the
  /// currently-active model as the dropdown's initial value.
  Future<String> resolveModel() async => (await _preferredModel()) ?? _modelCandidates.first;

  static Uri _endpointForModel(String model, String apiKey) => Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey',
      );

  /// POSTs [body] against each candidate model until one succeeds.
  /// Returns the successful response, or the LAST failure so the caller
  /// can surface a real error message rather than a generic one.
  Future<http.Response> _postWithModelFallback(
    String apiKey,
    Map<String, dynamic> body,
  ) async {
    final preferred = await _preferredModel();
    final ordered = <String>[
      if (preferred != null) preferred,
      if (_workingModel != null && _workingModel != preferred) _workingModel!,
      ..._modelCandidates.where((m) => m != preferred && m != _workingModel),
    ];
    http.Response? last;
    for (final model in ordered) {
      final res = await _client
          .post(
            _endpointForModel(model, apiKey),
            headers: const {'Content-Type': 'application/json'},
            body: jsonEncode(body),
          )
          .timeout(_timeout);
      if (res.statusCode >= 200 && res.statusCode < 300) {
        if (_workingModel != model) {
          debugPrint('[GeminiApiService] using model: $model');
          _workingModel = model;
        }
        return res;
      }
      debugPrint(
        '[GeminiApiService] model "$model" failed: ${res.statusCode} ${res.body}',
      );
      last = res;
      // 401/403 are key problems, not model problems — trying other
      // models would just repeat the same failure, so stop early.
      if (res.statusCode == 401 || res.statusCode == 403) break;
    }
    return last!;
  }

  /// Turns a Gemini error response into something the ADMIN can act on.
  ///
  /// FIX (Aug 11 2026): every failure path in this file used to collapse
  /// into the same "Gemini agent is temporarily unavailable" string, so a
  /// wrong key, a disabled API, an exhausted quota and a retired model
  /// were indistinguishable — which is exactly why this stayed unfixed.
  /// These messages name the actual problem and the fix.
  static String _explainFailure(http.Response res) {
    String detail = '';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error']['message'] as String?)?.trim() ?? '';
      }
    } catch (_) {/* body wasn't JSON — fall through */}

    switch (res.statusCode) {
      case 400:
        return 'Gemini rejected the request (400). Usually an invalid API '
            'key format. Re-paste the key in Admin AI Configuration.'
            '${detail.isEmpty ? '' : '\n\nGoogle said: $detail'}';
      case 401:
      case 403:
        return 'Gemini refused this API key (${res.statusCode}). Check that '
            'the key is correct, that the "Generative Language API" is '
            'ENABLED for its Google Cloud project, and that the key has no '
            'HTTP-referrer/IP restriction blocking this app.'
            '${detail.isEmpty ? '' : '\n\nGoogle said: $detail'}';
      case 404:
        return 'Gemini model not found (404) for this key — none of the '
            'model IDs we try are available to it. This key may be from a '
            'region or project without Gemini access.'
            '${detail.isEmpty ? '' : '\n\nGoogle said: $detail'}';
      case 429:
        return 'Gemini quota exceeded (429). The free tier has a low '
            'per-minute limit — wait a moment and retry.'
            '${detail.isEmpty ? '' : '\n\nGoogle said: $detail'}';
      default:
        return 'Gemini error ${res.statusCode}.'
            '${detail.isEmpty ? '' : '\n\nGoogle said: $detail'}';
    }
  }

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
      final response = await _postWithModelFallback(
        apiKey.trim(),
        {'contents': contents},
      );
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[GeminiApiService] sendMessage failed: ${response.statusCode} ${response.body}');
        // Surface the REAL reason instead of a generic string — see
        // _explainFailure. This is what makes the problem diagnosable.
        return _explainFailure(response);
      }
      final text = _extractText(response.body);
      return (text == null || text.isEmpty) ? 'Gemini agent replied with an empty response.' : text;
    } catch (e) {
      debugPrint('[GeminiApiService] sendMessage error: $e');
      return 'Gemini agent is temporarily unavailable. Please try again shortly.';
    }
  }

  // NEW (Aug 12 2026 — Nizam: "apdi set pannuna model than quick task
  // la enaku full and full yennoda assistanta ah irukanum" — whichever
  // provider is switched to must be an equally capable admin agent,
  // not just a chat window): Gemini's own function-calling shape,
  // mirroring GuruAdminApiService.extractAgentAction's contract
  // exactly (same 5 tools, same return shape: null when no tool
  // matched or on any failure, otherwise {'action': name, ...args}).
  // Gemini's REST API differs from Groq/DeepSeek's OpenAI-compatible
  // shape in three ways handled here: (1) the system prompt is a
  // top-level `systemInstruction` field, not a `system` message; (2)
  // tools are `tools: [{functionDeclarations: [...]}]` with UPPERCASE
  // JSON-schema types (see admin_ai_tools_schema.dart), not an OpenAI
  // `tools` array; (3) a matched call arrives as
  // candidates[0].content.parts[].functionCall with `args` already a
  // JSON object — no jsonDecode of a string needed, unlike Groq's
  // `arguments` string field.
  Future<Map<String, dynamic>?> extractAgentAction({
    required String message,
    required String apiKey,
  }) async {
    final input = message.trim();
    if (apiKey.trim().isEmpty || input.isEmpty) return null;
    try {
      final response = await _postWithModelFallback(apiKey.trim(), {
        'systemInstruction': {
          'parts': [
            {'text': kAdminToolSystemPrompt},
          ],
        },
        'contents': [
          {
            'role': 'user',
            'parts': [
              {'text': input},
            ],
          },
        ],
        'tools': [
          {'functionDeclarations': kAdminGeminiFunctionDeclarations()},
        ],
        'toolConfig': {
          'functionCallingConfig': {'mode': 'AUTO'},
        },
        'generationConfig': {'temperature': 0},
      });
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[GeminiApiService] extractAgentAction failed: ${response.statusCode} ${response.body}');
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final candidates = body['candidates'] as List<dynamic>? ?? const [];
      if (candidates.isEmpty) return null;
      final content = (candidates.first as Map<String, dynamic>)['content'] as Map<String, dynamic>?;
      final parts = content?['parts'] as List<dynamic>? ?? const [];
      for (final part in parts) {
        if (part is! Map<String, dynamic>) continue;
        final functionCall = part['functionCall'] as Map<String, dynamic>?;
        if (functionCall == null) continue;
        final name = functionCall['name'] as String?;
        if (name == null || !kAdminKnownActions.contains(name)) continue;
        final args = functionCall['args'] as Map<String, dynamic>? ?? const <String, dynamic>{};
        return {'action': name, ...args};
      }
      return null;
    } catch (e) {
      debugPrint('[GeminiApiService] extractAgentAction error: $e');
      return null;
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
      // Same model-fallback path as sendMessage — a retired model ID
      // would otherwise silently break vision too, returning null with no
      // explanation.
      final response = await _postWithModelFallback(apiKey.trim(), {
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
      });
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
