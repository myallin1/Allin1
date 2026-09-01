// ================================================================
// chitti_screen_agent_test.dart
// ================================================================
// This is the gate standing between a generic "tap whatever the model
// inferred" loop and a phone that also holds banking apps, WhatsApp
// and a live admin console. Nizam explicitly chose the high-autonomy
// mode ("act freely, confirm only risky taps") after being told the
// agent can misjudge — which puts the whole weight of that decision on
// these rules being right.
//
// Every test here is a thing that must NOT happen silently.
import 'package:flutter_test/flutter_test.dart';

import 'package:erode_superapp/services/chitti/chitti_screen_agent.dart';

void main() {
  group('free movement stays free — the point of the mode', () {
    test('scrolling, back and home never stop to ask', () {
      for (final action in ['scroll', 'go_back', 'go_home']) {
        expect(
          ChittiScreenAgent.assess(actionType: action).needsConfirmation,
          isFalse,
          reason: action,
        );
      }
    });

    test('an ordinary menu tap runs without asking', () {
      final decision = ChittiScreenAgent.assess(
        actionType: 'click',
        targetText: 'Gallery',
        screenText: 'Gallery  Camera  Files  Settings',
      );
      expect(decision.needsConfirmation, isFalse);
    });
  });

  group('LAYER 1 — destructive verbs in the element itself', () {
    test('money verbs always confirm', () {
      for (final label in ['Pay Now', 'Transfer', 'Withdraw', 'Buy']) {
        expect(
          ChittiScreenAgent.assess(actionType: 'click', targetText: label)
              .needsConfirmation,
          isTrue,
          reason: label,
        );
      }
    });

    test('destruction verbs always confirm', () {
      for (final label in ['Delete', 'Remove', 'Uninstall', 'Reset']) {
        expect(
          ChittiScreenAgent.assess(actionType: 'click', targetText: label)
              .needsConfirmation,
          isTrue,
          reason: label,
        );
      }
    });

    test('decisions about PEOPLE confirm — approving a hero is not navigation', () {
      for (final label in ['Approve', 'Reject', 'Block', 'Suspend']) {
        expect(
          ChittiScreenAgent.assess(actionType: 'click', targetText: label)
              .needsConfirmation,
          isTrue,
          reason: label,
        );
      }
    });

    test('outbound sending confirms — a message cannot be unsent', () {
      expect(
        ChittiScreenAgent.assess(actionType: 'click', targetText: 'Send')
            .needsConfirmation,
        isTrue,
      );
    });

    test('Tamil labels are caught too, not just English', () {
      // An English-only list would wave every Tamil-labelled
      // destructive button straight through — on a phone that runs in
      // Tamil, that is most of them.
      for (final label in ['நீக்கு', 'பணம் செலுத்து', 'ஒப்புதல்', 'ரத்து']) {
        expect(
          ChittiScreenAgent.assess(actionType: 'click', targetText: label)
              .needsConfirmation,
          isTrue,
          reason: label,
        );
      }
    });
  });

  group('LAYER 2 — the screen makes bland buttons dangerous', () {
    test('"Continue" on a payment screen still confirms', () {
      // The case per-element matching alone would miss entirely: the
      // caption is harmless, the context is not.
      final decision = ChittiScreenAgent.assess(
        actionType: 'click',
        targetText: 'Continue',
        screenText: 'Enter UPI PIN  Amount: 4500  Total payable',
      );
      expect(decision.needsConfirmation, isTrue);
    });

    test('"Next" on a KYC screen still confirms', () {
      final decision = ChittiScreenAgent.assess(
        actionType: 'click',
        targetText: 'Next',
        screenText: 'Aadhaar number  PAN card  KYC verification',
      );
      expect(decision.needsConfirmation, isTrue);
    });

    test('the same "Continue" on an ordinary screen does NOT confirm', () {
      // Proof that LAYER 2 keys off context and is not just a blanket
      // "confirm everything", which would defeat the chosen mode.
      final decision = ChittiScreenAgent.assess(
        actionType: 'click',
        targetText: 'Continue',
        screenText: 'Welcome  Choose your language  Continue',
      );
      expect(decision.needsConfirmation, isFalse);
    });

    test('a Tamil payment screen is recognised as sensitive', () {
      final decision = ChittiScreenAgent.assess(
        actionType: 'click',
        targetText: 'சரி',
        screenText: 'கட்டணம் செலுத்த வேண்டிய தொகை ரூபாய் 2000',
      );
      expect(decision.needsConfirmation, isTrue);
    });
  });

  group('typing is held to a higher bar than tapping', () {
    test('never auto-types into a screen asking for OTP or a password', () {
      // This is how an agent that only THINKS it understood a form
      // ends up entering credentials.
      final decision = ChittiScreenAgent.assess(
        actionType: 'type',
        targetText: 'Enter code',
        screenText: 'Enter the OTP sent to your phone',
      );
      expect(decision.needsConfirmation, isTrue);
    });

    test('typing into an ordinary search box is fine', () {
      final decision = ChittiScreenAgent.assess(
        actionType: 'type',
        targetText: 'Search',
        screenText: 'Search photos  Albums  Recent',
      );
      expect(decision.needsConfirmation, isFalse);
    });
  });

  group('the reason is always sayable', () {
    test('a confirmation can explain itself to the admin', () {
      final decision = ChittiScreenAgent.assess(
        actionType: 'click',
        targetText: 'Delete',
      );
      // A gate that cannot say what it is worried about is just a nag.
      expect(decision.reason, isNotEmpty);
      expect(decision.reason, contains('Delete'));
    });
  });
}
