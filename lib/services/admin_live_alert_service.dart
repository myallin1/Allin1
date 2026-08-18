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

  // FIX (Aug 11 2026 — Nizam's "Admin Completion Notifications" request):
  // this listener used to filter to `DocumentChangeType.added` ONLY, so
  // Admin was alerted the instant a ride/request was CREATED but never
  // learned when one actually finished — a real gap for a revenue-
  // tracking-focused admin who wants to know the moment money changes
  // hands. `DocumentChangeType.modified` fires on every field write to a
  // matched doc though (status changes, fare edits, hero-assignment
  // writes, etc.), not just the transition into 'completed' — so each
  // doc id is tracked here once it's been alerted-as-completed, to avoid
  // re-notifying on every subsequent unrelated field write to the same
  // now-completed doc (e.g. a later payment-status update).
  final Set<String> _alertedRideCompletions = {};
  final Set<String> _alertedRequestCompletions = {};
  final Set<String> _alertedRequestPingings = {};

  void start() {
    stop(); // idempotent — clears any previous session's listeners first.
    final since = Timestamp.now();
    _alertedRideCompletions.clear();
    _alertedRequestCompletions.clear();
    _alertedRequestPingings.clear();

    _ridesSub = FirebaseFirestore.instance
        .collection('rides')
        .where('createdAt', isGreaterThan: since)
        .snapshots()
        .listen((snap) {
      for (final change in snap.docChanges) {
        final data = change.doc.data();
        if (data == null) continue;

        if (change.type == DocumentChangeType.added) {
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
        } else if (change.type == DocumentChangeType.modified) {
          final status = data['status'] as String?;
          if (status == 'completed' &&
              _alertedRideCompletions.add(change.doc.id)) {
            final fare = (data['finalFare'] ??
                    data['actualFare'] ??
                    data['estimatedFare'] ??
                    data['fare']) as num?;
            final heroName = (data['acceptedHeroName'] as String?) ??
                (data['heroName'] as String?) ??
                'Hero';
            unawaited(AdminAlertNotificationService.showForegroundAlert(
              title: '✅ Ride completed',
              body: fare != null
                  ? '$heroName • ₹${fare.toStringAsFixed(0)}'
                  : heroName,
              payloadId: 'ride_completed_${change.doc.id}',
              type: 'admin_ride_completed',
            ));
          }
        }
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
        final data = change.doc.data();
        if (data == null) continue;

        if (change.type == DocumentChangeType.added) {
          final requestType = (data['requestType'] as String?) ?? 'service request';
          final customerName = (data['customerName'] as String?) ?? 'A customer';
          unawaited(AdminAlertNotificationService.showForegroundAlert(
            title: '🛎️ New ${requestType.replaceAll('_', ' ')}',
            body: customerName,
            payloadId: 'request_${change.doc.id}',
            type: 'admin_new_service_request',
          ));
        } else if (change.type == DocumentChangeType.modified) {
          final status = data['status'] as String?;
          if (status == 'pinging' &&
              _alertedRequestPingings.add(change.doc.id)) {
            final requestType =
                (data['requestType'] as String?) ?? 'service request';
            final customerName = (data['customerName'] as String?) ?? 'A customer';
            unawaited(AdminAlertNotificationService.showForegroundAlert(
              title: '🚚 Partner Requested!',
              body: '$customerName\'s ${requestType.replaceAll('_', ' ')} is ready.',
              payloadId: 'request_${change.doc.id}',
              type: 'admin_delivery_requested',
            ));
          } else if (status == 'completed' &&
              _alertedRequestCompletions.add(change.doc.id)) {
            final requestType =
                (data['requestType'] as String?) ?? 'service request';
            final amount =
                (data['finalAmount'] ?? data['estimatedFare']) as num?;
            final heroName = (data['assignedHeroName'] as String?) ??
                (data['acceptedHeroName'] as String?) ??
                'Hero';
            unawaited(AdminAlertNotificationService.showForegroundAlert(
              title: '✅ ${requestType.replaceAll('_', ' ')} completed',
              body: amount != null
                  ? '$heroName • ₹${amount.toStringAsFixed(0)}'
                  : heroName,
              payloadId: 'request_completed_${change.doc.id}',
              type: 'admin_service_request_completed',
            ));
          }
        }
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
    _alertedRideCompletions.clear();
    _alertedRequestCompletions.clear();
    _alertedRequestPingings.clear();
  }
}
