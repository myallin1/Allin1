import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/db_usage_tracker.dart';
import '../widgets/promo_overlay.dart';
import '../widgets/banner_slider.dart';
import '../widgets/server_busy_dialog.dart' show kCallCenterNumberIntl;
import '../widgets/soundbox_easter_egg_overlay.dart';
import 'guru_chat_screen.dart';
import 'erode_offers_section.dart';

const Color _paytmBlue = Color(0xFF00BAF2);
const Color _paytmDarkBlue = Color(0xFF002970);
const Color _rewardInk = Color(0xFF121A3D);
const Color _rewardPink = Color(0xFFFF4FA3);
const Color _rewardWhite = Color(0xFFFFFBFE);
const Color _aiPurple = Color(0xFF6C63FF);
const Color _aiPurpleDark = Color(0xFF3D3494);

class RewardsScreen extends StatefulWidget {
  const RewardsScreen({
    this.promoOffers = const [], this.onClaimPromo, super.key,
  });

  final List<PromoOfferItem> promoOffers;
  final Future<void> Function(String offerId)? onClaimPromo;

  @override
  State<RewardsScreen> createState() => _RewardsScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IterableProperty<PromoOfferItem>('promoOffers', promoOffers));
    properties.add(ObjectFlagProperty<Future<dynamic> Function(String offerId)>.has('onClaimPromo', onClaimPromo));
  }
}

