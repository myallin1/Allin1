// ================================================================
// CaptainHomeScreen v2.0 — REAL Firebase (No Dummy Data!)
// Hero receives rides from Firestore in real-time
// ================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' hide Transaction;
import 'package:firebase_database/firebase_database.dart' as rtdb show Transaction;
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_navigator.dart';
import '../../config/city_config.dart';
import '../../models/ride_model.dart';
import '../../models/service_request_model.dart';
import '../../services/app_update_checker.dart';
import '../../services/chitti/chitti_host_bridge.dart';
import '../../services/db_usage_tracker.dart';
import '../../services/hero_foreground_service.dart';
import '../../services/hero_ride_notification_service.dart';
import '../../services/hero_usage_accumulator_service.dart';
import '../../services/hero_wallet_service.dart';
import '../../services/hero_web_audio_service.dart';
import '../../services/daily_quote_service.dart';
import '../../services/localization_service.dart';
import '../../services/location_service.dart';
import '../../services/service_request_service.dart';
import '../../services/sos_dispatch_service.dart';
import '../../services/update_service.dart';
import '../../utils/daily_boost_messages.dart';
import '../../widgets/stranded_orders_banner.dart';
import '../../widgets/allin1_map_widget.dart';
import '../../widgets/hero_premium_loader.dart';
import '../../widgets/order_photo_gallery.dart';
import '../earn/rewards_hub_screen.dart';
import '../../widgets/economic_vision_banner.dart';
import '../notifications_screen.dart';
import 'hero_ride_screen.dart';
import '../../config/hero_service_access.dart';
import '../../config/hero_skill_catalog.dart';
// RELATIVE, not package: (Aug 19 2026).
//
// These were the ONLY three `package:erode_superapp/` imports in this
// file — every other import here is relative — and they were also the
// only three symbols the analyzer reported as undefined
// (AppUpdateGateService, PwaCachePlatform). Both classes exist and both
// paths are correct, so that was never a code error: mixing the two
// import styles for the same package makes the analyzer resolve the
// same library twice, and a stale .dart_tool/package_config.json is
// then enough to break just the package: half while the relative half
// keeps working.
//
// Restarting the analysis server clears it, but only until next time.
// Matching the file's existing convention removes the failure mode.
import '../../services/app_update_gate_service.dart';
import '../../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../../services/pwa_cache_platform_web.dart';
import '../../widgets/cached_tile_provider.dart';

class HeroHomeScreen extends StatefulWidget {
  const HeroHomeScreen({
    super.key,
    this.embedded = false,
  });

  final bool embedded;

  @override
  State<HeroHomeScreen> createState() => _HeroHomeScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('embedded', embedded));
  }
}

class _HeroHomeScreenState extends State<HeroHomeScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  static const String _pendingHeroRideIdKey = 'pending_hero_ride_id';
  // FCM Data Push Layer 2 counterpart — mirrors kPendingHeroServiceRequestIdKey
  // in main_hero.dart's background handler (same string, duplicated
  // locally same as _pendingHeroRideIdKey/kPendingHeroRideIdKey already
  // are, to avoid an extra cross-file import for a single constant).
  static const String _pendingHeroServiceRequestIdKey = 'pending_hero_service_request_id';
  // T1: Corrected to Erode Bus Stand (was Mullamparappu at 11.2825, 77.7275)
  static const LatLng _erodeBusStandCenter = LatLng(11.3418, 77.7171);
  static const double _serviceZoneRadiusMeters = 5000;
  static const List<String> _restorableRideStatuses = <String>[
    'accepted',
    'in_progress',
  ];
  static const Duration _staleRideWindow = Duration(hours: 24);
  static const Duration _searchingRideWindow = Duration(minutes: 10);

  // ── Theme ────────────────────────────────────────────────────
  static const Color _bg = Color(0xFFFFF7FB);
  static const Color _surface = Colors.white;
  static const Color _card = Color(0xFFFFF1F8);
  static const Color _green = Color(0xFF00C853);
  static const Color _gold = Color(0xFFFFB347);
  static const Color _red = Color(0xFFFF5252);
  static const Color _darkRed = Color(0xFFB00020);
  static const Color _purple = Color(0xFFBE5CFF);
  static const Color _njPink = Color(0xFFFF4FA3);
  static const Color _njPinkSoft = Color(0xFFFF9AC8);
  static const Color _njWhite = Color(0xFFFFFBFE);
  static const Color _text = Color(0xFF4A1736);
  static const Color _muted = Color(0xFF94627F);
  static const Color _border = Color(0x26FF4FA3);

  // ── State ────────────────────────────────────────────────────
  bool _isOnline = false;
  bool _accepting = false;
  bool _isBootstrappingHeroData = true;
  String _activeRideId = '';
  int _mapRefreshGen = 0;
  bool _isShowingRideDialog = false;
  bool _showServiceZone = false;
  bool _isShowingServiceDialog = false;

  // Commission + Hero Coins state
  double _commissionRate = 0;
  final bool _waiverShown = false;
  bool _waiverCompleted = false;
  int _heroCoins = 0;
  bool _firstLoginToday = false;

  // Payment notification state
  bool _paymentAlertShown = false;
  String _vehicleType = 'bike';
  // Multi-city (Plan 3): loaded from heroes/{uid}.city, defaults to
  // kDefaultCity ('erode') for every hero doc created before this field
  // existed. Written into the online_heroes RTDB presence node so
  // service_request_service.dart / ride_search_screen.dart can filter
  // dispatch candidates by city.
  String _heroCity = kDefaultCity;

  // PER-HERO SERVICE ACCESS (Aug 17 2026 — Nizam: admin needs to be able
  // to stop a specific hero taking a specific kind of work).
  //
  // Loaded from heroes/{uid}.serviceAccess and mirrored into the RTDB
  // presence node on every write, so ride_search_screen.dart and
  // service_request_service.dart can filter dispatch without a Firestore
  // read per hero per booking. See lib/config/hero_service_access.dart.
  //
  // Stays NULL for every hero who has never had a restriction set, and
  // the mirror writes nothing in that case — an absent key means
  // "allowed", so untouched heroes keep behaving exactly as before.
  Map<String, dynamic>? _serviceAccess;

  // SKILL HEROES (Aug 29 2026). Loaded from heroes/{uid}.skills and
  // mirrored into the RTDB presence node exactly like _serviceAccess
  // above, for exactly the same reason: skill matching happens inside
  // service_request_service._broadcastToEligibleHeroes, which iterates
  // the whole online_heroes node and cannot afford a Firestore read per
  // hero per booking.
  //
  // Empty for every vehicle hero, and an empty list mirrors NOTHING —
  // heroHasSkill() reads a missing field as "no skills", which is the
  // correct answer for a bike rider, and writing an empty array to
  // three presence nodes per GPS tick would be pure noise.
  List<String> _heroSkills = const <String>[];

  /// Live listener on the hero's own doc, so an admin toggling a service
  /// takes effect on a hero who is ALREADY online. Without this the
  /// change would only apply the next time they went offline and back
  /// on — which, for a hero working a full shift, could be hours.
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _serviceAccessSub;

  // Cached stats — loaded once per session in _loadHeroData()
  int _totalRides = 0;
  double _totalEarnings = 0;
  bool _statsLoaded = false;

  // ── SOS Emergency state ──────────────────────────────────────
  final List<DateTime> _sosTapTimes = <DateTime>[];
  bool _sendingSos = false;

  // ── Nearby-SOS overlay: per-session dismiss + 15-min auto-expiry ──
  // "OK, I've seen it" adds the alert's doc id here so it stops
  // showing this session, even though the underlying sos_alerts doc
  // is still status:'active' (only an admin resolve changes that).
  // Independently, alerts older than 15 minutes are filtered out on
  // the read side below, regardless of dismiss state — a safety net
  // in case no admin ever resolves the alert.
  final Set<String> _dismissedSosIds = <String>{};
  static const Duration _sosAlertMaxAge = Duration(minutes: 15);

  // GPS throttling for RTDB
  DateTime? _lastGpsUpdate;
  Position? _lastUploadedPosition;

  /// Minimum movement, in metres, before the IDLE RADAR republishes the
  /// hero's position to RTDB `online_heroes/{uid}`.
  ///
  /// This gates ONLY the idle "available heroes nearby" radar — the marker
  /// customers see while browsing, before any ride exists. It deliberately
  /// does NOT gate live tracking during an active ride: that writes to
  /// `live_locations/{rideId}` via _sendLocationUpdate(), which keeps its
  /// own much tighter 50m gate so the customer sees the hero actually
  /// moving toward them in near-real-time.
  ///
  /// Trade-off at 200m: at ~20-30 km/h city speed a hero covers this in
  /// roughly 25-35 seconds, so an idle hero's radar position can be up to
  /// ~200m stale. Chosen as a middle ground between write cost and
  /// dispatch-matching accuracy. See the report accompanying this change.
  static const double _idleRadarMoveThresholdMeters = 200;
  Timer? _locationTimer;

  /// FIX (WhatsApp-model presence, take 2 — CTO architecture review):
  /// presence trust boundary is `.info/connected` + `onDisconnect()`
  /// only, deliberately with NO client heartbeat and NO admin-side
  /// staleness timeout. `onDisconnect()` is a server-side hook tied to
  /// the actual RTDB session — Firebase's own low-level keepalive
  /// detects a dead connection and fires it without any writes from
  /// us. The only real gap that pattern has is a SILENT RECONNECT
  /// (network blip, carrier switch, tab backgrounding) — the old
  /// session's onDisconnect() hook is gone the moment the socket
  /// drops, and nothing re-arms it on the new session unless we
  /// explicitly do so. `.info/connected` is RTDB's own connection-state
  /// stream (free, no reads/writes charged) — subscribing to it and
  /// re-writing + re-arming on every `true` transition (not just the
  /// first) closes that gap with zero polling. See
  /// _startPresenceConnectionWatcher() below.
  StreamSubscription<DatabaseEvent>? _presenceConnectedSub;
  Position? _latestPosition;
  LatLng? _displayHeroLocation;
  double? _displayHeroBearingDegrees;
  AnimationController? _heroMarkerMoveCtrl;

  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  // Captain profile from Firebase Auth
  User? _user;

  // ── Stable stream references (FIX A pattern, as in ride_history) ──
  // These two queries were previously created inline inside build()
  // (`.snapshots()` directly in the StreamBuilder). Every rebuild
  // produced a brand-new stream object, so StreamBuilder tore down and
  // re-attached the Firestore listener each time — and Firestore bills
  // the query's full initial result set on every re-attach. On a screen
  // that rebuilds on GPS marker movement, lifecycle resumes, etc., this
  // silently multiplied idle reads. Created ONCE in initState instead;
  // StreamBuilder then keeps a single persistent listener whose
  // incremental updates are the only ongoing cost.
  Stream<QuerySnapshot<Map<String, dynamic>>>? _activeServiceRequestsStream;
  Stream<QuerySnapshot<Map<String, dynamic>>>? _activeSosAlertsStream;

  // ── Service-request "busy" gate + live-tracking wiring ──────────
  // A hero already working a Hero Booking (or other service_requests
  // category) task should not receive new ride OR service pings until
  // that task completes — mirrors the existing _activeRideId.isNotEmpty
  // gate used throughout this file for rides. Driven by a plain
  // .listen() on the same _activeServiceRequestsStream the UI's
  // StreamBuilder already uses (Firestore snapshots() streams are
  // broadcast streams, so a second listener is safe and cheap — no
  // extra reads, just a second subscriber to the same stream).
  bool _hasActiveServiceRequest = false;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>?
      _serviceRequestBusySub;
  // Tracks which requestId live-location tracking is currently running
  // for, so we only stop it when THAT task leaves 'in_progress' (not
  // some unrelated snapshot event).
  String? _trackedServiceRequestId;
  String get _captainName =>
      _user?.displayName ?? _user?.email?.split('@').first ?? 'Hero Rider';
  String get _avatarLetter =>
      _captainName.isNotEmpty ? _captainName[0].toUpperCase() : 'H';

  // FIX (audit: "customer/hero number wiring" — same root cause as
  // ride_search_screen.dart's _resolveCustomerPhone): FirebaseAuth's own
  // `user.phoneNumber` is ONLY populated by actual phone-OTP auth, never
  // by a mobile number a Google-Sign-In hero types in manually at
  // hero_register_screen.dart. That number is written to Firestore
  // heroes/{uid}.phone (and .phoneNumber), so it must be read from there
  // — not straight off the Auth user object — before stamping it onto a
  // ride/service-request doc for the customer to call. Cached per
  // session since it won't change mid-shift.
  String? _resolvedHeroPhone;
  Future<String> _resolveHeroPhone(User user) async {
    if (_resolvedHeroPhone != null && _resolvedHeroPhone!.isNotEmpty) {
      return _resolvedHeroPhone!;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final phone = (data?['phoneNumber'] as String?)?.trim();
      final phoneAlt = (data?['phone'] as String?)?.trim();
      final resolved = (phone != null && phone.isNotEmpty)
          ? phone
          : (phoneAlt != null && phoneAlt.isNotEmpty
              ? phoneAlt
              : (user.phoneNumber ?? ''));
      _resolvedHeroPhone = resolved;
      return resolved;
    } catch (_) {
      return user.phoneNumber ?? '';
    }
  }

  // Stream subscriptions
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<Position>? _globalLocationSub;
  StreamSubscription<RemoteMessage>? _foregroundMessageSub;
  StreamSubscription<RemoteMessage>? _messageOpenedSub;

  // FIX-B1: Cached stream — created once when going online, never recreated
  // on setState(). Prevents the "Scanning" loader from flashing every GPS tick.

  // FIX-RIDE: Firestore broadcast stream for 'searching' rides + RTDB ping sub

  StreamSubscription<DatabaseEvent>? _heroPingSub;
  // Shown ride IDs (deprecated with old Firestore stream) a dialog for to prevent duplicates

  // Broadcast Order System — parallel ping subscription (mirrors _heroPingSub
  // lifecycle exactly: same init/pause/resume/dispose points).
  StreamSubscription<DatabaseEvent>? _servicePingSub;
  final Set<String> _shownServicePingIds = {};

  bool _isOnRide = false;
  DateTime? _lastFirestoreLocationWriteAt;
  Position? _lastFirestoreLocationPosition;
  DateTime? _lastFirestoreStatusWriteAt;

  DateTime _staleRideCutoff() => DateTime.now().subtract(_staleRideWindow);

  DateTime? _rideActivityAt(Map<String, dynamic> data) {
    final candidates = <Object?>[
      data['startedAt'],
      data['acceptedAt'],
      data['createdAt'],
    ];
    for (final candidate in candidates) {
      if (candidate is Timestamp) {
        return candidate.toDate();
      }
    }
    return null;
  }

  DateTime? _searchingRideActivityAt(Map<String, dynamic> data) {
    final candidates = <Object?>[
      data['lastPingAt'],
      data['createdAt'],
    ];
    for (final candidate in candidates) {
      if (candidate is Timestamp) {
        return candidate.toDate();
      }
    }
    return null;
  }

  bool _isFreshSearchingRide(Map<String, dynamic> data) {
    final activityAt = _searchingRideActivityAt(data);
    if (activityAt == null) {
      return false;
    }
    return activityAt.isAfter(DateTime.now().subtract(_searchingRideWindow));
  }

  Timestamp _recentRideCutoffTimestamp() {
    return Timestamp.fromDate(
      DateTime.now().subtract(_searchingRideWindow),
    );
  }

  bool _isRecentCreatedRide(Map<String, dynamic> data) {
    final createdAt = data['createdAt'];
    if (createdAt is! Timestamp) {
      return false;
    }
    return createdAt.toDate().isAfter(
          DateTime.now().subtract(_searchingRideWindow),
        );
  }

  String? _targetedHeroIdFromRide(Map<String, dynamic> data) {
    for (final key in const <String>[
      'targeted_hero_id',
      'targetedHeroId',
      'targetHeroId',
      'assignedHeroId',
    ]) {
      final value = data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String _normalizeHeroVehicleType(String? value) {
    switch (value?.trim().toLowerCase() ?? '') {
      case 'auto': return 'auto';
      case 'emergency_manpower':
      case 'manpower': return 'emergency_manpower';
      case 'mini_truck':
      case 'mini-truck':
      case 'truck': return 'mini_truck';
      case 'lorry': return 'lorry';
      case 'parcel': return 'parcel';
      case 'cab':
      case 'car':
      case 'mini': return 'car';
      case 'bike':
      default: return 'bike';
    }
  }

  String _assetForHeroVehicleType(String? vehicleType) {
    switch (_normalizeHeroVehicleType(vehicleType)) {
      case 'auto':
        return 'assets/images/top_auto.png';
      case 'car':
        return 'assets/images/top_cab.png';
      case 'bike':
      default:
        return 'assets/images/top_bike.png';
    }
  }

  double? _validHeading(double? heading) {
    if (heading == null || heading.isNaN || heading < 0) {
      return null;
    }
    return heading % 360;
  }

  double _bearingBetween(LatLng start, LatLng end) {
    final lat1 = start.latitude * math.pi / 180;
    final lat2 = end.latitude * math.pi / 180;
    final dLng = (end.longitude - start.longitude) * math.pi / 180;
    final y = math.sin(dLng) * math.cos(lat2);
    final x = (math.cos(lat1) * math.sin(lat2)) -
        (math.sin(lat1) * math.cos(lat2) * math.cos(dLng));
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  void _disposeHeroMarkerAnimation() {
    final controller = _heroMarkerMoveCtrl;
    _heroMarkerMoveCtrl = null;
    controller?.stop();
    controller?.dispose();
  }

  void _animateHeroMarkerTo(Position position) {
    if (!mounted) {
      return;
    }
    final target = LatLng(position.latitude, position.longitude);
    final start = _displayHeroLocation;
    final resolvedBearing = _validHeading(position.heading) ??
        (start != null ? _bearingBetween(start, target) : null) ??
        _displayHeroBearingDegrees;

    _disposeHeroMarkerAnimation();

    if (start == null) {
      setState(() {
        _displayHeroLocation = target;
        _displayHeroBearingDegrees = resolvedBearing;
      });
      return;
    }

    final movedMeters = Geolocator.distanceBetween(
      start.latitude,
      start.longitude,
      target.latitude,
      target.longitude,
    );
    if (movedMeters < 0.5) {
      setState(() {
        _displayHeroLocation = target;
        _displayHeroBearingDegrees = resolvedBearing;
      });
      return;
    }

    final controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    );
    final curved = CurvedAnimation(
      parent: controller,
      curve: Curves.easeInOutCubic,
    );
    _heroMarkerMoveCtrl = controller;
    controller.addListener(() {
      if (!mounted || _heroMarkerMoveCtrl != controller) {
        return;
      }
      final t = curved.value;
      setState(() {
        _displayHeroLocation = LatLng(
          start.latitude + ((target.latitude - start.latitude) * t),
          start.longitude + ((target.longitude - start.longitude) * t),
        );
        _displayHeroBearingDegrees = resolvedBearing;
      });
    });
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed ||
          !mounted ||
          _heroMarkerMoveCtrl != controller) {
        return;
      }
      setState(() {
        _displayHeroLocation = target;
        _displayHeroBearingDegrees = resolvedBearing;
      });
      _heroMarkerMoveCtrl = null;
      controller.dispose();
    });
    controller.forward();
  }

  bool _rideTargetsCurrentHero(Map<String, dynamic> data) {
    final uid = _user?.uid;
    if (uid == null || uid.isEmpty) return false;
    final status = data['status'] as String?;
    final heroId = data['heroId'] as String?;
    final captainId = data['captainId'] as String?;
    final targetedHeroId = _targetedHeroIdFromRide(data);

    // T3: Category guard — hero must not receive rides from other categories.
    final rideCategory = (data['category'] as String?)?.trim().toLowerCase();
    if (rideCategory != null &&
        rideCategory.isNotEmpty &&
        rideCategory != _vehicleType) {
      return false;
    }

    if (status == 'searching') {
      if (targetedHeroId == null || targetedHeroId.isEmpty) return true;
      return targetedHeroId == uid;
    }
    if (status == 'assigned') {
      return heroId == uid || captainId == uid || targetedHeroId == uid;
    }
    return false;
  }

  void _startTargetedRideFallback() {
    _listenForHeroPings();
    _listenForServicePings();
  }

  // FIX-RIDE: Firestore live stream for broadcast 'searching' rides.
  // This is the PRIMARY mechanism when no FCM push / RTDB signal is sent.
  void _startBroadcastRideStream() {}

  void _stopBroadcastRideStream() {}

  // FIX-B1: Create the pending-rides Firestore stream exactly once per online
  // session, using a fixed cutoff Timestamp captured at creation time.
  // Re-using the same Stream object means StreamBuilder never resets to
  // ConnectionState.waiting on subsequent setState() calls.
  void _initPendingRidesStream() {}

  void _clearPendingRidesStream() {}

  void _stopTargetedRideFallback() {
    _heroPingSub?.cancel();
    _heroPingSub = null;
    _stopServicePingListening();
  }

  void _stopServicePingListening() {
    _servicePingSub?.cancel();
    _servicePingSub = null;
  }

  // Best-effort automatic check — runs once per app launch. Fails
  // silently on any error so a flaky network never bothers the hero
  // mid-shift. See app_update_checker.dart for why this only ever
  // fires for the rare case Shorebird OTA can't patch on its own —
  // Shorebird already handles regular Dart-code updates silently in
  // the background (shorebird.yaml, auto_update).
  Future<void> _checkForAppUpdate() async {
    try {
      final hasUpdate = await AppUpdateChecker().isUpdateAvailable();
      if (hasUpdate && mounted) {
        await _showUpdateDialog();
      }
    } catch (e) {
      debugPrint('[HeroHome] app update check failed: $e');
    }
  }

  Future<void> _showUpdateDialog() async {
    final fallbackUpdateUrl =
        Uri.parse('https://my-allin1.web.app/hero-allin1.apk');

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _njWhite,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: BorderSide(color: _njPink.withValues(alpha: 0.24)),
          ),
          title: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: _njPink.withValues(alpha: 0.14),
                  borderRadius: BorderRadius.circular(14),
                ),
                child:
                    const Icon(Icons.system_update_alt_rounded, color: _njPink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  'Update Available! 🚀',
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontWeight: FontWeight.w800,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Text(
            'A new version of the NJ Tech Super App is ready. Update now for new features and better performance!',
            style: GoogleFonts.outfit(
              color: _text.withValues(alpha: 0.82),
              fontSize: 14,
              height: 1.45,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(
                'Later',
                style: GoogleFonts.outfit(
                  color: _muted,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.of(dialogContext).pop();
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Downloading update...')),
                  );
                }
                try {
                  // One-tap download + install — hands the APK straight
                  // to Android's installer (see app_update_checker.dart),
                  // instead of sending the hero to a browser download
                  // they'd then have to find and open manually.
                  await AppUpdateChecker().downloadAndInstall(
                    appVariant: 'hero',
                  );
                } catch (e) {
                  debugPrint('[HeroHome] in-app update install failed, '
                      'falling back to browser download: $e');
                  final launched = await launchUrl(
                    fallbackUpdateUrl,
                    mode: LaunchMode.externalApplication,
                  );
                  if (!launched && mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content:
                            Text('Unable to open the update link right now.'),
                        backgroundColor: Colors.redAccent,
                      ),
                    );
                  }
                }
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _njPink,
                foregroundColor: _njWhite,
                padding:
                    const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
              ),
              child: Text(
                'Update Now',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w700),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _handleSoundboxPromoTap() async {
    final launched = await launchUrl(Uri.parse('tel:+919597879191'));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? 'Calling NJ Tech... Claim your FREE Paytm Soundbox offer.'
              : 'Unable to open the NJ Tech dialer right now.',
        ),
        backgroundColor: launched ? _njPink : _red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    // REMOVED (Aug 19 2026 — nag-on-open cleanup): this used to fire an
    // "Update Available!" AlertDialog the moment the hero home screen
    // opened, every session, whether or not the hero was mid-something.
    // That's now handled by the non-intrusive _buildUpdateBanner(),
    // which only shows inline while the hero is idle between jobs — see
    // its comment above for why that's the safer moment. Left the
    // _checkForAppUpdate()/_showUpdateDialog() methods themselves intact
    // in case they're wanted again, just not auto-invoked on open.
    // unawaited(_checkForAppUpdate());
    // NEW (Aug 12 2026 — Nizam's "daily boost" request): one small,
    // non-blocking earn/motivate SnackBar per app cold-boot, right
    // under the time-of-day greeting. See daily_boost_messages.dart —
    // hero's list is specifically about earning/growing, not the
    // generic customer copy.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        showDailyBoostSnackBar(context, randomHeroBoostMessage());
      });
    });
    // NEW (Aug 27 2026 — Chitti hero tools): register the ONE safe way
    // for Chitti to take this hero online/offline. It runs this
    // screen's own _syncOnlineStatus(), which is what acquires the
    // location fix, writes the RTDB radar entry dispatch reads, and
    // attaches the ping listeners. See chitti_host_bridge.dart for why
    // Chitti must never write the online flag itself.
    ChittiHostBridge.heroOnlineHandler = _chittiSetOnline;
    _user = FirebaseAuth.instance.currentUser;
    // Build the query streams exactly once — see the field comments.
    final streamUid = _user?.uid;
    if (streamUid != null) {
      _activeServiceRequestsStream = FirebaseFirestore.instance
          .collection('service_requests')
          .where('assignedHeroId', isEqualTo: streamUid)
          .where(
            // 'completed' is included here (and NOT excluded) so a
            // task that's done-but-unpaid still shows to the hero for
            // the "Mark Payment Received (Cash)" close-out step —
            // filtered out client-side below once paymentStatus:'paid'
            // (see _buildActiveServiceRequests), avoiding a 3rd
            // inequality-filter composite index just for this.
            'status',
            whereIn: [
              'hero_assigned',
              'in_progress',
              'nearing_completion',
              'completed',
            ],
          )
          .snapshots();
      // DB usage monitor — side-channel .listen() on this already-hoisted,
      // broadcast .snapshots() stream to count docs per snapshot; the
      // stream already has _serviceRequestBusySub as a listener below, so
      // this adds no extra Firestore reads. See db_usage_tracker.dart.
      _activeServiceRequestsStream!.listen((s) => DbUsageTracker.instance
          .recordRead(s.docs.length, 'hero_active_service_requests'));
      _serviceRequestBusySub = _activeServiceRequestsStream!.listen((snap) {
        // FIX (CTO mandate — Final UI Migration Sweep): map to typed
        // models here so both this busy-gate check and the GPS-tracking
        // lookup below read `.status`/`.requestId` instead of
        // `doc.data()['status']`/`doc.id`. The query/stream itself is
        // unchanged — this only affects how the callback reads results.
        final models = snap.docs
            .map((doc) => ServiceRequestModel.fromFirestore(doc.data(), doc.id))
            .toList();

        // Busy = any non-completed doc assigned to this hero (hero_
        // assigned/in_progress/nearing_completion). 'completed' docs
        // stay in the query only for the payment-collection UI (see
        // comment above) — they don't count as "busy" anymore.
        //
        // FIX (Recovery System, Aug 11 2026): unlike rides (which already
        // self-expire from the busy-gate via _staleRideWindow, see
        // _checkActiveRide below), a service request had NO time-based
        // escape at all — one stuck at hero_assigned/in_progress forever
        // blocked this hero's pings with no automatic recovery. Mirrors
        // the ride behavior: a request whose last activity
        // (updatedAt ?? createdAt) is older than _staleRideWindow no
        // longer counts as "busy" for the ping-gate, even if its
        // Firestore doc is untouched. This is a purely client-side gate
        // change — it does NOT alter or delete the request document, so
        // the new Incomplete/Stuck Tasks hub (which has no such age
        // limit) still lists and can Release it. The manual hub remains
        // the primary fix; this is just the same defense-in-depth
        // rides already had.
        final activeDocs = models.where((m) =>
            m.status != 'completed' &&
            DateTime.now()
                    .difference(m.updatedAt ?? m.createdAt ?? DateTime.now())
                <= _staleRideWindow);
        final hasActive = activeDocs.isNotEmpty;
        if (mounted && hasActive != _hasActiveServiceRequest) {
          setState(() => _hasActiveServiceRequest = hasActive);
        }

        // Live GPS tracking: start once a task is actually in_progress
        // (hero is traveling/working, not just waiting on customer
        // estimate approval), stop once it's no longer in_progress for
        // the requestId we were tracking. Mirrors rides' live_locations
        // pattern exactly (_startLocationUpdates/_stopLocationUpdates),
        // just keyed by requestId instead of rideId.
        ServiceRequestModel? inProgressRequest;
        for (final m in models) {
          if (m.status == 'in_progress') {
            inProgressRequest = m;
            break;
          }
        }
        if (inProgressRequest != null) {
          if (_trackedServiceRequestId != inProgressRequest.requestId) {
            _trackedServiceRequestId = inProgressRequest.requestId;
            _startLocationUpdates(inProgressRequest.requestId);
          }
        } else if (_trackedServiceRequestId != null) {
          _trackedServiceRequestId = null;
          // Only stop if a ride isn't also relying on the same shared
          // location subscription right now.
          if (_activeRideId.isEmpty) {
            _stopLocationUpdates();
          }
        }
      });
    }
    // FIX (Aug 29 2026 — Emergency Responder dispatch). This was
    // `.where('status', isEqualTo: 'active')` only. Once
    // sos_dispatch_service.dart existed and could move a doc to
    // 'claimed' or 'escalated', that single-value filter would drop the
    // document out of THIS SNAPSHOT ENTIRELY the moment a hero claimed
    // it — including for the hero who just claimed it, who would lose
    // the call/resolve/escalate UI the instant they tapped "I'm
    // Responding". whereIn keeps every non-final state in the stream;
    // 'resolved' is deliberately excluded — nobody needs a closed alert
    // pushed to their client forever.
    _activeSosAlertsStream = FirebaseFirestore.instance
        .collection('sos_alerts')
        .where('status', whereIn: [
          SosAlertStatus.active,
          SosAlertStatus.claimed,
          SosAlertStatus.escalated,
        ])
        .snapshots();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 0.95, end: 1.05)
        .animate(CurvedAnimation(parent: _pulseCtrl!, curve: Curves.easeInOut));
    WidgetsBinding.instance.addObserver(this);
    _checkActiveRide();
    _loadHeroData();
    unawaited(_initializeNotifications());
    unawaited(_consumePendingRidePush());
    unawaited(_consumePendingServiceRequestPush());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // BUG B2 FIX (Aug 8 2026 — "tapped the notification, app opened, but
    // the accept popup never showed"): this used to be
    // `if (!_isOnline || _user == null) return;` — the ENTIRE resumed-case
    // body, including _consumePendingRidePush()/
    // _consumePendingServiceRequestPush() below, was skipped whenever
    // the hero's local `_isOnline` flag happened to read false at the
    // exact moment of resume. That's extremely common right after a
    // background→foreground transition, since (per the comment on the
    // `resumed` case below) the RTDB WebSocket — and therefore presence —
    // routinely drops while backgrounded and hasn't resynced yet by the
    // time this callback fires. So the most common real-world path
    // (hero backgrounds the app, gets a push, taps the notification to
    // bring it forward) was exactly the one this guard silently broke.
    // Comments elsewhere in this file already claim the `!_isOnline`
    // guard was "removed" as the fix for a near-identical bug — that
    // removal only reached the inner method bodies
    // (_consumePendingRidePush/_fetchTargetedRideOnce/
    // _fetchTargetedServiceRequestOnce), never this outer gate. Dropping
    // `_isOnline` from this check entirely: pending-push consumption
    // must always run on resume, and the resumed-case body already
    // handles re-establishing online status itself (goOnline() +
    // _syncOnlineStatus(true) below) regardless of what _isOnline read
    // going in.
    if (_user == null) {
      return;
    }
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.inactive:
        // App backgrounded — DO NOT go offline!
        // FCM background handler in main_hero.dart takes over ride alerts.
        debugPrint('Hero: backgrounded — staying ONLINE, FCM handles alerts');
        break;
      case AppLifecycleState.resumed:
        debugPrint('Hero: resumed — reconfirming ONLINE');
        // FIX (per Nizam's bug report — "online vachu vera apps ku
        // poitu varrathukullaye offline poiduthu"): root cause is
        // platform-level, not an app bug — switching away suspends the
        // RTDB WebSocket (aggressively on mobile browsers/PWA, and
        // sometimes even natively under battery optimization), which
        // fires the server-side onDisconnect() hook and removes
        // online_heroes/{uid} while the hero is away, exactly the
        // presence-without-heartbeat tradeoff the CTO explicitly chose.
        // Can't prevent the brief drop without reintroducing the
        // rejected heartbeat, but we CAN make recovery on return as
        // fast as possible: explicitly nudge the SDK to reconnect
        // (goOnline()) rather than only waiting on its own automatic
        // reconnect logic, right before re-arming presence.
        FirebaseDatabase.instance.goOnline();
        _syncOnlineStatus(true);
        unawaited(_loadHeroData());
        unawaited(_consumePendingRidePush());
        unawaited(_consumePendingServiceRequestPush());
        // Re-attach broadcast stream in case it dropped on background
        if (_isOnline) {}
        break;
      case AppLifecycleState.detached:
        // T1 CEO FIX: DO NOT call _syncOnlineStatus(false) here.
        // If we set Firestore status:'offline' on terminate, the hero stops
        // receiving FCM pushes for new rides while the app is closed.
        // The hero must explicitly tap "Go Offline" to stop receiving rides.
        // Only cancel UI-only resources (GPS timer, RTDB radar node).
        _locationTimer?.cancel();
        _locationTimer = null;
        if (_user != null) {
          // FIX (Aug 11 2026 — same root cause as the onDisconnect()
          // change in _syncOnlineStatus): this used to hard-remove the
          // node. On mobile browsers `detached` can fire simply from a
          // PWA tab being torn down/backgrounded — not only from a real
          // app exit — so deleting here made the hero instantly
          // undiscoverable to customer-side search in exactly the
          // two-tab scenario Nizam hit. Stamp instead of delete, so the
          // grace window in ride_search_screen.dart's
          // _fetchNearbyHeroes() governs discoverability uniformly, no
          // matter which path caused the disconnect. An explicit
          // "Go Offline" tap still hard-removes the node (see the
          // offline-toggle cleanup) — that remains the only immediate,
          // intentional way to disappear from radar.
          FirebaseDatabase.instance
              .ref('online_heroes/${_user!.uid}')
              .update({
                'connectionLost': true,
                'disconnectedAt': ServerValue.timestamp,
              })
              .catchError((Object e) {
            debugPrint('RTDB radar cleanup error (detached): $e');
          });
        }
        debugPrint(
          'Hero: detached — Firestore status PRESERVED as online. '
          'FCM background handler is active.',
        );
        break;
    }
  }

