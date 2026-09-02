// ================================================================
// hero_service_access.dart — per-hero service permissions
// ================================================================
// NEW (Aug 17 2026 — Nizam: "some heros correcta 3 work kum pappanga...
// avanga service accept ah particular serviceko ila full service um
// atten pannamudiyama pandrathuku access irukanum apo than avanga work
// pannuna atha control pannamudiyum").
//
// THE PROBLEM THIS SOLVES
// Before this file, a hero's workload was decided entirely by their
// vehicleType, and only for RIDES:
//   * ride_search_screen._fetchNearbyHeroes() matched the ride's
//     category against the hero's vehicleType, plus a hardcoded "SMART
//     MODE" rule that sent EVERY parcel job to EVERY bike hero whether
//     they were any good at parcels or not.
//   * service_request_service._broadcastToEligibleHeroes() did no
//     category filtering AT ALL — its own comment says so. Hero
//     bookings, grocery runs, food orders and custom orders were pinged
//     to every online hero in the city, indiscriminately.
// So there was no way to say "this hero does bike rides well, keep them
// off parcels" or "this one is only for hero bookings". Admin had two
// options for a hero who mishandled one kind of work: tolerate it, or
// reject them entirely.
//
// THE MODEL
// One map on heroes/{uid}:
//     serviceAccess: { "parcel": false, "grocery_order": false, ... }
// Only the DENIED entries need to be present. A missing key means
// allowed — see [isAllowed]. That default is load-bearing: every hero
// who already exists has no such map, and must keep receiving exactly
// the work they receive today. This feature can therefore be deployed
// to a live fleet without changing anybody's behaviour until an admin
// deliberately turns something off.
//
// WHERE IT IS ENFORCED
//   1. ride_search_screen.dart      — ride + parcel pings
//   2. service_request_service.dart — every broadcast requestType
// Both read the copy mirrored into the RTDB presence node
// (online_heroes/{uid}.serviceAccess) rather than re-reading Firestore
// per hero per dispatch, which would put N document reads on the
// critical path of every single booking.
// ================================================================

/// Firestore/RTDB field name holding the per-hero permission map.
const String kHeroServiceAccessField = 'serviceAccess';

/// The service "buckets" an admin can switch on or off per hero.
///
/// Deliberately coarser than the raw requestType list: an admin is
/// deciding what KIND of work a person is trusted with, not
/// administering a protocol. All three food paths
/// (catalog_food_order / custom_hotel_order / custom_food_order) are one
/// decision, because "can this hero deliver food" is one question.
class HeroServiceKeys {
  HeroServiceKeys._();

  /// Passenger rides in the hero's own vehicle category.
  static const String ride = 'ride';

  /// Parcel / courier jobs. Broken out from [ride] on purpose — this is
  /// the exact case Nizam raised, where bike heroes were being handed
  /// parcel work automatically by the old SMART MODE rule.
  static const String parcel = 'parcel';

  /// "Hero Buddy" — customer books a hero directly for general help.
  static const String heroBooking = 'hero_booking';

  /// Restaurant/hotel food delivery (all three food requestTypes).
  static const String foodOrder = 'food_order';

  /// Grocery / quick-commerce shopping runs.
  static const String groceryOrder = 'grocery_order';

  /// Free-text "order from any shop" requests.
  static const String customOrder = 'custom_order';

  /// NJ Tech electronics repair/install jobs.
  static const String electronicsService = 'electronics_service';

  /// Display order for the admin UI.
  static const List<String> all = [
    ride,
    parcel,
    heroBooking,
    foodOrder,
    groceryOrder,
    customOrder,
    electronicsService,
  ];

  static const Map<String, String> labels = {
    ride: 'Rides (bike / auto / cab)',
    parcel: 'Parcel & courier',
    heroBooking: 'Hero booking (Hero Buddy)',
    foodOrder: 'Food delivery',
    groceryOrder: 'Grocery shopping',
    customOrder: 'Custom orders (any shop)',
    electronicsService: 'Electronics service',
  };

