// ================================================================
// CaptainRideScreen v1.0 — Live Navigation & Trip Management
// Used by captains AFTER accepting a ride
// ================================================================

import 'dart:async';
import 'dart:math' as math;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../models/ride_model.dart';
import '../../services/map_service.dart';
import '../../services/hero_ride_notification_service.dart';
import '../../widgets/allin1_map_widget.dart';

class CaptainRideScreen extends StatefulWidget {
  final RideModel ride;
  final String rideDocId;
  const CaptainRideScreen({
    required this.ride,
    required this.rideDocId,
    super.key,
  });
  @override
  State<CaptainRideScreen> createState() => _CaptainRideScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<RideModel>('ride', ride))
      ..add(StringProperty('rideDocId', rideDocId));
  }
}

class _CaptainRideScreenState extends State<CaptainRideScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  // ── Theme ────────────────────────────────────────────────────
  static const Color _bg = Color(0xFF0A0A12);
  static const Color _surface = Color(0xFF12121E);
  static const Color _card = Color(0xFF1A1A2A);
  static const Color _green = Color(0xFF00C853);
  static const Color _gold = Color(0xFFFFBB00);
  static const Color _red = Color(0xFFFF5252);
  static const Color _purple = Color(0xFF6C63FF);
  static const Color _text = Color(0xFFEEEEF5);
  static const Color _muted = Color(0xFF7777A0);
  static const Color _border = Color(0x1AFFFFFF);

  bool get _isCargoRide {
    final type = (widget.ride.vehicleType ?? '').trim().toLowerCase();
    return type == 'lorry' || type == 'mini_truck';
  }

  // ── State ────────────────────────────────────────────────────
  String _rideStatus = '';
  bool _isLoading = true;
  Position? _currentPosition;
  StreamSubscription<Position>? _locationSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _rideDocSubscription;
  final MapController _mapController = MapController();
  final MapService _mapService = MapService();
  bool _rideMapReady = false;
  LatLng? _pendingRideMapCenter;
  double? _pendingRideMapZoom;

  // Captain location for map
  double? _captainLat;
  double? _captainLng;
  double? _captainBearingDegrees;
  AnimationController? _captainMarkerMoveCtrl;
  List<LatLng> _routePoints = [];
  int _routeRequestId = 0;
  double _finalFare = 0;
  double _netEarnings = 0;
  double _commissionAmount = 0;
  String _paymentStatus = 'pending';
  String _pickupAddress = '---';
  String _dropAddress = '---';
  String _customerPhone = 'Contact available';
  double _estimatedFare = 0;
  double _rideFareAmount = 0;
  double _tipAmount = 0;
  final TextEditingController _otpController = TextEditingController();
  String _rideOtpCode = '';
  bool _verifyingOtp = false;
  bool _liveLocationCleanedUp = false;
  // Set in initState() if widget.rideDocId arrives empty (hero_home_screen.dart
  // no longer silently substitutes the RTDB push key here — see its
  // _acceptRide() comment). build() shows a dedicated error state instead
  // of proceeding with a Firestore/OTP setup that would silently be wrong.
  bool _missingRideDocId = false;

  // Actual tracked distance during trip
  double _actualDistanceKm = 0;
  Position? _prevTrackingPosition;

  // ─── LOCAL DETERMINISTIC OTP GENERATOR (NO DB REQUIRED) ───
  String _generateLocalOtp(String docId) {
    final cleanId = docId.trim().replaceAll(RegExp(r'\s+'), '');
    if (cleanId.isEmpty) return '1234';
    // Platform-independent checksum — avoids String.hashCode, which
    // differs between native (VM) and web (dart2js/dart2wasm) builds,
    // causing OTP mismatches between mobile app and PWA.
    int checksum = 0;
    for (int i = 0; i < cleanId.length; i++) {
      checksum = (checksum * 31 + cleanId.codeUnitAt(i)) & 0x7FFFFFFF;
    }
    return (1000 + (checksum % 9000)).toString();
  }
  // ──────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    if (widget.rideDocId.trim().isEmpty) {
      debugPrint(
        '[HeroRideScreen] ❌ rideDocId is empty — the accepted-ride ping '
        'was missing its Firestore doc link. Skipping ride setup; '
        'build() will show an error state instead of a wrong OTP.',
      );
      _missingRideDocId = true;
      return;
    }

    // ✅ Generate Local OTP on Init
    _rideOtpCode = _generateLocalOtp(widget.rideDocId);

    _rideStatus = widget.ride.status ?? 'accepted';
    _pickupAddress = widget.ride.pickupAddress ?? '---';
    _dropAddress = widget.ride.dropAddress ?? '---';
    _customerPhone = widget.ride.heroPhone ?? 'Contact available';
    _estimatedFare = widget.ride.estimatedFare?.toDouble() ??
        widget.ride.fare?.toDouble() ??
        0;
    _rideFareAmount = _estimatedFare;
    _mapService.initialize();
    _startLocationUpdates();
    _fetchRideStatus();
    unawaited(_loadRoadRoute());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[HeroRideScreen] App resumed - refreshing ride map');
      if (!mounted) {
        return;
      }
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        try {
          final mapCenter = _currentPosition != null
              ? LatLng(
                  _currentPosition!.latitude,
                  _currentPosition!.longitude,
                )
              : _captainLat != null && _captainLng != null
                  ? LatLng(_captainLat!, _captainLng!)
                  : widget.ride.pickupLatitude != null &&
                          widget.ride.pickupLongitude != null
                      ? LatLng(
                          widget.ride.pickupLatitude!,
                          widget.ride.pickupLongitude!,
                        )
                      : const LatLng(11.3410, 77.7171);
          _moveRideMap(mapCenter, 15);
        } catch (e) {
          debugPrint('[HeroRideScreen] Map refresh failed on resume: $e');
        }
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _locationSubscription?.cancel();
    _rideDocSubscription?.cancel();
    _disposeCaptainMarkerAnimation();
    _otpController.dispose();

    // ✅ FIX: Cancel notification if screen closes abruptly
    if (widget.rideDocId.isNotEmpty && _rideStatus != 'paid') {
      unawaited(
        HeroRideNotificationService.cancelRideNotification(widget.rideDocId)
      );
    }

    super.dispose();
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
      debugPrint(
        '[HeroRideScreen] Removed RTDB live location for ${widget.rideDocId}',
      );
    } catch (e) {
      debugPrint('[HeroRideScreen] Live location cleanup failed: $e');
    }
  }

  void _moveRideMap(LatLng center, double zoom) {
    _pendingRideMapCenter = center;
    _pendingRideMapZoom = zoom;
    if (!_rideMapReady) {
      debugPrint('[HeroRideScreen] Ride map move queued until ready');
      return;
    }
    try {
      _mapController.move(center, zoom);
      _pendingRideMapCenter = null;
      _pendingRideMapZoom = null;
    } catch (e) {
      debugPrint('[HeroRideScreen] Ride map move failed: $e');
    }
  }

  void _handleRideMapReady() {
    _rideMapReady = true;
    final center = _pendingRideMapCenter;
    if (center != null) {
      _moveRideMap(center, _pendingRideMapZoom ?? 15);
    }
  }

  double _resolvePositionBearing(Position position) {
    final previous = _currentPosition;
    if (previous != null) {
      final movedMeters = Geolocator.distanceBetween(
        previous.latitude,
        previous.longitude,
        position.latitude,
        position.longitude,
      );
      if (movedMeters > 2) {
        return _bearingBetween(
          LatLng(previous.latitude, previous.longitude),
          LatLng(position.latitude, position.longitude),
        );
      }
    }

    final heading = position.heading;
    if (!heading.isNaN && heading >= 0) {
      return heading;
    }
    return _captainBearingDegrees ?? 0;
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

  String _assetForVehicleType(String? vehicleType) {
    final normalized = vehicleType?.trim().toLowerCase() ?? '';
    if (normalized.contains('auto')) {
      return 'assets/images/top_auto.png';
    }
    if (normalized.contains('car') ||
        normalized.contains('cab') ||
        normalized.contains('mini')) {
      return 'assets/images/top_cab.png';
    }
    return 'assets/images/top_bike.png';
  }

  void _disposeCaptainMarkerAnimation() {
    final controller = _captainMarkerMoveCtrl;
    _captainMarkerMoveCtrl = null;
    controller?.stop();
    controller?.dispose();
  }

  void _animateCaptainMarkerTo(Position position, double bearingDegrees) {
    if (!mounted) {
      return;
    }
    final target = LatLng(position.latitude, position.longitude);
    final start = _captainLat != null && _captainLng != null
        ? LatLng(_captainLat!, _captainLng!)
        : null;

    _disposeCaptainMarkerAnimation();
    if (start == null) {
      setState(() {
        _captainLat = target.latitude;
        _captainLng = target.longitude;
        _captainBearingDegrees = bearingDegrees;
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
    _captainMarkerMoveCtrl = controller;
    controller.addListener(() {
      if (!mounted || _captainMarkerMoveCtrl != controller) {
        return;
      }
      final t = curved.value;
      setState(() {
        _captainLat = start.latitude + ((target.latitude - start.latitude) * t);
        _captainLng =
            start.longitude + ((target.longitude - start.longitude) * t);
        _captainBearingDegrees = bearingDegrees;
      });
    });
    controller.addStatusListener((status) {
      if (status != AnimationStatus.completed ||
          !mounted ||
          _captainMarkerMoveCtrl != controller) {
        return;
      }
      setState(() {
        _captainLat = target.latitude;
        _captainLng = target.longitude;
        _captainBearingDegrees = bearingDegrees;
      });
      _captainMarkerMoveCtrl = null;
      controller.dispose();
    });
    controller.forward();
  }

  // ── Location Updates ─────────────────────────────────────────
  Future<void> _startLocationUpdates() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final result = await Geolocator.requestPermission();
        if (result == LocationPermission.denied ||
            result == LocationPermission.deniedForever) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Location permission is required for navigation'),
                backgroundColor: _red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          return;
        }
      }

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        ),
      ).listen((position) {
        if (mounted) {
          final bearingDegrees = _resolvePositionBearing(position);
          setState(() {
            if (_rideStatus == 'started' || _rideStatus == 'in_progress') {
              if (_prevTrackingPosition != null) {
                final d = Geolocator.distanceBetween(
                  _prevTrackingPosition!.latitude,
                  _prevTrackingPosition!.longitude,
                  position.latitude,
                  position.longitude,
                );
                _actualDistanceKm += d / 1000.0; // convert meters to km
              }
              _prevTrackingPosition = position;
            }

            _currentPosition = position;
          });
          // Write live location to RTDB
          if (widget.rideDocId.isNotEmpty) {
            unawaited(
              FirebaseDatabase.instance
                  .ref()
                  .child('live_locations/${widget.rideDocId}')
                  .set({
                'lat': position.latitude,
                'lng': position.longitude,
                'heading': bearingDegrees,
                'updatedAt': ServerValue.timestamp,
              }),
            );
          }
          _animateCaptainMarkerTo(position, bearingDegrees);
          if (_routePoints.isEmpty) {
            unawaited(_loadRoadRoute());
          }
        }
      });
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Location service error: ${e.toString()}'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _loadRoadRoute() async {
    final start = _captainLat != null && _captainLng != null
        ? LatLng(_captainLat!, _captainLng!)
        : _currentPosition != null
            ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
            : null;
    final target = _rideStatus == 'in_progress'
        ? (widget.ride.dropLatitude != null && widget.ride.dropLongitude != null
            ? LatLng(widget.ride.dropLatitude!, widget.ride.dropLongitude!)
            : null)
        : (widget.ride.pickupLatitude != null &&
                widget.ride.pickupLongitude != null
            ? LatLng(widget.ride.pickupLatitude!, widget.ride.pickupLongitude!)
            : null);
    if (start == null || target == null) {
      if (mounted && _routePoints.isNotEmpty) {
        setState(() => _routePoints = []);
      }
      return;
    }

    try {
      final requestId = ++_routeRequestId;
      await _mapService.initialize();
      final route = await _mapService.getRoute(start, target);
      if (!mounted || requestId != _routeRequestId) {
        return;
      }
      setState(() {
        _routePoints = route?.points ?? [];
      });
    } catch (e) {
      debugPrint('Hero route load error: $e');
      if (mounted) {
        setState(() => _routePoints = []);
      }
    }
  }

  // Fetch latest ride status from Firestore
  void _fetchRideStatus() {
    _rideDocSubscription?.cancel();
    _rideDocSubscription = FirebaseFirestore.instance
        .collection('rides')
        .doc(widget.rideDocId)
        .snapshots()
        .listen((snap) {
      if (snap.exists && mounted) {
        final data = snap.data()!;
        final nextStatus = data['status'] as String? ?? 'accepted';
        if (nextStatus == 'completed' || nextStatus.startsWith('cancelled')) {
          unawaited(_cleanupLiveLocationNode());
        }
        final previousStatus = _rideStatus;
        setState(() {
          _rideStatus = nextStatus;
          _pickupAddress = data['pickupAddress'] as String? ??
              data['pickupLocation'] as String? ??
              _pickupAddress;
          _dropAddress = data['dropAddress'] as String? ??
              data['dropLocation'] as String? ??
              _dropAddress;
          _customerPhone = data['customerPhone'] as String? ??
              data['customerContact'] as String? ??
              _customerPhone;
          _estimatedFare = (data['estimatedFare'] as num?)?.toDouble() ??
              (data['fare'] as num?)?.toDouble() ??
              _estimatedFare;
          _rideFareAmount = (data['actualFare'] as num?)?.toDouble() ??
              (data['lockedFare'] as num?)?.toDouble() ??
              (data['estimatedFare'] as num?)?.toDouble() ??
              (data['fare'] as num?)?.toDouble() ??
              _rideFareAmount;
          _tipAmount = (data['tipAmount'] as num?)?.toDouble() ?? _tipAmount;
          
          // ✅ Always use local deterministic OTP 
          _rideOtpCode = _generateLocalOtp(widget.rideDocId);

          _finalFare = (data['finalFare'] as num?)?.toDouble() ??
              (data['estimatedFare'] as num?)?.toDouble() ??
              (data['fare'] as num?)?.toDouble() ??
              _estimatedFare;
          _netEarnings =
              (data['netEarnings'] as num?)?.toDouble() ?? _netEarnings;
          _commissionAmount =
              (data['commission'] as num?)?.toDouble() ?? _commissionAmount;
          _paymentStatus = data['paymentStatus'] as String? ?? _paymentStatus;
          _isLoading = false;
        });
        if (previousStatus != nextStatus) {
          unawaited(_loadRoadRoute());
        }
      }
    });
  }

  // ── Trip Actions ─────────────────────────────────────────────
  Future<void> _arriveTrip() async {
    try {
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideDocId)
          .update({
        'status': 'arrived',
        'arrivedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _rideStatus = 'arrived');
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Arrived at pickup!'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _startTrip() async {
    final enteredOtp = _otpController.text.trim();
    if (_rideOtpCode.isNotEmpty && enteredOtp != _rideOtpCode) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: const Text('❌ Incorrect OTP, please ask the customer to confirm'),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
        ));
      }
      return;
    }
    setState(() => _verifyingOtp = true);
    try {
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(widget.rideDocId)
          .update({
        'status': 'in_progress',
        'startedAt': FieldValue.serverTimestamp(),
        'rideOtpVerifiedAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        setState(() => _verifyingOtp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Trip started! Navigate to destination'),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _verifyingOtp = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _completeTrip() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      final rideRef =
          FirebaseFirestore.instance.collection('rides').doc(widget.rideDocId);
      // Get locked ride fare settings
      final rideSnap = await rideRef.get();
      final rideData = rideSnap.data();
      // Idempotency guard: skip wallet credit if already settled
      if (rideData?['paymentStatus'] == 'settled') {
        debugPrint('[HeroRideScreen] Payment already settled — skipping');
        return;
      }

      final baseFare = (rideData?['baseFare'] as num?)?.toDouble() ?? 25.0;
      final farePerKm = (rideData?['farePerKm'] as num?)?.toDouble() ?? 6.0;
      final tipAmount = (rideData?['tipAmount'] as num?)?.toDouble() ?? 0.0;
      // Use CEO-mandated formula: ₹25 base (covers 1st km) + ₹6/km after
      const double baseDistance = 1;
      final double extraKm = _actualDistanceKm > baseDistance
          ? (_actualDistanceKm - baseDistance)
          : 0.0;
      final double fareBeforeTip = _actualDistanceKm <= baseDistance
          ? baseFare
          : (baseFare + (extraKm * farePerKm)).roundToDouble();
      final double finalFare = fareBeforeTip + tipAmount;

      final fare = finalFare;
      // Definitive fare for this completed trip

      // Zero-Commission Promotion: Hero keeps 100% of fare
      const double commission = 0;
      final double netEarnings = fare;
      const double adminCommission = 0;
      // Update ride status with real-time distance and final bill
      await rideRef.update({
        'status': 'completed',
        'completedAt': FieldValue.serverTimestamp(),
        'completedBy': user?.uid ?? '',
        'commission': commission,
        'netEarnings': netEarnings,
        'heroEarning': netEarnings,
        'adminCommission': adminCommission,
        'isZeroCommission': true,
        'actualFare': fareBeforeTip,
        'finalFare': finalFare,
        'tipAmount': tipAmount,
        'actualDistanceKm': _actualDistanceKm,
        'paymentStatus': 'pending_collection',
      });
      await _cleanupLiveLocationNode();

      // ✅ FIX: Kill the ride notification when ride completes
      if (widget.rideDocId.isNotEmpty) {
        try {
          await HeroRideNotificationService.cancelRideNotification(widget.rideDocId);
          debugPrint('[HeroRideScreen] Ride notification cancelled on trip complete');
        } catch (e) {
          debugPrint('[HeroRideScreen] Notification cancel error: $e');
        }
      }

      // ── Wallet credit intentionally removed from _completeTrip() ──
      // All wallet updates happen ONLY in _markPaymentReceived()
      // to prevent double-credit.
      // ✅ This keeps a single source of truth.

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Ride ended. Collect ₹${fare.toStringAsFixed(0)} from the customer.',
            ),
            backgroundColor: _green,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _reportPaymentIssue() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      final rideRef =
          FirebaseFirestore.instance.collection('rides').doc(widget.rideDocId);
      final heroRef =
          FirebaseFirestore.instance.collection('heroes').doc(user.uid);
      await rideRef.set(
        {
          'status': 'dispute',
          'paymentStatus': 'dispute',
          'paymentDispute': true,
          'disputeReason': 'payment_not_received',
          'disputeRaisedBy': user.uid,
          'disputeRaisedAt': FieldValue.serverTimestamp(),
          'adminAlertRequired': true,
          'archivedAt': FieldValue.serverTimestamp(),
          'archivedForHero': true,
        },
        SetOptions(merge: true),
      );
      await heroRef.set(
        {
          'status': 'online',
          'isAvailable': true,
          'activeRideId': null,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await FirebaseDatabase.instance
          .ref('live_locations/${widget.rideDocId}')
          .remove();
      await FirebaseDatabase.instance
          .ref('online_heroes/${user.uid}')
          .update({'isAvailable': true});

      // ✅ FIX: Kill the ride notification when payment is marked received
      if (widget.rideDocId.isNotEmpty) {
        try {
          await HeroRideNotificationService.cancelRideNotification(widget.rideDocId);
          debugPrint('[HeroRideScreen] Ride notification cancelled on payment received');
        } catch (e) {
          debugPrint('[HeroRideScreen] Notification cancel error: $e');
        }
      }

      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment issue reported. Admin has been alerted.'),
          backgroundColor: _gold,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Unable to report issue: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // ── Navigation ───────────────────────────────────────────────
  Future<void> _markPaymentReceived() async {
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user == null) {
        return;
      }

      final rideRef =
          FirebaseFirestore.instance.collection('rides').doc(widget.rideDocId);
      final rideSnap = await rideRef.get();
      final rideData = rideSnap.data() ?? <String, dynamic>{};
      // Idempotency guard: skip if already settled or paid via wallet
      // ('paid_by_wallet' already credited the hero in the customer's
      // wallet transaction — crediting again here would double-pay).
      if (rideData['paymentStatus'] == 'settled' ||
          rideData['paymentStatus'] == 'paid' ||
          rideData['paymentStatus'] == 'paid_by_wallet') {
        debugPrint('[HeroRideScreen] Payment already processed — skipping markPaymentReceived');
        return;
      }

      final double rideFare = ((rideData['actualFare'] ??
              rideData['lockedFare'] ??
              rideData['estimatedFare'] ??
              rideData['fare'] ??
              _rideFareAmount) as num)
          .toDouble();
      final double tipAmount =
          ((rideData['tipAmount'] ?? _tipAmount) as num).toDouble();
      final double fare = rideFare + tipAmount;
      const double commission = 0;
      // ZERO Commission for launch
      final double netEarnings = fare;
      // Hero keeps 100% of the fare

      final heroRef =
          FirebaseFirestore.instance.collection('heroes').doc(user.uid);
      final heroSnap = await heroRef.get();
      final currentBalance =
          (heroSnap.data()?['walletBalance'] as num?)?.toDouble() ??
          0.0;
      final totalEarnings =
          (heroSnap.data()?['totalEarnings'] as num?)?.toDouble() ?? 0.0;
      final totalRides = (heroSnap.data()?['totalRides'] as num?)?.toInt() ?? 0;

      await rideRef.update({
        'status': 'paid',
        'paymentStatus': 'settled',
        'actualFare': rideFare,
        'tipAmount': tipAmount,
        'finalFare': fare,
        'paidAt': FieldValue.serverTimestamp(),
        'paymentReceivedBy': user.uid,
        'archivedAt': FieldValue.serverTimestamp(),
        'archivedForHero': true,
      });
      await heroRef.set(
        {
          'status': 'online',
          'isAvailable': true,
          'activeRideId': null,
          'walletBalance': currentBalance + netEarnings,
          'totalEarnings': totalEarnings + netEarnings,
          'totalRides': totalRides + 1,
          'lastRideCompletedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await FirebaseFirestore.instance.collection('wallet_transactions').add({
        'heroId': user.uid,
        'type': 'credit',
        'amount': netEarnings,
        'commission': commission,
        'grossAmount': fare,
        'balanceBefore': currentBalance,
        'balanceAfter': currentBalance + netEarnings,
        'rideId': widget.rideDocId,
        'description': 'Payment collected for completed ride',
        'timestamp': FieldValue.serverTimestamp(),
       });

      await FirebaseDatabase.instance
          .ref('live_locations/${widget.rideDocId}')
          .remove();
      await FirebaseDatabase.instance
          .ref('online_heroes/${user.uid}')
          .update({'isAvailable': true});
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment received. You are back online now.'),
          backgroundColor: _green,
          behavior: SnackBarBehavior.floating,
        ),
      );
      Navigator.of(context).pop(true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Payment update failed: $e'),
            backgroundColor: _red,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _navigateToPickup() async {
    final lat = widget.ride.pickupLatitude;
    final lng = widget.ride.pickupLongitude;
    if (lat == null || lng == null) {
      return;
    }

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _navigateToDestination() async {
    final lat = widget.ride.dropLatitude;
    final lng = widget.ride.dropLongitude;
    if (lat == null || lng == null) {
      return;
    }

    final url = Uri.parse(
      'https://www.google.com/maps/dir/?api=1&destination=$lat,$lng&travelmode=driving',
    );
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  // ── Call Customer ────────────────────────────────────────────
  Future<void> _callCustomer() async {
    final phone = _customerPhone.trim();
    if (phone.isEmpty || phone == 'Contact available') {
      return;
    }

    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  // ── UI Builders ──────────────────────────────────────────────
  Widget _buildStatusBadge() {
    Color badgeColor;
    String statusText;
    switch (_rideStatus) {
      case 'accepted':
      case 'hero_assigned':
        badgeColor = _gold;
        statusText = 'Navigate to Pickup';
        break;
      case 'arriving':
        badgeColor = _purple;
        statusText = 'Arriving at Pickup';
        break;
      case 'arrived':
        badgeColor = _purple;
        statusText = 'Waiting at Pickup';
        break;
      case 'started':
      case 'in_progress':
        badgeColor = _green;
        statusText = _isCargoRide ? 'Navigate to Drop' : 'Navigate to Destination';
        break;
      case 'completed':
        badgeColor = _muted;
        statusText = _isCargoRide ? 'Delivery Complete' : 'Collect Payment';
        break;
      case 'paid':
        badgeColor = _green;
        statusText = 'Payment Received';
        break;
      default:
        badgeColor = _muted;
        statusText = 'Unknown Status';
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.2),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: badgeColor.withValues(alpha: 0.5)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(
              color: badgeColor,
              shape: BoxShape.circle,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            statusText,
            style: TextStyle(
              color: badgeColor,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButtons() {
    if (_rideStatus == 'paid') {
      return const SizedBox.shrink();
    }

    if (_rideStatus == 'completed') {
      final rideFare = _rideFareAmount > 0
          ? _rideFareAmount
          : (_estimatedFare > 0 ? _estimatedFare : _finalFare);
      final totalFare = rideFare + _tipAmount;
      return Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Collect Payment',
              style: TextStyle(
                color: _text,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 8),
            const Text(
              'Show the final amount and confirm once payment is in your hand.',
              style: TextStyle(
                color: _muted,
                fontSize: 13,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: _gold.withValues(alpha: 0.35)),
              ),
              child: Column(
                children: [
                  const Text(
                    'Total Fare',
                    style: TextStyle(color: _muted, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Rs ${totalFare.toStringAsFixed(0)}',
                    style: const TextStyle(
                      color: _gold,
                      fontSize: 30,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  if (_tipAmount > 0) ...[
                    const SizedBox(height: 10),
                    Text(
                      'Ride Rs ${rideFare.toStringAsFixed(0)} + Tip Rs ${_tipAmount.toStringAsFixed(0)}',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 14),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [Color(0xFFFF4FA3), Color(0xFFFF9CCC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: _green.withValues(alpha: 0.18),
                    blurRadius: 16,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: const Text(
                'Ini Erode ku Allin1 vanthachu',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w900,
                  letterSpacing: 0.2,
                ),
              ),
            ),
            const SizedBox(height: 14),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _markPaymentReceived,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                child: const Text(
                  'BILL RECEIVED',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                onPressed: _reportPaymentIssue,
                icon: const Icon(Icons.report_problem_outlined),
                style: OutlinedButton.styleFrom(
                  foregroundColor: _red,
                  side: BorderSide(color: _red.withValues(alpha: 0.65)),
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: const Text(
                  'REPORT ISSUE / PAYMENT NOT RECEIVED',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    final isAccepted = _rideStatus == 'accepted' || _rideStatus == 'arriving';
    final isArrived = _rideStatus == 'arrived';

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, -5),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Navigate Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: (isAccepted || isArrived)
                  ? _navigateToPickup
                  : _navigateToDestination,
              icon: const Icon(Icons.navigation, size: 20),
              label: Text(
                (isAccepted || isArrived)
                    ? 'Navigate to Pickup'
                    : 'Navigate to Destination',
                style:
                    const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: _purple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),

          if (isArrived) ...[
            TextField(
              controller: _otpController,
              keyboardType: TextInputType.number,
              maxLength: 4,
              style: const TextStyle(color: _text, fontWeight: FontWeight.w700),
              decoration: InputDecoration(
                counterText: '',
                hintText: 'Enter customer OTP',
                hintStyle: const TextStyle(color: _muted),
                filled: true,
                fillColor: _card,
                prefixIcon: const Icon(Icons.pin_outlined, color: _gold),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
            const SizedBox(height: 12),
          ],

          // Start/Complete Trip Button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: _verifyingOtp
                  ? null
                  : isAccepted
                      ? _arriveTrip
                      : (isArrived ? _startTrip : _completeTrip),
              style: ElevatedButton.styleFrom(
                backgroundColor:
                    isAccepted ? _purple : (isArrived ? _green : _gold),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: Text(
                isAccepted
                    ? (_isCargoRide ? 'PARCEL PICKED' : 'ARRIVED')
                    : (isArrived
                        ? (_verifyingOtp
                            ? 'VERIFYING OTP...'
                            : 'VERIFY OTP & START')
                        : (_isCargoRide ? 'DELIVERED' : 'END RIDE')),
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildRideDetails() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Status Badge
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _buildStatusBadge(),
              IconButton(
                onPressed: _callCustomer,
                icon: const Icon(Icons.phone, color: _green),
                style: IconButton.styleFrom(
                  backgroundColor: _green.withValues(alpha: 0.1),
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Customer Info
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.person, color: _purple, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _pickupAddress == '---' ? 'Customer' : _pickupAddress,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      _customerPhone,
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Route Info
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Pickup',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _pickupAddress,
                        style: const TextStyle(
                          color: _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward, color: _muted, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Drop',
                        style: TextStyle(color: _muted, fontSize: 10),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _dropAddress,
                        style: const TextStyle(
                          color: _text,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),

          // Fare Display
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Estimated Fare',
                style: TextStyle(color: _muted, fontSize: 12),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: _gold.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _gold.withValues(alpha: 0.5)),
                ),
                child: Text(
                  '₹${_estimatedFare.toStringAsFixed(0)}',
                  style: const TextStyle(
                    color: _gold,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_missingRideDocId) {
      return Scaffold(
        backgroundColor: _bg,
        appBar: AppBar(
          backgroundColor: _surface,
          title: const Text('Ride Error', style: TextStyle(color: _text)),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.error_outline_rounded, color: _red, size: 56),
                const SizedBox(height: 16),
                const Text(
                  'Ride reference missing — contact support',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _text, fontWeight: FontWeight.w700, fontSize: 16),
                ),
                const SizedBox(height: 8),
                const Text(
                  "This ride couldn't be linked to its booking record, "
                  'so a trip OTP cannot be generated safely.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: _muted, fontSize: 13),
                ),
                const SizedBox(height: 24),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(),
                  style: ElevatedButton.styleFrom(backgroundColor: _purple),
                  child: const Text('Go Back', style: TextStyle(color: Colors.white)),
                ),
              ],
            ),
          ),
        ),
      );
    }

    // Map center based on status
    final mapCenter = _currentPosition != null
        ? LatLng(_currentPosition!.latitude, _currentPosition!.longitude)
        : LatLng(
            widget.ride.pickupLatitude ?? 11.3410,
            widget.ride.pickupLongitude ?? 77.7171,
          );
    // Build markers
    final markers = <MapMarker>[
      // Captain marker (current location)
      if (_captainLat != null && _captainLng != null)
        MapMarker(
          point: LatLng(_captainLat!, _captainLng!),
          assetPath: _assetForVehicleType(widget.ride.vehicleType),
          bearingDegrees: _captainBearingDegrees,
          size: 45,
        ),
      // Pickup marker
      if (widget.ride.pickupLatitude != null &&
          widget.ride.pickupLongitude != null)
        MapMarker(
          point:
              LatLng(widget.ride.pickupLatitude!, widget.ride.pickupLongitude!),
          icon: Icons.person_pin_circle,
          color: _gold,
        ),
      // Drop marker
      if (widget.ride.dropLatitude != null && widget.ride.dropLongitude != null)
        MapMarker(
          point: LatLng(widget.ride.dropLatitude!, widget.ride.dropLongitude!),
          icon: Icons.location_on,
          color: _green,
        ),
    ];
    final routes = <MapRoute>[];
    if (_routePoints.isNotEmpty) {
      routes.add(
        MapRoute(
          points: _routePoints,
          color: _green,
        ),
      );
    }

    return Scaffold(
      backgroundColor: _bg,
      body: Stack(
        children: [
          // Map
          Allin1MapWidget(
            center: mapCenter,
            zoom: 15,
            markers: markers,
            routes: routes,
            mapController: _mapController,
            onMapReady: _handleRideMapReady,
          ),

          // Top Bar
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // Back button
                  DecoratedBox(
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: IconButton(
                      onPressed: () => Navigator.of(context).pop(),
                      icon: const Icon(Icons.arrow_back, color: _text),
                    ),
                  ),
                  // Ride ID badge
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: _border),
                    ),
                    child: Text(
                      'Ride: ${widget.rideDocId.substring(0, 8)}...',
                      style: const TextStyle(
                        color: _muted,
                        fontSize: 12,
                        fontFamily: 'monospace',
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Bottom Sheet with Ride Details & Actions
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildRideDetails(),
                _buildActionButtons(),
              ],
            ),
          ),

          // Loading indicator
          if (_isLoading)
            const Positioned.fill(
              child: Center(
                child: CircularProgressIndicator(color: _purple),
              ),
            ),
        ],
      ),
    );
  }
}
