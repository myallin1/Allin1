// ================================================================
// Fare Rates - Allin1 Super App
// ================================================================
// Single, centralized hardcoded fare-rate source of truth for EVERY
// ride category (bike, auto, cab, parcel, mini_truck, lorry) —
// deliberately NOT Firestore-backed. Rate changes ship through the
// normal `flutter build web` + `firebase deploy` cycle instead of
// costing a Firestore read on every fare calculation.
//
// Per Nizam's explicit MVP decision: no per-category tables anywhere
// else in the codebase. Every call site (customer app estimate, hero
// app booking-time snapshot + completion-time bill, admin display)
// must read numbers from THIS file via FareRates.calculateFare() (or
// the lower-level accessors below) instead of hardcoding its own
// values. This consolidates what used to be 3-4 disagreeing hardcoded
// tables (lib/models/ride_model.dart's defaultFares,
// lib/services/category_gateway_service.dart's
// _getDefaultRideFares(), and this file's old bike-only table) into
// one.
//
// Bike keeps its confirmed day/night per-km split. Every other
// category uses a single flat per-km rate — modeled as "day rate ==
// night rate" so every category can go through the exact same
// calculateFare()/resolvePerKm() code path without a bike-only
// special case at any call site.
// ================================================================

class FareRates {
  FareRates._();

  // ── Per-category rate table ─────────────────────────────────────
  // baseFare: flat fare covering the first `baseDistanceKm` of a trip.
  // perKmDay / perKmNight: rate charged per km beyond baseDistanceKm.
  //   Non-bike categories set perKmDay == perKmNight (no day/night
  //   split for them today) so every category can share one formula.
  // baseDistanceKm: distance covered by baseFare before per-km
  //   charges kick in.
  // minFare: floor applied to the final calculated fare.
  // FIX (Aug 8 2026 — Nizam's exact business rates, replacing the old
  // placeholder table above): baseDistanceKm is now 2km for every
  // category (was 1km). Bike no longer has a day/night split — Nizam's
  // spec gives one flat per-km rate — so perKmDay == perKmNight for
  // every category including bike now (kept both fields so the
  // resolvePerKm()/day-night API shape doesn't need to change at any
  // call site). MiniCab (cab) gets a genuine two-tier long-distance
  // rate via longDistanceThresholdKm/longDistancePerKm — see
  // calculateFare() below for how the tier is applied.
  static const Map<String, _CategoryRate> _rates = {
    'bike': _CategoryRate(
      baseFare: 29,
      baseDistanceKm: 2,
      perKmDay: 7,
      perKmNight: 7,
      minFare: 29,
    ),
    'auto': _CategoryRate(
      baseFare: 49,
      baseDistanceKm: 2,
      perKmDay: 12,
      perKmNight: 12,
      minFare: 49,
    ),
    'cab': _CategoryRate(
      baseFare: 99,
      baseDistanceKm: 2,
      perKmDay: 10,
      perKmNight: 10,
      minFare: 99,
      // MiniCab-only long-distance tier: ₹10/km applies from 2km up to
      // 100km; beyond 100km the rate drops to ₹8/km for the portion
      // past 100km. See calculateFare()'s tier branch.
      longDistanceThresholdKm: 100,
      longDistancePerKm: 8,
    ),
    'parcel': _CategoryRate(
      baseFare: 29,
      baseDistanceKm: 2,
      perKmDay: 9,
      perKmNight: 9,
      minFare: 29,
    ),
    'mini_truck': _CategoryRate(
      baseFare: 149,
      baseDistanceKm: 2,
      perKmDay: 14,
      perKmNight: 14,
      minFare: 149,
    ),
    'lorry': _CategoryRate(
      baseFare: 1000,
      baseDistanceKm: 2,
      perKmDay: 30,
      perKmNight: 30,
      minFare: 1000,
    ),
  };

  /// Day window: 06:00 (inclusive) to 22:00 (exclusive), Asia/Kolkata.
  static const int _dayStartHour = 6;

  /// Night window starts here: 22:00 (inclusive) to 06:00, Asia/Kolkata.
  static const int _nightStartHour = 22;

  static _CategoryRate _rateFor(String category) =>
      _rates[category] ?? _rates['bike']!;

  // ── Legacy bike-only constants (kept for existing call sites that
  // reference these directly — e.g. the booking-time snapshot write
  // and debug logging in hero_ride_screen.dart / bike_booking_screen
  // .dart) ───────────────────────────────────────────────────────
  static const double bikeBaseFare = 29;
  static const double bikeBaseDistanceKm = 2;
  static const double bikePerKmDay = 7;
  static const double bikePerKmNight = 7;

  /// Base fare for [category] (covers the first [baseDistanceKmFor]
  /// km of the trip).
  static double baseFareFor(String category) => _rateFor(category).baseFare;

  /// Distance (km) covered by the base fare before per-km charges
  /// apply, for [category].
  static double baseDistanceKmFor(String category) =>
      _rateFor(category).baseDistanceKm;

