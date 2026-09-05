// ================================================================
// chitti_model_picker_sheet.dart — switch which brain Chitti uses,
// from inside the chat itself
// ================================================================
// NEW (Sep 5 2026 — Nizam: "chitti kita ketta groq key ilanu soldran ...
// admin yentha api potrukkaro antha modela chitti oda chat screen la
// model maathuramari option kudukanum. ide la select pannuna model
// maathikuramari").
//
// Before this, switching models meant leaving the chat, opening AI
// Settings, and finding the right dropdown among four providers' keys
// and per-provider model pickers — a real detour for something that
// should be as quick as noticing "Groq's down, let me try Gemini"
// mid-conversation.
//
// ADMIN ONLY, ON PURPOSE — see chitti_model_provider.dart's own header:
// "the ADMIN can ask for a different model... letting the choice leak
// into the customer build would mean a support call the first time
// somebody picked a slow one." This sheet does not enforce that itself
// (a bottom sheet has no idea which app is showing it) — the caller in
// guru_overlay_service.dart is responsible for only reaching this from
// currentAppVariant == 'admin', matching every other admin-only Chitti
// affordance in this codebase.
//
// ONLY MODELS WITH A KEY ARE OFFERED. Listing all four regardless would
// let the admin pick one with no key configured, send a message, and
// land right back on "I could not reach the full AI" — the exact
// confusion this sheet exists to end. availableModels() is the same
// key-resolution logic guru_api_service.dart's real requests use, so
// this list can never promise a model that the next message can't
// actually reach.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/chitti/chitti_model_provider.dart';
import '../services/guru_api_service.dart';

/// Shows the picker and returns the newly chosen model, or null if the
/// admin dismissed it without picking one (including the "nothing
/// configured" empty state, where there is nothing TO pick).
Future<ChittiModel?> showChittiModelPickerSheet(
  BuildContext context, {
  required String? currentModelId,
}) {
  return showModalBottomSheet<ChittiModel>(
    context: context,
    backgroundColor: const Color(0xFF1A1A2E),
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
    ),
    builder: (_) => _ChittiModelPickerSheet(currentModelId: currentModelId),
  );
}

class _ChittiModelPickerSheet extends StatefulWidget {
  const _ChittiModelPickerSheet({required this.currentModelId});

  final String? currentModelId;

  @override
  State<_ChittiModelPickerSheet> createState() =>
      _ChittiModelPickerSheetState();
}

class _ChittiModelPickerSheetState extends State<_ChittiModelPickerSheet> {
  late Future<List<ChittiModel>> _future;

