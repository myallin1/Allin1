// ================================================================
// GuruAdminApiService — Admin AI Co-Pilot "brain" (Groq client)
// ================================================================
// NEW (CTO mandate — "Admin App Autonomous Agent Support System",
// Step 2 Base Setup): the admin-side twin of guru_api_service.dart.
// Kept as a SEPARATE class/file rather than reusing GuruApiService
// directly, on purpose:
//   - The system prompt is fundamentally different in intent (customer
//     guidance vs. an operator co-pilot with read access across the
//     whole system and the ability to PROPOSE writes).
//   - The tool set is different and will grow independently (DB audit,
//     KYC report generation, seller/hero/wallet approvals) — mixing
//     those function schemas into the customer-facing Groq call would
//     let a customer-side prompt injection attempt reach admin tool
//     names, which is an unnecessary attack surface to introduce.
//   - Keeping them separate means a change to customer tools (e.g. a
//     new booking category) can never accidentally alter what the
//     Admin AI is allowed to call, and vice versa.
//
// SAFETY MODEL (per the CTO's explicit Task 1/2/3 mandate — read this
// before adding a new tool here):
//   - Every tool this service can extract is either:
//       (a) a NAVIGATE tool (opens an admin screen) — no data changes,
//           still routed through the confirmation gate in
//           admin_quick_task_service.dart for UI consistency with the
//           rest of the app, OR
//       (b) a PROPOSE tool (requests a write/approval) — NEVER executes
//           a real database write itself. It only returns a structured
//           proposal (action type + target + a human-readable summary)
//           for admin_quick_task_service.dart to show the CTO and wait
//           for an explicit Yes.
//   - This file has ZERO Firestore write calls in it, deliberately. It
//     only ever reads (via whatever read-only helper is added for the
//     DB audit / KYC tasks) or talks to Groq. All writes, when Task 2/3
//     are implemented, live in admin_quick_task_service.dart's
//     _executePendingAdminAction, gated behind the CTO's Yes.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'chitti/chitti_local_answer_service.dart';
import 'chitti/chitti_model_provider.dart';
import 'guru_api_service.dart';

class GuruAdminApiService {
  GuruAdminApiService({http.Client? client, Duration? timeout})
      : _client = client ?? http.Client(),
        _timeout = timeout ?? const Duration(seconds: 18);

