// ================================================================
// order_tracking_notification_controller.dart — Phase 2 of the
// live-order-tracking-notification feature (branch: feature/live-
// order-tracking-notification)
// ================================================================
// The coordinator: subscribes to OrderTrackingService's per-order
// stream (Phase 1) and drives OrderTrackingForegroundService's
// start/update/stop (Phase 2's own low-level wrapper) — this is the
// only file that decides WHAT the notification says; the other two
// only know how to stream data and how to push a notification,
// respectively.
//
// SINGLE-ORDER SCOPE (v1): tracks at most one order/ride at a time —
// starting a new trackOrder() call replaces whatever was being
// tracked before. Matches Blinkit/Swiggy's own behaviour and the
// scope agreed for this feature; a customer with two simultaneous
// active orders is a real but rare case not solved by v1.
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../models/tracking_snapshot.dart';
import '../utils/service_request_labels.dart';
import 'order_tracking_foreground_service.dart';
import 'order_tracking_rich_notification_service.dart';
import 'order_tracking_service.dart';

class OrderTrackingNotificationController {
  OrderTrackingNotificationController._();
  static final OrderTrackingNotificationController instance =
      OrderTrackingNotificationController._();

  StreamSubscription<TrackingSnapshot?>? _sub;
  String? _trackedDocId;

  /// Whether the rich (Phase 3) notification is the one currently
  /// showing, as opposed to the plain text one (Phase 2). Null until
  /// the first snapshot for this order is processed.
  bool? _usingRichNotification;

  /// Starts (or switches to) tracking [docId]. Safe to call repeatedly
  /// with the same docId — a no-op if already tracking it. Call this
  /// exactly once, right after an order/ride is successfully created
  /// (status is already 'pending' at that point, matching the "start
  /// the moment the order is placed" requirement), and also once at
  /// app boot if OrderTrackingService.findActiveOrder() finds an order
  /// still active from before the app was last closed.
  Future<void> trackOrder(String docId, TrackingCollection collection) async {
    if (_trackedDocId == docId) return;
    await _sub?.cancel();
    _trackedDocId = docId;
    // FIX (grep re-audit, Sep 2026 — real bug, sequential-orders edge
    // case): these two flags used to be reset ONLY in stopTracking(),
    // never here. If order 1 had already transitioned into the rich
    // (Phase 3) notification — which stops the Phase 2 foreground
    // service entirely — and a customer then placed order 2 BEFORE
    // order 1 finished (trackOrder() switching docId without an
    // intervening stopTracking()), order 2's first snapshot would see
    // stale _hasStartedNotification == true and call
    // OrderTrackingForegroundService.update() instead of start(). That
    // service silently no-ops on update() when not already running
    // (by design — see its own header), so order 2 would show NO
    // notification at all until it too reached a live-location phase.
    // Resetting both here, on every genuine order switch, makes each
    // newly-tracked order start clean regardless of what the
    // previously-tracked order's notification state was.
    _hasStartedNotification = false;
    _usingRichNotification = null;

    _sub = OrderTrackingService.instance.streamOrder(docId, collection).listen(
      (snapshot) async {
        if (snapshot == null) {
          // Doc deleted (e.g. cancelled orders are hard-deleted
          // elsewhere in this codebase — see ServiceRequestService.
          // cancelServiceRequest) — nothing left to track.
          await stopTracking();
          return;
        }
        if (!snapshot.isActive) {
          await OrderTrackingForegroundService.stop();
          await OrderTrackingRichNotificationService.cancel();
          await stopTracking();
          return;
        }

        // PHASE 3 hand-off: once a hero/captain's live location exists
        // (enRoute/nearingCompletion with real coordinates), the rich
        // animated-icon notification takes over as THE ONE visible
        // notification — see order_tracking_rich_notification_service.
        // dart's header for why exactly one of the two is ever showing
        // at a time. Before that point (waiting/assigned, nothing to
        // animate), the plain text/progress notification from Phase 2
        // is what the customer sees.
        if (snapshot.hasLiveLocation) {
          if (_usingRichNotification == false) {
            // Switching FROM the plain notification — stop it so the
            // customer doesn't see two ongoing notifications for the
            // same order while both plugins settle.
            await OrderTrackingForegroundService.stop();
          }
          _usingRichNotification = true;
          await OrderTrackingRichNotificationService.show(snapshot);
          return;
        }

        if (_usingRichNotification == true) {
          // Regressed back to no live location (shouldn't normally
          // happen once a hero starts publishing, but handled anyway —
          // e.g. a brief RTDB node gap) — fall back to plain text
          // rather than leaving a stale image on screen.
          await OrderTrackingRichNotificationService.cancel();
        }
        _usingRichNotification = false;

        final content = _contentFor(snapshot);
        if (await _isFirstUpdateForThisOrder()) {
          await OrderTrackingForegroundService.start(
            title: content.title,
            text: content.text,
          );
        } else {
          await OrderTrackingForegroundService.update(
            title: content.title,
            text: content.text,
          );
        }
      },
      onError: (Object e) {
        debugPrint('[OrderTrackingNotificationController] Stream error (non-fatal): $e');
      },
    );
  }

