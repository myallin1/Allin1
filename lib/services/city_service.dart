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
import 'package:shared_preferences/shared_preferences.dart';

import '../config/city_config.dart';

class CityService {
  static const String _prefsKey = 'selected_city';

  static Future<String> getCurrentCity() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_prefsKey) ?? kDefaultCity;
  }

  static Future<void> setCurrentCity(String citySlug) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, citySlug);
  }
}
