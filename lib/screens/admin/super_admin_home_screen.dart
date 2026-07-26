import 'dart:async';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:colorful_iconify_flutter/icons/fluent_emoji_flat.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import 'admin_dashboard_screen.dart';
import 'admin_service_requests_screen.dart';
import 'commission_settings_screen.dart';

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
  static const Color _green = Color(0xFF00C853);
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

  @override
  void initState() {
    super.initState();
    _alertSub = FirebaseFirestore.instance
        .collection('service_requests')
        .where('requestType', whereIn: ['hero_booking', 'electronics_service'])
        .where('status', whereIn: ['pending', 'admin_review'])
        .snapshots()
        .listen(_onWaitingRequestsChanged, onError: (Object e) {
      debugPrint('[SuperAdminHome] Alert listener error: $e');
    });
  }

  @override
  void dispose() {
    _alertSub?.cancel();
    _alertPlayer.dispose();
    super.dispose();
  }

  void _onWaitingRequestsChanged(QuerySnapshot<Map<String, dynamic>> snapshot) {
    final currentIds = snapshot.docs.map((d) => d.id).toSet();
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

  String _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch
        .toString();
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _text)),
        backgroundColor: _surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _purple.withOpacity(0.4)),
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: IndexedStack(
          index: _tabIndex,
          children: [
            _buildOverviewTab(context),
            AdminServiceRequestsScreen(
              key: const ValueKey('hero_tab'),
              requestType: 'hero_booking',
              title: 'Hero Booking Status',
            ),
            AdminServiceRequestsScreen(
              key: const ValueKey('electronics_tab'),
              requestType: 'electronics_service',
              title: 'Electronics Booking',
            ),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildOverviewTab(BuildContext context) {
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(child: _buildHeader(context)),
        SliverToBoxAdapter(child: _buildSosCallCenterBanner(context)),
        SliverToBoxAdapter(child: _buildStatsRow()),
        // Single "Manage" section — every category an admin manages
        // (taxi/transportation, app settings) lives here, clearly
        // labeled. Hero/Electronics moved to their own bottom-nav tabs
        // above — Taxi and Settings stay here since Taxi pushes its
        // own full screen and Settings is a lightweight one-off.
        SliverToBoxAdapter(child: _buildManageSection(context)),
        SliverToBoxAdapter(child: _buildFooter(context)),
      ],
    );
  }

  // Same visual convention as dashboard_screen.dart's _buildBottomNav:
  // Row of InkWell icon+label items, active one highlighted.
  Widget _buildBottomNav() {
    final List<({String icon, String label, String? requestType})> items = [
      (icon: FluentEmojiFlat.bar_chart, label: 'Overview', requestType: null),
      (
        icon: FluentEmojiFlat.man_superhero,
        label: 'Hero',
        requestType: 'hero_booking'
      ),
      (
        icon: FluentEmojiFlat.mobile_phone,
        label: 'Electronics',
        requestType: 'electronics_service'
      ),
    ];
    return Container(
      decoration: BoxDecoration(
        color: _surface,
        border: Border(top: BorderSide(color: _purple.withOpacity(0.15))),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 16,
              offset: const Offset(0, -4)),
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
                onTap: () => setState(() => _tabIndex = i),
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
                            child: SvgPicture.string(item.icon),
                          ),
                        ),
                        if (item.requestType != null)
                          Positioned(
                            top: -4,
                            right: -8,
                            child: _NavWaitingDot(
                                requestType: item.requestType!),
                          ),
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(item.label,
                        style: TextStyle(
                            fontSize: 9.5,
                            color: active ? _gold : _text.withOpacity(0.55),
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400)),
                  ]),
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
      stream: FirebaseFirestore.instance
          .collection('sos_alerts')
          .where('status', isEqualTo: 'active')
          .snapshots(),
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
            border: Border.all(color: Colors.white.withOpacity(0.28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF1744).withOpacity(0.45),
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
          bottom: BorderSide(color: _purple.withOpacity(0.2)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _purple.withOpacity(0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _purple.withOpacity(0.3)),
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
                    color: _text.withOpacity(0.55),
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
              color: _text.withOpacity(0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final todayMs = int.parse(_todayStart());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rides')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo:
                  Timestamp.fromMillisecondsSinceEpoch(todayMs),
            )
            .snapshots(),
        builder: (context, snapshot) {
          int totalRides = 0;
          double revenue = 0;
          if (snapshot.hasData) {
            final docs = snapshot.data!.docs;
            totalRides = docs.length;
            for (final doc in docs) {
              final data = doc.data()! as Map<String, dynamic>;
              final finalFare = (data['finalFare'] as num?)?.toDouble();
              final actualFare = (data['actualFare'] as num?)?.toDouble();
              final tipAmount = (data['tipAmount'] as num?)?.toDouble();
              final estFare = (data['fare'] as num?)?.toDouble();
              if (finalFare != null) {
                revenue += finalFare;
              } else if (actualFare != null) {
                revenue += actualFare + (tipAmount ?? 0);
              } else {
                revenue += estFare ?? 0;
              }
            }
          }
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _purple.withOpacity(0.15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statChip(
                  icon: Icons.directions_bike,
                  label: 'Rides Today',
                  value: snapshot.hasData ? '$totalRides' : '…',
                  color: _orange,
                ),
                _divider(),
                _activeHeroesChip(),
                _divider(),
                _statChip(
                  icon: Icons.currency_rupee,
                  label: 'Revenue',
                  value:
                      snapshot.hasData ? '₹${revenue.toStringAsFixed(0)}' : '…',
                  color: _gold,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _activeHeroesChip() {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('online_heroes').onValue,
      builder: (context, snap) {
        int count = 0;
        if (snap.hasData && snap.data!.snapshot.value != null) {
          final val = snap.data!.snapshot.value;
          if (val is Map) {
            count = val.length;
          }
        }
        return _statChip(
          icon: Icons.flash_on,
          label: 'Active Heroes',
          value: '${snap.hasData ? count : '…'}',
          color: _green,
        );
      },
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: _text.withOpacity(0.5), fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _divider() =>
      Container(height: 36, width: 1, color: _text.withOpacity(0.08));

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
              color: _text.withOpacity(0.5),
              fontSize: 11,
              fontWeight: FontWeight.w800,
              letterSpacing: 1.2,
            ),
          ),
          const SizedBox(height: 10),
          _AdminReviewBadgeWrapper(
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
          const SizedBox(height: 12),
          // Hero Booking Status and Electronics Booking used to be tiles
          // here too — they're now their own bottom-nav tabs (Hero /
          // Electronics) so admins reach them with one tap instead of
          // Overview -> tile -> pushed screen. Taxi stays a tile because
          // AdminDashboardScreen owns its own full Scaffold/bottom-nav
          // and is reached by push, not by swapping this screen's body.
          _ManageTile(
            label: 'App Settings',
            subtitle: 'Commission, fares, ads, credentials',
            iconSvg: FluentEmojiFlat.gear,
            color: _gold,
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute<void>(
                builder: (_) => const CommissionSettingsScreen(),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SuperAdminHomeScreen(),
                ),
              ),
              icon: const Icon(
                Icons.update_rounded,
                color: _purple,
                size: 18,
              ),
              label: const Text(
                'Check for Updates',
                style: TextStyle(
                  color: _purple,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(
                  color: _purple,
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFFF5252),
                size: 18,
              ),
              label: const Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFFF5252),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(
                  color: Color(0xFFFF5252),
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'v1.0.0',
            style: TextStyle(
              color: _text.withOpacity(0.3),
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
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
    this.requestType,
  });

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
        border: Border.all(color: color.withOpacity(0.3)),
        boxShadow: [
          BoxShadow(
            color: color.withOpacity(0.1),
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
              color: color.withOpacity(0.15),
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
              color: color.withOpacity(0.6), size: 16),
        ],
      ),
    );

    return GestureDetector(onTap: onTap, child: content);
  }
}

// Small red dot for the bottom-nav Hero/Electronics tabs — same
// waiting-count query as _WaitingBadge, but rendered as a compact dot
// (no room for "N waiting" text at nav-bar icon size).
class _NavWaitingDot extends StatelessWidget {
  final String requestType;
  const _NavWaitingDot({required this.requestType});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .where('requestType', isEqualTo: requestType)
          .where('status', whereIn: ['pending', 'admin_review'])
          .snapshots(),
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
            style: const TextStyle(
                color: Colors.white, fontSize: 8, fontWeight: FontWeight.w800),
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
  const _AdminReviewBadgeWrapper({required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .where('status', isEqualTo: 'admin_review')
          .snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
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
}
