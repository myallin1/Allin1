// ================================================================
// service_request_model.dart
//
// FIX (CTO mandate — Phase 3 Prep, "WhatsApp Offline Model"): there was
// NO model class for `service_requests` anywhere in this repo — every
// screen/service (service_request_service.dart, service_request_
// tracking_screen.dart, admin_new_orders_screen.dart, etc.) reads and
// writes this collection as raw `Map<String, dynamic>`. That's fine
// for a pure-Firestore app, but it's the wrong shape for the planned
// local-DB sync layer (Hive/Isar): those libraries need a concrete
// class with a safe fromJson/toJson pair, because a value read back
// from a LOCAL disk cache will never contain a real
// `cloud_firestore.Timestamp` object the way a live `DocumentSnapshot`
// does — it will be whatever plain JSON-safe type toJson() wrote
// (a String or an int), and a naive `as Timestamp` cast (the pattern
// used by every OTHER model in lib/models/ that touches Firestore —
// food_models.dart, hero_wallet_model.dart, task_completion_model.dart,
// user_wallet_model.dart) would throw the moment it's fed local data
// instead of a live snapshot.
//
// This model is the template going forward: dates are ALWAYS stored on
// the wire (toJson) as an ISO-8601 String, and fromJson accepts THREE
// input shapes for every date field — a real Firestore `Timestamp`
// (when constructed via fromFirestore/live snapshot), an ISO-8601
// `String` (when loaded back from a local Hive/Isar/disk cache that
// was itself populated by this class's own toJson), or an `int` epoch-
// millis value (defensive third fallback, in case a future local-DB
// layer stores raw millis instead of a String for compactness). This
// makes the SAME fromJson usable for both "just read live from
// Firestore" and "just read back from local disk" without needing two
// separate parsing paths.
//
// FIX (CTO mandate — Model Adoption, Phase 3): now consumed by
// service_request_service.dart's streamRequest()/streamCustomerRequests()
// and read directly (request.status, request.requestId, etc.) by
// service_request_tracking_screen.dart, my_orders_screen.dart, and
// delivery_challan_card.dart, instead of raw Map lookups.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';

/// Parses a Firestore/local-cache date value that could be any of:
/// a real [Timestamp] (live Firestore read), an ISO-8601 [String]
/// (round-tripped through this model's own [ServiceRequestModel.toJson]
/// into a local cache), or epoch-millis [int] (defensive fallback).
/// Returns null (never throws) if the value is missing or unparseable,
/// so a corrupt/partial local-cache record never crashes the app —
/// callers should treat a null date as "unknown," not as an error.
DateTime? parseFlexibleTimestamp(Object? value) {
  if (value == null) return null;
  if (value is Timestamp) return value.toDate();
  if (value is DateTime) return value;
  if (value is int) {
    try {
      return DateTime.fromMillisecondsSinceEpoch(value);
    } catch (_) {
      return null;
    }
  }
  if (value is String && value.isNotEmpty) {
    return DateTime.tryParse(value);
  }
  return null;
}

/// One line item inside a Quick Order form (see
/// lib/widgets/quick_order_line_items.dart) or a priced cart item
/// (custom_hotel_order / catalog_food_order shape) — this model
/// accepts either shape defensively so it can represent every
/// request type's `details['items']` without a separate class per
/// request type.
class ServiceRequestLineItem {
  final int? sNo;
  final String name;
  final String? qty;
  final num? quantity;
  final num? price;

  const ServiceRequestLineItem({
    this.sNo,
    required this.name,
    this.qty,
    this.quantity,
    this.price,
  });

  factory ServiceRequestLineItem.fromJson(Map<String, dynamic> json) {
    return ServiceRequestLineItem(
      sNo: json['sNo'] is num ? (json['sNo'] as num).toInt() : null,
      name: (json['name'] as String?)?.trim() ?? '',
      qty: (json['qty'] as String?)?.trim(),
      quantity: json['quantity'] is num ? json['quantity'] as num : null,
      price: json['price'] is num ? json['price'] as num : null,
    );
  }

  Map<String, dynamic> toJson() => {
        if (sNo != null) 'sNo': sNo,
        'name': name,
        if (qty != null) 'qty': qty,
        if (quantity != null) 'quantity': quantity,
        if (price != null) 'price': price,
      };
}

/// Model for a single `service_requests/{requestId}` document — covers
/// every requestType this app writes (grocery_order, custom_food_order,
/// catalog_food_order, custom_hotel_order, hero_booking, etc.) since
/// they all share the same collection/status-pipeline shape and only
/// differ in what's inside `details`. Rather than one subclass per
/// requestType (overkill for a Prep-phase model), `details` and
/// `items` are kept as flexible bags — `rawDetails` preserves
/// everything for round-tripping, `items` is a convenience parse of
/// the common `details['items']` line-item list when present.
class ServiceRequestModel {
  final String requestId;
  final String requestType;
  final String customerId;
  final String customerName;
  final String customerPhone;
  final String status;
  final String? assignedHeroId;
  final String? assignedHeroName;
  final String? assignedHeroPhone;
  final String? city;
  final List<ServiceRequestLineItem> items;