class _RewardsScreenState extends State<RewardsScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _glowController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1450),
  )..repeat(reverse: true);

  // FIX (per Nizam's explicit request — the old rewards page was a
  // scam pattern): this used to be a scratch-card that unlocked a
  // rigged "come back tomorrow" dead end almost every time — a fake
  // reward that misled customers with no real payout. Replaced with
  // two genuine, ONE-TIME-PER-ACCOUNT quiz rewards, permanently
  // recorded on the customer's own users/{uid} doc (never resets
  // daily, never re-askable after being answered once): a Paytm quiz
  // that auto-unlocks a real cashback coupon, and an AI general-
  // knowledge quiz that unlocks a free 1-year Guru AI subscription
  // (claimed via WhatsApp to our support number, then activated
  // manually on our side).
  bool _loadingRewards = true;
  bool _paytmQuizClaimed = false;
  String? _paytmCouponCode;
  bool _aiQuizClaimed = false;

  int _topTab = 0; // 0 = Rewards, 1 = Erode Offers

  @override
  void initState() {
    super.initState();
    unawaited(_loadRewardsState());
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadRewardsState() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) setState(() => _loadingRewards = false);
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      DbUsageTracker.instance.recordRead(1);
      final data = snap.data() ?? <String, dynamic>{};
      final rewardsV2 = (data['rewardsV2'] as Map<String, dynamic>?) ?? {};

      if (!mounted) return;
      setState(() {
        _paytmQuizClaimed = rewardsV2['paytmQuizClaimed'] == true;
        _paytmCouponCode = rewardsV2['paytmCouponCode'] as String?;
        _aiQuizClaimed = rewardsV2['aiQuizClaimed'] == true;
        _loadingRewards = false;
      });
    } catch (e) {
      debugPrint('[RewardsScreen] Rewards state load failed: $e');
      if (mounted) setState(() => _loadingRewards = false);
    }
  }

  Future<void> _openPaytmQuizDialog() async {
    if (_loadingRewards || _paytmQuizClaimed) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => const _PaytmQuizDialog(),
    );
    await _loadRewardsState();
  }

  Future<void> _openAiQuizDialog() async {
    if (_loadingRewards || _aiQuizClaimed) return;
    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => const _AiQuizDialog(),
    );
    await _loadRewardsState();
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final horizontalPadding = width < 480 ? 16.0 : 28.0;

    return Stack(
      children: [
        DecoratedBox(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [
                Color(0xFFEAF9FF),
                _rewardWhite,
                Color(0xFFFFECF6),
              ],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                horizontalPadding,
                18,
                horizontalPadding,
                110,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildHeader(),
                  const SizedBox(height: 18),
                  _buildTopTabBar(),
                  const SizedBox(height: 22),
                  if (_topTab == 0) ..._buildRewardsTabContent()
                  else const ErodeOffersSection(),
                  const SizedBox(height: 40),
                ],
              ),
            ),
          ),
        ),
        // Floating Guru Bot — bottom-left
        Positioned(
          left: 16,
          bottom: 20,
          child: GestureDetector(
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (_) => const GuruChatScreen()),
              );
            },
            child: Container(
              width: 60, height: 60,
              decoration: BoxDecoration(
                color: Colors.white, shape: BoxShape.circle,
                border: Border.all(color: _paytmBlue.withValues(alpha: 0.35), width: 2),
                boxShadow: [BoxShadow(
                    color: _paytmBlue.withValues(alpha: 0.25),
                    blurRadius: 16, spreadRadius: 2)],
              ),
              child: ClipOval(
                child: Image.asset(
                  'assets/images/assistant.gif',
                  width: 46, height: 46,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Text('🤖', style: TextStyle(fontSize: 28)),
                ),
              ),
            ),
          ),
        ),
        // Bouncing Paytm soundbox. Previously mounted app-wide on
        // MaterialApp's builder, which kept its per-frame Ticker running
        // over every screen in the app. Now it lives here only, so it
        // animates while the customer is on Rewards and nowhere else.
        const RewardsSoundboxOverlay(),
      ],
    );
  }

  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_paytmDarkBlue, _paytmBlue],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(30),
        boxShadow: [
          BoxShadow(
            color: _paytmBlue.withValues(alpha: 0.32),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rewards',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 30,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Answer 2 quick one-time questions to unlock real rewards — no daily wait, no gimmicks.',
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.9),
              fontSize: 13,
              height: 1.35,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTopTabBar() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _paytmBlue.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Expanded(child: _tabButton(label: 'Rewards', icon: Icons.card_giftcard_rounded, index: 0)),
          Expanded(child: _tabButton(label: 'Erode Offers', icon: Icons.local_offer_rounded, index: 1)),
        ],
      ),
    );
  }

  Widget _tabButton({required String label, required IconData icon, required int index}) {
    final selected = _topTab == index;
    return GestureDetector(
      onTap: () => setState(() => _topTab = index),
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 12),
        decoration: BoxDecoration(
          gradient: selected
              ? const LinearGradient(colors: [_paytmDarkBlue, _paytmBlue])
              : null,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, size: 18, color: selected ? Colors.white : _rewardInk.withValues(alpha: 0.55)),
            const SizedBox(width: 6),
            Text(
              label,
              style: GoogleFonts.outfit(
                color: selected ? Colors.white : _rewardInk.withValues(alpha: 0.55),
                fontSize: 13,
                fontWeight: FontWeight.w800,
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildRewardsTabContent() {
    return [
      _QuizRewardCard(
        animation: _glowController,
        onTap: _openPaytmQuizDialog,
        loading: _loadingRewards,
        claimed: _paytmQuizClaimed,
        badgeLabel: 'PAYTM QUIZ',
        title: _paytmQuizClaimed ? 'Reward unlocked!' : 'Paytm Quiz: Win a Cashback Box',
        subtitle: _paytmQuizClaimed
            ? (_paytmCouponCode != null
                ? 'Your coupon: $_paytmCouponCode — claim at NJ TECH.'
                : 'You already answered this quiz.')
            : 'Answer 1 quick question about Paytm to unlock your free cashback box — one-time only.',
        icon: Icons.quiz_rounded,
        claimedIcon: Icons.verified_rounded,
        gradient: const [_paytmBlue, _paytmDarkBlue],
        ctaLabel: _paytmQuizClaimed ? 'Already claimed' : 'Tap to answer',
      ),
      const SizedBox(height: 16),
      _QuizRewardCard(
        animation: _glowController,
        onTap: _openAiQuizDialog,
        loading: _loadingRewards,
        claimed: _aiQuizClaimed,
        badgeLabel: 'AI QUIZ',
        title: _aiQuizClaimed ? 'Guru AI subscription claimed!' : 'AI Quiz: Win 1-Year Guru AI',
        subtitle: _aiQuizClaimed
            ? 'We\'ll activate your subscription shortly after your WhatsApp message.'
            : 'Answer 1 simple AI general-knowledge question to unlock a free 1-year Guru AI subscription — one-time only.',
        icon: Icons.psychology_alt_rounded,
        claimedIcon: Icons.verified_rounded,
        gradient: const [_aiPurple, _aiPurpleDark],
        ctaLabel: _aiQuizClaimed ? 'Already claimed' : 'Tap to answer',
      ),
      const SizedBox(height: 26),
      Text(
        'More launch rewards',
        style: GoogleFonts.outfit(
          color: _rewardInk,
          fontSize: 20,
          fontWeight: FontWeight.w900,
        ),
      ),
      const SizedBox(height: 12),
      ...widget.promoOffers.map(
        (offer) => Padding(
          padding: const EdgeInsets.only(bottom: 14),
          child: _RewardOfferTile(
            offer: offer,
            onClaim: () => widget.onClaimPromo?.call(offer.id),
          ),
        ),
      ),
      const SizedBox(height: 24),
      const BannerAdsSlider(
        height: 240,
        imageUrls: [
          'https://images.unsplash.com/photo-1555664424-778a1e5e1b48?w=800&q=80',
          'https://images.unsplash.com/photo-1593640408182-31c70c8268f5?w=800&q=80',
        ],
      ),
    ];
  }
}

class _QuizRewardCard extends StatelessWidget {
  const _QuizRewardCard({
    required this.animation,
    required this.onTap,
    required this.loading,
    required this.claimed,
    required this.badgeLabel,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.claimedIcon,
    required this.gradient,
    required this.ctaLabel,
  });

  final Animation<double> animation;
  final VoidCallback onTap;
  final bool loading;
  final bool claimed;
  final String badgeLabel;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData claimedIcon;
  final List<Color> gradient;
  final String ctaLabel;

  @override
  Widget build(BuildContext context) {
    final disabled = loading || claimed;
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final pulse = Curves.easeInOut.transform(animation.value);
        return GestureDetector(
          onTap: disabled ? null : onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 190),
            padding: const EdgeInsets.all(22),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: claimed
                    ? const [Color(0xFF8FBFA0), Color(0xFF4E7A5E)]
                    : gradient,
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(30),
              border: Border.all(color: Colors.white.withValues(alpha: 0.6), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: gradient.first.withValues(alpha: 0.26 + (claimed ? 0 : pulse * 0.16)),
                  blurRadius: claimed ? 16 : 20 + (pulse * 20),
                  spreadRadius: claimed ? 1 : 2 + (pulse * 6),
                  offset: const Offset(0, 12),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -14,
                  top: -14,
                  child: Icon(
                    claimed ? Icons.check_circle_outline_rounded : Icons.auto_awesome_rounded,
                    size: 100,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 56,
                          height: 56,
                          decoration: const BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                          ),
                          child: Icon(claimed ? claimedIcon : icon, color: gradient.last, size: 28),
                        ),
                        const SizedBox(width: 12),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            claimed ? 'CLAIMED' : badgeLabel,
                            style: GoogleFonts.outfit(
                              color: Colors.white, fontSize: 10.5,
                              fontWeight: FontWeight.w900, letterSpacing: 1.0,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    Text(
                      title,
                      style: GoogleFonts.outfit(color: Colors.white, fontSize: 19, height: 1.1, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.9), fontSize: 12.5, height: 1.35, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 14),
                    Row(
                      children: [
                        Text(ctaLabel, style: GoogleFonts.outfit(color: Colors.white, fontSize: 13, fontWeight: FontWeight.w900)),
                        if (!claimed) ...[
                          const SizedBox(width: 6),
                          const Icon(Icons.arrow_forward_rounded, color: Colors.white, size: 18),
                        ],
                      ],
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Animation<double>>('animation', animation));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
    properties.add(DiagnosticsProperty<bool>('loading', loading));
    properties.add(DiagnosticsProperty<bool>('claimed', claimed));
    properties.add(StringProperty('badgeLabel', badgeLabel));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(StringProperty('ctaLabel', ctaLabel));
  }
}

// ================================================================
// Shared quiz dialog scaffolding — question -> correct/wrong, no
// countdown timer and no daily lock (that scarcity mechanic was the
// dishonest part of the old scratch card). Each question is
// answerable exactly once per account, ever — enforced by the caller
// checking Firestore's rewardsV2.*Claimed flags before even opening
// the dialog.
// ================================================================
enum _RewardQuizStage { question, wrong, success }

class _PaytmQuizDialog extends StatefulWidget {
  const _PaytmQuizDialog();
  @override
  State<_PaytmQuizDialog> createState() => _PaytmQuizDialogState();
}

class _PaytmQuizDialogState extends State<_PaytmQuizDialog> {
  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
  _RewardQuizStage _stage = _RewardQuizStage.question;
  bool _saving = false;
  String? _couponCode;

  String _generateCouponCode() {
    final random = Random.secure();
    return List.generate(6, (_) => _chars[random.nextInt(_chars.length)]).join();
  }

  Future<void> _answer(bool correct) async {
    if (_saving) return;
    if (!correct) {
      setState(() => _stage = _RewardQuizStage.wrong);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _stage = _RewardQuizStage.wrong);
      return;
    }

    setState(() => _saving = true);
    final code = _generateCouponCode();
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'rewardsV2': {
          'paytmQuizClaimed': true,
          'paytmCouponCode': code,
          'paytmClaimedAt': FieldValue.serverTimestamp(),
        },
      }, SetOptions(merge: true));
      if (!mounted) return;
      setState(() {
        _couponCode = code;
        _saving = false;
        _stage = _RewardQuizStage.success;
      });
    } catch (e) {
      debugPrint('[RewardsScreen] Paytm quiz claim save failed: $e');
      if (mounted) {
        setState(() {
          _saving = false;
          _stage = _RewardQuizStage.wrong;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: width < 420 ? 18 : 34, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: _paytmDarkBlue.withValues(alpha: 0.28), blurRadius: 34, offset: const Offset(0, 18))],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: switch (_stage) {
              _RewardQuizStage.question => _buildQuestion(context),
              _RewardQuizStage.wrong => _buildWrong(context),
              _RewardQuizStage.success => _buildSuccess(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_paytmBlue, _paytmDarkBlue])),
          child: const Icon(Icons.quiz_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: GoogleFonts.outfit(color: _rewardInk, fontSize: 18, fontWeight: FontWeight.w900))),
        IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded), color: _rewardInk),
      ],
    );
  }

  Widget _buildQuestion(BuildContext context) {
    return Column(
      key: const ValueKey('q'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, 'Paytm Quiz'),
        const SizedBox(height: 16),
        Text(
          'What is Paytm mainly used for?',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(color: _rewardInk, fontSize: 20, height: 1.2, fontWeight: FontWeight.w900),
        ),
        const SizedBox(height: 20),
        _option('A) Digital payments & mobile recharge', Icons.account_balance_wallet_rounded, () => unawaited(_answer(true))),
        const SizedBox(height: 10),
        _option('B) Food delivery', Icons.fastfood_rounded, () => unawaited(_answer(false))),
        const SizedBox(height: 10),
        _option('C) Movie streaming', Icons.movie_rounded, () => unawaited(_answer(false))),
        if (_saving) ...[const SizedBox(height: 14), const CircularProgressIndicator(color: _paytmBlue)],
      ],
    );
  }

  Widget _option(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _saving ? null : onTap,
        icon: Icon(icon), label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _paytmDarkBlue, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  Widget _buildWrong(BuildContext context) {
    return Column(
      key: const ValueKey('wrong'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, 'Paytm Quiz'),
        const SizedBox(height: 20),
        const Icon(Icons.info_outline_rounded, color: _rewardPink, size: 64),
        const SizedBox(height: 12),
        Text('Not quite — try again!', style: GoogleFonts.outfit(color: _rewardInk, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _stage = _RewardQuizStage.question),
            style: FilledButton.styleFrom(backgroundColor: _paytmDarkBlue, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Try Again'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, 'Reward Unlocked!'),
        const SizedBox(height: 12),
        const Icon(Icons.card_giftcard_rounded, color: _rewardPink, size: 88),
        const SizedBox(height: 12),
        Text('🎉 Free Paytm Cashback Box! 🎉', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: _rewardInk, fontSize: 20, height: 1.15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 14),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(gradient: const LinearGradient(colors: [_paytmBlue, _rewardPink]), borderRadius: BorderRadius.circular(20)),
          child: Column(
            children: [
              Text('Coupon Code', style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.86), fontSize: 12, fontWeight: FontWeight.w700)),
              const SizedBox(height: 6),
              SelectableText(_couponCode ?? '------', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: Colors.white, fontSize: 28, letterSpacing: 4, fontWeight: FontWeight.w900)),
            ],
          ),
        ),
        const SizedBox(height: 12),
        Text('Claim at NJ TECH!', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: _rewardPink, fontSize: 15, fontWeight: FontWeight.w900)),
      ],
    );
  }
}

