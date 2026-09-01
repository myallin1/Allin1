// ================================================================
// chitti_screen_loop.dart — read the screen, decide one step, do it,
// look again.
// ================================================================
// NEW (Aug 31 2026 — Nizam: "ovvoru feature-kum function calling add
// pannama ... chitti puthusa paakura page-a avane purinju"; CTO
// approved max 8 steps, Groq primary).
//
// This is the loop that removes the need for a hand-written tool per
// feature. Instead of teaching Chitti "open_gallery", it reads
// whatever is actually on screen, asks the model which single element
// to touch next, touches it, and looks again — so a screen nobody has
// ever described to it still works.
//
// THE GATE IS NOT HERE, AND THAT IS THE POINT.
// Every step this loop produces goes through ChittiScreenAgent.assess()
// before anything happens. That separation is deliberate: the model
// decides what would be USEFUL, and a deterministic local rule decides
// what is SAFE. Folding the two together — letting the model mark its
// own steps safe — would be circular, because the failure being
// guarded against is the model misreading the very screen it is
// judging. See chitti_screen_agent.dart's header.
//
// THREE HARD STOPS, none of which depend on the model behaving:
//   1. kMaxSteps (8, per CTO) — a confused model cannot wander across
//      the phone indefinitely. It stops and reports where it got to.
//   2. A step that fails to parse ends the run. A garbled reply means
//      the model is not tracking the screen, and guessing at its
//      intent is how a wrong element gets tapped.
//   3. Any step the agent flags stops the loop and asks. It does not
//      "ask and continue optimistically".
//
// COST, because this is the expensive path in the app.
// One model call per step, so a 6-step job is 6 calls — that is
// inherent to understanding arbitrary screens and cannot be made
// offline (the on-device intent engine works only because its phrases
// and tools are both fixed). Groq is primary for latency and price;
// the active provider is the fallback so a missing Groq key degrades
// instead of dying.
import 'dart:convert';

import 'package:flutter/foundation.dart';

import '../guru_admin_api_service.dart';
import '../guru_api_service.dart';
import 'chitti_accessibility_bridge.dart';
import 'chitti_screen_agent.dart';

/// One move the model wants to make on the current screen.
@immutable
class ChittiScreenStep {
  const ChittiScreenStep({
    required this.action,
    this.target = '',
    this.text = '',
    this.say = '',
    this.done = false,
  });

  /// 'click' | 'type' | 'scroll' | 'go_back' | 'go_home' | 'launch_app'
  final String action;

  /// The element label to act on, or the app name for launch_app.
  final String target;

  /// What to type, for 'type'.
  final String text;

  /// Optional line to speak while doing it.
  final String say;

  /// The model believes the goal is met — stop looping.
  final bool done;

  /// Parses one step out of a raw model reply.
  ///
  /// Deliberately tolerant of the three things models actually do to
  /// JSON in practice — wrap it in ```json fences, print a sentence
  /// before it, or both — and deliberately INTOLERANT of anything it
  /// cannot read cleanly, returning null rather than a half-guessed
  /// step. A half-guessed step is a tap on the wrong element.
  static ChittiScreenStep? parse(String raw) {
    var body = raw.trim();
    if (body.isEmpty) return null;

    // Strip markdown fences, with or without a language tag.
    final fence = RegExp(r'```(?:json)?\s*([\s\S]*?)\s*```');
    final fenced = fence.firstMatch(body);
    if (fenced != null) body = fenced.group(1)!.trim();

    // Fall back to the outermost {...} when the model added prose.
    if (!body.startsWith('{')) {
      final start = body.indexOf('{');
      final end = body.lastIndexOf('}');
      if (start == -1 || end <= start) return null;
      body = body.substring(start, end + 1);
    }

    try {
      final decoded = jsonDecode(body);
      if (decoded is! Map<String, dynamic>) return null;

      final done = decoded['done'] == true;
      final action = (decoded['action'] as String?)?.trim().toLowerCase() ?? '';
      // "done" is the one case with no action to perform.
      if (!done && action.isEmpty) return null;

      return ChittiScreenStep(
        action: action,
        target: (decoded['target'] as String?)?.trim() ?? '',
        text: (decoded['text'] as String?)?.trim() ?? '',
        say: (decoded['say'] as String?)?.trim() ?? '',
        done: done,
      );
    } catch (_) {
      return null;
    }
  }
}

