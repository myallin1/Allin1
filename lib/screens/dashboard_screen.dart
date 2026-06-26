// ================================================================
// dashboard_screen.dart — Allin1 Super App Customer Dashboard
// Premium Pink UI — Rebuilt from CEO QA Screenshots — May 2026
// Patches: stream lift, optimistic wallet, cache layer, error feedback
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:scratcher/scratcher.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../services/pwa_cache_platform_web.dart';

import '../widgets/banner_slider.dart';
import 'bike_taxi/bike_booking_screen.dart';
import 'store_layout_screen.dart';
import 'car_wash_screen.dart';
import 'coming_soon_screen.dart';
import 'construction_screen.dart';
import 'custom_order_screen.dart';
import 'guru_chat_screen.dart';
import 'nj_tech_service_screen.dart';
import 'nj_tech_store_screen.dart';
import 'notifications_screen.dart';
import 'play_zone_screen.dart';
import 'profile_screen.dart';
import 'rewards_screen.dart';
import '../widgets/promo_overlay.dart';
import 'ride_history_screen.dart';
import 'settings_screen.dart';
import 'sos_screen.dart';
import '../services/local_sync_service.dart';
import '../services/hive_cache.dart';
import '../services/prefs_cache.dart';

// ── Brand Colors ─────────────────────────────────────────────────
const Color kPink     = Color(0xFFFF4FA3);
const Color kPinkDark = Color(0xFFBE2A7A);
const Color kPinkBg   = Color(0xFFFFF0F7);
const Color kBg       = Color(0xFFFFFFFF);
const Color kSurface  = Color(0xFFF8F8FF);
const Color kNJDark   = Color(0xFF130B28);
const Color kNJDark2  = Color(0xFF2A1060);
const Color kText     = Color(0xFF1A1A2E);
const Color kMuted    = Color(0xFF9999BB);
const Color kGreen    = Color(0xFF00C853);
const Color kTeal     = Color(0xFF00BFA5);
const Color kBlue     = Color(0xFF1565C0);
const Color kGold     = Color(0xFFFFBB00);
const Color kPurple   = Color(0xFF7B6FE0);
const Color kBorder   = Color(0xFFEEEEF5);
const Color kRed      = Color(0xFFFF5252);

// ── Service Tile Model ───────────────────────────────────────────
class _Tile {
  final String id, title, subtitle, emoji, badge;
  final Color color;
  final bool isLive;
  const _Tile({
    required this.id, required this.title, required this.subtitle,
    required this.emoji, required this.badge, required this.color,
    this.isLive = false,
  });
}

const _tiles = [
  _Tile(id:'taxi',        title:'Taxi',                    subtitle:'Fast rides in Erode',
        emoji:'🚕', badge:'LIVE', color:kTeal,   isLive:true),
  _Tile(id:'broadband',   title:'Broadband / WiFi',        subtitle:'Manage your internet service',
        emoji:'📶', badge:'LIVE', color:kBlue,   isLive:true),
  // Food Delivery — hidden until ready
  // _Tile(id:'food', title:'Food Delivery', subtitle:'16th Road specials', emoji:'🍔', badge:'', color:kPink),
  // Grocery — hidden until ready
  // _Tile(id:'grocery', title:'Grocery', subtitle:'Fresh and fast', emoji:'🛒', badge:'', color:kGreen),
  _Tile(id:'njtech',      title:'NJ Tech Store',           subtitle:'Mobile · Spares · Repairs',
        emoji:'🔋', badge:'NJ TECH', color:kPink),
  _Tile(id:'carwash',     title:'Car Service & Water Wash',subtitle:'',
        emoji:'🚗', badge:'',     color:kBlue),
  _Tile(id:'puncture',    title:'Mobile Puncture',         subtitle:'Fast puncture repair',
        emoji:'🛵', badge:'',     color:kPink),
  _Tile(id:'construction',title:'Constructions',           subtitle:'Usha Constructions',
        emoji:'🏗️', badge:'',    color:kGold),
  _Tile(id:'custom',      title:'Custom Order',            subtitle:'Call us for any order',
        emoji:'📦', badge:'Soon', color:kPurple),
];

// ── NJ Tech Quick-Service Icons ──────────────────────────────────
const _njServices = [
  {'icon': '📱', 'label': 'Mobile\nService',  'id': 'mobile'},
  {'icon': '🔧', 'label': 'Spare\nParts',     'id': 'spares'},
  // ✅ Updated to use local asset GIF
  {'icon': 'assets/images/assistant.gif', 'label': 'AI Bots', 'id': 'aibots'},
  {'icon': '📶', 'label': 'Broadband',         'id': 'broadband'},
  {'icon': '🛠️', 'label': 'Repairs',          'id': 'repairs'},
  {'icon': '🚚', 'label': 'Delivery',          'id': 'delivery'},
];

