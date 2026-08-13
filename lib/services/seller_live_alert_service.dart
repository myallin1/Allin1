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

    _requestsSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('sellerId', isEqualTo: sellerId)
        .where('createdAt', isGreaterThan: since)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;

        if (change.type == DocumentChangeType.added) {
          final status = data['status'] as String?;
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
