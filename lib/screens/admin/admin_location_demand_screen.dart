// ================================================================
// AdminLocationDemandScreen — Top searched locations in Erode
// ================================================================
// Per Nizam's request: shows which localities customers search for
// most often (pickup/drop address search in bike_booking_screen.dart,
// logged to location_search_logs — see that file's _logLocationSearch
// and this project's firestore.rules for the write-only-for-customers /
// admin-read rule), so admin can compare demand hotspots against where
// heroes have registered their preferredWorkLocation interest
// (hero_register_screen.dart / HeroApprovalsScreen detail dialog).
//
// Manual "Generate" report, same reasoning as AdminUsageBillingScreen —
// this is a periodic report, not something that needs a live listener.
// Aggregation (grouping + counting similar queries) happens client-side
// on a capped batch of recent logs rather than needing a new composite
// index or a Cloud Function.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF0D0D18);
const Color _card = Color(0xFF141420);
const Color _pink = Color(0xFFFF4FA3);
const Color _pinkLight = Color(0xFFFF92C8);
const Color _gold = Color(0xFFF5C542);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x267B6FE0);

class AdminLocationDemandScreen extends StatefulWidget {
  const AdminLocationDemandScreen({super.key});

  @override
  State<AdminLocationDemandScreen> createState() =>
      _AdminLocationDemandScreenState();
}

class _AdminLocationDemandScreenState
    extends State<AdminLocationDemandScreen> {
  static const List<int> _rangeOptions = [7, 30, 90];
  int _selectedRangeDays = 30;
  bool _isLoading = false;
  bool _hasGenerated = false;
  List<_DemandRow> _rows = [];
  int _totalSearches = 0;

  // Groups near-duplicate search text together (case/whitespace only —
  // deliberately NOT fuzzy-matching different spellings of the same
  // place, to avoid silently merging genuinely different localities).
  String _normalize(String query) => query.trim().toLowerCase();

  Future<void> _generate() async {
    setState(() => _isLoading = true);
    try {
      final since = DateTime.now().subtract(Duration(days: _selectedRangeDays));
      // Capped read — this is a demand SAMPLE, not an exhaustive count.
      // 2000 recent logs is plenty to see which localities dominate
      // without an unbounded/expensive query.
      final snapshot = await FirebaseFirestore.instance
          .collection('location_search_logs')
          .orderBy('createdAt', descending: true)
          .limit(2000)
          .trackedGet();

      final counts = <String, int>{};
      var total = 0;
      for (final doc in snapshot.docs) {
        final data = doc.data();
        final createdAt = data['createdAt'] as Timestamp?;
        if (createdAt != null && createdAt.toDate().isBefore(since)) continue;
        final rawQuery = data['query'] as String?;
        if (rawQuery == null || rawQuery.trim().isEmpty) continue;
        final key = _normalize(rawQuery);
        counts[key] = (counts[key] ?? 0) + 1;
        total++;
      }

      final rows = counts.entries
          .map((e) => _DemandRow(query: e.key, count: e.value))
          .toList()
        ..sort((a, b) => b.count.compareTo(a.count));

      if (mounted) {
        setState(() {
          _rows = rows.take(50).toList();
          _totalSearches = total;
          _hasGenerated = true;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to load demand report: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
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
          'Location Demand',
          // FIX (UI standardization, Aug 11 2026): explicit 18sp,
          // matching the app-bar title convention app-wide.
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w600, fontSize: 18),
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'What customers are actually searching for in Erode — use '
              "this alongside heroes' preferred work areas to spot "
              'coverage gaps.',
              style: GoogleFonts.outfit(color: _muted, fontSize: 12),
            ),
            const SizedBox(height: 14),
            Row(
              children: [
                Expanded(
                  child: DropdownButtonFormField<int>(
                    initialValue: _selectedRangeDays,
                    dropdownColor: _card,
                    decoration: InputDecoration(
                      filled: true,
                      fillColor: _card,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(horizontal: 14),
                    ),
                    items: _rangeOptions
                        .map((d) => DropdownMenuItem(
                              value: d,
                              child: Text('Last $d days',
                                  style: GoogleFonts.outfit(color: _text),),
                            ),)
                        .toList(),
                    onChanged: (v) {
                      if (v == null) return;
                      setState(() {
                        _selectedRangeDays = v;
                        _hasGenerated = false;
                      });
                    },
                  ),
                ),
                const SizedBox(width: 10),
                ElevatedButton(
                  onPressed: _isLoading ? null : _generate,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _pink,
                    padding:
                        const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
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
                    'Pick a range and tap Generate to see the most\n'
                    'searched locations in Erode.',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                  ),
                ),
              ),
            if (_hasGenerated) ...[
              Text(
                '$_totalSearches searches · ${_rows.length} unique locations',
                style: GoogleFonts.outfit(color: _muted, fontSize: 12),
              ),
              const SizedBox(height: 10),
              Expanded(
                child: _rows.isEmpty
                    ? Center(
                        child: Text(
                          'No searches logged in this range yet.',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 13),
                        ),
                      )
                    : ListView.builder(
                        itemCount: _rows.length,
                        itemBuilder: (context, i) =>
                            _demandTile(_rows[i], rank: i + 1),
                      ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _demandTile(_DemandRow row, {required int rank}) {
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
          SizedBox(
            width: 28,
            child: Text(
              '#$rank',
              style: GoogleFonts.outfit(
                color: rank <= 3 ? _gold : _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: Text(
              row.query,
              style: GoogleFonts.outfit(color: _text, fontSize: 14),
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            '${row.count}',
            style: GoogleFonts.outfit(
              color: _pinkLight,
              fontSize: 13,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _DemandRow {
  final String query;
  final int count;
  _DemandRow({required this.query, required this.count});
}
