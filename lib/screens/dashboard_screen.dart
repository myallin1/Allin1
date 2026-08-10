// ================================================================
// dashboard_screen.dart — Allin1 Super App Customer Dashboard
// Premium Pink UI — Mega Cards Revamp — June 2026
// Patches: stream lift, optimistic wallet, cache layer, error feedback, zero deprecation
// ================================================================

import 'dart:async';

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
import '../services/app_update_checker.dart';
import '../services/city_service.dart';
import '../services/hive_cache.dart';
import '../services/local_sync_service.dart';
import '../services/localization_service.dart';
import '../services/location_service.dart';
import '../services/prefs_cache.dart';
import '../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../services/pwa_cache_platform_web.dart';
import '../services/theme_service.dart';
import '../services/update_service.dart';
import '../services/usage_tracking_service.dart';
import '../services/web_version_checker.dart';
import '../widgets/banner_slider.dart';
import '../widgets/coach_mark_overlay.dart';
import '../widgets/download_app_banner.dart';
import '../widgets/promo_overlay.dart';
import 'bike_taxi/bike_booking_screen.dart';
import 'car_wash_screen.dart';
import 'coming_soon_screen.dart';
import 'construction_screen.dart';
import 'food_hub_screen.dart';
import 'grocery_order_screen.dart';
import 'guru_chat_screen.dart';
import 'hero_booking_screen.dart';
import 'my_orders_screen.dart';
import 'nj_tech_service_screen.dart';
import 'nj_tech_store_screen.dart';
import 'play_zone_screen.dart';
import 'printing_service_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';
import 'ride_history_screen.dart';
import 'settings_screen.dart';
import 'sos_screen.dart';

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
List<Map<String, Object>> get _bannerItems => [
  {'title': 'BIKE TAXI', 'emoji': '🏍️', 'color': kTeal},
  {'title': 'CAB', 'emoji': '🚗', 'color': kBlue},
  {'title': 'AUTO', 'emoji': '🛺', 'color': kPurple},
  {'title': 'GROCERIES', 'emoji': '🛒', 'color': kGreen},
  {'title': 'FOOD', 'emoji': '🍔', 'color': kGold},
  {'title': 'SERVICES', 'emoji': '🔧', 'color': kPink},
];

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

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_restoreLastTab());
    unawaited(_silentBackupIfNeeded());
    unawaited(_detectCityInBackground());
    // Per Nizam's request: warm up GPS the moment the home page opens, so
    // by the time the customer taps Taxi/Food/Hero, LocationService already
    // has a cached position ready — the booking screen no longer has to
    // run its own permission-check + GPS-fetch from a cold start.
    unawaited(_prefetchLocationInBackground());
    // Auto-show the daily Paytm Soundbox scratch card once per calendar day
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
            // _alreadyScratchedToday() is async because HiveCache.get() is.
            if (!await _alreadyScratchedToday()) {
              if (!mounted) return;
              _showScratchCardModal();
            }
          },
        );
        return;
      }

      // _alreadyScratchedToday() is async because HiveCache.get() is.
      // It previously read the Future without awaiting and cast it to
      // String?, which threw a TypeError before this branch could run —
      // so the scratch card never appeared at all.
      if (!await _alreadyScratchedToday()) {
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
    super.dispose();
  }

  // ── Daily scratch gate (local, calendar-day) ─────────────────
  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  /// TTL for cache keys that must survive a whole calendar day.
  ///
  /// HiveCache.put() defaults to a 30-MINUTE ttl. Every daily gate in this
  /// file (scratch card, coins backup) and in checkout_screen.dart (daily
  /// coin-redemption cap) relied on that default, which means that once
  /// the missing-await bug below is fixed those gates would silently reset
  /// every 30 minutes. These keys must therefore always be written with an
  /// explicit ttl. Day-rollover correctness comes from comparing the
  /// stored value against _todayKey(); this ttl only guarantees the entry
  /// outlives the day it was written for.
  static const Duration _dailyKeyTtl = Duration(hours: 24);

  Future<bool> _alreadyScratchedToday() async =>
      (await HiveCache.get<String>('last_scratch_date')) == _todayKey();

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

  void _navigate(Widget screen) => Navigator.push<void>(
    context, MaterialPageRoute<void>(builder: (_) => screen),);

  Future<void> _launchBroadband() async {
    _navigate(const NjTechBroadbandWebView());
  }

  // FIX (per Nizam/CTO's approved feature batch): Puncture Service direct
  // contact number set to the CTO-provided number (was a different,
  // incorrect number before this).
  Future<void> _callPuncture() async {
    final uri = Uri.parse('tel:+919843262951');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _showScratchCardModal() {
    // Mark today as used so the card auto-shows at most once per calendar day,
    // whether or not the customer fully scratches it.
    // Explicit ttl is REQUIRED — HiveCache.put() defaults to 30 minutes,
    // which would let the card re-appear ~48x/day. See _dailyKeyTtl.
    unawaited(
      HiveCache.put('last_scratch_date', _todayKey(), ttl: _dailyKeyTtl),
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
      case 'food':        _navigate(const FoodHubScreen()); break;
      case 'grocery':     _navigate(const GroceryOrderScreen()); break;
      case 'njtech':      _navigate(const NJTechStoreScreen()); break;
      case 'carwash':     _navigate(const CarWashScreen()); break;
      case 'puncture':    _callPuncture(); break;
      case 'construction':_navigate(const ConstructionScreen()); break;
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
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_navIndex != 0) { _goTab(0); return; }
        final t = context.read<LocalizationService>().t;
        final exit = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: kBg,
            title: Text(t('exit_app_title'),
                style: GoogleFonts.outfit(
                    color: kText, fontWeight: FontWeight.w700,),),
            content: Text(t('exit_app_body'),
                style: GoogleFonts.outfit(color: kMuted),),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: Text(t('no_label'), style: TextStyle(color: kPink)),),
              TextButton(onPressed: () => Navigator.pop(context, true),
                  child: Text(t('yes_label'), style: TextStyle(color: kRed)),),
            ],
          ),
        );
        if ((exit ?? false) && context.mounted) SystemNavigator.pop();
      },
      child: Scaffold(
        key: _scaffoldKey,
        backgroundColor: kBg,
        drawer: _ProfileDrawer(user: _user, onNavigate: _navigate),
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
    final name = _user?.displayName ?? 'User';
    final firstName = name.split(' ').first;

    return AppBar(
      backgroundColor: kBg,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      titleSpacing: 0,
      leading: IconButton(
        icon: Icon(Icons.menu_rounded, color: kPink, size: 26),
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
                  '${context.watch<LocalizationService>().t('greeting_hi')}, $firstName',
                  style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
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
          child: Icon(Icons.notifications_outlined, color: kText, size: 22),
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
                    if (icon != null) Icon(icon, color: active ? kPink : kMuted, size: 24) else _A1BadgeIcon(active: active),
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
                'assets/images/assistant.gif',
                width: 46, height: 46,
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
        const _CategorySlidingBanner(),
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
        _buildPrintingMegaCard(context),
        const SizedBox(height: 12),
        _buildOtherServicesMegaCard(context),
        // ───────────────────────────────────────────────────

        const SizedBox(height: 12),
        _buildFeaturedShop(context),
        const SizedBox(height: 10),
        _buildPromoCards(context),
        const SizedBox(height: 20),
        BannerAdsSlider(
          height: 240,
          textSlides: [
            BannerTextSlide(
              title: 'Internet Offers 🌐',
              subtitle: 'Fast recharge plans & broadband deals — tap to explore',
              gradient: const [Color(0xFFFF4FA3), Color(0xFF7B2FF7)],
              icon: Icons.wifi_rounded,
              // FIX (per Nizam's request — "internet offer option thotta
              // nammaloda internet option kulla poganum"): reuses the
              // exact same _launchBroadband() flow the "Other Services"
              // mega card's own Internet tile already calls.
              onTap: () => onTileTap('broadband'),
            ),
          ],
          imageUrls: [
            'https://images.unsplash.com/photo-1593640408182-31c70c8268f5?w=800&q=80',
            'https://images.unsplash.com/photo-1546054454-aa26e2b734c7?w=800&q=80',
          ],
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.taxi, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('taxi_mega_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('taxi_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
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
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.motor_scooter, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.package, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.auto_rickshaw, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.oncoming_taxi, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.delivery_truck, width: 32, height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
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
              MaterialPageRoute(builder: (_) => const FoodHubScreen()),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.hamburger, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('food_delivery_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('food_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          GestureDetector(
            key: const Key('dashboard_tile_food'),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const FoodHubScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.hamburger, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.pizza, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.chicken, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.french_fries, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.shortcake, width: 32, height: 32),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.shopping_cart, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('grocery_mega_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('grocery_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
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
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.leafy_green, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.red_apple, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.carrot, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.onion, width: 32, height: 32),
                  SvgPicture.string(FluentEmojiFlat.shopping_cart, width: 32, height: 32),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── ELECTRONICS MEGA CARD (Slim Static Layout) ───────────────────────
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.mobile_phone, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('electronics_mega_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('electronics_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
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
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.mobile_phone, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.laptop, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.desktop_computer, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.video_camera, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.television, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.snowflake, width: 30, height: 30),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.oncoming_taxi, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('carservice_mega_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('carservice_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
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
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.oncoming_taxi, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.sweat_droplets, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.gear, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.hammer_and_wrench, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.sport_utility_vehicle, width: 30, height: 30),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.building_construction, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('construction_mega_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('construction_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
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
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.building_construction, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.brick, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.construction_worker, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.triangular_ruler, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.office_building, width: 30, height: 30),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.man_superhero, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('hero_booking_mega_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('hero_booking_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
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
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.man_superhero, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.high_voltage, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.package, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.shopping_bags, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.man_running, width: 30, height: 30),
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
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        SvgPicture.string(FluentEmojiFlat.printer, width: 20, height: 20),
                        const SizedBox(width: 6),
                        Text(
                          context.watch<LocalizationService>().t('printing_mega_title'),
                          style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                        ),
                      ],
                    ),
                    Text(
                      '  ${context.watch<LocalizationService>().t('printing_mega_subtitle')}',
                      style: TextStyle(color: kMuted, fontSize: 11),
                    ),
                  ],
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
                color: kPink.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  SvgPicture.string(FluentEmojiFlat.card_index, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.scroll, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.framed_picture, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.label, width: 30, height: 30),
                  SvgPicture.string(FluentEmojiFlat.printer, width: 30, height: 30),
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
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      SvgPicture.string(FluentEmojiFlat.hammer_and_wrench, width: 20, height: 20),
                      const SizedBox(width: 6),
                      Text(
                        context.watch<LocalizationService>().t('otherservices_mega_title'),
                        style: GoogleFonts.outfit(color: kText, fontSize: 14, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  Text(
                    '  ${context.watch<LocalizationService>().t('otherservices_mega_subtitle')}',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: kPink.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: kPink.withValues(alpha: 0.2), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSmallActionTile(context, FluentEmojiFlat.antenna_bars, context.watch<LocalizationService>().t('other_internet_label'), () => onTileTap('broadband')),
                _buildSmallActionTile(context, FluentEmojiFlat.motorcycle, context.watch<LocalizationService>().t('other_puncture_label'), () => onTileTap('puncture')),
                _buildSmallActionTile(context, FluentEmojiFlat.broom, context.watch<LocalizationService>().t('other_cleaning_label'), () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(role: 'Home Cleaning')))),
                _buildSmallActionTile(context, FluentEmojiFlat.high_voltage, context.watch<LocalizationService>().t('other_electrician_label'), () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(role: 'Electrician')))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSmallActionTile(BuildContext context, String iconSvg, String label, VoidCallback onTap) {
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
            child: Center(child: SvgPicture.string(iconSvg, width: 28, height: 28)),
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
            MaterialPageRoute<void>(builder: (_) => const BikeBookingScreen()),),
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1035),
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(children: [
            const Text('🏍️', style: TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(child: Column(
                crossAxisAlignment: CrossAxisAlignment.start, children: [
              // Font switched from notoSansTamil to outfit along with the
              // copy — notoSansTamil exists to render Tamil glyphs, and
              // keeping it for English text just loads a font the app
              // doesn't otherwise need here.
              Text(t('promo_free_ride_title'),
                  style: GoogleFonts.outfit(
                      color: kPink, fontSize: 13, fontWeight: FontWeight.w700,),),
              const SizedBox(height: 2),
              Text(t('promo_free_ride_subtitle'),
                  style: GoogleFonts.outfit(
                      color: Colors.white60, fontSize: 10,),),
            ],),),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kPink, borderRadius: BorderRadius.circular(10),),
              child: Text(t('promo_book_label'), style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w700,),),
            ),
          ],),
        ),
      ),
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
              child: Center(
                child: Image.asset(
                  'assets/images/assistant.gif',
                  width: 32, height: 32,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('💬', style: TextStyle(fontSize: 22)),
                ),
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
  final void Function(Widget) onNavigate;
  const _ProfileDrawer({required this.user, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    final name  = user?.displayName ?? 'Guest';
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
                        .snapshots(),
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

  @override
  void initState() {
    super.initState();
    _openInApp();
  }

  Future<void> _openInApp() async {
    setState(() { _loading = true; _launched = false; });
    final uri = Uri.parse('https://www.erodefiber.net/');
    try {
      await launchUrl(uri, mode: LaunchMode.inAppWebView);
      if (mounted) setState(() { _loading = false; _launched = true; });
    } catch (_) {
      try {
        await launchUrl(uri, mode: LaunchMode.inAppBrowserView);
        if (mounted) setState(() { _loading = false; _launched = true; });
      } catch (e) {
        if (mounted) setState(() { _loading = false; _launched = false; });
      }
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
            : _launched
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('🌐', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 16),
                    Text(t('erode_fiber_open_title'),
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20, fontWeight: FontWeight.w800,),),
                    const SizedBox(height: 8),
                    Text(t('erode_fiber_open_subtitle'),
                        style: GoogleFonts.outfit(
                            color: Colors.white54, fontSize: 13,),),
                    const SizedBox(height: 28),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14,),
                        decoration: BoxDecoration(
                          color: kPink,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(
                              color: kPink.withValues(alpha: 0.4),
                              blurRadius: 12,),],
                        ),
                        child: Text(t('back_to_dashboard_label'),
                            style: GoogleFonts.outfit(
                                color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w700,),),
                      ),
                    ),
                  ],)
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

