// ================================================================
// ChittiOverlayService — keeps Chitti alive across screen changes
// Allin1 (Aug 19 2026)
// ================================================================
// Nizam's brief: "customer yentha section ponalum avan kuda poi antha
// service mudinjathum main page ku vanthuruvan" — he goes wherever the
// customer goes, and comes back when the job is done.
//
// WHY A ROOT OVERLAY ENTRY, NOT A WIDGET IN THE PAGE TREE
//   A companion placed inside any screen's build tree is destroyed the
//   moment that screen is popped, so he'd blink out on every
//   navigation — the exact opposite of following the customer. An
//   OverlayEntry on the ROOT navigator sits above the whole page
//   stack: pages push and pop underneath him while his State, his
//   animation controller and his drag position all survive untouched.
//
//   It also means he keeps his position. A companion that snapped back
//   to a default corner every time you opened a screen would feel like
//   a widget, not a character.
//
// WHY HE IS NOT INSIDE A Stack IN MaterialApp.builder
//   That was the simpler option and it fails on one specific thing:
//   modal bottom sheets and dialogs are themselves pushed onto the
//   root overlay, so a Stack in builder() would be painted UNDER them.
//   Chitti would vanish behind every sheet in the app — and sheets are
//   where most of this app's actual work happens.
//
// ANDROID-ONLY: every public method is a no-op elsewhere, so callers
// never need their own platform checks. See ChittiCompanion.isSupported
// for why the PWA is excluded.
// ================================================================

import 'dart:async';

import 'package:flutter/material.dart';

import '../widgets/chitti_companion.dart';
import 'chitti_memory_service.dart';

class ChittiOverlayService with WidgetsBindingObserver {
  ChittiOverlayService._();
  static final ChittiOverlayService instance = ChittiOverlayService._();

  OverlayEntry? _entry;
  final ValueNotifier<Offset> _position = ValueNotifier<Offset>(Offset.zero);
  final ValueNotifier<ChittiMood> _mood =
      ValueNotifier<ChittiMood>(ChittiMood.idle);
  final ValueNotifier<String?> _caption = ValueNotifier<String?>(null);

  // ── ENERGY LADDER (Aug 19 2026 — CTO: "Deep Sleep") ────────────
  // Nizam's requirement is that Chitti stays alive the whole time the
  // app is open; the CTO's is that he stops draining battery. Those
  // only conflict if "alive" is taken to mean "burning frames".
  //
  // So he steps DOWN through three tiers on inactivity and jumps
  // straight back to full on any sign of life:
  //
  //   interaction ──▶ active ──12s──▶ resting ──60s──▶ sleeping
  //        ▲                                              │
  //        └──────────── tap / drag / service event ◀──────┘
  //
  // Chosen over a hard on/off because a companion that simply freezes
  // reads as broken, while one that visibly calms down reads as idle.
  // Resting still moves — just slowly, and with the robot's own WebP
  // loop halted, which is where most of the cost actually was.
  final ValueNotifier<ChittiActivity> _activity =
      ValueNotifier<ChittiActivity>(ChittiActivity.active);
  Timer? _restTimer;
  Timer? _sleepTimer;

  static const Duration _kRestAfter = Duration(seconds: 12);
  static const Duration _kSleepAfter = Duration(seconds: 60);

  /// Any interaction or event wakes him and restarts the countdown.
  void wake() {
    _activity.value = ChittiActivity.active;
    _restTimer?.cancel();
    _sleepTimer?.cancel();
    _restTimer = Timer(_kRestAfter, () {
      // A live service keeps him at least resting-alert; he should not
      // fall fully asleep while a ride is in progress, because that is
      // exactly when the customer glances over to check on him.
      _activity.value = ChittiActivity.resting;
    });
    _sleepTimer = Timer(_kSleepAfter, () {
      if (ChittiMemoryService.instance.isEngaged) return;
      _activity.value = ChittiActivity.sleeping;
    });
  }

