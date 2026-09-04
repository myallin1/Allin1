// ================================================================
// admin_my_day_screen.dart — what Nizam said he'd do, and whether
// he's done it.
// ================================================================
// NEW (Sep 4 2026 — Nizam: "apopo adminoda daily schedule pottu vachutu
// itha mudichutingla boss athu mudichutingla boss nu kekekanum enkita
// ... enoda task ah folowup pannanum sollapona ennoda persnol
// secrotryavum irukanum").
//
// The store behind this (ChittiCommitmentService) shipped first, on
// purpose: the PR #40 persona audit found admin Chitti had been
// INSTRUCTED to follow up on commitments with nowhere to read them
// from, which leaves a model two options — stay silent, or invent a
// commitment. Inventing one is the same failure class as inventing a
// balance. So the record came first; this is the screen that fills it.
//
// WHY IT LOOKS PLAIN
// A founder's todo list has to be faster to use than a paper note or it
// loses to the paper note. One field, one date chip, done. No
// categories, no priorities, no projects — every one of those is a
// decision to make before the thing is written down, and the thing not
// getting written down is the actual failure mode here.
//
// Works with no API and no network: the store is SharedPreferences and
// every string on this screen is fixed. Chitti's spoken follow-up needs
// nothing more either.
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/chitti/chitti_commitment_service.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF16162A);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _purple = Color(0xFFB21FFF);
const Color _green = Color(0xFF4ADE80);
const Color _amber = Color(0xFFFFB020);

class AdminMyDayScreen extends StatefulWidget {
  const AdminMyDayScreen({super.key});

  @override
  State<AdminMyDayScreen> createState() => _AdminMyDayScreenState();
}

class _AdminMyDayScreenState extends State<AdminMyDayScreen> {
  final _service = ChittiCommitmentService.instance;

  @override
  void initState() {
    super.initState();
    _service.addListener(_onChanged);
    _service.load();
  }

