// ================================================================
// AdminDashboardScreen — Allin1 Super App
// Live Firestore: rides today, online heroes, wallet totals,
// recent transactions
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_hero_dispatch_screen.dart';
import 'admin_new_orders_screen.dart';
import 'admin_ride_tracking_screen.dart';
import 'ads_management_screen.dart';
import 'approved_heroes_screen.dart';
import 'commission_settings_screen.dart';
import 'credentials_admin_screen.dart';
import 'customer_rides_screen.dart';
import 'fare_management_screen.dart';
import 'hero_approvals_screen.dart';

// ── Theme ──────────────────────────────────────────────────────
const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _orange = Color(0xFFFF6B35);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
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
  ];

  // Cached wallet total — computed once on load to avoid massive reads
  double _walletTotal = 0;
  bool _walletLoading = true;

  // Cached stream — this badge is always mounted (lives in the AppBar,
  // shown on every tab), so without caching it tears down and reattaches
  // a Firestore listener on every unrelated setState() rebuild.
  late final Stream<QuerySnapshot> _pendingHeroApprovalsStream;

  @override
  void initState() {
    super.initState();
    _pendingHeroApprovalsStream = FirebaseFirestore.instance
        .collection('heroes')
        .where('approvalStatus', isEqualTo: 'pending')
        .snapshots();
    // Use unawaited if we don't want to block, or just call it since it handles its own state
    _computeWalletTotal();
  }

  @override
  void dispose() {
    _phoneController.dispose();
    _topUpAmountController.dispose();
    super.dispose();
  }

  /// Aggregates walletBalance from all users — run once per session.
  Future<void> _computeWalletTotal() async {
    try {
      final snap = await FirebaseFirestore.instance.collection('users').get();
      double total = 0;
      for (final doc in snap.docs) {
        total += (doc.data()['walletBalance'] as num?)?.toDouble() ?? 0;
      }
      if (mounted) {
        setState(() {
          _walletTotal = total;
          _walletLoading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _walletLoading = false);
      }
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
                            .update({
                          fieldName: FieldValue.increment(amount),
                        });

                        // Log transaction
                        await FirebaseFirestore.instance
                            .collection('wallet_transactions')
                            .add({
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

  // T2: Admin APK download — CEO drops admin_app.apk into Firebase hosting
  // web public dir and runs `firebase deploy` to push the latest build.
  Future<void> _downloadAdminApp() async {
    const apkUrl = 'https://my-allin1.web.app/admin_app.apk';
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

  @override
  Widget build(BuildContext context) {
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
                        : const AdminNewOrdersScreen(),
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
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _surface,
      title: Row(
        children: [
          const Text('🔐', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            'Admin Dashboard',
            style: GoogleFonts.outfit(
              color: _text,
              fontWeight: FontWeight.w800,
              fontSize: 17,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          icon: const Icon(Icons.campaign_outlined, color: _muted, size: 20),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const AdsManagementScreen(),
            ),
          ),
          tooltip: 'Manage Ads',
        ),
        IconButton(
          icon: const Icon(Icons.settings_outlined, color: _muted, size: 20),
          onPressed: () => _navigate(const CommissionSettingsScreen()),
          tooltip: 'Commission Settings',
        ),
        IconButton(
          icon: const Icon(Icons.price_check_outlined, color: _gold, size: 20),
          onPressed: () => _navigate(const FareManagementScreen()),
          tooltip: 'Fare Management',
        ),
        IconButton(
          icon: const Icon(Icons.badge_outlined, color: _muted, size: 20),
          onPressed: () => _navigate(const CredentialsAdminScreen()),
          tooltip: 'Credentials',
        ),
        IconButton(
          icon: const Icon(
            Icons.task_alt,
            color: Color(0xFF00C853),
          ),
          tooltip: 'Task Approvals',
          onPressed: () => Navigator.pushNamed(context, '/admin/tasks'),
        ),
        IconButton(
          icon: const Icon(
            Icons.account_balance_wallet,
            color: Color(0xFFFFBB00),
          ),
          tooltip: 'Top-Up Customer',
          onPressed: () => _showTopUpDialog(context),
        ),
        Stack(
          clipBehavior: Clip.none,
          children: [
            IconButton(
              icon: const Icon(
                Icons.person_add_alt_1,
                color: Color(0xFF00C853),
                size: 20,
              ),
              tooltip: 'Hero Approvals',
              onPressed: () => Navigator.push(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const HeroApprovalsScreen(),
                ),
              ),
            ),
            Positioned(
              right: 4,
              top: 4,
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
          icon: const Icon(
            Icons.how_to_reg_outlined,
            color: _gold,
            size: 20,
          ),
          tooltip: 'Approved Heroes',
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const ApprovedHeroesScreen(),
            ),
          ),
        ),
        // T2: Download latest admin APK from Firebase hosting
        IconButton(
          icon: const Icon(
            Icons.download_rounded,
            color: Color(0xFFFF4FA3),
            size: 20,
          ),
          onPressed: _downloadAdminApp,
          tooltip: 'Download Latest App',
        ),
        IconButton(
          icon:
              const Icon(Icons.map_rounded, color: Color(0xFFFF4FA3), size: 22),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminHeroDispatchScreen()),
          ),
          tooltip: 'Dispatch Heroes',
        ),
        IconButton(
          icon: const Icon(
            Icons.timeline_rounded,
            color: Color(0xFFFF4FA3),
            size: 22,
          ),
          onPressed: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => const AdminRideTrackingScreen()),
          ),
          tooltip: 'Track Active Rides',
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
        const SizedBox(height: 20),
        _buildOnlineHeroes(),
        const SizedBox(height: 20),
        _buildRecentTransactions(),
      ],
    );
  }

  // ── Stat Cards Row (rides today + wallet total) ───────────────
  Widget _buildStatCards() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .orderBy('createdAt', descending: true)
          .limit(200)
          .snapshots(),
      builder: (context, snap) {
        int ridesToday = 0;
        double earningsToday = 0;
        if (snap.hasData) {
          for (final doc in snap.data!.docs) {
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
        }
        return Column(
          children: [
            Row(
              children: [
                _statCard(
                  '🏍️',
                  'Rides Today',
                  '$ridesToday',
                  _orange,
                  snap.connectionState == ConnectionState.waiting,
                ),
                const SizedBox(width: 12),
                StreamBuilder<DatabaseEvent>(
                  stream:
                      FirebaseDatabase.instance.ref('online_heroes').onValue,
                  builder: (context, rtdbSnap) {
                    int activeNow = 0;
                    if (rtdbSnap.hasData &&
                        rtdbSnap.data!.snapshot.value != null) {
                      final val = rtdbSnap.data!.snapshot.value;
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
                  snap.connectionState == ConnectionState.waiting,
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
      },
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
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('🟢', 'Online Heroes', _green),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('heroes')
              .where('status', whereIn: ['online', 'on_ride']).snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child: CircularProgressIndicator(color: _green, strokeWidth: 2),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _emptyCard('No heroes online right now', '🛵');
            }
            return Column(
              children: docs.map((doc) {
                final d = doc.data()! as Map<String, dynamic>;
                final name = d['captainName'] as String? ?? 'Hero';
                final status = d['status'] as String? ?? 'offline';
                final rideId = d['activeRideId'] as String? ?? '';
                final isOnRide = status == 'on_ride';
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
                              isOnRide
                                  ? 'On Ride • ID: ${rideId.substring(0, rideId.length.clamp(0, 8))}...'
                                  : 'Available',
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
            );
          },
        ),
      ],
    );
  }

  // ── Recent Transactions ───────────────────────────────────────
  Widget _buildRecentTransactions() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader('💳', 'Recent Transactions', _purple),
        const SizedBox(height: 10),
        StreamBuilder<QuerySnapshot>(
          stream: FirebaseFirestore.instance
              .collection('wallet_transactions')
              .orderBy('createdAt', descending: true)
              .limit(15)
              .snapshots(),
          builder: (context, snap) {
            if (snap.connectionState == ConnectionState.waiting) {
              return const Center(
                child:
                    CircularProgressIndicator(color: _purple, strokeWidth: 2),
              );
            }
            final docs = snap.data?.docs ?? [];
            if (docs.isEmpty) {
              return _emptyCard('No transactions yet', '💸');
            }
            return Column(
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
            );
          },
        ),
      ],
    );
  }

  // ================================================================
  // TAB 1 — ALL RIDES LIST
  // ================================================================
  Widget _buildRidesList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .orderBy('createdAt', descending: true)
          .limit(100)
          .snapshots(),
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
            final pickup =
                d['pickup'] as String? ?? d['pickupAddress'] as String? ?? '—';
            final drop =
                d['drop'] as String? ?? d['dropAddress'] as String? ?? '—';
            final fare = (d['fare'] as num?)?.toInt() ?? 0;
            final tip = (d['tipAmount'] as num?)?.toInt() ?? 0;
            final finalFare = (d['finalFare'] as num?)?.toInt() ?? (fare + tip);
            final rating = (d['customerRating'] as num?)?.toInt();
            final captain =
                d['captainName'] as String? ?? d['heroName'] as String? ?? '—';
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
      case 'auto':
        return '🛺';
      case 'car':
      case 'cab':
        return '🚘';
      case 'parcel':
        return '📦';
      case 'emergency_manpower':
      case 'manpower':
        return '🚨';
      case 'bike':
      default:
        return '🏍️';
    }
  }

  String _categoryLabel(String category) {
    switch (category) {
      case 'auto':
        return 'Auto';
      case 'car':
      case 'cab':
        return 'Cab/Mini';
      case 'parcel':
        return 'Parcel';
      case 'emergency_manpower':
      case 'manpower':
        return 'Emergency';
      case 'bike':
      default:
        return 'Bike';
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
