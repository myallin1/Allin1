// ================================================================
// FoodDbService — secondary Firebase app for seller/catalog data
// ================================================================
// Nizam's cost-cutting plan: a SECOND, standalone Firebase project
// ("myallin1-food") hosts only sellers/menu_items/food_orders (all
// business verticals — food, grocery, electronics, home-kitchen).
// This is a genuinely separate Firebase project with its own free
// Spark-plan quota, so browsing traffic (customers loading category
// menus) no longer eats into the MAIN project's quota.
//
// Security: this project has NO customer PII (no orders with names/
// phone/address — those stay on the main project's service_requests
// collection). To still block random internet bots from spamming it
// (fake menu items, junk seller docs) without adding any real
// per-user security logic, every app signs in ANONYMOUSLY to this
// project on startup, and its Firestore rules require
// `request.auth != null`. No login screen, no user-visible change —
// it's a silent background sign-in purely to satisfy that rule.
//
// Only the Customer app and Admin app call ensureInitialized() (Hero
// app never touches seller/menu data, so it never opens this second
// connection at all).
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class FoodDbService {
  FoodDbService._internal();
  static final FoodDbService _instance = FoodDbService._internal();
  factory FoodDbService() => _instance;

  static const String _appName = 'foodDb';

  FirebaseApp? _app;
  FirebaseFirestore? _firestore;
  bool _initializing = false;

  /// The secondary project's Firestore instance. Only valid to call
  /// after [ensureInitialized] has completed at least once — every
  /// call site in this app goes through the main entry point's boot
  /// sequence first, so this should always be ready by the time a
  /// screen needs it.
  FirebaseFirestore get firestore {
    final fs = _firestore;
    if (fs == null) {
      // Defensive fallback: if a screen somehow runs before boot
      // finished initializing the secondary project, fail loud in
      // debug so it gets caught instead of silently querying the
      // wrong (main) database.
      throw StateError(
          '[FoodDbService] firestore accessed before ensureInitialized() completed.');
    }
    return fs;
  }

  bool get isReady => _firestore != null;

  /// Sets up the secondary Firebase app (idempotent — safe to call
  /// more than once, e.g. on hot-restart) and signs into it
  /// anonymously so its `request.auth != null` security rules pass.
  Future<void> ensureInitialized(FirebaseOptions options) async {
    if (_firestore != null) return;
    if (_initializing) return;
    _initializing = true;
    try {
      final existing = Firebase.apps.where((a) => a.name == _appName);
      _app = existing.isNotEmpty
          ? existing.first
          : await Firebase.initializeApp(name: _appName, options: options);

      final auth = FirebaseAuth.instanceFor(app: _app!);
      if (auth.currentUser == null) {
        await auth.signInAnonymously();
      }

      _firestore = FirebaseFirestore.instanceFor(app: _app!);
      debugPrint('[FoodDbService] Ready — connected to myallin1-food, anon uid: ${auth.currentUser?.uid}');
    } catch (e) {
      debugPrint('[FoodDbService] Failed to initialize secondary Firebase app: $e');
      // Leave _firestore null — callers that need it will throw a
      // clear StateError instead of silently hitting the wrong DB.
    } finally {
      _initializing = false;
    }
  }
}
