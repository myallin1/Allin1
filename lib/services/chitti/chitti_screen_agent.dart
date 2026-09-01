// ================================================================
// chitti_screen_agent.dart — deciding which taps Chitti may make on
// its own, and which ones stop and ask.
// ================================================================
// NEW (Aug 31 2026 — Nizam: "ovvoru feature-kum function calling add
// pannama ... chitti puthusa paakura page-a avane purinju admin-kitta
// kettu option select panni" — plus his explicit choice of "act
// freely, confirm only risky taps" when asked how much authority the
// agent gets).
//
// WHAT THIS FILE IS FOR
// The generic screen loop (read the screen → ask the model what to do
// → do it → read again) removes the need for a hand-written tool per
// feature. What it also removes is the safety that came for free with
// that tool list: every previous action Chitti could take was one
// somebody had deliberately written, named and gated. A generic loop
// can tap ANYTHING the accessibility tree exposes, on a phone that
// also has banking apps, WhatsApp and a live admin console on it.
//
// WHY THE MODEL DOES NOT GET TO MAKE THIS CALL
// The obvious design is to let the model tag its own step "risky:
// true/false". That is circular and unsafe: the failure being guarded
// against IS the model misreading the screen, and a model that
// misreads a screen will misjudge the risk of what it misread with
// exactly the same confidence. So the gate here is deterministic and
// local — plain text matching over the element being tapped and the
// screen it sits on. Boring on purpose. It cannot be argued out of a
// confirmation by a persuasive plan, and it behaves identically
// whether the model is Groq, Gemini, DeepSeek or offline.
//
// TWO LAYERS, because per-element matching alone is not enough:
//
//   1. THE ELEMENT — a destructive or financial verb in the thing
//      being tapped ("Delete", "Pay", "Send", "Approve", "நீக்கு").
//
//   2. THE SCREEN — some screens make EVERY button consequential.
//      On a payment or KYC screen, a button labelled something bland
//      like "Continue" or "Next" is the button that spends money or
//      approves a person. Layer 1 alone would wave those through,
//      because the danger is in the context, not the caption. So a
//      sensitive-looking screen raises the bar for everything on it.
//
// FAIL-SAFE DIRECTION: when the two layers disagree, the cautious
// answer wins. An unnecessary confirmation costs one tap. A missed
// one can send money, delete a record, or approve the wrong hero.
import 'package:flutter/foundation.dart';

/// What the agent is allowed to do with a proposed step.
enum ChittiTapVerdict {
  /// Ordinary navigation — scroll, open, go back, tap a tab. Runs
  /// without stopping, which is the whole point of the mode Nizam
  /// chose.
  proceed,

  /// Consequential — name it and wait for a human yes.
  confirmFirst,
}

@immutable
class ChittiTapDecision {
  const ChittiTapDecision({required this.verdict, required this.reason});

  final ChittiTapVerdict verdict;

  /// Why, in words worth showing the admin. A confirmation that cannot
  /// say what it is worried about is just a nag.
  final String reason;

  bool get needsConfirmation => verdict == ChittiTapVerdict.confirmFirst;
}

class ChittiScreenAgent {
  ChittiScreenAgent._();

  // ── LAYER 1: the element being tapped ────────────────────────────
  //
  // Verbs that spend, send, destroy or decide. Deliberately broad —
  // this list costing a few extra confirmations is a far better
  // failure than it missing one. Tamil and Tanglish included because
  // this admin's own phone runs in Tamil, and an English-only list
  // would silently pass every Tamil-labelled destructive button.
  static final RegExp _destructiveElement = RegExp(
    r'\b('
    // money
    r'pay|paying|payment|send money|transfer|withdraw|deposit|recharge|'
    r'buy|purchase|checkout|place order|confirm order|subscribe|'
    // destruction
    r'delete|remove|clear all|erase|discard|uninstall|reset|wipe|'
    r'cancel order|cancel booking|deactivate|close account|'
    // decisions about people
    r'approve|reject|verify|confirm|block|unblock|ban|suspend|'
    // outbound communication
    r'send|post|publish|share|submit|'
    // account
    r'log ?out|sign ?out|change password|delete account'
    r')\b',
    caseSensitive: false,
  );

