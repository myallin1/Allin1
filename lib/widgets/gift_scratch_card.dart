// ================================================================
// gift_scratch_card.dart — the customer-facing scratch card for one
// gift coupon. Rendered in the "My Gift Coupons" section of
// rewards_screen.dart.
//
// FOUR VISUAL STATES, driven entirely by the coupon's server-side
// status + unlock timer (see lib/models/gift_coupon_model.dart):
//   awaiting_gift  -> "preparing your gift" (admin hasn't set it yet)
//   ready, locked  -> live countdown to when it can be scratched
//   ready, unlocked-> the real thing: a foil the customer rubs off
//   scratched      -> the revealed gift, plus how to use it
//
// THE GIFT IS NOT IN THIS WIDGET UNTIL THE SERVER SENDS IT, and that
// is true all the way down: an unscratched coupon doc genuinely has no
// giftType/value/giftLabel on it — the prize sits in the admin-only
// `gift_coupon_gifts` collection the customer cannot read, and
// scratchGiftCoupon copies it across only after checking the unlock
// timer against the SERVER clock. The call fires on the first touch,
// so the answer is usually back by the time enough foil is gone.
//
// Net effect: patching this app or winding the device clock forward
// reveals nothing, because there is nothing local to reveal.
// ================================================================
import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/gift_coupon_model.dart';
import '../services/gift_coupon_service.dart';

const Color _gold = Color(0xFFFFC107);
const Color _goldDeep = Color(0xFFFF8F00);

class GiftScratchCard extends StatefulWidget {
  const GiftScratchCard({
    required this.coupon,
    required this.service,
    this.onRevealed,
    super.key,
  });

  final GiftCouponModel coupon;
  final GiftCouponService service;

  /// Fired once the gift has been successfully revealed, so the parent
  /// can celebrate (snackbar, confetti, refresh).
  final void Function(GiftCouponReveal reveal)? onRevealed;

  @override
  State<GiftScratchCard> createState() => _GiftScratchCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<GiftCouponModel>('coupon', coupon));
    properties.add(DiagnosticsProperty<GiftCouponService>('service', service));
    properties.add(ObjectFlagProperty<void Function(GiftCouponReveal)?>.has(
        'onRevealed', onRevealed,));
  }
}

class _GiftScratchCardState extends State<GiftScratchCard> {
  /// Completed strokes plus the one in progress. Kept as separate
  /// strokes so lifting a finger doesn't draw a straight line across
  /// the card to wherever it lands next.
  final List<List<Offset>> _strokes = [];

  /// Coarse occupancy grid used to decide "scratched enough" — far
  /// more reliable than counting points, which depends on how fast the
  /// finger moved.
  static const int _gridCols = 12;
  static const int _gridRows = 6;
  static const double _revealFraction = 0.32;
  final Set<int> _touchedCells = {};

  GiftCouponReveal? _reveal;
  bool _requested = false;
  bool _failed = false;
  String? _error;

  Timer? _countdownTimer;

  @override
  void initState() {
    super.initState();
    _syncCountdownTimer();
  }

  @override
  void didUpdateWidget(covariant GiftScratchCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncCountdownTimer();
  }

