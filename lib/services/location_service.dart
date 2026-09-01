// ================================================================
// Location Service - GPS & Geolocation
// Allin1 Super App v1.0
// ================================================================

import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint, kIsWeb;
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

  // FIX (Aug 11 2026 — Nizam's "laptop browser silent GPS failure"
  // report): getCurrentLocation() used to swallow every exception with
  // a bare `catch (e) { return null; }` -- no debugPrint, nothing. On a
  // laptop, the browser Geolocation API (which geolocator_web wraps)
  // often can't get a high-accuracy fix quickly -- no GPS hardware, so
  // it falls back to slow WiFi/IP-based positioning, or the OS-level
  // Location Services toggle is off, or the site permission was denied
  // -- any of which throws (most commonly a TimeoutException once
  // timeLimit is hit). That exception vanished into the void before,
  // which is exactly why the customer's console looked "completely
  // clean" while the ping never went out: no error was ever printed
  // anywhere. This field records the last real error so callers (and
  // debugPrint below) can surface something concrete instead of a
  // silent null.
  String? _lastLocationError;
  String? get lastLocationError => _lastLocationError;

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
        _lastLocationError =
            'Permission/service check failed (denied or Location Services off).';
        debugPrint('[LocationService] getCurrentLocation: $_lastLocationError');
        return null;
      }

      _currentPosition = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high, // bestForNavigation only needed during active ride
          timeLimit: Duration(seconds: 15),
        ),
      );
      _lastLocationError = null;
      return _currentPosition;
    } catch (e) {
      // FIX (Aug 11 2026): this used to be a bare `return null;` with the
      // exception thrown away entirely -- the root cause of the "clean
      // console, nothing happens" laptop reports. Now logged AND, on web
      // specifically (where this high-accuracy path most commonly times
      // out on laptops relying on slow WiFi-based positioning instead of
      // real GPS hardware), we retry once with reduced accuracy and a
      // longer time budget before giving up -- this is usually enough to
      // get a coarse-but-usable fix where the precise one failed.
      _lastLocationError = e.toString();
      debugPrint('[LocationService] getCurrentLocation failed: $e');
      if (kIsWeb) {
        try {
          debugPrint(
              '[LocationService] retrying with reduced accuracy (web fallback)...');
          _currentPosition = await Geolocator.getCurrentPosition(
            locationSettings: const LocationSettings(
              accuracy: LocationAccuracy.medium,
              timeLimit: Duration(seconds: 25),
            ),
          );
          _lastLocationError = null;
          debugPrint('[LocationService] reduced-accuracy retry succeeded.');
          return _currentPosition;
        } catch (e2) {
          _lastLocationError = e2.toString();
          debugPrint('[LocationService] reduced-accuracy retry also failed: $e2');
          return null;
        }
      }
      return null;
    }
  }

  // ================================================================
  // Get Fast Location (Aug 11 2026 — Instant-Seed architecture)
  // ================================================================
  // getCurrentLocation() above is deliberately PATIENT: 15s at high
  // accuracy, then a 25s medium-accuracy web retry. That is right for
  // callers that genuinely need a precise fix and have somewhere to
  // wait (hero registration, seller onboarding, the SOS screen).
  //
  // It is wrong for a booking screen. bike_booking_screen called it,
  // got null, waited 2s, and called it AGAIN — a worst case of roughly
  // 82 seconds staring at "Getting precise live location..." before the
  // customer was even offered the manual pin. On a Windows laptop with
  // no GPS chip, that 82 seconds was the NORMAL path, not the worst one.
  //
  // This is the impatient variant: ONE attempt, short budget, no
  // retries. It exists so a screen can fire GPS in the background while
  // the customer already has a usable map in front of them. Nothing
  // waits on it, so a failure costs nothing and needs no error UI.
  //
  // getCurrentLocation() is intentionally left exactly as it was —
  // it has ten other callers and none of them are being changed here.
  Future<Position?> getFastLocation({
    Duration timeout = const Duration(seconds: 3),
  }) async {
    try {
      final hasPermission = await checkAndRequestPermission();
      if (!hasPermission) {
        _lastLocationError =
            'Permission/service check failed (denied or Location Services off).';
        debugPrint('[LocationService] getFastLocation: no permission.');
        return await _fastLocationFallback();
      }

      // Medium accuracy on purpose: a booking pickup pin does not need
      // navigation-grade precision, and medium resolves dramatically
      // faster on hardware without a GPS chip — which is the exact
      // platform this method exists for.
      //
      // HARD CEILING via Future.any (Aug 11 2026, per Nizam's approved
      // 3-Step Manual Pin architecture): Geolocator's own `timeLimit`
      // is honoured by the plugin, but plugin behaviour has proven
      // inconsistent across web/mobile in this codebase before (see the
      // 82s laptop timeout this whole feature exists to fix). Racing
      // the fetch against an independent Future.delayed guarantees this
      // method NEVER exceeds `timeout`, regardless of what the
      // underlying platform channel does.
      final position = await Future.any<Position?>([
        Geolocator.getCurrentPosition(
          locationSettings: LocationSettings(
            accuracy: LocationAccuracy.medium,
            timeLimit: timeout,
          ),
        ),
        Future<Position?>.delayed(timeout, () => null),
      ]);

      if (position != null) {
        _currentPosition = position;
        _lastLocationError = null;
        return position;
      }

      debugPrint('[LocationService] getFastLocation: hit the ${timeout.inSeconds}s '
          'ceiling with no fix — falling back.');
      return await _fastLocationFallback();
    } catch (e) {
      // Silent by design — the caller already has a seeded map on screen.
      _lastLocationError = e.toString();
      debugPrint('[LocationService] getFastLocation failed: $e — falling back.');
      return await _fastLocationFallback();
    }
  }

  /// Immediate, no-network fallback for getFastLocation(): the device's
  /// last-known fix. Costs nothing and resolves instantly when present,
  /// which is exactly what a 3s-ceiling caller needs on the way out.
  /// Returns null (never throws) if even that isn't available — the
  /// caller's own Hive-remembered-pickup / city-centre seed takes it
  /// from there.
  Future<Position?> _fastLocationFallback() async {
    try {
      final lastKnown = await Geolocator.getLastKnownPosition();
      if (lastKnown != null) {
        debugPrint('[LocationService] getFastLocation: using last-known position.');
      }
      return lastKnown;
    } catch (e) {
      debugPrint('[LocationService] last-known fallback also failed: $e');
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