/// Why a run stopped — so Chitti can say something true about it.
enum ChittiLoopEnding {
  /// The model reported the goal met.
  goalReached,

  /// Hit kMaxSteps.
  stepLimit,

  /// A step needs a human yes before it can run.
  awaitingConfirmation,

  /// The model's reply could not be read as a step.
  unreadableStep,

  /// A tap/type reported failure.
  actionFailed,
}

@immutable
class ChittiLoopResult {
  const ChittiLoopResult({
    required this.ending,
    required this.stepsTaken,
    this.pendingStep,
    this.pendingReason = '',
    this.transcript = const <String>[],
  });

  final ChittiLoopEnding ending;
  final int stepsTaken;

  /// Set when [ending] is awaitingConfirmation — the step to put in
  /// front of the admin.
  final ChittiScreenStep? pendingStep;
  final String pendingReason;

  /// What was actually done, in order — for reporting back.
  final List<String> transcript;

  String summaryFor({bool isTamil = false}) {
    switch (ending) {
      case ChittiLoopEnding.goalReached:
        return isTamil
            ? 'முடிச்சிட்டேன் பாஸ் ($stepsTaken step).'
            : 'Done — finished in $stepsTaken steps.';
      case ChittiLoopEnding.stepLimit:
        return isTamil
            ? '$stepsTaken step பண்ணிட்டேன், ஆனா இன்னும் முடியல — '
                'நீங்க பாத்துக்கோங்க பாஸ்.'
            : "I did $stepsTaken steps but couldn't finish it — "
                'taking a look yourself may be quicker from here.';
      case ChittiLoopEnding.awaitingConfirmation:
        return pendingReason;
      case ChittiLoopEnding.unreadableStep:
        return isTamil
            ? 'இந்த screen-ஐ சரியா புரிஞ்சுக்க முடியல பாஸ், நிறுத்திட்டேன்.'
            : "I couldn't read that screen clearly, so I stopped rather "
                'than guess.';
      case ChittiLoopEnding.actionFailed:
        return isTamil
            ? 'ஒரு step வேலை செய்யல, அதனால நிறுத்திட்டேன் பாஸ்.'
            : "A step didn't go through, so I stopped there.";
    }
  }
}

class ChittiScreenLoop {
  ChittiScreenLoop._();

  /// CTO-approved cap. A confused model gets 8 moves, not the phone.
  static const int kMaxSteps = 8;

  static final GuruAdminApiService _groq = GuruAdminApiService();
  static final GuruApiService _fallback = GuruApiService();

  /// Works toward [goal] on whatever is currently on screen.
  ///
  /// Never throws — every exit is a ChittiLoopResult the caller can
  /// speak, because this runs hands-free and an unhandled error here
  /// would leave Chitti silent mid-task.
  static Future<ChittiLoopResult> run(String goal) async {
    final transcript = <String>[];
    var steps = 0;

    while (steps < kMaxSteps) {
      final screen = await _readScreenSafely();
      if (screen.isEmpty) {
        return ChittiLoopResult(
          ending: ChittiLoopEnding.unreadableStep,
          stepsTaken: steps,
          transcript: transcript,
        );
      }

      final reply = await _askModel(goal: goal, screen: screen, done: transcript);
      final step = ChittiScreenStep.parse(reply);
      if (step == null) {
        return ChittiLoopResult(
          ending: ChittiLoopEnding.unreadableStep,
          stepsTaken: steps,
          transcript: transcript,
        );
      }
      if (step.done) {
        return ChittiLoopResult(
          ending: ChittiLoopEnding.goalReached,
          stepsTaken: steps,
          transcript: transcript,
        );
      }

      // THE GATE. Nothing below this line runs until it passes.
      final decision = ChittiScreenAgent.assess(
        actionType: step.action,
        targetText: step.target,
        screenText: screen,
      );
      if (decision.needsConfirmation) {
        return ChittiLoopResult(
          ending: ChittiLoopEnding.awaitingConfirmation,
          stepsTaken: steps,
          pendingStep: step,
          pendingReason: decision.reason,
          transcript: transcript,
        );
      }

      final ok = await _perform(step);
      steps++;
      transcript.add('${step.action} ${step.target}'.trim());
      if (!ok) {
        return ChittiLoopResult(
          ending: ChittiLoopEnding.actionFailed,
          stepsTaken: steps,
          transcript: transcript,
        );
      }
    }

    return ChittiLoopResult(
      ending: ChittiLoopEnding.stepLimit,
      stepsTaken: steps,
      transcript: transcript,
    );
  }

