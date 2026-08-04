import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

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

  // FIX (unwanted-read audit, per Nizam's request): IndexedStack builds
  // AND MOUNTS every child immediately on first frame regardless of
  // which tab is active — History/Profile/SOS were all starting their
  // own Firestore listeners the instant the Hero app opened, even
  // though a hero almost always lands on Radar (tab 0) first and may
  // never tap the other 3 tabs in that session. Same root cause and
  // same fix already applied to SuperAdminHomeScreen's Hero/Electronics
  // tabs: only put the REAL widget in a slot once that tab has actually
  // been visited; unvisited slots get a cheap placeholder. Once
  // visited, IndexedStack keeps the real widget mounted for the rest of
  // the screen's life, so switching back after the first visit is still
  // instant with no re-listen.
  final Set<int> _visitedTabs = {0};

  static const List<Widget> _placeholder = [SizedBox.shrink()];

  void _goToTab(int index) {
    setState(() {
      _tabIndex = index;
      _visitedTabs.add(index);
    });
  }

  List<Widget> get _tabs => <Widget>[
        const HeroHomeScreen(embedded: true),
        if (_visitedTabs.contains(1)) const HeroHistoryScreen() else _placeholder.first,
        if (_visitedTabs.contains(2)) const HeroProfileTab() else _placeholder.first,
        if (_visitedTabs.contains(3)) const HeroSosScreen() else _placeholder.first,
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

  // FIX (back-button audit, per Nizam's request): this shell had zero
  // back-press handling — unlike dashboard_screen.dart (customer app),
  // which already traps back to reset to tab 0 first / confirm-exit on
  // tab 0. Without this, pressing back (hardware button or the browser's
  // back button on the PWA) while on any tab hit Navigator.canPop()==
  // false at the root and fell straight through to the OS/browser's
  // default action — the app just closed instantly, no step-by-step
  // "go back to previous tab" behavior a hero would expect. Mirrors the
  // exact same pattern for consistency across apps.
  Future<bool> _handleBackPress() async {
    if (_tabIndex != 0) {
      _goToTab(0);
      return false;
    }
    final exit = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Leave the app?',
            style: TextStyle(fontWeight: FontWeight.w700),),
        content: const Text('Close Allin1 Hero?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('No', style: TextStyle(color: _pink)),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Yes', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
    return exit ?? false;
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        final shouldExit = await _handleBackPress();
        if (shouldExit && context.mounted) SystemNavigator.pop();
      },
      child: Scaffold(
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
            onTap: _goToTab,
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
      ),
    );
  }
}
