// ================================================================
// service_request_service.dart — Broadcast Order System
// Data layer for the 4 service-request categories (Hero Booking,
// Custom Order, Custom Food Order, Grocery Order). Isolated from the
// `orders` collection per CTO decision. Mirrors the ride-hailing
// broadcast/atomic-accept pattern in ride_search_screen.dart and
// hero_home_screen.dart, but broadcasts to ALL eligible heroes
// simultaneously instead of pinging sequentially.
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:geolocator/geolocator.dart';

import '../config/city_config.dart';
import '../models/service_request_model.dart';
import 'city_service.dart';
import 'hero_usage_accumulator_service.dart';
import 'hero_wallet_service.dart';
import 'usage_tracking_service.dart';
import '../config/hero_service_access.dart';
import '../config/hero_skill_catalog.dart';

/// Canonical status enum — the single source of truth for lifecycle state.
/// UI label sets (task-type vs goods-type) are presentation-only mappings
/// on top of these exact string values; never introduce a second enum.
const List<String> kServiceRequestStatuses = [
  'pending',
  'hero_assigned',
  'in_progress',
  'nearing_completion',
  'completed',
  'admin_review',
];

const int kServiceRequestPingExpirySeconds = 90;

/// Status-advance order for the hero/admin 3-button control — a
/// deliberate subset of kServiceRequestStatuses (excludes 'pending'
/// and 'admin_review', which aren't reachable once a hero is
/// assigned). Single source of truth shared by hero_home_screen.dart
/// and admin_new_orders_screen.dart — do not redefine locally.
const List<String> kServiceRequestAdvanceOrder = [
  'hero_assigned',
  'in_progress',
  'nearing_completion',
  'completed',
];

class ServiceRequestService {
  // FIX (CTO mandate — Model Adoption, Phase 3): typed accessors, added
  // ALONGSIDE the existing write methods below (unchanged — every
  // create/update/delete call keeps writing plain Maps exactly as
  // before, since Firestore's wire format is Map-based regardless).
  // These two are what let read-side screens stop doing
  // `snapshot.data()!['status']` and start doing
  // `request.status` — see service_request_tracking_screen.dart and
  // my_orders_screen.dart for the first two callers.

  /// Live single-document stream, typed. Mirrors the exact query
  /// service_request_tracking_screen.dart used to build inline
  /// (`service_requests/{requestId}.snapshots()`) — same stream, just
  /// mapped through `ServiceRequestModel.fromFirestore` before it
  /// reaches the caller. Emits `null` if the document doesn't exist
  /// (deleted/cancelled) so callers can show a "not found" state the
  /// same way a missing `DocumentSnapshot.exists` used to signal.
  Stream<ServiceRequestModel?> streamRequest(String requestId) {
    return FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .snapshots()
        .map((doc) {
      if (!doc.exists) return null;
      return ServiceRequestModel.fromFirestore(doc.data()!, doc.id);
    });
  }

  /// Live list stream for one customer's own requests across every
  /// requestType, typed.
  ///
  /// FIX (post-fix audit — silent-data-loss risk): this used to be a
  /// single `.where('customerId', ...)` filter with NO `.orderBy()`,
  /// paired with `.limit(50)` + a client-side sort AFTER the fetch. That
  /// combination is broken once a customer has more than 50 requests
  /// total: Firestore's `.limit()` without a matching `.orderBy()` picks
  /// an unspecified 50 docs, NOT guaranteed to be the newest — sorting
  /// them client-side after the fact only sorts whichever arbitrary 50
  /// came back, so a genuinely recent order could simply never appear.
  /// Moving `.orderBy('createdAt', descending: true)` into the query
  /// itself (before `.limit()`) makes "50 most recent" a real guarantee
  /// instead of an assumption.
  ///
  /// REQUIRES a composite index (customerId ASC, createdAt DESC) on
  /// `service_requests` — added to firestore.indexes.json alongside this
  /// change. MUST be deployed (`firebase deploy --only firestore:indexes`)
  /// before this query will actually return data; until then it throws
  /// `failed-precondition: requires an index`, which the `onError`
  /// handler on the caller's side just logs — the same silent-failure
  /// class this codebase has hit before (see erode_offers_section.dart).
  Stream<List<ServiceRequestModel>> streamCustomerRequests(
    String customerId,
  ) {
    return FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerId', isEqualTo: customerId)
        .orderBy('createdAt', descending: true)
        // FIX (zero-cost Firestore audit): was fully uncapped — a
        // long-time customer's entire lifetime order history would be
        // re-read on every snapshot. 50 most-recent docs (now a real
        // guarantee thanks to the orderBy above) is plenty for an
        // order-history screen.
        .limit(50)
        .snapshots()
        .map((snap) {
      return snap.docs
          .map((doc) => ServiceRequestModel.fromFirestore(doc.data(), doc.id))
          .toList();
    });
  }

  /// Reserves a document ID without writing anything — used when a
  /// caller needs the future request's ID before creating the doc
  /// (e.g. to build a Storage upload path keyed by requestId).
  String reserveRequestId() =>
      FirebaseFirestore.instance.collection('service_requests').doc().id;

