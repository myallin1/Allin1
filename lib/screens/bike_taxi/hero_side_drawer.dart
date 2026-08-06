// ================================================================
// hero_side_drawer.dart — Hero app's Side Tray
// ================================================================
// NEW (CTO mandate — Universal Side Tray Banner). The Hero app had no
// side drawer at all before this. Minimal, additive: a header, a
// Settings shortcut (existing HeroSettingsScreen already owns
// logout/account actions — not duplicated here), and the shared
// DownloadAppBanner for brand/PWA-promotion consistency with the
// other 3 apps. Opens via edge-swipe (Scaffold's default drawer
// gesture) since HeroDashboardShell has no AppBar/hamburger icon.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../../widgets/download_app_banner.dart';
import 'hero_settings_screen.dart';

class HeroSideDrawer extends StatelessWidget {
  const HeroSideDrawer({super.key});

  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _pinkDark = Color(0xFFBE2A7A);
  static const Color _text = Color(0xFF1A1A2E);
  static const Color _muted = Color(0xFF8F5A78);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_pink, _pinkDark],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.local_taxi_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : 'Hero',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  if (user?.phoneNumber != null)
                    Text(
                      user!.phoneNumber!,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            ListTile(
              leading: const Icon(Icons.settings_rounded, color: _pink),
              title: const Text('Settings', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(builder: (_) => const HeroSettingsScreen()),
                );
              },
            ),
            const Spacer(),
            const DownloadAppBanner(appVariant: 'hero'),
            Padding(
              padding: const EdgeInsets.all(20),
              child: Text(
                'v1.0.0',
                style: TextStyle(color: _muted.withValues(alpha: 0.6), fontSize: 12, letterSpacing: 0.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
