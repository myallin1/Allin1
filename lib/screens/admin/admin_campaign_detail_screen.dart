// ================================================================
// admin_campaign_detail_screen.dart — per-campaign QR insights
// ================================================================
// NEW (Aug 13 2026 — Nizam: "customer scan pannuna detail vachu namma
// intha system la varramari management pannanum... campaign ah detailed
// ah monitor panna option venum, user experience better ah understand
// pannikuramari irukanum").
//
// This is the QRCG "insights" page rebuilt inside our own admin app,
// reading OUR data instead of a third-party trial account:
//   * Total vs unique scans (unique decided device-side by the /q/ page)
//   * Scans-over-time bar chart, switchable hour / day
//   * OS split (Android/iOS/other) — tells us which APK to push
//   * Signups attributed to this exact code + conversion rate
//   * Live destination editing (the dynamic-QR payoff) + pause/resume
//   * Campaign metadata: medium, print run, start/end
//
// READ COST: one bounded fetchScans() page per open (default 500 rows),
// NOT a .snapshots() listener — same discipline as the leads screen.
// Every chart/filter below is computed from that already-fetched list,
// so switching hour/day view costs zero additional reads.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../services/affiliate_service.dart';

const Color _bg = Color(0xFF0E0B10);
const Color _surface = Color(0xFF1A151D);
const Color _card = Color(0xFF241D28);
const Color _pink = Color(0xFFFF4FA3);
const Color _text = Color(0xFFF3EAF5);
const Color _muted = Color(0xFF9C8CA6);
const Color _green = Color(0xFF00C853);
const Color _amber = Color(0xFFFFB300);

class AdminCampaignDetailScreen extends StatefulWidget {
  const AdminCampaignDetailScreen({required this.code, super.key});
  final String code;

  @override
  State<AdminCampaignDetailScreen> createState() =>
      _AdminCampaignDetailScreenState();
}

class _AdminCampaignDetailScreenState extends State<AdminCampaignDetailScreen> {
  Map<String, dynamic>? _campaign;
  List<Map<String, dynamic>> _scans = [];
  int _signups = 0;
  bool _loading = true;
  String? _error;
  bool _byHour = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final fs = FirebaseFirestore.instance;
      final campaignDoc =
          await fs.collection('affiliate_codes').doc(widget.code).get();
      final scanSnap = await AffiliateService.instance.fetchScans(widget.code);
      // Leads carry the refCode, so this is the true attributed-signup
      // count rather than the denormalised counter.
      final leadSnap = await fs
          .collection('affiliate_leads')
          .where('refCode', isEqualTo: widget.code)
          .get();

