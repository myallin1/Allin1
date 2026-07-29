// ================================================================
// AdminDetailedReportsScreen — grouped entry point for heavy,
// deep-database-read admin reports
// ================================================================
// Per Nizam's explicit request: these reports (Usage Billing, Location
// Demand, DB Monitor) should NOT be scattered as top-level options that
// could get tapped casually — they do a real, potentially large
// Firestore read each time. Grouped here under Taxi & Transportation's
// "Detailed Reports" entry (inside AdminDashboardScreen's More sheet),
// and each tile below shows an explicit warning dialog — "this will
// read a large number of documents, continue?" — before navigating
// into the actual report screen, so a deep read only ever happens when
// the admin deliberately confirms it, not from casually browsing menus.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'admin_db_usage_screen.dart';
import 'admin_location_demand_screen.dart';
import 'admin_usage_billing_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _pink = Color(0xFFFF4FA3);
const Color _gold = Color(0xFFF5C542);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);
const Color _warn = Color(0xFFFF5252);

class AdminDetailedReportsScreen extends StatelessWidget {
  const AdminDetailedReportsScreen({super.key});

  Future<bool> _confirmDeepRead(BuildContext context, String reportName, String detail) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _card,
        icon: const Icon(Icons.warning_amber_rounded, color: _warn, size: 32),
        title: Text(
          'Deep Database Read',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
        ),
        content: Text(
          '$reportName $detail\n\nOnly continue if you genuinely need this data right now — '
          'opening it uses Firestore reads.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 13),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text('Cancel', style: GoogleFonts.outfit(color: _muted)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(ctx, true),
            style: ElevatedButton.styleFrom(backgroundColor: _warn),
            child: Text('Continue', style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  Future<void> _openIfConfirmed(
    BuildContext context, {
    required String reportName,
    required String detail,
    required WidgetBuilder builder,
  }) async {
    final ok = await _confirmDeepRead(context, reportName, detail);
    if (ok && context.mounted) {
      Navigator.push(context, MaterialPageRoute<void>(builder: builder));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Text(
          'DB & Detailed Report',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text(
            'These reports read a larger amount of data than the usual '
            'screens — each one asks you to confirm before it actually '
            'reads anything, so app usage stays light unless you really need one.',
            style: GoogleFonts.outfit(color: _muted, fontSize: 12),
          ),
          const SizedBox(height: 16),
          _reportTile(
            context,
            icon: Icons.receipt_long_outlined,
            iconColor: const Color(0xFF00C853),
            label: 'Usage Billing Report',
            subtitle: 'Commission + fare totals over a date range',
            onTap: () => _openIfConfirmed(
              context,
              reportName: 'Usage Billing Report',
              detail: 'reads every ride in the selected date range to total commission and fares.',
              builder: (_) => const AdminUsageBillingScreen(),
            ),
          ),
          const SizedBox(height: 10),
          _reportTile(
            context,
            icon: Icons.map_outlined,
            iconColor: _gold,
            label: 'Location Demand',
            subtitle: 'Most-searched localities in Erode',
            onTap: () => _openIfConfirmed(
              context,
              reportName: 'Location Demand',
              detail: 'reads up to 2000 recent location search logs.',
              builder: (_) => const AdminLocationDemandScreen(),
            ),
          ),
          const SizedBox(height: 10),
          _reportTile(
            context,
            icon: Icons.query_stats_rounded,
            iconColor: _pink,
            label: 'DB Monitor',
            subtitle: 'Per-app Firestore read/write usage',
            onTap: () => _openIfConfirmed(
              context,
              reportName: 'DB Monitor',
              detail: 'reads the full db_usage_stats collection.',
              builder: (_) => const AdminDbUsageScreen(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _reportTile(
    BuildContext context, {
    required IconData icon,
    required Color iconColor,
    required String label,
    required String subtitle,
    required VoidCallback onTap,
  }) {
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
        decoration: BoxDecoration(
          color: _card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _border),
        ),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 22),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: GoogleFonts.outfit(
                          color: _text, fontSize: 14, fontWeight: FontWeight.w700)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
                ],
              ),
            ),
            const Icon(Icons.chevron_right_rounded, color: _muted, size: 18),
          ],
        ),
      ),
    );
  }
}
