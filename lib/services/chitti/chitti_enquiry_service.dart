// ================================================================
// chitti_enquiry_service.dart — turns a price question into a lead
// NJ Tech can actually answer.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "rate and models daily maarum, so namma
// kita than final rate and final offer kekkanum. Angirunthu namaku oru
// enquiry varramari set pannirlam, atha namma seller and admin phone
// la monitor pannalam").
//
// THIS IS THE ACTUAL PRODUCT, NOT THE SEARCH
// It is tempting to treat the web lookup as the feature and this as
// plumbing. It is the other way round. Anything scraped is somebody
// else's price on a page that may have changed this morning, and a
// customer who quotes it at the counter is holding NJ Tech to a number
// NJ Tech never set. The market figure is context; the enquiry is the
// answer.
//
// WHY ITS OWN COLLECTION
// The obvious move — reuse service_requests — is wrong here.
// ServiceRequestService.createServiceRequest() BROADCASTS to nearby
// Heroes and starts a dispatch. A price question is not a job for a
// Hero, and putting one into that pipeline would ping riders for
// something none of them can fulfil. `chitti_enquiries` is a plain
// document nobody is dispatched for.
//
// Purely additive: no existing collection, rule or flow is touched.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../auth_service.dart';
import '../firestore_usage_tracking.dart';

/// How filing an enquiry ended.
///
/// A bool was not enough (self-audit, Aug 28 2026). `false` meant both
/// "you are not signed in" and "the write failed", so a signed-in
/// customer whose write was rejected — Firestore rules not yet
/// deployed, or simply offline — was told to sign in. Telling someone
/// who IS signed in to sign in reads as broken, and hides the real
/// reason from whoever has to debug it.
enum ChittiEnquiryOutcome {
  /// Filed. A human at NJ Tech will see it.
  sent,

  /// No real account, so there would be no way to call them back.
  needsSignIn,

  /// Reached Firestore and was refused, or there was no network.
  failed,
}

/// What the customer was asking about.
enum ChittiEnquiryKind {
  /// "What does a Redmi Note 13 display cost?"
  displayRepair,

  /// "Best mobile under 10000?"
  mobilePurchase,

  /// Anything else Chitti could not price itself.
  general,
}

class ChittiEnquiryService {
  ChittiEnquiryService._();

  static const String collectionPath = 'chitti_enquiries';

  /// Files an enquiry for a human at NJ Tech to answer.
  ///
  /// The outcome is distinguished so the caller can say something true
  /// — see [ChittiEnquiryOutcome].
  static Future<ChittiEnquiryOutcome> submit({
    required String question,
    required ChittiEnquiryKind kind,
    String? model,
    String? marketReference,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    // Anonymous sessions carry no phone number, so there would be no
    // way to call the customer back — a lead nobody can answer is
    // worse than telling them to sign in.
    if (user == null || user.isAnonymous) {
      debugPrint('[ChittiEnquiry] skipped — no real account to reply to.');
      return ChittiEnquiryOutcome.needsSignIn;
    }

    try {
      final phone = await AuthService().resolveCustomerPhone(user);
      await FirebaseFirestore.instance.collection(collectionPath).add({
        'question': question.trim(),
        'kind': kind.name,
        if (model != null && model.trim().isNotEmpty) 'model': model.trim(),
        // Stored so whoever answers can see what the customer was
        // already shown — quoting a number below what Chitti displayed
        // needs to be a deliberate choice, not a surprise.
        if (marketReference != null && marketReference.trim().isNotEmpty)
          'marketReference': marketReference.trim(),
        'customerId': user.uid,
        'customerName': user.displayName?.trim() ?? '',
        'customerPhone': phone,
        'status': 'open',
        'source': 'chitti',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return ChittiEnquiryOutcome.sent;
    } catch (e) {
      // Most likely an undeployed firestore.rules change or no
      // network. Either way the customer is owed an honest answer and
      // a way to reach a human.
      debugPrint('[ChittiEnquiry] submit failed: $e');
      return ChittiEnquiryOutcome.failed;
    }
  }

  /// Open enquiries, newest first — for the admin/seller monitor.
  ///
  /// Equality filter only, sorted client-side: a `where` on status plus
  /// an `orderBy` on createdAt needs a composite index, and on the
  /// Spark plan a missing index is a hard query failure rather than a
  /// slow one.
  static Stream<List<ChittiEnquiry>> watchOpen({int limit = 50}) {
    return FirebaseFirestore.instance
        .collection(collectionPath)
        .where('status', isEqualTo: 'open')
        .limit(limit)
        .trackedSnapshots()
        .map((snap) {
      final items = snap.docs.map(ChittiEnquiry.fromDoc).toList()
        ..sort((a, b) {
          final at = a.createdAt;
          final bt = b.createdAt;
          if (at == null || bt == null) return 0;
          return bt.compareTo(at);
        });
      return items;
    });
  }

  /// Marks one answered, so it leaves the monitor.
  static Future<void> markAnswered(String id) async {
    try {
      await FirebaseFirestore.instance
          .collection(collectionPath)
          .doc(id)
          .update({
        'status': 'answered',
        'answeredAt': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[ChittiEnquiry] markAnswered failed: $e');
    }
  }
}

/// One enquiry, as the monitor screen needs it.
@immutable
class ChittiEnquiry {
  const ChittiEnquiry({
    required this.id,
    required this.question,
    required this.kind,
    required this.customerName,
    required this.customerPhone,
    this.model = '',
    this.marketReference = '',
    this.createdAt,
  });

  factory ChittiEnquiry.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    return ChittiEnquiry(
      id: doc.id,
      question: (d['question'] as String?) ?? '',
      kind: (d['kind'] as String?) ?? 'general',
      customerName: (d['customerName'] as String?) ?? '',
      customerPhone: (d['customerPhone'] as String?) ?? '',
      model: (d['model'] as String?) ?? '',
      marketReference: (d['marketReference'] as String?) ?? '',
      createdAt: (d['createdAt'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String question;
  final String kind;
  final String customerName;
  final String customerPhone;
  final String model;
  final String marketReference;
  final DateTime? createdAt;
}
