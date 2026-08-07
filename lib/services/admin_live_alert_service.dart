// ================================================================
// admin_live_alert_service.dart — free, Cloud-Function-free alert
// pipeline for new rides / service requests.
// ================================================================
// NEW (per Nizam's request, free alternative — no Blaze/billing):
// pairs with admin_foreground_service.dart. As long as the Admin
// app's process is alive (kept alive by the foreground service below),
// these two live Firestore listeners fire a loud local notification
// the instant a NEW ride or service request document is created —
// entirely client-side, no Cloud Functions, no server, ₹0 cost.
//
// Each listener is scoped with `.where('createdAt', isGreaterThan:
// <the moment this listener started>)`, so the very first snapshot
// (which normally dumps every existing matching doc) naturally returns
// nothing — only documents created AFTER this admin session started
// ever fire an alert. This avoids re-notifying about old bookings
// every time the app restarts/reconnects.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'admin_alert_notification_service.dart';

class AdminLiveAlertService {
  AdminLiveAlertService._();
  static final AdminLiveAlertService instance = AdminLiveAlertService._();

  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _ridesSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _requestsSub;

  void start() {
    stop(); // idempotent — clears any previous session's listeners first.
    final since = Timestamp.now();

    _ridesSub = FirebaseFirestore.instance
        .collection('rides')
        .where('createdAt', isGreaterThan: since)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        final pickup = (data['pickupAddress'] as String?) ??
            (data['pickup'] as String?) ??
            'Pickup location';
        final drop = (data['dropAddress'] as String?) ??
            (data['drop'] as String?) ??
            'Drop location';
        final vehicleType = (data['vehicleType'] as String?) ?? 'ride';
        unawaited(AdminAlertNotificationService.showForegroundAlert(
          title: '🚕 New $vehicleType booking',
          body: '$pickup → $drop',
          payloadId: 'ride_${change.doc.id}',
          type: 'admin_new_ride',
        ));
      }
    }, onError: (Object e) {
      debugPrint('[AdminLiveAlertService] rides listener error: $e');
    });

    _requestsSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('createdAt', isGreaterThan: since)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        if (change.type != DocumentChangeType.added) continue;
        final data = change.doc.data();
        if (data == null) continue;
        final requestType = (data['requestType'] as String?) ?? 'service request';
        final customerName = (data['customerName'] as String?) ?? 'A customer';
        unawaited(AdminAlertNotificationService.showForegroundAlert(
          title: '🛎️ New ${requestType.replaceAll('_', ' ')}',
          body: customerName,
          payloadId: 'request_${change.doc.id}',
          type: 'admin_new_service_request',
        ));
      }
    }, onError: (Object e) {
      debugPrint('[AdminLiveAlertService] service_requests listener error: $e');
    });
  }

  void stop() {
    _ridesSub?.cancel();
    _ridesSub = null;
    _requestsSub?.cancel();
    _requestsSub = null;
  }
}