// ── Commission Waiver Banner + Hero Coins snippets ──

  Future<void> _loadHeroData() async {
    if (_user == null) {
      if (mounted && _isBootstrappingHeroData) {
        setState(() => _isBootstrappingHeroData = false);
      }
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(_user!.uid)
          .get();
      DbUsageTracker.instance.recordRead(1, 'hero_home_screen', 'profile_fetch');
      final data = doc.data() ?? {};
      String vehicleType =
          (data['vehicleType'] as String?)?.trim().isNotEmpty ?? false
              ? (data['vehicleType'] as String).trim()
              : 'bike';
      if (vehicleType == 'bike') {
        final userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(_user!.uid)
            .get();
        DbUsageTracker.instance.recordRead(1, 'hero_home_screen', 'vehicle_type_lookup');
        final userVehicle = userDoc.data()?['vehicleType'] as String?;
        if (userVehicle != null && userVehicle.trim().isNotEmpty) {
          vehicleType = userVehicle.trim();
        }
      }
      vehicleType = _normalizeHeroVehicleType(vehicleType);

      // Commission rate — default 10%, reduced to 5% after task
      final double rate =
          (data['active_commission_rate'] as num?)?.toDouble() ?? 0.0;

      // Hero coins
      final int coins = (data['hero_coins'] as int?) ?? 0;

      // Check if first login today
      final DateTime? lastLogin =
          (data['last_login_date'] as Timestamp?)?.toDate();
      final DateTime today = DateTime.now();
      final bool isFirstToday = lastLogin == null ||
          lastLogin.day != today.day ||
          lastLogin.month != today.month ||
          lastLogin.year != today.year;

      // FIX (WhatsApp-model presence migration, CTO mandate): this used
      // to restore _isOnline from Firestore's data['isOnline'] — exactly
      // the field that could go stale forever on an ungraceful exit
      // (app killed, crash, connection drop), which is the literal bug
      // being fixed. RTDB's online_heroes/{uid} node is backed by
      // onDisconnect(), so checking whether IT still exists is the
      // correct restore signal: it will already be gone by the time this
      // runs for any restart that follows an ungraceful exit, and still
      // present for a same-session resume (e.g. a background/foreground
      // cycle that never actually lost connection).
      bool restoredOnline = false;
      try {
        final onlineSnap = await FirebaseDatabase.instance
            .ref('online_heroes/${_user!.uid}')
            .get();
        restoredOnline = onlineSnap.exists;
      } catch (e) {
        debugPrint('[HeroHomeScreen] online_heroes restore check failed: $e');
      }

      if (mounted) {
        setState(() {
          _commissionRate = rate;
          _heroCoins = coins;
          _firstLoginToday = isFirstToday;
          _waiverCompleted = rate <= 0.0;
          _vehicleType = vehicleType;
          _heroCity = (data['city'] as String?)?.trim().toLowerCase().isNotEmpty ?? false
              ? (data['city'] as String).trim().toLowerCase()
              : kDefaultCity;
          _serviceAccess = data[kHeroServiceAccessField] is Map
              ? Map<String, dynamic>.from(
                  data[kHeroServiceAccessField] as Map)
              : null;
          _heroSkills = heroSkillsOf(data);
          _isOnline = restoredOnline;
        });
      }

      // Keep watching so an admin change reaches a hero who is already
      // mid-shift, instead of waiting for their next offline/online
      // cycle. One listener on ONE document — negligible read cost, and
      // it only exists while the hero screen is mounted.
      _watchServiceAccess();

      // FIX BUG #3: If captain was online before restart, restart tracking
      if (_isOnline) {
        // _initPendingRidesStream removed
        _startGlobalLocationTracking();
        _listenForHeroPings();
        _listenForServicePings();

        unawaited(_consumePendingRidePush());
        unawaited(_consumePendingServiceRequestPush());
        debugPrint('🔄 Hero online state restored — live tracking restarted');
      }

      // (see _watchServiceAccess below)

      // Stats — fetch once per session, cache in state
      if (!_statsLoaded) {
        try {
          final ridesSnap = await FirebaseFirestore.instance
              .collection('rides')
              .where('captainId', isEqualTo: _user!.uid)
              .where('status', isEqualTo: 'completed')
              .get();
          DbUsageTracker.instance
              .recordRead(ridesSnap.docs.length, 'hero_completed_rides_count');
          double earn = 0;
          for (final d in ridesSnap.docs) {
            earn += (d.data()['fare'] as num? ?? 0).toDouble();
          }
          if (mounted) {
            setState(() {
              _totalRides = ridesSnap.docs.length;
              _totalEarnings = earn;
              _statsLoaded = true;
            });
          }
        } catch (e) {
          debugPrint('Stats fetch error: $e');
        }
      }

      // Update last login date
      if (isFirstToday) {
        await FirebaseFirestore.instance
            .collection('heroes')
            .doc(_user!.uid)
            .set(
          {'last_login_date': FieldValue.serverTimestamp()},
          SetOptions(merge: true),
        );
        DbUsageTracker.instance.recordWrite(1, 'hero_home_screen', 'last_login_stamp');
      }
    } catch (e) {
      debugPrint('Hero data load error: $e');
    } finally {
      if (mounted && _isBootstrappingHeroData) {
        setState(() => _isBootstrappingHeroData = false);
      }
    }
  }

  Future<void> _launchCommissionWaiverTask() async {
    if (_user == null) {
      return;
    }
    // Navigate to centralized Rewards Hub — same screen for both Customer & Hero
    if (mounted) {
      await Navigator.push<void>(
        context,
        MaterialPageRoute<void>(builder: (context) => const RewardsHubScreen()),
      );
    }
  }

  // Sync captain online status to Firestore & RTDB
  /// Chitti entry point for `hero_set_online_status`.
  ///
  /// Mirrors the header toggle exactly — optimistic local flip, then
  /// the real [_syncOnlineStatus] — so a hero who says "I'm starting
  /// work" ends up in precisely the state the button would have put
  /// them in, listeners and radar entry included.
  ///
  /// Going online can legitimately fail (location denied, most often on
  /// web), and [_syncOnlineStatus] flips `_isOnline` back when it does.
  /// Re-reading the flag afterwards rather than assuming success is the
  /// point: telling a hero they are online when they are not means they
  /// sit waiting for pings that will never arrive.
  Future<String> _chittiSetOnline(bool online) async {
    if (_user == null) {
      return "You don't seem to be signed in — please sign in first.";
    }
    if (_isOnline == online) {
      return online
          ? "You're already online and receiving job pings."
          : "You're already offline.";
    }
    if (mounted) setState(() => _isOnline = online);
    await _syncOnlineStatus(online);
    if (_isOnline != online) {
      return online
          ? "I couldn't take you online — check your location permission on "
              'the home screen and try the toggle there.'
          : "I couldn't take you offline just now — please use the toggle on "
              'the home screen.';
    }
    return online
        ? "You're online — job pings will start coming in."
        : "You're offline now. No pings until you go back online.";
  }

  Future<void> _syncOnlineStatus(bool online) async {
    if (_user == null) {
      return;
    }
    // A genuine offline↔online transition, as opposed to a re-confirmation
    // of the state the hero is already in (which is what an app-lifecycle
    // resume triggers). Only a real transition justifies bypassing the
    // movement throttle on the RTDB radar write below.
    final bool isStateTransition = _isOnline != online;

    // 3-minute gate: throttle Firestore status writes to prevent write spikes
    final now = DateTime.now();
    if (_lastFirestoreStatusWriteAt != null &&
        now.difference(_lastFirestoreStatusWriteAt!).inMinutes < 3 &&
        _isOnline == online) {
      debugPrint('[HeroHomeScreen] Status write throttled by 3min gate');
      return;
    }
    try {
      Position? currentPos;
      if (online) {
        // FIX (root cause of "Hero PWA foreground tab open+focused but
        // NO ride popup ever appears"): getCurrentLocation() returning
        // null used to silently flip _isOnline back to false and show
        // one generic SnackBar — critically, this happens BEFORE
        // _listenForHeroPings()/_listenForServicePings() are ever
        // attached (they're only called further down, inside the
        // `if (online)` branch at the end of this method). So on a web
        // browser where location permission was previously denied
        // (browsers do NOT re-prompt once denied — Geolocator.
        // requestPermission() just returns `denied` again silently),
        // the hero's toggle visually flips back off almost instantly
        // and NO ping listener is ever attached for that session — the
        // hero looks "online" for a split second then silently isn't,
        // with no persistent indication anything is wrong. The old
        // message ("Enable high-accuracy location...") didn't say HOW
        // on a browser (there's no OS Settings app to open), and
        // auto-dismissed in a few seconds.
        //
        // Fix: distinguish deniedForever (needs a browser-level fix,
        // give exact steps) from a one-off failure (timeout / GPS not
        // ready yet — offer an immediate Retry action), and make both
        // messages persist until the hero dismisses them or the action
        // fires, instead of auto-hiding.
        final permission = await Geolocator.checkPermission();
        currentPos = await LocationService().getCurrentLocation();
        if (currentPos == null) {
          if (mounted) {
            setState(() => _isOnline = false);
            final isBrowserBlocked = kIsWeb &&
                (permission == LocationPermission.deniedForever ||
                    permission == LocationPermission.denied);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                  isBrowserBlocked
                      ? 'Location is blocked for this site. Click the lock/info icon next to the address bar, allow Location, then tap Online again.'
                      : 'Could not get your location. Check GPS is on and try again.',
                ),
                backgroundColor: _red,
                behavior: SnackBarBehavior.floating,
                duration: const Duration(seconds: 8),
                action: SnackBarAction(
                  label: 'RETRY',
                  textColor: Colors.white,
                  onPressed: () {
                    setState(() => _isOnline = true);
                    unawaited(_syncOnlineStatus(true));
                  },
                ),
              ),
            );
          }
          return;
        }
      }

      if (online) {
        // ── RTDB radar write ──
        // On a genuine offline→online transition we force the write and
        // bypass the movement throttle: the hero has just appeared and
        // must show on customer radar immediately.
        //
        // On a mere re-confirmation (app-lifecycle resume, which fires on
        // every browser tab-focus change in the PWA) the hero has not
        // moved and is already published, so we apply the same movement
        // gate the periodic radar timer uses instead of writing
        // unconditionally. Without this, every tab switch cost a
        // redundant RTDB write.
        if (currentPos != null) {
          bool shouldWriteRadar = isStateTransition;
          if (!shouldWriteRadar) {
            if (_lastUploadedPosition == null) {
              // No published baseline — must write to appear on radar.
              shouldWriteRadar = true;
            } else {
              final movedMeters = Geolocator.distanceBetween(
                _lastUploadedPosition!.latitude,
                _lastUploadedPosition!.longitude,
                currentPos.latitude,
                currentPos.longitude,
              );
              shouldWriteRadar =
                  movedMeters >= _idleRadarMoveThresholdMeters;
              if (!shouldWriteRadar) {
                debugPrint(
                  '[ONLINE] Skipped radar write — no state change, '
                  'moved only ${movedMeters.toStringAsFixed(1)}m of '
                  '${_idleRadarMoveThresholdMeters.toStringAsFixed(0)}m',
                );
              }
            }
          }

          if (shouldWriteRadar) {
            // Reset throttle baselines only when we are actually writing.
            _lastUploadedPosition = null;
            _lastGpsUpdate = null;
            final onlineHeroRef =
                FirebaseDatabase.instance.ref('online_heroes/${_user!.uid}');
            await onlineHeroRef.set({
              'lat': currentPos.latitude,
              'lng': currentPos.longitude,
              'latitude': currentPos.latitude,
              'longitude': currentPos.longitude,
              'name': _captainName,
              'vehicleType': _normalizeHeroVehicleType(_vehicleType),
              'isAvailable': _activeRideId.isEmpty,
              'category': _normalizeHeroVehicleType(_vehicleType).toLowerCase(),
        // PER-HERO SERVICE ACCESS (Aug 17 2026): mirrored into the
        // presence node so both dispatchers can honour it without
        // spending a Firestore read per hero per booking. See
        // lib/config/hero_service_access.dart.
        if (_serviceAccess != null) kHeroServiceAccessField: _serviceAccess,
        if (_heroSkills.isNotEmpty) kHeroSkillsField: _heroSkills,
              'city': _heroCity,
              'lastUpdated': ServerValue.timestamp,
            });
            // FIX: every .remove() call on this node elsewhere in this
            // file only runs on a GRACEFUL exit (dispose(), the offline
            // toggle, tab-hidden cleanup) — none of that code runs if the
            // hero force-closes the app, the OS kills the process, their
            // network drops, or a browser tab gets killed outright. This
            // is a server-side hook: Firebase's own RTDB server removes
            // this node the instant it detects the connection is gone,
            // no matter how ungracefully the client left. Re-registering
            // it on every write is safe/idempotent — it just replaces
            // the pending disconnect action with an equivalent one.
            // FIX (presence reliability audit): was a bare unawaited()
            // with no error handling — if this registration call itself
            // failed (transient network blip at exactly the wrong
            // moment), the hero would go online with NO server-side
            // disconnect hook armed for that entire session, and
            // nothing would ever know. Now logged so a silent failure
            // is at least visible in debug output instead of invisible.
            // FIX (Aug 11 2026 — ROOT CAUSE of Nizam's "2 tabs on mobile
            // browser, hero never receives the ride request"): this used
            // to be `onDisconnect().remove()`, which DELETED the hero
            // from online_heroes the instant their socket dropped. On a
            // mobile browser that is catastrophic for the two-tab test:
            // the moment the Hero tab is backgrounded (because the
            // customer switched to the Customer tab to book!), the
            // browser suspends its WebSocket, RTDB's server fires this
            // hook, the hero's node is deleted -- and
            // ride_search_screen.dart's _fetchNearbyHeroes() then finds
            // NOBODY, so no ping is ever broadcast. The hero was made
            // undiscoverable by the very act of the customer switching
            // tabs to book. Same thing happens on any phone-screen-off,
            // app-switch, or brief network blip.
            //
            // Fix: keep the node but STAMP it as disconnected. The hero
            // stays discoverable for a short grace window (see
            // kPresenceGraceMs in ride_search_screen.dart), which is
            // correct because the ping is delivered by mechanisms that
            // survive a suspended tab anyway -- the persisted
            // hero_pings/{heroId}/{requestId} RTDB node (their listener
            // fires the moment the tab resumes) plus the FCM push. A
            // hero who genuinely left simply stops being returned once
            // the grace window lapses, and the broadcast already pings
            // ALL nearby heroes simultaneously, so one stale entry can
            // never block dispatch.
            unawaited(onlineHeroRef
                .onDisconnect()
                .update({
                  'connectionLost': true,
                  'disconnectedAt': ServerValue.timestamp,
                })
                .catchError((Object e) {
              debugPrint('[HeroHomeScreen] onDisconnect() registration failed: $e');
            }));
            _lastUploadedPosition = currentPos;
            debugPrint(
              '🔥 [ONLINE] Wrote hero position to RTDB '
              'online_heroes/${_user!.uid} '
              '(transition=$isStateTransition)',
            );
          }
        }
      }

      // FIX (WhatsApp-model presence migration, CTO mandate): this used
      // to also .set() {isOnline, status, isAvailable, lastSeen,
      // captainName, vehicleType} into the Firestore heroes doc on every
      // toggle. Firestore no longer tracks any of that — RTDB's
      // online_heroes/{uid} node above (backed by onDisconnect()) is now
      // the ONLY place presence lives, which is exactly what fixes
      // "heroes showing online even after closing the app": RTDB
      // self-heals on disconnect, Firestore never could.
      _lastFirestoreStatusWriteAt = now;

      if (mounted) {
        setState(() {
          _isOnline = online;
        });
      }

      // Manage ping subscription based on online state
      if (online) {
        _listenForHeroPings();
        _listenForServicePings();
        _startPresenceConnectionWatcher();
        // CTO mandate — FCM Layer 2 alternative, Option D: keeps the
        // app process (and the two listeners started just above) alive
        // in the background via a persistent "You are Online"
        // notification, instead of relying on FCM to wake a killed
        // process. Best-effort — never blocks going online.
        unawaited(HeroForegroundService.start());
        // APP INFRA COST RECOVERY (per Nizam's instruction): start the
        // in-memory "active minutes" clock the moment the hero is
        // genuinely online. Idempotent -- a lifecycle-resume that just
        // re-confirms an already-online state does NOT reset it (see
        // HeroUsageAccumulatorService.startSession()).
        if (isStateTransition) {
          HeroUsageAccumulatorService().startSession();
        }
      } else {
        _heroPingSub?.cancel();
        _heroPingSub = null;
        _stopServicePingListening();
        _stopPresenceConnectionWatcher();
        unawaited(HeroForegroundService.stop());
        // APP INFRA COST RECOVERY: flush the accumulated online-minutes
        // usage fee the moment the hero goes Offline -- this is one of
        // only two flush points in the whole design (the other is ride
        // completion, in hero_ride_screen.dart), per Nizam's explicit
        // "batched, not per-minute" cost-optimization instruction. Fully
        // non-fatal: a flush failure must never block the hero from
        // actually going offline.
        if (isStateTransition) {
          // FIX (Hero Earnings & Online Time Monitor, Aug 11 2026):
          // captured BEFORE endSession() clears it — this is when the
          // online period truly began, unlike _sessionStartedAt which
          // gets reset on every mid-session flush above.
          final trueSessionStart =
              HeroUsageAccumulatorService().trueSessionStartedAt;
          final activeMinutes =
              HeroUsageAccumulatorService().consumeBillableMinutes();
          final ridesHandled =
              HeroUsageAccumulatorService().consumeRidesHandled();
          // FIX (Dynamic Micro-Billing, Aug 11 2026): safety-net flush —
          // ride/task completions normally flush immediately at their
          // own payment point, so this is usually 0, but if a hero goes
          // Offline with any un-flushed activity still pending, its
          // distance (if any) must come along too so it bills
          // dynamically instead of silently falling back to flat.
          final rideDistancesKm =
              HeroUsageAccumulatorService().consumeRideDistances();
          HeroUsageAccumulatorService().endSession();
          unawaited(
            HeroWalletService()
                .flushUsageCost(
                  heroId: _user!.uid,
                  activeMinutes: activeMinutes,
                  ridesHandled: ridesHandled,
                  rideDistancesKm: rideDistancesKm,
                  heroName: _captainName,
                )
                .catchError((Object e) {
              debugPrint(
                '[HeroHomeScreen] Usage-fee flush on offline-toggle failed (non-fatal): $e',
              );
            }),
          );
          // FIX (Hero Earnings & Online Time Monitor, Aug 11 2026): logs
          // one doc per online→offline cycle so the new Earnings/Online
          // Time screen has a persistent history to sum — nothing
          // tracked this before (confirmed by audit: online-time only
          // ever existed as an in-memory clock, lost on app kill).
          // Bounded exactly like the usage-fee flush above — one write
          // per toggle, never per-minute. Best-effort: a logging
          // failure must never block the hero from going offline.
          if (trueSessionStart != null && _user != null) {
            final now = DateTime.now();
            final durationMinutes =
                now.difference(trueSessionStart).inSeconds / 60.0;
            if (durationMinutes > 0) {
              unawaited(_logHeroSession(
                heroId: _user!.uid,
                startedAt: trueSessionStart,
                durationMinutes: durationMinutes,
              ));
            }
          }
        }
        // FIX: this is the root cause of "admin dispatched a ride but the
        // hero never saw it." Going online (the `if (online)` branch
        // above) writes online_heroes/{uid} — but going offline never
        // removed it. So after a hero manually flips the toggle off,
        // their RTDB radar entry lingered with stale coordinates and a
        // stale isAvailable value, and kept showing as "AVAILABLE" on
        // the admin's Dispatch Heroes map/list indefinitely (until an
        // ungraceful disconnect eventually fired the onDisconnect()
        // cleanup added earlier, or the hero went online again and
        // overwrote it). An admin could then dispatch a ride straight to
        // a hero who looked available but whose ping listener had
        // already been cancelled two lines above — the ping went
        // nowhere, silently, with no error on either side.
        FirebaseDatabase.instance
            .ref('online_heroes/${_user!.uid}')
            .remove()
            .catchError((Object e) {
          debugPrint('[HeroHomeScreen] online_heroes cleanup on offline-toggle failed: $e');
        });
      }
    } catch (e) {
      debugPrint('[HeroHomeScreen] syncOnlineStatus error: ');
      _heroPingSub?.cancel();
      _heroPingSub = null;
      _stopServicePingListening();
      _stopPresenceConnectionWatcher();
      unawaited(HeroForegroundService.stop());
      if (mounted) {
        setState(() => _isOnline = false);
      }
    }
  }

  // ── `.info/connected` reconnect watcher ──────────────────────────
  // FIX (CTO architecture review — presence, take 2): onDisconnect()
  // is armed against the CURRENT RTDB session only. If that session
  // drops and silently reconnects (network blip, carrier handover, a
  // backgrounded PWA tab resuming its socket) the old onDisconnect()
  // hook is gone with the dead session, and nothing re-arms it on the
  // new one unless we explicitly do so — a hero could stay "online" in
  // Firestore/UI terms but have zero disconnect protection until they
  // next move enough to trigger a radar write (which, correctly, no
  // longer happens on any fixed timer).
  //
  // `.info/connected` is RTDB's own connection-state stream: free (not
  // a real read/write against the database, just local connection
  // state), and event-driven — it only fires on an actual connect or
  // disconnect transition, never on a timer. Re-writing presence +
  // re-arming onDisconnect() on every `true` transition (the official
  // Firebase presence pattern) closes the reconnect gap with zero
  // polling and zero writes while the hero simply stays connected and
  // stationary.
  void _startPresenceConnectionWatcher() {
    _presenceConnectedSub?.cancel();
    final uid = _user?.uid;
    if (uid == null) return;
    _presenceConnectedSub = FirebaseDatabase.instance
        .ref('.info/connected')
        .onValue
        .listen((event) {
      final connected = event.snapshot.value == true;
      // Also covers the very first connect right after _syncOnlineStatus's
      // own write above — a harmless, one-time redundant write, not a
      // recurring one, since this only re-fires on genuine
      // connect/disconnect transitions.
      if (!connected || !_isOnline) return;
      final onlineHeroRef = FirebaseDatabase.instance.ref('online_heroes/$uid');
      final pos = _latestPosition;
      final payload = <String, dynamic>{
        'name': _captainName,
        'vehicleType': _normalizeHeroVehicleType(_vehicleType),
        'isAvailable': _activeRideId.isEmpty,
        'category': _normalizeHeroVehicleType(_vehicleType).toLowerCase(),
        // PER-HERO SERVICE ACCESS (Aug 17 2026): mirrored into the
        // presence node so both dispatchers can honour it without
        // spending a Firestore read per hero per booking. See
        // lib/config/hero_service_access.dart.
        if (_serviceAccess != null) kHeroServiceAccessField: _serviceAccess,
        if (_heroSkills.isNotEmpty) kHeroSkillsField: _heroSkills,
        'city': _heroCity,
        'lastUpdated': ServerValue.timestamp,
        // Clear the disconnect stamp — this is a live reconnect, so the
        // hero is genuinely back. (This is an .update()/merge, unlike the
        // .set() calls elsewhere which replace the node wholesale and
        // therefore drop these fields automatically.)
        'connectionLost': false,
        if (pos != null) 'lat': pos.latitude,
        if (pos != null) 'lng': pos.longitude,
        if (pos != null) 'latitude': pos.latitude,
        if (pos != null) 'longitude': pos.longitude,
      };
      unawaited(
        onlineHeroRef.update(payload).then((_) {
          // See the detailed comment on the first onDisconnect()
          // registration in _syncOnlineStatus — stamp-don't-delete, so a
          // backgrounded/suspended tab stays discoverable for the grace
          // window instead of vanishing from customer-side search.
          return onlineHeroRef.onDisconnect().update({
            'connectionLost': true,
            'disconnectedAt': ServerValue.timestamp,
          });
        }).catchError((Object e) {
          debugPrint('[HeroHomeScreen] .info/connected re-arm failed: $e');
        }),
      );
    }, onError: (Object e) {
      debugPrint('[HeroHomeScreen] .info/connected listener error: $e');
    });
  }

  void _stopPresenceConnectionWatcher() {
    _presenceConnectedSub?.cancel();
    _presenceConnectedSub = null;
  }

  // ── GLOBAL LOCATION TRACKING (Radar) ─────────────────────────
  void _startGlobalLocationTracking() {
    // IDEMPOTENCE GUARD — fixes "hero vanishes from radar on tab switch".
    //
    // This method used to unconditionally call _stopGlobalLocationTracking()
    // first, which does an RTDB remove() on online_heroes/{uid}. On an
    // AppLifecycleState.resumed event (fired on every browser tab-focus
    // change in the PWA) _loadHeroData() calls this method again, so the
    // node that _syncOnlineStatus had just force-written was immediately
    // deleted. For a stationary hero the 50m gate below then legitimately
    // suppresses every subsequent write, so the hero could stay invisible
    // to customer-side radar indefinitely.
    //
    // If tracking is already running there is nothing to restart: the
    // location stream and timer are both still live.
    if (_locationTimer != null && _locationTimer!.isActive) {
      debugPrint(
        '🛰️ Hero Live Tracking already active — skipping redundant restart',
      );
      return;
    }

    _stopGlobalLocationTracking();

    // FIX BUG #1: Get initial position IMMEDIATELY so the 5s timer has data
    LocationService().getCurrentLocation().then((pos) {
      if (pos != null && mounted) {
        _latestPosition = pos;
        _animateHeroMarkerTo(pos);
      }
    }).catchError((Object e) {
      debugPrint('⚠️ Initial GPS fetch failed: $e');
    });

    // Listen to location stream to keep _latestPosition fresh
    _globalLocationSub = LocationService().getLocationStream(
      
    ).listen(
      (position) {
        _latestPosition = position;
        _animateHeroMarkerTo(position);
      },
      onError: (Object e) => debugPrint('Global location stream error: $e'),
    );

    // 10-second interval — only for idle radar when no active ride
    _locationTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      if (_isOnline && _user != null && _latestPosition != null) {
        final pos = _latestPosition!;

        // SKIP both RTDB radar & Firestore writes if on an active ride
        if (_activeRideId.isNotEmpty) {
          return;
        }

        // RTDB idle radar — movement-gated to save writes.
        // The timer only SAMPLES position every 10s; it never writes on
        // elapsed time alone. A write happens strictly when the hero has
        // moved at least _idleRadarMoveThresholdMeters since the last
        // published position.
        if (_lastUploadedPosition != null) {
          final dist = Geolocator.distanceBetween(
            _lastUploadedPosition!.latitude,
            _lastUploadedPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          if (dist < _idleRadarMoveThresholdMeters) {
            debugPrint(
              '[Location] Skipped RTDB update — moved only '
              '${dist.toStringAsFixed(1)}m of '
              '${_idleRadarMoveThresholdMeters.toStringAsFixed(0)}m',
            );
            // No heartbeat write here (removed per CTO architecture
            // review — DB cost + wrong business fit for a hero parked
            // and waiting on an order for an hour). Presence for a
            // stationary-but-connected hero is entirely covered by
            // onDisconnect() + the .info/connected re-arm watcher
            // (_startPresenceConnectionWatcher) — neither needs the
            // node touched again until the hero actually moves.
            return;
          }
        }
        _lastUploadedPosition = pos;
        final onlineHeroRef =
            FirebaseDatabase.instance.ref('online_heroes/${_user!.uid}');
        await onlineHeroRef.set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'name': _captainName,
          'vehicleType': _normalizeHeroVehicleType(_vehicleType),
          'isAvailable': _activeRideId.isEmpty,
          'category': _normalizeHeroVehicleType(_vehicleType).toLowerCase(),
        // PER-HERO SERVICE ACCESS (Aug 17 2026): mirrored into the
        // presence node so both dispatchers can honour it without
        // spending a Firestore read per hero per booking. See
        // lib/config/hero_service_access.dart.
        if (_serviceAccess != null) kHeroServiceAccessField: _serviceAccess,
        if (_heroSkills.isNotEmpty) kHeroSkillsField: _heroSkills,
          'lastUpdated': ServerValue.timestamp,
        });
        // See the matching comment on the other online_heroes.set() call
        // above — server-side stamp (NOT delete) for ungraceful exits, so
        // a suspended background tab stays discoverable for the grace
        // window rather than disappearing from customer-side search.
        unawaited(onlineHeroRef
            .onDisconnect()
            .update({
              'connectionLost': true,
              'disconnectedAt': ServerValue.timestamp,
            })
            .catchError((Object e) {
          debugPrint('[HeroHomeScreen] onDisconnect() re-registration failed: $e');
        }));

        // Firestore: SKIPPED in timer — status writes are handled by
        // _syncOnlineStatus with its own 3-minute gate.
      } else if (_isOnline && _user != null && _latestPosition == null) {
        debugPrint(
          '⚠️ RTDB skipped — _latestPosition still null, waiting for GPS',
        );
      }
    });

    debugPrint('🛰️ Hero Live Tracking STARTED (10s interval)');
  }

  // _shouldWriteFirestoreLocation REMOVED - Firestore writes only via _syncOnlineStatus

  /// Watches heroes/{uid}.serviceAccess so an admin's change reaches a
  /// hero who is ALREADY online (Aug 17 2026 — see _serviceAccess).
  ///
  /// Without this, disabling e.g. parcel for a hero mid-shift would keep
  /// sending them parcel jobs until they next went offline and back on,
  /// because both dispatchers read the mirrored copy in the RTDB
  /// presence node — and only this screen ever writes that node.
  void _watchServiceAccess() {
    final uid = _user?.uid;
    if (uid == null) return;
    _serviceAccessSub?.cancel();
    _serviceAccessSub = FirebaseFirestore.instance
        .collection('heroes')
        .doc(uid)
        .snapshots()
        .listen((snap) {
      final data = snap.data();
      if (data == null) return;
      final next = data[kHeroServiceAccessField] is Map
          ? Map<String, dynamic>.from(data[kHeroServiceAccessField] as Map)
          : null;

      // Skills ride along on this same listener rather than getting a
      // second one: it is already watching the whole hero doc, and an
      // admin granting a hero a second trade mid-shift should reach
      // dispatch on the next booking, not the next app restart.
      final nextSkills = heroSkillsOf(data);

      // Cheap equality check — this listener also fires for every other
      // field on the hero doc (coins, commission, status...), and we do
      // not want an RTDB presence rewrite on each of those.
      if (next.toString() == _serviceAccess.toString() &&
          nextSkills.join(',') == _heroSkills.join(',')) {
        return;
      }

      _serviceAccess = next;
      _heroSkills = nextSkills;
      if (!mounted) return;
      setState(() {});

      // Republish presence immediately so dispatch honours the new
      // permissions on the very next booking, not the next GPS tick.
      if (_isOnline && _user != null) {
        FirebaseDatabase.instance
            .ref('online_heroes/${_user!.uid}')
            .update({
          if (next != null) kHeroServiceAccessField: next,
          if (next == null) kHeroServiceAccessField: null,
          // Null, not an omitted key: this is an update(), so writing
          // null is what actually CLEARS a stale skill list from the
          // presence node when an admin removes a hero's trade.
          kHeroSkillsField: nextSkills.isEmpty ? null : nextSkills,
        }).catchError((Object e) {
          debugPrint('[HeroHome] serviceAccess presence sync failed: $e');
        });
      }
    }, onError: (Object e) {
      debugPrint('[HeroHome] serviceAccess watcher error: $e');
    });
  }

  // ================================================================
  // UPDATE BANNER (Aug 17 2026)
  // ================================================================
  // Nizam: "hero work iruntha athu mudichutu home page irukapo mattum
  // update button kaati, again instal agi home page ku varramari
  // pannirlam" — and that instruction is what makes this safe.
  //
  // It is rendered ONLY inside the OFFLINE view, which by construction
  // is the idle state: a hero with a live ride or an accepted service
  // request is never looking at this widget. Belt and braces, the two
  // active-work flags are re-checked below anyway, because "which view
  // am I in" is a UI fact and "am I mid-job" is a data fact, and the
  // second one is the one that matters.
  //
  // Why interrupting a working hero would be serious: installing an APK
  // kills the process. A hero halfway to a customer would lose their
  // screen, their tracking, and the customer's ride. So the update is
  // offered between jobs or not at all. After reinstall the app cold
  // starts on the hero home page, which is exactly the "same place"
  // outcome asked for — no state restore machinery needed, because
  // there is no in-progress state to restore.
  Widget _buildUpdateBanner() {
    if (!AppUpdateGateService.instance.updateAvailable) {
      return const SizedBox.shrink();
    }
    // Data-level idle check (see above).
    if (_activeRideId.isNotEmpty || _hasActiveServiceRequest) {
      return const SizedBox.shrink();
    }

    final notes = AppUpdateGateService.instance.notes;
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFF6C63FF).withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF6C63FF)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.system_update_rounded,
                  color: Color(0xFF6C63FF), size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  'New Hero app update available',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF6C63FF),
                    fontWeight: FontWeight.w800,
                    fontSize: 13.5,
                  ),
                ),
              ),
            ],
          ),
          if (notes.isNotEmpty) ...[
            const SizedBox(height: 6),
            Text(notes,
                style: GoogleFonts.outfit(fontSize: 12, height: 1.4)),
          ],
          const SizedBox(height: 4),
          Text(
            'You have no active job right now — this is a safe moment to '
            'update. The app will reopen on this home screen.',
            style: GoogleFonts.outfit(fontSize: 11, height: 1.4),
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            height: 40,
            child: ElevatedButton.icon(
              onPressed: _runHeroUpdate,
              icon: const Icon(Icons.download_rounded, size: 17),
              label: Text('Update now',
                  style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF6C63FF),
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(11)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _runHeroUpdate() async {
    // Re-check at the moment of the tap, not just at render. A ride can
    // arrive between the banner painting and the hero pressing it.
    if (_activeRideId.isNotEmpty || _hasActiveServiceRequest) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'You just got a job — finish it first, then update from here.',
          ),
        ),
      );
      return;
    }

    if (kIsWeb) {
      // PWA path: no APK. Clear the cached bundle and reload in place —
      // same mechanism the drawer's Check for Updates already uses.
      try {
        await PwaCachePlatform().clearAndReload();
      } catch (e) {
        debugPrint('[HeroHome] PWA update reload failed: $e');
      }
      return;
    }

    final url = AppUpdateGateService.instance.apkUrlFor('hero');
    final ok = await launchUrl(
      Uri.parse(url),
      mode: LaunchMode.externalApplication,
    );
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open the update link.')),
      );
    }
  }

  void _stopGlobalLocationTracking() {
    _globalLocationSub?.cancel();
    _globalLocationSub = null;
    _locationTimer?.cancel();
    _locationTimer = null;
    _lastUploadedPosition = null;
    _lastGpsUpdate = null;
    if (_user != null) {
      FirebaseDatabase.instance.ref('online_heroes/${_user!.uid}').remove();
    }
    debugPrint('Global Radar tracking STOPPED');
  }

  @override
  void dispose() {
    ChittiHostBridge.unregisterHeroOnline(_chittiSetOnline);
    WidgetsBinding.instance.removeObserver(this);
    // T1: Cancel UI-only subscriptions (foreground popup listeners).
    // FCM background handler in main_hero.dart continues to deliver
    // ride alerts when the app is minimised or terminated.
    _foregroundMessageSub?.cancel();
    _messageOpenedSub?.cancel();
    _serviceRequestBusySub?.cancel();
    _presenceConnectedSub?.cancel();
    // Server-clock watcher (Aug 11 2026) — one lightweight RTDB
    // subscription on .info/serverTimeOffset; must be released like the
    // rest or it leaks across screen rebuilds.
    _serverOffsetSub?.cancel();
    _serverOffsetSub = null;
    // Per-hero service-access watcher (Aug 17 2026) — one Firestore
    // listener on this hero's own doc; released like every other stream.
    _serviceAccessSub?.cancel();
    _serviceAccessSub = null;
    // Cancel Firestore/RTDB popup streams — background FCM replaces them.
    _stopBroadcastRideStream();
    // Dispose UI-only animation controllers.
    _pulseCtrl?.dispose();
    _disposeHeroMarkerAnimation();
    // Stop GPS position listener and location timer (battery saving).
    // _stopGlobalLocationTracking also cleans up RTDB online_heroes node.
    // T1: Does NOT touch Firestore heroes/{uid}.status — stays 'online'.
    _stopLocationUpdates();
    _stopGlobalLocationTracking();
    super.dispose();
  }

  Future<void> _initializeNotifications() async {
    try {
      await HeroRideNotificationService.initialize();
      if (!mounted) {
        return;
      }
      final messaging = FirebaseMessaging.instance;
      final settings = await messaging.requestPermission();
      if (!mounted) {
        return;
      }
      debugPrint(
        '[HeroHomeScreen] Notification permission: ${settings.authorizationStatus}',
      );

      _foregroundMessageSub?.cancel();
      _foregroundMessageSub = FirebaseMessaging.onMessage.listen((message) {
        unawaited(_handleIncomingPush(message, openedByUser: false));
      });

      _messageOpenedSub?.cancel();
      _messageOpenedSub =
          FirebaseMessaging.onMessageOpenedApp.listen((message) {
        unawaited(_handleIncomingPush(message, openedByUser: true));
      });

      final initialMessage = await messaging.getInitialMessage();
      if (!mounted) {
        return;
      }
      if (initialMessage != null) {
        unawaited(_handleIncomingPush(initialMessage, openedByUser: true));
      }
    } catch (e) {
      debugPrint('[HeroHomeScreen] Notification init error: $e');
    }
  }

  // T3 FIX: looping param — pass true when called from showRideRequestDialog
  // so ringtone keeps playing until the hero responds.
  void _playIncomingRideAlertSafe({bool looping = false}) {
    Future.microtask(() async {
      try {
        if (!kIsWeb) {
          await HeroRideNotificationService.playWakeAlertRingtone(
            looping: looping,
          );
        } else {
          debugPrint(
            '[HeroHomeScreen] Web: skipping ringtone (autoplay policy)',
          );
        }
      } catch (e) {
        debugPrint('[HeroHomeScreen] Ringtone suppressed: $e');
      }
    }).catchError((Object e) {
      debugPrint('[HeroHomeScreen] Ringtone microtask error: $e');
    });
  }

  Future<void> _playIncomingRideAlert() async => _playIncomingRideAlertSafe();

  Future<void> _consumePendingRidePush() async {
    if (!mounted) {
      return;
    }
    try {
      // FIX (killed-app notification-tap dead end, same root cause as
      // _fetchTargetedRideOnce): removed `!_isOnline` — this is the
      // exact cold-start path where _isOnline hasn't restored yet.
      //
      // FIX 2 (Aug 10 2026 — "notification tap opens app, hero lands on
      // a blank dummy screen, no way to start the ride"): a plain
      // `if (_user == null) return;` used to bail out for good right
      // here on a cold/killed-app launch triggered by tapping the
      // notification — Firebase Auth restore hasn't necessarily
      // finished by the time this runs on a fresh process start, so
      // `_user` (this State's own field, kept in sync by a separate
      // auth listener elsewhere) can still be null at this exact
      // moment even though the hero IS actually signed in and about to
      // be recognized a beat later. Previously that one null check
      // permanently dropped the pending accept — nothing ever retried
      // it, so the hero opened the app to whatever the default boot
      // screen is, with zero indication a ride was waiting. Now waits
      // briefly for auth to catch up before giving up for real.
      if (_user == null) {
        final becameReady = await _waitForUserReady();
        if (!becameReady) {
          return;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) {
        return;
      }
      final rideId = prefs.getString(_pendingHeroRideIdKey);
      if (rideId == null || rideId.trim().isEmpty) {
        return;
      }
      final normalizedRideId = rideId.trim();
      final acceptRideId = prefs.getString(kPendingHeroAcceptRideIdKey);
      if (acceptRideId == normalizedRideId) {
        final doc = await FirebaseFirestore.instance
            .collection('rides')
            .doc(normalizedRideId)
            .get();
        if (!mounted) {
          return;
        }
        final data = doc.data();
        if (doc.exists &&
            data != null &&
            _rideTargetsCurrentHero(data) &&
            _isRecentCreatedRide(data)) {
          await prefs.remove(kPendingHeroAcceptRideIdKey);
          await prefs.remove(_pendingHeroRideIdKey);
          await _acceptRide(doc.id, data);
          return;
        }
      }
      await _fetchTargetedRideOnce(normalizedRideId);
      await prefs.remove(_pendingHeroRideIdKey);
    } catch (e) {
      debugPrint('[HeroHomeScreen] Pending push restore failed: $e');
    }
  }

  /// Shared helper (Aug 10 2026 fix) for both _consumePendingRidePush()
  /// and _consumePendingServiceRequestPush(): on a cold/killed-app
  /// launch triggered by a notification tap, `_user` (kept in sync by
  /// this State's own auth listener) can lag a beat behind Firebase
  /// Auth's actual session restore. Polls briefly instead of giving up
  /// on the very first check — cheap (a few in-memory field reads, no
  /// network calls), and short enough (2s max) that it never makes a
  /// genuinely-signed-out cold open hang.
  Future<bool> _waitForUserReady({
    Duration timeout = const Duration(seconds: 2),
  }) async {
    final deadline = DateTime.now().add(timeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!mounted) return false;
      if (_user != null) return true;
      await Future<void>.delayed(const Duration(milliseconds: 150));
    }
    return _user != null;
  }

  /// FCM Data Push Layer 2 counterpart to _consumePendingRidePush() —
  /// picks up a service-request push that arrived while the app was
  /// fully killed (main_hero.dart's background handler wrote the
  /// pending key to SharedPreferences since there was no live Dart
  /// isolate to show the accept dialog directly at that moment).
  Future<void> _consumePendingServiceRequestPush() async {
    if (!mounted) {
      return;
    }
    try {
      // FIX (same root cause as above): removed `!_isOnline`.
      // FIX 2 (same root cause as _consumePendingRidePush's FIX 2,
      // above — this is the exact bug reported: "hero_booking
      // notification ACCEPT opens the app to a blank dummy screen with
      // no way to start the ride"): was a hard `if (_user == null)
      // return;` with no retry. Service-request accept has no
      // fast-path the way ride-accept does (see the comment where
      // kPendingHeroAcceptRideIdKey is written) — it depends entirely
      // on this method successfully reaching
      // _fetchTargetedServiceRequestOnce() to open the accept dialog.
      // If auth wasn't ready yet on a cold launch, this used to just
      // silently give up forever, which is exactly why the hero saw
      // nothing happen after tapping ACCEPT.
      if (_user == null) {
        final becameReady = await _waitForUserReady();
        if (!becameReady) {
          return;
        }
      }
      final prefs = await SharedPreferences.getInstance();
      if (!mounted) {
        return;
      }
      final requestId = prefs.getString(_pendingHeroServiceRequestIdKey);
      if (requestId == null || requestId.trim().isEmpty) {
        return;
      }
      await _fetchTargetedServiceRequestOnce(requestId.trim());
      await prefs.remove(_pendingHeroServiceRequestIdKey);
    } catch (e) {
      debugPrint('[HeroHomeScreen] Pending service-request push restore failed: $e');
    }
  }

  String? _rideIdFromPush(RemoteMessage message) {
    for (final key in const <String>[
      'rideId',
      'ride_id',
      'rideDocId',
      'ride_doc_id',
    ]) {
      final value = message.data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  String? _serviceRequestIdFromPush(RemoteMessage message) {
    for (final key in const <String>['requestId', 'request_id']) {
      final value = message.data[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
    }
    return null;
  }

  Future<void> _handleIncomingPush(
    RemoteMessage message, {
    required bool openedByUser,
  }) async {
    await _storeIncomingNotification(message);
    if (!mounted) {
      return;
    }
    final rideId = _rideIdFromPush(message);
    if (rideId != null) {
      await _fetchTargetedRideOnce(
        rideId,
        showLocalNotification: !openedByUser,
      );
      if (!mounted) {
        return;
      }
      return;
    }
    // FCM Data Push Layer 2 — generic service_requests dispatch
    // (hero_booking/custom_food_order/grocery_order/etc.), keyed by
    // requestId rather than rideId. Same "targeted push" shape as the
    // ride branch above, just routed into _showServiceRequestDialog
    // instead of _showRideRequestDialog.
    final requestId = _serviceRequestIdFromPush(message);
    if (requestId != null) {
      await _fetchTargetedServiceRequestOnce(
        requestId,
        showLocalNotification: !openedByUser,
      );
      if (!mounted) {
        return;
      }
      return;
    }
    if (!mounted) {
      return;
    }
    if (openedByUser) {
      Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => const NotificationsScreen(),
        ),
      );
      return;
    }
    final title = message.notification?.title ?? 'New update';
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(title),
        backgroundColor: _njPink,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _fetchTargetedRideOnce(
    String rideId, {
    bool showLocalNotification = false,
  }) async {
    // FIX (per Nizam's bug report — "ride enquiry never reaches Hero
    // PWA/app, notification tap does nothing"): dropped the `!_isOnline`
    // check here. Root cause found: _isOnline defaults false and only
    // flips true asynchronously after a hero-status restore completes,
    // which races against a cold-start notification tap or an app-resume
    // ping — the exact moment a ride is most likely to arrive. But the
    // fact a targeted push/ping exists for THIS rideId already proves the
    // server-side dispatch (which reads online_heroes) considered this
    // hero online when it sent it; re-checking the local (possibly still
    // stale) _isOnline flag here just silently swallowed real rides.
    if (_user == null ||
        _activeRideId.isNotEmpty ||
        _hasActiveServiceRequest) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('rides')
          .doc(rideId)
          .get();
      if (!mounted || !doc.exists) {
        return;
      }
      final data = doc.data();
      if (data == null) {
        return;
      }
      if (!_rideTargetsCurrentHero(data) || !_isRecentCreatedRide(data)) {
        debugPrint('[HeroHomeScreen] Ignored non-targeted ride push: $rideId');
        return;
      }
      // FIX-B2: Notification is best-effort; web guard prevents plugin crash.
      if (showLocalNotification && !kIsWeb) {
        try {
          unawaited(
            HeroRideNotificationService.showRideAssigned(
              rideId: doc.id,
              data: data,
              playAlertTone: false,
            ),
          );
        } catch (e) {
          debugPrint('[HeroHomeScreen] Notification error (ignored): $e');
        }
      }
      // Popup fires regardless of notification success.
      if (!_isShowingRideDialog) {
        _showRideRequestDialog(doc.id, data);
      }
    } catch (e) {
      debugPrint('[HeroHomeScreen] Single ride fetch failed: $e');
    }
  }

  /// FCM Data Push Layer 2 counterpart to _fetchTargetedRideOnce(), for
  /// the generic service_requests dispatch pipeline. Deliberately reads
  /// back the `hero_service_pings/{uid}/{requestId}` RTDB node (rather
  /// than the Firestore service_requests doc) — that node is already in
  /// exactly the shape _showServiceRequestDialog() expects (same shape
  /// every existing ping-based dispatch path writes), so this reuses
  /// the proven accept-dialog flow with zero reshaping/duplication. If
  /// the node is gone (another hero already accepted it, or it expired
  /// before the push was opened) this is a silent no-op — the hero
  /// simply sees nothing to accept, same as a stale/expired ping today.
  Future<void> _fetchTargetedServiceRequestOnce(
    String requestId, {
    bool showLocalNotification = false,
  }) async {
    // FIX (same root cause as _fetchTargetedRideOnce): removed
    // `!_isOnline` — a targeted service-request push already proves the
    // dispatcher considered this hero online; the local flag can still
    // be lagging false right after cold start/resume.
    final uid = _user?.uid;
    if (uid == null ||
        _activeRideId.isNotEmpty ||
        _hasActiveServiceRequest ||
        _isShowingServiceDialog) {
      return;
    }
    try {
      final snap = await FirebaseDatabase.instance
          .ref('hero_service_pings/$uid/$requestId')
          .get();
      if (!mounted || !snap.exists || snap.value is! Map) {
        return;
      }
      final data = Map<String, dynamic>.from(snap.value! as Map);
      final pingExpiresAt = (data['pingExpiresAt'] as num?)?.toInt();
      if (pingExpiresAt != null &&
          DateTime.now().toUtc().millisecondsSinceEpoch > pingExpiresAt) {
        debugPrint('[HeroHomeScreen] Ignored expired service-request push: $requestId');
        return;
      }
      if (showLocalNotification && !kIsWeb) {
        try {
          unawaited(
            HeroRideNotificationService.showRideAssigned(
              rideId: requestId,
              data: data,
              playAlertTone: false,
              pushType: 'service_request',
              title: 'New Service Request',
              channelDescription:
                  'Lock-screen ride and service-request alerts with ACCEPT action and ringtone.',
              ticker: 'New service request assigned',
              emptyBodyFallback: 'Tap ACCEPT to open the request.',
            ),
          );
        } catch (e) {
          debugPrint('[HeroHomeScreen] Notification error (ignored): $e');
        }
      }
      _showServiceRequestDialog(requestId, data);
    } catch (e) {
      debugPrint('[HeroHomeScreen] Single service-request fetch failed: $e');
    }
  }

  Future<void> _storeIncomingNotification(RemoteMessage message) async {
    if (_user == null) {
      return;
    }

    final payload = UpdateService().buildNotificationPayload(
      userId: _user!.uid,
      data: message.data,
      title: message.notification?.title,
      body: message.notification?.body,
      messageId: message.messageId,
      defaultAppVariant: 'hero',
    )..['createdAt'] = FieldValue.serverTimestamp();

    await FirebaseFirestore.instance.collection('notifications').add(payload);
  }

  // Check if captain has an active ride already
  Future<void> _checkActiveRide() async {
    if (_user == null) {
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('rides')
          .where('heroId', isEqualTo: _user!.uid)
          .where('status', whereIn: _restorableRideStatuses)
          .get();
      final cutoff = _staleRideCutoff();
      final docs = snap.docs.where((doc) {
        final activityAt = _rideActivityAt(doc.data());
        return activityAt != null && activityAt.isAfter(cutoff);
      }).toList();
      docs.sort((a, b) {
        final aTime =
            _rideActivityAt(a.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        final bTime =
            _rideActivityAt(b.data()) ?? DateTime.fromMillisecondsSinceEpoch(0);
        return bTime.compareTo(aTime);
      });
      if (docs.isNotEmpty && mounted) {
        final doc = docs.first;
        setState(() {
          _activeRideId = doc.id;
          _isOnline = true;
        });
        _startLocationUpdates(doc.id);
        return;
      }
      if (mounted) {
        setState(() => _activeRideId = '');
      }
    } catch (e) {
      debugPrint('Active ride restore error: $e');
    }
  }

  Widget _njEarningsLabel(String label, String value, Color color) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          label,
          style: const TextStyle(
            color: Color(0xFF8F5A78),
            fontSize: 9,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 13,
            fontWeight: FontWeight.w800,
          ),
        ),
      ],
    );
  }

  // ================================================================
  // Ping diagnostics + server clock (Aug 11 2026)
  // ================================================================
  // WHY print() AND NOT debugPrint(): during the "customer books, hero
  // receives nothing" investigation, the customer tab's console showed
  // every print() line and NOT ONE debugPrint() line — Chrome DevTools
  // was filtering them out ("23 hidden"), so the entire ride-dispatch
  // trace was invisible exactly when it was needed. The handful of lines
  // that answer "did the ping arrive, and if it was dropped, WHY" must
  // survive a default DevTools filter. Everything else in this file
  // stays on debugPrint.
  void _pingLog(String message) {
    // ignore: avoid_print
    print('[HeroPing] $message');
  }

  /// RTDB's own clock, corrected by the offset the SDK maintains at
  /// `.info/serverTimeOffset`. Ping timing MUST NOT be judged on a raw
  /// device clock: the writer and the reader are different devices, and
  /// on a browser/PWA neither is NTP-disciplined.
  int _serverTimeOffsetMs = 0;

  int _serverNowMs() =>
      DateTime.now().toUtc().millisecondsSinceEpoch + _serverTimeOffsetMs;

  StreamSubscription<DatabaseEvent>? _serverOffsetSub;

  void _watchServerTimeOffset() {
    if (_serverOffsetSub != null) return;
    _serverOffsetSub =
        FirebaseDatabase.instance.ref('.info/serverTimeOffset').onValue.listen(
      (event) {
        final offset = (event.snapshot.value as num?)?.toInt();
        if (offset == null) return;
        _serverTimeOffsetMs = offset;
        if (offset.abs() > 5000) {
          _pingLog(
            'device clock is off by ${(offset / 1000).toStringAsFixed(1)}s '
            'vs Firebase server time — corrected',
          );
        }
      },
      onError: (Object e) {
        // Non-fatal: offset stays 0, i.e. previous behaviour.
        _pingLog('serverTimeOffset watch failed: $e');
      },
    );
  }

  void _listenForHeroPings() {
    final uid = _user?.uid;
    if (uid == null) {
      _pingLog('NOT LISTENING: no signed-in hero uid yet');
      return;
    }
    _watchServerTimeOffset();
    // Already subscribed — RTDB listeners survive app backgrounding, so a
    // lifecycle resume must not tear this down and re-create it. Both
    // _syncOnlineStatus() and _loadHeroData() call this on the same resume
    // cycle, which previously re-attached the listener twice per tab switch
    // (each re-attach costs a fresh initial-data sync). Every cancel path
    // nulls the field, so non-null reliably means "currently attached".
    if (_heroPingSub != null) {
      _pingLog('already listening on hero_pings/$uid');
      return;
    }
    _pingLog('LISTENING on hero_pings/$uid');

    // Track when listener was attached — ignore pings older than this
    final listenerAttachedAt = DateTime.now().toUtc().millisecondsSinceEpoch;

    _heroPingSub = FirebaseDatabase.instance
        .ref('hero_pings/$uid')
        .onChildAdded
        .listen((event) async {
      // FIX (same root cause as _fetchTargetedRideOnce above): removed
      // the `!_isOnline` guard. hero_pings/$uid only ever receives an
      // entry because the write side (ride_search_screen.dart) already
      // found this hero inside online_heroes and pinged them by uid —
      // by the time this listener fires, the ping's existence IS the
      // online proof. Gating on the local _isOnline flag (which can lag
      // true by several seconds after app resume/cold start) was
      // silently dropping real, valid ride pings.
      // Each of these three used to swallow a ping with no trace at all.
      // If a hero says "I got nothing", this is where the answer is.
      if (!mounted) {
        _pingLog('DROPPED: hero_home_screen not mounted');
        return;
      }
      if (_activeRideId.isNotEmpty) {
        _pingLog('DROPPED: hero already on ride $_activeRideId');
        return;
      }
      if (_hasActiveServiceRequest) {
        _pingLog('DROPPED: hero already on a service request');
        return;
      }
      if (_isShowingRideDialog) {
        _pingLog('DROPPED: a ride dialog is already showing');
        return;
      }

      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key ?? '';
      if (pingData == null || requestId.isEmpty) return;

      _pingLog('ping arrived: $requestId  data=${pingData.keys.toList()}');

      final pingExpiresAt = (pingData['pingExpiresAt'] as num?)?.toInt();
      if (pingExpiresAt == null) {
        _pingLog('DROPPED $requestId: no pingExpiresAt field');
        return;
      }

      // FIX (Aug 11 2026 — "customer books, hero app just sits there"):
      // this compared the customer's clock (pingExpiresAt is stamped from
      // the CUSTOMER's device via DateTime.now()) against the HERO's
      // clock, then DELETED the ping if it looked expired. Two phones
      // whose clocks differ by more than the 90s window would therefore
      // destroy every incoming ping on arrival — silently, with the hero
      // showing nothing and the customer searching forever. Device clocks
      // routinely drift, and a browser/PWA has no NTP discipline at all.
      //
      // Now corrected by RTDB's own server-time offset (.info/
      // serverTimeOffset, maintained by the SDK), so both sides measure
      // against Firebase's clock rather than their own.
      final nowServer = _serverNowMs();
      if (nowServer > pingExpiresAt) {
        final lateBy = nowServer - pingExpiresAt;
        _pingLog('EXPIRED $requestId by ${(lateBy / 1000).toStringAsFixed(0)}s');
        // Only sweep pings that are expired beyond any plausible skew.
        // Deleting a merely-borderline ping used to destroy the only
        // evidence that dispatch had happened at all.
        if (lateBy > const Duration(minutes: 5).inMilliseconds) {
          FirebaseDatabase.instance.ref('hero_pings/$uid/$requestId').remove();
        }
        return;
      }

      // ✅ FIX: Ignore pings that existed before this listener attached
      // Prevents stale pings from re-triggering on app resume.
      // TASK 2 (Aug 8 2026): was `- 10000`, matching the old sequential
      // model's 15s-per-hero ping window. Ride pings now use the same
      // 90s broadcast window as service-request pings (see
      // _startBroadcastPinging in ride_search_screen.dart) — this MUST
      // track that window, or every fresh broadcast ping's derived
      // "created at" lands far in the future and this dedup check goes
      // silent, letting an already-seen/dismissed ping re-trigger the
      // Accept dialog on every app resume for the rest of the window.
      // FIX (Aug 11 2026): prefer the EXPLICIT server-stamped createdAt
      // that ride_search_screen now writes. The old derivation
      // (pingExpiresAt - 90000) silently assumed the customer's broadcast
      // window constant and inherited the customer's clock — if either
      // moved, every fresh ping's derived age was wrong and real pings
      // were dropped as "pre-existing". The subtraction is kept only as a
      // fallback for pings written by an older customer build still in
      // the wild during rollout.
      final pingCreatedAt =
          (pingData['createdAt'] as num?)?.toInt() ?? (pingExpiresAt - 90000);
      if (pingCreatedAt < listenerAttachedAt - 18000) {
        _pingLog(
          'DROPPED $requestId as pre-existing '
          '(created=$pingCreatedAt, listenerAttached=$listenerAttachedAt)',
        );
        return;
      }

      _pingLog('ACCEPTED for display: $requestId');

      // ── CATEGORY FILTER: Only show rides matching hero's vehicle ──
      final requestedCategory = (pingData['category'] as String?)?.trim().toLowerCase() ??
          (pingData['vehicleType'] as String?)?.trim().toLowerCase() ?? '';
      // Ensure _vehicleType is converted to lowercase for comparison
      final heroCategory = _vehicleType.trim().toLowerCase();

      // ── SMART MODE: parcel requests are accepted by BOTH parcel and bike
      // heroes — must mirror the customer-side filter in ride_search_screen,
      // otherwise bike heroes get pinged for parcels but silently drop them.
      bool categoryMatch = true;
      if (requestedCategory.isNotEmpty && heroCategory.isNotEmpty) {
        if (requestedCategory == 'parcel') {
          categoryMatch = heroCategory == 'parcel' || heroCategory == 'bike';
        } else {
          categoryMatch = heroCategory == requestedCategory;
        }
      }
      if (!categoryMatch) {
        _pingLog(
          'DROPPED $requestId on category: requested=$requestedCategory '
          'hero=$heroCategory',
        );
        // Silently remove the ping to clean up RTDB node
        FirebaseDatabase.instance.ref('hero_pings/${_user!.uid}/$requestId').remove();
        return;
      }

      // Notification: only if global listener hasn't fired yet
      if (!kIsWeb && !await HeroRideNotificationService.shouldProcessRideNotification(requestId)) {
        debugPrint('[HeroHomeScreen] Notification already fired by global listener. Showing dialog only.');
      } else if (!kIsWeb) {
        try {
          HeroRideNotificationService.showRideAssigned(
            rideId: requestId,
            data: Map<String, dynamic>.from(pingData),
          );
        } catch (e) {
          debugPrint('[HeroHomeScreen] Ringtone error: $e');
        }
      }

      _showRideRequestDialog(
          requestId, Map<String, dynamic>.from(pingData),);
    }, onError: (Object e) {
      debugPrint('[HeroHomeScreen] RTDB ping listener error: $e');
    },);
  }

  // ================================================================
  // BROADCAST ORDER SYSTEM — parallel ping listener + accept flow.
  // Extends (does not duplicate) the ride-ping pattern above: same
  // expiry check, same "ignore pre-existing pings on resume" guard,
  // same atomic-accept-wins-the-race semantics, same notification
  // mechanism. Only the RTDB path and dialog UI differ.
  // ================================================================
  void _listenForServicePings() {
    final uid = _user?.uid;
    if (uid == null) return;
    // Already subscribed — see the matching guard in _listenForHeroPings().
    // _stopServicePingListening() nulls the field on every cancel path.
    if (_servicePingSub != null) {
      return;
    }
    debugPrint('🔥 [DEBUG] Hero is LISTENING to EXACT PATH: hero_service_pings/$uid');

    final listenerAttachedAt = DateTime.now().toUtc().millisecondsSinceEpoch;

    _servicePingSub = FirebaseDatabase.instance
        .ref('hero_service_pings/$uid')
        .onChildAdded
        .listen((event) async {
      // FIX (same root cause as _listenForHeroPings): removed `!_isOnline`.
      if (!mounted ||
          _activeRideId.isNotEmpty ||
          _hasActiveServiceRequest) {
        return;
      }
      if (_isShowingServiceDialog) return;

      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key ?? '';
      if (pingData == null || requestId.isEmpty) return;

      final pingExpiresAt = (pingData['pingExpiresAt'] as num?)?.toInt();
      if (pingExpiresAt == null) return;
      if (DateTime.now().toUtc().millisecondsSinceEpoch > pingExpiresAt) {
        FirebaseDatabase.instance.ref('hero_service_pings/$uid/$requestId').remove();
        return;
      }

      // Ignore pings that existed before this listener attached (same
      // guard as ride pings — prevents stale-ping re-trigger on resume).
      // 90s broadcast window, same reasoning as the 10s ride window.
      final pingCreatedAt = pingExpiresAt - kServiceRequestPingExpirySeconds * 1000;
      if (pingCreatedAt < listenerAttachedAt - 90000) {
        debugPrint('[HeroHomeScreen] Ignoring pre-existing service ping: $requestId');
        return;
      }

      if (_shownServicePingIds.contains(requestId)) return;
      _shownServicePingIds.add(requestId);

      debugPrint('[HeroHomeScreen] RTDB service ping received: $requestId');

      if (!kIsWeb && !await HeroRideNotificationService.shouldProcessRideNotification(requestId)) {
        debugPrint('[HeroHomeScreen] Notification already fired by global listener. Showing dialog only.');
      } else if (!kIsWeb) {
        try {
          HeroRideNotificationService.showRideAssigned(
            rideId: requestId,
            data: Map<String, dynamic>.from(pingData),
            pushType: 'service_request',
            title: 'New Service Request',
            channelDescription:
                'Lock-screen ride and service-request alerts with ACCEPT action and ringtone.',
            ticker: 'New service request assigned',
            emptyBodyFallback: 'Tap ACCEPT to open the request.',
          );
        } catch (e) {
          debugPrint('[HeroHomeScreen] Ringtone error: $e');
        }
      }

      _showServiceRequestDialog(requestId, Map<String, dynamic>.from(pingData));
    }, onError: (Object e) {
      debugPrint('[HeroHomeScreen] RTDB service ping listener error: $e');
    },);
  }

  void _showServiceRequestDialog(String requestId, Map<String, dynamic> data) {
    if (!mounted) return;
    if (_isShowingServiceDialog) {
      debugPrint('[HeroHomeScreen] Service dialog already open — skipping $requestId');
      return;
    }
    setState(() => _isShowingServiceDialog = true);

    if (kIsWeb) {
      try {
        HeroWebAudioService().playAlert();
      } catch (e) {
        debugPrint('[HeroHomeScreen] Web audio error: $e');
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isShowingServiceDialog) return;
      _doShowServiceDialog(requestId, data);
    });
  }

  void _doShowServiceDialog(String requestId, Map<String, dynamic> data, [int attempt = 0]) {
    final dialogContext = navigatorKey.currentContext;
    if (dialogContext == null) {
      if (attempt >= 2) {
        debugPrint('[HeroHomeScreen] dialogContext null after 2 retries — giving up');
        if (mounted) setState(() => _isShowingServiceDialog = false);
        return;
      }
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || !_isShowingServiceDialog) return;
        _doShowServiceDialog(requestId, data, attempt + 1);
      });
      return;
    }

    final requestType = data['requestType'] as String? ?? 'hero_booking';
    final customerName = data['customerName'] as String? ?? 'Customer';
    final details = data['details'] as Map? ?? {};
    final summary = _serviceRequestSummary(requestType, details);

    // Hygiene: clear any earlier quiet background notification for this
    // request now that the in-app dialog is taking over. This dialog
    // does not play a looping ringtone (unlike the ride-taxi dialog), so
    // there is no fresh-sound-overlap concern here — just tidying up
    // the now-redundant lock-screen notification.
    if (!kIsWeb) {
      unawaited(HeroRideNotificationService.cancelRideNotification(requestId));
    }

    // Safety net for the simultaneous-broadcast design: since every
    // online hero gets pinged at once (unlike ride-hailing's sequential
    // pinging, where only one candidate is ever shown a dialog at a
    // time), this hero's dialog can already be open when someone else
    // wins the race. acceptServiceRequest() now sweep-clears every
    // other hero's ping node on accept (see service_request_service.dart),
    // which stops the dialog from showing again on a fresh app open —
    // but if it's already showing right now, only a live listener on
    // the doc itself can catch it and auto-dismiss.
    StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? staleSub;
    staleSub = FirebaseFirestore.instance
        .collection('service_requests')
        .doc(requestId)
        .snapshots()
        .listen((doc) {
      // FIX (CTO mandate — Final UI Migration Sweep): only the status
      // is needed here, so build a model just to read `.status` rather
      // than indexing the raw map directly.
      final liveStatus = doc.exists && doc.data() != null
          ? ServiceRequestModel.fromFirestore(doc.data()!, doc.id).status
          : null;
      if (liveStatus != null && liveStatus != 'pending') {
        staleSub?.cancel();
        final popContext = navigatorKey.currentContext;
        if (popContext != null && Navigator.of(popContext).canPop()) {
          Navigator.of(popContext).pop();
          ScaffoldMessenger.of(popContext).showSnackBar(
            const SnackBar(
                content: Text('This request was already taken by another hero.'),
                backgroundColor: Colors.grey,),
          );
        }
      }
    });

    // FIX (same root cause/fix as the taxi ping dialog's
    // _showDialogNow — see that method's comment for the full
    // explanation): an uncaught showDialog() error here would leave
    // `_isShowingServiceDialog` stuck true forever, silently blocking
    // every future hero-booking/food/grocery popup for the rest of the
    // session. Wrapped defensively for the same reason, applying the
    // "unified fix across all 4 request types" requirement.
    try {
    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_serviceRequestTitle(requestType), style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        content: SingleChildScrollView(
          child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: $customerName', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(summary, style: const TextStyle(color: Colors.black54)),
            // UNIFIED POPUP SPEC (Aug 8 2026): grocery/food/hero-booking
            // requests DO capture pinned pickup/delivery locations at
            // creation time (grocery_order_screen.dart's
            // LocationCaptureField, custom_food_order_screen.dart's shop +
            // delivery picker, hero_booking_screen.dart's from/to picker)
            // and that data already reaches this dialog intact inside
            // `details` (service_request_service.dart's
            // createServiceRequest/_broadcastToEligibleHeroes writes the
            // whole `details` map verbatim into the RTDB ping). The gap
            // was purely that this dialog never rendered it — fixed by
            // _serviceRequestLocationLines() below, styled to match the
            // taxi dialog's pink PICKUP/DROP rows for a consistent look.
            for (final line in _serviceRequestLocationLines(requestType, details)) ...[
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F8),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: const Color(0x33FF4FA3)),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(line.emoji, style: const TextStyle(fontSize: 16)),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(line.label,
                              style: const TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w700,
                                  color: Color(0xFF8F5A78),),),
                          Text(line.value,
                              style: const TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.black87,),),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
            // NEW (per Nizam's "screenshot the DMart cart, hero fulfills
            // manually" workflow — details['listImageUrls']/'listImageUrl'
            // written by grocery_order_screen.dart): the hero must
            // actually SEE these screenshots to fulfill the order, not
            // just a "photo attached" text badge, which is all this
            // dialog showed before.
            if (requestType == 'grocery_order' && orderPhotoUrlsFromDetails(details).isNotEmpty) ...[
              const SizedBox(height: 10),
              OrderPhotoGallery(
                imageUrls: orderPhotoUrlsFromDetails(details),
                label: 'Cart screenshots',
              ),
            ],
          ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () {
              // MINIMIZE (Aug 8 2026 unified-popup spec): same contract
              // as the taxi dialog's MINIMIZE — just closes the dialog,
              // does NOT remove the hero_service_pings node, so the
              // request stays valid for the rest of its broadcast window.
              Navigator.pop(ctx);
            },
            child: const Text('Minimize', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _rejectServiceRequest(requestId);
            },
            child: const Text('Reject', style: TextStyle(color: Color(0xFFFF5252))),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4FA3)),
            onPressed: () {
              Navigator.pop(ctx);
              _acceptServiceRequest(requestId, data);
            },
            child: const Text('ACCEPT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((_) {
      staleSub?.cancel();
      if (mounted) setState(() => _isShowingServiceDialog = false);
    }).catchError((Object e, StackTrace st) {
      debugPrint('[HeroHomeScreen] Service dialog showDialog() future error: $e\n$st');
      staleSub?.cancel();
      if (mounted) setState(() => _isShowingServiceDialog = false);
    });
    } catch (e, st) {
      debugPrint('[HeroHomeScreen] Service dialog showDialog() threw synchronously: $e\n$st');
      staleSub?.cancel();
      if (mounted) setState(() => _isShowingServiceDialog = false);
      return;
    }
    // Belt-and-braces safety net — same rationale as the taxi dialog's.
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isShowingServiceDialog) {
        debugPrint('[HeroHomeScreen] Safety-net: force-clearing stuck _isShowingServiceDialog');
        setState(() => _isShowingServiceDialog = false);
      }
    });
  }

  String _serviceRequestTitle(String requestType) {
    switch (requestType) {
      case 'hero_booking':
        return 'New Hero Booking';
      case 'custom_order':
        return 'New Custom Order';
      case 'custom_food_order':
        return 'New Food Order';
      case 'grocery_order':
        return 'New Grocery Order';
      default:
        return 'New Service Request';
    }
  }

  // details['items'] may now be the structured List<Map>
  // {sNo, name, qty} shape (see quick_order_line_items.dart) instead of
  // a plain String — returns null when details['items'] isn't a List,
  // so callers fall back to whatever legacy string field they used.
  String? _itemsListSummary(Map details) {
    final raw = details['items'];
    if (raw is! List) return null;
    return raw
        .whereType<Map>()
        .map((it) => '${it['qty'] ?? ''} ${it['name'] ?? ''}'.trim())
        .where((s) => s.isNotEmpty)
        .join(', ');
  }

  String _serviceRequestSummary(String requestType, Map details) {
    switch (requestType) {
      case 'hero_booking':
        final itemsSummary = _itemsListSummary(details);
        if (itemsSummary != null && itemsSummary.isNotEmpty) return itemsSummary;
        return (details['taskDescription'] as String?) ?? '';
      case 'custom_order':
        return (details['orderDescription'] as String?) ?? '';
      case 'custom_food_order':
        final itemsSummary = _itemsListSummary(details);
        final items = (itemsSummary != null && itemsSummary.isNotEmpty)
            ? itemsSummary
            : (details['items'] as String?) ?? '';
        final pref = (details['restaurantOrPreference'] as String?) ?? '';
        return [if (pref.isNotEmpty) 'From: $pref', if (items.isNotEmpty) items].join('\n');
      case 'grocery_order':
        final itemsSummary = _itemsListSummary(details);
        final text = (itemsSummary != null && itemsSummary.isNotEmpty)
            ? itemsSummary
            : (details['listText'] as String?) ?? '';
        final hasImage = (details['listImageUrl'] as String?)?.isNotEmpty ?? false;
        return [if (text.isNotEmpty) text, if (hasImage) '📷 Photo list attached'].join('\n');
      default:
        return '';
    }
  }

  // UNIFIED POPUP SPEC (Aug 8 2026): exact field names captured per
  // request type, confirmed against source:
  //   grocery_order        (grocery_order_screen.dart)     -> details['deliveryAddress'] (single point, no separate pickup)
  //   custom_food_order    (custom_food_order_screen.dart) -> details['shopAddress'] (from/pickup), details['deliveryAddress'] (to/drop)
  //   hero_booking         (hero_booking_screen.dart)      -> details['fromLocation'] (from, only if pickup-delivery task), details['location'] (to/task address)
  // Returns [] (renders nothing) when a type has no location concept
  // (e.g. plain 'custom_order') or the customer's picker didn't
  // capture anything for this particular request.
  List<_ServiceRequestLocationLine> _serviceRequestLocationLines(
      String requestType, Map details,) {
    String? s(String key) {
      final v = details[key];
      if (v is String && v.trim().isNotEmpty) return v.trim();
      return null;
    }

    switch (requestType) {
      case 'grocery_order':
        final delivery = s('deliveryAddress');
        return [
          if (delivery != null)
            _ServiceRequestLocationLine('🔴', 'DELIVER TO', delivery),
        ];
      case 'custom_food_order':
        final shop = s('shopAddress');
        final delivery = s('deliveryAddress');
        return [
          if (shop != null) _ServiceRequestLocationLine('🟢', 'PICKUP (SHOP)', shop),
          if (delivery != null) _ServiceRequestLocationLine('🔴', 'DELIVER TO', delivery),
        ];
      case 'hero_booking':
        final from = s('fromLocation');
        final to = s('location');
        return [
          if (from != null) _ServiceRequestLocationLine('🟢', 'FROM', from),
          if (to != null) _ServiceRequestLocationLine('🔴', 'TO', to),
        ];
      default:
        return const [];
    }
  }

  Future<void> _acceptServiceRequest(String requestId, Map<String, dynamic> data) async {
    if (_user == null) return;

    // Same clock-skew-tolerant expiry buffer as _acceptRide — reject
    // client-side before even attempting the transaction if this ping
    // has visibly expired (e.g. dialog was left open across a
    // background/foreground cycle).
    final pingExpiresAt = (data['pingExpiresAt'] as num?)?.toInt() ?? 0;
    final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    if (pingExpiresAt > 0 && nowMs > pingExpiresAt + 5000) {
      debugPrint('[HeroHomeScreen] Service ping expired, cannot accept');
      return;
    }

    try {
      final resolvedHeroPhone = await _resolveHeroPhone(_user!);
      final won = await ServiceRequestService().acceptServiceRequest(
        requestId: requestId,
        heroId: _user!.uid,
        heroName: _captainName,
        heroPhone: resolvedHeroPhone,
      );
      if (!won) {
        debugPrint('[HeroHomeScreen] Service request already accepted by another hero — aborting');
        return;
      }
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Request accepted! Check "My Requests" to update status.'), backgroundColor: Color(0xFF00C853)),
        );
      }
    } catch (e) {
      debugPrint('[HeroHomeScreen] acceptServiceRequest error: $e');
    }
  }

  Future<void> _rejectServiceRequest(String requestId) async {
    final uid = _user?.uid;
    if (uid == null) return;
    try {
      await FirebaseDatabase.instance.ref('hero_service_pings/$uid/$requestId').remove();
    } catch (e) {
      debugPrint('[HeroHomeScreen] rejectServiceRequest error: $e');
    }
  }

  Widget _buildPingDialog(String requestId, Map<String, dynamic> pingData) {
    return _PingCountdownDialog(
      requestId: requestId.toString(),
      pingData: Map<String, dynamic>.from(pingData),
      // dlgCtx is the dialog's own BuildContext (see onPressed in
      // _PingCountdownDialogState) — passed through so _acceptRide can
      // pop the dialog's own route itself, right before pushing
      // CaptainRideScreen, instead of racing a delayed pop from the
      // dialog side against _acceptRide's internal Navigator.push.
      onAccept: (id, data, dlgCtx) =>
          _acceptRide(id, data, dialogContext: dlgCtx),
      onReject: _rejectRide,
    );
  }

  void _showRideRequestDialog(String rideId, Map<String, dynamic> rideData) {
    if (!mounted) return;
    if (_isShowingRideDialog) {
      debugPrint('[HeroHomeScreen] Dialog already open — skipping $rideId');
      return;
    }
    setState(() => _isShowingRideDialog = true);

    // Web: play audio alert via platform audio service
    if (kIsWeb) {
      try {
        HeroWebAudioService().playAlert();
      } catch (e) {
        debugPrint('[HeroHomeScreen] Web audio error: $e');
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isShowingRideDialog) return;
      _doShowDialog(rideId, rideData);
    });
  }

  void _doShowDialog(String rideId, Map<String, dynamic> rideData) {
    var dialogContext = navigatorKey.currentContext;

    if (dialogContext == null) {
      debugPrint('[HeroHomeScreen] dialogContext null — retrying in 500ms');
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!mounted || !_isShowingRideDialog) return;
        dialogContext = navigatorKey.currentContext;
        if (dialogContext != null) {
          _showDialogNow(dialogContext!, rideId, rideData);
        } else {
          Future.delayed(const Duration(milliseconds: 500), () {
            if (!mounted || !_isShowingRideDialog) return;
            final thirdCtx = navigatorKey.currentContext;
            if (thirdCtx != null) {
              _showDialogNow(thirdCtx, rideId, rideData);
            } else {
              debugPrint('[HeroHomeScreen] dialogContext null after 2 retries — giving up');
              setState(() => _isShowingRideDialog = false);
            }
          });
        }
      });
      return;
    }

    _showDialogNow(dialogContext, rideId, rideData);
  }

  void _showDialogNow(BuildContext dialogContext, String rideId, Map<String, dynamic> rideData) {
    // Force-stop any sound left over from the earlier quiet background
    // notification, and cancel that notification, right as the in-app
    // dialog is about to take over — regardless of whether this dialog
    // was triggered by a notification tap or a listener re-fire. This
    // guarantees the fresh looping ringtone below never overlaps with a
    // residual background sound.
    if (!kIsWeb) {
      unawaited(HeroRideNotificationService.stopWakeAlertRingtone());
      unawaited(HeroRideNotificationService.cancelRideNotification(rideId));
    }

    // FIX (per Nizam's request): if another hero wins this ride while
    // THIS hero already has the accept dialog open, the ping-sweep in
    // _acceptRide() (which clears other heroes' hero_pings nodes) can't
    // help — the dialog is already showing, it's not waiting on that
    // node anymore. Watch the request's own status directly so an
    // already-open dialog auto-closes the moment someone else wins,
    // instead of only failing silently if this hero taps Accept a
    // beat too late.
    final uidForWatch = _user?.uid;
    StreamSubscription<DatabaseEvent>? takenSub;
    if (uidForWatch != null) {
      takenSub = FirebaseDatabase.instance
          .ref('active_ride_requests/$rideId/status')
          .onValue
          .listen((event) {
        final status = event.snapshot.value as String?;
        if ((status == 'accepted' || status == 'cancelled' || status == 'timeout') &&
            _isShowingRideDialog) {
          debugPrint('[HeroHomeScreen] Ride $rideId taken/closed elsewhere ($status) — auto-dismissing open dialog');
          if (Navigator.of(dialogContext).canPop()) {
            Navigator.of(dialogContext).pop();
          }
          if (mounted) {
            ScaffoldMessenger.of(dialogContext).showSnackBar(
              const SnackBar(content: Text('This ride was already accepted by another hero.')),
            );
          }
        }
      });
    }

    // FIX (root cause of "Hero PWA popup never visible, for ANY
    // future ping, not just this one"): showDialog() here was not
    // wrapped in try/catch. If it throws synchronously — which on Web
    // can happen if navigatorKey.currentContext resolves to a context
    // whose Overlay/Navigator ancestor is momentarily in an
    // inconsistent state (route transition mid-flight, hot-reload-like
    // rebuild triggered by the video-first boot swap, etc. — timing
    // windows that are far more common on a browser tab's event loop
    // than on native) — the exception used to propagate uncaught, the
    // `.then()` below never got attached (since showDialog() never
    // returned a Future to attach it to), and `_isShowingRideDialog`
    // stayed `true` FOREVER. Every _listenForHeroPings() callback after
    // that point silently no-ops on its `if (_isShowingRideDialog)
    // return;` guard — meaning ONE failed dialog-open, ever, in a
    // session permanently blocks every future ride/service popup for
    // that hero until they refresh the tab. This exactly matches "no
    // popup at all, even foreground, even repeated tests" — the first
    // failure poisons the rest of the session.
    //
    // Fix: catch it, log the real error (visible in the browser
    // console via debugPrint/print on web) so the exact cause is
    // diagnosable next time, and unconditionally reset the flag so the
    // NEXT ping still gets a fresh attempt instead of being silently
    // eaten forever.
    try {
      showDialog<void>(
        context: dialogContext,
        barrierDismissible: false,
        barrierColor: Colors.black.withValues(alpha: 0.78),
        builder: (context) {
          return _buildPingDialog(rideId.toString(), rideData);
        },
      ).then((_) {
        unawaited(takenSub?.cancel());
        if (!kIsWeb) {
          unawaited(HeroRideNotificationService.stopWakeAlertRingtone());
        }
        if (mounted) setState(() => _isShowingRideDialog = false);
      }).catchError((Object e, StackTrace st) {
        debugPrint('[HeroHomeScreen] showDialog() future error: $e\n$st');
        unawaited(takenSub?.cancel());
        if (mounted) setState(() => _isShowingRideDialog = false);
      });
    } catch (e, st) {
      debugPrint('[HeroHomeScreen] showDialog() threw synchronously: $e\n$st');
      unawaited(takenSub?.cancel());
      if (mounted) setState(() => _isShowingRideDialog = false);
      return;
    }
    // Belt-and-braces safety net: even if the above somehow still
    // leaves the flag stuck (an error path we haven't anticipated),
    // force it back to false after the ping's own 15s countdown would
    // have expired anyway, so the hero is never permanently stuck
    // silently missing every future ride for the rest of the session.
    Future.delayed(const Duration(seconds: 20), () {
      if (mounted && _isShowingRideDialog) {
        debugPrint('[HeroHomeScreen] Safety-net: force-clearing stuck _isShowingRideDialog');
        setState(() => _isShowingRideDialog = false);
      }
    });
    // Start looping ringtone AFTER dialog is visible (not before).
    // This ensures the alert plays continuously while the hero sees the dialog,
    // and stops only when they accept/reject/timeout.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_isShowingRideDialog) return;
      _playIncomingRideAlertSafe(looping: true);
    });
  }

  Future<void> _rejectRide(String requestId) async {
    final uid = _user?.uid;
    if (uid == null) return;
    debugPrint('[HeroHomeScreen] Rejecting ride: $requestId');
    try {
      await FirebaseDatabase.instance
          .ref('hero_pings/$uid/$requestId')
          .remove();
      await FirebaseFirestore.instance
          .collection('heroes')
          .doc(uid)
          .set({'isAvailable': true}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[HeroHomeScreen] Reject ride error: $e');
    }
  }

  // Accept a ride from Firestore — DISPATCH v2.0
  Future<void> _acceptRide(
      String requestId, Map<String, dynamic> pingData,
      {BuildContext? dialogContext,}) async {
    if (_user == null) return;
    setState(() => _accepting = true);
    debugPrint('[HeroHomeScreen] Accepting ride via RTDB: $requestId');

    // ── TEMPORARY INSTRUMENTATION — REMOVE AFTER MEASUREMENT ──────
    // Measures each awaited step between the ACCEPT tap and
    // Navigator.push, to identify what causes the reported ~7s delay.
    // Search the console for [ACCEPT-TIMING] and report all lines.
    final acceptStopwatch = Stopwatch()..start();
    int lastElapsedMs = 0;
    void mark(String step) {
      final total = acceptStopwatch.elapsedMilliseconds;
      final delta = total - lastElapsedMs;
      lastElapsedMs = total;
      debugPrint('[ACCEPT-TIMING] $step: +${delta}ms (total ${total}ms)');
    }
    // ── END TEMPORARY INSTRUMENTATION ─────────────────────────────

    try {
      final uid = _user!.uid;
      final resolvedHeroPhone = await _resolveHeroPhone(_user!);
      mark('STEP-0 resolveHeroPhone');

      // ── P0 FIX 1: Clock-skew-tolerant expiry check (5s buffer) ──
      final pingExpiresAt = (pingData['pingExpiresAt'] as num?)?.toInt() ?? 0;
      final nowMs = DateTime.now().toUtc().millisecondsSinceEpoch;
      
      // 🚀 FIX: Only enforce expiry check if pingExpiresAt was explicitly provided (>0)
      if (pingExpiresAt > 0 && nowMs > pingExpiresAt + 5000) {
        // 5-second tolerance for device clock skew
        debugPrint('[HeroHomeScreen] Ping expired, cannot accept');
        if (mounted) setState(() => _accepting = false);
        return;
      }

      // ── P0 FIX 1: Atomic RTDB transaction — only ONE hero can win ──
      final requestRef =
          FirebaseDatabase.instance.ref('active_ride_requests/$requestId');
      final transResult = await requestRef.runTransaction((currentData) {
        if (currentData == null) {
          // Optimistic local cache run. NEVER abort here!
          // Return intended data so the server compares it and returns the real data.
          return rtdb.Transaction.success({
            'status': 'accepted',
            'acceptedHeroId': uid,
            'acceptedHeroName': _captainName,
            'acceptedHeroPhone': resolvedHeroPhone,
            'acceptedHeroVehicle': _normalizeHeroVehicleType(_vehicleType),
          });
        }

        final data = Map<String, dynamic>.from(currentData as Map);
        final status = data['status'] as String? ?? '';

        debugPrint('🔍 [DEBUG] Current DB Status is: "$status"');

        // BLACKLIST APPROACH: Only abort if explicitly taken by another hero or cancelled
        if (status == 'accepted' || status == 'cancelled' || status == 'timeout') {
          debugPrint('❌ [TRANSACTION ABORTED] Ride already taken/dead. Status: $status');
          return rtdb.Transaction.abort();
        }

        // Otherwise, we win the ride!
        data['status'] = 'accepted';
        data['acceptedHeroId'] = uid;
        data['acceptedHeroName'] = _captainName;
        data['acceptedHeroPhone'] = resolvedHeroPhone;
        data['acceptedHeroVehicle'] = _normalizeHeroVehicleType(_vehicleType);

        return rtdb.Transaction.success(data);
      });
      mark('STEP-1 RTDB runTransaction(active_ride_requests)');

      if (!transResult.committed) {
        // Another hero accepted first — abort silently
        debugPrint('[HeroHomeScreen] Ride already accepted by another hero — aborting');
        await FirebaseDatabase.instance
            .ref('hero_pings/$uid/$requestId')
            .remove();
        if (mounted) setState(() => _accepting = false);
        return;
      }

      // Transaction won — clean up our own ping
      await FirebaseDatabase.instance
          .ref('hero_pings/$uid/$requestId')
          .remove();
      mark('STEP-2 RTDB remove(hero_pings)');

      // BILLING (Aug 17 2026 — Nizam: "summa iruntha bill agakudathu...
      // hero ride and yenna service yeduthu follow pandraro apo mattum").
      // The meter starts HERE — the exact moment this hero won the ride,
      // not when they came online. Waiting for work is free; doing work
      // is metered. Stopped at completion in hero_ride_screen.dart.
      HeroUsageAccumulatorService().startBillableWork();

      // FIX (per Nizam's request, mirrors the equivalent fix already
      // shipped in service_request_service.dart's acceptServiceRequest()):
      // previously only the WINNING hero's own ping node was ever
      // removed. Every OTHER online hero who was also broadcast this
      // requestId kept their `hero_pings/{otherUid}/{requestId}` node —
      // if their Accept dialog was already open, it stayed open showing
      // a ride that was already taken, only erroring out silently if
      // they actually tapped Accept. Sweep-clear every other online
      // hero's ping node for this requestId too, same hero pool the
      // broadcast used. Best-effort: a hero who went offline between
      // broadcast and accept won't be in this snapshot, but their stale
      // ping node self-expires via the client-side pingExpiresAt check
      // in _listenForHeroPings() regardless.
      unawaited(() async {
        try {
          final onlineSnap =
              await FirebaseDatabase.instance.ref('online_heroes').get();
          if (onlineSnap.exists && onlineSnap.value is Map) {
            final heroes = Map<dynamic, dynamic>.from(onlineSnap.value! as Map);
            final sweepFutures = <Future<void>>[];
            for (final otherHeroId in heroes.keys) {
              if (otherHeroId == uid) continue; // already removed above
              sweepFutures.add(
                FirebaseDatabase.instance
                    .ref('hero_pings/$otherHeroId/$requestId')
                    .remove(),
              );
            }
            await Future.wait(sweepFutures);
          }
        } catch (e) {
          debugPrint('[HeroHomeScreen] Ride ping sweep-clear failed: $e');
        }
      }());

      await FirebaseFirestore.instance
          .collection('heroes')
          .doc(uid)
          .update({'isAvailable': false});
      mark('STEP-3 Firestore update(heroes/uid)  <-- prime suspect');

      await FirebaseDatabase.instance
          .ref('online_heroes/$uid')
          .update({'isAvailable': false});
      mark('STEP-4 RTDB update(online_heroes)');

      if (mounted) {
        // Use the Firestore doc ID from the ping (not the RTDB push key).
        // Deliberately NOT falling back to requestId (the RTDB push key)
        // when firestoreDocId is missing — that silent substitution used
        // to feed the wrong ID into CaptainRideScreen's local OTP
        // checksum, producing an OTP that could never match what the
        // customer sees, with no visible error. Fall back to '' instead
        // so CaptainRideScreen can detect and surface this loudly.
        final rawFirestoreDocId = pingData['firestoreDocId'] as String?;
        final firestoreDocId = (rawFirestoreDocId ?? '').trim();
        if (firestoreDocId.isEmpty) {
          debugPrint(
            '⚠️ [RIDE ACCEPTED] Ping for request $requestId is missing '
            'firestoreDocId — cannot safely link this ride to its '
            'Firestore doc (OTP/status updates would break). '
            'rawFirestoreDocId=$rawFirestoreDocId requestId=$requestId',
          );
        }
        final rideModel = RideModel(
          rideId: firestoreDocId,
          customerId: pingData['customerId'] as String? ?? '',
          pickupAddress: pingData['pickupAddress'] as String? ?? '',
          dropAddress: pingData['dropAddress'] as String? ?? '',
          pickupLatitude: (pingData['pickupLat'] as num?)?.toDouble(),
          pickupLongitude: (pingData['pickupLng'] as num?)?.toDouble(),
          dropLatitude: (pingData['dropLat'] as num?)?.toDouble(),
          dropLongitude: (pingData['dropLng'] as num?)?.toDouble(),
          estimatedFare: (pingData['estimatedFare'] as num?)?.toDouble(),
          distanceKm: (pingData['distanceKm'] as num?)?.toDouble(),
          status: 'accepted',
          heroId: uid,
        );
        debugPrint('✅ [RIDE ACCEPTED] firestoreDocId confirmed: $firestoreDocId');
        // Pop the ACCEPT dialog's own route BEFORE pushing the ride
        // screen. Previously the dialog popped itself (via its own
        // ambient `context`) only after awaiting this whole method —
        // but by then this push below had already landed on top of
        // the still-open dialog route, so that later pop removed the
        // freshly-pushed CaptainRideScreen instead of the dialog,
        // leaving the dialog stuck open forever with its spinner
        // running. Popping the dialog's own route here, right before
        // the push, keeps the stack order correct: dialog closes,
        // then the ride screen is pushed on a clean stack.
        // ── DIAGNOSTIC LOGGING (temporary) ──────────────────────
        // Investigating a report where this pop silently doesn't
        // dismiss the dialog. These prints (and the isolated
        // try/catch below) exist only to pinpoint which branch
        // actually runs on the next test — no behavior change other
        // than ensuring a pop-time exception can no longer prevent
        // the push below from running.
        debugPrint(
          '🔍 [DIALOG-POP-CHECK] dialogContext=${dialogContext == null ? 'null' : 'non-null'} '
          'mounted=${dialogContext?.mounted}',
        );
        if (dialogContext != null && dialogContext.mounted) {
          try {
            Navigator.pop(dialogContext);
            debugPrint('🔍 [DIALOG-POP-CHECK] branch=popped (no exception)');
          } catch (e, st) {
            debugPrint('❌ [DIALOG-POP-ERROR] Navigator.pop(dialogContext) threw: $e\n$st');
          }
        } else {
          debugPrint('🔍 [DIALOG-POP-CHECK] branch=skipped (null or unmounted)');
        }
        debugPrint('🔍 [DIALOG-POP-CHECK] about to call Navigator.push for CaptainRideScreen');
        mark('STEP-5 reached Navigator.push (UI transition starts here)');
        Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) =>
                    CaptainRideScreen(ride: rideModel, rideDocId: firestoreDocId),),);
      }
    } catch (e) {
      debugPrint('[HeroHomeScreen] Accept ride error: $e');
      // Previously this error was only logged to debugPrint — the hero
      // got no feedback at all and was left stuck on the radar screen
      // with no indication anything had gone wrong. Surface it so the
      // hero knows to retry.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to accept ride — please try again.'),
            backgroundColor: Color(0xFFE05555),
          ),
        );
      }
    }
    if (mounted) setState(() => _accepting = false);
  }

  // Complete a ride — 0% Commission Promotion: Hero keeps 100% of fare
  /// Best-effort online-period log for the Earnings & Online Time
  /// monitor. Never throws to the caller — a logging failure must
  /// never affect the offline-toggle flow it's fired from.
  Future<void> _logHeroSession({
    required String heroId,
    required DateTime startedAt,
    required double durationMinutes,
  }) async {
    try {
      await FirebaseFirestore.instance.collection('hero_sessions').add({
        'heroId': heroId,
        'startedAt': Timestamp.fromDate(startedAt),
        'endedAt': FieldValue.serverTimestamp(),
        'durationMinutes': durationMinutes,
      });
    } catch (e) {
      debugPrint('[HeroHomeScreen] hero_sessions log write failed (non-fatal): $e');
    }
  }

  Future<void> _completeRide() async {
    if (_activeRideId.isEmpty) {
      return;
    }
    final db = FirebaseFirestore.instance;

    // Read the ride document to get the definitive fare
    late double fare;
    late double actualFare;
    late double tipAmount;
    try {
      final rideSnap = await db.collection('rides').doc(_activeRideId).get();
      if (!rideSnap.exists) {
        debugPrint('[completeRide] Ride doc not found: $_activeRideId');
        return;
      }
      final rideData = rideSnap.data()!;
      // Idempotency guard: skip wallet credit if already settled
      if (rideData['paymentStatus'] == 'settled') {
        debugPrint('[completeRide] Payment already settled — skipping');
        return;
      }
      fare = (rideData['finalFare'] as num?)?.toDouble() ??
          (rideData['actualFare'] as num?)?.toDouble() ??
          (rideData['lockedFare'] as num?)?.toDouble() ??
          (rideData['estimatedFare'] as num?)?.toDouble() ??
          (rideData['fare'] as num?)?.toDouble() ??
          0.0;
      actualFare = (rideData['actualFare'] as num?)?.toDouble() ?? fare;
      tipAmount = (rideData['tipAmount'] as num?)?.toDouble() ?? 0.0;
    } catch (e) {
      debugPrint('[completeRide] Failed to read ride fare: $e');
      return;
    }

    final heroEarning = fare; // 100% to hero — zero commission promotion
    const double adminCommission = 0;

    final batch = db.batch()
      ..update(db.collection('rides').doc(_activeRideId), {
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'paymentStatus': 'pending_collection',
        'heroEarning': heroEarning,
        'adminCommission': adminCommission,
        'isZeroCommission': true,
        'finalFare': fare,
        'actualFare': actualFare,
        'tipAmount': tipAmount,
      });

    // Update Hero wallet with 100% earnings
    if (_user != null) {
      batch.set(
        db.collection('heroes').doc(_user!.uid),
        {
          'totalEarnings': FieldValue.increment(heroEarning),
          'totalRides': FieldValue.increment(1),
          'lastRideCompletedAt': FieldValue.serverTimestamp(),
          'status': 'online',
          'activeRideId': null,
          // FIX (root cause, Aug 11 2026 — "hero completes a ride, next
          // request never reaches them"): _acceptRide() sets isAvailable
          // false in BOTH heroes/{uid} (Firestore) and online_heroes/{uid}
          // (RTDB) at accept time. This Home-screen "Mark Ride Complete"
          // button is a separate completion path from CaptainRideScreen's
          // payment-collection flow (hero_ride_screen.dart), which DOES
          // flip isAvailable back to true — this path never did, on
          // either store. ride_search_screen.dart's broadcast candidate
          // query and service_request_service.dart's dispatch check both
          // filter on this exact flag, so a hero who closes out a ride
          // here was left permanently invisible to every future ping with
          // no reliable self-heal. Restoring it here on the Firestore
          // side; the RTDB side is restored right after batch.commit()
          // below.
          'isAvailable': true,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
    }

    await batch.commit();
    debugPrint(
      'Hero complete: fare=$fare, heroEarning=$heroEarning, '
      'commission=$adminCommission, ride=$_activeRideId',
    );

    // Clean up RTDB live location
    await FirebaseDatabase.instance
        .ref('live_locations/$_activeRideId')
        .remove();

    // FIX (root cause, Aug 11 2026 — see the isAvailable comment on the
    // heroes/{uid} batch write above): online_heroes/{uid} in RTDB is
    // the actual source of truth both dispatch queries filter on, not
    // the Firestore copy. Both must be restored together.
    if (_user != null) {
      await FirebaseDatabase.instance
          .ref('online_heroes/${_user!.uid}')
          .update({'isAvailable': true});
    }

    setState(() {
      _activeRideId = '';
      _isOnRide = false;
    });
    _stopLocationUpdates();
    // Resume global radar + targeted ride listener now that ride is done
    if (_isOnline) {
      _startGlobalLocationTracking();
      _listenForHeroPings();
      _listenForServicePings();
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Ride completed! Collect payment from customer.',
            style: GoogleFonts.notoSansTamil(color: Colors.white),
          ),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      );
    }
  }

  // Call customer
  Future<void> _callCustomer(String phone) async {
    if (phone.isEmpty) {
      return;
    }
    final Uri uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  // ── LOCATION TRACKING ─────────────────────────────────────────
  void _startLocationUpdates(String rideId) {
    _stopLocationUpdates();
    // Pause global radar + Zero-Read fallback during active ride
    _stopGlobalLocationTracking();
    _heroPingSub?.cancel();
    _heroPingSub = null;
    _stopServicePingListening();
    _locationSubscription = LocationService().getLocationStream(
      highAccuracy: true, // active ride — full navigation accuracy
    ).listen(
      (position) {
        _latestPosition = position;
        _animateHeroMarkerTo(position);
        _updateLocationToRTDB(
          rideId,
          position.latitude,
          position.longitude,
          heading: position.heading,
        );
      },
      onError: (Object e) => debugPrint('Location update error: $e'),
    );
    debugPrint('Location tracking STARTED for ride: $rideId');
  }

  // Write GPS to RTDB (throttled to every 3 seconds + 50m gate)
  void _updateLocationToRTDB(
    String rideId,
    double lat,
    double lng, {
    double? heading,
  }) {
    final now = DateTime.now();
    if (_lastGpsUpdate != null &&
        now.difference(_lastGpsUpdate!).inSeconds < 3) {
      return; // Throttle — skip update
    }
    // 50m gate: skip if haven't moved enough since last upload.
    //
    // DELIBERATELY NOT _idleRadarMoveThresholdMeters (500m). This path
    // writes live_locations/{rideId} — the moving hero marker the
    // customer watches during an active ride. At 500m the hero would
    // appear to teleport every ~60-90s instead of tracking smoothly, so
    // this stays tight on purpose. Only the idle "heroes nearby" radar
    // uses the larger threshold.
    if (_lastUploadedPosition != null) {
      final dist = Geolocator.distanceBetween(
        _lastUploadedPosition!.latitude,
        _lastUploadedPosition!.longitude,
        lat,
        lng,
      );
      if (dist < 50) return;
    }
    _lastGpsUpdate = now;
    _lastUploadedPosition = _latestPosition;

    FirebaseDatabase.instance.ref('live_locations/$rideId').set({
      'lat': lat,
      'lng': lng,
      if (_validHeading(heading) != null) 'heading': _validHeading(heading),
      'vehicleType': _normalizeHeroVehicleType(_vehicleType),
      'updatedAt': ServerValue.timestamp,
    });
  }

  void _stopLocationUpdates() {
    _locationSubscription?.cancel();
    _locationSubscription = null;
    debugPrint('Location tracking STOPPED');
  }

  @override
  Widget build(BuildContext context) {
    if (_isBootstrappingHeroData) {
      if (widget.embedded) {
        return DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: <Color>[
                Color(0xFFFFF7FB),
                Color(0xFFFFEEF6),
                Color(0xFFFFFFFF),
              ],
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
            ),
          ),
          child: SafeArea(
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: const HeroPremiumLoader(
                  compact: true,
                  title: 'Preparing Hero Workspace',
                  subtitle:
                      'Loading your status, earnings, and live ride radar',
                  icon: Icons.radar_rounded,
                ),
              ),
            ),
          ),
        );
      }
      return const HeroPremiumLoader(
        title: 'Preparing Hero Workspace',
        subtitle: 'Loading your status, earnings, and live ride radar',
        icon: Icons.radar_rounded,
      );
    }

    final content = DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[
            Color(0xFFFFF7FB),
            Color(0xFFFFEEF6),
            Color(0xFFFFFFFF),
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: Stack(
        children: [
          SafeArea(
            child: Column(
              children: [
                _buildHeader(),
                _buildActiveServiceRequestsBanner(),
                // The unattended-order safety net (Aug 28 2026 — Nizam:
                // "admin mobile attend pannalainalum... hero ku assign
                // panni customer ku message anupuravaraikkum").
                //
                // Sits here, above the ride stream, because a hero with
                // an empty stream is exactly who should see it — and it
                // renders a zero-height box when nothing is stranded,
                // so it costs this screen nothing on a normal day.
                const StrandedOrdersBanner(),
                if (_isOnline) ...[
                  if (_activeRideId.isNotEmpty) ...[
                    _buildActiveRideCard(),
                  ] else
                    Expanded(child: _buildRideStream()),
                ] else
                  Expanded(child: _buildOfflineView()),
              ],
            ),
          ),
          _buildNearbySosOverlay(),
        ],
      ),
    );

    if (widget.embedded) {
      return content;
    }

    return Scaffold(
      backgroundColor: _bg,
      body: content,
    );
  }

  // ── BROADCAST ORDER SYSTEM: minimal status-advance UI ──────────
  // Shows any service_requests currently assigned to this hero
  // (whether the assignment came from broadcast-accept or an admin
  // manual assignment — both write the exact same fields) with a
  // simple 3-button status-advance control.
  Widget _buildActiveServiceRequestsBanner() {
    // Stream is created once in initState (null only when there was no
    // signed-in user at that point) — do NOT inline a .snapshots() call
    // here, that re-attaches the listener on every rebuild.
    final stream = _activeServiceRequestsStream;
    if (stream == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        // FIX (CTO mandate — Final UI Migration Sweep): map to typed
        // models before filtering/rendering — reads below now use
        // `.status`/`.paymentStatus`/`.customerName`/`.requestType`/
        // `.requestId` instead of `doc.data()['key']`/`doc.id`.
        final requests = snapshot.data!.docs
            .map((doc) => ServiceRequestModel.fromFirestore(doc.data(), doc.id))
            .toList();
        // 'completed' docs are included in the query (see
        // _activeServiceRequestsStream) so the cash-payment close-out UI
        // is reachable, but a completed-AND-paid task is fully done and
        // should stop showing here — filtered out client-side to avoid
        // a 3rd inequality-filter composite index just for this.
        final visibleRequests = requests.where((r) {
          final status = r.status.isNotEmpty ? r.status : 'hero_assigned';
          return !(status == 'completed' && r.paymentStatus == 'paid');
        }).toList();
        if (visibleRequests.isEmpty) return const SizedBox.shrink();
        // FIX (per Nizam's request — "hero ku yella process um main
        // page nadakama"): this used to render the FULL interactive
        // _ServiceRequestStatusCard (status stepper, Navigate buttons,
        // advance/complete/payment actions) inline in this scrolling
        // list — cluttered when a hero has more than one active task.
        // Now the home tab only shows a compact summary tile; tapping
        // it opens HeroTaskDetailScreen, a dedicated full-screen page
        // for that one task where all of that same interactive body
        // now lives (unchanged logic, just moved off the main page).
        return Column(
          children: visibleRequests.map((request) {
            final customerName = request.customerName.isNotEmpty ? request.customerName : 'Customer';
            final requestType = request.requestType.isNotEmpty ? request.requestType : 'hero_booking';
            final status = request.status.isNotEmpty ? request.status : 'hero_assigned';
            return Container(
              margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF4FA3).withValues(alpha: 0.2)),
                boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
              ),
              child: Material(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => HeroTaskDetailScreen(requestId: request.requestId)),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(14),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                requestType.replaceAll('_', ' '),
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13),
                              ),
                              Text('For $customerName', style: const TextStyle(color: Colors.black54, fontSize: 11)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(color: const Color(0xFFFF4FA3).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                          child: Text(status.replaceAll('_', ' '), style: const TextStyle(color: Color(0xFFFF4FA3), fontSize: 10, fontWeight: FontWeight.w700)),
                        ),
                        const SizedBox(width: 8),
                        const Icon(Icons.chevron_right_rounded, color: Colors.black38),
                      ],
                    ),
                  ),
                ),
              ),
            );
          }).toList(),
        );
      },
    );
  }

  // ── HEADER ───────────────────────────────────────────────────
  // EMERGENCY RESPONDER SOS DISPATCH (Aug 29 2026 — Nizam's full spec).
  //
  // This whole overlay used to fire for EVERY hero — bike, auto, car,
  // any skill — the instant they were within 2km of any active SOS,
  // with a single "Navigate to Help" button and nothing else. Nizam
  // asked for something more specific: SOS should be the ONE thing that
  // reaches a hero who registered specifically as "Only Emergency
  // Manpower" (they now get NO other job pings at all — see
  // hero_register_screen.dart's isEmergencyOnly), it should reach every
  // one of them within 5km carrying the customer's location and phone
  // number, the responding hero should CALL the customer to check, and
  // if that call goes unanswered every nearby responder should be told
  // to go and check in person.
  //
  // See sos_dispatch_service.dart for the claim/resolve/escalate state
  // machine this UI drives.
  Widget _buildNearbySosOverlay() {
    // Gate #1: only heroes who registered as Only Emergency Manpower see
    // this at all. Every other hero type keeps working exactly as
    // before this change — no SOS overlay, no distraction — which is
    // the literal ask ("vera yentha disturb-um pannathu" for everyone
    // else, not just the emergency responders).
    if (_vehicleType != 'emergency_manpower') {
      return const SizedBox.shrink();
    }

    final heroPosition = _latestPosition;
    if (heroPosition == null) {
      return const SizedBox.shrink();
    }

    // Stream created once in initState — see _activeSosAlertsStream.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _activeSosAlertsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final myUid = _user?.uid;
        double? nearestMeters;
        Map<String, dynamic>? nearestData;
        String? nearestDocId;
        final cutoff = DateTime.now().subtract(_sosAlertMaxAge);

        for (final doc in snapshot.data!.docs) {
          if (_dismissedSosIds.contains(doc.id)) {
            continue;
          }

          final data = doc.data();

          // Gate #2: which lifecycle states this hero may see this
          // alert in. 'active' and 'escalated' are broadcast to every
          // responder — that is the whole "yella emergency responder-
          // kkum poganum" ask. 'resolved' is done, nobody needs it.
          // 'claimed' is the tricky one: once ANOTHER hero has it,
          // showing this same full-screen takeover to every other
          // responder would have two (or ten) heroes converging on one
          // customer while everyone assumes someone else has it
          // covered — exactly the diffusion-of-responsibility failure a
          // single-claim model exists to prevent. A hero only keeps
          // seeing 'claimed' if the claim is THEIRS, so they can reach
          // the call/resolve/escalate step below.
          final status = data['status'] as String? ?? SosAlertStatus.active;
          final claimedBy = data['claimedByHeroId'] as String?;
          final visibleToMe = status == SosAlertStatus.active ||
              status == SosAlertStatus.escalated ||
              (status == SosAlertStatus.claimed && claimedBy == myUid);
          if (!visibleToMe) continue;

          // 15-minute auto-expiry safety net (creation writes use either
          // 'timestamp' or 'createdAt' depending on which screen sent the
          // alert — read side handles both without touching the writers).
          // A still-pending serverTimestamp() resolves to null locally
          // until the server acks it — treat null as "just created" so a
          // brand-new alert never briefly vanishes from this check.
          final rawTs = data['timestamp'] ?? data['createdAt'];
          if (rawTs is Timestamp && rawTs.toDate().isBefore(cutoff)) {
            continue;
          }

          final location = data['location'];
          if (location is! GeoPoint) {
            continue;
          }
          final distanceMeters = Geolocator.distanceBetween(
            heroPosition.latitude,
            heroPosition.longitude,
            location.latitude,
            location.longitude,
          );
          // 5km, per Nizam's explicit "nearbyla 5kms kulla irukka yella
          // emergency responder kum poganum" — widened from the old 2km
          // that applied when every hero type shared this one overlay.
          if (distanceMeters <= 5000 &&
              (nearestMeters == null || distanceMeters < nearestMeters)) {
            nearestMeters = distanceMeters;
            nearestData = data;
            nearestDocId = doc.id;
          }
        }

        if (nearestMeters == null || nearestData == null || nearestDocId == null) {
          return const SizedBox.shrink();
        }

        final distanceKm = nearestMeters / 1000;
        final alertId = nearestDocId;
        final location = nearestData['location'] as GeoPoint;
        final status =
            nearestData['status'] as String? ?? SosAlertStatus.active;
        final isMine =
            status == SosAlertStatus.claimed &&
                nearestData['claimedByHeroId'] == myUid;
        final customerName = (nearestData['userName'] as String?)?.trim();
        final customerPhone = (nearestData['userPhone'] as String?)?.trim();
        final escalatedCount = (nearestData['escalatedCount'] as num?)?.toInt() ?? 0;

        return Positioned.fill(
          child: ColoredBox(
            color: const Color(0xE6B00020),
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(22),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.warning_amber_rounded,
                      color: Colors.white,
                      size: 92,
                    ),
                    const SizedBox(height: 18),
                    Text(
                      isMine
                          ? "YOU'RE RESPONDING"
                          : 'EMERGENCY SOS NEARBY!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.4,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      isMine
                          ? 'Call ${customerName?.isNotEmpty == true ? customerName : 'the customer'} to check what happened.'
                          : (escalatedCount > 0
                              ? "Previous responder couldn't reach them — please help."
                              : 'A user needs immediate help!'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 21,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 18,
                        vertical: 12,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                      ),
                      child: Text(
                        'Distance: ${distanceKm.toStringAsFixed(2)} km',
                        style: GoogleFonts.outfit(
                          color: const Color(0xFFB00020),
                          fontSize: 18,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    if (isMine) ...[
                      // CLAIMED BY ME — call the customer, then say what
                      // happened. No dismiss button here: this hero
                      // committed to this one by claiming it, so the
                      // only ways out are actually resolving it.
                      FilledButton.icon(
                        onPressed: (customerPhone == null || customerPhone.isEmpty)
                            ? null
                            : () => unawaited(_callSosCustomer(customerPhone)),
                        icon: const Icon(Icons.call_rounded),
                        label: Text(
                          customerPhone == null || customerPhone.isEmpty
                              ? 'No phone number on file'
                              : 'Call $customerPhone',
                        ),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFB00020),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                          textStyle: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      OutlinedButton.icon(
                        onPressed: () =>
                            unawaited(_navigateToSosLocation(location)),
                        icon: const Icon(Icons.navigation_rounded, color: Colors.white),
                        label: const Text('Navigate there'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: Colors.white,
                          side: const BorderSide(color: Colors.white),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      Text(
                        'After you speak to them:',
                        style: GoogleFonts.outfit(
                          color: Colors.white70,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: _sosActionBusy
                                  ? null
                                  : () => unawaited(_resolveSosNoProblem(alertId)),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.white,
                                side: const BorderSide(color: Colors.white54),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                "No problem —\nclose",
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: FilledButton(
                              onPressed: _sosActionBusy
                                  ? null
                                  : () => unawaited(_escalateSosNoAnswer(alertId)),
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: const Color(0xFFB00020),
                                padding: const EdgeInsets.symmetric(vertical: 12),
                              ),
                              child: Text(
                                'No answer —\nnotify others',
                                textAlign: TextAlign.center,
                                style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ] else ...[
                      // NOT YET CLAIMED — first responder wins, exactly
                      // like accepting a ride. Every other Emergency
                      // Responder within 5km sees this identical banner
                      // at the same time.
                      FilledButton.icon(
                        onPressed: _sosActionBusy
                            ? null
                            : () => unawaited(_claimSos(alertId)),
                        icon: const Icon(Icons.pan_tool_alt_rounded),
                        label: const Text("I'm Responding"),
                        style: FilledButton.styleFrom(
                          backgroundColor: Colors.white,
                          foregroundColor: const Color(0xFFB00020),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 28,
                            vertical: 16,
                          ),
                          textStyle: GoogleFonts.outfit(
                            fontSize: 17,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () {
                          if (mounted) {
                            setState(() => _dismissedSosIds.add(alertId));
                          }
                        },
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 10,
                          ),
                        ),
                        child: Text(
                          "OK, I've seen it",
                          style: GoogleFonts.outfit(
                            fontSize: 15,
                            fontWeight: FontWeight.w800,
                            decoration: TextDecoration.underline,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 4),
                    Text(
                      'Stay safe. Call police/100 if required.',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                        color: Colors.white70,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Guards the claim/resolve/escalate buttons against a double-tap
  /// firing two transactions/writes for the same alert.
  bool _sosActionBusy = false;

  Future<void> _claimSos(String alertId) async {
    final user = _user;
    if (user == null || _sosActionBusy) return;
    setState(() => _sosActionBusy = true);
    try {
      final phone = await _resolveHeroPhone(user);
      final won = await SosDispatchService.instance.claim(
        alertId: alertId,
        heroId: user.uid,
        heroName: _captainName,
        heroPhone: phone,
      );
      if (!won && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Another responder already has this one.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sosActionBusy = false);
    }
  }

  Future<void> _callSosCustomer(String phone) async {
    final uri = Uri.parse('tel:$phone');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('[HeroHome] SOS call launch failed: $phone');
    }
  }

  Future<void> _resolveSosNoProblem(String alertId) async {
    final user = _user;
    if (user == null || _sosActionBusy) return;
    setState(() => _sosActionBusy = true);
    try {
      await SosDispatchService.instance.resolveNoProblem(
        alertId: alertId,
        heroId: user.uid,
      );
    } finally {
      if (mounted) setState(() => _sosActionBusy = false);
    }
  }

  Future<void> _escalateSosNoAnswer(String alertId) async {
    if (_sosActionBusy) return;
    setState(() => _sosActionBusy = true);
    try {
      await SosDispatchService.instance.escalateNoAnswer(alertId: alertId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Notified every nearby Emergency Responder.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sosActionBusy = false);
    }
  }

  Widget _buildHeroSosButton() {
    // Always visible when online - positioned at bottom-right above bottom nav
    return Positioned(
      left: 16,
      right: 16,
      bottom: 100, // above bottom navigation bar (typical 80-90px)
      child: GestureDetector(
        onTap: _sendingSos ? null : _handleHeroSosTap,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF5252), Color(0xFFB00020)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(28),
            boxShadow: const [
              BoxShadow(
                color: Color(0x4AFF5252),
                blurRadius: 20,
                offset: Offset(0, 10),
              ),
            ],
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: BorderRadius.circular(28),
              onTap: _sendingSos ? null : _handleHeroSosTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(
                      Icons.emergency_rounded,
                      color: Colors.white,
                      size: 28,
                    ),
                    const SizedBox(width: 10),
                    Text(
                      _sendingSos ? 'Sending SOS...' : 'SOS EMERGENCY',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    if (_sendingSos) ...[
                      const SizedBox(width: 12),
                      const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _navigateToSosLocation(GeoPoint location) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=${location.latitude},${location.longitude}&travelmode=driving',
    );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      debugPrint('Unable to launch SOS navigation: $uri');
    }
  }

  // ── HERO SOS EMERGENCY ─────────────────────────────────────────
  Future<void> _handleHeroSosTap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login before sending SOS.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
      return;
    }

    final now = DateTime.now();
    _sosTapTimes
      ..removeWhere((tap) => now.difference(tap).inSeconds > 3)
      ..add(now);

    if (_sosTapTimes.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tap SOS ${3 - _sosTapTimes.length} more time(s) within 3 seconds.',
            ),
            backgroundColor: const Color(0xFFB00020),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    _sosTapTimes.clear();
    final shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SosCountdownDialog(),
    );
    if (shouldSend != true || !mounted) {
      return;
    }
    await _sendHeroSosAlert(user);
  }

  Future<void> _sendHeroSosAlert(User user) async {
    if (_sendingSos) {
      return;
    }
    setState(() => _sendingSos = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable GPS to send an SOS alert.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required for SOS.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      final resolvedSosHeroPhone = await _resolveHeroPhone(user);
      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Hero',
        'userPhone': resolvedSosHeroPhone,
        'userType': 'hero',
        'location': GeoPoint(position.latitude, position.longitude),
        'status': 'active',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'SOS sent! NJ Tech team and nearby customers have been alerted.',),
          backgroundColor: Color(0xFF00C853),
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      debugPrint('[HeroHome] SOS failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS could not be sent. Please try again.'),
          backgroundColor: Color(0xFFFF5252),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sendingSos = false);
      }
    }
  }

  List<MapCircle> _serviceZoneCircles() {
    if (!_showServiceZone) {
      return const [];
    }
    return [
      const MapCircle(
        center: _erodeBusStandCenter,
        radiusMeters: _serviceZoneRadiusMeters,
        fillColor: Colors.transparent, // FIX T1: transparent fill
        borderColor: _njPink, // FIX T1: pink stroke
        borderStrokeWidth: 3,
      ),
    ];
  }

  void _toggleServiceZone() {
    setState(() => _showServiceZone = !_showServiceZone);
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Current Service Limit: 5km from Erode Bus Stand'),
        backgroundColor: _red,
        behavior: SnackBarBehavior.floating,
        duration: Duration(seconds: 3),
      ),
    );
  }

  Widget _buildServiceZoneMapCard() {
    return Container(
      height: 190,
      margin: const EdgeInsets.fromLTRB(16, 6, 16, 10),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x18FF4FA3),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          children: [
            // FIX T1: Direct OSM map — bypasses OLA API error entirely
            FlutterMap(
              options: const MapOptions(
                initialCenter: _erodeBusStandCenter,
                initialZoom: 12.2,
                minZoom: 10,
                maxZoom: 18,
                interactionOptions:
                    InteractionOptions(flags: InteractiveFlag.none),
              ),
              children: [
                TileLayer(
                  urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                  userAgentPackageName: 'com.allin1.superapp',
                  // Offline-first tiles (Aug 28 2026) — see
                  // cached_tile_provider.dart.
                  tileProvider: CachedTileProvider(),
                ),
                const CircleLayer(
                  circles: [
                    CircleMarker(
                      point: _erodeBusStandCenter,
                      radius: _serviceZoneRadiusMeters,
                      useRadiusInMeter: true,
                      // T1: NJ Pink fill + border — was transparent/orange
                      color: Color(0x18FF4FA3), // 10% pink fill
                      borderColor: _njPink, // solid pink border
                      borderStrokeWidth: 3.5,
                    ),
                  ],
                ),
                const MarkerLayer(
                  markers: [
                    Marker(
                      point: _erodeBusStandCenter,
                      width: 36,
                      height: 36,
                      child: Icon(
                        Icons.directions_bus_filled_rounded,
                        color: _red,
                        size: 26,
                      ),
                    ),
                  ],
                ),
              ],
            ),
            Positioned(
              left: 10,
              top: 10,
              child: Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _red.withValues(alpha: 0.38)),
                ),
                child: Text(
                  '5km Service Zone',
                  style: GoogleFonts.outfit(
                    color: _red,
                    fontSize: 11,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildPromoPrivilegeBanner() {
    final pulse = _pulseAnim;
    final banner = Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[_njPink, _njPinkSoft, _njWhite],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _njPink.withValues(alpha: 0.38),
            blurRadius: 24,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.94),
              borderRadius: BorderRadius.circular(18),
            ),
            child: const Icon(
              Icons.speaker_phone_rounded,
              color: _njPink,
              size: 30,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎁 Claim Paytm Soundbox!',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF5A1036),
                    fontSize: 19,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'No Commission Fees Offer Applied!',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF7A214B),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: const Color(0x33FFFFFF),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: const Color(0x66FFFFFF)),
            ),
            child: Text(
              'ACTIVE',
              style: GoogleFonts.outfit(
                color: const Color(0xFF7A214B),
                fontSize: 11,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );

    if (pulse == null) {
      return banner;
    }

    return ScaleTransition(
      scale: pulse,
      child: banner,
    );
  }

  Widget _buildHeader() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _surface.withValues(alpha: 0.94),
        border: const Border(bottom: BorderSide(color: _border)),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x12FF4FA3),
            blurRadius: 22,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 42,
            height: 42,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: <Color>[_njPink, _njPinkSoft],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(14),
              boxShadow: const <BoxShadow>[
                BoxShadow(
                  color: Color(0x33FF4FA3),
                  blurRadius: 16,
                  offset: Offset(0, 6),
                ),
              ],
            ),
            child: Center(
              child: Text(
                _avatarLetter,
                style: const TextStyle(
                  fontSize: 18,
                  color: Colors.white,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // NEW (Aug 12 2026 — Nizam's "personal touch" request):
                  // time-of-day greeting, same idea as the Customer app's
                  // dashboard header and the Claude desktop app itself
                  // ("Good afternoon, Nizam"). See LocalizationService
                  // .greetingKeyForNow().
                  '${context.watch<LocalizationService>().t(LocalizationService.greetingKeyForNow())}, $_captainName',
                  // 15 → 14 → 12.5 (Aug 19 2026). Even at 14 the line
                  // was still being clipped to "Good afternoon, …" on a
                  // normal phone, so the hero never saw their own name.
                  // The greeting prefix is what eats the width, and it
                  // is not worth losing the name over — 12.5 fits both.
                  style: const TextStyle(
                    fontSize: 12.5,
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // ── DAILY QUOTE (HERO POOL) ─────────────────────
                // Separate pool from the customer's, on purpose — see
                // daily_quote_service.dart. A hero opens this screen
                // about to go out and earn, so the lines are about
                // earnings, safety and customer trust, never abstract
                // self-belief.
                //
                // Rotates morning / afternoon / night on the same
                // deterministic schedule as the customer app, so the
                // two never drift apart.
                Text(
                  DailyQuoteService.instance.forHero(
                    context.watch<LocalizationService>().languageCode,
                  ),
                  // Location line is 10, so this is 11 — one point up.
                  style: const TextStyle(
                    fontSize: 11,
                    color: _njPink,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    height: 1.2,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),

                const Text(
                  'hero allin1 · Erode',
                  style: TextStyle(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
          // Update Bell with Badge
          Stack(
            children: [
              IconButton(
                icon: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                    boxShadow: const <BoxShadow>[
                      BoxShadow(
                        color: Color(0x14FF4FA3),
                        blurRadius: 12,
                        offset: Offset(0, 5),
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.notifications_active_rounded,
                    color: _njPink,
                    size: 20,
                  ),
                ),
                onPressed: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => const NotificationsScreen(),
                  ),
                ),
              ),
              Positioned(
                right: 12,
                top: 12,
                child: Container(
                  width: 8,
                  height: 8,
                  decoration: const BoxDecoration(
                    color: _red,
                    shape: BoxShape.circle,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 4),
          // Online toggle
          GestureDetector(
            onTap: () {
              setState(() => _isOnline = !_isOnline);
              _syncOnlineStatus(_isOnline);
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: _isOnline
                    ? const Color(0x1400C853)
                    : const Color(0x14FF5252),
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: _isOnline
                      ? const Color(0x4000C853)
                      : const Color(0x40FF5252),
                ),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x12FF4FA3),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                      color: _isOnline ? _green : _red,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 6),
                  Text(
                    _isOnline ? 'ONLINE' : 'OFFLINE',
                    style: TextStyle(
                      fontSize: 10,
                      color: _isOnline ? _green : _red,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 0.8,
                    ),
                  ),
                ],
              ),
            ),
          ),
          // LOGOUT MOVED TO SETTINGS (Aug 19 2026, Nizam).
          //
          // It sat here beside the notification bell and the
          // ONLINE/OFFLINE pill, competing for the same row as the
          // hero's name — which is why the name was being truncated to
          // "Good afternoon, …". Logout is a once-a-day action; the
          // name and the online state are looked at constantly. The
          // rare action gives up the prime space.
          //
          // Also removes a real hazard: a red power button one thumb
          // slip away from the bell, on a screen used while working.
          // It now lives behind the drawer's Settings, where a
          // deliberate trip is required — see _showLogoutDialog, still
          // wired, just reached from there.
        ],
      ),
    );
  }

  // _showLogoutDialog() REMOVED (Aug 19 2026). Its only caller was
  // the header power button, which moved to Settings — and the
  // HeroSideDrawer already had its own _logoutAndGoOffline() doing
  // exactly the same two steps (go offline, then sign out). Leaving
  // this here would have been an unused_element warning guarding a
  // second, drifting copy of the logout sequence.

  // ── STATS ROW ─────────────────────────────────────────────────
  Widget _buildStatsRow() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x22FFBB00)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: Row(
                  children: [
                    _stat('🏍️', 'Rides', '$_totalRides', _purple),
                    _vline(),
                    _stat('💰', 'Earned', '₹${_totalEarnings.toInt()}', _gold),
                    _vline(),
                    _stat('⭐', 'Rating', '4.8', _green),
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: _border, height: 24),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Service Quality',
                style: TextStyle(fontSize: 11, color: _muted),
              ),
              _buildCommissionBadge(),
            ],
          ),
        ],
      ),
    );
  }

  Widget _stat(String e, String l, String v, Color c) => Expanded(
        child: Column(
          children: [
            Text(e, style: const TextStyle(fontSize: 18)),
            const SizedBox(height: 4),
            Text(
              v,
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.w800,
                color: c,
              ),
            ),
            Text(l, style: const TextStyle(fontSize: 9, color: _muted)),
          ],
        ),
      );

  Widget _vline() => Container(
        width: 1,
        height: 36,
        color: _border,
        margin: const EdgeInsets.symmetric(horizontal: 8),
      );

  // ── PENDING RIDES STREAM ──────────────────────────────────────
  Widget _buildRideStream() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Row(
            children: [
              const Text('🔔', style: TextStyle(fontSize: 13)),
              const SizedBox(width: 6),
              const Text(
                'PENDING RIDES — LIVE',
                style: TextStyle(
                  fontSize: 10,
                  color: _muted,
                  letterSpacing: 1.2,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _toggleServiceZone,
                style: TextButton.styleFrom(
                  foregroundColor: _red,
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  visualDensity: VisualDensity.compact,
                ),
                icon: const Icon(Icons.radar_rounded, size: 15),
                label: const Text(
                  'Zone',
                  style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900),
                ),
              ),
              const SizedBox(width: 6),
              const _LivePulseDot(),
              const SizedBox(width: 5),
              const Text(
                'LIVE',
                style: TextStyle(
                  fontSize: 9,
                  color: _green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
        if (_showServiceZone) _buildServiceZoneMapCard(),
        Expanded(
          child: _isOnRide
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('🚦', style: TextStyle(fontSize: 48)),
                        const SizedBox(height: 12),
                        Text(
                          'On-Ride Mode',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            color: _text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Complete current ride — then new rides varum!',
                          style: GoogleFonts.notoSansTamil(
                            fontSize: 12,
                            color: _muted,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ],
                    ),
                  ),
                )
              : StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  // FIX-B1: Use the cached stream object. Passing the same
                  // Stream instance on every build() means StreamBuilder never
                  // resets to ConnectionState.waiting on GPS-tick setStates.
                  stream: const Stream<QuerySnapshot<Map<String, dynamic>>>.empty(),
                  builder: (context, snap) {
                    // T2 FIX: The full-screen HeroPremiumLoader was blocking
                    // the ride list even when rides were available.
                    // Rule: NEVER show a blocking loader once the stream is
                    // attached — use a compact top-bar spinner instead.

                    if (snap.hasError) {
                      // Auto-retry: reinitialise stream after 4s
                      Future.delayed(const Duration(seconds: 4), () {
                        if (!mounted || !_isOnline) return;
                        debugPrint(
                            '[HeroHomeScreen] Stream error — auto-retrying: ${snap.error}',);
                        setState(() {});
                      });
                      return const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.wifi_off_rounded,
                                color: _red, size: 32,),
                            SizedBox(height: 8),
                            Text(
                              'Connection error — retrying...',
                              style: TextStyle(color: _red, fontSize: 12),
                            ),
                          ],
                        ),
                      );
                    }
                    final List<QueryDocumentSnapshot<Map<String, dynamic>>>
                        docs = (snap.data?.docs ??
                                <QueryDocumentSnapshot<Map<String, dynamic>>>[])
                            .where((doc) => _isFreshSearchingRide(doc.data()))
                            .toList();
                    // T2+T4: Empty state — show animated radar sweep so the
                    // map stays visible and hero sees active scanning, not a
                    // static card. isFirstLoad shows a compact top spinner.
                    if (docs.isEmpty) {
                      return Column(
                        children: [
                          Expanded(
                            child: Stack(
                              fit: StackFit.expand,
                              children: [
                                // Base layer: Map showing the service zone
                                FlutterMap(
                                  options: const MapOptions(
                                    initialCenter: _erodeBusStandCenter,
                                    minZoom: 10,
                                    maxZoom: 18,
                                    interactionOptions: InteractionOptions(
                                        flags: InteractiveFlag.none,),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.allin1.superapp',
                                      // Offline-first tiles (Aug 28 2026)
                                      // — see cached_tile_provider.dart.
                                      tileProvider: CachedTileProvider(),
                                    ),
                                    const CircleLayer(circles: [
                                      CircleMarker(
                                        point: _erodeBusStandCenter,
                                        radius: 5000,
                                        useRadiusInMeter: true,
                                        color: Color(0x08FF4FA3),
                                        borderColor: Color(0x40FF4FA3),
                                        borderStrokeWidth: 2,
                                      ),
                                    ],),
                                  ],
                                ),
                                // Radar animation calibrated to match service zone circle
                                Positioned.fill(
                                  child: LayoutBuilder(
                                    builder: (_, constraints) {
                                      final rawDiameter = constraints.maxWidth < constraints.maxHeight
                                          ? constraints.maxWidth
                                          : constraints.maxHeight;
                                      // FIX (Aug 31 2026 — "hero main
                                      // screen blank, radar animation
                                      // doesn't show"). Same root cause
                                      // already found and fixed on the
                                      // registration form's category
                                      // grid: a LayoutBuilder nested this
                                      // deep (Positioned.fill inside a
                                      // Stack inside a StreamBuilder) can
                                      // report a transient zero (or
                                      // NaN/negative) constraint before
                                      // its ancestors have finished
                                      // sizing. _RadarPainter builds a
                                      // SweepGradient shader sized off
                                      // this exact diameter — CanvasKit
                                      // throws "Null check operator used
                                      // on a null value" out of its own
                                      // gradient-shader code for a
                                      // degenerate (zero-area) rect, on
                                      // every repaint attempt, which is
                                      // what turns one bad frame into a
                                      // permanently blank, unresponsive
                                      // screen rather than a one-frame
                                      // glitch. A floor identical in
                                      // spirit to the one on the
                                      // registration screen closes it.
                                      final diameter =
                                          rawDiameter < 40.0 ? 40.0 : rawDiameter;
                                      return Center(
                                        child: SizedBox(
                                          width: diameter,
                                          height: diameter,
                                          child: _HeroRadarVisual(size: diameter),
                                        ),
                                      );
                                    },
                                  ),
                                ),
                              ],
                            ),
                          ),
                          // Text below the map area
                          Padding(
                            padding: const EdgeInsets.fromLTRB(24, 16, 24, 8),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  'All-in-1 Lens Active',
                                  style: GoogleFonts.outfit(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w800,
                                    color: const Color(0xFF4A1736),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  'Scanning your zone for premium rides...',
                                  style: GoogleFonts.outfit(
                                    fontSize: 11,
                                    color: const Color(0xFF94627F),
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        ],
                      );
                    }
                    return ListView.builder(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      itemCount: docs.length,
                      itemBuilder: (context, i) {
                        final doc = docs[i];
                        final data = doc.data();
                        return _PendingRideCard(
                          rideId: doc.id,
                          data: data,
                          accepting: _accepting,
                          onAccept: () => _acceptRide(doc.id, data),
                          onCall: () => _callCustomer(
                            data['customerPhone'] as String? ?? '',
                          ),
                        );
                      },
                    );
                  },
                ),
        ),
      ],
    );
  }

  // ── ACTIVE RIDE CARD ──────────────────────────────────────────
  Widget _buildActiveRideCard() {
    if (_activeRideId.isEmpty) {
      return const SizedBox.shrink();
    }

    // StreamBuilder to listen to payment status changes
    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .doc(_activeRideId)
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const SizedBox.shrink();
        }

        final rideDoc = snapshot.data!;
        final rideData = rideDoc.data() as Map<String, dynamic>? ?? {};
        final rideStatus = rideData['status'] as String? ?? '';
        final rideActivityAt = _rideActivityAt(rideData);
        final isRecentRide = rideActivityAt != null &&
            rideActivityAt.isAfter(_staleRideCutoff());

        if (!_restorableRideStatuses.contains(rideStatus) || !isRecentRide) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted && _activeRideId == rideDoc.id) {
              setState(() {
                _activeRideId = '';
                _isOnRide = false;
              });
            }
          });
          return const SizedBox.shrink();
        }

        final paymentStatus = rideData['paymentStatus'] as String? ?? '';

        // Check if payment is completed - show notification (once per ride)
        if ((paymentStatus == 'completed' ||
                paymentStatus == 'paid' ||
                paymentStatus == 'paid_by_wallet' ||
                paymentStatus == 'paid_offline_p2p' ||
                paymentStatus == 'settled' ||
                paymentStatus == 'confirmed') &&
            !_paymentAlertShown) {
          _paymentAlertShown = true;

          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              // Show hero notification banner
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  duration: Duration(seconds: 6),
                  backgroundColor: Color(0xFF00C853),
                  content: Row(
                    children: [
                      Icon(Icons.payments, color: Colors.white),
                      SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              '💚 Payment Received!',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            Text(
                              'Customer payment confirmed ✅',
                              style: TextStyle(
                                color: Colors.white70,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              );
            }
          });
        }

        final int fare = (rideData['fare'] as num?)?.toInt() ?? 0;
        final String pickup = rideData['pickup'] as String? ?? '';
        final String drop = rideData['drop'] as String? ?? '';
        final String phone = rideData['customerPhone'] as String? ?? '';
        final String cname = rideData['customerName'] as String? ?? 'Customer';

        // Customer coordinates — written by booking screen
        final double? pickupLat = (rideData['pickupLat'] as num?)?.toDouble();
        final double? pickupLng = (rideData['pickupLng'] as num?)?.toDouble();
        final double? dropLat = (rideData['dropLat'] as num?)?.toDouble();
        final double? dropLng = (rideData['dropLng'] as num?)?.toDouble();

        // Build map markers
        final List<MapMarker> markers = [];
        if (pickupLat != null && pickupLng != null) {
          markers.add(
            MapMarker(
              point: LatLng(pickupLat, pickupLng),
              label: 'Pickup',
              icon: Icons.person_pin_circle_rounded,
            ),
          );
        }
        if (dropLat != null && dropLng != null) {
          markers.add(
            MapMarker(
              point: LatLng(dropLat, dropLng),
              label: 'Drop',
              icon: Icons.flag_rounded,
              color: const Color(0xFF00C853),
            ),
          );
        }
        final heroPoint = _displayHeroLocation;
        if (heroPoint != null) {
          markers.add(
            MapMarker(
              point: heroPoint,
              label: 'Hero',
              assetPath: _assetForHeroVehicleType(_vehicleType),
              bearingDegrees: _displayHeroBearingDegrees,
              size: 45,
            ),
          );
        }

        return Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                // Status banner
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: const Color(0x1A00C853),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x3300C853)),
                  ),
                  child: Column(
                    children: [
                      const Text('🚀', style: TextStyle(fontSize: 32)),
                      const SizedBox(height: 8),
                      Text(
                        'Ride Accepted!',
                        style: GoogleFonts.notoSansTamil(
                          fontSize: 18,
                          fontWeight: FontWeight.w800,
                          color: _green,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Go pick up $cname',
                        style: GoogleFonts.notoSansTamil(
                          fontSize: 12,
                          color: _muted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ── LIVE MAP — Customer pickup + drop ──────────
                if (markers.isNotEmpty)
                  Container(
                    height: 200,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: _border),
                    ),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: Stack(
                        children: [
                          Allin1MapWidget(
                            key: ValueKey(_mapRefreshGen),
                            center: LatLng(
                              pickupLat ?? 11.3410,
                              pickupLng ?? 77.7172,
                            ),
                            markers: markers,
                            circles: _serviceZoneCircles(),
                            routes: (pickupLat != null && dropLat != null)
                                ? [
                                    MapRoute(
                                      points: [
                                        LatLng(pickupLat, pickupLng!),
                                        LatLng(dropLat, dropLng!),
                                      ],
                                    ),
                                  ]
                                : [],
                          ),
                          Positioned(
                            top: 8,
                            left: 8,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xCC0A0A12),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _border),
                              ),
                              child: const Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.navigation,
                                    size: 10,
                                    color: Color(0xFF00C853),
                                  ),
                                  SizedBox(width: 4),
                                  Text(
                                    'Customer Location',
                                    style: TextStyle(
                                      fontSize: 9,
                                      color: Color(0xFFEEEEF5),
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          Positioned(
                            top: 8,
                            right: 8,
                            child: FilledButton.icon(
                              onPressed: _toggleServiceZone,
                              style: FilledButton.styleFrom(
                                backgroundColor: Colors.white,
                                foregroundColor: _red,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 10,
                                  vertical: 8,
                                ),
                                visualDensity: VisualDensity.compact,
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(999),
                                ),
                              ),
                              icon: const Icon(Icons.radar_rounded, size: 14),
                              label: const Text(
                                'Zone',
                                style: TextStyle(
                                  fontSize: 10,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // Route card
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    children: [
                      _rRow('🔴', 'Pickup', pickup),
                      const SizedBox(height: 12),
                      _rRow('🟢', 'Drop', drop),
                      const Divider(color: Color(0x1AFFFFFF), height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Collect from Customer:',
                            style: TextStyle(fontSize: 12, color: _muted),
                          ),
                          Text(
                            '₹$fare',
                            style: const TextStyle(
                              fontSize: 22,
                              color: _gold,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),

                // Call customer
                if (phone.isNotEmpty)
                  GestureDetector(
                    onTap: () => _callCustomer(phone),
                    child: Container(
                      width: double.infinity,
                      height: 50,
                      decoration: BoxDecoration(
                        color: const Color(0x1A00C853),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: const Color(0x3300C853)),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.phone, size: 18, color: _green),
                          SizedBox(width: 8),
                          Text(
                            'Call Customer',
                            style: TextStyle(
                              fontSize: 14,
                              color: _green,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                const SizedBox(height: 10),

                // Complete ride
                GestureDetector(
                  onTap: _completeRide,
                  child: Container(
                    width: double.infinity,
                    height: 56,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [_green, Color(0xFF009624)],
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: _green.withValues(alpha: 0.4),
                          blurRadius: 16,
                          offset: const Offset(0, 6),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const Icon(
                          Icons.check_circle_outline,
                          size: 20,
                          color: Colors.white,
                        ),
                        const SizedBox(width: 8),
                        Text(
                          'Mark Ride Complete ✅',
                          style: GoogleFonts.notoSansTamil(
                            fontSize: 15,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _rRow(String dot, String lbl, String txt) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dot, style: const TextStyle(fontSize: 12)),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  lbl,
                  style: const TextStyle(
                    fontSize: 9,
                    color: _muted,
                    letterSpacing: 0.8,
                  ),
                ),
                Text(
                  txt,
                  style: const TextStyle(
                    fontSize: 13,
                    color: _text,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      );

  // ── OFFLINE VIEW ──────────────────────────────────────────────
  // ── Commission Waiver Banner Widget ──────────────────────────
  Widget _buildCommissionBanner() {
    // Show only on first login AND waiver not completed
    if (!_firstLoginToday || _waiverCompleted || _waiverShown) {
      return const SizedBox.shrink();
    }
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1A1500), Color(0xFF0F1A00)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFFBB00).withValues(alpha: 0.5),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFFBB00).withValues(alpha: 0.15),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 46,
            height: 46,
            decoration: BoxDecoration(
              color: const Color(0xFFFFBB00).withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(13),
              border: Border.all(
                color: const Color(0xFFFFBB00).withValues(alpha: 0.3),
              ),
            ),
            child: const Center(
              child: Text('🎯', style: TextStyle(fontSize: 22)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      '🎁 Rewards & Offers',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        color: const Color(0xFFFFBB00),
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 5,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5252).withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(5),
                      ),
                      child: const Text(
                        'TODAY ONLY',
                        style: TextStyle(
                          fontSize: 7,
                          color: Color(0xFFFF5252),
                          fontWeight: FontWeight.w900,
                          letterSpacing: 0.5,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  'Complete offers & tasks to earn rewards!',
                  style: GoogleFonts.notoSansTamil(
                    fontSize: 10,
                    color: const Color(0xFF7777A0),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: _launchCommissionWaiverTask,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFBB00),
                borderRadius: BorderRadius.circular(11),
              ),
              child: const Text(
                'View →',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.black,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Hero Coins Tile ──────────────────────────────────────────
  Widget _buildHeroCoinsTile() {
    final double rupeesValue = _heroCoins / 100.0; // 100 coins = Rs.1
    return GestureDetector(
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Hero Coins coming soon! Abhi $_heroCoins coins = Rs.${rupeesValue.toStringAsFixed(2)}',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: const Color(0xFF6C63FF),
            behavior: SnackBarBehavior.floating,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
            ),
          ),
        );
      },
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
        decoration: BoxDecoration(
          color: const Color(0xFF10102A),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: const Color(0xFF6C63FF).withValues(alpha: 0.3),
          ),
        ),
        child: Row(
          children: [
            const Text('🪙', style: TextStyle(fontSize: 20)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Hero Coins: $_heroCoins',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFFEEEEF5),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  Text(
                    'Zero commission launch active. Earn coins while you wait!',
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 10,
                      color: const Color(0xFF7777A0),
                    ),
                  ),
                ],
              ),
            ),
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  '= Rs.${rupeesValue.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Text(
                  'Earn more →',
                  style: TextStyle(fontSize: 9, color: Color(0xFF7777A0)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ── Commission Rate Badge ──────────────────────────────────
  Widget _buildCommissionBadge() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: _commissionRate < 0.10
              ? const Color(0xFF00C853).withValues(alpha: 0.12)
              : const Color(0xFF1A1A2A),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: _commissionRate < 0.10
                ? const Color(0xFF00C853).withValues(alpha: 0.4)
                : const Color(0x1AFFFFFF),
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              _commissionRate < 0.10
                  ? Icons.trending_down_rounded
                  : Icons.percent_rounded,
              size: 12,
              color: _commissionRate < 0.10
                  ? const Color(0xFF00C853)
                  : const Color(0xFF7777A0),
            ),
            const SizedBox(width: 4),
            Text(
              '${(_commissionRate * 100).toInt()}% Fee',
              style: TextStyle(
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: _commissionRate < 0.10
                    ? const Color(0xFF00C853)
                    : const Color(0xFF7777A0),
              ),
            ),
          ],
        ),
      );

  Widget _buildOfflineView() {
    // NEW (Aug 13 2026): the பொருளாதாரப் புரட்சி banner is placed on the
    // OFFLINE view deliberately. The online view is a fixed-height
    // Column whose ride stream takes Expanded — dropping a banner in
    // there would squeeze the thing a working hero actually needs. The
    // offline state is exactly when a hero is idle and has time to
    // read it, so it lands where it can be absorbed rather than where
    // it competes with live ride cards. Wrapped in a scroll view since
    // the extra content can exceed a short screen.
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _buildUpdateBanner(),
            const EconomicVisionBanner(
              horizontalPadding: 0,
              compact: true,
              heroApp: true,
            ),
            const SizedBox(height: 28),
            // TECHNICAL OFFLINE INDICATOR (Aug 19 2026, Nizam —
            // replaces a 😴 sleeping-face emoji).
            //
            // The emoji read as "you are lazy", which is the wrong
            // thing to say to someone who has just finished a shift or
            // is waiting to start one. A signal-off icon states the
            // same fact — not receiving rides — as a system status
            // rather than a comment on the hero.
            Container(
              width: 92,
              height: 92,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _muted.withValues(alpha: 0.10),
                border: Border.all(color: _muted.withValues(alpha: 0.28), width: 2),
              ),
              child: Icon(
                Icons.wifi_tethering_off_rounded,
                size: 44,
                color: _muted,
              ),
            ),
            const SizedBox(height: 20),
            Text(
              "You're Offline",
              style: GoogleFonts.outfit(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Go Online to start accepting rides!',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: _muted,
              ),
            ),
            const SizedBox(height: 28),
            GestureDetector(
              onTap: () {
                setState(() => _isOnline = true);
                _syncOnlineStatus(true);
              },
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_green, Color(0xFF009624)],
                  ),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: _green.withValues(alpha: 0.4),
                      blurRadius: 16,
                      offset: const Offset(0, 6),
                    ),
                  ],
                ),
                child: Text(
                  'Go Online 🟢',
                  style: GoogleFonts.notoSansTamil(
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// HERO TASK DETAIL SCREEN (per Nizam's request): "hero ku yella
// process um main page nadakama, task start pannunathum oru page la
// task open agi athu mudiravarayum antha page la irukamari
// panirlam" — the full accept→start→navigate→complete→payment flow
// used to live inline inside a card in the scrolling home-tab list,
// crowded next to every other active task. Now the home list only
// shows a compact summary tile (see _buildActiveServiceRequestsBanner
// below); tapping it pushes this dedicated full-screen page, and the
// hero stays on it — doing every step of THIS task, including the
// Navigate buttons — until the task is fully closed out. Reuses
// _ServiceRequestStatusCard's entire interactive body unchanged (same
// file, so its privacy is not an issue) rather than duplicating any of
// that logic — this is purely a full-screen presentation wrapper with
// its own live doc listener so it keeps working even after the home
// list's own stream re-queries.
class HeroTaskDetailScreen extends StatelessWidget {
  final String requestId;
  const HeroTaskDetailScreen({required this.requestId, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBFE),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFFBFE),
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: const Text('Task', style: TextStyle(color: Colors.black87, fontWeight: FontWeight.w800)),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance.collection('service_requests').doc(requestId).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFFF4FA3)));
          }
          final doc = snapshot.data!;
          if (!doc.exists) {
            // Task was deleted (hero's own "Delete Task" action, or
            // admin cancellation) — nothing left to show, step back to
            // the home list automatically instead of leaving the hero
            // stuck staring at a gone task.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
            return const SizedBox.shrink();
          }
          // FIX (CTO mandate — Final UI Migration Sweep): one typed
          // model built here instead of a raw `data` map — every field
          // handed to _ServiceRequestStatusCard below now comes from
          // `request.*` (including estimatedAmount/finalAmount, which
          // the model already centralizes the root-vs-details lookup
          // for, eliminating the manual `(data['estimatedAmount'] as
          // num?)` casts that used to live here).
          final request = ServiceRequestModel.fromFirestore(doc.data()!, doc.id);
          final status = request.status.isNotEmpty ? request.status : 'hero_assigned';
          final paymentStatus = request.paymentStatus;
          // Fully closed out — same terminal condition the home list
          // uses to stop showing a task. Auto-return the hero to the
          // main list right when the task finishes, per "athu
          // mudiravarayum antha page la irukanum" (stay only until it's
          // done).
          if (status == 'completed' && paymentStatus == 'paid') {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (Navigator.of(context).canPop()) Navigator.of(context).pop();
            });
          }
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: _ServiceRequestStatusCard(
              requestId: request.requestId,
              requestType: request.requestType.isNotEmpty ? request.requestType : 'hero_booking',
              status: status,
              customerName: request.customerName.isNotEmpty ? request.customerName : 'Customer',
              estimatedAmount: request.estimatedAmount?.toDouble(),
              finalAmount: request.finalAmount?.toDouble(),
              paymentStatus: paymentStatus,
              estimateApprovedByCustomer: request.estimateApprovedByCustomer,
              // NEW (per Nizam's request — Negotiate flow): read
              // straight off the raw doc root, same pattern already used
              // for customerRating elsewhere — not yet promoted into
              // ServiceRequestModel since this is the only reader.
              customerCounterOffer:
                  (doc.data()!['customerCounterOffer'] as num?)?.toDouble(),
              details: request.rawDetails,
            ),
          );
        },
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
  }
}

