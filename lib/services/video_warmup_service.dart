// ================================================================
// video_warmup_service.dart — makes the first tap on a video play
// immediately instead of buffering.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "customer reward page kulla vanthathume
// videos net-la irunthu load agikatum, athuvum cache-la vachitta
// customer again play pannuna load agathu, takkunu play agurathu,
// ready-yum irukum 1st time").
//
// ── WHAT IS AND IS NOT POSSIBLE, STATED PLAINLY ─────────────────────
// The video BYTES cannot be cached. These are YouTube videos played
// through YouTube's own iframe player; the app never sees the media
// stream, and downloading it would breach YouTube's terms and break
// the moment they change their delivery. Any library that claims
// otherwise is scraping, and scraping is not something to build a
// shop's app on.
//
// What actually costs the customer their wait is not the video data —
// it is everything that happens BEFORE the first frame:
//   1. creating the WebView / iframe,
//   2. downloading and running YouTube's player JavaScript,
//   3. the player handshaking and asking for the first segments.
// Steps 1 and 2 are most of it on a cold tap, and both CAN be done in
// advance. That is what this file does.
//
// So the promise this delivers is exactly the one that matters: by the
// time a thumb reaches the play button, the player already exists and
// YouTube's assets are already in the WebView's HTTP cache, so
// playback starts almost at once — and on a second open there is
// nothing left to load at all, because the controller is kept alive
// rather than thrown away.
//
// ── WHY ONLY ONE PLAYER IS WARMED ───────────────────────────────────
// rewards_hub_screen.dart already made this call, and it was right:
//   "NO player, no WebView, is created while the carousel is merely
//    scrolling past ... that lazy discipline is what keeps this
//    affordable on the low-end Android phones most of Erode is on."
// Ten hidden WebViews would trade a two-second wait for an
// out-of-memory kill. So: every THUMBNAIL is precached (images are
// cheap and that is what the customer actually sees), and exactly ONE
// player is warmed — the one they are most likely to tap.
import 'package:flutter/material.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

/// The ownership rules for one warm, borrowable thing.
///
/// Generic and free of any player type on purpose. Every bug the
/// Aug 28 re-audit found lived in these rules, not in the player:
///
///   • leaving the screen that warmed it closed the item while a modal
///     was still rendering it;
///   • releasing a borrowed item after that closed it a SECOND time,
///     inside a State.dispose(), which is the worst place to throw.
///
/// Keeping the rules here means they can be tested directly — creating
/// a real YoutubePlayerController needs a platform WebView and cannot
/// run in a unit test, which is exactly how these slipped through.
class VideoWarmSlot<T extends Object> {
  VideoWarmSlot({required this.onClose});

  /// How to tear an item down. Called at most once per item.
  final void Function(T item) onClose;

  T? _item;
  String? _key;
  bool _borrowed = false;
  bool _disposeWhenReturned = false;
  final Set<T> _closed = <T>{};

  T? get item => _item;
  String? get key => _key;
  bool get isBorrowed => _borrowed;

  /// Installs [item] for [key], replacing nothing — callers re-point an
  /// existing item themselves rather than creating a second one.
  void fill(String key, T item) {
    _item = item;
    _key = key;
  }

  /// Records that the existing item now holds [key].
  // ignore: use_setters_to_change_properties
  void repoint(String key) => _key = key;

  /// Hands the item over when it matches [key] and nobody else has it.
  T? take(String key) {
    if (_item == null || _key != key || _borrowed) return null;
    _borrowed = true;
    return _item;
  }

  /// Takes the item back. Returns true when the caller should keep it
  /// alive (it is ours and still wanted), false when it has been closed.
  bool release(T item) {
    if (!identical(item, _item)) {
      // Not ours — the borrower built its own, so it owns the teardown.
      // Guarded so an item closed during a deferred dispose cannot be
      // closed again here.
      _close(item);
      return false;
    }

    _borrowed = false;
    if (_disposeWhenReturned) {
      _disposeWhenReturned = false;
      dispose();
      return false;
    }
    return true;
  }

  /// Releases the item, or defers until the borrower returns it.
  void dispose() {
    if (_borrowed) {
      _disposeWhenReturned = true;
      return;
    }
    final current = _item;
    if (current != null) _close(current);
    _item = null;
    _key = null;
  }