  static const Map<String, String> descriptions = {
    ride: 'Passenger trips in their registered vehicle category.',
    parcel: 'Bike heroes also receive parcel jobs unless this is off.',
    heroBooking: 'Direct bookings where a customer hires the hero.',
    foodOrder: 'Shop-menu, custom hotel and custom food orders.',
    groceryOrder: 'Shopping-list runs paid on delivery.',
    customOrder: 'Free-text requests to buy from any shop.',
    electronicsService: 'Repair and installation jobs.',
  };
}

/// Maps a `service_requests.requestType` to the permission bucket that
/// governs it. Returns null for a requestType nothing gates (in which
/// case dispatch must NOT filter — an unknown type is not a denied one).
String? serviceKeyForRequestType(String requestType) {
  switch (requestType.trim()) {
    case 'hero_booking':
      return HeroServiceKeys.heroBooking;
    case 'catalog_food_order':
    case 'custom_hotel_order':
    case 'custom_food_order':
      return HeroServiceKeys.foodOrder;
    case 'grocery_order':
    // FIX (audit pass, Sep 2026 — universal catalog build): the new
    // catalog-based grocery order type was missing here entirely, which
    // meant serviceKeyForRequestType() fell through to `default: null` —
    // per this function's own doc comment, null means "dispatch must
    // NOT filter." Every catalog_grocery_order was silently broadcast
    // to ALL online heroes regardless of their own Grocery Order
    // service-access toggle, bypassing the opt-out entirely. Same
    // bucket as the free-text 'grocery_order' — a hero who disabled
    // grocery work meant ALL grocery work, catalog or free-text.
    case 'catalog_grocery_order':
      return HeroServiceKeys.groceryOrder;
    case 'custom_order':
      return HeroServiceKeys.customOrder;
    case 'electronics_service':
      return HeroServiceKeys.electronicsService;
    default:
      return null;
  }
}

/// True if [heroData] permits [serviceKey].
///
/// [heroData] may be either a Firestore heroes/{uid} document map or the
/// RTDB online_heroes/{uid} presence map — both carry the same
/// [kHeroServiceAccessField] shape, so dispatch can use whichever it
/// already has in hand.
///
/// DEFAULTS TO TRUE, and that is deliberate, not lazy. This has to ship
/// onto a live fleet where not one hero doc has this map yet. Defaulting
/// to false would silently strip every existing hero of every kind of
/// work the moment it deployed. A permission that has never been set is
/// not a permission that was denied.
bool isServiceAllowed(Object? heroData, String serviceKey) {
  if (heroData is! Map) return true;
  final raw = heroData[kHeroServiceAccessField];
  if (raw is! Map) return true;
  final value = raw[serviceKey];
  // Only an explicit `false` denies. Null/missing/malformed = allowed.
  return value != false;
}

/// True only when [serviceKey] is set to an explicit `true`.
///
/// Different question from [isServiceAllowed], and the difference
/// matters (Aug 17 2026 — Nizam: "already oru category la accept
/// pannuna oru hero ku yepdi parcel accept pandra permission
/// kudukurathu?").
///
/// [isServiceAllowed] answers "is this hero BLOCKED from work they would
/// otherwise be offered" — it defaults to true so nobody is accidentally
/// cut off. That is the right default for taking permissions away, but
/// it cannot GRANT anything, because "absent" already reads as allowed.
///
/// This one answers "has an admin deliberately opted this hero IN". Used
/// by ride_search_screen.dart to hand parcel jobs to an auto/cab hero,
/// who the vehicle-category rules would otherwise never match: SMART
/// MODE only ever widened parcel dispatch to BIKE heroes.
bool isServiceExplicitlyGranted(Object? heroData, String serviceKey) {
  if (heroData is! Map) return false;
  final raw = heroData[kHeroServiceAccessField];
  if (raw is! Map) return false;
  return raw[serviceKey] == true;
}

/// The denied keys in [heroData], for admin display ("2 services off").
List<String> deniedServices(Object? heroData) {
  if (heroData is! Map) return const [];
  final raw = heroData[kHeroServiceAccessField];
  if (raw is! Map) return const [];
  return HeroServiceKeys.all
      .where((k) => raw[k] == false)
      .toList(growable: false);
}
