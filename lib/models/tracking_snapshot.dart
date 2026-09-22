// ================================================================
// tracking_snapshot.dart — unified live-tracking shape across all 4
// customer-facing order/booking verticals
// ================================================================
// PHASE 1 of the live-order-tracking-notification feature (branch:
// feature/live-order-tracking-notification).
//
// WHY THIS EXISTS
// Bike/car taxi ('rides' collection) and food/grocery/hero-services
// ('service_requests' collection, split by requestType) use DIFFERENT
// status vocabularies (see TrackingPhase below) and are read from two
// different Firestore collections — but both use the exact same
// `live_locations/{docId}` RTDB node shape (`{lat, lng, heading,
// updatedAt}`, keyed by the ride/request doc's own id — confirmed by
// reading ride_tracking_screen.dart and service_request_live_map_
// screen.dart's actual current usage) for a hero/captain's live
// position mid-delivery/mid-ride.
//
// This model — and OrderTrackingService's stream that produces it —
// is the single shape the Phase 2 foreground-notification service
// consumes, so that service never needs to know it's looking at a ride
// vs a food order vs a hero-booking; it just reads a TrackingSnapshot.
/// Which Firestore collection this order/booking lives in. Determines
/// which raw status vocabulary applies and how OrderTrackingService
/// reads it — never used for anything customer-visible directly.
enum TrackingCollection { rides, serviceRequests }

/// Normalized, cross-vertical lifecycle phase. Every raw status string
/// from either 'rides' or 'service_requests' maps into exactly one of
/// these — see TrackingSnapshot._phaseFromRaw for the mapping table.
enum TrackingPhase {
  /// Order/ride placed, no hero/captain assigned yet.
  waiting,

  /// A hero/captain has accepted but hasn't started moving toward the
  /// pickup/customer yet (service_requests: 'hero_assigned'; rides:
  /// 'accepted').
  assigned,

  /// Actively en route (rides: 'arriving'/'started'/'in_progress';
  /// service_requests: 'in_progress'). This is the phase the animated
  /// moving-icon notification (Phase 3) actually animates during.
  enRoute,

  /// Final stretch (service_requests: 'nearing_completion'; rides:
  /// 'arrived'). Distinct from enRoute so the notification can switch
  /// copy to "Arriving now" without needing a live ETA countdown.
  nearingCompletion,

  /// Terminal — notification should be dismissed.
  completed,

  /// Terminal — notification should be dismissed, no rating prompt.
  cancelled,
}

/// One order/ride/booking's current trackable state, unified across
/// all 4 verticals. Immutable — a new snapshot is built on every
/// Firestore/RTDB update rather than mutating one in place, so a
/// notification-update diff is always comparing two real snapshots.
class TrackingSnapshot {
  const TrackingSnapshot({
    required this.docId,
    required this.collection,
    required this.requestType,
    required this.phase,
    required this.rawStatus,
    this.heroName,
    this.heroPhone,
    this.heroLat,
    this.heroLng,
    this.heroHeading,
    this.destinationLat,
    this.destinationLng,
  });

  final String docId;
  final TrackingCollection collection;

  /// 'bike_taxi' | 'car_taxi' | 'catalog_food_order' |
  /// 'custom_hotel_order' | 'grocery_order' | 'hero_booking' |
  /// 'electronics_service' | ... — drives which icon/label Phase 2's
  /// notification shows (e.g. a scooter icon vs a shopping-bag icon).
  final String requestType;

  final TrackingPhase phase;

  /// The original, vertical-specific status string — kept for any
  /// screen/log that wants the exact raw value rather than the
  /// normalized phase.
  final String rawStatus;

  final String? heroName;
  final String? heroPhone;

  /// Null until a hero/captain has actually started publishing to
  /// live_locations/{docId} — i.e. always null during [waiting]/
  /// [assigned], populated from [enRoute] onward. Phase 3's animated
  /// icon has nothing to animate until these are non-null.
  final double? heroLat;
  final double? heroLng;
  final double? heroHeading;

  /// Where the hero/captain is headed — the customer's own delivery/
  /// pickup location. Used to draw the path the Phase 3 icon animates
  /// along. Null for verticals that don't expose a fixed destination
  /// point (rare; falls back to a text-only notification for those).
  final double? destinationLat;
  final double? destinationLng;

  bool get isActive =>
      phase != TrackingPhase.completed && phase != TrackingPhase.cancelled;

  bool get hasLiveLocation => heroLat != null && heroLng != null;

  TrackingSnapshot copyWith({
    TrackingPhase? phase,
    String? rawStatus,
    String? heroName,
    String? heroPhone,
    double? heroLat,
    double? heroLng,
    double? heroHeading,
  }) {
    return TrackingSnapshot(
      docId: docId,
      collection: collection,
      requestType: requestType,
      phase: phase ?? this.phase,
      rawStatus: rawStatus ?? this.rawStatus,
      heroName: heroName ?? this.heroName,
      heroPhone: heroPhone ?? this.heroPhone,
      heroLat: heroLat ?? this.heroLat,
      heroLng: heroLng ?? this.heroLng,
      heroHeading: heroHeading ?? this.heroHeading,
      destinationLat: destinationLat,
      destinationLng: destinationLng,
    );
  }

