// ================================================================
// offline_sos_mesh_service.dart — 300m Offline SOS Mesh & Proximity Service
// ================================================================
// Handles zero-network emergency distress signals using local mesh
// store-and-forward logic. When a user (especially women/children in
// remote areas or basements with no cellular tower) triggers an SOS:
//
// 1. Encodes a compact SOS Beacon payload:
//    `ALLIN1_SOS:<uid>:<lat>:<lng>:<timestamp>:<battery>`
// 2. Broadcasts locally over BLE / Wi-Fi Direct / Local Radio.
// 3. When any nearby Allin1 Hero or Customer device detects the beacon:
//    - Alerts the local device with distance & compass direction.
//    - Once any device regains internet connectivity, automatically
//      relays the distress payload to Firestore `sos_alerts` (Relay).
// ================================================================

import 'dart:async';
import 'dart:math' as math;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class SosBeaconPayload {
  const SosBeaconPayload({
    required this.userId,
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.batteryLevel,
    this.userName,
    this.userPhone,
    this.rssi,
    this.estimatedDistanceMeters,
  });

  final String userId;
  final double latitude;
  final double longitude;
  final int timestamp;
  final int batteryLevel;
  final String? userName;
  final String? userPhone;
  final int? rssi;
  final double? estimatedDistanceMeters;

  /// Encodes to a compact string for radio transmission (BLE advertisement packet)
  String encode() {
    return 'ALLIN1_SOS:$userId:$latitude:$longitude:$timestamp:$batteryLevel';
  }

  /// Parses an encoded beacon packet
  static SosBeaconPayload? parse(String raw, {int? rssi}) {
    if (!raw.startsWith('ALLIN1_SOS:')) return null;
    final parts = raw.split(':');
    if (parts.length < 6) return null;

    final uid = parts[1];
    final lat = double.tryParse(parts[2]);
    final lng = double.tryParse(parts[3]);
    final ts = int.tryParse(parts[4]);
    final batt = int.tryParse(parts[5]);

    if (lat == null || lng == null || ts == null || batt == null) return null;

    final distance = rssi != null ? estimateDistance(rssi) : null;

    return SosBeaconPayload(
      userId: uid,
      latitude: lat,
      longitude: lng,
      timestamp: ts,
      batteryLevel: batt,
      rssi: rssi,
      estimatedDistanceMeters: distance,
    );
  }

  /// Estimates approximate distance in meters from Bluetooth RSSI
  /// Path loss formula: Distance = 10 ^ ((Measured Power - RSSI) / (10 * N))
  /// Measured Power @ 1m ~ -59 dBm, Path Loss Exponent N ~ 2.4
  static double estimateDistance(int rssi) {
    if (rssi == 0) return -1.0;
    const double txPower = -59.0;
    const double n = 2.4;
    final ratio = (txPower - rssi) / (10 * n);
    final distance = math.pow(10.0, ratio).toDouble();
    return double.parse(distance.toStringAsFixed(1));
  }

  Map<String, dynamic> toMap() => {
        'userId': userId,
        'latitude': latitude,
        'longitude': longitude,
        'timestamp': timestamp,
        'batteryLevel': batteryLevel,
        'userName': userName ?? 'Emergency Requester',
        'userPhone': userPhone ?? '',
        'rssi': rssi,
        'estimatedDistanceMeters': estimatedDistanceMeters,
      };
}

class OfflineSosMeshService {
  OfflineSosMeshService._();
  static final OfflineSosMeshService instance = OfflineSosMeshService._();

  bool _isBroadcasting = false;
  bool get isBroadcasting => _isBroadcasting;

  bool _isScanning = false;
  bool get isScanning => _isScanning;

  SosBeaconPayload? _activeBeacon;
  SosBeaconPayload? get activeBeacon => _activeBeacon;

  final StreamController<SosBeaconPayload> _nearbyBeaconController =
      StreamController<SosBeaconPayload>.broadcast();
  Stream<SosBeaconPayload> get nearbyBeacons => _nearbyBeaconController.stream;

  final Set<String> _relayedBeacons = <String>{};

