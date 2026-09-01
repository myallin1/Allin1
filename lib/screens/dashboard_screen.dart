// ================================================================
// dashboard_screen.dart — Allin1 Super App Customer Dashboard
// Premium Pink UI — Mega Cards Revamp — June 2026
// Patches: stream lift, optimistic wallet, cache layer, error feedback, zero deprecation
// ================================================================

import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:scratcher/scratcher.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config/city_config.dart';
import '../services/app_minimizer_service.dart';
import '../services/app_update_checker.dart';
// GUEST MODE (Aug 11 2026): the 30s deferred sign-in nudge.
import '../services/auth_prompt_service.dart';
import '../services/city_service.dart';
import '../services/hive_cache.dart';
import '../services/local_sync_service.dart';
import '../services/localization_service.dart';
import '../services/chitti/chitti_screen_tracker.dart';
import '../services/chitti_nudge_service.dart';
import '../services/chitti_order_memory_service.dart';
import '../services/chitti_overlay_service.dart';
// Real embedded browser view — WebView on native, <iframe> on the PWA.
// Named for DMart (its first use, in Grocery) but URL-generic; the
// Internet/Broadband page now renders through the exact same widget so
// the two pages genuinely look and behave identically.
import '../widgets/dmart_embedded_view_web.dart'
    if (dart.library.io) '../widgets/dmart_embedded_view_native.dart';
import '../services/daily_quote_service.dart';
import '../widgets/chitti_companion.dart';
import '../services/location_service.dart';
import '../services/prefs_cache.dart';
import '../services/route_breadcrumb_observer.dart' show isRouteSafeToRestore;
import '../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../services/pwa_cache_platform_web.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../services/usage_tracking_service.dart';
import '../services/web_version_checker.dart';
import '../utils/daily_boost_messages.dart';
import '../widgets/auto_image_slider.dart';
import '../widgets/auto_widget_slider.dart';
import '../widgets/ai_bot_avatar.dart';
import '../widgets/cached_cloud_image.dart';
import '../services/migration_gate_service.dart';
import 'mobiles/listing_video_player.dart' show showPremiumVideoModal;
import '../models/mobile_models.dart' show youtubeVideoId;

import '../widgets/banner_slider.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/download_app_banner.dart';
import '../widgets/promo_overlay.dart';
import 'bike_taxi/bike_booking_screen.dart';
import 'car_wash_screen.dart';
import 'coming_soon_screen.dart';
import 'construction_screen.dart';
import 'eseva_service_screen.dart';
import 'custom_food_order_screen.dart';
import 'grocery_order_screen.dart';
import '../services/guru_overlay_service.dart';
import 'guru_chat_screen.dart';
import 'hero_booking_screen.dart';
import 'mobiles/mobile_hub_screen.dart';
import 'my_orders_screen.dart';
import 'nj_tech_service_screen.dart';
import 'skilled_services_screen.dart';
import 'nj_tech_store_screen.dart';
import 'play_zone_screen.dart';
import 'printing_service_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';
import 'ride_history_screen.dart';
import '../widgets/economic_vision_banner.dart';
import 'hero_promo_screen.dart';
import 'invite_friends_screen.dart';
import 'settings_screen.dart';
import 'sos_screen.dart';
import '../services/firestore_usage_tracking.dart';

// ── Brand Colors ─────────────────────────────────────────────────
// NOTE: these used to be `const` — hardcoded to the pink&white palette no
// matter what theme the customer picked in Settings. Per Nizam's decision
// (CTO-reviewed): dropped `const` so they're live variables that
// _syncDashboardPalette() below refreshes from the active ThemeService
// theme every time the dashboard rebuilds — so switching theme actually
// reflects on the home page instead of always showing pink&white.
Color kPink     = const Color(0xFFFF4FA3);
Color kPinkDark = const Color(0xFFBE2A7A);
Color kPinkBg   = const Color(0xFFFFF0F7);
Color kBg       = const Color(0xFFFFFFFF);
Color kSurface  = const Color(0xFFF8F8FF);
Color kNJDark   = const Color(0xFF130B28);
Color kNJDark2  = const Color(0xFF2A1060);
Color kText     = const Color(0xFF1A1A2E);
Color kMuted    = const Color(0xFF9999BB);
Color kGreen    = const Color(0xFF00C853);
Color kTeal     = const Color(0xFF00BFA5);
Color kBlue     = const Color(0xFF1565C0);
Color kGold     = const Color(0xFFFFBB00);
Color kPurple   = const Color(0xFF7B6FE0);
Color kBorder   = const Color(0xFFEEEEF5);
Color kRed      = const Color(0xFFFF5252);

/// Refreshes the dashboard's palette variables (above) from whichever
/// theme is currently active in [ThemeService]. Semantic status colors
/// (green/teal/blue/gold/purple/red) are left as-is on purpose -- they
/// mean "success"/"info"/"warning" etc regardless of theme, only the
/// brand + surface colors should follow the selected theme.
void _syncDashboardPalette(ThemeService ts) {
  final theme = ts.currentTheme;
  final cs = theme.colorScheme;
  kPink = cs.primary;
  kPinkDark = cs.secondary;
  kPinkBg = cs.primary.withValues(alpha: 0.06);
  kBg = theme.scaffoldBackgroundColor;
  kSurface = cs.surface;
  kNJDark = cs.surface;
  kNJDark2 = cs.primary;
  kText = cs.onSurface;
  kMuted = cs.onSurface.withValues(alpha: 0.55);
  kBorder = theme.dividerColor;
}

// ── NJ Tech Quick-Service Icons ──────────────────────────────────
// ── Banner Items ──────────────────────────────────────────────────
// Was a top-level `const` list -- turned into a getter (recomputed on
// every access) so the 'color' entries pick up live kPink/kTeal/etc
// values instead of freezing whatever they were at first app load.