// ================================================================
// SERVICE REQUEST STATUS CARD — minimal 3-button status-advance UI
// for the Broadcast Order System. Deliberately simple per spec.
// (Status-advance order lives in kServiceRequestAdvanceOrder,
// service_request_service.dart — single source of truth.)
// ================================================================

class _ServiceRequestStatusCard extends StatefulWidget {
  final String requestId;
  final String requestType;
  final String status;
  final String customerName;
  /// Manually-entered quote (see service_request_service.dart's
  /// "Unified Hero Task System: money fields" section) — null until
  /// the hero (or, optionally, an admin at assignment time) enters
  /// one. Pre-fills the "Mark Complete" final-amount dialog below.
  final double? estimatedAmount;
  final double? finalAmount;
  final String? paymentStatus;
  /// null = customer hasn't responded yet, true = approved, false =
  /// rejected (transient — rejectEstimate() clears estimatedAmount
  /// back to null in the same write, so `false` is never actually
  /// observed here in practice, only null/true).
  final bool? estimateApprovedByCustomer;
  /// NEW (per Nizam's request — Negotiate flow): set when the customer
  /// tapped "Negotiate" instead of "Approve" on the hero's estimate —
  /// the amount they'd rather pay, shown to the hero as a starting
  /// point for a revised quote. Cleared automatically once the hero
  /// submits a new estimate (see setEstimatedAmount()).
  final double? customerCounterOffer;
  /// NEW (per Nizam's request): raw `details` map off the service_
  /// requests doc — used to pull whatever pickup/drop coordinates that
  /// particular request type actually captured, to power the
  /// "Navigate" buttons below. Not every requestType has coordinates
  /// yet (see _pickupDropForRequest below) — those simply don't show a
  /// button rather than showing a broken one.
  final Map<String, dynamic> details;
  const _ServiceRequestStatusCard({
    required this.requestId,
    required this.requestType,
    required this.status,
    required this.customerName,
    this.estimatedAmount,
    this.finalAmount,
    this.paymentStatus,
    this.estimateApprovedByCustomer,
    this.customerCounterOffer,
    this.details = const {},
  });

