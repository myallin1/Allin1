import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../config/app_knowledge_briefing.dart';

enum AIPersona {
  customer,
  hero,
}

class AIService {
  AIService({
    List<String>? modelChain,
    http.Client? client,
    Duration? requestTimeout,
  })  : _modelChain = modelChain ??
            const <String>[
              'llama-3.3-70b-versatile',
              'llama-3.1-8b-instant',
              'openai/gpt-oss-20b',
            ],
        _client = client ?? http.Client(),
        _requestTimeout = requestTimeout ?? const Duration(seconds: 12);

  static const String _apiKeyPrefsKey = 'personal_ai_api_key';
  static final Uri _endpoint =
      Uri.parse('https://api.groq.com/openai/v1/chat/completions');

  final List<String> _modelChain;
  final http.Client _client;
  final Duration _requestTimeout;

  Future<String> sendMessage(
    String message, {
    AIPersona persona = AIPersona.customer,
    List<Map<String, String>> history = const <Map<String, String>>[],
    String? systemPrompt,
    // FIX (QA bug — "AI State Mismatch"): callers that already hold an
    // AiActivationService (which reads the customer's key from
    // flutter_secure_storage) should pass its `apiKey` here directly.
    // Without this, this method fell back to its OWN independent
    // SharedPreferences('personal_ai_api_key') lookup — the LEGACY
    // storage location that AiActivationService's one-time migration
    // actively deletes from once a key is moved into secure storage.
    // That split meant Settings could report "activated" (secure
    // storage has the key) while every actual chat call still saw an
    // empty key here and returned a generic "add your key" message.
    String? apiKey,
  }) async {
    final trimmed = message.trim();
    if (trimmed.isEmpty) {
      return 'Tell me what you need, and I will help you place the right request.';
    }

    var resolvedKey = apiKey?.trim() ?? '';
    if (resolvedKey.isEmpty) {
      // Back-compat fallback only — no current caller should hit this
      // once every call site passes AiActivationService's apiKey, but
      // kept so an old/legacy key some device migrated from still works
      // rather than silently breaking.
      final prefs = await SharedPreferences.getInstance();
      resolvedKey = prefs.getString(_apiKeyPrefsKey)?.trim() ?? '';
    }
    if (resolvedKey.isEmpty) {
      return 'Add your Groq API key in Settings to activate NJ Tech AI chat.';
    }

    Object? lastError;
    for (final model in _modelChain) {
      try {
        final response = await _sendViaGroq(
          apiKey: resolvedKey,
          model: model,
          persona: persona,
          message: trimmed,
          history: history,
          systemPrompt: systemPrompt,
        ).timeout(_requestTimeout);

        if (response.statusCode == 429) {
          debugPrint(
            'Groq rate limited on $model. Retrying with the next model...',
          );
          lastError = '429';
          continue;
        }

        if (response.statusCode >= 500) {
          debugPrint(
            'Groq server error ${response.statusCode} on $model. Trying fallback...',
          );
          lastError = 'server_${response.statusCode}';
          continue;
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          debugPrint(
            'Groq request failed on $model: ${response.statusCode} ${response.body}',
          );
          lastError = 'http_${response.statusCode}';
          continue;
        }

        final data = jsonDecode(response.body) as Map<String, dynamic>;
        final choices = data['choices'] as List<dynamic>? ?? const [];
        if (choices.isEmpty) {
          lastError = 'empty_choices';
          continue;
        }

        final firstChoice = choices.first as Map<String, dynamic>;
        final messageMap =
            firstChoice['message'] as Map<String, dynamic>? ?? const {};
        final content = messageMap['content']?.toString().trim() ?? '';
        if (content.isNotEmpty) {
          return content;
        }

        lastError = 'empty_content';
      } on TimeoutException catch (error) {
        lastError = error;
        debugPrint(
          'Groq timeout on $model. Retrying with the next model...',
        );
      } catch (error) {
        lastError = error;
        debugPrint('Groq request failed on $model: $error');
      }
    }

    debugPrint('Groq fallback chain exhausted: $lastError');
    return persona == AIPersona.hero
        ? 'Hero AI is taking a short pit stop right now. Try again in a moment and we will get your motivation buddy back.'
        : 'Local Friend is busy for a moment. Try again shortly and I will help with rides, offers, and local services.';
  }

  Future<http.Response> _sendViaGroq({
    required String apiKey,
    required String model,
    required AIPersona persona,
    required String message,
    required List<Map<String, String>> history,
    String? systemPrompt,
  }) {
    final messages = <Map<String, String>>[
      {
        'role': 'system',
        'content': systemPrompt?.trim().isNotEmpty ?? false
            ? systemPrompt!.trim()
            : _systemPromptFor(persona),
      },
      ...history
          .where(
            (entry) =>
                (entry['role'] == 'user' || entry['role'] == 'assistant') &&
                (entry['content']?.trim().isNotEmpty ?? false),
          )
          .map(
            (entry) => <String, String>{
              'role': entry['role']!,
              'content': entry['content']!.trim(),
            },
          ),
      {
        'role': 'user',
        'content': message,
      },
    ];

    return _client.post(
      _endpoint,
      headers: <String, String>{
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $apiKey',
      },
      body: jsonEncode(
        <String, dynamic>{
          'model': model,
          'messages': messages,
          'temperature': 0.6,
        },
      ),
    );
  }

  /// NEW (Aug 17 2026): every persona is now briefed on the real app
  /// before its own personality is applied.
  ///
  /// Previously each persona prompt described only a TONE ("motivation
  /// buddy", "local friend") and nothing about the system it lives in,
  /// so the assistant had no idea what MyAllin1 actually does, which
  /// collections exist, or that there is no server. It answered from
  /// generic world knowledge and guessed.
  ///
  /// The briefing comes from AppKnowledgeBriefing, whose factual half is
  /// REGENERATED FROM THE CODEBASE ON EVERY DEPLOY
  /// (tools/gen_app_knowledge.dart, wired into deploy_web.ps1). That is
  /// what makes "namma oru new update vittalum athuvum AI-ku theriyum"
  /// true by construction rather than by remembering to update a prompt.
  ///
  /// Persona voice is appended AFTER the briefing so it stays the last
  /// instruction the model reads.
  String _systemPromptFor(AIPersona persona) {
    return '${AppKnowledgeBriefing.build()}\n\n${_personaVoiceFor(persona)}';
  }

  String _personaVoiceFor(AIPersona persona) {
    switch (persona) {
      case AIPersona.hero:
        return 'You are NJ Tech Hero AI, a Motivation Buddy for bike-taxi Heroes. '
            'Celebrate completed trips, earnings, discipline, and consistency. '
            'Use short, energetic Tamil-English lines when helpful. '
            'Be supportive, practical, and confidence-building, especially around daily goals, customer handling, safety, and income.';
      case AIPersona.customer:
        return 'You are NJ Tech Customer AI, a Local Friend for people in Erode. '
            'Speak like a friendly Tamil-English local guide. '
            'Help with rides, delivery, NJ Tech offers, broadband, and nearby service questions. '
            'Keep answers concise, warm, and practical, with Erode-friendly phrasing when natural.';
    }
  }
}
