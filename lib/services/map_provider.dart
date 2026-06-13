// lib/services/map_provider.dart
// Dual Map Provider Architecture | Ola + OSM
// ─────────────────────────────────────────────

import 'package:latlong2/latlong.dart';

/// Abstract interface for all map providers
abstract class MapProvider {
  final String name;
  final String apiKey;

  MapProvider({required this.name, this.apiKey = ''});

  /// Search for locations (geocoding)
  Future<List<Map<String, dynamic>>> search(String query);

  /// Get route between two points
  Future<MapRouteResult?> getRoute(LatLng start, LatLng end);

  /// Get tile URL for rendering (Pure URL generation)
  String getTileUrl(int x, int y, int z);

  /// Check if provider is available
  Future<bool> isAvailable();
}

/// Route result model
class MapRouteResult {
  final List<LatLng> points;
  final double distanceMeters;
  final double durationSeconds;
  final String? instructions;

  MapRouteResult({
    required this.points,
    required this.distanceMeters,
    required this.durationSeconds,
    this.instructions,
  });

  /// Get human-readable distance
  String get distanceText {
    if (distanceMeters < 1000) {
      return '${distanceMeters.toStringAsFixed(0)}m';
    }
    return '${(distanceMeters / 1000).toStringAsFixed(1)}km';
  }

  /// Get human-readable duration
  String get durationText {
    final minutes = (durationSeconds / 60).round();
    if (minutes < 60) {
      return '${minutes}min';
    }
    final hours = minutes ~/ 60;
    final remainingMins = minutes % 60;
    return '${hours}h ${remainingMins}m';
  }
}
