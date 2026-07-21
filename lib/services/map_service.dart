// lib/services/map_service.dart
// Strict Ola-first provider manager

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import 'map_provider.dart';
import 'ola_maps_provider.dart';
import 'osm_provider.dart';

enum MapProviderType { ola, osm }

class MapService extends ChangeNotifier {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  // Lazily-constructed providers.
  //
  // These were previously `late final` and assigned only inside
  // initialize(). Because initialize() early-returned on web, the fields
  // were never assigned there and every call site threw
  // LateInitializationError on the PWA build (the minified web build
  // reports it as "Field '' has not been initialized").
  //
  // Backing them with nullable fields + self-initializing getters makes
  // that failure mode structurally impossible on every platform: the
  // provider is constructed on first read, no matter which code path
  // gets there first. Both constructors are cheap and pure-Dart.
  MapProvider? _olaProviderInstance;
  MapProvider? _osmProviderInstance;

  MapProvider get _olaProvider => _olaProviderInstance ??= OlaMapsProvider();
  MapProvider get _osmProvider => _osmProviderInstance ??= OSMProvider();

  // ── Dynamic search-bias center ──────────────────────────────────
  // Erode-only search was hardcoded, so the search box wouldn't just
  // exclude other cities — it also over-restricted Erode itself and
  // caused irrelevant/empty results for local place names.
  // Screens can call setSearchCenter() with the customer's live
  // location so search is biased to whatever city they're actually
  // in. When unset (or the customer's location isn't available),
  // OSMProvider falls back to its built-in Erode default, so nothing
  // breaks for anyone who hasn't wired this up yet.
  LatLng? _searchCenterOverride;

  void setSearchCenter(LatLng? center) {
    _searchCenterOverride = center;
  }

  // Backed lazily for the same reason as the providers above: this field
  // initialiser used to run at singleton-construction time, constructing
  // an OlaMapsProvider — and therefore reading dotenv — before
  // ApiConfig.ensureEnvLoaded() had completed. Touching MapService() at
  // all was enough to snapshot an empty API key.
  MapProvider? _currentProviderInstance;
  MapProvider get _currentProvider =>
      _currentProviderInstance ??= _olaProvider;
  set _currentProvider(MapProvider provider) =>
      _currentProviderInstance = provider;

  MapProviderType _selectedProvider = MapProviderType.ola;
  bool _isInitialized = false;
  bool _isUsingFallback = false;
  String? _uiErrorMessage;

  MapProvider get currentProvider => _currentProvider;
  MapProviderType get selectedProvider => _selectedProvider;
  bool get isUsingFallback => _isUsingFallback;
  bool get isInitialized => _isInitialized;
  String? get uiErrorMessage => _uiErrorMessage;
  bool get hasUiError => _uiErrorMessage != null && _uiErrorMessage!.isNotEmpty;

  void markFailure() {
    if (_selectedProvider == MapProviderType.ola) {
      debugPrint('❌ Ola tile loading failed.');
      _uiErrorMessage = 'Map Error: Ola Maps tile loading failed';
      notifyListeners();
    }
  }

