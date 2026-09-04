// ================================================================
// chitti_call_screen_test.dart
// ================================================================
// WHY THE TIMEOUT DURATION IS SET BEFORE EVERY TEST, AND WHY THAT
// MATTERS MORE THAN IT LOOKS
// speech_to_text and flutter_tts have no platform implementation in
// this test environment, so ChittiCallScreen.initState's connect
// sequence never resolves on its own — it only ever moves off
// "Connecting..." once its own timeout fires (see initTimeout on the
// screen itself). flutter_test enforces zero pending Timers at the end
// of every test, unconditionally, so a test that pumps forward without
// ever letting that Timer actually fire fails not because anything is
// broken, but because the Timer is still legitimately ticking when the
// test function returns.
//
// The production duration (12s) exists for a real reason — see the
// screen's own comment on initTimeout — and pumping 12 fake seconds
// forward in every test would make this suite slow for no honest gain.
// initTimeout is `@visibleForTesting` specifically so a test can set it
// to something that actually finishes inside the test body instead of
// skipping the wait altogether, which is the difference between testing
// the timeout path and just working around it.
//
// WHAT THIS SUITE DOES NOT AND CANNOT COVER
// Real speech recognition, real TTS playback, and the full
// connect → speak → listen → end conversation loop all need a real
// microphone and speaker — an on-device call, the same status this
// screen's own file header already states for the voice loop. What IS
// covered here — the screen renders correctly, opens as a real route,
// and reliably recovers to a usable "failed" state (with a working End
// button) rather than hanging forever when the voice engine cannot be
// reached — is exactly the part most likely to strand a customer if it
// were wrong, so it earns its place even though the microphone itself
// does not.
import 'package:erode_superapp/screens/chitti_call_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final originalTimeout = ChittiCallScreen.initTimeout;

  tearDown(() {
    ChittiCallScreen.initTimeout = originalTimeout;
  });

  testWidgets('shows Chitti, a status line, and both call controls '
      'on first render', (tester) async {
    // Set BEFORE pumpWidget, same as the test below: initState reads
    // this once, synchronously, when the timer is created, so setting
    // it any later has no effect on an already-running Timer. Short
    // rather than the production 12s purely so this test can drain it
    // before returning — flutter_test enforces zero pending Timers at
    // the end of every test, unconditionally, regardless of whether
    // this test cares about the timeout firing at all.
    ChittiCallScreen.initTimeout = const Duration(milliseconds: 10);

    await tester.pumpWidget(const MaterialApp(home: ChittiCallScreen()));
    await tester.pump();

    expect(find.text('Chitti'), findsOneWidget);
    expect(find.text('Connecting...'), findsOneWidget);
    expect(find.byIcon(Icons.call_end_rounded), findsOneWidget);
    expect(find.byIcon(Icons.mic_rounded), findsOneWidget);
    expect(find.text('Mute'), findsOneWidget);
    expect(find.text('End'), findsOneWidget);

    // Drains the timer so it is not still pending when this test ends.
    await tester.pump(const Duration(milliseconds: 20));
  });

  testWidgets(
      'openChittiCallScreen pushes a real route, and a screen that '
      'cannot reach the voice engine still recovers to a usable state',
      (tester) async {
    // Set BEFORE pumpWidget: initState reads this once, synchronously,
    // when the timer is created.
    ChittiCallScreen.initTimeout = const Duration(milliseconds: 10);

    ChittiCallOutcome? outcome;
    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => ElevatedButton(
            onPressed: () async {
              outcome = await openChittiCallScreen(context);
            },
            child: const Text('open'),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    // A push's own transition keeps the outgoing page mounted for the
    // duration of the animation, so a bare pump() with no duration is
    // not enough — 2 fake seconds clears any standard transition with
    // margin to spare.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    expect(find.byType(ChittiCallScreen), findsOneWidget);

    // Long enough to clear the 10ms timeout above with room to spare.
    await tester.pump(const Duration(milliseconds: 100));

    expect(
      find.textContaining('Could not reach the mic or voice engine'),
      findsOneWidget,
    );

    // The one button that must never depend on the voice engine at all.
    await tester.tap(find.byIcon(Icons.call_end_rounded));
    // Same reasoning as the push above: the outgoing ChittiCallScreen
    // stays mounted, painting the exit transition, for a moment after
    // Navigator.pop() has already logically removed it from the route
    // stack — confirmed separately via NavigatorState.canPop() while
    // narrowing this down. The final bare pump() flushes the frame
    // where the widget is actually removed once that animation ends.
    await tester.pump();
    await tester.pump(const Duration(seconds: 2));
    await tester.pump();

    expect(find.byType(ChittiCallScreen), findsNothing);
    expect(outcome, ChittiCallOutcome.endedByUser);
  });
}
