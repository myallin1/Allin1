// ================================================================
// AdminQuickTaskService — Admin "Quick Task Chatbox" + CTO Approval
// Gate
// ================================================================
// NEW (CTO mandate — "Admin App Autonomous Agent Support System",
// Task 1: The Admin Confirmation Gate). Mirrors the customer app's
// GuruOverlayService (lib/services/guru_overlay_service.dart)
// architecture exactly — singleton ChangeNotifier holding a single
// root-level OverlayEntry inserted via the shared `navigatorKey`, so
// it floats above every admin screen with zero per-screen wiring and
// survives Navigator.push/pop.
//
// SAFETY MODEL — read before adding a new tool/case here:
//   - `_pendingAdminAction` is the human-in-the-loop gate. A tool call
//     from GuruAdminApiService is NEVER executed immediately. It is
//     stored here, a confirmation message is posted with the AI's
//     report/summary and Yes/No suggestion chips, and only an explicit
//     "yes" from the CTO runs `_executePendingAdminAction`.
//   - Today (Task 1 foundation only) there are two possible actions:
//       navigate_to_admin_section — opens an admin screen. Not a write,
//         but still routed through this same gate for one consistent
//         "AI proposes, CTO confirms" experience across the whole app.
//       propose_write_action — Task 2 (DB audit) and Task 3 (KYC
//         report) will have the AI call this once they exist. Today,
//         confirming it does NOT touch seller/hero/wallet data (those
//         write paths are not built yet) — it only writes an audit-log
//         entry to `admin_ai_actions` recording what the CTO approved,
//         so the exact same confirm-then-log shape is already proven
//         out and ready for Task 2/3 to plug a real write into.
//   - Every write this file performs is to `admin_ai_actions` only
//     (an audit trail), never to `sellers`, `heroes`, `wallets`, or any
//     other operational collection. That boundary is intentional and
//     should stay intentional until Task 2/3 are explicitly built and
//     reviewed.
import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:google_fonts/google_fonts.dart';

import '../app_navigator.dart';
import '../screens/admin/admin_dashboard_screen.dart';
import '../screens/admin/admin_db_usage_screen.dart';
import '../screens/admin/admin_new_orders_screen.dart';
import '../screens/admin/admin_seller_approval_screen.dart';
import '../screens/admin/admin_sos_kyc_approvals_screen.dart';
import '../screens/admin/admin_wallet_approvals_screen.dart';
import '../screens/admin/hero_approvals_screen.dart';
import 'admin_ai_audit_tools.dart';
import 'admin_kyc_vision_service.dart';
import 'admin_kyc_write_service.dart';
import 'gemini_api_service.dart';
import 'guru_admin_api_service.dart';
import 'voice_booking_intent_service.dart';

class AdminChatTurn {
  const AdminChatTurn({required this.role, required this.text, this.suggestions = const []});
  final String role; // 'user' | 'assistant'
  final String text;
  final List<String> suggestions;
}

class AdminQuickTaskService extends ChangeNotifier {
  AdminQuickTaskService._();
  static final AdminQuickTaskService instance = AdminQuickTaskService._();

  final GuruAdminApiService _api = GuruAdminApiService();
  final GeminiApiService _gemini = GeminiApiService();
  final VoiceBookingIntentService _yesNo = VoiceBookingIntentService();

  // NEW (CTO mandate — Multi-Agent Orchestration & Handoff Architecture,
  // Dual Agent Toggle). 'groq' (default) or 'gemini' — controls ONLY
  // which agent answers plain conversational messages (see the branch
  // in sendMessage() below). All 5 admin tools (navigate/propose-write/
  // audit_ui_sections/generate_kyc_report/run_ux_audit) keep running
  // through Groq's extractAgentAction regardless of this toggle — Groq
  // is this app's "Fast Logic" tool-calling agent by the CTO's own
  // framing, so tool-calling parity for Gemini was judged out of scope
  // for this toggle and left for a future mandate if wanted.
  String activeAgent = 'groq';

  void setActiveAgent(String agent) {
    if (agent != 'groq' && agent != 'gemini') return;
    if (activeAgent == agent) return;
    activeAgent = agent;
    notifyListeners();
  }
  // NEW (CTO mandate — Voice & Speech Fix for Quick Task): the CTO's
  // explicit complaint was the Quick Task chatbox "going silent" —
  // this service had zero TTS before now, unlike the customer overlay
  // (GuruOverlayService._speak). Mirrors that exact FlutterTts setup,
  // English-only (no multi-language requirement for the admin side).
  final FlutterTts _tts = FlutterTts();
  bool _autoSpeak = true;
  bool get autoSpeak => _autoSpeak;

