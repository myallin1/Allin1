// ================================================================
// RideTrackingScreen v2.0 — Real Firestore status listener & Local OTP
// ================================================================

import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/ride_model.dart';
import '../../widgets/allin1_map_widget.dart';
import '../payment_screen.dart';
import 'bike_booking_screen.dart';

class RideTrackingScreen extends StatefulWidget {
  final RideModel ride;
  final String rideDocId;
  const RideTrackingScreen({
    required this.ride,
    required this.rideDocId,
    super.key,
  });

  @override
  State<RideTrackingScreen> createState() => _RideTrackingScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<RideModel>('ride', ride))
      ..add(StringProperty('rideDocId', rideDocId));
  }
}

class _RideTrackingScreenState extends State<RideTrackingScreen>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const Color _page = Color(0xFFFFFBFE);
  static const Color _card = Colors.white;
  static const Color _cardTint = Color(0xFFFFF1F8);
  static const Color _green = Color(0xFF00A86B);
  static const Color _gold = Color(0xFFFF2F92);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _border = Color(0x33FF4FA3);

  bool get _isCargoRide {
    final type = (widget.ride.vehicleType ?? '').trim().toLowerCase();
    return type == 'lorry' || type == 'mini_truck';
  }

  String _rideStatus = 'arriving';
  bool _completed = false;
  String? _paymentStatus;
  double? _captainLat;
  double? _captainLng;
  double? _captainBearingDegrees;
  String? _captainName;
  String? _captainBike;
  String? _captainPhone;
  String? _captainVehicleType;
  String? _trackedHeroId;
  String _rideOtp = '----';
  String? _phoneLookupHeroId;

  double? _lockedFare;
  double? _finalFare;
  double? _actualFare;
  double? _tipAmount;
  double? _remainingDistanceKm;
  int? _remainingEtaMinutes;

  // RTDB live GPS tracking (Zero-Read Rule)
  StreamSubscription<DatabaseEvent>? _captainLocationSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _rideDocSubscription;
  final MapController _trackingMapController = MapController();
  bool _trackingMapReady = false;
  bool _pendingTrackingFit = false;
  LatLng? _pendingTrackingMove;
  double? _pendingTrackingZoom;

  // Smooth animation for hero marker
  AnimationController? _moveAnimCtrl;

  // Route polyline for showing path between customer and captain
  List<LatLng> _routePoints = [];
  bool _handledPaidFlow = false;
  bool _hasNavigatedToPayment = false;
  bool _liveLocationCleanedUp = false;
  String? _selectedPaymentMethod;
  bool _isRideLoading = true;
  String? _rideErrorMessage;
  DateTime? _lastRouteDrawAt;

  // ─── LOCAL DETERMINISTIC OTP GENERATOR (NO DB REQUIRED) ───
  String _generateLocalOtp(String docId) {
    final cleanId = docId.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanId.isEmpty) return '1234';
    final hash = cleanId.hashCode.abs();
    return (1000 + (hash % 9000)).toString(); // Generates 1000-9999
  }
  // ──────────────────────────────────────────────────────────

  void _returnToRootSafely() {
    if (!mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  bool get _isPaymentSettled {
    final status = _paymentStatus?.trim() ?? '';
    // Added 'settled' and 'confirmed' to sync with Hero and Admin app updates
    return ['completed', 'paid', 'paid_by_wallet', 'paid_offline_p2p', 'settled', 'confirmed'].contains(status);
  }

  LatLng? _pickupTarget() {
    if (widget.ride.pickupLatitude == null ||
        widget.ride.pickupLongitude == null) {
      return null;
    }
    return LatLng(widget.ride.pickupLatitude!, widget.ride.pickupLongitude!);
  }

  LatLng? _routeTargetForStatus() {
    if (_rideStatus == 'in_progress' || _rideStatus == 'started') {
      if (widget.ride.dropLatitude != null &&
          widget.ride.dropLongitude != null) {
        return LatLng(widget.ride.dropLatitude!, widget.ride.dropLongitude!);
      }
      return null;
    }
    if (widget.ride.pickupLatitude != null &&
        widget.ride.pickupLongitude != null) {
      return LatLng(widget.ride.pickupLatitude!, widget.ride.pickupLongitude!);
    }
    return null;
  }

  ({double lat, double lng})? _extractHeroCoordinates(
      Map<String, dynamic> data,) {
    final rawLoc = data['currentLocation'];
    if (rawLoc is Map) {
      final loc = Map<String, dynamic>.from(rawLoc);
      final nestedLat = (loc['latitude'] ??
          loc['lat'] ??
          data['latitude'] ??
          data['lat']) as num?;
      final nestedLng = (loc['longitude'] ??
          loc['lng'] ??
          data['longitude'] ??
          data['lng']) as num?;
      if (nestedLat != null && nestedLng != null) {
        return (lat: nestedLat.toDouble(), lng: nestedLng.toDouble());
      }
    }

    final flatLat = (data['captainLat'] ??
        data['heroLat'] ??
        data['latitude'] ??
        data['lat']) as num?;
    final flatLng = (data['captainLng'] ??
        data['heroLng'] ??
        data['longitude'] ??
        data['lng']) as num?;
    if (flatLat == null || flatLng == null) {
      return null;
    }
    return (lat: flatLat.toDouble(), lng: flatLng.toDouble());
  }

  String _normalizeHeroVehicleType(String? value) {
    final normalized = value?.trim().toLowerCase() ?? '';
    if (normalized.contains('auto')) return 'auto';
    if (normalized.contains('car') ||
        normalized.contains('cab') ||
        normalized.contains('truck')) {
      return 'car';
    }
    return 'bike';
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

  void _refreshTrackingMetrics(double heroLat, double heroLng) {
    final target = _routeTargetForStatus() ?? _pickupTarget();
    if (target == null) {
      return;
    }
    final meters = Geolocator.distanceBetween(
      heroLat,
      heroLng,
      target.latitude,
      target.longitude,
    );
    final distanceKm = meters / 1000;
    final etaMinutes = (meters / 250).ceil().clamp(1, 90);
    _remainingDistanceKm = distanceKm;
    _remainingEtaMinutes = etaMinutes;
  }

  void _fitTrackingCamera() {
    final pickup = _pickupTarget();
    if (pickup == null || _captainLat == null || _captainLng == null) {
      return;
    }
    if (!_trackingMapReady) {
      _pendingTrackingFit = true;
      debugPrint('[RideTrackingScreen] Tracking camera fit queued until ready');
      return;
    }
    final bounds = LatLngBounds.fromPoints([
      pickup,
      LatLng(_captainLat!, _captainLng!),
    ]);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) {
        return;
      }
      try {
        _trackingMapController.fitCamera(
          CameraFit.bounds(
            bounds: bounds,
            padding: const EdgeInsets.all(48),
          ),
        );
        _pendingTrackingFit = false;
      } catch (e) {
        debugPrint('[RideTrackingScreen] Tracking camera fit failed: $e');
      }
    });
  }

  void _moveTrackingMap(LatLng center, double zoom) {
    _pendingTrackingMove = center;
    _pendingTrackingZoom = zoom;
    if (!_trackingMapReady) {
      debugPrint('[RideTrackingScreen] Tracking map move queued until ready');
      return;
    }
    try {
      _trackingMapController.move(center, zoom);
      _pendingTrackingMove = null;
      _pendingTrackingZoom = null;
    } catch (e) {
      debugPrint('[RideTrackingScreen] Tracking map move failed: $e');
    }
  }

  void _handleTrackingMapReady() {
    _trackingMapReady = true;
    if (_pendingTrackingFit) {
      _fitTrackingCamera();
      return;
    }
    final center = _pendingTrackingMove;
    if (center != null) {
      _moveTrackingMap(center, _pendingTrackingZoom ?? 15);
    }
  }

  void _applyHeroLocationUpdate(
    double heroLat,
    double heroLng, {
    String? vehicleType,
    double? headingDegrees,
  }) {
    if (!mounted) {
      return;
    }
    final previous = _captainLat != null && _captainLng != null
        ? LatLng(_captainLat!, _captainLng!)
        : null;
    final current = LatLng(heroLat, heroLng);
    final resolvedBearing = _validHeading(headingDegrees) ??
        (previous != null ? _bearingBetween(previous, current) : null) ??
        _captainBearingDegrees;
    final normalizedVehicle = vehicleType != null && vehicleType.isNotEmpty
        ? _normalizeHeroVehicleType(vehicleType)
        : null;

    _animateCaptainMarkerTo(
      target: current,
      bearingDegrees: resolvedBearing,
      vehicleType: normalizedVehicle,
    );
    _refreshTrackingMetrics(heroLat, heroLng);

    final target = _routeTargetForStatus();
    final now = DateTime.now();
    if (target != null &&
        (_lastRouteDrawAt == null ||
         now.difference(_lastRouteDrawAt!).inSeconds >= 30)) {
      _lastRouteDrawAt = now;
      unawaited(
        _drawRoute(
          heroLat,
          heroLng,
          target.latitude,
          target.longitude,
        ),
      );
    }
    _fitTrackingCamera();
  }

  double? _validHeading(double? heading) {
    if (heading == null || heading.isNaN || heading < 0) {
      return null;
    }
    return heading % 360;
  }

  void _animateCaptainMarkerTo({
    required LatLng target,
    double? bearingDegrees,
    String? vehicleType,
  }) {
    final start = _captainLat != null && _captainLng != null
        ? LatLng(_captainLat!, _captainLng!)
        : null;

    _disposeMoveAnimation();

    if (start == null) {
      setState(() {
        _captainLat = target.latitude;
        _captainLng = target.longitude;
        _captainBearingDegrees = bearingDegrees;
        if (vehicleType != null && vehicleType.isNotEmpty) {
          _captainVehicleType = vehicleType;
        }
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
        _captainLat = target.latitude;
        _captainLng = target.longitude;
        _captainBearingDegrees = bearingDegrees;
        if (vehicleType != null && vehicleType.isNotEmpty) {
          _captainVehicleType = vehicleType;
        }
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
    _moveAnimCtrl = controller;

    controller.addListener(() {
      if (!mounted || _moveAnimCtrl != controller) {
        return;
      }
      final t = curved.value;
      setState(() {
        _captainLat = start.latitude + ((target.latitude - start.latitude) * t);
        _captainLng =
            start.longitude + ((target.longitude - start.longitude) * t);
        _captainBearingDegrees = bearingDegrees;
        if (vehicleType != null && vehicleType.isNotEmpty) {
          _captainVehicleType = vehicleType;
        }
      });
    });
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed ||
          !mounted ||
          _moveAnimCtrl != controller) {
        return;
      }
      setState(() {
        _captainLat = target.latitude;
        _captainLng = target.longitude;
        _captainBearingDegrees = bearingDegrees;
        if (vehicleType != null && vehicleType.isNotEmpty) {
          _captainVehicleType = vehicleType;
        }
      });
      _moveAnimCtrl = null;
      controller.dispose();
    });
    controller.forward();
  }

  Future<void> _handlePaidClosure() async {
    if (!mounted || _handledPaidFlow) {
      return;
    }
    _handledPaidFlow = true;
    if (!mounted) return;
    final rating = await showDialog<int>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => _HeroRatingSheet(),
    );
    final heroId = widget.ride.heroId;
    if (rating != null && rating > 0) {
      try {
        await FirebaseFirestore.instance
            .collection('rides')
            .doc(widget.rideDocId)
            .update({
          'customerRating': rating,
          'ratedAt': FieldValue.serverTimestamp(),
        });
        if (heroId != null && heroId.isNotEmpty) {
          final ridesSnap = await FirebaseFirestore.instance
              .collection('rides')
              .where('heroId', isEqualTo: heroId)
              .where('customerRating', isGreaterThan: 0)
              .get();
          final avg = ridesSnap.docs.fold<double>(0, (s, d) {
                final r = (d.data()['customerRating'] as num?)?.toDouble() ?? 0;
                return s + r;
              }) /
              (ridesSnap.docs.isNotEmpty ? ridesSnap.docs.length : 1);
          await FirebaseFirestore.instance
              .collection('heroes')
              .doc(heroId)
              .set({'heroRating': avg}, SetOptions(merge: true));
        }
      } catch (e) {
        debugPrint('[Rating] Save failed: $e');
      }
    }
    if (!mounted) return;
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute<void>(builder: (_) => const BikeBookingScreen()),
      (route) => false,
    );
  }

  Future<void> _navigateToPayment() async {
    if (!mounted || _hasNavigatedToPayment) {
      return;
    }
    _hasNavigatedToPayment = true;
    final tip = _tipAmount ?? 0;
    final baseToCharge = _lockedFare ??
        widget.ride.estimatedFare?.toDouble() ??
        _calculateFareFromDistance(widget.ride.distanceKm ?? 0);
    final amount = baseToCharge + tip;
    try {
      await Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(
          builder: (_) => PaymentScreen(
            amount: amount,
            note: 'Bike Taxi Ride',
            rideDocId: widget.rideDocId,
          ),
        ),
      );
    } catch (e) {
      _hasNavigatedToPayment = false;
      debugPrint('[RideTrackingScreen] Payment navigation failed: $e');
    }
  }

  Future<void> _selectPaymentMethod(String method) async {
    try {
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideDocId)
          .set({
        'preferredPaymentMethod': method,
        'paymentStatus': 'awaiting_confirmation',
      }, SetOptions(merge: true),);
      if (!mounted) {
        return;
      }
      setState(() => _selectedPaymentMethod = method);
      final methodLabel = method == 'upi'
          ? 'Open your UPI app and pay the hero'
          : method == 'wallet'
              ? 'Wallet selected. Complete payment and wait for hero confirmation.'
              : 'Pay cash to the hero and wait for confirmation.';
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(methodLabel),
          backgroundColor: _gold,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      debugPrint('Payment intent update failed: $e');
    }
  }

  Future<void> _openGenericUpi() async {
    await _selectPaymentMethod('upi');
    const candidateUris = <String>[
      'upi://pay',
      'upi://',
    ];

    for (final candidate in candidateUris) {
      final uri = Uri.parse(candidate);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
        return;
      }
    }

    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('No UPI apps installed.'),
        backgroundColor: Color(0xFFFF5252),
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    
    // ✅ Set local OTP immediately upon screen load
    _rideOtp = _generateLocalOtp(widget.rideDocId); 
    
    _rideStatus = widget.ride.status ?? _rideStatus;
    _captainName = widget.ride.heroName;
    _captainBike = widget.ride.heroVehicleNumber;
    _captainPhone = widget.ride.heroPhone;
    _lockedFare = widget.ride.fare?.toDouble();
    if (widget.ride.fare == null) {
      _finalFare = widget.ride.estimatedFare?.toDouble();
    }
    _bindRideDocument();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[RideTrackingScreen] App resumed');
      if (!mounted) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        try {
          if (_captainLat != null && _captainLng != null) {
            _fitTrackingCamera();
          } else {
            final pickup = _pickupTarget();
            if (pickup != null) {
              _moveTrackingMap(pickup, 15);
            }
          }
        } catch (e) {
          debugPrint('[RideTrackingScreen] Tracking map refresh failed: $e');
        }
      });
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.inactive) {
      debugPrint(
          '[RideTrackingScreen] App paused/inactive',);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _rideDocSubscription?.cancel();
    _captainLocationSub?.cancel();
    _disposeMoveAnimation();
    super.dispose();
  }

  void _disposeMoveAnimation() {
    final controller = _moveAnimCtrl;
    _moveAnimCtrl = null;
    controller?.stop();
    controller?.dispose();
  }

  Future<void> _cleanupLiveLocationNode() async {
    if (_liveLocationCleanedUp || widget.rideDocId.isEmpty) {
      return;
    }
    _liveLocationCleanedUp = true;
    try {
      await FirebaseDatabase.instance
          .ref('live_locations/${widget.rideDocId}')
          .remove();
      await _captainLocationSub?.cancel();
      _captainLocationSub = null;
      debugPrint(
        '[RideTrackingScreen] Removed RTDB live location for ${widget.rideDocId}',
      );
    } catch (e) {
      debugPrint('[RideTrackingScreen] Live location cleanup failed: $e');
    }
  }



  void _bindRideDocument() {
    if (widget.rideDocId.isEmpty) {
      _isRideLoading = false;
      return;
    }
    _rideDocSubscription?.cancel();
    _rideDocSubscription = FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.rideDocId)
        .snapshots()
        .listen(
      _handleRideDocument,
      onError: (Object error) {
        if (!mounted) {
          return;
        }
        setState(() {
          _rideErrorMessage =
              'Unable to track ride. Please check your connection.';
          _isRideLoading = false;
        });
      },
    );
  }

  Future<void> _hydrateCaptainPhone(String heroId) async {
    if (!mounted || heroId.isEmpty || _phoneLookupHeroId == heroId) {
      return;
    }
    _phoneLookupHeroId = heroId;
    try {
      final heroSnap = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(heroId)
          .get();
      String? phone =
          (heroSnap.data()?['phoneNumber'] as String?)?.trim().isNotEmpty ?? false
              ? (heroSnap.data()!['phoneNumber'] as String).trim()
              : (heroSnap.data()?['phone'] as String?)?.trim();

      if (phone == null || phone.isEmpty) {
        final userSnap = await FirebaseFirestore.instance
            .collection('users')
            .doc(heroId)
            .get();
        phone =
            (userSnap.data()?['phoneNumber'] as String?)?.trim().isNotEmpty ?? false
                ? (userSnap.data()!['phoneNumber'] as String).trim()
                : (userSnap.data()?['phone'] as String?)?.trim();
      }

      if (!mounted || phone == null || phone.isEmpty) {
        return;
      }

      setState(() {
        _captainPhone = phone;
      });
    } catch (e) {
      debugPrint('[RideTrackingScreen] Hero phone lookup failed: $e');
    }
  }

  Future<void> _callHero() async {
    final phone = (_captainPhone ?? widget.ride.heroPhone ?? '').trim();
    if (phone.isEmpty) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Hero phone number not available yet.'),
          backgroundColor: Color(0xFFFF5252),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    final uri = Uri.parse('tel://$phone');
    final launched = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the dialer right now.'),
          backgroundColor: Color(0xFFFF5252),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _handleRideDocument(DocumentSnapshot<Map<String, dynamic>> snap) {
    if (!mounted) {
      return;
    }
    if (!snap.exists) {
      setState(() {
        _rideErrorMessage = 'Ride not found or already closed.';
        _isRideLoading = false;
      });
      return;
    }

    final data = snap.data();
    if (data == null) {
      setState(() {
        _rideErrorMessage = 'Ride data unavailable.';
        _isRideLoading = false;
      });
      return;
    }

    final currentCustomerUid = FirebaseAuth.instance.currentUser?.uid;
    final rideCustomerId = (data['customerId'] as String?)?.trim();
    if (currentCustomerUid == null || rideCustomerId != currentCustomerUid) {
      _rideDocSubscription?.cancel();
      _captainLocationSub?.cancel();
      setState(() {
        _rideErrorMessage = 'This ride is not linked to your account.';
        _isRideLoading = false;
      });
      return;
    }

    final nextStatus = data['status'] as String? ?? 'arriving';
    final nextPaymentStatus = data['paymentStatus'] as String?;
    final nextLockedFare = (data['lockedFare'] as num?)?.toDouble();
    final nextFinalFare = (data['finalFare'] as num?)?.toDouble();
    final nextActualFare = (data['actualFare'] as num?)?.toDouble();
    final nextTipAmount = (data['tipAmount'] as num?)?.toDouble();
    final nextCaptainName =
        data['heroName'] as String? ?? data['captainName'] as String?;
    final nextCaptainBike =
        data['heroVehicleNumber'] as String? ?? data['captainBike'] as String?;
    final nextCaptainPhone =
        data['heroPhone'] as String? ?? data['captainPhone'] as String?;
    final nextCaptainVehicleType = _normalizeHeroVehicleType(
      (data['heroVehicleType'] ??
              data['captainVehicleType'] ??
              data['vehicleType'] ??
              widget.ride.vehicleType)
          ?.toString(),
    );
    
    // ✅ Always use local deterministic OTP based on rideDocId
    final nextRideOtp = _generateLocalOtp(widget.rideDocId); 
    
    final nextCaptainLat = ((data['captainLat'] ??
            data['heroLat'] ??
            data['latitude'] ??
            data['lat']) as num?)
        ?.toDouble();
    final nextCaptainLng = ((data['captainLng'] ??
            data['heroLng'] ??
            data['longitude'] ??
            data['lng']) as num?)
        ?.toDouble();
    final heroId = data['heroId'] as String? ?? data['captainId'] as String?;
    final shouldNavigateToPayment =
        nextStatus == 'completed' && !_hasNavigatedToPayment;
    final shouldHandlePaid = !_handledPaidFlow &&
        (nextPaymentStatus == 'paid' ||
            nextPaymentStatus == 'completed' ||
            nextPaymentStatus == 'settled' ||
            nextPaymentStatus == 'paid_by_wallet' ||
            nextPaymentStatus == 'paid_offline_p2p');
    final shouldCleanupLiveLocation =
        nextStatus == 'completed' || nextStatus.startsWith('cancelled');

    if (shouldCleanupLiveLocation) {
      unawaited(_cleanupLiveLocationNode());
    } else if (heroId != null && heroId.isNotEmpty) {
      _startCaptainLocationTracking(heroId);
      if ((nextCaptainPhone == null || nextCaptainPhone.trim().isEmpty) &&
          ((_captainPhone ?? widget.ride.heroPhone)?.trim().isEmpty ?? true)) {
        unawaited(_hydrateCaptainPhone(heroId));
      }
    }

    setState(() {
      _rideStatus = nextStatus;
      _paymentStatus = nextPaymentStatus;
      _lockedFare = nextLockedFare;
      _finalFare = nextFinalFare;
      _actualFare = nextActualFare;
      _tipAmount = nextTipAmount;
      _captainName = nextCaptainName;
      _captainBike = nextCaptainBike;
      _captainPhone = nextCaptainPhone;
      _captainVehicleType = nextCaptainVehicleType;
      _rideOtp = nextRideOtp;
      _completed = nextStatus == 'completed' || _isPaymentSettled;
      _isRideLoading = false;
      _rideErrorMessage = null;
    });

    // Force check for payment completion to prevent getting stuck
    if (nextPaymentStatus == 'settled' || nextStatus == 'paid') {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && !_handledPaidFlow) {
          unawaited(_handlePaidClosure());
        }
      });
    }

    if (nextCaptainLat != null && nextCaptainLng != null) {
      _applyHeroLocationUpdate(
        nextCaptainLat,
        nextCaptainLng,
        vehicleType: nextCaptainVehicleType,
      );
    }

    if (shouldNavigateToPayment) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_navigateToPayment());
      });
    } else if (shouldHandlePaid) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        unawaited(_handlePaidClosure());
      });
    }
  }

  // RTDB listener for live captain GPS with smooth animation (Zero-Read Rule)
  void _startCaptainLocationTracking(String? heroId) {
    if (heroId == null || heroId.isEmpty) return;
    if (_trackedHeroId == heroId && _captainLocationSub != null) {
      return;
    }
    _trackedHeroId = heroId;
    _captainLocationSub?.cancel();
    _captainLocationSub = FirebaseDatabase.instance
        .ref('live_locations/${widget.rideDocId}')
        .onValue
        .listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value as Map<dynamic, dynamic>?;
      if (data == null) {
        return;
      }

      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      final heading = (data['heading'] as num?)?.toDouble();
      final vehicleType =
          (data['vehicleType'] ?? data['heroVehicleType'])?.toString();
      if (lat == null || lng == null) return;

      if (mounted) {
        _applyHeroLocationUpdate(
          lat,
          lng,
          headingDegrees: heading,
          vehicleType: vehicleType,
        );

        debugPrint(
            '🛰️ Hero location updated (RTDB): ${lat.toStringAsFixed(4)}, ${lng.toStringAsFixed(4)}',);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _returnToRootSafely();
      },
      child: Scaffold(
        backgroundColor: _page,
        body: SafeArea(
          child: _buildContent(),
        ),
      ),
    );
  }

  Widget _buildContent() {
    if (_rideErrorMessage != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.red, size: 48),
            const SizedBox(height: 16),
            Text(
              'Connection Error',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
            const SizedBox(height: 8),
            Text(
              _rideErrorMessage!,
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ],
        ),
      );
    }

    if (_isRideLoading) {
      return const Center(
        child: CircularProgressIndicator(),
      );
    }

    return _buildBody();
  }

  Widget _buildBody() {
    return Column(
      children: [
        _buildHeader(),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(
              children: [
                if (_completed) ...[
                  _completedBanner(),
                  const SizedBox(height: 16),
                  _paymentSheet(),
                ] else ...[
                  _arrivalBanner(),
                  const SizedBox(height: 16),
                  _buildTrackingMap(),
                ],
                const SizedBox(height: 16),
                if (_rideOtp.trim().isNotEmpty &&
                    _rideOtp.trim() != '----') ...[
                  _otpCard(),
                  const SizedBox(height: 16),
                ],
                _captainCard(),
                const SizedBox(height: 16),
                _routeCard(),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: Colors.white,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: _returnToRootSafely,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _cardTint,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _border),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 14,
                  color: _muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            const Text(
              'Track Your Ride',
              style: TextStyle(
                fontSize: 16,
                color: _text,
                fontWeight: FontWeight.w700,
              ),
            ),
            const Spacer(),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: const Color(0x1400A86B),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: const Color(0x3300A86B)),
              ),
              child: Text(
                _completed ? 'Completed ✅' : 'Live 🟢',
                style: const TextStyle(
                  fontSize: 10,
                  color: _green,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );

  Widget _arrivalBanner() {
    final String title =
        _rideStatus == 'started' || _rideStatus == 'in_progress'
            ? (_isCargoRide ? 'Goods picked up' : 'Ride started')
            : 'Driver arriving...';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFFFF0F7), Color(0xFFFFFFFF)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x16FF4FA3),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        children: [
          const Text('🏍️', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              fontSize: 18,
              color: _text,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            _captainName ?? widget.ride.heroName ?? 'Your Hero',
            style: GoogleFonts.notoSansTamil(
              fontSize: 12,
              color: _muted,
            ),
          ),
          if (_remainingDistanceKm != null && _remainingEtaMinutes != null) ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF5FA),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _border),
              ),
              child: Text(
                '${_remainingDistanceKm!.toStringAsFixed(1)} km away • ETA ${_remainingEtaMinutes!} mins',
                style: const TextStyle(
                  fontSize: 12,
                  color: _text,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _completedBanner() {
    final tip = _tipAmount ?? 0;
    final baseToCharge = _lockedFare ??
        widget.ride.estimatedFare?.toDouble() ??
        _calculateFareFromDistance(widget.ride.distanceKm ?? 0);
    final absoluteTotal = baseToCharge + tip;
    final fareBeforeTip = absoluteTotal - tip;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFFEFFFF6),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x3300A86B)),
      ),
      child: Column(
        children: [
          const Text('🎉', style: TextStyle(fontSize: 40)),
          const SizedBox(height: 8),
          Text(
            _paymentStatus == 'pending_collection' || _paymentStatus == 'awaiting_confirmation'
                ? 'Ride Completed — Awaiting Payment'
                : 'Ride Successful — Paid Offline',
            style: const TextStyle(
              fontSize: 18,
              color: _green,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 12),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.6),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Column(
              children: [
                Text(
                  '₹${absoluteTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 28,
                    color: Color(0xFF00A86B),
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  tip > 0
                      ? 'Fare: ₹${fareBeforeTip.toStringAsFixed(0)} + Tip: ₹${tip.toStringAsFixed(0)}'
                      : 'Fare: ₹${fareBeforeTip.toStringAsFixed(0)}',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Thank you for riding with Allin1!',
            style: GoogleFonts.notoSansTamil(
              fontSize: 12,
              color: _muted,
            ),
          ),
        ],
      ),
    );
  }

  Widget _otpCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [Color(0xFFFFF2F9), Color(0xFFFFFFFF)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x18FF4FA3),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Ride OTP',
              style: GoogleFonts.outfit(
                fontSize: 13,
                color: _muted,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              _rideOtp,
              style: GoogleFonts.outfit(
                fontSize: 34,
                color: _gold,
                fontWeight: FontWeight.w900,
                letterSpacing: 6,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'Tell this OTP to your Hero before the ride starts.',
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: _text,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _paymentSheet() {
    final tip = _tipAmount ?? 0;
    final baseToCharge = _lockedFare ??
        widget.ride.estimatedFare?.toDouble() ??
        _calculateFareFromDistance(widget.ride.distanceKm ?? 0);
    final absoluteTotal = baseToCharge + tip;
    final fareBeforeTip = absoluteTotal - tip;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0x14FF4FA3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x55FF4FA3)),
        boxShadow: const [
          BoxShadow(
            color: Color(0x22FF4FA3),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text('💳', style: TextStyle(fontSize: 34)),
          const SizedBox(height: 10),
          const Text(
            'Complete Your Payment',
            style: TextStyle(
              fontSize: 20,
              color: _text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            'ரைடரின் Paytm Soundbox-ஐ ஸ்கேன் செய்து பணம் செலுத்தவும்.',
            style: GoogleFonts.notoSansTamil(
              fontSize: 13,
              color: _muted,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Open your UPI app, scan the rider soundbox, and pay offline.',
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: _text,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 18),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      'Fare: ₹${fareBeforeTip.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: Color(0xFFFF4FA3),
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (tip > 0) ...[
                      const SizedBox(width: 8),
                      Text(
                        '+ ₹${tip.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: Color(0xFFFFBB00),
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 8),
                const Text(
                  'Total',
                  style: TextStyle(color: _muted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  '₹${absoluteTotal.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: Color(0xFF00A86B),
                    fontSize: 30,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                if (tip > 0) ...[
                  const SizedBox(height: 4),
                  const Text(
                    'Fare + Tip included',
                    style: TextStyle(
                      color: _muted,
                      fontSize: 10,
                    ),
                  ),
                ],
              ],
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: _paymentActionButton(
                  label: 'Cash',
                  icon: Icons.payments_outlined,
                  selected: _selectedPaymentMethod == 'cash',
                  onTap: () => _selectPaymentMethod('cash'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _paymentActionButton(
                  label: 'Wallet',
                  icon: Icons.account_balance_wallet_outlined,
                  selected: _selectedPaymentMethod == 'wallet',
                  onTap: () => _selectPaymentMethod('wallet'),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _paymentActionButton(
                  label: 'Open UPI App',
                  icon: Icons.qr_code_scanner_rounded,
                  selected: _selectedPaymentMethod == 'upi',
                  onTap: _openGenericUpi,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _captainCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12FF4FA3),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF4FA3), Color(0xFFFF9CCC)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  (_captainName ?? widget.ride.heroName)?.isNotEmpty ?? false
                      ? (_captainName ?? widget.ride.heroName)![0].toUpperCase()
                      : 'H',
                  style: const TextStyle(
                    fontSize: 22,
                    color: Colors.white,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _captainName ?? widget.ride.heroName ?? 'Hero Rider',
                    style: const TextStyle(
                      fontSize: 15,
                      color: _text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  if ((_captainBike ?? widget.ride.heroVehicleNumber)
                          ?.isNotEmpty ??
                      false)
                    Text(
                      _captainBike ?? widget.ride.heroVehicleNumber!,
                      style: const TextStyle(fontSize: 11, color: _muted),
                    ),
                ],
              ),
            ),
            // Call button
            if (_trackedHeroId != null ||
                ((_captainName ?? widget.ride.heroName)?.isNotEmpty ?? false))
              GestureDetector(
                onTap: _callHero,
                child: Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF4FA),
                    borderRadius: BorderRadius.circular(13),
                    border: Border.all(color: _border),
                  ),
                  child: const Icon(Icons.phone, size: 18, color: _green),
                ),
              ),
          ],
        ),
      );

  Widget _routeCard() => Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x10FF4FA3),
              blurRadius: 16,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          children: [
            _rRow('🔴', 'Pickup', widget.ride.pickupAddress ?? ''),
            const SizedBox(height: 10),
            _rRow('🟢', 'Drop', widget.ride.dropAddress ?? ''),
            const Divider(color: _border, height: 20),
            if (_tipAmount != null && _tipAmount! > 0) ...[
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Tip',
                    style: TextStyle(
                      fontSize: 12,
                      color: _muted,
                    ),
                  ),
                  Text(
                    '₹${_tipAmount!.round()}',
                    style: const TextStyle(
                      fontSize: 16,
                      color: Color(0xFFFFBB00),
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  _finalFare != null
                      ? 'Final Fare'
                      : _lockedFare != null
                          ? 'Locked Fare'
                          : 'Estimated Fare',
                  style: const TextStyle(
                    fontSize: 12,
                    color: _muted,
                  ),
                ),
                Text(
                  '₹${(_finalFare ?? _lockedFare ?? widget.ride.estimatedFare?.toDouble() ?? 0).round()}',
                  style: const TextStyle(
                    fontSize: 20,
                    color: _gold,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  Widget _paymentActionButton({
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        height: 84,
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: selected
                ? const [Color(0xFFFF4FA3), Color(0xFFFF8FC6)]
                : const [Color(0xFF6C63FF), Color(0xFF4A44CC)],
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color:
                  selected ? const Color(0x44FF4FA3) : const Color(0x446C63FF),
              blurRadius: 16,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 22, color: Colors.white),
            const SizedBox(height: 8),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 12,
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTrackingMap() {
    final pickup = LatLng(
      widget.ride.pickupLatitude ?? 11.3410,
      widget.ride.pickupLongitude ?? 77.7172,
    );

    final markers = <MapMarker>[
      MapMarker(
        point: pickup,
        label: 'You',
        icon: Icons.person_pin_circle_rounded,
      ),
    ];

    if (_captainLat != null && _captainLng != null) {
      markers.add(
        MapMarker(
          point: LatLng(_captainLat!, _captainLng!),
          color: _green,
          assetPath: _assetForHeroVehicleType(_captainVehicleType),
          bearingDegrees: _captainBearingDegrees,
          size: 45,
        ),
      );
    }

    return Container(
      height: 240,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x12FF4FA3),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          children: [
            Allin1MapWidget(
              mapController: _trackingMapController,
              onMapReady: _handleTrackingMapReady,
              center: markers.length > 1 ? markers.last.point : pickup,
              zoom: 15,
              markers: markers,
              routes: _routePoints.isNotEmpty
                  ? [
                      MapRoute(
                        points: _routePoints,
                        color: _gold,
                      ),
                    ]
                  : [],
            ),
            // Overlay when hero location not yet received
            if (_captainLat == null)
              Positioned(
                bottom: 12,
                left: 0,
                right: 0,
                child: Center(
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDF0F7),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: _border),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: _green,
                          ),
                        ),
                        SizedBox(width: 8),
                        Text(
                          'Waiting for Hero location…',
                          style: TextStyle(
                            fontSize: 10,
                            color: _text,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // Draw route between captain and customer using OSRM
  Future<void> _drawRoute(
    double fromLat,
    double fromLng,
    double toLat,
    double toLng,
  ) async {
    try {
      final url = Uri.parse('https://router.project-osrm.org/route/v1'
          '/driving/$fromLng,$fromLat;$toLng,$toLat'
          '?overview=simplified&geometries=geojson');

      final response = await http.get(url);
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        final coords = data['routes'][0]['geometry']['coordinates'] as List;

        if (mounted) {
          setState(() {
            _routePoints = coords
                .where((c) => c[1] != null && c[0] != null)
                .map(
                  (c) => LatLng(
                    (c[1] as num).toDouble(),
                    (c[0] as num).toDouble(),
                  ),
                )
                .toList();
          });
        }
      }
    } catch (e) {
      debugPrint('Route error: $e');
    }
  }

  double _calculateFareFromDistance(double km) {
    if (km <= 0) return 25;
    const double baseFare = 25;
    const double baseDistance = 1;
    const double perKm = 6;
    if (km <= baseDistance) return baseFare;
    return (baseFare + ((km - baseDistance) * perKm)).roundToDouble();
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

  Widget _rRow(String dot, String lbl, String txt) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(dot, style: const TextStyle(fontSize: 11)),
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
}

// ── HERO RATING SHEET ──────────────────────────────────────────────
class _HeroRatingSheet extends StatefulWidget {
  @override
  State<_HeroRatingSheet> createState() => _HeroRatingSheetState();
}

class _HeroRatingSheetState extends State<_HeroRatingSheet> {
  int _rating = 5;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFFFFFBFE),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x33FF4FA3)),
      ),
      title: const Text(
        'Rate Your Hero',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Color(0xFF3D1230),
          fontWeight: FontWeight.w800,
          fontSize: 20,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text(
            'How was your ride?',
            style: TextStyle(color: Color(0xFF8F5A78), fontSize: 14),
          ),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(5, (i) {
              final star = i + 1;
              return GestureDetector(
                onTap: () => setState(() => _rating = star),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(
                    star <= _rating
                        ? Icons.star_rounded
                        : Icons.star_outline_rounded,
                    color: star <= _rating
                        ? const Color(0xFFFFBB00)
                        : const Color(0xFFCCC0D0),
                    size: 40,
                  ),
                ),
              );
            }),
          ),
        ],
      ),
      actions: [
        SizedBox(
          width: double.infinity,
          child: ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF4FA3),
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14),
              ),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: () => Navigator.pop(context, _rating),
            child: const Text(
              'Submit Rating',
              style: TextStyle(fontWeight: FontWeight.w800),
            ),
          ),
        ),
      ],
    );
  }
}