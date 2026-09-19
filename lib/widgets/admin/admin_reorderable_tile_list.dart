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

import 'package:flutter/material.dart';

import '../../services/dynamic_app_layout_service.dart';

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
    required this.sectionKey,
    required this.tiles,
    super.key,
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
  List<AdminHomeTile> _ordered = const [];
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _ordered = widget.tiles;
    DynamicAppLayoutService.instance.layoutNotifier.addListener(_onExternalLayoutChanged);
    unawaited(_restoreOrder());
  }

  @override
  void dispose() {
    DynamicAppLayoutService.instance.layoutNotifier.removeListener(_onExternalLayoutChanged);
    super.dispose();
  }

  void _onExternalLayoutChanged() {
    if (!mounted) return;
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
    setState(() {
      _ordered = _applyOrder(
        widget.tiles,
        _ordered.map((t) => t.id).toList(growable: false),
      );
    });
  }

  Future<void> _restoreOrder() async {
    final defaultIds = widget.tiles.map((t) => t.id).toList(growable: false);
    final savedIds = await DynamicAppLayoutService.instance.getOrderedIds(
      sectionKey: widget.sectionKey,
      defaultIds: defaultIds,
    );

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
    result.addAll(byId.values);
    return result;
  }

  Future<void> _persistOrder() async {
    final orderedIds = _ordered.map((t) => t.id).toList(growable: false);
    await DynamicAppLayoutService.instance.saveSectionOrder(
      sectionKey: widget.sectionKey,
      orderedIds: orderedIds,
    );
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
      // ignore: deprecated_member_use
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
