// ================================================================
// CoachMarkOverlay — reusable first-open "how to use this app" tour
// ================================================================
// Per Nizam's request: when a customer opens the app for the very
// first time, show a brief step-by-step walkthrough that spotlights
// real buttons on the real home screen (not a separate slideshow) and
// explains what each one does. Shown once ever per install (tracked
// via SharedPreferences) — see CoachMarkPrefs.hasSeenTour /
// markTourSeen below.
//
// Usage: build a List<CoachMarkStep> (each optionally anchored to a
// GlobalKey on a real widget), then call:
//   showCoachMarkTour(context, steps: [...], onFinish: () {...});
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

class CoachMarkStep {
  final String title;
  final String description;
  // Null = a centered "welcome" card with no spotlight (e.g. the
  // intro step before pointing at real buttons).
  final GlobalKey? targetKey;

  const CoachMarkStep({
    required this.title,
    required this.description,
    this.targetKey,
  });
}

class CoachMarkPrefs {
  static const String _keyPrefix = 'coach_mark_seen_';

  static Future<bool> hasSeenTour(String tourId) async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('$_keyPrefix$tourId') ?? false;
  }

  static Future<void> markTourSeen(String tourId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('$_keyPrefix$tourId', true);
  }
}

/// Inserts a full-screen OverlayEntry that walks through [steps] one at
/// a time, spotlighting each step's targetKey (if any). Call this after
/// the first frame has rendered (e.g. from a post-frame callback) so
/// target widgets have real, measurable positions.
void showCoachMarkTour(
  BuildContext context, {
  required List<CoachMarkStep> steps,
  VoidCallback? onFinish,
}) {
  if (steps.isEmpty) return;
  late OverlayEntry entry;
  int index = 0;

  void close() {
    entry.remove();
    onFinish?.call();
  }

  void rebuild() {
    entry.markNeedsBuild();
  }

  entry = OverlayEntry(
    builder: (ctx) => _CoachMarkFrame(
      step: steps[index],
      stepNumber: index + 1,
      totalSteps: steps.length,
      onNext: () {
        if (index >= steps.length - 1) {
          close();
        } else {
          index++;
          rebuild();
        }
      },
      onSkip: close,
    ),
  );

  Overlay.of(context, rootOverlay: true).insert(entry);
}

class _CoachMarkFrame extends StatelessWidget {
  final CoachMarkStep step;
  final int stepNumber;
  final int totalSteps;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _CoachMarkFrame({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.onNext,
    required this.onSkip,
  });

  Rect? _targetRect() {
    final key = step.targetKey;
    if (key == null) return null;
    final ctx = key.currentContext;
    if (ctx == null) return null;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null || !box.attached) return null;
    final topLeft = box.localToGlobal(Offset.zero);
    return topLeft & box.size;
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final rect = _targetRect();
    final isLast = stepNumber >= totalSteps;

    // Position the tooltip card below the spotlight if there's room,
    // otherwise above it; vertically centered if there's no target.
    final card = _CoachMarkCard(
      step: step,
      stepNumber: stepNumber,
      totalSteps: totalSteps,
      isLast: isLast,
      onNext: onNext,
      onSkip: onSkip,
    );

    Widget cardPositioned;
    if (rect == null) {
      cardPositioned = Center(
        child: Padding(padding: const EdgeInsets.symmetric(horizontal: 20), child: card),
      );
    } else {
      final spaceBelow = screenSize.height - rect.bottom;
      final useBelow = spaceBelow > 220;
      cardPositioned = Positioned(
        left: 20,
        right: 20,
        top: useBelow ? rect.bottom + 16 : null,
        bottom: useBelow ? null : (screenSize.height - rect.top + 16),
        child: card,
      );
    }

    return Stack(
      children: [
        // Dimmed barrier with a spotlight cutout around the target.
        Positioned.fill(
          child: IgnorePointer(
            child: CustomPaint(
              painter: _SpotlightPainter(rect: rect),
            ),
          ),
        ),
        // Tap-anywhere-to-advance barrier (behind the card).
        Positioned.fill(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onTap: onNext,
          ),
        ),
        cardPositioned,
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CoachMarkStep>('step', step));
    properties.add(IntProperty('stepNumber', stepNumber));
    properties.add(IntProperty('totalSteps', totalSteps));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onNext', onNext));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onSkip', onSkip));
  }
}

