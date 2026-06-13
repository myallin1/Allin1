// ================================================================
// CustomerRidesScreen — Admin Panel
// View all rides per customer, searchable by name or phone
// Firestore: rides collection, filtered by customerId / customerName
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _orange = Color(0xFFFF6B35);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class CustomerRidesScreen extends StatefulWidget {
  const CustomerRidesScreen({super.key});
  @override
  State<CustomerRidesScreen> createState() => _CustomerRidesScreenState();
}

class _CustomerRidesScreenState extends State<CustomerRidesScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return _green;
      case 'accepted':
      case 'in_progress':
      case 'arriving':
        return _orange;
      case 'searching':
        return _gold;
      default:
        return _red;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          '👤 Customer Ride History',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w800,
          ),
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
            child: TextField(
              controller: _searchCtrl,
              style: const TextStyle(color: _text),
              onChanged: (v) => setState(() => _query = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'Search by customer name or phone…',
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                prefixIcon: const Icon(Icons.search, color: _muted, size: 18),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                suffixIcon: _query.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: _muted, size: 16),
                        onPressed: () => setState(() {
                          _searchCtrl.clear();
                          _query = '';
                        }),
                      )
                    : null,
              ),
            ),
          ),
        ),
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rides')
            .orderBy('createdAt', descending: true)
            .limit(300)
            .snapshots(),
        builder: (context, snap) {
          if (snap.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: _gold),
            );
          }
          final allDocs = snap.data?.docs ?? [];
          // Client-side filter by name/phone
          final docs = _query.isEmpty
              ? allDocs
              : allDocs.where((doc) {
                  final d = doc.data()! as Map<String, dynamic>;
                  final name =
                      (d['customerName'] as String? ?? '').toLowerCase();
                  final phone =
                      (d['customerPhone'] as String? ?? '').toLowerCase();
                  return name.contains(_query) || phone.contains(_query);
                }).toList();

          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('🔍', style: TextStyle(fontSize: 48)),
                  const SizedBox(height: 12),
                  Text(
                    _query.isEmpty
                        ? 'No rides yet'
                        : 'No results for "$_query"',
                    style: GoogleFonts.outfit(color: _muted, fontSize: 14),
                  ),
                ],
              ),
            );
          }
          return _buildRidesList(docs);
        },
      ),
    );
  }

  Widget _buildRidesList(List<QueryDocumentSnapshot> docs) {
    // Group by customerId
    final Map<String, List<QueryDocumentSnapshot>> grouped = {};
    for (final doc in docs) {
      final d = doc.data()! as Map<String, dynamic>;
      final cid = d['customerId'] as String? ?? 'unknown';
      grouped.putIfAbsent(cid, () => []).add(doc);
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: grouped.length,
      itemBuilder: (context, i) {
        final cid = grouped.keys.elementAt(i);
        final rides = grouped[cid]!;
        final first = rides.first.data()! as Map<String, dynamic>;
        final name = first['customerName'] as String? ?? 'Unknown';
        final phone = first['customerPhone'] as String? ?? '—';
        final total = rides.fold<double>(
          0,
          (s, d) {
            final rd = d.data()! as Map<String, dynamic>;
            final finalFare = (rd['finalFare'] as num?)?.toDouble();
            final actualFare = (rd['actualFare'] as num?)?.toDouble();
            final tipAmount = (rd['tipAmount'] as num?)?.toDouble();
            final estFare = (rd['fare'] as num?)?.toDouble();
            return s + (finalFare ?? ((actualFare ?? 0) + (tipAmount ?? 0)) ?? estFare ?? 0.0);
          },
        );
        final completed = rides
            .where(
              (d) =>
                  (d.data()! as Map<String, dynamic>)['status'] == 'completed',
            )
            .length;

        return Container(
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: _card,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: _border),
          ),
          child: ExpansionTile(
            tilePadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
            childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            leading: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(
                color: _orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Center(
                child: Text(
                  name.isNotEmpty ? name[0].toUpperCase() : '?',
                  style: const TextStyle(
                    fontSize: 18,
                    color: _orange,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ),
            title: Text(
              name,
              style: const TextStyle(
                fontSize: 13,
                color: _text,
                fontWeight: FontWeight.w700,
              ),
            ),
            subtitle: Text(
              '$phone  •  ${rides.length} rides  •  ₹${total.toInt()} total',
              style: const TextStyle(fontSize: 10, color: _muted),
            ),
            trailing: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: _green.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                '$completed ✓',
                style: const TextStyle(
                  fontSize: 11,
                  color: _green,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            children: rides.map((rDoc) {
              final rd = rDoc.data()! as Map<String, dynamic>;
              final status = rd['status'] as String? ?? 'unknown';
              final fare = (rd['fare'] as num?)?.toInt() ?? 0;
              final tip = (rd['tipAmount'] as num?)?.toInt() ?? 0;
              final finalFare = (rd['finalFare'] as num?)?.toInt() ?? (fare + tip);
              final pickup = rd['pickup'] as String? ?? '—';
              final drop = rd['drop'] as String? ?? '—';
              final ts = rd['createdAt'] as Timestamp?;
              final time = ts != null
                  ? '${ts.toDate().day}/${ts.toDate().month}  '
                      '${ts.toDate().hour}:${ts.toDate().minute.toString().padLeft(2, '0')}'
                  : '—';
              final captain = rd['captainName'] as String? ?? '—';
              final color = _statusColor(status);
              return Container(
                margin: const EdgeInsets.only(bottom: 8),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: _bg,
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: color.withValues(alpha: 0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            time,
                            style: const TextStyle(fontSize: 10, color: _muted),
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 7, vertical: 3,),
                          decoration: BoxDecoration(
                            color: color.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            status.toUpperCase().replaceAll('_', ' '),
                            style: TextStyle(
                              fontSize: 8,
                              color: color,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            Text(
                              '₹$finalFare',
                              style: const TextStyle(
                                fontSize: 13,
                                color: _gold,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            if (tip > 0)
                              Text(
                                '+ ₹$tip tip',
                                style: const TextStyle(
                                  fontSize: 8,
                                  color: _muted,
                                ),
                              ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 6),
                    Text(
                      '🔴 $pickup',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '🟢 $drop',
                      style: const TextStyle(
                        fontSize: 11,
                        color: _text,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (captain != '—') ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Text(
                            '🏍️ $captain',
                            style: const TextStyle(
                              fontSize: 10,
                              color: _muted,
                            ),
                          ),
                          const Spacer(),
                          if (tip > 0)
                            Text(
                              'Fare: ₹$fare',
                              style: const TextStyle(
                                fontSize: 8,
                                color: _muted,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              );
            }).toList(),
          ),
        );
      },
    );
  }
}
