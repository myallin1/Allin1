// ================================================================
// chitti_debug_logs_screen.dart — an in-app viewer for
// chitti_screening_debug_logs, so Nizam does not need the Firebase
// Console to see what happened on a screened call.
// ================================================================
// NEW (Aug 31 2026 — Nizam: "இங்க நிறைய இருக்கு, இதை admin app-க்குள்ளயே
// பாக்க ஒரு detail screen ready பண்ணு").
//
// Every diagnosis of the "Chitti doesn't speak on the call" bug this
// session has needed these logs, and getting them meant opening the
// Firebase Console, finding the collection, and clicking into
// alphabetically-sorted random document IDs one at a time — no
// chronological order, no grouping by call, no visual distinction
// between a normal step and an error. This screen is exactly that
// friction removed: newest first, one call's entries visually grouped,
// errors in red.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:share_plus/share_plus.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _red = Color(0xFFE05555);
const Color _green = Color(0xFF4ADE80);

class ChittiDebugLogsScreen extends StatefulWidget {
  const ChittiDebugLogsScreen({super.key});

  @override
  State<ChittiDebugLogsScreen> createState() => _ChittiDebugLogsScreenState();
}

class _ChittiDebugLogsScreenState extends State<ChittiDebugLogsScreen> {
  static const int _pageSize = 200;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          'Chitti Call Debug Logs',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 16),
        ),
        iconTheme: const IconThemeData(color: _text),
        actions: [
          IconButton(
            icon: const Icon(Icons.share_rounded, color: _text),
            tooltip: 'Share as text',
            onPressed: _shareVisibleLogs,
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chitti_screening_debug_logs')
            .orderBy('timestamp', descending: true)
            .limit(_pageSize)
            .snapshots(),
        builder: (context, snap) {
          if (snap.hasError) {
            return Center(
              child: Text(
                'Could not load logs:\n${snap.error}',
                style: const TextStyle(color: _red),
                textAlign: TextAlign.center,
              ),
            );
          }
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator(color: _red));
          }
          final docs = snap.data!.docs;
          if (docs.isEmpty) {
            return Center(
              child: Text(
                'No call debug logs yet — make a test call and they will\n'
                'appear here as soon as Chitti attempts to answer it.',
                style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                textAlign: TextAlign.center,
              ),
            );
          }

          // FIX (Aug 31 2026 — Nizam: "oru time nadakura process oru
          // name la irukanum... full ah ovvoru try um oru list ah
          // theriyakudathu"). This used to group by `caller`, which is
          // 'unknown' on virtually every screened call — so the fallback
          // key ('unknown-<docId>') made every single line its own "1
          // step" card, exactly the unreadable wall of cards reported.
          // Now grouped by the sessionId the screening service stamps on
          // each line (see ChittiCallScreeningService.beginSession), so
          // one call = one collapsible block with a real name.
          final groups = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
          final labels = <String, String>{};
          final order = <String>[];
          for (final d in docs) {
            final data = d.data();
            final sessionId = (data['sessionId'] as String?)?.trim();
            // Logs written before this build have no sessionId at all —
            // keep them readable rather than dropping them, bucketed
            // under one clearly-marked legacy group.
            final key = (sessionId == null || sessionId.isEmpty || sessionId == 'no_session')
                ? 'legacy_ungrouped'
                : sessionId;
            if (!groups.containsKey(key)) {
              groups[key] = [];
              order.add(key);
              labels[key] = key == 'legacy_ungrouped'
                  ? 'Older logs (before session tracking)'
                  : ((data['sessionLabel'] as String?)?.trim().isNotEmpty ?? false
                      ? data['sessionLabel'] as String
                      : 'Call session');
            }
            groups[key]!.add(d);
          }

          return ListView.builder(
            padding: const EdgeInsets.all(14),
            itemCount: order.length,
            itemBuilder: (context, i) {
              final key = order[i];
              return _CallLogGroup(
                caller: labels[key] ?? 'Call session',
                entries: groups[key]!,
                // Newest call open by default; everything older starts
                // collapsed so the screen opens on "what just happened"
                // instead of a scroll wall.
                initiallyExpanded: i == 0,
              );
            },
          );
        },
      ),
    );
  }

  Future<void> _shareVisibleLogs() async {
    final snap = await FirebaseFirestore.instance
        .collection('chitti_screening_debug_logs')
        .orderBy('timestamp', descending: true)
        .limit(_pageSize)
        .get();
    final buffer = StringBuffer();
    for (final d in snap.docs) {
      final data = d.data();
      final ts = (data['timestamp'] as Timestamp?)?.toDate();
      buffer.writeln('${ts ?? ''} | ${data['caller'] ?? ''} | ${data['message'] ?? ''}');
    }
    if (buffer.isEmpty) return;
    await SharePlus.instance.share(
      ShareParams(text: buffer.toString(), subject: 'Chitti call debug logs'),
    );
  }
}

