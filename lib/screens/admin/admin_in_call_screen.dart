// ================================================================
// admin_in_call_screen.dart — the screen you see while a call is
// actually happening.
// ================================================================
// NEW (Sep 1 2026 — Nizam: "notification la mattum than call atten
// option irukku but atha thottu ulla pona curren calling screene ila...
// anga call recording on,off option, whatsapp button atha thotta nera
// avanga whatsapp chat ku poganum, then end button irukanum").
//
// Once this app took the device's Phone role, Android stopped drawing
// its own in-call UI for these calls — so the only controls were the
// two notification buttons, and tapping the notification led nowhere.
// This is that missing screen.
//
// Deliberately minimize-able rather than modal: an admin mid-call
// frequently needs to look something up in the rest of the app (an
// order, a price), which is exactly what the stock dialer allows. The
// call keeps running because the call lives in Telecom, not in this
// widget — backing out never hangs up.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/chitti/chitti_accessibility_bridge.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF25D366);
const Color _red = Color(0xFFE05555);

class AdminInCallScreen extends StatefulWidget {
  const AdminInCallScreen({super.key});

  @override
  State<AdminInCallScreen> createState() => _AdminInCallScreenState();
}

class _AdminInCallScreenState extends State<AdminInCallScreen> {
  Timer? _poll;
  String _number = '';
  String _state = 'connecting';
  bool _speakerOn = false;
  bool _recording = false;
  int? _connectedAt;
  bool _callGone = false;

  @override
  void initState() {
    super.initState();
    _refresh();
    // Telecom pushes no per-second updates, so the duration and the
    // speaker/recording state are polled. One second is enough for a
    // call timer and cheap enough not to matter.
    _poll = Timer.periodic(const Duration(seconds: 1), (_) => _refresh());
  }

  @override
  void dispose() {
    _poll?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final info = await ChittiAccessibilityBridge.instance.getActiveCallInfo();
    if (!mounted) return;
    if (info == null) {
      // The call ended (by either side). Close the screen rather than
      // leaving a dead in-call UI on top of the app.
      setState(() => _callGone = true);
      _poll?.cancel();
      await Future<void>.delayed(const Duration(milliseconds: 900));
      if (mounted) Navigator.of(context).maybePop();
      return;
    }
    setState(() {
      _number = (info['number'] as String?)?.trim() ?? '';
      _state = (info['state'] as String?) ?? 'active';
      _speakerOn = info['speakerOn'] == true;
      _recording = info['recording'] == true;
      _connectedAt = (info['connectedAt'] as num?)?.toInt();
    });
  }

  String get _durationLabel {
    final startedAt = _connectedAt;
    if (startedAt == null) return _state;
    final secs = (DateTime.now().millisecondsSinceEpoch - startedAt) ~/ 1000;
    if (secs < 0) return _state;
    String two(int n) => n.toString().padLeft(2, '0');
    final m = secs ~/ 60;
    final s = secs % 60;
    return '${two(m)}:${two(s)}';
  }

