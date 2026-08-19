// ================================================================
// ChittiProcessingSteps — "Chitti is working on it" sequence UI
// Allin1 (Aug 19 2026)
// ================================================================
// Shown while Chitti executes a task the customer asked for:
// "Analyzing request…" → "Finding heroes nearby…" → "Confirming…".
//
// ── THE ONE RULE THIS WIDGET ENFORCES ──────────────────────────
// The steps are DRIVEN BY REAL WORK, not by a timer.
//
// The tempting version is a list of labels on a 900ms Timer that looks
// busy regardless of what the backend is doing. It is also a lie, and
// it breaks in the two cases that matter most:
//   - work finishes in 200ms → the customer watches a fake progress
//     bar for 3 seconds for no reason;
//   - work takes 12 seconds or fails → the animation has long since
//     shown "Done" while nothing is done.
// Both destroy trust in exactly the moment the app is asking for it.
//
// So the caller advances the steps as each real stage completes (see
// ChittiTaskRunner below). The only thing on a clock here is the
// shimmer, which is decoration.
//
// ── ZERO-JANK CONTRACT ─────────────────────────────────────────
// One AnimationController for the whole list, driving a shimmer that
// is a pure function of (controller value, row index). Rows are const
// where possible and rebuild only when their own status changes.
//
// Nothing here awaits anything. The async work belongs to the caller;
// this widget only renders state it is handed. That separation is what
// keeps the animation smooth while real work runs — not the storage
// engine underneath it (see the note in ChittiTaskRunner).
// ================================================================

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum ChittiStepStatus { pending, running, done, failed }

@immutable
class ChittiStep {
  final String label;
  final ChittiStepStatus status;

  const ChittiStep(this.label, {this.status = ChittiStepStatus.pending});

  ChittiStep copyWith({ChittiStepStatus? status}) =>
      ChittiStep(label, status: status ?? this.status);
}

/// Renders a step list. Purely presentational — hand it steps, it draws
/// them. Drive it with [ChittiTaskRunner].
class ChittiProcessingSteps extends StatefulWidget {
  final List<ChittiStep> steps;

  /// Shown under the list, e.g. "Chitti is on it". Null hides it.
  final String? footnote;

  const ChittiProcessingSteps({
    super.key,
    required this.steps,
    this.footnote,
  });

  @override
  State<ChittiProcessingSteps> createState() => _ChittiProcessingStepsState();
}

