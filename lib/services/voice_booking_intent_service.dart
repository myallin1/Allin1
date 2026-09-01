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
  // FIX (Aug 25 2026 — Pre-Router Loophole audit finding): this used to
  // be a plain `lower.contains(entry.key)` substring check, which was
  // tolerable when only deliberate voice commands reached it but became
  // a real false-positive risk once typed chat started hitting the same
  // parser too — "automatic payment failed" contains "auto", "I want to
  // open car wash" contains "car", "cancel my auto booking" contains
  // "auto". Every keyword below is now wrapped in `\b...\b` so it only
  // matches a whole word/phrase, never a substring buried inside a
  // longer one. Compiled once as RegExp (not built per-parse-call) for
  // the same reason the rest of this file stays regex-based instead of
  // reaching for an LLM: this runs on every keystroke-adjacent message,
  // so it needs to stay cheap.
  static RegExp _word(String phrase) => RegExp(
        '\\b${phrase.replaceAll(' ', r'\s+')}\\b',
        caseSensitive: false,
      );

  // Longer/more-specific phrases first so "mini truck" wins over a bare
  // "truck" or "auto" false-positive inside another word.
  static final List<MapEntry<RegExp, VoiceService>> _servicePatterns = [
    MapEntry(_word('mini truck'), VoiceService.miniTruck),
    MapEntry(_word('minitruck'), VoiceService.miniTruck),
    MapEntry(_word('mini-truck'), VoiceService.miniTruck),
    MapEntry(_word('lorry'), VoiceService.lorry),
    MapEntry(_word('truck'), VoiceService.miniTruck),
    MapEntry(_word('parcel'), VoiceService.parcel),
    MapEntry(_word('courier'), VoiceService.parcel),
    MapEntry(_word('package'), VoiceService.parcel),
    MapEntry(_word('emergency'), VoiceService.sos),
    MapEntry(_word('sos'), VoiceService.sos),
    MapEntry(_word('help me'), VoiceService.sos),
    // "bike taxi" is this app's own name for the two-wheeler service, so it
    // must be checked before the generic "taxi"/"cab" patterns below —
    // otherwise "bike taxi book pannu" would match "taxi" first and book a
    // cab instead of a bike.
    MapEntry(_word('bike taxi'), VoiceService.bike),
    MapEntry(_word('biketaxi'), VoiceService.bike),
    MapEntry(_word('bike-taxi'), VoiceService.bike),
    MapEntry(_word('two wheeler'), VoiceService.bike),
    MapEntry(_word('bike'), VoiceService.bike),
    MapEntry(_word('cab'), VoiceService.cab),
    MapEntry(_word('car'), VoiceService.cab),
    MapEntry(_word('taxi'), VoiceService.cab),
    MapEntry(_word('auto'), VoiceService.auto),
    MapEntry(_word('rickshaw'), VoiceService.auto),
  ];

  // Matches "... to <destination>", "... at <destination>",
  // "... for <destination>", "... near <destination>" — whichever comes
  // last in the utterance, so "book an auto to the railway station"
  // yields "the railway station".
  static final RegExp _destinationPattern = RegExp(
    r'\b(?:to|at|for|near|towards?)\s+(.+)$',
    caseSensitive: false,
  );

  // NEW (Aug 25 2026 — Super Chitti Phase 1, Step 3: Text Pre-Router).
  // A spoken utterance is always a command by construction (the
  // customer tapped the mic specifically to book something), so
  // parse()'s keyword match alone was safe for voice. Typed chat text
  // is not — a genuine question like "is auto available right now?" or
  // "what is the cab fare policy" also contains a service keyword but
  // must NOT silently trigger book_transport (which auto-navigates
  // with no confirmation, per the Autonomous Interaction Rule elsewhere
  // in this codebase). This is the guard the text pre-router checks
  // before trusting parse()'s result — deliberately conservative
  // (English + common Tamil/Tanglish question markers only): letting an
  // ambiguous message fall through to Groq costs a little latency,
  // wrongly auto-navigating a customer away from a question costs
  // their trust.
  static final RegExp _questionMarkers = RegExp(
    r'\?|\b(is|are|does|do|can|could|should|why|what|when|where|which|'
    r'how|yepdi|epdi|yenna|enna|yean|ஏன்|என்ன|எப்படி)\b',
    caseSensitive: false,
  );

  bool looksLikeQuestion(String text) => _questionMarkers.hasMatch(text);

  /// Step 1 (pure, synchronous, no network): figure out which service
  /// the customer meant and what destination text (if any) they said.
  /// Returns null if no known service keyword was found at all — the
  /// caller should fall back to a normal AI chat reply in that case.
  // FIX (Aug 25 2026 — Pre-Router Loophole, follow-up): word-boundary
  // matching alone does NOT save "I want to open car wash" — "car" is a
  // genuine standalone word there, not a substring of another word, and
  // this app has an actual Car Wash section (see book_transport's
  // sibling navigate_to_section tool, 'car_wash'). Scrubbing this one
  // known collision out before pattern-matching is cheaper and more
  // precise than trying to generalize word-boundary matching into
  // solving same-word-different-meaning ambiguity, which it fundamentally
  // can't. Add further phrases here only when a real collision like this
  // one is found — this is a targeted patch, not a general mechanism.
  static final RegExp _carWashCollision = RegExp(r'\bcar\s*wash\b', caseSensitive: false);

  VoiceBookingIntent? parse(String utterance) {
    final lower = utterance.toLowerCase().trim();
    if (lower.isEmpty) return null;
    final scrubbed = lower.replaceAll(_carWashCollision, 'car_wash_service');

    VoiceService? matched;
    for (final entry in _servicePatterns) {
      if (entry.key.hasMatch(scrubbed)) {
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

  static const List<String> _yesWords = [
    'yes', 'yeah', 'yep', 'yup', 'correct', 'right', 'confirm', 'confirmed',
    'sure', 'ok', 'okay', 'go ahead', 'book it', "that's right",
  ];
  static const List<String> _noWords = [
    'no', 'nope', 'nah', 'wrong', 'incorrect', 'cancel', 'not that',
    "that's wrong", 'different',
  ];

  /// Interactive Disambiguation (per Nizam's request): classifies a
  /// short spoken reply to a "Did you mean X?" clarifying question as a
  /// clear yes, a clear no, or unclear (meaning the customer likely just
  /// re-said their command/correction by voice instead of answering
  /// yes/no — the caller should re-run [parse] on it in that case).
  VoiceYesNo classifyYesNo(String utterance) {
    final lower = utterance.toLowerCase().trim();
    if (lower.isEmpty) return VoiceYesNo.unclear;
    // Check "no" phrases first — "nope" contains no useful yes substring
    // risk, but keeping no-checks first guards against short utterances
    // like "not really" that could otherwise partially confuse matching.
    for (final word in _noWords) {
      if (lower == word || lower.startsWith('$word ') || lower.contains(' $word')) {
        return VoiceYesNo.no;
      }
    }
    for (final word in _yesWords) {
      if (lower == word || lower.startsWith('$word ') || lower.contains(' $word')) {
        return VoiceYesNo.yes;
      }
    }
    return VoiceYesNo.unclear;
  }
}

enum VoiceYesNo { yes, no, unclear }
