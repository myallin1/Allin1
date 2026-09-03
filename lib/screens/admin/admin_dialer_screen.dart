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
// all. Scope was originally just dial/place, see the live call, hang
// up — but Nizam flagged that as incomplete on Sep 2 2026: without
// call history and contacts, this dialer can't do what the stock
// Oppo/Samsung dialer it replaced could, so those are now here too.
//
// Placing the call goes through TelecomManager.placeCall(), the same
// system entry point ChittiDialerActivity already uses for taps on a
// tel: link, so there is exactly one calling path in this app rather
// than a second one that can drift.
import 'dart:async';

import 'package:call_log/call_log.dart' as android_call_log;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/chitti/chitti_accessibility_bridge.dart';
import 'admin_in_call_screen.dart';
import 'chitti_conversations_screen.dart';

// NEW (Sep 2 2026 — Nizam: "athula nama quick greetings and call
// recording ah manage panna option ila"). Same SharedPreferences keys
// admin_ai_settings_screen.dart already reads/writes for these two
// settings — this is a second, quicker place to flip them from, not a
// second source of truth. Kept to exactly these two because they are
// the ones a call is actually about to happen from here.
const String _kCallAnsweringModeKey = 'kChittiCallAnsweringMode';
const String _kCallRecordingEnabledKey = 'kChittiCallRecordingEnabled';
// NEW (Sep 2 2026 — Nizam: "chitti sollavendiya intro change
// panniklam, yevlo second la chitti call aaten pannanumnu set
// panniklam"). Empty custom-greeting means "use Chitti's default
// line" — see ChittiCallScreeningService's _greetingText(). Delay is
// read natively by PhoneCallService.onCallRinging, stored as a string
// for the reason documented at that read site.
const String _kCustomGreetingKey = 'kChittiCustomGreeting';
const String _kAutoAnswerDelayKey = 'kChittiAutoAnswerDelaySeconds';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFE05555);
const Color _green = Color(0xFF4ADE80);
const Color _purple = Color(0xFFB21FFF);

class AdminDialerScreen extends StatefulWidget {
  const AdminDialerScreen({super.key});

  @override
  State<AdminDialerScreen> createState() => _AdminDialerScreenState();
}

