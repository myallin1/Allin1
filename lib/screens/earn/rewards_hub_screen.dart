// ================================================================
// rewards_hub_screen.dart — NJ Coins Rewards Hub v3.0
// MEGA JACKPOT Edition — IDFC + AU + Kotak Live CPA
// Static UI + Real SubID url_launcher for Finance cards
// ================================================================

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

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

// ── Finance Card Model ────────────────────────────────────────
class _FinanceCard {
  final String id, emoji, bank, tagline, subtitle, coins, buttonLabel;
  final String trackingUrl; // CEO replaces with real EarnKaro URL
  final Color primaryColor, buttonTextColor;
  final List<Color> gradientColors;
  final bool isMegaJackpot, isTopPick, showKycWarning;
  const _FinanceCard({
    required this.id,
    required this.emoji,
    required this.bank,
    required this.tagline,
    required this.subtitle,
    required this.coins,
    required this.buttonLabel,
    required this.trackingUrl,
    required this.primaryColor,
    required this.gradientColors,
    this.buttonTextColor = Colors.white,
    this.isMegaJackpot = false,
    this.isTopPick = false,
    this.showKycWarning = false,
  });
}

// ── Shopping / Fun Models ─────────────────────────────────────
class _ShopOffer {
  final String emoji, store, deal, tag, discount, coins;
  final Color tagColor, cardColor;
  const _ShopOffer({
    required this.emoji,
    required this.store,
    required this.deal,
    required this.tag,
    required this.discount,
    required this.coins,
    this.tagColor = _purple,
    this.cardColor = _card,
  });
}

class _FunTask {
  final String emoji, title, desc, tag, reward, duration;
  final Color tagColor;
  const _FunTask({
    required this.emoji,
    required this.title,
    required this.desc,
    required this.tag,
    required this.reward,
    required this.duration,
    this.tagColor = _green,
  });
}

class _LocalAd {
  final String id, emoji, shop, offer, category, phone, actionUrl;
  final int? coinsReward;
  final Color color;
  const _LocalAd({
    required this.id,
    required this.emoji,
    required this.shop,
    required this.offer,
    required this.category,
    required this.phone,
    required this.actionUrl,
    required this.color,
    this.coinsReward,
  });

  factory _LocalAd.fromFirestore(String docId, Map<String, dynamic> d) =>
      _LocalAd(
        id: docId,
        emoji: d['emoji'] as String? ?? '📢',
        shop: d['shop'] as String? ?? 'Local Shop',
        offer: d['offer'] as String? ?? '',
        category: d['category'] as String? ?? 'General',
        phone: d['phone'] as String? ?? '',
        actionUrl: d['actionUrl'] as String? ?? '',
        coinsReward: (d['coinsReward'] as num?)?.toInt(),
        color: Color(d['color'] as int? ?? 0xFF6C63FF),
      );

  void trackView() {
    // Track view locally for analytics
    debugPrint('Ad viewed: $id - $shop');
  }
}

class _Earner {
  final String name, coins, avatar, city;
  final Color color;
  const _Earner({
    required this.name,
    required this.coins,
    required this.avatar,
    required this.city,
    required this.color,
  });
}

// ================================================================
// DUMMY DATA
// ================================================================

// ── Finance Cards (Live CPA — SubID injected at runtime) ──────
const _financeCards = [
  // ── CARD 1: IDFC FIRST Bank — MEGA JACKPOT ─────────────────
  _FinanceCard(
    id: 'idfc_first',
    emoji: '🏆',
    bank: 'IDFC FIRST Bank Credit Card',
    tagline: 'MEGA JACKPOT — Lifetime Free Card!',
    subtitle: 'Premium credit card with no annual fee ever. '
        '10X rewards on online spends. Instant approval!',
    coins: '20,000',
    buttonLabel: 'Claim Jackpot →',
    trackingUrl: 'https://tracking.earnkaro.com/idfc?subid1=',
    primaryColor: Color(0xFFFFBB00),
    gradientColors: [Color(0xFF2A2000), Color(0xFF1A1500), Color(0xFF0A0A12)],
    buttonTextColor: Colors.black,
    isMegaJackpot: true,
  ),

  // ── CARD 2: AU Small Finance Bank — TOP PICK ───────────────
  _FinanceCard(
    id: 'au_bank',
    emoji: '⭐',
    bank: 'AU Small Finance Bank Account',
    tagline: 'TOP PICK — Premium Zero Balance',
    subtitle: 'Earn 7% interest p.a. on savings. '
        'Unlimited free ATM withdrawals. Video KYC in 5 mins!',
    coins: '15,000',
    buttonLabel: 'Open Account →',
    trackingUrl: 'https://tracking.earnkaro.com/au?subid1=',
    primaryColor: Color(0xFFB0C4DE),
    gradientColors: [Color(0xFF1A1A2A), Color(0xFF141420), Color(0xFF0A0A12)],
    isTopPick: true,
  ),

  // ── CARD 3: Kotak 811 — existing logic + KYC warning ───────
  _FinanceCard(
    id: 'kotak_811',
    emoji: '🏦',
    bank: 'Kotak 811 Zero Balance Account',
    tagline: 'Get 1 FREE Ride Pass on completion!',
    subtitle: 'Fully digital savings account. '
        'Open in 2 mins. No minimum balance required.',
    coins: '10,000',
    buttonLabel: 'Open Account →',
    trackingUrl: 'https://tracking.earnkaro.com/kotak?subid1=',
    primaryColor: Color(0xFF004C97),
    gradientColors: [Color(0xFF001020), Color(0xFF0A121A), Color(0xFF0A0A12)],
    showKycWarning: true,
  ),
];