  /// Creates a new service_requests doc, mirrors it to
  /// active_service_requests in RTDB, and broadcasts a ping to every
  /// online + available hero simultaneously.
  Future<String> createServiceRequest({
    required String requestType,
    required String customerId,
    required String customerName,
    required String customerPhone,
    required Map<String, dynamic> details,
    String? preGeneratedRequestId,

    /// Hold the hero broadcast back until the SELLER says the food is
    /// ready (Aug 17 2026 seller audit — Nizam: "food ready anathum
    /// 'book delivery partner' nu kaatanum, appo than heros-ku
    /// notification pogaNum").
    ///
    /// Default false keeps every existing caller (hero booking, custom
    /// order, grocery, custom food) on the unchanged
    /// broadcast-immediately behaviour. Only shop-menu food orders pass
    /// true, because only they have a cooking step: broadcasting at
    /// order time made a hero ride out and wait at the hotel while the
    /// food was still being cooked, burning their time and ours.
    ///
    /// When true the Firestore doc is still created identically (status
    /// 'pending', so the seller's existing listener and admin's screens
    /// see it exactly as before) and the RTDB mirror is still written —
    /// only the ping fan-out is skipped, until
    /// [requestDeliveryBroadcast] fires it.
    bool deferBroadcast = false,

    /// Skill key (see lib/config/hero_skill_catalog.dart) when this is a
    /// trade booking — electrician, plumber, laptop_pc, tv_service,
    /// fridge_ac.
    ///
    /// NEW (Aug 29 2026 — Nizam: skill heroes). When set, the ping goes
    /// ONLY to heroes carrying that skill, and only those within
    /// `kSkillDispatchRadiusKm` of the customer's own location.
    ///
    /// Null for every existing caller, and null means the broadcast
    /// behaves exactly as it did before this parameter existed — same
    /// city-wide fan-out, same serviceAccess gate, no distance test.
    /// That is what keeps rides, food, grocery and custom orders
    /// untouched on a live fleet.
    String? requiredSkill,
    double? customerLat,
    double? customerLng,
  }) async {
    // Allow callers that need the ID before the doc exists (e.g. grocery
    // orders that upload an image to a Storage path keyed by requestId)
    // to reserve the ID up front via `reserveRequestId()`.
    final docRef = preGeneratedRequestId != null
        ? FirebaseFirestore.instance.collection('service_requests').doc(preGeneratedRequestId)
        : FirebaseFirestore.instance.collection('service_requests').doc();
    final requestId = docRef.id;

    // Multi-city (Plan 3): tags this request with the customer's current
    // city so the broadcast below only pings same-city heroes. Defaults
    // to kDefaultCity ('erode') until a real city-picker UI exists for
    // customers.
    final requestCity = await CityService.getCurrentCity();

    await docRef.set({
      'requestId': requestId,
      'requestType': requestType,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'details': details,
      'status': 'pending',
      'assignedHeroId': null,
      'assignedHeroName': null,
      'assignedHeroPhone': null,
      'assignmentMethod': null,
      'city': requestCity,
      // Seller kitchen stage — only meaningful for deferred-broadcast
      // (shop menu food) orders. Written as null for every other request
      // type so the field's absence never has to be special-cased.
      'sellerStage': deferBroadcast ? kSellerStageNew : null,
      'sellerStageAt': null,
      // Financial idempotency flag (seller-earnings audit, Phase 1):
      // flips to true exactly once, inside the same Firestore
      // transaction that credits the seller's pendingPayouts on
      // completion — see _completeAndCreditSeller(). Written false here
      // (not omitted) so the field always exists for that transaction's
      // read-check-write guard and so firestore.rules' create clause can
      // enforce it starts false.
      'earningsCredited': false,
      'createdAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // DEMAND TRACKING (Aug 11 2026 — Nizam's request): this is the single
    // creation point for ALL FOUR non-ride categories (Hero Booking,
    // Custom Order, Custom Food Order, Grocery Order), so tracking here
    // covers every one of them rather than needing a call per screen.
    // Fire-and-forget single-doc atomic increments — never awaited, so
    // tracking can't delay a real customer request.
    unawaited(UsageTrackingService.instance.trackServiceUsed(requestType));
    // Hotel/store name lives inside the free-form `details` map — check
    // the keys the various builders actually use, in priority order.
    final vendorName = (details['hotelName'] ??
        details['sellerName'] ??
        details['storeName'] ??
        details['shopName'] ??
        details['restaurantName']) as String?;
    if (vendorName != null) {
      unawaited(UsageTrackingService.instance.trackHotelOrdered(vendorName));
    }
    final pickupPlace = (details['pickupAddress'] ?? details['pickup']) as String?;
    final dropPlace = (details['dropAddress'] ?? details['drop']) as String?;
    if (pickupPlace != null) {
      unawaited(UsageTrackingService.instance.trackPlaceSearched(pickupPlace));
    }
    if (dropPlace != null) {
      unawaited(UsageTrackingService.instance.trackPlaceSearched(dropPlace));
    }

    final pingExpiresAt = DateTime.now().toUtc().millisecondsSinceEpoch +
        kServiceRequestPingExpirySeconds * 1000;

    await rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId')
        .set({
      'requestId': requestId,
      'requestType': requestType,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'details': details,
      // 'awaiting_seller' is a HOLDING state, not a pinging one — no
      // hero has been contacted yet and none should treat this node as
      // claimable. requestDeliveryBroadcast() flips it to 'pinging'.
      'status': deferBroadcast ? 'awaiting_seller' : 'pinging',
      'currentPingHeroId': '',
      'acceptedHeroId': '',
      // Deferred requests get their expiry stamped at BROADCAST time
      // instead — an expiry computed now would already be half spent (or
      // fully expired) by the time a 30-minute biriyani is ready, and
      // every hero would discard the ping the instant it arrived.
      'pingExpiresAt': deferBroadcast ? 0 : pingExpiresAt,
      'city': requestCity,
      'createdAt': rtdb.ServerValue.timestamp,
    });

    if (!deferBroadcast) {
      await _broadcastToEligibleHeroes(
        requestId: requestId,
        requestType: requestType,
        customerName: customerName,
        customerPhone: customerPhone,
        details: details,
        pingExpiresAt: pingExpiresAt,
        requestCity: requestCity,
        requiredSkill: requiredSkill,
        customerLat: customerLat,
        customerLng: customerLng,
      );
    }

    // NEW (Issue 2 fix — "seller app not receiving any order
    // notification", zero-cost/no-Cloud-Functions constraint): wakes the
    // seller's RTDB listener the exact same way heroes are woken —
    // `hero_pings/{heroId}/{requestId}` — see main_seller.dart's
    // _initSellerPingListener for the read side. Only orders that
    // actually belong to a seller (catalog_food_order / custom_hotel_order,
    // both of which pass details.sellerId) get a ping; every other
    // requestType has no sellerId and is skipped.
    //
    // Kept deliberately tiny (no full item list/address) — this node
    // exists only to wake the app and is deleted the moment it's read
    // (or found expired), so it never accumulates against the project's
    // 1GB RTDB budget the way a full order mirror would.
    final sellerId = details['sellerId'] as String?;
    if (sellerId != null && sellerId.isNotEmpty) {
      final items = details['items'];
      final itemsSummary = items is List
          ? items
              .whereType<Map>()
              .take(3)
              .map((it) => '${it['quantity'] ?? it['qty'] ?? 1} × ${it['name'] ?? 'Item'}')
              .join(', ')
          : '';
      // Same "delete once consumed" contract as hero_pings — expiry here
      // is a long backstop (48h) for the case the seller never opens the
      // app at all, not the tight 90s ping window heroes use, since a
      // seller order can legitimately sit unopened overnight.
      final sellerPingExpiresAt = DateTime.now().toUtc().millisecondsSinceEpoch +
          (48 * 60 * 60 * 1000);
      unawaited(
        rtdb.FirebaseDatabase.instance
            .ref('seller_pings/$sellerId/$requestId')
            .set({
          'requestId': requestId,
          'requestType': requestType,
          'customerName': customerName,
          'itemsSummary': itemsSummary,
          'pingExpiresAt': sellerPingExpiresAt,
          'createdAt': rtdb.ServerValue.timestamp,
        }).catchError((Object e) {
          debugPrint('[ServiceRequestService] seller_pings write failed (non-fatal): $e');
        }),
      );
    }

    return requestId;
  }

  // ================================================================
  // SELLER KITCHEN FLOW (Aug 17 2026 seller-app audit)
  // ================================================================
  // Nizam's flow: order varum -> seller accept -> samaikkiraar -> food
  // ready -> "Book Delivery Partner" -> heroes-ku notification -> mudhal
  // hero accept pannaraaro avarukku mattum -> matha heros-kitta maraiyum.
  //
  // The last two steps needed NO new code: acceptServiceRequest() below
  // is already an atomic RTDB transaction where exactly one hero can
  // win, and it already sweep-clears every other hero's ping node on
  // accept. What was missing was only the trigger — the seller had no
  // way to say "now".

  /// Seller kitchen stages. Deliberately a separate axis from `status`,
  /// which remains owned by the hero/admin dispatch state machine.
  static const String kSellerStageNew = 'new';
  static const String kSellerStageAccepted = 'accepted';
  static const String kSellerStagePreparing = 'preparing';
  static const String kSellerStageReady = 'ready';
  static const String kSellerStageDeliveryRequested = 'delivery_requested';

  /// Moves the seller's own kitchen stage forward. Writes ONLY the three
  /// `sellerStage`/`sellerStageAt`/`updatedAt` fields on the request doc
  /// (firestore.rules' seller clause permits exactly those — adding any
  /// other field there will make the whole update permission-denied),
  /// plus — on the genuine first new->accepted transition — the ₹5
  /// platform usage fee debit and its matching ledger entry.
  ///
  /// FIX (seller-earnings audit, Phase 1 — double-debit risk): this used
  /// to be a plain WriteBatch that charged the fee unconditionally
  /// whenever `stage == 'accepted'`, with the ONLY protection against a
  /// duplicate charge being `_busyRequestIds` — in-memory widget state
  /// on the seller dashboard, gone the instant the app is killed or
  /// crashes mid-request. Now a real Firestore Transaction: reads the
  /// request's CURRENT sellerStage first, and only debits when it isn't
  /// already 'accepted' (or later). Firestore auto-retries a transaction
  /// on write conflict with fresh data, so even two near-simultaneous
  /// calls for the same order are safe — only the one that first
  /// observes the pre-accept stage ever charges the fee. The ledger
  /// entry's fixed id (`${requestId}_fee`) is a second, independent
  /// idempotency layer enforced by firestore.rules itself (no `update`
  /// rule exists for wallet_transactions, so a second create attempt at
  /// the same id is rejected outright regardless of this Dart guard).
  Future<void> advanceSellerStage(String requestId, String stage, {String? sellerId}) async {
    final reqRef = FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(reqRef);
      final currentStage = snap.data()?['sellerStage'] as String?;

      tx.update(reqRef, {
        'sellerStage': stage,
        'sellerStageAt': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
      });

      if (stage == kSellerStageAccepted &&
          sellerId != null &&
          currentStage != kSellerStageAccepted) {
        final sellerRef =
            FirebaseFirestore.instance.collection('sellers').doc(sellerId);
        tx.update(sellerRef, {
          'walletBalance': FieldValue.increment(-5.0),
          // Lifetime running total (seller-earnings audit, Phase 2 —
          // Earnings screen's "Total Platform Fees" metric card). Purely
          // additive bookkeeping alongside the real debit above — the
          // per-transaction ledger entry below is still the source of
          // truth for auditability; this is just a cheap pre-summed
          // total so the Earnings screen doesn't need to sum the whole
          // ledger just to show one number.
          'totalFeesDeducted': FieldValue.increment(5.0),
          'updatedAt': FieldValue.serverTimestamp(),
        });
        tx.set(
          sellerRef.collection('wallet_transactions').doc('${requestId}_fee'),
          {
            'requestId': requestId,
            'sellerId': sellerId,
            'amount': -5.0,
            'type': 'platform_fee',
            'createdAt': FieldValue.serverTimestamp(),
          },
        );
      }
    });