  // Written at the TOP level of the doc (not inside `details`) by
  // service_request_service.dart's setEstimatedAmount()/
  // completeWithFinalAmount() — kept as real fields here rather than
  // folded into rawDetails, so callers read `request.finalAmount`
  // instead of having to know which of the two possible locations
  // (root vs details) a given requestType happened to use.
  final num? estimatedAmountRoot;
  final num? finalAmountRoot;

  // Also root-level fields (not inside `details`) — written by
  // completeWithFinalAmount()/markServiceRequestPaid()/
  // markServiceRequestPaymentReceived() (paymentStatus) and
  // approveEstimate()/rejectEstimate()/setEstimatedAmount()
  // (estimateApprovedByCustomer). Added when hero_home_screen.dart's
  // migration needed them — HeroTaskDetailScreen and
  // _buildActiveServiceRequestsBanner() both read these directly off
  // the doc root.
  final String? paymentStatus;
  final bool? estimateApprovedByCustomer;

  /// Seller's own kitchen stage for shop-menu food orders — 'new',
  /// 'accepted', 'preparing', 'ready', 'delivery_requested'.
  /// (Aug 17 2026 seller audit.)
  ///
  /// Deliberately a SEPARATE axis from [status]: `status` belongs to the
  /// hero/admin dispatch state machine (pending -> hero_assigned ->
  /// in_progress -> completed) and a hotel must never be able to move an
  /// order along that machine. This tracks only what is happening in the
  /// kitchen, and it is the field the seller's Accept / Preparing /
  /// Food Ready / Book Delivery Partner strip drives.
  ///
  /// Null for every request type that has no cooking step (hero booking,
  /// custom order, grocery, taxi) — those still broadcast to heroes
  /// immediately at creation, exactly as before.
  final String? sellerStage;

  /// Everything from Firestore's `details` map, untouched — so fields
  /// specific to one requestType (deliveryAddress, taskDescription,
  /// sellerName, etc.) are never lost even though this model doesn't
  /// declare a named field for every single one of them.
  final Map<String, dynamic> rawDetails;

  final DateTime? createdAt;
  final DateTime? updatedAt;

  const ServiceRequestModel({
    required this.requestId,
    required this.requestType,
    required this.customerId,
    required this.customerName,
    required this.customerPhone,
    required this.status,
    this.assignedHeroId,
    this.assignedHeroName,
    this.assignedHeroPhone,
    this.city,
    this.items = const [],
    this.rawDetails = const {},
    this.estimatedAmountRoot,
    this.finalAmountRoot,
    this.paymentStatus,
    this.estimateApprovedByCustomer,
    this.sellerStage,
    this.createdAt,
    this.updatedAt,
  });

  /// Convenience accessors for the fields every DC (Delivery Challan)
  /// card / tracking screen actually reads, so callers don't have to
  /// know `rawDetails`' key names themselves. Amount can legitimately
  /// live at the document root (setEstimatedAmount/
  /// completeWithFinalAmount) OR inside `details` (e.g.
  /// catalog_food_order's `subtotal`) depending on requestType — checks
  /// both, root first, matching DeliveryChallanCard's original
  /// candidate-list order exactly.
  String? get deliveryAddress =>
      (rawDetails['deliveryAddress'] as String?) ??
      (rawDetails['location'] as String?);
  num? get estimatedAmount =>
      estimatedAmountRoot ?? (rawDetails['estimatedAmount'] as num?);
  num? get finalAmount =>
      finalAmountRoot ?? (rawDetails['finalAmount'] as num?);
  num? get subtotal => rawDetails['subtotal'] as num?;

  /// Best available amount to show on a DC card, in the same
  /// precedence DeliveryChallanCard originally used: finalAmount (root
  /// or details) > estimatedAmount (root or details) > subtotal.
  num? get displayAmount => finalAmount ?? estimatedAmount ?? subtotal;

  /// Live-Firestore constructor — `data` is a `DocumentSnapshot.data()`
  /// map (contains real `Timestamp` objects), `id` is the doc ID
  /// (Firestore doesn't store the doc's own ID inside its data, so it
  /// has to be passed separately — same convention already used by
  /// hero_wallet_model.dart/task_completion_model.dart's
  /// `fromFirestore(data, id)` in this codebase).
  factory ServiceRequestModel.fromFirestore(
    Map<String, dynamic> data,
    String id,
  ) {
    return ServiceRequestModel._fromMap(data, id);
  }