class _ScratchCardModalState extends State<_ScratchCardModal> {
  bool   _revealed = false;
  double _progress = 0;

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
        color: kNJDark,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kGold.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [BoxShadow(
            color: kGold.withValues(alpha: 0.2), blurRadius: 30,),],
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
          child: Row(children: [
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.15),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: kGold.withValues(alpha: 0.5)),
              ),
              child: Text(t('daily_scratch_badge'),
                  style: GoogleFonts.outfit(
                      color: kGold, fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 0.5,),),
            ),
            const Spacer(),
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.08),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close_rounded,
                    color: Colors.white54, size: 18,),
              ),
            ),
          ],),
        ),
        Text(t('scratch_reveal_hint'),
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Scratcher(
            brushSize: 40,
            threshold: 45,
            color: const Color(0xFFD4AF37),
            onThreshold: () => setState(() => _revealed = true),
            onChange: (v) => setState(() => _progress = v),
            child: Container(
              height: 180,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(20),
                gradient: const LinearGradient(
                  colors: [Color(0xFF1E0E3E), Color(0xFF2A1060)],
                  begin: Alignment.topLeft, end: Alignment.bottomRight,
                ),
              ),
              child: Center(
                child: Column(mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                  const Text(emoji, style: TextStyle(fontSize: 52)),
                  const SizedBox(height: 10),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: kPink, fontSize: 22,
                          fontWeight: FontWeight.w900,),),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: Colors.white70, fontSize: 13,),),
                ],),
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
              backgroundColor: Colors.white12,
              valueColor: AlwaysStoppedAnimation<Color>(
                  _revealed ? kGreen : kGold,),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(_revealed ? t('scratch_revealed_label') : t('scratch_keep_going_label'),
            style: GoogleFonts.outfit(
                color: _revealed ? kGreen : Colors.white38,
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
                    color: kGold,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(
                        color: kGold.withValues(alpha: 0.4),
                        blurRadius: 10,),],
                  ),
                  child: Center(child: Text(t('call_to_claim_label'),
                      style: GoogleFonts.outfit(
                          color: Colors.black,
                          fontSize: 15, fontWeight: FontWeight.w800,),),),
                ),
              ),
            ),
          )
        else
          const SizedBox(height: 20),
      ],),
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
class _CategorySlidingBanner extends StatefulWidget {
  const _CategorySlidingBanner();
  @override
  State<_CategorySlidingBanner> createState() => _CategorySlidingBannerState();
}

