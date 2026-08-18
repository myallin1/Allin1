// ================================================================
// SellerMobileDashboardScreen — mobile shop's own stock manager
// ================================================================
// Unlike Grocery and Electronics (which are deliberately catalog-free,
// broadcast/booking-only verticals), a mobile shop DOES get a real
// catalog: customers browse specific phones at specific prices, so the
// seller needs to list them.
//
// PopScope + AppMinimizer is wired from the start here, not bolted on
// later — seller_dashboard_screen.dart reaches this screen via
// Navigator.pushReplacement(), which destroys the route below it, so
// this becomes a mobile seller's literal app root. Without a PopScope,
// any back-press would hit Flutter's default un-intercepted behaviour
// and hard-close the app. That was exactly the bug fixed across the
// other dashboards in the Aug 18 2026 navigation audit; this screen
// ships correct.
// ================================================================

import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/food_models.dart';
import '../models/mobile_models.dart';
import '../services/app_minimizer_service.dart';
import '../services/food_seller_service.dart';
import '../services/mobile_catalog_service.dart';
import '../services/mobile_listing_service.dart';
import 'mobiles/mobile_listings_tab.dart' show MobileListingImage;
import 'seller_mobile_listing_editor.dart';

const Color _bg = Color(0xFF08080F);
const Color _card = Color(0xFF141420);
const Color _pink = Color(0xFFFF4FA3);
const Color _green = Color(0xFF00C853);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

class SellerMobileDashboardScreen extends StatefulWidget {
  const SellerMobileDashboardScreen({super.key});

  @override
  State<SellerMobileDashboardScreen> createState() =>
      _SellerMobileDashboardScreenState();
}

