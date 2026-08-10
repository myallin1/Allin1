import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../config/city_config.dart';
import '../../models/ride_model.dart';
import '../../services/city_service.dart';
import '../../utils/otp_utils.dart';
import '../../widgets/allin1_map_widget.dart';
import 'ride_tracking_screen.dart';

class RideSearchScreen extends StatefulWidget {
  final RideModel ride;
  final String? existingRideDocId;
  const RideSearchScreen({
    required this.ride,
    this.existingRideDocId,
    super.key,
  });

  @override
  State<RideSearchScreen> createState() => _RideSearchScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<RideModel>('ride', ride))
      ..add(StringProperty('existingRideDocId', existingRideDocId));
  }
}

class _RideSearchScreenState extends State<RideSearchScreen>
    with TickerProviderStateMixin {
  static const Color _bg = Colors.white;
  static const Color _card = Color(0xFFFFF7FB);
  static const Color _accent = Color(0xFFFF4FA3);
  static const Color _gold = Color(0xFFFF4FA3);
  static const Color _green = Color(0xFFFF4FA3);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _border = Color(0x33FF4FA3);

  late AnimationController _radarCtrl;
  late AnimationController _pulseCtrl;
  late AnimationController _foundCtrl;
  late Animation<double> _radarAnim;
  late Animation<double> _foundFadeAnim;
  late Animation<Offset> _foundSlideAnim;

  // NEW (audit fix — "customer phone not reaching Hero/Admin" bug):
  // cached so both _createRideInRTDB() and _finalizeRideToFirestore()
  // reuse one Firestore lookup instead of two.
  String? _resolvedCustomerPhone;

  bool _captainFound = false;
  bool _cancelled = false;
  bool _searchTimedOut = false;
  int _searchSeconds = 0;
  String _requestId = '';
  String _rideDocId = '';
  int _pingSeconds = 15;
  Timer? _pingCountdown;
  Timer? _countTimer;
  StreamSubscription<DatabaseEvent>? _rtdbRequestSub;
  StreamSubscription<DatabaseEvent>? _heroLocationSubscription;
  StreamSubscription<DatabaseEvent>? _nearbyHeroesSub;
  List<MapMarker> _nearbyMarkers = [];
  final MapController _acceptedMapController = MapController();
  bool _acceptedMapReady = false;
  bool _pendingAcceptedFit = false;
  String _rideStatus = 'searching';
  LatLng? _acceptedHeroLocation;

  String _captainName = '';
  String _captainBike = '';
  String _captainPhone = '';
  String _captainModel = '';
  double _captainRating = 0;
  final int _captainTrips = 0;
  int _captainEta = 5;
  String _rideOtp = '----';
  bool _heroAcceptedOverlayShown = false;
  int _selectedTipAmount = 0;
  String _assignedHeroId = '';
  static const int _searchTimeoutSeconds = 90;

  // RTDB matchmaking state
  List<Map<String, dynamic>> _heroesQueue = [];
  int _currentHeroIndex = 0;
  bool _isPinging = false;
  bool _rideFinalized = false;

  @override
  void initState() {
    super.initState();
    _initAnimations();
    final existingRideDocId = widget.existingRideDocId;
    if (existingRideDocId != null && existingRideDocId.trim().isNotEmpty) {
      _rideDocId = existingRideDocId.trim();
      _requestId = existingRideDocId.trim();
      _rideOtp = generateLocalOtp(_rideDocId);
    }
    _startRideCreation();
  }

  @override
  void dispose() {
    _radarCtrl.dispose();
    _pulseCtrl.dispose();
    _foundCtrl.dispose();
    _countTimer?.cancel();
    _pingCountdown?.cancel();
    _rtdbRequestSub?.cancel();
    _heroLocationSubscription?.cancel();
    _nearbyHeroesSub?.cancel();
    super.dispose();
  }

  // ================================================================
  // FIX #1: await _startSequentialPinging() — was fire-and-forget
  // Before: _startSequentialPinging() ← no await, loop ran instantly
  // After:  await _startSequentialPinging() ← properly sequential
  // ================================================================
  Future<void> _startRideCreation() async {
    // FIX (root cause, Aug 10 2026 — "Customer PWA books a bike ride,
    // it never reaches Hero at all, neither PWA nor native"): this
    // used to do a single synchronous `currentUser` null-check and
    // then immediately call `_fetchNearbyHeroes()`, which reads RTDB
    // `online_heroes` — a node that requires `auth != null` per
    // database.rules.json. bike_booking_screen.dart's own
    // `_listenToNearbyCaptains()` (see that file's detailed comment)
    // was already fixed for exactly this: on a fresh Customer PWA load,
    // Firebase Auth's session restore from IndexedDB is measurably
    // slower than native, so `currentUser` can still be non-null (the
    // uid is known) while the underlying RTDB auth token hasn't
    // finished propagating — or this screen can simply be reached
    // before restore finishes at all. `ride_search_screen.dart` was
    // never given that same fix, so a PWA customer's very first ride
    // request after a fresh page load could hit `online_heroes` before
    // auth was truly ready, get a silent permission-denied (swallowed
    // by `_fetchNearbyHeroes`'s catch block below, logged only via
    // debugPrint), and the whole broadcast never happened — the
    // customer just saw "no heroes found," not a real error, and Hero
    // never received anything to be silent about.
    //
    // Fix: wait for a real authStateChanges() event before proceeding,
    // same pattern as bike_booking_screen.dart, with a short timeout so
    // a genuinely signed-out customer isn't stuck waiting forever.
    var user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      try {
        user = await FirebaseAuth.instance
            .authStateChanges()
            .firstWhere((u) => u != null)
            .timeout(const Duration(seconds: 6));
      } catch (_) {
        user = null;
      }
    }
    if (user == null) {
      if (mounted) Navigator.pop(context);
      return;
    }
    debugPrint('🔥 [RIDE CREATION] About to fetch nearby heroes...');
    await _fetchNearbyHeroes();
    debugPrint('🔥 [RIDE CREATION] Awaited _fetchNearbyHeroes. Moving to next step...');
    if (_heroesQueue.isEmpty) {
      debugPrint('[RideSearch] No nearby heroes found within 3km');
      if (mounted) {
        setState(() => _searchTimedOut = true);
        if (_fetchNearbyHeroesError != null) {
          // FIX: previously a permission-denied/network error while
          // fetching heroes looked IDENTICAL to "genuinely nobody is
          // online" — both just silently landed on the same timeout
          // screen. Now surfaces the real error so it's diagnosable
          // instead of looking like "no heroes in the area."
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Could not search for heroes: $_fetchNearbyHeroesError'),
              backgroundColor: const Color(0xFFFF5252),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
      return;
    }
    await _createRideInRTDB(user);
    _startCountTimer();
    _listenToNearbyCaptains();
    _listenForAcceptance();
    debugPrint('🔥 [DEBUG-TRACE] About to call _startSequentialPinging()...');

    // TASK 2 (Aug 8 2026): sequential per-hero pinging replaced with a
    // single 5km simultaneous broadcast — see _startBroadcastPinging.
    await _startBroadcastPinging();
  }

  /// Must match the canonical keys used in hero registration:
  /// bike / auto / car / parcel / mini_truck / lorry / emergency_manpower
  String _normalizeCategoryKey(String vehicleType) {
    switch (vehicleType.trim().toLowerCase()) {
      case 'auto':
        return 'auto';
      case 'cab':
      case 'car':
      case 'mini':
        return 'car';
      case 'parcel':
        return 'parcel';
      case 'mini_truck':
      case 'mini-truck':
      case 'truck':
        return 'mini_truck';
      case 'lorry':
        return 'lorry';
      case 'emergency_manpower':
      case 'manpower':
        return 'emergency_manpower';
      case 'bike':
      default:
        return 'bike';
    }
  }

  String? _fetchNearbyHeroesError;

  Future<void> _fetchNearbyHeroes() async {
    _fetchNearbyHeroesError = null;
    try {
      final pickupLat = widget.ride.pickupLatitude ?? 11.3410;
      final pickupLng = widget.ride.pickupLongitude ?? 77.7172;
      print('[RideSearch] _fetchNearbyHeroes: pickup=$pickupLat,$pickupLng');

      // Multi-city (Plan 3): the 3km bounding box below already makes
      // cross-city matches practically impossible today (cities are far
      // apart), but as more cities share this same online_heroes RTDB
      // node, an explicit city check is the real safety net rather than
      // relying on geography alone. Defaults both sides to kDefaultCity
      // for any hero/customer that predates this field.
      final rideCity = await CityService.getCurrentCity();

      final onlineSnap = await FirebaseDatabase.instance
          .ref('online_heroes')
          .once();

      final onlineData = onlineSnap.snapshot.value as Map<dynamic, dynamic>?;
      if (onlineData == null || onlineData.isEmpty) {
        print('[RideSearch] No online heroes found in RTDB');
        _heroesQueue = [];
        return;
      }

      print('[RideSearch] RTDB returned ${onlineData.length} online hero entries');

      // TASK 2 (broadcast dispatch, Aug 8 2026): widened 3km -> 5km per
      // "fastest finger first" redesign — more heroes candidates now get
      // pinged simultaneously (see _startBroadcastPinging below), so the
      // wider net is intentional, not a leftover.
      const double rangeKm = 5;
      const double earthRadius = 6371;
      const double latDelta = rangeKm / earthRadius * (180.0 / pi);
      final double lngDelta = rangeKm / earthRadius * (180.0 / pi) /
          (pickupLat.abs() > 89.0 ? 1.0 : cos(pickupLat * pi / 180.0));

      final double minLat = pickupLat - latDelta;
      final double maxLat = pickupLat + latDelta;
      final double minLng = pickupLng - lngDelta;
      final double maxLng = pickupLng + lngDelta;

      final pickupLocation = LatLng(pickupLat, pickupLng);
      final List<Map<String, dynamic>> validHeroes = [];

      // ── FIX: compute the requested category ONCE, before the loop ──
      final requestedCategory =
          _normalizeCategoryKey(widget.ride.vehicleType ?? 'bike');
      debugPrint('🔥 [CATEGORY FILTER] Requested category: $requestedCategory');

      for (final entry in onlineData.entries) {
        final heroId = entry.key.toString();
        final data = entry.value as Map<dynamic, dynamic>?;
        if (data == null) {
          debugPrint('🔥 [REJECTED] Hero $heroId rejected because RTDB value is null');
          continue;
        }

        final heroLat = (data['lat'] as num?)?.toDouble() ??
            (data['latitude'] as num?)?.toDouble();
        final heroLng = (data['lng'] as num?)?.toDouble() ??
            (data['longitude'] as num?)?.toDouble();
        if (heroLat == null || heroLng == null) {
          debugPrint('🔥 [REJECTED] Hero $heroId rejected because lat/lng is null. data keys: ${data.keys}');
          continue;
        }

        if (heroLat < minLat || heroLat > maxLat || heroLng < minLng || heroLng > maxLng) {
          debugPrint('🔥 [REJECTED] Hero $heroId rejected by bounding box.');
          continue;
        }

        final isAvailable = data['isAvailable'] as bool?;
        if (isAvailable == false) {
          debugPrint('🔥 [REJECTED] Hero $heroId rejected because isAvailable=false');
          continue;
        }

        final heroCity = (data['city'] as String?)?.trim().toLowerCase().isNotEmpty ?? false
            ? (data['city'] as String).trim().toLowerCase()
            : kDefaultCity;
        if (heroCity != rideCity) {
          debugPrint('🔥 [REJECTED] Hero $heroId rejected: city mismatch (hero=$heroCity, ride=$rideCity)');
          continue;
        }

        final heroCategory =
            _normalizeCategoryKey((data['vehicleType'] as String?) ?? 'bike');

        // ── SMART MODE LOGIC: Parcel requests go to BOTH Parcel and Bike heroes ──
        bool categoryMatch = false;
        if (requestedCategory == 'parcel') {
          categoryMatch = heroCategory == 'parcel' || heroCategory == 'bike';
          if (categoryMatch && heroCategory == 'bike') {
            debugPrint('🔥 [SMART MODE] Hero $heroId matched via bike-fallback for parcel request');
          }
        } else {
          categoryMatch = (heroCategory == requestedCategory);
        }

        if (!categoryMatch) {
          debugPrint(
            '🔥 [REJECTED] Hero $heroId rejected: category mismatch '
            '(hero=$heroCategory, requested=$requestedCategory)',
          );
          continue;
        }

        final distance = _haversineDistance(pickupLocation, LatLng(heroLat, heroLng));
        print('[RideSearch] Hero $heroId: distance=${distance.toStringAsFixed(2)}km');
        validHeroes.add({
          'id': heroId,
          'distance': distance,
          'name': (data['name'] as String?) ?? 'Hero',
          'lat': heroLat,
          'lng': heroLng,
        });
      }

      print('[RideSearch] _fetchNearbyHeroes: sorted queue has ${validHeroes.length} heroes');
      validHeroes.sort((a, b) => (a['distance'] as num).compareTo(b['distance'] as num));
      _heroesQueue = validHeroes;
      debugPrint('[RideSearch] Found ${validHeroes.length} heroes within 3km');
    } catch (e) {
      debugPrint('🔥 [REJECTED] _fetchNearbyHeroes error: $e');
      _fetchNearbyHeroesError = e.toString();
      _heroesQueue = [];
    }
  }

  // FIX (audit: "customer avanga signup pannumbothu kudukura mobile
  // number namma hero/admin ku wire agi irukanum" — customer-reported
  // pipeline gap): this used to be `user.phoneNumber ?? user.email ??
  // ''` inline at both write sites below — FirebaseAuth's own
  // phoneNumber field is ONLY populated by actual phone-OTP auth, never
  // by the mobile number a Google-Sign-In customer types in at
  // customer_login_screen.dart's signup step (that number is written
  // to Firestore users/{uid}.phoneNumber, with .phone kept in sync).
  // So every Google-Sign-In customer's ride request carried an EMPTY
  // phone (or their email, which isn't a phone number at all) into
  // active_ride_requests (RTDB) and the rides Firestore doc — meaning
  // the Hero's "call customer" button and Admin's order-detail screen
  // both had nothing to call. Matches the same Firestore-first, Auth-
  // field-fallback pattern already used correctly elsewhere in this
  // app (bike_booking_screen.dart, ride_tracking_screen.dart).
  Future<String> _resolveCustomerPhone(User user) async {
    if (_resolvedCustomerPhone != null && _resolvedCustomerPhone!.isNotEmpty) {
      return _resolvedCustomerPhone!;
    }
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
      final data = doc.data();
      final phone = (data?['phoneNumber'] as String?)?.trim();
      final phoneAlt = (data?['phone'] as String?)?.trim();
      final resolved = (phone != null && phone.isNotEmpty)
          ? phone
          : (phoneAlt != null && phoneAlt.isNotEmpty ? phoneAlt : (user.phoneNumber ?? ''));
      _resolvedCustomerPhone = resolved;
      return resolved;
    } catch (_) {
      return user.phoneNumber ?? '';
    }
  }

  Future<void> _createRideInRTDB(User user) async {
    try {
      final customerPhone = await _resolveCustomerPhone(user);
      if (_rideDocId.isEmpty) {
        final firestoreRef = FirebaseFirestore.instance.collection('rides').doc();
        _rideDocId = firestoreRef.id;
        await firestoreRef.set({
          'status': 'searching',
          'customerId': user.uid,
          'category': _normalizeCategoryKey(widget.ride.vehicleType ?? 'bike'),
          'createdAt': FieldValue.serverTimestamp(),
        });
      }

      final ref = FirebaseDatabase.instance.ref('active_ride_requests').push();
      _requestId = ref.key!;
      await ref.set({
        'customerId': user.uid,
        'customerName': user.displayName ?? 'Customer',
        'customerPhone': customerPhone,
        'firestoreDocId': _rideDocId,
        'pickupAddress': widget.ride.pickupAddress ?? '',
        'dropAddress': widget.ride.dropAddress ?? '',
        'pickupLat': widget.ride.pickupLatitude ?? 11.3410,
        'pickupLng': widget.ride.pickupLongitude ?? 77.7172,
        'dropLat': widget.ride.dropLatitude ?? 11.3520,
        'dropLng': widget.ride.dropLongitude ?? 77.7280,
        'distanceKm': widget.ride.distanceKm ?? 0,
        'estimatedFare': widget.ride.estimatedFare ?? widget.ride.fare ?? 0,
        'tipAmount': 0,
        'status': 'pinging',
        'currentPingHeroId': '',
        'acceptedHeroId': '',
        'createdAt': ServerValue.timestamp,
      });
      debugPrint('[RideSearch] RTDB ride request created: $_requestId');
      if (mounted) {
        setState(() => _requestId = _requestId);
      }
    } catch (e) {
      debugPrint('[RideSearch] createRideInRTDB error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Booking failed: $e'), backgroundColor: const Color(0xFFFF5252)),
        );
      }
    }
  }

  // ================================================================
  // FIX #2: _startSequentialPinging — now Future<void> not void
  //
  // THE ROOT CAUSE WAS:
  //   void _startSequentialPinging() async { ... }
  //   called with: _startSequentialPinging()  ← no await
  //
  // Because there was no await in _startRideCreation, Dart started
  // the async loop and immediately returned. The 15 x Future.delayed(1s)
  // all yielded control at once — so the entire while loop ran through
  // all heroes in the same microtask queue tick before any 1-second
  // delay could block it. Result: all pings fired simultaneously.
  //
  // FIX: Changed to Future<void> + caller now awaits it.
  //      The loop now BLOCKS at each hero's 10s window before moving on.
  // ================================================================
  // ================================================================
  // TASK 2 (Aug 8 2026) — Broadcast dispatch ("fastest finger first")
  //
  // REPLACES the old one-hero-at-a-time _startSequentialPinging (each
  // hero got a private 15s window; slow if the nearest hero ignored
  // it). Now ALL heroes within 5km get pinged AT ONCE, for the full
  // 90s customer search window. First hero to tap Accept wins.
  //
  // Why this was a small patch, not a rewrite: hero_home_screen.dart's
  // _acceptRide() ALREADY does everything a broadcast model needs on
  // the winning side — an atomic RTDB runTransaction on
  // active_ride_requests/$requestId (only one hero's write can commit,
  // rtdb.Transaction.abort() for everyone else), followed by a sweep
  // that removes hero_pings/{everyOtherOnlineHero}/$requestId so their
  // Accept dialog auto-closes (_listenForHeroPings' onChildRemoved/
  // onValue drop fires when their own ping node disappears — that IS
  // the "auto-dismiss for losing heroes" mechanism, no separate
  // "already claimed" snackbar plumbing was needed since the dialog
  // just goes away). So this method only had to change WHO gets
  // pinged and WHEN — write to every hero's inbox in the same tick
  // instead of looping with a delay between each.
  // ================================================================
  Future<void> _startBroadcastPinging() async {
    debugPrint('🔥 [BROADCAST] _startBroadcastPinging started. Candidates: ${_heroesQueue.length}');
    if (_heroesQueue.isEmpty || _requestId.isEmpty) return;

    _isPinging = true;

    // Matches the customer-facing search timer (_searchTimeoutSeconds = 90).
    const int broadcastWindowSeconds = 90;
    final pingExpiresAt =
        DateTime.now().toUtc().millisecondsSinceEpoch + broadcastWindowSeconds * 1000;

    if (mounted) {
      setState(() {
        _assignedHeroId = '';
        _pingSeconds = broadcastWindowSeconds;
      });
    }

    // ── Step 1: mark the request as broadcasting (no single "current" hero) ──
    await FirebaseDatabase.instance
        .ref('active_ride_requests/$_requestId')
        .update({'currentPingHeroId': '', 'dispatchMode': 'broadcast'});

    // ── Step 2: write the SAME ping to every candidate hero's inbox, simultaneously ──
    final Map<String, dynamic> multiPathUpdate = {};
    for (final hero in _heroesQueue) {
      final heroId = hero['id'] as String;
      multiPathUpdate['hero_pings/$heroId/$_requestId'] = {
        'requestId': _requestId,
        'customerId': FirebaseAuth.instance.currentUser?.uid ?? '',
        'firestoreDocId': _rideDocId,
        'pickupAddress': widget.ride.pickupAddress ?? '',
        'dropAddress': widget.ride.dropAddress ?? '',
        'pickupLat': widget.ride.pickupLatitude ?? 11.3410,
        'pickupLng': widget.ride.pickupLongitude ?? 77.7172,
        'dropLat': widget.ride.dropLatitude ?? 11.3520,
        'dropLng': widget.ride.dropLongitude ?? 77.7280,
        'distanceKm': widget.ride.distanceKm ?? 0,
        'estimatedFare': widget.ride.estimatedFare ?? widget.ride.fare ?? 0,
        'tipAmount': _selectedTipAmount,
        'vehicleType': widget.ride.vehicleType ?? 'bike',
        'category': _normalizeCategoryKey(widget.ride.vehicleType ?? 'bike'),
        'pingExpiresAt': pingExpiresAt,
        'status': 'pinging',
      };
    }
    await FirebaseDatabase.instance.ref().update(multiPathUpdate);
    debugPrint('🔥 [BROADCAST] Ping broadcast to ${_heroesQueue.length} heroes — waiting up to ${broadcastWindowSeconds}s...');

    // ── Step 3: wait for the full window, checking every 1s for acceptance ──
    // (_rtdbRequestSub, already listening on active_ride_requests/$_requestId,
    // flips _rideFinalized/_captainFound the instant any hero's transaction
    // commits — see the acceptance handler further down this file.)
    for (int w = 0; w < broadcastWindowSeconds; w++) {
      await Future.delayed(const Duration(seconds: 1));

      if (_rideFinalized || _captainFound) {
        debugPrint('🔥 [BROADCAST] ✅ Ride finalized during wait at second $w — stopping');
        break;
      }
      if (_cancelled || !mounted) {
        debugPrint('🔥 [BROADCAST] ❌ Cancelled during wait at second $w — stopping');
        break;
      }
      if (mounted) {
        setState(() => _pingSeconds = broadcastWindowSeconds - w - 1);
      }
    }

    // ── Step 4: cleanup — remove any surviving ping nodes for this request ──
    // (the winning hero's _acceptRide already sweeps every OTHER online
    // hero's node; this is belt-and-suspenders for heroes who went
    // offline mid-broadcast and weren't in that sweep's online_heroes
    // snapshot, and for the plain-timeout/no-winner case below.)
    try {
      final Map<String, dynamic> cleanup = {};
      for (final hero in _heroesQueue) {
        cleanup['hero_pings/${hero['id']}/$_requestId'] = null;
      }
      await FirebaseDatabase.instance.ref().update(cleanup);
      debugPrint('🔥 [BROADCAST] Ping nodes cleared for all ${_heroesQueue.length} candidates');
    } catch (e) {
      debugPrint('🔥 [BROADCAST] Ping cleanup error: $e');
    }

    // ── Step 5: no one accepted within the window ──
    if (!_captainFound && !_cancelled && !_rideFinalized && mounted) {
      debugPrint('🔥 [BROADCAST] Window expired — no acceptance from ${_heroesQueue.length} heroes');

      if (_requestId.isNotEmpty) {
        try {
          await FirebaseDatabase.instance
              .ref('active_ride_requests/$_requestId')
              .update({'status': 'timeout'});
        } catch (e) {
          debugPrint('🔥 [BROADCAST] Timeout update error: $e');
        }
      }

      if (mounted) {
        setState(() {
          _searchTimedOut = true;
          _isPinging = false;
        });
      }
      _radarCtrl.stop();
      _countTimer?.cancel();
    }

    _isPinging = false;
    debugPrint('🔥 [BROADCAST] _startBroadcastPinging complete.');
  }

  void _listenForAcceptance() {
    if (_requestId.isEmpty) {
      debugPrint('❌ [CRITICAL ERROR] _listenForAcceptance failed because _requestId is empty!');
      return;
    }
    _rtdbRequestSub = FirebaseDatabase.instance
        .ref('active_ride_requests/$_requestId')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;

      final status = data['status'] as String? ?? '';
      final acceptedHeroId = data['acceptedHeroId'] as String? ?? '';

      if (status == 'accepted' && acceptedHeroId.isNotEmpty && !_rideFinalized) {
        debugPrint('🔥 [ACCEPTANCE] Hero $acceptedHeroId accepted the ride!');
        _rideFinalized = true;
        _countTimer?.cancel();
        _pingCountdown?.cancel();
        _radarCtrl.stop();
        _finalizeRideToFirestore(acceptedHeroId, data);
      }
    });
  }

  Future<void> _finalizeRideToFirestore(String acceptedHeroId, Map<dynamic, dynamic> requestData) async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) return;

      final heroName = requestData['acceptedHeroName'] as String? ?? 'Hero Rider';
      final heroPhone = requestData['acceptedHeroPhone'] as String? ?? '';
      final heroVehicle = requestData['acceptedHeroVehicle'] as String? ?? '';
      final customerPhone = await _resolveCustomerPhone(user);

      if (_rideDocId.isEmpty) {
        debugPrint('❌ [CRITICAL ERROR] _finalizeRideToFirestore called with empty _rideDocId — aborting!');
        return;
      }
      final docRef = FirebaseFirestore.instance.collection('rides').doc(_rideDocId);

      final rideData = {
        'pickupAddress': widget.ride.pickupAddress ?? '',
        'dropAddress': widget.ride.dropAddress ?? '',
        'distanceKm': widget.ride.distanceKm ?? 0,
        'fare': widget.ride.estimatedFare ?? 0,
        'estimatedFare': widget.ride.estimatedFare ?? widget.ride.fare ?? 0,
        'status': 'accepted',
        'customerId': user.uid,
        'customerPhone': customerPhone,
        'customerName': user.displayName ?? 'Customer',
        'heroId': acceptedHeroId,
        'heroName': heroName,
        'heroPhone': heroPhone,
        'heroVehicleNumber': heroVehicle,
        'tipAmount': _selectedTipAmount,
        'pickupLat': widget.ride.pickupLatitude ?? 11.3410,
        'pickupLng': widget.ride.pickupLongitude ?? 77.7172,
        'dropLat': widget.ride.dropLatitude ?? 11.3520,
        'dropLng': widget.ride.dropLongitude ?? 77.7280,
        'paymentStatus': 'pending',
        'acceptedAt': FieldValue.serverTimestamp(),
      };

      await docRef.update(rideData);

      final finalRideId = docRef.id;
      debugPrint('[RideSearch] Ride finalized in Firestore: $finalRideId');

      _foundCtrl.forward();
      if (mounted) {
        setState(() {
          _captainFound = true;
          _rideDocId = finalRideId;
          _captainName = heroName;
          _captainPhone = heroPhone;
          _captainBike = heroVehicle;
          _captainModel = 'Bike';
          _captainRating = 4.5;
          _captainEta = 5;
        });
      }
      _showHeroAcceptedOverlay();
      _startHeroLocationTracking(acceptedHeroId);
    } catch (e) {
      debugPrint('[RideSearch] finalizeRideToFirestore error: $e');
    }
  }

  void _startCountTimer() {
    _countTimer?.cancel();
    _countTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) {
        setState(() => _searchSeconds++);
        if (_searchSeconds >= _searchTimeoutSeconds && !_captainFound && !_searchTimedOut) {
          unawaited(_handleSearchTimeout());
        }
      }
    });
  }

  Future<void> _handleSearchTimeout() async {
    if (_captainFound || _cancelled || _searchTimedOut) return;
    _countTimer?.cancel();
    _radarCtrl.stop();
    if (_requestId.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('active_ride_requests/$_requestId')
          .update({'status': 'timeout'});
    }
    if (_assignedHeroId.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('hero_pings/$_assignedHeroId/$_requestId')
          .remove();
    }
    // T-3 FIX (audit 2026-08-07): mark the stub Firestore rides doc as
    // 'timeout' so it doesn't stay orphaned with status 'searching'.
    // Fire-and-forget — if this fails (network loss) it's non-critical;
    // never block or throw from the timeout path.
    if (_rideDocId.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('rides')
          .doc(_rideDocId)
          .update({'status': 'timeout', 'cancelledAt': FieldValue.serverTimestamp()})
          .catchError((Object e) {
        debugPrint('[RideSearch] Firestore ride timeout-cleanup failed (non-fatal): $e');
      });
    }
    if (mounted) {
      setState(() {
        _searchTimedOut = true;
        _rideStatus = 'cancelled_by_system';
      });
    }
  }


  Future<void> _cancelRide() async {
    setState(() => _cancelled = true);
    _countTimer?.cancel();
    _pingCountdown?.cancel();
    _rtdbRequestSub?.cancel();
    if (_requestId.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('active_ride_requests/$_requestId')
          .remove();
    }
    if (_assignedHeroId.isNotEmpty && _requestId.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('hero_pings/$_assignedHeroId/$_requestId')
          .remove();
    }
    // T-3 FIX (audit 2026-08-07): mark the stub Firestore rides doc as
    // 'cancelled' so it doesn't stay orphaned with status 'searching'.
    // Fire-and-forget — never block or throw from the cancel path.
    if (_rideDocId.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('rides')
          .doc(_rideDocId)
          .update({'status': 'cancelled', 'cancelledAt': FieldValue.serverTimestamp()})
          .catchError((Object e) {
        debugPrint('[RideSearch] Firestore ride cancel-cleanup failed (non-fatal): $e');
      });
    }
    if (mounted) Navigator.pop(context);
  }


  Future<void> _selectEncourageTip(int amount) async {
    setState(() => _selectedTipAmount = amount);
    if (_requestId.isNotEmpty) {
      await FirebaseDatabase.instance
          .ref('active_ride_requests/$_requestId')
          .update({'tipAmount': amount, 'tipUpdatedAt': ServerValue.timestamp});
    }
  }

  Future<void> _tryAgainSearch() async {
    // _isPinging is set true for the duration of _startSequentialPinging()
    // (see its start/end points below) — guard against a stray re-entrant
    // call (e.g. a fast double-tap) starting a second overlapping pinging
    // loop against the same _heroesQueue/_requestId state, which would
    // double-write to active_ride_requests/hero_pings.
    if (_isPinging) {
      return;
    }
    _pingCountdown?.cancel();
    _countTimer?.cancel();
    _heroAcceptedOverlayShown = false;
    _currentHeroIndex = 0;
    _rideFinalized = false;
    setState(() {
      _searchTimedOut = false;
      _cancelled = false;
      _captainFound = false;
      _searchSeconds = 0;
      _rideStatus = 'searching';
    });
    _radarCtrl.repeat();
    await _fetchNearbyHeroes();
    if (_heroesQueue.isNotEmpty) {
      _startCountTimer();
      _listenForAcceptance();
      // ✅ Listeners must start BEFORE the blocking await.
      // TASK 2: "Try Again" now fires a fresh 5km broadcast, per spec
      // item 6 ("simply fire a fresh broadcast to all nearby heroes").
      await _startBroadcastPinging();
    } else {
      setState(() => _searchTimedOut = true);
    }
  }

  void _listenToNearbyCaptains() {
    // Defense-in-depth alongside the bike_booking_screen.dart fix for the
    // same RTDB node: _startRideCreation() (the only caller) already
    // checks for a signed-in user before reaching this point, but an
    // onError handler costs nothing and means any future transient
    // permission hiccup degrades silently instead of crashing to the
    // Flutter framework the way an unhandled stream error does.
    _nearbyHeroesSub = FirebaseDatabase.instance
        .ref('online_heroes')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) {
        if (_nearbyMarkers.isNotEmpty) setState(() => _nearbyMarkers = []);
        return;
      }
      final List<MapMarker> newMarkers = [];
      data.forEach((key, value) {
        if (value is Map) {
          final lat = (value['lat'] as num?)?.toDouble();
          final lng = (value['lng'] as num?)?.toDouble();
          if (lat != null && lng != null) {
            newMarkers.add(MapMarker(
              point: LatLng(lat, lng),
              icon: Icons.electric_bike_rounded,
              label: (value['name'] as String?) ?? 'Hero',
            ),);
          }
        }
      });
      if (mounted) setState(() => _nearbyMarkers = newMarkers);
    }, onError: (Object error, StackTrace stack) {
      debugPrint(
        '[RideSearchScreen] online_heroes listener error (non-fatal): $error',
      );
    },);
  }

  double _haversineDistance(LatLng point1, LatLng point2) {
    const double earthRadius = 6371;
    final lat1Rad = point1.latitude * (pi / 180.0);
    final lat2Rad = point2.latitude * (pi / 180.0);
    final dLat = lat2Rad - lat1Rad;
    final dLng = (point2.longitude - point1.longitude) * (pi / 180.0);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1Rad) * cos(lat2Rad) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * asin(sqrt(a));
    return earthRadius * c;
  }

  void _initAnimations() {
    _radarCtrl = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat();
    _pulseCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _foundCtrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
    _radarAnim = Tween<double>(begin: 0, end: 1).animate(_radarCtrl);
    _foundFadeAnim = Tween<double>(begin: 0, end: 1)
        .animate(CurvedAnimation(parent: _foundCtrl, curve: Curves.easeOut));
    _foundSlideAnim = Tween<Offset>(
      begin: const Offset(0, 0.3),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _foundCtrl, curve: Curves.easeOutCubic));
  }

  void _showCancelledSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: const Color(0xFFE05555), behavior: SnackBarBehavior.floating),
    );
  }

  Widget _tipIncentiveSection() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [BoxShadow(color: Color(0x12FF4FA3), blurRadius: 24, offset: Offset(0, 12))],
      ),
      child: Column(
        children: [
          Text('Encourage Hero with a quick tip', style: GoogleFonts.outfit(fontSize: 15, color: _text, fontWeight: FontWeight.w800)),
          const SizedBox(height: 6),
          Text('Boost your request with a premium tip to get noticed faster.', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 11, color: _muted, fontWeight: FontWeight.w600)),
          const SizedBox(height: 14),
          Wrap(
            spacing: 10, runSpacing: 10, alignment: WrapAlignment.center,
            children: [10, 20, 30, 40, 50].map((amount) {
              final isSelected = _selectedTipAmount == amount;
              return GestureDetector(
                onTap: () => _selectEncourageTip(amount),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  width: 86,
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                  decoration: BoxDecoration(
                    gradient: isSelected
                        ? const LinearGradient(colors: [Color(0xFFFF4FA3), Color(0xFFFF8FC8)], begin: Alignment.topLeft, end: Alignment.bottomRight)
                        : const LinearGradient(colors: [Color(0xFFFFFFFF), Color(0xFFFFF3F9)], begin: Alignment.topLeft, end: Alignment.bottomRight),
                    borderRadius: BorderRadius.circular(22),
                    border: Border.all(color: isSelected ? _accent : _border.withValues(alpha: 0.8)),
                    boxShadow: isSelected
                        ? [BoxShadow(color: _accent.withValues(alpha: 0.28), blurRadius: 18, offset: const Offset(0, 10))]
                        : [const BoxShadow(color: Color(0x0DFF4FA3), blurRadius: 12, offset: Offset(0, 6))],
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('Tip', style: GoogleFonts.outfit(fontSize: 11, color: isSelected ? Colors.white70 : _muted, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text('Rs $amount', style: GoogleFonts.outfit(fontSize: 18, color: isSelected ? Colors.white : _text, fontWeight: FontWeight.w900)),
                    ],
                  ),
                ),
              );
            }).toList(),
          ),
          if (_selectedTipAmount > 0) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity, padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: const Color(0xFFFFF3F9), borderRadius: BorderRadius.circular(16), border: Border.all(color: _border)),
              child: Text('Tip added: Rs $_selectedTipAmount. Heroes will see the boosted fare.', textAlign: TextAlign.center, style: GoogleFonts.outfit(fontSize: 12, color: _muted, fontWeight: FontWeight.w700)),
            ),
          ],
        ],
      ),
    );
  }

  void _showHeroAcceptedOverlay() {
    if (!mounted || _heroAcceptedOverlayShown) return;
    _heroAcceptedOverlayShown = true;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        margin: EdgeInsets.fromLTRB(16, 18, 16, 0), behavior: SnackBarBehavior.floating,
        backgroundColor: Color(0xFFFF4FA3), duration: Duration(seconds: 3),
        content: Row(children: [Icon(Icons.verified_rounded, color: Colors.white), SizedBox(width: 10), Expanded(child: Text('Hero accepted', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w700)))]),
      ),
    );
  }

  void _startHeroLocationTracking(String heroId) {
    _heroLocationSubscription?.cancel();
    if (_rideDocId.isEmpty) return;
    _heroLocationSubscription = FirebaseDatabase.instance
        .ref('live_locations/$_rideDocId').onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      setState(() => _acceptedHeroLocation = LatLng(lat, lng));
      _fitAcceptedRideBounds();
    });
  }

  void _fitAcceptedRideBounds() {
    final hero = _acceptedHeroLocation;
    if (hero == null || !mounted) return;
    if (!_acceptedMapReady) { _pendingAcceptedFit = true; return; }
    final customer = LatLng(widget.ride.pickupLatitude ?? 11.3410, widget.ride.pickupLongitude ?? 77.7172);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        _acceptedMapController.fitCamera(CameraFit.bounds(bounds: LatLngBounds.fromPoints([customer, hero]), padding: const EdgeInsets.fromLTRB(44, 110, 44, 240)));
        _pendingAcceptedFit = false;
      } catch (e) {
        debugPrint('[RideSearchScreen] Map fit failed: $e');
      }
    });
  }

  void _handleAcceptedMapReady() {
    _acceptedMapReady = true;
    if (_pendingAcceptedFit) _fitAcceptedRideBounds();
  }

  Future<void> _callCaptain() async {
    final number = _captainPhone.isEmpty ? '+919597879191' : _captainPhone;
    if (await canLaunchUrl(Uri.parse('tel:$number'))) {
      await launchUrl(Uri.parse('tel:$number'));
    }
  }

  void _trackRide() {
    _heroLocationSubscription?.cancel();
    _nearbyHeroesSub?.cancel();
    _rtdbRequestSub?.cancel();
    final ride = widget.ride
      ..heroName = _captainName
      ..heroVehicleNumber = _captainBike
      ..heroPhone = _captainPhone
      ..heroRating = _captainRating
      ..status = 'arriving';
    Navigator.pushReplacement(
      context,
      PageRouteBuilder<void>(
        pageBuilder: (_, anim, __) => RideTrackingScreen(ride: ride, rideDocId: _rideDocId),
        transitionDuration: const Duration(milliseconds: 400),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: _captainFound ? _buildAcceptedRideScaffold() : _buildSearchingView(),
      ),
    );
  }

  Widget _buildSearchingView() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: Row(
            children: [
              const Text('Finding a Hero...', style: TextStyle(fontSize: 18, color: _text, fontWeight: FontWeight.w700)),
              const Spacer(),
              TextButton(onPressed: _cancelRide, child: const Text('Cancel', style: TextStyle(color: Color(0xFFFF5252)))),
            ],
          ),
        ),
        Expanded(
          flex: 2,
          child: Allin1MapWidget(
            center: LatLng(widget.ride.pickupLatitude ?? 11.3410, widget.ride.pickupLongitude ?? 77.7172),
            zoom: 13,
            markers: [
              MapMarker(point: LatLng(widget.ride.pickupLatitude ?? 11.3410, widget.ride.pickupLongitude ?? 77.7172), label: 'You'),
              ..._nearbyMarkers,
            ],
            interactive: false,
          ),
        ),
        Expanded(
          flex: 3,
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 24),
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const SizedBox(height: 20),
                  AnimatedBuilder(
                    animation: _radarAnim,
                    builder: (_, __) => SizedBox(
                      width: 140, height: 140,
                      child: Stack(
                        children: [
                          CustomPaint(
                            size: const Size(140, 140),
                            painter: _RadarPainter(_radarAnim.value),
                          ),
                          // Decorative-only vehicle icons — purely cosmetic,
                          // zero Firestore/RTDB reads. Does NOT touch
                          // _fetchNearbyHeroes()/_nearbyMarkers/live_locations
                          // or any real hero-matching/ping logic.
                          const Positioned.fill(
                            child: _DecorativeRadarVehicles(),
                          ),
                          Center(
                            child: Container(
                              width: 60, height: 60,
                              decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: _accent, width: 2),
                                boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.4), blurRadius: 16)],),
                              child: const Center(child: Text('🏍️', style: TextStyle(fontSize: 28))),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_searchTimedOut ? 'Heroes are busy now!' : 'Finding Nearby Hero', style: const TextStyle(fontSize: 18, color: _text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    _searchTimedOut
                        ? 'No Hero available right now. Try VIP Booking for immediate help.'
                        : 'Looking near Erode... (${_searchSeconds}s)',
                    style: const TextStyle(fontSize: 12, color: _muted),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  if (_searchTimedOut) ...[
                    // ── VIP Booking fallback ──
                    // No hero accepted after the sequential-ping queue was
                    // exhausted. Instead of a dead end, give the customer a
                    // direct line to the call center so admin can manually
                    // assign a hero (see admin_taxi_rides_screen.dart's
                    // "Assign Hero" action). _rtdbRequestSub is still alive
                    // at this point (only cancelled on accept/dispose), so
                    // when admin assigns a hero it flips
                    // active_ride_requests/$_requestId to accepted and this
                    // screen picks it up automatically via
                    // _listenForAcceptance -- same as a normal hero accept.
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 8),
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: _accent.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: _accent.withValues(alpha: 0.25)),
                      ),
                      child: Column(
                        children: [
                          const Text('⭐ VIP Booking', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w800, color: _accent)),
                          const SizedBox(height: 4),
                          const Text(
                            'Call center will assign a Hero for you right away.',
                            style: TextStyle(fontSize: 11.5, color: _muted),
                            textAlign: TextAlign.center,
                          ),
                          const SizedBox(height: 12),
                          Row(
                            children: [
                              Expanded(
                                child: ElevatedButton.icon(
                                  onPressed: () => launchUrl(Uri(scheme: 'tel', path: '8681869091')),
                                  icon: const Icon(Icons.call_rounded, size: 16),
                                  label: const Text('Call Now', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700)),
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: _accent, foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () => launchUrl(
                                    Uri.parse('https://wa.me/918681869091'),
                                    mode: LaunchMode.externalApplication,
                                  ),
                                  icon: const Icon(Icons.chat_rounded, size: 16, color: Color(0xFF25D366)),
                                  label: const Text('WhatsApp', style: TextStyle(fontSize: 13, fontWeight: FontWeight.w700, color: Color(0xFF25D366))),
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(color: Color(0xFF25D366), width: 1.5),
                                    padding: const EdgeInsets.symmetric(vertical: 12),
                                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 10),
                    TextButton(
                      onPressed: _tryAgainSearch,
                      child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
                    ),
                  ] else
                    _tipIncentiveSection(),
                  if (_requestId.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(color: const Color(0x1A00C853), borderRadius: BorderRadius.circular(20), border: Border.all(color: const Color(0x3300C853))),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(width: 6, height: 6, decoration: const BoxDecoration(color: _green, shape: BoxShape.circle)),
                          const SizedBox(width: 6),
                          const Text('Live', style: TextStyle(fontSize: 10, color: _green, fontWeight: FontWeight.w600)),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildAcceptedRideScaffold() {
    return FadeTransition(
      opacity: _foundFadeAnim,
      child: SlideTransition(
        position: _foundSlideAnim,
        child: Stack(
          children: [
            Positioned.fill(
              child: Allin1MapWidget(
                mapController: _acceptedMapController,
                onMapReady: _handleAcceptedMapReady,
                center: _acceptedHeroLocation ?? LatLng(widget.ride.pickupLatitude ?? 11.3410, widget.ride.pickupLongitude ?? 77.7172),
                zoom: 15,
                markers: _acceptedRideMarkers,
                interactive: false,
              ),
            ),
            Positioned(
              left: 16, right: 16, bottom: 20,
              child: _ActiveRideSheet(
                heroName: _captainName.isNotEmpty ? _captainName : 'Hero Rider',
                bikeModel: _captainModel.isNotEmpty ? _captainModel : 'Bike',
                vehicleNumber: _captainBike.isNotEmpty ? _captainBike : 'TN 00 AB 1234',
                etaMinutes: _captainEta,
                rating: _captainRating,
                rideOtp: _rideOtp,
                onCallHero: _callCaptain,
                onTrackRide: _trackRide,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<MapMarker> get _acceptedRideMarkers {
    final markers = <MapMarker>[
      MapMarker(point: LatLng(widget.ride.pickupLatitude ?? 11.3410, widget.ride.pickupLongitude ?? 77.7172), label: 'You'),
    ];
    if (_acceptedHeroLocation != null) {
      markers.add(MapMarker(point: _acceptedHeroLocation!, icon: Icons.electric_bike_rounded, label: _captainName));
    }
    return markers;
  }
}

// ── Helper Widgets ──────────────────────────────────────────────
class _ActiveRideSheet extends StatelessWidget {
  final String heroName;
  final String bikeModel;
  final String vehicleNumber;
  final int etaMinutes;
  final double rating;
  final String rideOtp;
  final VoidCallback onCallHero;
  final VoidCallback onTrackRide;

  const _ActiveRideSheet({
    required this.heroName, required this.bikeModel, required this.vehicleNumber,
    required this.etaMinutes, required this.rating, required this.rideOtp,
    required this.onCallHero, required this.onTrackRide,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.12), blurRadius: 30, offset: const Offset(0, 8))],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(color: const Color(0xFF1A1A2E), borderRadius: BorderRadius.circular(14)),
                child: const Icon(Icons.pedal_bike_rounded, color: Color(0xFFFF4FA3), size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(heroName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Color(0xFF3D1230))),
                    const SizedBox(height: 2),
                    Text('$bikeModel · $vehicleNumber', style: const TextStyle(fontSize: 12, color: Color(0xFF8F5A78))),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(color: const Color(0x1A00C853), borderRadius: BorderRadius.circular(20)),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.timer_rounded, size: 14, color: Color(0xFF00A86B)),
                    const SizedBox(width: 4),
                    Text('$etaMinutes min', style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: Color(0xFF00A86B))),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: onCallHero,
                  icon: const Icon(Icons.phone_rounded, size: 18),
                  label: const Text('Call'),
                  style: OutlinedButton.styleFrom(foregroundColor: const Color(0xFFFF4FA3),
                    side: const BorderSide(color: Color(0x33FF4FA3)), padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: onTrackRide,
                  icon: const Icon(Icons.navigation_rounded, size: 18),
                  label: const Text('Track'),
                  style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFFFF4FA3), foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    shadowColor: const Color(0x40FF4FA3), elevation: 8,),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('heroName', heroName));
    properties.add(StringProperty('bikeModel', bikeModel));
    properties.add(StringProperty('vehicleNumber', vehicleNumber));
    properties.add(IntProperty('etaMinutes', etaMinutes));
    properties.add(DoubleProperty('rating', rating));
    properties.add(StringProperty('rideOtp', rideOtp));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onCallHero', onCallHero));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTrackRide', onTrackRide));
  }
}

// ── Radar Painter ───────────────────────────────────────────────
class _RadarPainter extends CustomPainter {
  final double progress;
  _RadarPainter(this.progress);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2;
    final paint = Paint()..color = const Color(0x20FF4FA3)..style = PaintingStyle.fill;
    canvas.drawCircle(center, radius, paint);
    final sweepPaint = Paint()
      ..shader = const RadialGradient(
        colors: [Color(0x30FF4FA3), Color(0x00FF4FA3)],
        stops: [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, 2 * pi * progress, true, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => oldDelegate.progress != progress;
}

// ── Decorative Radar Vehicles ───────────────────────────────────
// Purely cosmetic layer for the "Finding a Hero" radar — zero
// Firestore/RTDB reads, entirely client-side hardcoded/randomized
// icons. Does NOT represent real hero positions or availability;
// the actual hero-matching pipeline (_fetchNearbyHeroes(),
// _nearbyMarkers, live_locations, ping/accept flow) is completely
// separate and untouched by this widget. Icons are biased toward 4
// fixed angular "zones" loosely standing in for well-known Erode
// landmarks (Erode Bus Stand, P.S. Park, Erode Junction, Nadarmedu)
// — this is purely visual clustering, not real geographic/LatLng
// mapping.
enum _DecorativeVehicleKind { bike, auto, car, miniTruck, lorry }

class _DecorativeVehicleSpec {
  const _DecorativeVehicleSpec({
    required this.kind,
    required this.baseAngle,
    required this.radiusFraction,
    required this.phase,
  });

  final _DecorativeVehicleKind kind;
  final double baseAngle;
  final double radiusFraction;
  final double phase;
}

class _DecorativeRadarVehicles extends StatefulWidget {
  const _DecorativeRadarVehicles();

  @override
  State<_DecorativeRadarVehicles> createState() =>
      _DecorativeRadarVehiclesState();
}

class _DecorativeRadarVehiclesState extends State<_DecorativeRadarVehicles>
    with SingleTickerProviderStateMixin {
  late final AnimationController _driftCtrl;
  late final List<_DecorativeVehicleSpec> _specs;

  // Roughly evenly spaced zone angles, one per landmark — visual
  // clustering only, no real coordinates involved.
  static const List<double> _zoneAngles = <double>[-pi / 2, 0, pi / 2, pi];
  static const int _vehicleCount = 12;

  @override
  void initState() {
    super.initState();
    _driftCtrl = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 6),
    )..repeat();
    _specs = _generateSpecs();
  }

  @override
  void dispose() {
    _driftCtrl.dispose();
    super.dispose();
  }

  List<_DecorativeVehicleSpec> _generateSpecs() {
    final rnd = Random();
    final specs = <_DecorativeVehicleSpec>[];
    for (var i = 0; i < _vehicleCount; i++) {
      final nearZone = rnd.nextDouble() < 0.7;
      final double angle;
      if (nearZone) {
        final zone = _zoneAngles[rnd.nextInt(_zoneAngles.length)];
        angle = zone + (rnd.nextDouble() - 0.5) * (pi / 3);
      } else {
        angle = rnd.nextDouble() * 2 * pi;
      }
      specs.add(_DecorativeVehicleSpec(
        kind: _pickKind(rnd),
        baseAngle: angle,
        radiusFraction: 0.35 + rnd.nextDouble() * 0.55,
        phase: rnd.nextDouble() * 2 * pi,
      ),);
    }
    return specs;
  }

  // Weighted toward bike, per spec — more bike icons should cluster
  // near the landmark zones than other vehicle types.
  _DecorativeVehicleKind _pickKind(Random rnd) {
    final r = rnd.nextDouble();
    if (r < 0.50) return _DecorativeVehicleKind.bike;
    if (r < 0.70) return _DecorativeVehicleKind.auto;
    if (r < 0.85) return _DecorativeVehicleKind.car;
    if (r < 0.95) return _DecorativeVehicleKind.miniTruck;
    return _DecorativeVehicleKind.lorry;
  }

  String _emoji(_DecorativeVehicleKind kind) {
    switch (kind) {
      case _DecorativeVehicleKind.bike:
        return '🏍️';
      case _DecorativeVehicleKind.auto:
        return '🛺';
      case _DecorativeVehicleKind.car:
        return '🚗';
      case _DecorativeVehicleKind.miniTruck:
        return '🚚';
      case _DecorativeVehicleKind.lorry:
        return '🚛';
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final diameter = constraints.maxWidth < constraints.maxHeight
            ? constraints.maxWidth
            : constraints.maxHeight;
        final center = diameter / 2;
        final maxRadius = diameter / 2;
        return AnimatedBuilder(
          animation: _driftCtrl,
          builder: (_, __) {
            return Stack(
              children: _specs.map((spec) {
                // Gentle sinusoidal drift so icons feel alive — purely
                // cosmetic, not tied to any real motion/location data.
                final drift = sin(_driftCtrl.value * 2 * pi + spec.phase);
                final radius = maxRadius * spec.radiusFraction + drift * 4;
                final angle = spec.baseAngle + drift * 0.05;
                final dx = center + radius * cos(angle);
                final dy = center + radius * sin(angle);
                return Positioned(
                  left: dx - 10,
                  top: dy - 10,
                  child: Opacity(
                    opacity: 0.55,
                    child: Text(
                      _emoji(spec.kind),
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                );
              }).toList(),
            );
          },
        );
      },
    );
  }
}