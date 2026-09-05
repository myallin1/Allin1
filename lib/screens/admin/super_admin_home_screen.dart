import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/app_minimizer_service.dart';
import '../../services/db_usage_tracker.dart';
import '../../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../../services/pwa_cache_platform_web.dart';
import '../../services/service_requests_listener.dart';
import '../../services/sos_dispatch_service.dart';
import '../../services/web_version_checker.dart';
import '../../services/chitti_overlay_service.dart';
import '../../services/guru_overlay_service.dart';
import '../../services/chitti/chitti_dev_monitor_service.dart';
import '../../services/map_simulation_service.dart';
import '../../widgets/download_app_banner.dart';
import 'admin_ai_settings_screen.dart';
import 'admin_app_versions_screen.dart';
import 'admin_cloudinary_dashboard_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_chitti_lens_screen.dart';
import 'admin_cm_presentation_screen.dart';
import 'admin_dialer_screen.dart';
import 'admin_my_day_screen.dart';
import 'admin_web_tabs_screen.dart';
import 'clay_gallery_screen.dart';
import '../../services/admin_shell_nav.dart';
import '../../services/admin_webview_power.dart';
import 'chitti_conversations_screen.dart';
import 'chitti_debug_logs_screen.dart';
import 'chitti_dev_monitor_screen.dart';
import 'admin_food_orders_screen.dart';
import 'admin_gift_coupons_screen.dart';
import 'admin_orders_cleanup_screen.dart';
import 'admin_affiliate_leads_screen.dart';
import 'admin_affiliate_qr_screen.dart';
import 'admin_map_simulation_screen.dart';
import 'admin_qr_generator_screen.dart';
import 'admin_service_requests_screen.dart';
import 'admin_sos_kyc_approvals_screen.dart';
import 'admin_taxi_rides_screen.dart';
import 'admin_ux_audit_screen.dart';
import 'commission_settings_screen.dart';
import 'customer_usage_tracking_screen.dart';
import 'bug_reports_screen.dart';
import 'customer_demand_screen.dart';
import 'payments_received_screen.dart';
import 'usage_fee_ledger_screen.dart';
import 'erode_offers_management_screen.dart';
import 'admin_home_banner_screen.dart';
import '../../services/firestore_usage_tracking.dart';

class SuperAdminHomeScreen extends StatefulWidget {
  const SuperAdminHomeScreen({super.key});

  @override
  State<SuperAdminHomeScreen> createState() => _SuperAdminHomeScreenState();
}

class _SuperAdminHomeScreenState extends State<SuperAdminHomeScreen> {
  static const Color _bg = Color(0xFF0A0A12);
  static const Color _surface = Color(0xFF12121E);
  static const Color _purple = Color(0xFF6C63FF);
  static const Color _orange = Color(0xFFFF6B35);
  static const Color _gold = Color(0xFFFFBB00);
  static const Color _text = Color(0xFFEEEEF5);

  // ── New-request sound/vibration alert ────────────────────────
  // Admin app-open-only alert (no Blaze plan → no background Cloud
  // Function / push, per Nizam's decision). Watches BOTH Hero
  // Booking and Electronics Service requests still waiting for a
  // hero (pending/admin_review — the same set the bottom buttons'
  // badges count) and plays the existing ride_alert.mp3 sound +
  // a vibration the moment a NEW request id appears that wasn't in
  // the previous snapshot. First snapshot on load never alerts (would
  // otherwise fire for every already-waiting request on every app
  // open) — only subsequent *new* arrivals do.
  final AudioPlayer _alertPlayer = AudioPlayer();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _alertSub;
  Set<String> _knownWaitingIds = {};
  bool _alertPrimed = false;

  // FIX (root cause of "admin app open = ~1000 reads", found while
  // chasing the same symptom in admin_dashboard_screen.dart — see that
  // file for the full explanation): _buildSosCallCenterBanner() used to
  // call .snapshots() INLINE inside its build method, called from this
  // StatefulWidget's overall build path. Any rebuild anywhere in this
  // screen tore down and recreated this listener, re-paying the full
  // initial-read cost every time. Hoisted to an instance field, created
  // once. Kept LIVE (not manual-refresh) — this feeds the emergency SOS
  // banner, which is safety-critical and must update instantly.
  //
  // NOTE: _statsRowRidesStream (Rides Today/Active Heroes/Revenue stat
  // row) used to live here too, with NO .limit() at all — a genuinely
  // unbounded live listener. The widget that rendered it was already
  // removed per Nizam's request (duplicated AdminDashboardScreen's own
  // Overview tab), but the stream itself was accidentally left running
  // just to feed the DB usage side-channel counter — i.e. a real,
  // uncapped Firestore listener open on every admin app load with ZERO
  // UI benefit. Deleted entirely as part of the auto-listener cleanup.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sosAlertsStream;

  // FIX (unnecessary-read consolidation): _NavWaitingDot (x2, bottom nav)
  // and _AdminReviewBadgeWrapper used to each open their OWN separate
  // service_requests listener with an overlapping status filter — 3
  // extra live listeners, on top of the alert listener below which
  // already reads nearly the same data. Every one of those re-paid the
  // full query cost independently, every single time this screen opened
  // — exactly the "app open = unwanted database read" pattern Nizam
  // flagged. Hoisted to ONE shared stream (broadest superset: any
  // requestType, status pending/admin_review); every badge widget below
  // now derives its count by filtering this SAME stream's already-
  // fetched docs client-side, instead of opening its own listener.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _waitingRequestsStream;

  // Same caching reasoning — feeds _SosKycWaitingDot, which used to call
  // .snapshots() directly inside its own build(), re-subscribing to
  // sos_kyc_requests on every parent rebuild (every tab switch, every
  // setState). Hoisted here alongside the other badge streams.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _sosKycWaitingStream;

