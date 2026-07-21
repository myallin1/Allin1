import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

import '../config/api_config.dart';
import 'map_provider.dart';

class OlaMapsProvider extends MapProvider {
  OlaMapsProvider()
      : super(name: 'ola', apiKey: _validatedApiKey());

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

  // Default bias point, used only when no live centre is supplied.
  static const double _defaultBiasLat = 11.3410;
  static const double _defaultBiasLng = 77.7171;

  @override
  Future<List<Map<String, dynamic>>> search(String query) => searchNear(query);

  /// Autocomplete biased around [center] — pass the customer's live
  /// location so results follow whatever city they are actually in.
  ///
  /// This used to hardcode Erode twice: a '11.3410,77.7171' location
  /// param AND a ', Erode, Tamil Nadu' suffix glued onto the query. The
  /// suffix in particular actively hurt results — it turned a search for
  /// a local shop into a search for that shop *in a text string that
  /// already says Erode*, which Ola then had to disambiguate. The
  /// location+radius bias alone does the same job properly, and works
  /// unchanged when we open in a second city.
  Future<List<Map<String, dynamic>>> searchNear(
    String query, {
    LatLng? center,
  }) async {
    final trimmedQuery = query.trim();
    if (trimmedQuery.isEmpty) return [];
    if (apiKey.isEmpty) return [];

    final biasLat = center?.latitude ?? _defaultBiasLat;
    final biasLng = center?.longitude ?? _defaultBiasLng;

    try {
      final autocompleteUri = Uri.https(
        _placesHost,
        '$_placesBasePath/autocomplete',
        <String, String>{
          'input': trimmedQuery,
          'api_key': apiKey,
          'location': '$biasLat,$biasLng',
          'radius': '40000',
        },
      );
      final response = await http.get(
        autocompleteUri,
      ).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final predictions = _extractPlaceList(data);
        final results = <Map<String, dynamic>>[];

        // Predictions that already carry coordinates are free. Ones that
        // don't need a follow-up geocode call — those used to run one
        // after another inside this loop, up to 8 sequential HTTP
        // round-trips at a 10s timeout each, on every keystroke batch.
        // That alone could make autocomplete feel broken. Now they run
        // together, and only for the few that actually need it.
        final needsGeocode = <String>[];
        for (final item in predictions.take(8)) {
          final parsed = _parsePlaceResult(item);
          if (parsed != null) {
            results.add(parsed);
            continue;
          }
          final label = _extractDisplayText(item);
          if (label != null && label.trim().isNotEmpty) {
            needsGeocode.add(label);
          }
        }

        if (needsGeocode.isNotEmpty) {
          final geocoded = await Future.wait(
            needsGeocode.take(4).map(_geocodeAddress),
          );
          results.addAll(geocoded.whereType<Map<String, dynamic>>());
        }

        if (results.isNotEmpty) return _dedupeResults(results);

        final geocoded = await _geocodeAddress(trimmedQuery);
        return geocoded == null ? [] : <Map<String, dynamic>>[geocoded];
      }

      return [];
    } catch (e) {
      return [];
    }
  }

  Future<Map<String, dynamic>?> reverseGeocode(LatLng point) async {
    if (apiKey.isEmpty) return null;

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
      if (response.statusCode != 200) return null;

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
      if (response.statusCode != 200) return null;

      final data = json.decode(response.body);
      final places = _extractPlaceList(data);
      if (places.isNotEmpty) return _parsePlaceResult(places.first);
      return _parsePlaceResult(data);
    } catch (e) {
      return null;
    }
  }

  List<dynamic> _extractPlaceList(dynamic data) {
    if (data is List) return data;
    if (data is! Map) return const [];

    for (final key in const <String>[
      'predictions',
      'suggestions',
      'results',
      'data',
      'features',
      'places',
    ]) {
      final value = data[key];
      if (value is List) return value;
      if (value is Map) {
        final nested = _extractPlaceList(value);
        if (nested.isNotEmpty) return nested;
      }
    }
    return const [];
  }

  Map<String, dynamic>? _parsePlaceResult(
    dynamic item, {
    LatLng? fallbackPoint,
  }) {
    if (item is! Map) return null;

    final lat = _extractLatitude(item) ?? fallbackPoint?.latitude;
    final lng = _extractLongitude(item) ?? fallbackPoint?.longitude;
    if (lat == null || lng == null || (lat == 0.0 && lng == 0.0)) return null;

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

  String? _extractDisplayText(dynamic item) {
    if (item is! Map) return null;

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
      if (value != null && value.isNotEmpty) return value;
    }

    final structured = item['structured_formatting'];
    if (structured is Map) {
      final main = structured['main_text']?.toString().trim();
      final secondary = structured['secondary_text']?.toString().trim();
      if (main != null && main.isNotEmpty) {
        return secondary == null || secondary.isEmpty ? main : '$main, $secondary';
      }
    }

    return null;
  }

  String? _extractPrimaryText(dynamic item) {
    if (item is! Map) return null;
    for (final key in const <String>['name', 'main_text', 'title']) {
      final value = item[key]?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final structured = item['structured_formatting'];
    if (structured is Map) {
      final value = structured['main_text']?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    final terms = item['terms'];
    if (terms is List && terms.isNotEmpty && terms.first is Map) {
      final value = (terms.first as Map)['value']?.toString().trim();
      if (value != null && value.isNotEmpty) return value;
    }
    return null;
  }

  double? _extractLatitude(dynamic item) {
    if (item is! Map) return null;
    final coordinates = item['geometry']?['coordinates'];
    return _asDouble(item['lat']) ??
        _asDouble(item['latitude']) ??
        _asDouble(item['geometry']?['location']?['lat']) ??
        _asDouble(item['location']?['lat']) ??
        _asDouble(_coordinateAt(coordinates, 1));
  }

  double? _extractLongitude(dynamic item) {
    if (item is! Map) return null;
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

  dynamic _coordinateAt(dynamic coordinates, int index) {
    if (coordinates is List && coordinates.length > index) {
      return coordinates[index];
    }
    return null;
  }

  double? _asDouble(dynamic value) {
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value.trim());
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
