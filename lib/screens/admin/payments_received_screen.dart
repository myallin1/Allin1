// ================================================================
// payments_received_screen.dart — Admin: MyAllin1 UPI Payments +
// Payment Disputes
// ================================================================
// Per Nizam's "Self vs MyAllin1" payment-collection split
// (hero_ride_screen.dart's _markPaymentReceived): when a hero marks
// "PAID TO MYALLIN1 (UPI)", the money already sits in the company's
// own UPI account (never touched the hero's wallet) — this screen is
// where Admin verifies/reconciles those collections, filterable by
// day/month.
//
// Also surfaces the PRE-EXISTING "Payment Not Received" dispute flow
// (hero_ride_screen.dart's _reportPaymentIssue / hero_history_screen.
// dart's _reportPaymentIssue — both already write `paymentDispute:
// true` + `adminAlertRequired: true` to the ride doc) — that data had
// zero admin-side visibility anywhere in the app before this screen;
// heroes could flag a ride as unpaid and it just sat in Firestore with
// nobody looking at it.
//
// Deliberately simple client-side month filtering (stream the most
// recent N docs ordered by timestamp, filter in memory) rather than a
// server-side date-range query — avoids needing a new Firestore
// composite index before the Aug 15 launch, and N=300 is already far
// more than a realistic month of either collection for this stage.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);

class PaymentsReceivedScreen extends StatefulWidget {
  const PaymentsReceivedScreen({super.key});

  @override
  State<PaymentsReceivedScreen> createState() =>
      _PaymentsReceivedScreenState();
}

