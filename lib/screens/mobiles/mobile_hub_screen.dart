// ================================================================
// MobileHubScreen — "Allin1 Mobile Hub" (Aug 18 2026, Nizam's mandate)
// ================================================================
// Erode's phone destination inside Allin1: buy new, buy used, book a
// repair, and track it all in one place.
//
// FOUR TABS (per spec):
//   0  New Mobiles Offer   — every shop's new stock, one query
//   1  Used Mobiles        — second-hand stock + "sell your old phone"
//   2  Mobile Service      — repair booking
//   3  Order & Service Status
//
// COST DESIGN — the whole point of this feature's architecture:
//   * Catalog metadata (brand/model names) is a bundled JSON asset →
//     0 Firestore reads to browse, works offline, no spinner.
//   * New-phone photos come from ONE shared Cloudinary image per model,
//     reused by every seller listing that model, cached ~30 days on
//     device by CachedCloudImage → downloaded once per customer, ever.
//   * Used-phone photos are per-listing (a buyer must see the real
//     unit) but compressed to ~100 KB on upload.
//   * Browse is a one-shot collectionGroup .get() with pull-to-refresh,
//     NOT a live listener — a phone catalog doesn't need to change
//     under the customer's thumb, and a standing cross-seller listener
//     would re-read for every customer on any shop's edit.
//   * Service booking reuses the EXISTING 'electronics_service'
//     pipeline (which already has a 'mobile' category), so there is no
//     new requestType to register in hero_service_access.dart,
//     service_request_labels.dart, my_orders_screen.dart and
//     firestore.rules — and no risk to the live dispatch flow.
// ================================================================

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/app_minimizer_service.dart';
import '../../services/mobile_catalog_service.dart';
import 'mobile_listings_tab.dart';
import 'mobile_service_tab.dart';
import 'mobile_status_tab.dart';

// Theme — same palette as nj_tech_store_screen.dart so the hub reads as
// part of the same app rather than a bolted-on section.
const Color kMobBg = Color(0xFFFFFFFF);
const Color kMobSurface = Color(0xFFF8F8FF);
const Color kMobPink = Color(0xFFFF4FA3);
const Color kMobText = Color(0xFF1A1A2E);
const Color kMobMuted = Color(0xFF9999BB);
const Color kMobBorder = Color(0xFFEEEEF5);
const Color kMobGreen = Color(0xFF00C853);
const Color kMobGold = Color(0xFFFFBB00);
const Color kMobRed = Color(0xFFFF5252);
const Color kMobBlue = Color(0xFF1565C0);

class MobileHubScreen extends StatefulWidget {
  /// Which tab to land on. Lets the dashboard deep-link straight to
  /// e.g. Used Mobiles later without a new screen.
  final int initialTab;

  const MobileHubScreen({super.key, this.initialTab = 0});

  @override
  State<MobileHubScreen> createState() => _MobileHubScreenState();
}

class _MobileHubScreenState extends State<MobileHubScreen> {
  late int _tabIndex = widget.initialTab;

  @override
  void initState() {
    super.initState();
    // Warm the bundled catalog once, here at the hub root, so both
    // listing tabs render instantly with no per-tab load. Costs no
    // network and no database read — it's a local asset decode.
    MobileCatalogService.instance.ensureLoaded();
  }

  // Back handling, consistent with the Aug 18 2026 navigation audit:
  // a non-zero tab steps back to tab 0 first (so Back feels like "one
  // step back" rather than jumping out of the section), and only then
  // does a normal pop happen — this screen is pushed, so popping
  // returns to the dashboard rather than closing the app. The
  // AppMinimizer branch is the safety net for the case where this ends
  // up as the first route (deep link / PWA entry).
  void _handleBackPress() {
    if (_tabIndex != 0) {
      setState(() => _tabIndex = 0);
      return;
    }
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
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
    AppMinimizer.moveToBackground();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
        backgroundColor: kMobBg,
        body: IndexedStack(
          index: _tabIndex,
          children: const [
            MobileListingsTab(condition: 'new'),
            MobileListingsTab(condition: 'used'),
            MobileServiceTab(),
            MobileStatusTab(),
          ],
        ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  // Hand-rolled Row-of-InkWell bottom nav — the house style used by
  // dashboard_screen.dart and nj_tech_store_screen.dart. Deliberately
  // not Material's BottomNavigationBar, which renders differently from
  // the rest of this app.
  Widget _buildBottomNav() {
    const items = [
      {'icon': Icons.smartphone_rounded, 'label': 'New Mobiles'},
      {'icon': Icons.autorenew_rounded, 'label': 'Used Mobiles'},
      {'icon': Icons.build_circle_outlined, 'label': 'Service'},
      {'icon': Icons.receipt_long_rounded, 'label': 'Order & Status'},
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kMobBg,
        border: const Border(top: BorderSide(color: kMobBorder)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: List.generate(items.length, (i) {
            final active = _tabIndex == i;
            final icon = items[i]['icon']! as IconData;
            final label = items[i]['label']! as String;
            return Expanded(
              child: InkWell(
                onTap: () => setState(() => _tabIndex = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(icon,
                          color: active ? kMobPink : kMobMuted, size: 24),
                      const SizedBox(height: 3),
                      Text(
                        label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 9.5,
                          color: active ? kMobPink : kMobMuted,
                          fontWeight:
                              active ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}

// ================================================================
// Shared bits used by more than one tab
// ================================================================

/// The hub's standard header. Kept here so all four tabs share one
/// look without each re-implementing an app bar.
class MobileHubHeader extends StatelessWidget {
  final String title;
  final String subtitle;
  final Widget? trailing;

  const MobileHubHeader({
    super.key,
    required this.title,
    required this.subtitle,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF130B28), Color(0xFF2A1060)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
              onPressed: () => Navigator.maybePop(context),
              tooltip: 'Back',
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.7),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            ),
            if (trailing != null) trailing!,
          ],
        ),
      ),
    );
  }
}

/// Free, zero-bandwidth fallback shown when a phone has no photo —
/// either because no admin has uploaded the shared model image yet, or
/// because a seller didn't add one. Never render a broken image box,
/// and never fall back to a scraped third-party URL.
class MobilePhotoFallback extends StatelessWidget {
  final String brand;
  final double size;

  const MobilePhotoFallback({super.key, required this.brand, this.size = 64});

  @override
  Widget build(BuildContext context) {
    final initial = brand.trim().isEmpty ? '?' : brand.trim()[0].toUpperCase();
    return Container(
      color: kMobSurface,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.smartphone_rounded, color: kMobMuted, size: size * 0.5),
          const SizedBox(height: 4),
          Text(
            initial,
            style: GoogleFonts.outfit(
              color: kMobMuted,
              fontSize: size * 0.22,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }
}
