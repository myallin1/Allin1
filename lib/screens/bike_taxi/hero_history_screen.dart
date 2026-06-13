import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../widgets/hero_premium_loader.dart';

class HeroHistoryScreen extends StatefulWidget {
  const HeroHistoryScreen({super.key});

  @override
  State<HeroHistoryScreen> createState() => _HeroHistoryScreenState();
}

class _HeroHistoryScreenState extends State<HeroHistoryScreen>
    with AutomaticKeepAliveClientMixin {
  static const Color _bg = Color(0xFFFFFBFE);
  static const Color _surface = Colors.white;
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _border = Color(0x33FF4FA3);

  final List<_HeroHistoryItem> _rides = <_HeroHistoryItem>[];
  bool _loading = true;
  bool _syncing = false;
  String? _errorMessage;
  DateTime? _lastServerSyncAt;
  static const Duration _syncThrottle = Duration(seconds: 30);
  double _aggregateEarnings = 0;
  int _aggregateRides = 0;
  double _aggregateRating = 0;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    unawaited(_loadHistory());
    unawaited(_loadAggregates());
  }

    Future<void> _loadAggregates() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final heroDoc = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(uid)
          .get(const GetOptions(source: Source.cache));
      if (!mounted) return;
      final data = heroDoc.data() ?? {};
      setState(() {
        _aggregateEarnings = (data['totalEarnings'] as num?)?.toDouble() ?? 0;
        _aggregateRides = (data['totalRides'] as int?) ?? 0;
        _aggregateRating = (data['averageRating'] as num?)?.toDouble() ?? 0;
      });
      // Refresh from server
      final serverDoc = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(uid)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final serverData = serverDoc.data() ?? {};
      setState(() {
        _aggregateEarnings = (serverData['totalEarnings'] as num?)?.toDouble() ?? 0;
        _aggregateRides = (serverData['totalRides'] as int?) ?? 0;
        _aggregateRating = (serverData['averageRating'] as num?)?.toDouble() ?? 0;
      });
    } catch (_) {}
  }

  Query<Map<String, dynamic>>? _historyQuery() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null || uid.isEmpty) {
      return null;
    }
    return FirebaseFirestore.instance
        .collection('rides')
        .where('heroId', isEqualTo: uid)
        .limit(20);
  }

  DateTime? _extractWhen(Map<String, dynamic> data) {
    final candidates = <Object?>[
      data['paidAt'],
      data['completedAt'],
      data['archivedAt'],
      data['createdAt'],
    ];
    for (final value in candidates) {
      if (value is Timestamp) {
        return value.toDate();
      }
    }
    return null;
  }

  List<_HeroHistoryItem> _mapSnapshot(QuerySnapshot<Map<String, dynamic>> snap) {
    final items = snap.docs
        .map((doc) => _HeroHistoryItem.fromMap(doc.id, doc.data(), _extractWhen))
        .where((item) => item.isCompleted)
        .toList()
      ..sort((a, b) => b.when.compareTo(a.when));
    return items;
  }

  Future<void> _loadHistory() async {
    final query = _historyQuery();
    if (query == null) {
      if (!mounted) {
        return;
      }
      setState(() {
        _loading = false;
        _errorMessage = 'Hero session unavailable.';
      });
      return;
    }

    try {
      final cacheSnap = await query.get(const GetOptions(source: Source.cache));
      if (!mounted) {
        return;
      }
      setState(() {
        _rides
          ..clear()
          ..addAll(_mapSnapshot(cacheSnap));
        _loading = false;
        _errorMessage = null;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }

    unawaited(_refreshFromServer(silent: true));
  }

  Future<void> _refreshFromServer({bool silent = false}) async {
    final now = DateTime.now();
    if (_lastServerSyncAt != null &&
        now.difference(_lastServerSyncAt!) < _syncThrottle) {
      return;
    }
    _lastServerSyncAt = now;
    final query = _historyQuery();
    if (query == null) {
      return;
    }
    if (mounted) {
      setState(() {
        _syncing = true;
        if (!silent) {
          _errorMessage = null;
        }
      });
    }
    try {
      final serverSnap = await query.get(const GetOptions(source: Source.server));
      if (!mounted) {
        return;
      }
      setState(() {
        _rides
          ..clear()
          ..addAll(_mapSnapshot(serverSnap));
        _syncing = false;
        _errorMessage = null;
        _lastServerSyncAt = DateTime.now();
      });
    } catch (e) {
      if (!mounted) {
        return;
      }
      setState(() {
        _syncing = false;
        if (_rides.isEmpty) {
          _errorMessage = 'Unable to sync latest rides right now.';
        }
      });
    }
  }

  double get _totalEarnings => _aggregateEarnings;
  int get _totalRides => _aggregateRides;
  double get _averageRating => _aggregateRating;

  @override
  Widget build(BuildContext context) {
    super.build(context);
    return ColoredBox(
      color: _bg,
      child: SafeArea(
        child: Column(
          children: [
            _buildHeader(),
            _buildSummary(),
            Expanded(
              child: RefreshIndicator(
                color: _pink,
                onRefresh: _refreshFromServer,
                child: _buildContent(),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader() => Container(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        decoration: const BoxDecoration(
          color: _surface,
          border: Border(bottom: BorderSide(color: _border)),
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  colors: [_pink, Color(0xFFFF97C8)],
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: const Icon(
                Icons.receipt_long_rounded,
                color: Colors.white,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Earnings & History',
                    style: GoogleFonts.outfit(
                      fontSize: 18,
                      color: _text,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  Text(
                    _lastServerSyncAt == null
                        ? 'Cache-first mode enabled'
                        : 'Last synced ${_formatTime(_lastServerSyncAt!)}',
                    style: GoogleFonts.outfit(
                      fontSize: 12,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
            if (_syncing)
              const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(
                  strokeWidth: 2.2,
                  color: _pink,
                ),
              ),
          ],
        ),
      );

  Widget _buildSummary() => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Row(
          children: [
            Expanded(
              child: _summaryCard(
                label: 'Completed Rides',
                value: '$_totalRides',
                icon: Icons.two_wheeler_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                label: 'Total Earnings',
                value: '₹${_totalEarnings.toStringAsFixed(0)}',
                icon: Icons.currency_rupee_rounded,
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: _summaryCard(
                label: 'Avg Rating',
                value: _aggregateRating > 0 ? _aggregateRating.toStringAsFixed(1) : '0.0',
                icon: Icons.star_rounded,
              ),
            ),
          ],
        ),
      );

  Widget _summaryCard({
    required String label,
    required String value,
    required IconData icon,
  }) =>
      Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _border),
          boxShadow: const [
            BoxShadow(
              color: Color(0x12FF4FA3),
              blurRadius: 20,
              offset: Offset(0, 10),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: _pink),
            const SizedBox(height: 12),
            Text(
              value,
              style: GoogleFonts.outfit(
                fontSize: 22,
                color: _text,
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: GoogleFonts.outfit(
                fontSize: 12,
                color: _muted,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      );

  Widget _buildContent() {
    if (_loading && _rides.isEmpty) {
      return const HeroPremiumLoader(
        compact: true,
        title: 'Loading Earnings',
        subtitle: 'Reading your cached trips and syncing premium ride history',
        icon: Icons.receipt_long_rounded,
      );
    }

    if (_errorMessage != null && _rides.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: Column(
                children: [
                  const Icon(
                    Icons.cloud_off_rounded,
                    size: 52,
                    color: _muted,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _errorMessage!,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.outfit(
                      fontSize: 14,
                      color: _text,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
    }

    if (_rides.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          const SizedBox(height: 120),
          Center(
            child: Column(
              children: [
                const Icon(
                  Icons.receipt_long_rounded,
                  size: 54,
                  color: _muted,
                ),
                const SizedBox(height: 16),
                Text(
                  'No completed rides yet',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: _text,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'Completed rides will appear here from cache first.',
                  style: GoogleFonts.outfit(
                    fontSize: 12,
                    color: _muted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      physics: const AlwaysScrollableScrollPhysics(),
      itemBuilder: (context, index) => _HistoryCard(
        item: _rides[index],
        onReportIssue: () => _reportPaymentIssue(_rides[index]),
      ),
      separatorBuilder: (_, __) => const SizedBox(height: 12),
      itemCount: _rides.length,
    );
  }

  Future<void> _reportPaymentIssue(_HeroHistoryItem item) async {
    if (item.paymentSettled || item.paymentDispute) {
      return;
    }
    try {
      await FirebaseFirestore.instance.collection('rides').doc(item.id).set(
        {
          'status': 'dispute',
          'paymentStatus': 'dispute',
          'paymentDispute': true,
          'disputeReason': 'payment_not_received',
          'disputeRaisedBy': FirebaseAuth.instance.currentUser?.uid ?? '',
          'disputeRaisedAt': FieldValue.serverTimestamp(),
          'adminAlertRequired': true,
          'archivedAt': FieldValue.serverTimestamp(),
          'archivedForHero': true,
        },
        SetOptions(merge: true),
      );
      if (!mounted) {
        return;
      }
      setState(() {
        final index = _rides.indexWhere((ride) => ride.id == item.id);
        if (index >= 0) {
          _rides[index] = _rides[index].copyWith(
            status: 'dispute',
            paymentStatus: 'dispute',
            paymentDispute: true,
          );
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Payment dispute reported to admin.'),
          backgroundColor: _pink,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) {
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to report dispute right now.'),
          backgroundColor: Colors.redAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
    }
  }

  String _formatTime(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    final suffix = time.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $suffix';
  }
}

class _HeroHistoryItem {
  _HeroHistoryItem({
    required this.id,
    required this.pickup,
    required this.drop,
    required this.status,
    required this.paymentStatus,
    required this.paymentDispute,
    required this.amount,
    required this.tip,
    required this.netEarnings,
    required this.when,
  });

  final String id;
  final String pickup;
  final String drop;
  final String status;
  final String paymentStatus;
  final bool paymentDispute;
  final double amount;
  final double tip;
  final double netEarnings;
  final DateTime when;

  bool get isCompleted {
    return when.millisecondsSinceEpoch > 0 &&
        (status == 'completed' ||
            status == 'paid' ||
            status == 'pending_collection' ||
            status == 'dispute');
  }

  bool get paymentSettled =>
      paymentStatus == 'paid' ||
      paymentStatus == 'completed' ||
      paymentStatus == 'paid_by_wallet' ||
      paymentStatus == 'paid_offline_p2p';

  bool get canReportIssue => !paymentSettled && !paymentDispute;

  _HeroHistoryItem copyWith({
    String? status,
    String? paymentStatus,
    bool? paymentDispute,
  }) {
    return _HeroHistoryItem(
      id: id,
      pickup: pickup,
      drop: drop,
      status: status ?? this.status,
      paymentStatus: paymentStatus ?? this.paymentStatus,
      paymentDispute: paymentDispute ?? this.paymentDispute,
      amount: amount,
      tip: tip,
      netEarnings: netEarnings,
      when: when,
    );
  }

  static _HeroHistoryItem fromMap(
    String id,
    Map<String, dynamic> data,
    DateTime? Function(Map<String, dynamic>) whenReader,
  ) {
    return _HeroHistoryItem(
      id: id,
      pickup: (data['pickupAddress'] as String?)?.trim().isNotEmpty ?? false
          ? (data['pickupAddress'] as String).trim()
          : ((data['pickup'] as String?)?.trim() ?? 'Pickup unavailable'),
      drop: (data['dropAddress'] as String?)?.trim().isNotEmpty ?? false
          ? (data['dropAddress'] as String).trim()
          : ((data['drop'] as String?)?.trim() ?? 'Drop unavailable'),
      status: (data['status'] as String? ?? '').trim(),
      paymentStatus: (data['paymentStatus'] as String? ?? '').trim(),
      paymentDispute: data['paymentDispute'] == true,
      amount: ((data['finalFare'] ?? data['amountPaid'] ?? data['lockedFare'] ?? data['fare']) as num?)
              ?.toDouble() ??
          0.0,
      tip: (data['tip'] as num?)?.toDouble() ?? 0.0,
      netEarnings: (data['netEarnings'] as num?)?.toDouble() ??
          ((data['finalFare'] ?? data['amountPaid'] ?? data['lockedFare'] ?? data['fare']) as num?)
              ?.toDouble() ??
          0.0,
      when: whenReader(data) ?? DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class _HistoryCard extends StatelessWidget {
  const _HistoryCard({
    required this.item,
    required this.onReportIssue,
  });

  static const Color _surface = Colors.white;
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _green = Color(0xFF00A86B);
  static const Color _text = Color(0xFF3D1230);
  static const Color _muted = Color(0xFF8F5A78);
  static const Color _border = Color(0x33FF4FA3);
  static const Color _cardTint = Color(0xFFFFF1F8);

  final _HeroHistoryItem item;
  final VoidCallback onReportIssue;

  @override
  Widget build(BuildContext context) {
    final statusColor = item.status == 'paid' ? _green : _pink;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x10FF4FA3),
            blurRadius: 18,
            offset: Offset(0, 8),
          ),
        ],
      ),
      child: Column(
        children: [
          Row(
            children: [
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(
                  color: _cardTint,
                  borderRadius: BorderRadius.circular(16),
                ),
                child: const Icon(Icons.route_rounded, color: _pink),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.pickup,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 14,
                        color: _text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      item.drop,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: GoogleFonts.outfit(
                        fontSize: 12,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: statusColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: statusColor.withValues(alpha: 0.28)),
                ),
                child: Text(
                  item.status.toUpperCase(),
                  style: GoogleFonts.outfit(
                    fontSize: 10,
                    color: statusColor,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: _cardTint,
              borderRadius: BorderRadius.circular(16),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Text(
                            '₹${item.amount.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: _pink,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (item.tip > 0) ...[
                            Text(
                              '  +  ₹${item.tip.toStringAsFixed(0)}',
                              style: GoogleFonts.outfit(
                                fontSize: 12,
                                color: const Color(0xFFFFBB00),
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                          Text(
                            '  =  ',
                            style: GoogleFonts.outfit(
                              fontSize: 12,
                              color: _muted,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          Text(
                            '₹${item.netEarnings.toStringAsFixed(0)}',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: const Color(0xFF00A86B),
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Fare${item.tip > 0 ? ' + Tip' : ''} = Total',
                        style: GoogleFonts.outfit(
                          fontSize: 9,
                          color: _muted,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    const Icon(Icons.calendar_today_rounded, size: 12, color: _muted),
                    const SizedBox(height: 2),
                    Text(
                      '${item.when.day}/${item.when.month}',
                      style: GoogleFonts.outfit(
                        fontSize: 10,
                        color: _muted,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (item.canReportIssue) ...[
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerRight,
              child: OutlinedButton.icon(
                onPressed: onReportIssue,
                icon: const Icon(Icons.report_problem_outlined, size: 18),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.redAccent,
                  side: const BorderSide(color: Colors.redAccent),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                label: Text(
                  'Payment Not Received',
                  style: GoogleFonts.outfit(
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  // _miniStat removed — dead code, was never called anywhere.

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_HeroHistoryItem>('item', item));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onReportIssue', onReportIssue));
  }
}