// ================================================================
// DASHBOARD SCREEN — Main Entry
// ================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with WidgetsBindingObserver {
  // Number of entries in the IndexedStack / bottom nav below. Kept as a
  // named constant so _restoreLastTab() can range-check a persisted
  // index instead of trusting it blindly.
  static const int _tabCount = 5;

  int _navIndex = 0;

  // Multi-city (Plan 3): displayed under the "Hi, Name" greeting. Starts
  // at whatever's cached locally (or kDefaultCity 'erode' on first-ever
  // launch), then _detectCityInBackground() silently refreshes it via
  // GPS + reverse-geocoding once the frame is up -- no loading spinner,
  // no blocking the UI, and zero Firestore/RTDB cost (GPS + geocoding
  // are device/OS-side calls, not database reads).
  String _displayCity = kDefaultCity;

  // FIX (unwanted-read audit, per Nizam's request): IndexedStack below
  // used to mount ALL 5 tabs (Home/Rewards/PlayZone/GuruChat/SOS)
  // immediately on app open, regardless of which one was active — each
  // one starting its own listeners the moment the customer app opened,
  // same root cause already fixed on the admin and hero home screens.
  // Only put the REAL widget in a slot once that tab has actually been
  // visited; unvisited slots get a cheap placeholder. Tab 0 (Home) is
  // always needed immediately. _restoreLastTab() below may also jump
  // straight to a persisted tab on relaunch — that index must count as
  // "visited" too, so it renders for real instead of a placeholder.
  final Set<int> _visitedTabs = {0};
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _user = FirebaseAuth.instance.currentUser;

  // NAME FETCHING FIX (Aug 19 2026 — Nizam: "customer app la name
  // fetching problem iruku"). ROOT CAUSE: the header and drawer both
  // read `_user?.displayName` — a ONE-TIME snapshot of
  // FirebaseAuth.instance.currentUser taken when this State object was
  // constructed. Two separate ways that goes wrong:
  //   1. Phone-OTP / guest-upgraded accounts often have an EMPTY Auth
  //      displayName even though the customer's real name is correctly
  //      sitting in Firestore users/{uid}.name (profile_screen.dart's
  //      save flow already writes both places; login flows write only
  //      Firestore) — so the header showed "User"/"Guest" for exactly
  //      those customers.
  //   2. Even when Auth's displayName IS eventually set (e.g. the
  //      customer edits their name in Profile, which calls
  //      updateDisplayName), this `_user` field is never re-read after
  //      that — the dashboard is not rebuilt from scratch just because
  //      Auth's cached user object changed underneath it, so the OLD
  //      name kept showing until the next full app restart.
  // FIX: cache-first (HiveCache.getCachedUserProfile, already
  // populated by login/profile_screen.dart) then a background Firestore
  // refresh, same pattern _loadProfileFromFirestore() in
  // profile_screen.dart already uses. _buildAppBar()/_ProfileDrawer
  // read this instead of the frozen `_user.displayName`.
  String? _resolvedName;

  Future<void> _loadResolvedName() async {
    final user = _user;
    if (user == null) return;
    try {
      final cached = await HiveCache.getCachedUserProfile();
      final cachedName = (cached?['name'] as String?)?.trim();
      if (cachedName != null && cachedName.isNotEmpty && mounted) {
        setState(() => _resolvedName = cachedName);
      }
      // Always refresh in the background — cheap single .get(), and it
      // is what keeps a just-edited name from going stale until the
      // 30-minute cache TTL expires.
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = doc.data();
      final freshName = (data?['name'] as String?)?.trim();
      if (freshName != null && freshName.isNotEmpty) {
        if (mounted && freshName != _resolvedName) {
          setState(() => _resolvedName = freshName);
        }
        unawaited(HiveCache.cacheUserProfile({
          'name': freshName,
          'email': (data?['email'] as String?) ?? user.email ?? '',
          'phone': (data?['phoneNumber'] as String?) ??
              (data?['phone'] as String?) ??
              user.phoneNumber ??
              '',
        }));
      } else if (cachedName == null || cachedName.isEmpty) {
        // Nothing in Firestore either — fall back to whatever Auth has,
        // so a genuinely name-less guest still doesn't get stuck with
        // "User" if a display name exists on the Auth object itself.
        final authName = user.displayName?.trim();
        if (authName != null && authName.isNotEmpty && mounted) {
          setState(() => _resolvedName = authName);
        }
      }
    } catch (e) {
      debugPrint('[Dashboard] name fetch failed (non-fatal): $e');
    }
  }

  // FIX (Nizam's request): first-time-open "how to use this app" coach
  // mark tour — spotlights the real bottom-nav tabs on the real home
  // screen (not a separate slideshow). GlobalKeys attached to each tab
  // in _buildBottomNav() below; shown exactly once ever per install via
  // CoachMarkPrefs. See widgets/coach_mark_overlay.dart.
  static const String _dashboardTourId = 'dashboard_v1';
  final List<GlobalKey> _navTabKeys = List.generate(_tabCount, (_) => GlobalKey());

  // ── Classic Rewards promo state ──────────────────────────────
  // Built once real content is needed (see _localizedPromoOffers below) so
  // the title/subtitle/labels can come from LocalizationService instead of
  // being frozen in English at field-init time (no BuildContext available
  // here yet). Starts null; _ensurePromoOffersLoaded() populates it from
  // the first build().
  List<PromoOfferItem>? _promoOffers;

  List<PromoOfferItem> _localizedPromoOffers(String Function(String) t) => [
    // ── V2: Daily Quiz & Referral cards temporarily hidden ──
    // Re-enable these two entries to bring the cards back.
    // PromoOfferItem(
    //   id: 'quiz',    title: 'Daily Quiz Reward',
    //   subtitle: 'Answer 5 questions · Win Free Tempered Glass!',
    //   icon: Icons.quiz_rounded,     claimed: false,
    //   buttonLabel: 'Play Quiz',     statusLabel: 'Today Only',
    // ),
    // PromoOfferItem(
    //   id: 'refer',   title: '₹50 Referral Bonus',
    //   subtitle: 'Refer a friend · Both get ₹50 wallet cash',
    //   icon: Icons.person_add_rounded, claimed: false,
    //   buttonLabel: 'Refer Now',     statusLabel: 'Unlimited',
    // ),
    PromoOfferItem(
      id: 'firstride', title: t('promo_firstride_title'),
      subtitle: t('promo_firstride_subtitle'),
      icon: Icons.electric_bike_rounded, claimed: false,
      buttonLabel: t('promo_book_now_label'), statusLabel: t('promo_new_users_label'),
    ),
  ];

  // Only shows once a real update signal fires — web via
  // WebVersionChecker (version.json comparison), native via
  // AppUpdateChecker's GitHub-release version check. It used to be
  // hardcoded `true` on every platform, so the button showed regardless
  // of whether an update actually existed.
  bool _updateAvailable = false;
  Timer? _pwaUpdatePollTimer;
  // Deep linking (Aug 19 2026): subscription for app_links' uriLinkStream,
  // native/non-web only. Null on web (never assigned).
  StreamSubscription<Uri>? _deepLinkSub;

  Future<void> _claimPromo(String offerId) async {
    final t = context.read<LocalizationService>().t;
    setState(() {
      _promoOffers = (_promoOffers ?? _localizedPromoOffers(t)).map((p) =>
        p.id == offerId ? PromoOfferItem(
          id: p.id, title: p.title, subtitle: p.subtitle,
          icon: p.icon, claimed: true,
          buttonLabel: p.buttonLabel,
          claimedButtonLabel: p.claimedButtonLabel,
          statusLabel: t('promo_claimed_label'),
        ) : p,
      ).toList();
    });
  }

  // NEW (Aug 25 2026 — "Priority 2: Proactive Nudges"). See
  // ChittiNudgeService for the shared anti-spam gate every proactive
  // Chitti message must pass through, and chitti_order_memory_service.dart
  // for what "recorded" means (a rolling Hive history the completion
  // screens already write to). Deliberately a loose heuristic — "there
  // IS an order on record, and it's been at least 18h" — not real
  // pattern detection; a more precise "same weekday/time" model is a
  // reasonable follow-up once there's usage data to tune it against.
  Future<void> _maybeNudgeReorderUsual() async {
    final entry = ChittiOrderMemoryService.mostRecentEntry();
    if (entry == null) return;
    final atMs = entry['at'] as int?;
    if (atMs == null) return;
    final since = DateTime.now().difference(DateTime.fromMillisecondsSinceEpoch(atMs));
    // Too soon after the order itself (they just did it — nothing to
    // suggest) and too long ago (past a couple of weeks, the "usual"
    // framing stops being accurate) are both skipped.
    if (since < const Duration(hours: 18) || since > const Duration(days: 14)) {
      return;
    }

    final allowed = await ChittiNudgeService.instance.tryFire(
      'reorder_usual',
      perTypeCooldown: const Duration(hours: 24),
    );
    if (!allowed) return;

    final service = entry['service'] as String? ?? 'that';
    final summary = entry['summary'] as String? ?? 'your last order';
    unawaited(ChittiOverlayService.instance.showNudge(
      'Should I get your usual $service — $summary?',
    ));
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Deep link (Aug 19 2026 — WhatsApp shop-share flow) takes priority
    // over both tab restore and breadcrumb restore: if a customer opened
    // the app via a shared /shop/<id> or /pshop/<name> link, that's an
    // explicit intent and should win over "go back to where you left
    // off". _handleInitialDeepLink() returns false when there's no
    // matching path, in which case _restoreLastTab() (which itself
    // chains into _restoreDeepBreadcrumb()) runs exactly as before.
    unawaited(_handleInitialDeepLink().then((handled) {
      if (!handled && mounted) {
        unawaited(_restoreLastTab());
      }
    }));
    if (!kIsWeb) {
      unawaited(_initNativeDeepLinks());
    }
    unawaited(_silentBackupIfNeeded());
    unawaited(_loadResolvedName());
    unawaited(_detectCityInBackground());
    // Per Nizam's request: warm up GPS the moment the home page opens, so
    // by the time the customer taps Taxi/Food/Hero, LocationService already
    // has a cached position ready — the booking screen no longer has to
    // run its own permission-check + GPS-fetch from a cold start.
    unawaited(_prefetchLocationInBackground());
    // GUEST MODE (Aug 11 2026): start the 30s deferred sign-in nudge.
    // addPostFrameCallback is REQUIRED — showModalBottomSheet needs a
    // context that is already mounted in the tree, which it is not
    // during initState. The service itself no-ops for a real account,
    // for a second call in the same session, within 24h of a "Later",
    // and whenever another route/modal is on top — so it can never
    // ambush someone mid-booking. See auth_prompt_service.dart.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) AuthPromptService.instance.scheduleDeferredPrompt(context);
    });

    // CHITTI COMPANION (Aug 19 2026). Mounted once, here, on the root
    // overlay — from this point he outlives every screen the customer
    // opens, keeping his position, his animation and his memory of the
    // service in progress. See chitti_overlay_service.dart.
    //
    // Must be post-frame: the root Navigator's overlay does not exist
    // yet during initState, and show() would silently no-op.
    //
    // Android-only; show() no-ops on the PWA, so there is deliberately
    // no platform check at this call site.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ChittiOverlayService.instance.show(
        context,
        // FIX (Aug 29 2026 - Nizam: "chittya thotta neraa chitu screen
        // ku kutitu poguthu, popup yen open agalainu pathu open aga
        // vei"). This used to push the FULL chat page straight away,
        // so the floating mascot's tap never showed the popup at all -
        // GlobalGuruFab (the other Chitti icon, used on web/hero/
        // seller/admin) already opens the popup correctly via
        // GuruOverlayService.show(); the mascot just wasn't wired to
        // the same thing.
        onTapChitti: () => GuruOverlayService.instance.show(autoStartMic: true),
      );
    });

    // NEW (Aug 25 2026 — "Priority 2: Proactive Nudges", reorder-usual
    // trigger). Deliberately a loose heuristic, not real pattern
    // detection: "there IS an order on record, and it's been at least
    // 18h since it happened" — good enough for a v1 nudge, and every
    // rule about not spamming it lives in ChittiNudgeService, not here.
    // 5s delay: after the companion mount (post-frame) and clear of the
    // 3s daily-boost SnackBar above, so nothing stacks on cold boot.
    unawaited(Future<void>.delayed(const Duration(seconds: 5), () {
      if (!mounted) return;
      unawaited(_maybeNudgeReorderUsual());
    }));

    // NEW (Aug 12 2026 — Nizam's "daily boost" request): one small,
    // non-blocking motivational SnackBar per app cold-boot, right under
    // the time-of-day greeting. 3s delay clears the coach-mark tour /
    // scratch card sequencing below so overlays never stack on the
    // very first frame — see daily_boost_messages.dart for why this is
    // a plain local list, not a Firestore read.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future.delayed(const Duration(seconds: 3), () {
        if (!mounted) return;
        showDailyBoostSnackBar(context, randomCustomerBoostMessage());
      });
    });
    // Auto-show the Paytm Soundbox scratch card once ever per customer
    // — but only AFTER the first-open coach mark tour (if any) has been
    // shown/dismissed, so the two overlays never fight for the screen.
    // Runs after first frame so a bottom sheet/overlay can be shown safely.
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      final seenTour = await CoachMarkPrefs.hasSeenTour(_dashboardTourId);
      if (!seenTour) {
        if (!mounted) return;
        await CoachMarkPrefs.markTourSeen(_dashboardTourId);
        final t = context.read<LocalizationService>().t;
        showCoachMarkTour(
          context,
          steps: [
            CoachMarkStep(
              title: t('tour_welcome_title'),
              description: t('tour_welcome_desc'),
            ),
            CoachMarkStep(
              title: t('nav_home_label'),
              description: t('tour_home_desc'),
              targetKey: _navTabKeys[0],
            ),
            CoachMarkStep(
              title: t('nav_rewards_label'),
              description: t('tour_rewards_desc'),
              targetKey: _navTabKeys[1],
            ),
            CoachMarkStep(
              title: t('nav_playzone_label'),
              description: t('tour_playzone_desc'),
              targetKey: _navTabKeys[2],
            ),
            CoachMarkStep(
              title: t('nav_guru_label'),
              description: t('tour_guru_desc'),
              targetKey: _navTabKeys[3],
            ),
            CoachMarkStep(
              title: t('nav_safety_label'),
              description: t('tour_safety_desc'),
              targetKey: _navTabKeys[4],
            ),
          ],
          onFinish: () async {
            if (!mounted) return;
            // _hasSeenScratchCardEver() is async because HiveCache.get() is.
            if (!await _hasSeenScratchCardEver()) {
              if (!mounted) return;
              _showScratchCardModal();
            }
          },
        );
        return;
      }

      // _hasSeenScratchCardEver() is async because HiveCache.get() is.
      // It previously read the Future without awaiting and cast it to
      // String?, which threw a TypeError before this branch could run —
      // so the scratch card never appeared at all.
      if (!await _hasSeenScratchCardEver()) {
        if (!mounted) return;
        _showScratchCardModal();
      }
    });

    // Web: watch for a newer deployment.
    //
    // This used to read a flag set by service-worker update events. That
    // is dead — Flutter's current service worker unregisters itself on
    // activate, so it can never report anything, and the console showed
    // "[PWA] update check failed: InvalidStateError" every time. It now
    // compares /version.json against the build this tab loaded with,
    // which needs no service worker at all.
    if (kIsWeb) {
      // NEW (CTO mandate — PWA update popup): if this page load happened
      // right after we self-triggered an update reload, say welcome
      // once. Checked/cleared here (not in build()) so it never repeats
      // on a rebuild, and deferred a frame via addPostFrameCallback so
      // the dashboard is fully painted before a dialog pops on top of it.
      if (PwaCachePlatform().consumeJustUpdatedFlag()) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          _showWelcomeToNewVersionPopup(context);
        });
      }
      unawaited(WebVersionChecker.instance.start());
      _pwaUpdatePollTimer = Timer.periodic(const Duration(seconds: 8), (_) {
        if (!mounted) return;
        if (WebVersionChecker.instance.isUpdateAvailable &&
            !_updateAvailable) {
          setState(() => _updateAvailable = true);
          _pwaUpdatePollTimer?.cancel();
        }
      });
    } else {
      // Native: one check per launch, same pattern as hero_home_screen's
      // _checkForAppUpdate() — GitHub-release version check, only for
      // the rare case Shorebird OTA can't patch on its own.
      unawaited(_checkForNativeAppUpdate());
    }
  }

  // _goTab() has always written the current tab to PrefsCache, but
  // PrefsCache.loadLastTab() was never called anywhere — the save half of
  // the feature was built and the restore half was missing. So every
  // relaunch (and every PWA reload after Android discards the page on an
  // app switch) dumped the customer back on tab 0, even though the app
  // already knew where they were.
  //
  // Reading it is a local shared_preferences hit, so it resolves within
  // the first frame or two; the customer sees Home briefly at worst,
  // never a spinner.
  Future<void> _restoreLastTab() async {
    try {
      final last = await PrefsCache.loadLastTab();
      if (!mounted) return;
      // Guard the range: the nav bar's tab count can change between
      // releases, and a stale out-of-bounds index would throw inside
      // IndexedStack.
      if (last > 0 && last < _tabCount) {
        setState(() {
          _navIndex = last;
          _visitedTabs.add(last);
        });
      }
    } catch (e) {
      debugPrint('[Dashboard] last-tab restore failed: $e');
    }
    // Deep-screen restore (Aug 19 2026): runs after the tab restore above
    // has had a chance to settle. This is a pure mitigation for the
    // "app reloads from scratch after the OS kills it" complaint — it
    // cannot fix the underlying OS behavior, only make cold starts land
    // closer to where the customer actually was. See
    // route_breadcrumb_observer.dart for exactly which routes qualify
    // and why coverage is currently limited to the app's named routes.
    unawaited(_restoreDeepBreadcrumb());
  }

  // Deep link path parsing, shared by both the web (Uri.base) and native
  // (app_links) entry points below. Recognizes exactly the two share
  // formats produced by the Part 3 share buttons:
  //   /shop/<sellerId>        -> '/food_shop_detail' (SellerDetailScreen)
  //   /pshop/<shopName>       -> '/partner_shop_detail' (PartnerShopOrderScreen)
  // Returns null if the path doesn't match either pattern.
  ({String route, Map<String, dynamic> args})? _parseDeepLinkPath(String path) {
    final segments = path.split('/').where((s) => s.isNotEmpty).toList();
    if (segments.length < 2) return null;
    if (segments[0] == 'shop') {
      final sellerId = Uri.decodeComponent(segments[1]);
      if (sellerId.isEmpty) return null;
      return (
        route: '/food_shop_detail',
        args: {'sellerId': sellerId, 'categoryName': 'food'},
      );
    }
    if (segments[0] == 'pshop') {
      final shopName = Uri.decodeComponent(segments[1]);
      if (shopName.isEmpty) return null;
      return (route: '/partner_shop_detail', args: {'shopName': shopName});
    }
    return null;
  }

  Future<void> _pushDeepLink(String route, Map<String, dynamic> args) async {
    await Future.delayed(Duration.zero);
    if (!mounted) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      try {
        Navigator.of(context).pushNamed(route, arguments: args);
      } catch (e) {
        debugPrint('[Dashboard] deep link push failed: $e');
      }
    });
  }

  // Web cold start (Aug 19 2026): a WhatsApp-shared link opens the PWA at
  // e.g. my-allin1.web.app/shop/<id> — Uri.base.path is that clean path
  // thanks to usePathUrlStrategy() in main_customer.dart. Web-only; native
  // gets the equivalent via _initNativeDeepLinks() below. Returns true if
  // a deep link was found and a push was scheduled, so the caller can
  // skip the normal last-tab restore.
  Future<bool> _handleInitialDeepLink() async {
    if (!kIsWeb) return false;
    try {
      final parsed = _parseDeepLinkPath(Uri.base.path);
      if (parsed == null) return false;
      unawaited(_pushDeepLink(parsed.route, parsed.args));
      return true;
    } catch (e) {
      debugPrint('[Dashboard] initial web deep link parse failed: $e');
      return false;
    }
  }

  // Native Android App Links (Aug 19 2026): app_links' uriLinkStream
  // delivers BOTH the cold-start link (as its first event, per the
  // package's documented usage pattern) and any link received while the
  // app is already running (warm start, e.g. tapping the WhatsApp link
  // again with the app backgrounded). Non-web only — web's routing is
  // handled entirely by _handleInitialDeepLink() above via the browser's
  // own URL bar. Wrapped defensively: this must never block or crash app
  // startup.
  Future<void> _initNativeDeepLinks() async {
    try {
      final appLinks = AppLinks();
      _deepLinkSub = appLinks.uriLinkStream.listen((uri) {
        try {
          final parsed = _parseDeepLinkPath(uri.path);
          if (parsed != null) {
            unawaited(_pushDeepLink(parsed.route, parsed.args));
          }
        } catch (e) {
          debugPrint('[Dashboard] deep link handling failed: $e');
        }
      }, onError: (e) {
        debugPrint('[Dashboard] uriLinkStream error: $e');
      });
    } catch (e) {
      debugPrint('[Dashboard] native deep link init failed: $e');
    }
  }

  Future<void> _restoreDeepBreadcrumb() async {
    try {
      final crumb = await PrefsCache.loadBreadcrumb();
      if (crumb == null) return;
      if (!isRouteSafeToRestore(crumb.route)) return;
      // Wait one frame so the dashboard underneath is fully built —
      // pushing immediately during initState's async gap can race the
      // very first frame and has, historically, been a source of
      // "black screen for a moment" bugs elsewhere in this app.
      await Future.delayed(Duration.zero);
      if (!mounted) return;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        try {
          Navigator.of(context).pushNamed(crumb.route, arguments: crumb.args);
        } catch (e) {
          debugPrint('[Dashboard] deep breadcrumb push failed: $e');
        }
      });
    } catch (e) {
      debugPrint('[Dashboard] deep breadcrumb restore failed: $e');
    }
  }

  Future<void> _checkForNativeAppUpdate() async {
    try {
      final hasUpdate = await AppUpdateChecker().isUpdateAvailable();
      if (hasUpdate && mounted) {
        setState(() => _updateAvailable = true);
      }
    } catch (e) {
      debugPrint('[Dashboard] native app update check failed: $e');
    }
  }

  // Coming back to the app is the moment a deploy is most likely to
  // have happened while the customer was elsewhere — far more likely
  // than any given tick of the background timer. Checking here is what
  // lets the poll interval stay long (30 min) without the customer
  // waiting half an hour to be told an update exists.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed && kIsWeb) {
      unawaited(WebVersionChecker.instance.checkNow());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pwaUpdatePollTimer?.cancel();
    _deepLinkSub?.cancel();
    // GUEST MODE: kill the pending 30s timer — without this it would
    // fire against a disposed context if the customer leaves Home
    // within 30 seconds of opening the app.
    AuthPromptService.instance.cancel();
    super.dispose();
  }

  // ── One-time-ever scratch gate ────────────────────────────────
  // CHANGED (Nizam: "customer ku oru time mattum than scratchcard
  // kidaikanum, athukapram kaatave kudathu") — this used to re-arm every
  // calendar day (see _todayKey() below, now unused for this gate); a
  // customer now sees the scratch card at most ONCE ever, on any device/
  // reinstall-persistent local storage. Duration(days: 3650) stands in
  // for "forever" since HiveCache.put() requires a concrete ttl.
  static const Duration _foreverTtl = Duration(days: 3650);

  Future<bool> _hasSeenScratchCardEver() async =>
      (await HiveCache.get<bool>('scratch_card_seen_once')) ?? false;

  /// Multi-city (Plan 3): resolves the customer's real current city via
  /// GPS + reverse-geocoding, entirely in the background. Loads the
  /// last-cached value immediately (instant, no flicker to 'Erode' on
  /// repeat opens), then kicks off a fresh GPS read; if that resolves
  /// to a different (supported) city, updates the header. No dialogs,
  /// no spinners, no Firestore/RTDB reads -- CityService.detectAndUpdateCity()
  /// is device-side only and silently falls back to the cached value on
  /// any failure (permission denied, GPS off, no network for geocoding).
  Future<void> _detectCityInBackground() async {
    final cached = await CityService.getCurrentCity();
    if (mounted && cached != _displayCity) {
      setState(() => _displayCity = cached);
    }
    final detected = await CityService.detectAndUpdateCity();
    if (mounted && detected != _displayCity) {
      setState(() => _displayCity = detected);
    }
  }

  /// Silently warms up GPS permission + a first fix as soon as the home
  /// page opens (LocationService is a singleton, so whatever it caches
  /// here is instantly reused by BikeBookingScreen / other flows without
  /// re-running the permission dialog + GPS wait from scratch). Silent
  /// no-op on failure (permission denied, GPS off) -- the booking screen
  /// still has its own fallback UI for that case, this is purely a
  /// best-effort speed-up.
  Future<void> _prefetchLocationInBackground() async {
    try {
      final locationService = LocationService();
      final hasPermission = await locationService.checkAndRequestPermission();
      if (hasPermission) {
        await locationService.getCurrentLocation();
      }
    } catch (_) {
      // Silent -- booking screens re-check permission/GPS themselves.
    }
  }

  /// Manual city switch (Nizam's plan, item 2): tapping the city text
  /// under "Hi, Name" opens the full kSupportedCities list. Picking one
  /// marks it as a manual override (CityService.setCurrentCityManually)
  /// so future silent GPS detection won't flip it back -- e.g. a
  /// customer in Erode checking Coimbatore prices/heroes ahead of a
  /// trip stays on Coimbatore until they change it again. "Use my
  /// current location" at the top clears that override and re-runs
  /// GPS detection immediately.
  Future<void> _showCityPicker() async {
    final t = context.read<LocalizationService>().t;
    final selected = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Container(width: 40, height: 4, decoration: BoxDecoration(color: kMuted.withValues(alpha: 0.3), borderRadius: BorderRadius.circular(2))),
            const SizedBox(height: 16),
            Text(t('select_city_title'), style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16, color: kText)),
            const SizedBox(height: 8),
            ListTile(
              leading: Icon(Icons.my_location_rounded, color: kPink),
              title: Text(t('use_current_location_label'), style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
              onTap: () => Navigator.pop(ctx, '__auto__'),
            ),
            const Divider(height: 1),
            for (final city in kSupportedCities)
              ListTile(
                leading: Icon(
                  city.slug == _displayCity ? Icons.check_circle_rounded : Icons.location_city_rounded,
                  color: city.slug == _displayCity ? kPink : kMuted,
                ),
                title: Text(city.label, style: GoogleFonts.outfit(fontWeight: FontWeight.w600, fontSize: 14)),
                onTap: () => Navigator.pop(ctx, city.slug),
              ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
    if (selected == null) return;

    if (selected == '__auto__') {
      await CityService.clearManualOverride();
      final detected = await CityService.detectAndUpdateCity();
      if (mounted) setState(() => _displayCity = detected);
    } else {
      await CityService.setCurrentCityManually(selected);
      if (mounted) setState(() => _displayCity = selected);
    }
  }

  Future<void> _silentBackupIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final lastBackupStr = await HiveCache.get<String>('lastCoinsBackupDate');
      final now = DateTime.now();
      bool shouldBackup = false;

      if (lastBackupStr == null) {
        shouldBackup = true;
      } else {
        final lastBackup = DateTime.parse(lastBackupStr);
        if (now.difference(lastBackup).inHours >= 24) {
          shouldBackup = true;
        }
      }

      if (!shouldBackup) return;
      final currentCoins =
          (await HiveCache.get<num>(HiveCache.kWalletBalance))?.toDouble() ??
              0.0;
      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'njCoinsBackup': currentCoins,
            'lastCoinsBackupAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true),);

      // Explicit ttl — see _dailyKeyTtl. Given a 48h ttl the `>= 24 hours`
      // check above stays the single source of truth for backup cadence,
      // instead of the cache silently expiring first.
      await HiveCache.put(
        'lastCoinsBackupDate',
        now.toIso8601String(),
        ttl: const Duration(hours: 48),
      );
      debugPrint('[Dashboard] Silent backup completed: ${currentCoins.toStringAsFixed(0)} coins');
    } catch (e) {
      debugPrint('[Dashboard] Silent backup failed: $e');
    }
  }

  void _goTab(int i) {
    setState(() {
      _navIndex = i;
      _visitedTabs.add(i);
    });
    PrefsCache.saveLastTab(i);
  }

  // UPDATED (Aug 28 2026 — screen awareness): pushes through ChittiNav
  // so the route carries a human label. That is what lets Chitti answer
  // "what is this page?" about wherever the CUSTOMER navigated, not
  // just where Chitti sent them. Behaviour is otherwise identical to
  // the Navigator.push it replaces.
  void _navigate(Widget screen) => ChittiNav.push<void>(context, screen);

  Future<void> _launchBroadband() async {
    _navigate(const NjTechBroadbandWebView());
  }

  void _showScratchCardModal() {
    // Mark as seen forever so the card auto-shows at most ONCE per
    // customer, ever — whether or not they fully scratch it.
    unawaited(
      HiveCache.put('scratch_card_seen_once', true, ttl: _foreverTtl),
    );
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => const _ScratchCardModal(),
    );
  }

  void _tap(String id) {
    switch (id) {
      case 'taxi':        _navigate(const BikeBookingScreen()); break;
      case 'broadband':   _launchBroadband(); break;
      case 'food':        _navigate(const CustomFoodOrderScreen()); break;
      case 'grocery':     _navigate(const GroceryOrderScreen()); break;
      case 'njtech':      _navigate(const NJTechStoreScreen()); break;
      case 'carwash':     _navigate(const CarWashScreen()); break;
      case 'puncture':    Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen(initialCategory: 'puncture'))); break;
      case 'electrician': Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen(initialCategory: 'electrician'))); break;
      case 'construction':_navigate(const ConstructionScreen()); break;
      case 'homeservices': _navigate(const SkilledServicesScreen()); break;
      case 'custom':      _navigate(const HeroBookingScreen(initialCategory: 'custom_order')); break;
      case 'mobile':      _navigate(const NjTechServiceScreen()); break;
      case 'spares':      _navigate(const NjTechServiceScreen()); break;
      case 'aibots':      _navigate(const GuruChatScreen()); break;
      case 'repairs':     _navigate(const NjTechServiceScreen()); break;
      case 'delivery':    _navigate(const ComingSoonScreen(role: 'Delivery')); break;
    }
  }

  @override
  Widget build(BuildContext context) {
    // Refresh the dashboard's kPink/kBg/etc palette from whichever theme
    // is currently active. `watch` (not `read`) so this re-runs and the
    // whole home page repaints whenever the customer changes theme in
    // Settings -- this is what makes the theme switcher actually visible
    // on the home page instead of always showing pink & white.
    _syncDashboardPalette(context.watch<ThemeService>());
    // Populated once from the active language on first build. A language
    // switch afterwards only affects unclaimed cards on the next natural
    // rebuild (e.g. reopening the Rewards tab) -- claimed status itself
    // (rare, session-local) isn't persisted either way, matching the
    // original English-only behavior.
    _promoOffers ??= _localizedPromoOffers(context.watch<LocalizationService>().t);
    return PopScope(
      canPop: false,
      // FIX (Aug 12 2026 — CTO mandate: "System Back Button Overhaul"):
      // this used to show a Yes/No "exit app?" dialog and call
      // SystemNavigator.pop() on Yes — which FINISHES the Activity (a
      // real close), and on web either no-ops or leaves a blank/frozen
      // tab. That's the exact "app terminates / blank on PWA / full
      // cold-boot rebuild on reopen" bug this feature fixes. Minimizing
      // is a safe, fully reversible action (nothing is lost, the app
      // resumes instantly), so it no longer needs a confirmation dialog
      // at all — it just happens, the same way tapping the OS Home
      // button would.
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        if (_navIndex != 0) { _goTab(0); return; }
        if (kIsWeb) {
          // A browser tab cannot minimize itself to the OS home screen —
          // no such API exists (would be a sandboxing violation). Show
          // the "use your device's Home button" hint once per session,
          // then silently swallow further back-presses so it never nags.
          if (AppMinimizer.consumeWebHintOnce()) {
            final t = context.read<LocalizationService>().t;
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(t('press_home_to_minimize')),
                duration: const Duration(seconds: 3),
              ),
            );
          }
          return;
        }
        unawaited(AppMinimizer.moveToBackground());
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: kBg,
        drawer: _ProfileDrawer(
          user: _user,
          resolvedName: _resolvedName,
          onNavigate: _navigate,
        ),
        appBar: _buildAppBar(),
        body: Stack(
          children: [
            IndexedStack(
              index: _navIndex,
              children: [
                KeepAliveTab(
                  child: _HomeTab(
                    onTileTap: _tap,
                    user: _user,
                    userStream: const Stream.empty(),
                  ),
                ),
                if (_visitedTabs.contains(1)) KeepAliveTab(
                        child: RewardsScreen(
                          promoOffers: _promoOffers!,
                          onClaimPromo: _claimPromo,
                        ),
                      ) else const SizedBox.shrink(),
                if (_visitedTabs.contains(2)) const KeepAliveTab(child: PlayZoneScreen()) else const SizedBox.shrink(),
                if (_visitedTabs.contains(3)) const KeepAliveTab(child: GuruChatScreen()) else const SizedBox.shrink(),
                if (_visitedTabs.contains(4)) const KeepAliveTab(child: SosScreen()) else const SizedBox.shrink(),
              ],
          ),
        ],
      ),
        bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    final name = _resolvedName ?? _user?.displayName ?? 'User';
    final firstName = name.split(' ').first;

    return AppBar(
      backgroundColor: kBg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      // Raised from the default 56 (Aug 19 2026): the title column went
      // from two lines to three when the daily quote was added, and at
      // 56 the third line overflows on smaller phones. Set explicitly
      // rather than left to chance so the layout is not one font-scale
      // setting away from a yellow-stripe overflow.
      toolbarHeight: 66,
      leading: IconButton(
        // FIX (UI standardization, Aug 11 2026): every other screen's
        // leading nav icon (back button etc.) is size 20 — this hamburger
        // was 26, 30% larger for the same semantic slot.
        icon: Icon(Icons.menu_rounded, color: kPink, size: 20),
        onPressed: () => _scaffoldKey.currentState?.openDrawer(),
      ),
      title: Row(
        children: [
          CircleAvatar(
            radius: 16,
            backgroundColor: kPink,
            child: Text(
              firstName.isNotEmpty ? firstName[0].toUpperCase() : 'U',
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 13),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  // FIX (Aug 12 2026 — Nizam's "personal touch" request):
                  // was always the static 'greeting_hi' ("Hi") key —
                  // now picks morning/afternoon/evening/night based on
                  // the device clock (see LocalizationService
                  // .greetingKeyForNow()), matching how the Claude
                  // desktop app itself greets by time of day.
                  '${context.watch<LocalizationService>().t(LocalizationService.greetingKeyForNow())}, $firstName',
                  // 14 → 13 (Aug 19 2026, Nizam): the name steps back a
                  // point so the quote below can step forward one, which
                  // is what shifts the eye from "who am I" to "what's
                  // today". Same total header height either way.
                  style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w700, fontSize: 13),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),

                // ── DAILY QUOTE ─────────────────────────────────
                // Sits between the name and the city, exactly as asked.
                // Costs nothing: compiled into the app, no Firestore
                // read, no network, no state — see daily_quote_service
                // .dart for why it isn't AI-generated or server-fed.
                //
                // One line only, ellipsised rather than wrapped: this
                // is an AppBar title, and letting it wrap to two lines
                // would push the city out of the fixed toolbar height.
                Text(
                  DailyQuoteService.instance.forCustomer(
                    context.watch<LocalizationService>().languageCode,
                  ),
                  // Location is 9, so this is 10 — one point larger, per
                  // Nizam. Italic and muted-but-warmer than the city so
                  // it reads as an aside, not as data.
                  style: GoogleFonts.outfit(
                    color: kPink.withValues(alpha: 0.85),
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    fontStyle: FontStyle.italic,
                    height: 1.25,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 1),

                GestureDetector(
                  onTap: _showCityPicker,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '${cityLabelFor(_displayCity)}, TN',
                        style: TextStyle(color: kMuted, fontSize: 9, letterSpacing: 0.5, fontWeight: FontWeight.w700),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 12, color: kMuted),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
      actions: [
        if (_updateAvailable)
          _GlowingUpdateButton(
            onTap: () {
              setState(() => _updateAvailable = false);
              if (kIsWeb) {
                unawaited(_applyPwaUpdate(context));
              } else {
                unawaited(_applyNativeAppUpdate(context));
              }
            },
          ),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: kPinkBg,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: kPink.withValues(alpha: 0.3)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wallet_rounded, size: 16, color: kPink),
              const SizedBox(width: 4),
              Text(
                '₹0',
                style: TextStyle(color: kPink, fontWeight: FontWeight.w700, fontSize: 13),
              ),
            ],
          ),
        ),
        const SizedBox(width: 8),
        GestureDetector(
          onTap: () => _showApkSheet(context),
          // FIX (UI standardization, Aug 11 2026): matches the 18-20px
          // inline-icon convention used everywhere else (drawer icons,
          // list-row icons) instead of standing out at 22.
          child: Icon(Icons.notifications_outlined, color: kText, size: 20),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildBottomNav() {
    final t = context.watch<LocalizationService>().t;
    final items = [
      // FIX (per Nizam's request): the Home tab's icon slot now shows an
      // 'A1' text badge instead of a generic house glyph — reads as an
      // actual brand mark rather than a stock icon. 'icon' is left null
      // for this entry and handled as a special case below; the 'Home'
      // text label underneath is untouched.
      {'icon': null,                          'label': t('nav_home_label')},
      {'icon': Icons.card_giftcard_rounded,  'label': t('nav_rewards_label')},
      {'icon': Icons.sports_esports_rounded, 'label': t('nav_playzone_label')},
      {'icon': Icons.smart_toy_rounded,      'label': t('nav_guru_label')},
      {'icon': Icons.shield_rounded,         'label': t('nav_safety_label')},
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: kBg,
        border: Border(top: BorderSide(color: kBorder)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16, offset: const Offset(0, -4),),],
      ),
      child: SafeArea(
        child: Row(
          children: List.generate(items.length, (i) {
            final active = _navIndex == i;
            final icon  = items[i]['icon']  as IconData?;
            final label = items[i]['label']! as String;
            return Expanded(
              child: InkWell(
                key: _navTabKeys[i],
                onTap: () => _goTab(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    // FIX (Nizam: the Chitti AI tab's Icons.smart_toy_rounded
                    // read as an alarming/"panic" glyph to customers, not as
                    // the friendly assistant it represents). Swapped for the
                    // same static Chitti robot artwork used elsewhere in the
                    // app (assets/ai/ai_robot.webp, see the floating bot in
                    // this same file and guru_overlay_service.dart's
                    // AiBotAvatar) — no animation needed for a small nav
                    // icon slot, just a calm, on-brand image. Sized to match
                    // the 24px Icon() slot it replaces so the row doesn't
                    // shift. Only this one tab changes; every other nav icon
                    // is untouched.
                    if (icon == Icons.smart_toy_rounded)
                      Opacity(
                        opacity: active ? 1.0 : 0.55,
                        child: Image.asset(
                          'assets/ai/ai_robot.webp',
                          width: 24,
                          height: 24,
                          cacheWidth: 72,
                          fit: BoxFit.contain,
                          errorBuilder: (_, __, ___) =>
                              Icon(icon, color: active ? kPink : kMuted, size: 24),
                        ),
                      )
                    else if (icon != null) Icon(icon, color: active ? kPink : kMuted, size: 24) else _A1BadgeIcon(active: active),
                    const SizedBox(height: 3),
                    Text(label, style: TextStyle(
                        fontSize: 9.5,
                        color: active ? kPink : kMuted,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400,),),
                  ],),
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
// A1 BRAND BADGE — Home tab icon replacement
// ================================================================
// Small rounded-square 'A1' wordmark used in place of Icons.home_rounded
// on the bottom nav's Home tab — reads as a brand mark rather than a
// generic stock icon. Sizing matches the 24px Icon() slot it replaces
// so the row layout doesn't shift.
class _A1BadgeIcon extends StatelessWidget {
  final bool active;
  const _A1BadgeIcon({required this.active});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 24,
      height: 24,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: active ? kPink : kMuted.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(7),
      ),
      child: Text(
        'A1',
        style: TextStyle(
          fontSize: 10,
          fontWeight: FontWeight.w900,
          letterSpacing: -0.3,
          color: active ? Colors.white : kMuted,
          height: 1,
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<bool>('active', active));
  }
}

// ================================================================
// FLOATING GURU BOT — Draggable
// ================================================================
class _FloatingGuruBot extends StatefulWidget {
  final VoidCallback onTap;
  const _FloatingGuruBot({required this.onTap});
  @override
  State<_FloatingGuruBot> createState() => _FloatingGuruBotState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _FloatingGuruBotState extends State<_FloatingGuruBot> {
  double _x = 0, _y = 0;
  bool _placed = false;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    if (!_placed) { _x = size.width - 90; _y = size.height * 0.5; _placed = true; }

    return Positioned(
      left: _x, top: _y,
      child: GestureDetector(
        onPanUpdate: (d) => setState(() {
          _x = (_x + d.delta.dx).clamp(0, size.width - 80);
          _y = (_y + d.delta.dy).clamp(0, size.height - 80);
        }),
        onTap: widget.onTap,
        child: Stack(clipBehavior: Clip.none, children: [
          // CHITTI (Aug 19 2026, Nizam: "antha bommaya thookitu namma
          // new chitty robot oda head mattum anga animation ah
          // vaikkaporom"). The static assistant.gif is gone; this is
          // the live robot head, bobbing and glowing.
          //
          // A GIF was the wrong mechanism for this even ignoring the
          // art change: Flutter re-decodes every GIF frame on the UI
          // thread, so a permanently-visible animated GIF costs real
          // frame budget on exactly the low-end phones this app targets.
          // ChittiCompanion drives the same impression with transforms
          // on a single controller and one decoded still.
          //
          // Falls back to the plain glowing circle wherever the
          // companion isn't supported (PWA), so the web build keeps a
          // working button rather than a hole.
          if (ChittiCompanion.isSupported)
            const ChittiCompanion(mood: ChittiMood.idle, size: 60)
          else
            Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: kBg, shape: BoxShape.circle,
                border: Border.all(color: kPink.withValues(alpha: 0.35), width: 2),
                boxShadow: [BoxShadow(
                    color: kPink.withValues(alpha: 0.25),
                    blurRadius: 16, spreadRadius: 2,),],
              ),
              child: Center(
                child: Image.asset(
                  'assets/ai/ai_robot.webp',
                  width: 46, height: 46,
                  cacheWidth: 138,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('💬', style: TextStyle(fontSize: 28)),
                ),
              ),
            ),
          Positioned(top: -6, right: -4,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
              decoration: BoxDecoration(
                color: kGreen, borderRadius: BorderRadius.circular(8),),
              child: Text('FREE', style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 7,
                  fontWeight: FontWeight.w800,),),
            ),
          ),
        ],),
      ),
    );
  }
}

// ================================================================
// FLOATING GIFT BOX
// ================================================================
class _FloatingGiftBox extends StatefulWidget {
  final VoidCallback onTap;
  const _FloatingGiftBox({required this.onTap});
  @override
  State<_FloatingGiftBox> createState() => _FloatingGiftBoxState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _FloatingGiftBoxState extends State<_FloatingGiftBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200),)
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.08).animate(
        CurvedAnimation(parent: _glow, curve: Curves.easeInOut),);
  }

  @override
  void dispose() { _glow.dispose(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _pulse,
      builder: (_, __) => Transform.scale(
        scale: _pulse.value,
        child: GestureDetector(
          onTap: widget.onTap,
          child: Container(
            width: 60, height: 60,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: const RadialGradient(colors: [
                Color(0xFFFFDD00), Color(0xFFFF9800),
              ],),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFBB00)
                        .withValues(alpha: 0.5 + 0.35 * _pulse.value),
                    blurRadius: 22,
                    spreadRadius: 4,),
              ],
            ),
            child: const Center(
              child: Text('🎁', style: TextStyle(fontSize: 28)),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// HOME PAGE BANNER OFFERS  (Aug 19 2026 — Nizam's admin-created
// "home page banner offer" request)
// ================================================================
// Cache-first, version-gated exactly like ErodeOffersSection's
// _loadOffers() (see erode_offers_section.dart for the pattern this
// copies): a one-shot .get() behind a long-lived Hive cache, refetched
// only when MigrationGateService.homeBannerVersion moves (bumped once
// by the admin's own "Publish" button in admin_home_banner_screen.dart).
// A customer opening the app repeatedly on a quiet day costs zero
// Firestore reads.
//
// Deliberately its own top-level widget (not folded into _HomeTab)
// so it owns its own FutureBuilder / live-publish listener without
// forcing the entire home tab to rebuild on every version bump.
class _HomeBannerOffersSection extends StatefulWidget {
  const _HomeBannerOffersSection();

  @override
  State<_HomeBannerOffersSection> createState() => _HomeBannerOffersSectionState();
}

class _HomeBannerOffersSectionState extends State<_HomeBannerOffersSection> {
  static const String _versionCacheKey = 'home_banner_offers_version';

  Future<List<_BannerOfferRecord>?>? _future;
  int _lastAppliedVersion = -1;

  @override
  void initState() {
    super.initState();
    _future = _load();
    MigrationGateService.instance.addListener(_onGateChanged);
  }

  @override
  void dispose() {
    MigrationGateService.instance.removeListener(_onGateChanged);
    super.dispose();
  }

  void _onGateChanged() {
    final live = MigrationGateService.instance.homeBannerVersion;
    if (live == _lastAppliedVersion || !mounted) return;
    setState(() => _future = _load());
  }

  Future<List<_BannerOfferRecord>?> _load() async {
    final liveVersion = MigrationGateService.instance.homeBannerVersion;
    final cachedVersion = await HiveCache.get<int>(_versionCacheKey) ?? -1;
    final versionChanged = liveVersion != cachedVersion;
    _lastAppliedVersion = liveVersion;

    final raw = await HiveCache.cachedFetch<List<dynamic>>(
      HiveCache.kHomeBannerOffers,
      () async {
        final snap = await FirebaseFirestore.instance
            .collection('home_banner_offers')
            .where('isActive', isEqualTo: true)
            .get();
        return snap.docs.map((d) {
          final data = Map<String, dynamic>.from(d.data());
          final ts = data['createdAt'];
          return <String, dynamic>{
            '__id': d.id,
            '__createdAtMs': ts is Timestamp ? ts.millisecondsSinceEpoch : 0,
            ...data..remove('createdAt'),
          };
        }).toList();
      },
      ttl: HiveCache.ttlHomeBannerOffers,
      forceRefresh: versionChanged,
    );

    if (versionChanged && raw != null) {
      await HiveCache.put(_versionCacheKey, liveVersion, ttl: const Duration(days: 365));
    }

    if (raw == null) return null;

    final records = raw.map((e) => Map<String, dynamic>.from(e as Map)).toList()
      ..sort((a, b) => ((b['__createdAtMs'] as int?) ?? 0).compareTo((a['__createdAtMs'] as int?) ?? 0));

    return records
        .map((m) => _BannerOfferRecord(
              id: (m['__id'] as String?) ?? '',
              data: Map<String, dynamic>.from(m)
                ..remove('__id')
                ..remove('__createdAtMs'),
            ))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<_BannerOfferRecord>?>(
      future: _future,
      builder: (context, snapshot) {
        final offers = snapshot.data ?? const <_BannerOfferRecord>[];
        // No active banners -> render nothing at all, not even a gap.
        if (snapshot.connectionState != ConnectionState.waiting && offers.isEmpty) {
          return const SizedBox.shrink();
        }
        if (offers.isEmpty) return const SizedBox.shrink();

        final size = MediaQuery.of(context).size;
        final height = size.width * 0.46;

        return Padding(
          padding: const EdgeInsets.only(top: 14),
          child: SizedBox(
            height: height,
            child: PageView.builder(
              itemCount: offers.length,
              controller: PageController(viewportFraction: 0.94),
              itemBuilder: (context, index) {
                final offer = offers[index];
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: _HomeBannerCard(offerId: offer.id, data: offer.data),
                );
              },
            ),
          ),
        );
      },
    );
  }
}

class _BannerOfferRecord {
  const _BannerOfferRecord({required this.id, required this.data});
  final String id;
  final Map<String, dynamic> data;
}

class _HomeBannerCard extends StatelessWidget {
  final String offerId;
  final Map<String, dynamic> data;

  const _HomeBannerCard({required this.offerId, required this.data});

  @override
  Widget build(BuildContext context) {
    final shopName = (data['shopName'] as String?) ?? '';
    final imageUrl = (data['imageUrl'] as String?) ?? '';
    final videoId = youtubeVideoId(data['videoUrl'] as String?);

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => _HomeBannerDetailScreen(data: data),
        ),
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(20),
        child: Stack(
          fit: StackFit.expand,
          children: [
            // BoxFit.contain (per Nizam's explicit requirement — "whatever
            // image size admin uploads must render clearly on screen"):
            // an admin-uploaded banner of any aspect ratio is shown whole,
            // never cropped. Neutral backing so letterbox bars read as a
            // deliberate frame rather than a gap.
            Container(
              color: const Color(0xFFF3E7EF),
              child: imageUrl.isNotEmpty
                  ? CachedCloudImage(
                      imageUrl,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => const SizedBox.shrink(),
                    )
                  : const SizedBox.shrink(),
            ),
            if (videoId != null)
              Positioned(
                top: 10,
                right: 10,
                child: GestureDetector(
                  onTap: () => showPremiumVideoModal(
                    context,
                    videoId: videoId,
                    title: shopName.isNotEmpty ? shopName : 'Offer video',
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.55),
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 16),
                        SizedBox(width: 4),
                        Text('WATCH', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// Detail screen matching OfferDetailScreen's visual style exactly per
// Nizam's "ithe same style" requirement (see erode_offers_section.dart):
// full-size BoxFit.contain image, details below in a scrollable Column,
// reduced font sizes. Built as a lightweight equivalent here rather than
// reusing OfferDetailScreen directly because this collection carries a
// `description` field that screen doesn't render.
class _HomeBannerDetailScreen extends StatelessWidget {
  final Map<String, dynamic> data;
  const _HomeBannerDetailScreen({required this.data});

  @override
  Widget build(BuildContext context) {
    final shopName = (data['shopName'] as String?) ?? 'Shop';
    final description = (data['description'] as String?) ?? '';
    final address = (data['address'] as String?) ?? '';
    final phone = (data['phone'] as String?) ?? '';
    final imageUrl = data['imageUrl'] as String?;

    const Color ink = Color(0xFF121A3D);
    const Color muted = Color(0xFF6B7280);
    const Color pink = Color(0xFFFF4FA3);
    const Color purple = Color(0xFFB21FFF);

    return Scaffold(
      backgroundColor: const Color(0xFFFFF6FA),
      appBar: AppBar(
        backgroundColor: const Color(0xFFFFF6FA),
        elevation: 0,
        iconTheme: const IconThemeData(color: ink),
        title: Text('Offer Details', style: GoogleFonts.outfit(color: ink, fontWeight: FontWeight.w800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null && imageUrl.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(22),
                child: Container(
                  width: double.infinity,
                  constraints: BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.62),
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
                gradient: const LinearGradient(colors: [purple, pink]),
                borderRadius: BorderRadius.circular(26),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(shopName, style: GoogleFonts.outfit(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w900)),
                  if (description.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    Text(description, style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, fontWeight: FontWeight.w600, height: 1.4)),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (address.isNotEmpty)
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  border: Border.all(color: pink.withValues(alpha: 0.15)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.location_on_rounded, color: pink, size: 22),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Address', style: GoogleFonts.outfit(color: muted, fontSize: 9, fontWeight: FontWeight.w700)),
                          const SizedBox(height: 3),
                          Text(address, style: GoogleFonts.outfit(color: ink, fontSize: 11.5, fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            const SizedBox(height: 24),
            if (phone.isNotEmpty)
              GestureDetector(
                onTap: () async {
                  final uri = Uri(scheme: 'tel', path: phone);
                  if (await canLaunchUrl(uri)) await launchUrl(uri);
                },
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(colors: [Color(0xFF00C853), Color(0xFF00A843)]),
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Column(
                    children: [
                      const Icon(Icons.call_rounded, color: Colors.white, size: 22),
                      const SizedBox(height: 6),
                      Text('Call Shop', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 10)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// NEW (Nizam: "sila customer image paathe easy-a understand pannikuvanga
// andhandha section kulla povanga") — a 3rd icon theme, 'photo_realistic',
// for customers who recognize a real photo faster than a 3D render or flat
// glyph. One representative network photo per category, fetched through
// CachedCloudImage — same widget eseva_service_screen.dart already uses —
// so it downloads once and is served from disk cache on every later open
// (including offline). Deliberately ONE photo per category, not five: the
// mega-card row's 5 mini-icons stay whatever the OTHER active setting is
// (pink 3D or flat multicolor) — retrofitting 5 distinct real photos per
// category is a separate, much bigger asset job than this pass. Only the
// header icon and the top carousel's single icon switch to a photo.
// Top-level (not a class member) so both _HomeTab's _themedHeaderIcon and
// _CategorySlidingBannerState's carousel icon can share one source of truth.
const Map<String, String> kCategoryPhotoUrl = {
  'taxi': 'https://images.unsplash.com/photo-1449965408869-eaa3f722e40d?w=200&q=80',
  'food': 'https://images.unsplash.com/photo-1504674900247-0877df9cc836?w=200&q=80',
  'grocery': 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=200&q=80',
  'mobile': 'https://images.unsplash.com/photo-1580910051074-3eb694886505?w=200&q=80',
  'electronics': 'https://images.unsplash.com/photo-1550009158-9ebf69173e03?w=200&q=80',
  'carwash': 'https://images.unsplash.com/photo-1520340356584-f9917d1eea6f?w=200&q=80',
  'construction': 'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=200&q=80',
  'printing': 'https://images.unsplash.com/photo-1598327105666-5b89351cb315?w=200&q=80',
  'eseva': 'https://images.unsplash.com/photo-1580519542036-c47de6196ba5?w=200&q=80',
  'hero': 'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?w=200&q=80',
  'other_services': 'https://images.unsplash.com/photo-1581092160562-40aa08e78837?w=200&q=80',
  'broadband': 'https://images.unsplash.com/photo-1544197150-b99a580bb7a8?w=200&q=80',
};

// NEW (Nizam: "buttons mela 2d icon than therithu... mainpage yella option
// identify pandrathuku illa") — kCategoryPhotoUrl above only covers the
// ONE header photo per mega card; the actual 5 tappable buttons underneath
// (what a customer taps to pick bike vs auto vs cab, laptop vs PC vs CCTV,
// etc.) still showed the flat multicolor glyph even in Photo Realistic
// theme, which defeats the whole "recognize by photo, not icon" point.
// Key format: '<category>_<slot 1-5>'. Same CachedCloudImage/disk-cache
// mechanism as the header photo — one network fetch per photo, then
// served from cache on every later open including offline.
const Map<String, String> kSlotPhotoUrl = {
  // Taxi & Transportation: bike, auto, cab, parcel, mini truck/lorry
  'taxi_1': 'https://images.unsplash.com/photo-1558981806-ec527fa84c39?w=200&q=80',
  'taxi_2': 'https://images.unsplash.com/photo-1601362840469-51e4d8d58785?w=200&q=80',
  'taxi_3': 'https://images.unsplash.com/photo-1533473359331-0135ef1b58bf?w=200&q=80',
  'taxi_4': 'https://images.unsplash.com/photo-1595246140625-573b715d11dc?w=200&q=80',
  'taxi_5': 'https://images.unsplash.com/photo-1601584115197-04ecc0da31d7?w=200&q=80',
  // Food Delivery: 5 dish/cuisine shots
  'food_1': 'https://images.unsplash.com/photo-1585032226651-759b368d7246?w=200&q=80',
  'food_2': 'https://images.unsplash.com/photo-1567620905732-2d1ec7ab7445?w=200&q=80',
  'food_3': 'https://images.unsplash.com/photo-1601050690597-df0568f70950?w=200&q=80',
  'food_4': 'https://images.unsplash.com/photo-1601924582970-9238bcb495d9?w=200&q=80',
  'food_5': 'https://images.unsplash.com/photo-1550547660-d9450f859349?w=200&q=80',
  // Grocery: veggies, fruits, dairy/eggs, spices, packaged snacks
  'grocery_1': 'https://images.unsplash.com/photo-1518843875459-f738682238a6?w=200&q=80',
  'grocery_2': 'https://images.unsplash.com/photo-1610832958506-aa56368176cf?w=200&q=80',
  'grocery_3': 'https://images.unsplash.com/photo-1550583724-b2692b85b150?w=200&q=80',
  'grocery_4': 'https://images.unsplash.com/photo-1596040033229-a9821ebd058d?w=200&q=80',
  'grocery_5': 'https://images.unsplash.com/photo-1553546895-531931aa1aa8?w=200&q=80',
  // Mobiles: phone+battery, repair tools, sim/network, phone shop shelf, phone in hand
  'mobile_1': 'https://images.unsplash.com/photo-1511707171634-5f897ff02aa9?w=200&q=80',
  'mobile_2': 'https://images.unsplash.com/photo-1580522154071-c6ca47a859ec?w=200&q=80',
  'mobile_3': 'https://images.unsplash.com/photo-1556656793-08538906a9f8?w=200&q=80',
  'mobile_4': 'https://images.unsplash.com/photo-1573148195900-7845dcb9b127?w=200&q=80',
  'mobile_5': 'https://images.unsplash.com/photo-1601784551446-20c9e07cdbdb?w=200&q=80',
  // Electronics: laptop, PC/desktop, CCTV camera, TV, home theatre speaker
  'electronics_1': 'https://images.unsplash.com/photo-1496181133206-80ce9b88a853?w=200&q=80',
  'electronics_2': 'https://images.unsplash.com/photo-1587831990711-23ca6441447b?w=200&q=80',
  'electronics_3': 'https://images.unsplash.com/photo-1557324232-b8917d3c3dcb?w=200&q=80',
  'electronics_4': 'https://images.unsplash.com/photo-1593359677879-a4bb92f829d1?w=200&q=80',
  'electronics_5': 'https://images.unsplash.com/photo-1545454675-3531b543be5d?w=200&q=80',
  // Car Service: exterior wash foam, interior cleaning, engine/repair tools, spares, tow/pickup
  'carwash_1': 'https://images.unsplash.com/photo-1607860108855-64acf2078ed9?w=200&q=80',
  'carwash_2': 'https://images.unsplash.com/photo-1601362840469-51e4d8d58785?w=200&q=80',
  'carwash_3': 'https://images.unsplash.com/photo-1486262715619-67b85e0b08d3?w=200&q=80',
  'carwash_4': 'https://images.unsplash.com/photo-1486006920555-c77dcf18193c?w=200&q=80',
  'carwash_5': 'https://images.unsplash.com/photo-1517524008697-84bbe3c3fd98?w=200&q=80',
  // Construction: bricks/cement, scaffolding/building, hardhat worker, excavator, mixer truck
  'construction_1': 'https://images.unsplash.com/photo-1541976590-713941681591?w=200&q=80',
  'construction_2': 'https://images.unsplash.com/photo-1503387762-592deb58ef4e?w=200&q=80',
  'construction_3': 'https://images.unsplash.com/photo-1516937941344-00b4e0337589?w=200&q=80',
  'construction_4': 'https://images.unsplash.com/photo-1581094794329-c8112a89af12?w=200&q=80',
  'construction_5': 'https://images.unsplash.com/photo-1578844251758-2f71da64c96f?w=200&q=80',
  // Designing & Printing: business cards, flex banner, notebook/bill book, ad/megaphone, design on screen
  'printing_1': 'https://images.unsplash.com/photo-1589998059171-988d887df646?w=200&q=80',
  'printing_2': 'https://images.unsplash.com/photo-1541746972996-4e0b0f43e02a?w=200&q=80',
  'printing_3': 'https://images.unsplash.com/photo-1544816155-12df9643f363?w=200&q=80',
  'printing_4': 'https://images.unsplash.com/photo-1533750349088-cd871a92f312?w=200&q=80',
  'printing_5': 'https://images.unsplash.com/photo-1561070791-2526d30994b5?w=200&q=80',
  // E-Seva: ID card, voter/certificate, fingerprint/aadhaar, documents, laptop e-service
  'eseva_1': 'https://images.unsplash.com/photo-1580519542036-c47de6196ba5?w=200&q=80',
  'eseva_2': 'https://images.unsplash.com/photo-1580128637411-70dfaf5ba591?w=200&q=80',
  'eseva_3': 'https://images.unsplash.com/photo-1614064548237-096d5814680f?w=200&q=80',
  'eseva_4': 'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=200&q=80',
  'eseva_5': 'https://images.unsplash.com/photo-1516321318423-f06f85e504b3?w=200&q=80',
  // Book a Hero: helper/handyman, SOS/emergency, parcel delivery, shopping bags errand, bike delivery
  'hero_1': 'https://images.unsplash.com/photo-1600880292203-757bb62b4baf?w=200&q=80',
  'hero_2': 'https://images.unsplash.com/photo-1584036561566-baf8f5f1b144?w=200&q=80',
  'hero_3': 'https://images.unsplash.com/photo-1595246140625-573b715d11dc?w=200&q=80',
  'hero_4': 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=200&q=80',
  'hero_5': 'https://images.unsplash.com/photo-1571068316344-75bc76f77890?w=200&q=80',
  // Electrician: wiring/outlet work, hardhat electrician, switch box wiring, panel repair, circuit breaker panel
  'electrician_1': 'https://images.unsplash.com/photo-1621905251189-08b45d6a269e?w=200&q=80',
  'electrician_2': 'https://images.unsplash.com/photo-1682345262055-8f95f3c513ea?w=200&q=80',
  'electrician_3': 'https://images.unsplash.com/photo-1555963966-b7ae5404b6ed?w=200&q=80',
  'electrician_4': 'https://images.unsplash.com/photo-1635335874521-7987db781153?w=200&q=80',
  'electrician_5': 'https://images.unsplash.com/photo-1660330589693-99889d60181e?w=200&q=80',
  // Puncture / Tyre: flat tyre closeup, mechanic changing tyre, worn tyre, wrench beside tyre, flat tyre roadside
  'puncture_1': 'https://images.unsplash.com/photo-1449426468159-d96dbf08f19f?w=200&q=80',
  'puncture_2': 'https://images.unsplash.com/photo-1601739722627-f00a99138ea1?w=200&q=80',
  'puncture_3': 'https://images.unsplash.com/photo-1596383765797-8e10e88d1590?w=200&q=80',
  'puncture_4': 'https://images.unsplash.com/photo-1647292882945-d5c839432d7e?w=200&q=80',
  'puncture_5': 'https://images.unsplash.com/photo-1568775376697-e16970e74861?w=200&q=80',
  // Internet / Broadband: antenna signal bars, wifi router, network modem, router+switch, close-up wireless router
  'internet_1': 'https://images.unsplash.com/photo-1544197150-b99a580bb7a8?w=200&q=80',
  'internet_2': 'https://images.unsplash.com/photo-1645725677294-ed0843b97d5c?w=200&q=80',
  'internet_3': 'https://images.unsplash.com/photo-1606904825846-647eb07f5be2?w=200&q=80',
  'internet_4': 'https://images.unsplash.com/photo-1516044734145-07ca8eef8731?w=200&q=80',
  'internet_5': 'https://images.unsplash.com/photo-1681383064412-171e5bee5f6e?w=200&q=80',
};

// ================================================================
// HOME TAB (Redesigned with Mega Cards)
// ================================================================
class _HomeTab extends StatelessWidget {
  final void Function(String) onTileTap;
  final User? user;
  final Stream<DocumentSnapshot> userStream;

  const _HomeTab({
    required this.onTileTap,
    required this.user,
    required this.userStream,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        // NEW (Aug 13 2026 — Erode "₹50,000 கோடி பொருளாதாரப் புரட்சி"
        // campaign). Deliberately its OWN static card rather than a slide
        // inside _CategorySlidingBanner below: that carousel auto-rotates
        // every 4s, which is fine for one-line category promos but would
        // sweep a two-sentence manifesto off screen before anyone finished
        // reading it. A campaign message that nobody can finish reading is
        // worse than no campaign message. Sits above the carousel so it is
        // the first thing on the home screen, and taps through to the full
        // data breakdown in EconomicVisionScreen.
        const EconomicVisionBanner(),
        // NEW (Aug 19 2026 — Nizam's "home page banner offer" request).
        // Own section, own Firestore collection (home_banner_offers),
        // own cache key/version — see _HomeBannerOffersSection below.
        // Renders nothing at all (not even a SizedBox gap) when there
        // are no active banners, so a quiet day never leaves a hole on
        // the home screen.
        const _HomeBannerOffersSection(),
        const SizedBox(height: 14),
        _CategorySlidingBanner(onTileTap: onTileTap),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(context.watch<LocalizationService>().t('what_need_today'),
              style: GoogleFonts.outfit(
                  fontSize: 17, fontWeight: FontWeight.w800, color: kText,),),
        ),
        const SizedBox(height: 12),
        
        // ── MEGA CARDS REVAMP ──────────────────────────────
        _buildHeroBookingMegaCard(context),
        const SizedBox(height: 12),
        _buildTaxiMegaCard(context),
        const SizedBox(height: 12),
        // 3rd position, per Nizam (Aug 18 2026) — the Mobile Hub sits
        // directly under Taxi so it's visible without scrolling.
        _buildMobilesMegaCard(context),
        const SizedBox(height: 12),
        _buildFoodMegaCard(context),
        const SizedBox(height: 12),
        _buildGroceryMegaCard(context),
        const SizedBox(height: 12),
        _buildElectronicsMegaCard(context),
        const SizedBox(height: 12),
        _buildCarServiceMegaCard(context),
        const SizedBox(height: 12),
        _buildConstructionMegaCard(context),
        const SizedBox(height: 12),
        _buildElectricianMegaCard(context),
        const SizedBox(height: 12),
        _buildPunctureMegaCard(context),
        const SizedBox(height: 12),
        _buildInternetMegaCard(context),
        const SizedBox(height: 12),
        _buildPrintingMegaCard(context),
        const SizedBox(height: 12),
        _buildEsevaMegaCard(context),
        const SizedBox(height: 12),
        _buildOtherServicesMegaCard(context),
        // ───────────────────────────────────────────────────

        const SizedBox(height: 12),
        _buildFeaturedShop(context),
        const SizedBox(height: 10),
        _buildPromoCards(context),
        const SizedBox(height: 20),
        // NEW (Aug 12 2026 — Nizam: "namma customer app top la sling
        // animations... athulla 10 sliding oodavidalam"): 10 promo slides,
        // one per requested category. All render as local vector-icon
        // gradient cards (BannerTextSlide) rather than hosted images — so
        // unlike the old 2 Unsplash stock photos below, these cost zero
        // network calls and show up instantly on every load, first-time
        // included. That's a stronger guarantee than a Hive-cached network
        // image would give, while still fully satisfying the "must not lag,
        // fast from reopen" requirement. Each onTap reuses the exact same
        // navigation targets as their matching mega-cards below, so tapping
        // a slide always opens the same real screen the corresponding tile
        // already opens. Food slide names real, already-onboarded partner
        // shops (KFC/A2B/Subway/Domino's/Taj) — see CustomFoodOrderScreen, which
        // links out to each shop's own ordering site via PartnerShopOrderScreen.
        BannerAdsSlider(
          height: 240,
          textSlides: [
            BannerTextSlide(
              title: 'Taxi & Transport 🚖',
              subtitle: 'Bike, auto, car, parcel & more — book a ride in seconds',
              gradient: const [Color(0xFFFF4FA3), Color(0xFF7B2FF7)],
              icon: Icons.local_taxi_rounded,
              onTap: () => onTileTap('taxi'),
            ),
            BannerTextSlide(
              title: 'Food from KFC, A2B, Subway, Domino\'s & Taj 🍽️',
              subtitle: 'Erode\'s favourite restaurants, one tap away',
              gradient: const [Color(0xFFFF7A45), Color(0xFFFF4FA3)],
              icon: Icons.restaurant_rounded,
              onTap: () => onTileTap('food'),
            ),
            BannerTextSlide(
              title: 'Grocery Delivered 🛒',
              subtitle: 'Daily essentials, straight to your door',
              gradient: const [Color(0xFF43C6AC), Color(0xFF2E9E7B)],
              icon: Icons.shopping_basket_rounded,
              onTap: () => onTileTap('grocery'),
            ),
            BannerTextSlide(
              title: 'Book a Hero 🦸',
              subtitle: 'On-demand help for any task, any time',
              gradient: const [Color(0xFF6C63FF), Color(0xFF7B2FF7)],
              icon: Icons.emoji_people_rounded,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const HeroBookingScreen()),
              ),
            ),
            BannerTextSlide(
              title: 'Car Service & Polish 🚗',
              subtitle: 'Wash, polish & servicing at your doorstep',
              gradient: const [Color(0xFF2193B0), Color(0xFF6DD5ED)],
              icon: Icons.local_car_wash_rounded,
              onTap: () => onTileTap('carwash'),
            ),
            BannerTextSlide(
              title: 'Construction & Alteration 🏗️',
              subtitle: 'Building work, alterations & crane services',
              gradient: const [Color(0xFFB79891), Color(0xFF94716B)],
              icon: Icons.construction_rounded,
              onTap: () => onTileTap('construction'),
            ),
            // SKILL HEROES (Aug 29 2026) — the customer-side entry
            // for electrician / plumber / laptop & PC / TV / fridge &
            // AC. Sits beside Construction because that is the same
            // mental category for a customer with a broken thing at
            // home.
            BannerTextSlide(
              title: 'Home Services 🔧',
              subtitle: 'Electrician, plumber, AC, TV & laptop — Heroes within 5 km',
              gradient: const [Color(0xFF2D9CDB), Color(0xFF56CCF2)],
              icon: Icons.handyman_rounded,
              onTap: () => onTileTap('homeservices'),
            ),
            BannerTextSlide(
              title: 'Electronic Services 🔌',
              subtitle: 'Repairs, spares & gadget store — all in one place',
              gradient: const [Color(0xFF0F2027), Color(0xFF2C5364)],
              icon: Icons.electrical_services_rounded,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const NJTechStoreScreen()),
              ),
            ),
            BannerTextSlide(
              title: 'Visiting Cards, Bill Books & Flex Printing 🖨️',
              subtitle: 'Design & print — delivered to your shop or home',
              gradient: const [Color(0xFFF7971E), Color(0xFFFFD200)],
              icon: Icons.print_rounded,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const PrintingServiceScreen()),
              ),
            ),
            BannerTextSlide(
              title: 'E-Seva Services 📋',
              subtitle: 'Government service solutions — coming soon',
              gradient: const [Color(0xFF11998E), Color(0xFF38EF7D)],
              icon: Icons.assignment_turned_in_rounded,
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(builder: (_) => const ComingSoonScreen(role: 'E-Seva')),
              ),
            ),
          ],
          imageUrls: const [],
        ),
        const SizedBox(height: 100),
      ],),
    );
  }

  // ── TAXI MEGA CARD ────────────────────────────────────────────────
  Widget _buildTaxiMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            // FIX (per Nizam's request — tappable section headings):
            // heading now opens the same screen as the tile below,
            // matching the tile's own onTap exactly.
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const BikeBookingScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'taxi', '3', SvgPicture.string(FluentEmojiFlat.taxi, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('taxi_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('taxi_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            // NEW (CTO mandate — Synthetic QA Test-Bot): stable Key for
            // integration_test to find this tile without depending on
            // icon/copy text, which the QA bot must not be fragile to.
            key: const Key('dashboard_tile_bike'),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const BikeBookingScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── REAL VEHICLE PHOTOS, NOT CARTOON EMOJI ──────
                  // (Aug 19 2026, Nizam: "antha button kulla icons
                  // yelleme cartoon look la iruku".)
                  //
                  // These were FluentEmojiFlat SVG emoji — flat cartoon
                  // glyphs. Two problems with that: they clashed with
                  // Food Delivery right below, which already uses real
                  // photos, and they showed a customer a cartoon scooter
                  // for a service where the very next screen shows the
                  // actual vehicle photo. The button now previews what
                  // the customer is about to pick.
                  //
                  // Sourced from the SAME assets the taxi vehicle
                  // selection screen uses (ride_catalog.dart), so the
                  // preview and the picker can never show different
                  // vehicles for the same service.
                  //
                  // AutoImageSlider is Food's exact widget — identical
                  // fade+slide, identical staggered durations, so the
                  // two rows read as one system. fit: contain because
                  // these are wide cut-out PNGs; cover would crop the
                  // nose and tail off every vehicle (see the fit doc in
                  // auto_image_slider.dart).
                  // Order matches Nizam's spec: bike, auto, yellow car,
                  // truck, lorry.
                  //
                  // EVERY path below points at a file that EXISTS today,
                  // so no slot ever blinks empty. The top_*.png images
                  // are NOT copied into taxi_slides/ — duplicating them
                  // would ship the same bytes twice in the APK for no
                  // gain. A folder is just a path; the slider does not
                  // care which one an image lives in.
                  //
                  // The realistic photos Nizam is adding
                  // (motorcycle.png, white_car.png) go in taxi_slides/
                  // and get appended to the matching list below — one
                  // word each, no restructuring.
                  // EVERY vehicle the taxi picker offers now appears in
                  // this row (Nizam: "namma taxi la iruka yella icons
                  // um button la irukamari pannu"). ride_catalog.dart
                  // lists seven — bike, auto, cab, parcel, mini truck,
                  // lorry, SOS — and there are five slots, so each slot
                  // owns one vehicle and cycles its variants: the new
                  // photo-real render first, the flat catalog icon
                  // second. Nothing is left out, and the slot still
                  // means one thing.
                  //
                  // SOS is deliberately the only one NOT here: it is an
                  // emergency action, not a vehicle to browse, and
                  // putting a red alert badge in a decorative carousel
                  // would both cheapen it and worry people.
                  _themedSlot(context, 'taxi', 1, const Duration(seconds: 3), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/taxi_slides/motorcycle.png', 'assets/images/top_bike.png'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(seconds: 3)))),
                  _themedSlot(context, 'taxi', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/top_auto.png'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(milliseconds: 3200)))),
                  _themedSlot(context, 'taxi', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/taxi_slides/yellow_car.png', 'assets/images/taxi_slides/white_car.png', 'assets/images/top_cab.png'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(milliseconds: 2800)))),
                  _themedSlot(context, 'taxi', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/taxi_slides/parcel.png', 'assets/images/top_parcel.png'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(milliseconds: 3500)))),
                  _themedSlot(context, 'taxi', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/top_mini_truck.png', 'assets/images/top_lorry.png'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(milliseconds: 3100)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }


  // NEW (Nizam: "sila customer image paathe easy-a understand pannikuvanga
  // andhandha section kulla povanga") — a 3rd icon theme, 'photo_realistic',
  // for customers who recognize a real photo faster than a 3D render or
  // flat glyph. One representative network photo per category, fetched
  // through CachedCloudImage — same widget eseva_service_screen.dart
  // already uses — so it downloads once and is served from disk cache
  // on every later open (including offline). Deliberately ONE photo per
  // category, not five: the mega-card row's 5 mini-icons stay whatever
  // the OTHER active setting is (pink 3D or flat multicolor) — retrofitting
  // 5 distinct real photos per category is a separate, much bigger asset
  // job than this pass. Only the header icon and the top carousel's
  // single icon switch to a photo.
  // Small section-header icon (the one next to "Hero Booking" / "Taxi &
  // Transportation" / "Food Delivery" titles) — swaps the flat FluentEmoji
  // glyph for that category's own pink_icons render so the header matches
  // the row of icons underneath instead of staying multicolor.
  Widget _themedHeaderIcon(BuildContext context, String category, String slot, Widget defaultIcon) {
    final iconTheme = context.watch<ThemeService>().iconThemeKey;
    // CHANGED (Nizam: "catogory name ku munnadi irukka image ah remove
    // pannitu anga text iruntha screen la namaku konjam space kidaikkum")
    // — the header used to show a small (32x32) photo next to the title;
    // dropped entirely in Photo Realistic theme so the title text gets
    // that width back, and because the REAL identification work now
    // happens on the 5 bigger buttons below (_themedSlot), not this tiny
    // header thumbnail.
    if (iconTheme == 'photo_realistic') {
      return const SizedBox.shrink();
    }
    if (iconTheme == 'pink_white_3d') {
      // No ClipOval here: these renders already have their background
      // removed (transparent webp), so circle-cropping just chopped off
      // parts of the subject for no reason. Contain lets the full
      // transparent cutout float on the card instead.
      return Image.asset(
        'assets/images/pink_icons/${category}_${slot}_a.webp',
        width: 22,
        height: 22,
        fit: BoxFit.contain,
        errorBuilder: (_, __, ___) => defaultIcon,
      );
    }
    return defaultIcon;
  }

  Widget _themedSlot(BuildContext context, String category, int slot, Duration duration, Widget defaultSlot, {bool hasThirdFrame = false}) {
    final iconTheme = context.watch<ThemeService>().iconThemeKey;
    final slotPhoto = kSlotPhotoUrl['${category}_$slot'];
    if (iconTheme == 'photo_realistic' && slotPhoto != null) {
      // CHANGED (Nizam: "button big-a panni antha button suthi irukka
      // pink line ku konjam mattum gape irukamari") — grown from 44 to
      // 50 inside the mega card row's fixed 56px-tall container, leaving
      // just a ~3px gap to the pink border on each side instead of the
      // wider gap the other two themes' 44px icon leaves.
      //
      // CHANGED (Nizam: "orey image asingala... ovvoru button layum
      // smooth animation oodatum") — reuses the SAME AutoWidgetSlider
      // (fade+slide crossfade) the pink_white_3d theme already uses for
      // its a/b frames, just fed CachedCloudImage widgets instead of
      // local assets, so it's our own established animation language,
      // not a new one-off.
      //
      // FIX (Nizam: "orey photove again and again varuthu... 5 images
      // set pannu, onnu maathi onnu varanum") — the previous version
      // crossfaded each button between ITS OWN photo and the category's
      // ONE shared header photo, so all 5 buttons in a row kept
      // converging on that same shared frame and looked repetitive.
      // Now each button cycles through ALL 5 of the category's photos
      // (still the same 50 URLs already sourced, no new fetching),
      // just started at ITS OWN slot so slot 1 shows order [1,2,3,4,5],
      // slot 2 shows [2,3,4,5,1], etc. — every button always shows a
      // different frame than its neighbours at any given moment, and
      // no photo is shared/repeated across the row.
      Widget photoTile(String url) => ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: CachedCloudImage(
              url,
              width: 50,
              height: 50,
              fit: BoxFit.cover,
              cacheWidth: 200,
              errorWidget: defaultSlot,
            ),
          );
      final rotated = List.generate(5, (i) => kSlotPhotoUrl['${category}_${((slot - 1 + i) % 5) + 1}'])
          .whereType<String>()
          .toSet() // dedupe in case a category has fewer than 5 distinct entries
          .toList();
      return AutoWidgetSlider(
        width: 50,
        height: 50,
        duration: duration,
        children: rotated.map(photoTile).toList(),
      );
    }
    if (iconTheme == 'pink_white_3d') {
      // No ClipOval: these are already background-removed transparent
      // cutouts (bg-removed at asset-prep time), so a circular clip just
      // chops off part of the subject for no reason — contain shows the
      // whole render floating on the card instead.
      return AutoImageSlider(
        imagePaths: [
          'assets/images/pink_icons/${category}_${slot}_a.webp',
          'assets/images/pink_icons/${category}_${slot}_b.webp',
          if (hasThirdFrame) 'assets/images/pink_icons/${category}_${slot}_c.webp',
        ],
        width: 44,
        height: 44,
        fit: BoxFit.contain,
        duration: duration,
        // FIX: categories with no dedicated 3D render yet (Electrician,
        // Puncture, Internet as of this change) used to show a blank
        // slot in this theme instead of the flat icon every other theme
        // already shows — now degrades to the same defaultSlot instead.
        fallback: defaultSlot,
      );
    }
    return defaultSlot;
  }

  // ── FOOD MEGA CARD ────────────────────────────────────────────────
  Widget _buildFoodMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomFoodOrderScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'food', '5', SvgPicture.string(FluentEmojiFlat.hamburger, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('food_delivery_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('food_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            key: const Key('dashboard_tile_food'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const CustomFoodOrderScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'food', 1, const Duration(seconds: 3), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/food_slides/slide1.png', 'assets/images/food_slides/slide6.png'], width: 34, height: 34, duration: const Duration(seconds: 3)))),
                  _themedSlot(context, 'food', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/food_slides/slide2.png', 'assets/images/food_slides/slide7.png'], width: 34, height: 34, duration: const Duration(milliseconds: 3200)))),
                  _themedSlot(context, 'food', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/food_slides/slide3.png', 'assets/images/food_slides/slide8.jpg'], width: 34, height: 34, duration: const Duration(milliseconds: 2800)))),
                  _themedSlot(context, 'food', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/food_slides/slide4.jpg', 'assets/images/food_slides/slide1.png'], width: 34, height: 34, duration: const Duration(milliseconds: 3500)))),
                  _themedSlot(context, 'food', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/food_slides/slide5.jpg', 'assets/images/food_slides/slide2.png'], width: 34, height: 34, duration: const Duration(milliseconds: 3100)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── GROCERY MEGA CARD ────────────────────────────────────────────
  Widget _buildGroceryMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const GroceryOrderScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'grocery', '1', SvgPicture.string(FluentEmojiFlat.shopping_cart, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('grocery_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('grocery_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            key: const Key('dashboard_tile_grocery'),
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const GroceryOrderScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'grocery', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.leafy_green), SvgPicture.string(FluentEmojiFlat.broccoli)]))),
                  _themedSlot(context, 'grocery', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.red_apple), SvgPicture.string(FluentEmojiFlat.banana)]))),
                  _themedSlot(context, 'grocery', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.carrot), SvgPicture.string(FluentEmojiFlat.potato)]))),
                  _themedSlot(context, 'grocery', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.onion), SvgPicture.string(FluentEmojiFlat.garlic)])), hasThirdFrame: true),
                  _themedSlot(context, 'grocery', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.shopping_cart), SvgPicture.string(FluentEmojiFlat.shopping_bags)])), hasThirdFrame: true),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ELECTRONICS MEGA CARD (Slim Static Layout) ───────────────────────
  // ── MOBILES MEGA CARD (Allin1 Mobile Hub) ─────────────────────────
  // NEW (Aug 18 2026, Nizam: "customer main page la 3rd la oru button…
  // namma myallin1 mobile hub ah maathanum"). Sits 3rd among the mega
  // cards, directly after Taxi.
  //
  // Deliberately the SAME hand-written shape as every other mega card
  // (header row + 56px kPink strip of emoji icons) rather than a new
  // component — a one-off style here would read as a bolted-on section.
  //
  // All five icons below are from the set already proven present in
  // this app's colorful_iconify_flutter version (verified against every
  // FluentEmojiFlat reference in lib/) — a missing constant would fail
  // the build for all four flavours.
  Widget _buildMobilesMegaCard(BuildContext context) {
    void openHub([int tab = 0]) {
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => MobileHubScreen(initialTab: tab)),
      );
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: openHub,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'mobile', '1', SvgPicture.string(FluentEmojiFlat.mobile_phone,
                            width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('mobiles_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('mobiles_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: openHub,
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border:
                    Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'mobile', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.mobile_phone), SvgPicture.string(FluentEmojiFlat.laptop)]))),
                  _themedSlot(context, 'mobile', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.battery), SvgPicture.string(FluentEmojiFlat.electric_plug)]))),
                  _themedSlot(context, 'mobile', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.hammer_and_wrench), SvgPicture.string(FluentEmojiFlat.gear)]))),
                  _themedSlot(context, 'mobile', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.shopping_bags), SvgPicture.string(FluentEmojiFlat.shopping_cart)]))),
                  _themedSlot(context, 'mobile', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.label), SvgPicture.string(FluentEmojiFlat.receipt)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildElectronicsMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NJTechStoreScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'electronics', '2', SvgPicture.string(FluentEmojiFlat.mobile_phone, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('electronics_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('electronics_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const NJTechStoreScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'electronics', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 44, height: 44, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.mobile_phone), SvgPicture.string(FluentEmojiFlat.battery)]))),
                  _themedSlot(context, 'electronics', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 44, height: 44, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.laptop), SvgPicture.string(FluentEmojiFlat.desktop_computer)]))),
                  _themedSlot(context, 'electronics', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 44, height: 44, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.desktop_computer), SvgPicture.string(FluentEmojiFlat.floppy_disk)]))),
                  _themedSlot(context, 'electronics', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 44, height: 44, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.video_camera), SvgPicture.string(FluentEmojiFlat.camera)]))),
                  _themedSlot(context, 'electronics', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 44, height: 44, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.television), SvgPicture.string(FluentEmojiFlat.radio)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CAR SERVICE MEGA CARD (Slim Static Layout) ────────────────────
  Widget _buildCarServiceMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const CarWashScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'carwash', '1', SvgPicture.string(FluentEmojiFlat.oncoming_taxi, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('carservice_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('carservice_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const CarWashScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'carwash', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.oncoming_taxi), SvgPicture.string(FluentEmojiFlat.sport_utility_vehicle)]))),
                  _themedSlot(context, 'carwash', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.sweat_droplets), SvgPicture.string(FluentEmojiFlat.sponge)]))),
                  _themedSlot(context, 'carwash', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.gear), SvgPicture.string(FluentEmojiFlat.nut_and_bolt)]))),
                  _themedSlot(context, 'carwash', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.hammer_and_wrench), SvgPicture.string(FluentEmojiFlat.wrench)]))),
                  _themedSlot(context, 'carwash', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.sport_utility_vehicle), SvgPicture.string(FluentEmojiFlat.oncoming_automobile)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ELECTRICIAN MEGA CARD (own standalone button, same shell as
  // every other mega card — was previously only a small tile shared
  // inside Other Services' row + a banner slide; promoted per Nizam's
  // "adhukum oru main button set pannirlam, other buttons yepdi
  // irukanumo apdi same style la" request) ──────────────────────────
  Widget _buildElectricianMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen(initialCategory: 'electrician'))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'electrician', '1', SvgPicture.string(FluentEmojiFlat.high_voltage, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('electrician_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('electrician_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen(initialCategory: 'electrician'))),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'electrician', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.high_voltage), SvgPicture.string(FluentEmojiFlat.electric_plug)]))),
                  _themedSlot(context, 'electrician', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.light_bulb), SvgPicture.string(FluentEmojiFlat.electric_plug)]))),
                  _themedSlot(context, 'electrician', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.gear), SvgPicture.string(FluentEmojiFlat.nut_and_bolt)]))),
                  _themedSlot(context, 'electrician', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.hammer_and_wrench), SvgPicture.string(FluentEmojiFlat.wrench)]))),
                  _themedSlot(context, 'electrician', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.high_voltage), SvgPicture.string(FluentEmojiFlat.light_bulb)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PUNCTURE / TYRE MEGA CARD (own standalone button) ─────────────
  Widget _buildPunctureMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen(initialCategory: 'puncture'))),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'puncture', '1', SvgPicture.string(FluentEmojiFlat.motorcycle, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('puncture_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('puncture_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(context, MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen(initialCategory: 'puncture'))),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'puncture', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.motorcycle), SvgPicture.string(FluentEmojiFlat.wrench)]))),
                  _themedSlot(context, 'puncture', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.gear), SvgPicture.string(FluentEmojiFlat.nut_and_bolt)]))),
                  _themedSlot(context, 'puncture', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.hammer_and_wrench), SvgPicture.string(FluentEmojiFlat.wrench)]))),
                  _themedSlot(context, 'puncture', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.oncoming_automobile), SvgPicture.string(FluentEmojiFlat.motorcycle)]))),
                  _themedSlot(context, 'puncture', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.motorcycle), SvgPicture.string(FluentEmojiFlat.gear)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── INTERNET / BROADBAND MEGA CARD (own standalone button) ────────
  Widget _buildInternetMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const NjTechBroadbandWebView()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'internet', '1', SvgPicture.string(FluentEmojiFlat.antenna_bars, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('internet_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('internet_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const NjTechBroadbandWebView()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'internet', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.antenna_bars), SvgPicture.string(FluentEmojiFlat.satellite_antenna)]))),
                  _themedSlot(context, 'internet', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.globe_with_meridians), SvgPicture.string(FluentEmojiFlat.satellite)]))),
                  _themedSlot(context, 'internet', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.satellite_antenna), SvgPicture.string(FluentEmojiFlat.antenna_bars)]))),
                  _themedSlot(context, 'internet', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.globe_with_meridians), SvgPicture.string(FluentEmojiFlat.antenna_bars)]))),
                  _themedSlot(context, 'internet', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.satellite), SvgPicture.string(FluentEmojiFlat.globe_with_meridians)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── CONSTRUCTION MEGA CARD (Slim Static Layout) ───────────────────
  Widget _buildConstructionMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const ConstructionScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'construction', '1', SvgPicture.string(FluentEmojiFlat.building_construction, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('construction_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('construction_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const ConstructionScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'construction', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.building_construction), SvgPicture.string(FluentEmojiFlat.house)]))),
                  _themedSlot(context, 'construction', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.brick), SvgPicture.string(FluentEmojiFlat.wood)]))),
                  _themedSlot(context, 'construction', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.construction_worker), SvgPicture.string(FluentEmojiFlat.man_construction_worker)]))),
                  _themedSlot(context, 'construction', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.triangular_ruler), SvgPicture.string(FluentEmojiFlat.straight_ruler)]))),
                  _themedSlot(context, 'construction', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.office_building), SvgPicture.string(FluentEmojiFlat.classical_building)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── HERO BOOKING MEGA CARD ───────────────────────────────────────
  Widget _buildHeroBookingMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HeroBookingScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'hero', '1', SvgPicture.string(FluentEmojiFlat.man_superhero, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('hero_booking_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('hero_booking_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const HeroBookingScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  // ── HERO BOOKING ROW ────────────────────────────
                  // The two 3D delivery-partner renders Nizam sent go
                  // here (slots 1 and 5) — they ARE the Hero, so they
                  // anchor the row at both ends.
                  //
                  // Slot 3 uses the same real parcel photo as the Taxi
                  // row, so "parcel" looks identical wherever it
                  // appears.
                  //
                  // Slots 2 and 4 (errand / shopping) are STILL cartoon
                  // emoji, and that is a known gap, not an oversight:
                  // there is no photo asset in the project for either
                  // concept. Substituting an unrelated vehicle photo
                  // just to avoid mixing styles would be worse — the
                  // icon would stop meaning what it says. Two more
                  // images finish this row; see the note handed to
                  // Nizam with the filenames.
                  // Slots 1 and 5 lead with an image that EXISTS today
                  // (erode_delivery_hero.png, already in assets/images)
                  // and list Nizam's two 3D renders after it. While
                  // hero_slides/ is still empty those two frames are
                  // skipped by errorBuilder and the existing hero photo
                  // simply holds the slot — so the row looks finished
                  // now and gets richer the moment the files land, with
                  // no code change and no empty circles in between.
                  // superman_hero.webp reused per Nizam, rather than
                  // shipping another asset for the same idea. It is an
                  // ANIMATED WebP (27 frames), so this slot has its own
                  // motion on top of the slider's cross-fade — which is
                  // why it earns the lead position. Remaining icons get
                  // replaced next phase.
                  _themedSlot(context, 'hero', 1, const Duration(seconds: 3), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/gifs/superman_hero.webp', 'assets/images/hero_slides/delivery_man_blue.png', 'assets/images/erode_delivery_hero.png'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(seconds: 3)))),
                  _themedSlot(context, 'hero', 4, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 44, height: 44, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.high_voltage), SvgPicture.string(FluentEmojiFlat.collision)]))),
                  _themedSlot(context, 'hero', 2, const Duration(milliseconds: 2800), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/top_parcel.png', 'assets/taxi/parcel.png'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(milliseconds: 2800)))),
                  _themedSlot(context, 'hero', 5, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 44, height: 44, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.shopping_bags), SvgPicture.string(FluentEmojiFlat.shopping_cart)]))),
                  _themedSlot(context, 'hero', 3, const Duration(milliseconds: 3100), ClipOval(child: AutoImageSlider(imagePaths: const ['assets/images/hero_slides/delivery_man_green.png', 'assets/images/erode_delivery_hero.png', 'assets/gifs/superman_hero.webp'], width: 44, height: 44, fit: BoxFit.contain, duration: const Duration(milliseconds: 3100)))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── PRINTING MEGA CARD ─────────────────────────────────────────
  Widget _buildPrintingMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrintingServiceScreen()),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'printing', '1', SvgPicture.string(FluentEmojiFlat.printer, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('printing_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('printing_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const PrintingServiceScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'printing', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.card_index), SvgPicture.string(FluentEmojiFlat.card_file_box)]))),
                  _themedSlot(context, 'printing', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.scroll), SvgPicture.string(FluentEmojiFlat.page_facing_up)]))),
                  _themedSlot(context, 'printing', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.framed_picture), SvgPicture.string(FluentEmojiFlat.artist_palette)]))),
                  _themedSlot(context, 'printing', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.label), SvgPicture.string(FluentEmojiFlat.bookmark)]))),
                  _themedSlot(context, 'printing', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.printer), SvgPicture.string(FluentEmojiFlat.camera)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── E-SEVA MEGA CARD ────────────────────────────────────────────
  // NEW (Aug 12 2026 — Nizam: "designing and printing kum other
  // services kum middile E Seva services kondu varaporom"): opens
  // EsevaServiceScreen, which lists each e-Seva service (PAN,
  // Aadhaar, Passport, Voter ID, etc.) as its own icon tile — those
  // tiles are intentionally dummy (no action) for now, with a
  // Call/WhatsApp contact section below per his explicit instruction.
  Widget _buildEsevaMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EsevaServiceScreen()),
              );
            },
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        _themedHeaderIcon(context, 'eseva', '1', SvgPicture.string(FluentEmojiFlat.scroll, width: 20, height: 20)),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text.rich(
                            TextSpan(children: [
                              TextSpan(
                                text: context.watch<LocalizationService>().t('eseva_mega_title'),
                                style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                              ),
                              TextSpan(
                                text: ' - ${context.watch<LocalizationService>().t('eseva_mega_subtitle')}',
                                style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                              ),
                            ]),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const EsevaServiceScreen()),
              );
            },
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: Colors.transparent,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  _themedSlot(context, 'eseva', 1, const Duration(seconds: 3), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(seconds: 3), children: [SvgPicture.string(FluentEmojiFlat.card_index), SvgPicture.string(FluentEmojiFlat.identification_card)]))),
                  _themedSlot(context, 'eseva', 2, const Duration(milliseconds: 3200), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3200), children: [SvgPicture.string(FluentEmojiFlat.scroll), SvgPicture.string(FluentEmojiFlat.rolled_up_newspaper)]))),
                  _themedSlot(context, 'eseva', 3, const Duration(milliseconds: 2800), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 2800), children: [SvgPicture.string(FluentEmojiFlat.label), SvgPicture.string(FluentEmojiFlat.receipt)]))),
                  _themedSlot(context, 'eseva', 4, const Duration(milliseconds: 3500), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3500), children: [SvgPicture.string(FluentEmojiFlat.office_building), SvgPicture.string(FluentEmojiFlat.bank)]))),
                  _themedSlot(context, 'eseva', 5, const Duration(milliseconds: 3100), ClipOval(child: AutoWidgetSlider(width: 34, height: 34, duration: const Duration(milliseconds: 3100), children: [SvgPicture.string(FluentEmojiFlat.printer), SvgPicture.string(FluentEmojiFlat.fax_machine)]))),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── OTHER SERVICES MEGA CARD ────────────────────────────────────
  Widget _buildOtherServicesMegaCard(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      _themedHeaderIcon(context, 'other_services', '1', SvgPicture.string(FluentEmojiFlat.hammer_and_wrench, width: 20, height: 20)),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text.rich(
                          TextSpan(children: [
                            TextSpan(
                              text: context.watch<LocalizationService>().t('otherservices_mega_title'),
                              style: GoogleFonts.outfit(color: kText, fontSize: 13, fontWeight: FontWeight.w800),
                            ),
                            TextSpan(
                              text: ' - ${context.watch<LocalizationService>().t('otherservices_mega_subtitle')}',
                              style: GoogleFonts.outfit(color: kMuted, fontSize: 11, fontWeight: FontWeight.w500),
                            ),
                          ]),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: Colors.transparent,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                // Electrician, Puncture & Internet used to share this
                // row too — per Nizam's request they're now their own
                // standalone mega-card buttons (_buildElectricianMegaCard
                // / _buildPunctureMegaCard / _buildInternetMegaCard),
                // same shell as every other main service button.
                _buildSmallActionTile(context, FluentEmojiFlat.broom, context.watch<LocalizationService>().t('other_cleaning_label'), () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(role: 'Home Cleaning'))), photoUrl: 'https://images.unsplash.com/photo-1581578731548-c64695cc6952?w=200&q=80'),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionTile(BuildContext context, String iconSvg, String label, VoidCallback onTap, {String? photoUrl}) {
    final iconTheme = context.watch<ThemeService>().iconThemeKey;
    final usePhoto = iconTheme == 'photo_realistic' && photoUrl != null;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: Colors.white,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 8, offset: const Offset(0, 3)),
              ],
            ),
            child: usePhoto
                ? ClipOval(
                    child: CachedCloudImage(
                      photoUrl,
                      width: 48,
                      height: 48,
                      fit: BoxFit.cover,
                      cacheWidth: 192,
                      errorWidget: Center(child: SvgPicture.string(iconSvg, width: 28, height: 28)),
                    ),
                  )
                : Center(child: SvgPicture.string(iconSvg, width: 28, height: 28)),
          ),
          const SizedBox(height: 6),
          Text(
            label,
            style: GoogleFonts.outfit(color: kText, fontSize: 10, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }

  // ── Featured Shop Card ─────────────────────────────────────────
  Widget _buildFeaturedShop(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return GestureDetector(
      onTap: () => Navigator.push<void>(context,
          MaterialPageRoute<void>(
              builder: (_) => const ComingSoonScreen(role: 'Erode Fresh'),),),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kGreen.withValues(alpha: 0.08),
                kGreen.withValues(alpha: 0.03),],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: kGreen.withValues(alpha: 0.25)),
        ),
        child: Row(children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: kGreen.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(14),
            ),
            child: const Center(child: Text('🥬', style: TextStyle(fontSize: 26))),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(t('featured_shop_badge'),
                  style: TextStyle(color: kGold, fontSize: 10,
                      fontWeight: FontWeight.w700,),),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: kGreen, borderRadius: BorderRadius.circular(6),),
                child: Text(t('shop_open_label'), style: const TextStyle(
                    color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w700,),),
              ),
            ],),
            const SizedBox(height: 2),
            Text(t('erode_fresh_name'), style: GoogleFonts.outfit(
                color: kText, fontSize: 15, fontWeight: FontWeight.w800,),),
            Text(t('erode_fresh_subtitle'),
                style: TextStyle(color: kMuted, fontSize: 11),),
          ],),),
          Icon(Icons.chevron_right_rounded, color: kMuted),
        ],),
      ),
    );
  }

  // ── Promo Cards ────────────────────────────────────────────────
  Widget _buildPromoCards(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return Column(children: [
      GestureDetector(
        onTap: () => Navigator.push<void>(context,
            MaterialPageRoute<void>(builder: (_) => const GuruChatScreen()),),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: kSurface,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kBorder),
          ),
          child: Row(children: [
            Container(
              width: 42, height: 42,
              decoration: BoxDecoration(
                color: kPurple.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(12),
              ),
              child: const Center(
                child: AiBotAvatar(size: 32),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Text(t('promo_guru_title'),
                    style: GoogleFonts.outfit(
                        color: kText, fontSize: 12,
                        fontWeight: FontWeight.w700,),),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2,),
                  decoration: BoxDecoration(
                    color: kPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kPurple.withValues(alpha: 0.4)),
                  ),
                  child: Text(t('promo_guru_badge'), style: TextStyle(
                      color: kPurple, fontSize: 8,
                      fontWeight: FontWeight.w800,),),
                ),
              ],),
              const SizedBox(height: 2),
              Text(t('promo_guru_subtitle'),
                  style: TextStyle(color: kMuted, fontSize: 10),),
            ],),),
            Icon(Icons.chevron_right_rounded, color: kMuted),
          ],),
        ),
      ),
    ],);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<void Function(String)>.has('onTileTap', onTileTap));
    properties.add(DiagnosticsProperty<User?>('user', user));
    properties.add(DiagnosticsProperty<Stream<DocumentSnapshot<Object?>>>('userStream', userStream));
  }
}