  @override
  void initState() {
    super.initState();
    _future = GuruApiService().availableModels();
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 36,
              height: 4,
              margin: const EdgeInsets.only(bottom: 14),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              "Choose Chitti's model",
              style: GoogleFonts.outfit(
                color: Colors.white,
                fontWeight: FontWeight.w800,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 3),
            Text(
              'Only models with a key already saved in AI Settings are shown.',
              style: GoogleFonts.outfit(
                color: Colors.white.withValues(alpha: 0.55),
                fontSize: 11.5,
              ),
            ),
            const SizedBox(height: 14),
            FutureBuilder<List<ChittiModel>>(
              future: _future,
              builder: (context, snapshot) {
                if (snapshot.connectionState != ConnectionState.done) {
                  return const Padding(
                    padding: EdgeInsets.symmetric(vertical: 24),
                    child: Center(
                      child: SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(strokeWidth: 2.2),
                      ),
                    ),
                  );
                }
                final models = snapshot.data ?? const <ChittiModel>[];
                if (models.isEmpty) {
                  return _EmptyState(onClose: () => Navigator.pop(context));
                }
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final m in models)
                      _ModelTile(
                        model: m,
                        selected: m.id == widget.currentModelId ||
                            (widget.currentModelId == null &&
                                m.id == defaultChittiModel.id),
                        onTap: () async {
                          await setChittiModelId(m.id);
                          if (context.mounted) Navigator.pop(context, m);
                        },
                      ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _ModelTile extends StatelessWidget {
  const _ModelTile({
    required this.model,
    required this.selected,
    required this.onTap,
  });

  final ChittiModel model;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: selected
            ? const Color(0xFFFF4FA3).withValues(alpha: 0.16)
            : Colors.white.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(14),
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        model.label,
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                      if (!model.supportsTools) ...[
                        const SizedBox(height: 2),
                        Text(
                          'Can answer questions, but cannot act (no tools)',
                          style: GoogleFonts.outfit(
                            color: Colors.white.withValues(alpha: 0.5),
                            fontSize: 10.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                if (selected)
                  const Icon(
                    Icons.check_circle_rounded,
                    color: Color(0xFFFF4FA3),
                    size: 20,
                  )
                else
                  Icon(
                    Icons.circle_outlined,
                    color: Colors.white.withValues(alpha: 0.25),
                    size: 20,
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onClose});

  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'No model has a key saved yet.',
            style: GoogleFonts.outfit(
              color: Colors.white,
              fontWeight: FontWeight.w700,
              fontSize: 13,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            'Add at least one API key in AI Settings, then come back here '
            'to pick one. Chitti still works offline for opening sections, '
            'checking orders, and booking — it just cannot chat freely '
            'until a key is added.',
            style: GoogleFonts.outfit(
              color: Colors.white.withValues(alpha: 0.55),
              fontSize: 11.5,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onClose,
              style: TextButton.styleFrom(
                backgroundColor: Colors.white.withValues(alpha: 0.08),
                padding: const EdgeInsets.symmetric(vertical: 11),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(11),
                ),
              ),
              child: Text(
                'Got it',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A small pill showing which model Chitti is currently using, and
/// opening the full picker on tap.
///
/// PROMOTED TO PUBLIC (Sep 2026 — CTO review of PR #61): the overlay
/// header (guru_overlay_service.dart) had its own private copy of this;
/// GuruChatScreen's AppBar needed the identical behaviour, so this is
/// now the one copy both call, parameterised for the two very different
/// backgrounds it sits on (the overlay's pink gradient header vs the
/// chat screen's plain themed AppBar).
///
/// Its own tiny StatefulWidget (rather than reading state the parent
/// screen already tracks) because the chosen model lives in
/// SharedPreferences, not in any ChangeNotifier either caller already
/// has — nothing would tell this chip to rebuild when the admin picks a
/// different one, so it re-reads its own label after the picker sheet
/// closes instead.
class ChittiModelChip extends StatefulWidget {
  const ChittiModelChip({
    super.key,
    required this.onChanged,
    this.foregroundColor = Colors.white,
    this.backgroundColor = const Color(0x29FFFFFF),
  });

  /// Called after the admin actually picks a (possibly different)
  /// model, so the parent can rebuild anything else that cares — a
  /// silent no-op parent callback is cheaper insurance than finding out
  /// later something needed it.
  final VoidCallback onChanged;

  /// Text/icon colour. Defaults to the overlay header's white-on-pink
  /// look; GuruChatScreen's AppBar passes its own themed ink colour so
  /// the chip reads correctly against a plain (often light) background.
  final Color foregroundColor;

  /// Pill fill. Defaults to a translucent white, which only reads
  /// correctly on a dark/coloured header — callers on a light
  /// background should pass a themed subtle fill instead.
  final Color backgroundColor;

  @override
  State<ChittiModelChip> createState() => _ChittiModelChipState();
}

class _ChittiModelChipState extends State<ChittiModelChip> {
  String? _modelId;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    final id = await getChittiModelId();
    if (mounted) setState(() => _modelId = id);
  }

  /// The label's first word ("Groq", "Gemini", "DeepSeek", "Claude") —
  /// the parenthetical qualifier ("fastest", "best reasoning") is meant
  /// for the full picker sheet, not a header chip with room for one
  /// short word.
  String get _shortLabel {
    final model = chittiModelById(_modelId);
    return model.label.split(' ').first;
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: widget.backgroundColor,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () async {
          final picked = await showChittiModelPickerSheet(
            context,
            currentModelId: _modelId,
          );
          if (picked != null && mounted) {
            setState(() => _modelId = picked.id);
            widget.onChanged();
          }
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                _shortLabel,
                style: GoogleFonts.outfit(
                  color: widget.foregroundColor,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(width: 2),
              Icon(
                Icons.expand_more_rounded,
                color: widget.foregroundColor,
                size: 13,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
