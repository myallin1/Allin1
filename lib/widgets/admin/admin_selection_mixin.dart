// ================================================================
// admin_selection_mixin.dart — shared multi-select state
// ================================================================
// NEW (Aug 11 2026 — Test Data Cleanup System). Five different admin
// screens need "select mode + checkboxes + a phone filter + a Delete
// (N) Selected bar", and each screen's list is a different shape
// (ServiceRequestModel, a rides Map, an orders Map...). Rather than
// duplicate that state five times, this mixin owns just the STATE and
// the reusable pieces of UI (the toolbar and the delete bar); each
// screen still renders its own cards and decides where to put the
// checkbox, since card layouts differ too much to share further than
// this.
// ================================================================
import 'package:flutter/material.dart';

mixin AdminSelectionMixin<T extends StatefulWidget> on State<T> {
  bool selectMode = false;
  final Set<String> selectedIds = <String>{};

  /// Empty means "no filter" — every screen using this mixin should
  /// treat that as "show everything".
  String phoneFilter = '';

  void toggleSelectMode() {
    setState(() {
      selectMode = !selectMode;
      if (!selectMode) selectedIds.clear();
    });
  }

  void toggleItemSelected(String id) {
    setState(() {
      if (selectedIds.contains(id)) {
        selectedIds.remove(id);
      } else {
        selectedIds.add(id);
      }
    });
  }

  void selectAll(Iterable<String> ids) {
    setState(() => selectedIds
      ..clear()
      ..addAll(ids));
  }

  void clearSelection() => setState(() => selectedIds.clear());

  void setPhoneFilter(String value) => setState(() => phoneFilter = value);

  /// True if [phone] matches the current filter. Deliberately loose
  /// (contains, not equals) — an admin typing the last 4-6 digits of
  /// their own dev number should not need the exact full string.
  bool matchesPhoneFilter(String phone) {
    if (phoneFilter.trim().isEmpty) return true;
    return phone.contains(phoneFilter.trim());
  }

  // ── Reusable UI pieces ──────────────────────────────────────────

  /// Row of controls: select-mode toggle + (when in select mode) the
  /// phone filter field and a "Select all visible" action. Each screen
  /// places this wherever fits its existing app bar / header.
  Widget buildSelectionToolbar({
    required BuildContext context,
    required List<String> visibleIds,
    required VoidCallback onFilterChanged,
  }) {
    return Row(
      children: [
        IconButton(
          icon: Icon(
            selectMode ? Icons.close_rounded : Icons.checklist_rounded,
            color: const Color(0xFFEEEEF5),
          ),
          tooltip: selectMode ? 'Exit select mode' : 'Select mode',
          onPressed: toggleSelectMode,
        ),
        if (selectMode) ...[
          Expanded(
            child: SizedBox(
              height: 38,
              child: TextField(
                style: const TextStyle(color: Color(0xFFEEEEF5), fontSize: 13),
                decoration: InputDecoration(
                  isDense: true,
                  hintText: 'Filter by phone (e.g. your dev number)',
                  hintStyle:
                      const TextStyle(color: Color(0xFF7777A0), fontSize: 12.5),
                  prefixIcon: const Icon(Icons.phone_iphone_rounded,
                      size: 16, color: Color(0xFF7777A0)),
                  filled: true,
                  fillColor: const Color(0xFF1A1A2E),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide.none,
                  ),
                ),
                onChanged: (v) {
                  setPhoneFilter(v);
                  onFilterChanged();
                },
              ),
            ),
          ),
          const SizedBox(width: 8),
          // Only ever selects what's currently VISIBLE (i.e. already
          // passed the phone filter) — "Select all" must never reach
          // past a filter the admin deliberately narrowed the list
          // with.
          TextButton(
            onPressed: () => selectAll(visibleIds),
            child: const Text('Select all',
                style: TextStyle(color: Color(0xFFFF4FA3), fontSize: 12.5)),
          ),
        ],
      ],
    );
  }

  /// The floating "Delete (N) Selected" bar. Returns an empty widget
  /// when there's nothing selected, so screens can place this
  /// unconditionally at the bottom of their build().
  Widget buildDeleteBar({
    required String subjectPlural,
    required Future<void> Function() onDelete,
  }) {
    if (!selectMode || selectedIds.isEmpty) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        color: Color(0xFF12121E),
        border: Border(top: BorderSide(color: Color(0x1AFFFFFF))),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          width: double.infinity,
          child: ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF5252),
              foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 13),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.delete_forever_rounded),
            label: Text('Delete (${selectedIds.length}) Selected'),
            onPressed: onDelete,
          ),
        ),
      ),
    );
  }

  /// A small leading checkbox, styled consistently, for a screen's own
  /// card widget to place wherever fits its layout.
  Widget buildSelectionCheckbox(String id) {
    return Checkbox(
      value: selectedIds.contains(id),
      onChanged: (_) => toggleItemSelected(id),
      fillColor: WidgetStateProperty.resolveWith(
        (states) => states.contains(WidgetState.selected)
            ? const Color(0xFFFF4FA3)
            : const Color(0xFF262636),
      ),
    );
  }
}
