import 'package:flutter/material.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// NEW (Aug 25 2026 — Super Chitti Phase 1 fix: "Screen Forgetting
// Sickness"). App-wide RouteObserver, same singleton-per-app-lifetime
// shape as navigatorKey above. Registered in each MaterialApp's
// navigatorObservers list; ChittiScreenTag and any screen that tracks
// its own Chitti screen-awareness (bike_booking_screen.dart,
// grocery_order_screen.dart) subscribe to it as a RouteAware so
// didPopNext() can re-register the screen label when the user
// navigates BACK to it — initState()/dispose() alone only ever see a
// screen appearing for the first time or going away for good, never a
// screen becoming visible again after something pushed on top of it
// was popped.
final RouteObserver<PageRoute<dynamic>> chittiRouteObserver =
    RouteObserver<PageRoute<dynamic>>();
