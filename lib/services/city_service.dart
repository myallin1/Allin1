// lib/services/city_service.dart
// ================================================================
// Customer's currently-selected operating city, persisted locally.
// Defaults to kDefaultCity ('erode') so a customer who never touches
// this (i.e. everyone today, before any city picker UI exists) keeps
// seeing exactly the same Erode heroes/stores/rides as before this
// multi-city work started -- this is additive, not a breaking change.
//
// Phase 1 scope (this commit): schema + filtering only. A visible
// city-picker UI for customers to switch cities is a follow-up --
// for now this just reads/writes the persisted value so the
// filtering logic (ride_search_screen.dart, service_request_service.
// dart) has something real to key off of.
// ================================================================
import 'package:latlong2/latlong.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../config/city_config.dart';
import 'location_service.dart';

class CityService {
  static const String _prefsKey = 'selected_city';
  // Set true the moment the customer manually picks a city from the
  // picker (dashboard_screen.dart's city tap). Once set, silent GPS
  // auto-detection stops overwriting their choice -- e.g. someone who
  // manually switches to Coimbatore while physically still in Erode
  // (checking prices/heroes ahead of a trip) shouldn't get silently
  // flipped back to Erode next time GPS resolves.
  static const String _manualFlagKey = 'selected_city_is_manual';

  static Future<String> getCurrentCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey) ?? kDefaultCity;
  }

  /// Explicit manual pick (from the city-picker UI). Marks the flag so
  /// detectAndUpdateCity() won't silently override this later.
  static Future<void> setCurrentCityManually(String citySlug) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, citySlug);
    await prefs.setBool(_manualFlagKey, true);
  }

  /// Internal/auto-detect write path -- does NOT set the manual flag.
  static Future<void> setCurrentCity(String citySlug) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, citySlug);
  }

  static Future<bool> isManuallySet() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_manualFlagKey) ?? false;
  }

  /// Lets the customer go back to "auto-detect via GPS" after having
  /// manually picked a city -- offered as a "Use my current location"
  /// option in the city picker alongside the explicit city list.
  static Future<void> clearManualOverride() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_manualFlagKey, false);
  }

  /// Silent GPS-based city detection, called once on app-open (dashboard
  /// header). Fully local/device-side (GPS + geocoding API) -- no
  /// Firestore/RTDB read, so this costs nothing on our database usage.
  /// If location permission was already granted, this runs with no UI
  /// at all. If not yet decided, it triggers the normal OS permission
  /// dialog once (same as every other location feature in the app) --
  /// after that it's silent on every future app open.
  ///
  /// Skips entirely if the customer has manually picked a city (see
  /// setCurrentCityManually) -- their explicit choice always wins over
  /// GPS until they manually change it again or tap "Use my location".
  ///
  /// Returns the resolved city slug (persisted via setCurrentCity), or
  /// the previously cached/default city if GPS/geocoding fails for any
  /// reason (no network, permission denied, etc) -- never throws, never
  /// blocks the caller with a loading state.
  static Future<String> detectAndUpdateCity() async {
    final fallback = await getCurrentCity();
    if (await isManuallySet()) return fallback;
    try {
      final position = await LocationService().getCurrentLocation();
      if (position == null) return fallback;

      final cityName = await LocationService().getCityFromCoordinates(
        LatLng(position.latitude, position.longitude),
      );
      if (cityName == null || cityName.trim().isEmpty) return fallback;

      final matched = _matchSupportedCity(cityName);
      final resolved = matched ?? fallback;
      await setCurrentCity(resolved);
      return resolved;
    } catch (e) {
      return fallback;
    }
  }

  /// Fuzzy-matches a raw geocoded place name (e.g. "Erode", "Erode
  /// District", "Coimbatore North") against kSupportedCities' labels.
  /// Returns null if it doesn't match any known city yet -- rather than
  /// silently mis-tagging someone in an unlaunched city as the wrong
  /// one, we keep them on the previously cached/default value until
  /// their city is actually onboarded.
  static String? _matchSupportedCity(String rawPlaceName) {
    final normalized = rawPlaceName.trim().toLowerCase();
    for (final city in kSupportedCities) {
      if (normalized.contains(city.slug) || city.slug.contains(normalized)) {
        return city.slug;
      }
    }
    return null;
  }
}
