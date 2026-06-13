import 'package:flutter/material.dart';

import 'hero_history_screen.dart';
import 'hero_home_screen.dart';
import 'hero_profile_tab.dart';
import 'hero_sos_screen.dart';

class HeroDashboardShell extends StatefulWidget {
  const HeroDashboardShell({super.key});

  @override
  State<HeroDashboardShell> createState() => _HeroDashboardShellState();
}

class _HeroDashboardShellState extends State<HeroDashboardShell> {
  static const Color _bg = Color(0xFFFFFBFE);
  static const Color _surface = Colors.white;
  static const Color _cardTint = Color(0xFFFFF1F8);
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _pinkSoft = Color(0xFFFF9CCC);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _border = Color(0x33FF4FA3);

  int _tabIndex = 0;

  late final List<Widget> _tabs = <Widget>[
    const HeroHomeScreen(embedded: true),
    const HeroHistoryScreen(),
    const HeroProfileTab(),
    const HeroSosScreen(),
  ];

  Widget _inactiveIcon(IconData icon) {
    return Container(
      padding: const EdgeInsets.all(8),
      decoration: BoxDecoration(
        color: _cardTint,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: _border),
        boxShadow: const <BoxShadow>[
          BoxShadow(
            color: Color(0x10FF4FA3),
            blurRadius: 12,
            offset: Offset(0, 4),
          ),
        ],
      ),
      child: Icon(icon, color: _pink, size: 22),
    );
  }

  Widget _activeIcon(IconData icon) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: <Color>[_pink, _pinkSoft],
        ),
        borderRadius: BorderRadius.all(Radius.circular(14)),
        boxShadow: <BoxShadow>[
          BoxShadow(
            color: Color(0x2AFF4FA3),
            blurRadius: 18,
            offset: Offset(0, 6),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Icon(icon, color: Colors.white, size: 22),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: IndexedStack(
        index: _tabIndex,
        children: _tabs,
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(top: BorderSide(color: _border)),
          boxShadow: [
            BoxShadow(
              color: Color(0x12FF4FA3),
              blurRadius: 24,
              offset: Offset(0, -6),
            ),
          ],
        ),
        child: SafeArea(
          top: false,
          child: BottomNavigationBar(
            currentIndex: _tabIndex,
            onTap: (index) => setState(() => _tabIndex = index),
            backgroundColor: _surface,
            elevation: 0,
            type: BottomNavigationBarType.fixed,
            selectedItemColor: _pink,
            unselectedItemColor: _muted,
            selectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w800,
              fontSize: 12,
            ),
            unselectedLabelStyle: const TextStyle(
              fontWeight: FontWeight.w600,
              fontSize: 12,
            ),
            items: [
              BottomNavigationBarItem(
                icon: _inactiveIcon(Icons.radar_rounded),
                activeIcon: _activeIcon(Icons.radar_rounded),
                label: 'Radar',
              ),
              BottomNavigationBarItem(
                icon: _inactiveIcon(Icons.receipt_long_rounded),
                activeIcon: _activeIcon(Icons.receipt_long_rounded),
                label: 'Earnings',
              ),
              BottomNavigationBarItem(
                icon: _inactiveIcon(Icons.account_circle_outlined),
                activeIcon: _activeIcon(Icons.account_circle_rounded),
                label: 'Profile',
              ),
              BottomNavigationBarItem(
                icon: _inactiveIcon(Icons.emergency_rounded),
                activeIcon: _activeIcon(Icons.emergency_rounded),
                label: 'SOS',
              ),
            ],
          ),
        ),
      ),
    );
  }
}
