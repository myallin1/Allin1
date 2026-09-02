// ================================================================
// ErodeOffersSection — "Erode Offers" tab inside the Rewards screen
// ================================================================
// Shows a live list of local shop offers (managed by admin via
// AdminErodeOffersScreen, stored in Firestore `erode_offers`
// collection). Tapping a card opens OfferDetailScreen with full
// shop details, a Call button, and a Location button that opens
// Google Maps in street-view mode at the shop's coordinates.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:youtube_player_iframe/youtube_player_iframe.dart';

import 'package:cached_network_image/cached_network_image.dart';

import '../services/cloudinary_upload_service.dart';
import '../services/hive_cache.dart';
import '../models/mobile_models.dart' show youtubeVideoId;
import '../services/migration_gate_service.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';
import '../widgets/premium_theme.dart';
import 'mobiles/listing_video_player.dart' show ListingVideoPlayer;
import '../services/firestore_usage_tracking.dart';

const Color _offerInk = Color(0xFF121A3D);
const Color _offerPink = Color(0xFFFF4FA3);
const Color _offerPurple = Color(0xFFB21FFF);
const Color _offerMuted = Color(0xFF6B7280);

/// A cached offer row. Firestore's own QueryDocumentSnapshot can't be
/// stored in Hive (it holds a live reference), so offers are flattened
/// to plain id+map pairs on the way into the cache and rehydrated on the
/// way out.
class _OfferRecord {
  const _OfferRecord({required this.id, required this.data});

  final String id;
  final Map<String, dynamic> data;
}

class ErodeOffersSection extends StatefulWidget {
  const ErodeOffersSection({super.key});

  @override
  State<ErodeOffersSection> createState() => _ErodeOffersSectionState();
}

class _ErodeOffersSectionState extends State<ErodeOffersSection> {
  // ================================================================
  // VERSION-GATED CACHE  (Aug 18 2026 — Nizam's "admin ping" model)
  // ================================================================
  // The TTL alone had one weakness and one cost:
  //   * an admin edit could sit invisible for up to an hour, and
  //   * every customer paid a full refetch each hour whether anything
  //     had changed or not.
  //
  // Now the admin's explicit "Publish Rewards" action bumps
  // rewardsVersion on system_settings/app_status, which
  // MigrationGateService ALREADY watches with a listener that exists
  // regardless of this feature. So:
  //
  //   version unchanged -> serve the Hive cache, ZERO Firestore reads,
  //                        no matter how many times the app is opened
  //   version changed   -> refetch once, re-cache, stamp the new version
  //
  // A customer who opens the app 10 times on a quiet day now costs 0
  // offer reads instead of up to 10 refetches. And because the
  // underlying listener is live, a publish reaches phones that already
  // have the app OPEN — the "ping" behaviour Nizam wanted — without a
  // single extra listener, connection, or collection.
  //
  // The 1-hour TTL is retained underneath as a safety net for the case
  // where an admin edits offers and forgets to press Publish.
  static const String _versionCacheKey = 'erode_offers_version';

  Future<List<_OfferRecord>?>? _future;
  int _lastAppliedVersion = -1;

  // Active inline video controllers, keyed by offerId. Capped at 3 to prevent OOM crashes on budget devices.
  final Map<String, YoutubePlayerController> _inlineControllers = {};
  // Tracks access order for Least Recently Used (LRU) eviction
  final List<String> _controllerAccessOrder = [];
  String? _currentlyPlayingId;

  @override
  void initState() {
    super.initState();
    _future = _loadOffers();
    // Mid-session publishes: the kill-switch listener notifies on any
    // app_status change, so a publish while the customer is browsing
    // refreshes the list without them doing anything.
    MigrationGateService.instance.addListener(_onGateChanged);
  }

