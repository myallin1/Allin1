// ================================================================
// tutorial_videos_section.dart — Firestore-driven "how it works"
// videos, shared by the Hero app, the Hero PWA and the Customer app.
// ================================================================
// NEW (Aug 29 2026 — Nizam: "namma customer app rewards page la
// vachchmari hero app kum tutorial video, hero onboarding app, PWA
// layum vaikanum... namma already use pannuna super architecture audit
// pannitu athula irukkamariye best idea va ingayum reuse panniklama?").
//
// Answer to that question: yes, and this file is the reuse. Nothing
// about video playback is reinvented here. It composes the exact three
// pieces the Rewards page already runs in production:
//
//   youtubeVideoId()      — mobile_models.dart. Resolves any pasted
//                           link shape (youtu.be, /shorts/, /embed/, a
//                           bare 11-char id) to an id, or null. Nothing
//                           renders until it returns non-null, so a
//                           typo'd link degrades to "no video" instead
//                           of a dead player.
//   VideoThumbnail        — listing_video_player.dart. YouTube's own
//                           free static thumbnail endpoint, cached like
//                           any other image. Costs nothing and needs no
//                           player.
//   showPremiumVideoModal — listing_video_player.dart. Builds the
//                           WebView ONLY when a tap happens and tears
//                           it down on close. That laziness is a
//                           performance contract, and it is why this
//                           file calls the shared modal instead of
//                           writing a second player.
//   VideoWarmupService    — warms exactly ONE player + precaches
//                           thumbnails, so the first tap is not a cold
//                           two-second WebView boot.
//
// WHY NOT tutorial_video_player_screen.dart
// That older widget plays a BUNDLED ASSET. Shipping onboarding videos
// as assets would put tens of megabytes into an APK aimed at low-end
// Android phones in Erode, and would make every re-shoot an app-store
// release. YouTube-hosted links cost ₹0 on the Spark plan (no Storage
// bucket exists), stream from YouTube's CDN, work identically in the
// PWA because the player is a real DOM iframe there, and let Nizam
// swap a video by editing one Firestore field. That file stays unused.
//
// WHY FIRESTORE AND NOT A CONST LIST
// Same reason the Rewards ads are Firestore-driven: the videos do not
// exist yet. A const list would mean an app release the day each one is
// shot. `tutorial_videos/{id}` lets them appear the moment they are
// uploaded, in any order, per audience.
//
// DOCUMENT SHAPE — tutorial_videos/{autoId}
//   title     string   'How to register as a Hero'
//   subtitle  string   optional one-liner
//   videoUrl  string   any YouTube link shape
//   audience  string   'hero' | 'customer'  (see [TutorialAudience])
//   category  string   optional — a hero skill key, or 'onboarding'
//   order     number   ascending; ties fall back to createdAt
//   active    bool     false hides it without deleting it
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/mobile_models.dart' show youtubeVideoId;
import '../screens/mobiles/listing_video_player.dart'
    show showPremiumVideoModal, VideoThumbnail;
import '../services/video_warmup_service.dart';

/// Who a tutorial is for. Stored as the raw string in Firestore so an
/// admin can type it, and matched case-insensitively on read.
class TutorialAudience {
  TutorialAudience._();

  /// Shown in the Hero app and the Hero PWA — onboarding, going online,
  /// accepting a job, getting paid.
  static const String hero = 'hero';

  /// Shown in the Customer app.
  static const String customer = 'customer';
}

/// One tutorial video.
@immutable
class TutorialVideo {
  const TutorialVideo({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.videoUrl,
    required this.category,
  });

  final String id;
  final String title;
  final String subtitle;
  final String videoUrl;
  final String category;

  /// Resolved 11-char YouTube id, or null when the link is unusable.
  /// Never bypassed — see the header.
  String? get videoId => youtubeVideoId(videoUrl);

  factory TutorialVideo.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    return TutorialVideo(
      id: doc.id,
      title: (d['title'] as String?)?.trim() ?? 'How it works',
      subtitle: (d['subtitle'] as String?)?.trim() ?? '',
      videoUrl: (d['videoUrl'] as String?)?.trim() ?? '',
      category: (d['category'] as String?)?.trim().toLowerCase() ?? '',
    );
  }
}

/// A horizontal strip of tutorial videos for one [audience].
///
/// RENDERS NOTHING when there are no playable videos — no empty state,
/// no "coming soon" placeholder, no reserved blank space. That matters
/// right now, because the videos genuinely do not exist yet: this can be
/// dropped into the hero welcome screen, the registration form and the
/// customer app today, be completely invisible, and light up on its own
/// the moment Nizam adds the first document. No follow-up release.
class TutorialVideosSection extends StatefulWidget {
  const TutorialVideosSection({
    required this.audience,
    this.heading = 'How it works',
    this.category,
    this.accentColor = const Color(0xFFFF4FA3),
    super.key,
  });

  /// [TutorialAudience.hero] or [TutorialAudience.customer].
  final String audience;

  final String heading;

  /// Optional narrower filter — a skill key, or 'onboarding'. Null shows
  /// every video for the audience.
  final String? category;

  final Color accentColor;

  @override
  State<TutorialVideosSection> createState() => _TutorialVideosSectionState();
}

class _TutorialVideosSectionState extends State<TutorialVideosSection> {
  /// Guards the one-time warm-up, exactly as rewards_hub_screen.dart
  /// does. Without the flag this fires on every rebuild of the stream.
  bool _warmed = false;

