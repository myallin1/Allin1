// ================================================================
// chitti_error_log_sheet.dart — "what Chitti got wrong" viewer
// ================================================================
// NEW (Sep 22 2026 — Nizam: "chitti chat box la oru error log vaikalm
// ithu chitti namma soldratha purinjukavum and chitti soldrathula
// iruka namma pesuratha purinjukavum besta irukum" — wants BOTH
// directions visible: moments Chitti misheard what the customer said,
// and moments Chitti's own reply/tool-call logic broke).
//
// Reuses AppErrorLogService (already Hive-backed, already capped/
// deduplicated — see that file's own header) rather than a second log
// store. Two NEW category values feed this view:
//   - 'chitti_communication' — recorded directly at the speech
//     recognition onError hook in guru_chat_screen.dart (a genuine
//     "didn't understand what you said" moment; STT failures don't
//     throw, so there's no exception for the global handler to catch).
//   - 'chitti_behavior' — recorded automatically by
//     AppErrorLogService.inferCategory()'s new branch, which recognises
//     Chitti's own code by stack frame on any UNCAUGHT error that
//     already reaches the app's existing global FlutterError.onError/
//     PlatformDispatcher.onError handlers — no new call site needed
//     for this half.
//
// "Tell Chitti" deliberately does not call any dev-task API directly.
// It hands the formatted report back to the chat screen to PREFILL the
// message box — sending it through the normal chat flow means Chitti's
// own existing create_dev_task tool (with its own confirmation gate)
// is what actually files the issue, exactly as if the customer had
// typed and reported it themselves. Never a silent, unconfirmed write.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/app_error_log_service.dart';

const Color _bg = Color(0xFF0D0E15);
const Color _card = Color(0xFF181924);
const Color _text = Color(0xFFF1F5F9);
const Color _muted = Color(0xFF94A3B8);
const Color _accent = Color(0xFFB21FFF);
const Color _warn = Color(0xFFFFB020);
const Color _err = Color(0xFFEF4444);

enum _CategoryFilter { all, communication, behavior }

enum _DateFilter { today, last7Days, allTime }

/// Opens the sheet. Returns a formatted report string if the admin
/// tapped "Tell Chitti" on an entry, null otherwise — the caller
/// (guru_chat_screen.dart) is responsible for putting it in the chat
/// input, never sending it automatically.
Future<String?> showChittiErrorLogSheet(BuildContext context) {
  return showModalBottomSheet<String>(
    context: context,
    backgroundColor: _bg,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => const _ChittiErrorLogSheet(),
  );
}

class _ChittiErrorLogSheet extends StatefulWidget {
  const _ChittiErrorLogSheet();

  @override
  State<_ChittiErrorLogSheet> createState() => _ChittiErrorLogSheetState();
}

