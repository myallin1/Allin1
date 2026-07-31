// ================================================================
// FoodFirebaseOptions — config for the SECOND, dedicated Firebase
// project ("myallin1-food") that holds only seller/catalog data
// (sellers, menu_items, food_orders — every business vertical:
// food/grocery/electronics/home-kitchen). This keeps that read-heavy
// browsing traffic off the MAIN project's Spark free-tier quota,
// giving the app a second independent quota bucket.
// ================================================================
// Auth, taxi rides, hero bookings and service_requests (real order
// dispatch) all stay on the MAIN project (firebase_options.dart) —
// only sellers/menu_items/food_orders live here. This project has no
// customer PII: shop name/category/menu/price data only.
//
// Only the Customer app and Admin app touch this project (Hero app
// never reads seller/menu data). The Seller app is web-only (PWA), so
// it always uses the `web` config below regardless of platform.
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb, TargetPlatform;

class FoodFirebaseOptions {
  /// Web config, shared by the Customer PWA, Admin PWA, and the
  /// (web-only) Seller app.
  static const FirebaseOptions web = FirebaseOptions(
    apiKey: 'AIzaSyBszGNo1h3QapBHlUvMzDmrgZTZoUYnf7A',
    appId: '1:231344900059:web:3db7607c6806f2f6b109fe',
    messagingSenderId: '231344900059',
    projectId: 'myallin1-food',
    authDomain: 'myallin1-food.firebaseapp.com',
    storageBucket: 'myallin1-food.firebasestorage.app',
    measurementId: 'G-VK30CFBBKW',
  );

  /// Native Android — Customer app flavor (com.njtech.myallin1).
  static const FirebaseOptions androidCustomer = FirebaseOptions(
    apiKey: 'AIzaSyC7P56p7uTYN9X6fQ-AfTQFJgB-NGyzwMw',
    appId: '1:231344900059:android:83a68ba14a517032b109fe',
    messagingSenderId: '231344900059',
    projectId: 'myallin1-food',
    storageBucket: 'myallin1-food.firebasestorage.app',
  );

  /// Native Android — Admin app flavor (com.njtech.admininallin1).
  static const FirebaseOptions androidAdmin = FirebaseOptions(
    apiKey: 'AIzaSyC7P56p7uTYN9X6fQ-AfTQFJgB-NGyzwMw',
    appId: '1:231344900059:android:ca8f33a450b1f664b109fe',
    messagingSenderId: '231344900059',
    projectId: 'myallin1-food',
    storageBucket: 'myallin1-food.firebasestorage.app',
  );

  /// Picks the right options for the CUSTOMER app on whatever platform
  /// it's currently running on.
  static FirebaseOptions forCustomerApp() {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return androidCustomer;
    return web; // iOS/other: no native config yet, fall back gracefully.
  }

  /// Picks the right options for the ADMIN app on whatever platform
  /// it's currently running on.
  static FirebaseOptions forAdminApp() {
    if (kIsWeb) return web;
    if (defaultTargetPlatform == TargetPlatform.android) return androidAdmin;
    return web;
  }
}
