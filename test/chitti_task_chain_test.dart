// ================================================================
// chitti_task_chain_test.dart
// ================================================================
// The three rules in chitti_task_chain.dart's header are the whole
// reason that class exists as its own file, and all three fail
// silently if they break: a chain that runs unapproved, a chain that
// keeps going after a failure, or a forty-step plan from a confused
// model. None of those announce themselves — hence tests.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_task_chain.dart';

void main() {
  Map<String, dynamic> step(String action) => <String, dynamic>{'action': action};

  // Stands in for ChittiToolRegistry.requiresConfirmation.
  bool gatesWrites(String? action) =>
      action == 'send_sms' || action == 'propose_write_action';

  group('building', () {
    test('a single step is not a chain — it runs the ordinary way', () {
      expect(ChittiTaskChain.tryBuild([step('read_recent_sms')]), isNull);
    });

    test('two or more steps build a chain', () {
      final chain = ChittiTaskChain.tryBuild([
        step('generate_kyc_report'),
        step('propose_write_action'),
      ]);
      expect(chain, isNotNull);
      expect(chain!.length, 2);
    });

    test('RULE 3 — an over-long plan is refused outright, not truncated', () {
      // Truncating would be the dangerous version: the admin would
      // approve a plan they were shown in full, and a different,
      // shorter one would run.
      final tooMany = List.generate(
        ChittiTaskChain.kMaxSteps + 1,
        (i) => step('read_recent_sms'),
      );
      expect(ChittiTaskChain.tryBuild(tooMany), isNull);
    });

    test('steps with no action name are ignored', () {
      final chain = ChittiTaskChain.tryBuild([
        step('read_recent_sms'),
        <String, dynamic>{'action': ''},
        <String, dynamic>{},
      ]);
      // Only one usable step survives, so it is not a chain.
      expect(chain, isNull);
    });
  });

  group('RULE 1 — any gated step gates the whole chain', () {
    test('a chain ending in a write needs confirmation', () {
      final chain = ChittiTaskChain.tryBuild([
        step('generate_kyc_report'), // read-only
        step('send_sms'), // gated
      ])!;
      expect(chain.requiresConfirmation(gatesWrites), isTrue);
    });

    test('an all-read chain does not', () {
      final chain = ChittiTaskChain.tryBuild([
        step('read_recent_sms'),
        step('summarize_last_call'),
      ])!;
      expect(chain.requiresConfirmation(gatesWrites), isFalse);
    });

    test('nothing is approved until approve() is called', () {
      final chain = ChittiTaskChain.tryBuild([
        step('generate_kyc_report'),
        step('send_sms'),
      ])!;
      expect(chain.isApproved, isFalse);
      chain.approve();
      expect(chain.isApproved, isTrue);
    });
  });

  group('RULE 2 — stop on the first failure', () {
    test('a failure skips every remaining step and ends the chain', () {
      // The case that motivated the rule: approving a hero fails, so
      // the "you are approved!" SMS must never go out.
      final chain = ChittiTaskChain.tryBuild([
        step('generate_kyc_report'),
        step('propose_write_action'),
        step('send_sms'),
      ])!;
      chain.approve();

      chain.completeCurrentStep(success: true); // report read
      expect(chain.currentStep!.action, 'propose_write_action');

      chain.completeCurrentStep(success: false); // approval FAILED

      expect(chain.isFinished, isTrue);
      expect(chain.completedSuccessfully, isFalse);
      expect(chain.failedStep!.action, 'propose_write_action');
      expect(
        chain.steps.last.outcome,
        ChittiStepOutcome.skipped,
        reason: 'the SMS must never run after the approval failed',
      );
    });

    test('completing steps past a finished chain is a no-op', () {
      final chain = ChittiTaskChain.tryBuild([
        step('read_recent_sms'),
        step('summarize_last_call'),
      ])!;
      chain.approve();
      chain.completeCurrentStep(success: false);
      expect(chain.isFinished, isTrue);
      // Must not throw or resurrect the chain.
      chain.completeCurrentStep(success: true);
      expect(chain.completedSuccessfully, isFalse);
    });

    test('every step succeeding completes the chain', () {
      final chain = ChittiTaskChain.tryBuild([
        step('read_recent_sms'),
        step('summarize_last_call'),
      ])!;
      chain.approve();
      chain.completeCurrentStep(success: true);
      chain.completeCurrentStep(success: true);
      expect(chain.isFinished, isTrue);
      expect(chain.completedSuccessfully, isTrue);
      expect(chain.failedStep, isNull);
    });
  });

  group('aborting', () {
    test('a declined chain runs nothing and reports nothing ran', () {
      final chain = ChittiTaskChain.tryBuild([
        step('generate_kyc_report'),
        step('send_sms'),
      ])!;
      chain.abort();
      expect(chain.isFinished, isTrue);
      expect(chain.completedSuccessfully, isFalse);
      expect(chain.failedStep, isNull);
      expect(
        chain.steps.every((s) => s.outcome == ChittiStepOutcome.skipped),
        isTrue,
      );
    });
  });

  group('what the admin is shown', () {
    test('the preview names every step before any of them runs', () {
      final chain = ChittiTaskChain.tryBuild([
        step('generate_kyc_report'),
        step('send_sms'),
      ])!;
      final preview = chain.previewText((args) => args['action'] as String);
      // The whole point of the single-approval design: full
      // consequence visible up front.
      expect(preview, contains('generate_kyc_report'));
      expect(preview, contains('send_sms'));
      expect(preview, contains('1.'));
      expect(preview, contains('2.'));
    });

    test('a stopped chain says how far it got, not that it succeeded', () {
      final chain = ChittiTaskChain.tryBuild([
        step('generate_kyc_report'),
        step('propose_write_action'),
      ])!;
      chain.approve();
      chain.completeCurrentStep(success: true);
      chain.completeCurrentStep(success: false);
      final summary = chain.summaryText();
      expect(summary.toLowerCase(), contains('stopped'));
      expect(summary, contains('1 of 2'));
    });
  });
}