// ================================================================
// PROFILE DRAWER (Restored MVP Version)
// ================================================================
class _ProfileDrawer extends StatelessWidget {
  final User? user;
  // Same fix as the AppBar header (see _loadResolvedName() above) — a
  // Firestore/HiveCache-resolved name, passed down from
  // _DashboardScreenState so this drawer doesn't repeat the same "only
  // ever reads the frozen Auth displayName" bug the phone number field
  // right below it was already fixed for.
  final String? resolvedName;
  final void Function(Widget) onNavigate;
  const _ProfileDrawer({
    required this.user,
    required this.onNavigate,
    this.resolvedName,
  });

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    final name  = resolvedName ?? user?.displayName ?? 'Guest';
    final phone = user?.phoneNumber ?? 'Phone not added';

    return Drawer(
      backgroundColor: kBg,
      child: SafeArea(
        child: Column(children: [
          // Drawer Header
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [kPink, kPinkDark],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            child: Row(children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: Colors.white.withValues(alpha: 0.3),
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : 'G',
                  style: const TextStyle(color: Colors.white,
                      fontWeight: FontWeight.w900, fontSize: 24,),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w800,),
                    overflow: TextOverflow.ellipsis,),
                const SizedBox(height: 3),
                // FIX (audit: customer/hero number wiring): user?.phoneNumber
                // is only populated by real phone-OTP auth — a Google-Sign-In
                // customer's typed-in signup number lives in Firestore
                // users/{uid}.phoneNumber (with .phone kept in sync), not on
                // the Auth object, so this drawer showed "Phone not added"
                // for every such customer even though the number was
                // correctly stored. StreamBuilder falls back to the plain
                // `phone` local (Auth-derived) while the Firestore doc loads.
                if (user == null)
                  Text(phone, style: const TextStyle(
                      color: Colors.white70, fontSize: 12,),)
                else
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('users')
                        .doc(user!.uid)
                        .trackedSnapshots(),
                    builder: (context, snap) {
                      final data = snap.data?.data();
                      final resolvedPhone =
                          (data?['phoneNumber'] as String?)?.trim().isNotEmpty ?? false
                              ? (data!['phoneNumber'] as String).trim()
                              : ((data?['phone'] as String?)?.trim().isNotEmpty ?? false
                                  ? (data!['phone'] as String).trim()
                                  : phone);
                      return Text(resolvedPhone, style: const TextStyle(
                          color: Colors.white70, fontSize: 12,),);
                    },
                  ),
              ],),),
            ],),
          ),

          // Drawer Menu Items
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              const SizedBox(height: 10),

              _drawerItem(context, Icons.person_outline_rounded,
                  t('drawer_my_profile'), () => onNavigate(const ProfileScreen()),
                  itemKey: const Key('drawer_item_profile'),),

              // Activity (Replaces standard history)
              _drawerItem(context, Icons.local_activity_outlined,
                  t('drawer_activity'), () => onNavigate(const RideHistoryScreen()),),

              // NEW: unified view across all 4 service_requests
              // categories (Hero Booking / Custom Order / Custom Food
              // Order / Grocery Order) — additive, does not replace the
              // existing per-type status screens.
              _drawerItem(context, Icons.receipt_long_rounded,
                  'My Orders', () => onNavigate(const MyOrdersScreen()),
                  itemKey: const Key('drawer_item_my_orders'),),

              _drawerItem(context, Icons.settings_outlined,
                  t('drawer_settings'), () => onNavigate(const SettingsScreen()),),

              // NEW (Aug 13 2026 — customer referral). TWO entries on
              // purpose: customers reach for different words depending
              // on the situation — "share" when messaging a friend,
              // "QR" when the friend is standing right next to them.
              // Both open the same screen, which holds the WhatsApp
              // share button AND the personal QR.
              _drawerItem(context, Icons.share_rounded,
                  'Share App via WhatsApp',
                  () => onNavigate(InviteFriendsScreen(
                        displayName: resolvedName ?? user?.displayName,
                      )),),

              _drawerItem(context, Icons.qr_code_2_rounded,
                  'My Invite QR',
                  () => onNavigate(InviteFriendsScreen(
                        displayName: resolvedName ?? user?.displayName,
                      )),),

              _drawerItem(context, Icons.support_agent_rounded,
                  t('drawer_help_whatsapp'), () async {
                final url = Uri.parse("https://wa.me/918681869091?text=${Uri.encodeComponent('Hi NJ Tech! I need some help from the app.')}");
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              }),

              // Manual escape hatch for the automatic update flow.
              // The pink UPDATE button only appears once
              // WebVersionChecker has spotted a new build; this lets a
              // customer force the same refresh on demand — useful if
              // they've been told a fix is out, or if detection hasn't
              // caught up yet.
              if (kIsWeb)
                _drawerItem(context, Icons.system_update_alt_rounded,
                    t('drawer_check_update'), () {
                  Navigator.pop(context);
                  unawaited(_runManualUpdateCheck(context));
                }),

              const SizedBox(height: 20),

              // Growth Hack: Download App CTA — now the shared
              // DownloadAppBanner widget (appVariant: 'customer'), so
              // this drawer button is self-referential just like Hero/
              // Seller/Admin's own drawers: tapping it downloads ONLY
              // the Customer APK directly, instead of opening the old
              // Customer+Hero choice sheet (_showApkSheet, left intact
              // below for any other remaining callers). This does NOT
              // touch the separate automatic-update-detection button
              // above (the `if (kIsWeb) drawer_check_update` item).
              const DownloadAppBanner(appVariant: 'customer'),

              const SizedBox(height: 20),
              Divider(color: kBorder, height: 1),
              const SizedBox(height: 10),

              _drawerItem(context, Icons.logout_rounded,
                  t('drawer_sign_out'), () async {
                await LocalSyncService.instance.clearAll();
                await HiveCache.clearAll();
                await PrefsCache.clearAll();
                await FirebaseAuth.instance.signOut();
              }, color: kRed,),

              // ── JOIN AS HERO ────────────────────────────────────
              // MOVED here (Aug 18 2026, per Nizam: "hero invite yella
              // option kudavum onna kalanthurukku"). It was previously
              // a plain row in the list above, where it read as just
              // another menu item and got lost among Profile / Orders /
              // Settings / Share / QR / Help.
              //
              // This is a RECRUITMENT call to action, not navigation —
              // it deserves to look different from the utility rows. So
              // it now sits alone in the empty space below Sign Out,
              // where nothing competes with it, drawn as a proper
              // bordered card with the hero icon.
              const SizedBox(height: 22),
              _buildJoinHeroButton(context, onNavigate),
            ],),
          ),

          // Version Info at bottom
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text(t('app_version_footer'),
              style: TextStyle(color: kMuted.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold),
            ),
          ),
        ],),
      ),
    );
  }

  // NEW (CTO mandate — Synthetic QA Test-Bot): optional `itemKey`,
  // additive — every existing call site keeps working unchanged since
  // it defaults to null (Flutter's own ListTile behavior with no key).
  Widget _drawerItem(BuildContext context, IconData icon,
      String title, VoidCallback onTap, {Color? color, Key? itemKey,}) {
    final c = color ?? kPink;
    return ListTile(
      key: itemKey,
      onTap: () { Navigator.pop(context); onTap(); },
      leading: Icon(icon, color: c, size: 20),
      title: Text(title, style: TextStyle(
          color: c, fontSize: 13, fontWeight: FontWeight.w600,),),
      trailing: Icon(Icons.chevron_right_rounded,
          color: c.withValues(alpha: 0.5), size: 18,),
      dense: true,
    );
  }

  Widget _buildJoinHeroButton(BuildContext context, void Function(Widget) onNavigate) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: GestureDetector(
        onTap: () {
          Navigator.pop(context);
          onNavigate(const HeroPromoScreen());
        },
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
          decoration: BoxDecoration(
            color: kPink.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: kPink.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              SvgPicture.string(FluentEmojiFlat.man_superhero, width: 24, height: 24),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Join as Hero',
                      style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'Become a partner & start earning',
                      style: TextStyle(color: kMuted, fontSize: 10),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right_rounded, color: kPink),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<User?>('user', user));
    properties.add(ObjectFlagProperty<void Function(Widget)>.has('onNavigate', onNavigate));
  }
}

