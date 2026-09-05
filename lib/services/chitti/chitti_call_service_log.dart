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
// during the conversation and, if the list is non-empty when the call
// ends, hands it to admin. A call that was pure small talk produces no
// tool calls and therefore writes nothing here — there is no separate
// "was this worth telling admin about" judgment call to get wrong.
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

  /// Writes one call's worth of intents as a single document.
  ///
  /// Never throws to the caller — a failed write must not affect the
  /// call itself having already ended cleanly for the customer.
  /// Silently does nothing when [intents] is empty; that is the normal
  /// case (most calls are just conversation) and not an error.
  static Future<void> logCall({
    required List<ChittiCallIntent> intents,
    required DateTime callStartedAt,
    required DateTime callEndedAt,
  }) async {
    if (intents.isEmpty) return;
    try {
      final user = FirebaseAuth.instance.currentUser;
      await FirebaseFirestore.instance.collection(_collection).add({
        'customerId': user?.uid,
        'customerName': user?.displayName,
        'customerPhone': user?.phoneNumber,
        'callStartedAt': Timestamp.fromDate(callStartedAt),
        'callEndedAt': Timestamp.fromDate(callEndedAt),
        'intents': intents.map((i) => i.toJson()).toList(),
        'status': 'new',
        'createdAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ChittiCallServiceLog] failed to log call: $e');
    }
  }
}
