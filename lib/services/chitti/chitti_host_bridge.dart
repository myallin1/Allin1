// ================================================================
// chitti_host_bridge.dart — lets Chitti drive a screen's OWN logic
// instead of re-implementing it.
// ================================================================
// WHY THIS EXISTS (Aug 27 2026 — Hero/Seller tool work).
//
// Two of the new tools — hero_set_online_status and
// seller_set_shop_open — look like one-line Firestore writes and are
// absolutely not.
//
// Going online as a Hero is not `{'isOnline': true}`. Look at
// hero_home_screen.dart's _syncOnlineStatus(): it acquires a location
// fix (and has a whole documented failure path for browsers that
// refuse it), writes the RTDB radar entry that dispatch reads,
// installs the ride- and service-ping listeners, and throttles the
// Firestore status write behind a 3-minute gate. If Chitti wrote the
// flag by itself, the hero would look online to dispatch while having
// NO ping listener attached — jobs would be broadcast to them and
// silently never appear. That is worse than the tool not existing.
//
// So Chitti does not own that logic. The screen that already owns it
// registers a handler here while it is mounted, and Chitti calls
// through to the real thing. When the screen is not mounted there is
// no handler, and the executor falls back to navigating there and
// saying so honestly — which is the correct answer, not a failure.
//
// Deliberately dumb: no state, no streams, no notifyListeners. Just
// "the screen that can do X is currently on screen, here is how to
// ask it". Anything richer would start duplicating the screen state
// this file exists to avoid duplicating.
import 'package:flutter/foundation.dart';

/// Returns a short sentence describing what happened, for Chitti to
/// relay verbatim. Returning a string rather than a bool keeps the
/// wording with the code that actually knows what it did.
// A named parameter would read better in isolation, but this typedef
// exists to be satisfied by a screen method whose whole job is "set it
// to this" — `setOnline(true)` at every call site is clearer than
// `setOnline(value: true)`, and there is no second argument to confuse
// it with.
// ignore: avoid_positional_boolean_parameters
typedef ChittiToggleHandler = Future<String> Function(bool value);

class ChittiHostBridge {
  ChittiHostBridge._();

  /// Registered by HeroHomeScreen while mounted.
  static ChittiToggleHandler? heroOnlineHandler;

  /// Registered by SellerDashboardScreen while mounted.
  static ChittiToggleHandler? sellerShopOpenHandler;

  static bool get canToggleHeroOnline => heroOnlineHandler != null;

  static bool get canToggleSellerShop => sellerShopOpenHandler != null;

  /// Clears a handler only if it is still the one that was registered.
  ///
  /// The identity check matters: on a push/replace the NEW screen can
  /// register before the OLD one disposes, and an unconditional clear
  /// in dispose() would then wipe the live handler and leave the
  /// bridge dead for the rest of the session.
  static void unregisterHeroOnline(ChittiToggleHandler handler) {
    if (identical(heroOnlineHandler, handler)) heroOnlineHandler = null;
  }

  static void unregisterSellerShop(ChittiToggleHandler handler) {
    if (identical(sellerShopOpenHandler, handler)) sellerShopOpenHandler = null;
  }

  /// Test/teardown hook — never call this from app code.
  @visibleForTesting
  static void resetAll() {
    heroOnlineHandler = null;
    sellerShopOpenHandler = null;
  }
}
