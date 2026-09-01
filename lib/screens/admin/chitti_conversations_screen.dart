// ================================================================
// chitti_conversations_screen.dart — what Chitti and each caller
// actually said, with a one-line summary per call.
// ================================================================
// NEW (Sep 1 2026 — Nizam: "conversation end la customer and chitti
// yenna pandrangalo atha summerize panni admin phone la text ah store
// pannirlam conversation mode la apo namaku conversation data
// kidachurumla admin monitor panna").
//
// Deliberately separate from the Call Debug Logs screen: that one is
// for diagnosing the plumbing (routes, TTS events, errors) and is
// nearly unreadable as business information. This one carries only what
// the business actually needs — who called, what they wanted, and the
// exact words exchanged.
//
// Reads chitti_appointments, which ChittiCallScreeningService.
// _saveAppointment() already writes at the end of every screened call;
// the `summary` field is the AI (or offline-heuristic) one-liner and
// `transcript` the full back-and-forth.
import 'dart:io';

import 'package:audioplayers/audioplayers.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';
import '../../services/firestore_usage_tracking.dart';
import '../../services/guru_admin_api_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);

class ChittiConversationsScreen extends StatelessWidget {
  const ChittiConversationsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Call Conversations',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chitti_appointments')
            .orderBy('timestamp', descending: true)
            .limit(100)
            .trackedSnapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load conversations:\n${snap.error}',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 12),
                ),
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _purple));
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'No screened calls yet.\n\nOnce Chitti answers a call, what was said '
                  'appears here with a short summary.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 13, height: 1.4),
                ),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: docs.length,
            itemBuilder: (context, i) => _ConversationCard(data: docs[i].data(), docRef: docs[i].reference),
          );
        },
      ),
    );
  }
}

class _ConversationCard extends StatefulWidget {
  const _ConversationCard({required this.data, required this.docRef});
  final Map<String, dynamic> data;
  final DocumentReference<Map<String, dynamic>> docRef;

  @override
  State<_ConversationCard> createState() => _ConversationCardState();
}

class _ConversationCardState extends State<_ConversationCard> {
  bool _expanded = false;
  final AudioPlayer _player = AudioPlayer();
  bool _playing = false;
  final TextEditingController _noteCtrl = TextEditingController();
  bool _generatingPlan = false;