// ================================================================
// CHECK FOR UPDATES
// ================================================================
Future<void> _checkForUpdates(BuildContext context) async {
  final t = context.read<LocalizationService>().t;
  final navigator = Navigator.of(context, rootNavigator: true);
  final msg = kIsWeb
      ? t('app_updating_msg')
      : t('checking_updates_msg');

  showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 48, height: 48,
          child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(kPink),),
        ),
        const SizedBox(height: 20),
        Text(msg,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w600,),),
      ],),
    ),
  );

  await Future<void>.delayed(const Duration(milliseconds: 1500));
  // FIX (CTO QA — "crashes if no update exists"): the customer can
  // navigate away during the 1.5s delay above; without this guard the
  // navigator.pop()/showDialog calls below throw on a disposed context.
  if (!context.mounted) return;
  navigator.pop();

  if (kIsWeb) {
    try {
      await _clearPwaCacheAndReload();
    } catch (e) {
      debugPrint('[CheckUpdate] PWA cache clear failed: $e');
      final uri = Uri.parse(Uri.base.toString());
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      }
    }
  } else {
    if (!context.mounted) return;
    showDialog<void>(
      context: navigator.context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('✅ ', style: TextStyle(fontSize: 20)),
          Text(t('up_to_date_title'),
              style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w800,),),
        ],),
        content: Text(
          t('up_to_date_body'),
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: navigator.pop,
            child: Text(t('got_it_label'), style: TextStyle(color: kPink)),
          ),
        ],
      ),
    );
  }
}

