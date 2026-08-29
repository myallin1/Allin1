import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _kPink = Color(0xFFFF4FA3);

class AiLoadingDialog extends StatefulWidget {
  const AiLoadingDialog({super.key});

  // FIX (Aug 25 2026 — "infinite loading state" regression). ROOT CAUSE:
  // `hide()` used to call a bare `Navigator.of(context, rootNavigator:
  // true).pop()` — which pops whatever route is CURRENTLY ON TOP of the
  // stack, not "the dialog" specifically. Any action that pushes a new
  // screen (book_transport's BikeBookingScreen, navigate_to_section,
  // etc.) while this dialog is still showing puts that new screen on
  // top of the dialog. The next `hide()` call then popped that
  // freshly-opened screen instead of the dialog — the booking screen
  // closed itself immediately, and the dialog (never actually removed)
  // stayed on screen forever, reading as "stuck in infinite loading,
  // booking never completes". This existed for the pre-existing Groq
  // tool-calling path too (_actOnBookingAction also pushes while this
  // dialog is up) — the new Step-3 text pre-router just made "book a
  // bike" hit it deterministically every time instead of only when
  // Groq happened to call book_transport.
  //
  // FIX: track the exact Route this dialog was shown as, and remove
  // THAT route specifically via NavigatorState.removeRoute() — which
  // (unlike pop()) works regardless of what has been pushed on top of
  // it since. This makes `hide()` correct no matter what happens
  // between show() and hide(), including future code that navigates
  // before this dialog is dismissed. Also makes hide() safe to call
  // more than once (a no-op after the first successful removal), so
  // any call site that hides the dialog proactively (before its own
  // navigation) can never conflict with the outer `finally` block that
  // also calls hide() as a safety net.
  static Route<void>? _activeRoute;

  /// Helper to show the dialog. Safe to call while already showing —
  /// won't stack a second dialog on top of the first.
  static void show(BuildContext context) {
    if (_activeRoute != null) return;
    final navigator = Navigator.of(context, rootNavigator: true);
    // Same InheritedTheme capture showDialog() does internally — keeps
    // Theme/Directionality correct for the dialog even though it's
    // hosted on the root navigator, which is what this app's own
    // showDialog() call was implicitly relying on before this fix.
    final capturedThemes = InheritedTheme.capture(from: context, to: navigator.context);
    final route = DialogRoute<void>(
      context: context,
      barrierDismissible: false,
      barrierColor: Colors.black.withValues(alpha: 0.4),
      themes: capturedThemes,
      builder: (_) => const AiLoadingDialog(),
    );
    _activeRoute = route;
    navigator.push(route);
  }

  /// Helper to hide the dialog. Removes the exact route show() pushed,
  /// wherever it currently sits in the stack — never "whatever is on
  /// top". Safe to call when already hidden (no-op).
  static void hide(BuildContext context) {
    final route = _activeRoute;
    if (route == null) return;
    _activeRoute = null;
    if (route.isActive) {
      Navigator.of(context, rootNavigator: true).removeRoute(route);
    }
  }

  @override
  State<AiLoadingDialog> createState() => _AiLoadingDialogState();
}

class _AiLoadingDialogState extends State<AiLoadingDialog> with SingleTickerProviderStateMixin {
  int _step = 0;
  Timer? _timer;
  late final AnimationController _pulseController;

  static const List<String> _texts = [
    'wait',
    'AI processing for u',
    'Almost finish'
  ];

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // Step through the texts exactly once, without looping.
    _timer = Timer.periodic(const Duration(seconds: 2), (timer) {
      if (_step < _texts.length - 1) {
        if (mounted) setState(() => _step++);
      } else {
        timer.cancel();
      }
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _pulseController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A mini popup screen with a white theme, pink text, and thunder loading animation.
    return PopScope(
      canPop: false,
      child: Dialog(
        backgroundColor: Colors.transparent,
        elevation: 0,
        child: Center(
          child: Container(
          width: 220,
          padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(20),
            boxShadow: const [
              BoxShadow(
                color: Colors.black26,
                blurRadius: 20,
                offset: Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AnimatedBuilder(
                animation: _pulseController,
                builder: (context, child) {
                  return Transform.scale(
                    scale: 0.9 + (_pulseController.value * 0.2),
                    child: child,
                  );
                },
                child: const Icon(Icons.bolt_rounded, color: _kPink, size: 48),
              ),
              const SizedBox(height: 16),
              AnimatedSwitcher(
                duration: const Duration(milliseconds: 300),
                child: Text(
                  _texts[_step],
                  key: ValueKey<int>(_step),
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: _kPink,
                    fontSize: 16,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ));
  }
}
