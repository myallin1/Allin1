// ================================================================
// chitti_screen_tracker.dart — Chitti follows the customer around the
// app, without every screen having to opt in.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "customer yenna service yeduthu yentha
// screen la irukaro Chitti avarkuda poi antha page la irukurathu
// question kettu ... antha works mudikkanum").
//
// ChittiMemoryService.currentScreen already existed, and the prompt
// already used it. The problem was adoption: setCurrentScreen() was
// called from exactly TWO screens out of a hundred-odd, so for almost
// the whole app Chitti had no idea where the customer was standing.
// "Book it for me" or "what is this page?" had nothing to resolve
// against.
//
// The existing widget-level approach (ChittiScreenTag, plus an
// initState/dispose pair) works, but it needs a line in every screen —
// which is exactly why it stalled at two. This does it from the
// Navigator instead, so a screen is tracked without knowing it exists.
//
// HOW THE LABEL SURVIVES A POP
// The label rides on the ROUTE, in `RouteSettings.arguments`, rather
// than in a side map. Popping back is then free: the observer reads it
// off `previousRoute`, which is the route the customer is returning
// to. A side map would have had to be kept in sync with the navigator
// stack by hand — the class of bug that produced the "Screen
// Forgetting Sickness" note in chitti_screen_tag.dart.
//
// WHY `arguments` AND NOT `name` (found by running the app, Aug 28)
// `name` was the obvious slot and it is wrong here. This app calls
// usePathUrlStrategy(), and Flutter pushes a route's name into the
// browser's URL — which asserts unless the name starts with '/'.
// Putting a human label like 'Settings' there threw
//     "all route names must start with '/' ... Found route name:
//      'Settings'"
// on the very first navigation of the web build. `arguments` carries
// no URL meaning, so it is the correct place for something that is
// only ever for us.
//
// TWO WAYS A SCREEN GETS ITS NAME
// A NavigatorObserver is handed a Route, not the widget inside it, and
// a Route will not say what its builder returns without building it.
// So where the push site has the widget in hand, [ChittiNav] writes the
// registry label into RouteSettings — that is the precise path.
//
// Everything else (the dashboard's direct pushes, Chitti's own
// navigation, and every screen added in future) arrives unnamed, and
// falls back to asking the SCREEN what it calls itself via the
// semantics tree. That fallback is what makes coverage complete
// without anyone having to remember this file exists.
import 'dart:async';

import 'package:flutter/material.dart';

import '../chitti_memory_service.dart';
import 'chitti_screen_reader.dart';
import 'chitti_section_registry.dart';

/// A screen's human name, carried on the route for Chitti's benefit.
///
/// A dedicated type rather than a bare String so that reading it back
/// can never collide with whatever real arguments another route
/// happens to carry.
@immutable
class ChittiRouteLabel {
  const ChittiRouteLabel(this.label);
  final String label;
}

/// Pushes a screen and tells Chitti where the customer went.
///
/// A drop-in replacement for `Navigator.push(context,
/// MaterialPageRoute(builder: (_) => screen))`. The only difference is
/// the RouteSettings name, which [ChittiScreenObserver] reads.
class ChittiNav {
  ChittiNav._();

  /// Resolves a human label for [screen] — the section registry's own
  /// label where the screen is a known section, so what Chitti says
  /// ("you're on Food Genie") matches what it says when IT opens the
  /// same screen.
  ///
  /// Falls back to the class name split into words, which is wrong-ish
  /// but never misleading: "NjTechStoreScreen" reads as "Nj Tech
  /// Store". Better than null, which means Chitti claims not to know
  /// where you are.
  static String labelFor(Widget screen) {
    final section = chittiSectionForScreen(screen);
    if (section != null) return section.label;
    return _humanizeType(screen.runtimeType.toString());
  }

  static Future<T?> push<T>(BuildContext context, Widget screen) {
    return Navigator.push<T>(context, route<T>(screen));
  }

  /// The route on its own, for callers that push through a Navigator
  /// they hold directly (the overlay uses `navigatorKey.currentState`,
  /// which has no BuildContext of its own).
  static MaterialPageRoute<T> route<T>(Widget screen) {
    return MaterialPageRoute<T>(
      builder: (_) => screen,
      settings: RouteSettings(arguments: ChittiRouteLabel(labelFor(screen))),
    );
  }

  /// Same, for a caller that has a builder rather than a widget — which
  /// is what ChittiActionResult carries. [label] is passed explicitly
  /// because a builder cannot be asked what it returns without running
  /// it, and running it outside a build is not allowed.
  static MaterialPageRoute<T> routeForBuilder<T>(
    WidgetBuilder builder,
    String? label,
  ) {
    return MaterialPageRoute<T>(
      builder: builder,
      settings: RouteSettings(
        arguments: (label == null || label.isEmpty)
            ? null
            : ChittiRouteLabel(label),
      ),
    );
  }