Future<void> _clearPwaCacheAndReload() async {
  await PwaCachePlatform().clearAndReload();
}

// ================================================================
// MANUAL "CHECK FOR UPDATE" (drawer)
// ================================================================
// The automatic path (WebVersionChecker -> pink UPDATE button) only
// surfaces once a new build has actually been detected. This is the
// on-demand version: the customer asks, we look, and either refresh or
// tell them they're already current.
//
// Deliberately blunt about what it does — clearing the PWA cache and
// reloading is exactly what the automatic UPDATE button does, so both
// paths land the customer in the same place with the same code.
Future<void> _runManualUpdateCheck(BuildContext context) async {
  final t = context.read<LocalizationService>().t;
  final navigator = Navigator.of(context, rootNavigator: true);

  // Non-dismissible: the reload happens under this dialog, and letting
  // it be tapped away mid-refresh just looks like the app froze.
  showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: kPink),
          ),
          const SizedBox(width: 18),
          Flexible(
            child: Text(
              t('checking_updates_msg'),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    ),
  );

  await WebVersionChecker.instance.checkNow();

  // FIX (CTO QA — "Check for Updates crashes if no update exists"): the
  // real root cause was never a null crash on the no-update path -- it
  // was a missing context.mounted guard after this and the delay below.
  // If the customer navigates away mid-await, navigator.pop()/
  // ScaffoldMessenger.of(navigator.context) throw on a disposed context.
  if (!context.mounted) return;

  // A beat so the spinner reads as "it looked" rather than flashing
  // past too fast to notice.
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (!context.mounted) return;

  if (!WebVersionChecker.instance.isUpdateAvailable) {
    navigator.pop();
    ScaffoldMessenger.of(navigator.context).showSnackBar(
      SnackBar(
        content: Text(t('already_latest_version_snack')),
        duration: const Duration(seconds: 2),
      ),
    );
    return;
  }

  // Found one. Swap the message, then clear caches and reload — the
  // page goes away underneath us, so nothing after this needs to run.
  navigator.pop();
  showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: kPink),
          ),
          const SizedBox(width: 18),
          Flexible(
            child: Text(
              t('updating_app_msg'),
              style: const TextStyle(color: Colors.white, fontSize: 14),
            ),
          ),
        ],
      ),
    ),
  );

  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (!context.mounted) return;

  try {
    await _clearPwaCacheAndReload();
  } catch (e) {
    debugPrint('[ManualUpdate] cache clear failed, reloading anyway: $e');
    final uri = Uri.parse(Uri.base.toString());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ================================================================
// APPLY REAL PWA UPDATE
// ================================================================
// Called only when WebVersionChecker already confirmed /version.json
// reports a different build than the one this tab loaded with, so
// there's nothing to "check" here — just apply.
//
// This used to message the waiting service worker and wait for it to
// take over. That step is gone: Flutter's service worker unregisters
// itself, so the message went nowhere and the flow always ended up
// timing out into this same cache-clear-and-reload four seconds later.
// Doing it directly is the same result without the dead wait.
Future<void> _applyPwaUpdate(BuildContext context) async {
  final t = context.read<LocalizationService>().t;
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      content: Column(mainAxisSize: MainAxisSize.min, children: [
        const SizedBox(height: 8),
        SizedBox(
          width: 48, height: 48,
          child: CircularProgressIndicator(
              strokeWidth: 3,
              valueColor: AlwaysStoppedAnimation<Color>(kPink),),
        ),
        const SizedBox(height: 20),
        Text(t('app_updating_msg'),
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w600,),),
      ],),
    ),
  );

  try {
    await _clearPwaCacheAndReload();
  } catch (e) {
    debugPrint('[PwaUpdate] cache clear failed, reloading anyway: $e');
    if (!context.mounted) return;
    final uri = Uri.parse(Uri.base.toString());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}

