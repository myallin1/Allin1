// ================================================================
// chitti_web_search_service.dart — a free, keyless background web
// lookup for things the app itself does not know.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "Chitti ku theriyathatha iruntha ... api
// ilanalum background la DuckDuckGo la search panni atha fine tune
// panni screen la kaatanum. Background search customer ku theriya
// kudathu").
//
// ZERO COST IS THE POINT
// Nizam: "nammale free-ya than intha services tharaporom, so namma no
// cost strategy than importance kudukanum". So: no API key, no paid
// search API, no server. DuckDuckGo's HTML endpoint, parsed on device.
//
// ── THE ONE HONEST LIMITATION: THIS DOES NOT WORK ON THE PWA ────────
// A browser refuses cross-origin requests unless the far end sends
// Access-Control-Allow-Origin, and duckduckgo.com does not. That is
// the browser's security model, not something app code can work
// around, and no choice of HTML parser changes it — the request never
// reaches the parser.
//
// Verified while building this:
//   • api.duckduckgo.com DOES send `Access-Control-Allow-Origin: *`,
//     but it is an entity/definition API. For the exact queries this
//     feature is for — "best mobile under 10000", "redmi note 13
//     display price" — it returns an empty abstract, empty answer and
//     zero related topics. Confirmed against all three.
//   • html.duckduckgo.com returns real results but sends no CORS
//     header, so the PWA cannot read it.
// Making it work on web needs a proxy, which needs a server, which the
// Spark plan does not have.
//
// So this returns null on web, and the caller falls back to what the
// app knows about itself. The APK gets the market reference; the PWA
// gets the catalogue answer. Both get the enquiry, which is the part
// that actually matters — see ChittiEnquiryService.
//
// NEVER PRESENT THESE RESULTS AS OURS
// Nizam again: "rate and models daily maarum, so namma kita than final
// rate and final offer kekkanum". Scraped numbers are somebody else's
// prices on a page that changed this morning. They are labelled market
// reference wherever they are shown, and the real answer is always the
// enquiry that reaches a human at NJ Tech.
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// One search result, cleaned up.
@immutable
class ChittiSearchResult {
  const ChittiSearchResult({
    required this.title,
    required this.snippet,
    required this.url,
  });

  final String title;
  final String snippet;
  final String url;

  /// The site the result came from, for showing provenance without a
  /// full URL cluttering a chat bubble.
  String get source {
    final match = RegExp(r'https?://(?:www\.)?([^/]+)').firstMatch(url);
    return match?.group(1) ?? '';
  }
}

class ChittiWebSearchService {
  ChittiWebSearchService._();

  static const String _endpoint = 'https://html.duckduckgo.com/html/';

  /// Kept short. This runs while a customer is waiting on a chat reply,
  /// and a slow answer is worse than a local one.
  static const Duration _timeout = Duration(seconds: 8);

  /// True where a live search can actually run. See the CORS note in
  /// this file's header.
  static bool get isSupported => !kIsWeb;

  @visibleForTesting
  static http.Client? testClient;

  /// Searches, or returns an empty list.
  ///
  /// Never throws: this is a nice-to-have layer sitting under a chat
  /// reply, and a failed lookup must degrade to "I don't know that one"
  /// rather than break the message the customer just sent.
  static Future<List<ChittiSearchResult>> search(
    String query, {
    int limit = 5,
  }) async {
    if (!isSupported && testClient == null) {
      debugPrint('[ChittiWebSearch] skipped — browsers block this (CORS).');
      return const <ChittiSearchResult>[];
    }
    if (query.trim().isEmpty) return const <ChittiSearchResult>[];

    final client = testClient ?? http.Client();
    try {
      final response = await client
          .post(
            Uri.parse(_endpoint),
            headers: const <String, String>{
              'Content-Type': 'application/x-www-form-urlencoded',
              // Without a normal UA the endpoint serves a blocked page.
              'User-Agent':
                  'Mozilla/5.0 (Linux; Android 12) AppleWebKit/537.36 '
                      '(KHTML, like Gecko) Chrome/120 Mobile Safari/537.36',
            },
            body: <String, String>{'q': query},
          )
          .timeout(_timeout);

      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint('[ChittiWebSearch] HTTP ${response.statusCode}');
        return const <ChittiSearchResult>[];
      }
      return parseResults(response.body, limit: limit);
    } catch (e) {
      debugPrint('[ChittiWebSearch] failed: $e');
      return const <ChittiSearchResult>[];
    } finally {
      if (testClient == null) client.close();
    }
  }

  /// Pulls results out of DuckDuckGo's HTML.
  ///
  /// Regex rather than a DOM parser on purpose: it avoids adding a
  /// dependency for one screen's worth of markup, and the shape here is
  /// simple and stable. Exposed for tests so the parsing can be checked
  /// against a real captured page without hitting the network.
  @visibleForTesting
  static List<ChittiSearchResult> parseResults(
    String html, {
    int limit = 5,
  }) {
    final results = <ChittiSearchResult>[];

    final linkPattern = RegExp(
      '<a[^>]*class="[^"]*result__a[^"]*"[^>]*href="([^"]+)"[^>]*>(.*?)</a>',
      dotAll: true,
    );
    final snippetPattern = RegExp(
      '<a[^>]*class="[^"]*result__snippet[^"]*"[^>]*>(.*?)</a>',
      dotAll: true,
    );

    final links = linkPattern.allMatches(html).toList(growable: false);
    final snippets = snippetPattern.allMatches(html).toList(growable: false);

    for (var i = 0; i < links.length && results.length < limit; i++) {
      final rawUrl = links[i].group(1) ?? '';
      final title = _clean(links[i].group(2) ?? '');
      if (title.isEmpty) continue;

      final snippet =
          i < snippets.length ? _clean(snippets[i].group(1) ?? '') : '';

      results.add(
        ChittiSearchResult(
          title: title,
          snippet: snippet,
          url: _unwrapRedirect(rawUrl),
        ),
      );
    }
    return results;
  }

  /// DuckDuckGo wraps result links in its own redirect
  /// (`//duckduckgo.com/l/?uddg=<encoded real url>`), so the visible
  /// source would otherwise always read "duckduckgo.com".
  static String _unwrapRedirect(String href) {
    final match = RegExp('uddg=([^&]+)').firstMatch(href);
    if (match != null) {
      try {
        return Uri.decodeComponent(match.group(1)!);
      } catch (_) {
        // Fall through to the raw href.
      }
    }
    return href.startsWith('//') ? 'https:$href' : href;
  }

  static String _clean(String html) => html
      .replaceAll(RegExp('<[^>]*>'), '')
      .replaceAll('&amp;', '&')
      .replaceAll('&quot;', '"')
      .replaceAll('&#x27;', "'")
      .replaceAll('&#39;', "'")
      .replaceAll('&lt;', '<')
      .replaceAll('&gt;', '>')
      .replaceAll('&nbsp;', ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