  void toggleAutoSpeak() {
    _autoSpeak = !_autoSpeak;
    if (!_autoSpeak) unawaited(_tts.stop());
    notifyListeners();
  }

  Future<void> _speak(String text) async {
    if (!_autoSpeak || text.trim().isEmpty) return;
    try {
      await _tts.setLanguage('en-IN');
      await _tts.stop();
      await _tts.speak(text);
    } catch (e) {
      debugPrint('[AdminQuickTaskService] TTS failed: $e');
    }
  }

  Map<String, dynamic>? _pendingAdminAction;
  // NEW (CTO mandate — Task 3: Automated KYC Report Generator): the
  // most recently generated KYC report, held only long enough for the
  // CTO to tap one of its "Approve <name>" / "Reject <name>" / "Skip"
  // suggestion chips. Deliberately NOT the same thing as
  // _pendingAdminAction — generating and showing a report is a
  // read-only action with no gate needed; only what happens AFTER the
  // CTO reacts to it (an approve/reject decision) becomes a
  // _pendingAdminAction requiring the Yes/No confirmation below.
  KycReportResult? _lastKycReport;
  final List<AdminChatTurn> messages = [];
  OverlayEntry? _entry;
  bool _sending = false;
  bool _minimized = false;

  // FIX (CTO mandate — Admin Quick Task Box stability): this used to be
  // a plain field whose setter called this class's own
  // notifyListeners() (ChangeNotifier) — meaning every single
  // onPanUpdate() pixel of a drag rebuilt the ENTIRE panel (message
  // list + TextField + everything) via the AnimatedBuilder in
  // _AdminQuickTaskPanel/_AdminQuickTaskFab, since they all listen to
  // this same service. That's exactly the kind of "awkward UI rebuild"
  // that can make an on-screen TextField feel unstable while dragging
  // (Flutter usually preserves focus across a same-shape rebuild, but
  // rebuilding the whole subtree every frame during a drag is real,
  // avoidable jank). Position now lives on its own ValueNotifier, with
  // its own listeners — dragging only rebuilds the small Positioned
  // wrapper around the panel (see _AdminQuickTaskPanel below), never
  // the message list or the input TextField.
  final ValueNotifier<Offset> positionNotifier = ValueNotifier<Offset>(const Offset(16, 120));

  bool get isShowing => _entry != null;
  bool get isSending => _sending;
  bool get isMinimized => _minimized;
  Offset get position => positionNotifier.value;
  bool get hasPendingAction => _pendingAdminAction != null;

  void setPosition(Offset offset) {
    positionNotifier.value = offset;
  }

  void toggleMinimized() {
    _minimized = !_minimized;
    notifyListeners();
  }

  void show() {
    if (_entry != null) {
      if (_minimized) {
        _minimized = false;
        notifyListeners();
      }
      return;
    }
    _entry = OverlayEntry(builder: (_) => const _AdminQuickTaskPanel());
    final overlay = navigatorKey.currentState?.overlay;
    if (overlay == null) {
      _entry = null;
      return;
    }
    overlay.insert(_entry!);
    notifyListeners();
  }

