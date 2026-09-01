// ================================================================
// chitti_task_chain.dart — one spoken request, several tools, ONE yes.
// ================================================================
// NEW (Aug 31 2026 — Nizam: "ovvoru calling ah ready panni approve
// pandrathuku bathila ... admin soldra work ah end to end support
// pannanum").
//
// THE PROBLEM THIS SOLVES
// Until now every Chitti request resolved to exactly ONE tool call.
// "Approve the pending hero and send them a welcome SMS" is one
// sentence and one intention, but three tools — read the KYC, write
// the approval, send the message — so Chitti would do one, stop, and
// wait to be asked again. Worse, each gated tool asked for its own
// separate yes, so finishing a single job meant approving three times.
// That is the friction the request names.
//
// WHAT THIS IS NOT
// It is NOT the removal of the confirmation gates. Those exist because
// this admin build can approve a real hero's livelihood
// (propose_write_action), text a real customer (send_sms), tap the
// live screen (system_perform_action) and open a real GitHub issue
// that starts an automated coding run (create_dev_task). Deleting the
// gate would make a single misheard sentence able to do all of that
// unreviewed — the opposite of safe autonomy.
//
// So the gate MOVES rather than disappears: instead of N separate
// approvals mid-job, the whole plan is named ONCE, up front, and
// approved once. The admin still sees exactly what is about to happen
// before anything happens; they just say yes a single time and then
// the job runs to completion. That is genuinely less friction AND
// strictly more visibility than approving steps blind one at a time,
// because the full consequence is on screen before step one runs.
//
// THREE RULES, and why each exists:
//
// RULE 1 — ANY gated step gates the WHOLE chain.
// A chain is approved as a unit, so it must be judged as a unit. A
// plan that ends in "…and text the customer" is a plan that sends a
// text, no matter how harmless its first two steps look.
//
// RULE 2 — STOP on the first failure. Never continue past it.
// This is the rule that actually protects people. "Approve the hero,
// then SMS them the good news" must not send the good news when the
// approval itself failed. A half-finished chain that keeps going is
// how an admin ends up telling someone they are approved when they
// are not.
//
// RULE 3 — a hard cap on chain length.
// The steps come from a model. A hallucinated forty-step plan should
// be impossible to run, not merely unlikely, and a cap is the only
// version of that guarantee that does not depend on the model
// behaving.
//
// Pure Dart on purpose: no Flutter, no plugins, no I/O — the same
// reasoning as chitti_conversation_controller.dart. The rules above
// are exactly the kind that rot silently when they live inline in a
// widget, and they are all directly testable here.
import 'package:flutter/foundation.dart';

/// What happened to one step once it ran.
enum ChittiStepOutcome {
  /// Not attempted yet.
  pending,

  /// Ran and reported success.
  done,

  /// Ran and failed — under RULE 2 the chain stops here.
  failed,

  /// Never attempted, because an earlier step failed.
  skipped,
}

/// One tool call in a chain: the same args map a single-tool call uses.
@immutable
class ChittiTaskStep {
  const ChittiTaskStep({
    required this.args,
    this.outcome = ChittiStepOutcome.pending,
  });

  final Map<String, dynamic> args;
  final ChittiStepOutcome outcome;

  String? get action => args['action'] as String?;

  ChittiTaskStep withOutcome(ChittiStepOutcome next) =>
      ChittiTaskStep(args: args, outcome: next);
}

/// An ordered plan of tool calls, approved once and run to completion.
class ChittiTaskChain {
  ChittiTaskChain._(this._steps);

  /// Builds a chain, or returns null when there is nothing worth
  /// chaining.
  ///
  /// A single step is deliberately NOT a chain: it would add a plan
  /// preview and an extra confirmation to the simple case that already
  /// works well, which is the opposite of the point. Null means "run
  /// this the ordinary single-tool way".
  ///
  /// Over [maxSteps] returns null too — see RULE 3. Refusing to build
  /// the chain at all is safer than silently truncating a plan the
  /// admin was shown in full, which would approve one thing and run
  /// another.
  static ChittiTaskChain? tryBuild(
    List<Map<String, dynamic>> stepArgs, {
    int maxSteps = kMaxSteps,
  }) {
    final usable = stepArgs
        .where((a) => (a['action'] as String?)?.trim().isNotEmpty ?? false)
        .toList(growable: false);
    if (usable.length < 2 || usable.length > maxSteps) return null;
    return ChittiTaskChain._(
      usable.map((a) => ChittiTaskStep(args: a)).toList(),
    );
  }