  // CTO mandate — exact three goals baked into the system prompt:
  //   1. DB Leakage & Wastage Audit — broad READ access, reports only.
  //   2. Automated KYC & Verification — reads Hero/Seller submissions,
  //      cross-verifies, produces a report.
  //   3. Strict Approval Gate — no write/approve action executes without
  //      the CTO's explicit Yes/No in the Quick Task Chatbox.
  static const String systemPrompt =
      'You are the Allin1 Admin AI Co-Pilot, an autonomous support agent '
      'for the CTO of Allin1 (Erode, Tamil Nadu super-app, run by NJ '
      'Tech). You assist with three responsibilities:\n'
      '1. DATABASE AUDIT — you may read across the entire Firestore/'
      'Realtime Database structure to look for leakage (data readable '
      'that should not be), unused/orphaned nodes, and storage wastage '
      '(duplicated, stale, or oversized data). You report findings '
      'clearly; you never delete or modify anything yourself.\n'
      '2. KYC VERIFICATION — when a new Hero or Seller registers, you '
      'fetch their submitted details and photos, cross-check them for '
      'consistency (e.g. name/photo/address plausibility, missing '
      'fields, mismatched documents), and produce a concise verification '
      'report with a clear recommendation (approve / reject / needs more '
      'info) and your reasoning.\n'
      '3. ADMIN ACTIONS — you may navigate the admin app to the relevant '
      'screen for whatever the CTO is working on. For anything that '
      'writes to the database or changes an approval status, you NEVER '
      'execute it yourself. You always present your report or proposal '
      'and explicitly ask the CTO "Should I proceed? (Yes/No)" and wait '
      'for their answer before anything is written. This is a hard '
      'safety rule, not a suggestion — you have broad freedom to read '
      'and analyze, but zero authority to write without explicit human '
      'sign-off from the CTO.\n'
      'Be precise, concise, and professional — you are speaking to the '
      'CTO, not a customer. Do not pad reports with filler. When '
      'presenting a report before asking for approval, use short, '
      'clearly-labeled lines (e.g. "Finding: ...", "Risk: ...", '
      '"Recommendation: ...") rather than long paragraphs.\n'
      // NEW (per Nizam's explicit request): when the CTO gives a spoken
      // command that a navigation tool can already fulfil, call that
      // tool immediately in the SAME turn and reply with ONE short line
      // (e.g. "Opening KYC Approvals now."). Never explain steps he
      // could take manually instead of just doing it. Save the
      // "Finding/Risk/Recommendation" longer format strictly for DB
      // audit or KYC verification reports, where it is genuinely
      // needed.
      'If a request clearly matches a navigation tool, call it '
      'immediately and reply in one short sentence — do not describe '
      'what he should click instead of doing it.\n'
      // NEW (Sep 4 2026 — persona audit). GuruApiService's 'admin'
      // persona override was upgraded to a chief-of-staff brief in the
      // same change; the comment above that override has said since it
      // was written that "the two can never disagree about what admin
      // Chitti is for". This block is the matching half, kept short on
      // purpose — the three numbered responsibilities and the hard
      // approval gate above are untouched and still carry the safety
      // model, and nothing here relaxes any of them.
      'WHO YOU ARE WORKING FOR. Nizam owns MyAllin1 and runs the whole '
      'business alone — no ops team, no support desk, no second admin. '
      'Every approval, complaint and rupee passes through his one '
      'phone, so your job is to protect his attention.\n'
      'LEAD WITH WHAT IS WRONG — pending approvals, stranded orders, '
      'unanswered enquiries, unresolved bugs — and put the worst item '
      'in the first line. If nothing is pending, say so in one line '
      'and stop; never manufacture a report to look useful.\n'
      'NAME THE NEXT ACTION. Do not stop at the number: end with the '
      'one concrete thing to do next and offer to do it.\n'
      'FOLLOW UP. If earlier in this conversation he said he would '
      'call someone back, check a payment, or decide on an approval '
      'and never returned to it, raise it once, briefly. Only ever '
      'follow up on something actually said in this conversation — '
      'never on a commitment you assume he made.\n'
      'NEVER STATE A COUNT, AMOUNT, STATUS, NAME OR ID THAT DID NOT '
      'COME BACK FROM A TOOL. If a read fails, say plainly that you '
      'could not read it and name the admin screen that holds it. He '
      'is alone; there is nobody downstream to catch a confident wrong '
      'number before he acts on it.\n'
      'ANSWER IN WHATEVER LANGUAGE HE USED, including Tanglish, in '
      'natural spoken Erode Tamil rather than formal bookish Tamil. '
      'Keep numbers, money, IDs, screen names and status words exactly '
      'as the app shows them, in English, even mid-Tamil sentence.\n'
      'Straight and unsentimental. No motivation, no cheerleading, no '
      'praise for asking.';

