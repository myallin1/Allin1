import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../services/localization_service.dart';

class PlayZoneScreen extends StatefulWidget {
  const PlayZoneScreen({super.key});

  @override
  State<PlayZoneScreen> createState() => _PlayZoneScreenState();
}

class _PlayZoneScreenState extends State<PlayZoneScreen> {
  static const LinearGradient _brandGradient = LinearGradient(
    colors: <Color>[
      Color(0xFFFF4FA3),
      Color(0xFFFF73C0),
      Color(0xFFB21FFF),
    ],
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
  );

  final Random _random = Random();
  final List<int> _tiles = <int>[1, 2, 3, 4, 5, 6, 7, 8, 0];
  Timer? _timer;
  int _moves = 0;
  int _elapsedSeconds = 0;

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
    _timer?.cancel();
    setState(() {
      _moves = 0;
      _elapsedSeconds = 0;
      _tiles
        ..clear()
        ..addAll(_generateShuffledBoard());
    });
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!mounted) {
        return;
      }
      setState(() {
        _elapsedSeconds++;
      });
    });
  }

  List<int> _generateShuffledBoard() {
    final numbers = <int>[1, 2, 3, 4, 5, 6, 7, 8, 0];
    do {
      numbers.shuffle(_random);
    } while (!_isSolvable(numbers) || _isSolved(numbers));
    return List<int>.from(numbers);
  }

  bool _isSolvable(List<int> board) {
    var inversions = 0;
    for (var i = 0; i < board.length; i++) {
      for (var j = i + 1; j < board.length; j++) {
        if (board[i] != 0 && board[j] != 0 && board[i] > board[j]) {
          inversions++;
        }
      }
    }
    return inversions.isEven;
  }

  bool _isSolved(List<int> board) {
    for (var i = 0; i < 8; i++) {
      if (board[i] != i + 1) {
        return false;
      }
    }
    return board[8] == 0;
  }

  void _moveTile(int index) {
    final emptyIndex = _tiles.indexOf(0);
    if (!_isAdjacent(index, emptyIndex)) {
      return;
    }

    setState(() {
      final tapped = _tiles[index];
      _tiles[index] = 0;
      _tiles[emptyIndex] = tapped;
      _moves++;
    });

    if (_isSolved(_tiles)) {
      _timer?.cancel();
      unawaited(_showSolvedDialog());
    }
  }

  bool _isAdjacent(int first, int second) {
    final firstRow = first ~/ 3;
    final firstCol = first % 3;
    final secondRow = second ~/ 3;
    final secondCol = second % 3;
    return (firstRow == secondRow && (firstCol - secondCol).abs() == 1) ||
        (firstCol == secondCol && (firstRow - secondRow).abs() == 1);
  }

  Future<void> _showSolvedDialog() async {
    final localization = context.read<LocalizationService>();
    await showDialog<void>(
      context: context,
      builder: (context) {
        return AlertDialog(
          backgroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
            side: const BorderSide(color: Color(0x44FF4FA3)),
          ),
          title: Text(
            localization.t('solved_title'),
            style: GoogleFonts.notoSansTamil(
              color: const Color(0xFFFF4FA3),
              fontWeight: FontWeight.w800,
            ),
          ),
          content: Text(
            '${localization.t('solved_message_intro')} ✨\n'
            '${localization.t('time_label')}: $_elapsedSeconds s\n'
            '${localization.t('moves_label')}: $_moves',
            style: GoogleFonts.outfit(
              color: const Color(0xFF5A1740),
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          actions: <Widget>[
            ElevatedButton(
              onPressed: () {
                Navigator.of(context).pop();
                _startNewGame();
              },
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 18,
                  vertical: 12,
                ),
                backgroundColor: const Color(0xFFFF4FA3),
                foregroundColor: Colors.white,
              ),
              child: Text(localization.t('play_again_label')),
            ),
          ],
        );
      },
    );
  }

  String _formatTime(int seconds) {
    final mins = (seconds ~/ 60).toString().padLeft(2, '0');
    final secs = (seconds % 60).toString().padLeft(2, '0');
    return '$mins:$secs';
  }

  @override
  Widget build(BuildContext context) {
    final localization = context.watch<LocalizationService>();
    return ColoredBox(
      color: Colors.white,
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Column(
              children: <Widget>[
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    gradient: _brandGradient,
                    borderRadius: BorderRadius.circular(26),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFFFF4FA3).withValues(alpha: 0.18),
                        blurRadius: 18,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      Container(
                        width: 74,
                        height: 74,
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.18),
                          shape: BoxShape.circle,
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.7),
                            width: 1.2,
                          ),
                        ),
                        child: const Icon(
                          Icons.auto_awesome_rounded,
                          color: Colors.white,
                          size: 34,
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        'NJ TECH',
                        style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          letterSpacing: 1.6,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        localization.t('sliding_puzzle_title'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.notoSansTamil(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 14),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(24),
                    border: Border.all(color: const Color(0x55FF5CA8)),
                    boxShadow: <BoxShadow>[
                      BoxShadow(
                        color: const Color(0xFFFF4FA3).withValues(alpha: 0.08),
                        blurRadius: 16,
                        offset: const Offset(0, 8),
                      ),
                    ],
                  ),
                  child: Column(
                    children: <Widget>[
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: <Widget>[
                          _StatChip(
                            label: localization.t('moves_label'),
                            value: '$_moves',
                          ),
                          const SizedBox(width: 10),
                          _StatChip(
                            label: localization.t('time_label'),
                            value: _formatTime(_elapsedSeconds),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: 286,
                        height: 286,
                        child: GridView.builder(
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: 9,
                          gridDelegate:
                              const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 8,
                            mainAxisSpacing: 8,
                          ),
                          itemBuilder: (context, index) {
                            final tile = _tiles[index];
                            if (tile == 0) {
                              return Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3F9),
                                  borderRadius: BorderRadius.circular(18),
                                  border: Border.all(
                                    color: const Color(0x22FF4FA3),
                                  ),
                                ),
                              );
                            }

                            return GestureDetector(
                              onTap: () => _moveTile(index),
                              child: _PuzzleTile(
                                value: tile,
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 12),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _startNewGame,
                          icon: const Icon(Icons.refresh_rounded, size: 18),
                          label: Text(localization.t('reset_label')),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF4FA3),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 12,
                            ),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16),
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(height: 10),
                      Text(
                        localization.t('puzzle_instruction'),
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          color: const Color(0xFF8A4E72),
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatChip extends StatelessWidget {
  const _StatChip({
    required this.label,
    required this.value,
  });

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4FA),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0x44FF4FA3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          Text(
            label,
            style: GoogleFonts.outfit(
              color: const Color(0xFF8A4E72),
              fontSize: 11,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: GoogleFonts.outfit(
              color: const Color(0xFFFF4FA3),
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('label', label))
      ..add(StringProperty('value', value));
  }
}

class _PuzzleTile extends StatelessWidget {
  const _PuzzleTile({
    required this.value,
  });

  final int value;

  Alignment _alignmentFor(int index) {
    final row = (index - 1) ~/ 3;
    final column = (index - 1) % 3;
    return Alignment(
      -1 + column.toDouble(),
      -1 + row.toDouble(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final showLandmark = value.isEven;
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: const <Color>[
            Color(0xFFFF4FA3),
            Color(0xFFFF79C4),
            Color(0xFFB21FFF),
          ],
          begin: _alignmentFor(value),
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(18),
        border: Border.all(
          color: const Color(0x88FFFFFF),
          width: 1.4,
        ),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: const Color(0xFFFF4FA3).withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 6),
          ),
        ],
      ),
      child: Stack(
        children: <Widget>[
          Positioned.fill(
            child: DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: <Color>[
                    Colors.white.withValues(alpha: 0.18),
                    Colors.white.withValues(alpha: 0.02),
                  ],
                  begin: _alignmentFor(value),
                  end: Alignment.bottomRight,
                ),
              ),
              child: Stack(
                children: <Widget>[
                  Positioned(
                    left: -6 + ((value - 1) % 3) * 6,
                    top: 14 + ((value - 1) ~/ 3) * 6,
                    child: Icon(
                      showLandmark
                          ? Icons.account_balance_rounded
                          : Icons.auto_awesome_rounded,
                      color: Colors.white.withValues(alpha: 0.3),
                      size: showLandmark ? 36 : 30,
                    ),
                  ),
                  Positioned(
                    right: 8,
                    bottom: 10,
                    child: Container(
                      width: 18,
                      height: 18,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
          Positioned(
            top: 10,
            left: 10,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                showLandmark ? 'ERODE' : 'NJ',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 10,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 0.6,
                ),
              ),
            ),
          ),
          Positioned(
            right: 10,
            bottom: 8,
            child: Icon(
              showLandmark
                  ? Icons.location_city_rounded
                  : Icons.flash_on_rounded,
              color: Colors.white.withValues(alpha: 0.9),
              size: 18,
            ),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(IntProperty('value', value));
  }
}