// ================================================================
// WELCOME-BACK POPUP (shown once, right after a self-triggered update)
// ================================================================
void _showWelcomeToNewVersionPopup(BuildContext context) {
  final t = context.read<LocalizationService>().t;
  showDialog<void>(
    context: context,
    builder: (dialogCtx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      title: Row(children: [
        const Text('🎉 ', style: TextStyle(fontSize: 20)),
        Text(t('welcome_new_version_title'),
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 16, fontWeight: FontWeight.w800,),),
      ],),
      content: Text(
        t('welcome_new_version_body'),
        style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(dialogCtx).pop(),
          child: Text(t('got_it_label'), style: TextStyle(color: kPink)),
        ),
      ],
    ),
  );
}

// ================================================================
// APPLY NATIVE APP UPDATE (customer APK)
// ================================================================
// Called only when _checkForNativeAppUpdate() already confirmed a
// genuinely newer GitHub release exists — see AppUpdateChecker. Hands
// the APK straight to Android's installer (OpenFilex) instead of the
// old always-on button's "Up to Date / Shorebird OTA" placeholder
// message, which never actually offered a real update.
Future<void> _applyNativeAppUpdate(BuildContext context) async {
  final t = context.read<LocalizationService>().t;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(t('downloading_update_snack'))),
  );
  try {
    await AppUpdateChecker().downloadAndInstall(appVariant: 'customer');
  } catch (e) {
    debugPrint('[Dashboard] native update install failed: $e');
    if (context.mounted) {
      await _checkForUpdates(context);
    }
  }
}