  /// Only tick while a countdown is actually on screen — a permanent
  /// 1s timer per card would keep this whole tab rebuilding forever.
  void _syncCountdownTimer() {
    final needsTicking = widget.coupon.status != GiftCouponStatus.scratched &&
        !widget.coupon.isUnlocked;
    if (needsTicking && _countdownTimer == null) {
      _countdownTimer = Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else if (!needsTicking) {
      _countdownTimer?.cancel();
      _countdownTimer = null;
    }
  }

  @override
  void dispose() {
    _countdownTimer?.cancel();
    super.dispose();
  }

  Future<void> _requestReveal() async {
    if (_requested) return;
    _requested = true;
    try {
      final reveal = await widget.service.scratch(widget.coupon.id);
      if (!mounted) return;
      setState(() => _reveal = reveal);
      widget.onRevealed?.call(reveal);
    } catch (e) {
      debugPrint('[GiftScratchCard] scratch failed: $e');
      if (!mounted) return;
      setState(() {
        _failed = true;
        _error = e.toString().replaceFirst('Exception: ', '');
        // Put the foil back — nothing was revealed.
        _strokes.clear();
        _touchedCells.clear();
        _requested = false;
      });
    }
  }

  void _registerPoint(Offset point, Size size) {
    final col = (point.dx / size.width * _gridCols).floor();
    final row = (point.dy / size.height * _gridRows).floor();
    if (col < 0 || col >= _gridCols || row < 0 || row >= _gridRows) return;
    _touchedCells.add(row * _gridCols + col);
  }

  bool get _scratchedEnough =>
      _touchedCells.length / (_gridCols * _gridRows) >= _revealFraction;

  @override
  Widget build(BuildContext context) {
    final coupon = widget.coupon;

    if (coupon.status == GiftCouponStatus.scratched) {
      return _shell(child: _revealedContent(coupon.giftDescription, coupon));
    }
    if (coupon.status == GiftCouponStatus.awaitingGift) {
      return _shell(
        child: _lockedContent(
          icon: Icons.auto_awesome_rounded,
          title: 'Your gift is being prepared',
          subtitle: coupon.sourceSummary.isNotEmpty
              ? 'Earned from ${coupon.sourceSummary} — check back soon!'
              : 'Check back soon to scratch it open!',
        ),
      );
    }
    if (coupon.isCountingDown) {
      return _shell(
        child: _lockedContent(
          icon: Icons.lock_clock_rounded,
          title: 'Unlocks in ${_formatDuration(coupon.timeUntilUnlock)}',
          subtitle: coupon.sourceSummary.isNotEmpty
              ? 'A gift for your ${coupon.sourceSummary}'
              : 'Come back when the timer ends to scratch it open!',
        ),
      );
    }
    // ready + unlocked -> scratchable, unless we already revealed it in
    // this session (the Firestore stream usually catches up a beat later).
    if (_reveal != null && _scratchedEnough) {
      return _shell(child: _revealedContent(_reveal!.giftDescription, coupon));
    }
    return _shell(child: _scratchableContent(coupon));
  }

  // ── SHELL ───────────────────────────────────────────────────────
  Widget _shell({required Widget child}) {
    return Container(
      width: double.infinity,
      constraints: const BoxConstraints(minHeight: 132),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_gold, _goldDeep],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(22),
        boxShadow: [
          BoxShadow(
            color: _goldDeep.withValues(alpha: 0.3),
            blurRadius: 20,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(22),
        child: child,
      ),
    );
  }

  // ── STATES ──────────────────────────────────────────────────────
  Widget _lockedContent({
    required IconData icon,
    required String title,
    required String subtitle,
  }) {
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,),
            child: Icon(icon, color: _goldDeep, size: 26),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 17,
                        fontWeight: FontWeight.w900,),),
                const SizedBox(height: 3),
                Text(subtitle,
                    style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 12,
                        height: 1.3,
                        fontWeight: FontWeight.w600,),),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _revealedContent(String gift, GiftCouponModel coupon) {
    final isDiscount = (_reveal?.isDiscount ?? false) ||
        coupon.giftType == GiftCouponType.discount;
    return Padding(
      padding: const EdgeInsets.all(18),
      child: Row(
        children: [
          Container(
            width: 52,
            height: 52,
            decoration: const BoxDecoration(
                shape: BoxShape.circle, color: Colors.white,),
            child: const Icon(Icons.card_giftcard_rounded,
                color: _goldDeep, size: 26,),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('🎉 You won!',
                    style: GoogleFonts.outfit(
                        color: Colors.white.withValues(alpha: 0.92),
                        fontSize: 11.5,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.5,),),
                const SizedBox(height: 2),
                Text(gift.isNotEmpty ? gift : 'Your gift',
                    style: GoogleFonts.outfit(
                        color: Colors.white,
                        fontSize: 20,
                        height: 1.1,
                        fontWeight: FontWeight.w900,),),
                const SizedBox(height: 4),
                Text(
                  isDiscount
                      ? 'Apply it on your next Hero task bill or Hotel order.'
                      : 'Show this at NJ TECH to collect your gift.',
                  style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontSize: 11.5,
                      height: 1.3,
                      fontWeight: FontWeight.w600,),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _scratchableContent(GiftCouponModel coupon) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = Size(constraints.maxWidth, 132);
        return SizedBox(
          height: 132,
          width: constraints.maxWidth,
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Underneath the foil: whatever the server has told us so
              // far. Until the call returns this is a placeholder — the
              // app genuinely doesn't know the gift yet.
              Padding(
                padding: const EdgeInsets.all(18),
                child: Center(
                  child: _reveal != null
                      ? Text(_reveal!.giftDescription,
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.w900,),)
                      : Text(
                          _failed ? (_error ?? 'Try again') : '🎁',
                          textAlign: TextAlign.center,
                          style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: _failed ? 13 : 30,
                              fontWeight: FontWeight.w800,),
                        ),
                ),
              ),
              // The foil.
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onPanStart: (details) {
                  unawaited(_requestReveal());
                  setState(() {
                    _failed = false;
                    _strokes.add([details.localPosition]);
                    _registerPoint(details.localPosition, size);
                  });
                },
                onPanUpdate: (details) {
                  setState(() {
                    if (_strokes.isEmpty) _strokes.add([]);
                    _strokes.last.add(details.localPosition);
                    _registerPoint(details.localPosition, size);
                  });
                },
                onPanEnd: (_) {
                  // Once they've cleared enough, drop the rest of the
                  // foil for them rather than making them rub every
                  // last corner.
                  if (_scratchedEnough && _reveal != null) {
                    setState(() {});
                  }
                },
                child: CustomPaint(
                  painter: _FoilPainter(
                    strokes: _strokes,
                    strokeWidth: 34,
                  ),
                  child: _strokes.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.touch_app_rounded,
                                  color: Colors.white, size: 28,),
                              const SizedBox(height: 6),
                              Text('Scratch to reveal your gift!',
                                  style: GoogleFonts.outfit(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w900,),),
                              if (coupon.sourceSummary.isNotEmpty) ...[
                                const SizedBox(height: 2),
                                Text('Earned from ${coupon.sourceSummary}',
                                    style: GoogleFonts.outfit(
                                        color:
                                            Colors.white.withValues(alpha: 0.9),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w600,),),
                              ],
                            ],
                          ),
                        )
                      : const SizedBox.expand(),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  static String _formatDuration(Duration d) {
    if (d.inHours >= 1) {
      return '${d.inHours}h ${d.inMinutes % 60}m';
    }
    if (d.inMinutes >= 1) {
      return '${d.inMinutes}m ${d.inSeconds % 60}s';
    }
    return '${d.inSeconds}s';
  }
}

/// Paints the silver foil and erases it along the customer's strokes
/// using a `BlendMode.clear` layer, so what's underneath shows through.
class _FoilPainter extends CustomPainter {
  const _FoilPainter({required this.strokes, required this.strokeWidth});

  final List<List<Offset>> strokes;
  final double strokeWidth;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // saveLayer is required — BlendMode.clear needs its own layer, or
    // it would punch a hole through everything painted beneath it.
    canvas.saveLayer(rect, Paint());

    final foil = Paint()
      ..shader = const LinearGradient(
        colors: [Color(0xFFBFC5D2), Color(0xFF8E97A8), Color(0xFFBFC5D2)],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ).createShader(rect);
    canvas.drawRect(rect, foil);

    final eraser = Paint()
      ..blendMode = BlendMode.clear
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;

    for (final stroke in strokes) {
      if (stroke.isEmpty) continue;
      if (stroke.length == 1) {
        canvas.drawCircle(stroke.first, strokeWidth / 2,
            Paint()..blendMode = BlendMode.clear,);
        continue;
      }
      final path = Path()..moveTo(stroke.first.dx, stroke.first.dy);
      for (final point in stroke.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, eraser);
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _FoilPainter oldDelegate) => true;
}