// ================================================================
// DASHBOARD SCREEN — Main Entry
// ================================================================
class DashboardScreen extends StatefulWidget {
  const DashboardScreen({super.key});
  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen> {
  int _navIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _user = FirebaseAuth.instance.currentUser;

  // ── Classic Rewards promo state ──────────────────────────────
  List<PromoOfferItem> _promoOffers = const [
    PromoOfferItem(
      id: 'quiz',    title: 'Daily Quiz Reward',
      subtitle: 'Answer 5 questions · Win Free Tempered Glass!',
      icon: Icons.quiz_rounded,     claimed: false,
      buttonLabel: 'Play Quiz',     statusLabel: 'Today Only',
    ),
    PromoOfferItem(
      id: 'refer',   title: '₹50 Referral Bonus',
      subtitle: 'Refer a friend · Both get ₹50 wallet cash',
      icon: Icons.person_add_rounded, claimed: false,
      buttonLabel: 'Refer Now',     statusLabel: 'Unlimited',
    ),
    PromoOfferItem(
      id: 'firstride', title: 'First Ride FREE 🛵',
      subtitle: 'New user? Your first taxi ride is on us!',
      icon: Icons.electric_bike_rounded, claimed: false,
      buttonLabel: 'Book Now',      statusLabel: 'New Users',
    ),
  ];

  bool _updateAvailable = true; // Set to true to test the glow.

  Future<void> _claimPromo(String offerId) async {
    setState(() {
      _promoOffers = _promoOffers.map((p) =>
        p.id == offerId ? PromoOfferItem(
          id: p.id, title: p.title, subtitle: p.subtitle,
          icon: p.icon, claimed: true,
          buttonLabel: p.buttonLabel,
          claimedButtonLabel: p.claimedButtonLabel,
          statusLabel: 'Claimed ✓',
        ) : p,
      ).toList();
    });
  }

  @override
  void initState() {
    super.initState();
    unawaited(_silentBackupIfNeeded());
  }

  Future<void> _silentBackupIfNeeded() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      final lastBackupStr = HiveCache.get('lastCoinsBackupDate') as String?;
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

      final currentCoins = (HiveCache.get(HiveCache.kWalletBalance) as num?)?.toDouble() ?? 0.0;

      await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .set({
            'njCoinsBackup': currentCoins,
            'lastCoinsBackupAt': FieldValue.serverTimestamp(),
          }, SetOptions(merge: true));

      HiveCache.put('lastCoinsBackupDate', now.toIso8601String());

      debugPrint('[Dashboard] Silent backup completed: ${currentCoins.toStringAsFixed(0)} coins');
    } catch (e) {
      debugPrint('[Dashboard] Silent backup failed: $e');
    }
  }

  // ── Tab switch — saves last tab to PrefsCache ────────────────
  void _goTab(int i) {
    setState(() => _navIndex = i);
    PrefsCache.saveLastTab(i);
  }

  void _navigate(Widget screen) => Navigator.push<void>(
    context, MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _launchBroadband() async {
    _navigate(const NjTechBroadbandWebView());
  }

  // ── Scratch Card gifts pool ─────────────────────────────────
  static const _scratchGifts = [
    ('🎉', '₹50 Wallet Cash', 'Credited to your NJ Wallet!'),
    ('🛵', 'Free Taxi Ride', 'One free bike ride — use today!'),
    ('🏅', '500 NJ Coins', 'Coins added to your account!'),
    ('🎁', '10% Off Next Order', 'Valid on any custom order!'),
    ('☕', 'Free Coffee Voucher', 'Redeem at partner cafes!'),
    ('📦', 'Mystery Box', 'Surprise gift delivered to you!'),
    ('💎', '1000 NJ Coins JACKPOT', 'You hit the jackpot! 🎊'),
    ('🚀', 'Priority Delivery', 'Your next delivery is FREE!'),
    ('🧃', '₹25 Wallet Cash', 'Small gift, big love! 💕'),
    ('🎯', 'Double Coins Today', 'Earn 2x coins all day!'),
  ];

  void _showScratchCardModal() {
    final gifts = List.of(_scratchGifts)..shuffle();
    final gift = gifts.first;
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _ScratchCardModal(gift: gift),
    );
  }

  void _tap(String id) {
    switch (id) {
      case 'taxi':        _navigate(const BikeBookingScreen());
      case 'broadband':   _launchBroadband();
      case 'food':        _navigate(const StoreLayoutScreen(storeType: 'food'));
      case 'grocery':     _navigate(const StoreLayoutScreen(storeType: 'grocery'));
      case 'njtech':      _navigate(const NJTechStoreScreen());
      case 'carwash':     _navigate(const CarWashScreen());
      case 'puncture':    _navigate(const ComingSoonScreen(role: 'Mobile Puncture'));
      case 'construction':_navigate(const ConstructionScreen());
      case 'custom':      _navigate(const CustomOrderScreen());
      case 'mobile':      _navigate(const NjTechServiceScreen());
      case 'spares':      _navigate(const NjTechServiceScreen());
      case 'aibots':      _navigate(const GuruChatScreen());
      case 'repairs':     _navigate(const NjTechServiceScreen());
      case 'delivery':    _navigate(const ComingSoonScreen(role: 'Delivery'));
    }
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (_navIndex != 0) { _goTab(0); return; }
        final exit = await showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: kBg,
            title: Text('வெளியேறுவீர்களா?',
                style: GoogleFonts.notoSansTamil(
                    color: kText, fontWeight: FontWeight.w700)),
            content: Text('App-ஐ மூடவா?',
                style: GoogleFonts.notoSansTamil(color: kMuted)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: Text('இல்லை', style: TextStyle(color: kPink))),
              TextButton(onPressed: () => Navigator.pop(context, true),
                  child: Text('ஆம்', style: TextStyle(color: kRed))),
            ],
          ),
        );
        if (exit == true && context.mounted) SystemNavigator.pop();
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
                    onNJServiceTap: _tap,
                    user: _user,
                    userStream: const Stream.empty(),
                  ),
                ),
                KeepAliveTab(
                  child: RewardsScreen(
                    promoOffers: _promoOffers,
                    onClaimPromo: _claimPromo,
                  ),
                ),
                const KeepAliveTab(child: PlayZoneScreen()),
                const KeepAliveTab(child: GuruChatScreen()),
                const KeepAliveTab(child: SosScreen()),
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
                  'Hi, $firstName',
                  style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w700, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                const Text(
                  'Erode, TN',
                  style: TextStyle(color: kMuted, fontSize: 9, letterSpacing: 0.5),
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
              _checkForUpdates(context);
            }
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
          child: const Icon(Icons.notifications_outlined, color: kText, size: 22),
        ),
        const SizedBox(width: 16),
      ],
    );
  }

  Widget _buildBottomNav() {
    const items = [
      {'icon': Icons.home_rounded,           'label': 'Home'},
      {'icon': Icons.card_giftcard_rounded,  'label': 'Rewards'},
      {'icon': Icons.sports_esports_rounded, 'label': 'Play Zone'},
      {'icon': Icons.smart_toy_rounded,      'label': 'Guru AI'},
      {'icon': Icons.shield_rounded,         'label': 'Safety'},
    ];
    return Container(
      decoration: BoxDecoration(
        color: kBg,
        border: Border(top: BorderSide(color: kBorder, width: 1)),
        boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 16, offset: const Offset(0, -4))],
      ),
      child: SafeArea(
        child: Row(
          children: List.generate(items.length, (i) {
            final active = _navIndex == i;
            final icon  = items[i]['icon']  as IconData;
            final label = items[i]['label'] as String;
            return Expanded(
              child: InkWell(
                onTap: () => _goTab(i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: active ? kPink : kMuted, size: 24),
                    const SizedBox(height: 3),
                    Text(label, style: TextStyle(
                        fontSize: 9.5,
                        color: active ? kPink : kMuted,
                        fontWeight: active ? FontWeight.w700 : FontWeight.w400)),
                  ]),
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
// HOME TAB
// ================================================================
class _HomeTab extends StatelessWidget {
  final void Function(String) onTileTap;
  final void Function(String) onNJServiceTap;
  final User? user;
  final Stream<DocumentSnapshot> userStream;

  const _HomeTab({
    required this.onTileTap,
    required this.onNJServiceTap,
    required this.user,
    required this.userStream,
  });

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const SizedBox(height: 12),
        // Top Half-Screen Banner Ads
        const BannerAdsSlider(
          height: 240,
          imageUrls: [
            'https://images.unsplash.com/photo-1593640408182-31c70c8268f5?w=800&q=80',
            'https://images.unsplash.com/photo-1546054454-aa26e2b734c7?w=800&q=80',
            'https://images.unsplash.com/photo-1555664424-778a1e5e1b48?w=800&q=80',
          ],
        ),
        const SizedBox(height: 20),
        _buildNJTechBanner(context),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('What do you need today?',
              style: GoogleFonts.outfit(
                  fontSize: 17, fontWeight: FontWeight.w800, color: kText)),
        ),
        const SizedBox(height: 12),
        _buildServiceGrid(context),
        const SizedBox(height: 12),
        _buildFeaturedShop(context),
        const SizedBox(height: 10),
        _buildPromoCards(context),
        const SizedBox(height: 20),
        const BannerAdsSlider(
          height: 240,
          imageUrls: [
            'https://images.unsplash.com/photo-1593640408182-31c70c8268f5?w=800&q=80',
            'https://images.unsplash.com/photo-1546054454-aa26e2b734c7?w=800&q=80',
          ],
        ),
        const SizedBox(height: 100),
      ]),
    );
  }

  // ── NJ Tech Dark Banner ────────────────────────────────────────
  Widget _buildNJTechBanner(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [kNJDark, kNJDark2],
          begin: Alignment.topLeft, end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(children: [
        SizedBox(
          height: 78,
          child: _NJServiceMarquee(
            services: _njServices,
            onTap: onNJServiceTap,
          ),
        ),
        GestureDetector(
          onTap: () => Navigator.push<void>(context,
              MaterialPageRoute<void>(
                  builder: (_) => const CustomOrderScreen())),
          child: Container(
            margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.06),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                  color: Colors.white.withValues(alpha: 0.12)),
            ),
            child: Row(children: [
              Container(
                width: 44, height: 44,
                decoration: BoxDecoration(
                  color: kPink.withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(12),
                ),
                // ✅ Replaced basic box emoji with a premium 3D parcel image
                child: Center(
                  child: Image.network(
                    'https://img.icons8.com/fluency/96/magic-parcel.png',
                    width: 28, height: 28,
                    errorBuilder: (_, __, ___) => const Text('🎁', style: TextStyle(fontSize: 22)),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Call for Customise Order',
                    style: GoogleFonts.outfit(
                        color: Colors.white, fontSize: 14,
                        fontWeight: FontWeight.w800)),
                const SizedBox(height: 2),
                Text('Place custom orders & get support — tap to start',
                    style: const TextStyle(
                        color: Colors.white60, fontSize: 10)),
              ])),
              Container(
                width: 32, height: 32,
                decoration: BoxDecoration(
                  color: kPink, borderRadius: BorderRadius.circular(10)),
                child: const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 18),
              ),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Service Grid ───────────────────────────────────────────────
  Widget _buildServiceGrid(BuildContext context) {
    final cols = MediaQuery.of(context).size.width > 600 ? 5 : 3;
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: cols,
        childAspectRatio: cols == 5 ? 1.0 : 0.85,
        crossAxisSpacing: 8,
        mainAxisSpacing: 8,
      ),
      itemCount: _tiles.length,
      itemBuilder: (_, i) => _ServiceGridTile(
        tile: _tiles[i],
        onTap: () => onTileTap(_tiles[i].id),
      ),
    );
  }

  // ── Featured Shop Card ─────────────────────────────────────────
  Widget _buildFeaturedShop(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push<void>(context,
          MaterialPageRoute<void>(
              builder: (_) => const ComingSoonScreen(role: 'Erode Fresh'))),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [kGreen.withValues(alpha: 0.08),
                kGreen.withValues(alpha: 0.03)],
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
              Text('★ Featured Shop',
                  style: TextStyle(color: kGold, fontSize: 10,
                      fontWeight: FontWeight.w700)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: kGreen, borderRadius: BorderRadius.circular(6)),
                child: const Text('Open', style: TextStyle(
                    color: Colors.white, fontSize: 9,
                    fontWeight: FontWeight.w700)),
              ),
            ]),
            const SizedBox(height: 2),
            Text('Erode Fresh', style: GoogleFonts.outfit(
                color: kText, fontSize: 15, fontWeight: FontWeight.w800)),
            Text('★★  · Fresh Groceries',
                style: const TextStyle(color: kMuted, fontSize: 11)),
          ])),
          const Icon(Icons.chevron_right_rounded, color: kMuted),
        ]),
      ),
    );
  }

  // ── Promo Cards ────────────────────────────────────────────────
  Widget _buildPromoCards(BuildContext context) {
    return Column(children: [
      GestureDetector(
        onTap: () => Navigator.push<void>(context,
            MaterialPageRoute<void>(builder: (_) => const BikeBookingScreen())),
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
              Text('உங்கள் முதல் ride FREE!',
                  style: GoogleFonts.notoSansTamil(
                      color: kPink, fontSize: 13, fontWeight: FontWeight.w700)),
              const SizedBox(height: 2),
              Text('Erode-ல Bike Taxi book பண்ணுங்க',
                  style: GoogleFonts.notoSansTamil(
                      color: Colors.white60, fontSize: 10)),
            ])),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: kPink, borderRadius: BorderRadius.circular(10)),
              child: Text('Book →', style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 11,
                  fontWeight: FontWeight.w700)),
            ),
          ]),
        ),
      ),
      GestureDetector(
        onTap: () => Navigator.push<void>(context,
            MaterialPageRoute<void>(builder: (_) => const GuruChatScreen())),
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
                Text('Get your Guru AI subscription for 1yr free',
                    style: GoogleFonts.outfit(
                        color: kText, fontSize: 12,
                        fontWeight: FontWeight.w700)),
                const SizedBox(width: 6),
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 6, vertical: 2),
                  decoration: BoxDecoration(
                    color: kPurple.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(6),
                    border: Border.all(color: kPurple.withValues(alpha: 0.4)),
                  ),
                  child: Text('GURU', style: TextStyle(
                      color: kPurple, fontSize: 8,
                      fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 2),
              Text('Visit NJ TECH to unlock the 1-year free Guru AI offer.',
                  style: const TextStyle(color: kMuted, fontSize: 10)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: kMuted),
          ]),
        ),
      ),
    ]);
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<User?>('user', user));
  }
}

