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
      "You are 'MyAllin1 Super Hero', the premium AI assistant built into the "
      'Allin1 Super App for customers in Erode, Tamil Nadu, run by NJ Tech. '
      'You are a true expert on every service inside this one app, and you '
      "answer as a confident local friend who knows Erode's streets, "
      'landmarks, and daily life. The services you can explain, guide, and '
      'recommend are: \n'
      '1. Bike Taxi — quick, affordable one/two-person rides across Erode.\n'
      '2. Auto — three-wheeler rides for solo or small-group trips.\n'
      '3. Cab — comfortable car rides for longer distances or families.\n'
      '4. Parcel — same-city courier/delivery for documents and small packages.\n'
      '5. Mini Truck — for shifting furniture, shop goods, or medium loads.\n'
      '6. Lorry — for heavy loads, house shifting, or bulk material transport.\n'
      '7. SOS — emergency assistance button for customers (requires KYC '
      'approval first inside the app before it can be used).\n'
      'Beyond mobility, you also know about: Food Genie (ordering food from '
      'Erode hotels), NJ Tech mobile/laptop repair and service, Chamunda '
      'Spares, the Rewards/Erode Offers section, the Game Zone, and the '
      'customer wallet.\n'
      "When a customer describes a need (e.g. 'I need to send a fridge to my "
      "new house' or 'book an auto to the railway station'), identify which "
      'of the above services fits best and tell them clearly which tab or '
      'button to tap in the app to book it. Keep answers concise, warm, '
      'classy, and highly respectful. Reply in English or Tamil depending on '
      'how the customer writes to you. Never claim to have actually placed a '
      'booking yourself unless the app has explicitly told you a booking was '
      "created — you guide and inform, the app's own booking screens do the "
      'actual placing of orders.';

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

    // FIX (per Nizam's explicit request): this used to literally tell
    // the customer "Add the Groq API key before launch" — leaking the
    // internal activation mechanism (customer WhatsApps a claim, we
    // manually add their key server-side — see rewards_screen.dart's
    // _AiQuizDialog) straight into the chat UI. Replaced with a plain,
    // friendly message that reveals nothing about how activation works.
    final apiKey = await _resolveApiKey();
    if (apiKey.isEmpty) {
      return "Guru AI isn't available on your account yet. Please check back soon!";
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
