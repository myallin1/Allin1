// ================================================================
// chitti_order_escalation_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: "admin mobile attend pannalainalum...
// orders ah hero ku assign panni customer ku message anupuravaraikkum").
//
// The transaction itself needs Firestore, so what is pinned here is
// the decision logic around it — the part that decides WHETHER an
// order is fair game. Both directions are dangerous:
//   • too eager, and an order is yanked away from an admin who is
//     mid-decision, or a malformed document is released the instant a
//     hero opens the app;
//   • too shy, and the customer this feature exists for is never
//     served.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/services/chitti/chitti_order_escalation_service.dart';

void main() {
  final now = DateTime(2026, 8, 28, 20, 0);

  StrandedOrder order({DateTime? at}) => StrandedOrder(
        id: 'r1',
        requestType: 'food',
        customerName: 'Kumar',
        createdAt: at,
      );

  group('what counts as stranded', () {
    test('a fresh order is left alone', () {
      // An admin actively looking at their queue must not have an order
      // pulled out from under them.
      expect(
        order(at: now.subtract(const Duration(minutes: 1))).isStrandedAt(now),
        isFalse,
      );
    });

    test('an order just inside the grace period is still left alone', () {
      expect(
        order(at: now.subtract(const Duration(minutes: 9, seconds: 59)))
            .isStrandedAt(now),
        isFalse,
      );
    });

    test('an order exactly at the grace period is fair game', () {
      // Boundary pinned explicitly: an off-by-one here is the
      // difference between a safety net and a race with the admin.
      expect(
        order(at: now.subtract(ChittiOrderEscalationService.graceperiod))
            .isStrandedAt(now),
        isTrue,
      );
    });

    test('a long-forgotten order is definitely fair game', () {
      expect(
        order(at: now.subtract(const Duration(hours: 3))).isStrandedAt(now),
        isTrue,
      );
    });

    test('an order with NO timestamp is never released', () {
      // Missing data is not evidence of age. Treating null as "old"
      // would release every malformed document the moment any hero
      // opened the app — the worst possible failure mode, because it
      // would look like the feature working.
      expect(order().isStrandedAt(now), isFalse);
    });
  });

  group('the grace period is a deliberate compromise', () {
    test('long enough that an admin can finish a decision', () {
      expect(
        ChittiOrderEscalationService.graceperiod.inMinutes,
        greaterThanOrEqualTo(5),
      );
    });

    test('short enough that a hungry customer has not given up', () {
      expect(
        ChittiOrderEscalationService.graceperiod.inMinutes,
        lessThanOrEqualTo(20),
      );
    });
  });

  group('the wait label tells a hero what they are looking at', () {
    test('minutes while it is minutes', () {
      expect(
        order(at: now.subtract(const Duration(minutes: 12)))
            .waitedLabel(now: now),
        '12m waiting',
      );
    });

    test('hours once it is hours', () {
      expect(
        order(at: now.subtract(const Duration(hours: 2)))
            .waitedLabel(now: now),
        '2h waiting',
      );
    });

    test('nothing at all when the age is unknown', () {
      expect(order().waitedLabel(now: now), '');
    });
  });

  group('the customer is actually told', () {
    // "customer ku message anupuravaraikkum" — the dispatch is only
    // half the brief. A silently rerouted order still looks to the
    // customer like nothing happened.
    test('there is a message and it is reassuring', () {
      final m = ChittiOrderEscalationService.customerMessage;
      expect(m.trim(), isNotEmpty);
      expect(m.toLowerCase(), contains('hero'));
    });

    test('it never tells the customer nobody was watching', () {
      // How NJ Tech is staffed is not the customer's problem, and
      // "your order was missed" destroys confidence at the exact
      // moment we are trying to rebuild it.
      final m = ChittiOrderEscalationService.customerMessage.toLowerCase();
      for (final leak in ['admin', 'missed', 'delay', 'sorry', 'unattended']) {
        expect(m, isNot(contains(leak)), reason: leak);
      }
    });
  });

  group('the statuses match the rest of the pipeline', () {
    test('it watches the status admin screens actually use', () {
      // admin_new_orders_screen.dart filters on exactly this string.
      expect(
        ChittiOrderEscalationService.pendingAdminStatus,
        'admin_review',
      );
    });

    test('it releases into the normal broadcast status', () {
      // Anything else and the tested hero-side accept flow would not
      // recognise the order.
      expect(ChittiOrderEscalationService.releasedStatus, 'pending');
    });
  });
}
