// ================================================================
// hero_side_drawer.dart — Hero app's Side Tray
// ================================================================
// UPDATED (per Nizam's request — "hero profile la irukka options
// yellathayum side tray kulla kondu poiru"): every action that used to
// live inside HeroProfileTab (Settings, Help & Support, Check for
// Updates, Download App, Logout/Go Offline) now lives here instead —
// the bottom nav's old "Profile" tab slot is now Hero Wallet (see
// hero_dashboard_shell.dart). Converted from Stateless to Stateful so
// the header can show the hero's live name/phone/status/coins, same
// data HeroProfileTab used to load, instead of just FirebaseAuth's
// bare displayName/phoneNumber.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/pwa_cache_platform_stub.dart'
    if (dart.library.html) '../../services/pwa_cache_platform_web.dart';
import '../../services/update_service.dart';
import '../../services/web_version_checker.dart';
import '../../widgets/download_app_banner.dart';
import 'hero_earnings_screen.dart';
import 'hero_incomplete_tasks_screen.dart';
import 'hero_settings_screen.dart';
import '../invite_friends_screen.dart';

class HeroSideDrawer extends StatefulWidget {
  const HeroSideDrawer({super.key});

  @override
  State<HeroSideDrawer> createState() => _HeroSideDrawerState();
}

class _HeroSideDrawerState extends State<HeroSideDrawer> {
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _pinkSoft = Color(0xFFFF9CCC);
  static const Color _pinkDark = Color(0xFFBE2A7A);
  static const Color _text = Color(0xFF1A1A2E);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _red = Color(0xFFFF5252);

  String _status = 'offline';
  int _heroCoins = 0;
  bool _loggingOut = false;

  @override
  void initState() {
    super.initState();
    unawaited(_hydrate(Source.cache));
    unawaited(_hydrate(Source.server));
  }