class _AdminDialerScreenState extends State<AdminDialerScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  String _number = '';
  Map<String, dynamic>? _activeCall;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 3, vsync: this);
    _refreshActiveCall();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _refreshActiveCall() async {
    final state = await ChittiAccessibilityBridge.instance.getActiveCallInfo();
    if (!mounted) return;
    setState(() => _activeCall = state);
  }

  void _tap(String digit) {
    HapticFeedback.selectionClick();
    setState(() => _number += digit);
    _tabController.animateTo(0);
  }

  void _backspace() {
    if (_number.isEmpty) return;
    HapticFeedback.selectionClick();
    setState(() => _number = _number.substring(0, _number.length - 1));
  }

  void _dialNumber(String number) {
    setState(() => _number = number);
    _tabController.animateTo(0);
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
          // NEW (Sep 2 2026 — Nizam: "call summary pakka ovvoru time
          // admin app pogama dialer laye monitor pandramari varanum").
          // Opens the existing, already-working Call Conversations
          // screen (play recording, note, Chitti next-step plan) —
          // linked from here rather than rebuilt as a second copy
          // inside this screen, so there is exactly one place that
          // logic lives.
          IconButton(
            icon: const Icon(Icons.summarize_outlined, color: _text),
            tooltip: 'Call summaries',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(builder: (_) => const ChittiConversationsScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined, color: _text),
            tooltip: 'Quick greeting & recording',
            onPressed: () => _openCallSettingsSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _text),
            tooltip: 'Refresh call status',
            onPressed: _refreshActiveCall,
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _purple,
          labelColor: _purple,
          unselectedLabelColor: _muted,
          labelStyle: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 12.5),
          tabs: const [
            Tab(text: 'Keypad'),
            Tab(text: 'Recents'),
            Tab(text: 'Contacts'),
          ],
        ),
      ),
      body: SafeArea(
        child: Column(
          children: [
            _buildActiveCallCard(),
            Expanded(
              child: TabBarView(
                controller: _tabController,
                children: [
                  _buildKeypadTab(),
                  _RecentsTab(onCall: _dialNumber),
                  _ContactsTab(onCall: _dialNumber),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildKeypadTab() {
    return Column(
      children: [
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
    );
  }

  // Shows only while a call actually exists, so the tabs below aren't
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

  Future<void> _openCallSettingsSheet(BuildContext context) async {
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const _CallSettingsSheet(),
    );
  }
}

// NEW (Sep 2 2026 — Nizam: "athula nama quick greetings and call
// recording ah manage panna option ila"). A quick toggle right where a
// call is about to be made or answered from, instead of only inside
// the Chitti AI settings screen several taps away. Writes the same
// SharedPreferences keys that screen uses, so nothing here is a second
// source of truth for these two settings.
class _CallSettingsSheet extends StatefulWidget {
  const _CallSettingsSheet();

  @override
  State<_CallSettingsSheet> createState() => _CallSettingsSheetState();
}

class _CallSettingsSheetState extends State<_CallSettingsSheet> {
  bool _loading = true;
  String _mode = 'quick_record';
  bool _recordingEnabled = true;
  final _greetingCtrl = TextEditingController();
  final _delayCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _greetingCtrl.dispose();
    _delayCtrl.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final prefs = await SharedPreferences.getInstance();
    if (!mounted) return;
    setState(() {
      _mode = prefs.getString(_kCallAnsweringModeKey) ?? 'quick_record';
      _recordingEnabled = prefs.getBool(_kCallRecordingEnabledKey) ?? true;
      _greetingCtrl.text = prefs.getString(_kCustomGreetingKey) ?? '';
      _delayCtrl.text = prefs.getString(_kAutoAnswerDelayKey) ?? '20';
      _loading = false;
    });
  }

  Future<void> _setMode(String mode) async {
    setState(() => _mode = mode);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCallAnsweringModeKey, mode);
  }

  Future<void> _setRecording(bool enabled) async {
    setState(() => _recordingEnabled = enabled);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_kCallRecordingEnabledKey, enabled);
  }

  Future<void> _saveGreeting() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kCustomGreetingKey, _greetingCtrl.text.trim());
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Greeting saved.')),
    );
  }

  Future<void> _saveDelay() async {
    final parsed = int.tryParse(_delayCtrl.text.trim());
    final clamped = (parsed ?? 20).clamp(1, 60);
    _delayCtrl.text = '$clamped';
    final prefs = await SharedPreferences.getInstance();
    // Stored as a string on purpose — see PhoneCallService.onCallRinging's
    // header for why a native getInt() on a Flutter-written int throws.
    await prefs.setString(_kAutoAnswerDelayKey, '$clamped');
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Auto-answers after ${clamped}s of ringing.')),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: 40),
        child: Center(child: CircularProgressIndicator(strokeWidth: 2, color: _purple)),
      );
    }
    return SingleChildScrollView(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 14,
        bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36, height: 4,
              decoration: BoxDecoration(color: _border, borderRadius: BorderRadius.circular(2)),
            ),
          ),
          const SizedBox(height: 16),
          Text('Call handling', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 15)),
          const SizedBox(height: 14),
          Text('WHEN CHITTI ANSWERS', style: GoogleFonts.outfit(color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 8),
          _ModeOption(
            title: 'Quick greeting + record',
            subtitle: 'Chitti plays one greeting and a beep, then just records — no live back-and-forth',
            selected: _mode == 'quick_record',
            onTap: () => _setMode('quick_record'),
          ),
          const SizedBox(height: 8),
          _ModeOption(
            title: 'Full conversation',
            subtitle: 'Chitti tries to listen and reply turn by turn',
            selected: _mode == 'full',
            onTap: () => _setMode('full'),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(
                child: Text('Record calls', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13.5)),
              ),
              Switch(
                value: _recordingEnabled,
                activeThumbColor: _green,
                onChanged: _setRecording,
              ),
            ],
          ),
          Text(
            'Off automatically while Chitti is in Full conversation mode and actively listening.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 11, height: 1.3),
          ),
          const SizedBox(height: 20),
          Text('CUSTOM GREETING', style: GoogleFonts.outfit(color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 8),
          TextField(
            controller: _greetingCtrl,
            minLines: 2,
            maxLines: 4,
            style: const TextStyle(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText: "Leave blank to use Chitti's default greeting",
              hintStyle: const TextStyle(color: _muted, fontSize: 12),
              filled: true,
              fillColor: _bg,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton(
              onPressed: _saveGreeting,
              style: OutlinedButton.styleFrom(foregroundColor: _purple, side: const BorderSide(color: _purple)),
              child: const Text('Save greeting'),
            ),
          ),
          const SizedBox(height: 20),
          Text('AUTO-ANSWER AFTER', style: GoogleFonts.outfit(color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1)),
          const SizedBox(height: 8),
          Row(
            children: [
              SizedBox(
                width: 90,
                child: TextField(
                  controller: _delayCtrl,
                  keyboardType: TextInputType.number,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  style: const TextStyle(color: _text, fontSize: 13),
                  decoration: InputDecoration(
                    suffixText: 's',
                    suffixStyle: const TextStyle(color: _muted),
                    filled: true,
                    fillColor: _bg,
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton(
                  onPressed: _saveDelay,
                  style: OutlinedButton.styleFrom(foregroundColor: _purple, side: const BorderSide(color: _purple)),
                  child: const Text('Save'),
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'How many seconds of ringing before Chitti auto-answers (1-60).',
            style: GoogleFonts.outfit(color: _muted, fontSize: 11, height: 1.3),
          ),
        ],
      ),
    );
  }
}

class _ModeOption extends StatelessWidget {
  const _ModeOption({
    required this.title,
    required this.subtitle,
    required this.selected,
    required this.onTap,
  });

  final String title;
  final String subtitle;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _purple.withValues(alpha: 0.1) : _bg,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _purple : _border),
        ),
        child: Row(
          children: [
            Icon(
              selected ? Icons.radio_button_checked_rounded : Icons.radio_button_unchecked_rounded,
              color: selected ? _purple : _muted, size: 18,
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title, style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13)),
                  const SizedBox(height: 2),
                  Text(subtitle, style: GoogleFonts.outfit(color: _muted, fontSize: 11, height: 1.3)),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// NEW (Sep 2 2026 — Nizam: "antha cal history and contacts implement
// panniru athu enaku important"). Read-only mirror of the OS call log,
// same as what the stock dialer showed before this app took over the
// Phone role. Tapping a row fills the keypad rather than calling
// straight away, matching how the stock dialer's recents tab behaves.
class _RecentsTab extends StatefulWidget {
  const _RecentsTab({required this.onCall});
  final void Function(String number) onCall;

  @override
  State<_RecentsTab> createState() => _RecentsTabState();
}

class _RecentsTabState extends State<_RecentsTab> {
  List<android_call_log.CallLogEntry>? _entries;
  bool _denied = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final status = await Permission.phone.request();
    if (!status.isGranted) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    try {
      // FIX (Sep 2 2026 — Nizam: "slow va iruku"). CallLog.get() has
      // no limit — it marshals the phone's ENTIRE call history across
      // the platform channel before .take(100) ever runs in Dart,
      // which is the actual slow part on a phone with years of calls.
      // query()'s dateFrom filter cuts that at the source instead.
      final entries = await android_call_log.CallLog.query(
        dateFrom: DateTime.now().subtract(const Duration(days: 30)).millisecondsSinceEpoch,
      );
      if (!mounted) return;
      setState(() => _entries = entries.take(100).toList());
    } catch (e) {
      if (mounted) setState(() => _entries = []);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return _permissionMessage('Call log permission was denied. Grant "Phone" '
          'permission to see recent calls here.');
    }
    final entries = _entries;
    if (entries == null) {
      return const Center(child: CircularProgressIndicator(color: _purple));
    }
    if (entries.isEmpty) {
      return _permissionMessage('No recent calls found.');
    }
    return RefreshIndicator(
      onRefresh: _load,
      color: _purple,
      backgroundColor: _card,
      child: ListView.builder(
        padding: const EdgeInsets.symmetric(vertical: 6),
        itemCount: entries.length,
        itemBuilder: (context, i) {
          final e = entries[i];
          final number = e.number ?? '';
          final (IconData icon, Color color) = switch (e.callType) {
            android_call_log.CallType.incoming => (Icons.call_received_rounded, _green),
            android_call_log.CallType.outgoing => (Icons.call_made_rounded, _purple),
            android_call_log.CallType.missed => (Icons.call_missed_rounded, _red),
            android_call_log.CallType.rejected => (Icons.call_end_rounded, _red),
            _ => (Icons.call_rounded, _muted),
          };
          final when = e.timestamp != null
              ? DateTime.fromMillisecondsSinceEpoch(e.timestamp!)
              : null;
          final tile = ListTile(
            leading: Icon(icon, color: color, size: 22),
            title: Text(
              (e.name != null && e.name!.isNotEmpty) ? e.name! : (number.isEmpty ? 'Unknown' : number),
              style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600, fontSize: 14),
            ),
            subtitle: when != null
                ? Text(_formatWhen(when), style: GoogleFonts.outfit(color: _muted, fontSize: 11.5))
                : null,
            trailing: IconButton(
              icon: const Icon(Icons.call_rounded, color: _green),
              onPressed: number.isEmpty ? null : () => widget.onCall(number),
            ),
            onTap: number.isEmpty ? null : () => widget.onCall(number),
          );
          if (number.isEmpty) return tile;
          // NEW (Sep 3 2026 — Nizam: "call recent screen la irukka
          // contacts ah right to left swipe pannuna antha number ku
          // messege la chat open aganum, new vendam, ipo iruka messge
          // app ku jump aganum avlo than"). Deliberately hands off to
          // the phone's existing SMS app via an sms: intent rather than
          // building any chat UI here.
          //
          // confirmDismiss always returns false on purpose: the swipe
          // is a shortcut gesture, not a delete — the row springs back
          // and nothing leaves the call log.
          return Dismissible(
            key: ValueKey('recent_${e.timestamp}_$number'),
            direction: DismissDirection.endToStart,
            background: Container(
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(right: 22),
              color: _purple.withValues(alpha: 0.25),
              child: const Icon(Icons.message_rounded, color: _purple),
            ),
            confirmDismiss: (_) async {
              await _openSmsChat(number);
              return false;
            },
            child: tile,
          );
        },
      ),
    );
  }

  /// Opens the device's own messaging app on the thread for [number].
  /// See the Dismissible above for why this is a hand-off and not an
  /// in-app chat screen.
  Future<void> _openSmsChat(String number) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      final ok = await launchUrl(
        Uri.parse('sms:$number'),
        mode: LaunchMode.externalApplication,
      );
      if (!ok && mounted) {
        messenger?.showSnackBar(
          const SnackBar(content: Text('No messaging app found on this phone.')),
        );
      }
    } catch (e) {
      if (mounted) {
        messenger?.showSnackBar(
          SnackBar(content: Text('Could not open messages: $e')),
        );
      }
    }
  }

  static String _formatWhen(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${dt.day}/${dt.month}/${dt.year}';
  }
}