  @override
  State<_ServiceRequestStatusCard> createState() => _ServiceRequestStatusCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(StringProperty('requestType', requestType));
    properties.add(StringProperty('status', status));
    properties.add(StringProperty('customerName', customerName));
    properties.add(DoubleProperty('estimatedAmount', estimatedAmount));
    properties.add(DoubleProperty('finalAmount', finalAmount));
    properties.add(StringProperty('paymentStatus', paymentStatus));
    properties.add(DiagnosticsProperty<bool?>('estimateApprovedByCustomer', estimateApprovedByCustomer));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('details', details));
  }
}

class _ServiceRequestStatusCardState extends State<_ServiceRequestStatusCard> {
  bool _updating = false;

  // FIX (per Nizam's bug report — hero saw a silent failure when
  // trying to "Start" a task and described it as "permission error"):
  // every catch block below used to only debugPrint the exception,
  // never actually telling the hero anything went wrong. Now shows the
  // real error text so a genuine Firestore/RTDB permission-denied (or
  // any other failure) is visible and actionable instead of invisible.
  void _showActionError(Object e) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('Could not update task: $e'),
        backgroundColor: const Color(0xFFE05555),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── NAVIGATE-TO-LOCATION (per Nizam's request) ────────────────────
  // Opens the External Google Maps app/site in navigation mode — same
  // idea as the bike-taxi ride flow's map, but for service_requests
  // tasks (hero_booking / food orders / electronics / grocery / custom
  // orders), using whatever coordinates that particular requestType
  // captured at order time via LocationCaptureField (see
  // location_capture_field.dart):
  //   - hero_booking: details.fromLocationLat/Lng (pickup, only for
  //     pickup-delivery tasks) and details.locationLat/Lng (drop).
  //   - custom_food_order (Food Genie): details.shopLat/Lng (pickup)
  //     and details.deliveryLatitude/Longitude (drop).
  //   - electronics_service, custom_order, grocery_order: single
  //     location only (details.locationLat/Lng) — the customer's own
  //     pickup/delivery/inspection address, no separate second point.
  //   - catalog_food_order: seller's shop has no real coordinates on
  //     file yet (sellers/{id}.latitude/longitude are still hardcoded
  //     0.0 at onboarding — a separate gap, not fixable from this card)
  //     and checkout never collected a delivery address either, so
  //     still nothing to navigate to for this one type.
  // Returns null when this request type + doc simply has nothing usable.
  ({double lat, double lng})? _pickupCoords() {
    final d = widget.details;
    if (widget.requestType == 'hero_booking') {
      final lat = (d['fromLocationLat'] as num?)?.toDouble();
      final lng = (d['fromLocationLng'] as num?)?.toDouble();
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    } else if (widget.requestType == 'custom_food_order') {
      final lat = (d['shopLat'] as num?)?.toDouble();
      final lng = (d['shopLng'] as num?)?.toDouble();
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }
    return null;
  }

  ({double lat, double lng})? _dropCoords() {
    final d = widget.details;
    if (widget.requestType == 'hero_booking') {
      final lat = (d['locationLat'] as num?)?.toDouble();
      final lng = (d['locationLng'] as num?)?.toDouble();
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    } else if (widget.requestType == 'custom_food_order') {
      final lat = (d['deliveryLatitude'] as num?)?.toDouble();
      final lng = (d['deliveryLongitude'] as num?)?.toDouble();
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    } else if (widget.requestType == 'electronics_service' ||
        widget.requestType == 'custom_order' ||
        widget.requestType == 'grocery_order') {
      final lat = (d['locationLat'] as num?)?.toDouble();
      final lng = (d['locationLng'] as num?)?.toDouble();
      if (lat != null && lng != null) return (lat: lat, lng: lng);
    }
    return null;
  }

  Future<void> _openGoogleMapsNav(double lat, double lng) async {
    final uri = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Google Maps.'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _navButton(String label, ({double lat, double lng}) coords) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: () => _openGoogleMapsNav(coords.lat, coords.lng),
        style: OutlinedButton.styleFrom(
          foregroundColor: const Color(0xFF2979FF),
          side: const BorderSide(color: Color(0xFF2979FF)),
          padding: const EdgeInsets.symmetric(vertical: 8),
        ),
        icon: const Icon(Icons.navigation_rounded, size: 15),
        label: Text(label, style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _buildNavigateRow() {
    final pickup = _pickupCoords();
    final drop = _dropCoords();
    if (pickup == null && drop == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 4),
      child: Row(
        children: [
          if (pickup != null) _navButton('Navigate to Pickup', pickup),
          if (pickup != null && drop != null) const SizedBox(width: 8),
          if (drop != null) _navButton('Navigate to Customer', drop),
        ],
      ),
    );
  }

  Future<void> _advanceTo(String newStatus) async {
    // Gate 1: before starting work, the hero must quote an estimate
    // so the customer sees a number before the task begins (Unified
    // Hero Task System requirement). Manual entry only — see
    // service_request_service.dart for why no formula exists here.
    if (newStatus == 'in_progress') {
      // Gate 1b: customer approval. If an estimate is already sitting
      // there awaiting a response, this button shouldn't even be
      // reachable (build() swaps it for a "Waiting for customer..."
      // state) — this check is defense-in-depth only.
      if (widget.estimatedAmount != null &&
          widget.estimateApprovedByCustomer != true) {
        return;
      }

      // Already approved (customer said yes to a previously-entered
      // estimate) — proceed straight to Start, no re-prompt.
      if (widget.estimatedAmount != null &&
          (widget.estimateApprovedByCustomer ?? false)) {
        setState(() => _updating = true);
        try {
          await ServiceRequestService().advanceStatus(widget.requestId, newStatus);
        } catch (e) {
          debugPrint('[ServiceRequestStatusCard] advanceStatus error: $e');
          _showActionError(e);
        } finally {
          if (mounted) setState(() => _updating = false);
        }
        return;
      }

      // First time: prompt for the estimate, write it, then STOP and
      // wait — the customer must explicitly approve before the hero
      // can proceed (Unified Hero Task System customer-approval
      // requirement). setEstimatedAmount() resets
      // estimateApprovedByCustomer to null, which flips build() into
      // the waiting state until Firestore reports true.
      // FIX (per Nizam's request — Negotiate flow): if the customer
      // countered instead of approving, show that number and pre-fill
      // it so the hero can immediately see and match/adjust it instead
      // of guessing what price will actually get approved this time.
      final counter = widget.customerCounterOffer;
      final amount = await _promptForAmount(
        context,
        title: counter != null ? 'Customer offered ₹${counter.toStringAsFixed(0)}' : 'Estimated amount',
        message: counter != null
            ? 'The customer asked for a lower price — ₹${counter.toStringAsFixed(0)}. '
                'Enter the amount you can actually do this task for.'
            : 'Enter what you expect to charge for this task. '
                'The customer needs to approve this before you can start.',
        initialValue: counter ?? widget.estimatedAmount,
      );
      if (amount == null) return; // cancelled — stay on current status
      setState(() => _updating = true);
      try {
        await ServiceRequestService().setEstimatedAmount(widget.requestId, amount);
      } catch (e) {
        debugPrint('[ServiceRequestStatusCard] setEstimatedAmount error: $e');
        _showActionError(e);
      } finally {
        if (mounted) setState(() => _updating = false);
      }
      return;
    }

    // Gate 2: completing the task requires a final bill amount,
    // pre-filled with the estimate but adjustable — mirrors the ride
    // flow's completion→billing pattern.
    if (newStatus == 'completed') {
      final amount = await _promptForAmount(
        context,
        title: 'Final amount',
        message: 'Confirm or adjust the final amount to bill the customer.',
        initialValue: widget.estimatedAmount,
      );
      if (amount == null) return;
      setState(() => _updating = true);
      try {
        await ServiceRequestService()
            .completeWithFinalAmount(widget.requestId, amount);
      } catch (e) {
        debugPrint('[ServiceRequestStatusCard] completeWithFinalAmount error: $e');
        _showActionError(e);
      } finally {
        if (mounted) setState(() => _updating = false);
      }
      return;
    }

    // Middle step ('nearing_completion') — no amount gate, unchanged.
    setState(() => _updating = true);
    try {
      await ServiceRequestService().advanceStatus(widget.requestId, newStatus);
    } catch (e) {
      debugPrint('[ServiceRequestStatusCard] advanceStatus error: $e');
      _showActionError(e);
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  String _typeLabel() {
    switch (widget.requestType) {
      case 'hero_booking':
        return 'Hero Booking';
      case 'custom_order':
        return 'Custom Order';
      case 'custom_food_order':
        return 'Food Order';
      case 'grocery_order':
        return 'Grocery Order';
      default:
        return 'Service Request';
    }
  }

  @override
  Widget build(BuildContext context) {
    final currentIndex = kServiceRequestAdvanceOrder.indexOf(widget.status);
    final nextStatus = currentIndex >= 0 && currentIndex < kServiceRequestAdvanceOrder.length - 1
        ? kServiceRequestAdvanceOrder[currentIndex + 1]
        : null;

    return Container(
      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFFF4FA3).withValues(alpha: 0.2)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 8, offset: const Offset(0, 3))],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(_typeLabel(), style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 13)),
                    Text('For ${widget.customerName}', style: const TextStyle(color: Colors.black54, fontSize: 11)),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(color: const Color(0xFFFF4FA3).withValues(alpha: 0.1), borderRadius: BorderRadius.circular(8)),
                child: Text(widget.status.replaceAll('_', ' '), style: const TextStyle(color: Color(0xFFFF4FA3), fontSize: 10, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
          // NEW (per Nizam's DMart-cart-screenshot workflow): the same
          // "hero must actually SEE the screenshots" fix as the accept
          // dialog above, but here in the full task-detail card, since
          // this is where the hero actually works the order through to
          // completion (not just the first accept/decline moment).
          if (widget.requestType == 'grocery_order' && orderPhotoUrlsFromDetails(widget.details).isNotEmpty) ...[
            const SizedBox(height: 10),
            OrderPhotoGallery(
              imageUrls: orderPhotoUrlsFromDetails(widget.details),
              label: 'Cart screenshots',
            ),
          ],
          if (widget.status != 'completed') _buildNavigateRow(),
          if (widget.estimatedAmount != null && widget.status != 'completed') ...[
            const SizedBox(height: 6),
            Text(
              'Estimated: ₹${widget.estimatedAmount!.toStringAsFixed(0)}',
              style: const TextStyle(color: Colors.black54, fontSize: 11, fontWeight: FontWeight.w600),
            ),
          ],
          if (nextStatus == 'in_progress' &&
              widget.estimatedAmount != null &&
              widget.estimateApprovedByCustomer != true) ...[
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.orange.withValues(alpha: 0.3)),
              ),
              child: const Text(
                'Waiting for customer to approve estimate…',
                style: TextStyle(color: Colors.orange, fontSize: 11, fontWeight: FontWeight.w700),
                textAlign: TextAlign.center,
              ),
            ),
          ] else if (nextStatus != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4FA3)),
                onPressed: _updating ? null : () => _advanceTo(nextStatus),
                child: _updating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    // FIX (UI polish, Aug 11 2026 — Hero button text
                    // overflow bug): this SizedBox pins height to 38, but
                    // the longest label here ('Nearing Completion', 19
                    // chars at fontSize 12 bold) could wrap past that
                    // fixed height on narrow phones with no overflow
                    // handling, clipping the text. FittedBox scales the
                    // whole label down to fit instead of ever clipping —
                    // short labels ('Start', 'Mark Complete') render at
                    // their natural size since FittedBox only shrinks,
                    // never grows.
                    : FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(_buttonLabelFor(nextStatus), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
                      ),
              ),
            ),
          ],
          // "Release Task" — a hero who accepted but no longer wants to
          // do this task can hand it back. Only offered pre-Start
          // (hero_assigned) — once in_progress, backing out mid-task
          // is a phone-call-to-admin situation, not a one-tap UI action.
          // Routes to admin_review (see releaseServiceRequest()), which
          // surfaces on admin_new_orders_screen.dart's "AWAITING
          // ASSIGNMENT" section and the admin_review badges.
          if (widget.status == 'hero_assigned') ...[
            const SizedBox(height: 8),
            // FIX (per Nizam's request — "font colors la konjam
            // disturbed ah iruku, pink and white theme ku yeththamathiri
            // irukanum"): was flat Colors.black54/black26, which read
            // as visually out of place surrounded by pink CTAs and the
            // pink-accented card border. Switched to the same muted-pink
            // tone the rest of this card already uses for secondary
            // actions.
            SizedBox(
              width: double.infinity,
              height: 34,
              child: OutlinedButton(
                onPressed: _updating ? null : _releaseTask,
                style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8F5A78),
                  side: BorderSide(color: const Color(0xFFFF4FA3).withValues(alpha: 0.35)),
                ),
                child: const Text('Release Task',
                    style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),),
              ),
            ),
          ],
          // Requirement 5: after "Mark Complete", the task isn't fully
          // closed until payment is collected. The customer can pay
          // via UPI (service_request_payment_screen.dart writes
          // paymentStatus:'paid' directly), but for cash the hero needs
          // their own explicit close action — mirrors the ride flow's
          // "Collect Payment" step.
          if (widget.status == 'completed') ...[
            const SizedBox(height: 10),
            if (widget.finalAmount != null)
              Text(
                'Final bill: ₹${widget.finalAmount!.toStringAsFixed(0)}',
                style: GoogleFonts.outfit(color: const Color(0xFF3D1230), fontSize: 12, fontWeight: FontWeight.w700),
              ),
            const SizedBox(height: 6),
            // FIX (per Nizam's explicit request — payment authority now
            // lives entirely with the hero, see
            // markServiceRequestPaymentReceived()): the old interim
            // 'hero_marked_paid' state (and its "waiting for customer to
            // confirm" badge) is gone — tapping "Payment Received" below
            // now sets 'paid' directly, so there are only two states to
            // show here.
            if (widget.paymentStatus == 'paid')
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF00C853).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                ),
                child: const Text('Payment Received ✓',
                    style: TextStyle(color: Color(0xFF00C853), fontSize: 11, fontWeight: FontWeight.w800),),
              )
            else
              SizedBox(
                width: double.infinity,
                height: 38,
                child: OutlinedButton(
                  onPressed: _updating ? null : _markPaymentReceived,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: const Color(0xFF00C853),
                    side: const BorderSide(color: Color(0xFF00C853)),
                  ),
                  child: _updating
                      ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFF00C853)))
                      // FIX (UI polish, Aug 11 2026 — Hero button text
                      // overflow bug): 'Payment Received (Cash/UPI)' is
                      // 28 characters at fontSize 11 bold inside a fixed
                      // height:38 button — on narrow phones this was
                      // wrapping to 2 lines and clipping against the
                      // fixed height. FittedBox scales the label down to
                      // guarantee it always fits on one line instead.
                      : const FittedBox(
                          fit: BoxFit.scaleDown,
                          child: Text('Payment Received (Cash/UPI)', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 11)),
                        ),
                ),
              ),
          ],
          // "Delete Task" — hard-deletes the request doc entirely
          // (ServiceRequestService.cancelServiceRequest, same full-
          // delete path the admin's Cancel uses). Added because test
          // tasks were piling up with no hero-side way to clear them
          // — completed-but-unpaid cards especially stayed on screen
          // forever. Offered at every status, but always behind an
          // explicit confirm dialog since this also removes the
          // customer's tracking view of the request.
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 34,
            child: TextButton.icon(
              onPressed: _updating ? null : _deleteTask,
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              icon: const Icon(Icons.delete_outline_rounded, size: 16),
              label: const Text('Delete Task',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600),),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete this task?'),
        content: const Text(
          'This permanently deletes the request for everyone — the '
          'customer will no longer see it in their tracking either. '
          'This cannot be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Task'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updating = true);
    try {
      await ServiceRequestService().cancelServiceRequest(widget.requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task deleted.')),
        );
      }
    } catch (e) {
      debugPrint('[ServiceRequestStatusCard] cancelServiceRequest error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete task: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _markPaymentReceived() async {
    setState(() => _updating = true);
    try {
      await ServiceRequestService()
          .markServiceRequestPaymentReceived(widget.requestId);
    } catch (e) {
      debugPrint('[ServiceRequestStatusCard] markServiceRequestPaymentReceived error: $e');
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  Future<void> _releaseTask() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Release this task?'),
        content: const Text(
          'This task will be handed back to our team for reassignment. '
          'You will no longer be able to work on it.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Keep Task'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: TextButton.styleFrom(foregroundColor: Colors.red),
            child: const Text('Release Task'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    setState(() => _updating = true);
    try {
      await ServiceRequestService().releaseServiceRequest(widget.requestId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Task released back to our team.')),
        );
      }
    } catch (e) {
      debugPrint('[ServiceRequestStatusCard] releaseServiceRequest error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not release task: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _updating = false);
    }
  }

  String _buttonLabelFor(String nextStatus) {
    switch (nextStatus) {
      case 'in_progress':
        return 'Start';
      case 'nearing_completion':
        return 'Nearing Completion';
      case 'completed':
        return 'Mark Complete';
      default:
        return 'Advance';
    }
  }
}

/// Shared amount-entry dialog for the Unified Hero Task System's
/// estimate ("before Start") and final-bill ("at Mark Complete")
/// gates. Returns null if the hero cancels — callers must treat that
/// as "stay on current status," never silently proceeding without an
/// amount. Reused by both hero_home_screen.dart's status card and
/// (optionally) admin_new_orders_screen.dart's assign sheet.
Future<double?> _promptForAmount(
  BuildContext context, {
  required String title,
  required String message,
  double? initialValue,
}) async {
  final controller = TextEditingController(
    text: initialValue != null ? initialValue.toStringAsFixed(0) : '',
  );
  final result = await showDialog<double>(
    context: context,
    builder: (ctx) => AlertDialog(
      title: Text(title),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: const TextStyle(fontSize: 12, color: Colors.black54)),
          const SizedBox(height: 12),
          TextField(
            controller: controller,
            autofocus: true,
            keyboardType: const TextInputType.numberWithOptions(),
            decoration: const InputDecoration(
              prefixText: '₹ ',
              border: OutlineInputBorder(),
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: () {
            final parsed = double.tryParse(controller.text.trim());
            if (parsed == null || parsed <= 0) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                const SnackBar(content: Text('Enter a valid amount')),
              );
              return;
            }
            Navigator.pop(ctx, parsed);
          },
          child: const Text('Confirm'),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}

// ================================================================
// LIVE PULSE DOT — standalone widget to prevent full-screen rebuilds
// ================================================================
class _LivePulseDot extends StatefulWidget {
  const _LivePulseDot();

  @override
  State<_LivePulseDot> createState() => _LivePulseDotState();
}

class _LivePulseDotState extends State<_LivePulseDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _anim;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
    _anim = Tween<double>(begin: 0.95, end: 1.05).animate(
      CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut),
    );
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _anim,
      builder: (context, child) => Transform.scale(
        scale: _anim.value,
        child: Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: Color(0xFF00C853),
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}

// ================================================================
// T4: HERO RADAR ANIMATION
// Sweeping NJ-Pink lens shown when no rides are incoming.
// Replaces the static "Scanning" card — map stays visible beneath.
// ================================================================
class _HeroRadarVisual extends StatefulWidget {
  final double size;
  const _HeroRadarVisual({this.size = 56});

  @override
  State<_HeroRadarVisual> createState() => _HeroRadarVisualState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DoubleProperty('size', size));
  }
}

class _HeroRadarVisualState extends State<_HeroRadarVisual>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.size;
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (_, __) {
        return SizedBox(
          width: s,
          height: s,
          child: CustomPaint(
            size: Size(s, s),
            painter: _RadarPainter(sweepAngle: _ctrl.value * 2 * math.pi),
          ),
        );
      },
    );
  }
}

