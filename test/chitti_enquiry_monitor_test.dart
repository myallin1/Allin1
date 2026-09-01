// ================================================================
// chitti_enquiry_monitor_test.dart
// ================================================================
// NEW (Aug 28 2026 — Nizam: "atha namma seller and admin phone la
// monitor pannalam").
//
// ChittiEnquiryService had been WRITING leads since the market-answer
// work landed, and nothing read them. The customer was told "NJ Tech
// will confirm the exact rate shortly" — a promise the app had no way
// to keep. These pin the reachability of the screen that keeps it,
// because a monitor nobody can open is the same bug in a new place.
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/screens/admin/chitti_enquiries_screen.dart';
import 'package:erode_superapp/services/chitti/chitti_section_registry.dart';

void main() {
  group('the monitor is reachable in both apps that need it', () {
    test('admin and seller both have the section', () {
      final section = chittiSectionByKey('chitti_enquiries', 'admin');
      expect(section, isNotNull);
      expect(section!.variants, containsAll(<String>['admin', 'seller']));
    });

    test('customers do not', () {
      // The list carries other customers' names and phone numbers.
      final keys =
          chittiSectionsFor('customer').map((s) => s.key).toSet();
      expect(keys, isNot(contains('chitti_enquiries')));
    });

    test('it points at the real screen', () {
      // A section whose screenType drifted from its builder silently
      // breaks "am I already on this screen?" suppression.
      final section = chittiSectionByKey('chitti_enquiries', 'admin')!;
      expect(section.screenType, ChittiEnquiriesScreen);
    });

    test('a seller asking for enquiries finds it by name', () {
      final section = chittiSectionByKey('chitti_enquiries', 'admin')!;
      expect(section.aliases, contains('enquiries'));
      expect(section.aliases, contains('leads'));
    });
  });

  group('section registry stays internally consistent', () {
    test('no duplicate keys', () {
      final keys = kChittiSections.map((s) => s.key).toList();
      expect(keys.toSet().length, keys.length);
    });

    test('every section declares at least one variant', () {
      for (final s in kChittiSections) {
        expect(s.variants, isNotEmpty, reason: '${s.key} is unreachable.');
      }
    });
  });
}
