// ================================================================
// chitti_buddy_advisor_test.dart
// ================================================================
// The CEO's ask has two halves that pull against each other: Chitti
// should feel like a friend, AND it reads out order confirmations,
// wallet balances and SOS状态. So most of what matters here is the
// GATE — that the personality switches off on a bad moment — and that
// the "knowledgeable question" is built from what is actually on the
// screen rather than a canned line.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/config/app_variant.dart';
import 'package:erode_superapp/services/chitti/chitti_buddy.dart';
import 'package:erode_superapp/services/chitti/chitti_screen_advisor.dart';
import 'package:erode_superapp/services/chitti/chitti_screen_reader.dart';

ChittiScreenSnapshot _snap({
  String? title,
  List<ChittiScreenElement> fields = const <ChittiScreenElement>[],
  List<String> buttons = const <String>[],
}) {
  return ChittiScreenSnapshot(
    headings: title == null
        ? const <ChittiScreenElement>[]
        : <ChittiScreenElement>[
            ChittiScreenElement(label: title, kind: ChittiElementKind.heading),
          ],
    buttons: buttons
        .map((b) => ChittiScreenElement(label: b, kind: ChittiElementKind.button))
        .toList(),
    fields: fields,
    texts: const <ChittiScreenElement>[],
  );
}

void main() {
  final original = currentAppVariant;
  setUp(() {
    currentAppVariant = 'customer';
    ChittiBuddy.resetForTesting();
  });
  tearDown(() => currentAppVariant = original);

  group('the personality gate', () {
    test('stays silent on money, SOS, cancellations and failures', () {
      for (final serious in [
        'Your wallet balance is 240 rupees.',
        "I've opened SOS for you.",
        'Cancelled — that order will not be sent to any Hero.',
        "I couldn't place that order just now.",
        'Your KYC is still pending.',
      ]) {
        expect(
          ChittiBuddy.quipAfterAction(
            languageCode: 'en',
            saying: serious,
            always: true,
          ),
          isNull,
          reason: serious,
        );
      }
    });

    test('is silent when the CUSTOMER raised something serious', () {
      // Chitti's own line can look harmless while the conversation is
      // not — "Opening it now" next to "my payment failed" is wrong.
      expect(
        ChittiBuddy.quipAfterAction(
          languageCode: 'en',
          saying: 'Opening it now.',
          userSaid: 'my payment failed',
          always: true,
        ),
        isNull,
      );
    });

    test('speaks up on an ordinary action', () {
      expect(
        ChittiBuddy.quipAfterAction(
          languageCode: 'en',
          saying: 'Opening Game Zone for you now.',
          always: true,
        ),
        isNotNull,
      );
    });

    test('never repeats the same line twice running', () {
      final first = ChittiBuddy.quipAfterAction(
        languageCode: 'en',
        saying: 'Opening it.',
        always: true,
      );
      final second = ChittiBuddy.quipAfterAction(
        languageCode: 'en',
        saying: 'Opening it.',
        always: true,
      );
      expect(first, isNotNull);
      expect(second, isNot(first));
    });

    test('speaks the right language', () {
      final ta = ChittiBuddy.quipAfterAction(
        languageCode: 'ta',
        saying: 'Opening it.',
        always: true,
      );
      expect(ta, isNotNull);
      expect(RegExp('[஀-௿]').hasMatch(ta!), isTrue);
    });
  });

  group('daily quote', () {
    test('returns a line for each supported language', () {
      for (final code in ['en', 'ta', 'hi', 'ml']) {
        expect(ChittiBuddy.dailyQuote(code), isNotNull, reason: code);
      }
    });

    test('each role gets its own pool, not the customer one', () {
      // CHANGED (Aug 28 2026): the flag used to be a bool — hero, or
      // everyone else — so sellers and admins silently read the
      // customer pool. Four pools now, selected by variant.
      final customer = ChittiBuddy.dailyQuote('en', variant: 'customer');
      final hero = ChittiBuddy.dailyQuote('en', variant: 'hero');
      final seller = ChittiBuddy.dailyQuote('en', variant: 'seller');
      final admin = ChittiBuddy.dailyQuote('en', variant: 'admin');
      for (final q in [customer, hero, seller, admin]) {
        expect(q, isNotNull);
      }
      // All four distinct is the actual assertion: sharing a pool is
      // the bug, and it is invisible unless compared.
      expect({customer, hero, seller, admin}.length, 4);
    });
  });

  group('the knowledgeable question', () {
    test('names the blank field instead of describing the page', () {
      final a = ChittiScreenAdvisor.adviseFrom(_snap(
        title: 'Bike Taxi',
        fields: const [
          ChittiScreenElement(
            label: 'Drop location',
            kind: ChittiElementKind.field,
          ),
        ],
        buttons: const ['Confirm Booking'],
      ));
      expect(a, isNotNull);
      expect(a!.text, contains('Drop location'));
      expect(a.suggestions, contains('Confirm Booking'));
    });

    test('ignores a blank search box — not every empty field matters', () {
      final a = ChittiScreenAdvisor.adviseFrom(_snap(
        title: 'Food Genie',
        fields: const [
          ChittiScreenElement(label: 'Search', kind: ChittiElementKind.field),
        ],
        buttons: const ['View Cart'],
      ));
      expect(a!.text, isNot(contains('Search')));
      expect(a.suggestions, contains('View Cart'));
    });

    test('offers the screen own buttons — this is what needs no teaching', () {
      // A screen nobody has ever registered still produces real chips.
      final a = ChittiScreenAdvisor.adviseFrom(_snap(
        title: 'Brand New Feature',
        buttons: const ['Start Trial', 'See Plans'],
      ));
      expect(a, isNotNull);
      expect(a!.suggestions, containsAll(<String>['Start Trial', 'See Plans']));
    });

    test('drops navigation chrome from the chips', () {
      final a = ChittiScreenAdvisor.adviseFrom(_snap(
        title: 'Some Page',
        buttons: const ['Back', 'OK', 'Redeem Coins'],
      ));
      expect(a!.suggestions, <String>['Redeem Coins']);
    });

    test('says nothing when the screen offers nothing', () {
      expect(ChittiScreenAdvisor.adviseFrom(_snap()), isNull);
    });
  });
}
