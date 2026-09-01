// ================================================================
// auth_gate_sheet.dart
// ================================================================
// NEW (Aug 11 2026 — Guest Mode / Deferred Login).
//
// ONE modal bottom sheet with TWO entry points:
//   1. The 30s deferred prompt on Home  -> showLaterButton: true
//   2. Any gated action (book / order)  -> showLaterButton: false
//      via requireRealAuth() in ../../services/auth_prompt_service.dart
//
// WHY A SHEET AND NOT A PUSHED SCREEN (this is the load-bearing
// decision — do not "simplify" it back):
// customer_login_screen.dart and customer_welcome_login_screen.dart
// both finish with Navigator.pushNamedAndRemoveUntil('/dashboard',
// (route) => false). Pushing either of them from a booking screen would
// destroy the navigation stack, so after signing in the customer would
// land on Home having lost the cart/booking they were three taps into.
// A sheet leaves the stack completely intact: it pops with `true` and
// the original onPressed handler simply continues on the next line.
//
// The auth logic itself is NOT re-implemented here — it is
// AuthService.upgradeGuestWithGoogle(), which reuses the exact field
// shape customer_welcome_login_screen.dart's _signInWithGoogle()
// writes (phoneNumber + phone + isSetupComplete + campaign source).
//
// NOTE ON "Continue with Mobile Number": the customer app has no
// phone-OTP auth at all — there is no verifyPhoneNumber /
// signInWithPhoneNumber / PhoneAuthProvider call anywhere in lib/.
// The mobile number has always been a plain field collected ALONGSIDE
// Google sign-in and written into the new users/{uid} doc. This sheet
// reproduces that same wiring rather than inventing a second auth
// mechanism four days before launch.
// ================================================================
import 'dart:async';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/auth_service.dart';
import '../../services/theme_service.dart';

/// Shows the sign-in sheet.
///
/// Returns true ONLY if the customer genuinely completed sign-in.
/// Returns false if they dismissed it, tapped "Later", or cancelled the
/// Google picker — callers treat false as "do not proceed".
Future<bool> showAuthGateSheet(
  BuildContext context, {
  /// Why we're asking, shown as the subtitle. Always pass an
  /// action-specific reason ("Sign in to book a Hero"), never a generic
  /// "Please log in" — the specific version converts far better because
  /// it tells the customer what they get for signing in.
  required String reason,

  /// True for the 30s timer prompt (adds an explicit "Later" button).
  /// False for action-triggered auth — still dismissible by drag or
  /// back, but no "Later", since skipping cannot complete the action
  /// they just tapped.
  bool showLaterButton = false,
}) async {
  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _AuthGateSheet(
      reason: reason,
      showLaterButton: showLaterButton,
    ),
  );
  return result ?? false;
}

/// Collects a missing mobile number from an ALREADY signed-in customer.
///
/// Reuses the same sheet, in a mode where sign-in is not the point: the
/// account is fine, we simply have no number to reach them on. This is
/// the safety net for accounts created by a path that never collected
/// one — without it those customers place orders that no hero or admin
/// can follow up, which is worse than one extra tap.
///
/// Returns the saved number, or '' if they dismissed it.
Future<String> showPhoneCaptureSheet(
  BuildContext context, {
  required String reason,
}) async {
  final result = await showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (sheetContext) => _AuthGateSheet(
      reason: reason,
      showLaterButton: false,
      phoneOnly: true,
    ),
  );
  return result ?? '';
}

class _AuthGateSheet extends StatefulWidget {
  final String reason;
  final bool showLaterButton;

  /// Phone-capture mode: the customer is already signed in and we only
  /// need a number. Hides the Google button and the theme picker, and
  /// pops the saved number instead of a bool.
  final bool phoneOnly;

  const _AuthGateSheet({
    required this.reason,
    required this.showLaterButton,
    this.phoneOnly = false,
  });

  @override
  State<_AuthGateSheet> createState() => _AuthGateSheetState();
}