  /// Local-cache constructor — `json` is whatever this model's own
  /// [toJson] previously wrote to Hive/Isar/disk (dates are ISO-8601
  /// Strings here, not Timestamps). Uses the exact same parsing logic
  /// as [fromFirestore] via [parseFlexibleTimestamp], so one code path
  /// safely handles both sources.
  factory ServiceRequestModel.fromJson(Map<String, dynamic> json) {
    return ServiceRequestModel._fromMap(
      json,
      (json['requestId'] as String?) ?? '',
    );
  }

  static ServiceRequestModel _fromMap(Map<String, dynamic> map, String id) {
    final details = (map['details'] is Map)
        ? Map<String, dynamic>.from(map['details'] as Map)
        : <String, dynamic>{};

    final rawItems = details['items'];
    final items = <ServiceRequestLineItem>[];
    if (rawItems is List) {
      for (final entry in rawItems) {
        if (entry is Map) {
          items.add(
            ServiceRequestLineItem.fromJson(Map<String, dynamic>.from(entry)),
          );
        }
      }
    }

    return ServiceRequestModel(
      requestId: id,
      requestType: (map['requestType'] as String?) ?? '',
      customerId: (map['customerId'] as String?) ?? '',
      customerName: (map['customerName'] as String?) ?? '',
      customerPhone: (map['customerPhone'] as String?) ?? '',
      status: (map['status'] as String?) ?? 'pending',
      assignedHeroId: map['assignedHeroId'] as String?,
      assignedHeroName: map['assignedHeroName'] as String?,
      assignedHeroPhone: map['assignedHeroPhone'] as String?,
      city: map['city'] as String?,
      items: items,
      rawDetails: details,
      estimatedAmountRoot: map['estimatedAmount'] as num?,
      finalAmountRoot: map['finalAmount'] as num?,
      paymentStatus: map['paymentStatus'] as String?,
      estimateApprovedByCustomer: map['estimateApprovedByCustomer'] as bool?,
      sellerStage: map['sellerStage'] as String?,
      createdAt: parseFlexibleTimestamp(map['createdAt']),
      updatedAt: parseFlexibleTimestamp(map['updatedAt']),
    );
  }

  /// Firestore write shape — dates go back out as real [Timestamp]s
  /// (or `FieldValue.serverTimestamp()` is used by the caller directly
  /// for new writes, same as the rest of this codebase already does in
  /// service_request_service.dart; this toFirestore() is for updating
  /// an existing doc's fields where a concrete Timestamp is wanted).
  Map<String, dynamic> toFirestore() {
    return {
      'requestType': requestType,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'status': status,
      if (assignedHeroId != null) 'assignedHeroId': assignedHeroId,
      if (city != null) 'city': city,
      'details': {
        ...rawDetails,
        if (items.isNotEmpty) 'items': items.map((i) => i.toJson()).toList(),
      },
      if (createdAt != null) 'createdAt': Timestamp.fromDate(createdAt!),
      if (updatedAt != null) 'updatedAt': Timestamp.fromDate(updatedAt!),
    };
  }

  /// Local-disk-cache write shape (Hive/Isar-ready) — dates are
  /// ISO-8601 Strings, never a Firestore [Timestamp] object, so this
  /// map is plain JSON-safe and can be written to any local store
  /// without a Firestore dependency at read time.
  Map<String, dynamic> toJson() {
    return {
      'requestId': requestId,
      'requestType': requestType,
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'status': status,
      if (assignedHeroId != null) 'assignedHeroId': assignedHeroId,
      if (city != null) 'city': city,
      // Cached so the seller dashboard's Hive-hydrated first paint shows
      // the correct action button instead of flashing "Accept Order" on
      // an order that is already cooking.
      if (sellerStage != null) 'sellerStage': sellerStage,
      'details': {
        ...rawDetails,
        if (items.isNotEmpty) 'items': items.map((i) => i.toJson()).toList(),
      },
      if (createdAt != null) 'createdAt': createdAt!.toIso8601String(),
      if (updatedAt != null) 'updatedAt': updatedAt!.toIso8601String(),
    };
  }

  ServiceRequestModel copyWith({
    String? status,
    String? assignedHeroId,
    DateTime? updatedAt,
  }) {
    return ServiceRequestModel(
      requestId: requestId,
      requestType: requestType,
      customerId: customerId,
      customerName: customerName,
      customerPhone: customerPhone,
      status: status ?? this.status,
      assignedHeroId: assignedHeroId ?? this.assignedHeroId,
      assignedHeroName: assignedHeroName,
      assignedHeroPhone: assignedHeroPhone,
      city: city,
      items: items,
      rawDetails: rawDetails,
      estimatedAmountRoot: estimatedAmountRoot,
      finalAmountRoot: finalAmountRoot,
      paymentStatus: paymentStatus,
      estimateApprovedByCustomer: estimateApprovedByCustomer,
      sellerStage: sellerStage,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
