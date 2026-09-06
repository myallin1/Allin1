// ================================================================
// chitti_call_service_log.dart — what a customer asked Chitti for
// during an in-app call, handed to admin afterwards
// ================================================================
// NEW (Sep 2026 — Nizam: "customer oru intent or avanga requirement ah
// chitti kitta sonnangana apo chitti antha call ah namma customer app
// pesi mudichathum namma admin app ku varanum services option kulla
// call services nu athukla customeroda intenta chitti namaku
// sollum...admin atha follow pannuvaru").
//
// WHAT COUNTS AS "AN INTENT", AND WHY THIS DOES NOT RE-CLASSIFY
// ANYTHING
// ChittiCallScreen already asks GuruApiService.extractAgentAction()
// once per turn — the exact same tool-calling call the full chat
// screen uses to actually DO things (book a ride, place an order, open
// a section). This file does not add a second opinion about what the
// customer meant; it only collects whatever that call already decided
// during the conversation and hands it to admin, empty or not.
//
// UPDATED (Sep 2026 — Nizam's "100% reliably recorded" requirement):
// this used to skip writing anything when a call produced zero
// intents, on the reasoning that pure small talk wasn't worth an admin
// queue row. That's no longer true now that this collection is the
// PERMANENT record for a call whose live RTDB session gets deleted
// right after — see ChittiLiveCallService.cleanupCall — so a call with
// no intents still needs a durable row, or its transcript/duration/
// outcome would vanish the moment the ephemeral node is wiped. Every
// call now writes a document; the admin queue's "no requests yet"
// empty-state and per-row rendering already handle an empty
// `intents` list without any UI change needed.
//
// Per Nizam's explicit choice: every tool call is logged, not a
// filtered subset — "show me my wallet" ends up in the queue exactly
// like "book me a ride" does. The alternative (hand-picking which tool
// names "count") was rejected because it is a second classification
// decision hiding inside what was supposed to be a pass-through log.
//
// WHY THIS WRITES ONCE PER CALL, NOT ONCE PER INTENT
// A customer who asks for a ride AND mentions a stuck order in the same
// call is one thing for admin to follow up on, not two unrelated queue
// rows that arrived seconds apart with no visible connection between
// them. One document per call, intents as a list, keeps the admin
// picture matching what actually happened: one conversation.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// One tool call Chitti made during the call.
@immutable
class ChittiCallIntent {
  const ChittiCallIntent({required this.actionType, required this.detail});

  /// The tool name exactly as extractAgentAction returned it (e.g.
  /// 'book_ride', 'place_food_order', 'navigate_to_section') — kept as
  /// the model's own vocabulary rather than remapped to a second set of
  /// labels, so this can never drift out of sync with what the tools
  /// registry actually supports.
  final String actionType;

  /// Every other field extractAgentAction returned alongside 'action'
  /// — whatever arguments the model filled in for that tool.
  final Map<String, dynamic> detail;

  Map<String, dynamic> toJson() => {'actionType': actionType, 'detail': detail};
}

class ChittiCallServiceLog {
  ChittiCallServiceLog._();

  static const String _collection = 'call_service_requests';

  /// The admin-visibility SLA window in seconds (Sep 2026 — Nizam's
  /// product decision after the original customer-facing 45s timeout
  /// was found to be architecturally wrong: Chitti auto-handling a call
  /// end-to-end with no admin ever joining is the NORMAL, successful
  /// case here, not a failure — so nothing on the customer's side may
  /// ever time out or drop the call over this. This constant exists
  /// purely for admin's own after-the-fact visibility: "did a human
  /// ever join a call that ran long enough to plausibly have needed
  /// one," computed once, here, at logging time — no live timer, no
  /// RTDB write, nothing the customer's call flow can be affected by.
  static const int adminSlaSeconds = 45;

  /// Writes one call's full record as a single document — every call,
  /// not just ones that produced a tool call.
  ///
  /// CHANGED (Sep 2026 — Nizam's explicit requirement: "Every call's
  /// details and customer intents MUST be 100% reliably recorded
  /// before any temporary data is deleted"). This used to return early
  /// on an empty [intents] list, on the reasoning that a pure-chat call
  /// had nothing for admin to act on. That's still true for the admin
  /// queue's badge count, but this collection is now the PERMANENT
  /// record of a call whose RTDB signaling node gets deleted right
  /// after this write (see ChittiLiveCallService.cleanupCall) — a call
  /// with no intents still needs a durable row, or that call's
  /// transcript/outcome/duration is gone forever the moment RTDB wipes
  /// it. admin_call_services_screen.dart already renders an empty
  /// `intents` list fine (no crash, just no intent lines shown), so
  /// this is safe for that screen as-is.
  ///
  /// Field names `customerId`/`customerName`/`customerPhone` are kept
  /// (not renamed to callerId/callerName/callerPhone) deliberately —
  /// admin_call_services_screen.dart already reads these exact keys;
  /// renaming them here would silently break that screen's display for
  /// every call logged from now on.
  ///
  /// Never throws to the caller — a failed write must not affect the
  /// call itself having already ended cleanly for the customer.
  static Future<void> logCall({
    required List<ChittiCallIntent> intents,
    required DateTime callStartedAt,
    required DateTime callEndedAt,
    required String outcome,
    required bool adminJoined,
    List<String> fullTranscript = const [],
  }) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final durationSeconds = callEndedAt.difference(callStartedAt).inSeconds;
      // SLA breach = a call that ran long enough to plausibly have
      // needed a human (> adminSlaSeconds) and no admin ever actually
      // joined it — NOT "admin didn't answer instantly" (Chitti always
      // does, by design) and NOT evaluated on short calls that were
      // never at risk of needing a human in the first place.
      final adminSlaBreached = !adminJoined && durationSeconds > adminSlaSeconds;
      await FirebaseFirestore.instance.collection(_collection).add({
        'customerId': user?.uid,
        'customerName': user?.displayName,
        'customerPhone': user?.phoneNumber,
        'callStartedAt': Timestamp.fromDate(callStartedAt),
        'callEndedAt': Timestamp.fromDate(callEndedAt),
        'durationSeconds': durationSeconds,
        'intents': intents.map((i) => i.toJson()).toList(),
        // Redundant with `intents.isNotEmpty` but kept as its own field
        // so the admin badge query (AdminCallServicesScreen.newStream)
        // can filter on it directly — Firestore can't query "array is
        // non-empty" cleanly, and this collection deliberately still
        // writes a document for every call (history/analytics) even
        // though the badge should only fire for actionable ones.
        'hasIntents': intents.isNotEmpty,
        'fullTranscript': fullTranscript,
        'outcome': outcome,
        'adminJoined': adminJoined,
        'adminSlaBreached': adminSlaBreached,
        'status': 'new',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ChittiCallServiceLog] failed to log call: $e');
    }
  }
}
