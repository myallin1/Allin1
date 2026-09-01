// ================================================================
// qa_five_screens_test.dart — Synthetic QA Test-Bot, Phase 1
// ================================================================
// NEW (CTO mandate — Synthetic QA Test-Bot). Drives the REAL customer
// app (pumps the actual `CustomerApp` root widget from
// lib/main_customer.dart, not a stub/reimplementation) through the 5
// core screens named in QA_AGENT_BLUEPRINT.md — Dashboard, Bike
// Booking, Grocery, Food, Profile — and writes what it finds to the
// `ux_audit_reports` Firestore collection, which only
// AdminUxAuditScreen (Admin app's hamburger drawer → "UX Audit
// Reports") reads. Never touches a real customer session — see the
// prerequisite note in §PREREQUISITES below.
//
// SCOPE (Phase 1, per the approved blueprint — do not silently expand
// this without going back to the CTO):
//   - Navigation reachability + key-widget-presence checks only.
//   - Bike Booking: opens the screen, selects a vehicle category chip.
//     Does NOT attempt a real fare quote or booking (needs location
//     mocking — that's explicitly Phase 2 in the blueprint).
//   - Grocery: types into the list field, confirms the Send Order
//     button's enabled state responds correctly. Does NOT tap Send
//     Order — that would create a real service_request document.
//   - No Groq vision analysis of screenshots yet — that's Phase 1.5 in
//     the blueprint. This file only does widget-tree assertions and
//     Firestore reporting.
//
// PREREQUISITES (see QA_AGENT_BLUEPRINT.md §8 — these are Nizam's
// setup steps, not something this test file can do for itself):
//   1. A dedicated `qa_bot@…` Firebase Auth account must already have
//      a persisted session on whatever device/emulator runs this test
//      (Google/OTP sign-in can't be scripted headlessly here — this
//      test assumes it's already signed in, same as a returning user).
//   2. Firestore rules must allow that account read access to the 5
//      screens' own already-public data and write access to
//      `ux_audit_reports` ONLY — written by Nizam, never auto-edited
//      by this AI (standing rule for `firestore.rules` in this repo).
//   3. `flutter pub get` after this session's pubspec change
//      (`integration_test` added to dev_dependencies).
//
// HOW TO RUN (locally, once the above is done):
//   flutter test integration_test/qa_five_screens_test.dart
//
// CAVEAT — screenshot capture is the one piece of this file most
// likely to need local platform-specific adjustment.
// `IntegrationTestWidgetsFlutterBinding.takeScreenshot()`'s exact
// return shape and availability differs by platform/runner
// (`flutter test` vs `flutter drive`); it's wrapped in try/catch below
// so a capture failure never blocks the actual widget assertions or
// the Firestore report — verify this specific part on your target
// device before relying on `screenshotUrl` showing up in reports.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:erode_superapp/main_customer.dart' show CustomerApp;
import 'package:erode_superapp/services/cloudinary_upload_service.dart';
import 'package:erode_superapp/services/guru_admin_api_service.dart';
import 'package:erode_superapp/services/qa_vision_service.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:integration_test/integration_test.dart';

import '../lib/firebase_options.dart';