  /// Maps a 'rides' collection doc's raw `status` field to the
  /// normalized phase. Vocabulary confirmed against
  /// bike_booking_screen.dart's own authoritative
  /// _restorableCustomerRideStatuses list ('searching', 'assigned',
  /// 'accepted', 'arriving', 'started', 'in_progress') plus 'arrived'/
  /// 'completed'/'cancelled' from ride_tracking_screen.dart's literal
  /// status checks — NOT 'pending', which rides never actually use
  /// (an earlier draft of this mapping wrongly assumed the same
  /// vocabulary as service_requests; ride_search_screen.dart's actual
  /// creation write sets 'searching').
  static TrackingPhase phaseFromRideStatus(String status) {
    switch (status) {
      case 'searching':
        return TrackingPhase.waiting;
      case 'assigned':
      case 'accepted':
        return TrackingPhase.assigned;
      case 'arriving':
      case 'started':
      case 'in_progress':
        return TrackingPhase.enRoute;
      case 'arrived':
        return TrackingPhase.nearingCompletion;
      case 'completed':
        return TrackingPhase.completed;
      case 'cancelled':
      case 'timeout':
        return TrackingPhase.cancelled;
      default:
        return TrackingPhase.waiting;
    }
  }

  /// Maps a 'service_requests' collection doc's raw `status` field to
  /// the normalized phase. Vocabulary confirmed against
  /// utils/service_request_labels.dart's serviceRequestStatusIndex —
  /// deliberately kept in sync with that function's switch cases
  /// rather than duplicating its index-based logic.
  static TrackingPhase phaseFromServiceRequestStatus(String status) {
    switch (status) {
      case 'pending':
      case 'admin_review':
        return TrackingPhase.waiting;
      case 'hero_assigned':
        return TrackingPhase.assigned;
      case 'in_progress':
        return TrackingPhase.enRoute;
      case 'nearing_completion':
        return TrackingPhase.nearingCompletion;
      case 'completed':
        return TrackingPhase.completed;
      case 'cancelled':
        return TrackingPhase.cancelled;
      default:
        return TrackingPhase.waiting;
    }
  }

  /// Builds a snapshot from a 'rides' Firestore document, with no live
  /// location yet (that's merged in separately by OrderTrackingService
  /// once the RTDB node is read — keeping this factory pure/testable
  /// against just the Firestore doc).
  factory TrackingSnapshot.fromRideDoc(
    String docId,
    Map<String, dynamic> data,
  ) {
    final status = data['status'] as String? ?? 'searching';
    return TrackingSnapshot(
      docId: docId,
      collection: TrackingCollection.rides,
      requestType: (data['vehicleType'] as String?) ?? 'bike_taxi',
      phase: phaseFromRideStatus(status),
      rawStatus: status,
      heroName: data['captainName'] as String? ?? data['heroName'] as String?,
      heroPhone: data['captainPhone'] as String? ?? data['heroPhone'] as String?,
      destinationLat: (data['dropLat'] as num?)?.toDouble(),
      destinationLng: (data['dropLng'] as num?)?.toDouble(),
    );
  }

  /// Builds a snapshot from a 'service_requests' Firestore document.
  factory TrackingSnapshot.fromServiceRequestDoc(
    String docId,
    Map<String, dynamic> data,
  ) {
    final status = data['status'] as String? ?? 'pending';
    final details = data['details'] as Map<String, dynamic>? ?? const {};
    return TrackingSnapshot(
      docId: docId,
      collection: TrackingCollection.serviceRequests,
      requestType: (data['requestType'] as String?) ?? 'hero_booking',
      phase: phaseFromServiceRequestStatus(status),
      rawStatus: status,
      heroName: data['assignedHeroName'] as String?,
      heroPhone: data['assignedHeroPhone'] as String?,
      destinationLat: (details['deliveryLat'] as num?)?.toDouble() ??
          (details['customerLat'] as num?)?.toDouble(),
      destinationLng: (details['deliveryLng'] as num?)?.toDouble() ??
          (details['customerLng'] as num?)?.toDouble(),
    );
  }

  /// Merges a `live_locations/{docId}` RTDB read (`{lat, lng, heading}`,
  /// already parsed to a plain map by the caller) onto this snapshot.
  /// Returns `this` unchanged if [rtdbData] is null (node doesn't exist
  /// yet — hero hasn't started publishing location).
  TrackingSnapshot withLiveLocation(Map<Object?, Object?>? rtdbData) {
    if (rtdbData == null) return this;
    final lat = (rtdbData['lat'] as num?)?.toDouble();
    final lng = (rtdbData['lng'] as num?)?.toDouble();
    final heading = (rtdbData['heading'] as num?)?.toDouble();
    if (lat == null || lng == null) return this;
    return copyWith(heroLat: lat, heroLng: lng, heroHeading: heading);
  }
}
