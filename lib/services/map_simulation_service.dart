// lib/services/map_simulation_service.dart

// NEW (Aug 12 2026 — customer-facing demo-vehicle removal, per Nizam's
// explicit instruction after this file was found wired into the LIVE
// customer/hero map via a remote Firestore toggle): this service is now
// reachable ONLY from admin_map_simulation_screen.dart, an Admin-only
// screen that is never linked from the customer or hero apps and that
// carries a permanent "SIMULATION — NOT REAL DATA" watermark. The old
// Firestore-driven auto-start (system_settings/app_status.show_demo_
// vehicles) is gone entirely — start()/stop() are now the only way to
// control this, and only that admin screen calls them. No remote flag
// can ever make fake vehicles appear on a real customer's screen again.
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/allin1_map_widget.dart' show MapMarker;

// FIX (Aug 12 2026 — "Invisible Vehicles" bug): these used to point at
// 'assets/images/ride_*.png', which do not exist anywhere in this repo
// — every single vehicle silently hit _DefaultMarker's errorBuilder and
// rendered as a tiny plain white Icon instead of a real vehicle image.
// Swapped to the actual bundled top-down UI assets (confirmed present
// under assets/images/), one per vehicle type instead of sharing one
// generic truck image between lorry and mini_truck.
String rideAssetFor(String type) {
  switch (type) {
    case 'auto':
      return 'assets/images/top_auto.png';
    case 'bike':
      return 'assets/images/top_bike.png';
    case 'lorry':
      return 'assets/images/top_lorry.png';
    case 'mini_truck':
      return 'assets/images/top_mini_truck.png';
    case 'cab':
    default:
      return 'assets/images/top_cab.png';
  }
}

IconData rideFallbackIcon(String type) {
  switch (type) {
    case 'auto':
      return Icons.electric_rickshaw;
    case 'bike':
      return Icons.two_wheeler;
    case 'lorry':
    case 'mini_truck':
      return Icons.local_shipping;
    case 'cab':
    default:
      return Icons.local_taxi;
  }
}

// 1. Road-Constrained Movement: Predefined Erode main roads
const List<List<LatLng>> _erodeTrafficLoops = <List<LatLng>>[
  // Perundurai Road
  <LatLng>[
    LatLng(11.3195, 77.6830),
    LatLng(11.3250, 77.6900),
    LatLng(11.3320, 77.7000),
    LatLng(11.3400, 77.7100),
  ],
  // Brough Road
  <LatLng>[
    LatLng(11.3400, 77.7100),
    LatLng(11.3420, 77.7135),
    LatLng(11.3450, 77.7170),
  ],
  // Bhavani Road
  <LatLng>[
    LatLng(11.3450, 77.7170),
    LatLng(11.3600, 77.7050),
    LatLng(11.3800, 77.6950),
    LatLng(11.4000, 77.6900),
  ],
  // EVN Road
  <LatLng>[
    LatLng(11.3400, 77.7100),
    LatLng(11.3350, 77.7150),
    LatLng(11.3300, 77.7200),
  ],
  // Chennimalai Road
  <LatLng>[
    LatLng(11.3300, 77.7200),
    LatLng(11.3100, 77.7100),
    LatLng(11.2900, 77.7000),
  ],
];

