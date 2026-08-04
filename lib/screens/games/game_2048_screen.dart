// ================================================================
// Game2048Screen — classic 2048 number-merge puzzle
// ================================================================
// Part of the Game Zone refresh (per Nizam's request — the old single
// sliding-puzzle game felt bland). Pure-Dart game logic, swipe
// gestures via GestureDetector's pan-end velocity, no external
// packages or image assets needed.
// ================================================================
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFFFFF6FA);
const Color _pink = Color(0xFFFF4FA3);
const Color _navy = Color(0xFF201A22);
const Color _muted = Color(0xFF8A4E72);

class Game2048Screen extends StatefulWidget {
  const Game2048Screen({super.key});

  @override
  State<Game2048Screen> createState() => _Game2048ScreenState();
}

class _Game2048ScreenState extends State<Game2048Screen> {
  static const int _size = 4;
  final Random _random = Random();
  late List<List<int>> _grid;
  int _score = 0;
  int _best = 0;
  bool _gameOver = false;
  bool _won = false;

  @override
  void initState() {
    super.initState();
    _startNewGame();
  }

  void _startNewGame() {
    _grid = List.generate(_size, (_) => List.filled(_size, 0));
    _score = 0;
    _gameOver = false;
    _won = false;
    _spawnTile();
    _spawnTile();
    setState(() {});
  }

  void _spawnTile() {
    final empties = <Point<int>>[];
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) empties.add(Point(r, c));
      }
    }
    if (empties.isEmpty) return;
    final p = empties[_random.nextInt(empties.length)];
    _grid[p.x][p.y] = _random.nextDouble() < 0.9 ? 2 : 4;
  }

  List<int> _compress(List<int> row) {
    final nonZero = row.where((v) => v != 0).toList();
    final result = <int>[];
    var i = 0;
    while (i < nonZero.length) {
      if (i + 1 < nonZero.length && nonZero[i] == nonZero[i + 1]) {
        final merged = nonZero[i] * 2;
        result.add(merged);
        _score += merged;
        if (merged == 2048) _won = true;
        i += 2;
      } else {
        result.add(nonZero[i]);
        i += 1;
      }
    }
    while (result.length < _size) {
      result.add(0);
    }
    return result;
  }

  bool _move(String direction) {
    final before = _grid.map(List<int>.from).toList();

    List<List<int>> rotate(List<List<int>> g) {
      final rotated = List.generate(_size, (_) => List.filled(_size, 0));
      for (var r = 0; r < _size; r++) {
        for (var c = 0; c < _size; c++) {
          rotated[c][_size - 1 - r] = g[r][c];
        }
      }
      return rotated;
    }

    var working = _grid;
    var rotations = 0;
    switch (direction) {
      case 'left':
        rotations = 0;
        break;
      case 'up':
        rotations = 3;
        break;
      case 'right':
        rotations = 2;
        break;
      case 'down':
        rotations = 1;
        break;
    }
    for (var i = 0; i < rotations; i++) {
      working = rotate(working);
    }
    working = working.map(_compress).toList();
    for (var i = 0; i < (4 - rotations) % 4; i++) {
      working = rotate(working);
    }
    _grid = working;

    final changed = _grid.toString() != before.toString();
    return changed;
  }

  void _handleMove(String direction) {
    if (_gameOver) return;
    final changed = _move(direction);
    if (changed) {
      _spawnTile();
      if (_score > _best) _best = _score;
      if (!_hasMovesLeft()) _gameOver = true;
      setState(() {});
    }
  }

  bool _hasMovesLeft() {
    for (var r = 0; r < _size; r++) {
      for (var c = 0; c < _size; c++) {
        if (_grid[r][c] == 0) return true;
        if (c + 1 < _size && _grid[r][c] == _grid[r][c + 1]) return true;
        if (r + 1 < _size && _grid[r][c] == _grid[r + 1][c]) return true;
      }
    }
    return false;
  }

  Color _tileColor(int value) {
    switch (value) {
      case 2:
        return const Color(0xFFFFE0EF);
      case 4:
        return const Color(0xFFFFC2E0);
      case 8:
        return const Color(0xFFFF9CCB);
      case 16:
        return const Color(0xFFFF73BE);
      case 32:
        return const Color(0xFFFF4FA3);
      case 64:
        return const Color(0xFFE0399A);
      case 128:
        return const Color(0xFFC22C8C);
      case 256:
        return const Color(0xFFA31F80);
      case 512:
        return const Color(0xFF861774);
      case 1024:
        return const Color(0xFF6B1068);
      default:
        return const Color(0xFF4A0C5C);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _navy),
        title: Text('2048', style: GoogleFonts.outfit(color: _navy, fontWeight: FontWeight.w800)),
        actions: [
          IconButton(icon: const Icon(Icons.refresh_rounded, color: _pink), onPressed: _startNewGame),
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _scoreChip('Score', '$_score'),
                    _scoreChip('Best', '$_best'),
                  ],
                ),
                const SizedBox(height: 16),
                GestureDetector(
                  onPanEnd: (details) {
                    final v = details.velocity.pixelsPerSecond;
                    if (v.dx.abs() > v.dy.abs()) {
                      _handleMove(v.dx > 0 ? 'right' : 'left');
                    } else if (v.dy.abs() > 0) {
                      _handleMove(v.dy > 0 ? 'down' : 'up');
                    }
                  },
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFFEAF3),
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: const Color(0x33FF4FA3)),
                      ),
                      child: GridView.builder(
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: _size * _size,
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _size,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 8,
                        ),
                        itemBuilder: (context, index) {
                          final r = index ~/ _size;
                          final c = index % _size;
                          final value = _grid[r][c];
                          return AnimatedContainer(
                            duration: const Duration(milliseconds: 150),
                            decoration: BoxDecoration(
                              color: value == 0 ? Colors.white : _tileColor(value),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            alignment: Alignment.center,
                            child: value == 0
                                ? null
                                : Text(
                                    '$value',
                                    style: GoogleFonts.outfit(
                                      color: value <= 4 ? _navy : Colors.white,
                                      fontSize: value >= 1000 ? 20 : 24,
                                      fontWeight: FontWeight.w900,
                                    ),
                                  ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 14),
                Text(
                  _gameOver
                      ? 'Game over! Tap refresh to try again.'
                      : _won
                          ? 'You made 2048! Keep going for a higher score.'
                          : 'Swipe up/down/left/right to merge matching tiles.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    color: _gameOver ? const Color(0xFFE0245E) : _muted,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _scoreChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFEAF3),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0x33FF4FA3)),
      ),
      child: Column(
        children: [
          Text(label, style: GoogleFonts.outfit(color: _muted, fontSize: 11, fontWeight: FontWeight.w700)),
          Text(value, style: GoogleFonts.outfit(color: _pink, fontSize: 18, fontWeight: FontWeight.w900)),
        ],
      ),
    );
  }
}
