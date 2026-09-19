import 'package:erode_superapp/services/chitti/chitti_local_intent_engine.dart';
import 'package:erode_superapp/services/chitti/chitti_tool_registry.dart';
import 'package:erode_superapp/services/dynamic_app_layout_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Chitti layout orchestration tool & intents', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await DynamicAppLayoutService.instance.resetAllSections();
    });

    test('rearrange_admin_layout tool is properly registered in admin domain', () {
      expect(ChittiToolRegistry.isKnownAction('rearrange_admin_layout'), isTrue);
      expect(ChittiToolRegistry.isAllowedFor('rearrange_admin_layout', 'admin'), isTrue);
      expect(ChittiToolRegistry.isAllowedFor('rearrange_admin_layout', 'customer'), isFalse);
      expect(ChittiToolRegistry.requiresConfirmation('rearrange_admin_layout'), isTrue);

      final tool = ChittiToolRegistry.byName('rearrange_admin_layout');
      expect(tool, isNotNull);
      expect(tool!.domain, equals(ChittiDomain.admin));
      expect(tool.parameters, isNotNull);
    });

    test('local intent engine recognizes reset layout command', () {
      final intent = ChittiLocalIntentEngine.resolve(
        'reset admin home',
        variant: 'admin',
      );

      expect(intent, isNotNull);
      expect(intent!.action, equals('rearrange_admin_layout'));
      expect(intent.args['action_type'], equals('reset'));
      expect(intent.confidence, greaterThanOrEqualTo(0.8));
    });

    test('local intent engine recognizes approvals move to top command', () {
      final intent = ChittiLocalIntentEngine.resolve(
        'approvals mela kondu va',
        variant: 'admin',
      );

      expect(intent, isNotNull);
      expect(intent!.action, equals('rearrange_admin_layout'));
      expect(intent.args['action_type'], equals('move_to_top'));
      expect(intent.args['priority_tiles'], contains('hero_approvals'));
      expect(intent.confidence, greaterThanOrEqualTo(0.8));
    });

    test('local intent engine recognizes dev tools move to top command', () {
      final intent = ChittiLocalIntentEngine.resolve(
        'dev tools mela kondu va',
        variant: 'admin',
      );

      expect(intent, isNotNull);
      expect(intent!.action, equals('rearrange_admin_layout'));
      expect(intent.args['action_type'], equals('move_to_top'));
      expect(intent.args['section_key'], equals('super_admin_home.dev'));
      expect(intent.confidence, greaterThanOrEqualTo(0.8));
    });
  });
}