// 3. Outskirts Lorries (Spread out) on Ring Road
const List<List<LatLng>> _outskirtsTrafficLoops = <List<LatLng>>[
  <LatLng>[
    LatLng(11.2900, 77.7000),
    LatLng(11.3000, 77.7300),
    LatLng(11.3200, 77.7500),
    LatLng(11.3500, 77.7600),
    LatLng(11.3800, 77.7400),
    LatLng(11.4000, 77.7100),
    LatLng(11.4000, 77.6800),
    LatLng(11.3800, 77.6500),
    LatLng(11.3400, 77.6400),
    LatLng(11.3100, 77.6600),
    LatLng(11.2900, 77.7000),
  ],
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

// Step 3 (Aug 12 2026 — "GTA-style" idle states for vehicles, per
// Nizam's request): moving vehicles now also stop-and-go, same idea as
// _HeroAvatarState below but reusing whichever road segment they're
// already on — no routing API, no extra geometry, just a tick-counter
// state machine layered on top of the existing road-constrained
// interpolation. When a city vehicle finishes resting at a junction
// (progress 0 or 1), there's a chance it "turns" onto a different
// connected loopIndex instead of always bouncing back down the same
// road — the closest safe approximation of a real road graph without
// needing actual adjacency data for every Erode street.
enum _VehicleMotionState { moving, resting }

class _DummyVehicleState {
  _DummyVehicleState({
    required this.id,
    required this.vehicleType,
    required this.loopIndex,
    required this.progress,
    required this.direction,
    required this.speedStep,
    required this.laneOffset,
    this.isOutskirts = false,
    int? seed,
  }) : _random = Random(seed ?? id.hashCode) {
    _pickMovingDuration();
  }

  final String id;
  final String vehicleType;
  int loopIndex;
  final double speedStep;
  final double laneOffset;
  final bool isOutskirts;
  final Random _random;
  double progress;
  int direction;
  _VehicleMotionState motionState = _VehicleMotionState.moving;
  int _stateTicksLeft = 0;

  void _pickMovingDuration() {
    // 8-20 ticks (~8-20s at the 1s global tick) of continuous movement
    // before the next stop — varies per vehicle so a fleet never looks
    // like it's stepping in lockstep.
    _stateTicksLeft = 8 + _random.nextInt(13);
  }

  void _pickRestingDuration() {
    // 2-7 ticks (~2-7s) — short enough to read as "waiting at a light",
    // not a breakdown.
    motionState = _VehicleMotionState.resting;
    _stateTicksLeft = 2 + _random.nextInt(6);
  }

  List<LatLng> activePath() {
    return isOutskirts
        ? _outskirtsTrafficLoops[loopIndex % _outskirtsTrafficLoops.length]
        : _erodeTrafficLoops[loopIndex % _erodeTrafficLoops.length];
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

  void advance() {
    _stateTicksLeft--;
    if (motionState == _VehicleMotionState.resting) {
      // Idle: sits exactly where it stopped, no interpolation this
      // tick — this IS the "stop-and-go" behavior, at zero extra cost
      // (skipping the progress update is cheaper than doing it).
      if (_stateTicksLeft <= 0) {
        motionState = _VehicleMotionState.moving;
        _pickMovingDuration();
        // Chance to "turn" onto a different connected road segment
        // instead of always retracing the same one — only for city
        // loops; outskirts lorries stay on their single ring road.
        if (!isOutskirts && _random.nextDouble() < 0.35) {
          loopIndex = _random.nextInt(_erodeTrafficLoops.length);
          direction = _random.nextBool() ? 1 : -1;
          progress = direction == 1 ? 0 : 1;
        }
      }
      return;
    }

    progress += direction * speedStep;
    if (_stateTicksLeft <= 0) {
      _pickRestingDuration();
    }
    if (isOutskirts) {
      // Loop seamlessly for ring roads
      if (progress >= 1) progress -= 1;
      if (progress < 0) progress += 1;
    } else {
      // Bounce back and forth for city roads
      if (progress >= 1) {
        progress = 1;
        direction = -1;
      } else if (progress <= 0) {
        progress = 0;
        direction = 1;
      }
    }
  }
}

// 4. The 'Superman' Hero Avatars (State-Machine Logic)
enum HeroState { moving, resting }

class _HeroAvatarState {
  _HeroAvatarState(this.id, this.position, int seed) : _random = Random(seed) {
    _pickNewState();
  }

  final String id;
  LatLng position;
  LatLng? destination;
  HeroState state = HeroState.resting;
  int stateTicksLeft = 0;
  final Random _random;

  void _pickNewState() {
    if (state == HeroState.moving) {
      state = HeroState.resting;
      // Rest for 5 to 15 seconds (assuming 1 tick = 1 second)
      stateTicksLeft = 5 + _random.nextInt(11); 
    } else {
      state = HeroState.moving;
      // FIX (Aug 12 2026 — "Hyper-Speed" bug): longer move duration for
      // a shorter distance = a much slower crawl per tick.
      // Move for 18 to 40 seconds
      stateTicksLeft = 18 + _random.nextInt(23);
      // Pick a random nearby point (~0.5-1km, down from ~1-2km)
      final dist = 0.003 + _random.nextDouble() * 0.006;
      final angle = _random.nextDouble() * 2 * pi;
      destination = LatLng(
        position.latitude + dist * cos(angle),
        position.longitude + dist * sin(angle),
      );
    }
  }

  void advance() {
    stateTicksLeft--;
    if (stateTicksLeft <= 0) {
      _pickNewState();
    } else if (state == HeroState.moving && destination != null) {
      // Interpolate towards destination smoothly
      // Lerp by a factor inversely proportional to remaining ticks to reach exactly
      position = _lerpLatLng(position, destination!, 1.0 / stateTicksLeft);
    }
  }
}

class MapSimulationService extends ChangeNotifier {
  MapSimulationService._internal();

  static final MapSimulationService instance = MapSimulationService._internal();

  bool _isActive = false;
  bool get isActive => _isActive;

  Timer? _globalTickTimer;
  final List<_DummyVehicleState> _ambientVehicles = <_DummyVehicleState>[];
  final List<_HeroAvatarState> _heroes = <_HeroAvatarState>[];

  List<MapMarker> _simulatedMarkers = [];
  List<MapMarker> get simulatedMarkers => _simulatedMarkers;

  /// Manual control ONLY — called by admin_map_simulation_screen.dart's
  /// toggle switch. Nothing else in the app may call this.
  void start() {
    if (_isActive) return;
    _startSimulation();
  }

  /// Manual control ONLY — see start().
  void stop() {
    if (!_isActive) return;
    _stopSimulation();
  }

  void _startSimulation() {
    _isActive = true;
    _ambientVehicles.clear();
    _heroes.clear();
    
    // Scale up Generation: 40 inner city, 10 outskirts
    final trafficMix = <String, int>{
      'bike': 10,
      'auto': 10,
      'cab': 10,
      'mini_truck': 10,
    };

    // 2. Vehicle Spacing & Crossing Paths
    // Distribute vehicles randomly across different roads with different speeds
    for (final entry in trafficMix.entries) {
      final random = Random(entry.key.hashCode ^ DateTime.now().millisecondsSinceEpoch);
      for (var index = 0; index < entry.value; index++) {
        final loopIndex = random.nextInt(_erodeTrafficLoops.length);
        final baseProgress = random.nextDouble();
        
        // FIX (Aug 12 2026 — "Hyper-Speed" bug): the global tick is 1Hz
        // with no inter-tick animation, so each tick jumps the marker
        // straight to its new lat/lng — at the old 0.03-0.04 progress/
        // tick, that jump was large enough on screen to read as
        // "flying" rather than driving. Cut to roughly a third so each
        // 1-second jump is small and reads as a slow crawl.
        final baseSpeed = entry.key == 'bike' ? 0.014 : 0.011;
        final speedJitter = (random.nextDouble() - 0.5) * 0.004;
        
        final vehicle = _DummyVehicleState(
          id: 'inner_${entry.key}_$index',
          vehicleType: entry.key,
          loopIndex: loopIndex,
          progress: baseProgress,
          direction: random.nextBool() ? 1 : -1,
          speedStep: baseSpeed + speedJitter,
          laneOffset: 0,
        );
        _ambientVehicles.add(vehicle);
      }
    }

    // 3. Outskirts Lorries (Spread out)
    final lorryRandom = Random('lorry'.hashCode);
    for (var index = 0; index < 10; index++) {
      final baseProgress = index / 10.0; // Distribute evenly
      final vehicle = _DummyVehicleState(
        id: 'outskirts_lorry_$index',
        vehicleType: 'lorry', 
        loopIndex: 0, // Only 1 ring road loop
        progress: baseProgress,
        direction: lorryRandom.nextBool() ? 1 : -1,
        speedStep: 0.007, // Slower for lorries (see speed fix comment above)
        laneOffset: 0,
        isOutskirts: true,
      );
      _ambientVehicles.add(vehicle);
    }

    // FIX (Aug 12 2026 — "Clustering" bug): sampling distance as
    // `random * radius` biases points toward the CENTER (area grows
    // with r², so equal steps in r pack far more samples near r=0) —
    // that's why heroes looked bunched in one spot instead of spread
    // across Erode. `sqrt(random) * radius` is the standard fix for a
    // uniform-DENSITY (not uniform-radius) scatter across a disc. Also
    // widened the radius slightly (~6.5km) so the spread reads clearly
    // even when the map is zoomed out to show the wider district.
    final heroRandom = Random('hero'.hashCode ^ DateTime.now().millisecondsSinceEpoch);
    const double heroRadiusDegrees = 0.058; // ~6.5km
    for (var index = 0; index < 10; index++) {
      final distance = sqrt(heroRandom.nextDouble()) * heroRadiusDegrees;
      final angle = heroRandom.nextDouble() * 2 * pi;
      final pos = LatLng(
        11.3410 + distance * cos(angle),
        77.7171 + distance * sin(angle),
      );
      _heroes.add(_HeroAvatarState('hero_$index', pos, heroRandom.nextInt(1000000)));
    }

    // Single global timer to optimize performance and prevent CPU drain
    _globalTickTimer = Timer.periodic(const Duration(milliseconds: 1000), (_) {
      if (!_isActive) return;
      for (final v in _ambientVehicles) {
        v.advance();
      }
      for (final h in _heroes) {
        h.advance();
      }
      _updateMarkers();
    });

    _updateMarkers();
  }

  void _stopSimulation() {
    _isActive = false;
    _globalTickTimer?.cancel();
    _ambientVehicles.clear();
    _heroes.clear();
    _simulatedMarkers = [];
    notifyListeners();
  }

  void _updateMarkers() {
    if (!_isActive) return;

    // FIX (Aug 12 2026 — sizing per Nizam's request): strictly 40x40 for
    // every vehicle now, matching the real top_*.png asset dimensions
    // instead of the previous 45/55 mismatch.
    final markers = _ambientVehicles.map((vehicle) {
      return MapMarker(
        point: vehicle.project(),
        color: const Color(0xFFB21FFF),
        assetPath: rideAssetFor(vehicle.vehicleType),
        icon: rideFallbackIcon(vehicle.vehicleType),
        bearingDegrees: vehicle.bearing(),
        size: 40,
      );
    }).toList();

    for (final hero in _heroes) {
      markers.add(MapMarker(
        point: hero.position,
        color: Colors.redAccent,
        // UPDATED (Aug 12 2026 — back to the glowing .gif per Nizam's
        // new asset): the real jitter cause wasn't "gif vs png", it was
        // Image.asset restarting the GIF's animation from frame 0 on
        // every rebuild (every 1s tick). Fixed at the root in
        // allin1_map_widget.dart's _DefaultMarker via
        // `gaplessPlayback: true`, which lets the same animation
        // controller keep playing across rebuilds instead of resetting
        // — so the gif can come back without reintroducing the bug.
        assetPath: 'assets/gifs/superman_hero.gif',
        icon: Icons.person_pin,
        size: 40,
        circular: true,
      ));
    }

    _simulatedMarkers = markers;
    notifyListeners();
  }

  @override
  void dispose() {
    _stopSimulation();
    super.dispose();
  }
}
