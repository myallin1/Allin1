// ================================================================
// chitti_typewriter_text_test.dart
// ================================================================
// NEW (Aug 29 2026 -- Nizam: "ovvoru work ah type aguramari set
// pannuna customer ku oru nalla interest irukum"). Pure UI, but the
// two things worth pinning are the two ways this could silently
// break: showing nothing until the animation finishes (instead of a
// progressive reveal), and replaying the animation every time the
// surrounding list rebuilds instead of running once.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/widgets/chitti_typewriter_text.dart';

void main() {
  Widget host(Widget child) =>
      MaterialApp(home: Scaffold(body: child));

  testWidgets('animate: false shows the full text immediately',
      (tester) async {
    await tester.pumpWidget(host(
      const ChittiTypewriterText(
        'Your order is on the way.',
        style: TextStyle(),
        animate: false,
      ),
    ));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'Your order is on the way.');
  });

  testWidgets('animate: true starts empty and reveals over time',
      (tester) async {
    await tester.pumpWidget(host(
      const ChittiTypewriterText(
        'Hello boss!',
        style: TextStyle(),
      ),
    ));
    // First frame: nothing revealed yet.
    var text = tester.widget<Text>(find.byType(Text));
    expect(text.data!.length, lessThan('Hello boss!'.length));

    // Long enough for the capped animation to finish.
    await tester.pump(const Duration(milliseconds: 1200));
    text = tester.widget<Text>(find.byType(Text));
    expect(text.data, 'Hello boss!');
  });

  testWidgets('an empty string never throws', (tester) async {
    await tester.pumpWidget(host(
      const ChittiTypewriterText('', style: TextStyle()),
    ));
    await tester.pump(const Duration(milliseconds: 1200));
    final text = tester.widget<Text>(find.byType(Text));
    expect(text.data, '');
  });

  testWidgets(
      'a stable key inside a growing list keeps the animation from replaying',
      (tester) async {
    // Simulates the actual usage: a ListView.builder where each item
    // keeps a stable ValueKey(index) as new messages are appended.
    // That is what production code relies on -- see the "isLatest"
    // wiring in guru_chat_screen.dart and guru_overlay_service.dart.
    Widget list(int count) => host(
          ListView.builder(
            itemCount: count,
            itemBuilder: (context, i) => ChittiTypewriterText(
              key: ValueKey('msg_$i'),
              'message $i',
              style: const TextStyle(),
            ),
          ),
        );

    await tester.pumpWidget(list(1));
    await tester.pump(const Duration(milliseconds: 1200));
    expect(tester.widget<Text>(find.byType(Text)).data, 'message 0');

    // A second item is appended -- the SAME list, one more child. The
    // first item's key/position is unchanged, so its State (and the
    // fact that it already finished revealing) must survive.
    await tester.pumpWidget(list(2));
    await tester.pump();
    final texts = tester.widgetList<Text>(find.byType(Text)).toList();
    expect(texts.first.data, 'message 0');
  });

  group('pacing tracks length, for voice sync', () {
    // NEW (Aug 29 2026 -- Nizam: "voice soldrathum text generate
    // agurathum same sync la irukanum"). A length-INDEPENDENT cap was
    // the earlier design and is exactly what breaks this: it made a
    // long reply finish revealing on screen long before Chitti's own
    // TTS finished saying it. Pacing must scale with length instead.
    testWidgets('a longer reply is still mid-reveal when a shorter one has already finished',
        (tester) async {
      const short = 'OK boss.';
      final long = 'B' * 200;

      await tester.pumpWidget(host(Column(
        children: [
          ChittiTypewriterText(key: const ValueKey('s'), short, style: const TextStyle()),
          ChittiTypewriterText(key: const ValueKey('l'), long, style: const TextStyle()),
        ],
      )));

      // Long enough for the short reply to finish, nowhere near enough
      // for 200 characters at a natural pace.
      await tester.pump(const Duration(milliseconds: 700));

      final texts = tester.widgetList<Text>(find.byType(Text)).toList();
      expect(texts[0].data, short, reason: 'the short reply should be done');
      expect(
        texts[1].data!.length,
        lessThan(long.length),
        reason: 'the long reply should still be revealing',
      );
    });
  });
}