// ================================================================
// chitti_overlay_lift_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam, second report of the same class of bug:
// "chitti screen tap pannuna athu multiple time screen open agitten
// irukku... chitti popup close um screen ku backside multiple time
// close dialog varuthu... antha optionaye close panna mudiyatha mari
// varuthu").
//
// THE MECHANISM
// ChittiOverlayLift fires on every pushed route, and the lift
// re-inserts the overlay entry, which REBUILDS the panel. The panel's
// initState opened a dialog. A dialog is itself a route. So:
//
//   dialog opens -> route pushed -> lift -> panel rebuilt
//     -> initState -> dialog opens -> ...
//
// That is the stack of un-dismissable prompts and the screen that
// appeared to open several times. This has now regressed twice, so
// the rule is pinned here rather than left to a comment: a PopupRoute
// must never trigger a lift.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_screen_tracker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late int lifts;

  setUp(() {
    lifts = 0;
    ChittiOverlayLift.onRoutePushed = () => lifts++;
  });

  tearDown(() => ChittiOverlayLift.onRoutePushed = null);

  Route<dynamic> page() => MaterialPageRoute<void>(
        builder: (_) => const SizedBox.shrink(),
      );

  // A minimal PopupRoute. DialogRoute, ModalBottomSheetRoute and the
  // menu routes are all PopupRoutes, so this stands in for every
  // overlay-style route without needing a live element tree.
  Route<dynamic> dialog() => _TestPopupRoute();

  group('what may lift the panel', () {
    test('a real screen lifts it', () {
      // This is the case the lift exists for: a pushed page lands on
      // top of the panel and would hide it.
      ChittiScreenObserver().didPush(page(), null);
      expect(lifts, 1);
    });

    test('a dialog does NOT lift it', () {
      // The loop. A dialog cannot hide the panel the way a page does,
      // and lifting rebuilds the panel that opened the dialog.
      ChittiScreenObserver().didPush(dialog(), null);
      expect(
        lifts,
        0,
        reason: 'a dialog triggered a lift — this is the rebuild loop '
            'that stacks un-dismissable prompts',
      );
    });

    test('a modal bottom sheet does NOT lift it', () {
      // Past chats is a bottom sheet, so this is not hypothetical.
      // ModalBottomSheetRoute is a PopupRoute, same branch.
      expect(_TestPopupRoute(), isA<PopupRoute<dynamic>>());
      ChittiScreenObserver().didPush(_TestPopupRoute(), null);
      expect(lifts, 0);
    });

    test('many dialogs in a row still lift nothing', () {
      for (var i = 0; i < 5; i++) {
        ChittiScreenObserver().didPush(dialog(), null);
      }
      expect(lifts, 0);
    });

    test('a page after a dialog still lifts exactly once', () {
      ChittiScreenObserver()
        ..didPush(dialog(), null)
        ..didPush(page(), null);
      expect(lifts, 1);
    });
  });

  group('the tracker still records where the user is', () {
    test('a pushed page does not throw without a label', () {
      // The lift guard must not have broken screen tracking, which
      // runs on the same callback.
      expect(
        () => ChittiScreenObserver().didPush(page(), null),
        returnsNormally,
      );
    });

    test('popping back does not lift either', () {
      ChittiScreenObserver().didPop(page(), page());
      expect(lifts, 0);
    });
  });
}

/// The smallest possible PopupRoute — enough to exercise the branch
/// without a live element tree.
class _TestPopupRoute extends PopupRoute<void> {
  @override
  Color? get barrierColor => null;

  @override
  bool get barrierDismissible => true;

  @override
  String? get barrierLabel => null;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      const SizedBox.shrink();

  @override
  Duration get transitionDuration => Duration.zero;
}
