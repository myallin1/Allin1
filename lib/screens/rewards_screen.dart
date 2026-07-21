import 'dart:async';
import 'dart:math';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:lottie/lottie.dart';
import 'package:scratcher/scratcher.dart';

import '../widgets/promo_overlay.dart';
import '../widgets/banner_slider.dart';
import '../widgets/soundbox_easter_egg_overlay.dart';
import 'guru_chat_screen.dart';

const Color _paytmBlue = Color(0xFF00BAF2);
const Color _paytmDarkBlue = Color(0xFF002970);
const Color _rewardInk = Color(0xFF121A3D);
const Color _rewardPink = Color(0xFFFF4FA3);
const Color _rewardWhite = Color(0xFFFFFBFE);
const String _quizReward = 'Free Tempered Glass / ₹200 Off!';

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

  bool _checkingQuizLock = true;
  bool _quizLockedForToday = false;
  String? _activeCouponCode;

  @override
  void initState() {
    super.initState();
    unawaited(_loadQuizLock());
  }

  @override
  void dispose() {
    _glowController.dispose();
    super.dispose();
  }

  Future<void> _loadQuizLock() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        setState(() => _checkingQuizLock = false);
      }
      return;
    }

    try {
      final snap = await FirebaseFirestore.instance
          .collection('users')
          .doc(user.uid)
          .get();
      final data = snap.data() ?? <String, dynamic>{};
      final lastQuizWonAt = data['lastQuizWonAt'];
      final activeCoupon = data['activeCoupon'];
      final locked = lastQuizWonAt is Timestamp &&
          DateTime.now().difference(lastQuizWonAt.toDate()) <
              const Duration(hours: 24);

      if (!mounted) return;
      setState(() {
        _quizLockedForToday = locked;
        _activeCouponCode = activeCoupon is Map<String, dynamic>
            ? activeCoupon['code'] as String?
            : null;
        _checkingQuizLock = false;
      });
    } catch (e) {
      debugPrint('[RewardsScreen] Quiz lock check failed: $e');
      if (mounted) {
        setState(() => _checkingQuizLock = false);
      }
    }
  }

  Future<void> _openPaytmQuizScratchDialog() async {
    if (_checkingQuizLock) return;

    if (_quizLockedForToday) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Come back tomorrow for your next reward!'),
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    await showDialog<void>(
      context: context,
      barrierColor: Colors.black.withValues(alpha: 0.62),
      builder: (context) => const _PaytmQuizScratchDialog(),
    );
    await _loadQuizLock();
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
                  const SizedBox(height: 22),
                  _GlowingPaytmQuizCard(
                    animation: _glowController,
                    onTap: _openPaytmQuizScratchDialog,
                    disabled: _checkingQuizLock || _quizLockedForToday,
                    lockedMessage: _quizLockedForToday
                        ? 'Come back tomorrow for your next reward!'
                        : 'Checking reward status...',
                    couponCode: _activeCouponCode,
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
        // Floating Gift Box — bottom-right
        Positioned(
          right: 16,
          bottom: 20,
          child: _RewardsFloatingGiftBox(onTap: _openPaytmQuizScratchDialog),
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
            'Tap the glowing Paytm quiz card, scratch the cover, and unlock your entry.',
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
}

class _GlowingPaytmQuizCard extends StatelessWidget {
  const _GlowingPaytmQuizCard({
    required this.animation,
    required this.onTap,
    required this.disabled,
    required this.lockedMessage,
    this.couponCode,
  });

  final Animation<double> animation;
  final VoidCallback onTap;
  final bool disabled;
  final String lockedMessage;
  final String? couponCode;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      builder: (context, _) {
        final pulse = Curves.easeInOut.transform(animation.value);
        return GestureDetector(
          onTap: disabled ? null : onTap,
          child: Container(
            width: double.infinity,
            constraints: const BoxConstraints(minHeight: 230),
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: disabled
                    ? const [Color(0xFFB8C7D9), Color(0xFF667A94)]
                    : const [_paytmBlue, _paytmDarkBlue],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
              borderRadius: BorderRadius.circular(34),
              border: Border.all(
                color: Colors.white.withValues(alpha: 0.62),
                width: 1.4,
              ),
              boxShadow: [
                BoxShadow(
                  color: (disabled ? Colors.blueGrey : _paytmBlue).withValues(
                    alpha: 0.28 + (pulse * 0.18),
                  ),
                  blurRadius: disabled ? 18 : 24 + (pulse * 26),
                  spreadRadius: disabled ? 1 : 2 + (pulse * 9),
                  offset: const Offset(0, 16),
                ),
                BoxShadow(
                  color: _paytmDarkBlue.withValues(alpha: 0.32),
                  blurRadius: 20,
                  offset: const Offset(0, 10),
                ),
              ],
            ),
            child: Stack(
              children: [
                Positioned(
                  right: -18,
                  top: -18,
                  child: Icon(
                    disabled
                        ? Icons.lock_clock_rounded
                        : Icons.auto_awesome_rounded,
                    size: 128,
                    color: Colors.white.withValues(alpha: 0.14),
                  ),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 74,
                          height: 74,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: Colors.white,
                            boxShadow: [
                              BoxShadow(
                                color: Colors.white.withValues(alpha: 0.46),
                                blurRadius: 24,
                                spreadRadius: 3,
                              ),
                            ],
                          ),
                          child: Icon(
                            disabled
                                ? Icons.verified_rounded
                                : Icons.quiz_rounded,
                            color: _paytmDarkBlue,
                            size: 38,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 12,
                            vertical: 7,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.38),
                            ),
                          ),
                          child: Text(
                            disabled ? 'DAILY LOCK' : 'SCRATCH QUIZ',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 11,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.1,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    Text(
                      disabled
                          ? 'Reward locked for today'
                          : 'Paytm Quiz: Win Upto ₹500',
                      style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 28,
                        height: 1.05,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      disabled
                          ? couponCode == null
                              ? lockedMessage
                              : '$lockedMessage\nActive coupon: $couponCode'
                          : 'Scratch now to unlock your NJ TECH quiz entry and gift box.',
                      style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.9),
                        fontSize: 14,
                        height: 1.35,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Row(
                      children: [
                        Text(
                          disabled ? 'Daily reward claimed' : 'Tap to scratch',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 14,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                        const SizedBox(width: 8),
                        const Icon(
                          Icons.arrow_forward_rounded,
                          color: Colors.white,
                          size: 20,
                        ),
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
    properties.add(DiagnosticsProperty<bool>('disabled', disabled));
    properties.add(StringProperty('lockedMessage', lockedMessage));
    properties.add(StringProperty('couponCode', couponCode));
  }
}

enum _QuizDialogStage { scratch, quiz, success, timeout, wrong }

class _PaytmQuizScratchDialog extends StatefulWidget {
  const _PaytmQuizScratchDialog();

  @override
  State<_PaytmQuizScratchDialog> createState() =>
      _PaytmQuizScratchDialogState();
}

class _PaytmQuizScratchDialogState extends State<_PaytmQuizScratchDialog> {
  static const String _giftBoxLottieUrl =
      'https://assets2.lottiefiles.com/packages/lf20_touohxv0.json';
  static const String _chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';

  Timer? _quizTimer;
  _QuizDialogStage _stage = _QuizDialogStage.scratch;
  int _secondsLeft = 15;
  bool _savingWin = false;
  String? _couponCode;

  @override
  void dispose() {
    _quizTimer?.cancel();
    super.dispose();
  }

  void _startQuiz() {
    if (_stage != _QuizDialogStage.scratch) return;
    setState(() {
      _stage = _QuizDialogStage.quiz;
      _secondsLeft = 15;
    });
    _quizTimer?.cancel();
    _quizTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        setState(() {
          _secondsLeft = 0;
          _stage = _QuizDialogStage.timeout;
        });
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  String _generateCouponCode() {
    final random = Random.secure();
    return List.generate(
      6,
      (_) => _chars[random.nextInt(_chars.length)],
    ).join();
  }

  Future<void> _answerQuiz(bool isNjTech) async {
    if (_stage != _QuizDialogStage.quiz || _secondsLeft <= 0 || _savingWin) {
      return;
    }
    _quizTimer?.cancel();

    if (!isNjTech) {
      setState(() => _stage = _QuizDialogStage.wrong);
      return;
    }

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      setState(() => _stage = _QuizDialogStage.wrong);
      return;
    }

    setState(() => _savingWin = true);
    final code = _generateCouponCode();
    final expiresAt = DateTime.now().add(const Duration(hours: 48));
    try {
      await FirebaseFirestore.instance.collection('users').doc(user.uid).set({
        'lastQuizWonAt': FieldValue.serverTimestamp(),
        'activeCoupon': {
          'code': code,
          'reward': _quizReward,
          'source': 'paytm_quiz',
          'expiresAt': Timestamp.fromDate(expiresAt),
          'createdAt': FieldValue.serverTimestamp(),
          'status': 'active',
        },
      }, SetOptions(merge: true),);
      if (!mounted) return;
      setState(() {
        _couponCode = code;
        _savingWin = false;
        _stage = _QuizDialogStage.success;
      });
    } catch (e) {
      debugPrint('[RewardsScreen] Quiz win save failed: $e');
      if (mounted) {
        setState(() {
          _savingWin = false;
          _stage = _QuizDialogStage.wrong;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return Dialog(
      insetPadding: EdgeInsets.symmetric(
        horizontal: width < 420 ? 18 : 34,
        vertical: 24,
      ),
      backgroundColor: Colors.transparent,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 460),
        child: Container(
          padding: const EdgeInsets.all(18),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(30),
            boxShadow: [
              BoxShadow(
                color: _paytmDarkBlue.withValues(alpha: 0.28),
                blurRadius: 34,
                offset: const Offset(0, 18),
              ),
            ],
          ),
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 320),
            child: _buildStageContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildStageContent(BuildContext context) {
    return switch (_stage) {
      _QuizDialogStage.scratch => _buildScratchContent(context),
      _QuizDialogStage.quiz => _buildQuizContent(context),
      _QuizDialogStage.success => _buildSuccessContent(context),
      _QuizDialogStage.timeout => _buildMessageContent(
          context,
          icon: Icons.timer_off_rounded,
          title: "Time's up! Try again tomorrow.",
          subtitle: 'The 15-second quiz window closed.',
        ),
      _QuizDialogStage.wrong => _buildMessageContent(
          context,
          icon: Icons.info_outline_rounded,
          title: 'Try again tomorrow.',
          subtitle: 'Hint: NJ TECH is the service center to remember.',
        ),
    };
  }

  Widget _dialogHeader(BuildContext context, String title) {
    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: const BoxDecoration(
            shape: BoxShape.circle,
            gradient: LinearGradient(colors: [_paytmBlue, _paytmDarkBlue]),
          ),
          child: const Icon(Icons.card_giftcard_rounded, color: Colors.white),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.outfit(
              color: _rewardInk,
              fontSize: 19,
              fontWeight: FontWeight.w900,
            ),
          ),
        ),
        IconButton(
          onPressed: () => Navigator.of(context).pop(),
          icon: const Icon(Icons.close_rounded),
          color: _rewardInk,
        ),
      ],
    );
  }

  Widget _buildScratchContent(BuildContext context) {
    return Column(
      key: const ValueKey('scratch'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _dialogHeader(context, 'Paytm Quiz Scratch'),
        const SizedBox(height: 14),
        ClipRRect(
          borderRadius: BorderRadius.circular(24),
          child: Scratcher(
            brushSize: 42,
            threshold: 50,
            color: _paytmBlue,
            onThreshold: _startQuiz,
            child: Container(
              width: double.infinity,
              height: 250,
              padding: const EdgeInsets.all(22),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_paytmDarkBlue, _paytmBlue],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(
                    Icons.emoji_events_rounded,
                    color: Colors.white,
                    size: 58,
                  ),
                  const SizedBox(height: 18),
                  Text(
                    'Quiz Entry',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 26,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'Congratulations! Answer this simple NJ TECH question to unlock your ₹500 / Gift Box.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 14,
                      height: 1.35,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
        const SizedBox(height: 12),
        _scratchHint(),
      ],
    );
  }

  Widget _scratchHint() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: _paytmDarkBlue,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.touch_app_rounded, color: Colors.white, size: 18),
          const SizedBox(width: 8),
          Text(
            'Scratch Here',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontSize: 14,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildQuizContent(BuildContext context) {
    return Column(
      key: const ValueKey('quiz'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _dialogHeader(context, '15 Second Quiz'),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: _rewardPink.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _rewardPink.withValues(alpha: 0.28)),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.timer_rounded, color: _rewardPink),
              const SizedBox(width: 8),
              Text(
                '$_secondsLeft seconds left',
                style: GoogleFonts.outfit(
                  color: _rewardPink,
                  fontSize: 17,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 20),
        Text(
          'What is the best Mobile & Laptop Service Center in Erode?',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: _rewardInk,
            fontSize: 22,
            height: 1.18,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 22),
        _quizOption(
          label: 'A) NJ TECH',
          icon: Icons.workspace_premium_rounded,
          onTap: () => unawaited(_answerQuiz(true)),
        ),
        const SizedBox(height: 12),
        _quizOption(
          label: 'B) Others',
          icon: Icons.storefront_rounded,
          onTap: () => unawaited(_answerQuiz(false)),
        ),
        if (_savingWin) ...[
          const SizedBox(height: 16),
          const CircularProgressIndicator(color: _paytmBlue),
        ],
      ],
    );
  }

  Widget _quizOption({
    required String label,
    required IconData icon,
    required VoidCallback onTap,
  }) {
    return SizedBox(
      width: double.infinity,
      child: FilledButton.icon(
        onPressed: _savingWin ? null : onTap,
        icon: Icon(icon),
        label: Text(label),
        style: FilledButton.styleFrom(
          backgroundColor: _paytmDarkBlue,
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 16),
          textStyle: GoogleFonts.outfit(
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
        ),
      ),
    );
  }

  Widget _buildSuccessContent(BuildContext context) {
    return Column(
      key: const ValueKey('success'),
      mainAxisSize: MainAxisSize.min,
      children: [
        _dialogHeader(context, 'Gift Box Unlocked'),
        SizedBox(
          height: 190,
          child: Lottie.network(
            _giftBoxLottieUrl,
            repeat: false,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Icon(
              Icons.card_giftcard_rounded,
              color: _rewardPink,
              size: 112,
            ),
          ),
        ),
        Text(
          '🎉 YOU WON! 🎉\n$_quizReward',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: _rewardInk,
            fontSize: 24,
            height: 1.15,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 16),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [_paytmBlue, _rewardPink]),
            borderRadius: BorderRadius.circular(22),
          ),
          child: Column(
            children: [
              Text(
                'Coupon Code',
                style: GoogleFonts.outfit(
                  color: Colors.white.withValues(alpha: 0.86),
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 6),
              SelectableText(
                _couponCode ?? '------',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 30,
                  letterSpacing: 4,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 14),
        Text(
          'Claim at NJ TECH within 48 Hours!',
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: _rewardPink,
            fontSize: 16,
            fontWeight: FontWeight.w900,
          ),
        ),
      ],
    );
  }

  Widget _buildMessageContent(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Column(
      key: ValueKey(title),
      mainAxisSize: MainAxisSize.min,
      children: [
        _dialogHeader(context, 'Paytm Quiz'),
        const SizedBox(height: 22),
        Icon(icon, color: _rewardPink, size: 72),
        const SizedBox(height: 16),
        Text(
          title,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: _rewardInk,
            fontSize: 24,
            fontWeight: FontWeight.w900,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          subtitle,
          textAlign: TextAlign.center,
          style: GoogleFonts.outfit(
            color: _rewardInk.withValues(alpha: 0.64),
            fontSize: 14,
            height: 1.35,
            fontWeight: FontWeight.w600,
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

// ================================================================
// FLOATING GIFT BOX — Rewards Tab
// ================================================================
class _RewardsFloatingGiftBox extends StatefulWidget {
  final VoidCallback onTap;
  const _RewardsFloatingGiftBox({required this.onTap});
  @override
  State<_RewardsFloatingGiftBox> createState() => _RewardsFloatingGiftBoxState();
}

class _RewardsFloatingGiftBoxState extends State<_RewardsFloatingGiftBox>
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