// NEW (Sep 2 2026 — same request as _RecentsTab). Reads the device's
// existing contacts (Google account contacts sync to this the same
// way they do for any other dialer app) — read-only, this screen
// never edits or creates a contact.
class _ContactsTab extends StatefulWidget {
  const _ContactsTab({required this.onCall});
  final void Function(String number) onCall;

  @override
  State<_ContactsTab> createState() => _ContactsTabState();
}

class _ContactsTabState extends State<_ContactsTab> {
  List<Contact>? _contacts;
  bool _denied = false;
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  // FIX (Sep 2 2026 — Nizam: "mobile device dialer mari speed ilama
  // slow va iruku"). getContacts(withProperties: true) was fetching
  // every phone/email/address for every contact before the list could
  // render at all — exactly the flutter_contacts slowness trap; the
  // stock dialer shows names instantly and only reads a number when
  // you actually tap one. Two-phase load: names-only first (fast),
  // then upgrade in the background with full properties so search-by-
  // number and calling keep working once that finishes. If the admin
  // taps a contact before phase 2 lands, _callContact() below fetches
  // that one contact's number on demand instead of waiting on the
  // whole list.
  Future<void> _load() async {
    final granted = await FlutterContacts.requestPermission(readonly: true);
    if (!granted) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    try {
      final names = await FlutterContacts.getContacts(withProperties: false, withPhoto: false);
      names.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      if (!mounted) return;
      setState(() => _contacts = names);
    } catch (e) {
      if (mounted) setState(() => _contacts = []);
      return;
    }
    try {
      final full = await FlutterContacts.getContacts(withProperties: true);
      full.sort((a, b) => a.displayName.toLowerCase().compareTo(b.displayName.toLowerCase()));
      if (mounted) setState(() => _contacts = full);
    } catch (_) {
      // Names-only list from phase 1 is still shown — full properties
      // are a nice-to-have upgrade, not required to use this tab.
    }
  }