class _HeroRadarAnimation extends StatefulWidget {
  const _HeroRadarAnimation();

  @override
  State<_HeroRadarAnimation> createState() => _HeroRadarAnimationState();
}

class _HeroRadarAnimationState extends State<_HeroRadarAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 3),
    )..repeat();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _ctrl,
      builder: (context, _) {
        return CustomPaint(
          painter: _RadarPainter(sweepAngle: _ctrl.value * 2 * math.pi),
          child: Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: const Color(0xFFFF4FA3).withValues(alpha: 0.12),
                    border: Border.all(
                      color: const Color(0xFFFF4FA3).withValues(alpha: 0.4),
                      width: 2,
                    ),
                  ),
                  child: const Icon(
                    Icons.radar_rounded,
                    color: Color(0xFFFF4FA3),
                    size: 28,
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  'All-in-1 Lens Active',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                    color: const Color(0xFF4A1736),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'Scanning your zone for premium rides...',
                  style: GoogleFonts.outfit(
                    fontSize: 11,
                    color: const Color(0xFF94627F),
                  ),
                  textAlign: TextAlign.center,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

class _RadarPainter extends CustomPainter {
  const _RadarPainter({required this.sweepAngle});
  final double sweepAngle;

  @override
  void paint(Canvas canvas, Size size) {
    // FIX (Aug 31 2026 — "hero main screen blank"). Second, independent
    // layer of the same fix as the LayoutBuilder floor above this
    // painter's caller: whatever upstream widget sizing produced this
    // `size`, if it is degenerate (zero or negative on either axis) the
    // SweepGradient shader built below would get an equally degenerate
    // bounding Rect, and CanvasKit's gradient-shader code throws a raw
    // "Null check operator used on a null value" for that — inside the
    // rendering engine's own paint call, not catchable Dart code, and
    // it refires on every single repaint attempt. That turned one bad
    // frame into a permanently blank, unresponsive screen once before
    // (the registration form's category grid); skipping the paint
    // entirely for a canvas that isn't a real size closes the same
    // failure mode here, independent of whether the LayoutBuilder floor
    // above ever gets bypassed by some layout path this painter can't
    // see.
    if (size.width <= 0 || size.height <= 0) return;

    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.42;

    // ── Sweeping sector (transparent gradient arc) ─────────────
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        colors: const [
          Color(0x00FF4FA3),
          Color(0x30FF4FA3),
        ],
        startAngle: sweepAngle - 0.9,
        endAngle: sweepAngle,
      ).createShader(Rect.fromCircle(center: center, radius: maxRadius))
      ..style = PaintingStyle.fill;
    canvas.drawCircle(center, maxRadius, sweepPaint);

    // ── Sweep leading edge (thin line) ─────────────────────────
    final linePaint = Paint()
      ..color = const Color(0xFFFF4FA3).withValues(alpha: 0.5)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      center,
      Offset(
        center.dx + maxRadius * math.cos(sweepAngle),
        center.dy + maxRadius * math.sin(sweepAngle),
      ),
      linePaint,
    );
  }

  @override
  bool shouldRepaint(_RadarPainter old) => old.sweepAngle != sweepAngle;
}

