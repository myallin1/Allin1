// ================================================================
// admin_ai_dev_studio_test.dart — Unit & Widget Tests for AI Dev Studio
// ================================================================

import 'package:erode_superapp/screens/admin/admin_ai_dev_studio_screen.dart';
import 'package:erode_superapp/services/chitti/chitti_dev_task_service.dart';
import 'package:erode_superapp/services/chitti/chitti_section_registry.dart';
import 'package:erode_superapp/services/dynamic_app_layout_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  group('AI Dev Studio Section Registry & Navigation', () {
    test('resolves admin_ai_dev_studio section for admin variant', () {
      final section = chittiSectionByKey('admin_ai_dev_studio', 'admin');
      expect(section, isNotNull);
      expect(section!.label, contains('AI Dev Studio'));
      expect(section.screenType, AdminAiDevStudioScreen);
      expect(section.aliases, contains('claude studio'));
      expect(section.aliases, contains('gemini studio'));
      expect(section.aliases, contains('ai studio'));
    });

    test('blocks admin_ai_dev_studio section for customer and hero variants', () {
      final customerSec = chittiSectionByKey('admin_ai_dev_studio', 'customer');
      final heroSec = chittiSectionByKey('admin_ai_dev_studio', 'hero');
      final sellerSec = chittiSectionByKey('admin_ai_dev_studio', 'seller');

      expect(customerSec, isNull);
      expect(heroSec, isNull);
      expect(sellerSec, isNull);
    });
  });

  group('DynamicAppLayoutService integration with AI Dev Studio tile', () {
    test('preserves ai_dev_studio between dev_monitor and in_app_browser in development tab', () async {
      final defaultDevTiles = [
        'dev_monitor',
        'ai_dev_studio',
        'in_app_browser',
        'call_conversations',
        'call_debug_logs',
      ];

      final ordered = await DynamicAppLayoutService.instance.getOrderedIds(
        sectionKey: 'super_admin_home.development',
        defaultIds: defaultDevTiles,
      );

      expect(ordered, contains('ai_dev_studio'));
      expect(ordered, contains('in_app_browser'));
      expect(ordered.indexOf('ai_dev_studio'), equals(1));
      expect(ordered.indexOf('in_app_browser'), equals(2));
    });
  });

  group('ChittiDevEngine Tags & Configuration', () {
    test('all engine mentions follow exact GitHub workflow triggers', () {
      expect(ChittiDevEngine.claude.mention, equals('@claude'));
      expect(ChittiDevEngine.gemini.mention, equals('@gemini'));
      expect(ChittiDevEngine.antigravity.mention, equals('@agy'));
    });

    test('ChittiDevEngineTag labels and fromName lookups are accurate', () {
      expect(ChittiDevEngine.claude.label, equals('Claude'));
      expect(ChittiDevEngine.gemini.label, equals('Gemini'));
      expect(ChittiDevEngine.antigravity.label, equals('Antigravity'));

      expect(ChittiDevEngineTag.fromName('claude'), equals(ChittiDevEngine.claude));
      expect(ChittiDevEngineTag.fromName('gemini'), equals(ChittiDevEngine.gemini));
      expect(ChittiDevEngineTag.fromName('antigravity'), equals(ChittiDevEngine.antigravity));
      expect(ChittiDevEngineTag.fromName('agy'), equals(ChittiDevEngine.antigravity));
      expect(ChittiDevEngineTag.fromName(null), equals(ChittiDevEngine.claude));
    });
  });

  group('AdminAiDevStudioScreen widget construction', () {
    testWidgets('renders top engine switchers for Claude and Gemini', (tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: AdminAiDevStudioScreen(),
        ),
      );

      expect(find.text('AI Dev Studio'), findsOneWidget);
      expect(find.text('Claude Code'), findsOneWidget);
      expect(find.text('Gemini Coder'), findsOneWidget);
      expect(find.text('Antigravity'), findsOneWidget);
      expect(find.text('@claude'), findsOneWidget);
      expect(find.text('@gemini'), findsOneWidget);
      expect(find.text('@agy'), findsOneWidget);
      expect(find.text('COMPOSE AI DEV TASK'), findsOneWidget);
      expect(find.text('Plan First (AGENTS.md Safe Protocol)'), findsOneWidget);
    });
  });
}
