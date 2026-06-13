// ================================================================
// EarnDashboardScreen — Earn Allin1 Module
// NJ Coins: 1000 Coins = Rs.10
// Pending → Verified after 30-35 days (Manual Admin credit)
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'rewards_hub_screen.dart';

// ── Theme ─────────────────────────────────────────────────────
const Color _bg = Color(0xFF0A0A12);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2A);
const Color _card2 = Color(0xFF222235);
const Color _purple = Color(0xFF6C63FF);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _orange = Color(0xFFFF6B35);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

// ── Coin Rate ─────────────────────────────────────────────────
const int kCoinsPerRupee = 100; // 1000 coins = Rs.10
const int kMinWithdrawal = 5000; // 5000 coins = Rs.50
const double kCoinToRupee = 10.0 / 1000.0;

// ── Task Model ────────────────────────────────────────────────
class _EarnTask {
  final String id, title, subtitle, emoji;
  final int coins;
  final String channel; // 'cpa', 'internal', 'local'
  final String? url;
  final String? internalAction;
  final bool isHot;
  const _EarnTask({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.coins,
    required this.channel,
    this.url,
    this.internalAction,
    this.isHot = false,
  });
}

// ── Task List ─────────────────────────────────────────────────
const List<_EarnTask> _tasks = [
  // Channel A — EarnKaro CPA (SubID injected at runtime)
  _EarnTask(
    id: 'kotak_811',
    title: 'Open Kotak 811 Account',
    subtitle: 'Free zero-balance savings account',
    emoji: '🏦',
    coins: 10000,
    channel: 'cpa',
    url: 'https://earnkaro.com/offer/kotak811',
    isHot: true,
  ),
  _EarnTask(
    id: 'angelone',
    title: 'Install AngelOne & Sign Up',
    subtitle: 'Free Demat + Trading account',
    emoji: '📈',
    coins: 5000,
    channel: 'cpa',
    url: 'https://earnkaro.com/offer/angelone',
    isHot: true,
  ),
  _EarnTask(
    id: 'myntra',
    title: 'Install Myntra & Shop',
    subtitle: 'First order discount + coins',
    emoji: '👗',
    coins: 3000,
    channel: 'cpa',
    url: 'https://earnkaro.com/offer/myntra',
  ),
  _EarnTask(
    id: 'navi_loan',
    title: 'Apply for Navi Personal Loan',
    subtitle: 'Instant loan approval in minutes',
    emoji: '💰',
    coins: 8000,
    channel: 'cpa',
    url: 'https://earnkaro.com/offer/navi',
  ),
  // Channel C — Internal Tasks
  _EarnTask(
    id: 'first_ride',
    title: 'Book Your First Bike Taxi',
    subtitle: 'Complete a ride in Erode',
    emoji: '🏍️',
    coins: 2000,
    channel: 'internal',
    internalAction: 'bike_taxi',
    isHot: true,
  ),
  _EarnTask(
    id: 'complete_profile',
    title: 'Complete Your Profile',
    subtitle: 'Add name, photo & address',
    emoji: '👤',
    coins: 500,
    channel: 'internal',
    internalAction: 'profile',
  ),
  _EarnTask(
    id: 'nj_tech_visit',
    title: 'Visit NJ TECH Store Page',
    subtitle: 'Explore our tech accessories',
    emoji: '📱',
    coins: 300,
    channel: 'local',
    internalAction: 'tech_store',
  ),
];

// ================================================================
// MAIN SCREEN
// ================================================================
class EarnDashboardScreen extends StatefulWidget {
  const EarnDashboardScreen({super.key});
  @override
  State<EarnDashboardScreen> createState() => _EarnDashboardScreenState();
}

