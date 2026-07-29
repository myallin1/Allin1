// ================================================================
// CoinTapScreen — timer-based reflex tap game
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
const int _gameSeconds = 30;

class CoinTapScreen extends StatefulWidget {
  const CoinTapScreen({super.key});

  @override
  State<CoinTapScreen> createState() => _CoinTapScreenState();
}

class _CoinTapScreenState extends State<CoinTapScreen> {
  final Random _random = Random();
  int _score = 0;
  int _best = 0;
  int _timeLeft = _gameSeconds;
  bool _running = false;
  Timer? _countdownTimer;
  Timer? _spawnTimer;
  double _coinX = 0.5;
  double _coinY = 0.5;
  bool _coinVisible = false;
  bool _isBomb = false;

  @override
  void dispose() {
    _countdownTimer?.cancel();
    _spawnTimer?.cancel();
    super.dispose();
  }

  void _startGame() {
    setState(() {
      _score = 0;
      _timeLeft = _gameSeconds;
      _running = true;
      _coinVisible = false;
    });
    _countdownTimer?.cancel();
    _countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() => _timeLeft--);
      if (_timeLeft <= 0) {
        _endGame();
      }
    });
    _scheduleNextCoin();
  }

  void _endGame() {
    _countdownTimer?.cancel();
    _spawnTimer?.cancel();
    setState(() {
      _running = false;
      _coinVisible = false;
      if (_score > _best) _best = _score;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _showResultDialog());
  }

  void _scheduleNextCoin() {
    if (!_running) return;
    _spawnTimer?.cancel();
    _spawnTimer = Timer(Duration(milliseconds: 500 + _random.nextInt(500)), () {
      if (!_running || !mounted) return;
      setState(() {
        _coinX = 0.1 + _random.nextDouble() * 0.8;
        _coinY = 0.1 + _random.nextDouble() * 0.8;
        _isBomb = _random.nextDouble() < 0.2;
        _coinVisible = true;
      });
      Timer(const Duration(milliseconds: 900), () {
        if (!mounted) return;
        if (_coinVisible) {
          setState(() => _coinVisible = false);
          _scheduleNextCoin();
        }
      });
    });
  }

  void _onTapCoin() {
    if (!_running || !_coinVisible) return;
    setState(() {
      _score += _isBomb ? -3 : 1;
      if (_score < 0) _score = 0;
      _coinVisible = false;
    });
    _scheduleNextCoin();
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
        title: Text('Coin Tap', style: GoogleFonts.outfit(color: _navy, fontWeight: FontWeight.w800)),
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
              const SizedBox(height: 14),
              Expanded(
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFEAF3),
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: const Color(0x33FF4FA3)),
                  ),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        children: [
                          if (!_running)
                            Center(
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
                          if (_running && _coinVisible)
                            Positioned(
                              left: _coinX * (constraints.maxWidth - 60),
                              top: _coinY * (constraints.maxHeight - 60),
                              child: GestureDetector(
                                onTap: _onTapCoin,
                                child: Container(
                                  width: 60,
                                  height: 60,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    gradient: LinearGradient(
                                      colors: _isBomb
                                          ? [const Color(0xFF444444), const Color(0xFF111111)]
                                          : [const Color(0xFFFFD700), const Color(0xFFFFA500)],
                                    ),
                                    boxShadow: [
                                      BoxShadow(color: Colors.black.withOpacity(0.2), blurRadius: 8, offset: const Offset(0, 4)),
                                    ],
                                  ),
                                  child: Icon(
                                    _isBomb ? Icons.dangerous_rounded : Icons.paid_rounded,
                                    color: Colors.white,
                                    size: 30,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                'Tap gold coins fast, avoid the black bombs!',
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
