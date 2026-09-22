// ================================================================
// order_tracking_service.dart — Phase 1 of the live-order-tracking-
// notification feature (branch: feature/live-order-tracking-notification)
// ================================================================
// Produces a unified Stream<TrackingSnapshot> for any single order/
// ride, and a bounded discovery query for "does this customer have any
// order/ride active right now" — the thing Phase 2's foreground
// service polls once at boot (and re-runs on sign-in) to decide
// whether to start the notification at all, without ever needing an
// unbounded/always-on listener across the whole customer base.
//
// Deliberately NOT a live listener for discovery — mirrors this app's
// established "no live listener where a bounded one-shot query will
// do" convention (see the Sep 2026 database-wastage audit elsewhere in
// this codebase). Once a specific order IS being tracked, ITS
// Firestore doc + RTDB location node are live-streamed (that liveness
// is the entire point of Phase 2) — only the discovery step is bounded
// and on-demand.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;

import '../models/tracking_snapshot.dart';

class OrderTrackingService {
  OrderTrackingService._();
  static final OrderTrackingService instance = OrderTrackingService._();

  /// Statuses considered "active" for discovery purposes, per
  /// collection — mirrors TrackingSnapshot's phase mapping (waiting/
  /// assigned/enRoute/nearingCompletion, i.e. everything except
  /// completed/cancelled), kept as raw strings here so the query
  /// itself can filter server-side with `whereIn` rather than fetching
  /// terminal orders just to discard them client-side.
  static const _activeServiceRequestStatuses = [
    'pending',
    'admin_review',
    'hero_assigned',
    'in_progress',
    'nearing_completion',
  ];
  // Matches bike_booking_screen.dart's own authoritative
  // _restorableCustomerRideStatuses list + 'arrived' — see
  // TrackingSnapshot.phaseFromRideStatus's header for why this is NOT
  // 'pending' (rides never use that status; creation writes 'searching').
  static const _activeRideStatuses = [
    'searching',
    'assigned',
    'accepted',
    'arriving',
    'started',
    'in_progress',
    'arrived',
  ];

  /// One-shot, bounded (never live) check for whether [customerId] has
  /// any order/ride active right now. Returns at most one
  /// TrackingSnapshot — the single most relevant active order — or
  /// null if none. `limit(1)` on each query: Phase 2 only ever tracks
  /// one order's notification at a time (matching Blinkit/Swiggy's own
  /// behavior — a second concurrent order simply isn't a case this
  /// feature needs to solve for v1), so there's no reason to pay for
  /// more than one doc per collection even if a customer somehow has
  /// several active at once.
  Future<TrackingSnapshot?> findActiveOrder(String customerId) async {
    final ridesFuture = FirebaseFirestore.instance
        .collection('rides')
        .where('customerId', isEqualTo: customerId)
        .where('status', whereIn: _activeRideStatuses)
        .limit(1)
        .get();
    final requestsFuture = FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerId', isEqualTo: customerId)
        .where('status', whereIn: _activeServiceRequestStatuses)
        .limit(1)
        .get();

    final results = await Future.wait([ridesFuture, requestsFuture]);
    final rideDocs = results[0].docs;
    final requestDocs = results[1].docs;

    if (rideDocs.isNotEmpty) {
      return TrackingSnapshot.fromRideDoc(
        rideDocs.first.id,
        rideDocs.first.data(),
      );
    }
    if (requestDocs.isNotEmpty) {
      return TrackingSnapshot.fromServiceRequestDoc(
        requestDocs.first.id,
        requestDocs.first.data(),
      );
    }
    return null;
  }

  /// Live stream for ONE already-known order/ride — merges its
  /// Firestore doc (status/hero-identity fields) with its
  /// `live_locations/{docId}` RTDB node (hero position) into a single
  /// TrackingSnapshot stream. This is the stream Phase 2's foreground
  /// service actually stays subscribed to for the lifetime of the
  /// notification.
  Stream<TrackingSnapshot?> streamOrder(
    String docId,
    TrackingCollection collection,
  ) {
    final firestoreStream = collection == TrackingCollection.rides
        ? FirebaseFirestore.instance
            .collection('rides')
            .doc(docId)
            .snapshots()
            .map<TrackingSnapshot?>((snap) => snap.exists
                ? TrackingSnapshot.fromRideDoc(docId, snap.data()!)
                : null)
        : FirebaseFirestore.instance
            .collection('service_requests')
            .doc(docId)
            .snapshots()
            .map<TrackingSnapshot?>((snap) => snap.exists
                ? TrackingSnapshot.fromServiceRequestDoc(docId, snap.data()!)
                : null);

    final locationStream = rtdb.FirebaseDatabase.instance
        .ref('live_locations/$docId')
        .onValue
        .map((event) => event.snapshot.value as Map<Object?, Object?>?);

    // Manual combineLatest (no rxdart dependency in this app): re-emits
    // a merged snapshot whenever EITHER source fires, so a
    // location-only RTDB update (no Firestore write) still moves
    // Phase 3's animated icon without waiting on the next Firestore
    // change. Buffers the latest value from each side; only emits once
    // the Firestore side has fired at least once (a location update
    // arriving before the doc is known would have nothing to attach to).
    late StreamController<TrackingSnapshot?> controller;
    StreamSubscription<TrackingSnapshot?>? firestoreSub;
    StreamSubscription<Map<Object?, Object?>?>? locationSub;
    TrackingSnapshot? latestSnapshot;
    bool haveSnapshot = false;
    Map<Object?, Object?>? latestLocation;

    void emit() {
      if (!haveSnapshot) return;
      controller.add(latestSnapshot?.withLiveLocation(latestLocation));
    }

    controller = StreamController<TrackingSnapshot?>.broadcast(
      onListen: () {
        firestoreSub = firestoreStream.listen((snap) {
          latestSnapshot = snap;
          haveSnapshot = true;
          emit();
        }, onError: controller.addError);
        locationSub = locationStream.listen((loc) {
          latestLocation = loc;
          emit();
        }, onError: controller.addError);
      },
      onCancel: () async {
        await firestoreSub?.cancel();
        await locationSub?.cancel();
        await controller.close();
      },
    );

    return controller.stream;
  }
}
