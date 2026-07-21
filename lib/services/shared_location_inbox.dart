// ================================================================
// shared_location_inbox.dart
//
// Holds a location that arrived from OUTSIDE the app — shared in from
// WhatsApp, Google Maps, or anything else on the share sheet — until a
// screen is ready to consume it.
//
// The share can land before any screen that cares is mounted (the app
// may be cold-starting because of the share itself), so it can't be
// delivered by a direct call. It's parked here, and the hero booking
// screen picks it up when it appears.
//
// ── Platform coverage ───────────────────────────────────────────────
// WEB / PWA: fully wired. web/manifest.json declares a "share_target"
//   with method GET, so Android hands the shared text to the app as
//   query parameters on the launch URL. captureFromLaunchUrl() reads
//   them. No plugin, no new dependency.
//
// NATIVE APK: also fully wired. AndroidManifest.xml declares the
//   ACTION_SEND intent-filter (so Allin1 appears in the share sheet)
//   and _listenForSharedLocations() in main_customer.dart reads the
//   intent payload via receive_sharing_intent, covering both a
//   cold start caused by the share and a share that arrives while the
//   app is already running. Both paths end at deliver() below.
// ================================================================
import 'package:flutter/foundation.dart';

import '../utils/location_link_parser.dart';

class SharedLocation {
  final double lat;
  final double lng;
  final String? label;

  const SharedLocation({required this.lat, required this.lng, this.label});
}

class SharedLocationInbox extends ChangeNotifier {
  SharedLocationInbox._();
  static final SharedLocationInbox instance = SharedLocationInbox._();

  SharedLocation? _pending;

  /// A shared location waiting to be used, if any.
  SharedLocation? get pending => _pending;
  bool get hasPending => _pending != null;

  /// Reads it and clears it in one step, so two screens can't both
  /// consume the same share and prompt the customer twice.
  SharedLocation? take() {
    final value = _pending;
    _pending = null;
    return value;
  }

  void clear() {
    if (_pending == null) return;
    _pending = null;
    notifyListeners();
  }

  /// Entry point for any platform that receives a share. Pass the raw
  /// shared text; coordinates are extracted here.
  ///
  /// Returns true if the text actually contained a usable location.
  bool deliver(String rawText) {
    final result = LocationLinkParser.parse(rawText);
    if (!result.isResolved) {
      debugPrint('[SharedLocationInbox] no coordinates in shared text');
      return false;
    }
    _pending = SharedLocation(
      lat: result.lat!,
      lng: result.lng!,
      label: result.label,
    );
    debugPrint(
      '[SharedLocationInbox] received ${result.lat}, ${result.lng}',
    );
    notifyListeners();
    return true;
  }

  /// Web/PWA: pull the shared text off the launch URL's query string.
  ///
  /// Safe to call on every platform and on every launch — on native, or
  /// on an ordinary web visit with no share, the parameters simply
  /// aren't there and this does nothing.
  void captureFromLaunchUrl() {
    if (!kIsWeb) return;
    try {
      final params = Uri.base.queryParameters;
      // Matches the "params" block in web/manifest.json's share_target.
      // Android puts a shared map link in "text" most of the time, but
      // some apps use "url" instead, so check both plus the title.
      final candidate = <String?>[
        params['text'],
        params['url'],
        params['title'],
      ].whereType<String>().where((s) => s.trim().isNotEmpty).join(' ');

      if (candidate.trim().isEmpty) return;
      deliver(candidate);
    } catch (e) {
      debugPrint('[SharedLocationInbox] launch URL capture failed: $e');
    }
  }
}