  @override
  void dispose() {
    MigrationGateService.instance.removeListener(_onGateChanged);
    for (final controller in _inlineControllers.values) {
      try {
        controller.close();
      } catch (e) {
        debugPrint('Dispose pool controller failed: $e');
      }
    }
    _inlineControllers.clear();
    _controllerAccessOrder.clear();
    // Safety net (Aug 29 2026 review): if the customer leaves this whole
    // screen (back button, switch tabs) while a video was mid-fullscreen,
    // the exit-fullscreen branch of that controller's own listener never
    // gets a chance to run — it was still fullscreen when we just closed
    // it above. Without this, the rest of the app would stay stuck with
    // hidden system bars and a landscape-only preference forever.
    SystemChrome.setPreferredOrientations(
      const [DeviceOrientation.portraitUp],
    );
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  /// Pauses one card's controller without evicting it from the pool —
  /// used when a card scrolls off-screen (see [_OfferCardState.dispose]
  /// in _OfferCard below). Scrolling away should silence the video, not
  /// throw away the instant-replay cache the pool exists for.
  void _pauseInline(String offerId) {
    final controller = _inlineControllers[offerId];
    if (controller == null) return;
    try {
      controller.pauseVideo();
    } catch (e) {
      debugPrint('Scroll-away pause failed: $e');
    }
    if (_currentlyPlayingId == offerId) _currentlyPlayingId = null;
  }

  /// The close (X) button on an active inline player: pause and collapse
  /// back to the poster, but keep the controller warm in the pool so
  /// tapping play again is instant rather than a cold reload.
  void _closeInline(String offerId) {
    final controller = _inlineControllers[offerId];
    if (controller != null) {
      try {
        controller.pauseVideo();
      } catch (e) {
        debugPrint('Close-inline pause failed: $e');
      }
    }
    if (_currentlyPlayingId == offerId) _currentlyPlayingId = null;
    setState(() {});
  }

  void _playInline(String offerId, String videoId) {
    // 1. Auto-Pause (Single Sound Source): pause previously playing video
    if (_currentlyPlayingId != null && _currentlyPlayingId != offerId) {
      final activeController = _inlineControllers[_currentlyPlayingId];
      if (activeController != null) {
        try {
          activeController.pauseVideo();
        } catch (e) {
          debugPrint('Auto-pause failed: $e');
        }
      }
    }

    _currentlyPlayingId = offerId;

    // 2. Play immediately if already in cache pool
    if (_inlineControllers.containsKey(offerId)) {
      _controllerAccessOrder.remove(offerId);
      _controllerAccessOrder.add(offerId);
      final controller = _inlineControllers[offerId]!;
      try {
        controller.playVideo();
      } catch (e) {
        debugPrint('Resume video failed: $e');
      }
      setState(() {});
      return;
    }

    // 3. LRU Eviction: keep pool size capped at 3
    if (_inlineControllers.length >= 3) {
      final lruKey = _controllerAccessOrder.removeAt(0);
      final lruController = _inlineControllers.remove(lruKey);
      if (lruController != null) {
        try {
          lruController.close();
        } catch (e) {
          debugPrint('LRU controller eviction failed: $e');
        }
      }
    }

    // 4. Create new controller PAUSED, set portrait lock on fullscreen,
    // and start playback only once the modal/card has actually settled.
    //
    // FIX (Aug 29 2026 re-audit): this used to pass autoPlay: true, which
    // reintroduced a bug already found and fixed elsewhere in this same
    // codebase (see the Aug 28 2026 note in listing_video_player.dart) —
    // starting playback the instant the controller is created races the
    // platform view's surface attachment. YouTube's audio track needs no
    // surface and starts immediately; the video does, doesn't have one
    // yet, and arrives late — "audio plays before picture". Creating it
    // paused and starting after a settle delay is the same fix applied
    // here.
    final newController = YoutubePlayerController.fromVideoId(
      videoId: videoId,
      // ignore: avoid_redundant_argument_values
      autoPlay: false,
      params: const YoutubePlayerParams(
        showFullscreenButton: true,
        strictRelatedVideos: true,
        enableCaption: false,
      ),
    );

    newController.setFullScreenListener((isFullscreen) {
      SystemChrome.setPreferredOrientations(const [
        DeviceOrientation.portraitUp,
      ]);
      SystemChrome.setEnabledSystemUIMode(
        isFullscreen ? SystemUiMode.immersiveSticky : SystemUiMode.edgeToEdge,
      );
    });

    _inlineControllers[offerId] = newController;
    _controllerAccessOrder.add(offerId);
    setState(() {});

    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future<void>.delayed(const Duration(milliseconds: 120));
      // FIX (Aug 29 2026 re-re-audit): also bail if the customer closed
      // or switched away from this card within the 120ms settle delay.
      // The pool slot check alone wasn't enough — Close deliberately
      // leaves the controller in the pool (same object) so resuming it
      // later is instant, so "still the same controller" stays true even
      // after Close. Without this, tapping Close right after tapping
      // play made the video start itself back up a moment later.
      if (!mounted ||
          _inlineControllers[offerId] != newController ||
          _currentlyPlayingId != offerId) {
        return;
      }
      try {
        await newController.playVideo();
      } catch (e) {
        debugPrint('Inline autostart failed: $e');
      }
    });
  }

  void _onGateChanged() {
    final live = MigrationGateService.instance.rewardsVersion;
    // Only react to an actual version move. migrationUrl changes fire
    // this same callback and must not trigger a pointless refetch.
    if (live == _lastAppliedVersion || !mounted) return;
    setState(() => _future = _loadOffers());
  }

  Future<void> _refresh() async {
    final next = _loadOffers();
    if (mounted) setState(() => _future = next);
    await next;
  }

  /// Cache-first offers load, gated on [rewardsVersion]. Sorting stays
  /// client-side (newest first) — that was already required to avoid a
  /// composite index.
  Future<List<_OfferRecord>?> _loadOffers() async {
    // Compare the live published version against the one this device
    // last cached against. A mismatch is the ONLY thing that forces a
    // network refetch.
    final liveVersion = MigrationGateService.instance.rewardsVersion;
    final cachedVersion = await HiveCache.get<int>(_versionCacheKey) ?? -1;
    final versionChanged = liveVersion != cachedVersion;
    _lastAppliedVersion = liveVersion;

    final raw = await HiveCache.cachedFetch<List<dynamic>>(
      HiveCache.kErodeOffers,
      () async {
        final snap = await FirebaseFirestore.instance
            .collection('erode_offers')
            .where('active', isEqualTo: true)
            .trackedGet();
        // Stored as a plain List<Map> so it survives Hive serialization.
        // createdAt (a Timestamp) is converted to epoch millis for the
        // same reason, and used only for sorting.
        return snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          final ts = data['createdAt'];
          return <String, dynamic>{
            '__id': d.id,
            '__createdAtMs':
                ts is Timestamp ? ts.millisecondsSinceEpoch : 0,
            ...data..remove('createdAt'),
          };
        }).toList();
      },
      ttl: HiveCache.ttlErodeOffers,
      // The version bump is what makes a publish land immediately;
      // the TTL underneath is only the forgot-to-press-Publish net.
      forceRefresh: versionChanged,
    );

    // Stamp the version we just cached against — but ONLY after a
    // successful fetch, so a failed refetch (offline, quota) leaves the
    // old stamp in place and we retry next time instead of silently
    // pinning stale content to the new version forever.
    if (versionChanged && raw != null) {
      await HiveCache.put(
        _versionCacheKey,
        liveVersion,
        // Deliberately long-lived: this is a watermark, not content. If
        // it expired on its own it would force a pointless refetch.
        ttl: const Duration(days: 365),
      );
    }

    if (raw == null) return null;

    final records = raw
        .map((e) => Map<String, dynamic>.from(e as Map))
        .toList()
      ..sort((a, b) => ((b['__createdAtMs'] as int?) ?? 0)
          .compareTo((a['__createdAtMs'] as int?) ?? 0));

    return records
        .map((m) => _OfferRecord(
              id: (m['__id'] as String?) ?? '',
              data: Map<String, dynamic>.from(m)
                ..remove('__id')
                ..remove('__createdAtMs'),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    // CACHE-FIRST (Aug 11 2026 — Nizam's Spark read-budget hardening):
    // this was a live .snapshots() stream on a collection rendered on
    // the customer dashboard, i.e. loaded by every customer on nearly
    // every app open. A live stream bills per document delivered AND
    // re-bills whenever anything changes, so N offers x every open x
    // every customer came straight out of the 50K reads/day Spark
    // budget — for content that realistically changes once a week.
    // Now a one-shot .get() behind a 1-hour Hive cache: a customer
    // opening the app ten times in an hour costs ONE read instead of
    // ten streams. HiveCache.cachedFetch also serves stale data if the
    // fetch throws, so offers still render if we ever hit the daily
    // read ceiling. Admin edits show up within the hour (acceptable
    // for promo content — and admins can pull-to-refresh the dashboard
    // to force it sooner).
    return FutureBuilder<List<_OfferRecord>?>(
      future: _future,
      // FIX (root cause of "Could not load offers, please try again
      // later" — live bug, security rules were already correctly
      // deployed by this point): a Firestore query combining an
      // equality filter (.where('active', isEqualTo: true)) with an
      // .orderBy() on a DIFFERENT field (createdAt) requires a
      // composite index — Firestore does NOT auto-create these, unlike
      // single-field indexes. No such index existed for erode_offers
      // (confirmed: zero entries in firestore.indexes.json), so this
      // stream was throwing `[cloud_firestore/failed-precondition] The
      // query requires an index...` on every single load — surfacing
      // as snapshot.hasError below, which is exactly this UI's "Could
      // not load offers" message. This is a DIFFERENT failure mode
      // from the earlier rules-deployment bug (permission-denied vs.
      // failed-precondition) that happened to produce the identical
      // symptom. Dropping .orderBy() here — keeping only the
      // single-field .where('active', ...) filter, which Firestore
      // always auto-indexes — removes the composite-index requirement
      // entirely, so this feature can never break this way again
      // regardless of whether an index gets deployed. Sorting is done
      // client-side instead, right after the docs list is built below.
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 60),
            child: Center(child: CircularProgressIndicator(color: _offerPink)),
          );
        }
        if (snapshot.hasError) {
          // Was previously silent — no debugPrint at all — so a future
          // regression here would be just as invisible as this one was.
          debugPrint('ErodeOffersSection: stream error -> ${snapshot.error}');
          return _emptyState(
            icon: Icons.error_outline_rounded,
            title: 'Could not load offers',
            subtitle: 'Please try again in a moment.',
          );
        }
        final docs = snapshot.data ?? const <_OfferRecord>[];
        if (docs.isEmpty) {
          return _emptyState(
            icon: Icons.storefront_rounded,
            title: 'No offers right now',
            subtitle: 'Check back soon — Erode shop offers appear here.',
          );
        }
        // VIRTUALIZED (Aug 18 2026 — CTO performance review). This was
        // a Column with `...docs.map(...)`, which builds EVERY offer
        // card up-front regardless of how many are off-screen. That was
        // survivable for image-only cards, but it is the worst possible
        // container to later put video embeds in — N offers would mean
        // N players alive at once. ListView.builder builds only what is
        // visible (plus a small cache extent), so the cost stops
        // scaling with the number of offers.
        //
        // NOTE this list owns its own scrolling — see rewards_screen.dart,
        // which gives this tab an Expanded slot instead of nesting it in
        // a SingleChildScrollView. That matters: a ListView inside
        // another scrollable needs shrinkWrap: true, which builds all
        // children anyway and would have made this change cosmetic.
        //
        // Pull-to-refresh is the manual escape hatch if an admin
        // forgets to press Publish.
        return RefreshIndicator(
          color: _offerPink,
          onRefresh: _refresh,
          child: ListView.builder(
            physics: const AlwaysScrollableScrollPhysics(
              parent: BouncingScrollPhysics(),
            ),
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 40),
            // +1 for the gradient banner, kept inside the list so it
            // scrolls away naturally instead of eating permanent space.
            itemCount: docs.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _buildBanner();
              final doc = docs[index - 1];
              final videoId = youtubeVideoId(doc.data['videoUrl'] as String?);
              return Padding(
                key: ValueKey(doc.id),
                padding: const EdgeInsets.only(bottom: 14),
                child: _OfferCard(
                  offerId: doc.id,
                  data: doc.data,
                  // FIX (Aug 29 2026 re-re-audit): must gate on
                  // "this offer is the one actively shown", not merely
                  // "a warm controller exists for it somewhere in the
                  // pool" — those are different things by design. Close
                  // (X) deliberately keeps the controller warm in
                  // _inlineControllers for instant resume rather than
                  // disposing it, so checking pool membership alone
                  // meant the poster could never come back after Close
                  // was tapped: the card kept rendering the (now paused)
                  // YoutubePlayer forever. Gating on _currentlyPlayingId
                  // instead means Close only stops SHOWING the player;
                  // the pool entry it leaves behind is exactly what
                  // makes reopening the same video instant.
                  inlineController: _currentlyPlayingId == doc.id
                      ? _inlineControllers[doc.id]
                      : null,
                  onPlayTapped: videoId == null
                      ? null
                      : () => _playInline(doc.id, videoId),
                  onClosePlayer: () => _closeInline(doc.id),
                  onScrolledAway: () => _pauseInline(doc.id),
                ),
              );
            },
          ),
        );
      },
    );
  }

  Widget _buildBanner() {
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_offerPurple, _offerPink],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(24),
        ),
        child: Row(
          children: [
            const Icon(Icons.local_offer_rounded,
                color: Colors.white, size: 26),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Live offers from shops around Erode',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 12,
                  fontWeight: FontWeight.w800,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _emptyState({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 50, horizontal: 20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _offerPink.withValues(alpha: 0.15)),
      ),
      child: Column(
        children: [
          Icon(icon, color: _offerMuted, size: 40),
          const SizedBox(height: 12),
          Text(
            title,
            style: GoogleFonts.outfit(color: _offerInk, fontSize: 14, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: _offerMuted, fontSize: 11, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatefulWidget {
  final String offerId;
  final Map<String, dynamic> data;
  final YoutubePlayerController? inlineController;
  final VoidCallback? onPlayTapped;
  final VoidCallback? onClosePlayer;
  final VoidCallback? onScrolledAway;

  const _OfferCard({
    required this.offerId,
    required this.data,
    this.inlineController,
    this.onPlayTapped,
    this.onClosePlayer,
    this.onScrolledAway,
    super.key,
  });

  @override
  State<_OfferCard> createState() => _OfferCardState();
}

class _OfferCardState extends State<_OfferCard> {
  @override
  void dispose() {
    // FIX (Aug 29 2026 re-audit — "ghost audio" when a card scrolls off
    // screen): ListView.builder disposes an item's Element once it moves
    // far enough outside the cache extent, but the underlying
    // YoutubePlayerController lives one level up in the pool, deliberately
    // kept alive for instant replay. Nothing was telling THAT controller
    // to stop when THIS widget went away, so a playing video kept
    // making sound long after it scrolled out of sight. This is called
    // with the [key]'d offerId still correctly attached to this element
    // (see the ValueKey on each list item) so scroll reordering can never
    // pause the wrong card.
    if (widget.inlineController != null) {
      widget.onScrolledAway?.call();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final offerId = widget.offerId;
    final data = widget.data;
    final inlineController = widget.inlineController;
    final onPlayTapped = widget.onPlayTapped;
    final onClosePlayer = widget.onClosePlayer;
    final shopName = (data['shopName'] as String?) ?? 'Shop';
    final offerPercent = data['offerPercent'];
    final validTill = data['validTill'];
    final imageUrl = data['imageUrl'] as String?;
    final videoId = youtubeVideoId(data['videoUrl'] as String?);
    final hasImage = imageUrl != null && imageUrl.isNotEmpty;

    // VIP PASS CARD (Aug 18 2026 — Founder's premium brief). The
    // admin's uploaded offer image becomes a full-bleed poster with a
    // bottom scrim, so the shop name and discount read as engraved on
    // the artwork rather than sitting in a separate text strip.
    //
    // COST NOTE: this is still the SAME single cached image request as
    // the old 56x56 thumbnail — just requested at a poster-appropriate
    // width. CachedNetworkImageProvider + optimizedUrl() are retained
    // exactly as the bandwidth audit left them; the redesign spends
    // pixels, not extra network calls.
    // FIX (Aug 29 2026 — "card tap pannuna screen apdiye iruku"): a plain
    // Text's RenderObject always claims a hit test wherever its bounding
    // box is (RenderParagraph.hitTestSelf is unconditionally true — it
    // has to be, to support tappable TextSpans). This card is full of
    // Text (shop name, valid-till chip, footer line), so when PremiumCard's
    // whole-card InkWell sat BEHIND the card content, a tap landing on any
    // of that text got "claimed" by the Text and never reached the InkWell
    // underneath — the screen looked completely unresponsive. Nothing was
    // actually broken about the InkWell; it just never got a turn.
    //
    // Fix: don't let PremiumCard wrap this in its own InkWell at all.
    // Build the tap layering explicitly instead — whole-card InkWell ABOVE
    // the (non-interactive) content, and the WATCH OFFER badge's own
    // opaque GestureDetector on top of THAT, in its own small corner. Now
    // every point either belongs to the badge or falls straight through
    // to the InkWell — no Text in between to eat it.
    return Stack(
      children: [
        PremiumCard(
          radius: kRadiusLg,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SizedBox(
                height: 140,
                width: double.infinity,
                // When playing, this box stays an EMPTY placeholder — a
                // spacer reserving the layout height the video needs.
                // The real YoutubePlayer is painted separately, outside
                // PremiumCard's clip (see the Positioned sibling in the
                // outer Stack below and the note next to it for why.
                child: inlineController != null
                    ? const SizedBox.shrink()
                    : Stack(
                  fit: StackFit.expand,
                  children: [
                      if (hasImage)
                        Container(
                          color: const Color(0xFFF3E7EF), // Neutral backing for letterbox bars
                          child: Image(
                            image: CachedNetworkImageProvider(
                              CloudinaryUploadService.optimizedUrl(imageUrl,
                                  width: 720),
                            ),
                            fit: BoxFit.contain, // Changed to contain to show full image
                            errorBuilder: (_, __, ___) => _posterFallback(offerPercent),
                          ),
                        )
                      else
                        _posterFallback(offerPercent),

                      // Scrim so white text stays readable over any photo.
                      const DecoratedBox(
                        decoration: BoxDecoration(gradient: kImageScrim),
                        child: SizedBox.expand(),
                      ),

                      if (offerPercent != null)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 12, vertical: 7),
                            decoration: BoxDecoration(
                              gradient: kBrandGradient,
                              borderRadius: BorderRadius.circular(kRadiusSm),
                              boxShadow: glowShadow(kPremiumPink, strength: 0.7),
                            ),
                            child: Text(
                              '$offerPercent% OFF',
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.2,
                              ),
                            ),
                          ),
                        ),

                      // WATCH OFFER badge display ONLY here — the real tap
                      // target for it lives in the outer Stack below (see the
                      // "Aug 29 2026" note above _OfferCard.build), painted on
                      // top of the whole-card InkWell so it wins that corner
                      // without any Text in this box being able to swallow it.
                      if (videoId != null)
                        const Positioned(
                          top: 12,
                          right: 12,
                          child: IgnorePointer(
                            child: VideoGlowBadge(
                                label: 'WATCH OFFER', compact: false),
                          ),
                        ),

                      Positioned(
                        left: 16,
                        right: 16,
                        bottom: 14,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              shopName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontSize: 17,
                                fontWeight: FontWeight.w900,
                                letterSpacing: -0.3,
                                shadows: const [
                                  Shadow(color: Colors.black54, blurRadius: 8),
                                ],
                              ),
                            ),
                            const SizedBox(height: 4),
                            GlassChip(
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.schedule_rounded,
                                      color: Colors.white, size: 12),
                                  const SizedBox(width: 5),
                                  Text(
                                    _formatValidTill(validTill),
                                    style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 9,
                                      fontWeight: FontWeight.w700,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                  ],
                ),
              ),

              // Footer strip — the "pass" tear-off edge.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            OfferDetailScreen(offerId: offerId, data: data)),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      Container(
                        width: 26,
                        height: 26,
                        decoration: BoxDecoration(
                          color: kPremiumPink.withValues(alpha: 0.10),
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.local_offer_rounded,
                            color: kPremiumPink, size: 13),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          // While playing inline, the poster (with the
                          // shop name overlay) is replaced by the raw
                          // YouTube iframe \u2014 this line becomes the only
                          // place left showing WHICH shop's offer is
                          // playing, so it needs to actually say so.
                          inlineController != null
                              ? '$shopName \u00b7 ${_formatValidTill(validTill)}'
                              : videoId != null
                                  ? 'Tap to view details \u00b7 video available'
                                  : 'Tap to view shop details',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: premiumBody(size: 9.5),
                        ),
                      ),
                      const Icon(Icons.arrow_forward_ios_rounded,
                          color: kPremiumMuted, size: 11),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
        // Whole-card tap target, ABOVE the (non-interactive) content so no
        // Text inside it can ever swallow the tap before this sees it.
        // Disabled when playing inline to allow player controls interaction.
        if (inlineController == null)
          Positioned.fill(
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(kRadiusLg),
                splashColor: kPremiumPink.withValues(alpha: 0.08),
                highlightColor: kPremiumPink.withValues(alpha: 0.04),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                        builder: (_) =>
                            OfferDetailScreen(offerId: offerId, data: data)),
                  );
                },
              ),
            ),
          ),
        // The REAL WATCH OFFER tap target — opaque so its whole padded
        // area (not just the icon/text glyphs) is tappable, and on top
        // of the whole-card InkWell so it wins in this corner only.
        if (videoId != null && inlineController == null)
          Positioned(
            top: 12,
            right: 12,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onPlayTapped,
              child: const VideoGlowBadge(
                  label: 'WATCH OFFER', compact: false),
            ),
          ),
        // FIX (Aug 31 2026 re-audit): the YoutubePlayer must NOT sit
        // inside PremiumCard's Container — that Container clips with
        // Clip.antiAlias, and on Flutter Web the player is a real DOM
        // iframe (a platform view). A clip ancestor forces a platform
        // view onto its own composited layer, which is the exact same
        // "player fails to render under CanvasKit" bug already found and
        // fixed once in listing_video_player.dart's fullscreen sheet —
        // reusing the fix here rather than rediscovering it the hard way
        // on web. Painting it as a sibling here, above PremiumCard but
        // below nothing else, means it overlaps exactly the 140px
        // placeholder box left empty above — square top corners instead
        // of rounded ones, the same trade-off that earlier fix accepted.
        if (inlineController != null)
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 140,
            child: Stack(
              fit: StackFit.expand,
              children: [
                YoutubePlayer(
                  controller: inlineController,
                  aspectRatio: 16 / 9,
                ),
                // Close (X) — collapses back to the poster without
                // throwing the controller out of the pool, so reopening
                // this same video is instant.
                Positioned(
                  top: 8,
                  right: 8,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onClosePlayer,
                    child: Container(
                      padding: const EdgeInsets.all(5),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.55),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white, size: 16),
                    ),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  /// Shown when an offer has no image, or its image fails to load.
  /// Costs nothing — pure gradient + the discount number.
  Widget _posterFallback(Object? offerPercent) {
    return DecoratedBox(
      decoration: const BoxDecoration(gradient: kBrandGradient),
      child: Center(
        child: Text(
          offerPercent != null ? '$offerPercent%' : 'OFFER',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 34,
            letterSpacing: -1,
          ),
        ),
      ),
    );
  }

  String _formatValidTill(validTill) {
    if (validTill is Timestamp) {
      final d = validTill.toDate();
      return 'Valid till ${d.day}/${d.month}/${d.year}';
    }
    if (validTill is String && validTill.isNotEmpty) {
      return 'Valid till $validTill';
    }
    return 'Limited period offer';
  }
}