  Future<void> initialize() async {
    if (_isInitialized) return;

    // Guarantee .env is loaded before ANY provider is constructed or any
    // API key is read. Idempotent and race-safe, so it is correct no
    // matter which entrypoint reaches initialize() first — this is what
    // stops the empty-key state from being cached for the whole session.
    await ApiConfig.ensureEnvLoaded();

    // NOTE: There is deliberately no kIsWeb early-return here.
    // Both OlaMapsProvider and OSMProvider are pure HTTP clients
    // (package:http + dart:convert) with no native/platform-channel
    // dependencies, so they construct and operate correctly on web.
    // A previous early-return skipped the assignments below on web,
    // leaving _olaProvider/_osmProvider unassigned and causing every
    // search/reverseGeocode/getRoute call to throw
    // LateInitializationError on the PWA build.
    if (kIsWeb) {
      debugPrint('[MapService] Initializing map providers on Web');
    }

    try {
      debugPrint('[MapService] Starting initialization');
      _currentProvider = _olaProvider;
      _selectedProvider = MapProviderType.ola;
      _isUsingFallback = false;
      _uiErrorMessage = null;

      debugPrint(
        '[MapService] Ola API key present=${_olaProvider.apiKey.isNotEmpty} '
        'length=${_olaProvider.apiKey.length}',
      );

      bool olaAvailable = false;
      try {
        olaAvailable = await _olaProvider.isAvailable().timeout(
          const Duration(seconds: 5),
          onTimeout: () {
            debugPrint('⚠️ Ola Maps timeout while validating provider');
            return false;
          },
        );
      } catch (e) {
        debugPrint('⚠️ Ola Maps error during initialization: $e');
      }

      debugPrint('[MapService] Ola availability check result=$olaAvailable');
      if (!olaAvailable || _olaProvider.apiKey.isEmpty || _olaProvider.apiKey.length < 16) {
        final failureReason = (_olaProvider.apiKey.isEmpty || _olaProvider.apiKey.length < 16)
            ? 'Ola API key missing or invalid'
            : 'Ola Maps availability check failed (HTTP error or outdated endpoint)';
        debugPrint('ℹ️ MapService Ola failure reason: $failureReason');
        if (kIsWeb) {
          debugPrint(
            'ℹ️ Web Diagnostic: Ola Maps verification failed. '
            'Check domain allow-listing and endpoint compatibility in the Ola portal.',
          );
        }
        _uiErrorMessage = 'Map Error: $failureReason';
      }

      _isInitialized = true;
      notifyListeners();
    } catch (e) {
      debugPrint('❌ MapService init error: $e');
      _currentProvider = _olaProvider;
      _selectedProvider = MapProviderType.ola;
      _isUsingFallback = false;
      _isInitialized = true;
      _uiErrorMessage = 'Map Error: Ola Maps failed to initialize';
      notifyListeners();
    }
  }

  String getTileUrl(int x, int y, int z) {
    try {
      return _currentProvider.getTileUrl(x, y, z);
    } catch (e) {
      debugPrint('❌ Ola tile URL generation error: $e');
      _uiErrorMessage = 'Map Error: Ola tile URL generation failed';
      notifyListeners();
      rethrow;
    }
  }

