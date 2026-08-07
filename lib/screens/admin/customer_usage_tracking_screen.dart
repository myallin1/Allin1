// ================================================================
// customer_usage_tracking_screen.dart — Customer Usage Tracking
// ================================================================
// Per Nizam's final pre-launch request: a simple funnel view — how
// many people visited the Firebase-hosted landing page / PWA link,
// how many of those actually downloaded an APK (per app), and how
// many people have signed up (registered with an email) in the app —
// all WITHOUT going through the Play Store, so this monitors organic
// link/landing-page usage specifically.
//
// Reads a single Firestore doc (app_usage_stats/funnel) for the
// visit + download counters (see usage_tracking_service.dart), and
// performs one Firestore count() aggregation query on the `users`
// collection for total signups — a server-side count, so it costs a
// single read regardless of how many users exist.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _card = Color(0xFF15152A);
const Color _purple = Color(0xFF6C63FF);
const Color _pink = Color(0xFFFF4FA3);
const Color _gold = Color(0xFFFFC94A);
const Color _text = Colors.white;

class CustomerUsageTrackingScreen extends StatefulWidget {
  const CustomerUsageTrackingScreen({super.key});

  @override
  State<CustomerUsageTrackingScreen> createState() =>
      _CustomerUsageTrackingScreenState();
}

class _CustomerUsageTrackingScreenState
    extends State<CustomerUsageTrackingScreen> {
  int? _totalSignups;
  bool _loadingSignups = true;
  String? _signupError;

  @override
  void initState() {
    super.initState();
    _loadSignupCount();
  }

  Future<void> _loadSignupCount() async {
    try {
      // Single server-side aggregation read — never scans/downloads
      // the actual user documents.
      final agg = await FirebaseFirestore.instance
          .collection('users')
          .count()
          .get();
      if (!mounted) return;
      setState(() {
        _totalSignups = agg.count ?? 0;
        _loadingSignups = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _signupError = e.toString();
        _loadingSignups = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        title: Text(
          'Customer Usage Tracking',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
        iconTheme: const IconThemeData(color: _text),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _text),
            onPressed: () {
              setState(() => _loadingSignups = true);
              _loadSignupCount();
            },
          ),
        ],
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('app_usage_stats')
            .doc('funnel')
            .snapshots(),
        builder: (context, snapshot) {
          final data = snapshot.data?.data() ?? <String, dynamic>{};
          final visits = (data['landingPageVisits'] as num?)?.toInt() ?? 0;
          final dlCustomer = (data['download_customer'] as num?)?.toInt() ?? 0;
          final dlHero = (data['download_hero'] as num?)?.toInt() ?? 0;
          final dlAdmin = (data['download_admin'] as num?)?.toInt() ?? 0;
          final dlSeller = (data['download_seller'] as num?)?.toInt() ?? 0;
          final totalDownloads = dlCustomer + dlHero + dlAdmin + dlSeller;

          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Text(
                'Organic funnel — people who visited the PWA link on '
                'their own, outside the Play Store.',
                style: GoogleFonts.outfit(
                  color: _text.withValues(alpha: 0.55),
                  fontSize: 12,
                ),
              ),
              const SizedBox(height: 16),
              _funnelRow(
                icon: Icons.link_rounded,
                iconColor: _purple,
                label: 'Landing Page Visits',
                value: visits,
              ),
              _funnelArrow(),
              _funnelRow(
                icon: Icons.download_rounded,
                iconColor: _pink,
                label: 'APK Downloads (all apps)',
                value: totalDownloads,
                subtitle: visits == 0
                    ? null
                    : '${((totalDownloads / visits) * 100).clamp(0, 999).toStringAsFixed(1)}% of visitors downloaded',
              ),
              _funnelArrow(),
              _funnelRow(
                icon: Icons.how_to_reg_rounded,
                iconColor: _gold,
                label: 'Signed Up (email login)',
                value: _totalSignups ?? 0,
                loading: _loadingSignups,
                errorText: _signupError,
                subtitle: (totalDownloads == 0 || _totalSignups == null)
                    ? null
                    : '${((_totalSignups! / totalDownloads) * 100).clamp(0, 999).toStringAsFixed(1)}% of downloaders signed up',
              ),
              const SizedBox(height: 24),
              Text(
                'Downloads by app',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontWeight: FontWeight.w800,
                  fontSize: 14,
                ),
              ),
              const SizedBox(height: 10),
              _appDownloadTile('Customer', Icons.shopping_bag_rounded, dlCustomer, _pink),
              _appDownloadTile('Hero', Icons.delivery_dining_rounded, dlHero, _purple),
              _appDownloadTile('Admin', Icons.admin_panel_settings_rounded, dlAdmin, _gold),
              _appDownloadTile('Seller', Icons.storefront_rounded, dlSeller, const Color(0xFF00C853)),
            ],
          );
        },
      ),
    );
  }

  Widget _funnelRow({
    required IconData icon,
    required Color iconColor,
    required String label,
    required int value,
    bool loading = false,
    String? errorText,
    String? subtitle,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: iconColor.withValues(alpha: 0.25)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.15),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: GoogleFonts.outfit(
                    color: _text.withValues(alpha: 0.7),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                if (subtitle != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      subtitle,
                      style: TextStyle(
                        color: _text.withValues(alpha: 0.4),
                        fontSize: 10.5,
                      ),
                    ),
                  ),
                if (errorText != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(
                      'Error: $errorText',
                      style: const TextStyle(color: Colors.redAccent, fontSize: 10.5),
                    ),
                  ),
              ],
            ),
          ),
          loading
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2, color: _gold),
                )
              : Text(
                  '$value',
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w900,
                  ),
                ),
        ],
      ),
    );
  }

  Widget _funnelArrow() {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Icon(Icons.arrow_downward_rounded, color: Colors.white24, size: 18),
      ),
    );
  }

  Widget _appDownloadTile(String name, IconData icon, int count, Color color) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 18),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              name,
              style: GoogleFonts.outfit(color: _text, fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ),
          Text(
            '$count',
            style: GoogleFonts.outfit(color: _text, fontSize: 15, fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }
}
