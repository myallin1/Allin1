// Full ride history for logged-in customer
// Shows past rides with: date, pickup, drop, fare, rating, status

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/hive_cache.dart';

// Theme Constants
const Color kBg = Color(0xFF08080F);
const Color kSurface = Color(0xFF111118);
const Color kCard = Color(0xFF1A1A26);
const Color kCard2 = Color(0xFF20202E);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x2E7B6FE0);

class RideHistoryScreen extends StatefulWidget {
  const RideHistoryScreen({super.key});

  @override
  State<RideHistoryScreen> createState() => _RideHistoryScreenState();
}

class _RideHistoryScreenState extends State<RideHistoryScreen> {
  // FIX B: replaced the live .snapshots() listener with the same
  // cache-first, one-time-.get() pattern hero_history_screen.dart already
  // uses successfully — this screen shows completed/immutable ride
  // history, so a live listener was never actually needed here and was
  // the single biggest source of re-reads (see FIX A's comment for the
  // rebuild-multiplication half of the problem; this fixes the "why does
  // it re-read AT ALL on a normal, non-rebuild open" half).
  //
  // Built once in initState() (same reasoning as FIX A) so the query
  // object itself stays stable even though it's no longer a live stream.
  late final Query<Map<String, dynamic>> _rideHistoryQuery;

  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rides = <Map<String, dynamic>>[];

  @override
  void initState() {
    super.initState();
    _rideHistoryQuery = FirebaseFirestore.instance
        .collection('rides')
        .where('userId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .orderBy('createdAt', descending: true)
        .limit(20)
        .withConverter<Map<String, dynamic>>(
          fromFirestore: (snap, _) => snap.data() ?? <String, dynamic>{},
          toFirestore: (data, _) => data,
        );
    unawaited(_loadRideHistory());
  }

  // Firestore's Timestamp type isn't one of Hive's natively-supported
  // types, so it can't be stored in the cache box as-is — encode to a
  // plain millisecondsSinceEpoch int for caching, and decode it back to
  // a Timestamp when reading from cache, so _RideHistoryCard (which
  // expects a Timestamp) doesn't need to know or care whether its data
  // came from cache or from a fresh Firestore read.
  Map<String, dynamic> _encodeRideForCache(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    final createdAt = copy['createdAt'];
    if (createdAt is Timestamp) {
      copy['createdAt'] = createdAt.millisecondsSinceEpoch;
    }
    return copy;
  }

  Map<String, dynamic> _decodeCachedRide(Map<String, dynamic> data) {
    final copy = Map<String, dynamic>.from(data);
    final createdAt = copy['createdAt'];
    if (createdAt is int) {
      copy['createdAt'] = Timestamp.fromMillisecondsSinceEpoch(createdAt);
    }
    return copy;
  }

  // forceRefresh:true is used by pull-to-refresh below to bypass the
  // cache and always hit Firestore, regardless of TTL freshness.
  Future<void> _loadRideHistory({bool forceRefresh = false}) async {
    if (!forceRefresh) {
      final cached =
          await HiveCache.get<List<dynamic>>(HiveCache.kRideHistory);
      if (cached != null) {
        if (mounted) {
          setState(() {
            _rides = cached
                .map((e) => _decodeCachedRide(Map<String, dynamic>.from(e as Map)))
                .toList();
            _loading = false;
            _error = null;
          });
        }
        return; // Fresh cache hit — zero Firestore reads.
      }
    }

    if (mounted && forceRefresh) {
      setState(() => _loading = true);
    }

    try {
      final snap = await _rideHistoryQuery.get();
      final rides = snap.docs.map((d) => d.data()).toList();
      if (mounted) {
        setState(() {
          _rides = rides;
          _loading = false;
          _error = null;
        });
      }
      await HiveCache.put(
        HiveCache.kRideHistory,
        rides.map(_encodeRideForCache).toList(),
        ttl: HiveCache.ttlRideHistory,
      );
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Could not load ride history. Pull down to retry.';
        });
      }
      debugPrint('[RideHistoryScreen] Load failed: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Column(
          children: [
            // AppBar with back button
            _buildHeader(context),
            // Cache-first ride history — see _loadRideHistory(). Wrapped
            // in RefreshIndicator so the customer can still force a fresh
            // Firestore read on demand, since this no longer auto-updates
            // live the way the old .snapshots() listener did.
            Expanded(
              child: RefreshIndicator(
                color: kGold,
                backgroundColor: kSurface,
                onRefresh: () => _loadRideHistory(forceRefresh: true),
                child: _loading
                    ? const Center(
                        child: CircularProgressIndicator(color: kGold),
                      )
                    : _error != null
                        ? _errorState(_error!)
                        : _rides.isEmpty
                            ? _emptyStateScrollable()
                            : ListView.builder(
                                padding: const EdgeInsets.all(16),
                                itemCount: _rides.length,
                                itemBuilder: (_, i) =>
                                    _RideHistoryCard(data: _rides[i]),
                              ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(bottom: BorderSide(color: kBorder)),
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(11),
                border: Border.all(color: kBorder),
              ),
              child:
                  const Icon(Icons.arrow_back_ios_new, size: 14, color: kMuted),
            ),
          ),
          const SizedBox(width: 12),
          Text(
            'Ride History',
            style: GoogleFonts.notoSansTamil(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              color: kText,
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptyState() => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.directions_bike, size: 50, color: kMuted),
            const SizedBox(height: 16),
            Text(
              'No rides yet!',
              style: GoogleFonts.inter(fontSize: 16, color: kText),
            ),
            const SizedBox(height: 6),
            const Text(
              'Book your first ride!',
              style: TextStyle(fontSize: 12, color: kMuted),
            ),
          ],
        ),
      );

