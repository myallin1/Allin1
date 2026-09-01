// ================================================================
// MobileListingsTab — the New / Used browse grids
// ================================================================
// One widget serves both tabs (condition: 'new' | 'used') because the
// grid, filtering, and enquiry flow are identical; only the image
// source and a few badges differ. Keeping it as one widget means a fix
// to the buy flow can't drift between the two tabs.
//
// IMAGE SOURCE — the cost-critical difference between the two:
//   NEW  → shared catalog image (one Cloudinary asset per MODEL, reused
//          by every seller listing it). A seller uploading nothing
//          still gets a proper photo, at zero storage cost to us.
//   USED → the seller's own photo of the actual unit. A stock image
//          would misrepresent a second-hand phone's condition, so this
//          is the one place a per-listing upload is genuinely required.
//   Neither ever falls back to a scraped third-party URL — no photo
//   means MobilePhotoFallback, which is a local icon and costs nothing.
//
// LOADING — one-shot fetch + pull-to-refresh, not a live listener.
// See the header of mobile_hub_screen.dart for why.
// ================================================================

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart' show DocumentSnapshot;
import 'package:firebase_auth/firebase_auth.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/mobile_models.dart';
import '../../services/auth_prompt_service.dart';
import '../../services/auth_service.dart';
import '../../services/mobile_catalog_service.dart';
import '../../services/mobile_listing_service.dart';
import '../../services/service_request_service.dart';
import '../../widgets/cached_cloud_image.dart';
import '../service_request_tracking_screen.dart';
import '../../widgets/premium_theme.dart';
import 'listing_video_player.dart';
import 'mobile_hub_screen.dart';
import 'sell_your_phone_sheet.dart';

class MobileListingsTab extends StatefulWidget {
  /// 'new' or 'used' — see MobileCondition.
  final String condition;

  const MobileListingsTab({super.key, required this.condition});

  @override
  State<MobileListingsTab> createState() => _MobileListingsTabState();
}

