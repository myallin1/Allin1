// ================================================================
// chitti_first_touch_greeter.dart — fires Chitti's spoken welcome on
// the first touch of an app session.
// ================================================================
// NEW (Aug 28 2026 — Nizam: Chitti should welcome the customer when
// the app opens).
//
// It listens for a pointer-down instead of greeting from initState
// because browsers discard speech synthesis that happens before a user
// gesture, and the customer app is a PWA. See chitti_welcome_service.dart
// for the full reasoning.
//
// Deliberately a `Listener` with `HitTestBehavior.translucent` and no
// `onPointerDown` consumption: it observes the touch on its way past
// and changes nothing about it. Whatever the user actually tapped
// receives the event exactly as it would have without this widget —
// this must never eat a button press.
//
// It also removes itself from the equation once the greeting is done:
// after that, [child] is returned bare, so there is no permanent
// listener sitting above every screen for the rest of the run.
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/chitti/chitti_welcome_service.dart';
import '../services/localization_service.dart';

class ChittiFirstTouchGreeter extends StatefulWidget {
  const ChittiFirstTouchGreeter({required this.child, super.key});

  final Widget child;

  @override
  State<ChittiFirstTouchGreeter> createState() =>
      _ChittiFirstTouchGreeterState();
}

class _ChittiFirstTouchGreeterState extends State<ChittiFirstTouchGreeter> {
  bool _done = ChittiWelcomeService.done;

  void _onFirstTouch(PointerDownEvent _) {
    if (_done) return;
    // Read the language BEFORE the async gap — the greeting has to be
    // in the language the app is actually running in, and a context
    // read after an await is both unsafe and pointless here.
    var code = 'en';
    try {
      code = context.read<LocalizationService>().languageCode;
    } catch (_) {
      // Provider not reachable this early — English is the app default.
    }
    ChittiWelcomeService.greetOnFirstTouch(code);
    setState(() => _done = true);
  }

  @override
  Widget build(BuildContext context) {
    if (_done) return widget.child;
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: _onFirstTouch,
      child: widget.child,
    );
  }
}