  Future<void> _openWhatsApp() async {
    // WhatsApp needs a country-coded number with no punctuation. Indian
    // local numbers are the common case here, so a bare 10-digit number
    // gets +91 rather than silently failing to open a chat.
    var digits = _number.replaceAll(RegExp(r'[^0-9]'), '');
    if (digits.length == 10) digits = '91$digits';
    if (digits.isEmpty) {
      _snack('No number available for this call');
      return;
    }
    final uri = Uri.parse('https://wa.me/$digits');
    try {
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok) _snack('Could not open WhatsApp');
    } catch (e) {
      _snack('Could not open WhatsApp: $e');
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: Column(
          children: [
            // Minimize: pops this screen but leaves the call running,
            // matching what every stock dialer does.
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton(
                icon: const Icon(Icons.keyboard_arrow_down_rounded, color: _text, size: 30),
                tooltip: 'Minimize (call keeps running)',
                onPressed: () => Navigator.of(context).maybePop(),
              ),
            ),
            const Spacer(),
            Container(
              width: 96,
              height: 96,
              decoration: BoxDecoration(
                color: _purple.withValues(alpha: 0.15),
                shape: BoxShape.circle,
                border: Border.all(color: _purple.withValues(alpha: 0.4), width: 2),
              ),
              child: const Icon(Icons.person_rounded, color: _purple, size: 48),
            ),
            const SizedBox(height: 20),
            Text(
              _number.isEmpty ? 'Unknown caller' : _number,
              style: GoogleFonts.outfit(color: _text, fontSize: 24, fontWeight: FontWeight.w700),
            ),
            const SizedBox(height: 6),
            Text(
              _callGone ? 'Call ended' : _durationLabel,
              style: GoogleFonts.outfit(
                color: _callGone ? _red : _muted,
                fontSize: 14,
                fontWeight: FontWeight.w600,
              ),
            ),
            if (_recording && !_callGone)
              Padding(
                padding: const EdgeInsets.only(top: 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: const BoxDecoration(color: _red, shape: BoxShape.circle),
                    ),
                    const SizedBox(width: 7),
                    Text(
                      'Recording',
                      style: GoogleFonts.outfit(color: _red, fontSize: 12, fontWeight: FontWeight.w700),
                    ),
                  ],
                ),
              ),
            const Spacer(),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 30),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _RoundAction(
                    icon: _recording ? Icons.fiber_manual_record_rounded : Icons.radio_button_unchecked_rounded,
                    label: _recording ? 'Recording' : 'Record',
                    active: _recording,
                    activeColor: _red,
                    onTap: _callGone
                        ? null
                        : () async {
                            final now = await ChittiAccessibilityBridge.instance
                                .setCallRecording(!_recording);
                            if (!mounted) return;
                            setState(() => _recording = now);
                            if (!now && !_recording) {
                              _snack('Recording could not start — the mic may be '
                                  'in use by Chitti conversation mode');
                            }
                          },
                  ),
                  _RoundAction(
                    icon: _speakerOn ? Icons.volume_up_rounded : Icons.volume_down_rounded,
                    label: 'Speaker',
                    active: _speakerOn,
                    activeColor: _purple,
                    onTap: _callGone
                        ? null
                        : () async {
                            await ChittiAccessibilityBridge.instance.toggleSpeaker();
                            await _refresh();
                          },
                  ),
                  _RoundAction(
                    icon: Icons.chat_rounded,
                    label: 'WhatsApp',
                    active: false,
                    activeColor: _green,
                    iconColor: _green,
                    onTap: _openWhatsApp,
                  ),
                ],
              ),
            ),
            const SizedBox(height: 34),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 40),
              child: SizedBox(
                width: double.infinity,
                height: 60,
                child: ElevatedButton.icon(
                  onPressed: _callGone
                      ? null
                      : () async {
                          await ChittiAccessibilityBridge.instance.hangUpCall();
                          if (!mounted) return;
                          Navigator.of(context).maybePop();
                        },
                  icon: const Icon(Icons.call_end_rounded, size: 26),
                  label: Text(
                    'End Call',
                    style: GoogleFonts.outfit(fontSize: 16, fontWeight: FontWeight.w700),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: _red.withValues(alpha: 0.3),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({
    required this.icon,
    required this.label,
    required this.active,
    required this.activeColor,
    required this.onTap,
    this.iconColor,
  });

  final IconData icon;
  final String label;
  final bool active;
  final Color activeColor;
  final Color? iconColor;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    final fg = !enabled
        ? _muted.withValues(alpha: 0.4)
        : active
            ? Colors.white
            : (iconColor ?? _text);
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(36),
          child: Container(
            width: 66,
            height: 66,
            decoration: BoxDecoration(
              color: active ? activeColor : Colors.white.withValues(alpha: 0.07),
              shape: BoxShape.circle,
              border: Border.all(
                color: active ? activeColor : Colors.white.withValues(alpha: 0.15),
              ),
            ),
            child: Icon(icon, color: fg, size: 26),
          ),
        ),
        const SizedBox(height: 8),
        Text(
          label,
          style: GoogleFonts.outfit(
            color: enabled ? _muted : _muted.withValues(alpha: 0.4),
            fontSize: 11,
            fontWeight: FontWeight.w600,
          ),
        ),
      ],
    );
  }
}
