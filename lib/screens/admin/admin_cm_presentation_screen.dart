// ================================================================
// admin_cm_presentation_screen.dart — Nizam's remote control for what
// Chitti says while standing in front of the Chief Minister.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "1st chitti intro kudukanum app pathi apram
// cm kitta permission kekkanum, brief ah sollatuma boss nu solli then
// avar ok nu reply pannuna fulla sollanum").
//
// The whole screen is one idea: NIZAM controls the pace, Chitti does
// the talking, and nothing is said that wasn't written down in
// advance (see chitti_cm_pitch.dart for why fixed text and not a live
// model call).
//
// Flow on screen:
//   [Start] -> Chitti introduces itself and ASKS permission, then stops
//   CM says yes -> [Continue] walks the brief one section at a time
//   CM says not now -> [Not now] closes politely and stops
//
// One section per tap, on purpose. It lets Nizam read the room — if
// the CM interrupts with a question, he just stops tapping. A single
// "play the whole speech" button would talk over a Chief Minister,
// which is the one thing this must never do.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/chitti_cm_pitch.dart';
import '../../services/chitti/chitti_accessibility_bridge.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF16162A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);

class AdminCmPresentationScreen extends StatefulWidget {
  const AdminCmPresentationScreen({super.key, this.languageCode = 'ta'});

  final String languageCode;

  @override
  State<AdminCmPresentationScreen> createState() =>
      _AdminCmPresentationScreenState();
}

/// One thing the CM asked while Chitti was mid-sentence.
///
/// NEW (Sep 4 2026 — Nizam: "cm pesapesa vera question kettalum athayum
/// note panni vachutu queue pottu vachukkanum, current responsd solli
/// mudichathum que la irukura topic solli ithu paththi ketrukinga so
/// melaum ithai patri theriyanumanu question kekanum").
///
/// The behaviour this buys is the point: most assistants either talk
/// over an interruption or lose it. Holding the question, finishing the
/// current thought, and THEN coming back with "you also asked about X —
/// shall I go into that, sir?" is what a good chief-of-staff does.
class _QueuedQuestion {
  _QueuedQuestion(this.text) : askedAt = DateTime.now();
  final String text;
  final DateTime askedAt;
  bool answered = false;
}

class _AdminCmPresentationScreenState extends State<AdminCmPresentationScreen> {
  /// -1 = nothing said yet. 0 = intro done, waiting on the CM's answer.
  /// 1..n = that many brief sections delivered.
  int _stage = -1;
  bool _speaking = false;
  bool _declined = false;

  /// Captured mid-flow, oldest first. Never answered automatically —
  /// Chitti OFFERS, the CM decides, Nizam taps.
  final List<_QueuedQuestion> _queue = [];

  List<_QueuedQuestion> get _pending =>
      _queue.where((q) => !q.answered).toList();

  @override
  void dispose() {
    ChittiAccessibilityBridge.instance.stopCallVoice();
    super.dispose();
  }

  Future<void> _speak(String text) async {
    if (_speaking) return;
    setState(() => _speaking = true);
    try {
      await ChittiAccessibilityBridge.instance.speakOnCallStream(
        text,
        widget.languageCode == 'ta' ? 'ta-IN' : 'en-US',
      );
    } finally {
      if (mounted) setState(() => _speaking = false);
    }
  }

  Future<void> _start() async {
    await _speak(ChittiCmPitch.intro.text(widget.languageCode));
    if (mounted) setState(() => _stage = 0);
  }

  Future<void> _next() async {
    final idx = _stage; // 0 -> first brief section
    if (idx < 0 || idx >= ChittiCmPitch.brief.length) return;
    await _speak(ChittiCmPitch.brief[idx].text(widget.languageCode));
    if (mounted) setState(() => _stage = idx + 1);
  }

  Future<void> _declineGracefully() async {
    await _speak(ChittiCmPitch.politeClose.text(widget.languageCode));
    if (mounted) setState(() => _declined = true);
  }

  void _reset() => setState(() {
        _stage = -1;
        _declined = false;
        _queue.clear();
      });

