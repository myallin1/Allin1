import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../../services/app_minimizer_service.dart';
import 'hero_history_screen.dart';
import 'hero_home_screen.dart';
import 'hero_side_drawer.dart';
import 'hero_sos_screen.dart';
import 'hero_wallet_screen.dart';

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

  // FIX (per Nizam's request — "hero profile options yellathayum side
  // tray kulla kondu poiru, wallet button ah profile 3rd place la
  // replace pannu"): tab slot 2 used to be HeroProfileTab (settings,
  // help, logout, etc.) — all of that moved into HeroSideDrawer. This
  // slot is now Hero Wallet directly.
  List<Widget> get _tabs => <Widget>[
        const HeroHomeScreen(embedded: true),
        if (_visitedTabs.contains(1)) const HeroHistoryScreen() else _placeholder.first,
        if (_visitedTabs.contains(2)) const HeroWalletScreen() else _placeholder.first,
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

  // FIX (Aug 12 2026 — CTO mandate: "System Back Button Overhaul"): this
  // used to show a Yes/No "leave the app?" dialog and call
  // SystemNavigator.pop() on Yes, which FINISHES the Activity (a real
  // close) — exactly the "app terminates / blank on PWA / full cold-boot
  // rebuild on reopen" bug this feature fixes. Minimizing is safe and
  // fully reversible, so it no longer needs a confirmation dialog at
  // all. Tab-reset-first behavior (back on a non-Radar tab returns to
  // Radar before anything else) is unchanged.
  void _handleBackPress() {
    if (_tabIndex != 0) {
      _goToTab(0);
      return;
    }
    if (kIsWeb) {
      // A browser tab cannot minimize itself to the OS home screen — no
      // such API exists. Show the "use your device's Home button" hint
      // once per session, then silently swallow further back-presses.
      if (AppMinimizer.consumeWebHintOnce()) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Press your device's Home button to minimize"),
            duration: Duration(seconds: 3),
          ),
        );
      }
      return;
    }
    unawaited(AppMinimizer.moveToBackground());
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        _handleBackPress();
      },
      child: Scaffold(
      backgroundColor: _bg,
      // NEW (CTO mandate — Universal Side Tray Banner): Hero app had no
      // drawer at all before this.
      drawer: const HeroSideDrawer(),
      body: Stack(
        children: [
          IndexedStack(
            index: _tabIndex,
            children: _tabs,
          ),
          // FIX (per Nizam's report — "hamburger tray... ila", drawer
          // was edge-swipe-only since this shell has no AppBar to host
          // Flutter's automatic hamburger icon): a visible floating
          // menu button, top-left, safe-area aware, opens the same
          // HeroSideDrawer (which carries the "Download App 10x
          // faster" banner) on every tab.
          Positioned(
            top: 0,
            left: 0,
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Builder(
                  builder: (context) => Material(
                    color: _surface,
                    shape: const CircleBorder(),
                    elevation: 4,
                    shadowColor: const Color(0x33FF4FA3),
                    child: InkWell(
                      customBorder: const CircleBorder(),
                      onTap: () => Scaffold.of(context).openDrawer(),
                      child: Padding(
                        padding: const EdgeInsets.all(10),
                        child: Icon(Icons.menu_rounded, color: _pink, size: 24),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
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
                icon: _inactiveIcon(Icons.account_balance_wallet_outlined),
                activeIcon: _activeIcon(Icons.account_balance_wallet_rounded),
                label: 'Wallet',
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
