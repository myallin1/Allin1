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
import '../config/ride_catalog.dart';


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
enum _VehicleMotionState { moving, resting, working }

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
    _stateTicksLeft = 8 + _random.nextInt(13);
  }

  void _pickRestingDuration() {
    // Lifestyle: occasionally stop for a long time to work (parcel load/unload, drop passenger)
    if (_random.nextDouble() < 0.25 && !isOutskirts) {
      motionState = _VehicleMotionState.working;
      _stateTicksLeft = 15 + _random.nextInt(20); // 15-35s working
    } else {
      // Short rest (traffic light / junction)
      motionState = _VehicleMotionState.resting;
      _stateTicksLeft = 2 + _random.nextInt(6);
    }
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
    if (motionState == _VehicleMotionState.resting || motionState == _VehicleMotionState.working) {
      // Idle: sits exactly where it stopped
      if (_stateTicksLeft <= 0) {
        motionState = _VehicleMotionState.moving;
        _pickMovingDuration();
        // Chance to "turn" onto a different connected road segment
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
enum HeroState { traveling, working, resting }

class _HeroAvatarState {
  _HeroAvatarState({
    required this.id,
    required this.loopIndex,
    required this.progress,
    required this.direction,
    required this.speedStep,
    int? seed,
  }) : _random = Random(seed ?? id.hashCode) {
    _pickNewState();
  }

  final String id;
  int loopIndex;
  double progress;
  int direction;
  final double speedStep;
  final Random _random;

  HeroState state = HeroState.traveling;
  int stateTicksLeft = 0;

  void _pickNewState() {
    final rand = _random.nextDouble();
    if (state == HeroState.traveling) {
      if (rand < 0.6) {
        state = HeroState.working; // e.g., picking up/dropping off order
        stateTicksLeft = 10 + _random.nextInt(15); // 10-25s
      } else {
        state = HeroState.resting; // e.g., tea break, waiting
        stateTicksLeft = 20 + _random.nextInt(30); // 20-50s
      }
    } else {
      state = HeroState.traveling;
      stateTicksLeft = 25 + _random.nextInt(35); // 25-60s of driving
    }
  }

  List<LatLng> activePath() {
    return _erodeTrafficLoops[loopIndex % _erodeTrafficLoops.length];
  }

  LatLng project() {
    return _pointOnPath(activePath(), progress, 0);
  }

  void advance() {
    stateTicksLeft--;
    if (stateTicksLeft <= 0) {
      _pickNewState();
      // Chance to turn at a junction when starting to travel
      if (state == HeroState.traveling && _random.nextDouble() < 0.4) {
        loopIndex = _random.nextInt(_erodeTrafficLoops.length);
        direction = _random.nextBool() ? 1 : -1;
        progress = direction == 1 ? 0.0 : 1.0;
      }
    }

    if (state == HeroState.traveling) {
      progress += direction * speedStep;
      if (progress >= 1.0) {
        progress = 1.0;
        direction = -1;
      } else if (progress <= 0.0) {
        progress = 0.0;
        direction = 1;
      }
    }
  }
}

enum SimulationDensity { normal, busy, peak }

class MapSimulationService extends ChangeNotifier {
  MapSimulationService._internal();

  static final MapSimulationService instance = MapSimulationService._internal();

  bool _isActive = false;
  bool get isActive => _isActive;
  
  SimulationDensity _currentDensity = SimulationDensity.normal;
  SimulationDensity get currentDensity => _currentDensity;

  Timer? _globalTickTimer;
  final List<_DummyVehicleState> _ambientVehicles = <_DummyVehicleState>[];
  final List<_HeroAvatarState> _heroes = <_HeroAvatarState>[];

  List<MapMarker> _simulatedMarkers = [];
  List<MapMarker> get simulatedMarkers => _simulatedMarkers;

  /// Manual control ONLY — called by admin_map_simulation_screen.dart's
  /// toggle switch. Nothing else in the app may call this.
  void start({SimulationDensity density = SimulationDensity.normal}) {
    if (_isActive && _currentDensity == density) return;
    if (_isActive) {
      _stopSimulation(); // Restart with new density
    }
    _currentDensity = density;
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
    
    int bikeCount = 1;
    int autoCount = 1;
    int cabCount = 1;
    int truckCount = 1;
    int lorryCount = 1;
    int heroCount = 0;

    switch (_currentDensity) {
      case SimulationDensity.normal:
        bikeCount = 1;
        autoCount = 1;
        cabCount = 1;
        truckCount = 1;
        lorryCount = 1;
        heroCount = 1;
        break;
      case SimulationDensity.busy:
        bikeCount = 6;
        autoCount = 6;
        cabCount = 5;
        truckCount = 5;
        lorryCount = 3;
        heroCount = 5;
        break;
      case SimulationDensity.peak:
        bikeCount = 12;
        autoCount = 12;
        cabCount = 10;
        truckCount = 8;
        lorryCount = 8;
        heroCount = 10;
        break;
    }

    final trafficMix = <String, int>{
      'bike': bikeCount,
      'auto': autoCount,
      'cab': cabCount,
      'mini_truck': truckCount,
    };

    // 2. Vehicle Spacing & Crossing Paths
    // We space out normal vehicles strictly, busy/peak get some random overlap.
    for (final entry in trafficMix.entries) {
      final random = Random(entry.key.hashCode ^ DateTime.now().millisecondsSinceEpoch);
      int previousLoop = -1;
      
      for (var index = 0; index < entry.value; index++) {
        int loopIndex;
        if (_currentDensity == SimulationDensity.normal) {
           // Force different loop for spacing
           loopIndex = (index + entry.key.hashCode) % _erodeTrafficLoops.length;
        } else {
           loopIndex = random.nextInt(_erodeTrafficLoops.length);
        }
        
        // Prevent immediate clustering on same loop in normal mode
        if (_currentDensity == SimulationDensity.normal && loopIndex == previousLoop) {
          loopIndex = (loopIndex + 1) % _erodeTrafficLoops.length;
        }
        previousLoop = loopIndex;

        final baseProgress = _currentDensity == SimulationDensity.normal 
            ? (index / (entry.value > 0 ? entry.value : 1)) 
            : random.nextDouble();
        
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
    for (var index = 0; index < lorryCount; index++) {
      final baseProgress = index / (lorryCount > 0 ? lorryCount : 1); // Distribute evenly
      final vehicle = _DummyVehicleState(
        id: 'outskirts_lorry_$index',
        vehicleType: 'lorry', 
        loopIndex: 0, // Only 1 ring road loop
        progress: baseProgress,
        direction: lorryRandom.nextBool() ? 1 : -1,
        speedStep: 0.007, 
        laneOffset: 0,
        isOutskirts: true,
      );
      _ambientVehicles.add(vehicle);
    }

    // 4. Hero Avatars (Road-Bound Lifestyle)
    final heroRandom = Random('hero'.hashCode ^ DateTime.now().millisecondsSinceEpoch);
    int previousHeroLoop = -1;
    for (var index = 0; index < heroCount; index++) {
      int loopIndex;
      if (_currentDensity == SimulationDensity.normal) {
         loopIndex = (index + 2) % _erodeTrafficLoops.length;
      } else {
         loopIndex = heroRandom.nextInt(_erodeTrafficLoops.length);
      }
      
      // Prevent heroes from bunching up on the same road initially
      if (_currentDensity == SimulationDensity.normal && loopIndex == previousHeroLoop) {
        loopIndex = (loopIndex + 1) % _erodeTrafficLoops.length;
      }
      previousHeroLoop = loopIndex;

      final baseProgress = _currentDensity == SimulationDensity.normal 
          ? (index / (heroCount > 0 ? heroCount : 1)) 
          : heroRandom.nextDouble();

      _heroes.add(_HeroAvatarState(
        id: 'hero_$index',
        loopIndex: loopIndex,
        progress: baseProgress,
        direction: heroRandom.nextBool() ? 1 : -1,
        speedStep: 0.015 + (heroRandom.nextDouble() - 0.5) * 0.005,
        seed: heroRandom.nextInt(1000000),
      ));
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
        point: hero.project(),
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
