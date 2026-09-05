// ================================================================
// admin_incoming_call_dialog.dart — Real-Time Admin Incoming Call & Takeover
// ================================================================
// Displays full-screen live alert when a customer calls the business
// from the Customer App.
//
// Admin Actions:
// 1. 🟢 Answer (Human Voice): Connects two-way live voice.
// 2. 🤖 Let Chitti Handle: Chitti answers automatically and takes the order
//    while streaming the live dialogue transcript to this screen in real-time.
// 3. ✋ Take Over: Admin can barge-in at any time during Chitti's speech
//    and take over the call directly.
// 4. 🔴 Reject: Closes the call gracefully.
// ================================================================

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/chitti/chitti_live_call_service.dart';

class AdminIncomingCallDialog extends StatefulWidget {
  const AdminIncomingCallDialog({
    super.key,
    required this.callState,
    required this.adminId,
  });

  final ChittiLiveCallState callState;
  final String adminId;

  @override
  State<AdminIncomingCallDialog> createState() => _AdminIncomingCallDialogState();
}

class _AdminIncomingCallDialogState extends State<AdminIncomingCallDialog>
    with SingleTickerProviderStateMixin {
  static const Color _bg = Color(0xFF0D0E15);
  static const Color _card = Color(0xFF181924);
  static const Color _green = Color(0xFF22C55E);
  static const Color _red = Color(0xFFEF4444);
  static const Color _purple = Color(0xFFA855F7);
  static const Color _text = Color(0xFFF1F5F9);
  static const Color _muted = Color(0xFF94A3B8);

  late AnimationController _pulseCtrl;
  StreamSubscription<ChittiLiveCallState?>? _sub;
  late ChittiLiveCallState _state;

  @override
  void initState() {
    super.initState();
    _state = widget.callState;
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);

    _sub = ChittiLiveCallService.instance.watchCall(widget.callState.callId).listen((updated) {
      if (!mounted) return;
      if (updated == null || updated.status == 'ended') {
        Navigator.of(context, rootNavigator: true).pop();
      } else {
        setState(() => _state = updated);
      }
    });
  }

  @override
  void dispose() {
    _sub?.cancel();
    _pulseCtrl.dispose();
    super.dispose();
  }

  Future<void> _answerHuman() async {
    await ChittiLiveCallService.instance.answerCallHuman(_state.callId, adminId: widget.adminId);
  }

  Future<void> _answerChitti() async {
    await ChittiLiveCallService.instance.answerCallChitti(_state.callId, adminId: widget.adminId);
  }

  Future<void> _takeOver() async {
    await ChittiLiveCallService.instance.takeOverCall(_state.callId, adminId: widget.adminId);
  }

  Future<void> _reject() async {
    await ChittiLiveCallService.instance.endCall(_state.callId);
    if (mounted) {
      Navigator.of(context, rootNavigator: true).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isChittiHandling = _state.status == 'chitti_handling';
    final isHumanConnected = _state.status == 'connected' && _state.handlingMode == 'human';

    return Dialog.fullscreen(
      backgroundColor: _bg,
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 20),
          child: Column(
            children: [
              // Top Status Badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                decoration: BoxDecoration(
                  color: isHumanConnected
                      ? _green.withValues(alpha: 0.15)
                      : isChittiHandling
                          ? _purple.withValues(alpha: 0.15)
                          : _green.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: isHumanConnected ? _green : (isChittiHandling ? _purple : _green),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      isHumanConnected
                          ? Icons.phone_in_talk_rounded
                          : isChittiHandling
                              ? Icons.smart_toy_rounded
                              : Icons.ring_volume_rounded,
                      size: 16,
                      color: isHumanConnected ? _green : (isChittiHandling ? _purple : _green),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      isHumanConnected
                          ? 'Live Call Connected (Human)'
                          : isChittiHandling
                              ? 'Chitti AI is Answering'
                              : 'Incoming In-App Customer Call',
                      style: GoogleFonts.outfit(
                        color: isHumanConnected ? _green : (isChittiHandling ? _purple : _green),
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 30),

              // Caller Avatar / Pulse Ring
              AnimatedBuilder(
                animation: _pulseCtrl,
                builder: (context, child) {
                  return Container(
                    width: 110,
                    height: 110,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: _card,
                      boxShadow: [
                        BoxShadow(
                          color: (isChittiHandling ? _purple : _green).withValues(
                            alpha: 0.2 + (_pulseCtrl.value * 0.2),
                          ),
                          blurRadius: 20 + (_pulseCtrl.value * 15),
                          spreadRadius: 2 + (_pulseCtrl.value * 5),
                        ),
                      ],
                    ),
                    child: Center(
                      child: Icon(
                        isChittiHandling ? Icons.smart_toy_rounded : Icons.person_rounded,
                        size: 54,
                        color: isChittiHandling ? _purple : _green,
                      ),
                    ),
                  );
                },
              ),
              const SizedBox(height: 18),

              // Caller Details
              Text(
                _state.callerName,
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 24,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                _state.callerPhone.isNotEmpty ? _state.callerPhone : 'Allin1 Customer',
                style: GoogleFonts.outfit(
                  color: _muted,
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 24),

              // Transcript Card (if Chitti is handling or connected)
              if (isChittiHandling || isHumanConnected)
                Expanded(
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: Colors.white.withValues(alpha: 0.08)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.subtitles_rounded, size: 16, color: _purple),
                            const SizedBox(width: 8),
                            Text(
                              'Live Dialogue Transcript',
                              style: GoogleFonts.outfit(
                                color: _purple,
                                fontSize: 13,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white12, height: 18),
                        Expanded(
                          child: _state.liveTranscript.isEmpty
                            ? Center(
                                child: Text(
                                  'Chitti is listening to the customer...',
                                  style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                                ),
                              )
                            : ListView.builder(
                                itemCount: _state.liveTranscript.length,
                                itemBuilder: (context, i) {
                                  final line = _state.liveTranscript[i];
                                  final isChitti = line.startsWith('Chitti:');
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 4),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isChitti
                                            ? _purple.withValues(alpha: 0.12)
                                            : Colors.white.withValues(alpha: 0.05),
                                        borderRadius: BorderRadius.circular(12),
                                      ),
                                      child: Text(
                                        line,
                                        style: GoogleFonts.notoSansTamil(
                                          color: isChitti ? _purple : _text,
                                          fontSize: 13,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  );
                                },
                              ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                const Spacer(),

              const SizedBox(height: 24),

              // Action Buttons
              if (!isChittiHandling && !isHumanConnected)
                // Initial Ringing Actions: Answer (Human) / Let Chitti Handle / Reject
                Column(
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _answerHuman,
                            icon: const Icon(Icons.call_rounded),
                            label: const Text('Talk Live'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _green,
                              foregroundColor: Colors.black,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 15,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: ElevatedButton.icon(
                            onPressed: _answerChitti,
                            icon: const Icon(Icons.smart_toy_rounded),
                            label: const Text('Let Chitti Handle'),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _purple,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(18),
                              ),
                              textStyle: GoogleFonts.outfit(
                                fontWeight: FontWeight.w800,
                                fontSize: 14,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        onPressed: _reject,
                        icon: const Icon(Icons.call_end_rounded, color: _red),
                        label: const Text('Decline Call'),
                        style: TextButton.styleFrom(
                          foregroundColor: _red,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                        ),
                      ),
                    ),
                  ],
                )
              else if (isChittiHandling)
                // Chitti is Handling: Allow Take Over (Barge-In) or End Call
                Column(
                  children: [
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _takeOver,
                        icon: const Icon(Icons.pan_tool_rounded),
                        label: const Text('✋ Take Over Call (Talk Now)'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _green,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                          textStyle: GoogleFonts.outfit(
                            fontWeight: FontWeight.w900,
                            fontSize: 16,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton.icon(
                        onPressed: _reject,
                        icon: const Icon(Icons.call_end_rounded),
                        label: const Text('End Call'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: _red,
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                          ),
                        ),
                      ),
                    ),
                  ],
                )
              else
                // Human Connected: End Call Button
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                    onPressed: _reject,
                    icon: const Icon(Icons.call_end_rounded),
                    label: const Text('End Live Call'),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _red,
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(18),
                      ),
                      textStyle: GoogleFonts.outfit(
                        fontWeight: FontWeight.w800,
                        fontSize: 16,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
