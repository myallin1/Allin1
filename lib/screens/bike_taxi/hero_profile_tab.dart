import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/update_service.dart';
import '../../widgets/hero_premium_loader.dart';
import 'hero_settings_screen.dart';

class HeroProfileTab extends StatefulWidget {
  const HeroProfileTab({super.key});

  @override
  State<HeroProfileTab> createState() => _HeroProfileTabState();
}

class _HeroProfileTabState extends State<HeroProfileTab>
    with AutomaticKeepAliveClientMixin {
  static const Color _bg = Color(0xFFFFFBFE);
  static const Color _surface = Colors.white;
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _pinkSoft = Color(0xFFFF9CCC);
  static const Color _red = Color(0xFFFF5252);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _border = Color(0x33FF4FA3);

  bool _loading = true;
  bool _loggingOut = false;
  String _displayName = 'Hero Rider';
  String _phone = 'Not provided';
  String _status = 'offline';
  double _walletBalance = 0;
  int _heroCoins = 0;
  double _heroRating = 0;

  // T2: Earnings & Ratings Dashboard state

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadProfile());
  }

  Future<void> _loadProfile() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (!mounted) {
        return;
      }
      setState(() => _loading = false);
      return;
    }
    _displayName = user.displayName?.trim().isNotEmpty ?? false
        ? user.displayName!.trim()
        : (user.email?.split('@').first ?? 'Hero Rider');
    _phone = user.phoneNumber?.trim().isNotEmpty ?? false
        ? user.phoneNumber!.trim()
        : (user.email ?? 'Not provided');
    await _hydrateFromSource(Source.cache);
    unawaited(_hydrateFromSource(Source.server));
  }

  Future<void> _hydrateFromSource(Source source) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return;
    }
    try {
      final heroSnap = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(user.uid)
          .get(GetOptions(source: source));
      if (!mounted) {
        return;
      }
      final heroData = heroSnap.data() ?? <String, dynamic>{};
      setState(() {
        _status = (heroData['status'] as String? ?? _status).trim();
        _walletBalance =
            (heroData['walletBalance'] as num?)?.toDouble() ?? _walletBalance;
        _heroCoins = (heroData['hero_coins'] as int?) ?? _heroCoins;
        _heroRating =
            (heroData['heroRating'] as num?)?.toDouble() ?? _heroRating;
        final heroPhone = (heroData['phoneNumber'] as String?)?.trim();
        if (heroPhone != null && heroPhone.isNotEmpty) {
          _phone = heroPhone;
        }
        final heroName = (heroData['name'] as String?)?.trim();
        if (heroName != null && heroName.isNotEmpty) {
          _displayName = heroName;
        }
        _loading = false;
      });
    } catch (_) {
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // T2: REMOVED — aggregated earnings/rides now fetched from heroes/{uid}
  // in HeroHistoryScreen._loadAggregates() to avoid N+1 ride doc iterations.

  Future<void> _logoutAndGoOffline() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || _loggingOut) {
      return;
    }
    setState(() => _loggingOut = true);
    try {
      await FirebaseFirestore.instance.collection('heroes').doc(user.uid).set(
        {
          'isOnline': false,
          'status': 'offline',
          'activeRideId': null,
          'lastUpdated': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      await FirebaseDatabase.instance.ref('online_heroes/${user.uid}').remove();
      await FirebaseAuth.instance.signOut();
    } catch (e) {
      if (!mounted) {
        return;
      }
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
      setState(() => _loggingOut = false);
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const HeroSettingsScreen(),
      ),
    );
  }

  Future<void> _openHelpSupport() async {
    await Navigator.of(context).push(
      MaterialPageRoute<void>(
        builder: (_) => const _HeroHelpSupportScreen(),
      ),
    );
  }

  Future<void> _openHeroUpdateUrl() async {
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      Uri.parse(UpdateService().fallbackApkUrl('hero')),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to open the update link right now.'),
          backgroundColor: Color(0xFFFF5252),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  // T2: Direct APK download — CEO drops hero_app.apk into Firebase hosting
  // and runs `firebase deploy`. This URL auto-serves the latest build.
  Future<void> _downloadHeroApp() async {
    const apkUrl = 'https://my-allin1.web.app/hero_app.apk';
    final messenger = ScaffoldMessenger.of(context);
    final launched = await launchUrl(
      Uri.parse(apkUrl),
      mode: LaunchMode.externalApplication,
    );
    if (!launched && mounted) {
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Unable to start download. Try again later.'),
          backgroundColor: Color(0xFFFF5252),
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ColoredBox(
      color: _bg,
      child: SafeArea(
        child: _loading
            ? const HeroPremiumLoader(
                compact: true,
                title: 'Loading Hero Profile',
                subtitle: 'Fetching your stats, wallet, and premium controls',
                icon: Icons.account_circle_rounded,
              )
            : ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                children: [
                  _buildHeroCard(),
                  const SizedBox(height: 16),
                  _buildHeroCoinsTile(),
                  const SizedBox(height: 12),
                  _buildSoundboxBanner(),
                  const SizedBox(height: 16),
                  Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _surface,
                      borderRadius: BorderRadius.circular(22),
                      border: Border.all(color: _border),
                      boxShadow: const [
                        BoxShadow(
                          color: Color(0x12FF4FA3),
                          blurRadius: 18,
                          offset: Offset(0, 8),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hero Actions',
                          style: GoogleFonts.outfit(
                            fontSize: 14,
                            color: _text,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Use this to safely go offline and sign out from the Hero app.',
                          style: GoogleFonts.outfit(
                            fontSize: 10,
                            color: _muted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 12),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _openSettings,
                            icon: const Icon(Icons.settings_rounded),
                            label: Text(
                              'Hero Settings',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _pink,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _openHelpSupport,
                            icon: const Icon(Icons.support_agent_rounded),
                            label: Text(
                              'Help & Support',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFF6C63FF),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _openHeroUpdateUrl,
                            icon: const Icon(Icons.update_rounded),
                            label: Text(
                              'Check for Updates',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        // T2: Direct APK download tile
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: const Color(0xFFFF4FA3),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                              elevation: 4,
                              shadowColor: const Color(0xFFFF4FA3)
                                  .withValues(alpha: 0.4),
                            ),
                            onPressed: _downloadHeroApp,
                            icon: const Icon(Icons.download_rounded, size: 18),
                            label: Text(
                              'Download Latest App',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          width: double.infinity,
                          child: ElevatedButton.icon(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: _red,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(16),
                              ),
                            ),
                            onPressed: _loggingOut ? null : _logoutAndGoOffline,
                            icon: _loggingOut
                                ? const SizedBox(
                                    width: 18,
                                    height: 18,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(Icons.logout_rounded),
                            label: Text(
                              _loggingOut
                                  ? 'Going Offline...'
                                  : 'Logout / Go Offline',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
      ),
    );
  }

  // T2: REMOVED — _buildEarningsDashboard and _statPill moved to HeroHistoryScreen

  Widget _buildHeroCoinsTile() {
    final double rupeesValue = _heroCoins / 100.0;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF10102A),
        borderRadius: BorderRadius.circular(14),
        border:
            Border.all(color: const Color(0xFF6C63FF).withValues(alpha: 0.3)),
      ),
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
                    fontSize: 12,
                    color: Color(0xFFEEEEF5),
                    fontWeight: FontWeight.w700,
                  ),
                ),
                Text(
                  '= Rs.${rupeesValue.toStringAsFixed(2)}',
                  style: const TextStyle(
                    fontSize: 10,
                    color: Color(0xFF6C63FF),
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
          const Text(
            'Earn more →',
            style: TextStyle(fontSize: 9, color: Color(0xFF7777A0)),
          ),
        ],
      ),
    );
  }

  Widget _buildSoundboxBanner() {
    return GestureDetector(
      onTap: () async {
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
      },
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_pink, _pinkSoft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
          boxShadow: const [
            BoxShadow(
              color: Color(0x20FF4FA3),
              blurRadius: 14,
              offset: Offset(0, 6),
            ),
          ],
        ),
        child: Row(
          children: [
            const Text('🎁', style: TextStyle(fontSize: 22)),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Claim FREE Paytm Soundbox!',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            const Icon(
              Icons.phone_in_talk_rounded,
              color: Colors.white,
              size: 18,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeroCard() => Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_pink, _pinkSoft],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(20),
          boxShadow: const [
            BoxShadow(
              color: Color(0x24FF4FA3),
              blurRadius: 18,
              offset: Offset(0, 8),
            ),
          ],
        ),
        child: Row(
          children: [
            CircleAvatar(
              radius: 24,
              backgroundColor: Colors.white.withValues(alpha: 0.94),
              child: Text(
                _displayName.isNotEmpty ? _displayName[0].toUpperCase() : 'H',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  color: _pink,
                  fontWeight: FontWeight.w900,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _displayName,
                    style: GoogleFonts.outfit(
                      fontSize: 16,
                      color: Colors.white,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _phone,
                    style: GoogleFonts.outfit(
                      fontSize: 11,
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.18),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
              ),
              child: Text(
                _status.toUpperCase(),
                style: GoogleFonts.outfit(
                  fontSize: 9,
                  color: _status == 'online'
                      ? Colors.white
                      : const Color(0xFFFFF7FB),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ),
      );
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
                  BoxShadow(
                    color: Color(0x24FF4FA3),
                    blurRadius: 22,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Icon(
                    Icons.health_and_safety_rounded,
                    color: Colors.white,
                    size: 42,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'NJ Tech Hero Support',
                    style: GoogleFonts.outfit(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Need help during live testing? Contact our team instantly.',
                    style: GoogleFonts.outfit(
                      color: Colors.white.withValues(alpha: 0.92),
                      fontWeight: FontWeight.w700,
                    ),
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
              onTap: () => _launchSupport(
                context,
                Uri.parse('https://wa.me/918681869091'),
              ),
            ),
            const SizedBox(height: 12),
            _SupportButton(
              icon: Icons.phone_in_talk_rounded,
              title: 'Call for Help',
              subtitle: 'Dial 8681869091',
              color: _pink,
              onTap: () => _launchSupport(
                context,
                Uri.parse('tel:8681869091'),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'We are monitoring the Erode live test. Stay online only when ready to accept rides.',
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
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
              BoxShadow(
                color: Color(0x12FF4FA3),
                blurRadius: 18,
                offset: Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              Container(
                width: 50,
                height: 50,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: color, size: 28),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: GoogleFonts.outfit(
                        color: _HeroHelpSupportScreen._text,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    Text(
                      subtitle,
                      style: GoogleFonts.outfit(
                        color: _HeroHelpSupportScreen._muted,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(ColorProperty('color', color));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