void main() {
  final binding = IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  // One shared runId groups every finding from this execution together
  // in AdminUxAuditScreen, so the CTO can tell "today's run" apart from
  // yesterday's without cross-referencing timestamps manually.
  final runId = DateTime.now().toIso8601String();

  // Resolved once in setUpAll and reused for every screenshot's vision
  // check — same Groq key the Admin AI Co-Pilot already uses
  // (guru_admin_api_service.dart's resolveApiKey(), env var first, then
  // SharedPreferences fallback). Left empty only degrades the vision
  // step (QaVisionService.analyzeScreenshot short-circuits to null),
  // never breaks the widget-tree assertions or the Firestore report.
  var qaVisionApiKey = '';

  setUpAll(() async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
    }
    await Hive.initFlutter();
    try {
      qaVisionApiKey = await GuruAdminApiService().resolveApiKey();
    } catch (e) {
      debugPrint('[QA bot] could not resolve Groq API key for vision checks: $e');
    }
  });

  // NEW: the ONLY write this whole test file performs, besides
  // whatever the real app itself writes as a side effect of normal
  // navigation (e.g. analytics). Mirrors the exact schema in
  // QA_AGENT_BLUEPRINT.md §5.
  Future<void> report({
    required String screen,
    required String step,
    required bool ok,
    String? findingText,
    Uint8List? screenshotBytes,
  }) async {
    String? screenshotUrl;
    if (screenshotBytes != null) {
      try {
        screenshotUrl = await CloudinaryUploadService().uploadImageBytes(
          screenshotBytes,
          fileName: '${screen}_${step}_$runId.png',
          folder: 'ux_audit_reports',
          targetBytes: 300 * 1024,
        );
      } catch (e) {
        debugPrint('[QA bot] screenshot upload failed for $screen/$step: $e');
      }
    }

    // NEW (Phase 1.5) — vision-analyze the screenshot regardless of
    // whether the widget-tree assertion already passed: a screen can
    // be structurally present (the Key was found) while still looking
    // visually broken (overlap, cut-off text, a blank area), and that
    // is exactly the class of bug widget-tree checks can't see.
    var combinedOk = ok;
    var combinedFinding = findingText;
    if (screenshotBytes != null) {
      final visionFinding = await QaVisionService.analyzeScreenshot(
        apiKey: qaVisionApiKey,
        screenshotBytes: screenshotBytes,
        screenName: '$screen / $step',
      );
      if (visionFinding != null) {
        combinedOk = false;
        combinedFinding = combinedFinding == null || combinedFinding.isEmpty
            ? visionFinding
            : '$combinedFinding | $visionFinding';
      }
    }

    try {
      await FirebaseFirestore.instance.collection('ux_audit_reports').add(<String, dynamic>{
        'runId': runId,
        'screen': screen,
        'step': step,
        'status': combinedOk ? 'ok' : 'finding',
        if (!combinedOk && combinedFinding != null) 'findingText': combinedFinding,
        if (screenshotUrl != null) 'screenshotUrl': screenshotUrl,
        'timestamp': FieldValue.serverTimestamp(),
      });
    } catch (e) {
      debugPrint('[QA bot] Firestore report write failed for $screen/$step: $e');
    }
  }

  Future<Uint8List?> tryScreenshot(String name) async {
    try {
      final list = await binding.takeScreenshot(name);
      return Uint8List.fromList(list);
    } catch (e) {
      debugPrint('[QA bot] screenshot capture failed for $name: $e');
      return null;
    }
  }

  group('Synthetic QA Test-Bot — 5 core screens', () {
    testWidgets('Dashboard: service tiles present and tappable', (tester) async {
      await tester.pumpWidget(const CustomerApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final bikeTile = find.byKey(const Key('dashboard_tile_bike'));
      final groceryTile = find.byKey(const Key('dashboard_tile_grocery'));
      final foodTile = find.byKey(const Key('dashboard_tile_food'));

      final allPresent = bikeTile.evaluate().isNotEmpty &&
          groceryTile.evaluate().isNotEmpty &&
          foodTile.evaluate().isNotEmpty;

      await report(
        screen: 'dashboard',
        step: 'tiles_present',
        ok: allPresent,
        findingText: allPresent
            ? null
            : 'One or more dashboard tiles (bike/grocery/food) were not found — '
                'either the QA account never reached the Dashboard (still on '
                'login/welcome/intro), or a tile was removed/renamed without '
                'updating its Key.',
        screenshotBytes: await tryScreenshot('dashboard'),
      );

      expect(allPresent, isTrue,
          reason: 'See ux_audit_reports/dashboard/tiles_present for details if this fails.');
    });

    testWidgets('Bike Booking: opens and vehicle category is selectable', (tester) async {
      await tester.pumpWidget(const CustomerApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final bikeTile = find.byKey(const Key('dashboard_tile_bike'));
      if (bikeTile.evaluate().isEmpty) {
        await report(
          screen: 'bike_booking',
          step: 'navigate_from_dashboard',
          ok: false,
          findingText: 'dashboard_tile_bike not found — cannot reach Bike Booking from Dashboard.',
        );
        return;
      }
      await tester.tap(bikeTile);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final bikeChip = find.byKey(const Key('bike_booking_category_chip_bike'));
      final opened = bikeChip.evaluate().isNotEmpty;
      await report(
        screen: 'bike_booking',
        step: 'category_chip_present',
        ok: opened,
        findingText: opened
            ? null
            : 'Bike Booking screen opened but the "bike" category chip was not '
                'found — form layout may have changed.',
        screenshotBytes: await tryScreenshot('bike_booking'),
      );
      if (opened) {
        // Selection only — never proceeds to a fare quote or Confirm/Book,
        // per Phase 1 scope.
        await tester.tap(bikeChip);
        await tester.pumpAndSettle();
      }
      expect(opened, isTrue);
    });

    testWidgets('Grocery: list field + Send Order button respond correctly', (tester) async {
      await tester.pumpWidget(const CustomerApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final groceryTile = find.byKey(const Key('dashboard_tile_grocery'));
      if (groceryTile.evaluate().isEmpty) {
        await report(
          screen: 'grocery',
          step: 'navigate_from_dashboard',
          ok: false,
          findingText: 'dashboard_tile_grocery not found — cannot reach Grocery from Dashboard.',
        );
        return;
      }
      await tester.tap(groceryTile);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final listField = find.byKey(const Key('grocery_list_field'));
      final sendButton = find.byKey(const Key('grocery_send_order_button'));
      final fieldsPresent = listField.evaluate().isNotEmpty && sendButton.evaluate().isNotEmpty;

      if (!fieldsPresent) {
        await report(
          screen: 'grocery',
          step: 'form_fields_present',
          ok: false,
          findingText: 'Grocery list field or Send Order button not found.',
          screenshotBytes: await tryScreenshot('grocery'),
        );
        expect(fieldsPresent, isTrue);
        return;
      }

      // Type into the list field — mirrors what GroceryAiNotesService's
      // consumeAll() already does non-interactively; this confirms the
      // human-typing path still works too.
      await tester.enterText(listField, 'QA bot test item — safe to ignore');
      await tester.pumpAndSettle();

      final buttonWidget = tester.widget<ElevatedButton>(sendButton);
      final enabledAfterTyping = buttonWidget.onPressed != null;

      await report(
        screen: 'grocery',
        step: 'send_button_enables_on_text',
        ok: enabledAfterTyping,
        findingText: enabledAfterTyping
            ? null
            : 'Send Order button did not enable after typing into the list field — '
                '_canSubmit logic may be broken.',
        screenshotBytes: await tryScreenshot('grocery_filled'),
      );
      // Deliberately never taps Send Order — that would create a real
      // service_request document under the QA account, out of Phase 1
      // scope (this test only verifies the button's enabled STATE).
      expect(enabledAfterTyping, isTrue);
    });

    testWidgets('Food: hub screen opens and shop grid renders', (tester) async {
      await tester.pumpWidget(const CustomerApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final foodTile = find.byKey(const Key('dashboard_tile_food'));
      if (foodTile.evaluate().isEmpty) {
        await report(
          screen: 'food',
          step: 'navigate_from_dashboard',
          ok: false,
          findingText: 'dashboard_tile_food not found — cannot reach Food from Dashboard.',
        );
        return;
      }
      await tester.tap(foodTile);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final customOrderTile = find.byKey(const Key('food_hub_custom_order_tile'));
      final shopGrid = find.byKey(const Key('food_hub_partner_shops_grid'));
      final ok = customOrderTile.evaluate().isNotEmpty && shopGrid.evaluate().isNotEmpty;

      await report(
        screen: 'food',
        step: 'hub_renders',
        ok: ok,
        findingText: ok ? null : 'Food Hub opened but the custom-order tile or shop grid was missing.',
        screenshotBytes: await tryScreenshot('food_hub'),
      );
      expect(ok, isTrue);
    });

    testWidgets('Profile: screen opens without crashing for the QA account', (tester) async {
      await tester.pumpWidget(const CustomerApp());
      await tester.pumpAndSettle(const Duration(seconds: 5));

      // Reached via the drawer (see dashboard_screen.dart's
      // `_drawerItem(..., itemKey: const Key('drawer_item_profile'))`),
      // not a dashboard tile — the drawer itself needs opening first.
      final scaffoldFinder = find.byType(Scaffold).first;
      await tester.dragFrom(
        tester.getTopLeft(scaffoldFinder) + const Offset(10, 100),
        const Offset(250, 0),
      );
      await tester.pumpAndSettle();

      final profileItem = find.byKey(const Key('drawer_item_profile'));
      if (profileItem.evaluate().isEmpty) {
        await report(
          screen: 'profile',
          step: 'open_drawer',
          ok: false,
          findingText: 'drawer_item_profile not found after attempting to open the drawer — '
              'the drag-open gesture may not have worked on this platform, or the '
              'drawer item was moved.',
          screenshotBytes: await tryScreenshot('profile_drawer_attempt'),
        );
        return;
      }
      await tester.tap(profileItem);
      await tester.pumpAndSettle(const Duration(seconds: 5));

      final profileScaffold = find.byKey(const Key('profile_screen_scaffold'));
      final ok = profileScaffold.evaluate().isNotEmpty;
      await report(
        screen: 'profile',
        step: 'screen_opens',
        ok: ok,
        findingText: ok ? null : 'Profile screen did not open, or crashed before rendering its Scaffold.',
        screenshotBytes: await tryScreenshot('profile'),
      );
      expect(ok, isTrue);
    });
  });
}
