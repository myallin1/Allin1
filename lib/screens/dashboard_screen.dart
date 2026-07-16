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
import 'package:scratcher/scratcher.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../services/pwa_cache_platform_web.dart';

import '../widgets/banner_slider.dart';
import 'bike_taxi/bike_booking_screen.dart';
import 'custom_food_order_screen.dart';
import 'hero_booking_screen.dart';
import 'car_wash_screen.dart';
import 'coming_soon_screen.dart';
import 'construction_screen.dart';
import 'custom_order_screen.dart';
import 'grocery_order_screen.dart';
// import 'printing_service_screen.dart'; // TODO(printing): file missing, feature temporarily disabled
import 'guru_chat_screen.dart';
import 'nj_tech_service_screen.dart';
import 'nj_tech_store_screen.dart';
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

// ── NJ Tech Quick-Service Icons ──────────────────────────────────
const _njServices = [
  {'icon': FluentEmojiFlat.mobile_phone, 'label': 'Mobile\nService',  'id': 'mobile'},
  {'icon': FluentEmojiFlat.wrench, 'label': 'Spare\nParts',     'id': 'spares'},
  {'icon': 'assets/images/assistant.gif', 'label': 'AI Bots', 'id': 'aibots'},
  {'icon': FluentEmojiFlat.antenna_bars, 'label': 'Broadband',         'id': 'broadband'},
  {'icon': FluentEmojiFlat.hammer_and_wrench, 'label': 'Repairs',          'id': 'repairs'},
  {'icon': FluentEmojiFlat.delivery_truck, 'label': 'Delivery',          'id': 'delivery'},
];

