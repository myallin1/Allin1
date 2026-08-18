// ================================================================
// ListingVideoPlayer — inline YouTube player for a phone listing
// ================================================================
// COST: zero. YouTube stores, transcodes, and streams the video from
// its own CDN; we persist a single URL string in Firestore. That is
// the entire reason video is offered on phones at all — self-hosting
// even a handful of short clips would exhaust the Cloudinary free tier
// and is impossible on Firebase's Spark plan (no Storage bucket).
//
// TRADE-OFF (Nizam's explicit call): an embedded player keeps the
// customer inside Allin1, at the cost of app weight — youtube_player_
// iframe pulls in webview_flutter and its platform implementations.
// The zero-weight alternative was handing off to the YouTube app via
// url_launcher. Embedded was chosen deliberately.
//
// LAZY BY DESIGN: the controller is only created when the customer
// actually taps play. Building a WebView for every listing detail that
// merely *has* a video would spin up a browser engine the customer may
// never use — slow on the low-end Android phones most of Erode is on.
// Until then this shows a cheap thumbnail (YouTube's own free static
// thumbnail endpoint, cached like any other image).
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import '../../widgets/premium_theme.dart';

// ================================================================
// SHARED LAZY VIDEO MODAL
// ================================================================
// Used by BOTH the Mobile Hub and the Rewards page. Shared on purpose:
// the lazy-loading discipline (never build a player until the customer
// asks for one) is a performance contract, and a second copy of this
// is how that contract quietly gets broken later.
//
// The controller is created inside the modal's own State and closed in
// its dispose(), so a WebView exists ONLY while the sheet is open and
// is torn down the moment it closes. Nothing in any scrolling list
// ever constructs one.
Future<void> showPremiumVideoModal(
  BuildContext context, {
  required String videoId,
  required String title,
  String? subtitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    // Transparent barrier + our own blurred scrim, so the page behind
    // softly recedes instead of just going flat black.
    barrierColor: Colors.black.withValues(alpha: 0.25),
    builder: (_) => _PremiumVideoSheet(
      videoId: videoId,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _PremiumVideoSheet extends StatefulWidget {
  final String videoId;
  final String title;
  final String? subtitle;

  const _PremiumVideoSheet({
    required this.videoId,
    required this.title,
    this.subtitle,
  });

  @override
  State<_PremiumVideoSheet> createState() => _PremiumVideoSheetState();
}

class _PremiumVideoSheetState extends State<_PremiumVideoSheet> {
  late final YoutubePlayerController _controller;

  @override
  void initState() {
    super.initState();
    // Safe to build eagerly HERE — this State only exists once the
    // customer has already tapped to open the modal.
    _controller = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        // Keeps end-screen suggestions within the same channel where
        // possible — we don't want a competitor's shop suggested at the
        // end of our seller's clip.
        strictRelatedVideos: true,
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PremiumModalScrim(
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 10),
              Container(
                width: 44,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 14),
              ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusLg),
                child: Container(
                  color: kPremiumWhite,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      AspectRatio(
                        aspectRatio: 16 / 9,
                        child: YoutubePlayer(
                          controller: _controller,
                          aspectRatio: 16 / 9,
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 12, 16),
                        child: Row(
                          children: [
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    widget.title,
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                    style: premiumTitle(size: 16),
                                  ),
                                  if (widget.subtitle != null &&
                                      widget.subtitle!.trim().isNotEmpty) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      widget.subtitle!,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: premiumBody(size: 12),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            IconButton(
                              tooltip: 'Close',
                              onPressed: () => Navigator.maybePop(context),
                              icon: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: kPremiumHairline,
                                  shape: BoxShape.circle,
                                ),
                                child: const Icon(Icons.close_rounded,
                                    size: 18, color: kPremiumInk),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Cheap pre-play poster used in lists and detail headers. YouTube's
/// `hqdefault` endpoint is free, needs no API key, and exists for every
/// public video — unlike `maxresdefault`, which 404s on lower-resolution
/// uploads and would leave a broken box.
class VideoThumbnail extends StatelessWidget {
  final String videoId;
  final BoxFit fit;

  const VideoThumbnail({super.key, required this.videoId, this.fit = BoxFit.cover});

  @override
  Widget build(BuildContext context) {
    return Image.network(
      'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
      fit: fit,
      errorBuilder: (_, __, ___) => Container(
        color: kPremiumHairline,
        alignment: Alignment.center,
        child: const Icon(Icons.videocam_off_rounded,
            color: kPremiumMuted, size: 30),
      ),
      loadingBuilder: (context, child, progress) =>
          progress == null ? child : Container(color: kPremiumHairline),
    );
  }
}

class ListingVideoPlayer extends StatefulWidget {
  /// Raw URL as the seller pasted it. The caller is expected to have
  /// already resolved a valid video id via youtubeVideoId(); this
  /// widget takes the id directly so it can never render a dead frame.
  final String videoId;

  const ListingVideoPlayer({super.key, required this.videoId});

  @override
  State<ListingVideoPlayer> createState() => _ListingVideoPlayerState();
}

class _ListingVideoPlayerState extends State<ListingVideoPlayer> {
  YoutubePlayerController? _controller;

  void _startPlayback() {
    if (_controller != null) return;
    final c = YoutubePlayerController.fromVideoId(
      videoId: widget.videoId,
      autoPlay: true,
      params: const YoutubePlayerParams(
        showControls: true,
        showFullscreenButton: true,
        // Keep related videos scoped to this channel where possible —
        // we don't want the player suggesting a competitor's shop at
        // the end of our seller's clip.
        strictRelatedVideos: true,
      ),
    );
    setState(() => _controller = c);
  }

  @override
  void dispose() {
    // Must be closed or the underlying WebView leaks — this sheet can
    // be opened and dismissed many times while browsing.
    _controller?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: AspectRatio(
        aspectRatio: 16 / 9,
        child: controller == null
            ? _buildThumbnail()
            : YoutubePlayer(controller: controller, aspectRatio: 16 / 9),
      ),
    );
  }

  /// Pre-play state: YouTube's free static thumbnail plus a play badge.
  /// hqdefault exists for every public video (unlike maxresdefault,
  /// which 404s on lower-resolution uploads and would leave a broken
  /// box), so this is the safe endpoint to depend on.
  Widget _buildThumbnail() {
    return GestureDetector(
      onTap: _startPlayback,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image.network(
            'https://img.youtube.com/vi/${widget.videoId}/hqdefault.jpg',
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) => Container(
              color: Colors.black87,
              alignment: Alignment.center,
              child: const Icon(Icons.videocam_off_rounded,
                  color: Colors.white38, size: 34),
            ),
            loadingBuilder: (context, child, progress) {
              if (progress == null) return child;
              return Container(color: Colors.black12);
            },
          ),
          // Scrim so the play badge stays legible over a bright frame.
          Container(color: Colors.black.withValues(alpha: 0.25)),
          Center(
            child: Container(
              width: 56,
              height: 56,
              decoration: const BoxDecoration(
                color: Color(0xFFFF0000),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.play_arrow_rounded,
                  color: Colors.white, size: 34),
            ),
          ),
          Positioned(
            left: 10,
            bottom: 10,
            child: Container(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                'Watch this phone in action',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