// ================================================================
// T1b: NJ SERVICE MARQUEE — auto-scrolling icon strip
// ================================================================
class _NJServiceMarquee extends StatefulWidget {
  final List<Map<String, String>> services;
  final void Function(String) onTap;
  const _NJServiceMarquee({required this.services, required this.onTap});

  @override
  State<_NJServiceMarquee> createState() => _NJServiceMarqueeState();
}

class _NJServiceMarqueeState extends State<_NJServiceMarquee> {
  late final ScrollController _sc;
  Timer? _timer;
  static const double _itemW = 64;

  @override
  void initState() {
    super.initState();
    _sc = ScrollController();
    WidgetsBinding.instance.addPostFrameCallback((_) => _startMarquee());
  }

  void _startMarquee() {
    _timer = Timer.periodic(const Duration(milliseconds: 16), (_) {
      if (!mounted || !_sc.hasClients) return;
      final max = _sc.position.maxScrollExtent;
      if (max <= 0) return;
      final next = _sc.offset + 0.8;
      if (next >= max) {
        _sc.jumpTo(0);
      } else {
        _sc.jumpTo(next);
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _sc.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final doubled = [...widget.services, ...widget.services];
    return ListView.builder(
      controller: _sc,
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      itemCount: doubled.length,
      itemBuilder: (_, i) {
        final s = doubled[i % widget.services.length];
        return GestureDetector(
          onTap: () => widget.onTap(s['id']!),
          child: SizedBox(
            width: _itemW,
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              s['icon']!.startsWith('assets/')
                  ? Image.asset(s['icon']!, width: 26, height: 26, fit: BoxFit.contain)
                  : Text(s['icon']!, style: const TextStyle(fontSize: 22)),
              const SizedBox(height: 3),
              Text(s['label']!, textAlign: TextAlign.center,
                  style: const TextStyle(
                      color: Colors.white70, fontSize: 9,
                      fontWeight: FontWeight.w500),
                  maxLines: 2, overflow: TextOverflow.ellipsis),
            ]),
          ),
        );
      },
    );
  }
}

// ================================================================
// SERVICE GRID TILE
// ================================================================
class _ServiceGridTile extends StatefulWidget {
  final _Tile tile;
  final VoidCallback onTap;
  const _ServiceGridTile({required this.tile, required this.onTap});