class _SellerMobileDashboardScreenState
    extends State<SellerMobileDashboardScreen> {
  final FoodSellerService _sellerService = FoodSellerService();
  final MobileListingService _listingService = MobileListingService();

  SellerModel? _seller;
  bool _loading = true;

  /// 0 = New stock, 1 = Used stock.
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    MobileCatalogService.instance.ensureLoaded();
    _load();
  }

  Future<void> _load() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    final seller = await _sellerService.getSeller(uid);
    if (mounted) {
      setState(() {
        _seller = seller;
        _loading = false;
      });
    }
  }

  void _handleBackPress() {
    if (_tab != 0) {
      setState(() => _tab = 0);
      return;
    }
    if (kIsWeb) {
      if (AppMinimizer.consumeWebHintOnce()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Press your device's Home button to minimize"),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    unawaited(AppMinimizer.moveToBackground());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Scaffold(
        backgroundColor: _bg,
        body: Center(child: CircularProgressIndicator(color: _pink)),
      );
    }

    final seller = _seller;
    final uid = FirebaseAuth.instance.currentUser?.uid;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        title: Text(
          seller?.name ?? 'Mobile Shop',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.logout_rounded, color: _muted),
            onPressed: () async {
              await FirebaseAuth.instance.signOut();
              if (context.mounted) {
                Navigator.of(context)
                    .pushNamedAndRemoveUntil('/', (route) => false);
              }
            },
          ),
        ],
      ),
      floatingActionButton: (seller == null || uid == null)
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _pink,
              onPressed: () => _openEditor(seller, uid, null),
              icon: const Icon(Icons.add_rounded, color: Colors.white),
              label: Text(
                'Add Phone',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
      body: (seller == null || uid == null)
          ? Center(
              child: Text(
                'Could not load your shop profile.',
                style: GoogleFonts.outfit(color: _muted),
              ),
            )
          : Column(
              children: [
                _buildTabs(),
                Expanded(child: _buildList(uid, seller)),
              ],
            ),
    );
  }

  Widget _buildTabs() {
    const labels = ['New Stock', 'Used Stock'];
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: List.generate(labels.length, (i) {
          final active = _tab == i;
          return Expanded(
            child: GestureDetector(
              onTap: () => setState(() => _tab = i),
              child: Container(
                margin: EdgeInsets.only(right: i == 0 ? 8 : 0),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  color: active ? _pink : _card,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: active ? _pink : _border),
                ),
                child: Center(
                  child: Text(
                    labels[i],
                    style: GoogleFonts.outfit(
                      color: active ? Colors.white : _muted,
                      fontSize: 13,
                      fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          );
        }),
      ),
    );
  }

  Widget _buildList(String uid, SellerModel seller) {
    final wantUsed = _tab == 1;
    return StreamBuilder<List<MobileListing>>(
      stream: _listingService.streamSellerListings(uid),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: _pink, strokeWidth: 2),
          );
        }
        final all = snap.data ?? const <MobileListing>[];
        final items =
            all.where((l) => l.isUsed == wantUsed).toList(growable: false);

        if (items.isEmpty) {
          return Center(
            child: Padding(
              padding: const EdgeInsets.all(32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.smartphone_rounded,
                      color: _muted, size: 54),
                  const SizedBox(height: 14),
                  Text(
                    wantUsed
                        ? 'No used phones listed yet.'
                        : 'No new phones listed yet.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: _text, fontSize: 15),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    'Tap "Add Phone" to list your first one — customers '
                    'will see it in the Allin1 Mobile Hub straight away.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                  ),
                ],
              ),
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 90),
          itemCount: items.length,
          itemBuilder: (context, i) =>
              _buildCard(items[i], seller, uid),
        );
      },
    );
  }

  Widget _buildCard(MobileListing listing, SellerModel seller, String uid) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Row(
          children: [
            SizedBox(
              width: 84,
              height: 92,
              child: MobileListingImage(listing: listing, cacheWidth: 200),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      listing.displayName,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          '₹${listing.price.toInt()}',
                          style: GoogleFonts.outfit(
                            color: _pink,
                            fontSize: 15,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        if (listing.discountPercent != null) ...[
                          const SizedBox(width: 6),
                          Text(
                            '${listing.discountPercent}% off',
                            style: GoogleFonts.outfit(
                              color: _green,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 6),
                    Row(
                      children: [
                        // Stock toggle — by far the most frequent action
                        // a shop takes, so it's one tap here rather than
                        // buried in the editor.
                        GestureDetector(
                          onTap: () => _listingService.setInStock(
                              uid, listing.id, !listing.inStock),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: (listing.inStock ? _green : _muted)
                                  .withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              listing.inStock ? 'In stock' : 'Sold out',
                              style: GoogleFonts.outfit(
                                color: listing.inStock ? _green : _muted,
                                fontSize: 10,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const Spacer(),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.edit_outlined,
                              color: _muted, size: 18),
                          onPressed: () => _openEditor(seller, uid, listing),
                          tooltip: 'Edit',
                        ),
                        IconButton(
                          visualDensity: VisualDensity.compact,
                          icon: const Icon(Icons.delete_outline_rounded,
                              color: Color(0xFFFF5252), size: 18),
                          onPressed: () => _confirmDelete(uid, listing),
                          tooltip: 'Delete',
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openEditor(
    SellerModel seller,
    String uid,
    MobileListing? existing,
  ) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SellerMobileListingEditor(
          sellerId: uid,
          sellerName: seller.name,
          sellerPhone: seller.phone,
          existing: existing,
          initialCondition:
              _tab == 1 ? MobileCondition.used : MobileCondition.isNew,
        ),
      ),
    );
    // The list is a live stream, so it refreshes itself — nothing to do
    // on return.
  }

  Future<void> _confirmDelete(String uid, MobileListing listing) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text('Remove listing?',
            style: GoogleFonts.outfit(color: _text)),
        content: Text(
          '${listing.displayName} will no longer be visible to customers.',
          style: GoogleFonts.outfit(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text('Remove',
                style: GoogleFonts.outfit(
                    color: const Color(0xFFFF5252),
                    fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    if (ok == true) {
      await _listingService.deleteListing(uid, listing.id);
    }
  }
}