  Future<void> requestClose() async {
    final ctx = navigatorKey.currentContext;
    if (ctx == null) {
      _forceClose();
      return;
    }
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (dialogCtx) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(
          'Close Quick Task?',
          style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Are you sure you want to close the Admin AI Co-Pilot?',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: const Text('Close', style: TextStyle(color: Color(0xFFE05555))),
          ),
        ],
      ),
    );
    if (confirmed == true) _forceClose();
  }

  void _forceClose() {
    _entry?.remove();
    _entry = null;
    notifyListeners();
  }

  Future<void> sendMessage(String text) async {
    final trimmed = text.trim();
    if (trimmed.isEmpty || _sending) return;

    messages.add(AdminChatTurn(role: 'user', text: trimmed));
    _sending = true;
    notifyListeners();

    // NEW (CTO mandate — Task 3: Automated KYC Report Generator, "The
    // Connection"): if a KYC report is on screen awaiting a decision,
    // this message IS that decision — checked BEFORE the general
    // pending-action gate below, since these two states are mutually
    // exclusive (a report never coexists with an already-pending
    // action; tapping a decision chip here is what CREATES the pending
    // action). "Skip" needs no confirmation (nothing proposed yet); Approve/
    // Reject convert into a normal propose_write_action pending action,
    // reusing the exact same Yes/No gate + audit-log write path as
    // every other admin action in this file — no new write logic added.
    if (_lastKycReport != null) {
      final report = _lastKycReport!;
      final lower = trimmed.toLowerCase();
      if (lower == 'skip') {
        _lastKycReport = null;
        messages.add(const AdminChatTurn(role: 'assistant', text: 'Okay, skipped — no changes made.'));
        unawaited(_speak('Okay, skipped. No changes made.'));
        _sending = false;
        notifyListeners();
        return;
      }
      if (lower == 'approve ${report.name}'.toLowerCase() ||
          lower == 'reject ${report.name}'.toLowerCase()) {
        final isApprove = lower.startsWith('approve');
        _lastKycReport = null;
        _pendingAdminAction = <String, dynamic>{
          'action': 'propose_write_action',
          'actionType': '${isApprove ? 'approve' : 'reject'}_${report.targetType}_kyc',
          'targetLabel': report.name,
          // NEW (CTO mandate — Final Write Execution, "No Blind
          // Writes"): uid + kycTargetType come straight from the
          // verified Firestore document AdminAiAuditTools just read —
          // never guessed or LLM-invented. _executePendingAdminAction
          // below only performs a REAL write when both of these are
          // present, which is only ever true for actions that
          // originated from this exact KYC-report flow.
          'uid': report.uid,
          'kycTargetType': report.targetType,
          'reportText': report.reportText,
          'summary':
              '${isApprove ? 'Approve' : 'Reject'} KYC for ${report.name} '
              '(${report.targetType}, uid: ${report.uid}) based on the '
              'AI-generated KYC report above.',
        };
        final confirmationText = _confirmationTextFor(_pendingAdminAction!);
        messages.add(AdminChatTurn(
          role: 'assistant',
          text: confirmationText,
          suggestions: const ['Yes, proceed', 'No, cancel'],
        ));
        unawaited(_speak(confirmationText));
        _sending = false;
        notifyListeners();
        return;
      }
      // Anything else -- drop the stale report and fall through to
      // treat this as a brand-new message.
      _lastKycReport = null;
    }

    // Human-in-the-loop gate: if a proposal is awaiting Yes/No, this
    // message IS the CTO's answer — never re-run agent-action
    // extraction on it. Exact same shape as the customer app's
    // guru_chat_screen.dart / guru_overlay_service.dart.
    if (_pendingAdminAction != null) {
      final decision = _yesNo.classifyYesNo(trimmed);
      final pending = _pendingAdminAction!;
      if (decision == VoiceYesNo.yes) {
        _pendingAdminAction = null;
        await _executePendingAdminAction(pending, approved: true);
        _sending = false;
        notifyListeners();
        return;
      } else if (decision == VoiceYesNo.no) {
        _pendingAdminAction = null;
        unawaited(_executePendingAdminAction(pending, approved: false));
        messages.add(const AdminChatTurn(role: 'assistant', text: 'Understood — cancelled, no changes made.'));
        unawaited(_speak('Understood. Cancelled, no changes made.'));
        _sending = false;
        notifyListeners();
        return;
      }
      _pendingAdminAction = null;
    }

    final acted = await _tryAgentActionFromText(trimmed);
    if (acted) {
      _sending = false;
      notifyListeners();
      return;
    }

    final history = messages.map((m) => {'role': m.role, 'content': m.text}).toList(growable: false);
    try {
      // NEW (CTO mandate — Dual Agent Toggle): plain-conversation-only
      // branch. Tool-calling (_tryAgentActionFromText above) already
      // returned early when a tool matched, so reaching here means this
      // is a normal question/reply either way — the only difference is
      // which agent answers it.
      final reply = activeAgent == 'gemini'
          ? await _gemini.sendMessage(
              message: trimmed,
              apiKey: await _api.resolveGeminiApiKey(),
              history: history,
            )
          : await _api.sendMessage(message: trimmed, history: history);
      messages.add(AdminChatTurn(role: 'assistant', text: reply));
      unawaited(_speak(reply));
    } catch (e) {
      const failureText = 'Admin AI is temporarily unavailable. Please try again shortly.';
      messages.add(const AdminChatTurn(role: 'assistant', text: failureText));
      unawaited(_speak(failureText));
    } finally {
      _sending = false;
      notifyListeners();
    }
  }

  Future<bool> _tryAgentActionFromText(String input) async {
    if (input.isEmpty) return false;
    Map<String, dynamic>? args;
    try {
      args = await _api.extractAgentAction(message: input);
    } catch (e) {
      debugPrint('[AdminQuickTaskService] extractAgentAction failed: $e');
    }
    if (args == null) return false;
    final action = args['action'] as String?;

    // NEW (CTO mandate — Full UI Section Audit + Task 3: KYC Report
    // Generator): both are READ-ONLY, so they run immediately — no
    // Yes/No gate needed to look something up, exactly like a customer
    // asking "where is X" doesn't need confirmation either. The gate
    // only guards what happens with the result: see the
    // _lastKycReport handling at the top of sendMessage() above for
    // how an Approve/Reject decision made FROM this report still goes
    // through the full confirmation + audit-log path.
    if (action == 'audit_ui_sections') {
      messages.add(const AdminChatTurn(role: 'assistant', text: 'Running UI section audit...'));
      notifyListeners();
      final report = await AdminAiAuditTools.auditUiSections();
      messages.add(AdminChatTurn(role: 'assistant', text: report));
      unawaited(_speak(report));
      notifyListeners();
      return true;
    }
    // NEW (CTO mandate — Phase 1.5: Admin Tool Wiring). Same read-only
    // shape as audit_ui_sections above — this only reads the
    // ux_audit_reports collection the Synthetic QA Test-Bot
    // (integration_test/qa_five_screens_test.dart) already wrote to; it
    // never triggers a new test run and never writes anything, so it
    // runs immediately with no confirmation gate, same justification as
    // every other read-only tool in this file.
    if (action == 'run_ux_audit') {
      messages.add(const AdminChatTurn(role: 'assistant', text: 'Checking the latest QA test bot findings...'));
      notifyListeners();
      final report = await AdminAiAuditTools.runUxAudit();
      messages.add(AdminChatTurn(role: 'assistant', text: report));
      unawaited(_speak(report));
      notifyListeners();
      return true;
    }
    if (action == 'generate_kyc_report') {
      final type = args['type'] as String?;
      final targetUid = args['targetUid'] as String?;
      messages.add(const AdminChatTurn(role: 'assistant', text: 'Fetching and cross-verifying the submission...'));
      notifyListeners();
      final result = switch (type) {
        'seller' => await AdminAiAuditTools.generateSellerKycReport(targetUid: targetUid),
        'sos' => await AdminAiAuditTools.generateSosKycReport(targetUid: targetUid),
        _ => await AdminAiAuditTools.generateHeroKycReport(targetUid: targetUid),
      };
      if (result == null) {
        final notFoundText = 'No pending ${type ?? 'hero'} KYC submissions found.';
        messages.add(AdminChatTurn(role: 'assistant', text: notFoundText));
        unawaited(_speak(notFoundText));
        notifyListeners();
        return true;
      }
      _lastKycReport = result;

      // NEW (CTO mandate — Advanced KYC & Facial Verification): OCR
      // number-matching + facial comparison, only for hero/sos (the
      // types with Aadhaar/PAN/License doc photos — see
      // KycVisionInputs' comment in admin_ai_audit_tools.dart). Fully
      // additive to the base report above: if this fails or is
      // skipped for any reason, the base report the CTO already sees
      // is untouched and still usable.
      var reportText = result.reportText;
      final visionInputs = result.visionInputs;
      if (visionInputs != null) {
        try {
          final apiKey = await _api.resolveApiKey();
          final vision = await AdminKycVisionService.crossCheck(
            apiKey: apiKey,
            aadhaarNumber: visionInputs.aadhaarNumber,
            aadhaarDocUrl: visionInputs.aadhaarDocUrl,
            panNumber: visionInputs.panNumber,
            panDocUrl: visionInputs.panDocUrl,
            licenseNumber: visionInputs.licenseNumber,
            licenseDocUrl: visionInputs.licenseDocUrl,
            selfieUrl: visionInputs.selfieUrl,
          );
          reportText = '$reportText\n\n--- Vision Cross-Check ---\n'
              '${vision.notes.join('\n')}\n\n${vision.strictRecommendation}';
        } catch (e) {
          debugPrint('[AdminQuickTaskService] vision cross-check failed: $e');
          reportText = '$reportText\n\n--- Vision Cross-Check ---\n'
              'Vision cross-check failed to run ($e) — falling back to manual review.';
        }
      }

      messages.add(AdminChatTurn(
        role: 'assistant',
        text: reportText,
        suggestions: ['Approve ${result.name}', 'Reject ${result.name}', 'Skip'],
      ));
      unawaited(_speak(reportText));
      notifyListeners();
      return true;
    }

    // NEW (CTO mandate — "True Autonomous Agent" / Active Navigation):
    // navigate_to_admin_section is pure navigation — it never writes
    // to Firestore, it just opens a screen (see _actOnNavigateAction
    // below). propose_write_action is the ONLY action in this whole
    // service that can ever touch a real record, and that gate is a
    // hard CTO requirement from an earlier session ("never remove
    // it") — completely unchanged below. Making navigation instant
    // does not weaken that in any way; it just stops routing a
    // harmless screen-open through the same Yes/No round-trip a real
    // write goes through.
    if (action == 'navigate_to_admin_section') {
      await _executePendingAdminAction(args, approved: true);
      return true;
    }

    if (action != 'propose_write_action') {
      return false;
    }

    _pendingAdminAction = args;
    final proposeConfirmText = _confirmationTextFor(args);
    messages.add(
      AdminChatTurn(
        role: 'assistant',
        text: proposeConfirmText,
        suggestions: const ['Yes, proceed', 'No, cancel'],
      ),
    );
    unawaited(_speak(proposeConfirmText));
    notifyListeners();
    return true;
  }

  String _confirmationTextFor(Map<String, dynamic> args) {
    switch (args['action'] as String?) {
      case 'navigate_to_admin_section':
        return "I'm ready to open ${_sectionLabel(args['section'] as String?)} for you — should I proceed?";
      case 'propose_write_action':
        final summary = (args['summary'] as String?)?.trim();
        final target = (args['targetLabel'] as String?)?.trim();
        final base = (summary != null && summary.isNotEmpty)
            ? summary
            : 'Apply this action${target != null && target.isNotEmpty ? ' to $target' : ''}';
        // NEW (CTO mandate — Final Write Execution): only actions that
        // carry a verified `uid` (i.e. came from a real KYC report this
        // service just read, not free-text) will actually write to the
        // real record — see _executePendingAdminAction's "No Blind
        // Writes" check below. Say so honestly here, since what happens
        // after "Yes" genuinely differs between the two cases.
        final hasVerifiedTarget = (args['uid'] as String?)?.trim().isNotEmpty ?? false;
        return '$base\nShould I proceed?'
            '${hasVerifiedTarget ? ' (This will update the real record.)' : ' (No verified document was captured for this — it will only be logged, not applied. Generate a KYC report first so I can target the exact document.)'}';
      default:
        return 'Should I proceed?';
    }
  }

  Future<void> _executePendingAdminAction(Map<String, dynamic> args, {required bool approved}) async {
    switch (args['action'] as String?) {
      case 'navigate_to_admin_section':
        if (approved) _actOnNavigateAction(args);
        break;
      case 'propose_write_action':
        await _executeWriteDecision(args, approved: approved);
        notifyListeners();
        break;
      default:
        break;
    }
  }

  void _actOnNavigateAction(Map<String, dynamic> args) {
    final section = args['section'] as String?;
    final target = _screenForSection(section);
    final navState = navigatorKey.currentState;
    if (target == null || navState == null) return;

    final openingText = 'Opening ${_sectionLabel(section)} now.';
    messages.add(AdminChatTurn(role: 'assistant', text: openingText));
    unawaited(_speak(openingText));
    notifyListeners();
    unawaited(navState.push(MaterialPageRoute<void>(builder: (_) => target)));
  }

  Widget? _screenForSection(String? section) {
    switch (section) {
      case 'dashboard':
        return const AdminDashboardScreen();
      case 'seller_approvals':
        return const AdminSellerApprovalScreen();
      case 'hero_approvals':
        return const HeroApprovalsScreen();
      case 'sos_kyc_approvals':
        return const AdminSosKycApprovalsScreen();
      case 'wallet_approvals':
        return const AdminWalletApprovalsScreen();
      case 'db_usage':
        return const AdminDbUsageScreen();
      case 'new_orders':
        return const AdminNewOrdersScreen();
      default:
        return null;
    }
  }

  String _sectionLabel(String? section) {
    switch (section) {
      case 'dashboard':
        return 'the Admin Dashboard';
      case 'seller_approvals':
        return 'Seller Approvals';
      case 'hero_approvals':
        return 'Hero Approvals';
      case 'sos_kyc_approvals':
        return 'SOS/KYC Approvals';
      case 'wallet_approvals':
        return 'Wallet Approvals';
      case 'db_usage':
        return 'the DB Usage Monitor';
      case 'new_orders':
        return 'New Orders';
      default:
        return 'that section';
    }
  }

  // NEW (CTO mandate — Final Write Execution): decides whether a
  // confirmed propose_write_action gets a REAL Firestore write, then
  // always logs the outcome to admin_ai_actions regardless. This is
  // the ONLY place in the whole Admin AI Co-Pilot feature that calls
  // AdminKycWriteService — i.e. the only place that can ever touch a
  // real heroes/sellers/sos_kyc_requests document.
  //
  // "No Blind Writes" (CTO's own requirement #3): a real write only
  // fires when BOTH `uid` and `kycTargetType` are present on the
  // pending action. Those two fields are only ever set in one place in
  // this file — the KYC-report Approve/Reject chip handling in
  // sendMessage() above — where they come from a document
  // AdminAiAuditTools just actually read via Firestore, never from
  // free-text the CTO typed or the model guessed. If the CTO instead
  // types something like "approve seller X" without going through a
  // generated report first, propose_write_action still fires and still
  // gets a Yes/No confirmation (per the CTO's own requirement #3 that
  // EVERY write action must go through the gate), but no uid was ever
  // resolved for it, so this method deliberately falls back to
  // log-only and says so plainly — refusing to guess which document
  // "X" refers to is the responsible reading of "No Blind Writes", not
  // a way of dodging the mandate.
  Future<void> _executeWriteDecision(Map<String, dynamic> args, {required bool approved}) async {
    final uid = (args['uid'] as String?)?.trim();
    final kycTargetType = (args['kycTargetType'] as String?)?.trim();
    final actionType = (args['actionType'] as String?) ?? '';
    final isApprove = actionType.startsWith('approve');
    final hasVerifiedTarget = uid != null && uid.isNotEmpty && kycTargetType != null && kycTargetType.isNotEmpty;

    AdminKycWriteResult? writeResult;
    if (approved && hasVerifiedTarget) {
      final reason = (args['reportText'] as String?)?.trim().isNotEmpty == true
          ? 'Rejected via Admin AI Co-Pilot after CTO review. Report:\n${args['reportText']}'
          : 'Rejected via Admin AI Co-Pilot after CTO review.';
      switch (kycTargetType) {
        case 'hero':
          writeResult = isApprove
              ? await AdminKycWriteService.approveHero(uid)
              : await AdminKycWriteService.rejectHero(uid, reason);
          break;
        case 'seller':
          writeResult = isApprove
              ? await AdminKycWriteService.approveSeller(uid)
              : await AdminKycWriteService.rejectSeller(uid, reason);
          break;
        case 'sos':
          writeResult = isApprove
              ? await AdminKycWriteService.approveSosKyc(uid)
              : await AdminKycWriteService.rejectSosKyc(uid, reason);
          break;
        default:
          writeResult = null;
      }
    }

    await _logAdminAiAction(
      args,
      approved: approved,
      downstreamWriteExecuted: writeResult?.success ?? false,
      writeError: writeResult?.error,
    );

    final String resultText;
    if (!approved) {
      resultText = 'Logged as declined — no changes made.';
    } else if (!hasVerifiedTarget) {
      resultText = 'Logged as approved. No verified document was captured for this request, so '
          'no real record was changed — generate a KYC report first so I can target the exact document.';
    } else if (writeResult?.success == true) {
      resultText = '✅ Done — the real ${kycTargetType ?? 'record'} document (uid: $uid) has been '
          '${isApprove ? 'approved' : 'rejected'}, and the decision is logged.';
    } else {
      resultText = '❌ The write failed: ${writeResult?.error ?? 'unknown error'}. Nothing was '
          'changed on the real document; the attempt is logged.';
    }
    messages.add(AdminChatTurn(role: 'assistant', text: resultText));
    unawaited(_speak(resultText));
  }

  // NEW (CTO mandate — Task 1 foundation, extended for Final Write
  // Execution): audit-trail write for every propose_write_action
  // decision, real write or not — `downstreamWriteExecuted` now
  // reflects what actually happened instead of always being false.
  Future<void> _logAdminAiAction(
    Map<String, dynamic> args, {
    required bool approved,
    bool downstreamWriteExecuted = false,
    String? writeError,
  }) async {
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('admin_ai_actions').add(<String, dynamic>{
        'actionType': args['actionType'],
        'targetLabel': args['targetLabel'],
        'targetUid': args['uid'],
        'summary': args['summary'],
        'approved': approved,
        'approvedBy': adminUid,
        'executedBy': 'guru_admin_ai',
        'downstreamWriteExecuted': downstreamWriteExecuted,
        if (writeError != null) 'writeError': writeError,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[AdminQuickTaskService] audit log failed: $e');
    }
  }
}