  @override
  State<_ServiceGridTile> createState() => _ServiceGridTileState();
}

class _ServiceGridTileState extends State<_ServiceGridTile>
    with TickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<double> _slide;
  int _vehicleIndex = 0;
  static const _vehicles = ['🏍️', '🛺', '🚗'];
  static const _vehicleAssets = [
    'assets/images/top_bike.png',
    null,
    null,
  ];

  // ✅ New High-Tech Asset Map (Placeholders)
  static const Map<String, String> _tileAssetMap = {
    'food': 'assets/icons/food.png',
    'grocery': 'assets/icons/grocery.png',
    'njtech': 'assets/icons/njtech.png',
    'broadband': 'assets/icons/broadband.png',
    'construction': 'assets/icons/construction.png',
    'carwash': 'assets/icons/carwash.png',
    'puncture': 'assets/icons/puncture.png',
    'custom': 'assets/icons/custom.png',
  };

  int _emojiIndex = 0;
  Timer? _emojiTimer;

  late final AnimationController _steamCtrl;
  late final Animation<double> _steamRise;
  late final Animation<double> _steamFade;

  late final AnimationController _bagCtrl;
  late final Animation<double> _bagBounce;
  late final Animation<double> _bagSpin;

  @override
  void initState() {
    super.initState();
    final id = widget.tile.id;
    // ✅ Slowed down the cycle from 2s to 4s for a premium feel
    _emojiTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (mounted) setState(() => _emojiIndex++);
    });

    if (id == 'taxi') {
      _ctrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1400))
        ..addStatusListener((status) {
          if (status == AnimationStatus.completed) {
            _ctrl.reverse();
          } else if (status == AnimationStatus.dismissed) {
            setState(() => _vehicleIndex = (_vehicleIndex + 1) % _vehicles.length);
            Future.delayed(const Duration(milliseconds: 180), () {
              if (mounted) _ctrl.forward();
            });
          }
        })
        ..forward();
      _slide = Tween<double>(begin: -18, end: 18).animate(
          CurvedAnimation(parent: _ctrl, curve: Curves.easeInOut));
    } else {
      _ctrl  = AnimationController(vsync: this, duration: Duration.zero);
      _slide = const AlwaysStoppedAnimation(0);
    }

    if (id == 'food') {
      _steamCtrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 1600))
        ..repeat();
      _steamRise = Tween<double>(begin: 4, end: -26).animate(
          CurvedAnimation(parent: _steamCtrl, curve: Curves.easeInOut));
      _steamFade = TweenSequence<double>([
        TweenSequenceItem(tween: Tween(begin: 0.0, end: 0.9), weight: 25),
        TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.9), weight: 20),
        TweenSequenceItem(tween: Tween(begin: 0.9, end: 0.0), weight: 55),
      ]).animate(_steamCtrl);
    } else {
      _steamCtrl = AnimationController(vsync: this, duration: Duration.zero);
      _steamRise = const AlwaysStoppedAnimation(0);
      _steamFade = const AlwaysStoppedAnimation(0);
    }

    if (id == 'grocery') {
      _bagCtrl = AnimationController(
          vsync: this, duration: const Duration(milliseconds: 900))
        ..repeat(reverse: true);
      _bagBounce = Tween<double>(begin: 2, end: -10).animate(
          CurvedAnimation(parent: _bagCtrl, curve: Curves.easeInOut));
      _bagSpin = Tween<double>(begin: -0.12, end: 0.12).animate(
          CurvedAnimation(parent: _bagCtrl, curve: Curves.easeInOut));
    } else {
      _bagCtrl   = AnimationController(vsync: this, duration: Duration.zero);
      _bagBounce = const AlwaysStoppedAnimation(0);
      _bagSpin   = const AlwaysStoppedAnimation(0);
    }
  }

  @override
  void dispose() {
    _emojiTimer?.cancel();
    _ctrl.dispose();
    _steamCtrl.dispose();
    _bagCtrl.dispose();
    super.dispose();
  }

  Widget _buildIconArea(_Tile tile) {
    if (tile.id == 'taxi') {
      return AnimatedBuilder(
        animation: _slide,
        builder: (_, __) => Transform.translate(
          offset: Offset(_slide.value, 0),
          child: _vehicleAssets[_vehicleIndex] != null
              ? Image.asset(_vehicleAssets[_vehicleIndex]!,
                  width: 50, height: 50, fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => Text(_vehicles[_vehicleIndex], style: const TextStyle(fontSize: 40)))
              : Text(_vehicles[_vehicleIndex], style: const TextStyle(fontSize: 40)),
        ),
      );
    }

    const Map<String, List<IconData>> premiumIcons = {
      'broadband':    [Icons.wifi_rounded, Icons.router_rounded, Icons.settings_ethernet_rounded, Icons.signal_wifi_4_bar_rounded],
      'food':         [Icons.fastfood_rounded, Icons.local_pizza_rounded, Icons.ramen_dining_rounded, Icons.cake_rounded],
      'grocery':      [Icons.shopping_basket_rounded, Icons.shopping_cart_rounded, Icons.local_grocery_store_rounded, Icons.kitchen_rounded],
      'njtech':       [Icons.smartphone_rounded, Icons.laptop_mac_rounded, Icons.headphones_rounded, Icons.electrical_services_rounded],
      'carwash':      [Icons.directions_car_rounded, Icons.local_car_wash_rounded, Icons.water_drop_rounded, Icons.cleaning_services_rounded],
      'puncture':     [Icons.two_wheeler_rounded, Icons.tire_repair_rounded, Icons.build_rounded, Icons.handyman_rounded],
      'construction': [Icons.engineering_rounded, Icons.handyman_rounded, Icons.foundation_rounded, Icons.architecture_rounded],
      'custom':       [Icons.inventory_2_rounded, Icons.card_giftcard_rounded, Icons.support_agent_rounded, Icons.local_shipping_rounded],
    };

    final iconSet = premiumIcons[tile.id] ?? [Icons.category_rounded];
    final currentIcon = iconSet[_emojiIndex % iconSet.length];

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        shape: BoxShape.circle,
        boxShadow: [BoxShadow(
          color: tile.color.withValues(alpha: 0.28),
          blurRadius: 14, spreadRadius: 2, offset: const Offset(0, 3),
        )],
      ),
      padding: const EdgeInsets.all(12),
      child: AnimatedSwitcher(
        duration: const Duration(milliseconds: 600),
        transitionBuilder: (child, animation) => ScaleTransition(
          scale: CurvedAnimation(
            parent: animation,
            curve: Curves.elasticOut,
          ),
          child: FadeTransition(opacity: animation, child: child),
        ),
        child: Icon(
          currentIcon,
          key: ValueKey<IconData>(currentIcon),
          size: 34,
          color: tile.color,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final tile = widget.tile;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          // Clean, subtle pastel background matching the brand theme
          color: tile.color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: tile.color.withValues(alpha: 0.12)),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.02), blurRadius: 4, offset: const Offset(0, 2))
          ],
        ),
        padding: const EdgeInsets.only(top: 10, left: 6, right: 6, bottom: 6),
        child: Stack(
          children: [
            Column(
              children: [
                // Layer 1: Text at the Top
                Text(
                  tile.title,
                  maxLines: 2,
                  textAlign: TextAlign.center,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    color: kText,
                    height: 1.1,
                    letterSpacing: -0.2,
                  ),
                ),
                const SizedBox(height: 8),
                // Layer 2: Animated Icon at the Bottom
                Expanded(
                  child: Center(child: _buildIconArea(tile)),
                ),
              ],
            ),
            // Layer 3: Live Badge
            if (tile.badge.isNotEmpty)
              Positioned(
                top: 0,
                right: 0,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                  decoration: BoxDecoration(
                    color: tile.isLive ? kGreen : kGold,
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(tile.badge, style: const TextStyle(fontSize: 7, fontWeight: FontWeight.w900, color: Colors.white)),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

// ================================================================
// PROFILE DRAWER
// ================================================================
class _ProfileDrawer extends StatelessWidget {
  final User? user;
  final void Function(Widget) onNavigate;
  const _ProfileDrawer({required this.user, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final name  = user?.displayName ?? 'Guest';
    final phone = user?.phoneNumber ?? 'Phone not added';

    return Drawer(
      backgroundColor: kBg,
      child: SafeArea(
        child: Column(children: [
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: const BoxDecoration(
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
                      fontWeight: FontWeight.w900, fontSize: 24),
                ),
              ),
              const SizedBox(width: 14),
              Expanded(child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 16,
                    fontWeight: FontWeight.w800),
                    overflow: TextOverflow.ellipsis),
                const SizedBox(height: 3),
                Text(phone, style: const TextStyle(
                    color: Colors.white70, fontSize: 12)),
              ])),
            ]),
          ),
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              _drawerItem(context, Icons.person_outline_rounded,
                  'My Profile', () => onNavigate(const ProfileScreen())),
              _drawerItem(context, Icons.history_rounded,
                  'My Rides', () => onNavigate(const RideHistoryScreen())),
              _drawerItem(context, Icons.account_balance_wallet_outlined,
                  'Wallet', () => Navigator.pop(context)),
              _drawerItem(context, Icons.payment_rounded,
                  'Payment Methods', () => Navigator.pop(context)),
              _drawerItem(context, Icons.notifications_outlined,
                  'Notifications', () => onNavigate(const NotificationsScreen())),
              _drawerItem(context, Icons.translate_rounded,
                  'Change Language', () {
                Navigator.pop(context);
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Language settings coming soon')));
              }),
              _drawerItem(context, Icons.download_rounded,
                  'Download Mobile App', () {
                Navigator.pop(context);
                _showApkSheet(context);
              }),
              _drawerItem(context, Icons.location_on_outlined,
                  'Saved Addresses', () => onNavigate(
                      const ComingSoonScreen(role: 'Saved Addresses'))),
              _drawerItem(context, Icons.help_outline_rounded,
                  'Help & Support', () async {
                final uri = Uri.parse('https://njtech.in/support');
                if (await canLaunchUrl(uri)) launchUrl(uri);
              }),
              _drawerItem(context, Icons.settings_outlined,
                  'Settings', () => onNavigate(const SettingsScreen())),
              _drawerItem(context, Icons.system_update_alt_rounded,
                  '🔄  Check for Updates', () {
                Navigator.pop(context);
                _checkForUpdates(context);
              }),
              const Divider(color: kBorder, height: 1),
              _drawerItem(context, Icons.logout_rounded,
                  'Sign Out / Logout', () async {
                await LocalSyncService.instance.clearAll();
                await HiveCache.clearAll();
                await PrefsCache.clearAll();
                await FirebaseAuth.instance.signOut();
              }, color: kRed),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _drawerItem(BuildContext context, IconData icon,
      String title, VoidCallback onTap, {Color? color}) {
    final c = color ?? kPink;
    return ListTile(
      onTap: () { Navigator.pop(context); onTap(); },
      leading: Icon(icon, color: c, size: 20),
      title: Text(title, style: TextStyle(
          color: c, fontSize: 13, fontWeight: FontWeight.w600)),
      trailing: Icon(Icons.chevron_right_rounded,
          color: c.withValues(alpha: 0.5), size: 18),
      dense: true,
    );
  }
}

