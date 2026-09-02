// ================================================================
// AdminUxAuditScreen — read-only viewer for the Synthetic QA Test-Bot's
// findings (ux_audit_reports collection).
// ================================================================
// NEW (CTO mandate — Synthetic QA Test-Bot, Step 2: Side Hamburger
// Tray Integration). Reads the `ux_audit_reports` collection the QA
// bot writes to (see integration_test/qa_five_screens_test.dart) and
// shows it grouped by run, newest first. This screen is 100%
// read-only — no button here writes anything, mirroring
// AdminDbUsageScreen's "manual Generate/Load, no live listener"
// pattern (a periodic diagnostic view, not something that needs to
// update live) rather than holding an open StreamBuilder for a
// collection nothing customer-facing ever touches.
import 'dart:async' show unawaited;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2A);
const Color _purple = Color(0xFF6C63FF);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF9999BB);

class AdminUxAuditScreen extends StatefulWidget {
  const AdminUxAuditScreen({super.key});

  @override
  State<AdminUxAuditScreen> createState() => _AdminUxAuditScreenState();
}

class _AdminUxAuditScreenState extends State<AdminUxAuditScreen> {
  bool _loading = false;
  String? _error;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _reports = const [];

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final snap = await FirebaseFirestore.instance
          .collection('ux_audit_reports')
          .orderBy('timestamp', descending: true)
          .limit(100)
          .trackedGet();
      if (!mounted) return;
      setState(() {
        _reports = snap.docs;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final findings = _reports.where((d) => (d.data()['status'] as String?) == 'finding').toList();
    final okCount = _reports.length - findings.length;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Text(
          'UX Audit Reports',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800, fontSize: 17),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded, color: _muted),
            tooltip: 'Reload',
            onPressed: _loading ? null : _load,
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _purple))
          : _error != null
              ? Center(
                  child: Padding(
                    padding: const EdgeInsets.all(24),
                    child: Text(
                      'Could not load reports:\n$_error',
                      style: const TextStyle(color: _red, fontSize: 13),
                      textAlign: TextAlign.center,
                    ),
                  ),
                )
              : _reports.isEmpty
                  ? Center(
                      child: Text(
                        'No QA runs yet.\nRun the Synthetic QA Test-Bot to populate this screen.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                      ),
                    )
                  : ListView(
                      padding: const EdgeInsets.all(16),
                      children: [
                        Row(
                          children: [
                            _SummaryChip(label: 'OK', count: okCount, color: _green),
                            const SizedBox(width: 10),
                            _SummaryChip(label: 'Findings', count: findings.length, color: _red),
                          ],
                        ),
                        const SizedBox(height: 16),
                        for (final doc in _reports) _ReportRow(data: doc.data()),
                      ],
                    ),
    );
  }
}

class _SummaryChip extends StatelessWidget {
  const _SummaryChip({required this.label, required this.count, required this.color});
  final String label;
  final int count;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: 0.4)),
      ),
      child: Text(
        '$label: $count',
        style: GoogleFonts.outfit(color: color, fontWeight: FontWeight.w700, fontSize: 12.5),
      ),
    );
  }
}

class _ReportRow extends StatelessWidget {
  const _ReportRow({required this.data});
  final Map<String, dynamic> data;

  @override
  Widget build(BuildContext context) {
    final isFinding = (data['status'] as String?) == 'finding';
    final screen = data['screen'] as String? ?? 'unknown';
    final step = data['step'] as String? ?? '';
    final findingText = data['findingText'] as String?;
    final screenshotUrl = data['screenshotUrl'] as String?;
    final ts = data['timestamp'] as Timestamp?;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: (isFinding ? _red : _green).withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(isFinding ? Icons.warning_amber_rounded : Icons.check_circle_outline_rounded,
                  color: isFinding ? _red : _green, size: 18),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  '$screen — $step',
                  style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700, fontSize: 13),
                ),
              ),
              if (ts != null)
                Text(
                  '${ts.toDate().day}/${ts.toDate().month} ${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}',
                  style: const TextStyle(color: _muted, fontSize: 10.5),
                ),
            ],
          ),
          if (isFinding && findingText != null && findingText.trim().isNotEmpty) ...[
            const SizedBox(height: 8),
            Text(findingText, style: const TextStyle(color: _muted, fontSize: 12.5)),
          ],
          if (screenshotUrl != null && screenshotUrl.trim().isNotEmpty) ...[
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: CachedCloudImage(
                screenshotUrl,
                height: 140,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) => const SizedBox.shrink(),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