class _AuthGateSheetState extends State<_AuthGateSheet> {
  static const Color _kPink = Color(0xFFFF4FA3);
  static const Color _kPinkLight = Color(0xFFFF92C8);

  final TextEditingController _mobileController = TextEditingController();
  bool _busy = false;
  String? _mobileError;
  String? _authError;

  @override
  void dispose() {
    _mobileController.dispose();
    super.dispose();
  }

  /// Same 10-digit India-focused check the two login screens already use.
  /// Kept identical on purpose — a customer must not pass validation in
  /// one place and fail it in another.
  bool _isValidMobile(String value) {
    return value.replaceAll(RegExp(r'\D'), '').length >= 10;
  }

  Future<void> _signIn() async {
    if (_busy) return;

    final mobile = _mobileController.text.trim();
    if (!_isValidMobile(mobile)) {
      setState(() => _mobileError = 'Please enter a valid mobile number.');
      return;
    }

    setState(() {
      _mobileError = null;
      _authError = null;
      _busy = true;
    });

    // Phone-capture mode: no sign-in to do — persist the number against
    // the existing account and hand it straight back to the caller, so
    // the booking it was blocking can proceed in the same tap.
    if (widget.phoneOnly) {
      final uid = FirebaseAuth.instance.currentUser?.uid ?? '';
      try {
        await AuthService().updateUserPhone(uid, mobile);
        if (!mounted) return;
        Navigator.of(context).pop(mobile);
      } catch (e) {
        if (!mounted) return;
        setState(() {
          _busy = false;
          _authError = 'Could not save your number: $e';
        });
      }
      return;
    }

    final result = await AuthService().upgradeGuestWithGoogle(mobile: mobile);

    if (!mounted) return;

    if (result.success) {
      // Pop true ONLY on genuine success — the caller uses this to decide
      // whether to run the booking/order it was gating.
      Navigator.of(context).pop(true);
      return;
    }

    // A dismissed Google account picker is a CANCELLATION, not a
    // failure — showing a red error box for "I changed my mind" is
    // exactly the harsh, off-brand treatment we're removing elsewhere.
    // Just release the button and let them try again or drag the sheet
    // away.
    final cancelled = (result.error ?? '').toLowerCase().contains('cancel');

    // Any genuine failure stays INSIDE the sheet — never close on error.
    // The customer keeps their typed number and retries without redoing
    // the flow.
    setState(() {
      _busy = false;
      _authError = cancelled
          ? null
          : (result.error ?? 'Sign-in failed. Please try again.');
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return PopScope(
      // Never trap the customer in a login sheet. Dismissing simply means
      // "not now" — Guest Mode's whole promise is that browsing is free.
      canPop: true,
      child: Padding(
        // Lifts the sheet above the keyboard while the number is typed.
        padding: EdgeInsets.only(bottom: bottomInset),
        child: Container(
          decoration: BoxDecoration(
            color: theme.colorScheme.surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: SafeArea(
            top: false,
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(22, 10, 22, 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // ── Drag handle ──────────────────────────────────
                  Center(
                    child: Container(
                      width: 42,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.dividerColor,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),

                  // ── Brand mark (same pink gradient tile the welcome
                  //    screen and BrandedLoadingScreen use) ─────────
                  Center(
                    child: Container(
                      width: 62,
                      height: 62,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kPink, _kPinkLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24FF4FA3),
                            blurRadius: 18,
                            offset: Offset(0, 10),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'NJ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 22,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 0.5,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  Text(
                    'Welcome to MyAllin1',
                    textAlign: TextAlign.center,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    widget.reason,
                    textAlign: TextAlign.center,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.textTheme.bodySmall?.color,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 20),

                  // ── Theme picker ─────────────────────────────────
                  // Hidden in phone-capture mode: the customer is mid-
                  // booking and only owes us a number — offering a theme
                  // switcher there would be noise at the worst moment.
                  if (!widget.phoneOnly) ...[
                    const _ThemeSwatchRow(),
                    const SizedBox(height: 20),
                  ],

                  // ── Mobile number (mandatory for NEW accounts —
                  //    discarded for returning ones, see
                  //    upgradeGuestWithGoogle) ─────────────────────
                  TextField(
                    controller: _mobileController,
                    keyboardType: TextInputType.phone,
                    enabled: !_busy,
                    onChanged: (_) {
                      if (_mobileError != null) {
                        setState(() => _mobileError = null);
                      }
                    },
                    decoration: InputDecoration(
                      labelText: 'Mobile Number',
                      hintText: 'Enter your mobile number',
                      prefixIcon: const Icon(Icons.phone_iphone_rounded),
                      errorText: _mobileError,
                      filled: true,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(14),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    "We'll only use this to reach you about your order.",
                    style: theme.textTheme.bodySmall?.copyWith(fontSize: 11.5),
                  ),
                  const SizedBox(height: 16),

                  // ── Inline error (sheet stays open on failure) ───
                  if (_authError != null) ...[
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.error_outline_rounded,
                            size: 18,
                            color: theme.colorScheme.onErrorContainer,
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              _authError!,
                              style: TextStyle(
                                fontSize: 12.5,
                                color: theme.colorScheme.onErrorContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 14),
                  ],

                  // ── Continue with Google ─────────────────────────
                  SizedBox(
                    height: 52,
                    child: ElevatedButton(
                      onPressed: _busy ? null : () => unawaited(_signIn()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPink,
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      child: _busy
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.4,
                                color: Colors.white,
                              ),
                            )
                          : Text(
                              widget.phoneOnly
                                  ? 'Save & Continue'
                                  : 'Continue with Google',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                    ),
                  ),

                  if (widget.showLaterButton) ...[
                    const SizedBox(height: 6),
                    TextButton(
                      onPressed:
                          _busy ? null : () => Navigator.of(context).pop(false),
                      child: const Text(
                        'Later',
                        style: TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

// ================================================================
// Theme swatch row
// ================================================================
// Applies the chosen theme IMMEDIATELY through the existing
// ThemeService.setTheme() — the sheet itself restyles live while the
// customer watches, which is the entire reason the picker sits here
// rather than buried in Settings.
//
// ThemeService already persists to SharedPreferences ('customer_theme_key')
// inside setTheme(). Do NOT add a second persistence path here.
// ================================================================
class _ThemeSwatchRow extends StatelessWidget {
  const _ThemeSwatchRow();

  /// One representative colour per key in ThemeService.themeKeys.
  /// Kept as a lookup rather than building all 5 ThemeData objects just
  /// to read a seed colour off them — that would be 5 full
  /// ColorScheme.fromSeed() builds on every rebuild of this sheet.
  static const Map<String, Color> _swatch = {
    'pink_white': Color(0xFFFF4FA3),
    'dark_purple': Color(0xFF6A1B9A),
    'system_dark': Color(0xFF2B2B2B),
    'system_light': Color(0xFFECECEC),
    'multicolor': Color(0xFF00B8A9),
  };

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final selected = themeService.themeKey;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Pick your look',
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(fontWeight: FontWeight.w800),
        ),
        const SizedBox(height: 10),
        Row(
          children: [
            for (final key in ThemeService.themeKeys)
              Padding(
                padding: const EdgeInsets.only(right: 12),
                child: InkWell(
                  borderRadius: BorderRadius.circular(30),
                  onTap: () => unawaited(themeService.setTheme(key)),
                  child: Container(
                    width: 38,
                    height: 38,
                    decoration: BoxDecoration(
                      color: _swatch[key] ?? Colors.grey,
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: key == selected
                            ? Theme.of(context).colorScheme.primary
                            : Theme.of(context).dividerColor,
                        width: key == selected ? 2.6 : 1,
                      ),
                    ),
                    child: key == selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 18,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ),
          ],
        ),
      ],
    );
  }
}