// ================================================================
// Global "Quick Task" trigger FAB — laid over AdminApp's MaterialApp
// `builder:` so it appears on every admin screen with zero per-screen
// wiring, same pattern as the customer app's GlobalGuruFab.
// ================================================================
class AdminQuickTaskFab extends StatelessWidget {
  const AdminQuickTaskFab({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: AdminQuickTaskService.instance,
      builder: (context, _) {
        // FIX (Nizam's report — "2 AI buttons on screen at once"): this
        // used to only hide while the panel was showing AND expanded,
        // so a MINIMIZED panel (isShowing == true, isMinimized == true)
        // left this condition false and the fixed launcher FAB
        // reappeared right alongside the minimized draggable bubble
        // below — two floating AI buttons visible simultaneously.
        // Hiding whenever the panel is showing at all (minimized or
        // not) means there is always exactly one floating AI entry
        // point on screen: this fixed FAB when the panel is fully
        // closed, or the draggable bubble/panel once it's open.
        if (AdminQuickTaskService.instance.isShowing) {
          return const SizedBox.shrink();
        }
        return Positioned(
          right: 14,
          bottom: 90,
          child: SafeArea(
            child: FloatingActionButton(
              heroTag: 'admin_quick_task_fab',
              backgroundColor: const Color(0xFFE05555),
              onPressed: () => AdminQuickTaskService.instance.show(),
              child: const Icon(Icons.support_agent_rounded, color: Colors.white),
            ),
          ),
        );
      },
    );
  }
}

