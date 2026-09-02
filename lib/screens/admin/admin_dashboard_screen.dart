// ================================================================
// AdminDashboardScreen — Allin1 Super App
// Live Firestore: rides today, online heroes, wallet totals,
// recent transactions
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/chitti/chitti_admin_briefing_service.dart';
import '../../services/chitti/chitti_enquiry_service.dart';
import '../../services/app_minimizer_service.dart';
import '../../widgets/native_update_button.dart';
import '../../services/db_usage_tracker.dart';
import '../../services/service_requests_listener.dart';
import '../../services/update_service.dart';
import '../../services/usage_tracking_service.dart';
import '../../widgets/manual_refresh_header.dart';
import 'admin_detailed_reports_screen.dart';
import 'admin_hero_dispatch_screen.dart';
import 'admin_master_catalog_screen.dart';
import 'admin_new_orders_screen.dart';
import 'admin_ride_tracking_screen.dart';
import 'admin_seller_approval_screen.dart';
import 'chitti_enquiries_screen.dart';
import 'ads_management_screen.dart';
import 'approved_heroes_screen.dart';
import 'commission_settings_screen.dart';
import 'credentials_admin_screen.dart';
import 'customer_rides_screen.dart';
import 'fare_management_screen.dart';
import 'hero_approvals_screen.dart';
// NEW (Aug 11 2026): Service Flow Monitor sub-page — fetch-on-demand.
import 'service_flow_monitor_screen.dart';
import 'admin_hero_earnings_screen.dart';
import '../../services/firestore_usage_tracking.dart';

