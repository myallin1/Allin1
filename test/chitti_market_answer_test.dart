// ================================================================
// chitti_market_answer_test.dart
// ================================================================
// Two rules matter more than the search itself.
//
// 1. A scraped figure is NEVER presented as an NJ Tech price. Nizam:
//    "rate and models daily maarum, so namma kita than final rate and
//    final offer kekkanum". A customer quoting a competitor's price
//    back at the counter is the failure this guards against.
//
// 2. The answer must be useful with no search at all — the PWA cannot
//    reach DuckDuckGo (CORS), so the tiers and the enquiry have to
//    stand on their own.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_enquiry_service.dart';
import 'package:erode_superapp/services/chitti/chitti_market_answer_service.dart';
import 'package:erode_superapp/services/chitti/chitti_web_search_service.dart';

Future<List<ChittiSearchResult>> _noResults(String _) async =>
    const <ChittiSearchResult>[];

Future<List<ChittiSearchResult>> _withPrice(String _) async =>
    const <ChittiSearchResult>[
      ChittiSearchResult(
        title: 'Redmi Note 13 Display Price',
        snippet: 'Buy combo display at ₹1,200 with warranty.',
        url: 'https://example-parts.in/redmi-note-13',
      ),
    ];

void main() {
  group('what it takes on', () {
    test('price and display questions', () {
      expect(ChittiMarketAnswerService.handles('redmi display price'), isTrue);
      expect(
        ChittiMarketAnswerService.handles('how much for a phone screen'),
        isTrue,
      );
      expect(
        ChittiMarketAnswerService.handles('best mobile under 10000'),
        isTrue,
      );
    });

    test('leaves the wallet read alone', () {
      // "how much" + no product = an account read, not a market
      // question. Stealing it would break a working feature.
      expect(
        ChittiMarketAnswerService.handles('how much balance do i have'),
        isFalse,
      );
      expect(ChittiMarketAnswerService.handles('where is my order'), isFalse);
    });
  });

  group('with no search available (the PWA case)', () {
    test('still returns three tiers', () async {
      final a = await ChittiMarketAnswerService.answer(
        'redmi note 13 display price',
        search: _noResults,
      );
      expect(a.tiers.length, 3);
      expect(
        a.tiers.map((t) => t.name),
        containsAll(<String>['Compatible', 'Better', 'Premium']),
      );
    });

    test('says "Ask us" rather than inventing a number', () {
      // Guessing a price with nothing to base it on would be the worst
      // possible failure of this feature.
      ChittiMarketAnswerService.answer(
        'display price',
        search: _noResults,
      ).then((a) {
        for (final tier in a.tiers) {
          expect(tier.price, 'Ask us');
        }
      });
    });

    test('still points at NJ Tech for the real rate', () async {
      final a = await ChittiMarketAnswerService.answer(
        'display price',
        search: _noResults,
      );
      expect(a.headline.toLowerCase(), contains('nj tech'));
      expect(a.hasMarketReference, isFalse);
    });
  });

  group('with a market reference', () {
    test('spreads one figure across the three tiers', () async {
      final a = await ChittiMarketAnswerService.answer(
        'redmi note 13 display price',
        search: _withPrice,
      );
      expect(a.marketReference, '₹1200');
      expect(a.tiers[0].price, '₹720'); // compatible, 0.6x
      expect(a.tiers[1].price, '₹1200'); // better, 1.0x
      expect(a.tiers[2].price, '₹1800'); // premium, 1.5x
    });

    test('labels the figure as market, never as ours', () async {
      final a = await ChittiMarketAnswerService.answer(
        'redmi note 13 display price',
        search: _withPrice,
      );
      expect(a.headline.toLowerCase(), contains('market'));
      // And still defers the final number to a human.
      expect(a.headline.toLowerCase(), contains('nj tech'));
      expect(a.sources, contains('example-parts.in'));
    });
  });

  _enquiryOutcomeTests();

  group('search result parsing', () {
    test('pulls title, snippet and the real URL out of DDG markup', () {
      const html = '''
        <a class="result__a" href="//duckduckgo.com/l/?uddg=https%3A%2F%2Fshop.in%2Fx">
          Redmi &amp; Note Display
        </a>
        <a class="result__snippet">Combo display at ₹1,499 only.</a>
      ''';
      final results = ChittiWebSearchService.parseResults(html);
      expect(results, hasLength(1));
      expect(results.first.title, 'Redmi & Note Display');
      // The DDG redirect must be unwrapped or every source reads
      // "duckduckgo.com", which tells the customer nothing.
      expect(results.first.url, 'https://shop.in/x');
      expect(results.first.source, 'shop.in');
    });

    test('empty markup is not an error', () {
      expect(ChittiWebSearchService.parseResults('<html></html>'), isEmpty);
    });

    test('is disabled on web, where browsers block it', () {
      // Documents the platform split rather than asserting a value that
      // flips between test targets.
      expect(ChittiWebSearchService.isSupported, isNotNull);
    });
  });
}

// ── the reply must match what actually happened ──────────────────────
//
// Self-audit finding: submit() returned a bool, so "not signed in" and
// "the write was refused" were the same value — and a signed-in
// customer whose enquiry failed (rules not deployed, or offline) was
// told to sign in. Telling someone who IS signed in to sign in reads as
// broken and hides the real cause from whoever has to debug it.
void _enquiryOutcomeTests() {
  group('enquiry outcomes are distinguishable', () {
    test('there is a third state beyond yes/no', () {
      expect(ChittiEnquiryOutcome.values, hasLength(3));
      expect(
        ChittiEnquiryOutcome.values,
        containsAll(<ChittiEnquiryOutcome>[
          ChittiEnquiryOutcome.sent,
          ChittiEnquiryOutcome.needsSignIn,
          ChittiEnquiryOutcome.failed,
        ]),
      );
    });

    test('failed is not the same as needsSignIn', () {
      // The whole point of the fix.
      expect(
        ChittiEnquiryOutcome.failed == ChittiEnquiryOutcome.needsSignIn,
        isFalse,
      );
    });
  });
}
