// lib/services/map_service.dart
// Strict Ola-first provider manager

import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:latlong2/latlong.dart';

import 'map_provider.dart';
import 'ola_maps_provider.dart';
import 'osm_provider.dart';

enum MapProviderType { ola, osm }

class MapService extends ChangeNotifier {
  static final MapService _instance = MapService._internal();
  factory MapService() => _instance;
  MapService._internal();

  late final MapProvider _olaProvider;
  late final MapProvider _osmProvider;

  MapProvider _currentProvider = OlaMapsProvider();
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
    if (_isInitialized) {
      return;
    }

    if (kIsWeb) {
      debugPrint('[MapService] Skipping native map init on Web');
      return;
    }

    try {
      debugPrint('[MapService] Starting initialization');
      _olaProvider = OlaMapsProvider();
      _osmProvider = OSMProvider();
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
      if (!olaAvailable ||
          _olaProvider.apiKey.isEmpty ||
          _olaProvider.apiKey.length < 16) {
        final failureReason = (_olaProvider.apiKey.isEmpty ||
                _olaProvider.apiKey.length < 16)
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
      _olaProvider = OlaMapsProvider();
      _osmProvider = OSMProvider();
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

    // OSM Nominatim first — accurate for Erode local places.
    // OLA Maps does not index Erode streets well, so Nominatim
    // with bounded Erode viewbox is the primary search source.
    try {
      final osmResults = await searchNearErode(query);
      if (osmResults.isNotEmpty) {
        debugPrint(
          '[MapService] Nominatim: ${osmResults.length} results for "$query"',
        );
        return osmResults;
      }
    } catch (e) {
      debugPrint('[MapService] Nominatim error, trying Ola: $e');
    }

    // OLA fallback — only when Nominatim returns empty.
    try {
      final results = await _olaProvider.search(query).timeout(
            const Duration(seconds: 5),
            onTimeout: () => throw Exception('Search timeout'),
          );
      if (results.isNotEmpty) {
        _currentProvider = _olaProvider;
        _selectedProvider = MapProviderType.ola;
        _isUsingFallback = false;
        _uiErrorMessage = null;
        notifyListeners();
        return results;
      }
    } catch (e) {
      debugPrint('❌ Ola search fallback error: $e');
    }

    return [];
  }

  Future<List<Map<String, dynamic>>> searchNearErode(String query) async {
    await initialize();

    try {
      final osm = _osmProvider as OSMProvider;
      return await osm.searchNearErode(query).timeout(
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
    const double r = 6371000;
    final double dLat = (p2.latitude - p1.latitude) * (math.pi / 180.0);
    final double dLon = (p2.longitude - p1.longitude) * (math.pi / 180.0);
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(p1.latitude * (math.pi / 180.0)) *
            math.cos(p2.latitude * (math.pi / 180.0)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
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