  @override
  void dispose() {
    _service.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final overdue = _service.overdue;
    final today = _service.today.where((c) => !c.isOverdue).toList();
    final later = _service.openItems
        .where((c) => !c.isOverdue && !c.isToday)
        .toList();
    final done = _service.all
        .where((c) => c.status == CommitmentStatus.done)
        .toList()
        .reversed
        .take(5)
        .toList();

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text('My Day',
            style: GoogleFonts.outfit(
                color: _text, fontWeight: FontWeight.w700, fontSize: 16)),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addSheet,
        backgroundColor: _purple,
        foregroundColor: Colors.white,
        icon: const Icon(Icons.add_rounded, size: 20),
        label: Text('Add',
            style: GoogleFonts.outfit(
                fontSize: 13, fontWeight: FontWeight.w600)),
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 90),
        children: [
          if (overdue.isEmpty && today.isEmpty && later.isEmpty) _emptyState(),
          // Overdue first and unmissable: this is the only section Chitti
          // will ever speak up about, so the screen and the voice agree.
          if (overdue.isNotEmpty) ...[
            _sectionHeader('Overdue', overdue.length, _amber),
            for (final c in overdue) _tile(c, overdue: true),
            const SizedBox(height: 14),
          ],
          if (today.isNotEmpty) ...[
            _sectionHeader('Today', today.length, _purple),
            for (final c in today) _tile(c),
            const SizedBox(height: 14),
          ],
          if (later.isNotEmpty) ...[
            _sectionHeader('Later', later.length, _muted),
            for (final c in later) _tile(c),
            const SizedBox(height: 14),
          ],
          if (done.isNotEmpty) ...[
            _sectionHeader('Done', done.length, _green),
            for (final c in done) _doneTile(c),
          ],
        ],
      ),
    );
  }

  Widget _emptyState() => Padding(
        padding: const EdgeInsets.only(top: 60),
        child: Column(
          children: [
            const Icon(Icons.check_circle_outline_rounded,
                color: _muted, size: 40),
            const SizedBox(height: 12),
            Text('Nothing on the list.',
                style: GoogleFonts.outfit(color: _text, fontSize: 15)),
            const SizedBox(height: 5),
            Text(
              'Add something you need to come back to, and Chitti will '
              'ask you about it once it is due.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted, fontSize: 12.5),
            ),
          ],
        ),
      );

  Widget _sectionHeader(String label, int count, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 8, top: 2),
        child: Row(
          children: [
            Text(label.toUpperCase(),
                style: GoogleFonts.outfit(
                    color: color,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1)),
            const SizedBox(width: 7),
            Text('$count',
                style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
          ],
        ),
      );

  Widget _tile(Commitment c, {bool overdue = false}) => Container(
        margin: const EdgeInsets.only(bottom: 9),
        padding: const EdgeInsets.fromLTRB(13, 12, 8, 12),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(13),
          border:
              overdue ? Border.all(color: _amber.withValues(alpha: 0.4)) : null,
        ),
        child: Row(
          children: [
            // Tapping the circle is the whole "done" interaction — no
            // menu, no confirm. Marking something done should cost less
            // effort than the thing itself.
            InkWell(
              onTap: () => _service.markDone(c.id),
              customBorder: const CircleBorder(),
              child: const Padding(
                padding: EdgeInsets.all(4),
                child: Icon(Icons.radio_button_unchecked_rounded,
                    color: _muted, size: 22),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(c.what,
                      style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          height: 1.3)),
                  const SizedBox(height: 3),
                  Row(
                    children: [
                      Text(_when(c.dueAt),
                          style: GoogleFonts.outfit(
                              color: overdue ? _amber : _muted, fontSize: 11.5)),
                      if (c.timesAsked > 0) ...[
                        const SizedBox(width: 8),
                        Text(
                          c.timesAsked >=
                                  ChittiCommitmentService.kMaxAsksPerCommitment
                              ? 'Chitti stopped asking'
                              : 'asked ${c.timesAsked}x',
                          style:
                              GoogleFonts.outfit(color: _muted, fontSize: 11),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
            PopupMenuButton<String>(
              color: _card,
              icon: const Icon(Icons.more_vert_rounded, color: _muted, size: 19),
              onSelected: (v) {
                switch (v) {
                  case 'later':
                    _service.snooze(c.id, const Duration(hours: 3));
                  case 'tomorrow':
                    _service.snooze(c.id, const Duration(days: 1));
                  case 'remove':
                    _service.remove(c.id);
                }
              },
              itemBuilder: (_) => [
                _menuItem('later', 'Ask me in 3 hours'),
                _menuItem('tomorrow', 'Tomorrow'),
                _menuItem('remove', 'Remove'),
              ],
            ),
          ],
        ),
      );

  PopupMenuItem<String> _menuItem(String value, String label) =>
      PopupMenuItem<String>(
        value: value,
        child: Text(label,
            style: GoogleFonts.outfit(color: _text, fontSize: 13)),
      );

  Widget _doneTile(Commitment c) => Padding(
        padding: const EdgeInsets.only(bottom: 7, left: 4),
        child: Row(
          children: [
            const Icon(Icons.check_circle_rounded, color: _green, size: 17),
            const SizedBox(width: 9),
            Expanded(
              child: Text(c.what,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: GoogleFonts.outfit(
                      color: _muted,
                      fontSize: 13,
                      decoration: TextDecoration.lineThrough)),
            ),
            TextButton(
              onPressed: () => _service.reopen(c.id),
              style: TextButton.styleFrom(
                  foregroundColor: _muted, minimumSize: Size.zero),
              child: Text('Undo',
                  style: GoogleFonts.outfit(fontSize: 11.5)),
            ),
          ],
        ),
      );

  Future<void> _addSheet() async {
    final controller = TextEditingController();
    // Default to this evening rather than "now": almost everything he
    // adds is something to come back to later today.
    var due = DateTime.now().add(const Duration(hours: 4));

    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: _card,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) => Padding(
          padding: EdgeInsets.fromLTRB(
              18, 18, 18, MediaQuery.of(sheetContext).viewInsets.bottom + 18),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What do you need to come back to?',
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 15.5, fontWeight: FontWeight.w700)),
              const SizedBox(height: 12),
              TextField(
                controller: controller,
                autofocus: true,
                textCapitalization: TextCapitalization.sentences,
                style: GoogleFonts.outfit(color: _text, fontSize: 14),
                decoration: InputDecoration(
                  hintText: 'e.g. call the Gandhipuram seller back',
                  hintStyle:
                      GoogleFonts.outfit(color: _muted, fontSize: 13),
                  filled: true,
                  fillColor: _bg,
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide.none),
                ),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                children: [
                  _dueChip('In 1 hour', const Duration(hours: 1), due,
                      (d) => setSheet(() => due = d)),
                  _dueChip('This evening', const Duration(hours: 4), due,
                      (d) => setSheet(() => due = d)),
                  _dueChip('Tomorrow', const Duration(days: 1), due,
                      (d) => setSheet(() => due = d)),
                ],
              ),
              const SizedBox(height: 14),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () async {
                    final text = controller.text.trim();
                    if (text.isEmpty) return;
                    await _service.add(what: text, dueAt: due);
                    if (sheetContext.mounted) {
                      Navigator.of(sheetContext).pop();
                    }
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _purple,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 13),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(11)),
                  ),
                  child: const Text('Add'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _dueChip(String label, Duration offset, DateTime current,
      ValueChanged<DateTime> onPick) {
    final target = DateTime.now().add(offset);
    final selected = (current.difference(target).inMinutes).abs() < 2;
    return ChoiceChip(
      label: Text(label,
          style: GoogleFonts.outfit(
              color: selected ? Colors.white : _muted, fontSize: 12)),
      selected: selected,
      onSelected: (_) => onPick(target),
      backgroundColor: _bg,
      selectedColor: _purple,
      showCheckmark: false,
      side: BorderSide(color: _muted.withValues(alpha: 0.25)),
    );
  }

  static String _when(DateTime dt) {
    final now = DateTime.now();
    final diff = dt.difference(now);
    if (diff.isNegative) {
      final late = now.difference(dt);
      if (late.inMinutes < 60) return '${late.inMinutes}m overdue';
      if (late.inHours < 24) return '${late.inHours}h overdue';
      return '${late.inDays}d overdue';
    }
    if (diff.inMinutes < 60) return 'in ${diff.inMinutes}m';
    if (diff.inHours < 24) return 'in ${diff.inHours}h';
    return '${dt.day}/${dt.month} at ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
  }
}