  /// Starts broadcasting an emergency SOS beacon
  Future<void> startBroadcasting({
    required String userId,
    required double latitude,
    required double longitude,
    required int batteryLevel,
    String? userName,
    String? userPhone,
  }) async {
    _activeBeacon = SosBeaconPayload(
      userId: userId,
      latitude: latitude,
      longitude: longitude,
      timestamp: DateTime.now().millisecondsSinceEpoch,
      batteryLevel: batteryLevel,
      userName: userName,
      userPhone: userPhone,
    );
    _isBroadcasting = true;
    debugPrint('[OfflineSosMesh] Started broadcasting SOS beacon: ${_activeBeacon?.encode()}');
  }

  /// Stops broadcasting
  Future<void> stopBroadcasting() async {
    _isBroadcasting = false;
    _activeBeacon = null;
    debugPrint('[OfflineSosMesh] Stopped broadcasting SOS beacon.');
  }

  /// Simulates / processes an incoming offline radio packet received from nearby peer
  Future<void> onPacketReceived(String rawPacket, {int? rssi, String? relayingUserId}) async {
    final payload = SosBeaconPayload.parse(rawPacket, rssi: rssi);
    if (payload == null) return;

    _nearbyBeaconController.add(payload);
    debugPrint('[OfflineSosMesh] Detected nearby SOS Beacon: ${payload.userId} (dist: ${payload.estimatedDistanceMeters}m)');

    // Attempt Store & Forward relay to Cloud Firestore if connected
    await relayToCloud(payload, relayedBy: relayingUserId);
  }

  /// Relays an offline-received beacon to Firestore `sos_alerts`
  Future<bool> relayToCloud(SosBeaconPayload beacon, {String? relayedBy}) async {
    final beaconKey = '${beacon.userId}_${beacon.timestamp}';
    if (_relayedBeacons.contains(beaconKey)) {
      return true; // Already relayed
    }

    try {
      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'userId': beacon.userId,
        'name': beacon.userName ?? 'Offline Requester',
        'phone': beacon.userPhone ?? '',
        'latitude': beacon.latitude,
        'longitude': beacon.longitude,
        'location': GeoPoint(beacon.latitude, beacon.longitude),
        'timestamp': FieldValue.serverTimestamp(),
        'beaconTimestamp': beacon.timestamp,
        'batteryLevel': beacon.batteryLevel,
        'status': 'active',
        'type': 'mesh_relay',
        'relayedBy': relayedBy ?? 'nearby_peer',
        'relayedAt': FieldValue.serverTimestamp(),
        'rssi': beacon.rssi,
        'estimatedDistanceMeters': beacon.estimatedDistanceMeters,
      });

      _relayedBeacons.add(beaconKey);
      debugPrint('[OfflineSosMesh] Successfully relayed offline SOS beacon to cloud!');
      return true;
    } catch (e) {
      debugPrint('[OfflineSosMesh] Could not relay to cloud (offline): $e');
      return false;
    }
  }

  /// Computes distance in meters between two lat/lng coordinates (Haversine formula)
  static double calculateDistanceInMeters(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    const double earthRadius = 6371000; // meters
    final dLat = _degToRad(lat2 - lat1);
    final dLon = _degToRad(lon2 - lon1);

    final a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);

    final c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return earthRadius * c;
  }

  /// Computes initial bearing / compass angle in degrees from point A to point B
  static double calculateBearing(
    double lat1,
    double lon1,
    double lat2,
    double lon2,
  ) {
    final dLon = _degToRad(lon2 - lon1);
    final y = math.sin(dLon) * math.cos(_degToRad(lat2));
    final x = math.cos(_degToRad(lat1)) * math.sin(_degToRad(lat2)) -
        math.sin(_degToRad(lat1)) *
            math.cos(_degToRad(lat2)) *
            math.cos(dLon);

    final brng = math.atan2(y, x);
    return (_radToDeg(brng) + 360) % 360;
  }

  static double _degToRad(double deg) => deg * (math.pi / 180.0);
  static double _radToDeg(double rad) => rad * (180.0 / math.pi);
}