  /// The largest single saving here, and the cheapest to implement.
  ///
  /// A backgrounded app still gets frames on Android in some states,
  /// and an animated WebP keeps decoding regardless. Freezing on
  /// pause means Chitti costs literally nothing whenever the customer
  /// is not looking at the app — which, over a day, is most of it.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        wake();
      case AppLifecycleState.inactive:
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        _restTimer?.cancel();
        _sleepTimer?.cancel();
        _activity.value = ChittiActivity.sleeping;
    }
  }

  /// Tap handler supplied by the app shell (normally: open the Chitti
  /// chat screen). Held here so the overlay doesn't need a BuildContext
  /// from whichever screen happens to be on top.
  VoidCallback? onTap;

  bool get isShowing => _entry != null;

  /// Mounts Chitti above the entire navigation stack. Safe to call more
  /// than once — a second call is ignored rather than stacking a second
  /// robot, which is a real risk when this is wired to a route observer.
  void show(BuildContext context, {VoidCallback? onTapChitti}) {
    if (!ChittiCompanion.isSupported || _entry != null) return;

    onTap = onTapChitti ?? onTap;

    final overlay = Navigator.of(context, rootNavigator: true).overlay;
    if (overlay == null) return;

    // Seed to the lower-right, above the bottom navigation bar so he
    // never sits on top of the tab the customer is reaching for.
    final size = MediaQuery.of(context).size;
    _position.value = Offset(size.width - 84, size.height - 210);

    WidgetsBinding.instance.addObserver(this);
    wake();

    _entry = OverlayEntry(builder: (ctx) => _ChittiLayer(
          position: _position,
          mood: _mood,
          caption: _caption,
          activity: _activity,
          onTap: () {
            wake();
            onTap?.call();
          },
          onInteract: wake,
        ),);
    overlay.insert(_entry!);
  }

  void hide() {
    WidgetsBinding.instance.removeObserver(this);
    _restTimer?.cancel();
    _sleepTimer?.cancel();
    _entry?.remove();
    _entry = null;
  }

  /// Sends Chitti to a point on screen with his flying posture, then
  /// settles him into [settleMood]. Used when the customer asks him to
  /// take them somewhere: he visibly travels there instead of teleporting.
  Future<void> flyTo(
    Offset target, {
    ChittiMood settleMood = ChittiMood.working,
    String? caption,
  }) async {
    if (!isShowing) return;
    wake();
    _mood.value = ChittiMood.flying;
    _position.value = target;
    // Matches the AnimatedPositioned duration in _ChittiLayer. Kept as
    // a named constant in one place so the posture can never outlast
    // the movement (or end before it), which reads as a glitch.
    await Future<void>.delayed(_kFlightDuration);
    _mood.value = settleMood;
    if (caption != null) _caption.value = caption;
  }

  static const Duration _kFlightDuration = Duration(milliseconds: 900);

  /// Attaches Chitti to a live service and starts his memory for it.
  void engageService(ChittiServiceContext ctx) {
    ChittiMemoryService.instance.beginService(ctx);
    wake();
    _mood.value = ChittiMood.working;
    _caption.value = ctx.label;
  }

  /// Service finished: he dances, then returns to idle and forgets the
  /// thread. The dance is deliberately short — it's a full-brightness
  /// animation on top of whatever screen the customer is on, and a
  /// celebration that outstays its welcome becomes an obstruction.
  Future<void> completeService() async {
    if (!isShowing) {
      ChittiMemoryService.instance.endService();
      return;
    }
    wake();
    _mood.value = ChittiMood.dancing;
    _caption.value = 'Done! 🎉';
    await Future<void>.delayed(const Duration(milliseconds: 2600));
    _mood.value = ChittiMood.idle;
    _caption.value = null;
    ChittiMemoryService.instance.endService();
  }

  void setMood(ChittiMood m) => _mood.value = m;
  void setCaption(String? c) => _caption.value = c;
}

/// The draggable, animated layer itself.
///
/// Listens to three ValueNotifiers rather than taking plain values, so
/// a mood or position change repaints ONLY this layer. Calling
/// `_entry.markNeedsBuild()` instead would rebuild the overlay entry
/// wholesale and discard the companion's State — taking its animation
/// controller with it and restarting the animation from zero on every
/// single update.
class _ChittiLayer extends StatefulWidget {
  final ValueNotifier<Offset> position;
  final ValueNotifier<ChittiMood> mood;
  final ValueNotifier<String?> caption;
  final ValueNotifier<ChittiActivity> activity;
  final VoidCallback onTap;
  final VoidCallback onInteract;

  const _ChittiLayer({
    required this.position,
    required this.mood,
    required this.caption,
    required this.activity,
    required this.onTap,
    required this.onInteract,
  });