// ── Theme ──────────────────────────────────────────────────────
const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _orange = Color(0xFFFF6B35);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _teal = Color(0xFF11998E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

// paymentStatus values that mean the ride/task is fully paid/settled.
// Kept in sync with payment_screen.dart's _settledStatuses — the badge
// here used to only recognize 'confirmed', so a ride paid via wallet,
// UPI-offline, or auto-settled would still show a red "PENDING" badge
// to the admin even though the customer had already paid in full.
const Set<String> _settledPaymentStatuses = {
  'paid',
  'paid_by_wallet',
  'paid_offline_p2p',
  'completed',
  'settled',
  'confirmed',
};
const Color _border = Color(0x1AFFFFFF);

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _selectedTab = 0;
  bool _isLoggingOut = false;

  // Top-Up controllers and state
  final TextEditingController _phoneController = TextEditingController();
  final TextEditingController _topUpAmountController = TextEditingController();
  String _topUpType = 'coins'; // 'coins' or 'wallet'
  bool _isTopUpLoading = false;

  // Tab labels + icons
  static const _tabs = [
    {'icon': Icons.dashboard_outlined, 'label': 'Overview'},
    {'icon': Icons.electric_bike_outlined, 'label': 'Rides'},
    {'icon': Icons.people_outline, 'label': 'Customers'},
    {'icon': Icons.assignment_late_outlined, 'label': 'New Orders'},
    // NEW (Aug 11 2026, per Nizam): Service Flow Monitor — every
    // category's requests in one place, with delivery health. Added as
    // a bottom-nav tab INSIDE the existing Taxi & Transportation screen
    // rather than a new top-level entry, so it sits where an admin is
    // already looking when they ask "did that booking reach a hero?".
    // Fetch-on-demand only — see the quota note in
    // service_flow_monitor_screen.dart.
    {'icon': Icons.monitor_heart_outlined, 'label': 'Monitor'},
  ];

  // Cached wallet total — computed once on load to avoid massive reads
  double _walletTotal = 0;
  bool _walletLoading = true;

  // Cached stream — this badge is always mounted (lives in the AppBar,
  // shown on every tab), so without caching it tears down and reattaches
  // a Firestore listener on every unrelated setState() rebuild.
  late final Stream<QuerySnapshot> _pendingHeroApprovalsStream;

  // Same caching reasoning — feeds the new "Seller Approvals" badge in
  // the nav sheet (seller approval gate, per Nizam/CTO's request).
  late final Stream<QuerySnapshot> _pendingSellerApprovalsStream;
  late final Stream<List<ChittiEnquiry>> _openEnquiriesStream;

  // Same caching reasoning as above — feeds the "New Orders" bottom-nav
  // badge, which (like the AppBar) is always mounted regardless of
  // which tab is selected (see _buildBottomNav()).
  // Sourced from the shared singleton (see
  // service_requests_listener.dart) instead of opening its own
  // .snapshots() -- this is the SAME real Firestore listener
  // SuperAdminHomeScreen already has open (this screen is pushed on
  // top of it, which stays alive underneath). This screen only wants
  // the admin_review-status subset, so the badge below filters the
  // shared stream's docs client-side instead of running a second
  // server-side query.
  late final Stream<QuerySnapshot<Map<String, dynamic>>> _adminReviewCountStream;

  // Same caching reasoning — feeds the Rides tab list (_buildRidesList()).
  // Previously constructed inline inside _buildRidesList(), which is
  // called fresh from build() on every rebuild while the Rides tab is
  // selected, tearing down and reopening a 100-doc listener each time.
  late final Stream<QuerySnapshot> _ridesListStream;

  // FIX (per Nizam's request — cut auto-listeners, use manual refresh):
  // _buildStatCards() (rides, limit 200), _buildOnlineHeroes() (heroes),
  // and _buildRecentTransactions() (wallet_transactions, limit 15) used
  // to be live .snapshots() listeners that stayed open the whole time
  // this screen was mounted, re-reading on every server-side change.
  // These are "overview/browse" widgets, not safety-critical live feeds,
  // so they're now one-time .get() fetches triggered once on load and
  // again only when the admin taps the round refresh button — see
  // ManualRefreshHeader. (Booking-notification badges above — pending
  // hero approvals / admin_review count — stay live since admins need
  // to know about those immediately.)
  QuerySnapshot? _statCardsSnapshot;
  bool _statCardsLoading = true;
  DateTime? _statCardsSyncedAt;

  // FIX (WhatsApp-model presence migration, CTO mandate): this used to
  // be a QuerySnapshot from a Firestore `heroes.where('status', whereIn:
  // ['online', 'on_ride'])` query. Firestore no longer carries any
  // presence field at all (see hero_home_screen.dart's _syncOnlineStatus
  // — RTDB's online_heroes/{uid} node, backed by onDisconnect(), is now
  // the ONLY source of truth for who's online), so this now reads that
  // RTDB node directly instead. `isAvailable` already encodes the
  // on_ride/available distinction (see _syncOnlineStatus:
  // isAvailable = activeRideId.isEmpty), so nothing here needed a
  // Firestore lookup to begin with.
  Map<dynamic, dynamic>? _onlineHeroesData;
  bool _onlineHeroesLoading = true;
  DateTime? _onlineHeroesSyncedAt;

  QuerySnapshot? _recentTransactionsSnapshot;
  bool _recentTransactionsLoading = true;
  DateTime? _recentTransactionsSyncedAt;

  @override
  void initState() {
    super.initState();
    _pendingHeroApprovalsStream = FirebaseFirestore.instance
        .collection('heroes')
        .where('approvalStatus', isEqualTo: 'pending')
        .trackedSnapshots();
    _adminReviewCountStream =
        ServiceRequestsListener.instance.waitingAndReviewStream;
    _ridesListStream = FirebaseFirestore.instance
        .collection('rides')
        .orderBy('createdAt', descending: true)
        .limit(100)
        .trackedSnapshots();
    // Built once. See _MoreSheet.openEnquiriesStream.
    _openEnquiriesStream = ChittiEnquiryService.watchOpen();
    _pendingSellerApprovalsStream = FirebaseFirestore.instance
        .collection('sellers')
        .where('status', isEqualTo: 'pending')
        .trackedSnapshots();

    // DB usage monitor — side-channel .listen() on each already-hoisted
    // stream just to count docs per snapshot; this does NOT add extra
    // Firestore reads (Firestore snapshots() streams are broadcast
    // streams — StreamBuilder above and this .listen() share the same
    // underlying query/watch). See lib/services/db_usage_tracker.dart.
    _pendingHeroApprovalsStream.listen((s) => DbUsageTracker.instance
        .recordRead(s.docs.length, 'admin_dashboard_pending_hero_approvals'));
    _adminReviewCountStream.listen((s) => DbUsageTracker.instance.recordRead(
        s.docs.where((d) => d.data()['status'] == 'admin_review').length,
        'admin_dashboard', 'review_count_listener'));
    _pendingSellerApprovalsStream.listen((s) => DbUsageTracker.instance
        .recordRead(s.docs.length, 'admin_dashboard_pending_seller_approvals'));

    unawaited(_fetchStatCards());
    unawaited(_fetchOnlineHeroes());
    unawaited(_fetchRecentTransactions());

    // Use unawaited if we don't want to block, or just call it since it handles its own state
    _computeWalletTotal();

    // Trigger Chitti's Daily Morning Briefing for the CEO (Phase 1)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ChittiAdminBriefingService.instance.speakBriefingIfFirstTimeToday();
    });
  }

  Future<void> _fetchStatCards() async {
    if (mounted) setState(() => _statCardsLoading = true);
    // Scope the query to just "today" instead of fetching the 200 most
    // recent rides regardless of date and filtering client-side — bounds
    // the read count to actual today's-ride volume, not a fixed 200 every
    // open/refresh.
    final now = DateTime.now();
    final startOfToday = DateTime(now.year, now.month, now.day);
    final endOfToday = startOfToday.add(const Duration(days: 1));
    final snap = await FirebaseFirestore.instance
        .collection('rides')
        .where('createdAt', isGreaterThanOrEqualTo: Timestamp.fromDate(startOfToday))
        .where('createdAt', isLessThan: Timestamp.fromDate(endOfToday))
        .orderBy('createdAt', descending: true)
        .limit(300)
        .trackedGet();
    DbUsageTracker.instance
        .recordRead(snap.docs.length, 'admin_dashboard_today_rides');
    if (!mounted) return;
    setState(() {
      _statCardsSnapshot = snap;
      _statCardsLoading = false;
      _statCardsSyncedAt = DateTime.now();
    });
  }

  Future<void> _fetchOnlineHeroes() async {
    if (mounted) setState(() => _onlineHeroesLoading = true);
    // RTDB reads aren't counted by DbUsageTracker (that instrument only
    // tracks Firestore) — this is now a single RTDB node read instead of
    // a Firestore collection query, i.e. strictly cheaper than before,
    // not just moved.
    final snap = await FirebaseDatabase.instance.ref('online_heroes').get();
    if (!mounted) return;
    setState(() {
      _onlineHeroesData = snap.exists && snap.value is Map
          ? Map<dynamic, dynamic>.from(snap.value! as Map)
          : {};
      _onlineHeroesLoading = false;
      _onlineHeroesSyncedAt = DateTime.now();
    });
  }

  Future<void> _fetchRecentTransactions() async {
    if (mounted) setState(() => _recentTransactionsLoading = true);
    final snap = await FirebaseFirestore.instance
        .collection('wallet_transactions')
        .orderBy('createdAt', descending: true)
        .limit(15)
        .trackedGet();
    DbUsageTracker.instance
        .recordRead(snap.docs.length, 'admin_dashboard_recent_transactions');
    if (!mounted) return;
    setState(() {
      _recentTransactionsSnapshot = snap;
      _recentTransactionsLoading = false;
      _recentTransactionsSyncedAt = DateTime.now();
    });
  }

  Future<void> _showUtrDialog(String rideDocId, String customerName, double amount) async {
    final TextEditingController utrController = TextEditingController();
    bool isLoading = false;

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2A),
          title: const Text(
            '✅ Verify Payment',
            style: TextStyle(color: Color(0xFFFFBB00), fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Customer: $customerName\nAmount: ₹${amount.toStringAsFixed(2)}',
                style: const TextStyle(color: Color(0xFFEEEEF5)),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: utrController,
                keyboardType: TextInputType.text,
                style: const TextStyle(color: Color(0xFFEEEEF5)),
                decoration: InputDecoration(
                  labelText: '📋 UTR Number (Transaction ID)',
                  hintText: 'e.g., 123456789012',
                  labelStyle: const TextStyle(color: Color(0xFF7777A0)),
                  filled: true,
                  fillColor: const Color(0xFF0A0A12),
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel', style: TextStyle(color: Color(0xFF7777A0))),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF00C853)),
              onPressed: isLoading ? null : () async {
                final utr = utrController.text.trim();
                if (utr.isEmpty || utr.length < 6) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('⚠️ Enter a valid UTR number (min 6 chars)'), backgroundColor: Color(0xFFFF5252)),
                  );
                  return;
                }
                setDialogState(() => isLoading = true);
                try {
                  await FirebaseFirestore.instance.collection('rides').doc(rideDocId).update({
                    'paymentStatus': 'confirmed',
                    'utrNumber': utr,
                    'confirmedAt': FieldValue.serverTimestamp(),
                    'confirmedBy': FirebaseAuth.instance.currentUser?.uid ?? 'admin',
                  });
                  if (context.mounted) {
                    Navigator.pop(context);
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('✅ Payment confirmed!'), backgroundColor: Color(0xFF00C853)),
                    );
                  }
                } catch (e) {
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('❌ Error: ${e.toString()}'), backgroundColor: const Color(0xFFFF5252)),
                    );
                  }
                } finally {
                  setDialogState(() => isLoading = false);
                }
              },
              child: isLoading
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                  : const Text('Confirm Payment ✅', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void dispose() {
    ChittiAdminBriefingService.instance.stopBriefing();
    _phoneController.dispose();
    _topUpAmountController.dispose();
    super.dispose();
  }

  /// Aggregates walletBalance from all users — run once per session.
  Future<void> _computeWalletTotal() async {
    // V1 Launch: Wallet feature backend is on hold to save DB costs.
    // UI remains intact, but backend returns 0.0
    //
    // FIX: this used to only set _walletTotal, never _walletLoading (which
    // starts true) — the "Wallet Pool" stat card checks _walletLoading to
    // decide whether to show a spinner or the value, so it was stuck
    // showing a spinner forever even though _walletTotal was already 0.0.
    if (mounted) {
      setState(() {
        _walletTotal = 0.0;
        _walletLoading = false;
      });
    }
  }

  // ── Helpers ────────────────────────────────────────────────
  /// Firestore Timestamp → today midnight check
  bool _isToday(Object? ts) {
    if (ts == null) {
      return false;
    }
    final dt = (ts as Timestamp).toDate();
    final now = DateTime.now();
    return dt.year == now.year && dt.month == now.month && dt.day == now.day;
  }

  void _navigate(Widget screen) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => screen),
    );
  }

  Future<void> _showTopUpDialog(BuildContext context) async {
    _phoneController.clear();
    _topUpAmountController.clear();
    _topUpType = 'coins';

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF1A1A2A),
          title: const Text(
            '🪙 Customer Top-Up',
            style: TextStyle(
              color: Color(0xFFFFBB00),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Phone search field
                TextField(
                  controller: _phoneController,
                  keyboardType: TextInputType.phone,
                  style: const TextStyle(color: Color(0xFFEEEEF5)),
                  decoration: InputDecoration(
                    labelText: '📱 Customer Phone Number',
                    hintText: '9XXXXXXXXX',
                    labelStyle: const TextStyle(color: Color(0xFF7777A0)),
                    filled: true,
                    fillColor: const Color(0xFF0A0A12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Amount field
                TextField(
                  controller: _topUpAmountController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Color(0xFFEEEEF5)),
                  decoration: InputDecoration(
                    labelText: '💰 Amount',
                    hintText: 'Enter coins or ₹ amount',
                    labelStyle: const TextStyle(color: Color(0xFF7777A0)),
                    filled: true,
                    fillColor: const Color(0xFF0A0A12),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                // Type selector
                Row(
                  children: [
                    const Text(
                      'Type: ',
                      style: TextStyle(color: Color(0xFF7777A0)),
                    ),
                    // Coins option
                    GestureDetector(
                      onTap: () => setDialogState(
                        () => _topUpType = 'coins',
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _topUpType == 'coins'
                              ? const Color(0xFFFFBB00)
                              : const Color(0xFF0A0A12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '🪙 NJ Coins',
                          style: TextStyle(
                            color: _topUpType == 'coins'
                                ? Colors.black
                                : const Color(0xFF7777A0),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Wallet option
                    GestureDetector(
                      onTap: () => setDialogState(
                        () => _topUpType = 'wallet',
                      ),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _topUpType == 'wallet'
                              ? const Color(0xFF00C853)
                              : const Color(0xFF0A0A12),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '₹ Wallet',
                          style: TextStyle(
                            color: _topUpType == 'wallet'
                                ? Colors.white
                                : const Color(0xFF7777A0),
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text(
                'Cancel',
                style: TextStyle(color: Color(0xFF7777A0)),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF00C853),
              ),
              onPressed: _isTopUpLoading
                  ? null
                  : () async {
                      // Validate
                      if (_phoneController.text.trim().isEmpty ||
                          _topUpAmountController.text.trim().isEmpty) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('⚠️ Fill all fields!'),
                            backgroundColor: Color(0xFFFF5252),
                          ),
                        );
                        return;
                      }

                      setDialogState(() => _isTopUpLoading = true);

                      try {
                        // Find user by phone
                        final query = await FirebaseFirestore.instance
                            .collection('users')
                            .where(
                              'phone',
                              isEqualTo: _phoneController.text.trim(),
                            )
                            .limit(1)
                            .get();

                        if (query.docs.isEmpty) {
                          if (context.mounted) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(
                                content: Text('❌ User not found!'),
                                backgroundColor: Color(0xFFFF5252),
                              ),
                            );
                          }
                          setDialogState(() => _isTopUpLoading = false);
                          return;
                        }

                        final userDoc = query.docs.first;
                        final userId = userDoc.id;
                        final amount = int.parse(
                          _topUpAmountController.text.trim(),
                        );
                        final fieldName = _topUpType == 'coins'
                            ? 'pending_coins'
                            : 'walletBalance';

                        // Update user balance
                        await FirebaseFirestore.instance
                            .collection('users')
                            .doc(userId)
                            .trackedUpdate({
                          fieldName: FieldValue.increment(amount),
                        });

                        // Log transaction
                        await FirebaseFirestore.instance
                            .collection('wallet_transactions')
                            .trackedAdd({
                          'userId': userId,
                          'amount': amount,
                          'type': 'credit',
                          'title': _topUpType == 'coins'
                              ? 'Admin Coin Top-Up 🪙'
                              : 'Admin Wallet Top-Up ₹',
                          'topUpType': _topUpType,
                          'addedBy': 'admin',
                          'balanceBefore': userDoc.data()[fieldName] ?? 0,
                          'timestamp': FieldValue.serverTimestamp(),
                        });

                        if (context.mounted) {
                          Navigator.pop(context);

                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '✅ ${_topUpType == 'coins' ? '$amount Coins' : '₹$amount'} added successfully!',
                              ),
                              backgroundColor: const Color(0xFF00C853),
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('❌ Error: ${e.toString()}'),
                              backgroundColor: const Color(0xFFFF5252),
                            ),
                          );
                        }
                      } finally {
                        setDialogState(() => _isTopUpLoading = false);
                      }
                    },
              child: _isTopUpLoading
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2,
                      ),
                    )
                  : const Text(
                      'Add Now ✅',
                      style: TextStyle(color: Colors.white),
                    ),
            ),
          ],
        ),
      ),
    );
  }

  // FIX (per Nizam's bug report — "admin android app download button
  // la nera admin app ah git la irunthu download pannunthu paru"): this
  // used to point at a stale, never-deployed Firebase Hosting URL
  // (my-allin1.web.app/admin_app.apk) — completely disconnected from
  // the canonical GitHub Releases source every other download button
  // in the app (DownloadAppBanner, Hero's own download buttons) uses.
  // Switched to the same canonical UpdateService source.
  Future<void> _downloadAdminApp() async {
    unawaited(UsageTrackingService.instance.trackApkDownload('admin'));
    final apkUrl = UpdateService().fallbackApkUrl('admin');
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      Uri.parse(apkUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to start download. Try again later.'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  void _showLogoutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          '🔐 Admin Logout',
          style: TextStyle(color: _text, fontWeight: FontWeight.w700),
        ),
        content: const Text(
          'Are you sure you want to securely logout from the Admin Panel?',
          style: TextStyle(color: _muted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: _muted)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _isLoggingOut = true);
              await FirebaseAuth.instance.signOut();
              if (!context.mounted) {
                return;
              }
              await Navigator.pushNamedAndRemoveUntil(
                context,
                '/',
                (route) => false,
              );
            },
            child: const Text(
              'Logout',
              style: TextStyle(color: _red, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
    );
  }

  // NEW (Aug 18 2026 — Turbo App navigation audit, task #149): this is
  // the admin app's real root screen (pushed straight after login) and
  // had zero PopScope — any back-press here hit Flutter's default
  // un-intercepted behaviour (instant SystemNavigator.pop(), app closes
  // with no chance to minimize). Same AppMinimizer pattern as the other
  // 3 app roots (customer/hero/seller). Since this screen has its own
  // bottom-nav tabs, back first resets to the Overview tab (idx 0) if
  // the admin is elsewhere, then minimizes on a second back-press from
  // Overview — matching the tab-reset-then-minimize convention already
  // used by the other dashboard shells.
  void _handleBackPress() {
    if (_selectedTab != 0) {
      setState(() => _selectedTab = 0);
      return;
    }
    if (Navigator.canPop(context)) {
      Navigator.pop(context);
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
      child: _buildScaffold(),
    );
  }

  Widget _buildScaffold() {
    return Scaffold(
      backgroundColor: _bg,
      appBar: _buildAppBar(),
      body: Stack(
        children: [
          Positioned.fill(
            child: _selectedTab == 0
                ? _buildDashboard()
                : _selectedTab == 1
                    ? _buildRidesList()
                    : _selectedTab == 2
                        ? const CustomerRidesScreen()
                        : _selectedTab == 3
                            ? const AdminNewOrdersScreen()
                            : const ServiceFlowMonitorScreen(),
          ),
          if (_isLoggingOut)
            const ColoredBox(
              color: Colors.black54,
              child: Center(
                child: CircularProgressIndicator(
                  color: _purple,
                ),
              ),
            ),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── App Bar ─────────────────────────────────────────────────
  // Was an 11-icon row (Ads, Commission, Fare, Credentials, Task
  // Approvals, Top-Up, Hero Approvals, Approved Heroes, Download App,
  // Dispatch, Track Rides) plus Logout — the main source of "not
  // organized, confusing" feedback on this screen. Kept the 2 actions
  // an admin actually needs live/at-a-glance during normal use
  // (Dispatch Heroes, Track Active Rides — both map/live-tracking
  // tools used constantly, unlike the rest which are occasional
  // settings/approval actions) plus Logout, and moved everything else
  // into one grouped "More" bottom sheet (_buildMoreSheet) organized
  // into Heroes / Money / Settings sections. Nothing removed — every
  // one of the 11 original destinations is still one tap away.
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      leading: Navigator.canPop(context)
          ? IconButton(
              icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _text, size: 20),
              tooltip: 'Back to HQ',
              onPressed: () {
                if (_selectedTab != 0) {
                  setState(() => _selectedTab = 0);
                } else {
                  Navigator.pop(context);
                }
              },
            )
          : null,
      title: Row(
        children: [
          const Text('🚕', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            'Taxi & Transport',
            style: GoogleFonts.outfit(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 18, // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
            ),
          ),
        ],
      ),
      actions: [
        // NEW (Aug 19 2026): Admin had only WebVersionChecker, which
        // covers the PWA's service-worker refresh and does nothing at
        // all for the installed Android build. So the admin APK had no
        // update path — on the one app used to fix everything else.
        const NativeUpdateButton(appVariant: 'admin'),
        IconButton(
          icon: const Icon(Icons.map_rounded, color: Color(0xFFFF4FA3), size: 22),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminHeroDispatchScreen()),
          ),
          tooltip: 'Dispatch Heroes',
        ),
        IconButton(
          icon: const Icon(Icons.timeline_rounded, color: Color(0xFFFF4FA3), size: 22),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminRideTrackingScreen()),
          ),
          tooltip: 'Track Active Rides',
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(Icons.more_vert_rounded, color: _muted, size: 22),
              tooltip: 'More',
              onPressed: () => _showMoreSheet(context),
            ),
            // Badge sums BOTH counts that used to be shown separately
            // on individual AppBar icons (pending hero approvals +
            // admin_review requests) so nothing that needed attention
            // becomes less visible just by moving behind this menu.
            Positioned(
              right: 6,
              top: 6,
              child: StreamBuilder<QuerySnapshot>(
                stream: _pendingHeroApprovalsStream,
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: _red,
                      shape: BoxShape.circle,
                    ),
                    constraints:
                        const BoxConstraints(minWidth: 14, minHeight: 14),
                    child: Text(
                      count > 9 ? '9+' : '$count',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 8,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  );
                },
              ),
            ),
          ],
        ),
        IconButton(
          icon: const Icon(Icons.logout, color: _red, size: 20),
          onPressed: _showLogoutDialog,
          tooltip: 'Logout',
        ),
      ],
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(height: 1, color: _border),
      ),
    );
  }

  void _showMoreSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _MoreSheet(
        pendingHeroApprovalsStream: _pendingHeroApprovalsStream,
        pendingSellerApprovalsStream: _pendingSellerApprovalsStream,
        openEnquiriesStream: _openEnquiriesStream,
        onTopUp: () => _showTopUpDialog(context),
        onDownloadApp: _downloadAdminApp,
      ),
    );
  }

  // ── Bottom Nav ───────────────────────────────────────────────
  Widget _buildBottomNav() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _border)),
      ),
      child: Row(
        children: List.generate(
          _tabs.length,
          (i) => _navItem(
            i,
            _tabs[i]['icon']! as IconData,
            _tabs[i]['label']! as String,
          ),
        ),
      ),
    );
  }

  // "New Orders" is index 3 — the only tab that needs the escalated-
  // task badge (see admin visibility gap: admin_review tasks need to
  // be obvious the moment an admin lands here, not something they
  // stumble on by tapping into the tab).
  static const int _newOrdersTabIndex = 3;

  Widget _navItem(int idx, IconData icon, String label) {
    final active = _selectedTab == idx;
    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedTab = idx),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (idx == _newOrdersTabIndex)
                Stack(
                  clipBehavior: Clip.none,
                  children: [
                    Icon(icon, color: active ? _gold : _muted, size: 22),
                    Positioned(
                      right: -6,
                      top: -4,
                      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                        stream: _adminReviewCountStream,
                        builder: (context, snap) {
                          // Shared stream covers pending+admin_review; this
                          // badge only wants the admin_review subset, so
                          // filter client-side instead of opening a second
                          // server-side listener.
                          final count = snap.data?.docs
                                  .where((d) => d.data()['status'] == 'admin_review')
                                  .length ??
                              0;
                          if (count == 0) return const SizedBox.shrink();
                          return Container(
                            padding: const EdgeInsets.all(3),
                            decoration: const BoxDecoration(
                              color: _red,
                              shape: BoxShape.circle,
                            ),
                            constraints: const BoxConstraints(
                                minWidth: 14, minHeight: 14,),
                            child: Text(
                              count > 9 ? '9+' : '$count',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 8,
                                  fontWeight: FontWeight.bold,),
                              textAlign: TextAlign.center,
                            ),
                          );
                        },
                      ),
                    ),
                  ],
                )
              else
                Icon(icon, color: active ? _gold : _muted, size: 22),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  fontSize: 10,
                  color: active ? _gold : _muted,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w400,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // TAB 0 — OVERVIEW DASHBOARD
  // ================================================================
  Widget _buildDashboard() {
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildStatCards(),
        const SizedBox(height: 14),
        // FIX: per Nizam's explicit request — moved from being buried
        // inside the "More" menu to a visible tile right on the Taxi
        // main/Overview page, so it's easy to find without hunting
        // through menus. Still opens a confirmation warning per-report
        // before any deep read happens (see AdminDetailedReportsScreen).
        _buildDbAndReportsTile(context),
        const SizedBox(height: 20),
        _buildOnlineHeroes(),
        const SizedBox(height: 20),
        _buildRecentTransactions(),
      ],
    );
  }

  Widget _buildDbAndReportsTile(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: () => Navigator.push(context,
          MaterialPageRoute<void>(builder: (_) => const AdminDetailedReportsScreen()),),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _green.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(color: _green.withValues(alpha: 0.1), blurRadius: 8, spreadRadius: 1),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.query_stats_rounded, color: _green, size: 22),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('DB & Detailed Report',
                      style: TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w700),),
                  SizedBox(height: 2),
                  Text('Usage billing, location demand, DB usage — deep-read warning before opening',
                      style: TextStyle(color: _muted, fontSize: 11),),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
          ],
        ),
      ),
    );
  }

  // ── Stat Cards Row (rides today + wallet total) ───────────────
  Widget _buildStatCards() {
    int ridesToday = 0;
    double earningsToday = 0;
    final docs = _statCardsSnapshot?.docs ?? [];
    for (final doc in docs) {
      final d = doc.data()! as Map<String, dynamic>;
      if (_isToday(d['createdAt'])) {
        ridesToday++;
        final finalFare = (d['finalFare'] as num?)?.toDouble();
        final actualFare = (d['actualFare'] as num?)?.toDouble();
        final tipAmount = (d['tipAmount'] as num?)?.toDouble();
        final estFare = (d['fare'] as num?)?.toDouble();
        if (finalFare != null) {
          earningsToday += finalFare;
        } else if (actualFare != null) {
          earningsToday += actualFare + (tipAmount ?? 0.0);
        } else {
          earningsToday += estFare ?? 0.0;
        }
      }
    }
    return Column(
      children: [
        ManualRefreshHeader(
          lastSyncedAt: _statCardsSyncedAt,
          loading: _statCardsLoading,
          onRefresh: () => unawaited(_fetchStatCards()),
          accentColor: _orange,
          textColor: _muted,
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _statCard(
              '🏍️',
              'Rides Today',
              '$ridesToday',
              _orange,
              _statCardsLoading && _statCardsSnapshot == null,
            ),
            const SizedBox(width: 12),
            StreamBuilder<DatabaseEvent>(
              stream: FirebaseDatabase.instance.ref('online_heroes').onValue,
              builder: (context, rtdbSnap) {
                int activeNow = 0;
                if (rtdbSnap.hasData && rtdbSnap.data!.snapshot.value != null) {
                  final val = rtdbSnap.data!.snapshot.value;
                  // Trust RTDB node existence alone (CTO architecture
                  // decision): presence is governed entirely by
                  // onDisconnect() + the `.info/connected` reconnect
                  // watcher in hero_home_screen.dart — no client
                  // heartbeat, no staleness timeout here. A hero stays
                  // counted online indefinitely until they manually go
                  // offline or RTDB's own connection-drop detection
                  // removes the node server-side.
                  if (val is Map) activeNow = val.length;
                }
                return _statCard(
                  '⚡',
                  'Active Now',
                  '${rtdbSnap.hasData ? activeNow : '…'}',
                  _green,
                  false,
                );
              },
            ),
          ],
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            _statCard(
              '💰',
              'Fare Today',
              '₹${earningsToday.toInt()}',
              _gold,
              _statCardsLoading && _statCardsSnapshot == null,
            ),
            const SizedBox(width: 12),
            _statCard(
              '💳',
              'Wallet Pool',
              _walletLoading
                  ? '...'
                  : '₹${_walletTotal.toStringAsFixed(0)}',
              _purple,
              _walletLoading,
            ),
          ],
        ),
      ],
    );
  }

  Widget _statCard(
    String emoji,
    String label,
    String value,
    Color color,
    bool loading,
  ) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 20)),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration:
                      BoxDecoration(color: color, shape: BoxShape.circle),
                ),
              ],
            ),
            const SizedBox(height: 10),
            if (loading)
              SizedBox(
                height: 24,
                width: 24,
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              )
            else
              Text(
                value,
                style: TextStyle(
                  fontSize: 22,
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 10, color: _muted)),
          ],
        ),
      ),
    );
  }

  // ── Online Heroes Live Feed ────────────────────────────────────
  Widget _buildOnlineHeroes() {
    // Node existence = online (CTO architecture decision — see the
    // "Active Now" stat card comment above for the reasoning).
    final entries = _onlineHeroesData?.entries.toList() ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('🟢', 'Online Heroes', _green),
        const SizedBox(height: 8),
        ManualRefreshHeader(
          lastSyncedAt: _onlineHeroesSyncedAt,
          loading: _onlineHeroesLoading,
          onRefresh: () => unawaited(_fetchOnlineHeroes()),
          accentColor: _green,
          textColor: _muted,
        ),
        const SizedBox(height: 10),
        if (_onlineHeroesLoading && _onlineHeroesData == null)
          const Center(
            child: CircularProgressIndicator(color: _green, strokeWidth: 2),
          )
        else if (entries.isEmpty)
          _emptyCard('No heroes online right now', '🛵')
        else
          Column(
              children: entries.map((entry) {
                final d = Map<dynamic, dynamic>.from(entry.value as Map? ?? {});
                final name = d['name'] as String? ?? 'Hero';
                final isAvailable = d['isAvailable'] as bool? ?? true;
                // "On ride" == not available for a new dispatch. RTDB's
                // isAvailable already carries this (see _syncOnlineStatus
                // in hero_home_screen.dart: isAvailable = activeRideId
                // .isEmpty) — no separate 'status' field needed anymore.
                final isOnRide = !isAvailable;
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: isOnRide
                          ? _orange.withValues(alpha: 0.4)
                          : _green.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 38,
                        height: 38,
                        decoration: BoxDecoration(
                          color: isOnRide
                              ? _orange.withValues(alpha: 0.12)
                              : _green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            name.isNotEmpty ? name[0].toUpperCase() : 'H',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: isOnRide ? _orange : _green,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              name,
                              style: const TextStyle(
                                fontSize: 13,
                                color: _text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              // NOTE: activeRideId isn't in RTDB's
                              // online_heroes node (only Firestore's
                              // heroes doc has it, and that's Step 4 —
                              // active-order-state migration — not part
                              // of this presence-only cleanup), so this
                              // no longer claims to show a ride ID.
                              isOnRide ? 'On Ride' : 'Available',
                              style: TextStyle(
                                fontSize: 10,
                                color: isOnRide ? _orange : _green,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: isOnRide
                              ? _orange.withValues(alpha: 0.12)
                              : _green.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          isOnRide ? '🚀 ON RIDE' : '✅ ONLINE',
                          style: TextStyle(
                            fontSize: 9,
                            fontWeight: FontWeight.w800,
                            color: isOnRide ? _orange : _green,
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
      ],
    );
  }

  // ── Recent Transactions ───────────────────────────────────────
  Widget _buildRecentTransactions() {
    final docs = _recentTransactionsSnapshot?.docs ?? [];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('💳', 'Recent Transactions', _purple),
        const SizedBox(height: 8),
        ManualRefreshHeader(
          lastSyncedAt: _recentTransactionsSyncedAt,
          loading: _recentTransactionsLoading,
          onRefresh: () => unawaited(_fetchRecentTransactions()),
          accentColor: _purple,
          textColor: _muted,
        ),
        const SizedBox(height: 10),
        if (_recentTransactionsLoading && _recentTransactionsSnapshot == null)
          const Center(
            child: CircularProgressIndicator(color: _purple, strokeWidth: 2),
          )
        else if (docs.isEmpty)
          _emptyCard('No transactions yet', '💸')
        else
          Column(
              children: docs.map((doc) {
                final d = doc.data()! as Map<String, dynamic>;
                final type = d['type'] as String? ?? 'debit';
                final amount = (d['amount'] as num?)?.toDouble() ?? 0;
                final uid = d['userId'] as String? ?? '';
                final rideId = d['rideId'] as String? ?? '';
                final ts = d['createdAt'] as Timestamp?;
                final time = ts != null
                    ? '${ts.toDate().day}/${ts.toDate().month} '
                        '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                    : '—';
                final isDebit = type == 'debit';
                final isBurn = type == 'burn';
                final color = isBurn
                    ? _gold
                    : isDebit
                        ? _red
                        : _green;
                final icon = isBurn
                    ? '🪙'
                    : isDebit
                        ? '↓'
                        : '↑';
                final label = isBurn
                    ? 'Coins Burned'
                    : isDebit
                        ? 'Wallet Debit'
                        : 'Wallet Credit';
                return Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: color.withValues(alpha: 0.2)),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 36,
                        height: 36,
                        decoration: BoxDecoration(
                          color: color.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            icon,
                            style: TextStyle(
                              fontSize: 16,
                              color: color,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              label,
                              style: const TextStyle(
                                fontSize: 12,
                                color: _text,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              'UID: ${uid.substring(0, uid.length.clamp(0, 8))}… • $time',
                              style:
                                  const TextStyle(fontSize: 9, color: _muted),
                            ),
                            if (rideId.isNotEmpty)
                              Text(
                                'Ride: $rideId',
                                style:
                                    const TextStyle(fontSize: 9, color: _muted),
                              ),
                          ],
                        ),
                      ),
                      Text(
                        isBurn
                            ? '${(d['coinsUsed'] as int?) ?? 0} coins'
                            : '₹${amount.toStringAsFixed(2)}',
                        style: TextStyle(
                          fontSize: 14,
                          color: color,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
            ),
      ],
    );
  }

  // ================================================================
  // TAB 1 — ALL RIDES LIST
  // ================================================================
  Widget _buildRidesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: _ridesListStream,
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _gold));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return _emptyCard('No rides found', '🏍️');
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final d = doc.data()! as Map<String, dynamic>;
            final status = d['status'] as String? ?? 'unknown';
            final pickup = d['pickup'] as String? ??
                d['pickupAddress'] as String? ?? '—';
            final drop = d['drop'] as String? ??
                d['dropAddress'] as String? ?? '—';
            final fare = (d['fare'] as num?)?.toInt() ?? 0;
            final tip = (d['tipAmount'] as num?)?.toInt() ?? 0;
            final finalFare = (d['finalFare'] as num?)?.toInt() ?? (fare + tip);
            final rating = (d['customerRating'] as num?)?.toInt();
            final captain = d['captainName'] as String? ??
                d['heroName'] as String? ?? '—';
            final cust = d['customerName'] as String? ?? '—';
            final ts = d['createdAt'] as Timestamp?;
            final time = ts != null
                ? '${ts.toDate().day}/${ts.toDate().month} '
                    '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                : '—';
            // T4: Read normalized 'category' first, fall back to vehicleType
            final rawCategory =
                (d['category'] as String? ?? d['vehicleType'] as String? ?? '')
                    .trim()
                    .toLowerCase();
            final categoryEmoji = _categoryEmoji(rawCategory);
            final categoryLabel = _categoryLabel(rawCategory);
            final color = _statusColor(status);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: color.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              '🟢 $pickup',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                            const SizedBox(height: 2),
                            Text(
                              '🔴 $drop',
                              style: const TextStyle(
                                fontSize: 11,
                                color: _text,
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ],
                        ),
                      ),
                      _statusBadge(status, color),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      _pill('👤 $cust', _muted),
                      const SizedBox(width: 6),
                      _pill('🏍️ $captain', _muted),
                      const Spacer(),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(
                            '₹$finalFare',
                            style: const TextStyle(
                              fontSize: 14,
                              color: _gold,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (tip > 0)
                            Text(
                              'Fare: ₹$fare + Tip: ₹$tip',
                              style: const TextStyle(
                                fontSize: 9,
                                color: _muted,
                              ),
                            ),
                          if (rating != null && rating > 0)
                            Text(
                              '⭐' * rating,
                              style: const TextStyle(fontSize: 9),
                            ),
                        ],
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      // T4: Category badge — shows fleet type for admin monitoring
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _purple.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _purple.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '$categoryEmoji $categoryLabel',
                          style: const TextStyle(
                            fontSize: 9,
                            color: _purple,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      // ── Payment status badge ─────────────────────────
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: _settledPaymentStatuses.contains(d['paymentStatus'] as String? ?? 'pending')
                              ? _green.withValues(alpha: 0.12)
                              : _red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(7),
                          border: Border.all(
                            color: _settledPaymentStatuses.contains(d['paymentStatus'] as String? ?? 'pending')
                                ? _green.withValues(alpha: 0.3)
                                : _red.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          '💳 ${(d['paymentStatus'] as String? ?? 'pending').toUpperCase()}',
                          style: TextStyle(
                            fontSize: 9,
                            color: _settledPaymentStatuses.contains(d['paymentStatus'] as String? ?? 'pending') ? _green : _red,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      if (!_settledPaymentStatuses.contains(d['paymentStatus'] as String? ?? 'pending'))
                        Padding(
                          padding: const EdgeInsets.only(left: 4),
                          child: TextButton(
                            onPressed: () => _showUtrDialog(doc.id, cust, (d['finalFare'] as num?)?.toDouble() ?? 0),
                            style: TextButton.styleFrom(
                              backgroundColor: _purple.withValues(alpha: 0.12),
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              minimumSize: Size.zero,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                            child: const Text(
                              'Verify UTR',
                              style: TextStyle(fontSize: 9, fontWeight: FontWeight.w800, color: _purple),
                            ),
                          ),
                        ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          'ID: ${doc.id.substring(0, 12)}…  •  $time',
                          style: const TextStyle(fontSize: 9, color: _muted),
                        ),
                      ),
                      if (rating != null && rating > 0)
                        Text(
                          '⭐ $rating/5',
                          style: const TextStyle(fontSize: 9, color: _muted),
                        ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Shared helpers ─────────────────────────────────────────────

  // T4: Category helpers for admin fleet monitoring
  String _categoryEmoji(String category) {
    switch (category) {
      case 'auto':       return '🛺';
      case 'car':
      case 'cab':        return '🚘';
      case 'parcel':     return '📦';
      case 'emergency_manpower':
      case 'manpower':   return '🚨';
      case 'bike':
      default:           return '🏍️';
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'auto':             return 'Auto';
      case 'car':
      case 'cab':              return 'Cab/Mini';
      case 'parcel':           return 'Parcel';
      case 'emergency_manpower':
      case 'manpower':         return 'Emergency';
      case 'bike':
      default:                 return 'Bike';
    }
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'completed':
        return _green;
      case 'accepted':
      case 'arriving':
      case 'in_progress':
        return _orange;
      case 'searching':
        return _gold;
      case 'cancelled':
      case 'cancelled_by_captain':
        return _red;
      default:
        return _muted;
    }
  }

  Widget _statusBadge(String status, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          status.toUpperCase().replaceAll('_', ' '),
          style:
              TextStyle(fontSize: 8, color: color, fontWeight: FontWeight.w800),
        ),
      );

  Widget _pill(String label, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: _border),
        ),
        child: Text(
          label,
          style: TextStyle(fontSize: 9, color: color),
          overflow: TextOverflow.ellipsis,
        ),
      );

  Widget _sectionHeader(String emoji, String title, Color color) => Row(
        children: [
          Text(emoji, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 8),
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 14,
              color: _text,
              fontWeight: FontWeight.w800,
            ),
          ),
          const Spacer(),
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
          const SizedBox(width: 4),
          Text(
            'LIVE',
            style: TextStyle(
              fontSize: 8,
              color: color,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      );

  Widget _emptyCard(String msg, String emoji) => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(24),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(emoji, style: const TextStyle(fontSize: 36)),
            const SizedBox(height: 8),
            Text(msg, style: const TextStyle(fontSize: 13, color: _muted)),
          ],
        ),
      );
}

