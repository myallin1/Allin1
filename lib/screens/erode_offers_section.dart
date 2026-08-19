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

import 'package:cached_network_image/cached_network_image.dart';

import '../services/cloudinary_upload_service.dart';
import '../services/hive_cache.dart';
import '../models/mobile_models.dart' show youtubeVideoId;
import '../services/migration_gate_service.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';
import '../widgets/premium_theme.dart';
import 'mobiles/listing_video_player.dart' show showPremiumVideoModal;

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
    super.dispose();
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
            .get();
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
              return Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _OfferCard(offerId: doc.id, data: doc.data),
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
        padding: const EdgeInsets.all(18),
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
                color: Colors.white, size: 30),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Live offers from shops around Erode',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 14,
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
            style: GoogleFonts.outfit(color: _offerInk, fontSize: 16, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(color: _offerMuted, fontSize: 13, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _OfferCard extends StatelessWidget {
  final String offerId;
  final Map<String, dynamic> data;

  const _OfferCard({required this.offerId, required this.data});

  @override
  Widget build(BuildContext context) {
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
    return PremiumCard(
      radius: kRadiusLg,
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => OfferDetailScreen(offerId: offerId, data: data)),
        );
      },
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            height: 156,
            width: double.infinity,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasImage)
                  Image(
                    image: CachedNetworkImageProvider(
                      CloudinaryUploadService.optimizedUrl(imageUrl,
                          width: 720),
                    ),
                    fit: BoxFit.contain, // Changed to contain to show full image
                    errorBuilder: (_, __, ___) => _posterFallback(offerPercent),
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
                          fontSize: 13,
                          fontWeight: FontWeight.w900,
                          letterSpacing: -0.2,
                        ),
                      ),
                    ),
                  ),

                // WATCH OFFER — only when the admin actually saved a
                // valid link. Tapping it opens the shared lazy modal
                // player; nothing heavier than this poster image is
                // ever built while scrolling.
                if (videoId != null)
                  Positioned(
                    top: 12,
                    right: 12,
                    child: GestureDetector(
                      onTap: () => showPremiumVideoModal(
                        context,
                        videoId: videoId,
                        title: shopName,
                        subtitle: _formatValidTill(validTill),
                      ),
                      child: const VideoGlowBadge(
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
                          fontSize: 19,
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
                                fontSize: 11,
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
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
            child: Row(
              children: [
                Container(
                  width: 30,
                  height: 30,
                  decoration: BoxDecoration(
                    color: kPremiumPink.withValues(alpha: 0.10),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.local_offer_rounded,
                      color: kPremiumPink, size: 15),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    videoId != null
                        ? 'Tap to view details \u00b7 video available'
                        : 'Tap to view shop details',
                    style: premiumBody(size: 11.5),
                  ),
                ),
                const Icon(Icons.arrow_forward_ios_rounded,
                    color: kPremiumMuted, size: 13),
              ],
            ),
          ),
        ],
      ),
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('offerId', offerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
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
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900),
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
                      style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11),
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
                Text(label, style: GoogleFonts.outfit(color: _offerMuted, fontSize: 9, fontWeight: FontWeight.w700)),
                const SizedBox(height: 3),
                Text(value, style: GoogleFonts.outfit(color: _offerInk, fontSize: 11.5, fontWeight: FontWeight.w700)),
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
            Text(label, style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
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