// ================================================================
// SOS COUNTDOWN DIALOG
// ================================================================
class _SosCountdownDialog extends StatefulWidget {
  const _SosCountdownDialog();

  @override
  State<_SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<_SosCountdownDialog> {
  int _secondsLeft = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFB00020),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      title: const Text(
        'SOS Triggered!',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sos_rounded, color: Colors.white, size: 58),
          const SizedBox(height: 14),
          Text(
            'Cancelling in ${_secondsLeft}s...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nearby Heroes and NJ Tech Call Center will be alerted.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFFB00020),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}

// ================================================================
// PENDING RIDE CARD WIDGET
// ================================================================
class _PendingRideCard extends StatelessWidget {
  final String rideId;
  final Map<String, dynamic> data;
  final bool accepting;
  final VoidCallback onAccept;
  final VoidCallback onCall;
  const _PendingRideCard({
    required this.rideId,
    required this.data,
    required this.accepting,
    required this.onAccept,
    required this.onCall,
  });

  String _ago(Object? ts) {
    if (ts == null) {
      return 'just now';
    }
    try {
      final dt = (ts as Timestamp).toDate();
      final diff = DateTime.now().difference(dt);
      if (diff.inSeconds < 60) {
        return '${diff.inSeconds}s ago';
      }
      return '${diff.inMinutes}m ago';
    } catch (_) {
      return 'just now';
    }
  }

  @override
  Widget build(BuildContext context) {
    final fare = (data['fare'] as num?)?.toDouble() ?? 0.0;
    final tip = (data['tipAmount'] as num?)?.toDouble() ?? 0.0;
    final total = fare + tip;
    final pickup =
        (data['pickupAddress'] as String?)?.trim().isNotEmpty ?? false
            ? (data['pickupAddress'] as String).trim()
            : (data['pickup'] as String? ?? '');
    final drop = (data['dropAddress'] as String?)?.trim().isNotEmpty ?? false
        ? (data['dropAddress'] as String).trim()
        : (data['drop'] as String? ?? '');
    final cname = data['customerName'] as String? ?? 'Customer';
    final ts = data['createdAt'];
    final dist = (data['distanceKm'] as num?)?.toStringAsFixed(1) ?? '?';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: const Color(0xFF0A0A12),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0x33FF4FA3),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x30FF4FA3),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              children: [
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0x22FF4FA3),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: const Color(0x44FF4FA3)),
                  ),
                  child: const Center(
                    child: Text('🏍️', style: TextStyle(fontSize: 22)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        cname,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFFEEEEF5),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      Text(
                        _ago(ts),
                        style: const TextStyle(
                          fontSize: 10,
                          color: Color(0xFF7777A0),
                        ),
                      ),
                    ],
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '₹${fare.toInt()}',
                      style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: Color(0xFFFF4FA3),
                      ),
                    ),
                    Text(
                      '$dist km',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Color(0xFF7777A0),
                      ),
                    ),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            _loc('🟢', pickup),
            const SizedBox(height: 6),
            _loc('🔴', drop),
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x26FF4FA3)),
              ),
              child: Row(
                children: [
                  Text(
                    'Fare: ₹${fare.toInt()}',
                    style: const TextStyle(
                      fontSize: 12,
                      color: Color(0xFFFF4FA3),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (tip > 0) ...[
                    Text(
                      '  +  ₹${tip.toInt()}',
                      style: const TextStyle(
                        fontSize: 11,
                        color: Color(0xFFFFBB00),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                  const Spacer(),
                  Text(
                    '= ₹${total.toInt()}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: Color(0xFF00A86B),
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                GestureDetector(
                  onTap: onCall,
                  child: Container(
                    width: 42,
                    height: 42,
                    decoration: BoxDecoration(
                      color: const Color(0x1A00C853),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: const Color(0x3300C853)),
                    ),
                    child: const Icon(
                      Icons.phone,
                      size: 18,
                      color: Color(0xFF00C853),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: GestureDetector(
                    onTap: accepting ? null : onAccept,
                    child: Container(
                      height: 44,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFFF4FA3), Color(0xFFFF9AC8)],
                        ),
                        borderRadius: BorderRadius.circular(13),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x40FF4FA3),
                            blurRadius: 10,
                            offset: Offset(0, 4),
                          ),
                        ],
                      ),
                      child: accepting
                          ? const Center(
                              child: SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  color: Colors.white,
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.check_circle_outline,
                                  size: 18,
                                  color: Colors.white,
                                ),
                                const SizedBox(width: 6),
                                Text(
                                  'ACCEPT',
                                  style: GoogleFonts.outfit(
                                    fontSize: 14,
                                    fontWeight: FontWeight.w900,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _loc(String dot, String txt) => Row(
        children: [
          Text(dot, style: const TextStyle(fontSize: 10)),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              txt,
              style: const TextStyle(fontSize: 12, color: Color(0xFFEEEEF5)),
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      );

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('rideId', rideId))
      ..add(DiagnosticsProperty<Map<String, dynamic>>('data', data))
      ..add(DiagnosticsProperty<bool>('accepting', accepting))
      ..add(ObjectFlagProperty<VoidCallback>.has('onAccept', onAccept))
      ..add(ObjectFlagProperty<VoidCallback>.has('onCall', onCall));
  }
}

class _HeroSoundboxPromoButton extends StatelessWidget {
  const _HeroSoundboxPromoButton({
    required this.controller,
    required this.onTap,
  });

  final AnimationController controller;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: controller,
      builder: (context, _) {
        final glowStrength = 0.22 + (controller.value * 0.38);
        final rotation = controller.value * math.pi * 2;
        return GestureDetector(
          onTap: onTap,
          child: Transform.rotate(
            angle: rotation,
            child: SizedBox(
              width: 92,
              height: 92,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: <Widget>[
                  Container(
                    width: 92,
                    height: 92,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: const LinearGradient(
                        colors: <Color>[
                          Color(0xFFFF4FA3),
                          Color(0xFFFF73C0),
                          Color(0xFFB21FFF),
                        ],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: <BoxShadow>[
                        BoxShadow(
                          color: const Color(0xFFFF4FA3)
                              .withValues(alpha: glowStrength),
                          blurRadius: 28,
                          spreadRadius: 4,
                        ),
                      ],
                    ),
                  ),
                  Transform.rotate(
                    angle: -rotation,
                    child: Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        shape: BoxShape.circle,
                        boxShadow: <BoxShadow>[
                          BoxShadow(
                            color: Colors.white.withValues(alpha: 0.55),
                            blurRadius: 16,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                      padding: const EdgeInsets.all(6),
                      child: Image.asset(
                        'assets/images/paytm_soundbox.png',
                        width: 45,
                        height: 45,
                        fit: BoxFit.contain,
                      ),
                    ),
                  ),
                  Positioned(
                    top: -2,
                    right: -2,
                    child: Transform.rotate(
                      angle: -rotation,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(999),
                          boxShadow: <BoxShadow>[
                            BoxShadow(
                              color: const Color(0xFFFF4FA3)
                                  .withValues(alpha: 0.22),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            ),
                          ],
                        ),
                        child: const Text(
                          'FREE',
                          style: TextStyle(
                            color: Color(0xFFFF4FA3),
                            fontSize: 10,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(
        DiagnosticsProperty<AnimationController>('controller', controller),);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _PingCountdownDialog extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> pingData;
  final Function(String requestId, Map<String, dynamic> pingData,
      BuildContext dialogContext,) onAccept;
  final Function(String requestId) onReject;
  const _PingCountdownDialog({
    required this.requestId,
    required this.pingData,
    required this.onAccept,
    required this.onReject,
  });
  @override
  State<_PingCountdownDialog> createState() => _PingCountdownDialogState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('pingData', pingData));
    properties.add(ObjectFlagProperty<Function(String requestId, Map<String, dynamic> pingData, BuildContext dialogContext)>.has('onAccept', onAccept));
    properties.add(ObjectFlagProperty<Function(String requestId)>.has('onReject', onReject));
  }
}

class _PingCountdownDialogState extends State<_PingCountdownDialog> {
  Timer? _countdownTimer;
  int _remainingSec = 15;
  // Guards the ACCEPT button against firing before the previous tap's
  // accept write has finished — previously this dialog popped itself
  // immediately on tap without awaiting widget.onAccept(), so a slow or
  // failed write left the hero stuck with no feedback (see onPressed
  // below).
  bool _isAccepting = false;

  @override
  void initState() {
    super.initState();
    int pingExpiresAt = (widget.pingData['pingExpiresAt'] as num?)?.toInt() ?? 0;
    
    // 🚀 FIX: Fallback for Push Notifications (Firestore data doesn't have pingExpiresAt)
    if (pingExpiresAt == 0) {
      pingExpiresAt = DateTime.now().toUtc().millisecondsSinceEpoch + 15000; // 15s from now
    }
    
    final remainingMs =
        (pingExpiresAt - DateTime.now().toUtc().millisecondsSinceEpoch)
            .clamp(0, 15000);
    _remainingSec = (remainingMs / 1000).ceil();
    
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      final nowRemaining =
          (pingExpiresAt - DateTime.now().toUtc().millisecondsSinceEpoch)
              .clamp(0, 15000);
      if (nowRemaining <= 0) {
        t.cancel();
        widget.onReject(widget.requestId);
        if (mounted) {
          try {
            Navigator.pop(context);
          } catch (_) {}
        }
        return;
      }
      setState(() => _remainingSec = (nowRemaining / 1000).ceil());
    });
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pickup =
        widget.pingData['pickupAddress'] as String? ?? 'Unknown Pickup';
    final drop = widget.pingData['dropAddress'] as String? ?? 'Unknown Drop';
    final estimatedFare =
        (widget.pingData['estimatedFare'] as num?)?.toDouble() ?? 0.0;
    final tipAmount = (widget.pingData['tipAmount'] as num?)?.toDouble() ?? 0.0;
    final double boostedFare = estimatedFare + tipAmount;
    // FIX (per Nizam's request — "2 popup notificationla irukura good
    // things yeduthu final ah oru notification popup align pandrom"):
    // this dialog used to be dark-themed (bg #0A0A12, cards #1A1A2E,
    // white text) while the hero_booking dialog (_doShowServiceDialog
    // above) was already the correct pink/white "cute" look the user
    // wants everywhere. Purely a color swap here — every data binding
    // (pickup/drop/fare/tip/countdown/actions) is completely untouched,
    // same as before, per the explicit "backend logic yethume maathi
    // app crash paniratha" instruction.
    return AlertDialog(
      backgroundColor: Colors.white,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x33FF4FA3)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      title: const Text('🚀 New Ride Request',
          style:
              TextStyle(color: Color(0xFFFF4FA3), fontWeight: FontWeight.w800),),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF1F8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x33FF4FA3)),),
            child: Row(children: [
              const Text('🟢', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PICKUP',
                      style: TextStyle(
                          color: Color(0xFF8F5A78),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,),),
                  const SizedBox(height: 4),
                  Text(pickup,
                      style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,),),
                ],
              ),),
            ],),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFFFFF1F8),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x33FF4FA3)),),
            child: Row(children: [
              const Text('🔴', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DROP',
                      style: TextStyle(
                          color: Color(0xFF8F5A78),
                          fontSize: 10,
                          fontWeight: FontWeight.w700,),),
                  const SizedBox(height: 4),
                  Text(drop,
                      style: const TextStyle(
                          color: Colors.black87,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,),),
                ],
              ),),
            ],),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F8),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: tipAmount > 0
                      ? const Color(0xFF00A86B).withValues(alpha: 0.45)
                      : const Color(0x33FF4FA3),),
            ),
            child: Row(children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Fare',
                        style: TextStyle(
                            color: Color(0xFF8F5A78),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,),),
                    const SizedBox(height: 2),
                    Text('\u{20b9}${estimatedFare.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Color(0xFFFF4FA3),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,),),
                  ],
                ),
              ),
              if (tipAmount > 0) ...[
                const Text('  +  ',
                    style: TextStyle(color: Color(0xFF8F5A78), fontSize: 11),),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tip',
                          style: TextStyle(
                              color: Color(0xFF8F5A78),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,),),
                      const SizedBox(height: 2),
                      Text('\u{20b9}${tipAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Color(0xFFFFBB00),
                              fontSize: 16,
                              fontWeight: FontWeight.w900,),),
                    ],
                  ),
                ),
              ],
              const Text('  =  ',
                  style: TextStyle(
                      color: Color(0xFF8F5A78),
                      fontSize: 13,
                      fontWeight: FontWeight.w800,),),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            color: Color(0xFF8F5A78),
                            fontSize: 10,
                            fontWeight: FontWeight.w700,),),
                    const SizedBox(height: 2),
                    Text('\u{20b9}${boostedFare.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Color(0xFF00A86B),
                            fontSize: 16,
                            fontWeight: FontWeight.w900,),),
                  ],
                ),
              ),
            ],),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Expires in $_remainingSec s',
                style: const TextStyle(
                    color: Color(0xFFFF5252),
                    fontSize: 13,
                    fontWeight: FontWeight.w700,),),
          ),
        ],
      ),
      actions: [
        Row(children: [
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFFFF5252),
                  side: const BorderSide(color: Color(0x40FF5252)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),),
                  padding: const EdgeInsets.symmetric(vertical: 14),),
              onPressed: () {
                _countdownTimer?.cancel();
                widget.onReject(widget.requestId);
                Navigator.pop(context);
              },
              child: const Text('REJECT',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8F5A78),
                  side: const BorderSide(color: Color(0x338F5A78)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),),
                  padding: const EdgeInsets.symmetric(vertical: 14),),
              onPressed: () {
                // MINIMIZE (Aug 8 2026 unified-popup spec): unlike
                // REJECT, this does NOT touch the RTDB ping — the
                // request stays valid/active for the rest of its
                // broadcast window, this just closes the dialog so the
                // hero isn't blocked from using the app. No reopen
                // surface exists yet for a minimized ping (tracked
                // separately); tapping the original lock-screen
                // notification still works as a reopen path.
                _countdownTimer?.cancel();
                Navigator.pop(context);
              },
              child: const Text('MINIMIZE',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11),),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF4FA3), Color(0xFFFF9AC8)],),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x40FF4FA3),
                      blurRadius: 16,
                      offset: Offset(0, 6),),
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),),
                    padding: const EdgeInsets.symmetric(vertical: 14),),
                onPressed: _isAccepting
                    ? null
                    : () async {
                        _countdownTimer?.cancel();
                        setState(() => _isAccepting = true);
                        final data =
                            Map<String, dynamic>.from(widget.pingData);
                        try {
                          // Previously this fired widget.onAccept() without
                          // awaiting it and popped the dialog on the very
                          // next line — the dialog closed before the accept
                          // write even started, so a slow/failed write left
                          // the hero stuck on the radar with no feedback.
                          // Awaiting here, plus a timeout, ensures we only
                          // move on once the outcome is known.
                          //
                          // Note: we no longer pop the dialog here on
                          // success. _acceptRide (via the dialogContext
                          // passed as the 3rd arg below) now pops this
                          // dialog's own route itself, right before it
                          // pushes CaptainRideScreen — this avoids a race
                          // where this dialog's own delayed pop (running
                          // after the push already landed) ended up
                          // popping the freshly-pushed ride screen instead
                          // of the dialog. On failure/timeout below,
                          // _acceptRide's success path (including its
                          // dialog-pop) never runs, so this dialog stays
                          // open and only resets its own accepting state.
                          await (widget.onAccept(
                                  widget.requestId, data, context,)
                              as Future<void>)
                              .timeout(const Duration(seconds: 12));
                        } on TimeoutException {
                          if (mounted) {
                            setState(() => _isAccepting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Taking longer than expected — check your '
                                  'connection and try again.',
                                ),
                                backgroundColor: Color(0xFFE05555),
                              ),
                            );
                          }
                          // Do NOT navigate/pop — the RTDB transaction is
                          // atomic, so retapping ACCEPT safely no-ops if
                          // the write actually did succeed server-side.
                        } catch (e) {
                          if (mounted) {
                            setState(() => _isAccepting = false);
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text(
                                  'Failed to accept ride — please try again.',
                                ),
                                backgroundColor: Color(0xFFE05555),
                              ),
                            );
                          }
                          debugPrint(
                            '[_PingCountdownDialog] Accept failed: $e',
                          );
                        }
                      },
                child: _isAccepting
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          valueColor:
                              AlwaysStoppedAnimation<Color>(Colors.white),
                        ),
                      )
                    : const Text('ACCEPT',
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w900,
                            fontSize: 15,),),
              ),
            ),
          ),
        ],),
      ],
    );
  }
}

// UNIFIED POPUP SPEC (Aug 8 2026): tiny data holder for one address row
// (emoji marker, label like "FROM"/"DELIVER TO", the address string) in
// the grocery/food/hero-booking Accept dialog — see
// _serviceRequestLocationLines() above.
class _ServiceRequestLocationLine {
  final String emoji;
  final String label;
  final String value;
  const _ServiceRequestLocationLine(this.emoji, this.label, this.value);
}