  static final RegExp _destructiveTamil = RegExp(
    'நீக்கு|அழி|பணம்|செலுத்து|அனுப்பு|உறுதி|ஒப்புதல்|நிராகரி|'
    'வாங்கு|ரத்து|வெளியேறு|மாற்று',
  );

  // ── LAYER 2: the screen it sits on ───────────────────────────────
  //
  // Context that makes a bland caption dangerous. If any of these
  // appear anywhere in the screen text, even "Continue" gets a
  // confirmation — see the two-layer note in the header.
  static final RegExp _sensitiveScreen = RegExp(
    r'\b('
    r'upi|paytm|gpay|phonepe|netbanking|net banking|'
    r'card number|cvv|expiry|ifsc|account number|a/c no|'
    r'balance|wallet|amount|total payable|pay now|'
    r'aadhaar|aadhar|pan card|kyc|otp|'
    r'password|passcode|pin'
    r')\b',
    caseSensitive: false,
  );

  static final RegExp _sensitiveScreenTamil = RegExp(
    'பணம்|கட்டணம்|வங்கி|ரூபாய்|கடவுச்சொல்|ஆதார்',
  );

  /// Actions that are safe by construction regardless of labels —
  /// they move around, they do not commit anything.
  static const Set<String> _navigationOnly = <String>{
    'scroll',
    'go_back',
    'goback',
    'go_home',
    'gohome',
    'read_screen',
    'readscreen',
  };

  /// Decides whether a proposed step may run unattended.
  ///
  /// [actionType] is the primitive ('click', 'type', 'scroll',
  /// 'launch_app', …). [targetText] is the element's own label.
  /// [screenText] is the current readScreen() dump — optional, but
  /// passing it is what enables LAYER 2, and without it a bland button
  /// on a payment screen looks exactly like a bland button anywhere
  /// else.
  static ChittiTapDecision assess({
    required String actionType,
    String targetText = '',
    String screenText = '',
  }) {
    final action = actionType.trim().toLowerCase();

    // Pure movement commits nothing, on any screen.
    if (_navigationOnly.contains(action)) {
      return const ChittiTapDecision(
        verdict: ChittiTapVerdict.proceed,
        reason: 'Navigation only — nothing is committed.',
      );
    }

    // Typing is never auto-run into a sensitive screen: that is how
    // credentials and OTPs get entered by something that only thought
    // it understood the form.
    final sensitiveContext = _sensitiveScreen.hasMatch(screenText) ||
        _sensitiveScreenTamil.hasMatch(screenText);

    if (action == 'type' || action == 'input' || action == 'inputtext') {
      if (sensitiveContext) {
        return const ChittiTapDecision(
          verdict: ChittiTapVerdict.confirmFirst,
          reason: 'This screen asks for payment or identity details — '
              "I won't type into it without your say-so.",
        );
      }
    }

    final target = targetText.trim();
    final destructiveTarget = _destructiveElement.hasMatch(target) ||
        _destructiveTamil.hasMatch(target);

    if (destructiveTarget) {
      return ChittiTapDecision(
        verdict: ChittiTapVerdict.confirmFirst,
        reason: target.isEmpty
            ? 'That looks like it does something irreversible.'
            : '"$target" looks like it does something irreversible.',
      );
    }

    // LAYER 2 — the caption looked harmless, but the screen does not.
    if (sensitiveContext) {
      return const ChittiTapDecision(
        verdict: ChittiTapVerdict.confirmFirst,
        reason: 'This looks like a payment or identity screen, so I '
            'want a yes before tapping anything on it.',
      );
    }

    return const ChittiTapDecision(
      verdict: ChittiTapVerdict.proceed,
      reason: 'Ordinary navigation.',
    );
  }
}