// ── Banner Items ──────────────────────────────────────────────────
const _bannerItems = [
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

class _DashboardScreenState extends State<DashboardScreen> {
  int _navIndex = 0;
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  final _user = FirebaseAuth.instance.currentUser;

  // ── Classic Rewards promo state ──────────────────────────────
  List<PromoOfferItem> _promoOffers = const [
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
      id: 'firstride', title: 'First Ride FREE 🛵',
      subtitle: 'New user? Your first taxi ride is on us!',
      icon: Icons.electric_bike_rounded, claimed: false,
      buttonLabel: 'Book Now',      statusLabel: 'New Users',
    ),
  ];

  bool _updateAvailable = true;

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
    // Auto-show the daily Paytm Soundbox scratch card once per calendar day.
    // Runs after first frame so a bottom sheet can be shown safely.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!_alreadyScratchedToday()) {
        _showScratchCardModal();
      }
    });
  }

  // ── Daily scratch gate (local, calendar-day) ─────────────────
  String _todayKey() {
    final n = DateTime.now();
    return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
        '${n.day.toString().padLeft(2, '0')}';
  }

  bool _alreadyScratchedToday() =>
      (HiveCache.get('last_scratch_date') as String?) == _todayKey();

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

  void _goTab(int i) {
    setState(() => _navIndex = i);
    PrefsCache.saveLastTab(i);
  }

  void _navigate(Widget screen) => Navigator.push<void>(
    context, MaterialPageRoute<void>(builder: (_) => screen));

  Future<void> _launchBroadband() async {
    _navigate(const NjTechBroadbandWebView());
  }

  void _showScratchCardModal() {
    // Mark today as used so the card auto-shows at most once per calendar day,
    // whether or not the customer fully scratches it.
    HiveCache.put('last_scratch_date', _todayKey());
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
      case 'puncture':    _navigate(const ComingSoonScreen(role: 'Mobile Puncture')); break;
      case 'construction':_navigate(const ConstructionScreen()); break;
      case 'custom':      _navigate(const CustomOrderScreen()); break;
      case 'mobile':      _navigate(const NjTechServiceScreen()); break;
      case 'spares':      _navigate(const NjTechServiceScreen()); break;
      case 'aibots':      _navigate(const GuruChatScreen()); break;
      case 'repairs':     _navigate(const NjTechServiceScreen()); break;
      case 'delivery':    _navigate(const ComingSoonScreen(role: 'Delivery')); break;
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
                style: GoogleFonts.outfit(
                    color: kText, fontWeight: FontWeight.w700)),
            content: Text('App-ஐ மூடவா?',
                style: GoogleFonts.outfit(color: kMuted)),
            actions: [
              TextButton(onPressed: () => Navigator.pop(context, false),
                  child: const Text('இல்லை', style: TextStyle(color: kPink))),
              TextButton(onPressed: () => Navigator.pop(context, true),
                  child: const Text('ஆம்', style: TextStyle(color: kRed))),
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
        icon: const Icon(Icons.menu_rounded, color: kPink, size: 26),
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
          child: const Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.wallet_rounded, size: 16, color: kPink),
              SizedBox(width: 4),
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
        border: const Border(top: BorderSide(color: kBorder, width: 1)),
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
// FLOATING GURU BOT — Draggable
// ================================================================
class _FloatingGuruBot extends StatefulWidget {
  final VoidCallback onTap;
  const _FloatingGuruBot({required this.onTap});
  @override
  State<_FloatingGuruBot> createState() => _FloatingGuruBotState();
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
                  blurRadius: 16, spreadRadius: 2)],
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
                color: kGreen, borderRadius: BorderRadius.circular(8)),
              child: Text('FREE', style: GoogleFonts.outfit(
                  color: Colors.white, fontSize: 7,
                  fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
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
}

class _FloatingGiftBoxState extends State<_FloatingGiftBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glow;
  late final Animation<double> _pulse;

  @override
  void initState() {
    super.initState();
    _glow = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200))
      ..repeat(reverse: true);
    _pulse = Tween<double>(begin: 0.85, end: 1.08).animate(
        CurvedAnimation(parent: _glow, curve: Curves.easeInOut));
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
              ]),
              boxShadow: [
                BoxShadow(
                    color: const Color(0xFFFFBB00)
                        .withValues(alpha: 0.5 + 0.35 * _pulse.value),
                    blurRadius: 22,
                    spreadRadius: 4),
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
        const _CategorySlidingBanner(),
        const SizedBox(height: 12),
        _buildNJTechBanner(context),
        const SizedBox(height: 20),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text('What do you need today?',
              style: GoogleFonts.outfit(
                  fontSize: 17, fontWeight: FontWeight.w800, color: kText)),
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

  // ── TAXI MEGA CARD ────────────────────────────────────────────────
  Widget _buildTaxiMegaCard(BuildContext context) {
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
                      SvgPicture.string(FluentEmojiFlat.taxi, width: 20, height: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Taxi & Transportation',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Bike, Auto, Cab, Parcel & Rent',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: kPink.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: kPink, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
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
          Row(
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
                        'Food Delivery',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Order from ANY shop in Erode!',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: kGold.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: kGold, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const CustomFoodOrderScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: kGold.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGold.withValues(alpha: 0.3), width: 1.5),
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
          Row(
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
                        'Grocery Order',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Type your list or snap a photo',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: kGreen.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: kGreen, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const GroceryOrderScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: kGreen.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGreen.withValues(alpha: 0.3), width: 1.5),
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
          Row(
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
                        'Electronic Services',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Mobile, Laptop, PC, CCTV, TV & AC',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: kBlue.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: kBlue, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const NJTechStoreScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: kBlue.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kBlue.withValues(alpha: 0.2), width: 1.5),
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
          Row(
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
                        'Car Service & Wash',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Water Wash, Repairs & Old Spares',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: kTeal.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: kTeal, size: 12),
              ),
            ],
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
                color: kTeal.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kTeal.withValues(alpha: 0.2), width: 1.5),
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
          Row(
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
                        'Constructions & Building',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Usha Constructions, Contracts & Plans',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: kPurple.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: kPurple, size: 12),
              ),
            ],
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
                color: kPurple.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kPurple.withValues(alpha: 0.2), width: 1.5),
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
    const Color heroColor = Color(0xFFFF5252); // Red
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
                      SvgPicture.string(FluentEmojiFlat.man_superhero, width: 20, height: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Hero Booking',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Hire a Hero for any tasks & deliveries',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: heroColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: heroColor, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute<void>(builder: (_) => const HeroBookingScreen()),
            ),
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: heroColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: heroColor.withValues(alpha: 0.2), width: 1.5),
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
    const Color printColor = Color(0xFF673AB7); // Deep Purple
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
                      SvgPicture.string(FluentEmojiFlat.printer, width: 20, height: 20),
                      const SizedBox(width: 6),
                      Text(
                        'Designing & Printing',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Visiting Cards, Flex, Bill Books & Notices',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: printColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: printColor, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          GestureDetector(
            onTap: () {
              // TODO(printing): PrintingServiceScreen is missing
              // (printing_service_screen.dart not found). Navigation disabled
              // until the screen is restored.
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Printing service is temporarily unavailable')),
              );
            },
            child: Container(
              width: double.infinity,
              height: 56,
              padding: const EdgeInsets.symmetric(horizontal: 20),
              decoration: BoxDecoration(
                color: printColor.withValues(alpha: 0.05),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: printColor.withValues(alpha: 0.2), width: 1.5),
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
    const Color serviceColor = Color(0xFF607D8B); // Blue Grey
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
                        'Other Services',
                        style: GoogleFonts.outfit(color: kText, fontSize: 16, fontWeight: FontWeight.w800),
                      ),
                    ],
                  ),
                  const Text(
                    '  Broadband, Mobile Puncture & More',
                    style: TextStyle(color: kMuted, fontSize: 11),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(color: serviceColor.withValues(alpha: 0.1), shape: BoxShape.circle),
                child: const Icon(Icons.arrow_forward_ios_rounded, color: serviceColor, size: 12),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
            decoration: BoxDecoration(
              color: serviceColor.withValues(alpha: 0.05),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: serviceColor.withValues(alpha: 0.2), width: 1.5),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: [
                _buildSmallActionTile(context, FluentEmojiFlat.antenna_bars, 'Internet', () => onTileTap('broadband')),
                _buildSmallActionTile(context, FluentEmojiFlat.motorcycle, 'Puncture', () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(role: 'Mobile Puncture')))),
                _buildSmallActionTile(context, FluentEmojiFlat.broom, 'Cleaning', () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(role: 'Home Cleaning')))),
                _buildSmallActionTile(context, FluentEmojiFlat.high_voltage, 'Electrician', () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => const ComingSoonScreen(role: 'Electrician')))),
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
                const Text('Place custom orders & get support — tap to start',
                    style: TextStyle(
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
              const Text('★ Featured Shop',
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
            const Text('★★  · Fresh Groceries',
                style: TextStyle(color: kMuted, fontSize: 11)),
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
                  child: const Text('GURU', style: TextStyle(
                      color: kPurple, fontSize: 8,
                      fontWeight: FontWeight.w800)),
                ),
              ]),
              const SizedBox(height: 2),
              const Text('Visit NJ TECH to unlock the 1-year free Guru AI offer.',
                  style: TextStyle(color: kMuted, fontSize: 10)),
            ])),
            const Icon(Icons.chevron_right_rounded, color: kMuted),
          ]),
        ),
      ),
    ]);
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
                  : s['icon']!.startsWith('<svg')
                      ? SvgPicture.string(s['icon']!, width: 26, height: 26)
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
// PROFILE DRAWER (Restored MVP Version)
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
          // Drawer Header
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

          // Drawer Menu Items
          Expanded(
            child: ListView(padding: EdgeInsets.zero, children: [
              const SizedBox(height: 10),

              _drawerItem(context, Icons.person_outline_rounded,
                  'My Profile', () => onNavigate(const ProfileScreen())),

              // Activity (Replaces standard history)
              _drawerItem(context, Icons.local_activity_outlined,
                  'Activity', () => onNavigate(const RideHistoryScreen())),

              _drawerItem(context, Icons.settings_outlined,
                  'Settings', () => onNavigate(const SettingsScreen())),

              _drawerItem(context, Icons.support_agent_rounded,
                  'Help & WhatsApp Support', () async {
                final url = Uri.parse("https://wa.me/918681869091?text=${Uri.encodeComponent('Hi NJ Tech! I need some help from the app.')}");
                if (await canLaunchUrl(url)) {
                  await launchUrl(url, mode: LaunchMode.externalApplication);
                }
              }),

              const SizedBox(height: 20),

              // Growth Hack: Download App CTA
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: GestureDetector(
                  onTap: () {
                    Navigator.pop(context);
                    _showApkSheet(context);
                  },
                  child: Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        colors: [kPurple, Color(0xFF5A50C8)],
                        begin: Alignment.topLeft, end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [BoxShadow(color: kPurple.withValues(alpha: 0.3), blurRadius: 10, offset: const Offset(0, 4))],
                    ),
                    child: Row(
                      children: [
                        const Text('🚀', style: TextStyle(fontSize: 32)),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Download the App!', style: GoogleFonts.outfit(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 2),
                              const Text('Get the app & run 10x faster!', style: TextStyle(color: Colors.white70, fontSize: 10)),
                            ],
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.all(6),
                          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.2), shape: BoxShape.circle),
                          child: const Icon(Icons.download_rounded, color: Colors.white, size: 16),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 20),
              const Divider(color: kBorder, height: 1),
              const SizedBox(height: 10),

              _drawerItem(context, Icons.logout_rounded,
                  'Sign Out / Logout', () async {
                await LocalSyncService.instance.clearAll();
                await HiveCache.clearAll();
                await PrefsCache.clearAll();
                await FirebaseAuth.instance.signOut();
              }, color: kRed),
            ]),
          ),

          // Version Info at bottom
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 16),
            child: Text('Allin1 Super App v1.0.0',
              style: TextStyle(color: kMuted.withValues(alpha: 0.5), fontSize: 10, fontWeight: FontWeight.bold)
            ),
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
        const SizedBox(
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
            child: const Text('Got it', style: TextStyle(color: kPink)),
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
                const CircularProgressIndicator(color: kPink),
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
    // Single universal reward — no random selection, no wallet/coin credit.
    const emoji = '🎉';
    const title = 'You won a Paytm Soundbox!';
    const subtitle = 'Tap below to claim your reward';
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
                        blurRadius: 10)],
                  ),
                  child: Center(child: Text('📞 Call to Claim',
                      style: GoogleFonts.outfit(
                          color: Colors.black,
                          fontSize: 15, fontWeight: FontWeight.w800))),
                ),
              ),
            ),
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

  final List<_CategorySlideData> _slides = const [
    _CategorySlideData(title: '🚕 Taxi & Transport', icons: [
      FluentEmojiFlat.motor_scooter, FluentEmojiFlat.package, FluentEmojiFlat.auto_rickshaw,
      FluentEmojiFlat.oncoming_taxi, FluentEmojiFlat.delivery_truck, FluentEmojiFlat.bicycle,
    ]),
    _CategorySlideData(title: '🍔 Food Delivery', icons: [
      FluentEmojiFlat.hamburger, FluentEmojiFlat.pizza, FluentEmojiFlat.chicken,
      FluentEmojiFlat.french_fries, FluentEmojiFlat.cup_with_straw, FluentEmojiFlat.shortcake,
    ]),
    _CategorySlideData(title: '🛒 Groceries', icons: [
      FluentEmojiFlat.leafy_green, FluentEmojiFlat.red_apple, FluentEmojiFlat.carrot,
      FluentEmojiFlat.onion, FluentEmojiFlat.garlic, FluentEmojiFlat.shopping_cart,
    ]),
    _CategorySlideData(title: '🔧 Services', icons: [
      FluentEmojiFlat.mobile_phone, FluentEmojiFlat.laptop, FluentEmojiFlat.battery,
      FluentEmojiFlat.antenna_bars, FluentEmojiFlat.hammer_and_wrench, FluentEmojiFlat.delivery_truck,
    ]),
  ];

  @override
  void initState() {
    super.initState();
    _autoScrollTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_pageController.hasClients) {
        final nextPage = (_currentIndex + 1) % _slides.length;
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
    return Column(
      children: [
        Container(
          height: 140,
          margin: const EdgeInsets.all(16),
          child: PageView.builder(
            controller: _pageController,
            onPageChanged: (index) => setState(() => _currentIndex = index),
            itemCount: _slides.length,
            itemBuilder: (_, i) {
              final slide = _slides[i];
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
            _slides.length,
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
    _timer = Timer.periodic(const Duration(milliseconds: 30), (_) {
      if (!mounted || !_controller.hasClients) return;
      final max = _controller.position.maxScrollExtent;
      if (max <= 0) return;
      final next = _controller.offset + 1.0;
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

