// ================================================================
// chitti_screen_reader.dart — Chitti reads the screen it is standing
// on, without anybody teaching it that screen first.
// ================================================================
// NEW (Aug 28 2026 — Nizam's idea: "namma ovvoru screen um Chitti ku
// sollikudukurathu ... avan reading knowledge vachu avane
// therinjukuvan ... ipo app la irukura screen and new add pandra new
// updates, features and screens namma Chitti ku sollikuduthutte
// irukka thevayilla").
//
// The instinct behind that is right, and this codebase already agreed
// with it once: tools/gen_app_knowledge.dart opens with "a hand-written
// 'here is what the app does' prompt is correct for exactly one day".
// Hand-maintaining a description of every screen is the same treadmill.
//
// WHY NOT OCR, WHICH IS WHAT WAS ASKED FOR
// OCR is the right tool when all you have is pixels — a customer's
// DMart screenshot, a photographed bill. This app's own screens are
// not that. We own the widget tree, so the text is already sitting
// there as structured data with roles attached. Screenshotting it and
// guessing it back would mean:
//   • throwing away perfect data and re-deriving it with error, and
//     Tamil OCR is materially worse than English while half these
//     screens are Tamil;
//   • +5-15MB of ML Kit that does not run on web at all — and the
//     customer app ships primarily as a PWA, the same wall the
//     on-device LLM idea hit;
//   • a full-screen raster + encode (~100-300ms and a memory spike) on
//     the budget phones this app targets;
//   • screenshotting wallet balances, phone numbers, addresses and KYC
//     documents, which is a privacy problem the moment those bytes go
//     anywhere;
//   • and still only seeing what happens to be rendered — anything
//     scrolled off, collapsed, or behind a tab stays invisible.
//
// Flutter's SEMANTICS TREE gives the same answer for free. It is what
// a screen reader consumes: every label, value, button and field on
// screen, as text, with its role. Native and web, no package, no API
// call, no accuracy loss — it IS the original text.
//
// COST, HONESTLY
// Flutter only builds this tree when something is listening. Holding a
// handle open permanently makes every frame do extra work, so this
// enables semantics, waits for one frame, reads, and releases. A read
// costs about a frame; it is not something to poll.
import 'dart:async';

import 'package:flutter/semantics.dart';
import 'package:flutter/widgets.dart';

/// One thing Chitti can see on the current screen.
@immutable
class ChittiScreenElement {
  const ChittiScreenElement({
    required this.label,
    required this.kind,
    this.value = '',
  });

  final String label;
  final ChittiElementKind kind;

  /// A field's current contents, or a reading's value. Empty for a
  /// field the customer has not filled — which is the single most
  /// useful thing on this whole object, because an empty required
  /// field is exactly what Chitti should offer to fill.
  final String value;

  bool get isEmptyField => kind == ChittiElementKind.field && value.isEmpty;

  @override
  String toString() => '$kind:$label${value.isEmpty ? '' : '=$value'}';
}

enum ChittiElementKind { heading, button, field, text }

/// What Chitti can see right now.
@immutable
class ChittiScreenSnapshot {
  const ChittiScreenSnapshot({
    required this.headings,
    required this.buttons,
    required this.fields,
    required this.texts,
  });

  static const empty = ChittiScreenSnapshot(
    headings: <ChittiScreenElement>[],
    buttons: <ChittiScreenElement>[],
    fields: <ChittiScreenElement>[],
    texts: <ChittiScreenElement>[],
  );

  final List<ChittiScreenElement> headings;
  final List<ChittiScreenElement> buttons;
  final List<ChittiScreenElement> fields;
  final List<ChittiScreenElement> texts;

  bool get isEmpty =>
      headings.isEmpty && buttons.isEmpty && fields.isEmpty && texts.isEmpty;

  /// Fields the customer has not filled in yet.
  List<ChittiScreenElement> get blankFields =>
      fields.where((f) => f.value.isEmpty).toList(growable: false);

  /// The screen's own title, as the screen itself states it — better
  /// than any label we could guess from a route name.
  String? get title => headings.isNotEmpty ? headings.first.label : null;

