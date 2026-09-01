// ================================================================
// chitti_variant_parity_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: "admin, seller, hero app la iruka
// chittikum intha customer app mari power kudu").
//
// The failure these pin is not a crash. Before this, the admin build
// had three tools — navigate, report a bug, check for an update — so
// Chitti could open the approvals screen and then had nothing to say
// about what was on it, while its own persona promised exact figures.
// That is invisible to a compiler and invisible to a smoke test; it
// only shows up as an owner asking "how many are waiting?" and being
// told nothing. So the parity itself is the assertion.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_tool_registry.dart';

void main() {
  group('every variant has real reads, not just plumbing', () {
    // Tools that exist in every build and answer nothing about the
    // business: opening a screen, filing a bug, checking for updates,
    // switching language. A build with ONLY these is the bug.
    const plumbing = <String>{
      'navigate_to_section',
      'report_app_bug',
      'check_and_update_app',
      'set_app_language',
    };

    for (final variant in ['customer', 'hero', 'seller', 'admin']) {
      test('$variant can answer questions about its own work', () {
        final tools = kChittiTools
            .where((t) => t.variants.contains(variant))
            .map((t) => t.name)
            .toSet();
        final substantive = tools.difference(plumbing);

        expect(
          substantive,
          isNotEmpty,
          reason: '$variant has only plumbing tools — Chitti can open '
              'screens there but cannot say anything about them.',
        );
      });
    }

    test('admin can read every queue an owner actually asks about', () {
      final admin = kChittiTools
          .where((t) => t.variants.contains('admin'))
          .map((t) => t.name)
          .toSet();
      expect(
        admin,
        containsAll(<String>[
          'admin_pending_approvals',
          'admin_today_activity',
          'admin_open_bugs',
          'admin_open_enquiries',
        ]),
      );
    });

    test('sellers see the enquiries addressed to them', () {
      // Nizam's rule: a price enquiry is monitored on "seller and admin
      // phone", not admin alone. A seller who cannot see the lead
      // cannot answer it.
      final tool = kChittiTools.firstWhere(
        (t) => t.name == 'admin_open_enquiries',
      );
      expect(tool.variants, containsAll(<String>['admin', 'seller']));
    });
  });

  group('routing reaches the new tools', () {
    test('an owner asking about approvals gets the admin domain', () {
      expect(
        ChittiToolRegistry.routeDomains(
          'how many heroes are waiting for approval',
          variant: 'admin',
        ),
        contains(ChittiDomain.admin),
      );
    });

    test('an admin with no clear question still gets oversight tools', () {
      // The empty/unmatched case falls back to the variant's core
      // bundle. If admin's core were still navigation+support only, the
      // new reads would be unreachable for every vague question — the
      // most common kind.
      expect(
        ChittiToolRegistry.routeDomains('', variant: 'admin'),
        contains(ChittiDomain.admin),
      );
    });

    test('a hero asking what is left reaches the hero domain', () {
      expect(
        ChittiToolRegistry.routeDomains(
          'enna vela bakki iruku',
          variant: 'hero',
        ),
        contains(ChittiDomain.hero),
      );
    });
  });

  group('the new tools are wired, not merely declared', () {
    // A tool the registry offers but the executor cannot run is worse
    // than a missing tool: the model picks it and the turn dead-ends.
    test('every declared tool is a known action', () {
      for (final tool in kChittiTools) {
        expect(
          ChittiToolRegistry.isKnownAction(tool.name),
          isTrue,
          reason: '${tool.name} is offered to the model but unhandled.',
        );
      }
    });

    test('none of the new oversight tools can write', () {
      // Reads only, by design — a wrong call yields a wrong answer,
      // never a wrong action, so none of them needs a confirm gate.
      for (final name in <String>[
        'admin_pending_approvals',
        'admin_today_activity',
        'admin_open_bugs',
        'admin_open_enquiries',
        'hero_pending_work',
        'seller_shop_status',
      ]) {
        expect(
          ChittiToolRegistry.requiresConfirmation(name),
          isFalse,
          reason: '$name is a read; gating it would add a pointless '
              'confirmation to every question.',
        );
      }
    });

    test('admin tools are not offered to customers', () {
      for (final name in <String>[
        'admin_pending_approvals',
        'admin_today_activity',
        'admin_open_bugs',
      ]) {
        expect(
          ChittiToolRegistry.isAllowedFor(name, 'customer'),
          isFalse,
          reason: '$name would leak platform-wide figures to a customer.',
        );
      }
    });
  });
}