class _PaymentsReceivedScreenState extends State<PaymentsReceivedScreen>
    with SingleTickerProviderStateMixin {
  late final TabController _tabController;
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month);

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _pickMonth() {
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: _surface,
      builder: (context) {
        final now = DateTime.now();
        final months = List<DateTime>.generate(
          12,
          (i) => DateTime(now.year, now.month - i),
        );
        return SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: months.map((m) {
              final label = '${_monthName(m.month)} ${m.year}';
              return ListTile(
                title: Text(label, style: GoogleFonts.outfit(color: _text)),
                trailing: (m.year == _selectedMonth.year &&
                        m.month == _selectedMonth.month)
                    ? const Icon(Icons.check_circle, color: _green)
                    : null,
                onTap: () {
                  setState(() => _selectedMonth = m);
                  Navigator.pop(context);
                },
              );
            }).toList(),
          ),
        );
      },
    );
  }

  String _monthName(int m) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][m - 1];

  bool _inSelectedMonth(DateTime? dt) {
    if (dt == null) return false;
    return dt.year == _selectedMonth.year && dt.month == _selectedMonth.month;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: Text(
          'Payments Received',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _purple,
          labelColor: _text,
          unselectedLabelColor: _muted,
          tabs: const [
            Tab(text: 'MyAllin1 UPI'),
            Tab(text: 'Disputes'),
          ],
        ),
        actions: [
          TextButton.icon(
            onPressed: _pickMonth,
            icon: const Icon(Icons.calendar_month_rounded, color: _gold),
            label: Text(
              '${_monthName(_selectedMonth.month)} ${_selectedMonth.year}',
              style: GoogleFonts.outfit(color: _gold, fontWeight: FontWeight.w700),
            ),
          ),
        ],
      ),
      body: TabBarView(
        controller: _tabController,
        children: [
          _buildCompanyPaymentsTab(),
          _buildDisputesTab(),
        ],
      ),
    );
  }

  Widget _buildCompanyPaymentsTab() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('company_payments_received')
          .orderBy('collectedAt', descending: true)
          .limit(300)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load: ${snapshot.error}',
              style: GoogleFonts.outfit(color: _red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }
        final docs = snapshot.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final ts = data['collectedAt'] as Timestamp?;
          return _inSelectedMonth(ts?.toDate());
        }).toList();

        double totalAmount = 0;
        for (final d in docs) {
          final data = d.data() as Map<String, dynamic>;
          totalAmount += (data['amount'] as num?)?.toDouble() ?? 0;
        }

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No MyAllin1 UPI collections this month.',
              style: GoogleFonts.outfit(color: _muted),
            ),
          );
        }

        return Column(
          children: [
            Container(
              margin: const EdgeInsets.all(14),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '${docs.length} collections',
                    style: GoogleFonts.outfit(color: _muted, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    '₹${totalAmount.toStringAsFixed(0)}',
                    style: GoogleFonts.outfit(
                      color: _green,
                      fontWeight: FontWeight.w900,
                      fontSize: 20,
                    ),
                  ),
                ],
              ),
            ),
            Expanded(
              child: ListView.separated(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                itemCount: docs.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (context, index) {
                  final data = docs[index].data() as Map<String, dynamic>;
                  final ts = (data['collectedAt'] as Timestamp?)?.toDate();
                  final verified = data['verified'] as bool? ?? false;
                  return Container(
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: _card,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                data['heroName']?.toString().isNotEmpty == true
                                    ? data['heroName'].toString()
                                    : 'Hero ${data['heroId']}',
                                style: GoogleFonts.outfit(
                                    color: _text, fontWeight: FontWeight.w700),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                ts != null
                                    ? '${ts.day}/${ts.month}/${ts.year} • ${ts.hour}:${ts.minute.toString().padLeft(2, '0')}'
                                    : '—',
                                style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          '₹${(data['amount'] as num?)?.toStringAsFixed(0) ?? '0'}',
                          style: GoogleFonts.outfit(
                              color: _gold, fontWeight: FontWeight.w800),
                        ),
                        const SizedBox(width: 10),
                        if (!verified)
                          OutlinedButton(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: _green,
                              side: const BorderSide(color: _green),
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                            ),
                            onPressed: () async {
                              await docs[index].reference.update({
                                'verified': true,
                                'verifiedAt': FieldValue.serverTimestamp(),
                              });
                            },
                            child: const Text('Verify'),
                          )
                        else
                          const Icon(Icons.verified_rounded, color: _green, size: 20),
                      ],
                    ),
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDisputesTab() {
    // FIX (root cause of the Firestore error on this screen): combining
    // a `.where('paymentDispute', isEqualTo: true)` filter with
    // `.orderBy('disputeRaisedAt', ...)` on a DIFFERENT field requires
    // a Firestore composite index, and none exists for this pair in
    // firestore.indexes.json — Firestore throws
    // "FAILED_PRECONDITION: The query requires an index" instead of
    // just running slower. Rather than add a composite index and wait
    // for it to build/propagate this close to the Aug 15 launch, this
    // now does the equality filter ONLY (no composite index needed for
    // a single-field equality filter) and sorts by disputeRaisedAt
    // client-side after fetching — genuine unpaid-ride disputes are a
    // small collection, so client-side sort is not a real cost here.
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .where('paymentDispute', isEqualTo: true)
          .limit(300)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Center(
            child: Text(
              'Failed to load: ${snapshot.error}',
              style: GoogleFonts.outfit(color: _red),
            ),
          );
        }
        if (!snapshot.hasData) {
          return const Center(child: CircularProgressIndicator(color: _purple));
        }
        final docs = snapshot.data!.docs.where((d) {
          final data = d.data() as Map<String, dynamic>;
          final ts = data['disputeRaisedAt'] as Timestamp?;
          return _inSelectedMonth(ts?.toDate());
        }).toList()
          ..sort((a, b) {
            final tsA = (a.data() as Map<String, dynamic>)['disputeRaisedAt'] as Timestamp?;
            final tsB = (b.data() as Map<String, dynamic>)['disputeRaisedAt'] as Timestamp?;
            return (tsB?.millisecondsSinceEpoch ?? 0)
                .compareTo(tsA?.millisecondsSinceEpoch ?? 0);
          });

        if (docs.isEmpty) {
          return Center(
            child: Text(
              'No unpaid-ride disputes this month.',
              style: GoogleFonts.outfit(color: _muted),
            ),
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.all(14),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            final data = docs[index].data() as Map<String, dynamic>;
            final ts = (data['disputeRaisedAt'] as Timestamp?)?.toDate();
            final fare = (data['finalFare'] ?? data['estimatedFare'] ?? data['fare']) as num?;
            final resolved = data['adminAlertRequired'] == false;
            return Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _card,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: _red.withValues(alpha: 0.4)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.report_problem_outlined, color: _red),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Ride ${docs[index].id}',
                          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '₹${fare?.toStringAsFixed(0) ?? '—'} • ${ts != null ? '${ts.day}/${ts.month}/${ts.year}' : '—'}',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 11),
                        ),
                      ],
                    ),
                  ),
                  if (!resolved)
                    OutlinedButton(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: _gold,
                        side: const BorderSide(color: _gold),
                        padding: const EdgeInsets.symmetric(horizontal: 10),
                      ),
                      onPressed: () async {
                        await docs[index].reference.update({
                          'adminAlertRequired': false,
                          'disputeResolvedAt': FieldValue.serverTimestamp(),
                        });
                      },
                      child: const Text('Mark Resolved'),
                    )
                  else
                    const Icon(Icons.check_circle, color: _green, size: 20),
                ],
              ),
            );
          },
        );
      },
    );
  }
}
