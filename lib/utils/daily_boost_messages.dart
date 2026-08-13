// ================================================================
// daily_boost_messages.dart — the "daily motivational push"
// ================================================================
// NEW (Aug 12 2026 — Nizam: "app close panitu reopen pannumbothu lam
// customer ah daily boost pandramari motivational simple puch dialog
// anga varanum... hero ku avar work pandrathukum, earn panni develop
// pandrathukum namma allin1 wish and motivate pandrmari irukanum"):
// one small, non-blocking message shown once per app session (cold
// boot), right under the time-of-day greeting — a different message on
// (almost) every reopen, picked at random from these lists. Customer's
// list is generic positive/engagement framing; Hero's is specifically
// about earning and growing, per Nizam's explicit distinction between
// the two.
//
// Deliberately a plain const List<String>, not a Firestore collection —
// this is copy, not data that changes per-user or needs admin editing
// yet; keeping it fully local means showing it costs zero reads and can
// never fail/lag waiting on a network call.
import 'dart:math';

import 'package:flutter/material.dart';

const List<String> kCustomerBoostMessages = [
  'Whatever you need today, Allin1 has your back. 💗',
  'One tap away from food, rides, and everything Erode. 🚀',
  'Thanks for being part of the Allin1 family!',
  'Your city, your app — glad to have you here today.',
  'Erode runs faster with you on Allin1. 🏙️',
  'Hope your day is off to a great start!',
  'Small city, big convenience — that\'s Allin1.',
  'Every order you place helps a local hero earn. 🙌',
  'Here for whatever you need, whenever you need it.',
  'Made with ❤ in Erode, just for you.',
];

const List<String> kHeroBoostMessages = [
  'Every ride you take today is a step forward. Let\'s go! 🏍️',
  'Your hustle keeps Erode moving — thank you for showing up.',
  'More rides, more earnings — Allin1 is rooting for you today. 💪',
  'You\'re building something real, one trip at a time.',
  'Stay online, stay sharp — today\'s a good day to earn.',
  'Erode needs heroes like you. Go make it count!',
  'Your effort today is your growth tomorrow. Keep going.',
  'Every customer you help is one step closer to your goal.',
  'Proud to have you on the team — let\'s earn well today!',
  'Small steps, steady earnings — you\'ve got this.',
];

final Random _rng = Random();

String randomCustomerBoostMessage() =>
    kCustomerBoostMessages[_rng.nextInt(kCustomerBoostMessages.length)];

String randomHeroBoostMessage() =>
    kHeroBoostMessages[_rng.nextInt(kHeroBoostMessages.length)];

/// Shows one boost message as a floating SnackBar. Callers fire this
/// from initState() (once per screen mount = once per app cold boot),
/// with a short delay so it never races the migration-gate check or the
/// PWA update banner for the same slice of screen. Non-blocking, no
/// buttons, auto-dismisses on its own — a "daily push" that never
/// forces the customer/hero to interact with it.
void showDailyBoostSnackBar(
  BuildContext context,
  String message, {
  Color accentColor = const Color(0xFFFF4FA3),
}) {
  if (!context.mounted) return;
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: 13),
      ),
      backgroundColor: const Color(0xFF1A1A2A),
      behavior: SnackBarBehavior.floating,
      duration: const Duration(seconds: 4),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: accentColor.withValues(alpha: 0.4)),
      ),
      margin: const EdgeInsets.fromLTRB(16, 0, 16, 16),
    ),
  );
}