// ── Shopping Offers ───────────────────────────────────────────
const _shopOffers = [
  _ShopOffer(
    emoji: '👗',
    store: 'Myntra New User Offer',
    deal: 'Flat 50% off on first order. Min purchase Rs.499',
    tag: '🛍️ Women Special',
    discount: '50% OFF',
    coins: '+2,000',
    tagColor: Color(0xFFE91E8C),
    cardColor: Color(0xFF1A0F1A),
  ),
  _ShopOffer(
    emoji: '✨',
    store: 'Ajio Fashion Deal',
    deal: 'Extra 30% off on branded clothing. Use code AJIO30',
    tag: '✨ 1000 Coins Bonus',
    discount: '30% OFF',
    coins: '+1,000',
    cardColor: Color(0xFF10101A),
  ),
  _ShopOffer(
    emoji: '📱',
    store: 'Flipkart Big Billion',
    deal: 'Electronics from Rs.999. Easy EMI on all cards',
    tag: '⚡ Flash Sale',
    discount: 'Up to 80%',
    coins: '+3,000',
    tagColor: _orange,
    cardColor: Color(0xFF1A1000),
  ),
  _ShopOffer(
    emoji: '🛒',
    store: 'Amazon Fresh Grocery',
    deal: 'Free delivery on orders above Rs.299. Daily fresh produce',
    tag: '🥗 Daily Essentials',
    discount: 'FREE Delivery',
    coins: '+500',
    tagColor: _green,
    cardColor: Color(0xFF0F1A10),
  ),
];

// ── Fun Tasks ─────────────────────────────────────────────────
const _funTasks = [
  _FunTask(
    emoji: '🧩',
    title: 'Daily Puzzle Challenge',
    desc: "Solve today's word puzzle and win coins. New puzzle every 24h!",
    tag: '🎮 Hero Timepass',
    reward: '200 Coins',
    duration: '3 mins',
    tagColor: _purple,
  ),
  _FunTask(
    emoji: '📋',
    title: 'Quick Survey (2 Mins)',
    desc: 'Share your opinion on local Erode businesses. 100% anonymous!',
    tag: '🪙 Instant Coins',
    reward: '500 Coins',
    duration: '2 mins',
  ),
  _FunTask(
    emoji: '🎯',
    title: 'Spin the Wheel',
    desc: 'Spin once daily for a chance to win up to 5000 Hero Coins!',
    tag: '🎲 Lucky Draw',
    reward: 'Up to 5,000',
    duration: '30 secs',
    tagColor: _gold,
  ),
  _FunTask(
    emoji: '📸',
    title: 'Photo Contest: Best Erode Spot',
    desc: 'Upload your favourite Erode landmark photo and win big!',
    tag: '🏆 Weekly Contest',
    reward: '10,000 Coins',
    duration: '5 mins',
    tagColor: _orange,
  ),
  _FunTask(
    emoji: '🤔',
    title: 'Tech Knowledge Quiz',
    desc: '10 questions on smartphones & gadgets. Beat the leaderboard!',
    tag: '🧠 Brain Teaser',
    reward: '1,000 Coins',
    duration: '4 mins',
    tagColor: _purple,
  ),
];

// ── Local Erode Ads — now live from Firestore ads collection ──

// ── Leaderboard ───────────────────────────────────────────────
const _earners = [
  _Earner(
    name: 'Karthik R.',
    coins: '48,200',
    avatar: '👑',
    city: 'Erode West',
    color: _gold,
  ),
  _Earner(
    name: 'Priya M.',
    coins: '35,750',
    avatar: '🥈',
    city: 'Perundurai',
    color: Color(0xFFB0C4DE),
  ),
  _Earner(
    name: 'Selvam K.',
    coins: '29,100',
    avatar: '🥉',
    city: 'Bhavani',
    color: Color(0xFFCD7F32),
  ),
];

// ── Streak Data ───────────────────────────────────────────────
const _streakDays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
const _streakDone = [true, true, true, true, false, false, false];

// ================================================================
// MAIN SCREEN WIDGET
// ================================================================
class RewardsHubScreen extends StatefulWidget {
  const RewardsHubScreen({super.key});
  @override
  State<RewardsHubScreen> createState() => _RewardsHubScreenState();
}

