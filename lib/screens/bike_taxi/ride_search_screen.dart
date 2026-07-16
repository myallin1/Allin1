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

import '../../models/ride_model.dart';
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
  int _captainTrips = 0;
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
    final user = FirebaseAuth.instance.currentUser;
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
      }
      return;
    }
    await _createRideInRTDB(user);
    _startCountTimer();
    _listenToNearbyCaptains();
    _listenForAcceptance();
    debugPrint('🔥 [DEBUG-TRACE] About to call _startSequentialPinging()...');

    // ✅ FIX: await ensures the loop runs strictly sequentially
    // Without await, Dart fires the loop async and all pings go out
    // simultaneously because Future.delayed yields control immediately.
    await _startSequentialPinging();
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

  Future<void> _fetchNearbyHeroes() async {
    try {
      final pickupLat = widget.ride.pickupLatitude ?? 11.3410;
      final pickupLng = widget.ride.pickupLongitude ?? 77.7172;
      print('[RideSearch] _fetchNearbyHeroes: pickup=$pickupLat,$pickupLng');

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

      const double rangeKm = 3.0;
      const double earthRadius = 6371.0;
      final double latDelta = rangeKm / earthRadius * (180.0 / pi);
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

        final heroCategory =
            _normalizeCategoryKey((data['vehicleType'] as String?) ?? 'bike');

        // ── SMART MODE LOGIC: Parcel requests go to BOTH Parcel and Bike heroes ──
        bool categoryMatch = false;
        if (requestedCategory == 'parcel') {
          categoryMatch = (heroCategory == 'parcel' || heroCategory == 'bike');
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
      _heroesQueue = [];
    }
  }

  Future<void> _createRideInRTDB(User user) async {
    try {
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
        'customerPhone': user.phoneNumber ?? user.email ?? '',
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
  Future<void> _startSequentialPinging() async {
    debugPrint('🔥 [SEQUENTIAL] _startSequentialPinging started. Queue: ${_heroesQueue.length}');
    if (_heroesQueue.isEmpty || _requestId.isEmpty) return;

    _isPinging = true;
    _currentHeroIndex = 0;

    while (
      _currentHeroIndex < _heroesQueue.length &&
      !_captainFound &&
      !_cancelled &&
      !_rideFinalized &&
      mounted
    ) {
      final hero = _heroesQueue[_currentHeroIndex];
      final heroId = hero['id'] as String;

      debugPrint('🔥 [SEQUENTIAL] ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
      debugPrint('🔥 [SEQUENTIAL] Pinging hero #$_currentHeroIndex: $heroId');
      debugPrint('🔥 [SEQUENTIAL] Distance: ${(hero['distance'] as num).toStringAsFixed(2)}km');

      if (mounted) {
        setState(() {
          _assignedHeroId = heroId;
          _pingSeconds = 10;
        });
      }

      // ── Step 1: Tell RTDB who we're pinging right now ─────────
      await FirebaseDatabase.instance
          .ref('active_ride_requests/$_requestId')
          .update({'currentPingHeroId': heroId});

      // ── Step 2: Write ping to hero's inbox ────────────────────
      final pingExpiresAt = DateTime.now().toUtc().millisecondsSinceEpoch + 10000;
      await FirebaseDatabase.instance
          .ref('hero_pings/$heroId/$_requestId')
          .set({
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
      });

      debugPrint('🔥 [SEQUENTIAL] Ping sent to hero $heroId — waiting 10s...');

      // ── Step 3: Wait 10 seconds — check every 1s for acceptance ─
      // FIX: This loop now ACTUALLY BLOCKS because _startSequentialPinging
      // is awaited by _startRideCreation. Each 1-second delay is real.
      for (int w = 0; w < 10; w++) {
        await Future.delayed(const Duration(seconds: 1));

        // Early exit if ride was accepted/cancelled while waiting
        if (_rideFinalized || _captainFound) {
          debugPrint('🔥 [SEQUENTIAL] ✅ Ride finalized during wait at second $w — stopping loop');
          break;
        }
        if (_cancelled || !mounted) {
          debugPrint('🔥 [SEQUENTIAL] ❌ Cancelled during wait at second $w — stopping loop');
          break;
        }

        debugPrint('🔥 [SEQUENTIAL] Hero $heroId wait: ${w + 1}/10s');
      }

      // ── Step 4: Clean up ping regardless of outcome ───────────
      try {
        await FirebaseDatabase.instance
            .ref('hero_pings/$heroId/$_requestId')
            .remove();
        debugPrint('🔥 [SEQUENTIAL] Ping cleaned up for hero $heroId');
      } catch (e) {
        debugPrint('🔥 [SEQUENTIAL] Ping cleanup error: $e');
      }

      // ── Step 5: Check final state before moving to next hero ──
      if (_rideFinalized || _captainFound || _cancelled || !mounted) {
        debugPrint('🔥 [SEQUENTIAL] Loop exit — finalized=$_rideFinalized found=$_captainFound cancelled=$_cancelled');
        break;
      }

      // Hero did not respond — move to next
      debugPrint('🔥 [SEQUENTIAL] Hero $heroId timed out — moving to next hero');
      _currentHeroIndex++;
    }

    // ── Loop exhausted — no hero accepted ─────────────────────
    if (!_captainFound && !_cancelled && !_rideFinalized && mounted) {
      debugPrint('🔥 [SEQUENTIAL] All ${_heroesQueue.length} heroes pinged — no acceptance');

      // Mark RTDB request as timeout
      if (_requestId.isNotEmpty) {
        try {
          await FirebaseDatabase.instance
              .ref('active_ride_requests/$_requestId')
              .update({'status': 'timeout'});
        } catch (e) {
          debugPrint('🔥 [SEQUENTIAL] Timeout update error: $e');
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
    debugPrint('🔥 [SEQUENTIAL] _startSequentialPinging complete.');
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
        'customerPhone': user.phoneNumber ?? user.email ?? '',
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
      // ✅ Listeners must start BEFORE the blocking await
      await _startSequentialPinging();
    } else {
      setState(() => _searchTimedOut = true);
    }
  }

  void _listenToNearbyCaptains() {
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
            ));
          }
        }
      });
      if (mounted) setState(() => _nearbyMarkers = newMarkers);
    });
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
                      child: CustomPaint(
                        painter: _RadarPainter(_radarAnim.value),
                        child: Center(
                          child: Container(
                            width: 60, height: 60,
                            decoration: BoxDecoration(color: Colors.white, shape: BoxShape.circle, border: Border.all(color: _accent, width: 2),
                              boxShadow: [BoxShadow(color: _accent.withValues(alpha: 0.4), blurRadius: 16)]),
                            child: const Center(child: Text('🏍️', style: TextStyle(fontSize: 28))),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(_searchTimedOut ? 'No Heroes Available' : 'Finding Nearby Hero', style: TextStyle(fontSize: 18, color: _text, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(
                    _searchTimedOut
                        ? 'We could not find a Hero within 90 seconds.'
                        : 'Looking near Erode... (${_searchSeconds}s)',
                    style: const TextStyle(fontSize: 12, color: _muted),
                  ),
                  const SizedBox(height: 14),
                  if (_searchTimedOut)
                    ElevatedButton(
                      onPressed: _tryAgainSearch,
                      style: ElevatedButton.styleFrom(backgroundColor: _accent, foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16))),
                      child: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.w700)),
                    )
                  else
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
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14))),
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
                    shadowColor: const Color(0x40FF4FA3), elevation: 8),
                ),
              ),
            ],
          ),
        ],
      ),
    );
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
      ..shader = RadialGradient(
        colors: [const Color(0x30FF4FA3), const Color(0x00FF4FA3)],
        stops: [0.0, 1.0],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), -pi / 2, 2 * pi * progress, true, sweepPaint);
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => oldDelegate.progress != progress;
}