  Future<void> _hydrate(Source source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(user.uid)
          .get(GetOptions(source: source));
      if (!mounted) return;
      final data = snap.data() ?? <String, dynamic>{};
      setState(() {
        _status = (data['status'] as String? ?? _status).trim();
        _heroCoins = (data['hero_coins'] as int?) ?? _heroCoins;
      });
    } catch (_) {
      // Silent — this is a secondary display, not a gate.
    }
  }

  Future<void> _openSettings() async {
    Navigator.pop(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/hero/HeroSettingsScreen'),
        builder: (_) => const HeroSettingsScreen(),
      ),
    );
  }

  Future<void> _openHelpSupport() async {
    Navigator.pop(context);
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        settings: const RouteSettings(name: '/hero/_HeroHelpSupportScreen'),
        builder: (_) => const _HeroHelpSupportScreen(),
      ),
    );
  }

  // FIX (per Nizam's recurring bug report — Hero "Check for Updates"
  // still ended up downloading/updating a different app): see the
  // matching FIX comment on HeroProfileTab._openHeroUpdateUrl in
  // hero_profile_tab.dart for the full root-cause writeup. Short
  // version: this used to unconditionally launchUrl() the Hero APK
  // link even when running as the Hero PWA on web, instead of using
  // the same self-referential /version.json check (WebVersionChecker)
  // that Customer's and Admin's "Check for Updates" buttons already
  // use. Now identical to that pattern: web self-checks and reloads
  // in place; native falls back to the GitHub APK link for 'hero'.
  Future<void> _openHeroUpdateUrl() async {
    final messenger = ScaffoldMessenger.of(context);

    if (kIsWeb) {
      await WebVersionChecker.instance.checkNow();
      if (!mounted) return;

      if (!WebVersionChecker.instance.isUpdateAvailable) {
        messenger.showSnackBar(
          const SnackBar(
            content: Text('You already have the latest version.'),
            backgroundColor: _pink,
            behavior: SnackBarBehavior.floating,
          ),
        );
        return;
      }

      messenger.showSnackBar(
        const SnackBar(
          content: Text('Updating…'),
          backgroundColor: _pink,
          behavior: SnackBarBehavior.floating,
        ),
      );
      try {
        await PwaCachePlatform().clearAndReload();
      } catch (e) {
        debugPrint('[HeroCheckUpdate] cache clear failed: $e');
      }
      return;
    }

    final launched = await launchUrl(
      Uri.parse(UpdateService().fallbackApkUrl('hero')),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to open the update link right now.'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  Future<void> _callSoundboxOffer() async {
    final launched = await launchUrl(Uri.parse('tel:+919597879191'));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          launched
              ? 'Calling NJ Tech... Claim your FREE Paytm Soundbox offer.'
              : 'Unable to open dialer right now.',
        ),
        backgroundColor: launched ? _pink : _red,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  Future<void> _logoutAndGoOffline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _loggingOut) return;
    setState(() => _loggingOut = true);
    try {
      await FirebaseFirestore.instance.collection('heroes').doc(user.uid).set({
        'activeRideId': null,
        'lastUpdated': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true),);
      await FirebaseDatabase.instance.ref('online_heroes/${user.uid}').remove();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Logout failed: $e'),
          backgroundColor: _red,
          behavior: SnackBarBehavior.floating,
        ),
      );
      setState(() => _loggingOut = false);
      return;
    }
    if (mounted) {
      Navigator.pop(context);
      setState(() => _loggingOut = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final rupeesValue = _heroCoins / 100.0;
    return Drawer(
      child: SafeArea(
        child: ListView(
          padding: EdgeInsets.zero,
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
              child: Row(
                children: [
                  const CircleAvatar(
                    radius: 28,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.local_taxi_rounded, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          user?.displayName?.trim().isNotEmpty == true
                              ? user!.displayName!
                              : 'Hero',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 17, fontWeight: FontWeight.w800,),
                          overflow: TextOverflow.ellipsis,
                        ),
                        if (user?.phoneNumber != null)
                          Text(
                            user!.phoneNumber!,
                            style: const TextStyle(color: Colors.white70, fontSize: 12),
                          ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.white.withValues(alpha: 0.18),
                            borderRadius: BorderRadius.circular(999),
                            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
                          ),
                          child: Text(
                            _status.toUpperCase(),
                            style: GoogleFonts.outfit(
                              fontSize: 9, color: Colors.white, fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 4),
            // Hero Coins tile — FIX (per Nizam's "dummy items" report):
            // this used to be a dead, non-tappable card with an "Earn
            // more →" label that went nowhere. Now it actually opens
            // Help & Support (where coin-earning promos are explained)
            // instead of dangling.
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Material(
                color: const Color(0xFF10102A),
                borderRadius: BorderRadius.circular(14),
                child: InkWell(
                  borderRadius: BorderRadius.circular(14),
                  onTap: _openHelpSupport,
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    child: Row(
                      children: [
                        const Text('🪙', style: TextStyle(fontSize: 18)),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Hero Coins: $_heroCoins',
                                style: const TextStyle(
                                  fontSize: 12, color: Color(0xFFEEEEF5), fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '= Rs.${rupeesValue.toStringAsFixed(2)}',
                                style: const TextStyle(
                                  fontSize: 10, color: Color(0xFF6C63FF), fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const Text('Earn more →',
                            style: TextStyle(fontSize: 9, color: Color(0xFF7777A0)),),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            GestureDetector(
              onTap: _callSoundboxOffer,
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_pink, _pinkSoft],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Row(
                  children: [
                    const Text('🎁', style: TextStyle(fontSize: 20)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Claim FREE Paytm Soundbox!',
                        style: GoogleFonts.outfit(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                    const Icon(Icons.phone_in_talk_rounded, color: Colors.white, size: 16),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            ListTile(
              leading: const Icon(Icons.settings_rounded, color: _pink),
              title: const Text('Settings', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              onTap: _openSettings,
            ),
            ListTile(
              leading: const Icon(Icons.support_agent_rounded, color: _pink),
              title: const Text('Help & Support', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              onTap: _openHelpSupport,
            ),
            // NEW (Aug 11 2026 — Recovery System): escape hatch for the
            // "hero already on a service request" stuck-ping bug — a
            // hero can reach a task assigned to them (however old/stuck)
            // and either Resume it or Release it back to admin, freeing
            // themselves up for new pings without waiting on any
            // automatic timeout.
            ListTile(
              leading: const Icon(Icons.build_circle_rounded, color: _pink),
              title: const Text('Incomplete / Stuck Tasks', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/hero/HeroIncompleteTasksScreen'),
                    builder: (_) => const HeroIncompleteTasksScreen(),
                  ),
                );
              },
            ),
            // NEW (Aug 11 2026 — Business Analytics & Dynamic Billing
            // Upgrade, Tasks 4/5): hero-facing Earnings + Online Time
            // monitor. Fetch-on-demand + Hive cached, same architecture
            // as the admin analytics screens — never a live listener.
            ListTile(
              leading: const Icon(Icons.bar_chart_rounded, color: _pink),
              title: const Text('Earnings & Online Time', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    settings: const RouteSettings(name: '/hero/HeroEarningsScreen'),
                    builder: (_) => const HeroEarningsScreen(),
                  ),
                );
              },
            ),
            // NEW (Aug 17 2026 — Nizam: "heros avanga innoru heros ah
            // refer panna antha particular hero app la irunthu hero
            // referral qr and link generation").
            //
            // Reuses the customer InviteFriendsScreen in hero mode
            // rather than a second copied screen — same QR, WhatsApp
            // share, copy-link and invite count, but a hero-referral
            // code pointing at the HERO app and a recruitment pitch
            // instead of a "try this app" pitch.
            ListTile(
              leading: const Icon(Icons.group_add_rounded, color: _pink),
              title: const Text('Refer a Hero',
                  style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              subtitle: const Text('Share your QR / link and grow the team',
                  style: TextStyle(color: _muted, fontSize: 11)),
              onTap: () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute<void>(
                    settings:
                        const RouteSettings(name: '/hero/HeroInviteScreen'),
                    builder: (_) => const InviteFriendsScreen(
                      mode: InviteMode.hero,
                    ),
                  ),
                );
              },
            ),
            ListTile(
              leading: const Icon(Icons.update_rounded, color: Color(0xFF6C63FF)),
              title: const Text('Check for Updates', style: TextStyle(color: _text, fontWeight: FontWeight.w600)),
              onTap: () {
                Navigator.pop(context);
                unawaited(_openHeroUpdateUrl());
              },
            ),
            ListTile(
              leading: _loggingOut
                  ? const SizedBox(
                      width: 20, height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2, color: _red),
                    )
                  : const Icon(Icons.logout_rounded, color: _red),
              title: Text(
                _loggingOut ? 'Going Offline...' : 'Logout / Go Offline',
                style: const TextStyle(color: _red, fontWeight: FontWeight.w600),
              ),
              onTap: _loggingOut ? null : _logoutAndGoOffline,
            ),
            const SizedBox(height: 12),
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

class _HeroHelpSupportScreen extends StatelessWidget {
  const _HeroHelpSupportScreen();

  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _green = Color(0xFF10B759);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);

  Future<void> _launchSupport(BuildContext context, Uri uri) async {
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to open support right now.'),
          backgroundColor: Color(0xFFFF5252),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFBFE),
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _text,
        title: Text(
          'Hero Help & Support',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w900),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(18),
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_pink, Color(0xFFFF9CCC)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(24),
                boxShadow: const [
                  BoxShadow(color: Color(0x24FF4FA3), blurRadius: 22, offset: Offset(0, 10)),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(Icons.health_and_safety_rounded, color: Colors.white, size: 42),
                  const SizedBox(height: 14),
                  Text(
                    'NJ Tech Hero Support',
                    style: GoogleFonts.outfit(color: Colors.white, fontSize: 24, fontWeight: FontWeight.w900),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Need help during live testing? Contact our team instantly.',
                    style: GoogleFonts.outfit(color: Colors.white.withValues(alpha: 0.92), fontWeight: FontWeight.w700),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _SupportButton(
              icon: Icons.chat_rounded,
              title: 'WhatsApp Support',
              subtitle: 'Message NJ Tech Hero support',
              color: _green,
              onTap: () => _launchSupport(context, Uri.parse('https://wa.me/918681869091')),
            ),
            const SizedBox(height: 12),
            _SupportButton(
              icon: Icons.phone_in_talk_rounded,
              title: 'Call for Help',
              subtitle: 'Dial 8681869091',
              color: _pink,
              onTap: () => _launchSupport(context, Uri.parse('tel:8681869091')),
            ),
            const SizedBox(height: 16),
            Text(
              'We are monitoring the Erode live test. Stay online only when ready to accept rides.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted, fontSize: 12, fontWeight: FontWeight.w700),
            ),
          ],
        ),
      ),
    );
  }
}

class _SupportButton extends StatelessWidget {
  const _SupportButton({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(20),
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: color.withValues(alpha: 0.22)),
            boxShadow: const [
              BoxShadow(color: Color(0x12FF4FA3), blurRadius: 18, offset: Offset(0, 8)),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(color: color.withValues(alpha: 0.12), borderRadius: BorderRadius.circular(16)),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.outfit(color: _HeroHelpSupportScreen._text, fontSize: 16, fontWeight: FontWeight.w900)),
                    Text(subtitle, style: GoogleFonts.outfit(color: _HeroHelpSupportScreen._muted, fontSize: 12, fontWeight: FontWeight.w700)),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: color, size: 16),
            ],
          ),
        ),
      ),
    );
  }
}
