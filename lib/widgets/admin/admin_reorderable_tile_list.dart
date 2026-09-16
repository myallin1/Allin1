// admin_reorderable_tile_list.dart — drag-to-reorder for admin home
// tiles, exactly like rearranging icons on a phone homescreen.
//
// NEW (Sep 16 2026 — Nizam: "admin app la iruka UI yellame phone la
// app homescreen la icons allign pannikuramari... admin end to end
// logic disturb agama... inimel build agaporathum automatic ah same
// setup la build aga universal ah setup pannanum"). This widget is
// the ONLY new piece: it decides WHERE each tile renders (long-press
// to drag, order remembered per device). Every tile keeps its own
// onTap/badge/stream logic completely untouched — this file never
// sees or calls any of that, it only holds a Widget and a stable id.
//
// "Automatic for future builds" comes from how the saved order is
// applied: a tile id that was never saved (every tile the first time
// a section is opened, and any brand-new tile added to a screen
// later) just falls through to the end, in the screen's own original
// order — see _applyOrder. A screen author adds a new tile to their
// list exactly as before; there is nothing else to wire up.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One entry in an [AdminReorderableTileList]. [id] is never shown —
/// it exists only so the saved order can be matched back to the right
/// tile even after the screen rebuilds with fresh widget instances
/// (new onTap closures, new StreamBuilder snapshots, etc).
@immutable
class AdminHomeTile {
  const AdminHomeTile({required this.id, required this.child});

  final String id;
  final Widget child;
}

class AdminReorderableTileList extends StatefulWidget {
  const AdminReorderableTileList({
    super.key,
    required this.sectionKey,
    required this.tiles,
    this.spacing = 10,
  });

  /// Unique per section (e.g. 'super_admin_home.services') — each
  /// section's order is saved and restored independently.
  final String sectionKey;
  final List<AdminHomeTile> tiles;
  final double spacing;

  @override
  State<AdminReorderableTileList> createState() =>
      _AdminReorderableTileListState();
}

class _AdminReorderableTileListState extends State<AdminReorderableTileList> {
  static const _prefsPrefix = 'admin_home_tile_order::';

  List<AdminHomeTile> _ordered = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ordered = widget.tiles;
    unawaited(_restoreOrder());
  }

  @override
  void didUpdateWidget(covariant AdminReorderableTileList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.sectionKey != widget.sectionKey) {
      _loaded = false;
      _ordered = widget.tiles;
      unawaited(_restoreOrder());
      return;
    }
    // The host screen may rebuild its tile list with fresh instances on
    // every build (live badge counts via StreamBuilder, for example) —
    // re-apply the order already in memory to those NEW instances
    // rather than reloading from disk, so neither a live badge update
    // nor a parent rebuild ever undoes a drag mid-session.
    setState(() {
      _ordered = _applyOrder(
        widget.tiles,
        _ordered.map((t) => t.id).toList(growable: false),
      );
    });
  }

  Future<void> _restoreOrder() async {
    List<String> savedIds = const [];
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString('$_prefsPrefix${widget.sectionKey}');
      if (raw != null) {
        savedIds = (jsonDecode(raw) as List<dynamic>).cast<String>();
      }
    } catch (_) {
      // Corrupt or unreadable prefs — fall back to the screen's own
      // hardcoded order, same as a fresh admin with nothing saved yet.
      savedIds = const [];
    }
    if (!mounted) return;
    setState(() {
      _ordered = _applyOrder(widget.tiles, savedIds);
      _loaded = true;
    });
  }

  static List<AdminHomeTile> _applyOrder(
    List<AdminHomeTile> tiles,
    List<String> savedIds,
  ) {
    final byId = {for (final t in tiles) t.id: t};
    final result = <AdminHomeTile>[];
    for (final id in savedIds) {
      final tile = byId.remove(id);
      if (tile != null) result.add(tile);
    }
    // Anything left — every tile on a section's very first load, and
    // any tile added to the screen's code since the order was last
    // saved — is appended in the screen's own original order.
    result.addAll(byId.values);
    return result;
  }

  Future<void> _persistOrder() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        '$_prefsPrefix${widget.sectionKey}',
        jsonEncode(_ordered.map((t) => t.id).toList(growable: false)),
      );
    } catch (_) {
      // Non-fatal: the new order still applies for this session even
      // if it couldn't be written to disk.
    }
  }

  @override
  Widget build(BuildContext context) {
    // Before the very first prefs read resolves (near-instant, but not
    // synchronous), render in the screen's own order rather than an
    // empty list — avoids a one-frame flash of nothing.
    final tiles = _loaded ? _ordered : widget.tiles;

    return ReorderableListView(
      buildDefaultDragHandles: false,
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      onReorder: (oldIndex, newIndex) {
        setState(() {
          if (newIndex > oldIndex) newIndex -= 1;
          final moved = _ordered.removeAt(oldIndex);
          _ordered.insert(newIndex, moved);
        });
        unawaited(_persistOrder());
      },
      children: [
        for (var i = 0; i < tiles.length; i++)
          // Delayed listener (not the immediate variant): a plain tap
          // still reaches the tile's own onTap/InkWell untouched, and
          // dragging only starts after a genuine long-press — the same
          // gesture a phone homescreen uses to enter "move icons" mode.
          ReorderableDelayedDragStartListener(
            key: ValueKey(tiles[i].id),
            index: i,
            child: Padding(
              padding: EdgeInsets.only(bottom: widget.spacing),
              child: tiles[i].child,
            ),
          ),
      ],
    );
  }
}