  Future<List<Map<String, dynamic>>> search(String query) async {
    await initialize();

    // ── Ola FIRST, Nominatim as the fallback ──────────────────────
    //
    // This order used to be reversed, with a comment claiming "OLA Maps
    // does not index Erode streets well". That turned out to be the
    // wrong call: Ola's /places/v1/autocomplete is a proper Indian
    // local-places index and knows Erode shops and streets by name.
    // Nominatim does not.
    //
    // Worse, the old code returned OSM's results the moment they were
    // non-empty — so a single loosely-matching Nominatim hit was enough
    // to make sure Ola was never asked at all. Typing three letters of a
    // local place gave a list of irrelevant suggestions (or nothing),
    // while the provider that actually had the answer sat unused.
    try {
      final ola = _olaProvider as OlaMapsProvider;
      final results = await ola
          .searchNear(query, center: _searchCenterOverride)
          .timeout(
        const Duration(seconds: 6),
        onTimeout: () => <Map<String, dynamic>>[],
      );
      if (results.isNotEmpty) {
        debugPrint('[MapService] Ola: ${results.length} results for "$query"');
        _currentProvider = _olaProvider;
        _selectedProvider = MapProviderType.ola;
        _isUsingFallback = false;
        _uiErrorMessage = null;
        notifyListeners();
        return results;
      }
    } catch (e) {
      debugPrint('[MapService] Ola search error, trying Nominatim: $e');
    }

    // Nominatim fallback — only when Ola returns nothing (no API key,
    // network failure, or a genuinely unknown place).
    try {
      final osmResults = await searchNearErode(query);
      if (osmResults.isNotEmpty) {
        debugPrint(
          '[MapService] Nominatim fallback: ${osmResults.length} results for "$query"',
        );
        return osmResults;
      }
    } catch (e) {
      debugPrint('❌ Nominatim fallback error: $e');
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> searchNearErode(String query) async {
    await initialize();

    try {
      final osm = _osmProvider as OSMProvider;
      return await osm
          .searchNearErode(query, center: _searchCenterOverride)
          .timeout(
        const Duration(seconds: 6),
        onTimeout: () => <Map<String, dynamic>>[],
      );
    } catch (e) {
      debugPrint('🔎 Erode search error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> reverseGeocode(LatLng point) async {
    await initialize();

    try {
      final ola = _olaProvider as OlaMapsProvider;
      final result = await ola.reverseGeocode(point).timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
      if (result != null) {
        _currentProvider = _olaProvider;
        _selectedProvider = MapProviderType.ola;
        _isUsingFallback = false;
        _uiErrorMessage = null;
        notifyListeners();
        return result;
      }
    } catch (e) {
      debugPrint('Ola reverse geocode error, falling back to OSM: $e');
    }

    try {
      final osm = _osmProvider as OSMProvider;
      return await osm.reverseGeocode(point).timeout(
        const Duration(seconds: 6),
        onTimeout: () => null,
      );
    } catch (e) {
      debugPrint('📍 Reverse geocode error: $e');
      return null;
    }
  }

  Future<MapRouteResult?> getRoute(LatLng start, LatLng end) async {
    await initialize();

    try {
      final route = await _olaProvider.getRoute(start, end).timeout(
        const Duration(seconds: 8),
        onTimeout: () => throw Exception('Route timeout'),
      );
      if (route != null && route.points.length > 2) {
        _currentProvider = _olaProvider;
        _selectedProvider = MapProviderType.ola;
        _isUsingFallback = false;
        _uiErrorMessage = null;
        notifyListeners();
        return route;
      }
      if (route != null) {
        debugPrint(
          'Ola route returned only ${route.points.length} points; falling back to OSRM to avoid air-line route.',
        );
      }
    } catch (e) {
      debugPrint('❌ Ola route error: $e');
      debugPrint('Ola route error, falling back to OSRM: $e');
    }
    try {
      final osm = _osmProvider as OSMProvider;
      final route = await osm.getRoute(start, end).timeout(
        const Duration(seconds: 10),
        onTimeout: () => null,
      );
      if (route != null) {
        _uiErrorMessage = null;
        notifyListeners();
        return route;
      }
    } catch (e) {
      debugPrint('OSRM route fallback error: $e');
    }

    // Final fallback: Haversine straight-line distance (no mock data)
    debugPrint('Using Haversine direct distance as final fallback');
    final double distanceMeters = _haversineDistance(start, end);
    return MapRouteResult(
      points: <LatLng>[start, end],
      distanceMeters: distanceMeters,
      durationSeconds: distanceMeters / 8, // ~8 m/s avg bike speed
      instructions: 'Direct distance (route API unavailable)',
    );
  }

  double _haversineDistance(LatLng p1, LatLng p2) {
     const double r = 6371000.0;
     final double dLat = (p2.latitude - p1.latitude) * (math.pi / 180.0);
     final double dLon = (p2.longitude - p1.longitude) * (math.pi / 180.0);
     final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
         math.cos(p1.latitude * (math.pi / 180.0)) *
         math.cos(p2.latitude * (math.pi / 180.0)) *
         math.sin(dLon / 2) * math.sin(dLon / 2);
     return r * 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
   }

  Future<bool> isAvailable() async {
    await initialize();
    return _olaProvider.isAvailable();
  }

  String getProviderDisplayName() {
    switch (_selectedProvider) {
      case MapProviderType.ola:
        return 'Ola Maps';
      case MapProviderType.osm:
        return 'OpenStreetMap';
      default:
        return 'Unknown';
    }
  }

  Map<String, dynamic> getDebugInfo() {
    return {
      'selectedProvider': _selectedProvider.name,
      'currentProvider': _currentProvider.name,
      'isUsingFallback': _isUsingFallback,
      'isInitialized': _isInitialized,
      'uiErrorMessage': _uiErrorMessage,
    };
  }

  @override
  String toString() {
    return 'MapService(provider=${_selectedProvider.name}, fallback=$_isUsingFallback)';
  }
}
