// ================================================================
// PlayZoneScreen — Game Zone hub (redesigned)
// ================================================================
// Replaced the old single sliding-number-puzzle game per Nizam's
// request ("game zone game romba mokkaya iruku") with a hub of 4
// selectable games: 2048, Memory Match, Coin Tap, Whack-a-Mole.
// Class name kept unchanged (PlayZoneScreen) so dashboard_screen.dart
// does not need to be touched — it still just does
// `const PlayZoneScreen()`.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'games/game_2048_screen.dart';
import 'games/memory_match_screen.dart';
import 'games/coin_tap_screen.dart';
import 'games/whack_a_mole_screen.dart';

const Color _bg = Color(0xFFFFF6FA);
const Color _pink = Color(0xFFFF4FA3);
const Color _purple = Color(0xFFB21FFF);
const Color _navy = Color(0xFF201A22);
const Color _muted = Color(0xFF8A4E72);

class PlayZoneScreen extends StatelessWidget {
  const PlayZoneScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final games = <_GameInfo>[
      _GameInfo(
        title: '2048',
        subtitle: 'Merge tiles to reach 2048',
        icon: Icons.grid_view_rounded,
        colors: const [Color(0xFFFF4FA3), Color(0xFFB21FFF)],
        builder: (context) => const Game2048Screen(),
      ),
      _GameInfo(
        title: 'Memory Match',
        subtitle: 'Find all the matching pairs',
        icon: Icons.style_rounded,
        colors: const [Color(0xFFFF7BAC), Color(0xFF9C4FE0)],
        builder: (context) => const MemoryMatchScreen(),
      ),
      _GameInfo(
        title: 'Coin Tap',
        subtitle: 'Tap coins fast, dodge bombs',
        icon: Icons.paid_rounded,
        colors: const [Color(0xFFFFA34F), Color(0xFFFF4FA3)],
        builder: (context) => const CoinTapScreen(),
      ),
      _GameInfo(
        title: 'Whack-a-Mole',
        subtitle: 'Whack moles before they hide',
        icon: Icons.pest_control_rodent_rounded,
        colors: const [Color(0xFF8D6E63), Color(0xFFB21FFF)],
        builder: (context) => const WhackAMoleScreen(),
      ),
    ];

    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(colors: [_pink, _purple]),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NJ TECH',
                        style: GoogleFonts.outfit(
                            color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 12, letterSpacing: 1.2)),
                    const SizedBox(height: 4),
                    Text('Game Zone',
                        style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 26)),
                    const SizedBox(height: 6),
                    Text('Pick a game and have some fun!',
                        style: GoogleFonts.outfit(color: Colors.white.withOpacity(0.9), fontSize: 13, fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: games.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.95,
                ),
                itemBuilder: (context, index) {
                  final game = games[index];
                  return _GameTile(game: game);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GameInfo {
  final String title;
  final String subtitle;
  final IconData icon;
  final List<Color> colors;
  final WidgetBuilder builder;

  _GameInfo({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.colors,
    required this.builder,
  });
}

class _GameTile extends StatelessWidget {
  final _GameInfo game;

  const _GameTile({required this.game});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => Navigator.push(context, MaterialPageRoute(builder: game.builder)),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: const Color(0x22B21FFF)),
          boxShadow: [
            BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(colors: game.colors),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(game.icon, color: Colors.white, size: 28),
            ),
            const Spacer(),
            Text(game.title, style: GoogleFonts.outfit(color: _navy, fontWeight: FontWeight.w800, fontSize: 16)),
            const SizedBox(height: 4),
            Text(
              game.subtitle,
              style: GoogleFonts.outfit(color: _muted, fontSize: 11.5, fontWeight: FontWeight.w600),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );
  }
}
