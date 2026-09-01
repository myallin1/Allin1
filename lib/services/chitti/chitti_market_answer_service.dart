// ================================================================
// chitti_market_answer_service.dart — the answer to a "what does it
// cost / what should I buy" question.
// ================================================================
// NEW (Aug 28 2026 — Nizam, two asks in one:
//   "new best mobile under 10000 nu ketta ... correctana mobile and
//    athu yen antha customer ku useful ah irukumnu explain pannanum"
//   "customer mobile display price kettalum ... 300, 500, 1000 range ku
//    compatible, better, premium nu 3 quality list la kaatanum box
//    potu").
//
// THE SHAPE OF THE ANSWER
// Three tiers, always, because that is how this trade actually quotes:
// a compatible part, a better one, and the original. A single number
// invites an argument at the counter; three tiers turn the same
// conversation into a choice, and the customer arrives already knowing
// which one they want.
//
// WHERE THE NUMBERS COME FROM, AND WHAT THEY ARE NOT
// Nizam was explicit: "rate and models daily maarum, so namma kita than
// final rate and final offer kekkanum". So every figure here is a
// MARKET REFERENCE, labelled as one, and every answer ends the same
// way — an enquiry to NJ Tech, because that is the only place a real
// price can come from. Getting this backwards would have Chitti
// quoting a competitor's price in NJ Tech's own app.
//
// On the APK the reference comes from a live background search; on the
// PWA that is blocked by CORS (see ChittiWebSearchService) and the
// answer is the tiers plus the enquiry, without a market figure. The
// customer never sees the difference except that one has a "market
// today" line and the other does not — and the enquiry, which is the
// part that matters, works identically on both.
import 'package:flutter/foundation.dart';

import '../mobile_catalog_service.dart';
import 'chitti_web_search_service.dart';

/// One quality option for a repair.
@immutable
class ChittiPriceTier {
  const ChittiPriceTier({
    required this.name,
    required this.blurb,
    required this.multiplier,
  });

  final String name;
  final String blurb;

  /// Applied to the market reference when one is available. Ratios
  /// rather than fixed prices so a single reference figure produces a
  /// sensible spread for any model, cheap or flagship.
  final double multiplier;
}

/// The three tiers, in the order they should be shown.
const List<ChittiPriceTier> kChittiPriceTiers = <ChittiPriceTier>[
  ChittiPriceTier(
    name: 'Compatible',
    blurb: 'Budget replacement. Works fine for calls, messages and daily use.',
    multiplier: 0.6,
  ),
  ChittiPriceTier(
    name: 'Better',
    blurb: 'Closer to the original in brightness and touch feel. Most people pick this.',
    multiplier: 1,
  ),
  ChittiPriceTier(
    name: 'Premium',
    blurb: 'Original-grade panel. Same display quality the phone shipped with.',
    multiplier: 1.5,
  ),
];

/// A finished market answer.
@immutable
class ChittiMarketAnswer {
  const ChittiMarketAnswer({
    required this.headline,
    required this.tiers,
    required this.model,
    this.marketReference = '',
    this.sources = const <String>[],
  });

  final String headline;

  /// Tier name -> the line to show under it. Rendered as boxes by the
  /// caller; kept as plain data here so this file stays testable and
  /// free of widgets.
  final List<({String name, String blurb, String price})> tiers;

  final String model;

  /// The raw figure the tiers were derived from, empty when no live
  /// search was possible.
  final String marketReference;

  /// Where the reference came from, so the customer can see it is not
  /// an NJ Tech quote.
  final List<String> sources;

  bool get hasMarketReference => marketReference.isNotEmpty;
}

class ChittiMarketAnswerService {
  ChittiMarketAnswerService._();

  /// Questions this service should take.
  static final RegExp _priceAsk = RegExp(
    r'\b(price|cost|rate|how much|display|screen|glass|panel|'
    r'replace|replacement|repair)\b|'
    '(விலை|ரேட்|டிஸ்ப்ளே|ஸ்கிரீன்|மாத்த|ரிப்பேர்)',
    caseSensitive: false,
  );

  static final RegExp _buyAsk = RegExp(
    r'\b(best|good|suggest|recommend|which|buy|new)\b.{0,24}'
    r'\b(mobile|phone|smartphone)\b|'
    '(எந்த மொபைல்|நல்ல போன்|மொபைல் வாங்க)',
    caseSensitive: false,
  );