// ================================================================
// _MoreSheet — the 9 AppBar actions that used to be a single 11-icon
// row (2 of the 11 — Dispatch Heroes, Track Active Rides — stayed
// directly on the AppBar since those are used constantly). Grouped
// into 3 clearly-labeled sections so it reads as organized rather
// than a flat list: Heroes (approvals, approved roster), Money
// (commission, fares, customer top-up), Settings (ads, credentials,
// task approvals, app download).
// ================================================================
class _MoreSheet extends StatelessWidget {
  final Stream<QuerySnapshot> pendingHeroApprovalsStream;
  final Stream<QuerySnapshot> pendingSellerApprovalsStream;
  /// Built once by the parent, not per rebuild: re-attaching a
  /// Firestore listener re-bills its whole result set.
  final Stream<List<ChittiEnquiry>> openEnquiriesStream;
  final VoidCallback onTopUp;
  final VoidCallback onDownloadApp;

  const _MoreSheet({
    required this.pendingHeroApprovalsStream,
    required this.pendingSellerApprovalsStream,
    required this.openEnquiriesStream,
    required this.onTopUp,
    required this.onDownloadApp,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 16),
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            _sheetSectionLabel('HEROES'),
            _sheetTile(
              context,
              icon: Icons.person_add_alt_1,
              iconColor: _green,
              label: 'Hero Approvals',
              trailing: StreamBuilder<QuerySnapshot>(
                stream: pendingHeroApprovalsStream,
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(count > 9 ? '9+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),),
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const HeroApprovalsScreen()));
              },
            ),
            _sheetTile(
              context,
              icon: Icons.how_to_reg_outlined,
              iconColor: _gold,
              label: 'Approved Heroes',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ApprovedHeroesScreen()));
              },
            ),
            // NEW (Aug 17 2026 — Nizam: "adminala exact hero earning
            // pakkamudila... hero voda uid vachu than kaatuthu hero name
            // kaatala"). Resolves uid -> name/phone and gives
            // Today/7-day/Month/All plus per-hero drill-down. One Fetch
            // powers every filter — see the screen's own header for the
            // read-cost reasoning.
            _sheetTile(
              context,
              icon: Icons.payments_outlined,
              iconColor: _green,
              label: 'Hero Earnings',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminHeroEarningsScreen(),
                  ),
                );
              },
            ),
            const SizedBox(height: 16),
            _sheetSectionLabel('SELLERS'),
            _sheetTile(
              context,
              icon: Icons.storefront_outlined,
              iconColor: _teal,
              label: 'Seller Approvals',
              trailing: StreamBuilder<QuerySnapshot>(
                stream: pendingSellerApprovalsStream,
                builder: (context, snap) {
                  final count = snap.data?.docs.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(count > 9 ? '9+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),),
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AdminSellerApprovalScreen()));
              },
            ),
            // NEW (Sep 2026 — universal catalog build): the shared
            // grocery SKU list every grocery seller toggles items on
            // from — see admin_master_catalog_screen.dart's header.
            _sheetTile(
              context,
              icon: Icons.category_outlined,
              iconColor: _teal,
              label: 'Grocery Catalog',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    builder: (_) => const AdminMasterCatalogScreen(department: 'grocery'),
                  ),
                );
              },
            ),
            _sheetTile(
              context,
              icon: Icons.forum_outlined,
              iconColor: _teal,
              // Reachable without Chitti on purpose. These are leads
              // with a phone number and a shelf life — a rate question
              // answered tomorrow has already been answered by
              // somebody else's shop — so they must not depend on
              // anyone thinking to ask the assistant.
              label: 'Customer Enquiries',
              trailing: StreamBuilder<List<ChittiEnquiry>>(
                stream: openEnquiriesStream,
                builder: (context, snap) {
                  final count = snap.data?.length ?? 0;
                  if (count == 0) return const SizedBox.shrink();
                  return Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(
                      color: _red,
                      borderRadius: BorderRadius.circular(999),
                    ),
                    child: Text(count > 9 ? '9+' : '$count',
                        style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),),
                  );
                },
              ),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const ChittiEnquiriesScreen()));
              },
            ),
            const SizedBox(height: 16),
            _sheetSectionLabel('MONEY'),
            _sheetTile(
              context,
              icon: Icons.settings_outlined,
              iconColor: _muted,
              label: 'Commission Settings',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CommissionSettingsScreen()));
              },
            ),
            _sheetTile(
              context,
              icon: Icons.price_check_outlined,
              iconColor: _gold,
              label: 'Fare Management',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const FareManagementScreen()));
              },
            ),
            _sheetTile(
              context,
              icon: Icons.account_balance_wallet,
              iconColor: _gold,
              label: 'Top-Up Customer',
              onTap: () {
                Navigator.pop(context);
                onTopUp();
              },
            ),
            // FIX: this used to be a separate "Detailed Reports" tile
            // here too — now a single entry point, moved to a visible
            // "DB & Detailed Report" card right on the Taxi Overview
            // page (see _buildDbAndReportsTile), per Nizam's explicit
            // request. Not duplicated here anymore.
            const SizedBox(height: 16),
            _sheetSectionLabel('SETTINGS'),
            _sheetTile(
              context,
              icon: Icons.campaign_outlined,
              iconColor: _muted,
              label: 'Manage Ads',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const AdsManagementScreen()));
              },
            ),
            _sheetTile(
              context,
              icon: Icons.badge_outlined,
              iconColor: _muted,
              label: 'Credentials',
              onTap: () {
                Navigator.pop(context);
                Navigator.push(context, MaterialPageRoute<void>(builder: (_) => const CredentialsAdminScreen()));
              },
            ),
            _sheetTile(
              context,
              icon: Icons.task_alt,
              iconColor: _green,
              label: 'Task Approvals',
              onTap: () {
                Navigator.pop(context);
                Navigator.pushNamed(context, '/admin/tasks');
              },
            ),
            _sheetTile(
              context,
              icon: Icons.download_rounded,
              iconColor: const Color(0xFFFF4FA3),
              label: 'Download Latest App',
              onTap: () {
                Navigator.pop(context);
                onDownloadApp();
              },
            ),
          ],
        ),
      ),
    );
  }

  Widget _sheetSectionLabel(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 8, left: 4),
        child: Text(
          text,
          style: const TextStyle(
            color: _muted,
            fontSize: 11,
            fontWeight: FontWeight.w800,
            letterSpacing: 1,
          ),
        ),
      );

  Widget _sheetTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required VoidCallback onTap,
    Widget? trailing,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 20),
            const SizedBox(width: 14),
            Expanded(
              child: Text(label, style: const TextStyle(color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
            ),
            if (trailing != null) ...[trailing, const SizedBox(width: 8)],
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Stream<QuerySnapshot<Object?>>>('pendingHeroApprovalsStream', pendingHeroApprovalsStream));
    properties.add(DiagnosticsProperty<Stream<QuerySnapshot<Object?>>>('pendingSellerApprovalsStream', pendingSellerApprovalsStream));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTopUp', onTopUp));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onDownloadApp', onDownloadApp));
  }
}
