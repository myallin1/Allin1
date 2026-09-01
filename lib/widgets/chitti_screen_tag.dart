// ================================================================
// ChittiScreenTag — Super Chitti Phase 1, Step 1 (Passive Screen
// Awareness), Aug 25 2026
// ================================================================
// Small wrapper so a StatelessWidget screen (which has no initState/
// dispose of its own) can still report itself to
// ChittiMemoryService.setCurrentScreen(), exactly the way
// bike_booking_screen.dart's own StatefulWidget already does directly.
//
// Usage: wrap whatever a screen's build() returns —
//   return ChittiScreenTag(
//     label: 'Food Dashboard',
//     child: Scaffold(...),
//   );
//
// For a screen that's ALREADY a StatefulWidget with its own State,
// prefer calling ChittiMemoryService.instance.setCurrentScreen(...)
// directly in that State's initState/dispose (see
// grocery_order_screen.dart) — this wrapper exists only for screens
// with no State object of their own to hang the call off. Whichever
// approach a screen uses, it must ALSO subscribe to
// app_navigator.dart's `chittiRouteObserver` and re-register on
// didPopNext() — see the fix note below.
//
// FIX (Aug 25 2026 — "Screen Forgetting Sickness" audit finding):
// initState()/dispose() alone only ever see a screen appearing for
// the FIRST time or going away for GOOD. They never fire again when a
// screen that's still on the stack becomes visible again because
// something pushed on top of it got popped — e.g. Food Dashboard ->
// push -> Bike Taxi -> pop back to Food Dashboard. Bike Taxi's
// dispose() correctly clears the label on the way out, but nothing
// then re-sets it back to 'Food Dashboard', leaving currentScreen
// null until the next unrelated navigation happens to overwrite it.
// RouteAware.didPopNext() is the one Flutter lifecycle hook that
// fires exactly at that "became visible again" moment, so this now
// re-asserts the label there too.
import 'package:flutter/material.dart';

import '../app_navigator.dart' show chittiRouteObserver;
import '../services/chitti_memory_service.dart';

class ChittiScreenTag extends StatefulWidget {
  const ChittiScreenTag({super.key, required this.label, required this.child});

  /// Short, human-readable name Chitti can reason about directly in a
  /// prompt (e.g. "Food Dashboard") — not a route path or class name.
  final String label;
  final Widget child;

  @override
  State<ChittiScreenTag> createState() => _ChittiScreenTagState();
}

class _ChittiScreenTagState extends State<ChittiScreenTag> with RouteAware {
  @override
  void initState() {
    super.initState();
    ChittiMemoryService.instance.setCurrentScreen(widget.label);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final route = ModalRoute.of(context);
    if (route is PageRoute<dynamic>) {
      chittiRouteObserver.subscribe(this, route);
    }
  }

  /// Fired when the route pushed on top of this one is popped and this
  /// screen is visible again — re-registers the label the same way
  /// initState() did the first time around.
  @override
  void didPopNext() {
    ChittiMemoryService.instance.setCurrentScreen(widget.label);
  }

  @override
  void dispose() {
    chittiRouteObserver.unsubscribe(this);
    // Only clear if nothing else already overwrote it (e.g. a screen
    // pushed on top of this one tagged itself in the meantime) — same
    // best-effort guard bike_booking_screen.dart's dispose() uses.
    if (ChittiMemoryService.instance.currentScreen == widget.label) {
      ChittiMemoryService.instance.setCurrentScreen(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
