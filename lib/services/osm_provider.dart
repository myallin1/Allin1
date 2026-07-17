// lib/services/osm_provider.dart
// OpenStreetMap Provider Implementation
// Uses: Nominatim (search) + OSRM (routing) + CartoCDN (tiles)
// ─────────────────────────────────────────────

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'map_provider.dart';

class OSMProvider extends MapProvider {
  OSMProvider() : super(name: 'osm');

  // CartoCDN Dark Matter tiles (matches current visual style)
  static const List<String> _subdomains = ['a', 'b', 'c', 'd'];
  static const double _erodeCenterLat = 11.3410;
  static const double _erodeCenterLng = 77.7172;
  static const double _erodeRadiusDegrees = 0.27; // ~30km bias box

  @override
  String getTileUrl(int x, int y, int z) {
    final subdomain = _subdomains[(x + y) % _subdomains.length];
    return 'https://$subdomain.basemaps.cartocdn.com/rastertiles/voyager/$z/$x/$y.png';
  }

  @override
  Future<List<Map<String, dynamic>>> search(String query) async {
    if (query.trim().isEmpty) return [];

    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?'
          'q=${Uri.encodeComponent(query)}'
          '&format=json&limit=5&addressdetails=1',
        ),
        headers: {
          'User-Agent': 'Allin1SuperApp/1.0',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body) as List;
        return data
            .map((item) {
              // FIX #1: Safe lat/lng parsing with .toString() to prevent type crashes
              final latStr = item['lat']?.toString() ?? '0';
              final lngStr = item['lon']?.toString() ?? '0';

              return {
                'name': item['display_name'] ?? 'Unknown',
                'lat': double.tryParse(latStr) ?? 0.0,
                'lng': double.tryParse(lngStr) ?? 0.0,
                'provider': 'osm',
                'type': item['type'] ?? 'unknown',
              };
            })
            .where((item) => item['lat'] != 0.0 && item['lng'] != 0.0)
            .toList();
      }
      return [];
    } catch (e) {
      print('❌ OSM Search error: $e');
      return [];
    }
  }

  Future<List<Map<String, dynamic>>> searchNearErode(String query) async {
    if (query.trim().length < 3) return [];

    const west = _erodeCenterLng - _erodeRadiusDegrees;
    const east = _erodeCenterLng + _erodeRadiusDegrees;
    const north = _erodeCenterLat + _erodeRadiusDegrees;
    const south = _erodeCenterLat - _erodeRadiusDegrees;

    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?'
          'q=${Uri.encodeComponent(query)}'
          '&format=jsonv2'
          '&limit=8'
          '&addressdetails=1'
          '&countrycodes=in'
          '&bounded=1'
          '&dedupe=1'
          '&viewbox=$west,$north,$east,$south',
        ),
        headers: {
          'User-Agent': 'Allin1SuperApp/1.0',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return [];
      }

      final data = json.decode(response.body) as List<dynamic>;
      return data
          .map((item) {
            final map = item as Map<String, dynamic>;
            final lat = double.tryParse(map['lat']?.toString() ?? '');
            final lng = double.tryParse(map['lon']?.toString() ?? '');
            if (lat == null || lng == null) {
              return null;
            }
            final full = map['display_name']?.toString() ?? '';
            final shortName = full.split(',').first.trim();
            return <String, dynamic>{
              'name': shortName.isEmpty ? full : shortName,
              'full': full,
              'lat': lat,
              'lng': lng,
              'provider': 'osm',
              'type': map['type'] ?? 'place',
            };
          })
          .whereType<Map<String, dynamic>>()
          .toList();
    } catch (e) {
      print('❌ OSM Erode Search error: $e');
      return [];
    }
  }

  Future<Map<String, dynamic>?> reverseGeocode(LatLng point) async {
    try {
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/reverse?'
          'format=jsonv2'
          '&lat=${point.latitude}'
          '&lon=${point.longitude}'
          '&zoom=18'
          '&addressdetails=1',
        ),
        headers: {
          'User-Agent': 'Allin1SuperApp/1.0',
          'Accept-Language': 'en',
        },
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body) as Map<String, dynamic>;
      final displayName = data['display_name']?.toString().trim();
      if (displayName == null || displayName.isEmpty) {
        return null;
      }

      final address = data['address'] as Map<String, dynamic>? ?? const {};
      final primary = [
        address['road'],
        address['suburb'],
        address['neighbourhood'],
        address['quarter'],
        address['city_district'],
      ].whereType<String>().firstWhere(
            (value) => value.trim().isNotEmpty,
            orElse: () => displayName.split(',').first.trim(),
          );

      return <String, dynamic>{
        'name': primary,
        'full': displayName,
        'lat': point.latitude,
        'lng': point.longitude,
        'provider': 'osm',
        'type': 'reverse',
      };
    } catch (e) {
      print('❌ OSM Reverse Geocode error: $e');
      return null;
    }
  }

  @override
  Future<MapRouteResult?> getRoute(LatLng start, LatLng end) async {
    try {
      // OSRM routing service (free, no API key)
      final response = await http
          .get(
            Uri.parse(
              'https://router.project-osrm.org/route/v1/driving/'
              '${start.longitude.toStringAsFixed(6)},${start.latitude.toStringAsFixed(6)};'
              '${end.longitude.toStringAsFixed(6)},${end.latitude.toStringAsFixed(6)}'
              '?overview=full&geometries=geojson&steps=false',
            ),
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final routes = data['routes'] as List?;
        if (data['code'] == 'Ok' && routes != null && routes.isNotEmpty) {
          final route = routes[0];
          // FIX #2: Explicitly type geometry as List?
          final geometry = route['geometry']?['coordinates'] as List?;

          if (geometry == null) return null;

          // FIX #3: Safe coordinate conversion with (num).toDouble()
          final points = geometry.map<LatLng>((coord) {
            return LatLng(
              (coord[1] as num).toDouble(),
              (coord[0] as num).toDouble(),
            );
          }).toList();

          return MapRouteResult(
            points: points,
            distanceMeters: (route['distance'] as num?)?.toDouble() ?? 0.0,
            durationSeconds: (route['duration'] as num?)?.toDouble() ?? 0.0,
          );
        }
      }
      return null;
    } catch (e) {
      print('❌ OSM Route error: $e');
      return null;
    }
  }

  @override
  Future<bool> isAvailable() async {
    try {
      // FIX #4: Ping real search query instead of root URL
      final response = await http.get(
        Uri.parse(
          'https://nominatim.openstreetmap.org/search?q=Erode&format=json&limit=1',
        ),
        headers: {'User-Agent': 'Allin1SuperApp/1.0'},
      ).timeout(const Duration(seconds: 5));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }
}