  Future<void> _callContact(Contact c) async {
    if (c.phones.isNotEmpty) {
      widget.onCall(c.phones.first.number);
      return;
    }
    final full = await FlutterContacts.getContact(c.id);
    final phone = full?.phones.isNotEmpty == true ? full!.phones.first.number : null;
    if (phone != null) widget.onCall(phone);
  }

  List<Contact> get _filtered {
    final all = _contacts ?? [];
    if (_query.isEmpty) return all;
    final q = _query.toLowerCase();
    return all.where((c) {
      if (c.displayName.toLowerCase().contains(q)) return true;
      return c.phones.any((p) => p.number.replaceAll(RegExp(r'[^0-9]'), '').contains(q));
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    if (_denied) {
      return _permissionMessage('Contacts permission was denied. Grant "Contacts" '
          'permission to search contacts here.');
    }
    if (_contacts == null) {
      return const Center(child: CircularProgressIndicator(color: _purple));
    }
    final filtered = _filtered;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 6),
          child: TextField(
            controller: _searchCtrl,
            onChanged: (v) => setState(() => _query = v),
            style: const TextStyle(color: _text),
            decoration: InputDecoration(
              hintText: 'Search contacts',
              hintStyle: const TextStyle(color: _muted),
              prefixIcon: const Icon(Icons.search_rounded, color: _muted),
              filled: true,
              fillColor: _card,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
            ),
          ),
        ),
        Expanded(
          child: filtered.isEmpty
              ? _permissionMessage('No contacts found.')
              : ListView.builder(
                  itemCount: filtered.length,
                  itemBuilder: (context, i) {
                    final c = filtered[i];
                    final phone = c.phones.isNotEmpty ? c.phones.first.number : null;
                    return ListTile(
                      leading: CircleAvatar(
                        backgroundColor: _purple.withValues(alpha: 0.15),
                        child: Text(
                          c.displayName.isNotEmpty ? c.displayName[0].toUpperCase() : '?',
                          style: const TextStyle(color: _purple, fontWeight: FontWeight.w700),
                        ),
                      ),
                      title: Text(c.displayName,
                          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600, fontSize: 14)),
                      subtitle: phone != null
                          ? Text(phone, style: GoogleFonts.outfit(color: _muted, fontSize: 11.5))
                          : null,
                      // Always tappable, even before phase 2's full
                      // properties land — _callContact() fetches this
                      // one contact's number on demand when needed.
                      trailing: IconButton(
                        icon: const Icon(Icons.call_rounded, color: _green),
                        onPressed: () => _callContact(c),
                      ),
                      onTap: () => _callContact(c),
                    );
                  },
                ),
        ),
      ],
    );
  }
}

Widget _permissionMessage(String message) {
  return Center(
    child: Padding(
      padding: const EdgeInsets.all(24),
      child: Text(
        message,
        textAlign: TextAlign.center,
        style: GoogleFonts.outfit(color: _muted, fontSize: 13),
      ),
    ),
  );
}
