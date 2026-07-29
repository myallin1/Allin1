// ================================================================
// MemoryMatchScreen — card flip pair-matching game
// ================================================================
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFFFFF6FA);
const Color _pink = Color(0xFFFF4FA3);
const Color _purple = Color(0xFFB21FFF);
const Color _navy = Color(0xFF201A22);
const Color _muted = Color(0xFF8A4E72);

const List<IconData> _iconPool = [
  Icons.favorite_rounded,
  Icons.star_rounded,
  Icons.pets_rounded,
  Icons.local_pizza_rounded,
  Icons.bolt_rounded,
  Icons.emoji_emotions_rounded,
  Icons.local_florist_rounded,
  Icons.music_note_rounded,
];

class MemoryMatchScreen extends StatefulWidget {
  const MemoryMatchScreen({super.key});

  @override
  State<MemoryMatchScreen> createState() => _MemoryMatchScreenState();
}

class _MemoryMatchScreenState extends State<MemoryMatchScreen> {
  late List<IconData> _cards;
  late List<bool> _revealed;
  late List<bool> _matched;
  int? _firstIndex;
  bool _busy = false;
  int _moves = 0;
  int _matchedPairs = 0;
  int _seconds = 0;
  Timer? _timer;
  bool _finished = false;

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _startNewGame() {
    final pool = List<IconData>.from(_iconPool)..shuffle();
    final chosen = pool.take(8).toList();
    _cards = [...chosen, ...chosen]..shuffle(Random());
    _revealed = List.filled(_cards.length, false);
    _matched = List.filled(_cards.length, false);
    _firstIndex = null;
    _busy = false;
    _moves = 0;
    _matchedPairs = 0;
    _seconds = 0;
    _finished = false;
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_finished) setState(() => _seconds++);
    });
    setState(() {});
  }

  void _onTapCard(int index) {
    if (_busy || _revealed[index] || _matched[index] || _finished) return;
    setState(() => _revealed[index] = true);

    if (_firstIndex == null) {
      _firstIndex = index;
      return;
    }

    _moves++;
    final first = _firstIndex!;
    if (_cards[first] == _cards[index]) {
      _matched[first] = true;
      _matched[index] = true;
      _matchedPairs++;
      _firstIndex = null;
      if (_matchedPairs == _cards.length ~/ 2) {
        _finished = true;
        _timer?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) => _showWinDialog());
      }
    } else {
      _busy = true;
      Future.delayed(const Duration(milliseconds: 700), () {
        if (!mounted) return;
        setState(() {
          _revealed[first] = false;
          _revealed[index] = false;
          _firstIndex = null;
          _busy = false;
        });
      });
    }
    setState(() {});
  }

  void _showWinDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text('You matched them all!', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: _navy)),
        content: Text('Moves: $_moves\nTime: ${_formatTime(_seconds)}',
            style: GoogleFonts.outfit(color: _muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _pink, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _startNewGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  String _formatTime(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _navy),
        title: Text('Memory Match', style: GoogleFonts.outfit(color: _navy, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: _pink), onPressed: _startNewGame),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _statChip('Moves', '$_moves'),
                    _statChip('Time', _formatTime(_seconds)),
                    _statChip('Pairs', '$_matchedPairs/8'),
                  ],
                ),
                const SizedBox(height: 16),
                GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _cards.length,
                  gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: 4,
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final show = _revealed[index] || _matched[index];
                    return GestureDetector(
                      onTap: () => _onTapCard(index),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 200),
                        decoration: BoxDecoration(
                          gradient: show
                              ? const LinearGradient(colors: [Color(0xFFFFC2E0), Color(0xFFE7C2FF)])
                              : const LinearGradient(colors: [_pink, _purple]),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: [
                            BoxShadow(color: Colors.black.withOpacity(0.08), blurRadius: 6, offset: const Offset(0, 3)),
                          ],
                        ),
                        alignment: Alignment.center,
                        child: show
                            ? Icon(_cards[index], color: _navy, size: 28)
                            : Text('NJ',
                                style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 14)),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 14),
                Text(
                  'Tap two cards to find matching pairs.',
                  style: GoogleFonts.outfit(color: _muted, fontSize: 13, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEAF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FF4FA3)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.outfit(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
          Text(value, style: GoogleFonts.outfit(color: _pink, fontSize: 16, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