  static const String _apiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: 'GROQ_API_KEY_HERE',
  );
  static const String _savedApiKeyPrefsKey = 'personal_ai_api_key';
  static const String _textModel = 'llama-3.3-70b-versatile';

  // NEW (Aug 12 2026 — Nizam: "api key podumbothu athuku keelaye
  // model select pannalam"): admin_ai_settings_screen.dart now saves
  // whichever model the CTO picked from the hardcoded Groq list under
  // this key. Falls back to the original hardcoded _textModel when
  // nothing has been picked yet, so a fresh install behaves exactly
  // as before this feature existed.
  static const String _modelPrefsKey = 'personal_groq_model';

  Future<String> _resolveModel() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_modelPrefsKey)?.trim();
    return (saved == null || saved.isEmpty) ? _textModel : saved;
  }

  // NEW (CTO mandate — Multi-Agent Orchestration & Handoff Architecture,
  // Dual Agent Toggle): the "Gemini (Deep Reasoning)" agent's key,
  // resolved the exact same way as _apiKey above (env var first, then
  // SharedPreferences). The actual Gemini HTTP calls live in the
  // sibling file gemini_api_service.dart (GeminiApiService) — kept
  // separate so this file doesn't grow a second provider's request/
  // response plumbing, mirroring how AdminKycVisionService already
  // resolves ITS Groq key via this class's resolveApiKey() wrapper
  // rather than duplicating the resolution logic.
  static const String _geminiApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: 'GEMINI_API_KEY_HERE',
  );
  static const String _savedGeminiApiKeyPrefsKey = 'personal_gemini_api_key';

  final http.Client _client;
  final Duration _timeout;

  // AUDIT FIX (Sep 2026 — CTO architectural review of PR #61): this used
  // to hardcode Groq — the ONLY key it ever looked at was
  // personal_ai_api_key, so an admin who had configured Claude or
  // DeepSeek but never Groq got "add GROQ_API_KEY" back on every single
  // message, regardless of what was actually available. Now resolves
  // through GuruApiService().resolveBackendDirect(), the same
  // fallback-degradation logic the customer app already trusts (see
  // resolveChittiModel's header in chitti_model_provider.dart): it tries
  // whatever the admin last picked, and if that has no key, degrades to
  // any OTHER configured provider rather than failing outright.
  Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const <Map<String, String>>[],
  }) async {
    final input = message.trim();
    if (input.isEmpty) {
      return 'Tell me what you need — DB audit, a KYC check, or which admin screen to open.';
    }

    final backend = await GuruApiService().resolveBackendDirect();
    if (backend == null) {
      // NOT a hard failure: no key configured (or genuinely offline)
      // must not read as broken. ChittiLocalAnswerService's FAQ set is
      // customer-facing, so this only ever fires for a generic
      // question that happens to match one — it is not a substitute
      // admin brain and is not claimed to be one. When it has nothing,
      // say plainly that no AI is configured rather than naming one
      // specific provider's key as if the other three didn't exist.
      final local = ChittiLocalAnswerService.answer(input);
      if (local != null) return local.text;
      return 'Admin AI is not configured yet — add a Groq, Gemini, '
          'DeepSeek or Claude key in AI Settings before this can respond.';
    }

    final model = backend.model;
    final isAnthropic = model.id == 'anthropic';
    final headers = chittiRequestHeaders(model: model, apiKey: backend.key);
    final textModel = await _chosenModelFor(model);

    final Map<String, dynamic> requestPayload = isAnthropic
        ? <String, dynamic>{
            'model': textModel,
            'system': systemPrompt,
            'messages': _anthropicMessages(history, input),
            'max_tokens': 500,
          }
        : <String, dynamic>{
            'model': textModel,
            'messages': <Map<String, dynamic>>[
              {'role': 'system', 'content': systemPrompt},
              ..._openAiHistory(history),
              {'role': 'user', 'content': input},
            ],
            'temperature': 0.4,
            'max_tokens': 500,
          };

    try {
      final response = await _client
          .post(
            Uri.parse(model.endpoint),
            headers: headers,
            body: jsonEncode(requestPayload),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Admin AI request failed (${model.id}): '
            '${response.statusCode} ${response.body}');
        return _explainFailure(response, model);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      if (isAnthropic) {
        final contents = body['content'] as List<dynamic>? ?? const <dynamic>[];
        final text = contents
            .where((c) => (c as Map<String, dynamic>)['type'] == 'text')
            .map((c) =>
                (c as Map<String, dynamic>)['text']?.toString().trim() ?? '')
            .where((t) => t.isNotEmpty)
            .join('\n');
        return text.isEmpty
            ? 'Admin AI is thinking, but the reply came back empty. Please try again.'
            : text;
      }

      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) {
        return 'Admin AI did not receive a proper reply. Please ask once more.';
      }
      final choiceMessage = (choices.first as Map<String, dynamic>)['message']
              as Map<String, dynamic>? ??
          const {};
      final content = choiceMessage['content']?.toString().trim() ?? '';
      return content.isEmpty
          ? 'Admin AI is thinking, but the reply came back empty. Please try again.'
          : content;
    } on TimeoutException {
      return 'Admin AI took too long to respond. Please try again.';
    } catch (error) {
      debugPrint('Admin AI error: $error');
      return 'Admin AI is temporarily unavailable. I will be back shortly.';
    }
  }

  /// Shapes conversation history for an OpenAI-compatible body (Groq,
  /// Gemini's compat endpoint, DeepSeek) — extracted so sendMessage and
  /// extractAgentAction never disagree on what counts as valid history.
  List<Map<String, dynamic>> _openAiHistory(
          List<Map<String, String>> history) =>
      history
          .where((entry) =>
              (entry['role'] == 'user' || entry['role'] == 'assistant') &&
              (entry['content']?.trim().isNotEmpty ?? false))
          .toList();

  /// Same shaping for Anthropic's messages array, which has no system
  /// role inline (system is a top-level field) and needs the trailing
  /// user turn appended separately.
  List<Map<String, dynamic>> _anthropicMessages(
    List<Map<String, String>> history,
    String input,
  ) {
    final messages = <Map<String, dynamic>>[];
    for (final entry in history) {
      final role = entry['role'];
      final content = entry['content']?.trim() ?? '';
      if ((role == 'user' || role == 'assistant') && content.isNotEmpty) {
        messages.add({'role': role, 'content': content});
      }
    }
    messages.add({'role': 'user', 'content': input});
    return messages;
  }

  /// Which model id to actually send for [model]: the admin's saved
  /// per-provider choice (chitti_model_provider.dart's own
  /// modelPrefsKeyName — the exact mechanism admin_ai_settings_screen.
  /// dart already writes to for every provider, not just Groq) if one
  /// was ever saved, else that model's own default.
  Future<String> _chosenModelFor(ChittiModel model) async {
    final key = model.modelPrefsKeyName;
    if (key == null) return model.textModel;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(key)?.trim() ?? '';
    return saved.isEmpty ? model.textModel : saved;
  }

  /// The five admin tools, defined once in OpenAI/Groq function-call
  /// shape (used as-is by Groq/Gemini's compat endpoint/DeepSeek) and
  /// mechanically converted to Anthropic's {name, description,
  /// input_schema} shape by _anthropicAdminTools below -- one
  /// definition, so a tool added here reaches every provider.
  static final List<Map<String, dynamic>> _adminToolsOpenAi =
      <Map<String, dynamic>>[
    {
      'type': 'function',
      'function': {
        'name': 'navigate_to_admin_section',
        'description': 'Open a specific section of the Allin1 Admin app.',
        'parameters': {
          'type': 'object',
          'properties': {
            'section': {
              'type': 'string',
              'enum': [
                'dashboard',
                'seller_approvals',
                'hero_approvals',
                'sos_kyc_approvals',
                'wallet_approvals',
                'db_usage',
                'new_orders',
              ],
              'description': 'Which admin section to open.',
            },
          },
          'required': ['section'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'propose_write_action',
        'description':
            'Record a proposed approval/rejection/status-change for the '
                'CTO to confirm. Never executes by itself.',
        'parameters': {
          'type': 'object',
          'properties': {
            'actionType': {
              'type': 'string',
              'description':
                  "What kind of decision this is, e.g. 'approve_seller', "
                      "'reject_seller', 'approve_hero', 'reject_hero', "
                      "'approve_wallet_topup'.",
            },
            'targetLabel': {
              'type': 'string',
              'description': 'Human-readable name of who/what this is about.',
            },
            'summary': {
              'type': 'string',
              'description': 'One-sentence summary of what would happen.',
            },
          },
          'required': ['actionType', 'targetLabel', 'summary'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'audit_ui_sections',
        'description':
            'Read-only audit comparing what each admin UI screen shows '
                'against the full database, to surface DB leakage/unused '
                'nodes/storage wastage. No arguments.',
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
        'name': 'generate_kyc_report',
        'description':
            'Read-only: fetch a pending Hero or Seller registration, '
                'cross-verify their submitted details/photos, and produce a '
                'concise KYC verification report. Never approves/rejects.',
        'parameters': {
          'type': 'object',
          'properties': {
            'type': {
              'type': 'string',
              'enum': ['hero', 'seller', 'sos'],
              'description': 'Which registration type to check.',
            },
            'targetUid': {
              'type': 'string',
              'description':
                  'Optional specific uid to check. Omit to check the '
                      'oldest pending submission of that type.',
            },
          },
          'required': ['type'],
        },
      },
    },
    {
      'type': 'function',
      'function': {
        'name': 'run_ux_audit',
        'description':
            'Read-only: fetch a short summary of the Synthetic QA test '
                "bot's most recent findings from the ux_audit_reports "
                'collection (Dashboard, Bike Booking, Grocery, Food, Profile). '
                'Never triggers a new test run and never writes anything.',
        'parameters': {
          'type': 'object',
          'properties': <String, dynamic>{},
          'required': <String>[],
        },
      },
    },
  ];

  /// Mechanical conversion: OpenAI's {type:'function', function:{name,
  /// description, parameters}} -> Anthropic's {name, description,
  /// input_schema}. Both shapes carry the exact same JSON Schema for
  /// parameters/input_schema, so this is a rename, not a rewrite.
  static List<Map<String, dynamic>> _anthropicAdminTools() =>
      _adminToolsOpenAi.map((tool) {
        final fn = tool['function'] as Map<String, dynamic>;
        return <String, dynamic>{
          'name': fn['name'],
          'description': fn['description'],
          'input_schema': fn['parameters'],
        };
      }).toList();

  /// System prompt for extractAgentAction's tool-calling turn, shared
  /// verbatim by both the OpenAI-shape branch (Groq/Gemini/DeepSeek) and
  /// _extractAgentActionAnthropic below -- the whole point of a agent
  /// working the same way regardless of provider is that it is told the
  /// same thing regardless of provider.
  static const String _agentActionSystemPrompt =
      'You are the CTO\'s admin co-pilot. Your default behavior is to '
      'ACT by calling one of your five tools, not to reply with '
      'step-by-step instructions telling the CTO what to click '
      'themselves — if a request matches a tool even loosely, call '
      'the tool. Only fall back to a plain-text reply when NONE of '
      'the five tools fit, or when the request is genuinely '
      'ambiguous (see below). You have five tools. Call '
      'navigate_to_admin_section when the CTO wants to open, see, '
      'view, or check a specific admin screen (e.g. "show me '
      'pending seller approvals", "open the DB usage monitor", '
      '"take me to hero approvals", "any new orders?"). Call '
      'propose_write_action whenever the CTO is asking you to '
      'approve, reject, confirm, or change the status of something '
      '— including short/casual phrasing like "approve karthik", '
      '"reject that seller", "yes approve him", "clear the pending '
      'hero" — this tool NEVER executes anything by itself, it only '
      'records what they are asking for so it can be confirmed with '
      'a Yes/No; when in doubt about whether something counts as an '
      'approval/rejection request, prefer calling this tool over '
      'replying in plain text, since the confirmation step is the '
      'real safety net, not your judgment call here. Call '
      'audit_ui_sections when the CTO asks for a database/UI '
      'leakage, unused-node, or storage-wastage audit (e.g. "audit '
      'the database", "check for DB leakage", "is any data hidden '
      'from the UI?") — this tool is read-only and safe to run '
      'immediately. Call generate_kyc_report when the CTO asks for '
      'or about a Hero or Seller KYC/verification report, or wants '
      'a pending registration checked (e.g. "generate a KYC report '
      'for the next pending hero", "check this seller\'s documents", '
      '"is karthik\'s KYC ok?") — this tool is also read-only and '
      'safe to run immediately; it never approves or rejects '
      'anything by itself. Call run_ux_audit when the CTO asks '
      'about the Synthetic QA test bot\'s findings (e.g. "any UX '
      'bugs found?", "show me the latest QA audit results", "how '
      'did the last test run go?") — this tool is read-only and '
      'safe to run immediately; it only reads the ux_audit_reports '
      'collection the test bot already wrote, it never runs the '
      'test bot itself and never writes anything. The ONE case '
      'where you should NOT call a tool and should instead reply '
      'in plain text: the request is action-shaped but you cannot '
      'tell WHICH target it means (e.g. "approve the seller" when '
      'there could be more than one pending, with no name/id '
      'given) — in that case, do not guess a target and do not '
      'call propose_write_action with a made-up targetLabel; '
      'instead ask ONE short clarifying question in plain text '
      '(e.g. "Which seller — there are a few pending. Can you give '
      'a name?") and wait for their reply. For genuine general '
      'questions with no admin-section, approval, audit, or KYC '
      'angle at all, answer normally in text.';

  // NEW (CTO mandate — Task 1 foundation): the "brain" half of the
  // admin agent. Mirrors GuruApiService.extractAgentAction's shape
  // exactly (same tool-calling request pattern), with an admin-only
  // tool set. Every tool here is either a navigate (read-only) or a
  // propose_write_action (never self-executes) — see the safety-model
  // comment at the top of this file. Returns null whenever the model
  // calls no tool or on any failure, so the caller falls back to a
  // normal chat reply.
  // AUDIT FIX (Sep 2026): same root cause as sendMessage above — a
  // Groq-only key check meant an admin with only Claude/DeepSeek/Gemini
  // configured could open admin screens and audit tools by chat, this
  // silently returned null on every single request, and the caller
  // fell back to plain-text replies only (no navigate/propose/audit
  // ever fired). Anthropic needs its own branch here because its tool-
  // calling wire format is entirely different from the OpenAI-style
  // 'tools'/'function' shape Groq, Gemini's compat endpoint, and
  // DeepSeek all share — see _anthropicAdminTools and
  // _extractAnthropicToolCall below.
  Future<Map<String, dynamic>?> extractAgentAction({
    required String message,
  }) async {
    final backend = await GuruApiService().resolveBackendDirect();
    final input = message.trim();
    if (backend == null || input.isEmpty) return null;

    final model = backend.model;
    final isAnthropic = model.id == 'anthropic';
    if (isAnthropic) {
      return _extractAgentActionAnthropic(
          model: model, apiKey: backend.key, input: input);
    }

    final apiKey = backend.key;
    try {
      final response = await _client
          .post(
            Uri.parse(model.endpoint),
            headers: chittiRequestHeaders(model: model, apiKey: apiKey),
            body: jsonEncode(<String, dynamic>{
              'model': await _chosenModelFor(model),
              'messages': <Map<String, String>>[
                {'role': 'system', 'content': _agentActionSystemPrompt},
                {'role': 'user', 'content': input},
              ],
              'tools': _adminToolsOpenAi,
              'tool_choice': 'auto',
              'temperature': 0,
              'max_tokens': 200,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'Admin AI agent-action extraction failed: ${response.statusCode} ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) return null;

      final choiceMessage = (choices.first as Map<String, dynamic>)['message']
          as Map<String, dynamic>?;
      final toolCalls = choiceMessage?['tool_calls'] as List<dynamic>?;
      if (toolCalls == null || toolCalls.isEmpty) return null;

      final function = (toolCalls.first as Map<String, dynamic>)['function']
          as Map<String, dynamic>?;
      final functionName = function?['name'] as String?;
      const knownActions = {
        'navigate_to_admin_section',
        'propose_write_action',
        'audit_ui_sections',
        'generate_kyc_report',
        'run_ux_audit',
      };
      if (function == null || !knownActions.contains(functionName)) return null;

      // audit_ui_sections and run_ux_audit both take no arguments, so
      // Groq may return an empty/absent arguments string for them —
      // expected, not a parse failure, same as check_and_update_app on
      // the customer side.
      final argumentsRaw = function['arguments'] as String?;
      if (functionName == 'audit_ui_sections' ||
          functionName == 'run_ux_audit') {
        return {'action': functionName};
      }
      if (argumentsRaw == null || argumentsRaw.trim().isEmpty) return null;
      final args = jsonDecode(argumentsRaw) as Map<String, dynamic>;
      return {'action': functionName, ...args};
    } catch (error) {
      debugPrint('[GuruAdminApiService] extractAgentAction error: $error');
      return null;
    }
  }

  /// Anthropic's tool-calling wire format, start to finish: tools are
  /// {name, description, input_schema} at the top level (not nested
  /// under a 'function' key), and a call comes back as a content block
  /// of type 'tool_use' with 'input' already decoded (a real object,
  /// never a JSON string to re-parse the way OpenAI's 'arguments' is).
  Future<Map<String, dynamic>?> _extractAgentActionAnthropic({
    required ChittiModel model,
    required String apiKey,
    required String input,
  }) async {
    try {
      final response = await _client
          .post(
            Uri.parse(model.endpoint),
            headers: chittiRequestHeaders(model: model, apiKey: apiKey),
            body: jsonEncode(<String, dynamic>{
              'model': await _chosenModelFor(model),
              'system': _agentActionSystemPrompt,
              'messages': <Map<String, dynamic>>[
                {'role': 'user', 'content': input},
              ],
              'tools': _anthropicAdminTools(),
              'max_tokens': 200,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Admin AI agent-action extraction failed (anthropic): '
            '${response.statusCode} ${response.body}');
        return null;
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final contents = body['content'] as List<dynamic>? ?? const <dynamic>[];
      final toolUse = contents.cast<Map<String, dynamic>>().firstWhere(
            (c) => c['type'] == 'tool_use',
            orElse: () => const <String, dynamic>{},
          );
      if (toolUse.isEmpty) return null;

      final functionName = toolUse['name'] as String?;
      const knownActions = {
        'navigate_to_admin_section',
        'propose_write_action',
        'audit_ui_sections',
        'generate_kyc_report',
        'run_ux_audit',
      };
      if (!knownActions.contains(functionName)) return null;

      final args = toolUse['input'] as Map<String, dynamic>? ??
          const <String, dynamic>{};
      return {'action': functionName, ...args};
    } catch (error) {
      debugPrint(
          '[GuruAdminApiService] extractAgentAction (anthropic) error: $error');
      return null;
    }
  }

  Future<String> _resolveApiKey() async {
    final baked = _apiKey.trim();
    if (baked.isNotEmpty &&
        baked != 'GROQ_API_KEY_HERE' &&
        baked != 'GROQ_API_KEY') {
      return baked;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_savedApiKeyPrefsKey)?.trim() ?? '';
    debugPrint(
        '[GuruAdminApiService] resolved Groq key length: ${stored.length}');
    return stored;
  }

  // NEW (CTO mandate — Advanced KYC & Facial Verification): public
  // wrapper so admin_quick_task_service.dart can resolve the exact same
  // key AdminKycVisionService needs for its own direct Groq calls,
  // without duplicating the resolution logic above in a second place.
  Future<String> resolveApiKey() => _resolveApiKey();

  /// Public wrapper mirroring resolveApiKey() above, so
  /// admin_ai_settings_screen.dart can show the currently-active model
  /// as the dropdown's initial value.
  Future<String> resolveModel() => _resolveModel();

  // NEW (CTO mandate — Dual Agent Toggle): same public-wrapper pattern
  // as resolveApiKey() above, for admin_quick_task_service.dart to pass
  // into GeminiApiService when the CTO has switched the active agent to
  // Gemini.
  Future<String> resolveGeminiApiKey() async {
    final baked = _geminiApiKey.trim();
    if (baked.isNotEmpty &&
        baked != 'GEMINI_API_KEY_HERE' &&
        baked != 'GEMINI_API_KEY') {
      return baked;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_savedGeminiApiKeyPrefsKey)?.trim() ?? '';
    debugPrint(
        '[GuruAdminApiService] resolved Gemini key length: ${stored.length}');
    return stored;
  }

  // AUDIT FIX (Sep 2026): took an http.Response only, so every message
  // said "Groq" no matter which provider actually rejected the
  // request — actively misleading once Gemini/DeepSeek/Claude were
  // reachable through the same call site. Now takes the model that was
  // actually used and names it.
  static String _explainFailure(http.Response res, ChittiModel model) {
    String detail = '';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error']['message'] as String?)?.trim() ?? '';
      }
    } catch (_) {}

    final provider = model.label.split(' ').first;
    switch (res.statusCode) {
      case 401:
        return '$provider rejected this API key (401). Re-paste it in '
            'AI Settings.${detail.isEmpty ? '' : '\n\n$detail'}';
      case 402:
        return '$provider account has insufficient balance (402). Top '
            'up credit with that provider.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
      case 429:
        return '$provider rate limit hit (429). Wait a moment and retry.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
      default:
        return '$provider error ${res.statusCode}.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
    }
  }

  void dispose() {
    _client.close();
  }
}