// ================================================================
// The compact, draggable floating panel — text-only (no voice/TTS;
// not asked for on the admin side), report/message list + Yes/No
// suggestion chips.
// ================================================================
class _AdminQuickTaskPanel extends StatefulWidget {
  const _AdminQuickTaskPanel();

  @override
  State<_AdminQuickTaskPanel> createState() => _AdminQuickTaskPanelState();
}

class _AdminQuickTaskPanelState extends State<_AdminQuickTaskPanel> {
  final TextEditingController _controller = TextEditingController();
  final ScrollController _scroll = ScrollController();

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      _scroll.animateTo(
        _scroll.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send([String? preset]) async {
    final text = preset ?? _controller.text;
    if (text.trim().isEmpty) return;
    _controller.clear();
    _scrollToBottom();
    await AdminQuickTaskService.instance.sendMessage(text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final service = AdminQuickTaskService.instance;
    return AnimatedBuilder(
      animation: service,
      builder: (context, _) {
        if (service.isMinimized) {
          // FIX (CTO mandate — Admin Quick Task Box stability): the
          // Positioned's left/top now come from a ValueListenableBuilder
          // scoped to JUST positionNotifier, with the bubble's actual
          // content passed as `child` — dragging rebuilds only this
          // small wrapper, never re-creates the GestureDetector/
          // Container subtree. Also fixes ("the button and the box
          // should both be able to float anywhere"): this bubble
          // already read service.position for placement, but its
          // GestureDetector only had onTap — no onPanUpdate — so unlike
          // the expanded panel below (which drags fine), the minimized
          // bubble could never actually be moved. onPanUpdate now calls
          // the same service.setPosition(...) the expanded panel uses.
          return ValueListenableBuilder<Offset>(
            valueListenable: service.positionNotifier,
            builder: (context, pos, child) => Positioned(left: pos.dx, top: pos.dy, child: child!),
            child: GestureDetector(
              onTap: service.toggleMinimized,
              onPanUpdate: (details) {
                service.setPosition(service.position + details.delta);
              },
              child: SafeArea(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: const Color(0xFFE05555),
                    borderRadius: BorderRadius.circular(28),
                    boxShadow: const [BoxShadow(color: Colors.black45, blurRadius: 10)],
                  ),
                  child: const Icon(Icons.support_agent_rounded, color: Colors.white),
                ),
              ),
            ),
          );
        }
        return ValueListenableBuilder<Offset>(
          valueListenable: service.positionNotifier,
          builder: (context, pos, child) => Positioned(left: pos.dx, top: pos.dy, child: child!),
          child: SafeArea(
            child: GestureDetector(
              onPanUpdate: (details) {
                service.setPosition(service.position + details.delta);
              },
              child: Material(
                color: Colors.transparent,
                child: Container(
                  width: 320,
                  height: 420,
                  decoration: BoxDecoration(
                    color: const Color(0xFF14141F),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x26E05555)),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
                  ),
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1B1B29),
                          borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
                        ),
                        child: Row(
                          children: [
                            const Icon(Icons.support_agent_rounded, color: Color(0xFFE05555), size: 18),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Quick Task — Admin AI Co-Pilot',
                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 13),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            // NEW (CTO mandate — Voice & Speech Fix): lets the
                            // CTO mute/unmute the new TTS without opening
                            // settings — mirrors the customer overlay's
                            // speaker icon.
                            IconButton(
                              icon: Icon(
                                service.autoSpeak ? Icons.volume_up_rounded : Icons.volume_off_rounded,
                                color: Colors.white54,
                                size: 18,
                              ),
                              onPressed: service.toggleAutoSpeak,
                              tooltip: service.autoSpeak ? 'Mute voice' : 'Unmute voice',
                            ),
                            IconButton(
                              icon: const Icon(Icons.remove, color: Colors.white54, size: 18),
                              onPressed: service.toggleMinimized,
                              tooltip: 'Minimize',
                            ),
                            IconButton(
                              icon: const Icon(Icons.close, color: Colors.white54, size: 18),
                              onPressed: service.requestClose,
                              tooltip: 'Close',
                            ),
                          ],
                        ),
                      ),
                      // NEW (CTO mandate — Multi-Agent Orchestration &
                      // Handoff Architecture, Dual Agent Toggle): lets the
                      // CTO switch which agent answers plain conversation
                      // (see AdminQuickTaskService.setActiveAgent — tool
                      // calls like audits/KYC/navigation always stay on
                      // Groq regardless of this toggle, per that method's
                      // own doc comment). A separate row rather than
                      // cramming into the title row above, since the
                      // header is already tight at 320px wide.
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                        decoration: const BoxDecoration(
                          color: Color(0xFF1B1B29),
                          border: Border(bottom: BorderSide(color: Color(0x1AFFFFFF))),
                        ),
                        child: SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              Text(
                                'Agent:',
                                style: GoogleFonts.outfit(color: Colors.white38, fontSize: 10.5),
                              ),
                              const SizedBox(width: 6),
                              _AgentToggleChip(
                                label: 'Groq (Fast Logic)',
                                selected: service.activeAgent == 'groq',
                                onTap: () => service.setActiveAgent('groq'),
                              ),
                              const SizedBox(width: 6),
                              _AgentToggleChip(
                                label: 'Gemini (Deep Reasoning)',
                                selected: service.activeAgent == 'gemini',
                                onTap: () => service.setActiveAgent('gemini'),
                              ),
                            ],
                          ),
                        ),
                      ),
                      Expanded(
                        child: ListView.builder(
                          controller: _scroll,
                          padding: const EdgeInsets.all(10),
                          itemCount: service.messages.length,
                          itemBuilder: (context, i) {
                            final turn = service.messages[i];
                            final isUser = turn.role == 'user';
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Column(
                                crossAxisAlignment: isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                                    constraints: const BoxConstraints(maxWidth: 250),
                                    decoration: BoxDecoration(
                                      color: isUser ? const Color(0xFFE05555) : const Color(0xFF20202E),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      turn.text,
                                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 12.5),
                                    ),
                                  ),
                                  if (turn.suggestions.isNotEmpty)
                                    Padding(
                                      padding: const EdgeInsets.only(top: 6),
                                      child: Wrap(
                                        spacing: 6,
                                        children: turn.suggestions
                                            .map((s) => ActionChip(
                                                  label: Text(s, style: const TextStyle(fontSize: 11)),
                                                  backgroundColor: const Color(0xFF20202E),
                                                  labelStyle: const TextStyle(color: Colors.white),
                                                  onPressed: () => _send(s),
                                                ))
                                            .toList(),
                                      ),
                                    ),
                                ],
                              ),
                            );
                          },
                        ),
                      ),
                      if (service.isSending)
                        const Padding(
                          padding: EdgeInsets.only(bottom: 4),
                          child: SizedBox(
                            height: 14,
                            width: 14,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFE05555)),
                          ),
                        ),
                      Container(
                        padding: const EdgeInsets.all(8),
                        decoration: const BoxDecoration(
                          border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _controller,
                                style: const TextStyle(color: Colors.white, fontSize: 12.5),
                                decoration: const InputDecoration(
                                  hintText: 'Ask for a DB audit, KYC check, or open a screen...',
                                  hintStyle: TextStyle(color: Colors.white38, fontSize: 11.5),
                                  border: InputBorder.none,
                                ),
                                onSubmitted: (_) => _send(),
                              ),
                            ),
                            IconButton(
                              icon: const Icon(Icons.send_rounded, color: Color(0xFFE05555), size: 20),
                              onPressed: () => _send(),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

// NEW (CTO mandate — Multi-Agent Orchestration & Handoff Architecture,
// Dual Agent Toggle): tiny stateless chip used by the header row above.
// Kept as its own widget rather than an inline builder purely for
// readability at the two call sites — no shared state, no behavior
// beyond onTap.
class _AgentToggleChip extends StatelessWidget {
  const _AgentToggleChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: selected ? const Color(0xFFE05555) : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? const Color(0xFFE05555) : Colors.white24),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: selected ? Colors.white : Colors.white54,
            fontSize: 10,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
          ),
        ),
      ),
    );
  }
}
