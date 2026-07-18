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

  // Fare calculation: Base fare + per-km rate with free distance and minimum fare
  static const Map<String, Map<String, double>> defaultFares = {
    'bike': {'baseFare': 25.0, 'perKm': 6.0, 'baseDistance': 1.0},
    'auto': {'baseFare': 30.0, 'perKm': 8.0, 'baseDistance': 1.0},
    'cab': {'baseFare': 50.0, 'perKm': 12.0, 'baseDistance': 1.0},
    'parcel': {'baseFare': 40.0, 'perKm': 8.0, 'baseDistance': 1.0},
  };

  /// Calculates the estimated fare for a ride based on distance and vehicle type.
  /// Standard logic: baseFare covers the first [baseDistance] km.
  /// Additional distance is charged at [perKm].
  static double calculateFare(
    double distanceKm,
    String vehicleType, {
    Map<String, dynamic>? fares,
  }) {
    if (distanceKm <= 0) {
      return 0;
    }

    // Use provided fares or fallback to hardcoded defaults
    final vehicleFares = fares?[vehicleType] as Map<String, dynamic>? ??
        defaultFares[vehicleType] ??
        defaultFares['bike']!;

    final baseFare = (vehicleFares['baseFare'] as num?)?.toDouble() ?? 25.0;
    final perKm = (vehicleFares['perKm'] as num?)?.toDouble() ?? 10.0;
    final baseDistance =
        (vehicleFares['baseDistance'] as num?)?.toDouble() ?? 2.0;

    double calculatedFare;
    if (distanceKm <= baseDistance) {
      // Within base distance - charge base fare only
      calculatedFare = baseFare;
    } else {
      // After base distance - charge per km for the excess distance
      calculatedFare = baseFare + ((distanceKm - baseDistance) * perKm);
    }

    // Apply minimum fare and round to nearest whole number for display
    const double minFare = 20;
    final finalFare = calculatedFare < minFare ? minFare : calculatedFare;
    return finalFare.roundToDouble();
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