class _EarnDashboardScreenState extends State<EarnDashboardScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  User? _user;
  int _pendingCoins = 0;
  int _verifiedCoins = 0;
  bool _loadingCoins = true;
  final Set<String> _completedTaskIds = {};

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 2, vsync: this);
    _user = FirebaseAuth.instance.currentUser;
    _loadCoins();
    _loadCompletedTasks();
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    super.dispose();
  }

  // ── Load wallet ───────────────────────────────────────────────
  Future<void> _loadCoins() async {
    if (_user == null) {
      return;
    }
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_user!.uid)
          .get();
      if (doc.exists && mounted) {
        setState(() {
          _pendingCoins = (doc.data()?['pending_coins'] as int?) ?? 0;
          _verifiedCoins = (doc.data()?['verified_coins'] as int?) ?? 0;
          _loadingCoins = false;
        });
      } else {
        setState(() => _loadingCoins = false);
      }
    } catch (e) {
      debugPrint('Coins load error: $e');
      setState(() => _loadingCoins = false);
    }
  }

  // ── Load completed tasks ──────────────────────────────────────
  Future<void> _loadCompletedTasks() async {
    if (_user == null) {
      return;
    }
    try {
      final snap = await FirebaseFirestore.instance
          .collection('coin_transactions')
          .where('userId', isEqualTo: _user!.uid)
          .get();
      if (mounted) {
        setState(() {
          for (final doc in snap.docs) {
            final taskId = doc.data()['taskId'] as String?;
            if (taskId != null) {
              _completedTaskIds.add(taskId);
            }
          }
        });
      }
    } catch (e) {
      debugPrint('Tasks load error: $e');
    }
  }

  // ── Launch EarnKaro task with SubID ───────────────────────────
  Future<void> _launchCpaTask(_EarnTask task) async {
    if (_user == null) {
      _showSnack('Login seyyunga먼저!', _red);
      return;
    }
    if (_completedTaskIds.contains(task.id)) {
      _showSnack('Already completed! Pending coins-la irukku.', _gold);
      return;
    }

    // Inject SubID = user.uid for S2S postback matching
    final baseUrl = task.url!;
    final trackUrl = '$baseUrl?subid1=${_user!.uid}&subid2=${task.id}';
    final uri = Uri.parse(trackUrl);

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      // Record as "initiated" — Admin will verify & credit
      unawaited(_recordTaskInitiated(task));
    } else {
      _showSnack('Link open aagavillai. Try again!', _red);
    }
  }

  // ── Record task initiated (pending admin verification) ────────
  Future<void> _recordTaskInitiated(_EarnTask task) async {
    if (_user == null) {
      return;
    }
    try {
      final clearing = DateTime.now().add(const Duration(days: 32));
      await FirebaseFirestore.instance.collection('coin_transactions').add({
        'userId': _user!.uid,
        'taskId': task.id,
        'taskName': task.title,
        'coins': task.coins,
        'status': 'initiated', // Admin changes to pending/verified
        'source': task.channel,
        'subId': _user!.uid,
        'clearingDate': Timestamp.fromDate(clearing),
        'createdAt': FieldValue.serverTimestamp(),
      });
      _showSnack(
        'Task started! ${task.coins} coins pending after verification.',
        _green,
      );
    } catch (e) {
      debugPrint('Record task error: $e');
    }
  }

  // ── Internal task handler ─────────────────────────────────────
  Future<void> _handleInternalTask(_EarnTask task) async {
    if (_completedTaskIds.contains(task.id)) {
      _showSnack('Already completed!', _gold);
      return;
    }
    switch (task.internalAction) {
      case 'bike_taxi':
        Navigator.pop(context); // Go back to dashboard → tap Bike Taxi
        _showSnack('Book a ride to earn ${task.coins} coins!', _gold);
        break;
      case 'profile':
        await Navigator.pushNamed(context, '/profile');
        break;
      default:
        _showSnack('Coming soon!', _muted);
    }
  }

  void _showSnack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: Colors.white)),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ── Rupee value ───────────────────────────────────────────────
  String _toRupees(int coins) =>
      'Rs.${(coins * kCoinToRupee).toStringAsFixed(2)}';

  // ================================================================
  // BUILD
  // ================================================================
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildWalletCards(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildTaskFeed(),
                  _buildHistory(),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── HEADER ───────────────────────────────────────────────────
  Widget _buildHeader() => Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(context),
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _border),
                ),
                child: const Icon(
                  Icons.arrow_back_ios_new,
                  size: 14,
                  color: _muted,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Earn Allin1',
                  style: GoogleFonts.outfit(
                    fontSize: 17,
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'NJ Coins — 1000 Coins = Rs.10',
                  style: GoogleFonts.outfit(fontSize: 10, color: _muted),
                ),
              ],
            ),
            const Spacer(),
            // Refresh
            GestureDetector(
              onTap: () => Navigator.push(
                context,
                PageRouteBuilder<void>(
                  pageBuilder: (_, __, ___) => const RewardsHubScreen(),
                  transitionDuration: const Duration(milliseconds: 350),
                  transitionsBuilder: (_, a, __, c) => SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(1, 0),
                      end: Offset.zero,
                    ).animate(a),
                    child: c,
                  ),
                ),
              ),
              child: Container(
                width: 36,
                height: 36,
                margin: const EdgeInsets.only(right: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1500),
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(
                    color: const Color(0xFFFFBB00).withValues(alpha: 0.4),
                  ),
                ),
                child: const Center(
                  child: Text('ðŸ†', style: TextStyle(fontSize: 16)),
                ),
              ),
            ),
            GestureDetector(
              onTap: () {
                setState(() => _loadingCoins = true);
                _loadCoins();
              },
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: _card,
                  borderRadius: BorderRadius.circular(11),
                  border: Border.all(color: _border),
                ),
                child:
                    const Icon(Icons.refresh_rounded, size: 18, color: _muted),
              ),
            ),
          ],
        ),
      );

  // ── WALLET CARDS ─────────────────────────────────────────────
  Widget _buildWalletCards() => Container(
        padding: const EdgeInsets.all(16),
        color: _surface,
        child: Column(
          children: [
            Row(
              children: [
                // Pending Coins
                Expanded(
                  child: _coinCard(
                    label: 'Pending Coins',
                    coins: _pendingCoins,
                    icon: Icons.hourglass_bottom_rounded,
                    color: _orange,
                    subtitle: 'Clearing in ~30 days',
                  ),
                ),
                const SizedBox(width: 12),
                // Verified Coins
                Expanded(
                  child: _coinCard(
                    label: 'Verified Coins',
                    coins: _verifiedCoins,
                    icon: Icons.verified_rounded,
                    color: _green,
                    subtitle: '${_toRupees(_verifiedCoins)} available',
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Total earning bar
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: _gold.withValues(alpha: 0.2)),
              ),
              child: Row(
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Total NJ Coins: ${_pendingCoins + _verifiedCoins}',
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: _text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        Text(
                          '= ${_toRupees(_pendingCoins + _verifiedCoins)} total value',
                          style:
                              GoogleFonts.outfit(fontSize: 10, color: _muted),
                        ),
                      ],
                    ),
                  ),
                  // Withdraw button
                  if (_verifiedCoins >= kMinWithdrawal)
                    GestureDetector(
                      onTap: _showWithdrawDialog,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: _gold,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          'Withdraw',
                          style: GoogleFonts.outfit(
                            fontSize: 11,
                            color: Colors.black,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    )
                  else
                    Text(
                      'Need ${kMinWithdrawal - _verifiedCoins} more to withdraw',
                      style: GoogleFonts.outfit(fontSize: 9, color: _muted),
                    ),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _coinCard({
    required String label,
    required int coins,
    required IconData icon,
    required Color color,
    required String subtitle,
  }) =>
      Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withValues(alpha: 0.3)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, size: 16, color: color),
                const SizedBox(width: 6),
                Text(
                  label,
                  style: GoogleFonts.outfit(fontSize: 10, color: _muted),
                ),
              ],
            ),
            const SizedBox(height: 6),
            if (_loadingCoins)
              SizedBox(
                width: 60,
                height: 20,
                child: LinearProgressIndicator(
                  color: color,
                  backgroundColor: _card2,
                ),
              )
            else
              Text(
                '$coins',
                style: GoogleFonts.outfit(
                  fontSize: 22,
                  color: color,
                  fontWeight: FontWeight.w900,
                ),
              ),
            Text(
              subtitle,
              style: GoogleFonts.outfit(fontSize: 9, color: _muted),
            ),
          ],
        ),
      );

  // ── TAB BAR ───────────────────────────────────────────────────
  Widget _buildTabBar() => ColoredBox(
        color: _surface,
        child: TabBar(
          controller: _tabCtrl,
          indicatorColor: _gold,
          labelColor: _gold,
          unselectedLabelColor: _muted,
          labelStyle: GoogleFonts.outfit(
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
          tabs: const [
            Tab(text: '🎯  Earn Tasks'),
            Tab(text: '📋  History'),
          ],
        ),
      );

  // ── TASK FEED ─────────────────────────────────────────────────
  Widget _buildTaskFeed() => ListView(
        padding: const EdgeInsets.all(16),
        children: [
          // CPA Premium Offers section
          _sectionLabel('🏆 Premium Offers', 'EarnKaro CPA Tasks — High Coins'),
          const SizedBox(height: 10),
          ..._tasks.where((t) => t.channel == 'cpa').map(_buildTaskCard),
          const SizedBox(height: 20),
          // Internal tasks section
          _sectionLabel('⚡ Quick Tasks', 'Internal Allin1 Actions'),
          const SizedBox(height: 10),
          ..._tasks.where((t) => t.channel != 'cpa').map(_buildTaskCard),
          const SizedBox(height: 80),
        ],
      );

  Widget _sectionLabel(String title, String sub) => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              fontSize: 15,
              color: _text,
              fontWeight: FontWeight.w800,
            ),
          ),
          Text(sub, style: GoogleFonts.outfit(fontSize: 11, color: _muted)),
        ],
      );

  Widget _buildTaskCard(_EarnTask task) {
    final isDone = _completedTaskIds.contains(task.id);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: isDone ? _card2 : _card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: task.isHot && !isDone ? _gold.withValues(alpha: 0.4) : _border,
          width: task.isHot ? 1.5 : 1,
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: isDone
              ? null
              : () {
                  if (task.channel == 'cpa') {
                    _launchCpaTask(task);
                  } else {
                    _handleInternalTask(task);
                  }
                },
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                // Emoji icon
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: isDone
                        ? _card2
                        : (task.isHot
                            ? _gold.withValues(alpha: 0.1)
                            : _purple.withValues(alpha: 0.1)),
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: isDone
                          ? _border
                          : (task.isHot
                              ? _gold.withValues(alpha: 0.3)
                              : _purple.withValues(alpha: 0.3)),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      isDone ? '✅' : task.emoji,
                      style: const TextStyle(fontSize: 24),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              task.title,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                                color: isDone ? _muted : _text,
                              ),
                            ),
                          ),
                          if (task.isHot && !isDone)
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 6,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: _red.withValues(alpha: 0.15),
                                borderRadius: BorderRadius.circular(6),
                              ),
                              child: const Text(
                                'HOT',
                                style: TextStyle(
                                  fontSize: 8,
                                  color: _red,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                            ),
                        ],
                      ),
                      const SizedBox(height: 2),
                      Text(
                        task.subtitle,
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: _muted,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Text('🪙', style: TextStyle(fontSize: 12)),
                          const SizedBox(width: 4),
                          Text(
                            isDone ? 'Completed' : '+${task.coins} NJ Coins',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w700,
                              color: isDone ? _muted : _gold,
                            ),
                          ),
                          if (!isDone) ...[
                            const SizedBox(width: 8),
                            Text(
                              '= ${_toRupees(task.coins)}',
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                color: _muted,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (!isDone)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: task.isHot ? _gold : _purple,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      task.channel == 'cpa' ? 'Start' : 'Do it',
                      style: TextStyle(
                        fontSize: 11,
                        color: task.isHot ? Colors.black : Colors.white,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── HISTORY TAB ───────────────────────────────────────────────
  Widget _buildHistory() {
    if (_user == null) {
      return Center(
        child: Text(
          'Login seyyunga!',
          style: GoogleFonts.notoSansTamil(color: _muted),
        ),
      );
    }
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('coin_transactions')
          .where('userId', isEqualTo: _user!.uid)
          .orderBy('createdAt', descending: true)
          .limit(50)
          .snapshots(),
      builder: (_, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _gold));
        }
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('🪙', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 12),
                Text(
                  'No transactions yet!',
                  style: GoogleFonts.outfit(fontSize: 16, color: _text),
                ),
                Text(
                  'Complete tasks to earn NJ Coins',
                  style: GoogleFonts.outfit(fontSize: 12, color: _muted),
                ),
              ],
            ),
          );
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (_, i) {
            final d = docs[i].data()! as Map<String, dynamic>;
            final status = d['status'] as String? ?? 'pending';
            final coins = d['coins'] as int? ?? 0;
            final isVerified = status == 'verified';
            final isFailed = status == 'failed';
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isVerified
                      ? _green.withValues(alpha: 0.3)
                      : isFailed
                          ? _red.withValues(alpha: 0.3)
                          : _border,
                ),
              ),
              child: Row(
                children: [
                  Text(
                    isVerified
                        ? '✅'
                        : isFailed
                            ? '❌'
                            : '⏳',
                    style: const TextStyle(fontSize: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          d['taskName'] as String? ?? 'Task',
                          style: const TextStyle(
                            fontSize: 13,
                            color: _text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        const SizedBox(height: 2),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: isVerified
                                ? _green.withValues(alpha: 0.1)
                                : isFailed
                                    ? _red.withValues(alpha: 0.1)
                                    : _orange.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.toUpperCase(),
                            style: TextStyle(
                              fontSize: 9,
                              fontWeight: FontWeight.w800,
                              color: isVerified
                                  ? _green
                                  : isFailed
                                      ? _red
                                      : _orange,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        '+$coins',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                          color: isVerified
                              ? _green
                              : isFailed
                                  ? _muted
                                  : _orange,
                        ),
                      ),
                      Text(
                        '🪙 NJ Coins',
                        style: GoogleFonts.outfit(fontSize: 9, color: _muted),
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

  // ── WITHDRAW DIALOG ───────────────────────────────────────────
  void _showWithdrawDialog() {
    final rupees = _verifiedCoins * kCoinToRupee;
    showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _card2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: Text(
          'Withdraw NJ Coins',
          style: GoogleFonts.outfit(
            color: _text,
            fontSize: 16,
            fontWeight: FontWeight.w800,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '$_verifiedCoins Coins = Rs.${rupees.toStringAsFixed(2)}',
              style: GoogleFonts.outfit(
                fontSize: 18,
                color: _gold,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              'UPI withdrawal — Admin will process within 3-5 days.',
              style: GoogleFonts.outfit(fontSize: 11, color: _muted),
              textAlign: TextAlign.center,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: _gold,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              Navigator.pop(context);
              _requestWithdraw(rupees);
            },
            child: Text(
              'Request Withdrawal',
              style: GoogleFonts.outfit(
                color: Colors.black,
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _requestWithdraw(double rupees) async {
    if (_user == null) {
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('withdrawal_requests').add({
        'userId': _user!.uid,
        'coins': _verifiedCoins,
        'rupees': rupees,
        'status': 'pending',
        'upiId': '',
        'createdAt': FieldValue.serverTimestamp(),
      });
      _showSnack(
        'Withdrawal request submitted! Admin will process in 3-5 days.',
        _green,
      );
    } catch (e) {
      _showSnack('Request failed: $e', _red);
    }
  }
}
