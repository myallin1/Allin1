import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../models/ride_model.dart';
import '../../services/category_gateway_service.dart';
import '../../services/localization_service.dart';
import '../../services/location_service.dart';
import '../../services/map_service.dart';
import '../../services/session_service.dart';
import '../../widgets/allin1_map_widget.dart';
import '../../widgets/vehicle_selection_bottom_sheet.dart';
import '../login_screen.dart';
import '../payment_screen.dart';
import 'ride_search_screen.dart';
import 'ride_tracking_screen.dart';

enum _ServiceCategory {
  bike,
  auto,
  cab,
  parcel,
}

// Approximate Erode road paths aligned to major corridors such as
// Brough Road, EVN Road, and Perundurai Road for ambient traffic.
const List<List<LatLng>> _erodeTrafficLoops = <List<LatLng>>[
  <LatLng>[
    LatLng(11.3468, 77.7210),
    LatLng(11.3463, 77.7203),
    LatLng(11.3458, 77.7196),
    LatLng(11.3452, 77.7188),
    LatLng(11.3447, 77.7181),
    LatLng(11.3441, 77.7173),
    LatLng(11.3435, 77.7166),
    LatLng(11.3429, 77.7158),
    LatLng(11.3424, 77.7151),
    LatLng(11.3419, 77.7144),
  ],
  <LatLng>[
    LatLng(11.3479, 77.7228),
    LatLng(11.3472, 77.7221),
    LatLng(11.3466, 77.7214),
    LatLng(11.3459, 77.7206),
    LatLng(11.3452, 77.7199),
    LatLng(11.3445, 77.7192),
    LatLng(11.3438, 77.7186),
    LatLng(11.3431, 77.7180),
    LatLng(11.3423, 77.7175),
    LatLng(11.3416, 77.7169),
  ],
  <LatLng>[
    LatLng(11.3402, 77.7248),
    LatLng(11.3408, 77.7241),
    LatLng(11.3414, 77.7233),
    LatLng(11.3420, 77.7226),
    LatLng(11.3427, 77.7218),
    LatLng(11.3434, 77.7210),
    LatLng(11.3441, 77.7203),
    LatLng(11.3448, 77.7196),
    LatLng(11.3454, 77.7189),
    LatLng(11.3460, 77.7182),
  ],
  <LatLng>[
    LatLng(11.3398, 77.7283),
    LatLng(11.3384, 77.7308),
    LatLng(11.3369, 77.7336),
    LatLng(11.3355, 77.7363),
    LatLng(11.3341, 77.7392),
    LatLng(11.3327, 77.7420),
    LatLng(11.3311, 77.7450),
    LatLng(11.3295, 77.7482),
    LatLng(11.3280, 77.7515),
  ],
  <LatLng>[
    LatLng(11.3410, 77.7171),
    LatLng(11.3374, 77.7108),
    LatLng(11.3338, 77.7043),
    LatLng(11.3302, 77.6975),
    LatLng(11.3268, 77.6910),
    LatLng(11.3233, 77.6846),
    LatLng(11.3196, 77.6782),
    LatLng(11.3160, 77.6718),
  ],
  <LatLng>[
    LatLng(11.3520, 77.7280),
    LatLng(11.3560, 77.7240),
    LatLng(11.3600, 77.7198),
    LatLng(11.3642, 77.7153),
    LatLng(11.3680, 77.7109),
    LatLng(11.3718, 77.7065),
    LatLng(11.3754, 77.7020),
    LatLng(11.3792, 77.6974),
  ],
  <LatLng>[
    LatLng(11.3290, 77.7190),
    LatLng(11.3248, 77.7248),
    LatLng(11.3206, 77.7307),
    LatLng(11.3164, 77.7368),
    LatLng(11.3122, 77.7429),
    LatLng(11.3081, 77.7490),
    LatLng(11.3040, 77.7552),
    LatLng(11.3000, 77.7614),
  ],
];

const List<List<LatLng>> _dummyTrafficRoutePairs = <List<LatLng>>[
  <LatLng>[LatLng(11.3468, 77.7210), LatLng(11.3419, 77.7144)],
  <LatLng>[LatLng(11.3479, 77.7228), LatLng(11.3416, 77.7169)],
  <LatLng>[LatLng(11.3402, 77.7248), LatLng(11.3460, 77.7182)],
  <LatLng>[LatLng(11.3398, 77.7283), LatLng(11.3280, 77.7515)],
  <LatLng>[LatLng(11.3410, 77.7171), LatLng(11.3160, 77.6718)],
  <LatLng>[LatLng(11.3520, 77.7280), LatLng(11.3792, 77.6974)],
  <LatLng>[LatLng(11.3290, 77.7190), LatLng(11.3000, 77.7614)],
];

const List<Map<String, dynamic>> _defaultSearchLocations =
    <Map<String, dynamic>>[
  <String, dynamic>{
    'name': 'Erode Bus Stand',
    'full': 'Central Bus Stand, Erode, Tamil Nadu',
    'lat': 11.3419,
    'lng': 77.7172,
    'provider': 'favorite',
    'type': 'recent',
  },
  <String, dynamic>{
    'name': 'Erode Railway Station',
    'full': 'Erode Junction, Chennimalai Road, Erode',
    'lat': 11.3428,
    'lng': 77.7282,
    'provider': 'favorite',
    'type': 'recent',
  },
  <String, dynamic>{
    'name': 'B.P. Agraharam',
    'full': 'B.P. Agraharam, Erode, Tamil Nadu',
    'lat': 11.3577,
    'lng': 77.7321,
    'provider': 'favorite',
    'type': 'favorite',
  },
  <String, dynamic>{
    'name': 'Periyar Nagar',
    'full': 'Periyar Nagar, Erode, Tamil Nadu',
    'lat': 11.3347,
    'lng': 77.7207,
    'provider': 'favorite',
    'type': 'favorite',
  },
];

LatLng _lerpLatLng(LatLng a, LatLng b, double t) {
  return LatLng(
    a.latitude + ((b.latitude - a.latitude) * t),
    a.longitude + ((b.longitude - a.longitude) * t),
  );
}

LatLng _offsetAlongSegment(
  LatLng start,
  LatLng end,
  LatLng point,
  double laneOffset,
) {
  final dx = end.longitude - start.longitude;
  final dy = end.latitude - start.latitude;
  final length = sqrt((dx * dx) + (dy * dy));
  if (length == 0) {
    return point;
  }
  final perpLat = -dx / length;
  final perpLng = dy / length;
  return LatLng(
    point.latitude + (perpLat * laneOffset),
    point.longitude + (perpLng * laneOffset),
  );
}

LatLng _pointOnPath(List<LatLng> path, double progress, double laneOffset) {
  if (path.isEmpty) {
    return const LatLng(11.3410, 77.7171);
  }
  if (path.length == 1) {
    return path.first;
  }
  final clampedProgress = progress.clamp(0.0, 1.0);
  final segmentCount = path.length - 1;
  final scaled = clampedProgress * segmentCount;
  final segmentIndex = scaled.floor().clamp(0, segmentCount - 1);
  final nextIndex = (segmentIndex + 1).clamp(1, path.length - 1);
  final localT = scaled - scaled.floorToDouble();
  final point = _lerpLatLng(path[segmentIndex], path[nextIndex], localT);
  return _offsetAlongSegment(
    path[segmentIndex],
    path[nextIndex],
    point,
    laneOffset,
  );
}

double _bearingBetween(LatLng start, LatLng end) {
  final lat1 = start.latitude * pi / 180;
  final lat2 = end.latitude * pi / 180;
  final dLng = (end.longitude - start.longitude) * pi / 180;
  final y = sin(dLng) * cos(lat2);
  final x = (cos(lat1) * sin(lat2)) - (sin(lat1) * cos(lat2) * cos(dLng));
  return (atan2(y, x) * 180 / pi + 360) % 360;
}

double _bearingOnPath(List<LatLng> path, double progress, int direction) {
  if (path.length < 2) {
    return 0;
  }
  final clampedProgress = progress.clamp(0.0, 1.0);
  final segmentCount = path.length - 1;
  final scaled = clampedProgress * segmentCount;
  final segmentIndex = scaled.floor().clamp(0, segmentCount - 1);
  final nextIndex = (segmentIndex + 1).clamp(1, path.length - 1);
  final start = path[segmentIndex];
  final end = path[nextIndex];
  return direction >= 0
      ? _bearingBetween(start, end)
      : _bearingBetween(end, start);
}

class _DummyVehicleState {
  _DummyVehicleState({
    required this.id,
    required this.vehicleType,
    required this.busy,
    required this.loopIndex,
    required this.progress,
    required this.direction,
    required this.speedStep,
    required this.laneOffset,
  });

  final String id;
  final String vehicleType;
  final bool busy;
  final int loopIndex;
  final double speedStep;
  final double laneOffset;
  double progress;
  int direction;
  List<LatLng>? roadPath;

  List<LatLng> activePath() {
    final routedPath = roadPath;
    if (routedPath != null && routedPath.length > 1) {
      return routedPath;
    }
    return _erodeTrafficLoops[loopIndex];
  }

  LatLng project() {
    return _pointOnPath(
      activePath(),
      progress,
      laneOffset,
    );
  }

  double bearing() {
    return _bearingOnPath(
      activePath(),
      progress,
      direction,
    );
  }

  void advance(Random random) {
    final jitter = 0.65 + (random.nextDouble() * 0.7);
    progress += direction * speedStep * jitter;
    if (progress >= 1) {
      progress = 1;
      direction = -1;
    } else if (progress <= 0) {
      progress = 0;
      direction = 1;
    }
  }
}

class BikeBookingScreen extends StatefulWidget {
  const BikeBookingScreen({super.key});

  @override
  State<BikeBookingScreen> createState() => _BikeBookingScreenState();
}