    // 1GB RTDB budget cleanup safety net: the seller_pings/ node this
    // order created (see createServiceRequest) is normally deleted the
    // instant main_seller.dart's listener reads it, but a seller can
    // reach "Accept Order" through means that never triggered that read
    // (e.g. notifications permission was denied, or the listener hadn't
    // attached yet). The order has definitely been seen by the time any
    // stage advances, so it's always safe to sweep the ping here too.
    if (sellerId != null) {
      unawaited(
        rtdb.FirebaseDatabase.instance
            .ref('seller_pings/$sellerId/$requestId')
            .remove()
            .catchError((Object e) {
          debugPrint('[ServiceRequestService] seller_pings cleanup failed (non-fatal): $e');
        }),
      );
    }
  }

  /// Fires the held-back hero broadcast for a deferred order — the
  /// seller's "Book Delivery Partner" button.
  ///
  /// Returns false if there was nothing to broadcast (node already gone,
  /// already pinging, or already accepted by a hero), so the caller can
  /// avoid double-pinging when a seller taps twice.
  Future<bool> requestDeliveryBroadcast(String requestId) async {
    final nodeRef = rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId');
    final snap = await nodeRef.get();
    if (!snap.exists || snap.value is! Map) return false;

    final node = Map<String, dynamic>.from(snap.value! as Map);
    final status = node['status'] as String? ?? '';

    // FIX (Task 1 — "Retry Finding Delivery Partner"): a request still
    // parked in the holding state may always be released, same as
    // before. NEW: a request already 'pinging' may ALSO be released if
    // its previous broadcast's pingExpiresAt has already passed — no
    // hero could still legitimately claim an expired ping (a hero's own
    // client discards one past pingExpiresAt on sight, same check as
    // main_hero.dart's global ping listener), so re-firing is safe and
    // is exactly what lets the seller's "Retry Finding Delivery Partner"
    // button (seller_dashboard_screen.dart) actually work instead of
    // permanently no-op'ing once the first attempt goes stale. A request
    // that's 'pinging' and NOT yet expired, or already claimed by a
    // hero, is correctly still refused — guards the double-tap case AND
    // the case where an admin already dispatched this order by hand.
    final pingExpiresAtExisting = (node['pingExpiresAt'] as num?)?.toInt();
    final isExpiredPinging = status == 'pinging' &&
        pingExpiresAtExisting != null &&
        pingExpiresAtExisting > 0 &&
        DateTime.now().toUtc().millisecondsSinceEpoch > pingExpiresAtExisting;
    if (status != 'awaiting_seller' && !isExpiredPinging) return false;

    // Expiry is stamped NOW, not at order time — this is the whole point
    // of deferring (see the pingExpiresAt comment in createServiceRequest).
    final pingExpiresAt = DateTime.now().toUtc().millisecondsSinceEpoch +
        kServiceRequestPingExpirySeconds * 1000;

    await nodeRef.update({
      'status': 'pinging',
      'pingExpiresAt': pingExpiresAt,
    });

    await _broadcastToEligibleHeroes(
      requestId: requestId,
      requestType: (node['requestType'] as String?) ?? '',
      customerName: (node['customerName'] as String?) ?? 'Customer',
      customerPhone: (node['customerPhone'] as String?) ?? '',
      details: node['details'] is Map
          ? Map<String, dynamic>.from(node['details'] as Map)
          : <String, dynamic>{},
      pingExpiresAt: pingExpiresAt,
      requestCity: (node['city'] as String?) ?? kDefaultCity,
    );
    return true;
  }

  /// Broadcasts a ping to every hero currently online AND available IN
  /// THE SAME CITY as the request. Reuses the existing bike-taxi/parcel
  /// hero pool — no category filtering, since this is not a new hero
  /// recruitment. Multi-city (Plan 3): previously pinged every online
  /// hero nationwide with zero geographic filter — a real gap once more
  /// than one city shares this same online_heroes RTDB node.
  Future<void> _broadcastToEligibleHeroes({
    required String requestId,
    required String requestType,
    required String customerName,
    required String customerPhone,
    required Map<String, dynamic> details,
    required int pingExpiresAt,
    required String requestCity,
    String? requiredSkill,
    double? customerLat,
    double? customerLng,
  }) async {
    final snap =
        await rtdb.FirebaseDatabase.instance.ref('online_heroes').get();
    if (!snap.exists || snap.value is! Map) return;

    // SKILL DISPATCH (Aug 29 2026). Both conditions are required before
    // the distance test switches on: a skill with no customer location
    // must still reach every matching hero in the city rather than
    // silently reaching nobody, because a request that pings zero heroes
    // is indistinguishable, to the customer, from a broken app.
    final skillKey = (requiredSkill ?? '').trim().toLowerCase();
    final isSkillDispatch = skillKey.isNotEmpty;
    final applyRadius =
        isSkillDispatch && customerLat != null && customerLng != null;

    final heroes = Map<dynamic, dynamic>.from(snap.value! as Map);
    final futures = <Future<void>>[];

    heroes.forEach((heroId, heroDataRaw) {
      if (heroDataRaw is! Map) return;
      final heroData = Map<String, dynamic>.from(heroDataRaw);

      // FIX (Aug 11 2026 — presence-semantics mismatch found while
      // auditing "hero PWA never receives service requests"): this read
      // `(heroData['isAvailable'] as bool?) ?? false`, i.e. a hero whose
      // online_heroes node has no isAvailable key at all was treated as
      // UNAVAILABLE and silently skipped.
      //
      // The taxi dispatcher (ride_search_screen._fetchNearbyHeroes) does
      // the opposite for the same node: `if (isAvailable == false)
      // continue;` — only an EXPLICIT false excludes a hero. So the two
      // pipelines disagreed about the same presence record, and a node
      // written by any path that omits the key (or a partial/legacy
      // node) would keep receiving ride pings while never receiving a
      // single service-request ping. Presence has ONE meaning; both
      // readers must agree on it. Matched to the taxi semantics.
      final isAvailable = heroData['isAvailable'] as bool?;
      if (isAvailable == false) return;

      final heroCity = (heroData['city'] as String?)?.trim().toLowerCase().isNotEmpty ?? false
          ? (heroData['city'] as String).trim().toLowerCase()
          : kDefaultCity;
      if (heroCity != requestCity) return;

      // ── PER-HERO SERVICE ACCESS (Aug 17 2026) ────────────────────
      // This method's own doc comment above used to state, accurately,
      // that it did "no category filtering" — every online hero in the
      // city was pinged for hero bookings, grocery runs, food orders and
      // custom orders alike, with no way for an admin to say a
      // particular hero should not be getting a particular kind of job.
      // That is exactly what Nizam asked for control over.
      //
      // serviceKeyForRequestType() returns null for any requestType we
      // do not gate, and in that case we deliberately do NOT filter —
      // an unrecognised type must never be silently treated as denied,
      // or adding a new requestType later would quietly stop dispatching
      // to everyone.
      final serviceKey = serviceKeyForRequestType(requestType);
      if (serviceKey != null && !isServiceAllowed(heroData, serviceKey)) {
        return;
      }

      // ── SKILL MATCH + 5 KM RADIUS (Aug 29 2026) ──────────────────
      // Guarded by isSkillDispatch, so this whole block is inert for
      // every requestType that existed before skill heroes — rides,
      // food, grocery, parcel and custom orders reach exactly the same
      // heroes they reached yesterday.
      //
      // The skill test uses heroHasSkill(), which defaults to FALSE for
      // a hero with no skills recorded. That is the point: a plumbing
      // job must reach plumbers, not every hero who happens to be
      // online. See hero_skill_catalog.dart for why this default is the
      // opposite of isServiceAllowed's.
      if (isSkillDispatch) {
        if (!heroHasSkill(heroData, skillKey)) return;

        if (applyRadius) {
          final heroLat = (heroData['lat'] as num?)?.toDouble() ??
              (heroData['latitude'] as num?)?.toDouble();
          final heroLng = (heroData['lng'] as num?)?.toDouble() ??
              (heroData['longitude'] as num?)?.toDouble();
          // A hero whose presence node carries no usable position is
          // SKIPPED rather than included. Including them would send a
          // job to someone who may be 40km away, which is the failure
          // the radius exists to prevent; the presence writer stamps
          // lat/lng on every write, so a missing one means stale.
          if (heroLat == null || heroLng == null) return;
          final distanceKm = Geolocator.distanceBetween(
                customerLat, customerLng, heroLat, heroLng,
              ) /
              1000.0;
          if (distanceKm > kSkillDispatchRadiusKm) return;
        }
      }

      futures.add(
        rtdb.FirebaseDatabase.instance
            .ref('hero_service_pings/$heroId/$requestId')
            .set({
          'requestId': requestId,
          'requestType': requestType,
          'customerName': customerName,
          'customerPhone': customerPhone,
          'details': details,
          'pingExpiresAt': pingExpiresAt,
          'status': 'pinging',
        }),
      );
    });

    await Future.wait(futures);
  }

  /// Atomic accept — mirrors hero_home_screen.dart's `_acceptRide` exactly.
  /// Only one hero can win the race; the RTDB transaction is the single
  /// source of truth for "who got it first."
  Future<bool> acceptServiceRequest({
    required String requestId,
    required String heroId,
    required String heroName,
    required String heroPhone,
  }) async {
    final requestRef = rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId');

    final transResult = await requestRef.runTransaction((currentData) {
      if (currentData == null) {
        // Optimistic local cache run. NEVER abort here — the server
        // will re-run this against the real data.
        return rtdb.Transaction.success({
          'status': 'accepted',
          'acceptedHeroId': heroId,
          'acceptedHeroName': heroName,
          'acceptedHeroPhone': heroPhone,
        });
      }

      final data = Map<String, dynamic>.from(currentData as Map);
      final status = data['status'] as String? ?? '';

      if (status == 'accepted' || status == 'cancelled' || status == 'timeout') {
        return rtdb.Transaction.abort();
      }

      data['status'] = 'accepted';
      data['acceptedHeroId'] = heroId;
      data['acceptedHeroName'] = heroName;
      data['acceptedHeroPhone'] = heroPhone;
      return rtdb.Transaction.success(data);
    });

    if (!transResult.committed) {
      // Another hero won the race — clean up our own ping, no error shown.
      await rtdb.FirebaseDatabase.instance
          .ref('hero_service_pings/$heroId/$requestId')
          .remove();
      return false;
    }

    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': 'hero_assigned',
      'assignedHeroId': heroId,
      'assignedHeroName': heroName,
      'assignedHeroPhone': heroPhone,
      'assignmentMethod': 'broadcast',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Start the BILLABLE clock here — the moment this hero actually won
    // the job. Everything before this (being online, receiving pings,
    // waiting) is free (Aug 17 2026 — Nizam: "summa iruntha bill
    // agakudathu"). It is stopped when the task completes, is cancelled,
    // or is released.
    HeroUsageAccumulatorService().startBillableWork();

    // Winner's own ping is always removed (was already the case).
    await rtdb.FirebaseDatabase.instance
        .ref('hero_service_pings/$heroId/$requestId')
        .remove();

    // Sweep-clear every other online hero's ping node for this requestId.
    await _sweepClearPings(requestId, excludeHeroId: heroId);

    return true;
  }

  // FIX (Phase 4b — WhatsApp/Uber transient model for service_requests,
  // mirrors Phase 4a's active_rides/{rideDocId} migration for rides):
  // reads back whatever transient timeline timestamps
  // active_service_requests/{requestId} has accumulated (inProgressAt /
  // nearingCompletionAt, written by advanceStatus() below), converts
  // them from RTDB epoch-millis to Firestore Timestamps for the
  // permanent record, and deletes the RTDB node — called from every
  // path that writes a terminal Firestore status (completed).
  // Best-effort: a read/remove failure here must never block the
  // Firestore completion write itself, so failures are swallowed after
  // logging and simply mean the timeline fields are omitted / the RTDB
  // node is cleaned up on a later best-effort pass instead.
  Future<Map<String, dynamic>> _foldAndRemoveActiveServiceRequestNode(
    String requestId,
  ) async {
    final activeRef =
        rtdb.FirebaseDatabase.instance.ref('active_service_requests/$requestId');
    Map<dynamic, dynamic>? rtdbData;
    try {
      final snap = await activeRef.get();
      if (snap.exists && snap.value is Map) {
        rtdbData = Map<dynamic, dynamic>.from(snap.value! as Map);
      }
    } catch (e) {
      debugPrint('[ServiceRequestService] active_service_requests read failed (non-fatal): $e');
    }

    final inProgressAtMs = rtdbData?['in_progressAt'] as int?;
    final nearingCompletionAtMs = rtdbData?['nearing_completionAt'] as int?;

    unawaited(activeRef.remove());

    return {
      if (inProgressAtMs != null)
        'inProgressAt': Timestamp.fromMillisecondsSinceEpoch(inProgressAtMs),
      if (nearingCompletionAtMs != null)
        'nearingCompletionAt':
            Timestamp.fromMillisecondsSinceEpoch(nearingCompletionAtMs),
    };
  }

  /// Completes a service_requests doc AND, in the SAME Firestore
  /// Transaction, credits the owning seller's `pendingPayouts` for the
  /// order's value — shared by advanceStatus('completed') and
  /// completeWithFinalAmount() below (seller-earnings audit, Phase 1).
  ///
  /// Before this, NOTHING in the codebase ever credited a seller for a
  /// completed order — `pendingPayouts`/`totalSettled` were read on the
  /// dashboard's Payouts card but had no writer anywhere; the only
  /// wallet write that existed was the ₹5 accept-time debit. Sellers
  /// were only ever charged, never paid.
  ///
  /// Idempotency (two independent layers, so a retry after a
  /// successful-but-unacknowledged prior attempt — app killed right
  /// after commit, network drop on the response, etc. — can never
  /// double-credit):
  ///  1. This transaction reads `earningsCredited` first; if it's
  ///     already true, the credit/ledger writes are skipped entirely
  ///     (only the terminal status fields are written). Firestore
  ///     auto-retries the whole transaction on write conflict with a
  ///     fresh read, so two near-simultaneous completion calls for the
  ///     same order are safe.
  ///  2. firestore.rules independently enforces the same thing: the
  ///     seller-doc credit write and the ledger-doc create both require
  ///     (via a `get()` on this exact request doc) that
  ///     `earningsCredited != true` in the PRE-transaction committed
  ///     state — even a client that skipped/bypassed layer 1 gets
  ///     rejected. The ledger doc's fixed id (`${requestId}_credit`)
  ///     adds a third, structural guarantee: Firestore treats a second
  ///     `.set()` on an existing doc id as an `update`, and no `update`
  ///     rule exists for `wallet_transactions` — a duplicate can never
  ///     successfully write regardless of any application-level bug.
  ///
  /// Credit amount: prefers an explicit `finalAmount` (from
  /// completeWithFinalAmount's hero-entered bill); falls back to the
  /// request doc's own `finalAmount` if already set, then to
  /// `details.subtotal` (the original order value) for the
  /// admin-manual-completion path via advanceStatus(), which carries no
  /// amount parameter at all. A non-positive resolved amount credits
  /// nothing (defensive — avoids writing a zero/garbage ledger entry).
  ///
  /// Non-food requestTypes (hero_booking/custom_order/grocery_order —
  /// anything with no `details.sellerId`) simply have no seller to
  /// credit; only the terminal status fields are written for those,
  /// unchanged from before this fix.
  Future<void> _completeAndCreditSeller(
    String requestId, {
    required Map<String, dynamic> requestFields,
  }) async {
    final reqRef =
        FirebaseFirestore.instance.collection('service_requests').doc(requestId);

    await FirebaseFirestore.instance.runTransaction((tx) async {
      final snap = await tx.get(reqRef);
      final data = snap.data();
      if (data == null) {
        // Doc gone (e.g. concurrently cancelled/deleted) — nothing left
        // to complete or credit.
        return;
      }

      final details = data['details'] as Map<String, dynamic>?;
      final sellerId = details?['sellerId'] as String?;
      final creditAmount = (requestFields['finalAmount'] as num?)?.toDouble() ??
          (data['finalAmount'] as num?)?.toDouble() ??
          (details?['subtotal'] as num?)?.toDouble() ??
          0.0;
      final alreadyCredited = data['earningsCredited'] == true;
      final shouldCredit = !alreadyCredited &&
          sellerId != null &&
          sellerId.isNotEmpty &&
          creditAmount > 0;

      // Single update call on this document — Firestore transactions
      // reject a second write to the same doc reference within one
      // transaction, so `earningsCredited` is folded into the same map
      // as the caller's terminal-status fields rather than a separate
      // tx.update() call.
      tx.update(reqRef, {
        ...requestFields,
        if (shouldCredit) 'earningsCredited': true,
      });

      if (!shouldCredit) return;

      final sellerRef =
          FirebaseFirestore.instance.collection('sellers').doc(sellerId);
      tx.update(sellerRef, {
        'pendingPayouts': FieldValue.increment(creditAmount),
        'lastCreditedRequestId': requestId,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      tx.set(
        sellerRef.collection('wallet_transactions').doc('${requestId}_credit'),
        {
          'requestId': requestId,
          'sellerId': sellerId,
          'amount': creditAmount,
          'type': 'order_credit',
          'createdAt': FieldValue.serverTimestamp(),
        },
      );
    });
  }

  /// Hero or admin status-advance. Both paths write the exact same field
  /// on the exact same document — the customer tracking screen cannot
  /// tell (and does not need to know) which side triggered the update.
  ///
  /// FIX (Phase 4b — CTO "WhatsApp/Uber transient model" mandate,
  /// mirrors what Phase 4a already did for rides via
  /// active_rides/{rideDocId}): the mid-lifecycle transitions
  /// ('in_progress', 'nearing_completion') used to hit Firestore on
  /// every tap — exactly the kind of rapid, non-billing-critical write
  /// the CTO wants OFF Firestore. Those two now write ONLY to
  /// active_service_requests/{requestId} in RTDB (already created by
  /// createServiceRequest() for the pre-accept broadcast phase — this
  /// extends its lifecycle instead of abandoning it after
  /// hero_assigned). Firestore is only touched again for a genuinely
  /// terminal state: 'completed' here folds the RTDB timeline back in
  /// and wipes the node; hero_assigned is kept as a defensive
  /// Firestore-write fallback for any legacy caller, since the real
  /// hero_assigned write already happens in acceptServiceRequest() /
  /// adminAssignHero() and should never actually reach this branch in
  /// normal operation.
  Future<void> advanceStatus(String requestId, String newStatus) async {
    assert(kServiceRequestStatuses.contains(newStatus));

    if (newStatus == 'completed') {
      final timelineFields =
          await _foldAndRemoveActiveServiceRequestNode(requestId);
      await _completeAndCreditSeller(requestId, requestFields: {
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
        ...timelineFields,
      });
      return;
    }

    if (newStatus == 'in_progress' || newStatus == 'nearing_completion') {
      // FIX (per Nizam's bug report — "hero task ah start pannamudila"):
      // this used to write ONLY to RTDB active_service_requests, never
      // touching the Firestore service_requests doc's `status` field —
      // but every customer-facing read (streamRequest() above,
      // MyOrdersScreen, ServiceRequestTrackingScreen) reads Firestore,
      // not RTDB. So a hero tapping "Start" would silently succeed on
      // the RTDB side while the customer's screen stayed frozen on
      // 'hero_assigned' forever — from the hero's point of view this
      // looked exactly like "couldn't start the task" even though no
      // actual error occurred. Now writes both, matching the
      // Firestore-only branch below for every OTHER status.
      await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(requestId)
          .update({
        'status': newStatus,
        'updatedAt': FieldValue.serverTimestamp(),
      });
      await rtdb.FirebaseDatabase.instance
          .ref('active_service_requests/$requestId')
          .update({
        'status': newStatus,
        '${newStatus}At': rtdb.ServerValue.timestamp,
        'updatedAt': rtdb.ServerValue.timestamp,
      });
      return;
    }

    // hero_assigned / admin_review / pending — legacy/defensive path,
    // unchanged Firestore-only behavior.
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': newStatus,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  // ── Unified Hero Task System: money fields ──────────────────────
  // Generic 'estimatedAmount'/'finalAmount' fields (not fare-specific
  // names) since these apply across all 4 non-ride request types
  // (hero_booking, custom_order, custom_food_order, grocery_order),
  // none of which share a measurable basis (distance/weight/etc.) for
  // automatic calculation the way ride fares do — manual entry only,
  // by design (confirmed decision: a calculated-formula system is a
  // possible future per-category enhancement, not in scope now).

  /// Sets the estimated amount for a service request. Called by the
  /// hero right before they advance to 'in_progress' (gates the
  /// "Start" action — see _ServiceRequestStatusCard in
  /// hero_home_screen.dart), or optionally pre-filled by an admin at
  /// manual-assignment time. Does not itself change `status`.
  Future<void> setEstimatedAmount(String requestId, double amount) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'estimatedAmount': amount,
      // Reset to null (not-yet-responded) on every write — covers both
      // the hero's first entry and a re-entry after the customer
      // rejects (see rejectEstimate()), so a revised estimate always
      // needs a fresh approval rather than inheriting a stale decision.
      'estimateApprovedByCustomer': null,
      'estimateRespondedAt': null,
      // Clears any pending customer counter-offer — the hero has just
      // responded to it with a fresh number, so it shouldn't keep
      // showing as "still pending" once this new estimate is out.
      'customerCounterOffer': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Customer-side: approves the hero's entered estimate. This is what
  /// unblocks the hero's "Start" action — see
  /// _ServiceRequestStatusCard._advanceTo() in hero_home_screen.dart,
  /// which waits on `estimateApprovedByCustomer == true` before it will
  /// call advanceStatus('in_progress').
  Future<void> approveEstimate(String requestId) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'estimateApprovedByCustomer': true,
      'estimateRespondedAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Customer-side: rejects the hero's entered estimate. Deliberately
  /// does NOT touch `status` (no admin_review routing, no
  /// cancellation) — clears `estimatedAmount` back to null so the
  /// hero's UI drops back into "enter an estimate" mode and can submit
  /// a revised number, which re-triggers the same approval wait via
  /// setEstimatedAmount()'s reset above. A simple negotiate loop, no
  /// cap on rejection count (can be added later if repeated rejection
  /// turns out to be a real problem in practice).
  // FIX (per Nizam's request — Accept/Reject renamed to
  // Accept/Negotiate): unchanged reset behavior, plus an optional
  // customer counter-offer amount so the hero sees what price the
  // customer actually wants instead of just an unexplained blank
  // "enter an estimate again" prompt. Kept the same method name since
  // every existing behavior (reset estimate, let hero resend) is still
  // exactly what "Negotiate" does under the hood.
  Future<void> rejectEstimate(String requestId, {double? counterOffer}) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'estimatedAmount': null,
      'estimateApprovedByCustomer': null,
      'estimateRespondedAt': null,
      'customerCounterOffer': counterOffer,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Completes a service request with a final bill amount in one
  /// write — mirrors the ride flow's finalFare/actualFare pattern,
  /// generalized to a single generic field since these categories
  /// have no tip/base-fare split concept. Hero enters this at "Mark
  /// Complete", pre-filled with the estimate but adjustable.
  ///
  /// Also sets paymentStatus: 'pending_collection' — mirrors the ride
  /// flow's completed-but-unpaid state (rides collection's same
  /// field/value), so the customer's payment screen and the hero's
  /// "mark payment received" action both have a status to key off.
  Future<void> completeWithFinalAmount(
    String requestId,
    double finalAmount,
  ) async {
    // FIX (Phase 4b): this is the REAL terminal write for the hero-driven
    // completion flow (advanceStatus('completed') is only reachable from
    // admin's no-amount-gate manual control) — so this is where the
    // active_service_requests RTDB timeline needs to be folded into the
    // permanent Firestore record and the RTDB node wiped, same as
    // advanceStatus()'s 'completed' branch above.
    final timelineFields =
        await _foldAndRemoveActiveServiceRequestNode(requestId);
    await _completeAndCreditSeller(requestId, requestFields: {
      'finalAmount': finalAmount,
      'status': 'completed',
      'paymentStatus': 'pending_collection',
      'updatedAt': FieldValue.serverTimestamp(),
      ...timelineFields,
    });
  }

  /// Customer-side: marks a completed service request as paid. This is
  /// intentionally NOT a real payment-gateway integration — same scope
  /// boundary as the rest of the Unified Hero Task System v1 (manual
  /// amount entry, no automatic calculation). Records which method the
  /// customer selected for the hero's own records.
  Future<void> markServiceRequestPaid(
    String requestId, {
    required String method,
  }) async {
    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'paymentStatus': 'paid',
      'paymentMethod': method,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Hero-side: hero confirms cash/UPI payment was actually collected.
  ///
  /// FIX (per Nizam's explicit, later request — reversing the earlier
  /// "customer confirms" design below): the previous version wrote only
  /// an INTERIM status and made the CUSTOMER'S own confirmation the
  /// real terminal 'paid' write — but that let a customer tap "I paid"
  /// themselves the instant the task completed, closing the task and
  /// unlocking their own rating screen WITHOUT the hero ever actually
  /// receiving payment ("hero kita pay pannama avare task close
  /// pannikuramari iruku"). Nizam explicitly decided the opposite
  /// trust direction is the correct one for this business: only the
  /// HERO physically holding the cash/confirming the UPI transfer can
  /// know payment genuinely happened, so this now IS the terminal
  /// write — sets the real 'paid' status directly, which is what
  /// unlocks the customer's rating prompt. The customer-side
  /// self-attestation buttons in service_request_payment_screen.dart
  /// were removed to match (see that file's comments). Does not change
  /// `status` (already 'completed') — only paymentStatus/paidAt.
  Future<void> markServiceRequestPaymentReceived(
    String requestId, {
    String method = 'cash',
  }) async {
    final requestRef =
        FirebaseFirestore.instance.collection('service_requests').doc(requestId);
    await requestRef.update({
      'paymentStatus': 'paid',
      'paymentMethod': method,
      'paidAt': FieldValue.serverTimestamp(),
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // FIX (Aug 11 2026 — Nizam's "Phase 1" revenue-leak audit fix):
    // this method used to ONLY write payment status onto the
    // service_requests doc — it never charged the platform's infra
    // usage fee at all. hero_ride_screen.dart's taxi flow always called
    // HeroWalletService().flushUsageCost() at this exact point (payment
    // confirmed / task settled); this generic path (which covers ALL
    // FOUR non-ride categories — Hero Booking, Custom Order, Custom Food
    // Order, Grocery Order, per this file's header comment) never did,
    // so completing any of those four task types cost the platform real
    // Firestore/RTDB dispatch+completion load with ZERO fee recovery —
    // a straightforward, structural revenue leak, not an edge case.
    // Mirrors hero_ride_screen.dart's flush exactly: reads the
    // in-memory accumulator (minutes online + this one task), writes a
    // single batched debit to hero_wallets/{heroId}, non-fatal on
    // failure (a flush error must never block the hero from closing out
    // a task they already collected payment for).
    try {
      final requestSnap = await requestRef.get();
      final data = requestSnap.data();
      final heroId = (data?['assignedHeroId'] as String?) ??
          (data?['acceptedHeroId'] as String?);
      if (heroId != null && heroId.isNotEmpty) {
        final heroName = (data?['assignedHeroName'] as String?) ??
            (data?['acceptedHeroName'] as String?);
        HeroUsageAccumulatorService().recordRideHandled();
        // Close the billable-work clock before consuming it — the task
        // is finished, so the meter must stop here and not keep running
        // into the hero's idle waiting time (Aug 17 2026 billing fix).
        HeroUsageAccumulatorService().stopBillableWork();
        final activeMinutes =
            HeroUsageAccumulatorService().consumeBillableMinutes();
        final ridesHandled =
            HeroUsageAccumulatorService().consumeRidesHandled();
        await HeroWalletService().flushUsageCost(
          heroId: heroId,
          heroName: heroName,
          activeMinutes: activeMinutes,
          ridesHandled: ridesHandled,
        );
      } else {
        debugPrint(
          '[ServiceRequestService] markServiceRequestPaymentReceived: no '
          'assignedHeroId/acceptedHeroId on $requestId — usage fee not '
          'flushed (nothing to attribute it to).',
        );
      }
    } catch (e) {
      debugPrint(
        '[ServiceRequestService] Wallet usage-fee flush failed (non-fatal): $e',
      );
    }
  }

  Future<void> _sweepClearPings(String requestId, {String? excludeHeroId}) async {
    try {
      final onlineSnap =
          await rtdb.FirebaseDatabase.instance.ref('online_heroes').get();
      if (onlineSnap.exists && onlineSnap.value is Map) {
        final heroes = Map<dynamic, dynamic>.from(onlineSnap.value! as Map);
        final sweepFutures = <Future<void>>[];
        for (final otherHeroId in heroes.keys) {
          if (excludeHeroId != null && otherHeroId == excludeHeroId) continue;
          sweepFutures.add(
            rtdb.FirebaseDatabase.instance
                .ref('hero_service_pings/$otherHeroId/$requestId')
                .remove(),
          );
        }
        await Future.wait(sweepFutures);
      }
    } catch (e) {
      debugPrint('[ServiceRequestService] Ping sweep-clear failed: $e');
    }
  }

  /// Admin manually assigns a hero after confirming by phone — no
  /// broadcast ping needed since the admin already coordinated directly.
  ///
  /// FIX (CTO mandate — FCM Data Push Layer 2, Task 2): this used to
  /// ONLY write Firestore + `active_service_requests` — it never wrote
  /// a `hero_service_pings/{heroId}/{requestId}` node at all, which
  /// means the hero's already-built, already-proven accept-dialog UI
  /// (driven entirely by that RTDB path — see hero_home_screen.dart's
  /// _listenForServicePings) never fired for an admin-manual
  /// assignment. The hero would only ever find out via passively
  /// noticing the task appear in their own list — no dialog, no
  /// ringtone, no lock-screen alert, and (until this change) no FCM
  /// push either, since the send-side Cloud Function is triggered off
  /// this exact ping write. Writing a single-target ping here closes
  /// that gap and reuses the same proven mechanism every other
  /// dispatch path already relies on.
  Future<void> adminAssignHero({
    required String requestId,
    required String heroId,
    required String heroName,
    required String heroPhone,
  }) async {
    final requestDoc = await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .get();
    final requestData = requestDoc.data();

    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': 'hero_assigned',
      'assignedHeroId': heroId,
      'assignedHeroName': heroName,
      'assignedHeroPhone': heroPhone,
      'assignmentMethod': 'admin_manual',
      'updatedAt': FieldValue.serverTimestamp(),
    });

    // Also close out the RTDB broadcast state so a hero whose ping
    // hasn't expired yet can't win a concurrent atomic-accept race
    // against this manual assignment — acceptServiceRequest's
    // transaction aborts on status == 'accepted'.
    await rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId')
        .update({
      'status': 'accepted',
      'acceptedHeroId': heroId,
      'acceptedHeroName': heroName,
      'acceptedHeroPhone': heroPhone,
    });

    // See method-level doc comment above — reuses the exact ping shape
    // _broadcastToEligibleHeroes() writes, with a generous window since
    // this is a single specific hero the admin already confirmed by
    // phone, not a race against other heroes.
    await rtdb.FirebaseDatabase.instance
        .ref('hero_service_pings/$heroId/$requestId')
        .set({
      'requestId': requestId,
      'requestType': requestData?['requestType'] as String? ?? '',
      'customerName': requestData?['customerName'] as String? ?? '',
      'customerPhone': requestData?['customerPhone'] as String? ?? '',
      'details': requestData?['details'] ?? const <String, dynamic>{},
      'pingExpiresAt': DateTime.now().toUtc().millisecondsSinceEpoch +
          kServiceRequestPingExpirySeconds * 1000,
      // Matches _broadcastToEligibleHeroes()'s ping shape exactly —
      // nothing reads this field for branching logic today, but
      // keeping the value consistent avoids introducing a second,
      // unexplained status vocabulary for the same RTDB node shape.
      'status': 'pinging',
    });
  }

  /// Cancels a service request — customer- or admin-initiated. Per
  /// product decision, cancelled requests are FULLY DELETED from
  /// Firestore (not soft-deleted with a 'cancelled' status) to
  /// guarantee zero stale-data risk in hero/admin views. Eligibility
  /// (which statuses may be cancelled, by whom) is enforced by the
  /// CALLER — this method does not re-check status, since the
  /// customer-side and admin-side allowed-stage sets differ.
  ///
  /// Before deleting, best-effort marks the RTDB
  /// active_service_requests/{id} node's status as 'cancelled'. This
  /// matters because acceptServiceRequest()'s transaction already has
  /// a dormant guard — `if (status == 'accepted' || status ==
  /// 'cancelled' || status == 'timeout') return Transaction.abort()`
  /// — that aborts a hero's in-flight accept attempt when it sees
  /// this status. Deleting that RTDB node instead (rather than
  /// updating its status) would make the transaction's `currentData
  /// == null` branch treat it as a fresh "optimistic success" write,
  /// which could let a hero accidentally revive a task that was just
  /// cancelled. Updating first closes that race; the delete below
  /// only removes the Firestore source-of-truth document.
  // FIX (Cancellation Reason Analytics, Aug 11 2026 — Nizam: "we are
  // losing valuable business data on WHY customers cancel"): the spec
  // asks for a `cancellationReason` field ON the cancelled document,
  // but service_requests are DELETED here, not status-set (see the
  // doc comment above — deliberate, to close the accept-race with
  // acceptServiceRequest()'s transaction guard). A field on a doc
  // that's about to vanish can't be queried for analytics afterward,
  // so [reason] (when provided) is instead written to a small
  // `cancellation_analytics` doc BEFORE the delete — same requestId,
  // so it can still be joined back to whatever admin logs already
  // captured about the request. This is a deliberate, minimal
  // deviation from the literal spec wording to keep the existing
  // delete-based cancellation model (and the accept-race protection
  // it exists for) completely untouched.
  Future<void> cancelServiceRequest(String requestId, {String? reason}) async {
    try {
      final node = rtdb.FirebaseDatabase.instance.ref('active_service_requests/$requestId');
      await node.update({'status': 'cancelled'});
      // Delay to allow in-flight accept transactions to see the 'cancelled' status
      // and safely abort. Then completely remove the node to free RTDB storage.
      Future.delayed(const Duration(seconds: 15), () {
        node.remove().catchError((_) {});
      });
    } catch (e) {
      // Best-effort — the RTDB node may already be gone (hero accepted
      // and it was cleaned up, or it timed out) — proceed to delete
      // the Firestore doc regardless.
      debugPrint('[ServiceRequestService] RTDB cancel-mark failed (non-fatal): $e');
    }

    await _sweepClearPings(requestId);

    // FIX (Issue 3 — cancellation cleanup): _sweepClearPings above only
    // ever cleared hero_service_pings, never seller_pings. A deferred
    // catalog/custom-hotel order cancelled BEFORE the seller opened
    // their app (so main_seller.dart's listener never consumed it) or
    // advanced any kitchen stage (so advanceSellerStage's own cleanup
    // never ran) left its seller_pings/{sellerId}/{requestId} node
    // sitting in RTDB until its 48h expiry backstop — not an unbounded
    // leak, but no reason to wait 48h when we can sweep it right now.
    // Reads the doc once (needed for details.sellerId), reused below for
    // the existing analytics write instead of a second read.
    Map<String, dynamic>? requestData;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('service_requests')
          .doc(requestId)
          .get();
      requestData = snap.data();
      final details = requestData?['details'] as Map<String, dynamic>?;
      final sellerId = details?['sellerId'] as String?;
      if (sellerId != null && sellerId.isNotEmpty) {
        await rtdb.FirebaseDatabase.instance
            .ref('seller_pings/$sellerId/$requestId')
            .remove();
      }
    } catch (e) {
      // Best-effort — must never block the actual cancellation the
      // customer is waiting on.
      debugPrint('[ServiceRequestService] seller_pings cancel-sweep failed (non-fatal): $e');
    }

    if (reason != null && reason.trim().isNotEmpty) {
      try {
        await FirebaseFirestore.instance
            .collection('cancellation_analytics')
            .add({
          'requestId': requestId,
          'source': 'service_requests',
          'requestType': requestData?['requestType'],
          'customerId': requestData?['customerId'],
          'cancellationReason': reason,
          'cancelledAt': FieldValue.serverTimestamp(),
        });
      } catch (e) {
        // Best-effort — analytics must never block the actual
        // cancellation the customer is waiting on.
        debugPrint('[ServiceRequestService] cancellation_analytics write failed (non-fatal): $e');
      }
    }

    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .delete();
  }

  /// Hero-side "give this back" action for a task they accepted but no
  /// longer want to do — deliberately NOT the same thing as
  /// cancelServiceRequest() (which is customer/admin-initiated and
  /// deletes the doc entirely). A released task still needs doing, so
  /// it routes to 'admin_review' — the exact same status/query
  /// markTimeoutIfStillPending() uses — so it surfaces on
  /// admin_new_orders_screen.dart's "AWAITING ASSIGNMENT" section (and
  /// the admin_review-count badges) for a human to re-assign or call
  /// the customer, rather than silently re-entering the broadcast pool.
  /// Only sensible before the hero has actually started (see the
  /// 'Release Task' button's hero_assigned-only gating in
  /// hero_home_screen.dart) — clears the assignment and any
  /// not-yet-approved estimate so the request looks freshly
  /// admin-manageable again.
  Future<void> releaseServiceRequest(String requestId) async {
    try {
      final node = rtdb.FirebaseDatabase.instance.ref('active_service_requests/$requestId');
      await node.update({'status': 'timeout'});
      // Safely remove the node from RTDB after a short delay to free storage,
      // closing the abort window.
      Future.delayed(const Duration(seconds: 15), () {
        node.remove().catchError((_) {});
      });
    } catch (e) {
      debugPrint('[ServiceRequestService] RTDB release-mark failed (non-fatal): $e');
    }

    await _sweepClearPings(requestId);

    await FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .update({
      'status': 'admin_review',
      'assignedHeroId': null,
      'assignedHeroName': null,
      'assignedHeroPhone': null,
      'assignmentMethod': null,
      'estimatedAmount': null,
      'estimateApprovedByCustomer': null,
      'estimateRespondedAt': null,
      'updatedAt': FieldValue.serverTimestamp(),
    });
  }

  /// Called by the requesting screen ~90s after broadcast. If the
  /// request is still 'pending' (no hero accepted), routes it to the
  /// admin "New Orders" tab for manual follow-up.
  Future<void> markTimeoutIfStillPending(String requestId) async {
    final docRef =
        FirebaseFirestore.instance.collection('service_requests').doc(requestId);
    final doc = await docRef.get();
    if (!doc.exists) return;

    final status = doc.data()?['status'] as String? ?? '';
    if (status != 'pending') return; // Already progressed — nothing to do.

    await docRef.update({
      'status': 'admin_review',
      'updatedAt': FieldValue.serverTimestamp(),
    });
    await rtdb.FirebaseDatabase.instance
        .ref('active_service_requests/$requestId')
        .update({'status': 'timeout'});
  }
}
