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

import '../../services/db_usage_tracker.dart';
import '../../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../../services/pwa_cache_platform_web.dart';
import '../../services/service_requests_listener.dart';
import '../../services/web_version_checker.dart';
import '../../widgets/download_app_banner.dart';
import 'admin_ai_settings_screen.dart';
import 'admin_dashboard_screen.dart';
import 'admin_food_orders_screen.dart';
import 'admin_service_requests_screen.dart';
import 'admin_sos_kyc_approvals_screen.dart';
import 'admin_ux_audit_screen.dart';
import 'commission_settings_screen.dart';
import 'customer_usage_tracking_screen.dart';
import 'erode_offers_management_screen.dart';

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
        .snapshots();
    _alertSub = _waitingRequestsStream.listen(_onWaitingRequestsChanged,
        onError: (Object e) {
      debugPrint('[SuperAdminHome] Alert listener error: $e');
    },);
    _sosAlertsStream = FirebaseFirestore.instance
        .collection('sos_alerts')
        .where('status', isEqualTo: 'active')
        .snapshots();

    // DB usage monitor — side-channel count, shares the same
    // broadcast stream StreamBuilder already listens to, no extra reads.
    _waitingRequestsStream.listen((s) => DbUsageTracker.instance.recordRead(s.docs.length));
    _sosAlertsStream.listen((s) => DbUsageTracker.instance.recordRead(s.docs.length));
  }

  @override
  void dispose() {
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
  }

  // FIX (per Nizam's request): App Settings / Check for Updates / Logout
  // used to sit directly on the main Overview page, making it feel
  // cluttered. Moved into a left-side drawer (tray) instead — opened via
  // the hamburger icon in _buildHeader() — so the main page only shows
  // what admin needs to glance at daily (Manage tiles), with settings
  // tucked away one tap deeper, same drawer pattern any admin panel uses.
  final _scaffoldKey = GlobalKey<ScaffoldState>();

  // FIX (back-button audit, per Nizam's request): this screen — the
  // admin app's root home — had zero back-press handling, exactly the
  // same gap found in the Hero app's dashboard shell. Pressing back
  // (hardware button or the browser back button on the PWA) hit
  // Navigator.canPop()==false at the root and fell straight through to
  // the OS/browser default action, closing the app instantly instead of
  // stepping back tab-by-tab like dashboard_screen.dart (customer app)
  // already does. Same pattern applied here for consistency.
  Future<bool> _handleBackPress() async {
    if (_tabIndex != 0) {
      _goToTab(0);
      return false;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _bg,
        title: const Text('Leave the app?',
            style: TextStyle(fontWeight: FontWeight.w700),),
        content: const Text('Close Allin1 Admin?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return exit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _handleBackPress();
        if (shouldExit && context.mounted) SystemNavigator.pop();
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
            if (_visitedTabs.contains(1)) const AdminServiceRequestsScreen(
                    key: ValueKey('hero_tab'),
                    requestType: 'hero_booking',
                    title: 'Hero Booking Status',
                  ) else const SizedBox.shrink(),
            if (_visitedTabs.contains(2)) const AdminServiceRequestsScreen(
                    key: ValueKey('electronics_tab'),
                    requestType: 'electronics_service',
                    title: 'Electronics Booking',
                  ) else const SizedBox.shrink(),
            // NEW (per Nizam's request): 4th tab — one-time customer SOS
            // KYC verification queue. Same lazy-mount pattern as Hero/
            // Electronics above (only mounts, and only starts its
            // listener, once the admin actually taps this tab).
            if (_visitedTabs.contains(3)) const AdminSosKycApprovalsScreen(key: ValueKey('cus_sos_tab')) else const SizedBox.shrink(),
            // NEW (per Nizam's request): 5th tab — Food Orders. Same
            // lazy-mount pattern as every other tab here (only builds,
            // and only fires its first manual fetch, once the admin
            // actually taps this tab).
            if (_visitedTabs.contains(4)) const AdminFoodOrdersScreen(key: ValueKey('food_orders_tab')) else const SizedBox.shrink(),
            // FIX (pipeline audit, per Nizam's request): custom_order and
            // grocery_order service_requests had NO live admin tab at
            // all -- unlike hero_booking/electronics_service above, a
            // normal accepted/in-progress/completed request of these two
            // types was invisible to admin oversight; it only ever
            // surfaced via admin_new_orders_screen.dart's escalation
            // queue (timed-out or manually-assigned requests only). Same
            // lazy-mount pattern, same reused AdminServiceRequestsScreen
            // widget as the Hero/Electronics tabs -- no new plumbing.
            if (_visitedTabs.contains(5)) const AdminServiceRequestsScreen(
                    key: ValueKey('custom_order_tab'),
                    requestType: 'custom_order',
                    title: 'Custom Orders',
                  ) else const SizedBox.shrink(),
            if (_visitedTabs.contains(6)) const AdminServiceRequestsScreen(
                    key: ValueKey('grocery_order_tab'),
                    requestType: 'grocery_order',
                    title: 'Grocery Orders',
                  ) else const SizedBox.shrink(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
      ),
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
    // FIX (pipeline audit): added `materialIcon` so the two new tabs
    // below don't have to fake an SvgPicture.string('') (which would
    // render nothing/error) just to reuse this record shape. Existing
    // items are untouched functionally -- materialIcon: null on all of
    // them just means "fall through to the old isSos/isFoodOrders/svg
    // chain", exactly as before.
    final List<({String icon, String label, String? requestType, bool isSos, bool isFoodOrders, IconData? materialIcon})> items = [
      (icon: FluentEmojiFlat.bar_chart, label: 'Overview', requestType: null, isSos: false, isFoodOrders: false, materialIcon: null),
      (
        icon: FluentEmojiFlat.man_superhero,
        label: 'Hero',
        requestType: 'hero_booking',
        isSos: false,
        isFoodOrders: false,
        materialIcon: null,
      ),
      (
        icon: FluentEmojiFlat.mobile_phone,
        label: 'Electronics',
        requestType: 'electronics_service',
        isSos: false,
        isFoodOrders: false,
        materialIcon: null,
      ),
      // NEW (per Nizam's request): 4th tab for one-time customer SOS
      // KYC verification. Separate badge source (sos_kyc_requests, not
      // service_requests) — see isSos branch below. Uses a plain
      // Material icon (not FluentEmojiFlat) below since this is the
      // only tab whose icon isn't a pre-existing, already-confirmed-
      // valid FluentEmojiFlat SVG string constant.
      (
        icon: '',
        label: 'SOS Verify',
        requestType: null,
        isSos: true,
        isFoodOrders: false,
        materialIcon: null,
      ),
      // NEW (per Nizam's request): 5th tab — Food Orders management.
      // Deliberately requestType: null (no live "new booking" badge
      // stream attached) — AdminFoodOrdersScreen itself is a manual
      // "tap refresh" report, not a live listener, per the explicit
      // "auto listener oodama reload button vacharlam" instruction, so
      // this tab shouldn't imply live push notifications either.
      (
        icon: '',
        label: 'Food Orders',
        requestType: null,
        isSos: false,
        isFoodOrders: true,
        materialIcon: null,
      ),
      // NEW (pipeline audit fix): 6th/7th tabs -- custom_order and
      // grocery_order previously had no live badge/oversight anywhere in
      // admin. requestType set (not null) so the same _NavWaitingDot
      // badge stream used by Hero/Electronics above applies here too.
      (
        icon: '',
        label: 'Custom',
        requestType: 'custom_order',
        isSos: false,
        isFoodOrders: false,
        materialIcon: Icons.shopping_bag_rounded,
      ),
      (
        icon: '',
        label: 'Grocery',
        requestType: 'grocery_order',
        isSos: false,
        isFoodOrders: false,
        materialIcon: Icons.local_grocery_store_rounded,
      ),
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
                                : item.isSos
                                    ? Icon(Icons.sos_rounded,
                                        color: active ? _gold : _text.withValues(alpha: 0.55), size: 22,)
                                    : item.isFoodOrders
                                        ? Icon(Icons.restaurant_menu_rounded,
                                            color: active ? _gold : _text.withValues(alpha: 0.55), size: 22,)
                                        : SvgPicture.string(item.icon),
                          ),
                        ),
                        if (item.requestType != null)
                          Positioned(
                            top: -4,
                            right: -8,
                            child: _NavWaitingDot(
                                requestType: item.requestType!,
                                waitingStream: _waitingRequestsStream,),
                          ),
                        if (item.isSos)
                          Positioned(
                            top: -4,
                            right: -8,
                            child: _SosKycWaitingDot(
                                waitingStream: _sosKycWaitingStream,),
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
          // point right on the Overview page, on top of the existing
          // Grocery bottom-nav tab (index 6) — this is the tab admins
          // need most now that the DMart-screenshot workflow depends on
          // them reviewing uploaded cart photos quickly, so it shouldn't
          // require hunting through the bottom bar. Jumps to the SAME
          // already-mounted AdminServiceRequestsScreen tab via _goToTab
          // rather than pushing a second copy of it. Uses the confirmed-
          // safe FluentEmojiFlat.shopping_cart constant (already in use
          // elsewhere in this codebase, see dashboard_screen.dart) since
          // _ManageTile only renders an SVG string icon.
          _AdminReviewBadgeWrapper(
            waitingStream: _waitingRequestsStream,
            child: _ManageTile(
              label: 'Grocery Orders',
              subtitle: 'Review DMart cart screenshots, assign heroes',
              iconSvg: FluentEmojiFlat.shopping_cart,
              color: _orange,
              onTap: () => _goToTab(6),
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
    return Drawer(
      backgroundColor: _surface,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Padding(
              padding: EdgeInsets.fromLTRB(20, 20, 20, 12),
              child: Text(
                'Settings',
                style: TextStyle(
                  color: _text,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Divider(color: _purple.withValues(alpha: 0.15), height: 1),
            const SizedBox(height: 8),
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
            const Spacer(),
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

// Small red dot for the bottom-nav Hero/Electronics tabs — same
// waiting-count query as _WaitingBadge, but rendered as a compact dot
// (no room for "N waiting" text at nav-bar icon size).
class _NavWaitingDot extends StatelessWidget {
  final String requestType;
  final Stream<QuerySnapshot<Map<String, dynamic>>> waitingStream;
  const _NavWaitingDot({required this.requestType, required this.waitingStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: waitingStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs
                .where((d) => d.data()['requestType'] == requestType)
                .length ??
            0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFF1744),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF12121E), width: 1.5),
          ),
          child: Text(
            count > 9 ? '9+' : '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(
                color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800,),
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestType', requestType));
    properties.add(DiagnosticsProperty<Stream<QuerySnapshot<Map<String, dynamic>>>>('waitingStream', waitingStream));
  }
}

// Live pending-count dot for the Cus SOS tab — separate collection
// (sos_kyc_requests) from the service_requests-based badges above.
// Stream is sourced from the parent's cached _sosKycWaitingStream field
// (created once in initState()), same pattern as _NavWaitingDot /
// _AdminReviewBadgeWrapper, so this widget no longer opens its own
// listener on every parent rebuild.
class _SosKycWaitingDot extends StatelessWidget {
  final Stream<QuerySnapshot<Map<String, dynamic>>> waitingStream;

  const _SosKycWaitingDot({required this.waitingStream});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: waitingStream,
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        if (count == 0) return const SizedBox.shrink();
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
          constraints: const BoxConstraints(minWidth: 14, minHeight: 14),
          decoration: BoxDecoration(
            color: const Color(0xFFFF1744),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: const Color(0xFF12121E), width: 1.5),
          ),
          child: Text(
            count > 9 ? '9+' : '$count',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
          ),
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
          .snapshots(),
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