class _CallLogGroup extends StatefulWidget {
  const _CallLogGroup({
    required this.caller,
    required this.entries,
    this.initiallyExpanded = false,
  });

  final String caller;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> entries;
  final bool initiallyExpanded;

  @override
  State<_CallLogGroup> createState() => _CallLogGroupState();
}

class _CallLogGroupState extends State<_CallLogGroup> {
  late bool _expanded = widget.initiallyExpanded;

  // One-line verdict for this call, so the header alone answers "did it
  // work?" without expanding — the thing every debugging round this
  // session actually needed first.
  ({String text, Color color, IconData icon}) get _verdict {
    final messages = widget.entries.map((e) => ((e.data()['message'] as String?) ?? '').toLowerCase()).toList();
    final joined = messages.join(' | ');

    if (joined.contains('setaudioroute(speaker)=true')) {
      return (text: 'Speaker route succeeded', color: _green, icon: Icons.volume_up_rounded);
    }
    if (joined.contains('isdefaultdialer=false')) {
      return (text: 'NOT default Phone app — speaker cannot work', color: _red, icon: Icons.error_outline_rounded);
    }
    if (joined.contains('incallservicebound=false')) {
      return (text: 'InCallService not bound — speaker cannot work', color: _red, icon: Icons.error_outline_rounded);
    }
    if (joined.contains('setaudioroute(speaker)=false')) {
      return (text: 'Speaker route was refused by the OS', color: _red, icon: Icons.error_outline_rounded);
    }
    if (joined.contains('error') || joined.contains('failed') || joined.contains('timeout')) {
      return (text: 'Finished with errors', color: _red, icon: Icons.error_outline_rounded);
    }
    if (joined.contains('reported complete')) {
      return (text: 'Chitti spoke (route unknown)', color: _green, icon: Icons.check_circle_outline_rounded);
    }
    return (text: '${widget.entries.length} steps', color: _muted, icon: Icons.circle_outlined);
  }

  @override
  Widget build(BuildContext context) {
    final verdict = _verdict;
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
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
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Row(
                children: [
                  const Icon(Icons.call_rounded, color: _red, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          widget.caller,
                          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13.5),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          children: [
                            Icon(verdict.icon, color: verdict.color, size: 13),
                            const SizedBox(width: 5),
                            Expanded(
                              child: Text(
                                verdict.text,
                                style: GoogleFonts.outfit(color: verdict.color, fontSize: 11, fontWeight: FontWeight.w600),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${widget.entries.length}',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                  ),
                  Icon(
                    _expanded ? Icons.expand_less_rounded : Icons.expand_more_rounded,
                    color: _muted,
                    size: 20,
                  ),
                ],
              ),
            ),
          ),
          if (_expanded) ...[
            const Divider(color: _border, height: 1),
            // Oldest step of THIS call first, so the sequence reads
            // top-to-bottom the way it actually happened — the opposite
            // of the collection's own newest-first ordering.
            ...widget.entries.reversed.map(_buildEntry),
            const SizedBox(height: 6),
          ],
        ],
      ),
    );
  }

  Widget _buildEntry(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data();
    final message = (data['message'] as String?) ?? '';
    final ts = (data['timestamp'] as Timestamp?)?.toDate();
    final isError = message.toLowerCase().contains('error') ||
        message.toLowerCase().contains('failed') ||
        message.toLowerCase().contains('timeout');
    final isGood = message.toLowerCase().contains('reported start') ||
        message.toLowerCase().contains('reported complete') ||
        message.toLowerCase().contains('returned: 1');

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 6, 14, 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isError ? Icons.error_outline_rounded : (isGood ? Icons.check_circle_outline_rounded : Icons.circle),
            size: isError || isGood ? 14 : 6,
            color: isError ? _red : (isGood ? _green : _muted),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  style: GoogleFonts.outfit(
                    color: isError ? _red : _text,
                    fontSize: 12,
                    height: 1.35,
                    fontWeight: isError || isGood ? FontWeight.w600 : FontWeight.w400,
                  ),
                ),
                if (ts != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      _formatTime(ts),
                      style: GoogleFonts.outfit(color: _muted, fontSize: 10),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime dt) {
    String two(int n) => n.toString().padLeft(2, '0');
    return '${two(dt.hour)}:${two(dt.minute)}:${two(dt.second)}.${dt.millisecond.toString().padLeft(3, '0')}';
  }
}
