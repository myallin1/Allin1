// ================================================================
// VoiceBookingIntentService — "MyAllin1 Super Hero", Pro tier
// ================================================================
// Parses a Pro customer's spoken command (already transcribed to text
// by speech_to_text in guru_chat_screen.dart) into a service type +
// destination, resolves that destination to real coordinates via the
// existing MapService/Ola Maps search pipeline, and hands back a result
// the UI can act on directly — auto-navigating to the booking screen
// with the destination pre-filled, per Nizam's explicit instruction
// ("Do not just reply with text; execute the action").
//
// Kept deliberately simple and offline-first (pure keyword/regex
// matching, no extra LLM round-trip): the vocabulary is small and fixed
// (7 services), so a second network call to parse intent would only add
// latency and another point of failure for something regex handles
// reliably. If the vocabulary grows a lot later, this is the one place
// to swap in an LLM-based parse.
import 'package:latlong2/latlong.dart';

import 'map_service.dart';

enum VoiceService { bike, auto, cab, parcel, miniTruck, lorry, sos }

class VoiceBookingIntent {
  const VoiceBookingIntent({
    required this.service,
    this.destinationQuery,
    this.destination,
  });

  final VoiceService service;
  // Raw text the customer said as the destination (e.g. "Erode Railway
  // Station"), before geocoding. Null for SOS (no destination needed).
  final String? destinationQuery;
  // Resolved place, in the same {name, full, lat, lng} shape
  // BikeBookingScreen's own search flow already uses — null until/unless
  // geocoding succeeds.
  final Map<String, dynamic>? destination;

  bool get needsDestination => service != VoiceService.sos;
  bool get isResolved => !needsDestination || destination != null;

  VoiceBookingIntent copyWith({Map<String, dynamic>? destination}) {
    return VoiceBookingIntent(
      service: service,
      destinationQuery: destinationQuery,
      destination: destination ?? this.destination,
    );
  }

  String get categoryKey {
    switch (service) {
      case VoiceService.bike:
        return 'bike';
      case VoiceService.auto:
        return 'auto';
      case VoiceService.cab:
        return 'cab';
      case VoiceService.parcel:
        return 'parcel';
      case VoiceService.miniTruck:
        return 'mini_truck';
      case VoiceService.lorry:
        return 'lorry';
      case VoiceService.sos:
        return 'sos';
    }
  }

  String get displayName {
    switch (service) {
      case VoiceService.bike:
        return 'Bike';
      case VoiceService.auto:
        return 'Auto';
      case VoiceService.cab:
        return 'Cab';
      case VoiceService.parcel:
        return 'Parcel';
      case VoiceService.miniTruck:
        return 'Mini Truck';
      case VoiceService.lorry:
        return 'Lorry';
      case VoiceService.sos:
        return 'SOS';
    }
  }
}

class VoiceBookingIntentService {
  // Longer/more-specific phrases first so "mini truck" wins over a bare
  // "truck" or "auto" false-positive inside another word.
  static const List<MapEntry<String, VoiceService>> _servicePatterns = [
    MapEntry('mini truck', VoiceService.miniTruck),
    MapEntry('minitruck', VoiceService.miniTruck),
    MapEntry('mini-truck', VoiceService.miniTruck),
    MapEntry('lorry', VoiceService.lorry),
    MapEntry('truck', VoiceService.miniTruck),
    MapEntry('parcel', VoiceService.parcel),
    MapEntry('courier', VoiceService.parcel),
    MapEntry('package', VoiceService.parcel),
    MapEntry('emergency', VoiceService.sos),
    MapEntry('sos', VoiceService.sos),
    MapEntry('help me', VoiceService.sos),
    MapEntry('cab', VoiceService.cab),
    MapEntry('car', VoiceService.cab),
    MapEntry('taxi', VoiceService.cab),
    MapEntry('auto', VoiceService.auto),
    MapEntry('rickshaw', VoiceService.auto),
    MapEntry('bike', VoiceService.bike),
    MapEntry('two wheeler', VoiceService.bike),
  ];

  // Matches "... to <destination>", "... at <destination>",
  // "... for <destination>", "... near <destination>" — whichever comes
  // last in the utterance, so "book an auto to the railway station"
  // yields "the railway station".
  static final RegExp _destinationPattern = RegExp(
    r'\b(?:to|at|for|near|towards?)\s+(.+)$',
    caseSensitive: false,
  );

  /// Step 1 (pure, synchronous, no network): figure out which service
  /// the customer meant and what destination text (if any) they said.
  /// Returns null if no known service keyword was found at all — the
  /// caller should fall back to a normal AI chat reply in that case.
  VoiceBookingIntent? parse(String utterance) {
    final lower = utterance.toLowerCase().trim();
    if (lower.isEmpty) return null;

    VoiceService? matched;
    for (final entry in _servicePatterns) {
      if (lower.contains(entry.key)) {
        matched = entry.value;
        break;
      }
    }
    if (matched == null) return null;

    if (matched == VoiceService.sos) {
      return VoiceBookingIntent(service: matched);
    }

    final destMatch = _destinationPattern.firstMatch(lower);
    String? destinationQuery;
    if (destMatch != null) {
      destinationQuery = destMatch.group(1)?.trim();
    }
    // Strip a trailing service word the destination regex might have
    // swallowed if the customer phrased it as e.g. "auto to home please
    // book" (rare, but keeps the query clean).
    if (destinationQuery != null && destinationQuery.isEmpty) {
      destinationQuery = null;
    }

    return VoiceBookingIntent(
      service: matched,
      destinationQuery: destinationQuery,
    );
  }

  /// Step 2 (async, hits the network): resolve the parsed destination
  /// text into real coordinates via the same Ola Maps / Nominatim search
  /// pipeline BikeBookingScreen's own address search already uses, so
  /// the pre-filled pin lands on a real, familiar geocoding result.
  /// Returns the intent unchanged (destination still null) if resolution
  /// isn't needed (SOS), wasn't attempted (no destination text heard),
  /// or the search came back empty.
  Future<VoiceBookingIntent> resolve(
    VoiceBookingIntent intent, {
    LatLng? biasCenter,
  }) async {
    if (!intent.needsDestination) return intent;
    final query = intent.destinationQuery;
    if (query == null || query.isEmpty) return intent;

    try {
      if (biasCenter != null) {
        MapService().setSearchCenter(biasCenter);
      }
      final results = await MapService().search(query);
      if (results.isEmpty) return intent;
      return intent.copyWith(destination: results.first);
    } catch (_) {
      return intent;
    }
  }
}