// ================================================================
// DOWNLOAD FAILED FALLBACK
// ================================================================
// Shown when launchUrl can't open the APK download link directly (see
// _apkBtn's FIX comment) — gives the customer a way to still get the
// app (copy the link, open in the system browser manually) instead of
// a dead tap with no explanation.
void _showDownloadFailedDialog(BuildContext context, String url) {
  final t = context.read<LocalizationService>().t;
  showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      backgroundColor: const Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: Text(t('download_failed_title'), style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            t('download_failed_body'),
            style: const TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 12),
          SelectableText(url, style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () async {
            await Clipboard.setData(ClipboardData(text: url));
            if (ctx.mounted) {
              ScaffoldMessenger.of(ctx).showSnackBar(
                SnackBar(content: Text(t('link_copied_snack'))),
              );
            }
          },
          child: Text(t('copy_link_label'), style: const TextStyle(color: Colors.white70)),
        ),
        TextButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(t('close_label'), style: const TextStyle(color: Colors.white38)),
        ),
      ],
    ),
  );
}

// ================================================================
// APK DOWNLOAD SHEET
// ================================================================
void _showApkSheet(BuildContext context) {
  final t = context.read<LocalizationService>().t;
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => Container(
      margin: const EdgeInsets.all(12),
      padding: const EdgeInsets.fromLTRB(20, 24, 20, 32),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A26),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: kPink.withValues(alpha: 0.3)),
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Container(width: 40, height: 4,
            decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),),),
        const SizedBox(height: 16),
        Text(t('apk_sheet_title'),
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w800,),),
        const SizedBox(height: 20),
        // FIX: these used to point at customer_app.apk / hero_app.apk
        // (v1.0.0-pinned) — neither filename was ever actually uploaded
        // to the release (the real assets are allin1-customer.apk /
        // allin1-hero.apk), so every tap 404'd. Reuses UpdateService's
        // single source of truth for these URLs instead of a third
        // hardcoded copy.
        _apkBtn(
          context: context,
          label: t('download_customer_app_label'),
          gradient: [kPink, kPinkDark],
          url: UpdateService().fallbackApkUrl('customer'),
          appVariant: 'customer',
        ),
        const SizedBox(height: 10),
        _apkBtn(
          context: context,
          label: t('download_hero_app_label'),
          gradient: [kPurple, const Color(0xFF5A50C8)],
          url: UpdateService().fallbackApkUrl('hero'),
          appVariant: 'hero',
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: Text(t('dismiss_label'),
              style: const TextStyle(color: Colors.white38, fontSize: 12),),
        ),
      ],),
    ),
  );
}

Widget _apkBtn({
    required BuildContext context,
    required String label,
    required List<Color> gradient,
    required String url,
    required String appVariant,}) {
  return GestureDetector(
    onTap: () async {
      unawaited(UsageTrackingService.instance.trackApkDownload(appVariant));
      // FIX (root cause of "tap Download App and nothing happens — the
      // sheet just sits there, only Back works"): canLaunchUrl() can
      // return false on some mobile browser / installed-PWA contexts for
      // a direct-download https link (no query permission granted, or
      // the browser's "can this app handle this URL" check is stricter
      // in standalone/PWA display mode than in a normal tab) — and the
      // old code did NOTHING when that happened: no error, no snackbar,
      // no visible feedback at all. That silent no-op is exactly what
      // reads as "frozen." Now always attempts launchUrl regardless of
      // canLaunchUrl's answer (canLaunchUrl is known to be unreliable
      // for https on some Android WebView/PWA builds), wrapped in a
      // try/catch that surfaces a real error + a manual-copy fallback if
      // the browser genuinely can't open it.
      final uri = Uri.parse(url);
      try {
        final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
        if (!launched && context.mounted) {
          _showDownloadFailedDialog(context, url);
        }
      } catch (e) {
        if (context.mounted) {
          _showDownloadFailedDialog(context, url);
        }
      }
    },
    child: Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(colors: gradient),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Center(child: Text(label,
          style: GoogleFonts.outfit(
              color: Colors.white, fontSize: 14,
              fontWeight: FontWeight.w700,),),),
    ),
  );
}

// ================================================================
// NJ TECH BROADBAND WEBVIEW
// ================================================================
class NjTechBroadbandWebView extends StatefulWidget {
  const NjTechBroadbandWebView({super.key});
  @override
  State<NjTechBroadbandWebView> createState() => _NjTechBroadbandWebViewState();
}

class _NjTechBroadbandWebViewState extends State<NjTechBroadbandWebView> {
  bool _loading = true;
  bool _launched = false;

  /// Bumped on every reload so the embedded view gets a fresh key.
  int _reloadToken = 0;

  static const String _kBroadbandUrl = 'https://www.erodefiber.net/';

  // ── WHY THIS STILL FELT LIKE THE PHONE'S BROWSER ───────────────
  // (Aug 19 2026, Nizam: "namma app internet page um same embedded
  // look la maaranum" — like the DMart page in Grocery.)
  //
  // This screen already built a proper in-app shell: our AppBar, our
  // colours, our reload button. But the page itself was loaded with
  // `launchUrl(mode: LaunchMode.inAppWebView)`, and that is NOT an
  // embedded WebView despite the name — on Android it opens a Chrome
  // Custom Tab, which is a full browser surface that slides in OVER
  // the whole app. So the nice Scaffold underneath was never actually
  // visible: the customer saw Chrome's own toolbar, Chrome's own
  // address bar, and had left the app in every way that matters.
  //
  // DmartEmbeddedView is a REAL embedded view — WebView on Android/iOS,
  // an <iframe> platform view on the PWA — and it is already
  // URL-generic (`required this.url`) despite the DMart-specific name,
  // so Grocery's DMart page and this page now render through exactly
  // the same mechanism and genuinely look the same.
  //
  // Kept the name rather than renaming the widget: DMart is live and
  // working, and a cosmetic rename across three files is risk this
  // change does not need to take at final-build stage.
  @override
  void initState() {
    super.initState();
    // FIX (Nizam: "browser link open embedded system mobile app la nalla
    // work aguthu but pwa la page open agama error varuthu") — ROOT
    // CAUSE: erodefiber.net's own server sends X-Frame-Options / CSP
    // frame-ancestors headers (same caveat already documented in
    // dmart_embedded_view_web.dart's header). Android/iOS WebView
    // (dmart_embedded_view_native.dart) is NOT bound by those headers —
    // that's exactly why "mobile app la nalla work aguthu" — but the
    // PWA's <iframe> genuinely is, since it's the browser itself
    // enforcing the site's own anti-clickjacking policy. No client-side
    // fix can embed a page that refuses to be framed. So on web this
    // skips the doomed iframe attempt entirely and opens the real site
    // in a new browser tab instead — the same escape hatch
    // dmart_screen.dart already offers as a manual button, just
    // automatic here since the embed was never going to succeed.
    if (kIsWeb) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() => _loading = false);
        unawaited(_openInBrowser());
      });
      return;
    }
    // The embedded view loads itself; there is no launch step to await
    // any more. The brief _loading flash is kept so the AppBar doesn't
    // pop in against an empty white frame on a slow connection.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() { _loading = false; _launched = true; });
    });
  }

  Future<void> _openInApp() async {
    if (kIsWeb) {
      unawaited(_openInBrowser());
      return;
    }
    // Reload: rebuild the embedded view from scratch by flipping back
    // to the loading state. A key change on the child forces a fresh
    // WebView/iframe rather than a same-page no-op.
    setState(() { _loading = true; _launched = false; _reloadToken++; });
    await Future<void>.delayed(const Duration(milliseconds: 120));
    if (mounted) setState(() { _loading = false; _launched = true; });
  }

  Future<void> _openInBrowser() async {
    final uri = Uri.parse(_kBroadbandUrl);
    final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!opened && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not open Erode Fiber. Check your connection.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return Scaffold(
      backgroundColor: kNJDark,
      appBar: AppBar(
        backgroundColor: kNJDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20,),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: kPink.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: kPink.withValues(alpha: 0.4)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.lock_rounded, color: kPink, size: 12),
              const SizedBox(width: 4),
              Text('erodefiber.net',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600,),),
            ],),
          ),
        ],),
        actions: [
          IconButton(
            icon: const Icon(Icons.open_in_new_rounded, color: Colors.white70, size: 20),
            tooltip: 'Open in browser',
            onPressed: _openInBrowser,
          ),
          if (!kIsWeb)
            IconButton(
              icon: Icon(Icons.refresh_rounded, color: kPink),
              onPressed: _openInApp,
              tooltip: t('reload_tooltip'),
            ),
        ],
      ),
      body: Center(
        child: _loading
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircularProgressIndicator(color: kPink),
                const SizedBox(height: 20),
                Text(t('opening_erode_fiber_msg'),
                    style: GoogleFonts.outfit(
                        color: Colors.white70, fontSize: 14,),),
              ],)
            : kIsWeb
                // erodefiber.net's own headers block being framed by any
                // other site — see the _openInBrowser fallback in
                // initState — so on web there is nothing to embed; this
                // is the honest "we sent you to a new tab" state, not an
                // error screen.
                ? Padding(
                    padding: const EdgeInsets.all(24),
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                      const Icon(Icons.open_in_new_rounded, color: Colors.white38, size: 56),
                      const SizedBox(height: 16),
                      Text('Opened Erode Fiber in a new tab',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                              color: Colors.white, fontSize: 18,
                              fontWeight: FontWeight.w700,),),
                      const SizedBox(height: 8),
                      Text('This site can\'t be shown inside the app on web — tap below if the tab didn\'t open.',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                              color: Colors.white54, fontSize: 13,),),
                      const SizedBox(height: 20),
                      GestureDetector(
                        onTap: _openInBrowser,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
                          decoration: BoxDecoration(
                            color: kPink,
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text('Open Erode Fiber',
                              style: GoogleFonts.outfit(
                                  color: Colors.white, fontSize: 14,
                                  fontWeight: FontWeight.w700,),),
                        ),
                      ),
                    ],),
                  )
                : _launched
                // THE ACTUAL PAGE, in our own Scaffold.
                //
                // This branch used to be a dead-end placeholder — a 🌐
                // emoji, "Erode Fiber is open" and a "Back to
                // Dashboard" button — because the real site had been
                // handed to Chrome and was sitting on top of this
                // screen. The customer never saw this widget at all;
                // they saw a browser. Closing the browser revealed a
                // page telling them something was open that no longer
                // was.
                //
                // SizedBox.expand because the parent is a Center, which
                // passes loose constraints — an unconstrained WebView
                // would collapse to zero height and render blank.
                //
                // The ValueKey makes reload work: changing it forces a
                // brand-new WebView/iframe instead of Flutter reusing
                // the existing one and doing nothing.
                ? SizedBox.expand(
                    child: DmartEmbeddedView(
                      key: ValueKey<int>(_reloadToken),
                      url: _kBroadbandUrl,
                    ),
                  )
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.white38, size: 56,),
                    const SizedBox(height: 16),
                    Text(t('could_not_open_inapp_title'),
                        style: GoogleFonts.outfit(
                            color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.w700,),),
                    const SizedBox(height: 8),
                    Text(t('check_internet_retry_subtitle'),
                        style: GoogleFonts.outfit(
                            color: Colors.white54, fontSize: 13,),),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _openInApp,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12,),
                        decoration: BoxDecoration(
                          color: kPink,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(t('try_again_label'),
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,),),
                      ),
                    ),
                  ],),
      ),
    );
  }
}

// ================================================================
// SCRATCH CARD MODAL
// ================================================================
class _ScratchCardModal extends StatefulWidget {
  const _ScratchCardModal();
  @override
  State<_ScratchCardModal> createState() => _ScratchCardModalState();
}

