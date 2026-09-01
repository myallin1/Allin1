import '../config/fare_rates.dart';

enum RideStatus {
  searching,
  heroAssigned,
  arriving,
  inProgress,
  completed,
  cancelled,
}

class RideModel {
  // Original fields
  final String? id;
  final String? customerId;
  final String? heroId;
  final String? pickupLocation;
  final String? dropLocation;
  final double? pickupLatitude;
  final double? pickupLongitude;
  final double? dropLatitude;
  final double? dropLongitude;
  final double? fare;
  String? status;
  final DateTime? createdAt;
  final DateTime? acceptedAt;
  final DateTime? completedAt;

  // Booking screen fields
  final String? rideId;
  final String? pickupAddress;
  final String? dropAddress;
  double? estimatedFare;
  final double? distanceKm;
  final int? etaMinutes;
  final String? vehicleType;

  // Hero fields (set when hero found)
  String? heroName;
  String? heroVehicleNumber;
  String? heroPhone;
  double? heroRating;
  double? heroLat;
  double? heroLng;

  RideModel({
    this.id,
    this.customerId,
    this.heroId,
    this.pickupLocation,
    this.dropLocation,
    this.pickupLatitude,
    this.pickupLongitude,
    this.dropLatitude,
    this.dropLongitude,
    this.fare,
    this.status,
    this.createdAt,
    this.acceptedAt,
    this.completedAt,
    // Booking screen fields
    this.rideId,
    this.pickupAddress,
    this.dropAddress,
    this.estimatedFare,
    this.distanceKm,
    this.etaMinutes,
    this.vehicleType,
    // Hero fields
    this.heroName,
    this.heroVehicleNumber,
    this.heroPhone,
    this.heroRating,
    this.heroLat,
    this.heroLng,
  });

  // Fare calculation: Base fare + per-km rate with free distance and minimum fare.
  //
  // FIX: this used to be its own hardcoded table (independently
  // disagreeing with lib/config/fare_rates.dart and
  // category_gateway_service.dart's _getDefaultRideFares()). Per
  // Nizam's single-source-of-truth decision, the numbers now come
  // from FareRates — this getter just re-shapes them into the
  // `{'baseFare', 'perKm', 'baseDistance'}` map callers already
  // expect (e.g. the `.containsKey()` check in bike_booking_screen
  // .dart and the booking-time Firestore snapshot write).
  static Map<String, Map<String, double>> get defaultFares => {
        for (final category in FareRates.categories)
          category: FareRates.legacyMapFor(category),
      };

  /// Calculates the estimated fare for a ride based on distance and
  /// vehicle type. Delegates to the single central FareRates.calculateFare()
  /// — see lib/config/fare_rates.dart. [fares] is accepted only for
  /// backward source compatibility with older call sites that used to
  /// pass a Firestore-sourced override map; per Nizam's MVP decision
  /// fare math is no longer Firestore-driven, so this parameter is now
  /// ignored.
  static double calculateFare(
    double distanceKm,
    String vehicleType, {
    @Deprecated('Fare math is no longer Firestore-driven; this is ignored.')
    Map<String, dynamic>? fares,
  }) {
    return FareRates.calculateFare(vehicleType, distanceKm);
  }

  // Get status as display string
  String get statusDisplay {
    switch (status) {
      case 'searching':
        return 'Searching for hero...';
      case 'hero_assigned':
        return 'Hero Assigned';
      case 'arriving':
        return 'Hero Arriving';
      case 'in_progress':
        return 'Ride in Progress';
      case 'completed':
        return 'Ride Completed';
      case 'cancelled':
        return 'Ride Cancelled';
      default:
        return 'Unknown';
    }
  }
}