  @override
  void dispose() {
    _player.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _togglePlay(String audioPath) async {
    if (_playing) {
      await _player.stop();
      if (mounted) setState(() => _playing = false);
      return;
    }
    if (!File(audioPath).existsSync()) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Recording file not found on this device.')),
        );
      }
      return;
    }
    try {
      setState(() => _playing = true);
      await _player.play(DeviceFileSource(audioPath));
      _player.onPlayerComplete.first.then((_) {
        if (mounted) setState(() => _playing = false);
      });
    } catch (e) {
      if (mounted) {
        setState(() => _playing = false);
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not play recording: $e')));
      }
    }
  }

  // NEW (Sep 2 2026 — Nizam: "chitti admin ku antha audio kekumbothu
  // note pannuna text input ah vachu customer intent and next work
  // plan pannanum"). Admin listens to the recording, types a short
  // note in their own words, and Chitti turns that into a structured
  // "what the customer wants + what to do next" plan — reusing the
  // same Groq-backed admin AI already configured for chat, rather than
  // adding a second AI integration for this one screen.
  Future<void> _generatePlan(String caller, String transcript) async {
    final note = _noteCtrl.text.trim();
    if (note.isEmpty) return;
    setState(() => _generatingPlan = true);
    try {
      final prompt = 'A customer called our business ($caller). Here is what was said on '
          'the call (may be empty if only a recording exists):\n$transcript\n\n'
          'Here is the admin\'s note after listening to the recording:\n$note\n\n'
          'In under 80 words, write: 1) what the customer wants (one line), '
          '2) the concrete next step to do for this customer. Plain text, no '
          'markdown, no preamble.';
      final plan = await GuruAdminApiService().sendMessage(message: prompt);
      await widget.docRef.set({'followupNote': note, 'followupPlan': plan}, SetOptions(merge: true));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Follow-up plan saved.')),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Could not generate plan: $e')));
      }
    } finally {
      if (mounted) setState(() => _generatingPlan = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final d = widget.data;
    final phone = (d['phone'] as String?)?.trim();
    final caller = (phone == null || phone.isEmpty) ? 'Unknown caller' : phone;
    final summary = (d['summary'] as String?)?.trim() ?? '';
    final transcript = (d['transcript'] as String?)?.trim() ?? '';
    final ts = (d['timestamp'] as Timestamp?)?.toDate();
    final isRecorded = d['isRecorded'] == true;
    final audioPath = (d['localAudioPath'] as String?)?.trim();
    final transcriptPath = (d['localTranscriptPath'] as String?)?.trim();

    // Older records (written before the transcript field existed) stored
    // the whole back-and-forth in `summary`. Showing that raw dump as if
    // it were a one-line summary reads badly, so it is detected and
    // rendered as the transcript instead.
    final summaryIsRawTranscript = transcript.isEmpty && summary.contains('\n');
    final headline = summaryIsRawTranscript ? '(older call — full text below)' : summary;
    final body = transcript.isNotEmpty ? transcript : (summaryIsRawTranscript ? summary : '');

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            borderRadius: BorderRadius.circular(14),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.call_received_rounded, color: _purple, size: 16),
                      const SizedBox(width: 7),
                      Expanded(
                        child: Text(
                          caller,
                          style: GoogleFonts.outfit(
                            color: _text,
                            fontWeight: FontWeight.w700,
                            fontSize: 13.5,
                          ),
                        ),
                      ),
                      if (isRecorded)
                        const Padding(
                          padding: EdgeInsets.only(right: 6),
                          child: Icon(Icons.mic_rounded, color: _green, size: 14),
                        ),
                      Icon(
                        _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                        color: _muted,
                        size: 20,
                      ),
                    ],
                  ),
                  if (ts != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 2, left: 23),
                      child: Text(
                        _formatWhen(ts),
                        style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
                      ),
                    ),
                  if (headline.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8, left: 23),
                      child: Text(
                        headline,
                        style: GoogleFonts.outfit(color: _text, fontSize: 12.5, height: 1.35),
                      ),
                    ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(color: _border, height: 1),
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'WHAT WAS SAID',
                    style: GoogleFonts.outfit(
                      color: _muted,
                      fontSize: 10,
                      fontWeight: FontWeight.w800,
                      letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if (body.isEmpty)
                    Text(
                      'Chitti greeted the caller, but nothing the caller said was '
                      'captured on this call.',
                      style: GoogleFonts.outfit(color: _muted, fontSize: 12, height: 1.4),
                    )
                  else
                    ...body.split('\n').where((l) => l.trim().isNotEmpty).map(_speechLine),
                  if (audioPath != null && audioPath.isNotEmpty) ...[
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _togglePlay(audioPath),
                        icon: Icon(_playing ? Icons.stop_rounded : Icons.play_arrow_rounded, size: 18),
                        label: Text(_playing ? 'Stop playback' : 'Play recording'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: _green,
                          side: const BorderSide(color: _green),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                    _pathRow(context, 'Recording file', audioPath),
                  ],
                  if (transcriptPath != null && transcriptPath.isNotEmpty) ...[
                    const SizedBox(height: 6),
                    _pathRow(context, 'Text file', transcriptPath),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    'FOLLOW-UP',
                    style: GoogleFonts.outfit(
                      color: _muted, fontSize: 10, fontWeight: FontWeight.w800, letterSpacing: 1,
                    ),
                  ),
                  const SizedBox(height: 8),
                  if ((d['followupPlan'] as String?)?.trim().isNotEmpty ?? false)
                    Container(
                      width: double.infinity,
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _purple.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: _purple.withValues(alpha: 0.4)),
                      ),
                      child: Text(
                        (d['followupPlan'] as String).trim(),
                        style: GoogleFonts.outfit(color: _text, fontSize: 12, height: 1.4),
                      ),
                    ),
                  TextField(
                    controller: _noteCtrl,
                    minLines: 2,
                    maxLines: 4,
                    style: const TextStyle(color: _text, fontSize: 12.5),
                    decoration: InputDecoration(
                      hintText: 'What did the customer say? (your note after listening)',
                      hintStyle: const TextStyle(color: _muted, fontSize: 12),
                      filled: true,
                      fillColor: _bg,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                    ),
                  ),
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: _generatingPlan ? null : () => _generatePlan(caller, body),
                      icon: _generatingPlan
                          ? const SizedBox(
                              width: 14, height: 14,
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black))
                          : const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text('Ask Chitti for next-step plan'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _purple,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: () => SharePlus.instance.share(
                        ShareParams(
                          text: 'Call with $caller'
                              '${ts != null ? ' · ${_formatWhen(ts)}' : ''}\n\n'
                              '${headline.isNotEmpty ? 'Summary: $headline\n\n' : ''}'
                              '$body',
                          subject: 'Chitti call — $caller',
                        ),
                      ),
                      icon: const Icon(Icons.share_rounded, size: 16),
                      label: const Text('Share this conversation'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _purple,
                        side: const BorderSide(color: _purple),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  // "Assistant: ..." / "Caller: ..." are the exact prefixes
  // ChittiCallScreeningService writes into _conversation, so the two
  // sides can be told apart and coloured without any extra storage.
  Widget _speechLine(String line) {
    final isAssistant = line.startsWith('Assistant:');
    final isCaller = line.startsWith('Caller:');
    final body = isAssistant
        ? line.substring('Assistant:'.length).trim()
        : isCaller
            ? line.substring('Caller:'.length).trim()
            : line.trim();
    final label = isAssistant ? 'Chitti' : (isCaller ? 'Caller' : '');
    final color = isAssistant ? _purple : _green;

    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (label.isNotEmpty)
            Text(
              label,
              style: GoogleFonts.outfit(color: color, fontSize: 10, fontWeight: FontWeight.w700),
            ),
          Text(
            body,
            style: GoogleFonts.outfit(color: _text, fontSize: 12.5, height: 1.4),
          ),
        ],
      ),
    );
  }

  // The file lives on this phone, so the useful action is copying the
  // path to open in a file manager — there is no in-app player here.
  Widget _pathRow(BuildContext context, String label, String path) {
    return InkWell(
      onTap: () async {
        await Clipboard.setData(ClipboardData(text: path));
        if (!context.mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('$label path copied')),
        );
      },
      child: Row(
        children: [
          const Icon(Icons.folder_open_rounded, color: _muted, size: 13),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              '$label: ${path.split('/').last}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
            ),
          ),
          const Icon(Icons.copy_rounded, color: _muted, size: 12),
        ],
      ),
    );
  }

  static String _formatWhen(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    final now = DateTime.now();
    final sameDay = dt.year == now.year && dt.month == now.month && dt.day == now.day;
    final time = '${two(dt.hour)}:${two(dt.minute)}';
    return sameDay ? 'Today $time' : '${two(dt.day)}/${two(dt.month)} $time';
  }
}