  /// True when this looks like a market/price question rather than
  /// something the rest of Chitti should handle.
  static bool handles(String question) {
    final q = question.toLowerCase();
    if (_buyAsk.hasMatch(q)) return true;
    // A price word alone is not enough — "how much is my wallet
    // balance" is a read, not a market question. It must also mention a
    // product.
    return _priceAsk.hasMatch(q) && _mentionsProduct(q);
  }

  static final RegExp _productWord = RegExp(
    r'\b(mobile|phone|display|screen|laptop|tab|tv|ac|fridge)\b',
    caseSensitive: false,
  );

  static final RegExp _productWordTamil =
      RegExp('(மொபைல்|போன்|டிஸ்ப்ளே|ஸ்கிரீன்|லேப்டாப்)');

  static bool _mentionsProduct(String q) =>
      _productWord.hasMatch(q) || _productWordTamil.hasMatch(q);

  /// Builds the answer.
  ///
  /// [search] is injectable so tests can run the whole pipeline without
  /// a network.
  static Future<ChittiMarketAnswer> answer(
    String question, {
    Future<List<ChittiSearchResult>> Function(String)? search,
  }) async {
    final model = await _guessModel(question);
    final lookup = search ?? ChittiWebSearchService.search;

    var reference = '';
    var sources = <String>[];
    try {
      final results = await lookup(_searchQueryFor(question, model));
      reference = _firstPrice(results);
      sources = results
          .map((r) => r.source)
          .where((s) => s.isNotEmpty)
          .toSet()
          .take(3)
          .toList(growable: false);
    } catch (e) {
      debugPrint('[ChittiMarketAnswer] lookup failed: $e');
    }

    final base = _parseAmount(reference);
    final tiers = kChittiPriceTiers.map((t) {
      final price = base == null
          ? 'Ask us'
          : '₹${(base * t.multiplier).round()}';
      return (name: t.name, blurb: t.blurb, price: price);
    }).toList(growable: false);

    final what = model.isEmpty ? 'that' : model;
    final headline = base == null
        ? 'Here are the three options we do for $what. Rates move with the '
            'market, so I will get you the exact price from NJ Tech.'
        : 'Market today is around $reference for $what. Here is how the '
            'three options compare — NJ Tech will confirm the final rate.';

    return ChittiMarketAnswer(
      headline: headline,
      tiers: tiers,
      model: model,
      marketReference: reference,
      sources: sources,
    );
  }

  // ── helpers ──────────────────────────────────────────────────────

  /// Matches the question against the bundled 49-model catalogue.
  ///
  /// Our own catalogue first: it is free, offline, and a model we
  /// actually stock is a better answer than one we do not.
  static Future<String> _guessModel(String question) async {
    final q = question.toLowerCase();
    try {
      await MobileCatalogService.instance.ensureLoaded();
      final phones = MobileCatalogService.instance.models;
      String best = '';
      for (final phone in phones) {
        final name = '${phone.brand} ${phone.model}'.toLowerCase();
        if (q.contains(phone.model.toLowerCase()) && phone.model.length > 3) {
          if (name.length > best.length) best = '${phone.brand} ${phone.model}';
        }
      }
      if (best.isNotEmpty) return best;
    } catch (e) {
      debugPrint('[ChittiMarketAnswer] catalogue lookup failed: $e');
    }
    return '';
  }

  static String _searchQueryFor(String question, String model) {
    // "price in India" pulls rupee figures rather than dollars, which
    // is what the tier maths needs.
    final subject = model.isEmpty ? question : '$model display';
    return '$subject price in India';
  }

  /// The first rupee amount that looks like a real price.
  static String _firstPrice(List<ChittiSearchResult> results) {
    final pattern = RegExp(r'(?:₹|Rs\.?\s?|INR\s?)\s?([0-9][0-9,]{2,7})');
    for (final r in results) {
      for (final text in <String>[r.snippet, r.title]) {
        final match = pattern.firstMatch(text);
        if (match == null) continue;
        final amount = _parseAmount(match.group(0) ?? '');
        // Filter obvious noise: a two-digit "price" or a lakh-plus
        // figure is not a display replacement.
        if (amount != null && amount >= 300 && amount <= 100000) {
          return '₹${amount.round()}';
        }
      }
    }
    return '';
  }

  static double? _parseAmount(String raw) {
    if (raw.isEmpty) return null;
    final digits = raw.replaceAll(RegExp('[^0-9]'), '');
    if (digits.isEmpty) return null;
    return double.tryParse(digits);
  }
}