class _ChittiProcessingStepsState extends State<ChittiProcessingSteps>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c;

  static const Color _ink = Color(0xFFEEEEF5);
  static const Color _muted = Color(0xFF7777A0);
  static const Color _accent = Color(0xFF6C63FF);
  static const Color _ok = Color(0xFF00C853);
  static const Color _bad = Color(0xFFFF5252);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Color _colorFor(ChittiStepStatus s) {
    switch (s) {
      case ChittiStepStatus.pending:
        return _muted;
      case ChittiStepStatus.running:
        return _accent;
      case ChittiStepStatus.done:
        return _ok;
      case ChittiStepStatus.failed:
        return _bad;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 16),
      decoration: BoxDecoration(
        // Same Apple/CRED gradient language as the rest of the app:
        // a barely-there tint over near-black, never a flat panel.
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF161622), Color(0xFF0E0E16)],
        ),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0x1AFFFFFF)),
        boxShadow: [
          BoxShadow(
            color: _accent.withValues(alpha: 0.12),
            blurRadius: 28,
            spreadRadius: -6,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < widget.steps.length; i++)
            _StepRow(
              step: widget.steps[i],
              isLast: i == widget.steps.length - 1,
              color: _colorFor(widget.steps[i].status),
              shimmer: _c,
              index: i,
            ),
          if (widget.footnote != null) ...[
            const SizedBox(height: 6),
            Text(
              widget.footnote!,
              style: GoogleFonts.outfit(
                color: _muted,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _StepRow extends StatelessWidget {
  final ChittiStep step;
  final bool isLast;
  final Color color;
  final Animation<double> shimmer;
  final int index;

  const _StepRow({
    required this.step,
    required this.isLast,
    required this.color,
    required this.shimmer,
    required this.index,
  });

  @override
  Widget build(BuildContext context) {
    final running = step.status == ChittiStepStatus.running;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Column(
            children: [
              // The bullet: a ring while pending, a filled tick when
              // done, a pulsing dot while running. AnimatedBuilder is
              // scoped to JUST this 18px box, so a running step never
              // rebuilds the label or the connector beside it.
              SizedBox(
                width: 18,
                height: 18,
                child: running
                    ? AnimatedBuilder(
                        animation: shimmer,
                        builder: (_, __) {
                          // Offset by index so multiple running steps
                          // (rare, but possible) don't pulse in lockstep.
                          final t = (shimmer.value + index * 0.15) % 1.0;
                          final p = (math.sin(t * 2 * math.pi) + 1) / 2;
                          return Center(
                            child: Container(
                              width: 8 + p * 4,
                              height: 8 + p * 4,
                              decoration: BoxDecoration(
                                color: color.withValues(alpha: 0.35 + p * 0.5),
                                shape: BoxShape.circle,
                              ),
                            ),
                          );
                        },
                      )
                    : Center(
                        child: step.status == ChittiStepStatus.done
                            ? Icon(Icons.check_circle_rounded,
                                size: 16, color: color)
                            : step.status == ChittiStepStatus.failed
                                ? Icon(Icons.error_rounded,
                                    size: 16, color: color)
                                : Container(
                                    width: 8,
                                    height: 8,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                          color: color.withValues(alpha: 0.5)),
                                    ),
                                  ),
                      ),
              ),
              // Connector to the next step. Drawn only between rows so
              // the list doesn't end in a dangling tail.
              if (!isLast)
                Expanded(
                  child: Container(
                    width: 1.5,
                    margin: const EdgeInsets.symmetric(vertical: 3),
                    color: color.withValues(alpha: 0.22),
                  ),
                ),
            ],
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Padding(
              padding: EdgeInsets.only(bottom: isLast ? 0 : 14),
              child: Text(
                step.label,
                style: GoogleFonts.outfit(
                  // Done steps recede; the running one is the only thing
                  // at full weight, so the eye lands on it without any
                  // extra highlight box.
                  color: step.status == ChittiStepStatus.pending
                      ? const Color(0xFF7777A0)
                      : const Color(0xFFEEEEF5),
                  fontSize: 12.5,
                  height: 1.25,
                  fontWeight: running ? FontWeight.w700 : FontWeight.w500,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ================================================================
// ChittiTaskRunner — binds real async work to the step UI
// ================================================================
// Usage:
//
//   final runner = ChittiTaskRunner(['Analyzing request', 'Finding
//       heroes nearby', 'Confirming your booking']);
//   // ... render ValueListenableBuilder on runner.steps ...
//   await runner.run(0, () => ai.parseIntent(text));
//   await runner.run(1, () => heroes.findNearby(pickup));
//   await runner.run(2, () => rides.create(...));
//
// Each `run` marks its step running, awaits the REAL future, then marks
// it done or failed. The UI therefore always reflects what is actually
// happening — which is the whole point of this class existing rather
// than the screen flipping statuses by hand and eventually getting it
// out of step with the work.
class ChittiTaskRunner {
  final ValueNotifier<List<ChittiStep>> steps;

  ChittiTaskRunner(List<String> labels)
      : steps = ValueNotifier<List<ChittiStep>>(
          labels.map(ChittiStep.new).toList(growable: false),
        );

  void _set(int i, ChittiStepStatus s) {
    final next = [...steps.value];
    if (i < 0 || i >= next.length) return;
    next[i] = next[i].copyWith(status: s);
    // A NEW list instance is assigned, not the existing one mutated —
    // ValueNotifier compares by identity, so mutating in place would
    // notify nothing and the UI would silently freeze on step one.
    steps.value = next;
  }

  // ── MANUAL CONTROL ─────────────────────────────────────────────
  // For stages that are NOT a Future — the common real-world case
  // being "we've started something and a stream/listener will tell us
  // when it finishes" (a hero accepting a ride, a payment webhook).
  //
  // run() cannot express those: there is no future to await, and
  // wrapping the listener in a Completer just to satisfy run() would
  // add a second place the completion can be missed or double-fired.
  // So the caller marks these directly, at the same points it already
  // handles the outcome.
  void markRunning(int i) => _set(i, ChittiStepStatus.running);
  void markDone(int i) => _set(i, ChittiStepStatus.done);
  void markFailed(int i) => _set(i, ChittiStepStatus.failed);

  /// Marks every still-unfinished step as failed. For an overall
  /// timeout or cancel, where leaving a step spinning forever would be
  /// the one thing worse than saying it failed.
  void failRemaining() {
    steps.value = [
      for (final s in steps.value)
        s.status == ChittiStepStatus.done
            ? s
            : s.copyWith(status: ChittiStepStatus.failed),
    ];
  }

  /// Runs [work] while showing step [i] as active. Rethrows after
  /// marking the step failed, so the caller still controls error
  /// handling — this class narrates, it does not swallow.
  Future<T> run<T>(int i, Future<T> Function() work) async {
    _set(i, ChittiStepStatus.running);
    try {
      final result = await work();
      _set(i, ChittiStepStatus.done);
      return result;
    } catch (_) {
      _set(i, ChittiStepStatus.failed);
      rethrow;
    }
  }

  void dispose() => steps.dispose();
}