class _ScratchCardModalState extends State<_ScratchCardModal>
    with SingleTickerProviderStateMixin {
  bool   _revealed = false;
  double _progress = 0;

  late final AnimationController _revealCtrl = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 450),
  );
  late final Animation<double> _revealScale = CurvedAnimation(
    parent: _revealCtrl,
    curve: Curves.elasticOut,
  );
  late final Animation<double> _revealFade = CurvedAnimation(
    parent: _revealCtrl,
    curve: const Interval(0, 0.4, curve: Curves.easeOut),
  );

  @override
  void dispose() {
    _revealCtrl.dispose();
    super.dispose();
  }

  void _onRevealed() {
    if (_revealed) return;
    setState(() => _revealed = true);
    _revealCtrl.forward(from: 0);
  }

  Future<void> _callToClaim() async {
    final uri = Uri.parse('tel:+918681869091');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    // Single universal reward — no random selection, no wallet/coin credit.
    const emoji = '🎉';
    final title = t('scratch_reward_title');
    final subtitle = t('scratch_reward_subtitle');
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(color: kPink.withValues(alpha: 0.22), blurRadius: 36, spreadRadius: -4,),
          BoxShadow(color: kPinkDark.withValues(alpha: 0.10), blurRadius: 20, offset: const Offset(0, 12),),
        ],
      ),
      // Rose-gold gradient "hairline" border — a flat solid border reads
      // cheap on a premium card; a thin gradient ring around a plain
      // white/pink inner panel is what actually sells "premium".
      child: Container(
        padding: const EdgeInsets.all(1.6),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(30),
          gradient: LinearGradient(
            colors: [kPink, const Color(0xFFFFE3F2), kPinkDark, const Color(0xFFFFE3F2), kPink],
            begin: Alignment.topLeft, end: Alignment.bottomRight,
          ),
        ),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(28.5),
            gradient: LinearGradient(
              colors: [kBg, kPinkBg],
              begin: Alignment.topLeft, end: Alignment.bottomRight,
            ),
          ),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [kPink.withValues(alpha: 0.16), kPinkDark.withValues(alpha: 0.10)],
                  begin: Alignment.centerLeft, end: Alignment.centerRight,
                ),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: kPink.withValues(alpha: 0.4)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.auto_awesome_rounded, color: kPinkDark, size: 11),
                const SizedBox(width: 4),
                Text(t('daily_scratch_badge'),
                    style: GoogleFonts.outfit(
                        color: kPinkDark, fontSize: 10, fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,),),
              ],),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: kPink.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.close_rounded,
                    color: kMuted, size: 18,),
              ),
            ),
          ],),
        ),
        Text(t('scratch_reveal_hint'),
            style: GoogleFonts.outfit(color: kMuted, fontSize: 13),),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Scratcher(
            brushSize: 40,
            threshold: 30,
            color: const Color(0xFFFFB6D9),
            onThreshold: _onRevealed,
            onChange: (v) => setState(() => _progress = v),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: LinearGradient(
                  colors: [kBg, kPinkBg, kBg],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
                border: Border.all(color: kPink.withValues(alpha: 0.25)),
              ),
              child: Center(
                child: AnimatedBuilder(
                  animation: _revealCtrl,
                  builder: (context, child) => Transform.scale(
                    scale: _revealed
                        ? (0.85 + (_revealScale.value * 0.15))
                        : 1,
                    child: Opacity(
                      opacity: _revealed ? _revealFade.value : 1,
                      child: child,
                    ),
                  ),
                  child: Column(mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                    Text(emoji, style: TextStyle(
                        fontSize: 52,
                        shadows: [Shadow(
                            color: kPink.withValues(alpha: 0.45),
                            blurRadius: 16,),],),),
                    const SizedBox(height: 10),
                    Text(title,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: kPinkDark, fontSize: 22,
                            fontWeight: FontWeight.w900,),),
                    const SizedBox(height: 6),
                    Text(subtitle,
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                            color: kMuted, fontSize: 13,),),
                  ],),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(4),
            child: LinearProgressIndicator(
              value: _progress / 100,
              backgroundColor: kPink.withValues(alpha: 0.10),
              valueColor: AlwaysStoppedAnimation<Color>(
                  _revealed ? kGreen : kPink,),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(_revealed ? t('scratch_revealed_label') : t('scratch_keep_going_label'),
            style: GoogleFonts.outfit(
                color: _revealed ? kGreen : kMuted,
                fontSize: 11, fontWeight: FontWeight.w600,),),
        const SizedBox(height: 16),
        if (_revealed)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: SizedBox(
              width: double.infinity,
              child: GestureDetector(
                onTap: _callToClaim,
                child: Container(
                  padding: const EdgeInsets.symmetric(vertical: 15),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPink, kPinkDark],
                      begin: Alignment.centerLeft, end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(30),
                    boxShadow: [BoxShadow(
                        color: kPink.withValues(alpha: 0.35),
                        blurRadius: 14, offset: const Offset(0, 6),),],
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.call_rounded, color: Colors.white, size: 16),
                    const SizedBox(width: 8),
                    Text(t('call_to_claim_label'),
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 15, fontWeight: FontWeight.w800,
                            letterSpacing: 0.2,),),
                  ],),
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 20),
          ],),
        ),
      ),
    );
  }
}

// ================================================================
// GLOWING UPDATE BUTTON
// ================================================================
class _GlowingUpdateButton extends StatefulWidget {
  final VoidCallback onTap;
  const _GlowingUpdateButton({required this.onTap});
  @override
  State<_GlowingUpdateButton> createState() => _GlowingUpdateButtonState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
class _GlowingUpdateButtonState extends State<_GlowingUpdateButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _glow = Tween<double>(begin: 2, end: 8).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return AnimatedBuilder(
      animation: _glow,
      builder: (context, child) {
        return GestureDetector(
          onTap: widget.onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: kGold,
              borderRadius: BorderRadius.circular(12),
              boxShadow: [
                BoxShadow(color: kGold.withValues(alpha: 0.6), blurRadius: _glow.value, spreadRadius: _glow.value / 2),
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update_alt_rounded, color: Colors.black, size: 12),
                const SizedBox(width: 4),
                Text(t('update_badge_label'), style: GoogleFonts.outfit(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        );
      },
    );
  }
}

// ================================================================
// KEEP ALIVE WRAPPER
// ================================================================
class KeepAliveTab extends StatefulWidget {
  final Widget child;
  const KeepAliveTab({required this.child, super.key});
  @override
  State<KeepAliveTab> createState() => _KeepAliveTabState();
}
class _KeepAliveTabState extends State<KeepAliveTab> with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => true;
  @override
  Widget build(BuildContext context) {
    super.build(context);
    return widget.child;
  }
}

// ================================================================
// CATEGORY SLIDING BANNER — Animated marquee per slide
// ================================================================
// UPDATED (Aug 12 2026 — Nizam: "top layum replace pannu... top and
// bottom la namma new service slinding oodite irukanum but even ah top
// and bottom la same ads same timing la sliding oodama shuffle aagi
// oodanum"): now shows the SAME 10 categories as the bottom
// BannerAdsSlider (see _HomeTab.build()'s BannerTextSlide list), each
// with a richer icon set. Deliberately listed here in REVERSE order
// from the bottom banner, and on a different auto-scroll interval (4s
// here vs 5s at the bottom) — together those two things mean the top
// and bottom banners are never showing the same promo at the same
// moment, without needing any shared timer/state between two separate
// widgets. Every icon is a bundled local SVG (FluentEmojiFlat, via
// _IconMarquee's continuous Timer-driven scroll) — zero network calls
// and zero Hive/caching needed, since there's nothing to fetch in the
// first place; that's what keeps this from costing any battery/PWA
// speed no matter how many categories or icons are added.
class _CategorySlidingBanner extends StatefulWidget {
  final void Function(String) onTileTap;
  const _CategorySlidingBanner({required this.onTileTap});
  @override
  State<_CategorySlidingBanner> createState() => _CategorySlidingBannerState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(ObjectFlagProperty<void Function(String)>.has('onTileTap', onTileTap));
  }
}

class _CategorySlidingBannerState extends State<_CategorySlidingBanner> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  Timer? _autoScrollTimer;

  static const int _slideCount = 10;

  // Same 10 categories as the bottom BannerAdsSlider, listed in REVERSE
  // order on purpose (see header comment) so the two banners desync.
  static const List<String> _titles = [
    'E-Seva Online Services 📋',
    'Visiting Cards & Flex Printing 🖨️',
    'Electronic Services 🔌',
    'Internet Offers 🌐',
    'Construction & Alteration 🏗️',
    'Car Service & Polish 🚗',
    'Book a Hero 🦸',
    'Grocery Delivered 🛒',
    'Food from KFC, A2B, Subway, Domino\'s & Taj 🍽️',
    'Taxi & Transport 🚖',
  ];

  // NEW: more icons per category than before, so each marquee feels
  // fuller — food now also names the exact partner shops the icons
  // stand in for (see CustomFoodOrderScreen — these are real onboarded
  // partners, not a placeholder claim).
  static const List<List<String>> _slideIcons = [
    [
      FluentEmojiFlat.card_index, FluentEmojiFlat.scroll, FluentEmojiFlat.label,
      FluentEmojiFlat.office_building, FluentEmojiFlat.printer, FluentEmojiFlat.framed_picture,
    ],
    [
      FluentEmojiFlat.printer, FluentEmojiFlat.card_index, FluentEmojiFlat.scroll,
      FluentEmojiFlat.framed_picture, FluentEmojiFlat.label,
    ],
    [
      FluentEmojiFlat.mobile_phone, FluentEmojiFlat.laptop, FluentEmojiFlat.desktop_computer,
      FluentEmojiFlat.video_camera, FluentEmojiFlat.television, FluentEmojiFlat.snowflake,
      FluentEmojiFlat.battery,
    ],
    [
      FluentEmojiFlat.antenna_bars, FluentEmojiFlat.mobile_phone, FluentEmojiFlat.laptop,
      FluentEmojiFlat.desktop_computer,
    ],
    [
      FluentEmojiFlat.building_construction, FluentEmojiFlat.brick, FluentEmojiFlat.construction_worker,
      FluentEmojiFlat.triangular_ruler, FluentEmojiFlat.office_building, FluentEmojiFlat.hammer_and_wrench,
    ],
    [
      FluentEmojiFlat.oncoming_taxi, FluentEmojiFlat.sweat_droplets, FluentEmojiFlat.gear,
      FluentEmojiFlat.hammer_and_wrench, FluentEmojiFlat.sport_utility_vehicle,
    ],
    [
      FluentEmojiFlat.man_superhero, FluentEmojiFlat.high_voltage, FluentEmojiFlat.package,
      FluentEmojiFlat.shopping_bags, FluentEmojiFlat.man_running,
    ],
    [
      FluentEmojiFlat.leafy_green, FluentEmojiFlat.red_apple, FluentEmojiFlat.carrot,
      FluentEmojiFlat.onion, FluentEmojiFlat.garlic, FluentEmojiFlat.shopping_cart,
    ],
    [
      // KFC/A2B/Subway/Domino's/Taj — real onboarded partner shops
      // (see CustomFoodOrderScreen / PartnerShopOrderScreen), represented here
      // by their nearest matching bundled food-emoji icons since no
      // trademarked brand-logo assets are shipped in this repo.
      FluentEmojiFlat.hamburger, FluentEmojiFlat.pizza, FluentEmojiFlat.chicken,
      FluentEmojiFlat.french_fries, FluentEmojiFlat.cup_with_straw, FluentEmojiFlat.shortcake,
    ],
    [
      FluentEmojiFlat.motor_scooter, FluentEmojiFlat.package, FluentEmojiFlat.auto_rickshaw,
      FluentEmojiFlat.oncoming_taxi, FluentEmojiFlat.delivery_truck, FluentEmojiFlat.bicycle,
    ],
  ];

  // Three short highlight/benefit points per category — shown next to a
  // single big pink 3D icon when the pink theme is active (see
  // _slidePinkCategory below), replacing the scrolling multicolor icon
  // row so the slide actually tells the customer what the service does.
  static const List<List<String>> _slideBenefits = [
    ['Aadhaar, PAN & ID services', 'Govt certificates online', 'No queue, doorstep help'],
    ['Flex, sticker & photo printing', 'Business cards same day', 'Bulk order discounts'],
    ['Genuine parts guaranteed', 'Doorstep pickup & drop', 'Same-day repair service'],
    ['High-speed connections', 'Mobile & laptop setup help', 'Best plan comparison'],
    ['Verified contractors', 'Design to build support', 'Transparent material costs'],
    ['Foam wash & polish', 'SUV & sedan service', 'Doorstep car service'],
    ['Any errand, any time', 'Verified local heroes', 'Live tracking & support'],
    ['Order from any local shop', 'Fresh veggies & fruits', 'Fast doorstep delivery'],
    ['Order from any shop in Erode', 'Hot & fresh delivery', 'Real onboarded partners'],
    ['Bike, Auto, Cab & more', 'Transparent fare pricing', 'Live driver tracking'],
  ];

  // These have real pink_icons/*.webp renders today (taxi, hero, food,
  // electronics, grocery, printing, construction, eseva, carwash) — the
  // rest keep the flat FluentEmoji until matching pink assets exist for
  // them too. null = no swap for that slide.
  // 'broadband' has no pink_icons asset (falls back to flat FluentEmoji
  // for pink_white_3d via errorBuilder, unchanged), but DOES have a
  // kCategoryPhotoUrl entry so Photo Realistic theme covers it too.
  static const List<String?> _slidePinkCategory = [
    'eseva', 'printing', 'electronics', 'broadband', 'construction', 'carwash', 'hero', 'grocery', 'food', 'taxi',
  ];

  // Reverse-order tap ids matching _titles above. 'route:x' entries open
  // a screen directly instead of going through onTileTap's switch.
  static const List<String> _tapIds = [
    'route:eseva',
    'route:printing',
    'route:electronics',
    'broadband',
    'construction',
    'carwash',
    'route:hero',
    'grocery',
    'food',
    'taxi',
  ];

  List<_CategorySlideData> _buildSlides() {
    return List.generate(_slideCount, (i) =>
        _CategorySlideData(
          title: _titles[i],
          icons: _slideIcons[i],
          benefits: _slideBenefits[i],
          pinkCategory: _slidePinkCategory[i],
          tapId: _tapIds[i],
        ),);
  }

  void _handleTap(BuildContext context, String tapId) {
    switch (tapId) {
      case 'route:eseva':
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const EsevaServiceScreen()));
        break;
      case 'route:printing':
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const PrintingServiceScreen()));
        break;
      case 'route:electronics':
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const NJTechStoreScreen()));
        break;
      case 'route:hero':
        Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const HeroBookingScreen()));
        break;
      default:
        widget.onTileTap(tapId);
    }
  }

  @override
  void initState() {
    super.initState();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_pageController.hasClients) {
        final nextPage = (_currentIndex + 1) % _slideCount;
        _pageController.animateToPage(nextPage, duration: const Duration(milliseconds: 600), curve: Curves.easeInOut);
      }
    });
  }

  @override
  void dispose() {
    _autoScrollTimer?.cancel();
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final slides = _buildSlides();
    return Column(
      children: [
        Container(
          height: 140,
          margin: const EdgeInsets.all(16),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemCount: slides.length,
            itemBuilder: (_, i) {
              final slide = slides[i];
              return GestureDetector(
                onTap: () => _handleTap(context, slide.tapId),
                child: Container(
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [kPink.withValues(alpha: 0.15), kPink.withValues(alpha: 0.05)],
                      begin: Alignment.topLeft, end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kPink.withValues(alpha: 0.2)),
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
                  // Every slide now always shows title + 3 benefit points —
                  // that never changes with theme. Only the single icon on
                  // the left switches: the category's own pink_icons render
                  // in pink theme (for the 4 categories that have one
                  // today), or its flat FluentEmoji glyph otherwise. No more
                  // scrolling multicolor marquee — that was the "just
                  // running, means nothing" look this replaces.
                  child: Builder(builder: (context) {
                    final iconTheme = context.watch<ThemeService>().iconThemeKey;
                    final isPink = iconTheme == 'pink_white_3d' && slide.pinkCategory != null;
                    final photoUrl = iconTheme == 'photo_realistic' ? kCategoryPhotoUrl[slide.pinkCategory] : null;
                    return Row(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        SizedBox(
                          width: 56,
                          height: 56,
                          child: photoUrl != null
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(12),
                                  child: CachedCloudImage(
                                    photoUrl,
                                    fit: BoxFit.cover,
                                    cacheWidth: 112,
                                    errorWidget: SvgPicture.string(slide.icons.first, width: 44, height: 44),
                                  ),
                                )
                              : isPink
                                  ? Image.asset(
                                      'assets/images/pink_icons/${slide.pinkCategory}_1_a.webp',
                                      fit: BoxFit.contain,
                                      errorBuilder: (_, __, ___) => SvgPicture.string(slide.icons.first, width: 44, height: 44),
                                    )
                                  : Center(child: SvgPicture.string(slide.icons.first, width: 44, height: 44)),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(slide.title, style: GoogleFonts.outfit(color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 6),
                              ...slide.benefits.map((point) => Padding(
                                    padding: const EdgeInsets.only(bottom: 2),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.check_circle_rounded, color: kPink, size: 12),
                                        const SizedBox(width: 5),
                                        Expanded(
                                          child: Text(point, style: GoogleFonts.outfit(color: kMuted, fontSize: 10.5, fontWeight: FontWeight.w500)),
                                        ),
                                      ],
                                    ),
                                  ),),
                            ],
                          ),
                        ),
                      ],
                    );
                  }),
                ),
              );
            },
          ),
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(
            slides.length,
            (index) => Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              width: 6, height: 6,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: _currentIndex == index ? kPink : kMuted.withValues(alpha: 0.3),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class _CategorySlideData {
  final String title;
  final List<String> icons;
  final List<String> benefits;
  final String? pinkCategory;
  final String tapId;
  const _CategorySlideData({
    required this.title,
    required this.icons,
    required this.benefits,
    required this.pinkCategory,
    required this.tapId,
  });
}

class _IconMarquee extends StatefulWidget {
  final List<String> icons;
  const _IconMarquee({required this.icons});
  @override
  State<_IconMarquee> createState() => _IconMarqueeState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<String>('icons', icons));
  }
}

class _IconMarqueeState extends State<_IconMarquee> with SingleTickerProviderStateMixin {
  late ScrollController _controller;
  Timer? _timer;
  @override
  void initState() {
    super.initState();
    _controller = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
  }
  void _startMarquee() {
    // 60ms instead of the previous 30ms — half the timer fires, same
    // visual scroll speed (2.0px/60ms == 1.0px/30ms).
    _timer = Timer.periodic(const Duration(milliseconds: 60), (_) {
      if (!mounted || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 0) return;
      final next = _controller.offset + 2.0;
      if (next >= max) {
        _controller.jumpTo(0);
      } else {
        _controller.jumpTo(next);
      }
    });
  }
  @override
  void dispose() {
    _timer?.cancel();
    _controller.dispose();
    super.dispose();
  }
  @override
  Widget build(BuildContext context) {
    final doubled = [...widget.icons, ...widget.icons, ...widget.icons];
    return ListView.builder(
      controller: _controller,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: doubled.length,
      itemBuilder: (_, i) => Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: SvgPicture.string(doubled[i], width: 36, height: 36)),
    );
  }
}


