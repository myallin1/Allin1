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

import '../../services/db_usage_tracker.dart';
import '../../widgets/admin/cached_analytics_view.dart';

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
  int? _posterSignups;
  bool _loadingSignups = true;
  String? _signupError;

  // FETCH-ON-DEMAND (Nizam's architecture instruction, Aug 11 2026):
  // this screen used to auto-read on open TWICE over — an initState()
  // signup-count query AND a live .snapshots() listener on the funnel
  // doc. Both are gone: nothing is read until the admin taps Fetch.
  AnalyticsRange _range = AnalyticsRange.thisMonth;

  /// One funnel-document read + two server-side count() aggregations per
  /// explicit Fetch tap. count() is billed as a single read regardless of
  /// how many user documents exist — it never downloads them.
  Future<Map<String, dynamic>> _fetchUsage() async {
    final funnelFuture = FirebaseFirestore.instance
        .collection('app_usage_stats')
        .doc('funnel')
        .get();
    final aggFuture =
        FirebaseFirestore.instance.collection('users').count().get();
    final posterAggFuture = FirebaseFirestore.instance
        .collection('users')
        .where('source', isEqualTo: 'poster_campaign')
        .count()
        .get();

    final funnel = await funnelFuture;
    final results = await Future.wait([aggFuture, posterAggFuture]);
    // 1 document read + 2 count() aggregations (each billed as one read
    // regardless of collection size).
    DbUsageTracker.instance.recordRead(3, 'customer_usage_tracking', 'fetch_funnel');

    final data = funnel.data() ?? <String, dynamic>{};
    // Flatten to Hive-serializable primitives (no Timestamps).
    final daily = <String, dynamic>{};
    if (data['daily'] is Map) {
      (data['daily'] as Map).forEach((day, fields) {
        if (day is String && fields is Map) {
          daily[day] = fields.map(
            (k, v) => MapEntry(k.toString(), (v as num?)?.toInt() ?? 0),
          );
        }
      });
    }

    return <String, dynamic>{
      'landingPageVisits': (data['landingPageVisits'] as num?)?.toInt() ?? 0,
      'poster_qr_scans': (data['poster_qr_scans'] as num?)?.toInt() ?? 0,
      'download_customer': (data['download_customer'] as num?)?.toInt() ?? 0,
      'download_hero': (data['download_hero'] as num?)?.toInt() ?? 0,
      'download_admin': (data['download_admin'] as num?)?.toInt() ?? 0,
      'download_seller': (data['download_seller'] as num?)?.toInt() ?? 0,
      'poster_qr_pwa_installs':
          (data['poster_qr_pwa_installs'] as num?)?.toInt() ?? 0,
      'daily': daily,
      'totalSignups': results[0].count ?? 0,
      'posterSignups': results[1].count ?? 0,
    };
  }

  /// Sums a per-day bucketed field across the selected range.
  /// Returns null when no daily data covers the range at all, so the UI
  /// can say "not tracked yet" instead of misreporting a real zero.
  int? _rangeTotal(Map<String, dynamic> data, String field) {
    final daily = data['daily'];
    if (daily is! Map || daily.isEmpty) return null;
    final now = DateTime.now();
    var sum = 0;
    var matched = false;
    daily.forEach((day, fields) {
      final parsed = DateTime.tryParse(day.toString());
      if (parsed == null || fields is! Map) return;
      if (!_range.contains(parsed, now: now)) return;
      matched = true;
      sum += (fields[field] as num?)?.toInt() ?? 0;
    });
    return matched ? sum : null;
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
            fontSize: 18, // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
          ),
        ),
        iconTheme: const IconThemeData(color: _text),
      ),
      body: CachedAnalyticsView<Map<String, dynamic>>(
        cacheKey: 'admin_customer_usage',
        fetch: _fetchUsage,
        emptyMessage: 'No usage data loaded yet.',
        extraActions: [
          Expanded(
            child: AnalyticsRangeChips(
              selected: _range,
              onChanged: (r) => setState(() => _range = r),
            ),
          ),
        ],
        builder: (context, data) {
          final visits = (data['landingPageVisits'] as num?)?.toInt() ?? 0;
          final posterScans = (data['poster_qr_scans'] as num?)?.toInt() ?? 0;
          final dlCustomer = (data['download_customer'] as num?)?.toInt() ?? 0;
          final dlHero = (data['download_hero'] as num?)?.toInt() ?? 0;
          final dlAdmin = (data['download_admin'] as num?)?.toInt() ?? 0;
          final dlSeller = (data['download_seller'] as num?)?.toInt() ?? 0;
          final totalDownloads = dlCustomer + dlHero + dlAdmin + dlSeller;
          _totalSignups = (data['totalSignups'] as num?)?.toInt() ?? 0;
          _posterSignups = (data['posterSignups'] as num?)?.toInt() ?? 0;
          _loadingSignups = false;

          // Range-scoped figures from the per-day buckets. Null means no
          // daily data covers this range — shown as an explicit note
          // rather than a misleading zero, since per-day tracking only
          // starts from this build.
          final rangeVisits = _rangeTotal(data, 'landingPageVisits');
          final rangeScans = _rangeTotal(data, 'poster_qr_scans');
          final rangeDownloads = [
            'download_customer',
            'download_hero',
            'download_admin',
            'download_seller',
          ].map((f) => _rangeTotal(data, f)).fold<int?>(null, (acc, v) {
            if (v == null) return acc;
            return (acc ?? 0) + v;
          });

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
              const SizedBox(height: 14),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.04),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'In "${_range.label}"',
                      style: GoogleFonts.outfit(
                        color: _text,
                        fontWeight: FontWeight.w800,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(height: 8),
                    if (rangeVisits == null &&
                        rangeScans == null &&
                        rangeDownloads == null)
                      Text(
                        'Per-day tracking starts from this build — no '
                        'day-level history exists for this range yet. '
                        'Lifetime totals below are complete.',
                        style: GoogleFonts.outfit(
                          color: _text.withValues(alpha: 0.5),
                          fontSize: 11.5,
                        ),
                      )
                    else
                      Text(
                        '${rangeScans ?? 0} scans  •  ${rangeVisits ?? 0} visits  '
                        '•  ${rangeDownloads ?? 0} downloads',
                        style: GoogleFonts.outfit(
                          color: Colors.greenAccent,
                          fontWeight: FontWeight.w700,
                          fontSize: 13.5,
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Lifetime totals',
                style: GoogleFonts.outfit(
                  color: _text.withValues(alpha: 0.55),
                  fontSize: 11.5,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 10),
              _funnelRow(
                icon: Icons.qr_code_2_rounded,
                iconColor: Colors.blueAccent,
                label: 'Total QR Poster Scans',
                value: posterScans,
                subtitle: 'From ?source=poster_campaign links',
              ),
              _funnelArrow(),
              _funnelRow(
                icon: Icons.install_mobile_rounded,
                iconColor: Colors.tealAccent,
                label: 'Poster PWA Installs',
                value: (data['poster_qr_pwa_installs'] as num?)?.toInt() ?? 0,
                subtitle: posterScans == 0
                    ? null
                    : '${((((data['poster_qr_pwa_installs'] as num?)?.toInt() ?? 0) / posterScans) * 100).clamp(0, 999).toStringAsFixed(1)}% of scans installed',
              ),
              _funnelArrow(),
              _funnelRow(
                icon: Icons.how_to_reg_rounded,
                iconColor: Colors.amberAccent,
                label: 'Poster Registrations',
                value: _posterSignups ?? 0,
                loading: _loadingSignups,
                errorText: _signupError,
                subtitle: posterScans == 0 || _posterSignups == null
                    ? null
                    : '${((_posterSignups! / posterScans) * 100).clamp(0, 999).toStringAsFixed(1)}% of scans registered\n(Tap to view users)',
                onTap: () {
                  showModalBottomSheet(
                    context: context,
                    backgroundColor: _card,
                    isScrollControlled: true,
                    shape: const RoundedRectangleBorder(
                      borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
                    ),
                    builder: (context) => const _PosterSignupsSheet(),
                  );
                },
              ),
              _funnelArrow(),
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
    VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Container(
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

class _PosterSignupsSheet extends StatefulWidget {
  const _PosterSignupsSheet();

  @override
  State<_PosterSignupsSheet> createState() => _PosterSignupsSheetState();
}

class _PosterSignupsSheetState extends State<_PosterSignupsSheet> {
  final List<DocumentSnapshot> _users = [];
  bool _loading = false;
  bool _hasMore = true;
  DocumentSnapshot? _lastDoc;

  @override
  void initState() {
    super.initState();
    _fetchUsers();
  }

  Future<void> _fetchUsers() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    try {
      var query = FirebaseFirestore.instance
          .collection('users')
          .where('source', isEqualTo: 'poster_campaign')
          .limit(50);
      
      if (_lastDoc != null) {
        query = query.startAfterDocument(_lastDoc!);
      }
      
      final snap = await query.get();
      if (!mounted) return;
      setState(() {
        if (snap.docs.isNotEmpty) {
          _lastDoc = snap.docs.last;
          _users.addAll(snap.docs);
        }
        if (snap.docs.length < 50) {
          _hasMore = false;
        }
        _loading = false;
      });
    } catch (e) {
      debugPrint('Error fetching poster users: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.5,
      maxChildSize: 0.9,
      expand: false,
      builder: (context, scrollController) {
        scrollController.addListener(() {
          if (scrollController.position.pixels >=
              scrollController.position.maxScrollExtent - 50) {
            _fetchUsers();
          }
        });

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.symmetric(vertical: 12),
              height: 4,
              width: 40,
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            Text(
              'Poster Campaign Signups',
              style: GoogleFonts.outfit(
                color: _text,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Expanded(
              child: _users.isEmpty && _loading
                  ? const Center(
                      child: CircularProgressIndicator(color: _gold),
                    )
                  : _users.isEmpty
                      ? Center(
                          child: Text(
                            'No signups found.',
                            style: TextStyle(color: _text.withValues(alpha: 0.5)),
                          ),
                        )
                      : ListView.builder(
                          controller: scrollController,
                          itemCount: _users.length + (_hasMore ? 1 : 0),
                          itemBuilder: (context, index) {
                            if (index == _users.length) {
                              return const Padding(
                                padding: EdgeInsets.all(16.0),
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: _gold,
                                    strokeWidth: 2,
                                  ),
                                ),
                              );
                            }
                            final doc = _users[index];
                            final data = doc.data() as Map<String, dynamic>?;
                            final email = data?['email'] as String? ?? 'No email';
                            final phone = data?['phone'] as String? ?? 'No phone';
                            final name = data?['name'] as String? ?? 'Unknown';

                            return ListTile(
                              leading: const CircleAvatar(
                                backgroundColor: Colors.white10,
                                child: Icon(Icons.person, color: _gold),
                              ),
                              title: Text(name,
                                  style: const TextStyle(color: _text)),
                              subtitle: Text('$email\n$phone',
                                  style: TextStyle(
                                      color: _text.withValues(alpha: 0.6),
                                      fontSize: 12)),
                            );
                          },
                        ),
            ),
          ],
        );
      },
    );
  }
}
