import 'package:erode_superapp/services/dynamic_app_layout_service.dart';
import 'package:erode_superapp/widgets/admin/admin_reorderable_tile_list.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    DynamicAppLayoutService.instance.clearMemoryCacheForTesting();
  });

  Widget harness(List<AdminHomeTile> tiles, {String sectionKey = 'test.section'}) {
    return MaterialApp(
      home: Scaffold(
        body: AdminReorderableTileList(
          sectionKey: sectionKey,
          tiles: tiles,
        ),
      ),
    );
  }

  List<AdminHomeTile> threeTiles() => const [
        AdminHomeTile(id: 'a', child: Text('Tile A')),
        AdminHomeTile(id: 'b', child: Text('Tile B')),
        AdminHomeTile(id: 'c', child: Text('Tile C')),
      ];

  testWidgets("renders every tile in the screen's own order with nothing saved",
      (tester) async {
    await tester.pumpWidget(harness(threeTiles()));
    await tester.pumpAndSettle();

    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(order, ['Tile A', 'Tile B', 'Tile C']);
  });

  testWidgets('a saved order is restored on next load', (tester) async {
    SharedPreferences.setMockInitialValues({
      'admin_home_tile_order::test.section': '["c","a","b"]',
    });
    DynamicAppLayoutService.instance.clearMemoryCacheForTesting();

    await tester.pumpWidget(harness(threeTiles()));
    await tester.pumpAndSettle();

    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(order, ['Tile C', 'Tile A', 'Tile B']);
  });

  testWidgets('a new tile not in the saved order appends at the end',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'admin_home_tile_order::test.section': '["b","a"]',
    });
    DynamicAppLayoutService.instance.clearMemoryCacheForTesting();

    final tiles = [
      ...threeTiles(),
      const AdminHomeTile(id: 'd', child: Text('Tile D')),
    ];
    await tester.pumpWidget(harness(tiles));
    await tester.pumpAndSettle();

    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    // b and a per the saved order, then c and d (never saved) in the
    // screen's own original order — this is the "future tiles just
    // work" property.
    expect(order, ['Tile B', 'Tile A', 'Tile C', 'Tile D']);
  });

  testWidgets('dragging a tile persists the new order for next time',
      (tester) async {
    await tester.pumpWidget(harness(threeTiles()));
    await tester.pumpAndSettle();

    // Long-press Tile A, drag it below Tile C, release.
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Tile A')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.moveTo(tester.getCenter(find.text('Tile C')) + const Offset(0, 40));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();

    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('app_layout_order::test.section') ??
        prefs.getString('admin_home_tile_order::test.section');
    expect(saved, isNotNull);
    // Tile A should no longer be first.
    expect(saved!.startsWith('["a"'), isFalse);
  });

  testWidgets('a different section key uses its own independent order',
      (tester) async {
    SharedPreferences.setMockInitialValues({
      'admin_home_tile_order::section.one': '["c","a","b"]',
    });
    DynamicAppLayoutService.instance.clearMemoryCacheForTesting();

    await tester.pumpWidget(harness(threeTiles(), sectionKey: 'section.two'));
    await tester.pumpAndSettle();

    final order = tester
        .widgetList<Text>(find.byType(Text))
        .map((t) => t.data)
        .toList();
    expect(order, ['Tile A', 'Tile B', 'Tile C']);
  });
}
