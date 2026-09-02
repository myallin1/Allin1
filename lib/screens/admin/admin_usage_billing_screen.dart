// ================================================================
// AdminUsageBillingScreen — Monthly seller/hero usage report
// ================================================================
// Shows completed-order counts (sellers) and completed-ride/task
// counts (heroes) for a selected month — the basis for the
// usage-based monthly billing Nizam wants instead of upfront
// commission. See usage_billing_service.dart for the counting logic
// and the "why this metric" reasoning.
//
// Deliberately a manual "Generate" button rather than a live listener
// — this is a periodic report, not something that needs to update in
// real time, and this session fixed several read-spike bugs caused by
// exactly this kind of always-on listener where a one-time query would
// do.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import '../../services/usage_billing_service.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _teal = Color(0xFF11998E);
const Color _tealLight = Color(0xFF38EF7D);
const Color _gold = Color(0xFFF5C542);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

class AdminUsageBillingScreen extends StatefulWidget {
  const AdminUsageBillingScreen({super.key});

  @override
  State<AdminUsageBillingScreen> createState() =>
      _AdminUsageBillingScreenState();
}

class _AdminUsageBillingScreenState extends State<AdminUsageBillingScreen> {
  final _service = UsageBillingService();
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  bool _isLoading = false;
  bool _hasGenerated = false;
  List<_UsageRow> _sellerRows = [];
  List<_UsageRow> _heroRows = [];

  Future<void> _generate() async {
    setState(() => _isLoading = true);
    try {
      final monthStart = _selectedMonth;
      final monthEnd = DateTime(monthStart.year, monthStart.month + 1);

      final sellerCounts = await _service.getSellerCompletedOrderCounts(
        monthStart: monthStart,
        monthEnd: monthEnd,
      );
      final heroCounts = await _service.getHeroCompletedTaskCounts(
        monthStart: monthStart,
        monthEnd: monthEnd,
      );

      final sellerRows = await _resolveNames(
        counts: sellerCounts,
        collection: 'sellers',
        nameField: 'name',
      );
      final heroRows = await _resolveNames(
        counts: heroCounts,
        collection: 'heroes',
        nameField: 'name',
      );

      sellerRows.sort((a, b) => b.count.compareTo(a.count));
      heroRows.sort((a, b) => b.count.compareTo(a.count));

      if (mounted) {
        setState(() {
          _sellerRows = sellerRows;
          _heroRows = heroRows;
          _hasGenerated = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to generate report: $e'),
              backgroundColor: const Color(0xFFFF5252),),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<List<_UsageRow>> _resolveNames({
    required Map<String, int> counts,
    required String collection,
    required String nameField,
  }) async {
    final rows = <_UsageRow>[];
    for (final entry in counts.entries) {
      String name = entry.key;
      try {
        final doc = await FirebaseFirestore.instance
            .collection(collection)
            .doc(entry.key)
            .trackedGet();
        final data = doc.data();
        if (data != null && data[nameField] is String) {
          name = data[nameField] as String;
        }
      } catch (_) {
        // Keep the raw ID as the fallback label — report still useful.
      }
      rows.add(_UsageRow(id: entry.key, name: name, count: entry.value));
    }
    return rows;
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      helpText: 'Pick any date in the month',
    );
    if (picked != null) {
      setState(() {
        _selectedMonth = DateTime(picked.year, picked.month);
        _hasGenerated = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final monthLabel = DateFormat('MMMM yyyy').format(_selectedMonth);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        title: Text('Usage Billing Report',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600),),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _pickMonth,
                    icon: const Icon(Icons.calendar_month, color: _teal),
                    label: Text(monthLabel,
                        style: GoogleFonts.outfit(color: _text),),
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: _border),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isLoading ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _teal,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 14,),
                  ),
                  child: _isLoading
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: Colors.white,),
                        )
                      : const Text('Generate',
                          style: TextStyle(color: Colors.white),),
                ),
              ],
            ),
            const SizedBox(height: 16),
            if (!_hasGenerated && !_isLoading)
              Expanded(
                child: Center(
                  child: Text(
                    'Pick a month and tap Generate to see completed '
                    'orders per seller and completed tasks per hero.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                  ),
                ),
              ),
            if (_hasGenerated)
              Expanded(
                child: ListView(
                  children: [
                    _sectionHeader('Sellers (catalog food orders)'),
                    if (_sellerRows.isEmpty) _emptyRow('No completed orders this month'),
                    ..._sellerRows.map((r) => _usageTile(r, 'orders')),
                    const SizedBox(height: 24),
                    _sectionHeader('Heroes (rides + tasks)'),
                    if (_heroRows.isEmpty) _emptyRow('No completed tasks this month'),
                    ..._heroRows.map((r) => _usageTile(r, 'tasks')),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Text(title,
            style: GoogleFonts.outfit(
                color: _gold, fontSize: 15, fontWeight: FontWeight.w700,),),
      );

  Widget _emptyRow(String text) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Text(text, style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
      );

  Widget _usageTile(_UsageRow row, String unit) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _border),
      ),
      child: Row(
        children: [
          Expanded(
            child: Text(row.name,
                style: GoogleFonts.outfit(color: _text, fontSize: 14),),
          ),
          Text('${row.count} $unit',
              style: GoogleFonts.outfit(
                  color: _tealLight, fontSize: 13, fontWeight: FontWeight.w700,),),
        ],
      ),
    );
  }
}

class _UsageRow {
  final String id;
  final String name;
  final int count;
  _UsageRow({required this.id, required this.name, required this.count});
}
