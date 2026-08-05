import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'analytics_service.dart';

class GuruApiService {
  GuruApiService({
    http.Client? client,
    Duration? timeout,
  })  : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 18);

  // FIX (Guru AI upgrade, Task 3 — CTO's "Super App Manager" mandate):
  // reframed as an energetic, proud "AI Manager and Guide" per the
  // CTO's exact brief, while keeping the detailed per-service list and
  // the "never claim to have placed a booking" honesty guardrail from
  // the previous prompt — dropping those would make answers vaguer and
  // reintroduce a real risk of the AI implying it took an action it
  // didn't. Also now explicitly covers screenshot troubleshooting
  // (Task 2 — Vision) and calls out Groceries/Electronics by name, both
  // asked for directly in the mandate.
  static const String systemPrompt =
      'You are Guru, the official AI Manager and Guide for the Allin1 Super '
      'App, based in Erode, Tamil Nadu, run by NJ Tech. You help customers '
      "navigate the app, troubleshoot issues via screenshots, and guide them "
      'confidently on how to place orders across every category: Bike Taxi, '
      'Auto, Cab, Parcel, Mini Truck, Lorry, Groceries, Food, Electronics '
      'repair/service, and SOS emergency assistance. Be highly energetic, '
      'helpful, and speak proudly about empowering the customer — you know '
      "Erode's streets, landmarks, and daily life like a confident local "
      'friend.\n'
      'The services you can explain, guide, and recommend are: \n'
      '1. Bike Taxi — quick, affordable one/two-person rides across Erode.\n'
      '2. Auto — three-wheeler rides for solo or small-group trips.\n'
      '3. Cab — comfortable car rides for longer distances or families.\n'
      '4. Parcel — same-city courier/delivery for documents and small packages.\n'
      '5. Mini Truck — for shifting furniture, shop goods, or medium loads.\n'
      '6. Lorry — for heavy loads, house shifting, or bulk material transport.\n'
      '7. Groceries — Send Order (DMart cart screenshots) for daily needs.\n'
      '8. Food Genie — ordering food from Erode hotels.\n'
      '9. Electronics — NJ Tech mobile/laptop/AC/fridge repair and service.\n'
      '10. SOS — emergency assistance button for customers (requires KYC '
      'approval first inside the app before it can be used).\n'
      'Beyond that, you also know about: Chamunda Spares, the Rewards/Erode '
      'Offers section, the Game Zone, and the customer wallet.\n'
      'If the customer shares a screenshot of the app, look at it carefully '
      'and help them troubleshoot exactly what they are stuck on — which '
      'screen it is, what button or field to use next, or what error it '
      'shows.\n'
      "When a customer describes a need (e.g. 'I need to send a fridge to my "
      "new house' or 'book an auto to the railway station'), identify which "
      'of the above services fits best and tell them clearly which tab or '
      'button to tap in the app to book it. Keep answers concise, warm, '
      'classy, and highly respectful. Reply in English or Tamil depending on '
      'how the customer writes to you. Never claim to have actually placed a '
      'booking yourself unless the app has explicitly told you a booking was '
      "created — you guide and inform, the app's own booking screens do the "
      'actual placing of orders.\n'
      // NEW (CTO mandate — "Co-work Style Confirmation & Suggestions"):
      // free-text confirmation guidance for normal conversational
      // replies. The actual tool-call confirmation gate (for
      // book_transport/navigate_to_section/check_and_update_app) is
      // enforced in Dart in guru_chat_screen.dart's
      // _tryAgentActionFromText — a plain instruction here can't
      // reliably stop the model from calling a tool immediately, so the
      // real safety net lives in code. This line keeps the model's own
      // words consistent with that behavior instead of contradicting it.
      'Before suggesting you are about to take an action (like booking a '
      'ride or opening a section), phrase it as asking for confirmation, '
      "e.g. 'I'm ready to book a bike to the bus stand — should I proceed?' "
      'and wait for the customer to say yes or no.\n'
      // NEW (CTO mandate — Tamil Language Quality Fix): the earlier
      // prompt only said "Reply in ... Tamil" with no register guidance,
      // so the model defaulted to stiff, literal-translation Tamil.
      // This forces natural spoken Erode-local Tamil instead.
      'When speaking in Tamil, you MUST use natural, grammatically correct, '
      'conversational colloquial Tamil (Spoken Tamil) suitable for users in '
      'Erode, Tamil Nadu. Do NOT use formal/bookish "Sangam" Tamil. Do not '
      'use awkward machine translations. Speak like a friendly local '
      'assistant (e.g., use words like "பாஸ்", "சரிங்க", "புக் பண்ணிடலாம்").\n'
      // NEW: suggestion chips — a lightweight structured hint the UI
      // parses out and renders as tappable buttons (see
      // guru_suggestion_parser.dart). Optional: only include it when 2-4
      // short, genuinely useful quick-reply options make sense for what
      // you just said; never fabricate options that don\'t make sense.
      'When it would help the customer reply quickly, end your message '
      '(after your normal reply text) with a single line in exactly this '
      'format: [SUGGESTIONS: option one | option two | option three] — '
      '2 to 4 short options, separated by " | ". Omit this line entirely '
      'when there is nothing sensible to suggest.';

  static const String _apiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: 'GROQ_API_KEY_HERE',
  );
  static const String _savedApiKeyPrefsKey = 'personal_ai_api_key';
  static final Uri _endpoint =
      Uri.parse('https://api.groq.com/openai/v1/chat/completions');

  // NEW (Guru AI upgrade, Task 2 — Vision): text-only chat keeps using
  // the fast/cheap instant model; the moment a screenshot is attached
  // we switch to a vision-capable model for that single request only
  // (vision models are slower/pricier — no reason to pay that cost on
  // every plain-text message). Confirmed current via Groq's own docs
  // (console.groq.com/docs/model/...) at the time this was written —
  // meta-llama/llama-4-maverick-17b-128e-instruct was deprecated
  // Feb 2026, so Scout is the one to use.
  static const String _textModel = 'llama-3.1-8b-instant';
  static const String _visionModel = 'meta-llama/llama-4-scout-17b-16e-instruct';

  final http.Client _client;
  final Duration _timeout;

  Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const <Map<String, String>>[],
    // FIX (QA bug — "AI State Mismatch & Pro Mode Confusion"): the
    // caller (guru_chat_screen.dart) already holds an
    // AiActivationService with the customer's key loaded from
    // flutter_secure_storage — pass it here directly. Without this,
    // _resolveApiKey() below fell back to its OWN independent
    // SharedPreferences('personal_ai_api_key') lookup, which
    // AiActivationService's one-time migration actively DELETES once a
    // key is moved into secure storage. Net effect before this fix:
    // Settings correctly showed "Guru already activated" (secure
    // storage has the key) while every real chat message still hit
    // this empty-key branch below and replied "not available... check
    // back soon" — two code paths reading two different storage
    // locations for what was supposed to be the same key.
    String? apiKeyOverride,
    // NEW (Guru AI upgrade, Task 2 — Vision): raw screenshot bytes from
    // the attachment picker in guru_chat_screen.dart. When present, the
    // request switches to a vision-capable model and sends the image
    // alongside the text as a multimodal `content` array (OpenAI/Groq
    // chat-completions image_url format) instead of a plain string.
    Uint8List? imageBytes,
    String imageMimeType = 'image/jpeg',
    // NEW (CTO mandate — Deep Language Sync): 'Tamil' or 'English',
    // resolved by the caller from LocalizationService.languageCode.
    // Null/empty leaves the model to its existing "reply in whichever
    // language the customer wrote in" default behavior.
    String? languageLabel,
  }) async {
    final input = message.trim();
    if (input.isEmpty && imageBytes == null) {
      return 'Tell me what you need, and I will guide you quickly.';
    }

    // FIX (per Nizam's explicit request): this used to literally tell
    // the customer "Add the Groq API key before launch" — leaking the
    // internal activation mechanism (customer WhatsApps a claim, we
    // manually add their key server-side — see rewards_screen.dart's
    // _AiQuizDialog) straight into the chat UI. Replaced with a plain,
    // friendly message that reveals nothing about how activation works.
    final overrideTrimmed = apiKeyOverride?.trim() ?? '';
    final apiKey =
        overrideTrimmed.isNotEmpty ? overrideTrimmed : await _resolveApiKey();
    if (apiKey.isEmpty) {
      return "Guru AI isn't available on your account yet. Please check back soon!";
    }

    // NEW (Guru AI upgrade, Task 2 — Vision): build a multimodal user
    // message when a screenshot is attached; otherwise keep the exact
    // plain-string shape the text model expects. History stays
    // text-only either way — Groq's vision models only need the image
    // on the current turn, not replayed on every subsequent message.
    final Object userContent;
    if (imageBytes != null) {
      final effectiveText = input.isEmpty
          ? 'Here is a screenshot of an issue I\'m facing in the app. Please help me troubleshoot it.'
          : input;
      userContent = <Map<String, dynamic>>[
        {'type': 'text', 'text': effectiveText},
        {
          'type': 'image_url',
          'image_url': {
            'url': 'data:$imageMimeType;base64,${base64Encode(imageBytes)}',
          },
        },
      ];
    } else {
      userContent = input;
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
                'model': imageBytes != null ? _visionModel : _textModel,
                'messages': <Map<String, dynamic>>[
                  {
                    'role': 'system',
                    'content': (languageLabel != null && languageLabel.trim().isNotEmpty)
                        ? '$systemPrompt\nThe user has set their app language to '
                            '${languageLabel.trim()}. You MUST communicate, ask '
                            'questions, and provide suggestions strictly in '
                            '${languageLabel.trim()}.'
                        : systemPrompt,
                  },
                  ...history.where(
                    (entry) =>
                        (entry['role'] == 'user' ||
                            entry['role'] == 'assistant') &&
                        (entry['content']?.trim().isNotEmpty ?? false),
                  ),
                  {
                    'role': 'user',
                    'content': userContent,
                  },
                ],
                'temperature': 0.55,
                'max_tokens': 450,
              },
            ),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final logLine =
            'Guru Groq request failed: ${response.statusCode} ${response.body}';
        debugPrint(logLine);
        // FIX (Nizam's report — generic "network pause" message hides
        // the real reason, e.g. 401 invalid key / 429 rate limit / 400
        // bad request / model deprecated): debugPrint only reaches a
        // developer's attached console. Log the real status+body to
        // Crashlytics too (non-fatal) so Nizam can see the actual
        // Groq failure reason remotely from a QA device via the
        // Firebase Crashlytics dashboard, without me needing to be
        // physically present with a debugger.
        unawaited(
          AnalyticsService.instance.recordError(
            Exception('Guru Groq HTTP ${response.statusCode}'),
            StackTrace.current,
            reason: logLine.length > 500 ? logLine.substring(0, 500) : logLine,
          ),
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
    } catch (error, stackTrace) {
      debugPrint('Guru AI error: $error');
      unawaited(
        AnalyticsService.instance.recordError(error, stackTrace, reason: 'Guru AI sendMessage failed'),
      );
      return 'Guru AI is temporarily unavailable. I will be back shortly.';
    }
  }

  // NEW (Guru AI upgrade — CTO's "Autonomous Agent" mandate, Option 3
  // with the mandatory human-in-the-loop safety net, extended with the
  // "Dynamic PWA Guided Tour" navigation tool): the "brain" half of the
  // agent. Uses Groq's OpenAI-compatible function/tool calling with TWO
  // tools offered in the same request:
  //   - book_transport: a clear booking request → extract
  //     {service, destination}. Deliberately NEVER used to decide
  //     whether to actually dispatch a ride — that stays gated behind
  //     the customer's own tap on the existing booking screen's Confirm
  //     button, entirely unchanged by this method.
  //   - navigate_to_section: a "where/how do I do X" question → extract
  //     {section}, so the app can push the right screen directly
  //     instead of just describing it in text.
  // Returns null whenever the model calls neither tool (i.e. it judged
  // the message as neither) or on any failure — the caller
  // (guru_chat_screen.dart) falls back to a normal chat reply in every
  // such case, so a failure here never blocks the customer from
  // getting an answer. When a tool IS called, the returned map always
  // includes an 'action' key ('book_transport' or 'navigate_to_section')
  // alongside that tool's own arguments, so the caller can dispatch on
  // it without re-parsing raw Groq response shape.
  Future<Map<String, dynamic>?> extractAgentAction({
    required String message,
    required String apiKeyOverride,
  }) async {
    final apiKey = apiKeyOverride.trim();
    final input = message.trim();
    if (apiKey.isEmpty || input.isEmpty) {
      return null;
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
                'model': _textModel,
                'messages': <Map<String, String>>[
                  {
                    'role': 'system',
                    'content':
                        'You have three tools available. Call book_transport ONLY '
                        'when the user CLEARLY wants to book a ride or send '
                        'something right now (e.g. "book a bike to the bus '
                        'stand", "I need an auto to home", "send a parcel to '
                        'Erode market", "help, emergency"). Call '
                        'navigate_to_section ONLY when the user is asking where '
                        'or how to do something in the app that maps to one of '
                        'the listed sections (e.g. "where can I order food?", '
                        '"how do I fix my phone screen?", "show me rewards", '
                        '"I want to play a game"). Call check_and_update_app ONLY '
                        'when the user explicitly asks to update the app or '
                        'check for a new version (e.g. "update the app", "is '
                        'there a new version?", "check for updates"). For '
                        'general conversation, greetings, or anything that is '
                        'not clearly one of these three, do NOT call any tool '
                        '— just let the normal reply happen.',
                  },
                  {'role': 'user', 'content': input},
                ],
                'tools': <Map<String, dynamic>>[
                  {
                    'type': 'function',
                    'function': {
                      'name': 'book_transport',
                      'description':
                          'Start booking a transport/delivery service for the customer.',
                      'parameters': {
                        'type': 'object',
                        'properties': {
                          'service': {
                            'type': 'string',
                            'enum': ['bike', 'auto', 'cab', 'parcel', 'mini_truck', 'lorry', 'sos'],
                            'description': 'Which service the customer wants.',
                          },
                          'destination': {
                            'type': 'string',
                            'description':
                                'Where the customer wants to go or send something, in their own words. Omit for sos.',
                          },
                        },
                        'required': ['service'],
                      },
                    },
                  },
                  {
                    'type': 'function',
                    'function': {
                      'name': 'navigate_to_section',
                      'description':
                          'Open a specific section of the Allin1 app for the customer.',
                      'parameters': {
                        'type': 'object',
                        'properties': {
                          'section': {
                            'type': 'string',
                            'enum': [
                              'food',
                              'grocery',
                              'electronics',
                              'rewards',
                              'game_zone',
                              'safety',
                              'settings',
                              'car_wash',
                              'printing',
                            ],
                            'description': 'Which app section to open.',
                          },
                        },
                        'required': ['section'],
                      },
                    },
                  },
                  {
                    'type': 'function',
                    'function': {
                      'name': 'check_and_update_app',
                      'description':
                          'Check whether a newer version of the Allin1 app is '
                          'available and, if so, apply the update. No arguments.',
                      'parameters': {
                        'type': 'object',
                        'properties': <String, dynamic>{},
                        'required': <String>[],
                      },
                    },
                  },
                ],
                'tool_choice': 'auto',
                'temperature': 0,
                'max_tokens': 200,
              },
            ),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Guru agent-action extraction failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) return null;

      final choiceMessage =
          (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>?;
      final toolCalls = choiceMessage?['tool_calls'] as List<dynamic>?;
      if (toolCalls == null || toolCalls.isEmpty) {
        return null;
      }

      final function =
          (toolCalls.first as Map<String, dynamic>)['function'] as Map<String, dynamic>?;
      final functionName = function?['name'] as String?;
      const knownActions = {
        'book_transport',
        'navigate_to_section',
        'check_and_update_app',
      };
      if (function == null || !knownActions.contains(functionName)) {
        return null;
      }

      // check_and_update_app takes no arguments, so Groq may return an
      // empty/absent arguments string for it — that's expected, not a
      // parse failure, unlike the other two tools.
      final argumentsRaw = function['arguments'] as String?;
      if (functionName == 'check_and_update_app') {
        return {'action': functionName};
      }
      if (argumentsRaw == null || argumentsRaw.trim().isEmpty) {
        return null;
      }
      final args = jsonDecode(argumentsRaw) as Map<String, dynamic>;
      return {'action': functionName, ...args};
    } catch (error) {
      debugPrint('[GuruApiService] extractAgentAction error: $error');
      return null;
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