  /// RULE 3. Chosen to comfortably fit any real admin job ("read it,
  /// approve it, tell them") while making a runaway plan impossible.
  static const int kMaxSteps = 5;

  List<ChittiTaskStep> _steps;
  int _cursor = 0;
  bool _approved = false;
  bool _aborted = false;

  List<ChittiTaskStep> get steps => List.unmodifiable(_steps);

  int get length => _steps.length;

  /// The step about to run, or null when the chain is finished.
  ChittiTaskStep? get currentStep =>
      (_cursor >= 0 && _cursor < _steps.length) ? _steps[_cursor] : null;

  /// 1-based, for speaking progress ("step 2 of 3").
  int get currentStepNumber => _cursor + 1;

  bool get isApproved => _approved;

  bool get isFinished => _aborted || _cursor >= _steps.length;

  /// True when every step ran and none failed.
  bool get completedSuccessfully =>
      !_aborted && _steps.every((s) => s.outcome == ChittiStepOutcome.done);

  /// The step that failed, if any — what to name when reporting a
  /// stopped chain.
  ChittiTaskStep? get failedStep {
    for (final step in _steps) {
      if (step.outcome == ChittiStepOutcome.failed) return step;
    }
    return null;
  }

  /// RULE 1 — the chain needs a yes if ANY step does.
  ///
  /// [isGated] is injected rather than calling the registry directly so
  /// this class stays free of imports and directly testable; callers
  /// pass ChittiToolRegistry.requiresConfirmation.
  bool requiresConfirmation(bool Function(String? action) isGated) =>
      _steps.any((s) => isGated(s.action));

  /// The whole plan in one message, for the single up-front approval.
  ///
  /// [describe] turns one step's args into a phrase; the caller owns
  /// the wording because it already has the per-tool confirmation
  /// copy, and duplicating that here would let the two drift.
  String previewText(
    String Function(Map<String, dynamic> args) describe, {
    bool isTamil = false,
  }) {
    final buffer = StringBuffer()
      ..writeln(
        isTamil
            ? 'இதை ஒரே தடவையில் செய்யப்போறேன் பாஸ்:'
            : "Here's everything I'll do:",
      );
    for (var i = 0; i < _steps.length; i++) {
      buffer.writeln('${i + 1}. ${describe(_steps[i].args)}');
    }
    buffer.write(
      isTamil ? 'இதெல்லாம் செய்யட்டுமா?' : 'Should I go ahead with all of it?',
    );
    return buffer.toString();
  }

  /// Records the single human yes. Nothing runs before this.
  void approve() => _approved = true;

  /// Records the outcome of [currentStep] and moves on.
  ///
  /// RULE 2 lives here: a failure marks every remaining step skipped
  /// and ends the chain, rather than advancing to the next one.
  void completeCurrentStep({required bool success}) {
    if (isFinished) return;
    if (success) {
      _steps[_cursor] = _steps[_cursor].withOutcome(ChittiStepOutcome.done);
      _cursor++;
      return;
    }
    _steps[_cursor] = _steps[_cursor].withOutcome(ChittiStepOutcome.failed);
    for (var i = _cursor + 1; i < _steps.length; i++) {
      _steps[i] = _steps[i].withOutcome(ChittiStepOutcome.skipped);
    }
    _aborted = true;
  }

  /// Abandons the chain — the admin said no, or changed the subject.
  void abort() {
    for (var i = _cursor; i < _steps.length; i++) {
      _steps[i] = _steps[i].withOutcome(ChittiStepOutcome.skipped);
    }
    _aborted = true;
  }

  /// What to say once the chain stops running, either way.
  String summaryText({bool isTamil = false}) {
    if (completedSuccessfully) {
      return isTamil
          ? 'எல்லா $length வேலையும் முடிச்சிட்டேன் பாஸ்.'
          : 'Done — all $length steps finished.';
    }
    final failed = failedStep;
    final doneCount =
        _steps.where((s) => s.outcome == ChittiStepOutcome.done).length;
    if (failed != null) {
      return isTamil
          ? '$doneCount வேலை முடிஞ்சது, ஆனா அடுத்த step-ல நின்னுடுச்சு பாஸ் — '
              'மீதி வேலையை நான் தொடரல, நீங்க பாருங்க.'
          : 'Completed $doneCount of $length, then stopped — the next step '
              "failed, so I didn't run the rest.";
    }
    return isTamil
        ? 'சரி பாஸ், நிறுத்திட்டேன்.'
        : 'Okay — stopped, nothing further was run.';
  }
}