// ================================================================
// CHECK FOR UPDATES
// ================================================================
Future<void> _checkForUpdates(BuildContext context) async {
  final navigator = Navigator.of(context, rootNavigator: true);
  final msg = kIsWeb
      ? 'Please wait, app is updating...'
      : 'Checking for updates...';

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
              valueColor: AlwaysStoppedAnimation<Color>(kPink)),
        ),
        const SizedBox(height: 20),
        Text(msg,
            textAlign: TextAlign.center,
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 14,
                fontWeight: FontWeight.w600)),
      ]),
    ),
  );

  await Future<void>.delayed(const Duration(milliseconds: 1500));
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
    showDialog<void>(
      context: navigator.context,
      builder: (_) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A26),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(children: [
          const Text('✅ ', style: TextStyle(fontSize: 20)),
          Text('Up to Date',
              style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 16,
                  fontWeight: FontWeight.w800)),
        ]),
        content: Text(
          'App is up to date!\nBackground updates are active via Shorebird OTA.',
          style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => navigator.pop(),
            child: Text('Got it', style: TextStyle(color: kPink)),
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
// APK DOWNLOAD SHEET
// ================================================================
void _showApkSheet(BuildContext context) {
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
                borderRadius: BorderRadius.circular(2))),
        const SizedBox(height: 16),
        Text('📲 Download NJ TECH Apps',
            style: GoogleFonts.outfit(
                color: Colors.white, fontSize: 15,
                fontWeight: FontWeight.w800)),
        const SizedBox(height: 20),
        _apkBtn(
          label: '🛒  Download Customer App',
          gradient: [kPink, kPinkDark],
          url: 'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer_app.apk',
        ),
        const SizedBox(height: 10),
        _apkBtn(
          label: '🏍️  Download Hero App',
          gradient: [kPurple, const Color(0xFF5A50C8)],
          url: 'https://github.com/myallin1/Allin1-update-release/releases/download/v1.0.0/hero_app.apk',
        ),
        const SizedBox(height: 16),
        GestureDetector(
          onTap: () => Navigator.pop(context),
          child: const Text('Dismiss',
              style: TextStyle(color: Colors.white38, fontSize: 12)),
        ),
      ]),
    ),
  );
}