class _MobileListingsTabState extends State<MobileListingsTab>
    with AutomaticKeepAliveClientMixin {
  final MobileListingService _service = MobileListingService();

  List<MobileListing> _all = const [];
  bool _loading = true;
  String? _error;
  String _brandFilter = '';
  String _search = '';

  // ── PAGINATION (Aug 19 2026, CTO audit) ────────────────────────
  // The cursor for the next page, plus the two flags that stop us from
  // firing overlapping requests. `_loadingMore` is what makes the
  // scroll listener idempotent: it fires on every scroll frame near the
  // bottom, so without this guard one flick would launch a dozen
  // identical queries and pay for every one of them.
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _hasMore = true;
  bool _loadingMore = false;
  final ScrollController _scrollCtrl = ScrollController();

  bool get _isUsed => widget.condition == MobileCondition.used;

  // Keep the fetched list alive across tab switches inside the
  // IndexedStack — otherwise every switch back would re-run the query
  // and re-spend reads for data we already have.
  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    _scrollCtrl.addListener(_onScroll);
    _load();
  }

  @override
  void dispose() {
    _scrollCtrl
      ..removeListener(_onScroll)
      ..dispose();
    super.dispose();
  }

  /// Prefetches the next page while the customer is still ~600px from
  /// the bottom, so the grid keeps flowing and the loader is rarely
  /// seen. All the "don't fire twice" logic lives in _loadMore.
  void _onScroll() {
    if (!_scrollCtrl.hasClients) return;
    final pos = _scrollCtrl.position;
    if (pos.pixels >= pos.maxScrollExtent - 600) {
      _loadMore();
    }
  }

  /// Full reload — also used by pull-to-refresh, which is why it resets
  /// the cursor. Forgetting that reset would make a refresh append page
  /// 2 onto a stale page 1 instead of starting over.
  Future<void> _load() async {
    if (mounted) setState(() {
      _loading = true;
      _error = null;
      _cursor = null;
      _hasMore = true;
    });
    try {
      await MobileCatalogService.instance.ensureLoaded();
      final page =
          await _service.fetchListingsPage(condition: widget.condition);
      if (!mounted) return;
      setState(() {
        _all = page.items;
        _cursor = page.lastDoc;
        _hasMore = page.hasMore;
        _loading = false;
      });
    } catch (e) {
      // DIAGNOSTIC (Aug 19 2026, Nizam: "mobile page la onnume ila").
      // This catch used to collapse EVERY failure into one friendly
      // sentence, which is exactly why an empty Mobile Hub looked
      // identical to "no seller has listed a phone yet" — and the real
      // cause went unseen for days.
      //
      // The real cause was a MISSING COLLECTION-GROUP INDEX. Firestore
      // auto-creates single-field indexes at COLLECTION scope only;
      // fetchListings() runs collectionGroup('mobile_listings')
      // .where('condition', ...), which needs a COLLECTION_GROUP-scoped
      // index that must be declared explicitly. Without it every read
      // throws FAILED_PRECONDITION before a single doc comes back.
      // Now declared in firestore.indexes.json under fieldOverrides —
      // deploy with `firebase deploy --only firestore:indexes`.
      //
      // Logging the raw error costs nothing in release (debugPrint is
      // stripped) and turns the next occurrence into a 10-second fix.
      debugPrint('❌ Mobile Hub load failed (${widget.condition}): $e');
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString().contains('failed-precondition') ||
                e.toString().contains('requires an index')
            ? 'Phone listings are still being set up. Please try again shortly.'
            : 'Could not load phones right now. Pull down to retry.';
      });
    }
  }

  /// Appends the next page. Silent on failure by design: the customer
  /// already has results on screen, and throwing a red error banner over
  /// a working grid because page 4 timed out would be worse than simply
  /// letting them retry by scrolling again.
  Future<void> _loadMore() async {
    if (_loadingMore || !_hasMore || _loading || _cursor == null) return;
    setState(() => _loadingMore = true);
    try {
      final page = await _service.fetchListingsPage(
        condition: widget.condition,
        startAfter: _cursor,
      );
      if (!mounted) return;
      setState(() {
        _all = [..._all, ...page.items];
        _cursor = page.lastDoc ?? _cursor;
        _hasMore = page.hasMore;
        _loadingMore = false;
      });
    } catch (e) {
      debugPrint('❌ Mobile Hub page load failed: $e');
      if (!mounted) return;
      // _hasMore stays true so a later scroll can retry.
      setState(() => _loadingMore = false);
    }
  }

  List<MobileListing> get _visible {
    final q = _search.trim().toLowerCase();
    return _all.where((l) {
      if (_brandFilter.isNotEmpty && l.brand != _brandFilter) return false;
      if (q.isEmpty) return true;
      return l.displayName.toLowerCase().contains(q) ||
          l.sellerName.toLowerCase().contains(q);
    }).toList();
  }

  /// Brands that actually have stock right now — no point offering a
  /// filter chip that leads to an empty grid.
  List<String> get _availableBrands {
    final set = <String>{};
    for (final l in _all) {
      if (l.brand.isNotEmpty) set.add(l.brand);
    }
    final list = set.toList()..sort();
    return list;
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return Column(
      children: [
        MobileHubHeader(
          title: _isUsed ? 'Used Mobiles' : 'New Mobiles',
          subtitle: _isUsed
              ? 'Verified second-hand phones from Erode shops'
              : 'Best offers from mobile shops near you',
          trailing: IconButton(
            icon: const Icon(Icons.refresh_rounded, color: Colors.white),
            tooltip: 'Refresh',
            onPressed: _loading ? null : _load,
          ),
        ),
        _buildSearchBar(),
        if (_availableBrands.isNotEmpty) _buildBrandChips(),
        if (_isUsed) _buildSellYourPhoneBanner(),
        Expanded(child: _buildBody()),
      ],
    );
  }

  Widget _buildSearchBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
      child: TextField(
        onChanged: (v) => setState(() => _search = v),
        style: GoogleFonts.outfit(color: kMobText, fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Search phone or shop…',
          hintStyle: GoogleFonts.outfit(color: kMobMuted, fontSize: 13),
          prefixIcon: const Icon(Icons.search_rounded, color: kMobMuted),
          filled: true,
          fillColor: kMobSurface,
          contentPadding: const EdgeInsets.symmetric(vertical: 4),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kMobBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kMobBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: kMobPink),
          ),
        ),
      ),
    );
  }

  Widget _buildBrandChips() {
    final brands = _availableBrands;
    return SizedBox(
      height: 38,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: brands.length + 1,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final isAll = i == 0;
          final brand = isAll ? '' : brands[i - 1];
          final active = _brandFilter == brand;
          return GestureDetector(
            onTap: () => setState(() => _brandFilter = brand),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: active ? kMobPink : kMobSurface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: active ? kMobPink : kMobBorder),
              ),
              child: Text(
                isAll ? 'All' : brand,
                style: GoogleFonts.outfit(
                  color: active ? Colors.white : kMobText,
                  fontSize: 12,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  /// Used tab only — the "customer can submit their old phone" half of
  /// the flow. Routes through the existing electronics_service pipeline
  /// as an enquiry, so it needs no new backend.
  Widget _buildSellYourPhoneBanner() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 2),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: () => showSellYourPhoneSheet(context),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          decoration: BoxDecoration(
            color: kMobGold.withValues(alpha: 0.10),
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: kMobGold.withValues(alpha: 0.35)),
          ),
          child: Row(
            children: [
              const Icon(Icons.sell_rounded, color: kMobGold, size: 22),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Sell your old phone',
                      style: GoogleFonts.outfit(
                        color: kMobText,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      'Send us the details — we\'ll quote you a price',
                      style: GoogleFonts.outfit(
                          color: kMobMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              const Icon(Icons.chevron_right_rounded, color: kMobMuted),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(
        child: CircularProgressIndicator(color: kMobPink, strokeWidth: 2),
      );
    }

    final items = _visible;

    // RefreshIndicator needs a scrollable child even when empty, hence
    // the ListView wrapper on the empty state.
    if (items.isEmpty) {
      return RefreshIndicator(
        color: kMobPink,
        onRefresh: _load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          children: [
            const SizedBox(height: 60),
            Icon(
              _error != null
                  ? Icons.cloud_off_rounded
                  : Icons.smartphone_rounded,
              color: kMobMuted,
              size: 56,
            ),
            const SizedBox(height: 14),
            Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 40),
                child: Text(
                  _error ??
                      (_all.isEmpty
                          ? (_isUsed
                              ? 'No used phones listed yet. Check back soon.'
                              : 'No phones listed yet. Check back soon.')
                          : 'No phones match your search.'),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: kMobMuted, fontSize: 13),
                ),
              ),
            ),
          ],
        ),
      );
    }

    // The grid and the "loading more" footer are separate slivers rather
    // than a fake extra grid cell — a spinner squeezed into a 0.62
    // aspect-ratio tile would be badly distorted, and it would also
    // break the two-column rhythm on the last row.
    return RefreshIndicator(
      color: kMobPink,
      onRefresh: _load,
      child: CustomScrollView(
        controller: _scrollCtrl,
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
            sliver: SliverGrid(
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount:
                    MediaQuery.of(context).size.width > 600 ? 3 : 2,
                childAspectRatio: 0.62,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
              delegate: SliverChildBuilderDelegate(
                (context, i) => _MobileCard(
                  listing: items[i],
                  onTap: () => _openListing(items[i]),
                  onPlayVideo: () => _playVideo(items[i]),
                ),
                childCount: items.length,
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 16, 12, 24),
              child: Center(
                child: _loadingMore
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: kMobPink,
                          strokeWidth: 2,
                        ),
                      )
                    // Only claim "that's everything" once the server has
                    // actually said so AND the customer isn't filtering
                    // — with a search active, the end of the loaded set
                    // is not the end of the catalog.
                    : (!_hasMore &&
                            _search.trim().isEmpty &&
                            _brandFilter.isEmpty &&
                            items.length > 6)
                        ? Text(
                            "That's all the phones for now",
                            style: GoogleFonts.outfit(
                              color: kMobMuted,
                              fontSize: 11.5,
                            ),
                          )
                        : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Straight to the player, bypassing the detail sheet. Still lazy —
  /// showPremiumVideoModal builds the controller only once the sheet
  /// itself is constructed, i.e. after this tap.
  void _playVideo(MobileListing listing) {
    final id = youtubeVideoId(listing.youtubeUrl);
    if (id == null) return;
    showPremiumVideoModal(
      context,
      videoId: id,
      title: listing.displayName,
      subtitle: listing.sellerName,
    );
  }

  void _openListing(MobileListing listing) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ListingDetailSheet(
        listing: listing,
        onEnquire: () => _sendBuyEnquiry(listing),
      ),
    );
  }

  /// Buy enquiry. Reuses the live 'electronics_service' pipeline rather
  /// than inventing a requestType, so it inherits the existing hero
  /// dispatch, admin visibility, tracking screen and Firestore rules
  /// with zero backend change. The details map carries the listing
  /// context — `service_requests` create rules put no hasOnly()
  /// restriction on `details`, so new keys are safe to add.
  Future<void> _sendBuyEnquiry(MobileListing listing) async {
    if (!await requireRealAuth(context,
        reason: 'Sign in to enquire about this phone')) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      final phone = await AuthService().resolveCustomerPhone(user);
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'electronics_service',
        customerId: user.uid,
        customerName: user.displayName ?? 'Customer',
        customerPhone: phone,
        details: <String, dynamic>{
          'category': 'mobile',
          'categoryLabel': 'Mobile',
          'intent': _isUsed ? 'buy_used_mobile' : 'buy_new_mobile',
          'issue':
              'Purchase enquiry: ${listing.displayName} — ₹${listing.price.toInt()}'
                  '${listing.isUsed ? ' (${listing.conditionGrade ?? 'Used'})' : ''}'
                  ' from ${listing.sellerName}',
          'listingId': listing.id,
          'sellerId': listing.sellerId,
          'sellerName': listing.sellerName,
          'brand': listing.brand,
          'model': listing.model,
          if (listing.variant.isNotEmpty) 'variant': listing.variant,
          'price': listing.price,
          'condition': listing.condition,
        },
      );

      if (!mounted) return;
      Navigator.pop(context); // close the detail sheet
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'electronics_service',
          ),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not send enquiry: $e'),
          backgroundColor: kMobRed,
        ),
      );
    }
  }
}

