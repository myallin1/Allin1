// ================================================================
// chitti_tool_registry_test.dart
// ================================================================
// These tests exist for one specific bug class, not for coverage.
//
// The reason Chitti only ever acted on transport was that three lists
// had to agree — the tools offered to the model, the actions the chat
// screen would run, and the actions the overlay bubble would run — and
// they silently stopped agreeing. Nothing failed loudly; a correctly
// called tool was just dropped, and the user got a paragraph.
//
// ChittiToolRegistry collapsed those three into one. What these tests
// protect is the invariants that make that safe to rely on: that every
// tool is reachable by the router, that variant scoping actually holds,
// and that the confirmation gate covers exactly the destructive tools
// and nothing else.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/config/app_variant.dart';
import 'package:erode_superapp/services/chitti/chitti_section_registry.dart';
import 'package:erode_superapp/services/chitti/chitti_tool_registry.dart';

void main() {
  final originalVariant = currentAppVariant;
  tearDown(() => currentAppVariant = originalVariant);

  group('registry invariants', () {
    test('tool names are unique', () {
      final names = kChittiTools.map((t) => t.name).toList();
      expect(names.toSet().length, names.length);
    });

    test('section keys are unique per variant', () {
      for (final variant in ['customer', 'hero', 'seller', 'admin']) {
        final keys = chittiSectionsFor(variant).map((s) => s.key).toList();
        expect(keys.toSet().length, keys.length, reason: variant);
      }
    });

    test('every tool belongs to at least one real variant', () {
      const known = {'customer', 'hero', 'seller', 'admin'};
      for (final tool in kChittiTools) {
        expect(tool.variants, isNotEmpty, reason: tool.name);
        expect(tool.variants.difference(known), isEmpty, reason: tool.name);
      }
    });

    test('only money and cancellation tools require confirmation', () {
      // Nizam's explicit decision. If a future tool needs a gate, this
      // list is where that decision gets recorded — an accidental gate
      // on a read tool would reintroduce exactly the friction the
      // Autonomous Interaction Rule removed.
      final gated = kChittiTools
          .where((t) => t.requiresConfirmation)
          .map((t) => t.name)
          .toSet();
      expect(gated, {
        'create_service_request',
        'cancel_order',
        'system_perform_action',
        'propose_write_action',
        'send_sms',
        'create_dev_task',
      });
    });
  });

  group('variant scoping', () {
    test('a hero is never offered customer order tools', () {
      currentAppVariant = 'hero';
      final names = ChittiToolRegistry.toolSchemasFor(
        message: 'I need 1kg onions and 2 packs of milk',
      ).map((t) => (t['function']! as Map<String, dynamic>)['name']).toSet();
      expect(names, isNot(contains('create_service_request')));
      expect(names, isNot(contains('add_to_grocery_cart')));
    });

    test('a customer is never offered seller or hero tools', () {
      currentAppVariant = 'customer';
      final names = ChittiToolRegistry.toolSchemasFor(
        message: 'close the shop, I am going offline',
      ).map((t) => (t['function']! as Map<String, dynamic>)['name']).toSet();
      expect(names, isNot(contains('seller_set_shop_open')));
      expect(names, isNot(contains('hero_set_online_status')));
    });

    test('isAllowedFor enforces the same rule the schema builder does', () {
      currentAppVariant = 'hero';
      expect(ChittiToolRegistry.isAllowedFor('create_service_request'), isFalse);
      expect(ChittiToolRegistry.isAllowedFor('hero_today_earnings'), isTrue);

      currentAppVariant = 'customer';
      expect(ChittiToolRegistry.isAllowedFor('create_service_request'), isTrue);
      expect(ChittiToolRegistry.isAllowedFor('hero_today_earnings'), isFalse);
    });

    test('an unknown tool name is never allowed', () {
      expect(ChittiToolRegistry.isKnownAction('delete_everything'), isFalse);
      expect(ChittiToolRegistry.isAllowedFor('delete_everything'), isFalse);
    });
  });

  group('domain router', () {
    // The router failing OPEN (too many tools) costs tokens. Failing
    // CLOSED (tool absent) makes the feature invisible to the model,
    // which is the bug this whole change fixes — so these assert
    // reachability, not minimality.
    Set<String> toolsFor(String message, String variant) {
      currentAppVariant = variant;
      return ChittiToolRegistry.toolSchemasFor(message: message)
          .map((t) => (t['function']! as Map<String, dynamic>)['name']! as String)
          .toSet();
    }

    test('an order request reaches create_service_request', () {
      expect(
        toolsFor('order 2 plate chicken biryani from Sagar', 'customer'),
        contains('create_service_request'),
      );
    });

    test('a ride request reaches book_transport', () {
      expect(
        toolsFor('book an auto to the railway station', 'customer'),
        contains('book_transport'),
      );
    });

    test('a broken-app complaint reaches report_app_bug', () {
      expect(
        toolsFor('the booking screen is blank, nothing is working', 'customer'),
        contains('report_app_bug'),
      );
    });

    test('a balance question reaches the wallet read', () {
      expect(
        toolsFor('how much balance do I have', 'customer'),
        contains('check_wallet_balance'),
      );
    });

    test('a hero earnings question reaches the hero read', () {
      expect(
        toolsFor('how much have I earned today', 'hero'),
        contains('hero_today_earnings'),
      );
    });

    test('a seller closing up reaches the shop toggle', () {
      expect(
        toolsFor('I am closing the shop now', 'seller'),
        contains('seller_set_shop_open'),
      );
    });

    test('vague input still gets the variant core bundle', () {
      final tools = toolsFor('hmm', 'customer');
      expect(tools, contains('navigate_to_section'));
      expect(tools, isNotEmpty);
    });

    test('the vision tool is offered only when an image is attached', () {
      currentAppVariant = 'customer';
      final without = ChittiToolRegistry.toolSchemasFor(
        message: 'what is this?',
      ).map((t) => (t['function']! as Map<String, dynamic>)['name']).toSet();
      expect(without, isNot(contains('analyze_screen_with_vision')));

      final with_ = ChittiToolRegistry.toolSchemasFor(
        message: 'what is this?',
        hasAttachedImage: true,
      ).map((t) => (t['function']! as Map<String, dynamic>)['name']).toSet();
      expect(with_, contains('analyze_screen_with_vision'));
    });

    test('routing keeps the tool list smaller than the full variant set', () {
      // The whole point of the router: adding ~30 tools must not mean
      // sending ~30 tools. If this ever fails, the token budget Nizam
      // was worried about has quietly regressed.
      currentAppVariant = 'customer';
      final routed = ChittiToolRegistry.toolSchemasFor(
        message: 'book an auto to the bus stand',
      ).length;
      final allCustomerTools =
          kChittiTools.where((t) => t.variants.contains('customer')).length;
      expect(routed, lessThan(allCustomerTools));
    });
  });

  group('section registry', () {
    test('covers far more than the twelve sections it replaced', () {
      expect(chittiSectionsFor('customer').length, greaterThan(12));
    });

    test('lookup is variant-scoped', () {
      expect(chittiSectionByKey('grocery', 'customer'), isNotNull);
      expect(chittiSectionByKey('grocery', 'hero'), isNull);
      expect(chittiSectionByKey('hero_earnings', 'hero'), isNotNull);
      expect(chittiSectionByKey('hero_earnings', 'customer'), isNull);
    });

    test('an unknown key resolves to null rather than a default screen', () {
      expect(chittiSectionByKey('not_a_section', 'customer'), isNull);
      expect(chittiSectionByKey(null, 'customer'), isNull);
    });
  });
}