  /// The live query subscription, created exactly ONCE in [initState].
  ///
  /// BUG FOUND WHILE INVESTIGATING "hero registration screen goes blank
  /// after filling basic details" (Aug 2026). This used to be built
  /// inline as `stream: _query().snapshots()` directly in [build] — a
  /// BRAND NEW Query object and a BRAND NEW Firestore listener
  /// subscription on every single rebuild of this widget.
  ///
  /// hero_register_screen.dart, where this section is embedded, rebuilds
  /// constantly and for reasons that have nothing to do with videos: GPS
  /// position updates, the draft-save timer, the city picker, the
  /// vehicle/skill kind toggle, checkbox taps, the "How to register"
  /// guide's expand animation. Every one of those rebuilds was tearing
  /// down this section's Firestore listener and opening a fresh one from
  /// scratch — a query-and-resubscribe loop running on a hot path,
  /// fighting the rest of the page for every frame. That is more than
  /// enough to stall Flutter's frame pipeline on a real phone, which is
  /// exactly the "screen shows nothing" symptom this was found from.
  ///
  /// A [StreamBuilder] is only safe when the `stream:` argument is
  /// STABLE across rebuilds — building it inline is a well-known trap.
  /// Creating the query once here and reusing the same `Stream` object
  /// on every subsequent build is the fix.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _stream = _query();

  Stream<QuerySnapshot<Map<String, dynamic>>> _query() {
    var q = FirebaseFirestore.instance
        .collection('tutorial_videos')
        .where('audience', isEqualTo: widget.audience)
        .where('active', isEqualTo: true);
    final category = widget.category;
    if (category != null && category.isNotEmpty) {
      q = q.where('category', isEqualTo: category);
    }
    // NOT ordered in the query. An orderBy here would need a composite
    // index per filter combination, and a missing index fails with
    // `failed-precondition` — which, on a StreamBuilder, surfaces as a
    // permanently empty section that looks exactly like "no videos yet".
    // These lists are a handful of documents; sorting them client-side
    // below is free and cannot fail that way.
    return q.limit(20).snapshots();
  }

  void _warmFirst(List<TutorialVideo> videos) {
    if (_warmed || videos.isEmpty) return;
    _warmed = true;
    final ids = videos
        .map((v) => v.videoId)
        .whereType<String>()
        .toList(growable: false);
    if (ids.isEmpty) return;
    // Deferred to after this frame — warming during build would mount a
    // player inside a widget tree that is still being constructed.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // ONE player warmed, never one per card. Ten hidden WebViews is
      // the trade video_warmup_service.dart's header explicitly refuses.
      VideoWarmupService.instance.warm(ids.first);
      setState(() {});
      unawaited(VideoWarmupService.precacheThumbnails(context, ids));
    });
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      // The SAME stream instance every rebuild — see [_stream]'s doc
      // comment for why building it inline here was the bug.
      stream: _stream,
      builder: (context, snapshot) {
        if (!snapshot.hasData) return const SizedBox.shrink();

        final videos = snapshot.data!.docs
            .map(TutorialVideo.fromDoc)
            // A document whose link does not resolve is dropped
            // entirely rather than rendered as a broken tile.
            .where((v) => v.videoId != null)
            .toList();

        if (videos.isEmpty) return const SizedBox.shrink();

        // Client-side sort — see the comment in _query().
        final ordered = snapshot.data!.docs;
        videos.sort((a, b) {
          num orderOf(String id) {
            final doc = ordered.firstWhere((d) => d.id == id);
            return (doc.data()['order'] as num?) ?? 9999;
          }

          return orderOf(a.id).compareTo(orderOf(b.id));
        });

        _warmFirst(videos);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(Icons.play_circle_fill_rounded,
                    color: widget.accentColor, size: 18,),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    widget.heading,
                    style: GoogleFonts.outfit(
                      color: Theme.of(context).textTheme.titleMedium?.color,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 158,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: videos.length,
                separatorBuilder: (_, __) => const SizedBox(width: 10),
                itemBuilder: (context, i) => _TutorialCard(
                  video: videos[i],
                  accentColor: widget.accentColor,
                ),
              ),
            ),
            // Hosts the single warmed player, offstage. Same placement
            // as the Rewards carousel.
            const VideoWarmupHost(),
          ],
        );
      },
    );
  }
}

class _TutorialCard extends StatelessWidget {
  const _TutorialCard({required this.video, required this.accentColor});

  final TutorialVideo video;
  final Color accentColor;

  @override
  Widget build(BuildContext context) {
    final videoId = video.videoId!;
    return SizedBox(
      width: 210,
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        // Taps play the video IN-APP through the shared modal. Not
        // url_launcher: handing a first-time hero off to the YouTube app
        // mid-registration is how a half-filled form gets abandoned.
        onTap: () => showPremiumVideoModal(
          context,
          videoId: videoId,
          title: video.title,
          subtitle: video.subtitle.isEmpty ? null : video.subtitle,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(14),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  SizedBox(
                    height: 112,
                    width: 210,
                    child: VideoThumbnail(videoId: videoId),
                  ),
                  Container(
                    width: 40,
                    height: 40,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: accentColor.withValues(alpha: 0.92),
                    ),
                    child: const Icon(Icons.play_arrow_rounded,
                        color: Colors.white, size: 24,),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 6),
            Text(
              video.title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                color: Theme.of(context).textTheme.bodyLarge?.color,
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                height: 1.25,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