  /// Capture an interruption. One text field, no categories, no
  /// tagging — this is typed one-handed while a Chief Minister is
  /// mid-sentence, so anything beyond "type it and go" would simply
  /// not get used.
  Future<void> _captureQuestion() async {
    final controller = TextEditingController();
    final text = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => Padding(
        padding: EdgeInsets.fromLTRB(
            18, 18, 18, MediaQuery.of(sheetContext).viewInsets.bottom + 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('What did he ask?',
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('A few words is enough — Chitti will bring it back up.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11.5)),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              style: GoogleFonts.outfit(color: _text, fontSize: 14),
              decoration: InputDecoration(
                hintText: 'e.g. how is data kept safe',
                hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
                filled: true,
                fillColor: _bg,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none),
              ),
              onSubmitted: (v) => Navigator.of(sheetContext).pop(v),
            ),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () =>
                    Navigator.of(sheetContext).pop(controller.text),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _purple,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
                child: const Text('Add to queue'),
              ),
            ),
          ],
        ),
      ),
    );
    if (text != null && text.trim().isNotEmpty && mounted) {
      setState(() => _queue.add(_QueuedQuestion(text.trim())));
    }
  }

  /// Chitti acknowledges the held question and asks whether to go into
  /// it. It does NOT answer here — the CM might say no, or might have
  /// moved on, and answering something nobody wants any more is worse
  /// than not remembering it at all.
  Future<void> _offerQueued(_QueuedQuestion q) async {
    final line = widget.languageCode == 'ta'
        ? 'சார், நீங்க "${q.text}" பத்தி கேட்டீங்க. அதைப் பத்தி இன்னும் '
            'விவரமா சொல்லட்டுமா சார்?'
        : 'Sir, you asked about "${q.text}". Would you like me to go into '
            'that, sir?';
    await _speak(line);
  }

  void _markAnswered(_QueuedQuestion q) => setState(() => q.answered = true);

  @override
  Widget build(BuildContext context) {
    final done = _stage >= ChittiCmPitch.brief.length;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('CM Presentation',
            style: GoogleFonts.outfit(
                color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          if (_stage >= 0)
            IconButton(
              tooltip: 'Start over',
              icon: const Icon(Icons.restart_alt_rounded, color: _muted),
              onPressed: _speaking ? null : _reset,
            ),
        ],
      ),
      // Always reachable, at every stage — an interruption doesn't wait
      // for a convenient moment, so neither can the button that catches
      // it.
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _captureQuestion,
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_comment_rounded, size: 19),
        label: Text('He asked something',
            style: GoogleFonts.outfit(
                fontSize: 12.5, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          _hint(),
          const SizedBox(height: 14),
          if (_pending.isNotEmpty) ...[
            _queueCard(),
            const SizedBox(height: 14),
          ],
          if (_stage < 0) _startCard() else if (_declined) _closedCard(),
          if (_stage == 0 && !_declined) _permissionCard(),
          if (_stage > 0 && !_declined && !done) _continueCard(),
          if (done && !_declined) _doneCard(),
          const SizedBox(height: 16),
          _script(),
        ],
      ),
    );
  }

  /// Sits ABOVE the presentation controls once anything is queued —
  /// the held question is now the most important thing on the screen,
  /// because forgetting it in front of the CM is the failure this
  /// whole feature exists to prevent.
  Widget _queueCard() => Container(
        width: double.infinity,
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _purple.withValues(alpha: 0.5)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('He asked — waiting (${_pending.length})',
                style: GoogleFonts.outfit(
                    color: _purple, fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 3),
            Text('Finish the section you are on, then tap Ask.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11.5)),
            const SizedBox(height: 10),
            for (final q in _pending) ...[
              Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(q.text,
                        style: GoogleFonts.outfit(
                            color: _text,
                            fontSize: 13.5,
                            fontWeight: FontWeight.w600)),
                    const SizedBox(height: 9),
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed:
                                _speaking ? null : () => _offerQueued(q),
                            icon: const Icon(Icons.volume_up_rounded, size: 15),
                            label: const Text('Ask about it'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _green,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 9),
                              textStyle: GoogleFonts.outfit(
                                  fontSize: 12, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(width: 7),
                        TextButton(
                          onPressed: () => _markAnswered(q),
                          style: TextButton.styleFrom(foregroundColor: _muted),
                          child: Text('Done',
                              style: GoogleFonts.outfit(fontSize: 12)),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      );

  Widget _hint() => Container(
        padding: const EdgeInsets.all(13),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(13),
        ),
        child: Text(
          'Chitti speaks only when you tap. Nothing here needs internet or '
          'the AI — every line is fixed, so it cannot fail in the room.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 12),
        ),
      );

  Widget _startCard() => _action(
        title: 'Ready',
        body:
            'Chitti will introduce itself and the app in a few seconds, then '
            'ask the CM for permission to continue. It will stop there.',
        buttonLabel: 'Start — Chitti introduces',
        color: _purple,
        onTap: _start,
      );

  Widget _permissionCard() => Column(
        children: [
          _action(
            title: 'Waiting on the CM',
            body:
                'Chitti has asked "may I explain briefly, sir?". Tap below '
                'once he answers.',
            buttonLabel: 'He said yes — continue',
            color: _green,
            onTap: _next,
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _speaking ? null : _declineGracefully,
              style: OutlinedButton.styleFrom(
                foregroundColor: _muted,
                side: const BorderSide(color: _muted),
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
              child: const Text('Not now — close politely'),
            ),
          ),
        ],
      );

  Widget _continueCard() {
    final next = ChittiCmPitch.brief[_stage];
    return _action(
      title: 'Next: ${next.label}',
      body: next.text(widget.languageCode),
      buttonLabel: 'Say this (${_stage + 1} of ${ChittiCmPitch.brief.length})',
      color: _green,
      onTap: _next,
    );
  }

  Widget _doneCard() => _action(
        title: 'Brief complete',
        body:
            'Chitti has finished. Anything the CM asks now goes to normal '
            'Chitti — open the assistant and let him ask.',
        buttonLabel: 'Start over',
        color: _purple,
        onTap: () async => _reset(),
      );

  Widget _closedCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
            color: _card, borderRadius: BorderRadius.circular(13)),
        child: Text(
          'Closed politely. Tap the restart icon above to begin again.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
        ),
      );

  Widget _action({
    required String title,
    required String body,
    required String buttonLabel,
    required Color color,
    required Future<void> Function() onTap,
  }) =>
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(15),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: color.withValues(alpha: 0.35)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: GoogleFonts.outfit(
                    color: _text, fontSize: 15, fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Text(body,
                style: GoogleFonts.outfit(
                    color: _muted, fontSize: 12.5, height: 1.45)),
            const SizedBox(height: 13),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _speaking ? null : () => onTap(),
                icon: Icon(
                    _speaking
                        ? Icons.graphic_eq_rounded
                        : Icons.volume_up_rounded,
                    size: 18),
                label: Text(_speaking ? 'Chitti is speaking…' : buttonLabel),
                style: ElevatedButton.styleFrom(
                  backgroundColor: color,
                  foregroundColor: Colors.black,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ],
        ),
      );

  /// The full script, so Nizam can read ahead and know exactly what is
  /// coming before he taps.
  Widget _script() => Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Full script',
              style: GoogleFonts.outfit(
                  color: _muted, fontSize: 12, fontWeight: FontWeight.w600)),
          const SizedBox(height: 8),
          _scriptLine(ChittiCmPitch.intro, spoken: _stage >= 0),
          for (var i = 0; i < ChittiCmPitch.brief.length; i++)
            _scriptLine(ChittiCmPitch.brief[i], spoken: _stage > i),
        ],
      );

  Widget _scriptLine(PitchStage s, {required bool spoken}) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: _card.withValues(alpha: spoken ? 0.5 : 1),
          borderRadius: BorderRadius.circular(11),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                if (spoken)
                  const Padding(
                    padding: EdgeInsets.only(right: 6),
                    child: Icon(Icons.check_circle_rounded,
                        color: _green, size: 14),
                  ),
                Expanded(
                  child: Text(s.label,
                      style: GoogleFonts.outfit(
                          color: spoken ? _green : _text,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w600)),
                ),
              ],
            ),
            const SizedBox(height: 5),
            Text(s.text(widget.languageCode),
                style: GoogleFonts.outfit(
                    color: _muted, fontSize: 11.5, height: 1.5)),
          ],
        ),
      );
}
