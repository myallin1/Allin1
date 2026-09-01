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
      'what he should click instead of doing it.';

  static const String _apiKey = String.fromEnvironment(
    'GROQ_API_KEY',
    defaultValue: 'GROQ_API_KEY_HERE',
  );
  static const String _savedApiKeyPrefsKey = 'personal_ai_api_key';
  static final Uri _endpoint =
      Uri.parse('https://api.groq.com/openai/v1/chat/completions');
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

  Future<String> sendMessage({
    required String message,
    List<Map<String, String>> history = const <Map<String, String>>[],
  }) async {
    final input = message.trim();
    if (input.isEmpty) {
      return 'Tell me what you need — DB audit, a KYC check, or which admin screen to open.';
    }

    final apiKey = await _resolveApiKey();
    if (apiKey.isEmpty) {
      return 'Admin AI is not configured yet — add GROQ_API_KEY before this can respond.';
    }

    try {
      final response = await _client
          .post(
            _endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(<String, dynamic>{
              'model': await _resolveModel(),
              'messages': <Map<String, dynamic>>[
                {'role': 'system', 'content': systemPrompt},
                ...history.where(
                  (entry) =>
                      (entry['role'] == 'user' || entry['role'] == 'assistant') &&
                      (entry['content']?.trim().isNotEmpty ?? false),
                ),
                {'role': 'user', 'content': input},
              ],
              'temperature': 0.4,
              'max_tokens': 500,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Admin AI Groq request failed: ${response.statusCode} ${response.body}');
        return _explainFailure(response);
      }

      final body = jsonDecode(response.body) as Map<String, dynamic>;
      final choices = body['choices'] as List<dynamic>? ?? const <dynamic>[];
      if (choices.isEmpty) {
        return 'Admin AI did not receive a proper reply. Please ask once more.';
      }
      final choiceMessage =
          (choices.first as Map<String, dynamic>)['message'] as Map<String, dynamic>? ?? const {};
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

  // NEW (CTO mandate — Task 1 foundation): the "brain" half of the
  // admin agent. Mirrors GuruApiService.extractAgentAction's shape
  // exactly (same tool-calling request pattern), with an admin-only
  // tool set. Every tool here is either a navigate (read-only) or a
  // propose_write_action (never self-executes) — see the safety-model
  // comment at the top of this file. Returns null whenever the model
  // calls no tool or on any failure, so the caller falls back to a
  // normal chat reply.
  Future<Map<String, dynamic>?> extractAgentAction({
    required String message,
  }) async {
    final apiKey = await _resolveApiKey();
    final input = message.trim();
    if (apiKey.isEmpty || input.isEmpty) return null;

    try {
      final response = await _client
          .post(
            _endpoint,
            headers: <String, String>{
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiKey',
            },
            body: jsonEncode(<String, dynamic>{
              'model': await _resolveModel(),
              'messages': <Map<String, String>>[
                {
                  'role': 'system',
                  'content':
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
                      'angle at all, answer normally in text.',
                },
                {'role': 'user', 'content': input},
              ],
              'tools': <Map<String, dynamic>>[
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
              ],
              'tool_choice': 'auto',
              'temperature': 0,
              'max_tokens': 200,
            }),
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('Admin AI agent-action extraction failed: ${response.statusCode} ${response.body}');
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
      if (functionName == 'audit_ui_sections' || functionName == 'run_ux_audit') {
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

  Future<String> _resolveApiKey() async {
    final baked = _apiKey.trim();
    if (baked.isNotEmpty && baked != 'GROQ_API_KEY_HERE' && baked != 'GROQ_API_KEY') {
      return baked;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_savedApiKeyPrefsKey)?.trim() ?? '';
    debugPrint('[GuruAdminApiService] resolved Groq key length: ${stored.length}');
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
    if (baked.isNotEmpty && baked != 'GEMINI_API_KEY_HERE' && baked != 'GEMINI_API_KEY') {
      return baked;
    }
    final prefs = await SharedPreferences.getInstance();
    final stored = prefs.getString(_savedGeminiApiKeyPrefsKey)?.trim() ?? '';
    debugPrint('[GuruAdminApiService] resolved Gemini key length: ${stored.length}');
    return stored;
  }

  static String _explainFailure(http.Response res) {
    String detail = '';
    try {
      final decoded = jsonDecode(res.body);
      if (decoded is Map && decoded['error'] is Map) {
        detail = (decoded['error']['message'] as String?)?.trim() ?? '';
      }
    } catch (_) {}

    switch (res.statusCode) {
      case 401:
        return 'Groq rejected this API key (401). Re-paste it in Admin '
            'AI Configuration.${detail.isEmpty ? '' : '\n\n$detail'}';
      case 402:
        return 'Groq account has insufficient balance (402). Top up '
            'credit at console.groq.com.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
      case 429:
        return 'Groq rate limit hit (429). Wait a moment and retry.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
      default:
        return 'Groq error ${res.statusCode}.'
            '${detail.isEmpty ? '' : '\n\n$detail'}';
    }
  }

  void dispose() {
    _client.close();
  }
}