  void _close(T item) {
    if (!_closed.add(item)) return;
    onClose(item);
  }
}

class VideoWarmupService {
  VideoWarmupService._();

  static final VideoWarmupService instance = VideoWarmupService._();

  late final VideoWarmSlot<YoutubePlayerController> _slot =
      VideoWarmSlot<YoutubePlayerController>(
    onClose: (c) {
      try {
        c.close();
      } catch (e) {
        debugPrint('[VideoWarmup] close failed: $e');
      }
    },
  );

  /// The video the warm controller is currently holding, if any.
  String? get warmVideoId => _slot.key;

  /// The controller to mount invisibly, or null when nothing is warm.
  YoutubePlayerController? get warmController => _slot.item;

  /// Precaches the poster images for [videoIds].
  ///
  /// Cheap, and the highest-value half of this whole file: the
  /// thumbnail is what the customer looks at while deciding whether to
  /// tap, so a card that pops in fully formed reads as "fast" long
  /// before any video is involved.
  static Future<void> precacheThumbnails(
    BuildContext context,
    Iterable<String> videoIds,
  ) async {
    for (final id in videoIds) {
      if (id.isEmpty) continue;
      if (!context.mounted) return;
      try {
        await precacheImage(
          NetworkImage('https://img.youtube.com/vi/$id/hqdefault.jpg'),
          context,
        );
      } catch (e) {
        // A poster that will not load is not worth failing a page for.
        debugPrint('[VideoWarmup] thumbnail precache failed for $id: $e');
      }
    }
  }

  /// Gets a player ready for [videoId] without playing it.
  ///
  /// `cueVideoById` rather than `loadVideoById`: cue tells YouTube to
  /// fetch the player and the video's metadata and get ready, but not
  /// to start. Load would begin playback, which is the last thing a
  /// customer browsing a carousel wants to hear.
  void warm(String videoId) {
    if (videoId.isEmpty || videoId == _slot.key) return;

    final existing = _slot.item;
    if (existing != null) {
      // Re-point the player we already have. Creating a second WebView
      // to warm a different video would be exactly the memory problem
      // this service exists to avoid.
      _slot.repoint(videoId);
      try {
        existing.cueVideoById(videoId: videoId);
      } catch (e) {
        debugPrint('[VideoWarmup] re-cue failed: $e');
      }
      return;
    }

    _slot.fill(
      videoId,
      YoutubePlayerController.fromVideoId(
        videoId: videoId,
        // Warming, not playing.
        // ignore: avoid_redundant_argument_values
        autoPlay: false,
        params: const YoutubePlayerParams(
          showFullscreenButton: true,
          strictRelatedVideos: true,
          enableCaption: false,
        ),
      ),
    );
  }

  /// Hands over the warm controller when it already holds [videoId].
  ///
  /// Returns null when nothing matches or someone else already has it,
  /// and the caller then builds its own — so a miss costs the old
  /// behaviour, never a broken player.
  YoutubePlayerController? take(String videoId) => _slot.take(videoId);

  /// Takes a borrowed controller back instead of destroying it.
  void release(YoutubePlayerController controller) {
    final keep = _slot.release(controller);
    if (!keep) return;
    // Ours, and still wanted: stop the sound, keep the player. The next
    // open reuses it with nothing left to download.
    try {
      controller.pauseVideo();
    } catch (e) {
      debugPrint('[VideoWarmup] pause on release failed: $e');
    }
  }

  /// Releases the warm player.
  ///
  /// Deferred when a modal still holds it — see [VideoWarmSlot].
  void dispose() => _slot.dispose();
}

/// Mounts the warm player invisibly so it actually loads.
///
/// A platform view only downloads anything once it is in the tree and
/// laid out, so this gives it a real (tiny) box rather than Offstage,
/// which would skip layout and defeat the point.
class VideoWarmupHost extends StatelessWidget {
  const VideoWarmupHost({super.key});

  @override
  Widget build(BuildContext context) {
    final controller = VideoWarmupService.instance.warmController;
    if (controller == null) return const SizedBox.shrink();
    return IgnorePointer(
      child: Opacity(
        opacity: 0,
        child: SizedBox(
          width: 1,
          height: 1,
          child: YoutubePlayer(controller: controller),
        ),
      ),
    );
  }
}