Widget _apkBtn({required String label,
    required List<Color> gradient, required String url}) {
  return GestureDetector(
    onTap: () async {
      final uri = Uri.parse(url);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
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
              fontWeight: FontWeight.w700))),
    ),
  );
}

// ================================================================
// WALLET SHEET — Add Money / Transfer
// ================================================================
class _WalletSheet extends StatefulWidget {
  final User? user;
  const _WalletSheet({required this.user});
  @override
  State<_WalletSheet> createState() => _WalletSheetState();
}

class _WalletSheetState extends State<_WalletSheet>
    with SingleTickerProviderStateMixin {
  late final TabController _tab = TabController(length: 2, vsync: this);
  final _ctrl   = TextEditingController();
  final _toCtrl = TextEditingController();
  bool _loading = false;

  @override
  void dispose() {
    _tab.dispose();
    _ctrl.dispose();
    _toCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: Container(
        decoration: const BoxDecoration(
          color: kBg,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          const SizedBox(height: 12),
          Container(width: 40, height: 4,
              decoration: BoxDecoration(color: kBorder,
                  borderRadius: BorderRadius.circular(2))),
          const SizedBox(height: 16),
          TabBar(controller: _tab,
              labelColor: kPink, unselectedLabelColor: kMuted,
              indicatorColor: kPink, dividerColor: kBorder,
              tabs: const [Tab(text: 'Add Money'), Tab(text: 'Transfer')]),
          SizedBox(height: 220, child: TabBarView(controller: _tab, children: [
            _addMoneyTab(), _transferTab(),
          ])),
        ]),
      ),
    );
  }

  Widget _addMoneyTab() {
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      TextField(controller: _ctrl, keyboardType: TextInputType.number,
          decoration: InputDecoration(
            hintText: 'Enter amount (₹)', prefixText: '₹ ',
            prefixStyle: const TextStyle(color: kPink, fontWeight: FontWeight.w700),
            filled: true, fillColor: kSurface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none))),
      const SizedBox(height: 10),
      Row(children: [100, 200, 500, 1000].map((v) =>
        Padding(padding: const EdgeInsets.only(right: 8),
          child: GestureDetector(onTap: () => _ctrl.text = '$v',
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
              decoration: BoxDecoration(color: kPinkBg,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: kPink.withValues(alpha: 0.3))),
              child: Text('₹$v', style: TextStyle(color: kPink, fontSize: 12,
                  fontWeight: FontWeight.w600)))))).toList()),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kPink,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          onPressed: _loading ? null : _addMoney,
          child: _loading
              ? const SizedBox(width: 20, height: 20,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2))
              : const Text('Add Money', style: TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w800)))),
    ]));
  }

  Widget _transferTab() {
    return Padding(padding: const EdgeInsets.all(20), child: Column(children: [
      TextField(controller: _toCtrl, keyboardType: TextInputType.phone,
          decoration: InputDecoration(hintText: 'Recipient phone number',
            prefixIcon: const Icon(Icons.phone_outlined, color: kMuted, size: 18),
            filled: true, fillColor: kSurface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none))),
      const SizedBox(height: 10),
      TextField(controller: _ctrl, keyboardType: TextInputType.number,
          decoration: InputDecoration(hintText: 'Amount (₹)', prefixText: '₹ ',
            prefixStyle: const TextStyle(
                color: kPink, fontWeight: FontWeight.w700),
            filled: true, fillColor: kSurface,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none))),
      const SizedBox(height: 14),
      SizedBox(width: double.infinity, height: 48,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: kPink,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14))),
          onPressed: _loading ? null : _transfer,
          child: const Text('Transfer Now', style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800)))),
    ]));
  }

  Future<void> _addMoney() async {
    final amt = double.tryParse(_ctrl.text.trim());
    if (amt == null || amt <= 0 || widget.user == null) return;
    setState(() => _loading = true);
    try {
      final db = FirebaseFirestore.instance;
      await db.runTransaction((txn) async {
        final ref  = db.collection('users').doc(widget.user!.uid);
        final snap = await txn.get(ref);
        final cur  = (snap.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        txn
          ..update(ref, {'walletBalance': cur + amt})
          ..set(db.collection('wallet_transactions').doc(), {
            'userId': widget.user!.uid, 'type': 'credit',
            'amount': amt, 'createdAt': FieldValue.serverTimestamp()});
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  Future<void> _transfer() async {
    final amt   = double.tryParse(_ctrl.text.trim());
    final phone = _toCtrl.text.trim();
    if (amt == null || amt <= 0 || phone.isEmpty || widget.user == null) return;
    setState(() => _loading = true);
    try {
      final db      = FirebaseFirestore.instance;
      final recSnap = await db.collection('users')
          .where('phone', isEqualTo: phone).limit(1).get();
      if (recSnap.docs.isEmpty) throw Exception('User not found');
      final toUid = recSnap.docs.first.id;
      await db.runTransaction((txn) async {
        final fromRef = db.collection('users').doc(widget.user!.uid);
        final toRef   = db.collection('users').doc(toUid);
        final fSnap   = await txn.get(fromRef);
        final tSnap   = await txn.get(toRef);
        final fBal = (fSnap.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        final tBal = (tSnap.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
        if (fBal < amt) throw Exception('Insufficient balance');
        txn
          ..update(fromRef, {'walletBalance': fBal - amt})
          ..update(toRef,   {'walletBalance': tBal + amt});
      });
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(e.toString().replaceAll('Exception: ', '')),
          backgroundColor: kRed,
          behavior: SnackBarBehavior.floating,
        ));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }
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
    return Scaffold(
      backgroundColor: kNJDark,
      appBar: AppBar(
        backgroundColor: kNJDark,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: Colors.white, size: 20),
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
              const Icon(Icons.lock_rounded, color: kPink, size: 12),
              const SizedBox(width: 4),
              Text('erodefiber.net',
                  style: GoogleFonts.outfit(
                      color: Colors.white, fontSize: 13,
                      fontWeight: FontWeight.w600)),
            ]),
          ),
        ]),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: kPink),
            onPressed: _openInApp,
            tooltip: 'Reload',
          ),
        ],
      ),
      body: Center(
        child: _loading
            ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                CircularProgressIndicator(color: kPink),
                const SizedBox(height: 20),
                Text('Opening Erode Fiber...',
                    style: GoogleFonts.outfit(
                        color: Colors.white70, fontSize: 14)),
              ])
            : _launched
                ? Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Text('🌐', style: TextStyle(fontSize: 56)),
                    const SizedBox(height: 16),
                    Text('Erode Fiber is open!',
                        style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 20, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 8),
                    Text('The site loaded in-app above.',
                        style: GoogleFonts.outfit(
                            color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 28),
                    GestureDetector(
                      onTap: () => Navigator.pop(context),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 32, vertical: 14),
                        decoration: BoxDecoration(
                          color: kPink,
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [BoxShadow(
                              color: kPink.withValues(alpha: 0.4),
                              blurRadius: 12)],
                        ),
                        child: Text('← Back to Dashboard',
                            style: GoogleFonts.outfit(
                                color: Colors.white, fontSize: 14,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ])
                : Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                    const Icon(Icons.wifi_off_rounded,
                        color: Colors.white38, size: 56),
                    const SizedBox(height: 16),
                    Text('Could not open in-app',
                        style: GoogleFonts.outfit(
                            color: Colors.white, fontSize: 18,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('Check internet and try again.',
                        style: GoogleFonts.outfit(
                            color: Colors.white54, fontSize: 13)),
                    const SizedBox(height: 20),
                    GestureDetector(
                      onTap: _openInApp,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 28, vertical: 12),
                        decoration: BoxDecoration(
                          color: kPink,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text('Try Again',
                            style: GoogleFonts.outfit(
                                color: Colors.white,
                                fontWeight: FontWeight.w700)),
                      ),
                    ),
                  ]),
      ),
    );
  }
}

