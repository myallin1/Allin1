// ================================================================
// chitti_video_service.dart — lets Chitti hand back a video when one
// is genuinely relevant.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "suppose Chitti yethachum video-va
// reference kudukanumna, YouTube la irunthu antha link reward maariye
// screen la stretch agi play aganum, customer ku Chitti chat
// section-laye").
//
// WHERE THE VIDEOS COME FROM
// Not a new content pipeline. The `ads` collection already holds the
// promo clips admin uploads for the Rewards carousel, each with a
// shop, an offer line and a category. Reusing it means a video Chitti
// shows is one somebody at NJ Tech deliberately published — never a
// random YouTube result — and adding a new one needs no code change.
//
// COST DISCIPLINE
// One bounded read per app run, cached in memory. Chitti is asked
// things constantly and a Firestore query per message would be a
// standing bill on a plan where reads are the budget. A session-length
// cache is the right trade: ads change daily at most, and a customer
// who reopens the app gets the fresh set.
//
// RESTRAINT IS THE FEATURE
// [findFor] returns null unless the match is genuinely good. A video
// attached to an unrelated answer is clutter, and clutter in a chat
// bubble is worse than in a carousel because the customer came here to
// get something done.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../../models/mobile_models.dart' show youtubeVideoId;
import '../firestore_usage_tracking.dart';

/// One publishable clip.
@immutable
class ChittiVideo {
  const ChittiVideo({
    required this.videoId,
    required this.shop,
    required this.offer,
    required this.category,
  });

  final String videoId;
  final String shop;
  final String offer;
  final String category;

  /// Everything worth matching a question against, lowercased once.
  String get haystack => '$shop $offer $category'.toLowerCase();
}

class ChittiVideoService {
  ChittiVideoService._();

  static List<ChittiVideo>? _cache;
  static Future<void>? _loading;

  /// Loads once per app run. Safe to call on every message.
  static Future<void> ensureLoaded() {
    if (_cache != null) return Future<void>.value();
    return _loading ??= _load();
  }

  static Future<void> _load() async {
    try {
      // Same filter the Rewards carousel uses, without the orderBy —
      // that pairing needs a composite index, and this list is small
      // enough that order does not matter for matching.
      final snap = await FirebaseFirestore.instance
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .limit(20)
          .trackedGet();

      _cache = snap.docs
          .map((doc) {
            final d = doc.data();
            final id = youtubeVideoId(d['videoUrl'] as String? ?? '');
            if (id == null || id.isEmpty) return null;
            return ChittiVideo(
              videoId: id,
              shop: (d['shop'] as String?) ?? '',
              offer: (d['offer'] as String?) ?? '',
              category: (d['category'] as String?) ?? '',
            );
          })
          .whereType<ChittiVideo>()
          .toList(growable: false);
    } catch (e) {
      debugPrint('[ChittiVideoService] load failed: $e');
      // An empty cache, not a null one: a failed load must not make
      // every later message retry the query.
      _cache = const <ChittiVideo>[];
    } finally {
      _loading = null;
    }
  }

  /// The best video for [query], or null when nothing is a good enough
  /// match.
  ///
  /// [sectionKey] narrows by category when Chitti already knows which
  /// part of the app this is about.
  static ChittiVideo? findFor(String query, {String? sectionKey}) {
    final videos = _cache;
    if (videos == null || videos.isEmpty) return null;

    final words = query
        .toLowerCase()
        .split(RegExp('[^a-z0-9஀-௿]+'))
        // Two-letter words match everything and mean nothing.
        .where((w) => w.length > 3)
        .toSet();
    if (words.isEmpty && sectionKey == null) return null;

    ChittiVideo? best;
    var bestScore = 0;
    for (final video in videos) {
      var score = 0;
      for (final word in words) {
        if (video.haystack.contains(word)) score += 2;
      }
      if (sectionKey != null &&
          video.category.toLowerCase().contains(sectionKey.toLowerCase())) {
        // Worth more than a word overlap, and on its own enough to
        // clear the bar: a section key is not a guess — Chitti already
        // resolved which part of the app this is about, so a clip
        // published under that category is on-topic by construction.
        score += 4;
      }
      if (score > bestScore) {
        bestScore = score;
        best = video;
      }
    }

    // A single incidental word overlap is not a reason to show a video.
    // Two signals, or a category hit, is.
    return bestScore >= 4 ? best : null;
  }

  @visibleForTesting
  // ignore: use_setters_to_change_properties
  static void seedForTesting(List<ChittiVideo> videos) => _cache = videos;

  @visibleForTesting
  static void resetForTesting() {
    _cache = null;
    _loading = null;
  }
}