class _RewardsHubScreenState extends State<RewardsHubScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabCtrl;
  int _carouselIdx = 0;
  Timer? _carouselTimer;

  // Task completion tracking
  Map<String, String> _taskStatuses = {};
  // Key: adId, Value: pending/approved/rejected

  @override
  void initState() {
    super.initState();
    _tabCtrl = TabController(length: 3, vsync: this);
    _carouselTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (mounted) {
        setState(
          () => _carouselIdx = _carouselIdx + 1,
        ); // mod done in StreamBuilder
      }
    });
    _loadTaskStatuses();
  }

  // Load all user task completions ONCE
  Future<void> _loadTaskStatuses() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final query = await FirebaseFirestore.instance
        .collection('task_completions')
        .where('userId', isEqualTo: uid)
        .get();

    final Map<String, String> statuses = {};
    for (final doc in query.docs) {
      final adId = doc.data()['adId'] as String;
      final status = doc.data()['status'] as String;
      statuses[adId] = status;
    }

    if (mounted) {
      setState(() => _taskStatuses = statuses);
    }
  }

  // Mark task as done
  Future<void> _markTaskDone(_LocalAd ad) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return;
    }

    final adId = ad.id;
    final docId = '${uid}_$adId';

    await FirebaseFirestore.instance
        .collection('task_completions')
        .doc(docId)
        .set({
      'userId': uid,
      'userName': FirebaseAuth.instance.currentUser?.displayName ?? '',
      'userEmail': FirebaseAuth.instance.currentUser?.email ?? '',
      'adId': adId,
      'adTitle': ad.shop,
      'actionUrl': ad.actionUrl,
      'coinsReward': ad.coinsReward ?? 50,
      'status': 'pending',
      'submittedAt': FieldValue.serverTimestamp(),
    });

    // Update pending_coins
    await FirebaseFirestore.instance.collection('users').doc(uid).set(
      {
        'pending_coins': FieldValue.increment(ad.coinsReward ?? 50),
      },
      SetOptions(merge: true),
    );

    if (mounted) {
      setState(() => _taskStatuses[adId] = 'pending');

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('🟡 Submitted! Pending approval.'),
          backgroundColor: Color(0xFFFFBB00),
        ),
      );
    }
  }

  // Status widget builder
  Widget _buildTaskStatus(_LocalAd ad, String adId) {
    final status = _taskStatuses[adId];

    if (status == 'pending') {
      return Chip(
        label: const Text('🟡 Pending Approval'),
        backgroundColor: const Color(0xFFFFBB00).withValues(alpha: 0.2),
        labelStyle: const TextStyle(
          color: Color(0xFFFFBB00),
          fontSize: 11,
        ),
      );
    } else if (status == 'approved') {
      return Chip(
        label: const Text('✅ Coins Added!'),
        backgroundColor: const Color(0xFF00C853).withValues(alpha: 0.2),
        labelStyle: const TextStyle(
          color: Color(0xFF00C853),
          fontSize: 11,
        ),
      );
    } else if (status == 'rejected') {
      return Chip(
        label: const Text('❌ Not Approved'),
        backgroundColor: const Color(0xFFFF5252).withValues(alpha: 0.2),
        labelStyle: const TextStyle(
          color: Color(0xFFFF5252),
          fontSize: 11,
        ),
      );
    }

    // No status — show button
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF00C853),
        minimumSize: const Size(double.infinity, 36),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
        ),
      ),
      icon: const Icon(
        Icons.check_circle_outline,
        size: 16,
        color: Colors.white,
      ),
      label: const Text(
        '✅ Mark as Done',
        style: TextStyle(
          color: Colors.white,
          fontSize: 12,
        ),
      ),
      onPressed: () => _markTaskDone(ad),
    );
  }

  @override
  void dispose() {
    _tabCtrl.dispose();
    _carouselTimer?.cancel();
    super.dispose();
  }

  // ── SubID URL Launcher — used by all finance cards ────────
  Future<void> _launchFinanceOffer(_FinanceCard card) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      _snack('Login seyyunga! Sign in to track your reward.', _red);
      return;
    }
    // Append uid as subid1 param — CEO replaces base URL with real link
    final trackingUrl = '${card.trackingUrl}$uid&subid2=${card.id}';
    final uri = Uri.parse(trackingUrl);
    debugPrint('Launching ${card.bank} for uid=$uid');
    debugPrint('URL: $trackingUrl');

    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (mounted) {
        _snack(
          '${card.bank} opened! Complete all steps to earn ${card.coins} coins.',
          card.primaryColor,
        );
      }
    } else {
      if (mounted) {
        _snack('Browser open aagavillai. Try again!', _red);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: NestedScrollView(
        headerSliverBuilder: (_, __) => [_buildSliverHeader()],
        body: Column(
          children: [
            _buildStreakAndLeaderboard(),
            _buildTabBar(),
            Expanded(
              child: TabBarView(
                controller: _tabCtrl,
                children: [
                  _buildTabWithAds(_buildFinanceTab()),
                  _buildTabWithAds(_buildShoppingTab()),
                  _buildTabWithAds(_buildFunTab()),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Tab wrapper with Local Ads at bottom ─────────────────
  Widget _buildTabWithAds(Widget tab) => Column(
        children: [
          Expanded(child: tab),
          _buildLocalAdsCarousel(),
        ],
      );

  // ── SLIVER APP BAR ────────────────────────────────────────
  Widget _buildSliverHeader() {
    return SliverAppBar(
      pinned: true,
      expandedHeight: 120,
      backgroundColor: _surface,
      leading: GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Container(
          margin: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: _border),
          ),
          child: const Icon(Icons.arrow_back_ios_new, size: 14, color: _muted),
        ),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFF1A1500), Color(0xFF0A0A12)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          padding: const EdgeInsets.fromLTRB(16, 48, 16, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.end,
            children: [
              Row(
                children: [
                  const Text('🪙', style: TextStyle(fontSize: 22)),
                  const SizedBox(width: 8),
                  Text(
                    'NJ Coins Rewards Hub',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      color: _text,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -0.3,
                    ),
                  ),
                  const Spacer(),
                  _balanceChip(
                    'Pending',
                    '5,000',
                    _orange,
                    const Color(0xFF1A0F00),
                  ),
                  const SizedBox(width: 8),
                  _balanceChip(
                    'Verified',
                    '12,000',
                    _green,
                    const Color(0xFF001A0A),
                  ),
                ],
              ),
              const SizedBox(height: 6),
              Text(
                '1000 Coins = Rs.10  •  Erode Super App',
                style: GoogleFonts.outfit(fontSize: 10, color: _muted),
              ),
            ],
          ),
        ),
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(1),
        child: Container(
          height: 1,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [
                _gold.withValues(alpha: 0),
                _gold.withValues(alpha: 0.5),
                _gold.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _balanceChip(String label, String val, Color color, Color bg) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.4)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 5),
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8,
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                Text(
                  val,
                  style: TextStyle(
                    fontSize: 11,
                    color: color,
                    fontWeight: FontWeight.w900,
                  ),
                ),
              ],
            ),
          ],
        ),
      );

  // ── STREAK + LEADERBOARD ──────────────────────────────────
  Widget _buildStreakAndLeaderboard() => Container(
        color: _surface,
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            _buildStreak(),
            const SizedBox(height: 12),
            _buildLeaderboard(),
          ],
        ),
      );

  Widget _buildStreak() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _gold.withValues(alpha: 0.25)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Text('🔥', style: TextStyle(fontSize: 16)),
                const SizedBox(width: 6),
                Text(
                  'Daily Check-in Streak',
                  style: GoogleFonts.outfit(
                    fontSize: 13,
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _gold.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    '4 Day Streak! 🎯',
                    style: GoogleFonts.outfit(
                      fontSize: 9,
                      color: _gold,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: List.generate(7, (i) {
                final done = _streakDone[i];
                final isToday = i == 4;
                return Expanded(
                  child: Column(
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 34,
                        height: 34,
                        decoration: BoxDecoration(
                          color: done
                              ? _gold
                              : isToday
                                  ? _gold.withValues(alpha: 0.15)
                                  : _card2,
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: done
                                ? _gold
                                : isToday
                                    ? _gold.withValues(alpha: 0.5)
                                    : _border,
                            width: isToday ? 2 : 1,
                          ),
                          boxShadow: done
                              ? [
                                  BoxShadow(
                                    color: _gold.withValues(alpha: 0.4),
                                    blurRadius: 8,
                                  ),
                                ]
                              : null,
                        ),
                        child: Center(
                          child: done
                              ? const Text(
                                  '✓',
                                  style: TextStyle(
                                    fontSize: 14,
                                    color: Colors.black,
                                    fontWeight: FontWeight.w900,
                                  ),
                                )
                              : Text(
                                  isToday ? '●' : '',
                                  style: TextStyle(
                                    fontSize: 8,
                                    color: _gold.withValues(alpha: 0.8),
                                  ),
                                ),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        _streakDays[i],
                        style: TextStyle(
                          fontSize: 9,
                          color: done ? _gold : _muted,
                          fontWeight: done ? FontWeight.w700 : FontWeight.w400,
                        ),
                      ),
                    ],
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: const LinearProgressIndicator(
                value: 4 / 7,
                backgroundColor: _card2,
                valueColor: AlwaysStoppedAnimation<Color>(_gold),
                minHeight: 4,
              ),
            ),
            const SizedBox(height: 5),
            Text(
              '3 more days for 7-day bonus: +2,000 Coins! 🏆',
              style: GoogleFonts.outfit(fontSize: 9, color: _muted),
            ),
          ],
        ),
      );

  Widget _buildLeaderboard() => Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _purple.withValues(alpha: 0.2)),
        ),
        child: Column(
          children: [
            Row(
              children: [
                const Text('🏆', style: TextStyle(fontSize: 14)),
                const SizedBox(width: 6),
                Text(
                  'Erode Top Earners This Week',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: _text,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const Spacer(),
                Text(
                  'Your Rank: #47',
                  style: GoogleFonts.outfit(
                    fontSize: 9,
                    color: _muted,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: _earners
                  .map(
                    (e) => Expanded(
                      child: Container(
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        decoration: BoxDecoration(
                          color: e.color.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: e.color.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Column(
                          children: [
                            Text(
                              e.avatar,
                              style: const TextStyle(fontSize: 22),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              e.name,
                              style: GoogleFonts.outfit(
                                fontSize: 10,
                                color: _text,
                                fontWeight: FontWeight.w700,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                            ),
                            Text(
                              e.city,
                              style: GoogleFonts.outfit(
                                fontSize: 8,
                                color: _muted,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              '🪙 ${e.coins}',
                              style: TextStyle(
                                fontSize: 10,
                                color: e.color,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  )
                  .toList(),
            ),
          ],
        ),
      );

  // ── TAB BAR ───────────────────────────────────────────────
  Widget _buildTabBar() => ColoredBox(
        color: _surface,
        child: TabBar(
          controller: _tabCtrl,
          indicatorColor: _gold,
          indicatorWeight: 3,
          labelColor: _gold,
          unselectedLabelColor: _muted,
          labelStyle:
              GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w700),
          unselectedLabelStyle:
              GoogleFonts.outfit(fontSize: 12, fontWeight: FontWeight.w500),
          tabs: const [
            Tab(text: '💰 Finance'),
            Tab(text: '🛍️ Shopping'),
            Tab(text: '🎮 Fun & Games'),
          ],
        ),
      );

  // ================================================================
  // TAB 1 — FINANCE (3 Live CPA Cards)
  // ================================================================
  Widget _buildFinanceTab() => ListView(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
        children: [
          // Section header
          Row(
            children: [
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '💰 Premium Finance Offers',
                    style: GoogleFonts.outfit(
                      fontSize: 15,
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    'Real EarnKaro tasks — Your UID auto-tracked',
                    style: GoogleFonts.outfit(fontSize: 10, color: _muted),
                  ),
                ],
              ),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: _green.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _green.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 5,
                      height: 5,
                      decoration: const BoxDecoration(
                        color: _green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      'LIVE',
                      style: GoogleFonts.outfit(
                        fontSize: 8,
                        color: _green,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // 3 Finance Cards
          ..._financeCards.asMap().entries.map(
                (e) => _buildFinanceCard(e.value, e.key),
              ),
          const SizedBox(height: 8),
        ],
      );

  Widget _buildFinanceCard(_FinanceCard c, int idx) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: c.gradientColors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(
          color: c.primaryColor.withValues(
            alpha: c.isMegaJackpot
                ? 0.7
                : c.isTopPick
                    ? 0.4
                    : 0.3,
          ),
          width: c.isMegaJackpot ? 2.0 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: c.primaryColor.withValues(
              alpha: c.isMegaJackpot ? 0.25 : 0.1,
            ),
            blurRadius: c.isMegaJackpot ? 24 : 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── MEGA JACKPOT crown banner ─────────────────────
            if (c.isMegaJackpot) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(vertical: 6),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      _gold.withValues(alpha: 0),
                      _gold.withValues(alpha: 0.15),
                      _gold.withValues(alpha: 0),
                    ],
                  ),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: _gold.withValues(alpha: 0.3)),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Text('👑', style: TextStyle(fontSize: 14)),
                    const SizedBox(width: 6),
                    Text(
                      'MEGA JACKPOT — HIGHEST PAYOUT TODAY',
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        color: _gold,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.8,
                      ),
                    ),
                    const SizedBox(width: 6),
                    const Text('👑', style: TextStyle(fontSize: 14)),
                  ],
                ),
              ),
            ],

            // ── TOP PICK banner ───────────────────────────────
            if (c.isTopPick) ...[
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                margin: const EdgeInsets.only(bottom: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFB0C4DE).withValues(alpha: 0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: const Color(0xFFB0C4DE).withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('🔥', style: TextStyle(fontSize: 11)),
                    const SizedBox(width: 5),
                    Text(
                      'TOP PICK — #2 Highest Paying',
                      style: GoogleFonts.outfit(
                        fontSize: 9,
                        color: const Color(0xFFB0C4DE),
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
            ],

            // ── Main content row ──────────────────────────────
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Bank icon
                Container(
                  width: 60,
                  height: 60,
                  decoration: BoxDecoration(
                    color: c.primaryColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(
                      color: c.primaryColor.withValues(alpha: 0.35),
                    ),
                  ),
                  child: Center(
                    child: Text(
                      c.emoji,
                      style: const TextStyle(fontSize: 28),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        c.bank,
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          color: _text,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        c.tagline,
                        style: TextStyle(
                          fontSize: 11,
                          color: c.primaryColor,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        c.subtitle,
                        style: GoogleFonts.notoSansTamil(
                          fontSize: 10,
                          color: _muted,
                          height: 1.4,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),

                      // ── KYC Warning (Kotak only) ──────────────────
                      if (c.showKycWarning) ...[
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: const Color(0xFF2A1500),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                              color: _orange.withValues(alpha: 0.5),
                              width: 1.2,
                            ),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('⚠️', style: TextStyle(fontSize: 11)),
                              const SizedBox(width: 5),
                              Expanded(
                                child: Text(
                                  'Aadhaar + PAN Video KYC mandatory to get '
                                  '1 Free Ride Pass. Just installing the app '
                                  'will NOT give rewards.',
                                  style: GoogleFonts.notoSansTamil(
                                    fontSize: 9,
                                    color: _orange,
                                    fontStyle: FontStyle.italic,
                                    height: 1.45,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 14),

            // ── Bottom row: Coins + Button ────────────────────
            Row(
              children: [
                // Coins badge
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: _gold.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _gold.withValues(alpha: 0.3)),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🪙', style: TextStyle(fontSize: 14)),
                      const SizedBox(width: 5),
                      Text(
                        '+${c.coins}',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          color: _gold,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ],
                  ),
                ),
                const Spacer(),
                // Launch button
                GestureDetector(
                  onTap: () => _launchFinanceOffer(c),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 18,
                      vertical: 10,
                    ),
                    decoration: BoxDecoration(
                      color: c.primaryColor,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                          color: c.primaryColor.withValues(alpha: 0.45),
                          blurRadius: 12,
                          offset: const Offset(0, 4),
                        ),
                      ],
                    ),
                    child: Text(
                      c.buttonLabel,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: c.buttonTextColor,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                ),
              ],
            ),

            // ── SubID tracking note ───────────────────────────
            const SizedBox(height: 8),
            Row(
              children: [
                Container(
                  width: 5,
                  height: 5,
                  decoration: const BoxDecoration(
                    color: _green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 5),
                Text(
                  'Your UID auto-tracked via Sub-ID for coin credit',
                  style: GoogleFonts.outfit(
                    fontSize: 8,
                    color: _green.withValues(alpha: 0.6),
                    fontStyle: FontStyle.italic,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  // ================================================================
  // TAB 2 — SHOPPING (2-col GridView)
  // ================================================================
  Widget _buildShoppingTab() => GridView.builder(
        padding: const EdgeInsets.all(14),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          childAspectRatio: 0.70,
        ),
        itemCount: _shopOffers.length,
        itemBuilder: (_, i) => _buildShopCard(_shopOffers[i]),
      );

  Widget _buildShopCard(_ShopOffer s) => DecoratedBox(
        decoration: BoxDecoration(
          color: s.cardColor,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: s.tagColor.withValues(alpha: 0.25)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Image placeholder
            Container(
              height: 88,
              decoration: BoxDecoration(
                borderRadius:
                    const BorderRadius.vertical(top: Radius.circular(18)),
                gradient: LinearGradient(
                  colors: [
                    s.tagColor.withValues(alpha: 0.2),
                    s.tagColor.withValues(alpha: 0.05),
                  ],
                ),
              ),
              child: Stack(
                children: [
                  Center(
                    child: Text(s.emoji, style: const TextStyle(fontSize: 38)),
                  ),
                  Positioned(
                    top: 8,
                    right: 8,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 3,
                      ),
                      decoration: BoxDecoration(
                        color: s.tagColor,
                        borderRadius: BorderRadius.circular(7),
                      ),
                      child: Text(
                        s.discount,
                        style: const TextStyle(
                          fontSize: 9,
                          color: Colors.black,
                          fontWeight: FontWeight.w900,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    s.store,
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    s.deal,
                    style: GoogleFonts.outfit(
                      fontSize: 9,
                      color: _muted,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                    decoration: BoxDecoration(
                      color: s.tagColor.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                      border:
                          Border.all(color: s.tagColor.withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      s.tag,
                      style: TextStyle(
                        fontSize: 8,
                        color: s.tagColor,
                        fontWeight: FontWeight.w700,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Text(
                        '🪙 ${s.coins}',
                        style: GoogleFonts.outfit(
                          fontSize: 10,
                          color: _gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const Spacer(),
                      GestureDetector(
                        onTap: () =>
                            _snack('${s.store} — Coming soon! 🚀', _purple),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 9,
                            vertical: 5,
                          ),
                          decoration: BoxDecoration(
                            color: s.tagColor,
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Text(
                            'Shop →',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.black,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ================================================================
  // TAB 3 — FUN & GAMES + Paytm Scratchcards + Gift Cards + Quiz
  // ================================================================
  Widget _buildFunTab() => ListView(
        padding: const EdgeInsets.all(14),
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '🎮 Quick Wins',
                  style: GoogleFonts.outfit(
                    fontSize: 15,
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                Text(
                  'Fast coins while waiting for rides',
                  style: GoogleFonts.outfit(fontSize: 10, color: _muted),
                ),
              ],
            ),
          ),
          ..._funTasks.map(_buildFunCard),
          const SizedBox(height: 24),
          _rewardsSectionHeader(
            '🪙 Paytm Scratchcards',
            'Win real cashback every day!',
            _gold,
          ),
          const SizedBox(height: 10),
          _buildPaytmScratchSection(),
          const SizedBox(height: 24),
          _rewardsSectionHeader(
            '🎁 Accessories Gift Cards',
            'Exclusive NJ Tech goodies & vouchers',
            _purple,
          ),
          const SizedBox(height: 10),
          _buildAccessoriesGiftSection(),
          const SizedBox(height: 24),
          _rewardsSectionHeader(
            '🧠 30-Days Quiz Challenge',
            'Answer daily — climb the leaderboard!',
            _orange,
          ),
          const SizedBox(height: 10),
          _buildQuizSection(),
          const SizedBox(height: 20),
        ],
      );

  Widget _buildFunCard(_FunTask t) => Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: t.tagColor.withValues(alpha: 0.2)),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                color: t.tagColor.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: t.tagColor.withValues(alpha: 0.3)),
              ),
              child: Center(
                child: Text(
                  t.emoji,
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
                          t.title,
                          style: GoogleFonts.outfit(
                            fontSize: 13,
                            color: _text,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: _card2,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '⏱ ${t.duration}',
                          style: GoogleFonts.outfit(fontSize: 8, color: _muted),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(
                    t.desc,
                    style: GoogleFonts.notoSansTamil(
                      fontSize: 10,
                      color: _muted,
                      height: 1.3,
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 7),
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 3,
                        ),
                        decoration: BoxDecoration(
                          color: t.tagColor.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: t.tagColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Text(
                          t.tag,
                          style: TextStyle(
                            fontSize: 8,
                            color: t.tagColor,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '🪙 ${t.reward}',
                        style: GoogleFonts.outfit(
                          fontSize: 11,
                          color: _gold,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(width: 8),
                      GestureDetector(
                        onTap: () =>
                            _snack('${t.title} — Coming soon!', t.tagColor),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: t.tagColor,
                            borderRadius: BorderRadius.circular(10),
                            boxShadow: [
                              BoxShadow(
                                color: t.tagColor.withValues(alpha: 0.3),
                                blurRadius: 6,
                                offset: const Offset(0, 2),
                              ),
                            ],
                          ),
                          child: Text(
                            'Play',
                            style: GoogleFonts.outfit(
                              fontSize: 11,
                              color: Colors.black,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      );

  // ================================================================
  // LOCAL ADS CAROUSEL — Live from Firestore ads collection
  // ================================================================
  Widget _buildLocalAdsCarousel() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('ads')
          .where('isActive', isEqualTo: true)
          .orderBy('createdAt', descending: true)
          .limit(10)
          .snapshots(),
      builder: (context, snap) {
        // Loading
        if (snap.connectionState == ConnectionState.waiting) {
          return Container(
            height: 80,
            margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _border),
            ),
            child: const Center(
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
              ),
            ),
          );
        }
        // No ads — hide gracefully
        final docs = snap.data?.docs ?? [];
        if (docs.isEmpty) return const SizedBox.shrink();

        final ads = docs
            .map(
              (d) => _LocalAd.fromFirestore(
                d.id,
                d.data()! as Map<String, dynamic>,
              ),
            )
            .toList();
        final idx = _carouselIdx % ads.length;
        final ad = ads[idx];

        // Track view — fire once per carousel change, non-blocking
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ad.trackView();
        });
        WidgetsBinding.instance.addPostFrameCallback((_) {
          docs[idx]
              .reference
              .update({'views': FieldValue.increment(1)}).catchError((_) {});
        });
        return Container(
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    '📍 Erode Flash Ads',
                    style: GoogleFonts.outfit(
                      fontSize: 13,
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const Spacer(),
                  Text(
                    'Local deals near you',
                    style: GoogleFonts.outfit(
                      fontSize: 9,
                      color: _muted,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 500),
                transitionBuilder: (child, anim) => FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween<Offset>(
                      begin: const Offset(0.08, 0),
                      end: Offset.zero,
                    ).animate(anim),
                    child: child,
                  ),
                ),
                child: GestureDetector(
                  onTap: () async {
                    if (ad.actionUrl.isNotEmpty) {
                      final uri = Uri.parse(ad.actionUrl);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(
                          uri,
                          mode: LaunchMode.externalApplication,
                        );
                      }
                    }
                  },
                  child: Container(
                    key: ValueKey(_carouselIdx),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [
                          ad.color.withValues(alpha: 0.12),
                          _card,
                        ],
                      ),
                      borderRadius: BorderRadius.circular(18),
                      border: Border.all(
                        color: ad.color.withValues(alpha: 0.4),
                        width: 1.5,
                      ),
                    ),
                    child: Row(
                      children: [
                        // Shop icon
                        Container(
                          width: 58,
                          height: 58,
                          decoration: BoxDecoration(
                            color: ad.color.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: ad.color.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Center(
                            child: Text(
                              ad.emoji,
                              style: const TextStyle(fontSize: 28),
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
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 6,
                                      vertical: 2,
                                    ),
                                    decoration: BoxDecoration(
                                      color: ad.color.withValues(alpha: 0.15),
                                      borderRadius: BorderRadius.circular(5),
                                    ),
                                    child: Text(
                                      ad.category,
                                      style: TextStyle(
                                        fontSize: 8,
                                        color: ad.color,
                                        fontWeight: FontWeight.w800,
                                      ),
                                    ),
                                  ),
                                  const Spacer(),
                                  // Carousel dots
                                  Row(
                                    children: List.generate(
                                      ads.length,
                                      (i) => AnimatedContainer(
                                        duration:
                                            const Duration(milliseconds: 300),
                                        width: i == _carouselIdx ? 14 : 5,
                                        height: 5,
                                        margin: const EdgeInsets.only(left: 3),
                                        decoration: BoxDecoration(
                                          color: i == _carouselIdx
                                              ? ad.color
                                              : _card2,
                                          borderRadius:
                                              BorderRadius.circular(3),
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ad.shop,
                                style: GoogleFonts.outfit(
                                  fontSize: 14,
                                  color: _text,
                                  fontWeight: FontWeight.w800,
                                ),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                ad.offer,
                                style: GoogleFonts.notoSansTamil(
                                  fontSize: 10,
                                  color: _muted,
                                  height: 1.3,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              GestureDetector(
                                onTap: () async {
                                  // Track click — increment Firestore ads/{id}.clicks
                                  try {
                                    final docRef = docs[idx].reference;
                                    await FirebaseFirestore.instance
                                        .runTransaction((txn) async {
                                      final s = await txn.get(docRef);
                                      txn.update(docRef, {
                                        'clicks': ((s.data() as Map<String,
                                                        dynamic>?)?['clicks']
                                                    as int? ??
                                                0) +
                                            1,
                                      });
                                    });
                                  } catch (_) {}
                                  // Launch phone call
                                  if (ad.phone.isNotEmpty) {
                                    final uri = Uri.parse('tel:${ad.phone}');
                                    if (await canLaunchUrl(uri)) {
                                      await launchUrl(uri);
                                    }
                                  }
                                },
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 6,
                                  ),
                                  decoration: BoxDecoration(
                                    color: ad.color,
                                    borderRadius: BorderRadius.circular(9),
                                    boxShadow: [
                                      BoxShadow(
                                        color: ad.color.withValues(alpha: 0.3),
                                        blurRadius: 8,
                                        offset: const Offset(0, 3),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(
                                        Icons.phone,
                                        size: 12,
                                        color: Colors.white,
                                      ),
                                      const SizedBox(width: 4),
                                      Text(
                                        'Call Now',
                                        style: GoogleFonts.outfit(
                                          fontSize: 11,
                                          color: Colors.white,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                              const SizedBox(height: 8),
                              // Task completion status/button
                              _buildTaskStatus(ad, docs[idx].id),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      }, // close builder
    ); // close StreamBuilder
  } // end _buildLocalAdsCarousel

  // ── Helper snackbar ───────────────────────────────────────
  void _snack(String msg, Color color) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          msg,
          style: GoogleFonts.notoSansTamil(
            color: Colors.white,
            fontSize: 12,
          ),
        ),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // ================================================================
  // SECTION HELPERS — Paytm / Gift Cards / Quiz
  // ================================================================

  Widget _rewardsSectionHeader(String title, String sub, Color color) => Column(
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
          Text(sub, style: GoogleFonts.outfit(fontSize: 10, color: _muted)),
        ],
      );

  // ── Paytm Scratch Cards ──────────────────────────────────────
  Widget _buildPaytmScratchSection() {
    const cards = [
      ('₹10 Cashback', '🪙', 'Scratch & Win', _gold),
      ('₹25 Cashback', '💰', 'Limited Today', _green),
      ('₹50 Cashback', '🎰', 'Lucky Draw', _orange),
    ];
    return Row(
      children: cards.map((c) {
        final (amount, emoji, tag, col) = c;
        return Expanded(
          child: GestureDetector(
            onTap: () =>
                _snack('Open Paytm app to scratch your $amount card!', col),
            child: Container(
              margin: const EdgeInsets.only(right: 8),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: col.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: col.withValues(alpha: 0.35)),
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(emoji, style: const TextStyle(fontSize: 28)),
                  const SizedBox(height: 6),
                  Text(
                    amount,
                    style: GoogleFonts.outfit(
                      color: col,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                    decoration: BoxDecoration(
                      color: col.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      tag,
                      style: TextStyle(
                        color: col,
                        fontSize: 8,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Accessories Gift Cards ────────────────────────────────────
  Widget _buildAccessoriesGiftSection() {
    const items = [
      ('🎧', 'Earphones', '₹199 Gift Card', Color(0xFF6C63FF)),
      ('📱', 'Phone Case', '₹99 Gift Card', Color(0xFF00C853)),
      ('🔋', 'Power Bank', '₹299 Gift Card', Color(0xFFFF4FA3)),
      ('💡', 'Smart Bulb', '₹149 Gift Card', Color(0xFFFF8A00)),
    ];
    return GridView.count(
      crossAxisCount: 2,
      crossAxisSpacing: 10,
      mainAxisSpacing: 10,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      childAspectRatio: 2.8,
      children: items.map((item) {
        final (emoji, name, card, col) = item;
        return GestureDetector(
          onTap: () =>
              _snack('$name gift card coming soon! Stay tuned 🎁', col),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: col.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: col.withValues(alpha: 0.3)),
            ),
            child: Row(
              children: [
                Text(emoji, style: const TextStyle(fontSize: 22)),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      Text(
                        card,
                        style: TextStyle(
                          color: col,
                          fontSize: 9,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── 30-Days Quiz Section ─────────────────────────────────────
  Widget _buildQuizSection() {
    const quizzes = [
      ('Day 1–7', '🟢', 'Beginner Round', '50 Coins/day', Color(0xFF00C853)),
      ('Day 8–20', '🟡', 'Intermediate', '100 Coins/day', Color(0xFFFFBB00)),
      ('Day 21–30', '🔴', 'Expert Level', '200 Coins/day', Color(0xFFFF5252)),
    ];
    return Column(
      children: quizzes.map((q) {
        final (days, dot, level, reward, col) = q;
        return Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: col.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: col.withValues(alpha: 0.3)),
          ),
          child: Row(
            children: [
              Text(dot, style: const TextStyle(fontSize: 18)),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      level,
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    Text(
                      days,
                      style: const TextStyle(color: _muted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    '🪙 $reward',
                    style: GoogleFonts.outfit(
                      color: col,
                      fontSize: 11,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  GestureDetector(
                    onTap: () => _snack('Quiz for $level starts soon! 🧠', col),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 5,
                      ),
                      decoration: BoxDecoration(
                        color: col,
                        borderRadius: BorderRadius.circular(8),
                        boxShadow: [
                          BoxShadow(
                            color: col.withValues(alpha: 0.35),
                            blurRadius: 6,
                          ),
                        ],
                      ),
                      child: Text(
                        'Play Now',
                        style: GoogleFonts.outfit(
                          color: Colors.black,
                          fontSize: 10,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      }).toList(),
    );
  }
}