  /// Minimum fare floor for [category].
  static double minFareFor(String category) => _rateFor(category).minFare;

  /// Resolves the per-km rate for [category] at [at] (day/night split
  /// for bike; a flat rate — day == night — for every other category
  /// today). Evaluated against explicit UTC+5:30 (Asia/Kolkata) rather
  /// than the device's own timezone/clock setting — this app is
  /// India-only, but trusting device-local time directly would make
  /// the day/night boundary dependent on whatever timezone a given
  /// device happens to be configured with.
  static double resolvePerKm(String category, DateTime at) {
    final istHour =
        at.toUtc().add(const Duration(hours: 5, minutes: 30)).hour;
    final isDay = istHour >= _dayStartHour && istHour < _nightStartHour;
    final rate = _rateFor(category);
    return isDay ? rate.perKmDay : rate.perKmNight;
  }

  /// Legacy alias for `resolvePerKm('bike', at)` — kept so existing
  /// bike-specific call sites don't all need to change their call
  /// shape.
  static double resolveBikePerKm(DateTime at) => resolvePerKm('bike', at);

  /// Full fare for [distanceKm] km of a [category] ride, using the
  /// "baseFare covers the first baseDistanceKm km" shape used
  /// throughout this codebase. [at] defaults to `DateTime.now()` and
  /// only matters for categories with a day/night split (bike) —
  /// pass the ride's booking time or completion time explicitly where
  /// that distinction matters.
  static double calculateFare(
    String category,
    double distanceKm, {
    DateTime? at,
  }) {
    if (distanceKm <= 0) return 0;

    final rate = _rateFor(category);
    final perKm = resolvePerKm(category, at ?? DateTime.now());

    double calculatedFare;
    if (distanceKm <= rate.baseDistanceKm) {
      calculatedFare = rate.baseFare;
    } else {
      // MiniCab-style long-distance tier: if this category defines a
      // longDistanceThresholdKm and the trip crosses it, split the
      // per-km portion into two segments — [baseDistanceKm..threshold]
      // at the normal per-km rate, and [threshold..distanceKm] at the
      // (cheaper) longDistancePerKm rate. Every other category has no
      // threshold set, so this collapses to the old single-rate formula.
      final threshold = rate.longDistanceThresholdKm;
      if (threshold != null && distanceKm > threshold) {
        final midSegmentKm = threshold - rate.baseDistanceKm;
        final farSegmentKm = distanceKm - threshold;
        final farPerKm = rate.longDistancePerKm ?? perKm;
        calculatedFare = rate.baseFare +
            (midSegmentKm * perKm) +
            (farSegmentKm * farPerKm);
      } else {
        calculatedFare =
            rate.baseFare + ((distanceKm - rate.baseDistanceKm) * perKm);
      }
    }

    final finalFare =
        calculatedFare < rate.minFare ? rate.minFare : calculatedFare;
    return finalFare.roundToDouble();
  }

  /// Legacy-shaped fare formula kept for the handful of call sites
  /// that already resolved their own `perKm` (via [resolveBikePerKm])
  /// and just need the arithmetic. Prefer [calculateFare] for new
  /// code — it resolves the per-km rate itself and applies the
  /// category's minimum fare floor.
  static double calculateBikeFare({
    required double distanceKm,
    required double perKm,
  }) {
    if (distanceKm <= bikeBaseDistanceKm) {
      return bikeBaseFare;
    }
    final extraKm = distanceKm - bikeBaseDistanceKm;
    return (bikeBaseFare + (extraKm * perKm)).roundToDouble();
  }

  /// Legacy-shaped `{'baseFare', 'perKm', 'baseDistance'}` map for
  /// [category], matching the shape `RideModel.defaultFares` used to
  /// return. Kept only so callers that still expect that shape (e.g.
  /// a `.containsKey()` check for which categories exist) don't need
  /// to change their data structure — the numbers themselves come
  /// from this file's single rate table above. `perKm` here is the
  /// DAY rate; call [resolvePerKm]/[calculateFare] directly wherever
  /// the day/night distinction actually matters.
  static Map<String, double> legacyMapFor(String category) {
    final rate = _rateFor(category);
    return {
      'baseFare': rate.baseFare,
      'perKm': rate.perKmDay,
      'baseDistance': rate.baseDistanceKm,
    };
  }

  /// All known category keys.
  static Iterable<String> get categories => _rates.keys;
}

class _CategoryRate {
  final double baseFare;
  final double baseDistanceKm;
  final double perKmDay;
  final double perKmNight;
  final double minFare;
  // Optional MiniCab-style long-distance tier — null for every
  // category that doesn't have one (single flat per-km rate applies).
  final double? longDistanceThresholdKm;
  final double? longDistancePerKm;

  const _CategoryRate({
    required this.baseFare,
    required this.baseDistanceKm,
    required this.perKmDay,
    required this.perKmNight,
    required this.minFare,
    this.longDistanceThresholdKm,
    this.longDistancePerKm,
  });
}