  /// `Screen` suffix dropped, camelCase split, acronyms left alone.
  static String _humanizeType(String type) {
    var name = type;
    if (name.endsWith('Screen')) {
      name = name.substring(0, name.length - 'Screen'.length);
    }
    final spaced = name.replaceAllMapped(
      RegExp('([a-z0-9])([A-Z])'),
      (m) => '${m[1]} ${m[2]}',
    );
    return spaced.trim().isEmpty ? type : spaced.trim();
  }
}

/// Lets the overlay lift itself when a route is pushed, without this
/// file having to import the overlay (which imports half the app).
class ChittiOverlayLift {
  ChittiOverlayLift._();

  /// Set by GuruOverlayService. Null when no overlay is mounted, which
  /// is a normal state, not an error.
  static void Function()? onRoutePushed;
}

/// Keeps [ChittiMemoryService.currentScreen] pointing at whatever is on
/// top of the navigator.
///
/// Register once in the app's `navigatorObservers`. Routes with no name
/// are ignored rather than clearing the label — a dialog or a bottom
/// sheet opening on top of Food Genie does not mean the customer left
/// Food Genie, and blanking it there would make Chitti forget the page
/// at the exact moment someone is most likely to ask about it.
class ChittiScreenObserver extends NavigatorObserver {
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _apply(route);
    // FIX (Aug 28 2026 re-audit). Overlay entries stack in insertion
    // order, and the Chitti panel is inserted once, early — so every
    // route pushed afterwards lands ON TOP of it and the panel
    // disappears behind the new screen while still being "open".
    // bringToFront() existed but was only wired to un-minimise, which
    // is not the moment this happens.
    // FIX (Aug 28 2026 — Nizam: "chitti popup close um screen ku
    // backside multiple time close dialog varuthu... antha optionaye
    // close panna mudiyatha mari varuthu").
    //
    // Lift only for a real SCREEN, never for a dialog or popup.
    //
    // The lift re-inserts the overlay entry, which rebuilds the panel
    // — and the panel's initState opens dialogs (the resume prompt).
    // A dialog is itself a route, so lifting on one created a loop:
    // dialog opens -> route pushed -> panel rebuilt -> initState ->
    // dialog opens again. That is the stack of un-dismissable close
    // prompts, and the screen that appeared to open several times.
    //
    // PopupRoute covers dialogs, bottom sheets and menus. None of them
    // can hide the panel the way a pushed page does, which is the only
    // thing the lift was ever for.
    if (route is! PopupRoute) {
      ChittiOverlayLift.onRoutePushed?.call();
    }
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    // The customer is going BACK to previousRoute, so that is where
    // they now are.
    _apply(previousRoute);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _apply(newRoute);
  }

  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _apply(previousRoute);
  }

  static void _apply(Route<dynamic>? route) {
    // Our own label, if this route was pushed through ChittiNav.
    final tagged = route?.settings.arguments;
    if (tagged is ChittiRouteLabel && tagged.label.isNotEmpty) {
      ChittiMemoryService.instance.setCurrentScreen(tagged.label);
      return;
    }

    final name = route?.settings.name;
    if (name == null || name.isEmpty) {
      // FIX (Aug 28 2026 re-audit). A route with no name used to be
      // ignored outright, and that turned out to cover most of the app:
      // the dashboard pushes major sections (Bike Taxi, Grocery, Hero
      // Booking, NJ Tech Store) directly rather than through the one
      // helper, and — worse — CHITTI'S OWN navigation did too. So
      // Chitti would open Food Genie for you and then not know you were
      // on Food Genie, which defeats the whole feature.
      //
      // Rather than edit ~19 push sites (and every future one), fall
      // back to asking the screen what it calls itself. The semantics
      // tree already carries the app bar title, so this covers every
      // screen ever added, with nobody remembering to do anything.
      // Costs one semantics read per navigation, which is user-paced.
      _labelFromScreen();
      return;
    }
    // What is left is the app's own named-route table, whose names are
    // real paths ('/ai-assistant') because PathUrlStrategy requires it.
    // Tidy one into something a prompt can use as a sentence.
    final label = ChittiNav._humanizeType(
      name.startsWith('/') ? name.substring(1) : name,
    ).replaceAll('-', ' ').replaceAll('_', ' ').trim();
    if (label.isEmpty) {
      _labelFromScreen();
      return;
    }
    ChittiMemoryService.instance.setCurrentScreen(label);
  }

  /// Reads the newly-pushed screen's own title, one frame later.
  ///
  /// Deliberately fire-and-forget: a screen whose title cannot be read
  /// leaves the previous label in place, which is a better wrong answer
  /// than blanking it — Chitti saying "I'm not sure which page you're
  /// on" is worse than naming the page you were on a moment ago.
  static void _labelFromScreen() {
    unawaited(() async {
      try {
        final snapshot = await ChittiScreenReader.read();
        final title = snapshot.title;
        if (title == null || title.isEmpty) return;
        ChittiMemoryService.instance.setCurrentScreen(title);
      } catch (e) {
        debugPrint('[ChittiScreenObserver] title read failed: $e');
      }
    }());
  }
}