class _CoachMarkCard extends StatelessWidget {
  final CoachMarkStep step;
  final int stepNumber;
  final int totalSteps;
  final bool isLast;
  final VoidCallback onNext;
  final VoidCallback onSkip;

  const _CoachMarkCard({
    required this.step,
    required this.stepNumber,
    required this.totalSteps,
    required this.isLast,
    required this.onNext,
    required this.onSkip,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(color: Colors.black.withValues(alpha: 0.25), blurRadius: 24, offset: const Offset(0, 10)),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF4FA3).withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$stepNumber / $totalSteps',
                    style: const TextStyle(color: Color(0xFFFF4FA3), fontSize: 11, fontWeight: FontWeight.w800),
                  ),
                ),
                const Spacer(),
                TextButton(
                  onPressed: onSkip,
                  child: const Text('Skip', style: TextStyle(color: Color(0xFF9999BB), fontWeight: FontWeight.w700)),
                ),
              ],
            ),
            const SizedBox(height: 10),
            Text(
              step.title,
              style: const TextStyle(color: Color(0xFF1A1A2E), fontSize: 17, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 6),
            Text(
              step.description,
              style: const TextStyle(color: Color(0xFF6E6E78), fontSize: 13.5, height: 1.4),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: onNext,
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF4FA3),
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 13),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(isLast ? 'Got it!' : 'Next', style: const TextStyle(fontWeight: FontWeight.w800)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<CoachMarkStep>('step', step));
    properties.add(IntProperty('stepNumber', stepNumber));
    properties.add(IntProperty('totalSteps', totalSteps));
    properties.add(DiagnosticsProperty<bool>('isLast', isLast));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onNext', onNext));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onSkip', onSkip));
  }
}

class _SpotlightPainter extends CustomPainter {
  final Rect? rect;
  _SpotlightPainter({required this.rect});

  @override
  void paint(Canvas canvas, Size size) {
    final barrier = Paint()..color = Colors.black.withValues(alpha: 0.65);

    if (rect == null) {
      canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), barrier);
      return;
    }

    final padded = rect!.inflate(8);
    // FIX (Nizam's report — PWA/web coach-mark tour showed a plain flat
    // dark overlay with no spotlight cutout, while native looked
    // correct): the old approach used Path.combine(PathOperation.
    // difference, ...) to punch a rounded-rect "hole" through the
    // barrier — a Skia path-boolean operation. Flutter's web renderers
    // (both the HTML renderer's SVG/CSS canvas translation and, in
    // some SDK/CanvasKit version combinations, CanvasKit itself) have
    // documented inconsistent support for Path.combine, so the "hole"
    // silently rendered as a solid fill on web instead of a cutout —
    // matching exactly what was reported. Replaced with four plain
    // rectangles (top/bottom/left/right bands around the target) —
    // zero path-boolean ops, zero blend modes, so there's no
    // renderer-specific behavior left to differ between native and web.
    canvas.drawRect(Rect.fromLTRB(0, 0, size.width, padded.top), barrier);
    canvas.drawRect(Rect.fromLTRB(0, padded.bottom, size.width, size.height), barrier);
    canvas.drawRect(Rect.fromLTRB(0, padded.top, padded.left, padded.bottom), barrier);
    canvas.drawRect(Rect.fromLTRB(padded.right, padded.top, size.width, padded.bottom), barrier);
    // The band approach leaves the padded rect's corners square; draw
    // the rounded highlight ring over them so the visible edge still
    // reads as a soft rounded spotlight even though the barrier itself
    // is now rectangular underneath.
    final cornerPaint = Paint()..color = Colors.black.withValues(alpha: 0.65);
    final roundedHole = RRect.fromRectAndRadius(padded, const Radius.circular(16));
    final cornerCover = Path()
      ..addRect(padded)
      ..addRRect(roundedHole)
      ..fillType = PathFillType.evenOdd;
    canvas.drawPath(cornerCover, cornerPaint);

    // Highlight ring around the spotlight.
    final ringPaint = Paint()
      ..color = const Color(0xFFFF4FA3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5;
    canvas.drawRRect(roundedHole, ringPaint);
  }

  @override
  bool shouldRepaint(covariant _SpotlightPainter oldDelegate) => oldDelegate.rect != rect;
}