  @override
  State<_ChittiLayer> createState() => _ChittiLayerState();
}

class _ChittiLayerState extends State<_ChittiLayer> {
  static const double _kSize = 62;

  /// How much of him hangs off the screen once parked. 0.55 leaves a
  /// clearly tappable sliver — far enough out of the way to stop
  /// blocking content on a 5-inch screen, but not so far that the
  /// remaining target is hard to hit with a thumb.
  static const double _kTuckFraction = 0.55;

  /// True while he is parked against an edge. Tapping restores him
  /// before the tap is treated as "open chat", so a tucked Chitti takes
  /// two deliberate taps to open — which is what stops a half-hidden
  /// companion from firing the chat screen when the customer only
  /// meant to nudge him out of the way.
  bool _tucked = false;

  /// Snaps to whichever side is nearer once the drag ends, the way a
  /// chat-head should. Done on END, not during the drag, so he tracks
  /// the finger exactly while it's down and only settles on release.
  void _snapToNearestEdge(Size screen) {
    final pos = widget.position.value;
    final centreX = pos.dx + _kSize / 2;
    final toLeft = centreX < screen.width / 2;
    final hidden = _kSize * _kTuckFraction;
    widget.position.value = Offset(
      toLeft ? -hidden : screen.width - _kSize + hidden,
      pos.dy,
    );
    setState(() => _tucked = true);
  }

  void _untuck(Size screen) {
    final pos = widget.position.value;
    final toLeft = pos.dx < screen.width / 2;
    widget.position.value = Offset(
      toLeft ? 12 : screen.width - _kSize - 12,
      pos.dy,
    );
    setState(() => _tucked = false);
  }

  @override
  Widget build(BuildContext context) {
    final screen = MediaQuery.of(context).size;

    return ValueListenableBuilder<Offset>(
      valueListenable: widget.position,
      builder: (context, pos, _) {
        return AnimatedPositioned(
          left: pos.dx,
          top: pos.dy,
          duration: ChittiOverlayService._kFlightDuration,
          // easeInOutCubic gives the flight a sense of mass: he
          // accelerates away and decelerates into place rather than
          // sliding at a constant machine-like speed.
          curve: Curves.easeInOutCubic,
          child: AnimatedOpacity(
            // Tucked = translucent, so the half of him still on screen
            // stops competing with the content behind it. This is the
            // difference between "parked" and "in the way".
            opacity: _tucked ? 0.55 : 1.0,
            duration: const Duration(milliseconds: 250),
            child: GestureDetector(
              // Dragging updates the notifier directly. Clamped so he
              // can never be flung somewhere unreachable — there is no
              // other way to get him back.
              onPanStart: (_) {
                widget.onInteract();
                if (_tucked) setState(() => _tucked = false);
              },
              onPanUpdate: (d) {
                final next = widget.position.value + d.delta;
                widget.position.value = Offset(
                  next.dx.clamp(0.0, screen.width - _kSize),
                  next.dy.clamp(
                      MediaQuery.of(context).padding.top,
                      screen.height - _kSize - 24,),
                );
              },
              onPanEnd: (_) => _snapToNearestEdge(screen),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  ValueListenableBuilder<String?>(
                  valueListenable: widget.caption,
                  builder: (context, cap, __) {
                    if (cap == null || cap.trim().isEmpty) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      margin: const EdgeInsets.only(bottom: 4),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4,),
                      constraints: const BoxConstraints(maxWidth: 130),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.78),
                        borderRadius: BorderRadius.circular(9),
                      ),
                      child: Text(
                        cap,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    );
                  },
                ),
                  // Two notifiers, nested rather than combined, so a
                  // mood change and an energy change each repaint only
                  // what they affect.
                  ValueListenableBuilder<ChittiMood>(
                    valueListenable: widget.mood,
                    builder: (context, m, __) =>
                        ValueListenableBuilder<ChittiActivity>(
                      valueListenable: widget.activity,
                      builder: (context, act, ___) => ChittiCompanion(
                        mood: m,
                        activity: act,
                        size: _kSize,
                        // A tucked Chitti's first tap only brings him
                        // back out; the second opens the chat.
                        onTap: () {
                          widget.onInteract();
                          if (_tucked) {
                            _untuck(screen);
                            return;
                          }
                          widget.onTap();
                        },
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