  @override
  void initState() {
    super.initState();
    // Sourced from the shared singleton (see service_requests_listener.dart)
    // instead of opening its own .snapshots() — AdminDashboardScreen and
    // AdminNewOrdersScreen (both pushed on top of this screen, which stays
    // alive underneath) now consume this SAME real Firestore listener.
    _waitingRequestsStream =
        ServiceRequestsListener.instance.waitingAndReviewStream;
    _sosKycWaitingStream = FirebaseFirestore.instance
        .collection('sos_kyc_requests')
        .where('status', isEqualTo: 'pending')
        .trackedSnapshots();
    _alertSub = _waitingRequestsStream.listen(_onWaitingRequestsChanged,
        onError: (Object e) {
      debugPrint('[SuperAdminHome] Alert listener error: $e');
    },);
    // FIX (Aug 29 2026 — Emergency Responder dispatch): matches the
    // identical fix on hero_home_screen.dart's own SOS stream. An
    // emergency that a hero has claimed and is actively calling the
    // customer about is not resolved — admin's live SOS badge should
    // keep counting it, not drop it the instant a hero says "I'm
    // Responding".
    _sosAlertsStream = FirebaseFirestore.instance
        .collection('sos_alerts')
        .where('status', whereIn: [
          SosAlertStatus.active,
          SosAlertStatus.claimed,
          SosAlertStatus.escalated,
        ])
        .trackedSnapshots();

    // DB usage monitor — side-channel count, shares the same
    // broadcast stream StreamBuilder already listens to, no extra reads.
    _waitingRequestsStream.listen((s) => DbUsageTracker.instance
        .recordRead(s.docs.length, 'admin_home_waiting_requests'));
    _sosAlertsStream.listen((s) => DbUsageTracker.instance
        .recordRead(s.docs.length, 'admin_home_sos_alerts'));

    AdminShellNav.register(_goToTab);

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ChittiOverlayService.instance.show(
        context,
        onTapChitti: () => GuruOverlayService.instance.show(autoStartMic: true),
      );
    });
  }

  @override
  void dispose() {
    AdminShellNav.unregister(_goToTab);
    _alertSub?.cancel();
    _alertPlayer.dispose();
    super.dispose();
  }

  static const _alertRequestTypes = {'hero_booking', 'electronics_service'};

  void _onWaitingRequestsChanged(QuerySnapshot<Map<String, dynamic>> snapshot) {
    // The shared stream now covers ALL requestTypes (widened so the nav
    // dots/admin-review badge can reuse it) — filter back down to just
    // the two types the alert sound is meant for.
    final currentIds = snapshot.docs
        .where((d) => _alertRequestTypes.contains(d.data()['requestType']))
        .map((d) => d.id)
        .toSet();
    if (!_alertPrimed) {
      // First snapshot after this screen opened — just record the
      // baseline, don't alert for requests that were already waiting.
      _alertPrimed = true;
      _knownWaitingIds = currentIds;
      return;
    }
    final newIds = currentIds.difference(_knownWaitingIds);
    _knownWaitingIds = currentIds;
    if (newIds.isNotEmpty) {
      _playNewRequestAlert();
    }
  }

  Future<void> _playNewRequestAlert() async {
    try {
      HapticFeedback.vibrate();
    } catch (e) {
      debugPrint('[SuperAdminHome] Haptic feedback failed (non-fatal): $e');
    }
    try {
      await _alertPlayer.stop();
      await _alertPlayer.play(AssetSource('sounds/ride_alert.mp3'));
    } catch (e) {
      debugPrint('[SuperAdminHome] Alert sound failed (non-fatal): $e');
    }
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _text)),
        backgroundColor: _surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _purple.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      unawaited(Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false));
    }
  }

  // ── Bottom nav — same real IndexedStack pattern as the CUSTOMER
  // app's dashboard_screen.dart bottom nav (Row of InkWell tabs,
  // tapping one swaps the whole body instead of scrolling to a
  // section). 3 tabs: Overview (stats/SOS/Taxi entry/settings/
  // logout), Hero (every Hero Booking request), Electronics (every
  // electronics enquiry). "Taxi & Transportation" is NOT one of these
  // tabs — it opens AdminDashboardScreen, which already has its OWN
  // full AppBar + bottom nav (Overview/Rides/Customers/New Orders), so
  // nesting it as a 4th IndexedStack tab here would stack two bottom
  // navs on screen at once. Instead it's a push (via the Taxi tile on
  // the Overview tab) — tap in, back button returns here, exactly
  // like tapping into any other detail screen.
  int _tabIndex = 0;

  // FIX (read-spike root cause): Flutter's IndexedStack builds AND MOUNTS
  // every child immediately on first frame, regardless of which index is
  // active — it never defers or disposes non-visible children. That
  // means both AdminServiceRequestsScreen instances below used to run
  // their initState() (and start their own service_requests .snapshots()
  // listener, each re-reading the WHOLE collection) the moment Admin
  // Home opened, even if the admin never tapped Hero or Electronics —
  // this is what was driving the ~1000-read spike on every admin app
  // open. Fix: track which tab indices have actually been visited, and
  // only put the REAL widget in that IndexedStack slot once visited;
  // unvisited slots get a cheap placeholder instead. Once visited, the
  // real widget stays in that slot for the rest of the screen's life
  // (IndexedStack keeps it mounted exactly as before), so switching back
  // and forth after the first visit is still instant with no re-listen.
  final Set<int> _visitedTabs = {0};

  void _goToTab(int index) {
    setState(() {
      _tabIndex = index;
      _visitedTabs.add(index);
    });
    unawaited(AdminWebViewPower.setActive(active: index == 4));
  }

  // FIX (per Nizam's request): App Settings / Check for Updates / Logout
  // used to sit directly on the main Overview page, making it feel
  // cluttered. Moved into a left-side drawer (tray) instead — opened via
  // the hamburger icon in _buildHeader() — so the main page only shows
  // what admin needs to glance at daily (Manage tiles), with settings
  // tucked away one tap deeper, same drawer pattern any admin panel uses.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // FIX (Aug 12 2026 — CTO mandate: "System Back Button Overhaul"): this
  // used to show a Yes/No "leave the app?" dialog and call
  // SystemNavigator.pop() on Yes, which FINISHES the Activity (a real
  // close) — exactly the "app terminates / blank on PWA / full cold-boot
  // rebuild on reopen" bug this feature fixes. Minimizing is safe and
  // fully reversible, so it no longer needs a confirmation dialog at
  // all. Tab-reset-first behavior is unchanged.
  void _handleBackPress() {
    // FIX (Aug 12 2026 — ROOT CAUSE of "back button minimizes the admin
    // app instead of navigating back"): this screen wraps its Scaffold
    // in PopScope(canPop: false). Flutter's Scaffold normally installs
    // its OWN back handler to close an open drawer — but a
    // canPop:false PopScope sits ABOVE the Scaffold in the widget tree
    // and intercepts the system back press first, so that built-in
    // drawer-close handler never runs. The press fell straight through
    // to the minimize branch below: admin opens the drawer, presses
    // back expecting the drawer to close, and the whole app minimizes
    // instead. Closing an open drawer must therefore be handled
    // explicitly here, BEFORE any tab-reset or minimize logic.
    final scaffold = _scaffoldKey.currentState;
    if (scaffold != null && scaffold.isDrawerOpen) {
      Navigator.of(context).pop();
      return;
    }
    // NEW (Sep 5 2026): on the Web tab (GitHub/Browser), back walks the
    // active segment's own history first.
    if (_tabIndex == 4) {
      unawaited(AdminWebTabsScreen.goBackIfPossible().then((wentBack) {
        if (!wentBack && mounted) _goToTab(0);
      }));
      return;
    }
    if (_tabIndex != 0) {
      _goToTab(0);
      return;
    }
    if (kIsWeb) {
      // A browser tab cannot minimize itself to the OS home screen — no
      // such API exists. Show the "use your device's Home button" hint
      // once per session, then silently swallow further back-presses.
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
      child: Scaffold(
      key: _scaffoldKey,
      backgroundColor: _bg,
      drawer: _buildDrawer(context),
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _buildOverviewTab(context),
            // UI REORG (per Nizam's request, Aug 31 2026): Hero,
            // Electronics, SOS Verify, Food Orders, Custom and Grocery
            // used to each be their own always-mounted bottom-nav tab —
            // 7 tabs total made the bar cramped and buried the thing
            // admin actually wanted one tap away (Chitti AI Config).
            // They're now reached via tiles on this single "Services"
            // tab (pushed on tap, not tabbed) — same screens, same
            // badges, zero backend/data changes, just a navigation
            // reshuffle. See _buildServicesTab below.
            _buildServicesTab(context),
            // NEW (per Nizam's request): Chitti AI Configuration is now
            // a direct bottom-nav tab instead of a Drawer -> AI Settings
            // scroll-down button — "udane access pannamudila" (couldn't
            // get to it instantly). Same lazy-mount-once-visited pattern
            // as the old per-type tabs above.
            if (_visitedTabs.contains(2)) const AdminAiSettingsScreen(key: ValueKey('chitti_ai_tab')) else const SizedBox.shrink(),
            // NEW (per Nizam's request, Sep 1 2026): a 4th tab holding
            // the two development-automation screens together. Both
            // already existed and were reachable only by scrolling deep
            // inside Chitti AI Configuration ("2 options ah iruku... 4th
            // optiona intha development section 2um intha section kulla
            // inner la 2screen optiona set panni"). This tab only
            // NAVIGATES to them — neither screen's own logic, service,
            // or backend wiring is touched, and their existing buttons
            // in AI Settings keep working, so nothing that already
            // depended on them can break.
            _buildDevelopmentTab(context),
            // NEW (Sep 4 2026 — Nizam: "namma main page bottom la athu
            // oru button ah irukanum apo than admin app kulla yenga
            // poitu vanthalum ... same screen la irukum, app close
            // pannitu vanthalum").
            //
            // As a TAB rather than a pushed screen, the WebView stays
            // mounted in this IndexedStack while he moves between tabs,
            // so switching away and back reloads nothing.
            // GitHubEmbeddedScreen's own static controller covers
            // leaving the screen entirely, and it now restores the last
            // page after the process is killed.
            //
            // NEW (Sep 5 2026 — Nizam: in-app browser beside GitHub).
            // AdminWebTabsScreen houses GitHub and Browser side by side.
            if (_visitedTabs.contains(4)) AdminWebTabsScreen(key: const ValueKey('github_tab'), visible: _tabIndex == 4) else const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
      ),
    );
  }

  // NEW (per Nizam's request, Aug 31 2026): "Services" tab — Hero,
  // Electronics, SOS Verify, Food Orders, Custom and Grocery tiles in
  // one place, one tap off the bottom nav (index 1). Reuses the exact
  // same screens and live waiting-count badges the old per-type tabs
  // used, just pushed via Navigator instead of kept always-mounted in
  // the IndexedStack — pure navigation change, no backend/data touched.
  Widget _buildServicesTab(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'SERVICES',
              style: TextStyle(
                color: _text.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          sliver: SliverList.list(
            children: [
              _AdminReviewBadgeWrapper(
                waitingStream: _waitingRequestsStream,
                child: _ManageTile(
                  label: 'Hero Booking Status',
                  subtitle: 'Every Hero Booking request',
                  iconSvg: FluentEmojiFlat.man_superhero,
                  color: _orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminServiceRequestsScreen(
                        requestType: 'hero_booking',
                        title: 'Hero Booking Status',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _AdminReviewBadgeWrapper(
                waitingStream: _waitingRequestsStream,
                child: _ManageTile(
                  label: 'Electronics Booking',
                  subtitle: 'Every electronics enquiry',
                  iconSvg: FluentEmojiFlat.mobile_phone,
                  color: _orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminServiceRequestsScreen(
                        requestType: 'electronics_service',
                        title: 'Electronics Booking',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              // FIX (UI reorg, Aug 31 2026): was wrapped in
              // _AdminReviewBadgeWrapper, which only counts docs with
              // status=='admin_review' — but _sosKycWaitingStream
              // already queries status=='pending' (see initState), so
              // that wrapper's count was silently always 0 and this
              // tile's badge could never show. _SosKycTile counts the
              // stream's docs directly instead.
              _SosKycTile(
                waitingStream: _sosKycWaitingStream,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminSosKycApprovalsScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _ManageTile(
                label: 'Food Orders',
                subtitle: 'Review and manage food orders',
                iconSvg: FluentEmojiFlat.takeout_box,
                color: _orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminFoodOrdersScreen(),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _AdminReviewBadgeWrapper(
                waitingStream: _waitingRequestsStream,
                child: _ManageTile(
                  label: 'Custom Orders',
                  subtitle: 'Review custom order requests',
                  iconSvg: FluentEmojiFlat.shopping_bags,
                  color: _orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminServiceRequestsScreen(
                        requestType: 'custom_order',
                        title: 'Custom Orders',
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              _AdminReviewBadgeWrapper(
                waitingStream: _waitingRequestsStream,
                child: _ManageTile(
                  label: 'Grocery Orders',
                  subtitle: 'Review DMart cart screenshots, assign heroes',
                  iconSvg: FluentEmojiFlat.shopping_cart,
                  color: _orange,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminServiceRequestsScreen(
                        requestType: 'grocery_order',
                        title: 'Grocery Orders',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // NEW (per Nizam's request, Sep 1 2026): the Development section —
  // the two automation screens in one place, plus the dialer the app
  // now needs as default phone app. Pure navigation: every screen here
  // is pushed exactly as its existing entry point pushes it, so no
  // service, listener, or backend path changes.
  Widget _buildDevelopmentTab(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
            child: Text(
              'DEVELOPMENT & AUTOMATION',
              style: TextStyle(
                color: _text.withValues(alpha: 0.5),
                fontSize: 11,
                fontWeight: FontWeight.w800,
                letterSpacing: 1.2,
              ),
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 20),
          sliver: SliverList.list(
            children: [
              _ManageTile(
                label: 'Development Monitor',
                subtitle: 'Latest test APK, builds running, dev tasks',
                iconSvg: FluentEmojiFlat.laptop,
                color: _purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const ChittiDevMonitorScreen()),
                ),
              ),
              const SizedBox(height: 10),
              // NEW (Sep 1 2026): the business-facing half of the call
              // data — what the caller wanted, in plain words. Kept
              // separate from Debug Logs below, which is the engineering
              // view of the same calls and is not readable as business
              // information.
              _ManageTile(
                label: 'Call Conversations',
                subtitle: 'What each caller said, with a summary',
                iconSvg: FluentEmojiFlat.speech_balloon,
                color: _purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const ChittiConversationsScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _ManageTile(
                label: 'Chitti Call Debug Logs',
                subtitle: 'Step-by-step logs of each screened call',
                iconSvg: FluentEmojiFlat.bug,
                color: _orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const ChittiDebugLogsScreen()),
                ),
              ),
              const SizedBox(height: 10),
              // Grouped here because it exists for the same reason the
              // rest of this tab does — the app became the device's
              // phone app, so it has to provide these controls itself.
              _ManageTile(
                label: 'Dialer',
                subtitle: 'Make a call, see the live call, hang up',
                iconSvg: FluentEmojiFlat.telephone,
                color: _orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminDialerScreen()),
                ),
              ),
              const SizedBox(height: 10),
              // NEW (Sep 4 2026 — Nizam: "chittiku camara on pannuna
              // udanede athu net la google lens open aguramari namma
              // app kulla vachcharlam"). Admin-only on purpose: it
              // spends a billable Vision API call per capture and is
              // aimed at the boss's own meetings, not customers.
              _ManageTile(
                label: 'My Day',
                subtitle: "What you said you'd do — Chitti follows up",
                iconSvg: FluentEmojiFlat.spiral_calendar,
                color: _purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminMyDayScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _ManageTile(
                label: 'Clay icons gallery',
                subtitle: 'All 3D clay icons in all 5 themes with live switcher',
                iconSvg: FluentEmojiFlat.artist_palette,
                color: _purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const ClayGalleryScreen()),
                ),
              ),
              const SizedBox(height: 10),
              _ManageTile(
                label: 'Chitti Lens',
                subtitle: 'Point the camera — Chitti looks it up and can greet them',
                iconSvg: FluentEmojiFlat.camera,
                color: _purple,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const AdminChittiLensScreen()),
                ),
              ),
              const SizedBox(height: 10),
              // NEW (Sep 4 2026): the CM/ministers briefing. Kept next
              // to Chitti Lens because they get used in the same room,
              // minutes apart.
              _ManageTile(
                label: 'CM Presentation',
                subtitle: 'Chitti introduces the app, asks permission, then briefs',
                iconSvg: FluentEmojiFlat.microphone,
                color: _orange,
                onTap: () => Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                      builder: (_) => const AdminCmPresentationScreen()),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    // FIX (per Nizam's request): removed the Rides Today/Active Heroes/
    // Revenue stat row from this outer page — it duplicated what's
    // already visible the moment admin taps into Taxi & Transportation
    // (AdminDashboardScreen has its own, identical Overview tab), so
    // showing it twice was redundant. App Settings + Check for Updates
    // + Logout also moved out of the main scroll into the left drawer
    // (see _buildDrawer) — this page now shows only what needs a daily
    // glance: the SOS banner and the Manage entry point.
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context)),
        SliverToBoxAdapter(child: _buildSosCallCenterBanner(context)),
        SliverToBoxAdapter(child: _buildManageSection(context)),
      ],
    );
  }

  // Same visual convention as dashboard_screen.dart's _buildBottomNav:
  // Row of InkWell icon+label items, active one highlighted.
  Widget _buildBottomNav() {
    // UI REORG (per Nizam's request, Aug 31 2026): "backend maarama quick
    // access pandratha" — collapsed the old 7-tab bar (Overview, Hero,
    // Electronics, SOS Verify, Food Orders, Custom, Grocery) down to 3:
    // Overview, Services (tiles for those 6, see _buildServicesTab) and
    // Chitti AI Config (one tap, was buried in AI Settings scroll
    // before). isServicesAggregate replaces the old per-type
    // requestType/isSos/isFoodOrders dots with one combined "something
    // needs review" dot on the Services tab itself.
    final List<({String icon, String label, bool isServicesAggregate, IconData? materialIcon})> items = [
      (icon: FluentEmojiFlat.bar_chart, label: 'Overview', isServicesAggregate: false, materialIcon: null),
      (icon: '', label: 'Services', isServicesAggregate: true, materialIcon: Icons.apps_rounded),
      (icon: '', label: 'Chitti AI', isServicesAggregate: false, materialIcon: Icons.smart_toy_rounded),
      // NEW (Sep 1 2026): Development & Automation — see
      // _buildDevelopmentTab. No badge stream: nothing here is a queue
      // waiting on the admin, so a dot would be noise.
      (icon: '', label: 'Dev', isServicesAggregate: false, materialIcon: Icons.terminal_rounded),
      // NEW (Sep 5 2026): Web (GitHub + Browser), one tap from anywhere.
      (icon: '', label: 'Web', isServicesAggregate: false, materialIcon: Icons.language_rounded),
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _purple.withValues(alpha: 0.15))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 16,
              offset: const Offset(0, -4),),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: List.generate(items.length, (i) {
            final active = _tabIndex == i;
            final item = items[i];
            return Expanded(
              child: InkWell(
                onTap: () => _goToTab(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Stack(
                      clipBehavior: Clip.none,
                      children: [
                        SizedBox(
                          width: 22,
                          height: 22,
                          child: Opacity(
                            opacity: active ? 1.0 : 0.55,
                            child: item.materialIcon != null
                                ? Icon(item.materialIcon,
                                    color: active ? _gold : _text.withValues(alpha: 0.55), size: 22,)
                                : SvgPicture.string(item.icon),
                          ),
                        ),
                        if (item.isServicesAggregate)
                          Positioned(
                            top: -4,
                            right: -8,
                            child: _ServicesAggregateWaitingDot(
                                waitingStream: _waitingRequestsStream,
                                sosKycWaitingStream: _sosKycWaitingStream,),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 9.5,
                            color: active ? _gold : _text.withValues(alpha: 0.55),
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400,),),
                  ],),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  Widget _buildSosCallCenterBanner(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: _sosAlertsStream,
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final doc = snapshot.data!.docs.first;
        final data = doc.data();
        final userName = data['userName']?.toString().trim();
        final userPhone = data['userPhone']?.toString().trim();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF1744), Color(0xFF7A0014)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF1744).withValues(alpha: 0.45),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LIVE SOS ALERT - CALL CENTER ACTION REQUIRED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (userName != null && userName.isNotEmpty) userName,
                        if (userPhone != null && userPhone.isNotEmpty)
                          userPhone,
                        'Dispatch support / Police 100 immediately',
                      ].join(' • '),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  await doc.reference.update({
                    'status': 'resolved',
                    'resolvedAt': FieldValue.serverTimestamp(),
                    'resolvedBy':
                        FirebaseAuth.instance.currentUser?.uid ?? 'admin',
                  });
                  if (context.mounted) {
                    _showSnack(context, 'SOS resolved and cleared.');
                  }
                },
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Resolve SOS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB00020),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          bottom: BorderSide(color: _purple.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            onPressed: () => _scaffoldKey.currentState?.openDrawer(),
            icon: Icon(Icons.menu_rounded, color: _text.withValues(alpha: 0.7)),
            tooltip: 'Settings menu',
          ),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _purple.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.lock, color: _purple, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔐 Allin1 HQ',
                  style: TextStyle(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'NJ TECH Admin Portal',
                  style: TextStyle(
                    color: _text.withValues(alpha: 0.55),
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(
              Icons.notifications_outlined,
              color: _text.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  // FIX (per Nizam's request): the Rides Today/Active Heroes/Revenue
  // stat row that used to live here was removed — it duplicated
  // AdminDashboardScreen's own Overview tab shown the moment admin taps
  // into Taxi & Transportation below, so showing it twice was
  // redundant. The stream that fed it (_statsRowRidesStream, unbounded
  // live listener) has since been deleted entirely too — see the note
  // near _sosAlertsStream above.

  // ── Manage section — single source of truth for every admin
  // category, all in one clearly-labeled place. Replaces the old
  // 2x2 card grid (2 of its 4 cards were permanently-disabled "coming
  // soon" placeholders for Food Delivery / Electronics Shop — the
  // real Electronics management already exists via the button below,
  // so that duplicate placeholder card is gone) plus a visually
  // separate row of buttons underneath — now one strip.
  //
  // Icons use the same colorful_iconify_flutter (FluentEmojiFlat) set
  // the customer app's dashboard uses, replacing the old flat Material
  // icons (Icons.electric_moped, Icons.devices, etc.) for a consistent,
  // modern look across apps.
  Widget _buildManageSection(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'MANAGE',
            style: TextStyle(
              color: _text.withValues(alpha: 0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _AdminReviewBadgeWrapper(
            waitingStream: _waitingRequestsStream,
            child: _ManageTile(
              label: 'Taxi & Transportation',
              subtitle: 'Rides, customers, escalated orders',
              iconSvg: FluentEmojiFlat.oncoming_taxi,
              color: _orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AdminDashboardScreen(),
                ),
              ),
            ),
          ),
          // Hero Booking Status and Electronics Booking used to be tiles
          // here too — they're now their own bottom-nav tabs (Hero /
          // Electronics) so admins reach them with one tap instead of
          // Overview -> tile -> pushed screen. Taxi stays a tile because
          // AdminDashboardScreen owns its own full Scaffold/bottom-nav
          // and is reached by push, not by swapping this screen's body.
          // App Settings moved to the left drawer (see _buildDrawer) —
          // this Manage section now holds only Taxi & Transportation.
          const SizedBox(height: 10),
          // NEW (per Nizam's request): a direct "Grocery Orders" entry
          // point right on the Overview page, on top of the Grocery tile
          // on the Services tab — this is the screen admins need most
          // now that the DMart-screenshot workflow depends on them
          // reviewing uploaded cart photos quickly, so it shouldn't
          // require hunting through Services first.
          // FIX (UI reorg, Aug 31 2026): was `_goToTab(6)`, jumping to a
          // fixed IndexedStack slot that held the always-mounted Grocery
          // tab. That slot no longer exists (bottom nav collapsed to 3
          // tabs — Overview/Services/Chitti AI, see _buildBottomNav) so
          // this would have thrown a RangeError the first time an admin
          // tapped it. Pushes the same screen the Services tab's Grocery
          // tile pushes instead.
          _AdminReviewBadgeWrapper(
            waitingStream: _waitingRequestsStream,
            child: _ManageTile(
              label: 'Grocery Orders',
              subtitle: 'Review DMart cart screenshots, assign heroes',
              iconSvg: FluentEmojiFlat.shopping_cart,
              color: _orange,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const AdminServiceRequestsScreen(
                    requestType: 'grocery_order',
                    title: 'Grocery Orders',
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          // NEW (per Nizam's placement choice): Gift Coupons. A coupon
          // is minted automatically every time a customer pays for a
          // service (onServiceRequestUpdated), and stays sealed until
          // an admin decides what's inside — so this is a queue that
          // needs working daily, which is why it sits on Overview
          // rather than being buried in the drawer.
          _ManageTile(
            label: 'Gift Coupons',
            subtitle: 'Set the gift inside customers’ scratch cards',
            iconSvg: FluentEmojiFlat.wrapped_gift,
            color: const Color(0xFFFFC107),
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const AdminGiftCouponsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // FIX (per Nizam's request): App Settings, Check for Updates, and
  // Logout moved here from the main Overview scroll — opened via the
  // hamburger icon in _buildHeader(), same as any standard admin-panel
  // side drawer, so the main page stays focused on daily-glance content.
  Widget _buildDrawer(BuildContext context) {
    // FIX (Aug 12 2026 — Nizam: "hamburger tray kulla list full aiduchu,
    // scroll panni vitu keela iruka update buttons pakka mudila"): this
    // whole drawer used to be ONE plain, non-scrolling Column with a
    // Spacer() pinning the download banner + version text to the
    // bottom. That layout only works while every tile fits in the
    // drawer's fixed height; the list has grown (UX Audit, Orders
    // Cleanup, Poster QR Generator, etc.) past that point, so the
    // bottom tiles (Check for Updates, Logout) were pushed off-screen
    // with literally no way to reach them — a plain Column has no
    // scroll behavior on its own, Spacer() included.
    //
    // FIX: header stays fixed at top, the tile list is now the ONLY
    // scrollable region (Expanded + ListView), and the version text
    // stays pinned at the very bottom outside the scroll area — same
    // visual layout as before, just actually reachable now. Not one
    // tile's onTap/order/icon was touched.
    return Drawer(
      backgroundColor: _surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              // FIX (UI standardization, Aug 11 2026): section headers
              // are 16sp app-wide, distinct from 18sp app-bar titles.
              child: Text(
                'Settings',
                style: TextStyle(
                  color: _text,
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Divider(color: _purple.withValues(alpha: 0.15), height: 1),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: EdgeInsets.zero,
                children: [
            ListTile(
              leading: const Icon(Icons.settings_outlined, color: _gold),
              title: const Text('App Settings', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Commission, fares, ads, credentials',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const CommissionSettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded, color: Color(0xFFE05555)),
              title: const Text('Admin AI Configuration', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Paste your Groq + Gemini API keys',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminAiSettingsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.local_offer_outlined, color: Color(0xFFFF4FA3)),
              title: const Text('Erode Offers', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Manage shop offers shown to customers',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminErodeOffersScreen()),
                );
              },
            ),
            // NEW (Aug 19 2026 — Nizam's "home page banner offer"
            // request). Separate feature/collection from Erode Offers
            // above — see admin_home_banner_screen.dart.
            ListTile(
              leading: const Icon(Icons.view_carousel_outlined, color: Color(0xFFB21FFF)),
              title: const Text('Home Page Banner Offers', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Manage the sliding banner on the customer home page',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminHomeBannerScreen()),
                );
              },
            ),
            // NEW (CTO mandate — Synthetic QA Test-Bot, Step 2: Side
            // Hamburger Tray Integration): "must not be hidden — must be
            // directly accessible as a dedicated menu item inside the
            // Admin app's Side Hamburger Drawer/Tray", per the CTO's
            // exact wording. Read-only screen, no existing tile touched.
            ListTile(
              leading: const Icon(Icons.fact_check_outlined, color: Color(0xFF00C853)),
              title: const Text('UX Audit Reports', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Synthetic QA bot findings across core screens',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminUxAuditScreen()),
                );
              },
            ),
            // NEW (per Nizam's bug report — "new ride vanthurukku, atha
            // vera hero ku assign pandra step yenga irukunu therila"):
            // AdminTaxiRidesScreen already existed (live rides list +
            // manual hero reassignment for VIP/timed-out bookings) but
            // had ZERO navigation entry point anywhere in the app —
            // genuinely unreachable except by editing code. This is the
            // fix, and it's also exactly where the new ride-alert
            // notification's tap now navigates to.
            ListTile(
              leading: const Icon(Icons.local_taxi_rounded, color: Color(0xFFFF9800)),
              title: const Text('Taxi Rides', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Live rides + manual hero assignment',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    // Named to match admin_alert_notification_service.dart's
                    // dedupe check — without this, opening Taxi from the
                    // drawer and THEN tapping a ride notification would
                    // still stack a second copy (each with its own live
                    // rides listener). Same name = one instance, always.
                    settings: const RouteSettings(name: '/admin/taxi-rides'),
                    builder: (_) => const AdminTaxiRidesScreen(),
                  ),
                );
              },
            ),
            // NEW (per Nizam's request, final pre-launch testing stage):
            // "customer usage tracking" — landing page visits + APK
            // downloads (per app) + total signups, to monitor organic
            // link usage outside the Play Store.
            ListTile(
              leading: const Icon(Icons.query_stats_rounded, color: Color(0xFF00E5FF)),
              title: const Text('Customer Usage Tracking', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Landing page visits, downloads, signups',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const CustomerUsageTrackingScreen()),
                );
              },
            ),
            // NEW (per Nizam's "Self vs MyAllin1" payment-split
            // request): when a hero marks a ride paid via the company's
            // own MyAllin1 UPI, that money never touches the hero's
            // wallet — it needs its own admin-facing verify/reconcile
            // page. Also surfaces the pre-existing "Payment Not
            // Received" dispute flag (hero_ride_screen.dart /
            // hero_history_screen.dart), which had zero admin
            // visibility before this screen.
            ListTile(
              leading: const Icon(Icons.account_balance_wallet_rounded, color: Color(0xFF00C853)),
              title: const Text('Payments Received', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('MyAllin1 UPI collections + unpaid-ride disputes',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const PaymentsReceivedScreen()),
                );
              },
            ),
            // NEW (Aug 11 2026 — Nizam's "Phase 2" revenue-tracking
            // audit request): real-time, chronological feed of every
            // platform infra usage-fee deduction (see
            // HeroWalletService.flushUsageCost() /
            // usage_fee_ledger_screen.dart), which had zero admin-side
            // visibility before this screen — the fee was being deducted
            // correctly but recorded nowhere Admin could see it.
            // NEW (Aug 11 2026 — Nizam's request): surfaces what
            // customers actually want (top places / hotels / vehicles /
            // services) so supply can be pointed at real demand. Reads a
            // single aggregate doc — see customer_demand_screen.dart.
            ListTile(
              leading: const Icon(Icons.insights_rounded, color: Color(0xFF00B8D4)),
              title: const Text('Customer Demand', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Top places, hotels, vehicles & services customers use',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const CustomerDemandScreen()),
                );
              },
            ),
            // NEW (Aug 11 2026): admin queue for bug reports filed by the
            // customer app's AI agent (guru_chat_screen's report_app_bug
            // tool → app_bug_reports).
            ListTile(
              leading: const Icon(Icons.bug_report_rounded, color: Color(0xFFFF5252)),
              title: const Text('Bug Reports', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Issues customers reported through the AI agent',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const BugReportsScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.bolt_rounded, color: Color(0xFFFFBB00)),
              title: const Text('Usage Fee Ledger', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Live feed of infra usage fees deducted from heroes',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const UsageFeeLedgerScreen()),
                );
              },
            ),
            // NEW (Aug 11 2026 — Test Data Cleanup System): the `orders`
            // collection (cart_screen.dart's catalog checkout) had no
            // admin screen at all before this. Minimal list + delete
            // screen so dev/test junk in there can be cleaned up too.
            ListTile(
              leading: const Icon(Icons.delete_sweep_rounded, color: Color(0xFFFF5252)),
              title: const Text('Orders Cleanup', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Remove test/dummy catalog orders',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminOrdersCleanupScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.cloud_done_rounded, color: Colors.blue),
              title: const Text('Cloudinary Dashboard', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Manage media, check usage, delete unused images',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminCloudinaryDashboardScreen()),
                );
              },
            ),
            // NEW (Aug 12 2026 — "Zero-Budget Escape Hatch" follow-up):
            // hardcoded-URL QR generator for poster/flex boards. See
            // admin_qr_generator_screen.dart's header for why the URL is
            // hardcoded rather than pulled from config.
            ListTile(
              leading: const Icon(Icons.qr_code_2_rounded, color: Color(0xFFFF4FA3)),
              title: const Text('Poster QR Generator', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Generate the official app QR for posters/flex',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminQrGeneratorScreen()),
                );
              },
            ),
            // NEW (Aug 12 2026 — "QR Monkey" affiliate system): trackable
            // referral QR codes for hero recruitment, customer growth
            // campaigns, and seller onboarding agents. See
            // admin_affiliate_qr_screen.dart / affiliate_service.dart.
            ListTile(
              leading: const Icon(Icons.share_rounded, color: Color(0xFFFF4FA3)),
              title: const Text('Affiliate QR Generator', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Trackable referral QR codes with live scan/signup stats',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminAffiliateQrScreen()),
                );
              },
            ),
            // NEW (Aug 12 2026 — Nizam: "yevlo peru link kulla vanthanga,
            // yevlo peru login pandranga... mobile number and mail id
            // list... pdf and excel export"): the WHO behind the QR
            // counters, with filters, funnel analytics and CSV export.
            // Uses incremental fetch (only rows newer than the local
            // cache) to keep Firestore reads down — see the screen's
            // header for the full reasoning.
            ListTile(
              leading: const Icon(Icons.insights_rounded, color: Color(0xFFFF4FA3)),
              title: const Text('QR Leads & Analytics', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Who joined via QR + contacts, filters & CSV export',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminAffiliateLeadsScreen()),
                );
              },
            ),
            // NEW (Aug 12 2026 — isolated, watermarked internal load-test
            // harness). See admin_map_simulation_screen.dart's header for
            // why this exists ONLY here, never in the customer/hero apps.
            ListTile(
              leading: const Icon(Icons.speed_rounded, color: Color(0xFFFF3B30)),
              title: const Text('Map Load-Test (Internal)', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Fake-vehicle stress test — admin-only, watermarked',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const AdminMapSimulationScreen()),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.update_rounded, color: _purple),
              title: const Text('Check for Updates', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              // FIX (per Nizam's bug report — "checking update kudutha
              // athu hero app or customer app ah open pannividuthu,
              // admin pwa update pannala"): this used to just
              // pushReplacement back to this same screen — not a real
              // update check at all, so the Admin PWA genuinely never
              // updated no matter how many times this was tapped. Now
              // calls the real WebVersionChecker + PWA-cache-clear-and-
              // reload mechanism (same one the Customer app's drawer
              // uses) — it reloads THIS tab's own URL (Uri.base), so it
              // can never accidentally jump to the Hero/Customer PWA.
              onTap: () {
                Navigator.pop(context);
                unawaited(_runAdminManualUpdateCheck(context));
              },
            ),
            // NEW (Sep 2026 — CTO review of PR #61): sits right next to
            // "Check for Updates" — the two are the same activity ("is
            // my build current, and can I get back to a working one").
            // Fetches the latest release on tap rather than requiring
            // this screen to keep one loaded at all times, matching how
            // ChittiDevMonitorScreen's own equivalent button already
            // works.
            ListTile(
              leading: const Icon(Icons.history_rounded, color: _purple),
              title: const Text('App Versions & Rollback',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: Text('Switch to an older build if the latest has a problem',
                  style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11)),
              onTap: () async {
                Navigator.pop(context);
                final messenger = ScaffoldMessenger.of(context);
                final snap = await ChittiDevMonitorService.fetch();
                final release = snap.latestRelease;
                if (release == null) {
                  messenger.showSnackBar(
                    const SnackBar(
                        content: Text('No published release found yet.')),
                  );
                  return;
                }
                if (!context.mounted) return;
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => AdminAppVersionsScreen(release: release),
                  ),
                );
              },
            ),
            StreamBuilder<DocumentSnapshot>(
              stream: FirebaseFirestore.instance.collection('system_settings').doc('app_status').trackedSnapshots(),
              builder: (context, snapshot) {
                final data = snapshot.data?.data() as Map<String, dynamic>?;
                final simMode = data?['simulation_mode'] as String? ?? 'off';
                
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Row(
                        children: [
                          Icon(Icons.airport_shuttle, color: Color(0xFFB21FFF), size: 20),
                          SizedBox(width: 12),
                          Text('Customer App Demo Vehicles', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text('Shows fake vehicles on CUSTOMER phones',
                          style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
                      const SizedBox(height: 12),
                      SegmentedButton<String>(
                        style: SegmentedButton.styleFrom(
                          backgroundColor: Colors.transparent,
                          selectedBackgroundColor: const Color(0xFFB21FFF).withValues(alpha: 0.2),
                          foregroundColor: _text,
                          selectedForegroundColor: const Color(0xFFB21FFF),
                          side: const BorderSide(color: Color(0xFF262636)),
                        ),
                        segments: const [
                          ButtonSegment(value: 'off', label: Text('Off', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: 'normal', label: Text('Normal', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: 'busy', label: Text('Busy', style: TextStyle(fontSize: 11))),
                          ButtonSegment(value: 'peak', label: Text('Peak', style: TextStyle(fontSize: 11))),
                        ],
                        selected: {simMode},
                        onSelectionChanged: (Set<String> newSelection) {
                          FirebaseFirestore.instance.collection('system_settings').doc('app_status').set(
                            {'simulation_mode': newSelection.first}, SetOptions(merge: true)
                          );
                        },
                      ),
                      const Divider(color: Color(0xFF262636), height: 32),
                    ],
                  ),
                );
              },
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Row(
                    children: [
                      Icon(Icons.layers_rounded, color: Color(0xFFB21FFF), size: 20),
                      SizedBox(width: 12),
                      Text('Map View Filters', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text('Local simulation controls for demo purposes',
                      style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11),),
                  const SizedBox(height: 12),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFF4CAF50).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.public_rounded, color: Color(0xFF4CAF50), size: 16),
                    ),
                    title: const Text('Live Map Simulation', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Default traffic mode', style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11)),
                    onTap: () {
                      MapSimulationService.instance.start(density: SimulationDensity.normal);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulation Started: Normal'), backgroundColor: Color(0xFF4CAF50)));
                    },
                  ),
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF9800).withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.two_wheeler_rounded, color: Color(0xFFFF9800), size: 16),
                    ),
                    title: const Text('4 Bikes & 3 Parcels', style: TextStyle(color: _text, fontSize: 13, fontWeight: FontWeight.w600)),
                    subtitle: Text('Custom filter mode', style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 11)),
                    onTap: () {
                      MapSimulationService.instance.start(density: SimulationDensity.custom4B3P);
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Simulation Started: Custom'), backgroundColor: Color(0xFFFF9800)));
                    },
                  ),
                  const Divider(color: Color(0xFF262636), height: 32),
                ],
              ),
            ),
            ListTile(
              leading: const Icon(Icons.logout_rounded, color: Color(0xFFFF5252)),
              title: const Text('Logout',
                  style: TextStyle(color: Color(0xFFFF5252), fontWeight: FontWeight.w600),),
              onTap: () {
                Navigator.pop(context);
                _logout(context);
              },
            ),
            const SizedBox(height: 20),
            // NEW (CTO mandate — Universal Side Tray Banner): same
            // "Download App" CTA as the Customer app's drawer, now
            // shared via widgets/download_app_banner.dart.
            const DownloadAppBanner(appVariant: 'admin'),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'v1.0.0',
                style: TextStyle(color: _text.withValues(alpha: 0.3), fontSize: 12, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── _ManageTile — single, consistent row-style tile for every entry
// in the Manage section. Replaces both the old grid-card _ServiceCard
// (Material icons, "LIVE/Coming Soon" badge) and the old
// _ServiceRequestButton (full-width row) with one widget, so every
// category reads the same way: icon, label, one-line description of
// what it does (this is the "clear label" fix for the 3 overlapping
// admin_review entry points — each tile's subtitle says exactly what
// it shows), and — when [requestType] is given — a live "waiting for
// a hero" count badge.
class _ManageTile extends StatelessWidget {
  final String label;
  final String subtitle;
  final String iconSvg;
  final Color color;
  final VoidCallback onTap;
  final String? requestType;

  const _ManageTile({
    required this.label,
    required this.subtitle,
    required this.iconSvg,
    required this.color,
    required this.onTap,
  }) : requestType = null;

  static const Color _text = Color(0xFFEEEEF5);
  static const Color _muted = Color(0xFF9999BB);

  @override
  Widget build(BuildContext context) {
    final content = Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withValues(alpha: 0.1),
            blurRadius: 8,
            spreadRadius: 1,
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            padding: const EdgeInsets.all(9),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: SvgPicture.string(iconSvg),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: const TextStyle(
                    color: _text,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(color: _muted, fontSize: 11),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (requestType != null) _WaitingBadge(requestType: requestType!),
          const SizedBox(width: 8),
          Icon(Icons.arrow_forward_ios_rounded,
              color: color.withValues(alpha: 0.6), size: 16,),
        ],
      ),
    );

    return GestureDetector(onTap: onTap, child: content);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(StringProperty('iconSvg', iconSvg));
    properties.add(ColorProperty('color', color));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
    properties.add(StringProperty('requestType', requestType));
  }
}

// NEW (UI reorg, Aug 31 2026): "SOS Verify" tile for the Services tab
// — same _ManageTile visual, but with its own badge source
// (sos_kyc_requests, not service_requests), so it can't reuse
// _AdminReviewBadgeWrapper (which reads a different field/collection).
class _SosKycTile extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> waitingStream;
  final VoidCallback onTap;
  const _SosKycTile({required this.waitingStream, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: waitingStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            _ManageTile(
              label: 'SOS Verify',
              subtitle: 'One-time customer SOS KYC verification',
              iconSvg: FluentEmojiFlat.police_car_light,
              color: const Color(0xFFFF1744),
              onTap: onTap,
            ),
            if (count > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(color: const Color(0xFF0A0A12), width: 2),
                  ),
                  constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

// NEW (UI reorg, Aug 31 2026): one combined nav-bar dot for the
// "Services" tab, replacing the old per-tab _NavWaitingDot/
// _SosKycWaitingDot dots that used to sit on 6 separate tabs. Lights
// up if EITHER stream has anything waiting, so admin still gets the
// "something needs a look" signal without those tabs being visible on
// the bottom bar any more.
class _ServicesAggregateWaitingDot extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> waitingStream;
  final Stream<QuerySnapshot<Map<String, dynamic>>> sosKycWaitingStream;
  const _ServicesAggregateWaitingDot({required this.waitingStream, required this.sosKycWaitingStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: waitingStream,
      builder: (context, waitingSnap) {
        final waitingCount = waitingSnap.data?.docs.length ?? 0;
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: sosKycWaitingStream,
          builder: (context, sosSnap) {
            final sosCount = sosSnap.data?.docs.length ?? 0;
            final total = waitingCount + sosCount;
            if (total == 0) return const SizedBox.shrink();
            return Container(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
              constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF1744),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: const Color(0xFF12121E), width: 1.5),
              ),
              child: Text(
                total > 9 ? '9+' : '$total',
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
              ),
            );
          },
        );
      },
    );
  }
}

// Live "waiting for a hero" count for one requestType — pending +
// admin_review (no hero has picked it up yet). Split out from
// _ManageTile so the taxi/settings tiles (no requestType) don't pay
// for a Firestore listener they don't need.
class _WaitingBadge extends StatelessWidget {
  final String requestType;
  const _WaitingBadge({required this.requestType});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .where('requestType', isEqualTo: requestType)
          .where('status', whereIn: ['pending', 'admin_review'])
          .trackedSnapshots(),
      builder: (context, snapshot) {
        final waitingCount = snapshot.data?.docs.length ?? 0;
        if (waitingCount == 0) return const SizedBox.shrink();
        return Container(
          margin: const EdgeInsets.only(left: 6),
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
          decoration: BoxDecoration(
            color: const Color(0xFFFF1744),
            borderRadius: BorderRadius.circular(999),
          ),
          child: Text(
            waitingCount > 9 ? '9+ waiting' : '$waitingCount waiting',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 11,
              fontWeight: FontWeight.w800,
            ),
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestType', requestType));
  }
}

// ── Admin-visibility gap fix: live count badge for escalated Hero
// Booking (and other service_requests category) tasks awaiting admin
// action. Placed on the Bike Taxi card since that's the first thing
// an admin sees on this landing screen and the only path down to
// AdminNewOrdersScreen — a bare "New Orders" tab 2 taps deep had no
// visibility from here otherwise. Inline (uncached) StreamBuilder
// matches this file's existing convention for _buildSosCallCenterBanner
// above, which also creates its stream inline in a StatelessWidget.
class _AdminReviewBadgeWrapper extends StatelessWidget {
  final Widget child;
  final Stream<QuerySnapshot<Map<String, dynamic>>> waitingStream;
  const _AdminReviewBadgeWrapper({required this.child, required this.waitingStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: waitingStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs
                .where((d) => d.data()['status'] == 'admin_review')
                .length ??
            0;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            child,
            if (count > 0)
              Positioned(
                top: -6,
                right: -6,
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF1744),
                    borderRadius: BorderRadius.circular(999),
                    border: Border.all(
                        color: const Color(0xFF0A0A12), width: 2,),
                  ),
                  constraints:
                      const BoxConstraints(minWidth: 22, minHeight: 22),
                  child: Text(
                    count > 9 ? '9+' : '$count',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Stream<QuerySnapshot<Map<String, dynamic>>>>('waitingStream', waitingStream));
  }
}

// ================================================================
// ADMIN "CHECK FOR UPDATE" — real implementation
// ================================================================
// FIX (per Nizam's bug report): Admin's ListTile used to just
// pushReplacement back to itself — never actually checked anything, so
// the Admin PWA could never update this way. Mirrors
// dashboard_screen.dart's _runManualUpdateCheck exactly: fetch
// /version.json (WebVersionChecker — deploy-agnostic, no appVariant
// awareness needed), and if it differs from what this tab loaded with,
// clear the PWA cache and reload THIS tab's own URL (Uri.base) — never
// a hardcoded URL, so it can never jump to a different app's PWA.
// Native (non-web) builds: WebVersionChecker.checkNow() is a no-op
// (kIsWeb guard inside it), so this just reports "already latest".
Future<void> _runAdminManualUpdateCheck(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);

  showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      backgroundColor: Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF6C63FF)),
          ),
          SizedBox(width: 18),
          Flexible(
            child: Text('Checking for updates…', style: TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    ),
  );

  await WebVersionChecker.instance.checkNow();
  if (!context.mounted) return;
  await Future<void>.delayed(const Duration(milliseconds: 900));
  if (!context.mounted) return;

  if (!WebVersionChecker.instance.isUpdateAvailable) {
    navigator.pop();
    ScaffoldMessenger.of(navigator.context).showSnackBar(
      const SnackBar(
        content: Text('You already have the latest version.'),
        duration: Duration(seconds: 2),
      ),
    );
    return;
  }

  navigator.pop();
  showDialog<void>(
    context: navigator.context,
    barrierDismissible: false,
    builder: (_) => const AlertDialog(
      backgroundColor: Color(0xFF1A1A26),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(20))),
      content: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(strokeWidth: 2.4, color: Color(0xFF6C63FF)),
          ),
          SizedBox(width: 18),
          Flexible(
            child: Text('Updating…', style: TextStyle(color: Colors.white, fontSize: 14)),
          ),
        ],
      ),
    ),
  );

  await Future<void>.delayed(const Duration(milliseconds: 600));
  if (!context.mounted) return;

  try {
    await PwaCachePlatform().clearAndReload();
  } catch (e) {
    debugPrint('[AdminManualUpdate] cache clear failed, reloading anyway: $e');
    final uri = Uri.parse(Uri.base.toString());
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }
}
