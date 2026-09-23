// admin_laptop_control_screen.dart — Allin1 Laptop Presence + Sleep Control
//
// Shows Nizam's laptop's online/asleep status (inferred from how stale
// `lastSeen` is — the laptop-side agent can never write "going offline"
// itself, since the OS suspends the whole process the instant it sleeps)
// and lets the admin request it go to sleep. There is deliberately NO
// remote wake here — see backend-admin/laptop_agent/presence_agent.js's
// header for why (WiFi Wake-on-LAN is unsupported on this laptop's NIC).
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_laptop_screen_view_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFFB020);
const Color _purple = Color(0xFFB21FFF);

const String _deviceId = 'nizam_laptop';
const Duration _staleAfter = Duration(seconds: 90);

class AdminLaptopControlScreen extends StatelessWidget {
  const AdminLaptopControlScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Laptop Control',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('laptop_control')
            .doc(_deviceId)
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data();
          final lastSeen = (data?['lastSeen'] as Timestamp?)?.toDate();
          final isOnline = lastSeen != null &&
              DateTime.now().difference(lastSeen) < _staleAfter;
          final sleepRequested = data?['sleepRequested'] == true;
          final hostname = data?['hostname'] as String? ?? '—';
          final sleepRequestedBy = data?['sleepRequestedBy'] as String?;

          return Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: _border),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Container(
                            width: 10,
                            height: 10,
                            decoration: BoxDecoration(
                              color: isOnline ? _green : _muted,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            isOnline ? 'Online' : 'Asleep / Offline',
                            style: GoogleFonts.outfit(
                              color: isOnline ? _green : _muted,
                              fontWeight: FontWeight.w700,
                              fontSize: 15,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'Host: $hostname',
                        style: GoogleFonts.outfit(color: _text, fontSize: 13),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        lastSeen == null
                            ? 'No heartbeat received yet'
                            : 'Last seen: ${_relativeTime(lastSeen)}',
                        style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                      ),
                      if (sleepRequested) ...[
                        const SizedBox(height: 8),
                        Text(
                          sleepRequestedBy == null
                              ? 'Sleep requested — waiting for the laptop to act on it...'
                              : 'Sleep requested by $sleepRequestedBy — waiting...',
                          style: GoogleFonts.outfit(
                            color: _amber,
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                ElevatedButton.icon(
                  onPressed: !isOnline || sleepRequested
                      ? null
                      : () => _confirmSleep(context),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12,),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.bedtime_outlined),
                  label: const Text('Put laptop to sleep'),
                ),
                const SizedBox(height: 10),
                OutlinedButton.icon(
                  onPressed: () => Navigator.of(context).push(
                    MaterialPageRoute<void>(
                      builder: (_) => const AdminLaptopScreenViewScreen(),
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _text,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 12,),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  icon: const Icon(Icons.screen_share_outlined),
                  label: const Text('View laptop screen (live)'),
                ),
                const SizedBox(height: 12),
                Text(
                  'Remote WAKE is not available on this laptop - its WiFi '
                  "adapter doesn't reliably support Wake-on-LAN. Waking it "
                  'back up needs a physical touch (power button/keyboard).',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _confirmSleep(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        title: Text(
          'Put laptop to sleep?',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          'It will sleep within a few seconds. You cannot wake it '
          'remotely - only a physical touch (power button/keyboard) wakes '
          'it back up.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _amber,
              foregroundColor: Colors.black,
            ),
            child: const Text('Sleep now'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await FirebaseFirestore.instance
          .collection('laptop_control')
          .doc(_deviceId)
          .set(
        {
          'sleepRequested': true,
          'sleepRequestedAt': FieldValue.serverTimestamp(),
          'sleepRequestedBy':
              FirebaseAuth.instance.currentUser?.email ?? 'unknown',
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          backgroundColor: _card,
          content: Text(
            'Could not send the sleep request: $e',
            style: GoogleFonts.outfit(color: _amber),
          ),
        ),
      );
    }
  }

  static String _relativeTime(DateTime t) {
    final diff = DateTime.now().difference(t);
    if (diff.inSeconds < 60) return '${diff.inSeconds}s ago';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}
