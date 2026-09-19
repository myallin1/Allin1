import 'package:erode_superapp/services/dynamic_app_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('DynamicAppLayoutService layout management', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DynamicAppLayoutService.instance.resetAllSections();
    });

    test('getOrderedIds returns default IDs when no saved order exists', () async {
      const section = 'test_section';
      const defaults = ['tile1', 'tile2', 'tile3'];

      final ordered = await DynamicAppLayoutService.instance.getOrderedIds(
        sectionKey: section,
        defaultIds: defaults,
      );

      expect(ordered, equals(['tile1', 'tile2', 'tile3']));
    });

    test('saveSectionOrder persists and retrieves custom tile order', () async {
      const section = 'test_section';
      const defaults = ['tile1', 'tile2', 'tile3'];
      const custom = ['tile3', 'tile1', 'tile2'];

      var notificationCount = 0;
      DynamicAppLayoutService.instance.layoutNotifier.addListener(() {
        notificationCount++;
      });

      await DynamicAppLayoutService.instance.saveSectionOrder(
        sectionKey: section,
        orderedIds: custom,
      );

      expect(notificationCount, greaterThan(0));

      final ordered = await DynamicAppLayoutService.instance.getOrderedIds(
        sectionKey: section,
        defaultIds: defaults,
      );

      expect(ordered, equals(['tile3', 'tile1', 'tile2']));
    });

    test('new default tiles not in saved order are gracefully appended', () async {
      const section = 'test_section';
      const saved = ['tile2', 'tile1'];
      const currentDefaults = ['tile1', 'tile2', 'tile3_new', 'tile4_new'];

      await DynamicAppLayoutService.instance.saveSectionOrder(
        sectionKey: section,
        orderedIds: saved,
      );

      final ordered = await DynamicAppLayoutService.instance.getOrderedIds(
        sectionKey: section,
        defaultIds: currentDefaults,
      );

      expect(ordered, equals(['tile2', 'tile1', 'tile3_new', 'tile4_new']));
    });

    test('moveTilesToFront prioritizes given tiles while preserving remainder', () async {
      const section = 'services';
      const defaults = ['a', 'b', 'c', 'd', 'e'];

      final updated = await DynamicAppLayoutService.instance.moveTilesToFront(
        sectionKey: section,
        tileIds: ['d', 'b'],
        defaultIds: defaults,
      );

      expect(updated, equals(['d', 'b', 'a', 'c', 'e']));
    });

    test('reorderTile moves tile to target index correctly', () async {
      const section = 'dev';
      const defaults = ['tile1', 'tile2', 'tile3', 'tile4'];

      final updated = await DynamicAppLayoutService.instance.reorderTile(
        sectionKey: section,
        tileId: 'tile4',
        targetIndex: 1,
        defaultIds: defaults,
      );

      expect(updated, equals(['tile1', 'tile4', 'tile2', 'tile3']));
    });

    test('resetSectionOrder clears custom order back to defaults', () async {
      const section = 'test_section';
      const defaults = ['tile1', 'tile2', 'tile3'];

      await DynamicAppLayoutService.instance.saveSectionOrder(
        sectionKey: section,
        orderedIds: ['tile3', 'tile2', 'tile1'],
      );

      await DynamicAppLayoutService.instance.resetSectionOrder(section);

      final ordered = await DynamicAppLayoutService.instance.getOrderedIds(
        sectionKey: section,
        defaultIds: defaults,
      );

      expect(ordered, equals(['tile1', 'tile2', 'tile3']));
    });
  });
}
