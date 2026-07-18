// ================================================================
// ride_search_service.dart — Admin Call Center ride creation
// Mirrors the customer-initiated ride model in ride_search_screen.dart:
// a `rides` doc in Firestore plus an `active_ride_requests` mirror and
// a `hero_pings/{heroId}/{requestId}` ping in RTDB, so the hero app's
// existing listeners pick up admin-created rides identically to
// customer-created ones.
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';

class RideSearchService {
  /// Normalizes a raw phone number to E.164 with the +91 country code.
  /// Passes through numbers that already carry a `+` prefix.
  static String normalizePhone(String phone) {
    final trimmed = phone.trim();
    if (trimmed.startsWith('+')) return trimmed;
    final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) {
      return '+91$digits';
    }
    return '+$digits';
  }

  /// Creates a call-center-initiated ride: a `rides` doc in Firestore
  /// plus an `active_ride_requests` mirror in RTDB, matching the shape
  /// the hero app already listens on for customer-initiated rides.
  /// Returns the Firestore doc ID (`rideId`), or null on failure.
  Future<String?> createCallCenterRide(Map<String, dynamic> rideData) async {
    try {
      final firestoreRef = FirebaseFirestore.instance.collection('rides').doc();
      final rideId = firestoreRef.id;

      await firestoreRef.set({
        'status': 'searching',
        'customerName': rideData['customerName'],
        'customerPhone': rideData['customerPhone'],
        'pickupAddress': rideData['pickupAddress'],
        'dropAddress': rideData['dropAddress'],
        'category': rideData['category'],
        'pickupLat': rideData['pickupLatitude'],
        'pickupLng': rideData['pickupLongitude'],
        'createdAt': FieldValue.serverTimestamp(),
        'source': 'call_center',
      });

      final ref = FirebaseDatabase.instance.ref('active_ride_requests').push();
      await ref.set({
        'customerName': rideData['customerName'],
        'customerPhone': rideData['customerPhone'],
        'firestoreDocId': rideId,
        'pickupAddress': rideData['pickupAddress'],
        'dropAddress': rideData['dropAddress'],
        'pickupLat': rideData['pickupLatitude'],
        'pickupLng': rideData['pickupLongitude'],
        'category': rideData['category'],
        'status': 'searching',
        'currentPingHeroId': '',
        'acceptedHeroId': '',
        'createdAt': ServerValue.timestamp,
      });

      return rideId;
    } catch (_) {
      return null;
    }
  }

  /// Pings a single hero about a call-center-created ride, mirroring
  /// the `hero_pings/{heroId}/{requestId}` write in ride_search_screen.dart
  /// so the hero app's existing ping listener picks it up unchanged.
  Future<void> pingHero(
    String heroId,
    String rideId,
    Map<String, dynamic> rideData,
  ) async {
    final pingExpiresAt =
        DateTime.now().toUtc().millisecondsSinceEpoch + 10000;
    await FirebaseDatabase.instance.ref('hero_pings/$heroId/$rideId').set({
      'requestId': rideId,
      'firestoreDocId': rideId,
      'customerName': rideData['customerName'],
      'customerPhone': rideData['customerPhone'],
      'pickupAddress': rideData['pickupAddress'],
      'dropAddress': rideData['dropAddress'],
      'pickupLat': rideData['pickupLatitude'],
      'pickupLng': rideData['pickupLongitude'],
      'category': rideData['category'],
      'pingExpiresAt': pingExpiresAt,
      'status': 'pinging',
    });
  }
}
