// ================================================================
// Location Service - GPS & Geolocation
// Allin1 Super App v1.0
// ================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:geocoding/geocoding.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
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

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, // bestForNavigation only needed during active ride
          timeLimit: Duration(seconds: 15),
        ),
      );
      return _currentPosition;
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

      _currentPosition = await Geolocator.getLastKnownPosition();
      return _currentPosition;
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
  // Get City Name from Coordinates (Reverse Geocoding)
  // FIX: getAddressFromCoordinates above never actually called the
  // geocoding package despite its comment claiming to -- it just
  // formatted the raw lat/lng as text. This is a real reverse-geocode
  // call, used by city_service.dart's silent city-detection on app
  // open (Multi-city Plan 3) to resolve GPS -> a real city name.
  // Device-only API call (no Firestore/RTDB read), so this costs
  // nothing on our database usage.
  // ================================================================
  Future<String?> getCityFromCoordinates(LatLng position) async {
    // FIX (root cause of "Use my current location" doing nothing on the
    // web PWA -- reported: customer manually on Coimbatore, physically
    // in Erode, tapped "Use my current location" and it never switched
    // to Erode): the `geocoding` package (placemarkFromCoordinates) has
    // NO web platform implementation at all -- it's Android/iOS/macOS
    // only. On Flutter Web this throws MissingPluginException every
    // single time, silently caught below, so city_service.dart's
    // detectAndUpdateCity() always fell back to whatever city was
    // already cached (Coimbatore, in this case) with zero indication
    // anything failed. Native Android/iOS builds were never affected --
    // this only broke the web build (my-allin1.web.app).
    // Fix: on web, use BigDataCloud's free client-side reverse-geocode
    // API instead (no API key needed, CORS-enabled, no cost -- HTTP call
    // straight from the browser, not billed against our Firestore/RTDB
    // usage). Native platforms keep using the geocoding package as
    // before.
    if (kIsWeb) {
      return _getCityFromCoordinatesWeb(position);
    }
    try {
      final placemarks = await placemarkFromCoordinates(
        position.latitude,
        position.longitude,
      );
      if (placemarks.isEmpty) return null;
      final p = placemarks.first;
      // locality is usually the city; subAdministrativeArea (district)
      // is a reasonable fallback for areas where locality comes back
      // empty (common for smaller towns in geocoding results).
      final city = (p.locality?.trim().isNotEmpty ?? false)
          ? p.locality!.trim()
          : p.subAdministrativeArea?.trim();
      return (city?.isNotEmpty ?? false) ? city : null;
    } catch (e) {
      return null;
    }
  }

  Future<String?> _getCityFromCoordinatesWeb(LatLng position) async {
    try {
      final uri = Uri.parse(
        'https://api.bigdatacloud.net/data/reverse-geocode-client'
        '?latitude=${position.latitude}&longitude=${position.longitude}&localityLanguage=en',
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 8));
      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      // BigDataCloud's "city" field is often empty for Indian towns;
      // "locality" is the more reliable field here, same fallback
      // ordering as the native path above.
      final city = (data['city'] as String?)?.trim();
      final locality = (data['locality'] as String?)?.trim();
      final principalSubdivision = (data['principalSubdivision'] as String?)?.trim();
      final resolved = (city?.isNotEmpty ?? false)
          ? city
          : (locality?.isNotEmpty ?? false)
              ? locality
              : principalSubdivision;
      return (resolved?.isNotEmpty ?? false) ? resolved : null;
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
