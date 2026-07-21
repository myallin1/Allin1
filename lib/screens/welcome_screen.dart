// ================================================================
// welcome_screen.dart
//
// Shown once, on first launch, after the intro video and before the
// app itself. Two jobs:
//
//   1. Let the customer pick their language up front, instead of
//      discovering the setting buried in a menu later.
//   2. Offer sign-in — but never demand it.
//
// "Sign in later" matters. The app deliberately lets people browse
// everything without an account and only asks them to sign in at the
// moment they actually book something. A hard login wall here would
// throw that away and lose the customers who just want to look first.
//
// Design matches BrandedLoadingScreen so the intro video -> welcome ->
// loading -> home sequence reads as one continuous screen rather than
// three unrelated ones.
// ================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';
import 'customer_login_screen.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kPinkLight = Color(0xFFFF92C8);
const Color _kInk = Color(0xFF4A1236);
const Color _kMuted = Color(0xFF8A4E72);
const Color _kBorder = Color(0xFFF0DCE8);

class WelcomeScreen extends StatefulWidget {
  /// Where to go once the customer is done here.
  final Widget next;

  const WelcomeScreen({required this.next, super.key});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  // Language options. Codes match LocalizationService exactly — 'en',
  // 'ta', 'tg' — so a selection here is the same value the rest of the
  // app reads. Labels are written in their own language, because
  // someone who only reads Tamil shouldn't have to parse the English
  // word "Tamil" to find their language.
  static const List<({String code, String label, String hint})> _languages = [
    (code: 'ta', label: 'தமிழ்', hint: 'Tamil'),
    (code: 'en', label: 'English', hint: 'English'),
    (code: 'tg', label: 'Tanglish', hint: 'Tamil + English'),
  ];

  bool _busy = false;

  String get _selected => context.watch<LocalizationService>().languageCode;

  Future<void> _choose(String code) async {
    if (_busy) return;
    // Applied immediately rather than on Continue, so the customer sees
    // the choice take effect and can tell it registered.
    await context.read<LocalizationService>().setLanguage(code);
  }

  Future<void> _continueToApp() async {
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute<void>(builder: (_) => widget.next),
    );
  }

  Future<void> _signIn() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      // Reuses the existing customer login screen rather than
      // reimplementing Google sign-in here. That screen already handles
      // the profile-setup and phone-collection follow-ups, and on
      // success it routes to /dashboard itself — so if sign-in works we
      // never come back to this screen at all.
      await Navigator.of(context).push<void>(
        MaterialPageRoute<void>(builder: (_) => const CustomerLoginScreen()),
      );
      // Reached only if the customer backed out of the login screen.
      // Let them into the app anyway; they can sign in when they book.
      if (mounted) await _continueToApp();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 32),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      width: 78,
                      height: 78,
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [_kPink, _kPinkLight],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(24),
                        boxShadow: const [
                          BoxShadow(
                            color: Color(0x24FF4FA3),
                            blurRadius: 22,
                            offset: Offset(0, 12),
                          ),
                        ],
                      ),
                      child: const Center(
                        child: Text(
                          'NJ',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.w900,
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  const Text(
                    "That'll Bapx NJ Tech",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    'made love ❤ with erode',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),

                  const SizedBox(height: 34),

                  const Text(
                    'மொழி / Language',
                    style: TextStyle(
                      color: _kInk,
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._languages.map(_buildLanguageTile),

                  const SizedBox(height: 28),

                  SizedBox(
                    height: 52,
                    child: ElevatedButton.icon(
                      onPressed: _busy ? null : () => unawaited(_signIn()),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPink,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: _kPink.withValues(alpha: 0.5),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(15),
                        ),
                      ),
                      icon: _busy
                          ? const SizedBox(
                              width: 17,
                              height: 17,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Icon(Icons.login_rounded, size: 19),
                      label: const Text(
                        'Continue with Google',
                        style: TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 6),
                  TextButton(
                    onPressed: _busy ? null : () => unawaited(_continueToApp()),
                    style: TextButton.styleFrom(foregroundColor: _kMuted),
                    child: const Text(
                      'Sign in later  →',
                      style: TextStyle(
                        fontSize: 13.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 4),
                  const Text(
                    'You can look around freely.\n'
                    "We'll only ask you to sign in when you book.",
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: _kMuted,
                      fontSize: 11.5,
                      height: 1.5,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildLanguageTile(({String code, String label, String hint}) lang) {
    final isSelected = _selected == lang.code;
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: InkWell(
        borderRadius: BorderRadius.circular(14),
        onTap: _busy ? null : () => unawaited(_choose(lang.code)),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
          decoration: BoxDecoration(
            color: isSelected ? const Color(0xFFFFF3F9) : Colors.white,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? _kPink : _kBorder,
              width: isSelected ? 1.8 : 1.2,
            ),
          ),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      lang.label,
                      style: TextStyle(
                        color: _kInk,
                        fontSize: 15,
                        fontWeight: isSelected
                            ? FontWeight.w800
                            : FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 1),
                    Text(
                      lang.hint,
                      style: const TextStyle(color: _kMuted, fontSize: 11),
                    ),
                  ],
                ),
              ),
              Icon(
                isSelected
                    ? Icons.check_circle_rounded
                    : Icons.circle_outlined,
                color: isSelected ? _kPink : _kBorder,
                size: 21,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
