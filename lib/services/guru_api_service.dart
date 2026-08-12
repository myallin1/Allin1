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
      // UPDATED (CTO mandate — Autonomous Interaction Rule): booking/
      // navigation/section-opening tool calls now execute immediately
      // (see guru_chat_screen.dart / guru_overlay_service.dart) — do
      // NOT ask "should I proceed?" for these anymore, that phrasing is
      // now wrong. Replaced with the new two-scenario rule below. FIX
      // (caught during this same edit): the actual instruction text
      // MUST be inside a string literal, not a // comment, or Groq
      // never receives it — worth flagging since a silently-inert
      // prompt change is a very easy mistake to ship unnoticed.
      'You no longer need to ask "should I proceed?" before booking or '
      'opening a section — that now happens immediately. Only ask for '
      'confirmation in words in two situations: (A) an actual payment or '
      'final order/booking commitment — that confirmation happens on the '
      "booking screen itself, not in this chat, so just mention it's the "
      'next step rather than asking to proceed yourself; or (B) when you '
      'are genuinely unsure which service, section, or item the customer '
      'means. For (B), do not guess — ask a short clarifying question and '
      'offer EXACTLY 3 suggestion chips (using the [SUGGESTIONS: ...] '
      'format below) covering the most likely options, and wait for the '
      'customer to pick one instead of calling a tool with a guessed '
      'value.\n'
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
      'when there is nothing sensible to suggest.\n'
      // NEW (per Nizam's explicit request — "AI oru command kudutha
      // athuku action la yerangama... instruction and paragraph reply
      // pannuthu"): this is a strict length/behavior rule, not a
      // preference. If the customer's request clearly matches an
      // available tool (booking a service, navigating to a section,
      // checking for updates), you MUST call that tool immediately in
      // the SAME turn — do not describe the steps they should take
      // manually instead of just doing it. Your visible reply text in
      // that case must be ONE short sentence (under 15 words) — e.g. '
      "\"Opening Bike Taxi for you now!\" — never a multi-line explainer. "
      'Only fall back to a longer explanation when NO tool genuinely '
      'fits (general questions, troubleshooting, or you are unsure which '
      'option they mean — use the 3-suggestion-chip format for that last '
      'case, per the rule above, instead of writing a paragraph).';

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
    bool hasAttachedImage = false,
  }) async {
    final apiKey = apiKeyOverride.trim();
    final input = message.trim();
    if (apiKey.isEmpty || input.isEmpty) {
      return null;
    }
    // NEW (CTO mandate — Multi-Agent Orchestration & Handoff
    // Architecture): the actual image bytes never come anywhere near
    // this text-only tool-calling request — only this plain marker
    // does, so Groq can decide whether analyze_screen_with_vision
    // applies without ever seeing the pixels itself (Gemini is the only
    // agent that ever sees the image — see GeminiApiService).
    final userContent = hasAttachedImage
        ? '$input\n\n[System note: the customer has attached an image to this message.]'
        : input;

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
                        // FIX (Aug 11 2026 — Nizam: "AI sariya automatic
                        // order set pannama namaku instructions kuduthutruku,
                        // athum athigama explain panni ... api key limit
                        // theenthurum ... function calling than athigama
                        // pannanum, question mattum ketutu next customer
                        // soldra action-a athuve pannanum"):
                        //
                        // ROOT CAUSE of "it explains instead of doing": the
                        // instructions below were written defensively — they
                        // told the model to call a tool ONLY under narrow
                        // conditions and, whenever anything was even slightly
                        // ambiguous, to "let it fall through to the normal
                        // reply". A normal reply is free-form prose, so the
                        // model defaulted to long explanations. That is both
                        // the wrong UX (the user wants the ACTION performed)
                        // and the expensive one, because prose burns far more
                        // output tokens than a compact tool call — which is
                        // exactly why the API quota was draining.
                        //
                        // The rule below inverts that default: ACT first, and
                        // when something genuinely is missing, ask ONE short
                        // question rather than explaining. Kept deliberately
                        // strict about never inventing values — guessing a
                        // destination or an item is worse than asking.
                        'You are an ACTING agent inside this app, not a help '
                        'desk. Your job is to DO things for the user by '
                        'calling tools — not to describe how to do them. '
                        'Never explain the steps a user could take if a tool '
                        'can take them instead. Never output long paragraphs. '
                        'If a tool applies, call it. If required information '
                        'is missing, ask exactly ONE short question naming at '
                        'most 3 concrete options, then call the tool on their '
                        'answer. Never invent a destination, item, quantity or '
                        'section the user did not say. Keep every text reply '
                        'under 2 short sentences.\n\n'
                        'Call create_service_request whenever the customer '
                        'wants to ORDER or BOOK something that a Hero fulfils — '
                        'food, groceries, an errand, a pickup/drop, or any '
                        'custom purchase (e.g. "order 2 biryani from Sagar", '
                        '"I need 1kg onions and milk", "someone pick up my '
                        'parcel from Surampatti", "book a hero to collect my '
                        'documents"). This PLACES the real order — never '
                        'explain how to order manually when you can call this. '
                        'If the customer named a shop/hotel, pass it as vendor; '
                        'if not, leave vendor out rather than guessing.\n\n'
                        'Call report_app_bug whenever the customer says '
                        'something in the app is broken, stuck, not loading, '
                        'showing a wrong number, or not working as expected '
                        '(e.g. "the booking screen is blank", "my wallet '
                        'balance is wrong", "it keeps crashing when I tap '
                        'pay"). NEVER just apologise and leave it — an '
                        'apology fixes nothing. If you do not know which '
                        'screen or what they were doing, ask ONE short '
                        'question, then file the report. After filing, tell '
                        'them in one line that it has been sent to the team.\n\n'
                        'You have seven tools available. Call book_transport ONLY '
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
                        'there a new version?", "check for updates"). Call '
                        'add_to_grocery_cart ONLY when the user clearly wants to '
                        'add a grocery item to their list (e.g. "add 2 packs of '
                        'milk", "I need rice and sugar", "put onions on my '
                        'list"). Call analyze_screen_with_vision ONLY when the '
                        'user has attached a photo/screenshot to this message AND '
                        'wants you to identify a product in it for their grocery '
                        'list (e.g. "what is this?", "add this to my list" with an '
                        'attached image). Never call this tool if no image is '
                        'attached — there is nothing to analyze in that case. '
                        'Only for pure greetings or small talk with no '
                        'actionable intent should you skip tools entirely — and '
                        'even then reply in ONE short line.\n\n'
                        'IMPORTANT: if the request is genuinely ambiguous — you '
                        'cannot tell which service, section, or item the user '
                        'means (e.g. "book me a ride" with no service named) — '
                        'do NOT guess and do NOT call a tool with a made-up '
                        'value. Ask ONE short clarifying question offering at '
                        'most 3 options, and nothing else. As soon as the user '
                        'answers, immediately call the matching tool. Do not '
                        're-explain, do not confirm twice, do not summarise '
                        'what you are about to do — just call the tool.',
                  },
                  {'role': 'user', 'content': userContent},
                ],
                'tools': <Map<String, dynamic>>[
                  // NEW (Aug 11 2026 — Nizam's "AI Bug Reporting"): when a
                  // customer says something is broken, the agent files a
                  // real report instead of apologising into the void.
                  //
                  // Why this is worth a tool rather than a support email:
                  // the customer is ALREADY describing the problem to the
                  // agent in their own words, at the moment it happened.
                  // That is the highest-quality bug signal we will ever
                  // get, and today it evaporates. The agent summarises it
                  // into `app_bug_reports`, which the admin can review.
                  {
                    'type': 'function',
                    'function': {
                      'name': 'report_app_bug',
                      'description':
                          'File a bug report when the customer says something in the app is '
                          'broken, stuck, not loading, showing a wrong value, or otherwise not '
                          'working. Use this INSTEAD of only apologising. Ask at most one short '
                          'question first if you do not know which screen or what they were '
                          'doing, then call this.',
                      'parameters': {
                        'type': 'object',
                        'properties': {
                          'summary': {
                            'type': 'string',
                            'description':
                                'One-line summary of the problem, in plain English. '
                                'e.g. "Booking Status screen stays empty after placing an order".',
                          },
                          'details': {
                            'type': 'string',
                            'description':
                                "The customer's description of what happened, what they expected, "
                                'and any error text they mentioned. Use their own words where '
                                'possible — do not invent details they did not say.',
                          },
                          'screen': {
                            'type': 'string',
                            'description':
                                'Which screen/section the problem happened on, if the customer '
                                'said (e.g. "taxi booking", "rewards", "grocery"). Omit if unknown.',
                          },
                          'severity': {
                            'type': 'string',
                            'enum': ['low', 'medium', 'high'],
                            'description':
                                'high = cannot use the app or lost money; medium = a feature is '
                                'broken but there is a workaround; low = cosmetic or minor.',
                          },
                        },
                        'required': ['summary', 'details'],
                      },
                    },
                  },
                  // NEW (Aug 11 2026 — Nizam: the agent must PLACE food /
                  // grocery / hero-booking orders, not just explain how).
                  //
                  // Deliberately ONE tool rather than three: on the backend
                  // all of these are a single `service_requests` document
                  // distinguished only by `requestType` (see
                  // ServiceRequestService.createServiceRequest — the same
                  // path used by hero_booking_screen, grocery_order_screen,
                  // custom_food_order_screen, etc.). Three separate tools
                  // would mean three near-identical schemas for the model to
                  // disambiguate between, which measurably increases
                  // wrong-tool picks AND token cost — the exact quota
                  // problem Nizam flagged. One tool with a requestType enum
                  // maps 1:1 onto the real data model.
                  {
                    'type': 'function',
                    'function': {
                      'name': 'create_service_request',
                      'description':
                          'Place a REAL order/booking for the customer and dispatch it to nearby '
                          'Heroes. Use for food orders, grocery orders, hero bookings (errands, '
                          'pickup/drop, help), and custom orders. Call this as soon as you know '
                          'the request type and what the customer wants — do not describe the '
                          'steps, just place it.',
                      'parameters': {
                        'type': 'object',
                        'properties': {
                          'request_type': {
                            'type': 'string',
                            'enum': [
                              'hero_booking',
                              'custom_food_order',
                              'grocery_order',
                              'custom_order',
                            ],
                            'description':
                                'hero_booking = errand/help/pickup-drop task. '
                                'custom_food_order = food from a hotel/restaurant. '
                                'grocery_order = groceries/provisions. '
                                'custom_order = anything else the customer wants bought/collected.',
                          },
                          'items': {
                            'type': 'string',
                            'description':
                                'What the customer wants, in their own words, including '
                                'quantities if they said any. e.g. "2 plate chicken biryani", '
                                '"1kg onions, 2 packs milk", "pick up my parcel from Surampatti".',
                          },
                          'vendor': {
                            'type': 'string',
                            'description':
                                'Hotel/shop/store name if the customer named one. Omit if not mentioned — never invent one.',
                          },
                          'address': {
                            'type': 'string',
                            'description':
                                'Delivery or task address if the customer gave one. Omit if not mentioned.',
                          },
                          'note': {
                            'type': 'string',
                            'description': 'Any extra instruction from the customer.',
                          },
                        },
                        'required': ['request_type', 'items'],
                      },
                    },
                  },
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
                              'hero_needs',
                              'profile',
                              'ride_history',
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
                  {
                    'type': 'function',
                    'function': {
                      'name': 'add_to_grocery_cart',
                      'description':
                          "Add an item to the customer's grocery list. Never "
                          'executes a purchase — only notes the item for the '
                          'existing grocery order form.',
                      'parameters': {
                        'type': 'object',
                        'properties': {
                          'item': {
                            'type': 'string',
                            'description': 'The grocery item name, e.g. "milk".',
                          },
                          'quantity': {
                            'type': 'string',
                            'description':
                                'How much/many, in the customer\'s own words, e.g. '
                                '"2 packs" or "1 kg". Omit if not stated.',
                          },
                        },
                        'required': ['item'],
                      },
                    },
                  },
                  {
                    'type': 'function',
                    'function': {
                      'name': 'analyze_screen_with_vision',
                      'description':
                          "Hand off to the Gemini vision agent to read the "
                          "customer's attached photo/screenshot, identify the "
                          "product(s) shown, and add them to the grocery list. "
                          'Only call this when an image is attached to the '
                          'current message. No text arguments — the image itself '
                          'is what gets analyzed.',
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
        'add_to_grocery_cart',
        'analyze_screen_with_vision',
        // NEW (Aug 11 2026): end-to-end order placement — see the tool
        // definition above for why food/grocery/hero-booking are ONE tool.
        'create_service_request',
        // NEW (Aug 11 2026): AI bug reporting.
        'report_app_bug',
      };
      if (function == null || !knownActions.contains(functionName)) {
        return null;
      }

      // check_and_update_app and analyze_screen_with_vision both take no
      // arguments, so Groq may return an empty/absent arguments string
      // for them — that's expected, not a parse failure, unlike the
      // other tools.
      final argumentsRaw = function['arguments'] as String?;
      if (functionName == 'check_and_update_app' || functionName == 'analyze_screen_with_vision') {
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

  // NEW (CTO mandate — Dual-Mode Grocery Cart, Mode 3 "I Need This"):
  // one-shot vision read for the DMart-screen photo-capture flow —
  // reuses the exact same _visionModel this class already uses for
  // screenshot troubleshooting in sendMessage() above, just with a
  // strict-JSON extraction prompt instead of a conversational one.
  // Returns null on any failure (unclear photo, network issue, bad
  // JSON) — the caller (dmart_screen.dart) shows a plain "couldn't
  // read that, please type it instead" message in that case, never a
  // crash or a silently wrong item.
  Future<Map<String, String>?> extractGroceryItemFromImage({
    required Uint8List imageBytes,
    required String apiKeyOverride,
  }) async {
    final apiKey = apiKeyOverride.trim();
    if (apiKey.isEmpty) return null;
    try {
      final response = await _client
          .post(
            _endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(<String, dynamic>{
              'model': _visionModel,
              'messages': <Map<String, dynamic>>[
                {
                  'role': 'user',
                  'content': <Map<String, dynamic>>[
                    {
                      'type': 'text',
                      'text':
                          'This is a photo of a grocery product or shopping app '
                          'screen. Identify the single main product shown and, if '
                          'visible, the quantity/pack size. Respond with ONLY '
                          'strict JSON, no other text: {"item": "<product name, '
                          'empty string if unclear>", "quantity": "<quantity/pack '
                          'size if visible, else empty string>"}.',
                    },
                    {
                      'type': 'image_url',
                      'image_url': {
                        'url': 'data:image/jpeg;base64,${base64Encode(imageBytes)}',
                      },
                    },
                  ],
                },
              ],
              'temperature': 0,
              'max_tokens': 150,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Grocery vision extraction failed: ${response.statusCode} ${response.body}');
        return null;
      }
      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) return null;
      final content = ((choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>?)?['content']
          ?.toString()
          .trim();
      if (content == null || content.isEmpty) return null;
      final cleaned = content.replaceAll(RegExp(r'```json|```'), '').trim();
      final parsed = jsonDecode(cleaned) as Map<String, dynamic>;
      final item = (parsed['item'] as String?)?.trim() ?? '';
      if (item.isEmpty) return null;
      return {
        'item': item,
        'quantity': (parsed['quantity'] as String?)?.trim() ?? '',
      };
    } catch (error) {
      debugPrint('[GuruApiService] extractGroceryItemFromImage error: $error');
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
