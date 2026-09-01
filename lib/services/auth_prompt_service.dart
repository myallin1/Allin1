// ================================================================
// auth_prompt_service.dart
// ================================================================
// NEW (Aug 11 2026 — Guest Mode / Deferred Login).
//
// Two responsibilities, deliberately in one small file:
//   1. requireRealAuth() — the guard every gated action calls.
//   2. AuthPromptService — the 30s "why not sign in?" nudge on Home.
//
// Both funnel into the same widget (showAuthGateSheet) so there is
// exactly one login UI in the customer app to maintain.
// ================================================================
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widgets/auth/auth_gate_sheet.dart';
import 'app_palette.dart';
import 'auth_service.dart';

/// The ONE way this app tells someone they need an account.
///
/// Replaces the scattered `backgroundColor: Colors.redAccent` /
/// `Color(0xFFFF5252)` snackbars that used to deliver this message.
/// Needing to sign in is not an ERROR — the customer did nothing wrong —
/// so it should not borrow the same red the app uses for genuine
/// failures. Brand pink, white text, floating and rounded to match the
/// auth sheet it usually accompanies.
///
/// [kPink] comes from app_palette.dart and is theme-reactive, so this
/// follows whichever of the 5 themes the customer picked rather than
/// freezing one hardcoded pink.
void showSignInRequiredSnack(
  BuildContext context, {
  String message = 'Please sign in to continue',
}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(
        message,
        style: const TextStyle(
          color: Colors.white,
          fontWeight: FontWeight.w600,
        ),
      ),
      backgroundColor: kPink,
      behavior: SnackBarBehavior.floating,
      margin: const EdgeInsets.all(14),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}

/// Call at the TOP of any action a guest must not perform.
/// Returns true if the caller may proceed.
///
/// Usage:
///   if (!await requireRealAuth(context, reason: 'Sign in to book a Hero')) {
///     return;
///   }
///   ...existing booking code, completely unchanged...
///
/// Deliberately a plain function rather than a widget wrapper: these
/// actions all fire inside onPressed callbacks, so a guard on the first
/// line of the handler is both simpler to add and impossible to bypass
/// by reaching the screen through some other route.
///
/// Because the sheet leaves the navigation stack intact, a customer who
/// signs in here resumes the action they originally tapped — they never
/// have to find their way back and tap it again.
Future<bool> requireRealAuth(
  BuildContext context, {
  required String reason,
}) async {
  if (!AuthService().isRealUser) {
    if (!context.mounted) return false;
    final signedIn = await showAuthGateSheet(context, reason: reason);
    if (!signedIn) return false;
  }

  // Safety net (Aug 11 2026): a real account is not enough — the order
  // also has to be REACHABLE. Google gives us no phone number (this app
  // has no phone-OTP auth, so user.phoneNumber is always empty), and any
  // account created by a path that never collected one would otherwise
  // place orders that no hero or admin can follow up on.
  //
  // This costs nothing in the normal case: resolveCustomerPhone() reads
  // the Hive cache, so a customer who has a number never sees this and
  // the dispatch path stays at zero Firestore reads.
  if (!await _ensureReachablePhone(context)) return false;

  return true;
}

/// Returns true if we have a number to call this customer on — asking
/// for one, once, if we genuinely don't.
Future<bool> _ensureReachablePhone(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return false;

  final existing = await AuthService().resolveCustomerPhone(user);
  if (existing.trim().isNotEmpty) return true;

  if (!context.mounted) return false;
  final captured = await showPhoneCaptureSheet(
    context,
    reason: 'We need a mobile number so your Hero can reach you',
  );
  return captured.trim().isNotEmpty;
}

/// The 30-second deferred prompt shown once on Home to a guest.
class AuthPromptService {
  AuthPromptService._();

  static final AuthPromptService instance = AuthPromptService._();

  static const Duration _delay = Duration(seconds: 30);

  /// SharedPreferences key holding the ms-since-epoch of the last
  /// dismissal. Someone who tapped "Later" must not be asked again on
  /// every single app open — that is how a nudge becomes a nag.
  static const String _dismissedKey = 'auth_prompt_dismissed_at';
  static const Duration _reAskAfter = Duration(hours: 24);

  Timer? _timer;
  bool _shownThisSession = false;

  /// Called from DashboardScreen.initState() via addPostFrameCallback.
  void scheduleDeferredPrompt(BuildContext context) {
    // Already a real account, or already asked once this session.
    if (AuthService().isRealUser) return;
    if (_shownThisSession) return;

    _timer?.cancel();
    _timer = Timer(_delay, () => unawaited(_maybeShow(context)));
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }

  Future<void> _maybeShow(BuildContext context) async {
    // Re-check everything: 30 seconds is long enough for the customer to
    // have signed in through a booking guard in the meantime.
    if (_shownThisSession) return;
    if (AuthService().isRealUser) return;
    if (!context.mounted) return;

    final prefs = await SharedPreferences.getInstance();
    final dismissedAt = prefs.getInt(_dismissedKey);
    if (dismissedAt != null) {
      final since = DateTime.now().millisecondsSinceEpoch - dismissedAt;
      if (since < _reAskAfter.inMilliseconds) return;
    }

    if (!context.mounted) return;

    // Do not ambush someone who has navigated away or already has a
    // modal open — being interrupted mid-booking-flow by a login sheet
    // is worse than not being asked at all. isCurrent is false whenever
    // this route is no longer the top of the stack.
    if (ModalRoute.of(context)?.isCurrent != true) return;

    _shownThisSession = true;

    final signedIn = await showAuthGateSheet(
      context,
      reason: 'Sign in to save your orders and track your bookings',
      showLaterButton: true,
    );

    if (!signedIn) {
      // Covers "Later", a drag-dismiss, and a cancelled Google picker —
      // all of them mean "not now", all of them earn a 24h quiet period.
      await prefs.setInt(
        _dismissedKey,
        DateTime.now().millisecondsSinceEpoch,
      );
    }
  }
}
