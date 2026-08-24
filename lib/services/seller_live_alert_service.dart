// ================================================================
// seller_live_alert_service.dart — Live listener for new orders.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'seller_alert_notification_service.dart';

class SellerLiveAlertService {
  SellerLiveAlertService._();
  static final SellerLiveAlertService instance = SellerLiveAlertService._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestsSub;

  void start(String sellerId) {
    stop();
    final since = Timestamp.now();

    // FIX (Aug 20 2026 audit HIGH-2 — "seller never gets the New Order
    // alert"): this used to query top-level `.where('sellerId', ...)`,
    // but createServiceRequest() (service_request_service.dart) stores
    // the seller's uid NESTED at details.sellerId (there is no
    // top-level sellerId field, and the method has no such param), so
    // the query silently matched ZERO documents and the loud
    // foreground alert never fired for any seller. The seller
    // dashboard's own order cards filter details.sellerId and worked,
    // which is why this stayed invisible.
    //
    // Also moved the "only alert for orders created after this
    // listener started" check OUT of the query into the listener:
    // equality + createdAt-range on a nested field would need a NEW
    // composite console index (details.sellerId ASC, createdAt ASC),
    // which we can't create from code — the equality-only query uses
    // Firestore's automatic single-field index and can never 401 with
    // a missing-index error.
    _requestsSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('details.sellerId', isEqualTo: sellerId)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;

        if (change.type == DocumentChangeType.added) {
          final status = data['status'] as String?;
          final createdAt = data['createdAt'] as Timestamp?;
          // Skip documents that already existed before this listener
          // started (the first snapshot dumps every matching doc).
          if (createdAt != null && !createdAt.toDate().isAfter(since.toDate())) {
            continue;
          }
          // Only alert for pending (new) orders, not orders the seller already accepted
          if (status == 'pending') {
             unawaited(SellerAlertNotificationService.showForegroundAlert(
              title: '🛎️ New Order Received!',
              body: 'Open the app to accept and pack.',
              payloadId: 'order_${change.doc.id}',
            ));
          }
        }
      }
    }, onError: (Object e) {
      debugPrint('[SellerLiveAlertService] requests listener error: $e');
    });
  }

  void stop() {
    _requestsSub?.cancel();
    _requestsSub = null;
  }
}
