// Full ride history for logged-in customer
// Shows past rides with: date, pickup, drop, fare, rating, status

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import '../services/db_usage_tracker.dart';
import '../services/hive_cache.dart';
import '../services/theme_service.dart';

// Theme Constants — NOTE (Nizam's full Option 2 rollout): kPurple/
// kPurple2 here are this screen's PRIMARY/SECONDARY brand color (not a
// decorative accent), so they get their own local sync rather than the
// shared app_palette.dart.
Color kBg      = const Color(0xFF08080F);
Color kSurface = const Color(0xFF111118);
Color kCard    = const Color(0xFF1A1A26);
Color kCard2   = const Color(0xFF20202E);
Color kPurple  = const Color(0xFF7B6FE0);
Color kPurple2 = const Color(0xFF9B8FF0);
Color kText    = const Color(0xFFEEEEF5);
Color kMuted   = const Color(0xFF7777A0);
Color kBorder  = const Color(0x2E7B6FE0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen  = Color(0xFF3DBA6F);
const Color kGold   = Color(0xFFF5C542);

void _syncRideHistoryPalette(BuildContext context) {
  ThemeService ts;
  try {
    ts = Provider.of<ThemeService>(context);
  } catch (_) {
    return;
  }
  final theme = ts.currentTheme;
  final cs = theme.colorScheme;
  kPurple = cs.primary;
  kPurple2 = cs.secondary;
  kBg = theme.scaffoldBackgroundColor;
  kSurface = cs.surface;
  kCard = cs.surface;
  kCard2 = Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface);
  kText = cs.onSurface;
  kMuted = cs.onSurface.withValues(alpha: 0.55);
  kBorder = theme.dividerColor;
}

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
    // NOTE: filter field is 'customerId', not 'userId' — the 'rides'
    // schema does not consistently write 'userId' on every document,
    // only 'customerId' is guaranteed present (see CHANGELOG). Using
    // 'userId' here silently returned zero rides for every customer.
    //
    // FIX (root cause of "Could not load ride history — pull down to
    // retry" — and pulling down NEVER actually fixed it, always the
    // exact same message): this combined a `.where('customerId', ...)`
    // equality filter with `.orderBy('createdAt', ...)` — two different
    // fields — which Firestore requires a composite index for.
    // firestore.indexes.json has a `customerId + status + createdAt`
    // index for `rides`, but NOT a plain `customerId + createdAt` one
    // (this query doesn't filter on status at all), so every single
    // read here threw `failed-precondition: requires an index`,
    // 100% of the time, for every customer — not a transient/flaky
    // failure at all. Pull-to-refresh forces a fresh Firestore call
    // (see forceRefresh in _loadRideHistory below) but it was hitting
    // the exact same broken query every time, which is exactly why
    // retrying never changed anything — same guaranteed failure, same
    // static error message. Fixed the same way as the earlier
    // Payments Received disputes-tab bug this session: drop the
    // orderBy (no composite index needed for a single equality filter
    // alone) and sort client-side instead — cheap, ride history is a
    // small per-customer list, and this avoids waiting on a Firestore
    // index build this close to launch. Limit bumped to 50 before the
    // client-side sort+truncate so "most recent 20" is still accurate
    // even for a customer with more than 20 rides ever.
    _rideHistoryQuery = FirebaseFirestore.instance
        .collection('rides')
        .where('customerId', isEqualTo: FirebaseAuth.instance.currentUser?.uid)
        .limit(50)
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
      DbUsageTracker.instance.recordRead(snap.docs.length, 'ride_history', 'fetch_rides');
      // Client-side sort (see the query-construction comment above for
      // why orderBy was removed) + truncate to the 20 most recent.
      final rides = snap.docs.map((d) => d.data()).toList()
        ..sort((a, b) {
          final tsA = a['createdAt'];
          final tsB = b['createdAt'];
          final msA = tsA is Timestamp ? tsA.millisecondsSinceEpoch : 0;
          final msB = tsB is Timestamp ? tsB.millisecondsSinceEpoch : 0;
          return msB.compareTo(msA);
        });
      final limitedRides = rides.take(20).toList();
      if (mounted) {
        setState(() {
          _rides = limitedRides;
          _loading = false;
          _error = null;
        });
      }
      await HiveCache.put(
        HiveCache.kRideHistory,
        limitedRides.map(_encodeRideForCache).toList(),
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
    _syncRideHistoryPalette(context);
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
      decoration: BoxDecoration(
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
                  Icon(Icons.arrow_back_ios_new, size: 14, color: kMuted),
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
            Icon(Icons.directions_bike, size: 50, color: kMuted),
            const SizedBox(height: 16),
            Text(
              'No rides yet!',
              style: GoogleFonts.outfit(fontSize: 16, color: kText),
            ),
            const SizedBox(height: 6),
            Text(
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
                    style: GoogleFonts.outfit(fontSize: 13, color: kMuted),
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
    final pickup = data['pickupAddress'] as String? ?? '';
    final drop = data['dropAddress'] as String? ?? '';
    final status = data['status'] as String? ?? 'pending';
    final rating = data['customerRating'] as int? ?? 0;
    final category = data['category'] as String? ?? 'bike';
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
                switch (category) {
                  'auto' => Icons.local_taxi,
                  'car' => Icons.directions_car,
                  'parcel' => Icons.local_shipping,
                  'mini_truck' || 'lorry' => Icons.local_shipping_outlined,
                  'emergency_manpower' => Icons.support_agent_rounded,
                  _ => Icons.directions_bike,
                },
                size: 20,
                color: kGold,
              ),
              const SizedBox(width: 8),
              Text(date, style: TextStyle(fontSize: 11, color: kMuted)),
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
                  style: TextStyle(fontSize: 12, color: kText),
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
                  style: TextStyle(fontSize: 12, color: kText),
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