      if (!mounted) return;
      setState(() {
        _campaign = campaignDoc.data();
        _scans = scanSnap.docs.map((d) => d.data()).toList();
        _signups = leadSnap.size;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  int get _total => _scans.length;
  int get _unique =>
      _scans.where((s) => s['isUnique'] == true).length;

  Map<String, int> get _osSplit {
    final m = <String, int>{};
    for (final s in _scans) {
      final os = (s['os'] ?? 'Other').toString();
      m[os] = (m[os] ?? 0) + 1;
    }
    return Map.fromEntries(
      m.entries.toList()..sort((a, b) => b.value.compareTo(a.value)),
    );
  }

  /// Buckets scans into the last 24 hours or last 14 days.
  List<MapEntry<String, int>> get _timeSeries {
    final now = DateTime.now();
    final buckets = <String, int>{};
    final count = _byHour ? 24 : 14;

    for (var i = count - 1; i >= 0; i--) {
      final t = _byHour
          ? now.subtract(Duration(hours: i))
          : now.subtract(Duration(days: i));
      buckets[_key(t)] = 0;
    }
    for (final s in _scans) {
      final ts = (s['ts'] as Timestamp?)?.toDate();
      if (ts == null) continue;
      final k = _key(ts);
      if (buckets.containsKey(k)) buckets[k] = buckets[k]! + 1;
    }
    return buckets.entries.toList();
  }

  String _key(DateTime t) => _byHour
      ? '${t.day}-${t.hour}'
      : '${t.year}-${t.month}-${t.day}';

  String _label(DateTime t) =>
      _byHour ? '${t.hour}' : '${t.day}/${t.month}';

  Future<void> _editDestination() async {
    final ctrl = TextEditingController(
      text: (_campaign?['destination'] ?? '') as String? ?? '',
    );
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: Text('Change destination',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800)),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'The printed QR never changes — only where it sends people. '
              'Takes effect on the very next scan.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: ctrl,
              style: GoogleFonts.outfit(color: _text, fontSize: 13),
              decoration: InputDecoration(
                filled: true,
                fillColor: _card,
                hintText: 'https://…',
                hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _pink),
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (result == null || result.isEmpty) return;
    if (!RegExp(r'^https?://', caseSensitive: false).hasMatch(result)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Destination must start with http:// or https://'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }
    await AffiliateService.instance.updateDestination(widget.code, result);
    await _load();
  }

  Future<void> _toggleActive() async {
    final active = (_campaign?['active'] as bool?) ?? true;
    await AffiliateService.instance.setActive(widget.code, !active);
    await _load();
  }

  void _showQrImage(String shortUrl) {
    showDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        contentPadding: const EdgeInsets.all(24),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            QrImageView(
              data: shortUrl,
              version: QrVersions.auto,
              size: 250,
              backgroundColor: Colors.white,
            ),
            const SizedBox(height: 20),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                foregroundColor: Colors.white,
                elevation: 0,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 12),
              ),
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Close', style: TextStyle(fontWeight: FontWeight.bold)),
            )
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final active = (_campaign?['active'] as bool?) ?? true;
    final shortUrl = AffiliateService.shortUrlFor(widget.code);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          (_campaign?['label'] ?? widget.code).toString(),
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Refresh',
            icon: const Icon(Icons.refresh_rounded, color: _pink),
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _pink))
          : RefreshIndicator(
              color: _pink,
              backgroundColor: _surface,
              onRefresh: _load,
              child: ListView(
                padding: const EdgeInsets.all(16),
                children: [
                  if (_error != null) _errorBox(_error!),
                  _linkCard(shortUrl, active),
                  const SizedBox(height: 14),
                  _statsRow(),
                  const SizedBox(height: 14),
                  _chartCard(),
                  const SizedBox(height: 14),
                  _osCard(),
                  const SizedBox(height: 14),
                  _metaCard(),
                  const SizedBox(height: 30),
                ],
              ),
            ),
    );
  }

  Widget _errorBox(String m) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red),
        ),
        child: Text(m, style: GoogleFonts.outfit(color: _text, fontSize: 12)),
      );

  Widget _linkCard(String shortUrl, bool active) {
    final dest = (_campaign?['destination'] ?? '') as String? ?? '';
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _pink.withValues(alpha: 0.25)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: (active ? _green : _amber).withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: Text(
                  active ? 'Active' : 'Paused',
                  style: GoogleFonts.outfit(
                      color: active ? _green : _amber,
                      fontSize: 10,
                      fontWeight: FontWeight.w800),
                ),
              ),
              const Spacer(),
              TextButton.icon(
                onPressed: _toggleActive,
                icon: Icon(
                    active
                        ? Icons.pause_circle_outline_rounded
                        : Icons.play_circle_outline_rounded,
                    color: _pink,
                    size: 18),
                label: Text(active ? 'Pause' : 'Resume',
                    style: GoogleFonts.outfit(color: _pink, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text('Printed short link (never changes)',
              style: GoogleFonts.outfit(color: _muted, fontSize: 10.5)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: SelectableText(
                  shortUrl,
                  style: GoogleFonts.robotoMono(
                      color: _text, fontSize: 12.5, fontWeight: FontWeight.w600),
                ),
              ),
              IconButton(
                tooltip: 'Copy',
                icon: const Icon(Icons.copy_rounded, color: _muted, size: 16),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: shortUrl));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Short link copied')),
                  );
                },
              ),
              IconButton(
                tooltip: 'View QR Code',
                icon: const Icon(Icons.qr_code_2_rounded, color: _pink, size: 18),
                onPressed: () => _showQrImage(shortUrl),
              ),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),
          Text('Currently forwards to (editable anytime)',
              style: GoogleFonts.outfit(color: _muted, fontSize: 10.5)),
          const SizedBox(height: 4),
          Row(
            children: [
              Expanded(
                child: Text(
                  dest.isEmpty ? '(app home)' : dest,
                  style: GoogleFonts.outfit(color: _text, fontSize: 12),
                ),
              ),
              TextButton(
                onPressed: _editDestination,
                child: Text('Change',
                    style: GoogleFonts.outfit(
                        color: _pink, fontSize: 12, fontWeight: FontWeight.w700)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _statsRow() {
    final rate = _total == 0 ? 0.0 : (_signups / _total * 100);
    return Row(
      children: [
        _stat('Total scans', '$_total', Icons.qr_code_scanner_rounded),
        _stat('Unique', '$_unique', Icons.person_outline_rounded),
        _stat('Signups', '$_signups', Icons.how_to_reg_rounded),
        _stat('Conv.', '${rate.toStringAsFixed(0)}%', Icons.trending_up_rounded),
      ],
    );
  }

  Widget _stat(String label, String value, IconData icon) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 6),
          decoration: BoxDecoration(
            color: _surface,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            children: [
              Icon(icon, color: _pink, size: 17),
              const SizedBox(height: 6),
              FittedBox(
                child: Text(value,
                    style: GoogleFonts.outfit(
                        color: _text, fontSize: 17, fontWeight: FontWeight.w800)),
              ),
              const SizedBox(height: 2),
              Text(label,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 9.5)),
            ],
          ),
        ),
      );

  Widget _chartCard() {
    final series = _timeSeries;
    final maxV = series.fold<int>(1, (m, e) => e.value > m ? e.value : m);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Scans over time',
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
              const Spacer(),
              _toggle('Hour', _byHour, () => setState(() => _byHour = true)),
              const SizedBox(width: 6),
              _toggle('Day', !_byHour, () => setState(() => _byHour = false)),
            ],
          ),
          const SizedBox(height: 14),
          SizedBox(
            height: 110,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: series.map((e) {
                final h = e.value == 0 ? 2.0 : (e.value / maxV) * 96;
                return Expanded(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 1.5),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        if (e.value > 0)
                          Text('${e.value}',
                              style: GoogleFonts.outfit(
                                  color: _muted, fontSize: 8)),
                        const SizedBox(height: 2),
                        Container(
                          height: h,
                          decoration: BoxDecoration(
                            color: e.value == 0
                                ? Colors.white12
                                : _pink.withValues(alpha: 0.85),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
          ),
          const SizedBox(height: 6),
          Text(
            _byHour ? 'Last 24 hours' : 'Last 14 days',
            style: GoogleFonts.outfit(color: _muted, fontSize: 10),
          ),
        ],
      ),
    );
  }

  Widget _toggle(String label, bool on, VoidCallback onTap) => GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: on ? _pink : _card,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(label,
              style: GoogleFonts.outfit(
                  color: on ? Colors.white : _muted,
                  fontSize: 10.5,
                  fontWeight: FontWeight.w700)),
        ),
      );

  Widget _osCard() {
    final split = _osSplit;
    if (split.isEmpty) {
      return const SizedBox.shrink();
    }
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Device / OS',
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 4),
          Text('Tells you which app build to push hardest in Erode.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 10.5)),
          const SizedBox(height: 12),
          ...split.entries.map((e) {
            final pct = _total == 0 ? 0.0 : e.value / _total;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(e.key,
                        style:
                            GoogleFonts.outfit(color: _text, fontSize: 11.5)),
                  ),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        value: pct,
                        minHeight: 8,
                        backgroundColor: Colors.white10,
                        valueColor: const AlwaysStoppedAnimation(_pink),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text('${(pct * 100).toStringAsFixed(0)}%',
                      style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _metaCard() {
    final c = _campaign ?? {};
    final start = (c['campaignStart'] as Timestamp?)?.toDate();
    final end = (c['campaignEnd'] as Timestamp?)?.toDate();
    final printRun = (c['printRun'] as num?)?.toInt() ?? 0;
    final medium = (c['medium'] ?? '') as String? ?? '';
    final scanned = _total;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Campaign',
              style: GoogleFonts.outfit(
                  color: _text, fontSize: 14, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          _metaRow('Code', widget.code),
          _metaRow('Type', (c['type'] ?? '-').toString()),
          _metaRow('Medium', medium.isEmpty ? '-' : medium),
          _metaRow('Print run', printRun == 0 ? '-' : '$printRun'),
          if (printRun > 0)
            _metaRow('Scan rate',
                '${(scanned / printRun * 100).toStringAsFixed(1)}% of printed'),
          _metaRow('Start', start == null ? '-' : '${start.day}/${start.month}/${start.year}'),
          _metaRow('End', end == null ? '-' : '${end.day}/${end.month}/${end.year}'),
        ],
      ),
    );
  }

  Widget _metaRow(String k, String v) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SizedBox(
              width: 84,
              child: Text(k,
                  style: GoogleFonts.outfit(color: _muted, fontSize: 11.5)),
            ),
            Expanded(
              child: Text(v,
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 11.5, fontWeight: FontWeight.w600)),
            ),
          ],
        ),
      );
}
