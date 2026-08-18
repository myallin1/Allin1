// ================================================================
// seller_side_drawer.dart — Seller app's Side Tray
// ================================================================
// NEW (CTO mandate — Universal Side Tray Banner). The Seller app had
// no side drawer before this. Minimal, additive: a header, a
// Settings shortcut (existing SellerSettingsScreen, already reachable
// from the AppBar — not duplicated logic, just a second entry point),
// and the shared DownloadAppBanner for brand/PWA-promotion consistency
// with the other 3 apps. Adding `drawer:` to SellerDashboardScreen's
// Scaffold makes Flutter auto-show the hamburger icon in its AppBar.
import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';

import '../models/food_models.dart';
import '../widgets/download_app_banner.dart';
import 'seller_settings_screen.dart';

class SellerSideDrawer extends StatelessWidget {
  final SellerModel? seller;
  
  const SellerSideDrawer({super.key, this.seller});

  static const Color _teal = Color(0xFF11998E);
  static const Color _tealLight = Color(0xFF38EF7D);
  static const Color _text = Color(0xFFEEEEF5);
  static const Color _muted = Color(0xFF7777A0);
  static const Color _bg = Color(0xFF0A0A1A);

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Drawer(
      backgroundColor: _bg,
      child: SafeArea(
        child: Column(
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 28, 20, 24),
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  colors: [_teal, _tealLight],
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
                    child: Icon(Icons.storefront_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    user?.displayName?.trim().isNotEmpty == true ? user!.displayName! : 'Seller',
                    style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800),
                  ),
                  if (user?.email != null)
                    Text(
                      user!.email!,
                      style: const TextStyle(color: Colors.white70, fontSize: 12),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            if (seller?.role != 'staff')
              ListTile(
                leading: const Icon(Icons.settings_rounded, color: _teal),
                title: const Text('Settings', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      settings: const RouteSettings(name: '/seller/SellerSettingsScreen'),
                      builder: (_) => const SellerSettingsScreen(),
                    ),
                  );
                },
              ),
            const Spacer(),
            const DownloadAppBanner(appVariant: 'seller'),
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