// ================================================================
// SCRATCH CARD MODAL
// ================================================================
class _ScratchCardModal extends StatefulWidget {
  final (String, String, String) gift;
  const _ScratchCardModal({required this.gift});
  @override
  State<_ScratchCardModal> createState() => _ScratchCardModalState();
}

class _ScratchCardModalState extends State<_ScratchCardModal> {
  bool   _revealed = false;
  double _progress = 0;

  @override
  Widget build(BuildContext context) {
    final (emoji, title, subtitle) = widget.gift;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 32),
      decoration: BoxDecoration(
        color: kNJDark,
        borderRadius: BorderRadius.circular(28),
        border: Border.all(color: kGold.withValues(alpha: 0.4), width: 1.5),
        boxShadow: [BoxShadow(
            color: kGold.withValues(alpha: 0.2), blurRadius: 30)],
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
              child: Text('🎰 DAILY SCRATCH',
                  style: GoogleFonts.outfit(
                      color: kGold, fontSize: 10, fontWeight: FontWeight.w800,
                      letterSpacing: 0.5)),
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
                    color: Colors.white54, size: 18),
              ),
            ),
          ]),
        ),
        Text('Scratch to reveal your gift!',
            style: GoogleFonts.outfit(color: Colors.white70, fontSize: 13)),
        const SizedBox(height: 16),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Scratcher(
            brushSize: 40,
            threshold: 45,
            color: const Color(0xFFD4AF37),
            onThreshold: () => setState(() => _revealed = true),
            onChange: (double v) => setState(() => _progress = v),
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
                  Text(emoji, style: const TextStyle(fontSize: 52)),
                  const SizedBox(height: 10),
                  Text(title,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: kPink, fontSize: 22,
                          fontWeight: FontWeight.w900)),
                  const SizedBox(height: 6),
                  Text(subtitle,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: Colors.white70, fontSize: 13)),
                ]),
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
                  _revealed ? kGreen : kGold),
              minHeight: 4,
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(_revealed ? '🎊 Revealed!' : 'Keep scratching...',
            style: GoogleFonts.outfit(
                color: _revealed ? kGreen : Colors.white38,
                fontSize: 11, fontWeight: FontWeight.w600)),
        const SizedBox(height: 16),
        if (_revealed)
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 20),
            child: Row(children: [
              Expanded(
                child: GestureDetector(
                  onTap: () {
                    // Capture context BEFORE pop — safe async pattern
                    final ctx = context;
                    Navigator.of(ctx).pop();
                    Future.delayed(const Duration(milliseconds: 300), () {
                      if (!ctx.mounted) return;
                      final gifts = List<(String, String, String)>.of(
                          _DashboardScreenState._scratchGifts)
                        ..shuffle();
                      showModalBottomSheet<void>(
                        context: ctx,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (_) => _ScratchCardModal(gift: gifts.first),
                      );
                    });
                  },
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: kPink.withValues(alpha: 0.3)),
                    ),
                    child: Center(child: Text('🎁 Next Card',
                        style: GoogleFonts.outfit(
                            color: kPink, fontSize: 13,
                            fontWeight: FontWeight.w700))),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: GestureDetector(
                  onTap: () => Navigator.pop(context),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    decoration: BoxDecoration(
                      color: kGold,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                          color: kGold.withValues(alpha: 0.4),
                          blurRadius: 10)],
                    ),
                    child: Center(child: Text('✅ Claim!',
                        style: GoogleFonts.outfit(
                            color: Colors.black,
                            fontSize: 13, fontWeight: FontWeight.w800))),
                  ),
                ),
              ),
            ]),
          )
        else
          const SizedBox(height: 20),
      ]),
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
}
class _GlowingUpdateButtonState extends State<_GlowingUpdateButton> with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;
  late Animation<double> _glow;
  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(vsync: this, duration: const Duration(milliseconds: 800))..repeat(reverse: true);
    _glow = Tween<double>(begin: 2.0, end: 8.0).animate(_ctrl);
  }
  @override
  void dispose() { _ctrl.dispose(); super.dispose(); }
  @override
  Widget build(BuildContext context) {
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
                BoxShadow(color: kGold.withValues(alpha: 0.6), blurRadius: _glow.value, spreadRadius: _glow.value / 2)
              ],
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.system_update_alt_rounded, color: Colors.black, size: 12),
                const SizedBox(width: 4),
                Text('UPDATE', style: GoogleFonts.outfit(color: Colors.black, fontSize: 10, fontWeight: FontWeight.w900)),
              ],
            ),
          ),
        );
      }
    );
  }
}

// ================================================================
// KEEP ALIVE WRAPPER
// ================================================================
class KeepAliveTab extends StatefulWidget {
  final Widget child;
  const KeepAliveTab({super.key, required this.child});
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
