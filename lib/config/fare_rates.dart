// ================================================================
// Fare Rates - Allin1 Super App
// ================================================================
// Hardcoded fare-rate source of truth for categories that use the
// day/night pricing model, resolved locally at both booking time and
// ride-completion time — deliberately NOT Firestore-backed. Rate
// changes ship through the normal `flutter build web` + `firebase
// deploy` cycle instead of costing a Firestore read on every fare
// calculation.
//
// SCOPE: bike ONLY, for now. Auto, cab, parcel, mini_truck, lorry, and
// emergency_manpower remain on the existing Firestore-backed
// `settings/ride_fares` path via CategoryGatewayService.loadRideFares()
// — that mechanism is untouched and still authoritative for every
// category except bike. This file is named generically so it can grow
// to cover other categories later without a rename, but today it only
// contains bike constants.
// ================================================================

class FareRates {
  FareRates._();

  // ── Bike (day/night split — confirmed pricing) ────────────────
  static const double bikeBaseFare = 25.0;
  static const double bikeBaseDistanceKm = 1.0;
  static const double bikePerKmDay = 7.0;
  static const double bikePerKmNight = 9.0;

  /// Day window: 06:00 (inclusive) to 22:00 (exclusive), Asia/Kolkata.
  static const int _dayStartHour = 6;

  /// Night window starts here: 22:00 (inclusive) to 06:00, Asia/Kolkata.
  static const int _nightStartHour = 22;

  /// Resolves the bike per-km rate for [at], evaluated against explicit
  /// UTC+5:30 (Asia/Kolkata) rather than the device's own timezone/clock
  /// setting — this app is India-only, but trusting device-local time
  /// directly would make the day/night boundary dependent on whatever
  /// timezone a given device happens to be configured with.
  static double resolveBikePerKm(DateTime at) {
    final istHour =
        at.toUtc().add(const Duration(hours: 5, minutes: 30)).hour;
    final isDay = istHour >= _dayStartHour && istHour < _nightStartHour;
    return isDay ? bikePerKmDay : bikePerKmNight;
  }

  /// Full bike fare for [distanceKm] at the given per-km rate, using the
  /// same "baseFare covers the first baseDistance km" shape already used
  /// throughout this codebase (RideModel.calculateFare, the old
  /// hardcoded hero-side formula). Callers resolve which per-km rate to
  /// pass in via [resolveBikePerKm] using their own reference time
  /// (booking time for the customer estimate, completion time for the
  /// hero's final bill) — this function only does the arithmetic.
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
}
