// ================================================================
// Location Service - GPS & Geolocation
// Allin1 Super App v1.0
// ================================================================

import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';

class LocationService {
  static final LocationService _instance = LocationService._internal();
  factory LocationService() => _instance;
  LocationService._internal();

  Position? _currentPosition;
  Position? get currentPosition => _currentPosition;

  LatLng? get currentLatLng {
    if (_currentPosition == null) {
      return null;
    }
    return LatLng(_currentPosition!.latitude, _currentPosition!.longitude);
  }

  // ================================================================
  // Check & Request Location Permissions
  // ================================================================
  Future<bool> checkAndRequestPermission() async {
    final bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      return false;
    }

    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) {
        return false;
      }
    }

    if (permission == LocationPermission.deniedForever) {
      return false;
    }

    return true;
  }

  // ================================================================
  // Get Current Location
  // ================================================================
  Future<Position?> getCurrentLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        return null;
      }

      return _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy
              .high, // bestForNavigation only needed during active ride
          timeLimit: Duration(seconds: 15),
        ),
      );
    } catch (e) {
      return null;
    }
  }

  // ================================================================
  // Get Last Known Location (faster, less accurate)
  // ================================================================
  Future<Position?> getLastKnownLocation() async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        return null;
      }

      return _currentPosition = await Geolocator.getLastKnownPosition();
    } catch (e) {
      return null;
    }
  }

  // ================================================================
  // Calculate Distance Between Two Points (in meters)
  // ================================================================
  double calculateDistance(LatLng start, LatLng end) {
    return Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      end.latitude,
      end.longitude,
    );
  }

  // ================================================================
  // Calculate Distance in Kilometers
  // ================================================================
  double calculateDistanceKm(LatLng start, LatLng end) {
    return calculateDistance(start, end) / 1000;
  }

  // ================================================================
  // Get Address from Coordinates (Reverse Geocoding)
  // ================================================================
  Future<String?> getAddressFromCoordinates(LatLng position) async {
    try {
      // Using placemarks from geocoding
      return '${position.latitude.toStringAsFixed(4)}, ${position.longitude.toStringAsFixed(4)}';
    } catch (e) {
      return null;
    }
  }

  // ================================================================
  // Stream Location Updates (for real-time tracking)
  // ================================================================
  Stream<Position> getLocationStream({bool highAccuracy = false}) {
    final locationSettings = LocationSettings(
      // Use bestForNavigation only during active ride (caller passes highAccuracy:true)
      // High accuracy for radar/online state — saves significant battery
      accuracy: highAccuracy
          ? LocationAccuracy.bestForNavigation
          : LocationAccuracy.high,
      distanceFilter: highAccuracy ? 5 : 10, // meters
    );

    return Geolocator.getPositionStream(locationSettings: locationSettings);
  }

  // ================================================================
  // Open Location Settings
  // ================================================================
  Future<bool> openLocationSettings() async {
    return await Geolocator.openLocationSettings();
  }

  // ================================================================
  // Open App Settings (for permission settings)
  // ================================================================
  Future<bool> openAppSettings() async {
    return await Geolocator.openAppSettings();
  }
}
