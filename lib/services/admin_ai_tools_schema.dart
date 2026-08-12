// ================================================================
// admin_ai_tools_schema.dart — shared tool-calling schema for the
// Admin AI Co-Pilot, used by every provider that supports tool
// calling (Groq, DeepSeek, Gemini).
// ================================================================
// NEW (Aug 12 2026 — Nizam: "quick task open pannuna 3 api um kaatuthu
// but model yepdi switch aagum... apdi set pannuna model than quick
// task la enaku full assistant ah irukanum"): until now only Groq
// (GuruAdminApiService.extractAgentAction) could call the 5 admin
// tools — Gemini and DeepSeek could only hold a plain conversation.
// This file is the SINGLE source of truth for the tool list and the
// tool-calling system prompt, so all three providers stay in sync
// automatically instead of three near-identical copies drifting apart
// over time.
//
// Groq's own inline copy of this same schema in
// guru_admin_api_service.dart is left completely untouched — that
// code is already proven working in production, and touching it here
// would risk regressing it for zero benefit. DeepSeek is OpenAI-
// compatible so it reuses [kAdminOpenAiTools] verbatim. Gemini's
// function-calling shape is different (OpenAPI-style schema with
// UPPERCASE type names, no "type": "function" wrapper), so
// [kAdminGeminiFunctionDeclarations] is a hand-converted mirror of
// the exact same 5 tools — keep both lists in sync if a 6th tool is
// ever added.
//
// SAFETY MODEL — unchanged from the Groq-only version: every tool
// here is either a read-only lookup (audit_ui_sections,
// generate_kyc_report, run_ux_audit), a pure navigation
// (navigate_to_admin_section), or a PROPOSAL that never self-executes
// (propose_write_action) — see admin_quick_task_service.dart's
// _executePendingAdminAction / _executeWriteDecision for the one and
// only place a real write can happen, gated behind the CTO's Yes.
library;

const Set<String> kAdminKnownActions = {
  'navigate_to_admin_section',
  'propose_write_action',
  'audit_ui_sections',
  'generate_kyc_report',
  'run_ux_audit',
};

/// Same wording Groq's extractAgentAction already uses, so switching
/// the active agent never changes how eagerly the Admin AI acts.
const String kAdminToolSystemPrompt =
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

/// OpenAI-compatible `tools` array — identical in shape to Groq's own
/// inline copy in guru_admin_api_service.dart. Used verbatim by
/// DeepSeek (also OpenAI-compatible), so a DeepSeek response can be
/// parsed with the exact same choices[0].message.tool_calls logic
/// Groq already uses.
List<Map<String, dynamic>> kAdminOpenAiTools() => [
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

/// Gemini's function-calling schema — OpenAPI-style, UPPERCASE type
/// names, no "type": "function" / "parameters" wrapper (Gemini calls
/// it "functionDeclarations" + "parameters" directly). Hand-mirrored
/// from [kAdminOpenAiTools] above; keep both in sync if a tool is
/// added or changed.
List<Map<String, dynamic>> kAdminGeminiFunctionDeclarations() => [
      {
        'name': 'navigate_to_admin_section',
        'description': 'Open a specific section of the Allin1 Admin app.',
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            'section': {
              'type': 'STRING',
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
      {
        'name': 'propose_write_action',
        'description':
            'Record a proposed approval/rejection/status-change for the '
            'CTO to confirm. Never executes by itself.',
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            'actionType': {
              'type': 'STRING',
              'description':
                  "What kind of decision this is, e.g. 'approve_seller', "
                  "'reject_seller', 'approve_hero', 'reject_hero', "
                  "'approve_wallet_topup'.",
            },
            'targetLabel': {
              'type': 'STRING',
              'description': 'Human-readable name of who/what this is about.',
            },
            'summary': {
              'type': 'STRING',
              'description': 'One-sentence summary of what would happen.',
            },
          },
          'required': ['actionType', 'targetLabel', 'summary'],
        },
      },
      {
        'name': 'audit_ui_sections',
        'description':
            'Read-only audit comparing what each admin UI screen shows '
            'against the full database, to surface DB leakage/unused '
            'nodes/storage wastage. No arguments.',
        'parameters': {
          'type': 'OBJECT',
          'properties': <String, dynamic>{},
        },
      },
      {
        'name': 'generate_kyc_report',
        'description':
            'Read-only: fetch a pending Hero or Seller registration, '
            'cross-verify their submitted details/photos, and produce a '
            'concise KYC verification report. Never approves/rejects.',
        'parameters': {
          'type': 'OBJECT',
          'properties': {
            'type': {
              'type': 'STRING',
              'enum': ['hero', 'seller', 'sos'],
              'description': 'Which registration type to check.',
            },
            'targetUid': {
              'type': 'STRING',
              'description':
                  'Optional specific uid to check. Omit to check the '
                  'oldest pending submission of that type.',
            },
          },
          'required': ['type'],
        },
      },
      {
        'name': 'run_ux_audit',
        'description':
            'Read-only: fetch a short summary of the Synthetic QA test '
            "bot's most recent findings from the ux_audit_reports "
            'collection (Dashboard, Bike Booking, Grocery, Food, Profile). '
            'Never triggers a new test run and never writes anything.',
        'parameters': {
          'type': 'OBJECT',
          'properties': <String, dynamic>{},
        },
      },
    ];