  /// Runs a single step the admin has just approved, so the caller can
  /// resume after an awaitingConfirmation stop.
  static Future<bool> performApproved(ChittiScreenStep step) => _perform(step);

  static Future<String> _readScreenSafely() async {
    try {
      final screen = await ChittiAccessibilityBridge.instance.readScreen();
      // The bridge returns this sentinel when no service is attached.
      if (screen.startsWith('Could not read screen')) return '';
      return screen;
    } catch (e) {
      debugPrint('[ChittiScreenLoop] readScreen failed: $e');
      return '';
    }
  }

  static Future<bool> _perform(ChittiScreenStep step) async {
    final bridge = ChittiAccessibilityBridge.instance;
    try {
      switch (step.action) {
        case 'click':
          return await bridge.clickElement(step.target);
        case 'type':
        case 'input':
        case 'inputtext':
          return await bridge.inputText(step.target, step.text);
        case 'scroll':
          return await bridge.scroll(step.target.isEmpty ? 'down' : step.target);
        case 'go_back':
        case 'goback':
          return await bridge.goBack();
        case 'go_home':
        case 'gohome':
          return await bridge.goHome();
        case 'launch_app':
        case 'launchapp':
          return await bridge.launchApp(step.target);
        default:
          debugPrint('[ChittiScreenLoop] unknown action "${step.action}"');
          return false;
      }
    } catch (e) {
      debugPrint('[ChittiScreenLoop] perform failed: $e');
      return false;
    }
  }

  /// Groq first (latency + cost), active provider as fallback.
  static Future<String> _askModel({
    required String goal,
    required String screen,
    required List<String> done,
  }) async {
    // The screen dump can be long; the tail is usually the actionable
    // part but the head carries the title, so keep both ends.
    final trimmedScreen =
        screen.length > 2500 ? '${screen.substring(0, 1500)}\n…\n${screen.substring(screen.length - 900)}' : screen;

    final prompt = '''
You are controlling an Android phone for the app's admin, one step at a time.

GOAL: $goal
${done.isEmpty ? '' : 'ALREADY DONE: ${done.join(' → ')}'}

CURRENT SCREEN (accessibility text):
$trimmedScreen

Reply with ONE JSON object and nothing else:
{"action":"click|type|scroll|go_back|go_home|launch_app","target":"exact element text from the screen above","text":"only for type","say":"short line for the user","done":false}

Rules:
- "target" MUST be text that appears verbatim on the screen above. Never invent a label.
- If the goal is already achieved, reply {"done":true}.
- If the screen does not contain what you need, use scroll or go_back.
- One step only. Do not plan ahead.''';

    try {
      final reply = await _groq.sendMessage(message: prompt);
      if (reply.trim().isNotEmpty && !_looksLikeServiceError(reply)) return reply;
    } catch (e) {
      debugPrint('[ChittiScreenLoop] Groq step failed, falling back: $e');
    }

    try {
      return await _fallback.sendMessage(message: prompt);
    } catch (e) {
      debugPrint('[ChittiScreenLoop] fallback step failed: $e');
      return '';
    }
  }

  /// GuruAdminApiService reports outages as ordinary prose replies
  /// rather than throwing, so a plain try/catch would treat "not
  /// configured" as a successful answer and then fail to parse it.
  static bool _looksLikeServiceError(String reply) {
    final lower = reply.toLowerCase();
    return lower.contains('not configured yet') ||
        lower.contains('temporarily unavailable') ||
        lower.contains('took too long');
  }
}