// ================================================================
// AI general-knowledge quiz -> 1-year Guru AI subscription. Correct
// answer doesn't auto-grant anything (unlike the Paytm quiz's instant
// coupon) — it unlocks a "Claim via WhatsApp" button, since activating
// a real Guru AI subscription needs a human on our side to add the
// customer's API key manually (see guru_chat_screen.dart's FIX
// comment). One WhatsApp claim, ever, per account.
// ================================================================
class _AiQuizDialog extends StatefulWidget {
  const _AiQuizDialog();
  @override
  State<_AiQuizDialog> createState() => _AiQuizDialogState();
}

class _AiQuizDialogState extends State<_AiQuizDialog> {
  _RewardQuizStage _stage = _RewardQuizStage.question;
  bool _saving = false;
  bool _claiming = false;

  void _answer(bool correct) {
    setState(() => _stage = correct ? _RewardQuizStage.success : _RewardQuizStage.wrong);
  }

  Future<void> _claimViaWhatsApp() async {
    if (_claiming) return;
    setState(() => _claiming = true);
    final user = FirebaseAuth.instance.currentUser;
    try {
      final name = (user?.displayName?.trim().isNotEmpty ?? false) ? user!.displayName!.trim() : 'Customer';
      final message = Uri.encodeComponent(
        'I claimed Guru AI subscription 🎉\nName: $name\nMobile: ${user?.phoneNumber ?? 'N/A'}\nEmail: ${user?.email ?? 'N/A'}',
      );
      final uri = Uri.parse('https://wa.me/$kCallCenterNumberIntl?text=$message');
      await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (user != null) {
        setState(() => _saving = true);
        await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
          'rewardsV2': {
            'aiQuizClaimed': true,
            'aiClaimedAt': FieldValue.serverTimestamp(),
          },
        }, SetOptions(merge: true));
      }
    } catch (e) {
      debugPrint('[RewardsScreen] AI quiz WhatsApp claim failed: $e');
    } finally {
      if (mounted) setState(() { _saving = false; _claiming = false; });
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(horizontal: width < 420 ? 18 : 34, vertical: 24),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [BoxShadow(color: _aiPurpleDark.withValues(alpha: 0.28), blurRadius: 34, offset: const Offset(0, 18))],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: switch (_stage) {
              _RewardQuizStage.question => _buildQuestion(context),
              _RewardQuizStage.wrong => _buildWrong(context),
              _RewardQuizStage.success => _buildSuccess(context),
            },
          ),
        ),
      ),
    );
  }

  Widget _header(BuildContext context, String title) {
    return Row(
      children: [
        Container(
          width: 44, height: 44,
          decoration: const BoxDecoration(shape: BoxShape.circle, gradient: LinearGradient(colors: [_aiPurple, _aiPurpleDark])),
          child: const Icon(Icons.psychology_alt_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(child: Text(title, style: GoogleFonts.outfit(color: _rewardInk, fontSize: 18, fontWeight: FontWeight.w900))),
        IconButton(onPressed: () => Navigator.of(context).pop(), icon: const Icon(Icons.close_rounded), color: _rewardInk),
      ],
    );
  }

  Widget _buildQuestion(BuildContext context) {
    return Column(
      key: const ValueKey('q'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, 'AI Quiz'),
        const SizedBox(height: 16),
        Text('What does "AI" stand for?', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: _rewardInk, fontSize: 20, height: 1.2, fontWeight: FontWeight.w900)),
        const SizedBox(height: 20),
        _option('A) Artificial Intelligence', Icons.smart_toy_rounded, () => _answer(true)),
        const SizedBox(height: 10),
        _option('B) Automated Internet', Icons.wifi_rounded, () => _answer(false)),
        const SizedBox(height: 10),
        _option('C) Advanced Interface', Icons.window_rounded, () => _answer(false)),
      ],
    );
  }

  Widget _option(String label, IconData icon, VoidCallback onTap) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: onTap,
        icon: Icon(icon), label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _aiPurpleDark, foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          textStyle: GoogleFonts.outfit(fontSize: 14, fontWeight: FontWeight.w800),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          alignment: Alignment.centerLeft,
        ),
      ),
    );
  }

  Widget _buildWrong(BuildContext context) {
    return Column(
      key: const ValueKey('wrong'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, 'AI Quiz'),
        const SizedBox(height: 20),
        const Icon(Icons.info_outline_rounded, color: _aiPurple, size: 64),
        const SizedBox(height: 12),
        Text('Not quite — try again!', style: GoogleFonts.outfit(color: _rewardInk, fontSize: 20, fontWeight: FontWeight.w900)),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton(
            onPressed: () => setState(() => _stage = _RewardQuizStage.question),
            style: FilledButton.styleFrom(backgroundColor: _aiPurpleDark, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14)),
            child: const Text('Try Again'),
          ),
        ),
      ],
    );
  }

  Widget _buildSuccess(BuildContext context) {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _header(context, 'Reward Unlocked!'),
        const SizedBox(height: 12),
        const Icon(Icons.workspace_premium_rounded, color: _aiPurple, size: 88),
        const SizedBox(height: 12),
        Text('🎉 1-Year Guru AI Subscription! 🎉', textAlign: TextAlign.center, style: GoogleFonts.outfit(color: _rewardInk, fontSize: 19, height: 1.15, fontWeight: FontWeight.w900)),
        const SizedBox(height: 8),
        Text(
          'Tap below to message us on WhatsApp — we\'ll activate your subscription shortly after.',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(color: _rewardInk.withValues(alpha: 0.64), fontSize: 13, height: 1.35, fontWeight: FontWeight.w600),
        ),
        const SizedBox(height: 16),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            onPressed: _claiming ? null : () => unawaited(_claimViaWhatsApp()),
            icon: _saving
                ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.chat_rounded),
            label: Text(_claiming ? 'Opening WhatsApp...' : 'Claim via WhatsApp'),
            style: FilledButton.styleFrom(
              backgroundColor: const Color(0xFF25D366), foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 14),
              textStyle: GoogleFonts.outfit(fontSize: 15, fontWeight: FontWeight.w900),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            ),
          ),
        ),
      ],
    );
  }
}

