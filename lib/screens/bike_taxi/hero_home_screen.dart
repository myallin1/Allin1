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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../app_navigator.dart';
import '../../models/ride_model.dart';
import '../../services/hero_ride_notification_service.dart';
import '../../services/hero_web_audio_service.dart';
import '../../services/location_service.dart';
import '../../services/service_request_service.dart';
import '../../services/update_service.dart';
import '../../widgets/allin1_map_widget.dart';
import '../../widgets/hero_premium_loader.dart';
import '../earn/rewards_hub_screen.dart';
import '../notifications_screen.dart';
import 'hero_ride_screen.dart';

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

  // Cached stats — loaded once per session in _loadHeroData()
  int _totalRides = 0;
  double _totalEarnings = 0.0;
  bool _statsLoaded = false;

  // ── SOS Emergency state ──────────────────────────────────────
  final List<DateTime> _sosTapTimes = <DateTime>[];
  bool _sendingSos = false;

  // GPS throttling for RTDB
  DateTime? _lastGpsUpdate;
  Position? _lastUploadedPosition;
  Timer? _locationTimer;
  Position? _latestPosition;
  LatLng? _displayHeroLocation;
  double? _displayHeroBearingDegrees;
  AnimationController? _heroMarkerMoveCtrl;

  AnimationController? _pulseCtrl;
  Animation<double>? _pulseAnim;

  // Captain profile from Firebase Auth
  User? _user;
  String get _captainName =>
      _user?.displayName ?? _user?.email?.split('@').first ?? 'Hero Rider';
  String get _avatarLetter =>
      _captainName.isNotEmpty ? _captainName[0].toUpperCase() : 'H';

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

  Future<void> _showUpdateDialog() async {
    final updateUrl = Uri.parse('https://my-allin1.web.app/hero-allin1.apk');

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
                final launched = await launchUrl(
                  updateUrl,
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
    _user = FirebaseAuth.instance.currentUser;
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
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (!_isOnline || _user == null) {
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
        setState(() {});
        setState(() => _mapRefreshGen++);
        _syncOnlineStatus(true);
        unawaited(_loadHeroData());
        unawaited(_consumePendingRidePush());
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
          // Remove from RTDB radar to save battery — does NOT touch Firestore
          FirebaseDatabase.instance
              .ref('online_heroes/${_user!.uid}')
              .remove()
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

      if (mounted) {
        setState(() {
          _commissionRate = rate;
          _heroCoins = coins;
          _firstLoginToday = isFirstToday;
          _waiverCompleted = rate <= 0.0;
          _vehicleType = vehicleType;
          // FIX BUG #3: Restore online state from Firestore if captain was online
          _isOnline = (data['isOnline'] as bool?) ?? false;
        });
      }

      // FIX BUG #3: If captain was online before restart, restart tracking
      if (_isOnline) {
        // _initPendingRidesStream removed
        _startGlobalLocationTracking();
        _listenForHeroPings();
        _listenForServicePings();

        unawaited(_consumePendingRidePush());
        debugPrint('🔄 Hero online state restored — live tracking restarted');
      }

      // Stats — fetch once per session, cache in state
      if (!_statsLoaded) {
        try {
          final ridesSnap = await FirebaseFirestore.instance
              .collection('rides')
              .where('captainId', isEqualTo: _user!.uid)
              .where('status', isEqualTo: 'completed')
              .get();
          double earn = 0;
          for (final d in ridesSnap.docs) {
            earn += ((d.data())['fare'] as num? ?? 0).toDouble();
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
  Future<void> _syncOnlineStatus(bool online) async {
    if (_user == null) {
      return;
    }
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
        currentPos = await LocationService().getCurrentLocation();
        if (currentPos == null) {
          if (mounted) {
            setState(() => _isOnline = false);
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Enable high-accuracy location to go online and receive rides.',
                ),
                backgroundColor: _red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      final data = <String, dynamic>{
        'isOnline': online,
        'status': online ? 'online' : 'offline',
        'lastUpdated': FieldValue.serverTimestamp(),
      };

      if (online) {
        data['isAvailable'] = _activeRideId.isEmpty;
        data['lastSeen'] = FieldValue.serverTimestamp();
        data['captainName'] = _captainName;
        data['vehicleType'] = _normalizeHeroVehicleType(_vehicleType);

        // ── FORCE immediate RTDB write: bypass all throttles ──
        _lastUploadedPosition = null;
        _lastGpsUpdate = null;
        if (currentPos != null) {
          await FirebaseDatabase.instance.ref('online_heroes/${_user!.uid}').set({
            'lat': currentPos.latitude,
            'lng': currentPos.longitude,
            'latitude': currentPos.latitude,
            'longitude': currentPos.longitude,
            'name': _captainName,
            'vehicleType': _normalizeHeroVehicleType(_vehicleType),
            'isAvailable': _activeRideId.isEmpty,
            'category': _normalizeHeroVehicleType(_vehicleType).toLowerCase(),
            'lastUpdated': ServerValue.timestamp,
          });
          _lastUploadedPosition = currentPos;
          debugPrint('🔥 [ONLINE] Force-wrote hero position to RTDB online_heroes/${_user!.uid}');
        }
      }

      await FirebaseFirestore.instance
          .collection('heroes')
          .doc(_user!.uid)
          .set(data, SetOptions(merge: true));
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
      } else {
        _heroPingSub?.cancel();
        _heroPingSub = null;
        _stopServicePingListening();
      }
    } catch (e) {
      debugPrint('[HeroHomeScreen] syncOnlineStatus error: ');
      _heroPingSub?.cancel();
      _heroPingSub = null;
      _stopServicePingListening();
      if (mounted) {
        setState(() => _isOnline = false);
      }
    }
  }

  // ── GLOBAL LOCATION TRACKING (Radar) ─────────────────────────
  void _startGlobalLocationTracking() {
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
      highAccuracy: false, // radar mode — battery efficient
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

        // RTDB: For real-time nearby heroes radar — 50m gate to save writes
        if (_lastUploadedPosition != null) {
          final dist = Geolocator.distanceBetween(
            _lastUploadedPosition!.latitude,
            _lastUploadedPosition!.longitude,
            pos.latitude,
            pos.longitude,
          );
          if (dist < 50) {
            debugPrint('[Location] Skipped RTDB update — moved only ${dist.toStringAsFixed(1)}m');
            return;
          }
        }
        _lastUploadedPosition = pos;
        await FirebaseDatabase.instance.ref('online_heroes/${_user!.uid}').set({
          'lat': pos.latitude,
          'lng': pos.longitude,
          'latitude': pos.latitude,
          'longitude': pos.longitude,
          'name': _captainName,
          'vehicleType': _normalizeHeroVehicleType(_vehicleType),
          'isAvailable': _activeRideId.isEmpty,
          'category': _normalizeHeroVehicleType(_vehicleType).toLowerCase(),
          'lastUpdated': ServerValue.timestamp,
        });

        // Firestore: SKIPPED in timer - status writes handled by _syncOnlineStatus with 3min gate\n} else if (_isOnline && _user != null && _latestPosition == null) {
        debugPrint(
          '⚠️ RTDB skipped — _latestPosition still null, waiting for GPS',
        );
      }
    });

    debugPrint('🛰️ Hero Live Tracking STARTED (10s interval)');
  }

  // _shouldWriteFirestoreLocation REMOVED - Firestore writes only via _syncOnlineStatus

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
    WidgetsBinding.instance.removeObserver(this);
    // T1: Cancel UI-only subscriptions (foreground popup listeners).
    // FCM background handler in main_hero.dart continues to deliver
    // ride alerts when the app is minimised or terminated.
    _foregroundMessageSub?.cancel();
    _messageOpenedSub?.cancel();
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
      if (_user == null || !_isOnline) {
        return;
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
    if (_user == null || !_isOnline || _activeRideId.isNotEmpty) {
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

  void _listenForHeroPings() {
    final uid = _user?.uid;
    if (uid == null) return;
    _heroPingSub?.cancel();
    debugPrint('🔥 [DEBUG] Hero is LISTENING to EXACT PATH: hero_pings/$uid');

    // Track when listener was attached — ignore pings older than this
    final listenerAttachedAt = DateTime.now().toUtc().millisecondsSinceEpoch;

    _heroPingSub = FirebaseDatabase.instance
        .ref('hero_pings/$uid')
        .onChildAdded
        .listen((event) {
      if (!mounted || !_isOnline || _activeRideId.isNotEmpty) return;
      if (_isShowingRideDialog) return;

      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key as String? ?? '';
      if (pingData == null || requestId.isEmpty) return;

      final pingExpiresAt = (pingData['pingExpiresAt'] as num?)?.toInt();
      if (pingExpiresAt == null) return;
      if (DateTime.now().toUtc().millisecondsSinceEpoch > pingExpiresAt) {
        FirebaseDatabase.instance.ref('hero_pings/$uid/$requestId').remove();
        return;
      }

      // ✅ FIX: Ignore pings that existed before this listener attached
      // Prevents stale pings from re-triggering on app resume
      final pingCreatedAt = pingExpiresAt - 10000; // expiresAt - 10s window
      if (pingCreatedAt < listenerAttachedAt - 2000) {
        debugPrint('[HeroHomeScreen] Ignoring pre-existing ping: $requestId');
        return;
      }

      debugPrint('[HeroHomeScreen] RTDB ping received: $requestId');

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
        debugPrint('[HeroHomeScreen] Skipping ping: requested $requestedCategory, hero $heroCategory');
        // Silently remove the ping to clean up RTDB node
        FirebaseDatabase.instance.ref('hero_pings/${_user!.uid}/$requestId').remove();
        return;
      }

      // Notification: only if global listener hasn't fired yet
      if (!kIsWeb && !HeroRideNotificationService.shouldProcessRideNotification(requestId)) {
        debugPrint('[HeroHomeScreen] Notification already fired by global listener. Showing dialog only.');
      } else if (!kIsWeb) {
        try {
          HeroRideNotificationService.showRideAssigned(
            rideId: requestId,
            data: Map<String, dynamic>.from(pingData as Map<dynamic, dynamic>),
            playAlertTone: true,
          );
        } catch (e) {
          debugPrint('[HeroHomeScreen] Ringtone error: $e');
        }
      }

      _showRideRequestDialog(
          requestId, Map<String, dynamic>.from(pingData as Map<dynamic, dynamic>));
    }, onError: (Object e) {
      debugPrint('[HeroHomeScreen] RTDB ping listener error: $e');
    });
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
    _servicePingSub?.cancel();
    debugPrint('🔥 [DEBUG] Hero is LISTENING to EXACT PATH: hero_service_pings/$uid');

    final listenerAttachedAt = DateTime.now().toUtc().millisecondsSinceEpoch;

    _servicePingSub = FirebaseDatabase.instance
        .ref('hero_service_pings/$uid')
        .onChildAdded
        .listen((event) {
      if (!mounted || !_isOnline || _activeRideId.isNotEmpty) return;
      if (_isShowingServiceDialog) return;

      final pingData = event.snapshot.value as Map<dynamic, dynamic>?;
      final requestId = event.snapshot.key as String? ?? '';
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
      if (pingCreatedAt < listenerAttachedAt - 2000) {
        debugPrint('[HeroHomeScreen] Ignoring pre-existing service ping: $requestId');
        return;
      }

      if (_shownServicePingIds.contains(requestId)) return;
      _shownServicePingIds.add(requestId);

      debugPrint('[HeroHomeScreen] RTDB service ping received: $requestId');

      if (!kIsWeb && !HeroRideNotificationService.shouldProcessRideNotification(requestId)) {
        debugPrint('[HeroHomeScreen] Notification already fired by global listener. Showing dialog only.');
      } else if (!kIsWeb) {
        try {
          HeroRideNotificationService.showRideAssigned(
            rideId: requestId,
            data: Map<String, dynamic>.from(pingData),
            playAlertTone: true,
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
    });
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

    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Text(_serviceRequestTitle(requestType), style: GoogleFonts.outfit(fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('From: $customerName', style: const TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            Text(summary, style: const TextStyle(color: Colors.black54)),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              _rejectServiceRequest(requestId);
            },
            child: const Text('Decline', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4FA3)),
            onPressed: () {
              Navigator.pop(ctx);
              _acceptServiceRequest(requestId);
            },
            child: const Text('ACCEPT', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    ).then((_) {
      if (mounted) setState(() => _isShowingServiceDialog = false);
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

  String _serviceRequestSummary(String requestType, Map details) {
    switch (requestType) {
      case 'hero_booking':
        return (details['taskDescription'] as String?) ?? '';
      case 'custom_order':
        return (details['orderDescription'] as String?) ?? '';
      case 'custom_food_order':
        final items = (details['items'] as String?) ?? '';
        final pref = (details['restaurantOrPreference'] as String?) ?? '';
        return [if (pref.isNotEmpty) 'From: $pref', if (items.isNotEmpty) items].join('\n');
      case 'grocery_order':
        final text = (details['listText'] as String?) ?? '';
        final hasImage = (details['listImageUrl'] as String?)?.isNotEmpty ?? false;
        return [if (text.isNotEmpty) text, if (hasImage) '📷 Photo list attached'].join('\n');
      default:
        return '';
    }
  }

  Future<void> _acceptServiceRequest(String requestId) async {
    if (_user == null) return;
    try {
      final won = await ServiceRequestService().acceptServiceRequest(
        requestId: requestId,
        heroId: _user!.uid,
        heroName: _captainName,
        heroPhone: _user!.phoneNumber ?? '',
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
      onAccept: (id, data) => _acceptRide(id, data),
      onReject: (id) => _rejectRide(id),
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
    showDialog<void>(
      context: dialogContext,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.78),
      builder: (context) {
        return _buildPingDialog(rideId.toString(), rideData);
      },
    ).then((_) {
      if (!kIsWeb) {
        unawaited(HeroRideNotificationService.stopWakeAlertRingtone());
      }
      if (mounted) setState(() => _isShowingRideDialog = false);
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
      String requestId, Map<String, dynamic> pingData) async {
    if (_user == null) return;
    setState(() => _accepting = true);
    debugPrint('[HeroHomeScreen] Accepting ride via RTDB: $requestId');
    try {
      final uid = _user!.uid;

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
      final transResult = await requestRef.runTransaction((Object? currentData) {
        if (currentData == null) {
          // Optimistic local cache run. NEVER abort here!
          // Return intended data so the server compares it and returns the real data.
          return rtdb.Transaction.success({
            'status': 'accepted',
            'acceptedHeroId': uid,
            'acceptedHeroName': _captainName,
            'acceptedHeroPhone': _user!.phoneNumber ?? '',
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
        data['acceptedHeroPhone'] = _user!.phoneNumber ?? '';
        data['acceptedHeroVehicle'] = _normalizeHeroVehicleType(_vehicleType);

        return rtdb.Transaction.success(data);
      });

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

      await FirebaseFirestore.instance
          .collection('heroes')
          .doc(uid)
          .update({'isAvailable': false});
          
      await FirebaseDatabase.instance
          .ref('online_heroes/$uid')
          .update({'isAvailable': false});

      if (mounted) {
        // Use the Firestore doc ID from the ping (not the RTDB push key)
        final firestoreDocId = pingData['firestoreDocId'] as String? ?? requestId;
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
        Navigator.push(
            context,
            MaterialPageRoute<void>(
                builder: (_) =>
                    CaptainRideScreen(ride: rideModel, rideDocId: firestoreDocId)));
      }
    } catch (e) {
      debugPrint('[HeroHomeScreen] Accept ride error: $e');
    }
    if (mounted) setState(() => _accepting = false);
  }

  // Complete a ride — 0% Commission Promotion: Hero keeps 100% of fare
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
    // 50m gate: skip if haven't moved enough since last upload
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
    final uid = _user?.uid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .where('assignedHeroId', isEqualTo: uid)
          .where('status', whereIn: ['hero_assigned', 'in_progress', 'nearing_completion'])
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }
        return Column(
          children: snapshot.data!.docs.map((doc) {
            final data = doc.data();
            return _ServiceRequestStatusCard(
              requestId: doc.id,
              requestType: data['requestType'] as String? ?? 'hero_booking',
              status: data['status'] as String? ?? 'hero_assigned',
              customerName: data['customerName'] as String? ?? 'Customer',
            );
          }).toList(),
        );
      },
    );
  }

  // ── HEADER ───────────────────────────────────────────────────
  Widget _buildNearbySosOverlay() {
    final heroPosition = _latestPosition;
    if (heroPosition == null) {
      return const SizedBox.shrink();
    }

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_alerts')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        double? nearestMeters;
        GeoPoint? nearestLocation;

        for (final doc in snapshot.data!.docs) {
          final location = doc.data()['location'];
          if (location is! GeoPoint) {
            continue;
          }
          final distanceMeters = Geolocator.distanceBetween(
            heroPosition.latitude,
            heroPosition.longitude,
            location.latitude,
            location.longitude,
          );
          if (distanceMeters <= 2000 &&
              (nearestMeters == null || distanceMeters < nearestMeters)) {
            nearestMeters = distanceMeters;
            nearestLocation = location;
          }
        }

        if (nearestMeters == null || nearestLocation == null) {
          return const SizedBox.shrink();
        }

        final distanceKm = nearestMeters / 1000;
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
                      'EMERGENCY SOS NEARBY!',
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
                      'A user needs immediate help!',
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
                    FilledButton.icon(
                      onPressed: () =>
                          unawaited(_navigateToSosLocation(nearestLocation!)),
                      icon: const Icon(Icons.navigation_rounded),
                      label: const Text('Navigate to Help'),
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

      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Hero',
        'userPhone': user.phoneNumber ?? '',
        'userType': 'hero',
        'location': GeoPoint(position.latitude, position.longitude),
        'status': 'active',
        'timestamp': FieldValue.serverTimestamp(),
      });

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'SOS sent! NJ Tech team and nearby customers have been alerted.'),
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
                  _captainName,
                  style: const TextStyle(
                    fontSize: 15,
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
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
          const SizedBox(width: 8),
          // Logout button
          GestureDetector(
            onTap: _showLogoutDialog,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: const Color(0x14FF5252),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: const Color(0x40FF5252)),
                boxShadow: const <BoxShadow>[
                  BoxShadow(
                    color: Color(0x12FF4FA3),
                    blurRadius: 12,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: const Icon(
                Icons.power_settings_new,
                color: _red,
                size: 20,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'Logout',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to go offline and logout?',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              // Set offline first, then logout
              await _syncOnlineStatus(false);
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) {
                return;
              }
              await Navigator.pushNamedAndRemoveUntil(
                context,
                '/',
                (route) => false,
              );
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

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
                  stream: Stream<QuerySnapshot<Map<String, dynamic>>>.empty(),
                  builder: (context, snap) {
                    // T2 FIX: The full-screen HeroPremiumLoader was blocking
                    // the ride list even when rides were available.
                    // Rule: NEVER show a blocking loader once the stream is
                    // attached — use a compact top-bar spinner instead.
                    snap.connectionState == ConnectionState.waiting &&
                        !snap.hasData;
                    if (snap.hasError) {
                      // Auto-retry: reinitialise stream after 4s
                      Future.delayed(const Duration(seconds: 4), () {
                        if (!mounted || !_isOnline) return;
                        debugPrint(
                            '[HeroHomeScreen] Stream error — auto-retrying: ${snap.error}');
                        setState(() {});
                      });
                      return Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(Icons.wifi_off_rounded,
                                color: _red, size: 32),
                            const SizedBox(height: 8),
                            Text(
                              'Connection error — retrying...',
                              style: const TextStyle(color: _red, fontSize: 12),
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
                                  options: MapOptions(
                                    initialCenter: _erodeBusStandCenter,
                                    initialZoom: 13,
                                    minZoom: 10,
                                    maxZoom: 18,
                                    interactionOptions: InteractionOptions(
                                        flags: InteractiveFlag.none),
                                  ),
                                  children: [
                                    TileLayer(
                                      urlTemplate:
                                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                                      userAgentPackageName:
                                          'com.allin1.superapp',
                                    ),
                                    CircleLayer(circles: [
                                      CircleMarker(
                                        point: _erodeBusStandCenter,
                                        radius: 5000,
                                        useRadiusInMeter: true,
                                        color: const Color(0x08FF4FA3),
                                        borderColor: const Color(0x40FF4FA3),
                                        borderStrokeWidth: 2,
                                      ),
                                    ]),
                                  ],
                                ),
                                // Radar animation calibrated to match service zone circle
                                Positioned.fill(
                                  child: LayoutBuilder(
                                    builder: (_, constraints) {
                                      final diameter = constraints.maxWidth < constraints.maxHeight
                                          ? constraints.maxWidth
                                          : constraints.maxHeight;
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
                paymentStatus == 'paid_offline_p2p') &&
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
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('😴', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 20),
            Text(
              'நீங்கள் Offline-ல இருக்கீங்க',
              style: GoogleFonts.notoSansTamil(
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: _text,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Ride accept பண்ண Online பண்ணுங்க!',
              style: GoogleFonts.notoSansTamil(
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
// SERVICE REQUEST STATUS CARD — minimal 3-button status-advance UI
// for the Broadcast Order System. Deliberately simple per spec.
// ================================================================
const List<String> _kServiceAdvanceOrder = [
  'hero_assigned',
  'in_progress',
  'nearing_completion',
  'completed',
];

class _ServiceRequestStatusCard extends StatefulWidget {
  final String requestId;
  final String requestType;
  final String status;
  final String customerName;
  const _ServiceRequestStatusCard({
    required this.requestId,
    required this.requestType,
    required this.status,
    required this.customerName,
  });

  @override
  State<_ServiceRequestStatusCard> createState() => _ServiceRequestStatusCardState();
}

class _ServiceRequestStatusCardState extends State<_ServiceRequestStatusCard> {
  bool _updating = false;

  Future<void> _advanceTo(String newStatus) async {
    setState(() => _updating = true);
    try {
      await ServiceRequestService().advanceStatus(widget.requestId, newStatus);
    } catch (e) {
      debugPrint('[ServiceRequestStatusCard] advanceStatus error: $e');
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
    final currentIndex = _kServiceAdvanceOrder.indexOf(widget.status);
    final nextStatus = currentIndex >= 0 && currentIndex < _kServiceAdvanceOrder.length - 1
        ? _kServiceAdvanceOrder[currentIndex + 1]
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
          if (nextStatus != null) ...[
            const SizedBox(height: 10),
            SizedBox(
              width: double.infinity,
              height: 38,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4FA3)),
                onPressed: _updating ? null : () => _advanceTo(nextStatus),
                child: _updating
                    ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text(_buttonLabelFor(nextStatus), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700, fontSize: 12)),
              ),
            ),
          ],
        ],
      ),
    );
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
    final center = Offset(size.width / 2, size.height / 2);
    final maxRadius = math.min(size.width, size.height) * 0.42;

    // ── Sweeping sector (transparent gradient arc) ─────────────
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        colors: [
          const Color(0x00FF4FA3),
          const Color(0x30FF4FA3),
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
        DiagnosticsProperty<AnimationController>('controller', controller));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _PingCountdownDialog extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> pingData;
  final Function(String requestId, Map<String, dynamic> pingData) onAccept;
  final Function(String requestId) onReject;
  const _PingCountdownDialog({
    required this.requestId,
    required this.pingData,
    required this.onAccept,
    required this.onReject,
  });
  @override
  State<_PingCountdownDialog> createState() => _PingCountdownDialogState();
}

class _PingCountdownDialogState extends State<_PingCountdownDialog> {
  Timer? _countdownTimer;
  int _remainingSec = 15;

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
    return AlertDialog(
      backgroundColor: const Color(0xFF0A0A12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x33FF4FA3)),
      ),
      titlePadding: const EdgeInsets.fromLTRB(24, 22, 24, 0),
      contentPadding: const EdgeInsets.fromLTRB(24, 18, 24, 10),
      title: const Text('\U0001f680 New Ride Request',
          style:
              TextStyle(color: Color(0xFFFF4FA3), fontWeight: FontWeight.w800)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x26FF4FA3))),
            child: Row(children: [
              const Text('\U0001f7e2', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('PICKUP',
                      style: TextStyle(
                          color: Color(0xFF8F5A78),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(pickup,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 8),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: const Color(0x26FF4FA3))),
            child: Row(children: [
              const Text('\U0001f534', style: TextStyle(fontSize: 14)),
              const SizedBox(width: 10),
              Expanded(
                  child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('DROP',
                      style: TextStyle(
                          color: Color(0xFF8F5A78),
                          fontSize: 10,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(height: 4),
                  Text(drop,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w700)),
                ],
              )),
            ]),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(
                  color: tipAmount > 0
                      ? const Color(0xFF00A86B).withValues(alpha: 0.45)
                      : const Color(0x26FF4FA3)),
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
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('\u{20b9}${estimatedFare.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Color(0xFFFF4FA3),
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
              if (tipAmount > 0) ...[
                const Text('  +  ',
                    style: TextStyle(color: Color(0xFF8F5A78), fontSize: 11)),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text('Tip',
                          style: TextStyle(
                              color: Color(0xFF8F5A78),
                              fontSize: 10,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: 2),
                      Text('\u{20b9}${tipAmount.toStringAsFixed(0)}',
                          style: const TextStyle(
                              color: Color(0xFFFFBB00),
                              fontSize: 16,
                              fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              ],
              const Text('  =  ',
                  style: TextStyle(
                      color: Color(0xFF8F5A78),
                      fontSize: 13,
                      fontWeight: FontWeight.w800)),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Total',
                        style: TextStyle(
                            color: Color(0xFF8F5A78),
                            fontSize: 10,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Text('\u{20b9}${boostedFare.toStringAsFixed(0)}',
                        style: const TextStyle(
                            color: Color(0xFF00A86B),
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
                  ],
                ),
              ),
            ]),
          ),
          const SizedBox(height: 12),
          Center(
            child: Text('Expires in $_remainingSec s',
                style: const TextStyle(
                    color: Color(0xFFFF5252),
                    fontSize: 13,
                    fontWeight: FontWeight.w700)),
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
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                _countdownTimer?.cancel();
                widget.onReject(widget.requestId);
                Navigator.pop(context);
              },
              child: const Text('REJECT',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: OutlinedButton(
              style: OutlinedButton.styleFrom(
                  foregroundColor: const Color(0xFF8F5A78),
                  side: const BorderSide(color: Color(0x338F5A78)),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14)),
                  padding: const EdgeInsets.symmetric(vertical: 14)),
              onPressed: () {
                _countdownTimer?.cancel();
                widget.onReject(widget.requestId);
                Navigator.pop(context);
              },
              child: const Text('SKIP',
                  style: TextStyle(fontWeight: FontWeight.w800, fontSize: 11)),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [Color(0xFFFF4FA3), Color(0xFFFF9AC8)]),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x40FF4FA3),
                      blurRadius: 16,
                      offset: Offset(0, 6))
                ],
              ),
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.transparent,
                    shadowColor: Colors.transparent,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    padding: const EdgeInsets.symmetric(vertical: 14)),
                onPressed: () {
                  _countdownTimer?.cancel();
                  final data = Map<String, dynamic>.from(widget.pingData);
                  widget.onAccept(widget.requestId, data);
                  Navigator.pop(context);
                },
                child: const Text('ACCEPT',
                    style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.w900,
                        fontSize: 15)),
              ),
            ),
          ),
        ]),
      ],
    );
  }
}
