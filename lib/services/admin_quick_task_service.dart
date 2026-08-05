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
  final VoiceBookingIntentService _yesNo = VoiceBookingIntentService();

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
  Offset _position = const Offset(16, 120);

  bool get isShowing => _entry != null;
  bool get isSending => _sending;
  bool get isMinimized => _minimized;
  Offset get position => _position;
  bool get hasPendingAction => _pendingAdminAction != null;

  void setPosition(Offset offset) {
    _position = offset;
    notifyListeners();
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
          'summary':
              '${isApprove ? 'Approve' : 'Reject'} KYC for ${report.name} '
              '(${report.targetType}, uid: ${report.uid}) based on the '
              'AI-generated KYC report above.',
        };
        messages.add(AdminChatTurn(
          role: 'assistant',
          text: _confirmationTextFor(_pendingAdminAction!),
          suggestions: const ['Yes, proceed', 'No, cancel'],
        ));
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
      final reply = await _api.sendMessage(message: trimmed, history: history);
      messages.add(AdminChatTurn(role: 'assistant', text: reply));
    } catch (e) {
      messages.add(const AdminChatTurn(
        role: 'assistant',
        text: 'Admin AI is temporarily unavailable. Please try again shortly.',
      ));
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
      notifyListeners();
      return true;
    }
    if (action == 'generate_kyc_report') {
      final type = args['type'] as String?;
      final targetUid = args['targetUid'] as String?;
      messages.add(const AdminChatTurn(role: 'assistant', text: 'Fetching and cross-verifying the submission...'));
      notifyListeners();
      final result = type == 'seller'
          ? await AdminAiAuditTools.generateSellerKycReport(targetUid: targetUid)
          : await AdminAiAuditTools.generateHeroKycReport(targetUid: targetUid);
      if (result == null) {
        messages.add(AdminChatTurn(
          role: 'assistant',
          text: 'No pending ${type == 'seller' ? 'seller' : 'hero'} KYC submissions found.',
        ));
        notifyListeners();
        return true;
      }
      _lastKycReport = result;
      messages.add(AdminChatTurn(
        role: 'assistant',
        text: result.reportText,
        suggestions: ['Approve ${result.name}', 'Reject ${result.name}', 'Skip'],
      ));
      notifyListeners();
      return true;
    }

    if (action != 'navigate_to_admin_section' && action != 'propose_write_action') {
      return false;
    }

    _pendingAdminAction = args;
    messages.add(
      AdminChatTurn(
        role: 'assistant',
        text: _confirmationTextFor(args),
        suggestions: const ['Yes, proceed', 'No, cancel'],
      ),
    );
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
        return '$base\nShould I proceed? (This will only be logged — no seller/hero/wallet '
            'record is modified until that write path is built and wired in.)';
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
        await _logAdminAiAction(args, approved: approved);
        messages.add(
          AdminChatTurn(
            role: 'assistant',
            text: approved
                ? "Logged as approved. Note: this foundation only records your decision "
                    "in the admin_ai_actions audit trail — the actual seller/hero/wallet "
                    "write path is not wired yet (that's Task 2/3)."
                : 'Logged as declined — no changes made.',
          ),
        );
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

    messages.add(AdminChatTurn(role: 'assistant', text: 'Opening ${_sectionLabel(section)} now.'));
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

  // NEW (CTO mandate — Task 1 foundation): the ONLY write this whole
  // service performs. Writes an audit record of what the CTO
  // approved/declined via the chatbox — never touches operational data.
  // This is exactly the audit-log shape Task 2 (DB audit) and Task 3
  // (KYC report) should reuse once their real write handlers exist.
  Future<void> _logAdminAiAction(Map<String, dynamic> args, {required bool approved}) async {
    try {
      final adminUid = FirebaseAuth.instance.currentUser?.uid;
      await FirebaseFirestore.instance.collection('admin_ai_actions').add(<String, dynamic>{
        'actionType': args['actionType'],
        'targetLabel': args['targetLabel'],
        'summary': args['summary'],
        'approved': approved,
        'approvedBy': adminUid,
        'executedBy': 'guru_admin_ai',
        // Task 2/3 will set this true once a real downstream write is
        // wired in for the given actionType; false here is honest about
        // today's foundation-only state.
        'downstreamWriteExecuted': false,
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
        if (AdminQuickTaskService.instance.isShowing && !AdminQuickTaskService.instance.isMinimized) {
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
          return Positioned(
            left: service.position.dx,
            top: service.position.dy,
            child: GestureDetector(
              onTap: service.toggleMinimized,
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
        return Positioned(
          left: service.position.dx,
          top: service.position.dy,
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