class _CategorySlidingBannerState extends State<_CategorySlidingBanner> {
  final PageController _pageController = PageController();
  int _currentIndex = 0;
  Timer? _autoScrollTimer;

  // Fixed count regardless of language -- used by the auto-scroll timer,
  // which fires before/independent of any given build() and can't call
  // t() itself. The actual translated titles are built fresh in build()
  // via _buildSlides() below so they follow the active language.
  static const int _slideCount = 4;

  static const List<List<String>> _slideIcons = [
    [
      FluentEmojiFlat.motor_scooter, FluentEmojiFlat.package, FluentEmojiFlat.auto_rickshaw,
      FluentEmojiFlat.oncoming_taxi, FluentEmojiFlat.delivery_truck, FluentEmojiFlat.bicycle,
    ],
    [
      FluentEmojiFlat.hamburger, FluentEmojiFlat.pizza, FluentEmojiFlat.chicken,
      FluentEmojiFlat.french_fries, FluentEmojiFlat.cup_with_straw, FluentEmojiFlat.shortcake,
    ],
    [
      FluentEmojiFlat.leafy_green, FluentEmojiFlat.red_apple, FluentEmojiFlat.carrot,
      FluentEmojiFlat.onion, FluentEmojiFlat.garlic, FluentEmojiFlat.shopping_cart,
    ],
    [
      FluentEmojiFlat.mobile_phone, FluentEmojiFlat.laptop, FluentEmojiFlat.battery,
      FluentEmojiFlat.antenna_bars, FluentEmojiFlat.hammer_and_wrench, FluentEmojiFlat.delivery_truck,
    ],
  ];

  List<_CategorySlideData> _buildSlides(String Function(String) t) {
    const titleKeys = [
      'category_taxi_slide',
      'category_food_slide',
      'category_grocery_slide',
      'category_services_slide',
    ];
    return List.generate(_slideCount, (i) =>
        _CategorySlideData(title: t(titleKeys[i]), icons: _slideIcons[i]),);
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
    final t = context.watch<LocalizationService>().t;
    final slides = _buildSlides(t);
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
              return Container(
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
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(slide.title, style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Expanded(child: _IconMarquee(icons: slide.icons)),
                  ],
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
  const _CategorySlideData({required this.title, required this.icons});
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