class _ChittiErrorLogSheetState extends State<_ChittiErrorLogSheet> {
  List<AppErrorLogEntry> _all = [];
  bool _loading = true;
  _CategoryFilter _category = _CategoryFilter.all;
  _DateFilter _date = _DateFilter.last7Days;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    // 300 is generous headroom over the two Chitti categories specifically
    // -- AppErrorLogService's own cap (500 total, all apps/categories
    // combined) means a busy day of unrelated crashes could otherwise
    // push Chitti's own entries out of a smaller window.
    final recent = await AppErrorLogService.getRecentLogs(limit: 300);
    final chittiOnly = recent
        .where(
          (e) =>
              e.category == 'chitti_communication' ||
              e.category == 'chitti_behavior',
        )
        .toList();
    if (!mounted) return;
    setState(() {
      _all = chittiOnly;
      _loading = false;
    });
  }

  List<AppErrorLogEntry> get _filtered {
    final now = DateTime.now();
    return _all.where((e) {
      if (_category == _CategoryFilter.communication &&
          e.category != 'chitti_communication') {
        return false;
      }
      if (_category == _CategoryFilter.behavior &&
          e.category != 'chitti_behavior') {
        return false;
      }
      if (_date == _DateFilter.allTime) return true;
      final ts = DateTime.tryParse(e.timestamp);
      if (ts == null) return true; // don't hide malformed-but-real entries
      final days = now.difference(ts).inDays;
      return _date == _DateFilter.today ? days < 1 : days < 7;
    }).toList();
  }

  void _copyEntry(AppErrorLogEntry e) {
    Clipboard.setData(ClipboardData(text: _formatEntry(e)));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Copied')),
    );
  }

  void _copyAll() {
    final text = _filtered.map(_formatEntry).join('\n\n---\n\n');
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Copied ${_filtered.length} entries')),
    );
  }

  void _tellChitti(AppErrorLogEntry e) {
    Navigator.of(context).pop(
      'Chitti, this happened and needs a look:\n\n${_formatEntry(e)}\n\n'
      'Please create a dev task for it.',
    );
  }

  static String _formatEntry(AppErrorLogEntry e) {
    final kind =
        e.category == 'chitti_communication' ? 'Misheard' : 'Logic/API error';
    return '[$kind] ${e.timestamp}\n${e.errorMessage}';
  }

  @override
  Widget build(BuildContext context) {
    final entries = _filtered;
    return SizedBox(
      height: MediaQuery.of(context).size.height * 0.8,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Center(
              child: Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.5),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Chitti Error Log',
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 16, fontWeight: FontWeight.w700,),
                ),
                if (entries.isNotEmpty)
                  TextButton(
                    onPressed: _copyAll,
                    child: Text('Copy all',
                        style: GoogleFonts.outfit(color: _accent, fontSize: 12),),
                  ),
              ],
            ),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _chip('All', _category == _CategoryFilter.all,
                    () => setState(() => _category = _CategoryFilter.all),),
                _chip(
                    'Misheard (communication)',
                    _category == _CategoryFilter.communication,
                    () => setState(
                        () => _category = _CategoryFilter.communication,),),
                _chip('Logic/API (behavior)',
                    _category == _CategoryFilter.behavior,
                    () => setState(() => _category = _CategoryFilter.behavior),),
              ],
            ),
            const SizedBox(height: 8),
            Wrap(
              spacing: 8,
              children: [
                _chip('Today', _date == _DateFilter.today,
                    () => setState(() => _date = _DateFilter.today),),
                _chip('Last 7 days', _date == _DateFilter.last7Days,
                    () => setState(() => _date = _DateFilter.last7Days),),
                _chip('All time', _date == _DateFilter.allTime,
                    () => setState(() => _date = _DateFilter.allTime),),
              ],
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _accent),)
                  : entries.isEmpty
                      ? Center(
                          child: Text(
                            'Nothing here for this filter.',
                            style:
                                GoogleFonts.outfit(color: _muted, fontSize: 13),
                          ),
                        )
                      : ListView.separated(
                          itemCount: entries.length,
                          separatorBuilder: (_, __) =>
                              const Divider(color: Color(0x26FFFFFF), height: 1),
                          itemBuilder: (context, i) => _entryTile(entries[i]),
                        ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: selected ? _accent.withValues(alpha: 0.18) : _card,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: selected ? _accent : Colors.transparent),
        ),
        child: Text(
          label,
          style: GoogleFonts.outfit(
            color: selected ? _text : _muted,
            fontSize: 11.5,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _entryTile(AppErrorLogEntry e) {
    final isComm = e.category == 'chitti_communication';
    final color = isComm ? _warn : _err;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            isComm ? Icons.hearing_disabled_rounded : Icons.error_outline_rounded,
            color: color,
            size: 18,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isComm ? 'Misheard' : 'Logic/API error',
                  style: GoogleFonts.outfit(
                      color: color, fontSize: 11, fontWeight: FontWeight.w700,),
                ),
                const SizedBox(height: 2),
                Text(
                  e.errorMessage,
                  style: GoogleFonts.outfit(color: _text, fontSize: 12.5),
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 2),
                Text(
                  e.timestamp,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 10),
                ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded, size: 16, color: _muted),
            tooltip: 'Copy',
            onPressed: () => _copyEntry(e),
          ),
          IconButton(
            icon: const Icon(Icons.forum_outlined, size: 18, color: _accent),
            tooltip: 'Tell Chitti',
            onPressed: () => _tellChitti(e),
          ),
        ],
      ),
    );
  }
}
