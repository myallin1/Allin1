// ================================================================
// admin_incoming_call_screen.dart — the screen for a call that is
// still ringing, not yet answered.
// ================================================================
// NEW (Sep 2 2026 — Nizam: "namma dialer la incoming call vantha
// attend panna screen ila athayum solve pannanum").
//
// Real gap, same reason the Dialer and the in-call screen exist at
// all: once this app holds the device's Phone role, Android draws no
// UI of its own for a ringing call — before this screen, the phone
// just rang with nothing to tap. Chitti's auto-answer timer (see
// PhoneCallService.onCallRinging) still fires if the admin does
// nothing, so this is purely additive: answer sooner, or decline,
// without waiting the configured delay out.
//
// Deliberately polls getActiveCallInfo() (state: "ringing" ->
// "active" -> gone) the same way AdminInCallScreen already does,
// rather than inventing a second live-update channel for one screen.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/chitti/chitti_accessibility_bridge.dart';
import 'admin_in_call_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);
const Color _red = Color(0xFFE05555);

class AdminIncomingCallScreen extends StatefulWidget {
  const AdminIncomingCallScreen({required this.number, super.key});

  final String number;

  @override
  State<AdminIncomingCallScreen> createState() => _AdminIncomingCallScreenState();
}

class _AdminIncomingCallScreenState extends State<AdminIncomingCallScreen> {
  Timer? _poll;
  bool _busy = false;
  bool _resolved = false;

  @override
  void initState() {
    super.initState();
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _checkState());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _checkState() async {
    if (_resolved) return;
    final info = await ChittiAccessibilityBridge.instance.getActiveCallInfo();
    if (!mounted) return;
    if (info == null) {
      // Caller hung up, or the call otherwise vanished before anyone
      // here answered it — nothing left to show.
      _resolved = true;
      Navigator.of(context).maybePop();
      return;
    }
    final state = info['state'] as String?;
    if (state == 'active') {
      _resolved = true;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute<void>(builder: (_) => const AdminInCallScreen()),
      );
    }
  }

  Future<void> _answer() async {
    if (_busy) return;
    setState(() => _busy = true);
    await ChittiAccessibilityBridge.instance.answerIncomingCall();
    // _checkState's next tick moves on to AdminInCallScreen once the
    // call actually reports "active" — no need to navigate here too.
  }

  Future<void> _decline() async {
    if (_busy) return;
    setState(() => _busy = true);
    _resolved = true;
    await ChittiAccessibilityBridge.instance.declineIncomingCall();
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final number = widget.number.trim();
    return PopScope(
      // A ringing call shouldn't be dismissible by accident — the
      // admin has to make an actual Answer/Decline choice (or the
      // auto-answer timer will make it for them).
      canPop: false,
      child: Scaffold(
        backgroundColor: _bg,
        body: SafeArea(
          child: Column(
            children: [
              const Spacer(flex: 2),
              Container(
                width: 100, height: 100,
                decoration: BoxDecoration(
                  color: _purple.withValues(alpha: 0.15),
                  shape: BoxShape.circle,
                  border: Border.all(color: _purple.withValues(alpha: 0.4), width: 2),
                ),
                child: const Icon(Icons.call_rounded, color: _purple, size: 50),
              ),
              const SizedBox(height: 22),
              Text(
                number.isEmpty ? 'Unknown caller' : number,
                style: GoogleFonts.outfit(color: _text, fontSize: 24, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              Text(
                'Incoming call — Chitti will answer automatically if you don\'t',
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: _muted, fontSize: 13),
              ),
              const Spacer(flex: 3),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 30),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _CallActionButton(
                      icon: Icons.call_end_rounded,
                      color: _red,
                      label: 'Decline',
                      onTap: _busy ? null : _decline,
                    ),
                    _CallActionButton(
                      icon: Icons.call_rounded,
                      color: _green,
                      label: 'Answer',
                      onTap: _busy ? null : _answer,
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _CallActionButton extends StatelessWidget {
  const _CallActionButton({
    required this.icon,
    required this.color,
    required this.label,
    required this.onTap,
  });

  final IconData icon;
  final Color color;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            onTap: onTap,
            customBorder: const CircleBorder(),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: GoogleFonts.outfit(color: _text, fontSize: 12.5, fontWeight: FontWeight.w600)),
      ],
    );
  }
}
