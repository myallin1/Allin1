import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../services/soundbox_easter_egg_service.dart';

/// The bouncing Paytm soundbox, scoped to the Rewards screen.
///
/// This used to be mounted app-wide via a `SoundboxEasterEggOverlayScope`
/// wrapper on MaterialApp's `builder:`, which kept a per-frame Ticker
/// alive on top of EVERY screen for the whole life of the app. It now
/// mounts only where it belongs, so its animation cost is paid only
/// while the customer is actually looking at Rewards.
///
/// Drop it as the last child of the Rewards screen's Stack.
class RewardsSoundboxOverlay extends StatelessWidget {
  const RewardsSoundboxOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    // The original easter egg is fully intact: tap it 33 times and it
    // flies off and stays hidden. Only WHERE it lives changed, not what
    // it does.
    return const _BouncingSoundboxOverlay();
  }
}

// `forceVisible` used to live here, for a second copy of this overlay
// that ignored the "tapped 33 times, fly away and stay gone" easter
// egg. That variant no longer exists — the overlay is mounted in
// exactly one place (the Rewards screen) and always honours the egg —
// so the flag was dead weight that only ever took its default value.
class _BouncingSoundboxOverlay extends StatefulWidget {
  const _BouncingSoundboxOverlay();

  @override
  State<_BouncingSoundboxOverlay> createState() => _BouncingSoundboxOverlayState();
}

class _BouncingSoundboxOverlayState extends State<_BouncingSoundboxOverlay>
    with SingleTickerProviderStateMixin {
  static const double _boxWidth = 72;
  static const double _boxHeight = 72;
  static const double _speedX = 74;
  static const double _speedY = 58;

  late final Ticker _ticker;
  Duration? _lastTick;
  Offset _position = const Offset(18, 160);
  Offset _velocity = const Offset(_speedX, _speedY);
  bool _started = false;
  bool _isExiting = false;
  double _pulseScale = 1;
  double _exitProgress = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick)..start();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  void _onTick(Duration elapsed) {
    final media = MediaQuery.maybeOf(context);
    if (media == null) {
      return;
    }
    final size = media.size;
    final topInset = media.padding.top + 12;
    final bottomInset = media.padding.bottom + 88;
    final availableWidth = math.max(0, size.width - _boxWidth);
    final availableHeight =
        math.max(0, size.height - topInset - bottomInset - _boxHeight);

    if (!_started) {
      _position = Offset(
        math.min(_position.dx, availableWidth).toDouble(),
        topInset + math.min((_position.dy - topInset).clamp(0, availableHeight), availableHeight).toDouble(),
      );
      _started = true;
    }

    if (_lastTick == null) {
      _lastTick = elapsed;
      return;
    }

    final dt = (elapsed - _lastTick!).inMicroseconds / Duration.microsecondsPerSecond;
    _lastTick = elapsed;

    if (_isExiting) {
      final nextProgress = (_exitProgress + (dt / 0.65)).clamp(0.0, 1.0);
      if (nextProgress != _exitProgress && mounted) {
        setState(() {
          _exitProgress = nextProgress;
          _position = Offset(
            (_position.dx + (_velocity.dx * dt * 1.6)).clamp(0.0, availableWidth + 120),
            (_position.dy - (44 * dt)).clamp(-140.0, size.height),
          );
        });
      }
      if (_exitProgress >= 1) {
        context.read<SoundboxEasterEggService>().hideGlobally();
      }
      return;
    }

    var nextX = _position.dx + (_velocity.dx * dt);
    var nextY = _position.dy + (_velocity.dy * dt);
    var velocityX = _velocity.dx;
    var velocityY = _velocity.dy;

    if (nextX <= 0 || nextX >= availableWidth) {
      velocityX = -velocityX;
      nextX = nextX.clamp(0.0, availableWidth.toDouble());
    }
    if (nextY <= topInset || nextY >= topInset + availableHeight) {
      velocityY = -velocityY;
      nextY = nextY.clamp(topInset, topInset + availableHeight);
    }

    if (mounted) {
      setState(() {
        _position = Offset(nextX, nextY);
        _velocity = Offset(velocityX, velocityY);
        _pulseScale = 1 + (0.02 * math.sin(elapsed.inMilliseconds / 180));
      });
    }
  }

  void _handleTap() {
    HapticFeedback.lightImpact();
    final service = context.read<SoundboxEasterEggService>();
    service.registerTap(); // async — fire and forget, UI updates via notifyListeners
    setState(() {
      _pulseScale = 1.14;
    });
    Future<void>.delayed(const Duration(milliseconds: 140), () {
      if (!mounted || _isExiting) {
        return;
      }
      setState(() {
        _pulseScale = 1;
      });
    });

    if (service.tapCount >= 33 && !_isExiting) {
      setState(() {
        _isExiting = true;
        _velocity = Offset(_velocity.dx * 1.8, -96);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final hidden = context.watch<SoundboxEasterEggService>().isHiddenGlobally;
    final shouldShow = !hidden || _isExiting;
    if (!shouldShow) {
      return const SizedBox.shrink();
    }

    final exitScale = (1 - (_exitProgress * 0.82)).clamp(0.18, 1.0);
    final opacity = (1 - _exitProgress).clamp(0.0, 1.0);

    return Positioned(
      left: _position.dx,
      top: _position.dy,
      child: RepaintBoundary(
        child: IgnorePointer(
          ignoring: false,
          child: GestureDetector(
            onTap: _handleTap,
            child: Transform.scale(
              scale: _pulseScale * exitScale,
              child: Opacity(
                opacity: opacity,
                child: Container(
                  width: _boxWidth,
                  height: _boxHeight,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.96),
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(
                      color: const Color(0x66FF4FA3),
                      width: 1.4,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0x38FF4FA3),
                        blurRadius: 14,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                        child: Padding(
                          padding: const EdgeInsets.all(10),
                          child: Image.asset(
                            'assets/images/paytm_soundbox.png',
                            fit: BoxFit.contain,
                          ),
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 7,
                            vertical: 4,
                          ),
                          decoration: BoxDecoration(
                            gradient: const LinearGradient(
                              colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                            ),
                            borderRadius: BorderRadius.circular(999),
                            boxShadow: const [
                              BoxShadow(
                                color: Color(0x2EFF4FA3),
                                blurRadius: 12,
                                offset: Offset(0, 4),
                              ),
                            ],
                          ),
                          child: const Text(
                            'FREE',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 0.4,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