class OfferDetailScreen extends StatelessWidget {
  final String offerId;
  final Map<String, dynamic> data;

  const OfferDetailScreen({required this.offerId, required this.data, super.key});

  @override
  Widget build(BuildContext context) {
    final shopName = (data['shopName'] as String?) ?? 'Shop';
    final offerPercent = data['offerPercent'];
    final validTill = data['validTill'];
    final address = (data['address'] as String?) ?? '';
    final phone = (data['phone'] as String?) ?? '';
    final lat = data['lat'];
    final lng = data['lng'];
    final imageUrl = data['imageUrl'] as String?;
    final videoId = youtubeVideoId(data['videoUrl'] as String?);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF6FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: _offerInk),
        title: Text('Offer Details', style: GoogleFonts.outfit(color: _offerInk, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // EMBEDDED at the top, not a pop-up (Aug 29 2026 — CTO
            // review, "video player directly at the top of the screen
            // instead of a pop-up bottom sheet, shop details below it").
            // ListingVideoPlayer is the same lazy widget the Mobile Hub
            // uses: a thumbnail until tapped, one real player built only
            // then, closed on dispose — one detail screen open at a
            // time, so this never risks the "N players alive" memory
            // problem a scrolling list of these would.
            if (videoId != null) ...[
              ListingVideoPlayer(videoId: videoId),
              const SizedBox(height: 16),
            ],
            // NEW (CTO mandate — Erode Offers image + map pin): shows
            // the shop photo admin uploaded, so the customer can
            // recognise the shop's storefront on sight. Only rendered
            // when an offer actually has one — older offers created
            // before this feature simply skip straight to the gradient
            // banner below.
            // FULL-SIZE OFFER IMAGE (Aug 19 2026, Nizam: "offer image
            // full size visible aganum").
            //
            // Was a fixed 180px box with BoxFit.cover — which CROPS.
            // On a tall poster (the usual shape a shop sends on
            // WhatsApp) that meant the customer saw a horizontal slice
            // out of the middle and never the offer text printed on it.
            // The whole point of the image was lost.
            //
            // Now BoxFit.contain inside a generous max height: the
            // image is shown WHOLE at its own aspect ratio, big, with
            // nothing cut off. 62% of screen height is the ceiling so a
            // very tall poster still leaves the details below it
            // visible without scrolling being the only way to know they
            // exist.
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(
                    maxHeight: MediaQuery.of(context).size.height * 0.62,
                  ),
                  // Neutral backing so a portrait poster's letterbox
                  // bars read as a deliberate frame, not a gap.
                  color: const Color(0xFFF3E7EF),
                  child: CachedCloudImage(
                    imageUrl,
                    fit: BoxFit.contain,
                    errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                  ),
                ),
              ),
            if (imageUrl != null && imageUrl.isNotEmpty) const SizedBox(height: 16),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(22),
              decoration: BoxDecoration(
                gradient: const LinearGradient(colors: [_offerPurple, _offerPink]),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    shopName,
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 19, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 10),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(
                      offerPercent != null ? '$offerPercent% OFF' : 'SPECIAL OFFER',
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 9),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            _detailTile(
              icon: Icons.event_available_rounded,
              label: 'Valid Till',
              value: _formatValidTillFull(validTill),
            ),
            const SizedBox(height: 12),
            _detailTile(
              icon: Icons.location_on_rounded,
              label: 'Address',
              value: address.isNotEmpty ? address : 'Not provided',
            ),
            const SizedBox(height: 24),
            Row(
              children: [
                if (phone.isNotEmpty)
                  Expanded(
                    child: _actionButton(
                      icon: Icons.call_rounded,
                      label: 'Call Shop',
                      colors: const [Color(0xFF00C853), Color(0xFF00A843)],
                      onTap: () => _launchPhone(phone),
                    ),
                  ),
                if (phone.isNotEmpty && lat != null && lng != null) const SizedBox(width: 12),
                if (lat != null && lng != null)
                  Expanded(
                    child: _actionButton(
                      icon: Icons.map_rounded,
                      label: 'View Location',
                      colors: const [_offerPurple, _offerPink],
                      onTap: () => _launchStreetView(lat, lng),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  String _formatValidTillFull(validTill) {
    if (validTill is Timestamp) {
      final d = validTill.toDate();
      return '${d.day}/${d.month}/${d.year}';
    }
    if (validTill is String && validTill.isNotEmpty) return validTill;
    return 'Limited period offer';
  }

  Widget _detailTile({required IconData icon, required String label, required String value}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _offerPink.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Icon(icon, color: _offerPink, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: GoogleFonts.outfit(color: _offerMuted, fontSize: 7, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(value, style: GoogleFonts.outfit(color: _offerInk, fontSize: 9.5, fontWeight: FontWeight.w700)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _actionButton({
    required IconData icon,
    required String label,
    required List<Color> colors,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: colors),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          children: [
            Icon(icon, color: Colors.white, size: 22),
            const SizedBox(height: 6),
            Text(label, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 8)),
          ],
        ),
      ),
    );
  }

  Future<void> _launchPhone(String phone) async {
    final uri = Uri(scheme: 'tel', path: phone);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  Future<void> _launchStreetView(lat, lng) async {
    final uri = Uri.parse('https://www.google.com/maps?layer=c&cbll=$lat,$lng');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('offerId', offerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
  }
}

