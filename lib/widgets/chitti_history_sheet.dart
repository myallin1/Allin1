// ================================================================
// chitti_history_sheet.dart — "என்ன பேசினோம்?"
// ================================================================
// NEW (Aug 28 2026 — Nizam: "all apps kum ithukumunnadi chitti kita
// pannuna chat ah pakka history oru button ah new chat la vei").
//
// WHAT WAS ACTUALLY BROKEN
// "New chat" called clear(), which DELETED the conversation outright.
// So the app whose entire premise is that Chitti remembers you threw
// that memory away every time anyone tapped New chat. Someone who
// explained their address once and then started a fresh chat had
// simply lost it, with no way back.
//
// The fix is in ChittiChatHistoryService (archive instead of delete).
// This is the way back in.
//
// ONE SHEET FOR ALL FOUR APPS
// Customer, hero, seller and admin all get the same button. The
// conversations differ; the need to look one up does not. A per-app
// variant would have meant four places for this to rot.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../config/app_variant.dart';
import '../services/chitti_chat_history_service.dart';

/// Shows the past-chats sheet.
///
/// Returns the messages of the conversation the user picked, or null
/// if they backed out.
Future<List<Map<String, dynamic>>?> showChittiHistorySheet(
  BuildContext context,
) {
  return showModalBottomSheet<List<Map<String, dynamic>>>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => const _ChittiHistorySheet(),
  );
}

class _ChittiHistorySheet extends StatefulWidget {
  const _ChittiHistorySheet();

  @override
  State<_ChittiHistorySheet> createState() => _ChittiHistorySheetState();
}

class _ChittiHistorySheetState extends State<_ChittiHistorySheet> {
  // The admin and seller builds are dark and light respectively; the
  // customer and hero builds are the pink theme. One palette would
  // look broken in whichever app it was not drawn for.
  bool get _dark => currentAppVariant == 'admin';

  Color get _surface => _dark ? const Color(0xFF12121E) : Colors.white;
  Color get _text => _dark ? const Color(0xFFEEEEF5) : const Color(0xFF4A1236);
  Color get _muted =>
      _dark ? const Color(0xFF7777A0) : const Color(0xFF8A4E72);
  Color get _accent =>
      _dark ? const Color(0xFF11998E) : const Color(0xFFFF4FA3);

  List<ChittiChatSession>? _sessions;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await ChittiChatHistoryService.pastSessions();
    if (!mounted) return;
    setState(() => _sessions = s);
  }

  Future<void> _open(int index) async {
    final msgs = await ChittiChatHistoryService.resumeSession(index);
    if (!mounted) return;
    Navigator.of(context).pop(msgs);
  }

  Future<void> _clearAll() async {
    // Confirmed: this is the one irreversible thing on the sheet, and
    // it removes exactly what the sheet exists to protect.
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(
          'Delete all past chats?',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
        content: Text(
          'Your current chat stays. Everything older is removed from this '
          'phone and cannot be recovered.',
          style: GoogleFonts.outfit(fontSize: 13.5),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ChittiChatHistoryService.clearHistory();
    await _load();
  }

  @override
  Widget build(BuildContext context) {
    final sessions = _sessions;

    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      minChildSize: 0.3,
      maxChildSize: 0.92,
      expand: false,
      builder: (context, scrollController) {
        return Container(
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: const BorderRadius.vertical(
              top: Radius.circular(22),
            ),
          ),
          child: Column(
            children: [
              const SizedBox(height: 10),
              Container(
                width: 38,
                height: 4,
                decoration: BoxDecoration(
                  color: _muted.withValues(alpha: 0.4),
                  borderRadius: BorderRadius.circular(99),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 10, 8),
                child: Row(
                  children: [
                    Icon(Icons.history_rounded, color: _accent, size: 20),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Past chats',
                        style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 16,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    if (sessions != null && sessions.isNotEmpty)
                      TextButton(
                        onPressed: _clearAll,
                        child: Text(
                          'Clear',
                          style: GoogleFonts.outfit(
                            color: _muted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              Expanded(
                child: sessions == null
                    ? Center(
                        child: CircularProgressIndicator(color: _accent),
                      )
                    : sessions.isEmpty
                        ? _empty()
                        : ListView.builder(
                            controller: scrollController,
                            padding: const EdgeInsets.fromLTRB(14, 0, 14, 24),
                            itemCount: sessions.length,
                            itemBuilder: (_, i) => _tile(sessions[i], i),
                          ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _empty() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(30),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('💬', style: TextStyle(fontSize: 36)),
            const SizedBox(height: 10),
            Text(
              'No past chats yet',
              style: GoogleFonts.outfit(
                color: _text,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'When you start a new chat, the old one is kept here instead '
              'of being thrown away.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: _muted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _tile(ChittiChatSession s, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: _dark ? const Color(0xFF1A1A2E) : const Color(0xFFFFF3F9),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: () => _open(index),
          child: Padding(
            padding: const EdgeInsets.all(13),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        s.title,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                          height: 1.3,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        [
                          if (s.whenLabel.isNotEmpty) s.whenLabel,
                          '${s.messages.length} messages',
                        ].join(' · '),
                        style: GoogleFonts.outfit(
                          color: _muted,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, color: _muted),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