class _RewardOfferTile extends StatelessWidget {
  const _RewardOfferTile({
    required this.offer,
    required this.onClaim,
  });

  final PromoOfferItem offer;
  final VoidCallback? onClaim;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _paytmBlue.withValues(alpha: 0.18)),
        boxShadow: [
          BoxShadow(
            color: _paytmBlue.withValues(alpha: 0.12),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              gradient: const LinearGradient(
                colors: [_rewardPink, _paytmBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(18),
            ),
            child: Icon(offer.icon, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  offer.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: _rewardInk,
                    fontSize: 16,
                    fontWeight: FontWeight.w900,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  offer.subtitle,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                    color: _rewardInk.withValues(alpha: 0.62),
                    fontSize: 12,
                    height: 1.3,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 12),
          FilledButton(
            onPressed: offer.claimed ? null : onClaim,
            style: FilledButton.styleFrom(
              backgroundColor: _paytmDarkBlue,
              disabledBackgroundColor: _paytmBlue.withValues(alpha: 0.22),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
            ),
            child: Text(
              offer.claimed ? offer.claimedButtonLabel : offer.buttonLabel,
              style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<PromoOfferItem>('offer', offer));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onClaim', onClaim));
  }
}

// FLOATING GIFT BOX (removed) — this was a second entry point into the
// same rigged "come back tomorrow" scratch-card dead end as the old
// _GlowingPaytmQuizCard, per Nizam's request to remove that scam
// pattern entirely. The two _QuizRewardCard tiles above are now the
// only reward entry points, and the floating Guru Bot button (kept, in
// build() above) is legitimate navigation, not a reward mechanic.
