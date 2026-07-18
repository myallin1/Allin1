import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import 'map_provider.dart';

class OlaMapsProvider extends MapProvider {
  OlaMapsProvider() : super(name: 'ola', apiKey: _validatedApiKey());

  static String _validatedApiKey() {
    final rawKey = ApiConfig.olaMapsApiKey;
    final normalizedKey = rawKey.trim();
    return normalizedKey;
  }

  static const String _placesHost = 'api.olamaps.io';
  static const String _placesBasePath = '/places/v1';

  @override
  String getTileUrl(int x, int y, int z) {
    return 'https://tile.openstreetmap.org/$z/$x/$y.png';
  }

  @override
  Future<bool> isAvailable() async {
    return apiKey.isNotEmpty && apiKey.length >= 16;
  }

  @override
  Future<List<Map<String, dynamic>>> search(String query) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) {
      return [];
    }
    if (apiKey.isEmpty) {
      return [];
    }

    try {
      final erodeBiasedQuery = trimmedQuery.toLowerCase().contains('erode')
          ? trimmedQuery
          : '$trimmedQuery, Erode, Tamil Nadu';
      final autocompleteUri = Uri.https(
        _placesHost,
        '$_placesBasePath/autocomplete',
        <String, String>{
          'input': erodeBiasedQuery,
          'api_key': apiKey,
          'location': '11.3410,77.7171',
          'radius': '40000',
        },
      );
      final response = await http
          .get(
            autocompleteUri,
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = _extractPlaceList(data);
        final results = <Map<String, dynamic>>[];

        for (final item in predictions.take(8)) {
          final parsed = _parsePlaceResult(item);
          if (parsed != null) {
            results.add(parsed);
            continue;
          }

          final label = _extractDisplayText(item);
          if (label == null || label.trim().isEmpty) {
            continue;
          }

          final geocoded = await _geocodeAddress(
            label.toLowerCase().contains('erode')
                ? label
                : '$label, Erode, Tamil Nadu',
          );
          if (geocoded != null) {
            results.add(geocoded);
          }
        }

        if (results.isNotEmpty) {
          return _dedupeResults(results);
        }

        final geocoded = await _geocodeAddress(erodeBiasedQuery);
        return geocoded == null ? [] : <Map<String, dynamic>>[geocoded];
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> reverseGeocode(LatLng point) async {
    if (apiKey.isEmpty) {
      return null;
    }

    try {
      final uri = Uri.https(
        _placesHost,
        '$_placesBasePath/reverse-geocode',
        <String, String>{
          'latlng': '${point.latitude},${point.longitude}',
          'api_key': apiKey,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body);
      final places = _extractPlaceList(data);
      if (places.isNotEmpty) {
        return _parsePlaceResult(places.first, fallbackPoint: point);
      }
      return _parsePlaceResult(data, fallbackPoint: point);
    } catch (e) {
      return null;
    }
  }

  Future<Map<String, dynamic>?> _geocodeAddress(String address) async {
    try {
      final uri = Uri.https(
        _placesHost,
        '$_placesBasePath/geocode',
        <String, String>{
          'address': address,
          'api_key': apiKey,
        },
      );
      final response = await http.get(uri).timeout(const Duration(seconds: 10));
      if (response.statusCode != 200) {
        return null;
      }

      final data = json.decode(response.body);
      final places = _extractPlaceList(data);
      if (places.isNotEmpty) {
        return _parsePlaceResult(places.first);
      }
      return _parsePlaceResult(data);
    } catch (e) {
      return null;
    }
  }

  List<dynamic> _extractPlaceList(Object? data) {
    if (data is List) {
      return data;
    }
    if (data is! Map) {
      return const [];
    }

    for (final key in const <String>[
      'predictions',
      'suggestions',
      'results',
      'data',
      'features',
      'places',
    ]) {
      final value = data[key];
      if (value is List) {
        return value;
      }
      if (value is Map) {
        final nested = _extractPlaceList(value);
        if (nested.isNotEmpty) {
          return nested;
        }
      }
    }
    return const [];
  }

  Map<String, dynamic>? _parsePlaceResult(
    Object? item, {
    LatLng? fallbackPoint,
  }) {
    if (item is! Map) {
      return null;
    }

    final lat = _extractLatitude(item) ?? fallbackPoint?.latitude;
    final lng = _extractLongitude(item) ?? fallbackPoint?.longitude;
    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) {
      return null;
    }

    final full = _extractDisplayText(item) ?? 'Selected location';
    final name = _extractPrimaryText(item) ?? full.split(',').first.trim();

    return <String, dynamic>{
      'name': name.isEmpty ? full : name,
      'full': full,
      'lat': lat,
      'lng': lng,
      'provider': 'ola',
      'type': item['type'] ?? item['place_type'] ?? item['types'] ?? 'place',
    };
  }

  String? _extractDisplayText(Object? item) {
    if (item is! Map) {
      return null;
    }

    for (final key in const <String>[
      'formatted_address',
      'formattedAddress',
      'description',
      'display_name',
      'displayName',
      'address',
      'name',
      'vicinity',
    ]) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }

    final structured = item['structured_formatting'];
    if (structured is Map) {
      final main = structured['main_text']?.toString().trim();
      final secondary = structured['secondary_text']?.toString().trim();
      if (main != null && main.isNotEmpty) {
        return secondary == null || secondary.isEmpty
            ? main
            : '$main, $secondary';
      }
    }

    return null;
  }

  String? _extractPrimaryText(Object? item) {
    if (item is! Map) {
      return null;
    }
    for (final key in const <String>['name', 'main_text', 'title']) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final structured = item['structured_formatting'];
    if (structured is Map) {
      final value = structured['main_text']?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    final terms = item['terms'];
    if (terms is List && terms.isNotEmpty && terms.first is Map) {
      final value = (terms.first as Map)['value']?.toString().trim();
      if (value != null && value.isNotEmpty) {
        return value;
      }
    }
    return null;
  }

  double? _extractLatitude(Object? item) {
    if (item is! Map) {
      return null;
    }
    final coordinates = item['geometry']?['coordinates'];
    return _asDouble(item['lat']) ??
        _asDouble(item['latitude']) ??
        _asDouble(item['geometry']?['location']?['lat']) ??
        _asDouble(item['location']?['lat']) ??
        _asDouble(_coordinateAt(coordinates, 1));
  }

  double? _extractLongitude(Object? item) {
    if (item is! Map) {
      return null;
    }
    final coordinates = item['geometry']?['coordinates'];
    return _asDouble(item['lng']) ??
        _asDouble(item['lon']) ??
        _asDouble(item['longitude']) ??
        _asDouble(item['geometry']?['location']?['lng']) ??
        _asDouble(item['geometry']?['location']?['lon']) ??
        _asDouble(item['location']?['lng']) ??
        _asDouble(item['location']?['lon']) ??
        _asDouble(_coordinateAt(coordinates, 0));
  }

  dynamic _coordinateAt(Object? coordinates, int index) {
    if (coordinates is List && coordinates.length > index) {
      return coordinates[index];
    }
    return null;
  }

  double? _asDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    if (value is String) {
      return double.tryParse(value.trim());
    }
    return null;
  }

  List<Map<String, dynamic>> _dedupeResults(
    List<Map<String, dynamic>> results,
  ) {
    final seen = <String>{};
    final deduped = <Map<String, dynamic>>[];
    for (final result in results) {
      final key = '${result['name']}|${result['lat']}|${result['lng']}';
      if (seen.add(key)) {
        deduped.add(result);
      }
    }
    return deduped;
  }

  @override
  Future<MapRouteResult?> getRoute(LatLng start, LatLng end) async {
    return null;
  }
}
