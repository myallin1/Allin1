// ================================================================
// stage_progress_tracker.dart — generic, reusable courier-tracking
// style stage progress widget.
//
// Generalizes two previously-duplicated, private, single-screen
// implementations found in this codebase:
//   - service_request_tracking_screen.dart's _StatusStepper/_StepCircle
//     (label-driven stage list, no glow animation)
//   - order_tracking_screen.dart's _buildTimeline (AnimatedContainer
//     glow/fill on the active node, but hardcoded to 4 delivery steps)
//
// This widget has NO Firestore/domain knowledge — it is purely a
// display widget driven by `stages` + `currentIndex`, so it can be
// reused by any future stage-based tracking UI in this app.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class StageProgressTracker extends StatelessWidget {
  const StageProgressTracker({
    super.key,
    required this.stages,
    required this.currentIndex,
    this.stageSubtitles,
    this.accentColor = const Color(0xFFFF4FA3),
    this.completedColor = const Color(0xFF00C853),
    this.mutedColor = const Color(0xFF9999BB),
    this.borderColor = const Color(0xFFEEEEF5),
    this.textColor = const Color(0xFF1A1A2E),
    this.compact = false,
  });

  /// Ordered list of stage labels, e.g. ['Waiting for hero
  /// confirmation', 'Your hero confirmed', ...].
  final List<String> stages;

  /// Index into [stages] of the currently-active stage. Stages before
  /// this index render as completed (filled + check); this stage
  /// renders as active (filled + glow); stages after render as
  /// pending (dim outline).
  final int currentIndex;

  /// Optional per-stage secondary text (e.g. an approximate-time
  /// hint), shown only under the currently-active stage. Index-aligned
  /// with [stages]; pass null, or a shorter list, to skip subtitles.
  final List<String?>? stageSubtitles;

  final Color accentColor;
  final Color completedColor;
  final Color mutedColor;
  final Color borderColor;
  final Color textColor;

  /// Compact mode: smaller node circles, tighter vertical spacing, and
  /// a smaller label font — for screens where the tracker needs to
  /// share vertical space with other content (e.g. task details above
  /// it) instead of being the sole focus of the screen. Visual
  /// metaphor (vertical timeline, glow on the active node) is
  /// unchanged; only sizing/spacing shrinks.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final double nodeSize = compact ? 20 : 28;
    final double iconSize = compact ? 12 : 16;
    final double currentIconSize = compact ? 10 : 14;
    final double horizontalGap = compact ? 10 : 14;
    final double bottomPadding = compact ? 10 : 24;
    final double labelFontSize = compact ? 12 : 14;
    final double subtitleFontSize = compact ? 10 : 11;

    return Column(
      children: List.generate(stages.length, (i) {
        final isCompleted = i < currentIndex;
        final isCurrent = i == currentIndex;
        final isLast = i == stages.length - 1;
        final subtitle =
            (stageSubtitles != null && i < stageSubtitles!.length)
                ? stageSubtitles![i]
                : null;

        return IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 400),
                    width: nodeSize,
                    height: nodeSize,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: isCompleted
                          ? completedColor
                          : (isCurrent ? accentColor : Colors.transparent),
                      border: (!isCompleted && !isCurrent)
                          ? Border.all(color: borderColor, width: compact ? 1.5 : 2)
                          : null,
                      boxShadow: isCurrent
                          ? [
                              BoxShadow(
                                color: accentColor.withValues(alpha: 0.45),
                                blurRadius: compact ? 8 : 12,
                                spreadRadius: 1,
                              ),
                            ]
                          : const [],
                    ),
                    child: isCompleted
                        ? Icon(Icons.check_rounded,
                            color: Colors.white, size: iconSize,)
                        : (isCurrent
                            ? Icon(Icons.radio_button_checked_rounded,
                                color: Colors.white, size: currentIconSize,)
                            : null),
                  ),
                  if (!isLast)
                    Expanded(
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 400),
                        width: 2,
                        color: isCompleted ? completedColor : borderColor,
                      ),
                    ),
                ],
              ),
              SizedBox(width: horizontalGap),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomPadding, top: 2),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        stages[i],
                        style: GoogleFonts.outfit(
                          color: (isCurrent || isCompleted)
                              ? textColor
                              : mutedColor,
                          fontSize: labelFontSize,
                          fontWeight:
                              isCurrent ? FontWeight.w800 : FontWeight.w600,
                        ),
                      ),
                      if (isCurrent &&
                          subtitle != null &&
                          subtitle.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(
                          subtitle,
                          style: TextStyle(color: mutedColor, fontSize: subtitleFontSize),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
        );
      }),
    );
  }
}
