// ================================================================
// WhackAMoleScreen — timer-based reflex tap game with pop-up holes
// ================================================================
import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFFFFF6FA);
const Color _pink = Color(0xFFFF4FA3);
const Color _navy = Color(0xFF201A22);
const Color _muted = Color(0xFF8A4E72);
const int _gameSeconds = 30;
const int _holeCount = 9;

class WhackAMoleScreen extends StatefulWidget {
  const WhackAMoleScreen({super.key});

  @override
  State<WhackAMoleScreen> createState() => _WhackAMoleScreenState();
}

class _WhackAMoleScreenState extends State<WhackAMoleScreen> {
  final Random _random = Random();
  int _score = 0;
  int _best = 0;
  int _timeLeft = _gameSeconds;
  bool _running = false;
  Timer? _countdownTimer;
  Timer? _moleTimer;
  int _activeHole = -1;
  bool _whacked = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _moleTimer?.cancel();
    super.dispose();
  }

  void _startGame() {
    setState(() {
      _score = 0;
      _timeLeft = _gameSeconds;
      _running = true;
      _activeHole = -1;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _timeLeft--);
      if (_timeLeft <= 0) _endGame();
    });
    _scheduleNextMole();
  }

  void _endGame() {
    _countdownTimer?.cancel();
    _moleTimer?.cancel();
    setState(() {
      _running = false;
      _activeHole = -1;
      if (_score > _best) _best = _score;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showResultDialog());
  }

  void _scheduleNextMole() {
    if (!_running) return;
    _moleTimer?.cancel();
    _moleTimer = Timer(Duration(milliseconds: 400 + _random.nextInt(500)), () {
      if (!_running || !mounted) return;
      setState(() {
        _activeHole = _random.nextInt(_holeCount);
        _whacked = false;
      });
      Timer(const Duration(milliseconds: 800), () {
        if (!mounted) return;
        if (_activeHole != -1 && !_whacked) {
          setState(() => _activeHole = -1);
          _scheduleNextMole();
        }
      });
    });
  }

  void _onTapHole(int index) {
    if (!_running || index != _activeHole || _whacked) return;
    setState(() {
      _score++;
      _whacked = true;
      _activeHole = -1;
    });
    _scheduleNextMole();
  }

  void _showResultDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
        title: Text("Time's up!", style: GoogleFonts.outfit(fontWeight: FontWeight.w800, color: _navy)),
        content: Text('Score: $_score\nBest: $_best', style: GoogleFonts.outfit(color: _muted)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _pink, foregroundColor: Colors.white),
            onPressed: () {
              Navigator.pop(context);
              _startGame();
            },
            child: const Text('Play Again'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _navy),
        title: Text('Whack-a-Mole', style: GoogleFonts.outfit(color: _navy, fontWeight: FontWeight.w800)),
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _statChip('Score', '$_score'),
                  _statChip('Time', '$_timeLeft s'),
                  _statChip('Best', '$_best'),
                ],
              ),
              const SizedBox(height: 16),
              Expanded(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 380),
                    child: Stack(
                      alignment: Alignment.center,
                      children: [
                        GridView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _holeCount,
                          gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: 3,
                            crossAxisSpacing: 12,
                            mainAxisSpacing: 12,
                          ),
                          itemBuilder: (context, index) {
                            final isUp = index == _activeHole;
                            return GestureDetector(
                              onTap: () => _onTapHole(index),
                              child: Container(
                                decoration: BoxDecoration(
                                  color: const Color(0xFF3E2723),
                                  shape: BoxShape.circle,
                                  boxShadow: [
                                    BoxShadow(color: Colors.black.withValues(alpha: 0.15), blurRadius: 6, offset: const Offset(0, 3)),
                                  ],
                                ),
                                alignment: Alignment.center,
                                child: AnimatedScale(
                                  scale: isUp ? 1.0 : 0.0,
                                  duration: const Duration(milliseconds: 150),
                                  child: Container(
                                    width: 44,
                                    height: 44,
                                    decoration: const BoxDecoration(
                                      color: Color(0xFF8D6E63),
                                      shape: BoxShape.circle,
                                    ),
                                    child: const Icon(Icons.pest_control_rodent_rounded, color: Colors.white, size: 26),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                        if (!_running)
                          ColoredBox(
                            color: _bg.withValues(alpha: 0.9),
                            child: Center(
                              child: ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _pink,
                                  foregroundColor: Colors.white,
                                  padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                ),
                                onPressed: _startGame,
                                child: Text('Start', style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Tap the moles as soon as they pop up!',
                style: GoogleFonts.outfit(color: _muted, fontSize: 13, fontWeight: FontWeight.w600),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(String label, String value) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
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