  // Tracks whether the CURRENT _sub has pushed anything yet, reset on
  // every trackOrder() call — lets the listener above decide start()
  // vs update() without a separate bool field to keep in sync by hand.
  bool _hasStartedNotification = false;
  Future<bool> _isFirstUpdateForThisOrder() async {
    if (_hasStartedNotification) return false;
    _hasStartedNotification = true;
    return true;
  }

  /// Stops tracking and tears down the subscription. Call on sign-out,
  /// or let it happen automatically when a tracked order reaches a
  /// terminal phase (already wired into the listener above).
  Future<void> stopTracking() async {
    await _sub?.cancel();
    _sub = null;
    _trackedDocId = null;
    _hasStartedNotification = false;
    _usingRichNotification = null;
  }

  /// Call once after a customer signs in (and at app boot if already
  /// signed in) — bounded, one-shot discovery (see
  /// OrderTrackingService.findActiveOrder's own header for why this is
  /// deliberately not a live listener) so a killed-and-reopened app
  /// resumes the notification for whatever was already active, instead
  /// of leaving the customer with no tracking until their next order.
  Future<void> resumeIfActive(String customerId) async {
    try {
      final active = await OrderTrackingService.instance.findActiveOrder(customerId);
      if (active != null) {
        await trackOrder(active.docId, active.collection);
      }
    } catch (e) {
      debugPrint('[OrderTrackingNotificationController] resumeIfActive failed (non-fatal): $e');
    }
  }

  ({String title, String text}) _contentFor(TrackingSnapshot snapshot) {
    final vertical = _verticalLabel(snapshot.requestType);
    switch (snapshot.collection) {
      case TrackingCollection.rides:
        return (title: vertical, text: _rideText(snapshot));
      case TrackingCollection.serviceRequests:
        // Reuses the exact copy already shown in-app on the tracking
        // screen (utils/service_request_labels.dart) rather than a
        // second, drifting copy of the same status strings.
        final label = serviceRequestStatusLabel(snapshot.requestType, snapshot.rawStatus);
        return (title: vertical, text: label);
    }
  }

  String _verticalLabel(String requestType) {
    switch (requestType) {
      case 'catalog_food_order':
      case 'custom_hotel_order':
        return 'Your food order';
      case 'grocery_order':
        return 'Your grocery order';
      case 'bike_taxi':
        return 'Your bike ride';
      case 'car_taxi':
        return 'Your car ride';
      case 'hero_booking':
        return 'Your service booking';
      case 'electronics_service':
        return 'Your NJ Tech service';
      default:
        return 'Your order';
    }
  }

  String _rideText(TrackingSnapshot snapshot) {
    final heroName = snapshot.heroName;
    switch (snapshot.phase) {
      case TrackingPhase.waiting:
        return 'Finding a hero for you...';
      case TrackingPhase.assigned:
        return heroName != null && heroName.isNotEmpty
            ? '$heroName is on the way to pick you up'
            : 'A hero is on the way to pick you up';
      case TrackingPhase.enRoute:
        return 'Ride in progress';
      case TrackingPhase.nearingCompletion:
        return heroName != null && heroName.isNotEmpty
            ? '$heroName has arrived'
            : 'Your hero has arrived';
      case TrackingPhase.completed:
      case TrackingPhase.cancelled:
        return '';
    }
  }
}
