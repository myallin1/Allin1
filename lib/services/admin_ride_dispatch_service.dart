// lib/services/admin_ride_dispatch_service.dart
// Call-center / admin-initiated bike-taxi ride booking.
//
// Self-contained on purpose — does NOT import or touch anything from
// ride_search_screen.dart's private State methods (per explicit
// instruction). It mirrors the same Firestore/RTDB document shapes
// that ride_search_screen.dart (customer self-booking) and
// hero_home_screen.dart (hero accept flow) already use, so the
// existing, already-tested hero-side accept UI can pick this up with
// zero changes on that side.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';

class AdminRideDispatchService {
  AdminRideDispatchService._();

  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final FirebaseDatabase _rtdb = FirebaseDatabase.instance;

  // Fallback pickup/drop coordinates — mirrors the exact fallback
  // constants ride_search_screen.dart uses when real coordinates are
  // unavailable. This screen has no geocoding yet (see the existing
  // "TODO(Phase 2): Replace with real dispatch-center / pickup
  // coordinates" comment at the top of admin_hero_dispatch_screen.dart)
  // — addresses are free-text only, so lat/lng here are placeholders,
  // not a regression introduced by this change.
  static const double _fallbackPickupLat = 11.3410;
  static const double _fallbackPickupLng = 77.7172;
  static const double _fallbackDropLat = 11.3520;
  static const double _fallbackDropLng = 77.7280;

  /// Looks up an existing `users` doc by phone number; creates a
  /// minimal one if none exists. Field set mirrors the required fields
  /// auth_service.dart's own `users` writes always include (phone,
  /// phoneNumber, userType, role, isSetupComplete, createdAt) so this
  /// record won't break any screen that reads a `users` doc expecting
  /// those fields to exist. No `.where()`/`.orderBy()` query anywhere
  /// in the codebase filters on the extra fields below, so this is
  /// safe to add without touching any other screen.
  static Future<String> _getOrCreateCustomerId({
    required String phone,
    required String name,
  }) async {
    final trimmedPhone = phone.trim();

    final existing = await _firestore
        .collection('users')
        .where('phone', isEqualTo: trimmedPhone)
        .limit(1)
        .get();
    if (existing.docs.isNotEmpty) {
      return existing.docs.first.id;
    }

    final newDoc = _firestore.collection('users').doc();
    await newDoc.set({
      'phone': trimmedPhone,
      'phoneNumber': trimmedPhone,
      'name': name.trim(),
      'username': name.trim(),
      // UserType.customer.index — see services/session_service.dart.
      // Kept as a raw int (not importing UserType here) to avoid
      // pulling session_service.dart's broader surface into this
      // narrow, self-contained service.
      'userType': 0,
      'role': 'customer',
      'isSetupComplete': true,
      // Not OTP-verified — this record was entered by an admin/call
      // center operator on the customer's behalf.
      'isVerified': false,
      'createdViaCallCenter': true,
      'createdAt': FieldValue.serverTimestamp(),
    });
    return newDoc.id;
  }

  /// Creates a call-center-initiated ride already assigned to a
  /// specific, admin-selected hero (no broadcast/ping-queue — the
  /// admin has already picked who gets it).
  ///
  /// IMPORTANT: still writes a `hero_pings/{heroId}/{requestId}` entry
  /// even though the ride is pre-assigned. hero_home_screen.dart's
  /// entire ride-notification UI (the dialog + ringtone) is driven
  /// ONLY by that RTDB path — there is no passive listener anywhere in
  /// the Hero app that watches `active_ride_requests` for docs where
  /// `acceptedHeroId` already equals the hero's uid. Skipping this
  /// write would make the booking invisible to the hero: it would
  /// exist correctly in Firestore/RTDB but never surface any UI, dialog,
  /// or ringtone on the hero's device. Writing it reuses the hero
  /// app's existing, already-tested accept flow completely unchanged.
  static Future<void> dispatchRideToHero({
    required String customerName,
    required String customerPhone,
    required String pickupAddress,
    required String dropAddress,
    required String category,
    required String heroId,
    required String heroName,
    required String heroPhone,
  }) async {
    final adminUid = FirebaseAuth.instance.currentUser?.uid ?? '';
    final customerId = await _getOrCreateCustomerId(
      phone: customerPhone,
      name: customerName,
    );

    final rideRef = _firestore.collection('rides').doc();
    await rideRef.set({
      'status': 'assigned',
      'customerId': customerId,
      'category': category,
      'createdAt': FieldValue.serverTimestamp(),
      'createdByAdminId': adminUid,
      'bookedViaCallCenter': true,
      'assignedHeroId': heroId,
    });

    final requestRef = _rtdb.ref('active_ride_requests').push();
    final requestId = requestRef.key!;
    await requestRef.set({
      'customerId': customerId,
      'customerName': customerName,
      'customerPhone': customerPhone,
      'firestoreDocId': rideRef.id,
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      'pickupLat': _fallbackPickupLat,
      'pickupLng': _fallbackPickupLng,
      'dropLat': _fallbackDropLat,
      'dropLng': _fallbackDropLng,
      'distanceKm': 0,
      'estimatedFare': 0,
      'tipAmount': 0,
      'vehicleType': category,
      'category': category,
      // Pre-assigned, not broadcast — no 'pinging'/currentPingHeroId
      // fields here, per the approved plan.
      'status': 'assigned',
      'acceptedHeroId': heroId,
      'acceptedHeroName': heroName,
      'acceptedHeroPhone': heroPhone,
      'createdAt': ServerValue.timestamp,
    });

    // See method-level doc comment above — required for the hero app
    // to actually show/notify this ride. Mirrors the exact ping shape
    // ride_search_screen.dart writes (lines ~403-421) so
    // hero_home_screen.dart's existing _acceptRide()/_rejectRide()
    // flow handles it identically to a normal broadcast ping.
    await _rtdb.ref('hero_pings/$heroId/$requestId').set({
      'requestId': requestId,
      'customerId': customerId,
      'firestoreDocId': rideRef.id,
      'pickupAddress': pickupAddress,
      'dropAddress': dropAddress,
      'pickupLat': _fallbackPickupLat,
      'pickupLng': _fallbackPickupLng,
      'dropLat': _fallbackDropLat,
      'dropLng': _fallbackDropLng,
      'distanceKm': 0,
      'estimatedFare': 0,
      'tipAmount': 0,
      'vehicleType': category,
      'category': category,
      // Generous 2-minute window — this hero was specifically chosen
      // by the admin, not competing in a sequential broadcast queue,
      // so there's no reason to use the tight ~10s per-hero window
      // ride_search_screen.dart uses while cycling through candidates.
      'pingExpiresAt':
          DateTime.now().toUtc().millisecondsSinceEpoch + 120000,
      'status': 'pinging',
    });
  }
}
