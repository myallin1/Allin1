// ================================================================
// phonepe_payment_service.dart — PhonePe Payment Gateway integration.
// ================================================================
// Deliberately does NOT trust anything the checkout WebView reports
// about its own final state (redirect URL reached, JS callback fired,
// etc.) — per explicit security requirement, only a server-verified
// signal counts as "paid". That signal is functions/phonepeWebhook.ts
// flipping payment_orders/{merchantTransactionId}.status server-side;
// this service's job is just:
//   1. Ask createPhonePeOrder (Cloud Function) for a checkout URL.
//   2. Show that URL in a WebView so the customer can pay.
//   3. Stream payment_orders/{merchantTransactionId} from Firestore —
//      the moment the webhook lands and flips status to 'paid'/
//      'failed', this stream reflects it. The WebView is closed then,
//      not before.
// A short reconciliation fallback (checkPhonePeOrderStatus) covers the
// rare case where PhonePe's webhook is delayed after the customer
// already closes/backs out of the checkout page.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/foundation.dart';
import './firestore_usage_tracking.dart';

enum PhonePeOrderStatus { created, paid, failed }

class PhonePeOrderResult {
  final String merchantTransactionId;
  final String redirectUrl;
  const PhonePeOrderResult({
    required this.merchantTransactionId,
    required this.redirectUrl,
  });
}

class PhonePePaymentService {
  PhonePePaymentService._();
  static final PhonePePaymentService instance = PhonePePaymentService._();

  final FirebaseFunctions _functions = FirebaseFunctions.instance;
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Creates a gateway order for [requestId] (a doc in [collection],
  /// default 'service_requests') worth [amount] rupees, and returns
  /// the hosted checkout URL to open in a WebView.
  Future<PhonePeOrderResult> createOrder({
    required String requestId,
    required double amount,
    String collection = 'service_requests',
  }) async {
    final callable = _functions.httpsCallable('createPhonePeOrder');
    final result = await callable.call<Map<String, dynamic>>({
      'requestId': requestId,
      'amount': amount,
      'collection': collection,
    });
    final data = result.data;
    final merchantTransactionId = data['merchantTransactionId'] as String;
    final redirectUrl = data['redirectUrl'] as String;
    return PhonePeOrderResult(
      merchantTransactionId: merchantTransactionId,
      redirectUrl: redirectUrl,
    );
  }

  /// Live stream of a gateway order's verified status. This is what
  /// the checkout screen should watch to decide when to close the
  /// WebView and show success/failure — never the WebView's own
  /// navigation events.
  Stream<PhonePeOrderStatus> watchOrderStatus(String merchantTransactionId) {
    return _db
        .collection('payment_orders')
        .doc(merchantTransactionId)
        .trackedSnapshots()
        .map((snap) {
      final status = snap.data()?['status'] as String?;
      switch (status) {
        case 'paid':
          return PhonePeOrderStatus.paid;
        case 'failed':
          return PhonePeOrderStatus.failed;
        default:
          return PhonePeOrderStatus.created;
      }
    });
  }

  /// Belt-and-braces reconciliation: forces a server-to-server status
  /// check against PhonePe directly, for when the customer has already
  /// left the checkout page and the webhook stream above hasn't
  /// resolved within a few seconds. Safe to call repeatedly — it's a
  /// read-through that only writes if the gateway itself reports a
  /// terminal state, and never on the client's say-so.
  Future<PhonePeOrderStatus> reconcile(String merchantTransactionId) async {
    try {
      final callable = _functions.httpsCallable('checkPhonePeOrderStatus');
      final result = await callable.call<Map<String, dynamic>>({
        'merchantTransactionId': merchantTransactionId,
      });
      final status = result.data['status'] as String?;
      switch (status) {
        case 'paid':
          return PhonePeOrderStatus.paid;
        case 'failed':
          return PhonePeOrderStatus.failed;
        default:
          return PhonePeOrderStatus.created;
      }
    } catch (e) {
      debugPrint('[PhonePePaymentService] reconcile failed: $e');
      return PhonePeOrderStatus.created;
    }
  }

  /// Closes the loop for a payment that was collected BEFORE its order
  /// doc existed (food checkout: payment happens first, against a
  /// RESERVED requestId via ServiceRequestService.reserveRequestId();
  /// the service_requests doc is only created afterward, once stock is
  /// confirmed). At payment time, phonepeWebhook.ts's own cascade finds
  /// nothing to write paymentStatus onto yet and skips it — call this
  /// immediately after actually creating the order (with that SAME
  /// requestId as preGeneratedRequestId) to finish the link.
  ///
  /// Still never trusts the client — this re-checks
  /// payment_orders/{merchantTransactionId}.status server-side and only
  /// acts if PhonePe's webhook already verified it as 'paid'. Safe to
  /// call even if that hasn't happened yet: returns `linked: false`
  /// rather than throwing, since the webhook may simply be running late.
  Future<bool> confirmLink({
    required String merchantTransactionId,
    required String requestId,
  }) async {
    try {
      final callable = _functions.httpsCallable('confirmPhonePeLink');
      final result = await callable.call<Map<String, dynamic>>({
        'merchantTransactionId': merchantTransactionId,
        'requestId': requestId,
      });
      return result.data['linked'] == true;
    } catch (e) {
      debugPrint('[PhonePePaymentService] confirmLink failed: $e');
      return false;
    }
  }
}