// ================================================================
// Grid card
// ================================================================
class _MobileCard extends StatelessWidget {
  final MobileListing listing;
  final VoidCallback onTap;
  final VoidCallback? onPlayVideo;

  const _MobileCard({
    required this.listing,
    required this.onTap,
    this.onPlayVideo,
  });

  @override
  Widget build(BuildContext context) {
    final discount = listing.discountPercent;
    final hasVideo = youtubeVideoId(listing.youtubeUrl) != null;
    final emiPerMonth = listing.emiPerMonth;

    // PREMIUM SHOWCASE CARD (Aug 18 2026 — Founder's "Apple Store meets
    // CRED" brief). The photo sits on a near-white podium plate rather
    // than bleeding to the card edge, which is what makes a product
    // read as *displayed* instead of merely pasted in. All tokens come
    // from premium_theme.dart so this can't drift from Rewards.
    return PremiumCard(
      onTap: onTap,
      radius: kRadiusLg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 10, 4),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  // The podium plate.
                  Container(
                    decoration: BoxDecoration(
                      color: kPremiumWhite,
                      borderRadius: BorderRadius.circular(kRadiusMd),
                      border: Border.all(color: kPremiumHairline),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: MobileListingImage(listing: listing, cacheWidth: 300),
                  ),
                  if (discount != null)
                    Positioned(
                      top: 8,
                      left: 8,
                      child: PremiumPill(
                        text: '$discount% OFF',
                        color: kPremiumGreen,
                      ),
                    ),
                  if (listing.isUsed && listing.conditionGrade != null)
                    Positioned(
                      top: 8,
                      right: 8,
                      child: PremiumPill(
                        text: listing.conditionGrade!.toUpperCase(),
                        color: kMobBlue,
                        solid: false,
                      ),
                    ),
                  // Tapping the badge itself jumps STRAIGHT to the
                  // player, skipping the detail sheet — for a used
                  // phone the clip is the thing the buyer actually came
                  // to see. Tapping anywhere else still opens details.
                  if (hasVideo)
                    Positioned(
                      bottom: 8,
                      left: 8,
                      child: GestureDetector(
                        onTap: onPlayVideo,
                        child: const VideoGlowBadge(),
                      ),
                    ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 6, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  listing.displayName,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: premiumTitle(size: 13),
                ),
                const SizedBox(height: 7),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('\u20B9${listing.price.toInt()}',
                        style: premiumPrice(size: 16)),
                    const SizedBox(width: 6),
                    if (listing.mrp != null && discount != null)
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(bottom: 2),
                          child: Text(
                            '\u20B9${listing.mrp!.toInt()}',
                            overflow: TextOverflow.ellipsis,
                            style: premiumBody(size: 10.5).copyWith(
                              decoration: TextDecoration.lineThrough,
                            ),
                          ),
                        ),
                      ),
                  ],
                ),
                // EMI line — sits directly under the price so the two
                // numbers are read together. Absent entirely on used
                // phones and on anything cheap enough that no financier
                // would write a plan (see MobileListing.isEmiEligible).
                if (emiPerMonth != null) ...[
                  const SizedBox(height: 5),
                  Row(
                    children: [
                      const Icon(Icons.credit_card_rounded,
                          color: kPremiumGreen, size: 11),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          'EMI from ₹$emiPerMonth/mo',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: premiumBody(size: 10).copyWith(
                            color: kPremiumGreen,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: 6),
                Row(
                  children: [
                    const Icon(Icons.storefront_rounded,
                        color: kPremiumMuted, size: 11),
                    const SizedBox(width: 4),
                    Expanded(
                      child: Text(
                        listing.sellerName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: premiumBody(size: 10),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// Image resolver — the shared-vs-own-photo decision in one place
// ================================================================
/// Resolves which image a listing should show, in this order:
///   1. the seller's own uploaded photo (always wins when present —
///      required for used phones, optional for new)
///   2. the shared catalog photo for that model (new phones; costs
///      nothing extra no matter how many sellers list the same model)
///   3. a local icon fallback (free)
class MobileListingImage extends StatelessWidget {
  final MobileListing listing;
  final int? cacheWidth;

  const MobileListingImage({
    super.key,
    required this.listing,
    this.cacheWidth,
  });

  @override
  Widget build(BuildContext context) {
    final own = listing.imageUrl;
    if (own != null && own.isNotEmpty) {
      return CachedCloudImage(
        own,
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorWidget: MobilePhotoFallback(brand: listing.brand),
      );
    }

    final shared =
        MobileCatalogService.instance.sharedImageUrlFor(listing.modelKey);
    if (shared != null) {
      return CachedCloudImage(
        shared,
        fit: BoxFit.contain,
        cacheWidth: cacheWidth,
        errorWidget: MobilePhotoFallback(brand: listing.brand),
      );
    }

    return MobilePhotoFallback(brand: listing.brand);
  }
}

// ================================================================
// Detail sheet
// ================================================================
class _ListingDetailSheet extends StatelessWidget {
  final MobileListing listing;
  final VoidCallback onEnquire;

  const _ListingDetailSheet({required this.listing, required this.onEnquire});

  @override
  Widget build(BuildContext context) {
    final discount = listing.discountPercent;
    final videoId = youtubeVideoId(listing.youtubeUrl);
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: const BoxDecoration(
            color: kMobBg,
            borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scrollController,
                  padding: EdgeInsets.zero,
                  children: [
                    Center(
                      child: Container(
                        width: 40,
                        height: 4,
                        margin: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: kMobBorder,
                          borderRadius: BorderRadius.circular(2),
                        ),
                      ),
                    ),
                    SizedBox(
                      height: 220,
                      child: MobileListingImage(
                          listing: listing, cacheWidth: 700),
                    ),
                    // Video sits directly under the photo: for a used
                    // phone it is the strongest proof of condition a
                    // buyer can get, so it should not be buried below
                    // the spec rows. Player is lazy — see
                    // ListingVideoPlayer: nothing heavier than a
                    // thumbnail loads until the customer taps play.
                    if (videoId != null)
                      Padding(
                        padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                        child: ListingVideoPlayer(videoId: videoId),
                      ),
                    Padding(
                      padding: const EdgeInsets.all(18),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            listing.displayName,
                            style: GoogleFonts.outfit(
                              color: kMobText,
                              fontSize: 19,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '₹${listing.price.toInt()}',
                                style: GoogleFonts.outfit(
                                  color: kMobPink,
                                  fontSize: 24,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(width: 8),
                              if (listing.mrp != null && discount != null) ...[
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '₹${listing.mrp!.toInt()}',
                                    style: GoogleFonts.outfit(
                                      color: kMobMuted,
                                      fontSize: 13,
                                      decoration: TextDecoration.lineThrough,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Padding(
                                  padding: const EdgeInsets.only(bottom: 4),
                                  child: Text(
                                    '$discount% off',
                                    style: GoogleFonts.outfit(
                                      color: kMobGreen,
                                      fontSize: 13,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 16),
                          _row(Icons.storefront_rounded, 'Shop',
                              listing.sellerName),
                          if (listing.variant.isNotEmpty)
                            _row(Icons.memory_rounded, 'Variant',
                                listing.variant),
                          if (listing.color.isNotEmpty)
                            _row(Icons.palette_outlined, 'Colour',
                                listing.color),
                          _row(
                            listing.isUsed
                                ? Icons.verified_outlined
                                : Icons.new_releases_outlined,
                            'Condition',
                            listing.isUsed
                                ? (listing.conditionGrade ?? 'Used')
                                : 'Brand New (Sealed)',
                          ),
                          if (listing.warrantyMonths > 0)
                            _row(Icons.shield_outlined, 'Warranty',
                                '${listing.warrantyMonths} months'),
                          if (listing.notes != null &&
                              listing.notes!.trim().isNotEmpty)
                            _row(Icons.notes_rounded, 'Details',
                                listing.notes!.trim()),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(18, 6, 18, 12),
                  child: SizedBox(
                    width: double.infinity,
                    height: 50,
                    child: ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: kMobPink,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      onPressed: onEnquire,
                      icon: const Icon(Icons.shopping_bag_outlined,
                          color: Colors.white, size: 20),
                      label: Text(
                        'Enquire / Book this phone',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _row(IconData icon, String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: kMobPink, size: 17),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style:
                        GoogleFonts.outfit(color: kMobMuted, fontSize: 10.5)),
                Text(
                  value,
                  style: GoogleFonts.outfit(
                    color: kMobText,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
