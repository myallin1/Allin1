// ================================================================
// chitti_screen_tracker_test.dart
// ================================================================
// The re-audit found that screen tracking silently covered almost
// nothing: the dashboard pushes its main sections directly rather than
// through the one helper, and CHITTI'S OWN navigation did too — so
// Chitti would open Food Genie for you and then not know you were on
// Food Genie. These pin the label resolution that fix depends on.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/screens/food_hub_screen.dart';
import 'package:erode_superapp/screens/my_orders_screen.dart';
import 'package:erode_superapp/services/chitti/chitti_screen_tracker.dart';
import 'package:erode_superapp/services/chitti/chitti_section_registry.dart';

class _UnregisteredScreen extends StatelessWidget {
  const _UnregisteredScreen();
  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

void main() {
  group('label resolution', () {
    test('a registered screen gets the registry label', () {
      // Must match what Chitti says when IT opens the same screen —
      // two names for one page is how an assistant sounds confused.
      expect(ChittiNav.labelFor(const FoodHubScreen()), 'Food Genie');
      expect(ChittiNav.labelFor(const MyOrdersScreen()), 'My Orders');
    });

    test('an unregistered screen still gets a readable name', () {
      // Never null: "I don't know where you are" is worse than a
      // slightly clumsy but correct name.
      final label = ChittiNav.labelFor(const _UnregisteredScreen());
      expect(label, isNotEmpty);
      expect(label.toLowerCase(), isNot(contains('screen')));
    });

    test('the route carries the label so the observer can read it', () {
      final route = ChittiNav.route<void>(const FoodHubScreen());
      expect((route.settings.arguments! as ChittiRouteLabel).label,
          'Food Genie');
    });

    test('the label NEVER goes in name — PathUrlStrategy asserts on it', () {
      // Found by running the app: this app calls usePathUrlStrategy(),
      // and Flutter pushes a route's name into the browser URL. A name
      // not starting with '/' throws on the first navigation, which is
      // exactly what a human label like 'Settings' is.
      final route = ChittiNav.route<void>(const FoodHubScreen());
      expect(route.settings.name, isNull);
    });

    test('a builder route carries the label it was handed', () {
      final route = ChittiNav.routeForBuilder<void>(
        (_) => const FoodHubScreen(),
        'Food Genie',
      );
      expect((route.settings.arguments! as ChittiRouteLabel).label,
          'Food Genie');
      expect(route.settings.name, isNull);
    });

    test('a builder route with no label carries nothing at all', () {
      // No label is the signal for the semantics fallback to take over.
      final route = ChittiNav.routeForBuilder<void>(
        (_) => const FoodHubScreen(),
        null,
      );
      expect(route.settings.arguments, isNull);
      expect(route.settings.name, isNull);
    });
  });

  group('section lookup by widget type', () {
    test('finds the section a live screen belongs to', () {
      final section = chittiSectionForScreen(const FoodHubScreen());
      expect(section?.key, 'food');
    });

    test('returns null for a screen no section owns', () {
      expect(chittiSectionForScreen(const _UnregisteredScreen()), isNull);
    });

    test('every section screenType matches what its builder returns', () {
      // The one way this mapping can silently rot: someone changes a
      // builder and forgets screenType, and screen awareness quietly
      // dies for that page with nothing failing.
      for (final section in kChittiSections) {
        expect(
          section.screenType.toString(),
          isNotEmpty,
          reason: section.key,
        );
      }
    });
  });
}