  /// A compact line for a prompt. Deliberately short: this rides along
  /// with every request that carries screen context, so it is written
  /// to be informative per token, not exhaustive.
  String toPromptLine({int maxButtons = 6, int maxFields = 5}) {
    final parts = <String>[];
    if (title != null) parts.add('Screen: $title.');
    if (fields.isNotEmpty) {
      final f = fields.take(maxFields).map((e) {
        return e.value.isEmpty ? '${e.label} (empty)' : '${e.label} = ${e.value}';
      }).join(', ');
      parts.add('Fields: $f.');
    }
    if (buttons.isNotEmpty) {
      parts.add('Buttons: ${buttons.take(maxButtons).map((e) => e.label).join(', ')}.');
    }
    return parts.join(' ');
  }
}

class ChittiScreenReader {
  ChittiScreenReader._();

  /// Junk that ends up in the semantics tree but means nothing to a
  /// person — decorative icons, single characters, framework chrome.
  static bool _isNoise(String label) {
    final t = label.trim();
    if (t.length < 2) return true;
    if (t.length > 120) return true;
    return const {'back', 'menu', 'close', 'more options', 'drawer'}
        .contains(t.toLowerCase());
  }

  /// Reads the current screen.
  ///
  /// Returns [ChittiScreenSnapshot.empty] rather than throwing when
  /// semantics cannot be produced (very early boot, a headless test) —
  /// a screen Chitti cannot read is a reason to say less, never a
  /// reason to fail the message the customer just sent.
  static Future<ChittiScreenSnapshot> read() async {
    SemanticsHandle? handle;
    try {
      final binding = WidgetsBinding.instance;
      // Turning semantics on is what makes Flutter build the tree at
      // all. Released in the finally below — holding it open would tax
      // every frame for the rest of the session.
      handle = binding.ensureSemantics();

      // The tree is built during a frame, so one has to pass before
      // there is anything to read.
      await binding.endOfFrame;

      // The semantics owner hangs off a CHILD of the root pipeline
      // owner, not the root itself — reading `binding.pipelineOwner`
      // directly is deprecated, and in a multi-view app it would only
      // ever have found one view's tree anyway.
      SemanticsNode? root;
      binding.rootPipelineOwner.visitChildren((child) {
        root ??= child.semanticsOwner?.rootSemanticsNode;
      });
      final rootNode = root;
      if (rootNode == null) return ChittiScreenSnapshot.empty;

      final headings = <ChittiScreenElement>[];
      final buttons = <ChittiScreenElement>[];
      final fields = <ChittiScreenElement>[];
      final texts = <ChittiScreenElement>[];
      final seen = <String>{};

      void visit(SemanticsNode node) {
        final data = node.getSemanticsData();
        final label = data.label.trim();
        final value = data.value.trim();

        if (label.isNotEmpty && !_isNoise(label)) {
          final flags = data.flagsCollection;
          final isButton = flags.isButton || data.hasAction(SemanticsAction.tap);
          final isField = flags.isTextField;
          final isHeader = flags.isHeader;

          final kind = isField
              ? ChittiElementKind.field
              : isHeader
                  ? ChittiElementKind.heading
                  : isButton
                      ? ChittiElementKind.button
                      : ChittiElementKind.text;

          // Same label twice is almost always one visual element
          // reported at two levels of the tree, not two controls.
          final key = '$kind|$label';
          if (seen.add(key)) {
            final element = ChittiScreenElement(
              label: label,
              kind: kind,
              value: value,
            );
            switch (kind) {
              case ChittiElementKind.heading:
                headings.add(element);
              case ChittiElementKind.button:
                buttons.add(element);
              case ChittiElementKind.field:
                fields.add(element);
              case ChittiElementKind.text:
                texts.add(element);
            }
          }
        }

        node.visitChildren((child) {
          visit(child);
          return true;
        });
      }

      visit(rootNode);

      // No explicit header on most screens, so fall back to the first
      // substantial piece of text — in practice that is the app bar
      // title, which is exactly what we want.
      if (headings.isEmpty && texts.isNotEmpty) {
        headings.add(texts.first);
        texts.removeAt(0);
      }

      return ChittiScreenSnapshot(
        headings: headings,
        buttons: buttons,
        fields: fields,
        texts: texts,
      );
    } catch (e) {
      debugPrint('[ChittiScreenReader] read failed: $e');
      return ChittiScreenSnapshot.empty;
    } finally {
      handle?.dispose();
    }
  }
}
