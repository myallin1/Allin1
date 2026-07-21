// ================================================================
// location_link_parser.dart
//
// Pulls coordinates out of whatever a customer pastes or shares in.
//
// The important thing to know: a location shared from WhatsApp itself
// carries its coordinates in plain sight —
//
//     https://maps.google.com/?q=11.341000,77.717100
//
// so there is nothing to look up and no network call to make. We just
// read the numbers. That is why this whole feature works identically on
// the PWA and the native APK.
//
// The one case we genuinely cannot handle client-side is a SHORTENED
// link (https://maps.app.goo.gl/xY7bK2mNp), which Google Maps' own
// "Share" produces. The coordinates are hidden behind a redirect, and
// following that redirect from a browser is blocked by CORS. Rather
// than fail silently, parse() reports that case distinctly so the UI
// can offer the map picker instead of leaving the customer stuck.
// ================================================================

/// What came back from a parse attempt.
enum LocationLinkResultKind {
  /// Coordinates were found and are ready to use.
  resolved,

  /// Recognised as a shortened map link whose coordinates can't be read
  /// without a server round-trip. Caller should offer the map picker.
  shortLink,

  /// Nothing location-shaped in the input at all.
  notFound,
}

class LocationLinkResult {
  final LocationLinkResultKind kind;
  final double? lat;
  final double? lng;

  /// Any human-readable place name we could salvage from the link
  /// (Google Maps /place/ URLs carry one). Often null.
  final String? label;

  const LocationLinkResult._(this.kind, {this.lat, this.lng, this.label});

  const LocationLinkResult.resolved({
    required double lat,
    required double lng,
    String? label,
  }) : this._(
          LocationLinkResultKind.resolved,
          lat: lat,
          lng: lng,
          label: label,
        );

  const LocationLinkResult.shortLink()
      : this._(LocationLinkResultKind.shortLink);

  const LocationLinkResult.notFound()
      : this._(LocationLinkResultKind.notFound);

  bool get isResolved => kind == LocationLinkResultKind.resolved;
  bool get isShortLink => kind == LocationLinkResultKind.shortLink;
}

class LocationLinkParser {
  LocationLinkParser._();

  // Known URL shorteners used by map apps. Coordinates are not in the
  // text, so these need a redirect we can't follow from the browser.
  static const List<String> _shortHosts = <String>[
    'maps.app.goo.gl',
    'goo.gl',
    'g.co',
    'maps.google.com/url',
  ];

  // A latitude/longitude pair anywhere in the text. Latitude is capped
  // at ±90 and longitude at ±180 by _isPlausible() rather than by the
  // pattern, which keeps the pattern readable.
  static final RegExp _coordPair = RegExp(
    r'(-?\d{1,3}\.\d{4,})\s*,\s*(-?\d{1,3}\.\d{4,})',
  );

  // Google Maps' "@lat,lng,zoom" form: .../@11.3410,77.7171,17z/...
  static final RegExp _atCoords = RegExp(
    r'@(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)',
  );

  // geo:11.3410,77.7171 — the Android standard location URI.
  static final RegExp _geoUri = RegExp(
    r'geo:(-?\d{1,3}\.\d+),(-?\d{1,3}\.\d+)',
    caseSensitive: false,
  );

  /// Reads [input] — a pasted link, a shared message, or just typed
  /// numbers — and reports what it found.
  static LocationLinkResult parse(String input) {
    final text = input.trim();
    if (text.isEmpty) return const LocationLinkResult.notFound();

    // 1. geo: URI — unambiguous, check it first.
    final geo = _geoUri.firstMatch(text);
    if (geo != null) {
      final result = _build(geo.group(1), geo.group(2));
      if (result != null) return result;
    }

    // 2. Explicit query params. WhatsApp's own location share uses ?q=,
    //    and several Maps URL shapes use ?query= or ?ll=.
    final uri = _tryParseUri(text);
    if (uri != null) {
      for (final key in const ['q', 'query', 'll', 'daddr', 'destination']) {
        final value = uri.queryParameters[key];
        if (value == null) continue;
        final match = _coordPair.firstMatch(value);
        if (match != null) {
          final result = _build(match.group(1), match.group(2));
          if (result != null) return result;
        }
      }
    }

    // 3. The @lat,lng form inside a full Google Maps place URL.
    final at = _atCoords.firstMatch(text);
    if (at != null) {
      final result = _build(at.group(1), at.group(2), label: _placeName(text));
      if (result != null) return result;
    }

    // 4. A bare coordinate pair anywhere in the text. This also covers a
    //    customer simply typing "11.3410, 77.7171".
    final loose = _coordPair.firstMatch(text);
    if (loose != null) {
      final result = _build(loose.group(1), loose.group(2));
      if (result != null) return result;
    }

    // 5. Nothing readable — but if it's a known shortener, say so, so
    //    the UI can react helpfully instead of just "invalid link".
    if (_shortHosts.any(text.toLowerCase().contains)) {
      return const LocationLinkResult.shortLink();
    }

    return const LocationLinkResult.notFound();
  }

  static Uri? _tryParseUri(String text) {
    // Shared messages are often "Check this out: https://... — see you"
    // rather than a bare URL, so pull the URL out of the sentence first.
    final match = RegExp(r'https?://\S+').firstMatch(text);
    final candidate = match?.group(0) ?? text;
    try {
      return Uri.parse(candidate);
    } catch (_) {
      return null;
    }
  }

  /// Google Maps place URLs embed the name as a path segment:
  /// .../maps/place/Erode+Bus+Stand/@11.34,77.71,17z/
  static String? _placeName(String text) {
    final match = RegExp(r'/place/([^/@]+)').firstMatch(text);
    final raw = match?.group(1);
    if (raw == null || raw.isEmpty) return null;
    try {
      return Uri.decodeComponent(raw.replaceAll('+', ' ')).trim();
    } catch (_) {
      return null;
    }
  }

  static LocationLinkResult? _build(String? latText, String? lngText,
      {String? label,}) {
    final lat = double.tryParse(latText ?? '');
    final lng = double.tryParse(lngText ?? '');
    if (lat == null || lng == null) return null;
    if (!_isPlausible(lat, lng)) return null;
    return LocationLinkResult.resolved(lat: lat, lng: lng, label: label);
  }

  static bool _isPlausible(double lat, double lng) {
    if (lat.abs() > 90 || lng.abs() > 180) return false;
    // Exactly (0, 0) is Null Island — always a parsing artefact, never a
    // real pickup point for this app.
    if (lat == 0 && lng == 0) return false;
    return true;
  }
}