class _BikeBookingScreenState extends State<BikeBookingScreen>
    with WidgetsBindingObserver {
  static const List<String> _restorableCustomerRideStatuses = <String>[
    'searching',
    'assigned',
    'accepted',
    'arriving',
    'started',
    'in_progress',
  ];
  static const Duration _pendingRideRestoreWindow = Duration(seconds: 90);
  static const Duration _activeRideRestoreWindow = Duration(hours: 24);
  // ── Style Tokens ──────────────────────────────────────────────
  static const Color _bg = Color(0xFFFFFBFE);
  static const Color _card = Color(0xFFFFFFFF);
  static const Color _accentOrange = Color(0xFFFF4FA3);
  static const Color _successGreen = Color(0xFFB21FFF);
  static const Color _border = Color(0x33FF4FA3);
  static const Color _textPrimary = Color(0xFF4A1236);
  static const Color _textSecondary = Color(0xFF8A4E72);

  // ── Controllers ───────────────────────────────────────────────
  final MapController _mapController = MapController();
  final MapController _searchMapController = MapController();
  final TextEditingController _pickupController = TextEditingController();
  final TextEditingController _dropController = TextEditingController();
  bool _mainMapReady = false;
  bool _searchMapReady = false;
  LatLng? _pendingMainMapCenter;
  double? _pendingMainMapZoom;
  LatLng? _pendingSearchMapCenter;
  double? _pendingSearchMapZoom;

  // ── Location State ────────────────────────────────────────────
  LatLng? _myPositionLatLng;
  final ValueNotifier<List<MapMarker>> _nearbyCaptainMarkersNotifier =
      ValueNotifier<List<MapMarker>>([]);
  final ValueNotifier<List<MapMarker>> _dummyHeroMarkersNotifier =
      ValueNotifier<List<MapMarker>>([]);
  List<Map<String, dynamic>> _onlineHeroSnapshots = [];
  StreamSubscription<DatabaseEvent>? _nearbyCaptainsSub;
  final Map<String, Timer> _dummyVehicleTimers = <String, Timer>{};
  final LocationService _locationService = LocationService();
  final MapService _mapService = MapService();
  List<LatLng> _routePoints = [];
  double? _routeDistanceKm;
  int? _routeEtaMinutes;
  int _routeRequestId = 0;
  final List<_DummyVehicleState> _ambientVehicles = <_DummyVehicleState>[];
  final Map<int, List<LatLng>> _dummyRouteCache = <int, List<LatLng>>{};
  final Set<int> _dummyRouteRequests = <int>{};

  // ── Search State ──────────────────────────────────────────────
  Map<String, dynamic>? _pickupLocation;
  Map<String, dynamic>? _dropLocation;
  bool _isSearchOverlayOpen = false;
  bool _isFocusingDrop = true;
  bool _isSearching = false;
  bool _isResolvingPinAddress = false;
  List<Map<String, dynamic>> _searchSuggestions = [];
  String _activeSearchQuery = '';
  Timer? _debounceTimer;
  Timer? _searchMapIdleTimer;
  LatLng? _searchMapCenter;
  Map<String, dynamic>? _pinDropLocation;
  int _searchRequestId = 0;
  int _reverseLookupId = 0;
  bool _isRestoringActiveRide = false;
  RideModel? _pendingActiveRide;
  String? _pendingActiveRideDocId;
  String? _pendingActiveRideStatus;
  String? _pendingActiveRidePaymentStatus;
  double? _pendingActiveRideAmount;

  // ── Fare State ────────────────────────────────────────────────
  Map<String, dynamic>? _fares;
  double? _estimatedFare;
  _ServiceCategory _selectedCategory = _ServiceCategory.bike;
  bool _isInitializingLocation = true;
  bool _locationPermissionRequired = false;
  String _startupStatus = 'Loading map and checking GPS...';

  // ── Lifecycle ─────────────────────────────────────────────────
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _mapService.initialize();
    _loadFareConfig();
    _listenToNearbyCaptains();
    _initLocationTracking();
    unawaited(_restoreActiveRideIfNeeded());
    Timer(const Duration(seconds: 1), () {
      if (!mounted) {
        return;
      }
      _ensureDummyTrafficInitialized();
      unawaited(_hydrateDummyTrafficRoutes());
      _refreshHeroMarkers();
    });
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      debugPrint('[BikeBookingScreen] App resumed - refreshing map surface');
      if (!mounted) {
        return;
      }
      setState(() {});
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) {
          return;
        }
        _moveMainMap(_myPositionLatLng ?? kErodeCenter, 15.5);
        if (_searchMapCenter != null) {
          _moveSearchMap(_searchMapCenter!, 16);
        }
      });
      unawaited(_restoreActiveRideIfNeeded());
    }
  }

  void _returnToRootSafely() {
    if (!mounted) {
      return;
    }
    final navigator = Navigator.of(context);
    if (navigator.canPop()) {
      navigator.popUntil((route) => route.isFirst);
    }
  }

  /// T2: Normalize bottom-sheet vehicle key → hero profile category key.
  /// This is the single source of truth for the pipeline:
  ///   Customer books 'cab' → rides/{id}.category = 'car'
  ///   Hero registered as 'car' → stream filter matches 'car'
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

  DateTime? _rideTimestamp(Map<String, dynamic> data, List<String> keys) {
    for (final key in keys) {
      final value = data[key];
      if (value is Timestamp) {
        return value.toDate();
      }
    }
    return null;
  }

  bool _isRestorableCustomerRide(
    Map<String, dynamic> data,
    String customerUid,
  ) {
    final customerId = (data['customerId'] as String?)?.trim();
    if (customerId != customerUid) {
      return false;
    }
    final status = (data['status'] as String? ?? '').trim();
    if (!_restorableCustomerRideStatuses.contains(status)) {
      return false;
    }
    final activityAt = _rideTimestamp(
      data,
      const <String>['acceptedAt', 'assignedAt', 'startedAt', 'createdAt'],
    );
    if (activityAt == null) {
      return false;
    }
    final cutoff = (status == 'searching')
        ? DateTime.now().subtract(_pendingRideRestoreWindow)
        : DateTime.now().subtract(_activeRideRestoreWindow);
    return activityAt.isAfter(cutoff);
  }

  bool _isExpiredSearchingRide(Map<String, dynamic> data) {
    final status = (data['status'] as String? ?? '').trim();
    final createdAt = data['createdAt'];
    return status == 'searching' &&
        createdAt is Timestamp &&
        DateTime.now().difference(createdAt.toDate()).inSeconds > 90;
  }

  RideModel _rideFromDocument(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    return RideModel(
      id: doc.id,
      rideId: doc.id,
      customerId: data['customerId'] as String? ?? data['userId'] as String?,
      heroId: data['heroId'] as String?,
      pickupAddress:
          data['pickupAddress'] as String? ?? data['pickupLocation'] as String?,
      dropAddress:
          data['dropAddress'] as String? ?? data['dropLocation'] as String?,
      pickupLatitude: (data['pickupLatitude'] as num?)?.toDouble(),
      pickupLongitude: (data['pickupLongitude'] as num?)?.toDouble(),
      dropLatitude: (data['dropLatitude'] as num?)?.toDouble(),
      dropLongitude: (data['dropLongitude'] as num?)?.toDouble(),
      fare: (data['fare'] as num?)?.toDouble(),
      estimatedFare: (data['estimatedFare'] as num?)?.toDouble() ??
          (data['fare'] as num?)?.toDouble(),
      distanceKm: (data['distanceKm'] as num?)?.toDouble() ??
          (data['distance_km'] as num?)?.toDouble(),
      etaMinutes: (data['etaMinutes'] as num?)?.toInt(),
      status: data['status'] as String?,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      acceptedAt: (data['acceptedAt'] as Timestamp?)?.toDate(),
      completedAt: (data['completedAt'] as Timestamp?)?.toDate(),
      heroName: data['heroName'] as String? ?? data['captainName'] as String?,
      heroPhone:
          data['heroPhone'] as String? ?? data['captainPhone'] as String?,
      heroVehicleNumber: data['heroVehicleNumber'] as String? ??
          data['captainBike'] as String?,
      heroRating: (data['heroRating'] as num?)?.toDouble() ??
          (data['captainRating'] as num?)?.toDouble(),
      heroLat: (data['heroLat'] as num?)?.toDouble() ??
          (data['captainLat'] as num?)?.toDouble(),
      heroLng: (data['heroLng'] as num?)?.toDouble() ??
          (data['captainLng'] as num?)?.toDouble(),
    );
  }

  Future<void> _restoreActiveRideIfNeeded({bool force = false}) async {
    if ((_isRestoringActiveRide && !force) || !mounted) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    _isRestoringActiveRide = true;
    try {
      final query = FirebaseFirestore.instance
          .collection('rides')
          .where('customerId', isEqualTo: user.uid)
          .where('status', whereIn: _restorableCustomerRideStatuses);

      QuerySnapshot<Map<String, dynamic>> snap;
      try {
        // ── Cache-first read: Populate UI instantly from local disk ──
        snap = await query.get(const GetOptions(source: Source.cache));
        if (snap.docs.isEmpty) {
          snap = await query.get(const GetOptions(source: Source.server));
        }
      } catch (_) {
        // Fallback to server if cache is unavailable or fails
        snap = await query.get(const GetOptions(source: Source.server));
      }

      if (!mounted) {
        return;
      }

      final expiredSearchDocs = snap.docs.where((doc) {
        final data = doc.data();
        return (data['customerId'] as String?)?.trim() == user.uid &&
            _isExpiredSearchingRide(data);
      }).toList();

      for (final doc in expiredSearchDocs) {
        unawaited(
          doc.reference.update({
            'status': 'cancelled',
            'cancelledBy': 'system',
            'cancelledAt': FieldValue.serverTimestamp(),
          }),
        );
      }
      if (!mounted) {
        return;
      }

      final docs = snap.docs.where((doc) {
        return _isRestorableCustomerRide(doc.data(), user.uid);
      }).toList()
        ..sort((a, b) {
          final aTime = _rideTimestamp(
                a.data(),
                const <String>[
                  'acceptedAt',
                  'assignedAt',
                  'startedAt',
                  'createdAt',
                ],
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          final bTime = _rideTimestamp(
                b.data(),
                const <String>[
                  'acceptedAt',
                  'assignedAt',
                  'startedAt',
                  'createdAt',
                ],
              ) ??
              DateTime.fromMillisecondsSinceEpoch(0);
          return bTime.compareTo(aTime);
        });

      if (docs.isEmpty) {
        if (mounted &&
            (_pendingActiveRide != null || _pendingActiveRideDocId != null)) {
          setState(() {
            _pendingActiveRide = null;
            _pendingActiveRideDocId = null;
            _pendingActiveRideStatus = null;
            _pendingActiveRidePaymentStatus = null;
            _pendingActiveRideAmount = null;
          });
        }
        return;
      }

      final doc = docs.first;
      final docData = doc.data();
      final ride = _rideFromDocument(doc);
      final status = (docData['status'] as String? ?? 'searching').trim();
      final paymentStatus = (docData['paymentStatus'] as String?)?.trim();
      final amount = (docData['finalFare'] as num?)?.toDouble() ??
          (docData['actualFare'] as num?)?.toDouble() ??
          (docData['amountPaid'] as num?)?.toDouble() ??
          (docData['lockedFare'] as num?)?.toDouble() ??
          (docData['estimatedFare'] as num?)?.toDouble() ??
          (docData['fare'] as num?)?.toDouble();
      if (!mounted) {
        return;
      }
      setState(() {
        _pendingActiveRide = ride;
        _pendingActiveRideDocId = doc.id;
        _pendingActiveRideStatus = status;
        _pendingActiveRidePaymentStatus = paymentStatus;
        _pendingActiveRideAmount = amount;
      });
    } catch (e) {
      debugPrint('[BikeBookingScreen] Active ride restore failed: $e');
    } finally {
      _isRestoringActiveRide = false;
    }
  }

  Future<void> _continueActiveRide() async {
    final ride = _pendingActiveRide;
    final rideDocId = _pendingActiveRideDocId;
    var status = (_pendingActiveRideStatus ?? '').trim();
    var paymentStatus = (_pendingActiveRidePaymentStatus ?? '').trim();
    var amount = _pendingActiveRideAmount;
    if (ride == null || rideDocId == null || !mounted) {
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }

    try {
      final rideSnap = await FirebaseFirestore.instance
          .collection('rides')
          .doc(rideDocId)
          .get();
      if (!mounted) {
        return;
      }
      final data = rideSnap.data();
      if (!rideSnap.exists ||
          data == null ||
          (data['customerId'] as String?)?.trim() != user.uid) {
        setState(() {
          _pendingActiveRide = null;
          _pendingActiveRideDocId = null;
          _pendingActiveRideStatus = null;
          _pendingActiveRidePaymentStatus = null;
          _pendingActiveRideAmount = null;
        });
        return;
      }
      status = (data['status'] as String? ?? '').trim();
      paymentStatus = (data['paymentStatus'] as String? ?? '').trim();
      final createdAt = data['createdAt'];
      if (status == 'searching' &&
          createdAt is Timestamp &&
          DateTime.now().difference(createdAt.toDate()).inSeconds > 90) {
        await rideSnap.reference.update({
          'status': 'cancelled',
          'cancelledBy': 'system',
          'cancelledAt': FieldValue.serverTimestamp(),
        });
        if (!mounted) {
          return;
        }
        setState(() {
          _pendingActiveRide = null;
          _pendingActiveRideDocId = null;
          _pendingActiveRideStatus = null;
          _pendingActiveRidePaymentStatus = null;
          _pendingActiveRideAmount = null;
        });
        return;
      }
      amount = (data['finalFare'] as num?)?.toDouble() ??
          (data['actualFare'] as num?)?.toDouble() ??
          (data['amountPaid'] as num?)?.toDouble() ??
          (data['lockedFare'] as num?)?.toDouble() ??
          (data['estimatedFare'] as num?)?.toDouble() ??
          (data['fare'] as num?)?.toDouble() ??
          amount;
      if (status == 'completed' ||
          status == 'rated' ||
          status.startsWith('cancelled')) {
        setState(() {
          _pendingActiveRide = null;
          _pendingActiveRideDocId = null;
          _pendingActiveRideStatus = null;
          _pendingActiveRidePaymentStatus = null;
          _pendingActiveRideAmount = null;
        });
        return;
      }
    } catch (e) {
      debugPrint('[BikeBookingScreen] Active ride refresh failed: $e');
    }

    if (_shouldResumePaymentFlow(status, paymentStatus)) {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => PaymentScreen(
            amount: amount ??
                ride.estimatedFare?.toDouble() ??
                ride.fare?.toDouble() ??
                0.0,
            note: 'Bike Taxi Ride',
            rideDocId: rideDocId,
          ),
        ),
      );
      if (mounted) {
        await _restoreActiveRideIfNeeded(force: true);
      }
      return;
    }

    if (status == 'searching') {
      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (_) => RideSearchScreen(
            ride: ride,
            existingRideDocId: rideDocId,
          ),
        ),
      );
      return;
    }

    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => RideTrackingScreen(
          ride: ride,
          rideDocId: rideDocId,
        ),
      ),
    );
  }

  Future<void> _cancelPendingActiveRide() async {
    final rideDocId = _pendingActiveRideDocId;
    if (rideDocId == null) {
      return;
    }
    // ── Optimistic UI: dismiss ride banner immediately before network write ──
    // The update propagates via the ride stream; on failure the user is notified.
    if (mounted) {
      setState(() {
        _pendingActiveRide = null;
        _pendingActiveRideDocId = null;
        _pendingActiveRideStatus = null;
        _pendingActiveRidePaymentStatus = null;
        _pendingActiveRideAmount = null;
      });
    }
    try {
      await FirebaseFirestore.instance
          .collection('rides')
          .doc(rideDocId)
          .update({
        'status': 'cancelled',
        'cancelledBy': 'customer',
        'cancelledAt': FieldValue.serverTimestamp(),
      });
      if (mounted) {
        _showError('Ride cancelled successfully');
      }
    } catch (e) {
      debugPrint('[BikeBookingScreen] Failed to cancel active ride: $e');
      if (mounted) {
        _showError('Unable to cancel ride right now');
        // Re-hydrate banner since cancel failed
        unawaited(_restoreActiveRideIfNeeded(force: true));
      }
    }
  }

  String _activeRideLabel(String status) {
    switch (status) {
      case 'searching':
        return 'Finding your Hero';
      case 'assigned':
        return 'Hero assigned';
      case 'accepted':
      case 'arriving':
        return 'Hero is arriving';
      case 'started':
      case 'in_progress':
        return 'Ride in progress';
      case 'completed':
        return 'Bill generated';
      case 'paid':
        return 'Payment confirmed';
      default:
        return 'Ongoing ride';
    }
  }

  bool _shouldResumePaymentFlow(String status, String paymentStatus) {
    return paymentStatus == 'pending_collection' ||
        paymentStatus == 'awaiting_confirmation' ||
        paymentStatus == 'completed';
  }

  String _continueActionLabel(String status, String paymentStatus) {
    return _shouldResumePaymentFlow(status, paymentStatus)
        ? 'Continue Payment'
        : 'Continue Ride';
  }

  bool _canCancelPendingRide(String status, String paymentStatus) {
    return !_shouldResumePaymentFlow(status, paymentStatus);
  }

  void _moveMainMap(LatLng center, double zoom) {
    _pendingMainMapCenter = center;
    _pendingMainMapZoom = zoom;
    if (!_mainMapReady) {
      debugPrint('[BikeBookingScreen] Main map move queued until ready');
      return;
    }
    try {
      _mapController.move(center, zoom);
      _pendingMainMapCenter = null;
      _pendingMainMapZoom = null;
    } catch (e) {
      debugPrint('[BikeBookingScreen] Main map move failed: $e');
    }
  }

  void _moveSearchMap(LatLng center, double zoom) {
    _pendingSearchMapCenter = center;
    _pendingSearchMapZoom = zoom;
    if (!_searchMapReady) {
      debugPrint('[BikeBookingScreen] Search map move queued until ready');
      return;
    }
    try {
      _searchMapController.move(center, zoom);
      _pendingSearchMapCenter = null;
      _pendingSearchMapZoom = null;
    } catch (e) {
      debugPrint('[BikeBookingScreen] Search map move failed: $e');
    }
  }

  void _flushMainMapMove() {
    _mainMapReady = true;
    final center = _pendingMainMapCenter ?? _mapCenter ?? kErodeCenter;
    final zoom = _pendingMainMapZoom ?? 15.5;
    _moveMainMap(center, zoom);
  }

  void _flushSearchMapMove() {
    _searchMapReady = true;
    final center = _pendingSearchMapCenter ?? _searchMapCenter;
    final zoom = _pendingSearchMapZoom ?? 16;
    if (center != null) {
      _moveSearchMap(center, zoom);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _nearbyCaptainsSub?.cancel();
    for (final timer in _dummyVehicleTimers.values) {
      timer.cancel();
    }
    _dummyVehicleTimers.clear();
    _debounceTimer?.cancel();
    _searchMapIdleTimer?.cancel();
    _pickupController.dispose();
    _dropController.dispose();
    _mapController.dispose();
    _searchMapController.dispose();
    super.dispose();
  }

  // ── Fare Config ───────────────────────────────────────────────
  // CategoryGatewayService.loadRideFares() is already cache-backed (in-memory +
  // Firestore persistence), so fares are available from disk on the first frame
  // after the initial install and do not block the UI.
  Future<void> _loadFareConfig() async {
    try {
      final fares = await CategoryGatewayService().loadRideFares();
      if (mounted) {
        setState(() => _fares = fares);
      }
    } catch (e) {
      debugPrint('Fare load error: $e');
    }
  }

  // ── Nearby Captains ───────────────────────────────────────────
  void _listenToNearbyCaptains() {
    _nearbyCaptainsSub =
        FirebaseDatabase.instance.ref('online_heroes').onValue.listen((event) {
      final raw = event.snapshot.value as Map<dynamic, dynamic>?;
      final heroes = <Map<String, dynamic>>[];
      if (raw != null) {
        raw.forEach((key, value) {
          if (value is Map) {
            heroes.add(
              <String, dynamic>{
                'id': '$key',
                'lat': (value['lat'] as num?)?.toDouble() ??
                    (value['latitude'] as num?)?.toDouble(),
                'lng': (value['lng'] as num?)?.toDouble() ??
                    (value['longitude'] as num?)?.toDouble(),
                'vehicleType': (value['vehicleType'] as String?)?.trim(),
                'name': (value['captainName'] as String?)?.trim() ??
                    (value['name'] as String?)?.trim() ??
                    'Hero',
                'isAvailable': value['isAvailable'] as bool?,
              },
            );
          }
        });
      }
      _onlineHeroSnapshots = heroes;
      _refreshHeroMarkers();
    });
  }

  // ── Location Tracking ─────────────────────────────────────────
  Future<void> _initLocationTracking() async {
    if (mounted) {
      setState(() {
        _isInitializingLocation = true;
        _locationPermissionRequired = false;
        _startupStatus = 'Checking GPS permission...';
      });
    }
    try {
      final hasPermission = await _locationService.checkAndRequestPermission();
      if (!hasPermission) {
        if (mounted) {
          setState(() {
            _isInitializingLocation = false;
            _locationPermissionRequired = true;
            _startupStatus =
                'Enable location services to detect your live pickup.';
          });
        }
        return;
      }

      if (mounted) {
        setState(() {
          _startupStatus = 'Getting precise live location...';
        });
      }

      final pos = await _locationService.getCurrentLocation();
      if (pos == null) {
        if (mounted) {
          setState(() {
            _isInitializingLocation = true;
            _locationPermissionRequired = false;
            _startupStatus =
                'Loading map / Checking GPS... you can browse while we locate you.';
          });
        }
      } else {
        _updateUserLocation(
          LatLng(pos.latitude, pos.longitude),
          animateMap: true,
        );
      }

      if (mounted && _isInitializingLocation) {
        setState(() {
          _isInitializingLocation = false;
          _locationPermissionRequired = false;
          _startupStatus = 'Live location ready';
        });
      }
    } catch (e) {
      debugPrint('Location error: $e');
      if (mounted) {
        setState(() {
          _isInitializingLocation = false;
          _locationPermissionRequired = true;
          _startupStatus = 'Unable to access live location. Please enable GPS.';
        });
      }
    }
  }

  void _updateUserLocation(LatLng position, {bool animateMap = false}) {
    if (!mounted) {
      return;
    }
    _myPositionLatLng = position;
    if (_pickupController.text.trim().isEmpty ||
        _pickupController.text == 'Current Location') {
      setState(() {
        _pickupLocation = {
          'name': 'Current Location',
          'lat': position.latitude,
          'lng': position.longitude,
        };
        _pickupController.text = 'Current Location';
      });
    }
    _ensureDummyTrafficInitialized();
    _refreshHeroMarkers();
    if (_pickupLocation != null && _dropLocation != null) {
      unawaited(_loadRoadRoute());
    }
    if (animateMap) {
      _moveMainMap(position, 15.5);
    }
  }

  String get _selectedVehicleTypeKey {
    switch (_selectedCategory) {
      case _ServiceCategory.auto:
        return 'auto';
      case _ServiceCategory.cab:
        return 'cab';
      case _ServiceCategory.parcel:
        return 'parcel';
      case _ServiceCategory.bike:
        return 'bike';
    }
  }

  String? _assetForVehicleType(String vehicleType) {
    switch (vehicleType) {
      case 'auto':
        return 'assets/images/top_auto.png';
      case 'car':
      case 'cab':
      case 'mini-truck':
      case 'mini_truck':
      case 'truck':
        return 'assets/images/top_cab.png';
      case 'parcel':
        return 'assets/images/top_parcel.png';
      case 'bike':
      default:
        return 'assets/images/top_bike.png';
    }
  }

  IconData _fallbackIconForVehicleType(String vehicleType) {
    switch (vehicleType) {
      case 'auto':
        return Icons.electric_rickshaw_rounded;
      case 'car':
      case 'cab':
      case 'mini-truck':
      case 'mini_truck':
      case 'truck':
        return Icons.local_taxi_rounded;
      case 'parcel':
        return Icons.inventory_2_rounded;
      case 'bike':
      default:
        return Icons.two_wheeler_rounded;
    }
  }

  double _baseLaneOffsetForVehicleType(String vehicleType) {
    return 0;
  }

  double _assetBearingOffset(String vehicleType) {
    switch (vehicleType) {
      case 'auto':
      case 'cab':
      case 'parcel':
      case 'bike':
      default:
        return 0;
    }
  }

  double _progressBiasForVehicleType(String vehicleType) {
    switch (vehicleType) {
      case 'auto':
        return 0.18;
      case 'cab':
        return 0.42;
      case 'parcel':
        return 0.62;
      case 'bike':
      default:
        return 0;
    }
  }

  void _ensureDummyTrafficInitialized() {
    if (_ambientVehicles.isNotEmpty) {
      return;
    }

    final trafficMix = <String, int>{
      'bike': 4,
      'auto': 3,
      'cab': 2,
    };

    for (final entry in trafficMix.entries) {
      final random = Random(entry.key.hashCode);
      final slotGap = 1 / entry.value;
      final laneBase = _baseLaneOffsetForVehicleType(entry.key);
      final progressBias = _progressBiasForVehicleType(entry.key);
      for (var index = 0; index < entry.value; index++) {
        final loopIndex =
            (index + entry.key.length) % _erodeTrafficLoops.length;
        final baseProgress = ((index * slotGap) + progressBias) % 1;
        final jitter = (random.nextDouble() - 0.5) * 0.08;
        final vehicle = _DummyVehicleState(
          id: '${entry.key}_$index',
          vehicleType: entry.key,
          busy: index.isOdd,
          loopIndex: loopIndex,
          progress: (baseProgress + jitter) % 1,
          direction: random.nextBool() ? 1 : -1,
          speedStep: 0.0025 + (random.nextDouble() * 0.0028),
          laneOffset: laneBase,
        );
        _ambientVehicles.add(vehicle);
        _scheduleVehicleTick(vehicle, random.nextInt(1600));
      }
    }
    unawaited(_hydrateDummyTrafficRoutes());
  }

  Future<void> _hydrateDummyTrafficRoutes() async {
    final routeIndexes = _ambientVehicles
        .map((vehicle) => vehicle.loopIndex)
        .toSet()
        .where((index) => !_dummyRouteCache.containsKey(index))
        .where((index) => !_dummyRouteRequests.contains(index))
        .toList();

    for (final routeIndex in routeIndexes) {
      _dummyRouteRequests.add(routeIndex);
      final pair =
          _dummyTrafficRoutePairs[routeIndex % _dummyTrafficRoutePairs.length];
      try {
        final route = await _mapService.getRoute(pair.first, pair.last);
        if (!mounted) {
          return;
        }
        final path = route?.points ?? const <LatLng>[];
        if (path.length > 2) {
          _dummyRouteCache[routeIndex] = path;
          for (final vehicle in _ambientVehicles) {
            if (vehicle.loopIndex == routeIndex) {
              vehicle.roadPath = path;
            }
          }
          _refreshHeroMarkers();
        }
      } catch (e) {
        debugPrint('Dummy traffic route load error: $e');
      } finally {
        _dummyRouteRequests.remove(routeIndex);
      }
    }
  }

  void _scheduleVehicleTick(_DummyVehicleState vehicle, [int? initialDelayMs]) {
    _dummyVehicleTimers[vehicle.id]?.cancel();
    final seed = vehicle.id.hashCode ^
        DateTime.now().microsecondsSinceEpoch ^
        (initialDelayMs ?? 0);
    final random = Random(seed);
    final delay = Duration(
      milliseconds: initialDelayMs ?? (2500 + random.nextInt(2500)),
    );
    _dummyVehicleTimers[vehicle.id] = Timer(delay, () {
      if (!mounted) {
        return;
      }
      vehicle.advance(
        Random(
          vehicle.id.hashCode ^ DateTime.now().millisecondsSinceEpoch,
        ),
      );
      _refreshHeroMarkers();
      _scheduleVehicleTick(vehicle);
    });
  }

  void _refreshHeroMarkers() {
    if (!mounted) {
      return;
    }

    _ensureDummyTrafficInitialized();
    final liveNearbyMarkers = _onlineHeroSnapshots.where((hero) {
      final lat = hero['lat'] as double?;
      final lng = hero['lng'] as double?;
      if (lat == null || lng == null || _myPositionLatLng == null) {
        return false;
      }
      final isAvailable = hero['isAvailable'] as bool?;
      if (isAvailable == false) {
        return false;
      }
      final distanceMeters = Geolocator.distanceBetween(
        _myPositionLatLng!.latitude,
        _myPositionLatLng!.longitude,
        lat,
        lng,
      );
      return distanceMeters <= 3000;
    }).map(
      (hero) {
        final vehicleType =
            (hero['vehicleType'] as String?)?.toLowerCase().trim() ?? 'bike';
        return MapMarker(
          point: LatLng(
            hero['lat'] as double,
            hero['lng'] as double,
          ),
          color: _accentOrange,
          assetPath: _assetForVehicleType(vehicleType),
          icon: _fallbackIconForVehicleType(vehicleType),
          label: hero['name'] as String?,
          size: 46,
        );
      },
    ).toList();

    final busyMarkers = _ambientVehicles
        .map(
          (vehicle) => MapMarker(
            point: vehicle.project(),
            color: _successGreen,
            assetPath: _assetForVehicleType(vehicle.vehicleType),
            icon: _fallbackIconForVehicleType(vehicle.vehicleType),
            bearingDegrees:
                vehicle.bearing() + _assetBearingOffset(vehicle.vehicleType),
            size: 45,
          ),
        )
        .toList();

    _nearbyCaptainMarkersNotifier.value = liveNearbyMarkers;
    _dummyHeroMarkersNotifier.value = busyMarkers;
  }

  Future<void> _loadRoadRoute() async {
    if (_pickupLocation == null || _dropLocation == null) {
      if (mounted && _routePoints.isNotEmpty) {
        setState(() {
          _routePoints = [];
          _routeDistanceKm = null;
          _routeEtaMinutes = null;
        });
      }
      return;
    }

    final requestId = ++_routeRequestId;
    final start = LatLng(
      (_pickupLocation!['lat'] as num).toDouble(),
      (_pickupLocation!['lng'] as num).toDouble(),
    );
    final end = LatLng(
      (_dropLocation!['lat'] as num).toDouble(),
      (_dropLocation!['lng'] as num).toDouble(),
    );

    try {
      await _mapService.initialize();
      final route = await _mapService.getRoute(start, end);
      if (!mounted || requestId != _routeRequestId) {
        return;
      }
      final routePoints = route?.points ?? const <LatLng>[];
      debugPrint('Booking route points: ${routePoints.length}');
      setState(() {
        _routePoints = routePoints.length > 2 ? routePoints : [];
        if (route != null) {
          _routeDistanceKm = route.distanceMeters / 1000.0;
          _routeEtaMinutes = (route.durationSeconds / 60.0).round();
          _estimatedFare = RideModel.calculateFare(
            _routeDistanceKm!,
            _selectedVehicleTypeKey,
            fares: _fares,
          );
        } else {
          _routeDistanceKm = null;
          _routeEtaMinutes = null;
          _estimatedFare = null;
        }
      });
    } catch (e) {
      debugPrint('Route load error: $e');
      if (!mounted || requestId != _routeRequestId) {
        return;
      }
      setState(() {
        _routePoints = [];
        _routeDistanceKm = null;
        _routeEtaMinutes = null;
      });
    }
  }

  void _showError(String message) {
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.redAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  // ── Search ────────────────────────────────────────────────────
  void _openSearch({required bool focusDrop}) {
    setState(() {
      _isSearchOverlayOpen = true;
      _isFocusingDrop = focusDrop;
      _searchSuggestions = [];
      _activeSearchQuery = '';
      _searchMapReady = false;
    });
    _primeSearchMap();
  }

  void _closeSearch() {
    _debounceTimer?.cancel();
    _searchMapIdleTimer?.cancel();
    setState(() {
      _isSearchOverlayOpen = false;
      _isSearching = false;
      _isResolvingPinAddress = false;
      _searchSuggestions = [];
      _activeSearchQuery = '';
      _searchMapReady = false;
    });
  }

  void _onSearchChanged(String query) {
    _debounceTimer?.cancel();
    final normalizedQuery = query.trim();
    _activeSearchQuery = normalizedQuery;
    if (normalizedQuery.length < 3) {
      if (mounted) {
        setState(() {
          _isSearching = false;
          _searchSuggestions = [];
          _activeSearchQuery = normalizedQuery;
        });
      }
      return;
    }
    final requestId = ++_searchRequestId;
    setState(() {
      _isSearching = true;
      _activeSearchQuery = normalizedQuery;
    });

    _debounceTimer = Timer(const Duration(milliseconds: 500), () async {
      try {
        final suggestions = await _mapService.search(normalizedQuery);

        if (mounted && requestId == _searchRequestId) {
          setState(() {
            _searchSuggestions = suggestions;
            _isSearching = false;
          });
        }
      } catch (_) {
        if (mounted && requestId == _searchRequestId) {
          setState(() {
            _searchSuggestions = [];
            _isSearching = false;
          });
        }
      }
    });
  }

  Future<void> _selectLocation(Map<String, dynamic> location) async {
    final selectedPoint = LatLng(
      (location['lat'] as num).toDouble(),
      (location['lng'] as num).toDouble(),
    );
    setState(() {
      if (_isFocusingDrop) {
        _dropLocation = location;
        _dropController.text = location['name'] as String? ?? '';
      } else {
        _pickupLocation = location;
        _pickupController.text = location['name'] as String? ?? '';
      }
      _searchMapCenter = selectedPoint;
      _pinDropLocation = location;
    });
    _moveMainMap(selectedPoint, 15.5);

    if (_isFocusingDrop) {
      _closeSearch();
      if (_pickupLocation != null && _dropLocation != null) {
        await _loadRoadRoute();
        if (mounted) {
          _triggerBooking();
        }
      }
      return;
    } else {
      if (_pickupLocation != null && _dropLocation != null) {
        unawaited(_loadRoadRoute());
      }
    }
    setState(() {
      _isFocusingDrop = true;
      _searchSuggestions = [];
      _activeSearchQuery = '';
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_isSearchOverlayOpen) {
        _moveSearchMap(selectedPoint, 16);
        _scheduleReverseGeocode(selectedPoint);
      }
    });
  }

  LatLng _resolveSearchSeedPoint() {
    final activeLocation = _isFocusingDrop ? _dropLocation : _pickupLocation;
    if (activeLocation != null) {
      return LatLng(
        (activeLocation['lat'] as num).toDouble(),
        (activeLocation['lng'] as num).toDouble(),
      );
    }
    if (_isFocusingDrop && _pickupLocation != null) {
      return LatLng(
        (_pickupLocation!['lat'] as num).toDouble(),
        (_pickupLocation!['lng'] as num).toDouble(),
      );
    }
    return _myPositionLatLng ?? _mapCenter ?? kErodeCenter;
  }

  void _primeSearchMap() {
    final localization = context.read<LocalizationService>();
    final seedPoint = _resolveSearchSeedPoint();
    final focusedText =
        (_isFocusingDrop ? _dropController.text : _pickupController.text)
            .trim();

    setState(() {
      _searchMapCenter = seedPoint;
      _pinDropLocation = {
        'name': focusedText.isEmpty
            ? localization.t('finding_street_label')
            : focusedText,
        'full': focusedText.isEmpty
            ? localization.t('move_map_to_select_label')
            : focusedText,
        'lat': seedPoint.latitude,
        'lng': seedPoint.longitude,
      };
    });

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_isSearchOverlayOpen) {
        return;
      }
      _moveSearchMap(seedPoint, 16);
      _scheduleReverseGeocode(seedPoint);
    });
  }

  void _scheduleReverseGeocode(LatLng center) {
    _searchMapIdleTimer?.cancel();
    _searchMapIdleTimer = Timer(const Duration(milliseconds: 450), () {
      unawaited(_reverseGeocodeSearchCenter(center));
    });
  }

  Future<void> _reverseGeocodeSearchCenter([LatLng? center]) async {
    final lookupPoint = center ?? _searchMapCenter;
    if (lookupPoint == null) {
      return;
    }

    final requestId = ++_reverseLookupId;
    if (mounted) {
      setState(() {
        _isResolvingPinAddress = true;
      });
    }

    final result = await _mapService.reverseGeocode(lookupPoint);
    if (!mounted || requestId != _reverseLookupId) {
      return;
    }

    setState(() {
      _searchMapCenter = lookupPoint;
      _pinDropLocation = result ??
          <String, dynamic>{
            'name': 'Selected location',
            'full':
                '${lookupPoint.latitude.toStringAsFixed(5)}, ${lookupPoint.longitude.toStringAsFixed(5)}',
            'lat': lookupPoint.latitude,
            'lng': lookupPoint.longitude,
          };
      _isResolvingPinAddress = false;
    });
  }

  void _confirmPinnedLocation() {
    final center = _searchMapCenter;
    if (center == null) {
      return;
    }

    final location = _pinDropLocation ??
        <String, dynamic>{
          'name': 'Selected location',
          'full':
              '${center.latitude.toStringAsFixed(5)}, ${center.longitude.toStringAsFixed(5)}',
          'lat': center.latitude,
          'lng': center.longitude,
        };
    _selectLocation(location);
  }

  // ── Distance & ETA ────────────────────────────────────────────
  double get _distance {
    if (_routeDistanceKm != null && _routeDistanceKm! > 0) {
      return _routeDistanceKm!;
    }
    if (_pickupLocation == null || _dropLocation == null) {
      return 0;
    }
    return _haversineKm(
      (_pickupLocation!['lat'] as num).toDouble(),
      (_pickupLocation!['lng'] as num).toDouble(),
      (_dropLocation!['lat'] as num).toDouble(),
      (_dropLocation!['lng'] as num).toDouble(),
    );
  }

  int get _eta {
    if (_routeEtaMinutes != null && _routeEtaMinutes! > 0) {
      return _routeEtaMinutes!;
    }
    final d = _distance;
    if (d <= 0) {
      return 3;
    }
    return (d * 2.5 + 4).round().clamp(3, 45);
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const r = 6371.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLon = (lon2 - lon1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) *
            cos(lat2 * pi / 180) *
            sin(dLon / 2) *
            sin(dLon / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  // ── Booking ───────────────────────────────────────────────────
  void _triggerBooking() {
    final dist = _distance;
    if (dist <= 0) {
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) => VehicleSelectionBottomSheet(
        distanceKm: dist,
        fares: _fares,
        initialVehicleType: _selectedVehicleTypeKey,
        onConfirm: (vehicleType, fare) {
          Navigator.of(ctx).pop();
          _createRide(vehicleType, fare, dist);
        },
      ),
    );
  }

  Future<void> _createRide(String vehicleType, double fare, double dist) async {
    debugPrint('🔥 [RIDE CREATION] Entered _createRide() method!');
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      _showError('Authentication required');
      // Redirect to login after a brief delay so the user sees the error
      Future.delayed(const Duration(seconds: 1), () {
        if (!mounted) {
          return;
        }
        Navigator.of(context).pushReplacement(
          MaterialPageRoute<void>(
            builder: (_) => const LoginScreen(
              presetUserType: UserType.customer,
            ),
          ),
        );
      });
      return;
    }
    if (_pickupLocation == null || _dropLocation == null) {
      _showError('Please select pickup and destination');
      return;
    }
    try {
      final rideRef = FirebaseFirestore.instance.collection('rides').doc();
      final normalizedDist = double.parse(dist.toStringAsFixed(2));
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final userData = userDoc.data() ?? <String, dynamic>{};
      final customerPhone =
          ((userData['phoneNumber'] as String?)?.trim().isNotEmpty ?? false)
              ? (userData['phoneNumber'] as String).trim()
              : ((userData['phone'] as String?)?.trim().isNotEmpty ?? false)
                  ? (userData['phone'] as String).trim()
                  : (user.phoneNumber ?? '').trim();
      final pickupAddress = (_pickupLocation!['name'] as String? ?? '').trim();
      final dropAddress = (_dropLocation!['name'] as String? ?? '').trim();

      // ── Optimistic UI: Prepare the model and state before network call ──
      final rideModel = RideModel(
        id: rideRef.id,
        rideId: rideRef.id,
        customerId: user.uid,
        pickupAddress: pickupAddress,
        dropAddress: dropAddress,
        pickupLatitude: (_pickupLocation!['lat'] as num).toDouble(),
        pickupLongitude: (_pickupLocation!['lng'] as num).toDouble(),
        dropLatitude: (_dropLocation!['lat'] as num).toDouble(),
        dropLongitude: (_dropLocation!['lng'] as num).toDouble(),
        fare: fare,
        estimatedFare: fare,
        distanceKm: normalizedDist,
        etaMinutes: _eta,
        vehicleType: vehicleType,
        status: 'searching',
        createdAt: DateTime.now(),
      );

      // ── Optimistic Update: Transition UI immediately ──
      setState(() {
        _isSearching = true;
      });

      // ── Background Write: Start Firebase task without awaiting blocking ──
      debugPrint('🔥 [RIDE CREATION] About to create Firestore document...');
      unawaited(
        rideRef.set({
          'rideId': rideRef.id,
          'userId': user.uid,
          'customerId': user.uid,
          'customerPhone': customerPhone,
          'pickupAddress': pickupAddress,
          'dropAddress': dropAddress,
          'pickupLatitude': _pickupLocation!['lat'],
          'pickupLongitude': _pickupLocation!['lng'],
          'dropLatitude': _dropLocation!['lat'],
          'dropLongitude': _dropLocation!['lng'],
          'fare': fare,
          'estimatedFare': fare,
          'distanceKm': normalizedDist,
          'distance_km': normalizedDist,
          'etaMinutes': _eta,
          'vehicleType': vehicleType,
          'category': _normalizeCategoryKey(vehicleType),
          'vehicle_category': _normalizeCategoryKey(vehicleType),
          'status': 'searching',
          'createdAt': FieldValue.serverTimestamp(),
          'heroId': null,
          'captainId': null,
          'heroName': null,
          'heroPhone': null,
          'heroVehicleNumber': null,
          'heroModel': null,
          'heroRating': null,
          'heroEta': null,
        }).then((_) {
          debugPrint(
            '🔥 [RIDE CREATION] Firestore document created successfully! Doc ID: ${rideRef.id}',
          );
        }).catchError((Object e) {
          debugPrint(
            '[BikeBookingScreen] Background ride creation failed: $e',
          );
        }),
      );

      if (!mounted) {
        return;
      }

      // ── Instant Navigation: User sees the search screen immediately ──
      unawaited(
        Navigator.of(context).push(
          MaterialPageRoute<void>(
            builder: (_) => RideSearchScreen(
              ride: rideModel,
              existingRideDocId: rideRef.id,
            ),
          ),
        ),
      );
    } catch (e) {
      debugPrint('🔥 [RIDE CREATION ERROR] Crashed with: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to book ride. Please try again.'),
          ),
        );
      }
    }
  }

  List<MapMarker> get _mapMarkers {
    final markers = <MapMarker>[];
    if (_myPositionLatLng != null) {
      markers.add(
        MapMarker(
          point: _myPositionLatLng!,
          icon: Icons.navigation_rounded,
          color: Colors.lightBlueAccent,
          label: 'You',
          size: 42,
        ),
      );
    }
    if (_pickupLocation != null) {
      markers.add(
        MapMarker(
          point: LatLng(
            (_pickupLocation!['lat'] as num).toDouble(),
            (_pickupLocation!['lng'] as num).toDouble(),
          ),
          icon: Icons.my_location_rounded,
          color: _accentOrange,
          label: 'Pickup',
          size: 40,
        ),
      );
    }
    if (_dropLocation != null) {
      markers.add(
        MapMarker(
          point: LatLng(
            (_dropLocation!['lat'] as num).toDouble(),
            (_dropLocation!['lng'] as num).toDouble(),
          ),
          color: _successGreen,
          label: 'Drop',
          size: 44,
        ),
      );
    }
    markers
      ..addAll(_nearbyCaptainMarkersNotifier.value)
      ..addAll(_dummyHeroMarkersNotifier.value);
    return markers;
  }

  List<MapRoute> get _mapRoutes {
    if (_routePoints.isEmpty) {
      return const [];
    }
    return [
      MapRoute(
        points: _routePoints,
        color: _accentOrange.withValues(alpha: 0.85),
        strokeWidth: 5,
      ),
    ];
  }

  LatLng? get _mapCenter {
    if (_myPositionLatLng != null) {
      return _myPositionLatLng;
    }
    if (_pickupLocation != null) {
      return LatLng(
        (_pickupLocation!['lat'] as num).toDouble(),
        (_pickupLocation!['lng'] as num).toDouble(),
      );
    }
    if (_dropLocation != null) {
      return LatLng(
        (_dropLocation!['lat'] as num).toDouble(),
        (_dropLocation!['lng'] as num).toDouble(),
      );
    }
    return kErodeCenter;
  }

  Widget _buildLocationRequiredState() {
    return Container(
      color: Colors.white,
      alignment: Alignment.center,
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.location_off_rounded,
            color: Colors.redAccent,
            size: 48,
          ),
          const SizedBox(height: 12),
          Text(
            'Enable location services to detect your live pickup.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'We are not using a fallback coordinate here. Turn on GPS and try again.',
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
              color: _textSecondary,
              fontSize: 12,
            ),
          ),
          const SizedBox(height: 16),
          ElevatedButton.icon(
            onPressed: () async {
              await _locationService.openLocationSettings();
            },
            icon: const Icon(Icons.my_location_rounded),
            label: const Text('Enable Location'),
          ),
        ],
      ),
    );
  }

  // ── Build ─────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final mapCenter = _mapCenter;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }
        _returnToRootSafely();
      },
      child: Scaffold(
        backgroundColor: Colors.white,
        body: Stack(
          children: [
            // LAYER 1: Background Map
            Positioned.fill(
              child: mapCenter == null
                  ? _buildLocationRequiredState()
                  : ListenableBuilder(
                      listenable: Listenable.merge([
                        _nearbyCaptainMarkersNotifier,
                        _dummyHeroMarkersNotifier,
                      ]),
                      builder: (context, _) => Allin1MapWidget(
                        mapController: _mapController,
                        onMapReady: _flushMainMapMove,
                        center: mapCenter,
                        zoom: 16,
                        markers: _mapMarkers,
                        routes: _mapRoutes,
                      ),
                    ),
            ),

            // LAYER 2: Floating UI Controls
            SafeArea(
              child: Stack(
                children: [
                  // Top controls: Navigation, Title & Live Status, My Location
                  Positioned(
                    left: 16,
                    top: 16,
                    right: 16,
                    child: Row(
                      children: [
                        _glassCircleButton(
                          icon: Icons.arrow_back_ios_new_rounded,
                          onTap: _returnToRootSafely,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: _glassPanel(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 14,
                            ),
                            child: Row(
                              children: [
                                Container(
                                  width: 10,
                                  height: 10,
                                  decoration: const BoxDecoration(
                                    color: _successGreen,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    'Erode Taxi',
                                    style: GoogleFonts.outfit(
                                      color: _textPrimary,
                                      fontSize: 17,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ),
                                Text(
                                  _myPositionLatLng == null
                                      ? 'Locating…'
                                      : 'Live',
                                  style: GoogleFonts.outfit(
                                    color: _textSecondary,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        _glassCircleButton(
                          icon: Icons.notifications_none_rounded,
                          onTap: () {
                            _showError('No new notifications');
                          },
                        ),
                      ],
                    ),
                  ),

                  // My Location Button (Floating)
                  Positioned(
                    right: 16,
                    bottom: 220, // Above the compact bottom search card
                    child: _glassCircleButton(
                      icon: Icons.my_location_rounded,
                      onTap: () {
                        if (_myPositionLatLng != null) {
                          _moveMainMap(_myPositionLatLng!, 16);
                        }
                      },
                    ),
                  ),

                  // Bottom Search/Details Card
                  Align(
                    alignment: Alignment.bottomCenter,
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(14, 16, 14, 10),
                      child: _buildBottomSearchCard(),
                    ),
                  ),
                ],
              ),
            ),

            // LAYER 3: Search Overlay (Highest Z-index)
            if (_isSearchOverlayOpen) _buildSearchOverlay(),
            _buildStartupOverlay(),
          ],
        ),
      ),
    );
  }

  Widget _buildStartupOverlay() {
    final showOverlay = _isInitializingLocation || _locationPermissionRequired;
    if (!showOverlay) {
      return const SizedBox.shrink();
    }

    return Positioned.fill(
      child: IgnorePointer(
        ignoring: !_locationPermissionRequired,
        child: Container(
          color: Colors.white.withValues(alpha: 0.76),
          padding: const EdgeInsets.all(24),
          child: Center(
            child: Container(
              width: 320,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(28),
                border: Border.all(color: _border),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x18FF4FA3),
                    blurRadius: 26,
                    offset: Offset(0, 14),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(24),
                    ),
                    child: const Icon(
                      Icons.map_rounded,
                      color: Colors.white,
                      size: 34,
                    ),
                  ),
                  const SizedBox(height: 18),
                  Text(
                    _locationPermissionRequired
                        ? 'Enable GPS for live pickup'
                        : 'Loading Map / Checking GPS...',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: _textPrimary,
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    _startupStatus,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: _textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  const SizedBox(height: 18),
                  if (_locationPermissionRequired)
                    ElevatedButton.icon(
                      onPressed: () async {
                        await _locationService.openLocationSettings();
                        unawaited(_initLocationTracking());
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _accentOrange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 18,
                          vertical: 14,
                        ),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(18),
                        ),
                      ),
                      icon: const Icon(Icons.gps_fixed_rounded),
                      label: const Text('Enable GPS'),
                    )
                  else
                    const LinearProgressIndicator(
                      minHeight: 6,
                      color: _accentOrange,
                      backgroundColor: Color(0x1AFF4FA3),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Reusable glass widgets ────────────────────────────────────
  Widget _glassCircleButton({
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(28),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: const Color(0xFFFDEAF5),
          child: InkWell(
            onTap: onTap,
            child: Container(
              width: 54,
              height: 54,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: _border),
                boxShadow: [
                  BoxShadow(
                    color: _accentOrange.withValues(alpha: 0.16),
                    blurRadius: 18,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(icon, color: _accentOrange, size: 22),
            ),
          ),
        ),
      ),
    );
  }

  Widget _glassPanel({
    required Widget child,
    EdgeInsetsGeometry padding = EdgeInsets.zero,
    BorderRadius borderRadius = const BorderRadius.all(Radius.circular(24)),
  }) {
    return ClipRRect(
      borderRadius: borderRadius,
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 20, sigmaY: 20),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _card.withValues(alpha: 0.96),
            borderRadius: borderRadius,
            border: Border.all(color: _border),
            boxShadow: [
              BoxShadow(
                color: _accentOrange.withValues(alpha: 0.12),
                blurRadius: 24,
                offset: const Offset(0, 10),
              ),
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  // ── Bottom floating card ──────────────────────────────────────
  Widget _buildBottomSearchCard() {
    final localization = context.watch<LocalizationService>();
    return _glassPanel(
      padding: const EdgeInsets.all(10),
      borderRadius: BorderRadius.circular(20),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.of(context).size.height * 0.28,
        ),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (_pendingActiveRide != null &&
                  _pendingActiveRideDocId != null) ...[
                _buildOngoingRideBanner(),
                const SizedBox(height: 10),
              ],
              _buildServiceCategorySelector(),
              const SizedBox(height: 8),
              _buildUnifiedSearchBar(),
              if (_pickupLocation == null || _dropLocation == null)
                const SizedBox(height: 2),
              if (_pickupLocation != null && _dropLocation != null) ...[
                const SizedBox(height: 8),
                Row(
                  children: [
                    Expanded(
                      child: _metricTile(
                        title: '${_distance.toStringAsFixed(1)} km',
                        subtitle: localization.t('distance_label'),
                        icon: Icons.route_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricTile(
                        title: '$_eta mins',
                        subtitle: localization.t('eta_label'),
                        icon: Icons.access_time_rounded,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: _metricTile(
                        title: _estimatedFare != null
                            ? '₹${_estimatedFare!.toStringAsFixed(0)}'
                            : '—',
                        subtitle: 'Est. Fare',
                        icon: Icons.currency_rupee_rounded,
                        highlight: true,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _triggerBooking,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _accentOrange,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16),
                      ),
                      elevation: 0,
                    ),
                    child: Text(
                      localization.t('choose_vehicle_label'),
                      style: GoogleFonts.outfit(
                        fontSize: 17,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildServiceCategorySelector() {
    return _buildPremiumVehicleScroller();
  }

  Widget _buildPremiumVehicleScroller() {
    final localization = context.watch<LocalizationService>();
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          _premiumCategoryChip(
            category: _ServiceCategory.bike,
            assetPath: 'assets/images/top_bike.png',
            fallbackIcon: Icons.two_wheeler_rounded,
            label: localization.t('bike_label'),
          ),
          const SizedBox(width: 12),
          _premiumCategoryChip(
            category: _ServiceCategory.auto,
            assetPath: 'assets/images/top_auto.png',
            fallbackIcon: Icons.electric_rickshaw_rounded,
            label: localization.t('auto_label'),
          ),
          const SizedBox(width: 12),
          _premiumCategoryChip(
            category: _ServiceCategory.cab,
            assetPath: 'assets/images/top_cab.png',
            fallbackIcon: Icons.local_taxi_rounded,
            label: localization.t('cab_label'),
          ),
          const SizedBox(width: 12),
          _premiumCategoryChip(
            category: _ServiceCategory.parcel,
            assetPath: 'assets/images/top_parcel.png',
            fallbackIcon: Icons.inventory_2_rounded,
            label: localization.t('parcel_label'),
          ),
        ],
      ),
    );
  }

  Widget _premiumCategoryChip({
    required _ServiceCategory category,
    required String assetPath,
    required IconData fallbackIcon,
    required String label,
  }) {
    final isSelected = _selectedCategory == category;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _selectCategory(category),
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 220),
          width: 76,
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.transparent,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: isSelected
                  ? const Color(0xFFFFA4CF).withValues(alpha: 0.45)
                  : _border,
            ),
          ),
          child: Transform.scale(
            scale: 0.9,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: 34,
                  height: 34,
                  child: Image.asset(
                    assetPath,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => Icon(
                      fallbackIcon,
                      color: _accentOrange,
                      size: 30,
                    ),
                  ),
                ),
                const SizedBox(height: 4),
                AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: isSelected
                        ? const Color(0xFFFF4FA3)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(999),
                    boxShadow: isSelected
                        ? [
                            BoxShadow(
                              color: const Color(0xFFFF4FA3)
                                  .withValues(alpha: 0.28),
                              blurRadius: 18,
                              offset: const Offset(0, 6),
                            ),
                          ]
                        : null,
                  ),
                  child: Text(
                    label,
                    style: GoogleFonts.outfit(
                      color: isSelected ? Colors.white : _textPrimary,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildUnifiedSearchBar() {
    final localization = context.watch<LocalizationService>();
    final destinationLabel =
        _dropLocation == null || _dropController.text.trim().isEmpty
            ? localization.t('where_to_go_hint')
            : _dropController.text.trim();

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: () => _openSearch(focusDrop: _pickupLocation != null),
        borderRadius: BorderRadius.circular(24),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
          decoration: BoxDecoration(
            color: _card.withValues(alpha: 0.82),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: _border),
          ),
          child: Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: const Color(0xFFFFF1F8),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  color: _accentOrange,
                  size: 19,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  destinationLabel,
                  style: GoogleFonts.outfit(
                    color:
                        _dropLocation == null ? _textSecondary : _textPrimary,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickDestinationsList() {
    final quickPlaces = <({String title, String subtitle})>[
      (
        title: 'Erode Railway Station',
        subtitle: 'Erode Junction, Chennimalai Rd...'
      ),
      (title: 'Periyar Nagar', subtitle: '8PMF+4QG, Periyar Nagar, Erode...'),
      (title: 'Erode Bus Stand', subtitle: 'Central Bus Terminus, Erode...'),
    ];

    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: quickPlaces.length,
      separatorBuilder: (_, __) => const Divider(
        color: _border,
        height: 1,
      ),
      itemBuilder: (context, index) {
        final place = quickPlaces[index];
        return ListTile(
          dense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 2, vertical: 2),
          leading: Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              color: const Color(0xFFFFF1F8),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Icon(
              Icons.place_outlined,
              color: index == 0 ? _accentOrange : _successGreen,
              size: 20,
            ),
          ),
          title: Text(
            place.title,
            style: GoogleFonts.outfit(
              color: _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          subtitle: Text(
            place.subtitle,
            style: GoogleFonts.outfit(
              color: _textSecondary,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          trailing: Icon(
            Icons.favorite_border_rounded,
            color: _accentOrange.withValues(alpha: 0.75),
            size: 22,
          ),
          onTap: () => _openSearch(focusDrop: true),
        );
      },
    );
  }

  void _selectCategory(_ServiceCategory category) {
    if (!mounted || _selectedCategory == category) {
      return;
    }

    setState(() {
      _selectedCategory = category;
      if (_routeDistanceKm != null && _routeDistanceKm! > 0) {
        _estimatedFare = RideModel.calculateFare(
          _routeDistanceKm!,
          _selectedVehicleTypeKey,
          fares: _fares,
        );
      }
    });
    _refreshHeroMarkers();
  }

  Widget _metricTile({
    required String title,
    required String subtitle,
    required IconData icon,
    bool highlight = false,
  }) {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        gradient: highlight
            ? const LinearGradient(
                colors: [Color(0xFFFF4FA3), Color(0xFFB21FFF)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              )
            : null,
        color: highlight ? null : _card.withValues(alpha: 0.72),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: highlight ? Colors.transparent : _border,
        ),
        boxShadow: highlight
            ? [
                BoxShadow(
                  color: const Color(0xFFFF4FA3).withValues(alpha: 0.32),
                  blurRadius: 14,
                  offset: const Offset(0, 6),
                ),
              ]
            : null,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            color: highlight ? Colors.white : _accentOrange,
            size: 16,
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: GoogleFonts.outfit(
              color: highlight ? Colors.white : _textPrimary,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            subtitle,
            style: GoogleFonts.outfit(
              color: highlight
                  ? Colors.white.withValues(alpha: 0.82)
                  : _textSecondary,
              fontSize: 10,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  // ── Search overlay ────────────────────────────────────────────
  Widget _buildSearchOverlay() {
    final localization = context.watch<LocalizationService>();
    final pinDetails = _pinDropLocation;
    return Positioned.fill(
      child: ColoredBox(
        color: _bg.withValues(alpha: 0.96),
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 12, 8),
                child: Row(
                  children: [
                    _glassCircleButton(
                      icon: Icons.arrow_back_ios_new_rounded,
                      onTap: _closeSearch,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        _isFocusingDrop
                            ? localization.t('choose_destination_title')
                            : localization.t('update_pickup_title'),
                        style: GoogleFonts.outfit(
                          color: _textPrimary,
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: _glassPanel(
                  padding: const EdgeInsets.all(10),
                  child: Column(
                    children: [
                      _searchField(
                        hint: localization.t('pickup_location_label'),
                        controller: _pickupController,
                        isDrop: false,
                      ),
                      const Padding(
                        padding: EdgeInsets.only(left: 34),
                        child: Divider(color: _border, height: 14),
                      ),
                      _searchField(
                        hint: localization.t('drop_destination_label'),
                        controller: _dropController,
                        isDrop: true,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Stack(
                      children: [
                        FlutterMap(
                          mapController: _searchMapController,
                          options: MapOptions(
                            initialCenter: _searchMapCenter ?? kErodeCenter,
                            initialZoom: 16,
                            minZoom: 12,
                            maxZoom: 18,
                            onMapReady: _flushSearchMapMove,
                            onPositionChanged: (camera, hasGesture) {
                              _searchMapCenter = camera.center;
                              if (hasGesture) {
                                _scheduleReverseGeocode(camera.center);
                              }
                            },
                          ),
                          children: [
                            TileLayer(
                              urlTemplate:
                                  'https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png',
                              subdomains: const ['a', 'b', 'c', 'd'],
                              userAgentPackageName: 'com.allin1.superapp',
                            ),
                          ],
                        ),
                        IgnorePointer(
                          child: Center(
                            child: Transform.translate(
                              offset: const Offset(0, -18),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    width: 44,
                                    height: 44,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF4FA3),
                                      borderRadius: BorderRadius.circular(22),
                                      border: Border.all(
                                        color: Colors.white,
                                        width: 2,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: const Color(0xFFFF4FA3)
                                              .withValues(alpha: 0.4),
                                          blurRadius: 24,
                                          spreadRadius: 2,
                                        ),
                                      ],
                                    ),
                                    child: const Icon(
                                      Icons.location_on_rounded,
                                      color: Colors.white,
                                      size: 26,
                                    ),
                                  ),
                                  Container(
                                    width: 10,
                                    height: 10,
                                    decoration: BoxDecoration(
                                      color: const Color(0xFFFF4FA3)
                                          .withValues(alpha: 0.22),
                                      shape: BoxShape.circle,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        Positioned(
                          top: 14,
                          left: 14,
                          right: 14,
                          child: _glassPanel(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            borderRadius: BorderRadius.circular(20),
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.pan_tool_alt_rounded,
                                  color: Color(0xFFFF4FA3),
                                  size: 18,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Text(
                                    localization.t('drag_map_hint'),
                                    style: GoogleFonts.outfit(
                                      color: _textPrimary,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_shouldShowSuggestionPanel)
                          Positioned(
                            left: 14,
                            right: 14,
                            top: 86,
                            child: _glassPanel(
                              padding: const EdgeInsets.all(10),
                              borderRadius: BorderRadius.circular(22),
                              child: ConstrainedBox(
                                constraints:
                                    const BoxConstraints(maxHeight: 260),
                                child: _buildSearchSuggestionPanel(),
                              ),
                            ),
                          ),
                        Positioned(
                          left: 14,
                          right: 14,
                          bottom: 16,
                          child: _glassPanel(
                            padding: const EdgeInsets.all(18),
                            borderRadius: BorderRadius.circular(24),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Row(
                                  children: [
                                    Container(
                                      width: 36,
                                      height: 36,
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFFF4FA3)
                                            .withValues(alpha: 0.14),
                                        borderRadius: BorderRadius.circular(14),
                                      ),
                                      child: const Icon(
                                        Icons.place_rounded,
                                        color: Color(0xFFFF4FA3),
                                        size: 18,
                                      ),
                                    ),
                                    const SizedBox(width: 12),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            _isFocusingDrop
                                                ? localization.t(
                                                    'drop_pin_destination_title',
                                                  )
                                                : localization.t(
                                                    'drop_pin_pickup_title',
                                                  ),
                                            style: GoogleFonts.outfit(
                                              color: _textPrimary,
                                              fontSize: 15,
                                              fontWeight: FontWeight.w700,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _isResolvingPinAddress
                                                ? localization.t(
                                                    'finding_street_label',
                                                  )
                                                : (pinDetails?['name']
                                                        as String? ??
                                                    localization.t(
                                                      'move_map_to_select_label',
                                                    )),
                                            style: GoogleFonts.outfit(
                                              color: _textSecondary,
                                              fontSize: 12,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 12),
                                Text(
                                  pinDetails?['full'] as String? ??
                                      'Pan the map and drop the pin where you want to be picked up.',
                                  style: GoogleFonts.outfit(
                                    color: _textPrimary.withValues(alpha: 0.92),
                                    fontSize: 13,
                                    height: 1.4,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                const SizedBox(height: 16),
                                SizedBox(
                                  width: double.infinity,
                                  child: ElevatedButton.icon(
                                    onPressed: _confirmPinnedLocation,
                                    style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF4FA3),
                                      foregroundColor: Colors.white,
                                      padding: const EdgeInsets.symmetric(
                                        vertical: 16,
                                      ),
                                      shape: RoundedRectangleBorder(
                                        borderRadius: BorderRadius.circular(18),
                                      ),
                                      elevation: 0,
                                    ),
                                    icon:
                                        const Icon(Icons.check_circle_rounded),
                                    label: Text(
                                      _isFocusingDrop
                                          ? localization.t(
                                              'use_as_destination_label',
                                            )
                                          : localization.t(
                                              'use_as_pickup_label',
                                            ),
                                      style: GoogleFonts.outfit(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
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
      ),
    );
  }

  bool get _shouldShowSuggestionPanel {
    return _isSearching ||
        _activeSearchQuery.isEmpty ||
        _searchSuggestions.isNotEmpty ||
        _activeSearchQuery.length >= 3;
  }

  List<Map<String, dynamic>> get _visibleSearchSuggestions {
    return _activeSearchQuery.isEmpty
        ? _defaultSearchLocations
        : _searchSuggestions;
  }

  Widget _buildSearchSuggestionPanel() {
    if (_isSearching) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 28),
        child: Center(
          child: CircularProgressIndicator(
            color: _accentOrange,
            strokeWidth: 2,
          ),
        ),
      );
    }

    final suggestions = _visibleSearchSuggestions;
    if (suggestions.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 18),
        child: Row(
          children: [
            Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _accentOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.search_off_rounded,
                color: _accentOrange,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'No places found',
                style: GoogleFonts.outfit(
                  color: _textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_activeSearchQuery.isEmpty)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
            child: Text(
              'Favorites / Recent locations',
              style: GoogleFonts.outfit(
                color: _textPrimary,
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        if (_activeSearchQuery.isEmpty)
          ListTile(
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 8,
              vertical: 4,
            ),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _accentOrange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(
                Icons.map_rounded,
                color: _accentOrange,
              ),
            ),
            title: Text(
              'Point on Map',
              style: GoogleFonts.outfit(
                color: _textPrimary,
                fontSize: 15,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              'Drop a pin for your exact destination',
              style: GoogleFonts.outfit(
                color: _textSecondary,
                fontSize: 11,
              ),
            ),
            onTap: () {
              setState(() {
                _activeSearchQuery = ' ';
                _searchSuggestions = [];
              });
              _primeSearchMap();
            },
          ),
        SizedBox(
          height: min(210, suggestions.length * 66.0),
          child: ListView.separated(
            shrinkWrap: true,
            itemCount: suggestions.length,
            separatorBuilder: (_, __) => const Divider(
              color: _border,
              height: 1,
            ),
            itemBuilder: (context, index) {
              final loc = suggestions[index];
              final isFavorite = loc['provider'] == 'favorite';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 8,
                  vertical: 4,
                ),
                leading: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: _accentOrange.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Icon(
                    isFavorite
                        ? Icons.favorite_border_rounded
                        : Icons.location_on_rounded,
                    color: _accentOrange,
                  ),
                ),
                title: Text(
                  loc['name'] as String? ?? '',
                  style: GoogleFonts.outfit(
                    color: _textPrimary,
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                subtitle: Text(
                  loc['full'] as String? ?? '',
                  style: GoogleFonts.outfit(
                    color: _textSecondary,
                    fontSize: 12,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                onTap: () => _selectLocation(loc),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _buildOngoingRideBanner() {
    final ride = _pendingActiveRide;
    final status = (_pendingActiveRideStatus ?? '').trim();
    final paymentStatus = (_pendingActiveRidePaymentStatus ?? '').trim();
    final isPaymentPending = _shouldResumePaymentFlow(status, paymentStatus);
    if (ride == null) {
      return const SizedBox.shrink();
    }

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 11),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: <Color>[Color(0xFFFF4FA3), Color(0xFFFF92C8)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x33FF4FA3),
            blurRadius: 20,
            offset: Offset(0, 10),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Row(
            children: <Widget>[
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  isPaymentPending
                      ? Icons.receipt_long_rounded
                      : Icons.local_taxi_rounded,
                  color: Colors.white,
                  size: 18,
                ),
              ),
              const SizedBox(width: 9),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: <Widget>[
                    Text(
                      isPaymentPending ? 'Pending Payment' : 'Ongoing Ride',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      _activeRideLabel(status),
                      style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              if (isPaymentPending && _pendingActiveRideAmount != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '₹${_pendingActiveRideAmount!.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      color: _accentOrange,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            ride.dropAddress?.trim().isNotEmpty ?? false
                ? ride.dropAddress!.trim()
                : 'Your active ride is waiting for you.',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 12,
              fontWeight: FontWeight.w500,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: <Widget>[
              if (_canCancelPendingRide(status, paymentStatus)) ...<Widget>[
                Expanded(
                  child: OutlinedButton(
                    onPressed: _cancelPendingActiveRide,
                    style: OutlinedButton.styleFrom(
                      foregroundColor: const Color(0xFFE53935),
                      side: const BorderSide(color: Colors.white),
                      backgroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(
                        fontSize: 13,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
              ],
              Expanded(
                child: ElevatedButton(
                  onPressed: _continueActiveRide,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: _accentOrange,
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: Text(
                    _continueActionLabel(status, paymentStatus),
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _searchField({
    required String hint,
    required TextEditingController controller,
    required bool isDrop,
  }) {
    final iconColor = isDrop ? _successGreen : _accentOrange;
    return Row(
      children: [
        Icon(
          isDrop ? Icons.location_on_rounded : Icons.my_location_rounded,
          color: iconColor,
          size: 17,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: controller,
            autofocus: isDrop == _isFocusingDrop,
            onTap: () {
              setState(() {
                _isFocusingDrop = isDrop;
              });
              _primeSearchMap();
            },
            onChanged: _onSearchChanged,
            style: GoogleFonts.outfit(
              color: _textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: _textSecondary),
              border: InputBorder.none,
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        if (controller.text.isNotEmpty)
          IconButton(
            icon: const Icon(
              Icons.close_rounded,
              color: _textSecondary,
              size: 18,
            ),
            onPressed: () {
              setState(() {
                controller.clear();
                _isSearching = false;
                _searchSuggestions = [];
                _activeSearchQuery = '';
                if (isDrop) {
                  _dropLocation = null;
                } else {
                  _pickupLocation = null;
                }
              });
              _primeSearchMap();
            },
          ),
      ],
    );
  }
}