  // RefreshIndicator's pull gesture needs a scrollable child underneath
  // it to detect the drag even when there's nothing to actually scroll —
  // a bare Center() (like _emptyState() alone) won't trigger it. This
  // wraps the same empty-state content in a minimal scrollable so
  // pull-to-refresh still works on a first-ever-open (empty history).
  Widget _emptyStateScrollable() => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: _emptyState(),
          ),
        ],
      );

  Widget _errorState(String message) => ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: [
          SizedBox(
            height: MediaQuery.of(context).size.height * 0.6,
            child: Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 44, color: kOrange),
                  const SizedBox(height: 14),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: GoogleFonts.inter(fontSize: 13, color: kMuted),
                  ),
                ],
              ),
            ),
          ),
        ],
      );
}

class _RideHistoryCard extends StatelessWidget {
  final Map<String, dynamic> data;
  const _RideHistoryCard({required this.data});

  Color _statusColor(String s) {
    switch (s) {
      case 'completed':
        return kGreen;
      case 'accepted':
        return kGold;
      case 'cancelled':
        return kOrange;
      default:
        return kMuted;
    }
  }

  @override
  Widget build(BuildContext context) {
    final fare = data['fare'] as num? ?? 0;
    final pickup = data['pickup'] as String? ?? '';
    final drop = data['drop'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final rating = data['customerRating'] as int? ?? 0;
    final rideType = data['rideType'] as String? ?? 'Bike';
    final ts = data['createdAt'] as Timestamp?;
    final date = ts != null
        ? '${ts.toDate().day}/${ts.toDate().month}/${ts.toDate().year}'
        : '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                rideType == 'Auto'
                    ? Icons.local_taxi
                    : rideType == 'Parcel'
                        ? Icons.local_shipping
                        : Icons.directions_bike,
                size: 20,
                color: kGold,
              ),
              const SizedBox(width: 8),
              Text(date, style: const TextStyle(fontSize: 11, color: kMuted)),
              const Spacer(),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _statusColor(status).withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: _statusColor(status).withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  status.toUpperCase(),
                  style: TextStyle(
                    fontSize: 8,
                    color: _statusColor(status),
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Text(
                '₹${fare.toInt()}',
                style: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kGold,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration:
                    const BoxDecoration(color: kGreen, shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  pickup,
                  style: const TextStyle(fontSize: 12, color: kText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          Padding(
            padding: const EdgeInsets.only(left: 3),
            child: Container(
              width: 2,
              height: 10,
              color: kBorder,
              margin: const EdgeInsets.symmetric(vertical: 2),
            ),
          ),
          Row(
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: BoxDecoration(
                  color: kOrange,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  drop,
                  style: const TextStyle(fontSize: 12, color: kText),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (rating > 0) ...[
            const SizedBox(height: 8),
            Row(
              children: List.generate(
                5,
                (i) => Icon(
                  i < rating ? Icons.star : Icons.star_border,
                  size: 14,
                  color: kGold,
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
  }
}
