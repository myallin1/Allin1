// ================================================================
// admin_dialer_screen.dart — the minimal phone dialer the admin app
// needs now that it holds the device's Phone role.
// ================================================================
// NEW (Sep 1 2026 — Nizam: "admin app ah default ah kuduthuttom but
// athula oru dialer ila... namma admin app la calls pannuna and cut
// panna and current calls status pakka oru minimal dialer ready
// paniru").
//
// This is a real gap, not a nicety: taking RoleManager.ROLE_DIALER
// makes Android stop showing the stock phone UI for this device, so
// without this screen the business phone has no way to place a call at
// all. Scope is deliberately the three things that were lost —
// dial/place, see the live call, hang up — and nothing more. Contacts,
// call log, and the full in-call surface stay with the OS's own apps.
//
// Placing the call goes through TelecomManager.placeCall(), the same
// system entry point ChittiDialerActivity already uses for taps on a
// tel: link, so there is exactly one calling path in this app rather
// than a second one that can drift.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/chitti/chitti_accessibility_bridge.dart';
import 'admin_in_call_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFE05555);
const Color _green = Color(0xFF4ADE80);

class AdminDialerScreen extends StatefulWidget {
  const AdminDialerScreen({super.key});

  @override
  State<AdminDialerScreen> createState() => _AdminDialerScreenState();
}

class _AdminDialerScreenState extends State<AdminDialerScreen> {
  String _number = '';
  Map<String, dynamic>? _activeCall;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _refreshActiveCall();
  }

  Future<void> _refreshActiveCall() async {
    final state = await ChittiAccessibilityBridge.instance.getActiveCallInfo();
    if (!mounted) return;
    setState(() => _activeCall = state);
  }

  void _tap(String digit) {
    HapticFeedback.selectionClick();
    setState(() => _number += digit);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  Future<void> _place() async {
    final n = _number.trim();
    if (n.isEmpty || _busy) return;
    setState(() => _busy = true);
    final result = await ChittiAccessibilityBridge.instance.placeCall(n);
    if (!mounted) return;
    setState(() => _busy = false);
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(result), duration: const Duration(seconds: 4)),
    );
    await _refreshActiveCall();
  }

  Future<void> _hangUp() async {
    await ChittiAccessibilityBridge.instance.hangUpCall();
    if (!mounted) return;
    await _refreshActiveCall();
  }

  Future<void> _toggleSpeaker() async {
    await ChittiAccessibilityBridge.instance.toggleSpeaker();
    if (!mounted) return;
    await _refreshActiveCall();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('Dialer',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _text),
            tooltip: 'Refresh call status',
            onPressed: _refreshActiveCall,
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildActiveCallCard(),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      _number.isEmpty ? 'Enter a number' : _number,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        color: _number.isEmpty ? _muted : _text,
                        fontSize: _number.isEmpty ? 16 : 26,
                        fontWeight: FontWeight.w600,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (_number.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.backspace_outlined, color: _muted),
                      onPressed: _backspace,
                    ),
                ],
              ),
            ),
            const Divider(color: _border, height: 1),
            Expanded(child: _buildKeypad()),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 18),
              child: SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton.icon(
                  onPressed: (_number.isEmpty || _busy) ? null : _place,
                  icon: _busy
                      ? const SizedBox(
                          width: 18, height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                      : const Icon(Icons.call_rounded),
                  label: Text(_busy ? 'Calling…' : 'Call',
                      style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _green,
                    foregroundColor: Colors.black,
                    disabledBackgroundColor: _card,
                    disabledForegroundColor: _muted,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Shows only while a call actually exists, so the keypad isn't
  // permanently pushed down by an empty placeholder.
  Widget _buildActiveCallCard() {
    final call = _activeCall;
    if (call == null) return const SizedBox.shrink();
    final number = (call['number'] as String?)?.trim();
    final state = (call['state'] as String?) ?? 'active';
    // NEW (Sep 1 2026): tapping the card opens the full in-call screen
    // (recording toggle, WhatsApp, end call) — the compact controls
    // below stay for the common hang-up/speaker case without leaving
    // the keypad.
    return GestureDetector(
      onTap: () => Navigator.of(context).push(
        MaterialPageRoute<void>(builder: (_) => const AdminInCallScreen()),
      ),
      child: Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _green.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _green.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.phone_in_talk_rounded, color: _green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  (number == null || number.isEmpty) ? 'Call in progress' : number,
                  style: GoogleFonts.outfit(color: _text, fontSize: 15, fontWeight: FontWeight.w700),
                ),
              ),
              Text(state,
                  style: GoogleFonts.outfit(color: _green, fontSize: 11, fontWeight: FontWeight.w700)),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _toggleSpeaker,
                  icon: const Icon(Icons.volume_up_rounded, size: 17),
                  label: const Text('Speaker'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 11),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _hangUp,
                  icon: const Icon(Icons.call_end_rounded, size: 18),
                  label: const Text('Hang Up'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _red,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 11),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
      ),
    );
  }

  Widget _buildKeypad() {
    const rows = [
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      ['*', '0', '#'],
    ];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 26, vertical: 6),
      child: Column(
        children: [
          for (final row in rows)
            Expanded(
              child: Row(
                children: [
                  for (final d in row)
                    Expanded(
                      child: InkWell(
                        borderRadius: BorderRadius.circular(60),
                        onTap: () => _tap(d),
                        child: Center(
                          child: Text(
                            d,
                            style: GoogleFonts.outfit(
                              color: _text,
                              fontSize: 27,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
