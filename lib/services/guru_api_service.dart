import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class GuruApiService {
  GuruApiService({
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 18);

  static const String systemPrompt =
      "You are Guru AI, the smart, friendly assistant for the Allin1 Super App and NJ Tech, based in Erode, Tamil Nadu. You are an expert in Erode's geography and culture. Your job is to help customers book bike taxis, order Chamunda Spares, get mobile/laptop repairs at NJ Tech, and navigate the app. Answer in English or Tamil. Be concise, classy, and highly respectful.";

  static const String _apiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: 'GROQ_API_KEY_HERE',
  );
  static const String _savedApiKeyPrefsKey = 'personal_ai_api_key';
  static final Uri _endpoint =
      Uri.parse('https://api.groq.com/openai/v1/chat/completions');

  final http.Client _client;
  final Duration _timeout;

  Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const <Map<String, String>>[],
  }) async {
    final input = message.trim();
    if (input.isEmpty) {
      return 'Tell me what you need, and I will guide you quickly.';
    }

    final apiKey = await _resolveApiKey();
    if (apiKey.isEmpty) {
      return 'Guru AI is ready. Add the Groq API key before launch to activate live replies.';
    }

    try {
      final response = await _client
          .post(
            _endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(
              <String, dynamic>{
                'model': 'llama-3.1-8b-instant',
                'messages': <Map<String, String>>[
                  {
                    'role': 'system',
                    'content': systemPrompt,
                  },
                  ...history.where(
                    (entry) =>
                        (entry['role'] == 'user' ||
                            entry['role'] == 'assistant') &&
                        (entry['content']?.trim().isNotEmpty ?? false),
                  ),
                  {
                    'role': 'user',
                    'content': input,
                  },
                ],
                'temperature': 0.55,
                'max_tokens': 450,
              },
            ),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
          'Guru Groq request failed: ${response.statusCode} ${response.body}',
        );
        return 'Guru AI is having a short network pause. Please try again in a moment.';
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) {
        return 'Guru AI did not receive a proper reply. Please ask once more.';
      }

      final choice = choices.first as Map<String, dynamic>;
      final responseMessage =
          choice['message'] as Map<String, dynamic>? ?? const {};
      final content = responseMessage['content']?.toString().trim() ?? '';
      return content.isEmpty
          ? 'Guru AI is thinking, but the reply came back empty. Please try again.'
          : content;
    } on TimeoutException {
      return 'Guru AI took too long to respond. Please try again.';
    } catch (error) {
      debugPrint('Guru AI error: $error');
      return 'Guru AI is temporarily unavailable. I will be back shortly.';
    }
  }

  Future<String> _resolveApiKey() async {
    if (_apiKey.trim().isNotEmpty && _apiKey != 'GROQ_API_KEY_HERE') {
      return _apiKey.trim();
    }
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_savedApiKeyPrefsKey)?.trim() ?? '';
  }

  void dispose() {
    _client.close();
  }
}
