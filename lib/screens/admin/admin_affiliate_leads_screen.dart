// ================================================================
// admin_affiliate_leads_screen.dart — "QR Leads & Analytics"
// ================================================================
// NEW (Aug 12 2026 — Nizam's 4-part request):
//
//  (2) "yevlo peru namma link kulla vanthanga, athula yevlo peru
//      customer app kulla login pandranga... mobile number and mail id
//      kuduthu login pandra customers list... pdf and excel export"
//      -> the funnel counters at the top (scans -> signups -> reachable)
//         plus the full per-person table below, exportable to CSV.
//
//  (3) "innum yennena analytics yedutha namma business grow panna
//      better" -> per-QR breakdown, role split, city split, date-range
//      and contactability filters, live search, and a conversion-rate
//      column so a poster that gets scans but no signups is obvious at
//      a glance.
//
//  (4) "database limit waste agama... total datavum fetch pannama...
//      new va vantha datava mattum fetch" -> INCREMENTAL fetch. Rows
//      are cached on-device (SharedPreferences JSON). On reopen we ask
//      Firestore only for documents newer than the newest cached row,
//      so a second visit typically costs a handful of reads instead of
//      re-downloading the whole collection. A deliberate "Refresh"
//      button drives this; there is intentionally NO always-on
//      .snapshots() listener here, because a live listener on a growing
//      leads collection is precisely the runaway read cost Nizam asked
//      to avoid.
//
// Deliberately NOT a StreamBuilder — see the note above. Everything
// below operates on the locally-cached list, so filtering, searching and
// sorting cost ZERO additional reads.
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../services/affiliate_service.dart';
import '../../services/csv_export_stub.dart'
    if (dart.library.html) '../../services/csv_export_web.dart';

const Color _bg = Color(0xFF0E0B10);
const Color _surface = Color(0xFF1A151D);
const Color _card = Color(0xFF241D28);
const Color _pink = Color(0xFFFF4FA3);
const Color _text = Color(0xFFF3EAF5);
const Color _muted = Color(0xFF9C8CA6);
const Color _green = Color(0xFF00C853);
const Color _amber = Color(0xFFFFB300);

class _Lead {
  const _Lead({
    required this.uid,
    required this.name,
    required this.phone,
    required this.email,
    required this.city,
    required this.role,
    required this.refCode,
    required this.createdAt,
  });

  final String uid;
  final String name;
  final String phone;
  final String email;
  final String city;
  final String role;
  final String refCode;
  final DateTime? createdAt;

  bool get hasPhone => phone.trim().isNotEmpty;
  bool get hasEmail => email.trim().isNotEmpty;
  bool get isReachable => hasPhone || hasEmail;

  Map<String, dynamic> toJson() => {
        'uid': uid,
        'name': name,
        'phone': phone,
        'email': email,
        'city': city,
        'role': role,
        'refCode': refCode,
        'createdAt': createdAt?.toIso8601String(),
      };

  factory _Lead.fromJson(Map<String, dynamic> j) => _Lead(
        uid: (j['uid'] ?? '') as String,
        name: (j['name'] ?? '') as String,
        phone: (j['phone'] ?? '') as String,
        email: (j['email'] ?? '') as String,
        city: (j['city'] ?? '') as String,
        role: (j['role'] ?? '') as String,
        refCode: (j['refCode'] ?? '') as String,
        createdAt: (j['createdAt'] as String?) == null
            ? null
            : DateTime.tryParse(j['createdAt'] as String),
      );

  factory _Lead.fromDoc(QueryDocumentSnapshot<Map<String, dynamic>> d) {
    final m = d.data();
    return _Lead(
      uid: (m['uid'] ?? d.id) as String,
      name: (m['name'] ?? '') as String,
      phone: (m['phone'] ?? '') as String,
      email: (m['email'] ?? '') as String,
      city: (m['city'] ?? '') as String,
      role: (m['role'] ?? '') as String,
      refCode: (m['refCode'] ?? '') as String,
      createdAt: (m['createdAt'] as Timestamp?)?.toDate(),
    );
  }
}

