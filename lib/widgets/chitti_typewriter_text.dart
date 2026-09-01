// ================================================================
// chitti_typewriter_text.dart — a reply that reveals as it "types".
// ================================================================
// NEW (Aug 29 2026 — Nizam: "ovvoru work ah type aguramari set
// pannuna customer ku oru nalla interest irukum").
//
// UI ONLY. The full reply is already in hand by the time this widget
// mounts — nothing here changes what Chitti says, when a message is
// saved to history, or when TTS speaks it. This only changes what the
// EYE sees: the text reveals character by character instead of
// appearing all at once, which is the one thing the request actually
// asked for.
//
// WHY A STABLE KEY IS THE WHOLE MECHANISM
// A chat list rebuilds constantly — a new message arrives, the typing
// indicator toggles, the keyboard opens. Every rebuild recreates this
// widget from the caller's point of view, but Flutter keeps the same
// State object alive as long as the widget's KEY does not change (see
// how this is used in guru_chat_screen.dart / guru_overlay_service.dart
// — each bubble gets `key: ValueKey(<stable message index>)`). That is
// what makes "animate once, then stay finished" work with no explicit
// bookkeeping in the caller: the animation runs in initState, which
// only fires once per key.
import 'dart:async';

import 'package:flutter/material.dart';

class ChittiTypewriterText extends StatefulWidget {
  const ChittiTypewriterText(
    this.text, {
    super.key,
    required this.style,
    this.animate = true,
  });

  final String text;
  final TextStyle style;

  /// Set false to skip the animation entirely (e.g. a message loaded
  /// from history — nobody needs to watch yesterday's reply "type"
  /// itself out again).
  final bool animate;

  @override
  State<ChittiTypewriterText> createState() => _ChittiTypewriterTextState();
}

class _ChittiTypewriterTextState extends State<ChittiTypewriterText> {
  Timer? _timer;
  int _shown = 0;

  // CHANGED AGAIN (Aug 29 2026 — Nizam: "voice soldrathum text
  // generate agurathum same sync la irukanum").
  //
  // The previous version capped the WHOLE reveal at a short fixed
  // duration regardless of length — tuned purely for "feels snappy".
  // That is the wrong shape for this ask: Chitti's TTS takes roughly
  // proportional-to-length time to SAY a reply, so a length-independent
  // cap meant a two-sentence reply finished revealing on screen while
  // the voice was still only a few words in. A flat per-character rate
  // is what actually tracks speech: a longer reply both takes longer
  // to say AND longer to reveal, in the same proportion, so the two
  // stay roughly together without this widget needing to listen to the
  // TTS engine at all (which would need a dependency this file
  // deliberately does not have — see the class doc).
  //
  // ~65ms/char approximates a normal spoken pace (~150-180 words/min
  // at ~5 characters/word) — close enough for the two to read as
  // "together" without wiring an exact callback per platform. A floor
  // and a ceiling protect the extremes: a one-word reply still gets a
  // beat of motion, and a very long reply does not make someone wait
  // several real seconds staring at a half-revealed paragraph.
  static const int _msPerChar = 65;
  static const int _minTotalMs = 120;
  static const int _maxTotalMs = 4500;

  @override
  void initState() {
    super.initState();
    if (!widget.animate || widget.text.isEmpty) {
      _shown = widget.text.length;
      return;
    }
    final rawTotal = widget.text.length * _msPerChar;
    final totalMs = rawTotal.clamp(_minTotalMs, _maxTotalMs);
    final perCharMs = (totalMs / widget.text.length).round().clamp(1, 999);
    _timer = Timer.periodic(Duration(milliseconds: perCharMs), (t) {
      if (!mounted) {
        t.cancel();
        return;
      }
      setState(() => _shown++);
      if (_shown >= widget.text.length) t.cancel();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final visible = _shown >= widget.text.length
        ? widget.text
        : widget.text.substring(0, _shown);
    return Text(visible, style: widget.style);
  }
}