class AdminAffiliateLeadsScreen extends StatefulWidget {
  const AdminAffiliateLeadsScreen({super.key});

  @override
  State<AdminAffiliateLeadsScreen> createState() =>
      _AdminAffiliateLeadsScreenState();
}

class _AdminAffiliateLeadsScreenState extends State<AdminAffiliateLeadsScreen> {
  static const String _kCacheKey = 'admin_affiliate_leads_cache_v1';

  List<_Lead> _leads = [];
  Map<String, Map<String, dynamic>> _codes = {}; // code -> {scans, signups, label, type}
  bool _loading = true;
  String? _error;
  int _lastFetchedCount = 0;
  DateTime? _lastSyncAt;

  // Filters — all applied locally, zero extra reads.
  String _search = '';
  String _roleFilter = 'all';
  String _codeFilter = 'all';
  String _reachFilter = 'all'; // all | phone | email | both | none
  int _daysFilter = 0; // 0 = all time

  @override
  void initState() {
    super.initState();
    _bootstrap();
  }

  Future<void> _bootstrap() async {
    await _loadCache();
    await _syncIncremental();
  }

  Future<void> _loadCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_kCacheKey);
      if (raw == null || raw.isEmpty) return;
      final list = (jsonDecode(raw) as List<dynamic>)
          .map((e) => _Lead.fromJson(e as Map<String, dynamic>))
          .toList();
      if (!mounted) return;
      setState(() => _leads = list);
    } catch (e) {
      debugPrint('[AffiliateLeads] cache load failed: $e');
    }
  }

  Future<void> _saveCache() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _kCacheKey,
        jsonEncode(_leads.map((l) => l.toJson()).toList()),
      );
    } catch (e) {
      debugPrint('[AffiliateLeads] cache save failed: $e');
    }
  }

  /// THE incremental read (Nizam's item 4). Only asks for rows newer
  /// than the newest one already cached locally.
  Future<void> _syncIncremental({bool full = false}) async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      DateTime? since;
      if (!full && _leads.isNotEmpty) {
        final dated = _leads.where((l) => l.createdAt != null).toList()
          ..sort((a, b) => b.createdAt!.compareTo(a.createdAt!));
        if (dated.isNotEmpty) since = dated.first.createdAt;
      }

      final snap = await AffiliateService.instance.fetchLeadsSince(since);
      final fetched = snap.docs.map(_Lead.fromDoc).toList();

      // Merge by uid so a re-fetched row replaces rather than duplicates.
      final byUid = <String, _Lead>{for (final l in _leads) l.uid: l};
      for (final l in fetched) {
        byUid[l.uid] = l;
      }
      final merged = byUid.values.toList()
        ..sort((a, b) {
          final ad = a.createdAt, bd = b.createdAt;
          if (ad == null && bd == null) return 0;
          if (ad == null) return 1;
          if (bd == null) return -1;
          return bd.compareTo(ad);
        });

      // Codes are a tiny collection (one doc per QR) — cheap to read in
      // full, and needed for the scans/conversion-rate analytics that
      // the leads rows alone cannot provide.
      final codesSnap =
          await FirebaseFirestore.instance.collection('affiliate_codes').get();
      final codeMap = <String, Map<String, dynamic>>{};
      for (final d in codesSnap.docs) {
        codeMap[d.id] = d.data();
      }

      if (!mounted) return;
      setState(() {
        _leads = merged;
        _codes = codeMap;
        _lastFetchedCount = fetched.length;
        _lastSyncAt = DateTime.now();
        _loading = false;
      });
      await _saveCache();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  // ── Filtering (all local) ────────────────────────────────────────
  List<_Lead> get _filtered {
    final now = DateTime.now();
    return _leads.where((l) {
      if (_roleFilter != 'all' && l.role != _roleFilter) return false;
      if (_codeFilter != 'all' && l.refCode != _codeFilter) return false;

      switch (_reachFilter) {
        case 'phone':
          if (!l.hasPhone) return false;
          break;
        case 'email':
          if (!l.hasEmail) return false;
          break;
        case 'both':
          if (!(l.hasPhone && l.hasEmail)) return false;
          break;
        case 'none':
          if (l.isReachable) return false;
          break;
      }

      if (_daysFilter > 0) {
        final c = l.createdAt;
        if (c == null) return false;
        if (now.difference(c).inDays > _daysFilter) return false;
      }

      if (_search.isNotEmpty) {
        final q = _search.toLowerCase();
        final hay =
            '${l.name} ${l.phone} ${l.email} ${l.city} ${l.refCode}'.toLowerCase();
        if (!hay.contains(q)) return false;
      }
      return true;
    }).toList();
  }

  int get _totalScans => _codes.values
      .fold<int>(0, (sum, m) => sum + ((m['scans'] as num?)?.toInt() ?? 0));

  // ── CSV export ───────────────────────────────────────────────────
  String _csvCell(String v) {
    final needsQuote = v.contains(',') || v.contains('"') || v.contains('\n');
    final escaped = v.replaceAll('"', '""');
    return needsQuote ? '"$escaped"' : escaped;
  }

  Future<void> _exportCsv() async {
    final rows = _filtered;
    final buf = StringBuffer()
      ..writeln('Name,Phone,Email,City,Role,QR Code,QR Label,Signed Up At');
    for (final l in rows) {
      final label = (_codes[l.refCode]?['label'] ?? '') as String;
      buf.writeln([
        _csvCell(l.name),
        _csvCell(l.phone),
        _csvCell(l.email),
        _csvCell(l.city),
        _csvCell(l.role),
        _csvCell(l.refCode),
        _csvCell(label),
        _csvCell(l.createdAt?.toIso8601String() ?? ''),
      ].join(','));
    }
    final stamp = DateTime.now().toIso8601String().split('T').first;
    try {
      await CsvExporter().save(buf.toString(), 'allin1_qr_leads_$stamp.csv');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Exported ${rows.length} leads to CSV'),
          backgroundColor: _green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Export failed: $e'), backgroundColor: Colors.red),
      );
    }
  }

  // ── UI ───────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    final rows = _filtered;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'QR Leads & Analytics',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        actions: [
          IconButton(
            tooltip: 'Fetch only new rows',
            icon: _loading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2, color: _pink),
                  )
                : const Icon(Icons.sync_rounded, color: _pink),
            onPressed: _loading ? null : () => _syncIncremental(),
          ),
          IconButton(
            tooltip: 'Export CSV (Excel / Sheets)',
            icon: const Icon(Icons.download_rounded, color: _pink),
            onPressed: rows.isEmpty ? null : _exportCsv,
          ),
        ],
      ),
      body: RefreshIndicator(
        color: _pink,
        backgroundColor: _surface,
        onRefresh: () => _syncIncremental(),
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            if (_error != null) _errorBox(_error!),
            _funnelCard(rows),
            const SizedBox(height: 14),
            _perCodeCard(),
            const SizedBox(height: 14),
            _filtersCard(),
            const SizedBox(height: 14),
            _syncNote(),
            const SizedBox(height: 10),
            if (rows.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Text(
                    _leads.isEmpty
                        ? 'No leads yet. They appear here as people sign up\nthrough your QR links.'
                        : 'No leads match the current filters.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                  ),
                ),
              )
            else
              ...rows.map(_leadTile),
            const SizedBox(height: 30),
          ],
        ),
      ),
    );
  }

  Widget _errorBox(String msg) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.red.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.red),
        ),
        child: Text(
          msg,
          style: GoogleFonts.outfit(color: _text, fontSize: 12),
        ),
      );

  Widget _funnelCard(List<_Lead> rows) {
    final signups = _leads.length;
    final reachable = _leads.where((l) => l.isReachable).length;
    final withPhone = _leads.where((l) => l.hasPhone).length;
    final withEmail = _leads.where((l) => l.hasEmail).length;
    final rate = _totalScans == 0
        ? 0.0
        : (signups / _totalScans * 100).clamp(0, 100).toDouble();

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
          Text(
            'QR Funnel',
            style: GoogleFonts.outfit(
                color: _text, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              _stat('Link opens', '$_totalScans', Icons.qr_code_scanner_rounded),
              _stat('Signed up', '$signups', Icons.how_to_reg_rounded),
              _stat('Conversion', '${rate.toStringAsFixed(1)}%',
                  Icons.trending_up_rounded),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              _stat('Reachable', '$reachable', Icons.campaign_rounded),
              _stat('Has phone', '$withPhone', Icons.phone_rounded),
              _stat('Has email', '$withEmail', Icons.mail_rounded),
            ],
          ),
          if (rows.length != _leads.length) ...[
            const SizedBox(height: 10),
            Text(
              'Showing ${rows.length} of $signups (filters active)',
              style: GoogleFonts.outfit(color: _amber, fontSize: 11),
            ),
          ],
        ],
      ),
    );
  }

  Widget _stat(String label, String value, IconData icon) => Expanded(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 3),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Column(
            children: [
              Icon(icon, color: _pink, size: 18),
              const SizedBox(height: 6),
              FittedBox(
                child: Text(
                  value,
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: _muted, fontSize: 10),
              ),
            ],
          ),
        ),
      );

  /// Per-QR breakdown — makes a poster that gets scans but no signups
  /// immediately obvious, which is the actionable business insight.
  Widget _perCodeCard() {
    if (_codes.isEmpty) return const SizedBox.shrink();
    final entries = _codes.entries.toList()
      ..sort((a, b) {
        final as = (a.value['scans'] as num?)?.toInt() ?? 0;
        final bs = (b.value['scans'] as num?)?.toInt() ?? 0;
        return bs.compareTo(as);
      });

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _pink.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Per-QR performance',
            style: GoogleFonts.outfit(
                color: _text, fontSize: 15, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 4),
          Text(
            'High opens + low signups = the QR works, the landing page does not.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 11),
          ),
          const SizedBox(height: 12),
          ...entries.map((e) {
            final scans = (e.value['scans'] as num?)?.toInt() ?? 0;
            final label = (e.value['label'] ?? '') as String;
            final type = (e.value['type'] ?? '') as String;
            final signups =
                _leads.where((l) => l.refCode == e.key).length;
            final rate = scans == 0 ? 0.0 : (signups / scans * 100);
            final healthy = rate >= 20 || scans == 0;
            return Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      e.key,
                      style: GoogleFonts.robotoMono(
                          color: _pink, fontSize: 11, fontWeight: FontWeight.w700),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          label.isEmpty ? '(no label)' : label,
                          overflow: TextOverflow.ellipsis,
                          style: GoogleFonts.outfit(
                              color: _text,
                              fontSize: 12,
                              fontWeight: FontWeight.w700),
                        ),
                        Text(
                          type,
                          style:
                              GoogleFonts.outfit(color: _muted, fontSize: 10),
                        ),
                      ],
                    ),
                  ),
                  Text(
                    '$scans opens · $signups joined',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    '${rate.toStringAsFixed(0)}%',
                    style: GoogleFonts.outfit(
                      color: healthy ? _green : _amber,
                      fontSize: 12,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ],
              ),
            );
          }),
        ],
      ),
    );
  }

  Widget _filtersCard() {
    final codeOptions = <String>{'all', ..._codes.keys}.toList();
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _pink.withValues(alpha: 0.18)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          TextField(
            style: GoogleFonts.outfit(color: _text, fontSize: 13),
            decoration: InputDecoration(
              hintText: 'Search name, phone, email, city, code…',
              hintStyle: GoogleFonts.outfit(color: _muted, fontSize: 13),
              prefixIcon: const Icon(Icons.search_rounded, color: _muted, size: 18),
              filled: true,
              fillColor: _card,
              contentPadding: const EdgeInsets.symmetric(vertical: 4),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
            ),
            onChanged: (v) => setState(() => _search = v.trim()),
          ),
          const SizedBox(height: 12),
          _chipRow('Role', ['all', 'customer', 'hero', 'seller'], _roleFilter,
              (v) => setState(() => _roleFilter = v)),
          const SizedBox(height: 8),
          _chipRow(
            'Contact',
            ['all', 'phone', 'email', 'both', 'none'],
            _reachFilter,
            (v) => setState(() => _reachFilter = v),
          ),
          const SizedBox(height: 8),
          _chipRow(
            'Period',
            ['0', '7', '30', '90'],
            '$_daysFilter',
            (v) => setState(() => _daysFilter = int.parse(v)),
            labelFor: (v) => v == '0' ? 'All time' : 'Last $v days',
          ),
          if (codeOptions.length > 1) ...[
            const SizedBox(height: 8),
            _chipRow('QR', codeOptions, _codeFilter,
                (v) => setState(() => _codeFilter = v)),
          ],
        ],
      ),
    );
  }

  Widget _chipRow(
    String title,
    List<String> values,
    String selected,
    void Function(String) onPick, {
    String Function(String)? labelFor,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title,
            style: GoogleFonts.outfit(
                color: _muted, fontSize: 10, fontWeight: FontWeight.w700)),
        const SizedBox(height: 6),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: values.map((v) {
              final on = v == selected;
              return Padding(
                padding: const EdgeInsets.only(right: 6),
                child: GestureDetector(
                  onTap: () => onPick(v),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 7),
                    decoration: BoxDecoration(
                      color: on ? _pink : _card,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      labelFor?.call(v) ?? (v == 'all' ? 'All' : v),
                      style: GoogleFonts.outfit(
                        color: on ? Colors.white : _muted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ),
              );
            }).toList(),
          ),
        ),
      ],
    );
  }

  Widget _syncNote() {
    final t = _lastSyncAt;
    return Row(
      children: [
        const Icon(Icons.bolt_rounded, color: _green, size: 14),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            t == null
                ? 'Incremental sync — only new rows are fetched.'
                : 'Last sync ${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')} · '
                    '$_lastFetchedCount new row(s) read · ${_leads.length} cached locally',
            style: GoogleFonts.outfit(color: _muted, fontSize: 10.5),
          ),
        ),
      ],
    );
  }

  Widget _leadTile(_Lead l) {
    final label = (_codes[l.refCode]?['label'] ?? '') as String;
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white.withValues(alpha: 0.05)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius: 18,
            backgroundColor: _pink.withValues(alpha: 0.18),
            child: Text(
              (l.name.isNotEmpty ? l.name[0] : '?').toUpperCase(),
              style: GoogleFonts.outfit(
                  color: _pink, fontWeight: FontWeight.w800, fontSize: 14),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  l.name.isEmpty ? '(no name)' : l.name,
                  style: GoogleFonts.outfit(
                      color: _text, fontSize: 13, fontWeight: FontWeight.w800),
                ),
                const SizedBox(height: 3),
                if (l.hasPhone)
                  _contactLine(Icons.phone_rounded, l.phone),
                if (l.hasEmail)
                  _contactLine(Icons.mail_outline_rounded, l.email),
                if (!l.isReachable)
                  Text(
                    'No contact details on file',
                    style: GoogleFonts.outfit(color: _amber, fontSize: 11),
                  ),
                const SizedBox(height: 5),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [
                    _tag(l.role, _pink),
                    if (l.refCode.isNotEmpty)
                      _tag(label.isEmpty ? l.refCode : '$label (${l.refCode})',
                          _green),
                    if (l.city.isNotEmpty) _tag(l.city, _muted),
                  ],
                ),
              ],
            ),
          ),
          if (l.createdAt != null)
            Text(
              '${l.createdAt!.day}/${l.createdAt!.month}',
              style: GoogleFonts.outfit(color: _muted, fontSize: 10),
            ),
        ],
      ),
    );
  }

  Widget _contactLine(IconData icon, String value) => Padding(
        padding: const EdgeInsets.only(bottom: 2),
        child: Row(
          children: [
            Icon(icon, size: 12, color: _muted),
            const SizedBox(width: 5),
            Expanded(
              child: Text(
                value,
                overflow: TextOverflow.ellipsis,
                style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
              ),
            ),
          ],
        ),
      );

  Widget _tag(String text, Color color) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.14),
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(
          text,
          style: GoogleFonts.outfit(
              color: color, fontSize: 9.5, fontWeight: FontWeight.w700),
        ),
      );
}
