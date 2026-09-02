// ================================================================
// hero_incomplete_tasks_screen.dart — Incomplete / Stuck Tasks Hub
// ================================================================
// NEW (Aug 11 2026, per Nizam — Customer Service Management & Recovery
// System). This is the hero-facing half of the fix for the
// `[HeroPing] DROPPED: hero already on a service request` stuck bug:
// a manual escape hatch a hero can reach any time from the side drawer,
// independent of whatever auto-restore/staleness logic hero_home_screen
// applies to its own busy-gate.
//
// Lists every ride/service_request currently assigned to this hero in
// an active (non-terminal) status — including ones far outside the
// 24h "recent" window hero_home_screen uses for its own inline active-
// ride card, since the whole point of this screen is to surface tasks
// that got stuck for exactly that kind of reason.
//
// Two actions per task:
//   Resume  — pushes the SAME tracking screens the app already uses
//             elsewhere (CaptainRideScreen for rides,
//             HeroTaskDetailScreen for service_requests) — no new
//             tracking UI invented here.
//   Release — hands the task back to admin (status -> 'admin_review',
//             hero's claim cleared) via the exact same
//             ServiceRequestService.releaseServiceRequest() /
//             HeroTaskRecoveryService.releaseRide() methods, so this
//             screen is just a second entry point into logic that
//             already exists (or, for rides, a small new Firestore-only
//             method — see hero_task_recovery_service.dart for why no
//             RTDB write is needed there).
//
// Live listeners here are intentionally scoped to `heroId == this hero`
// / `assignedHeroId == this hero` — bounded by one hero's own task
// count, not the fleet, so this is not the kind of unbounded-read
// concern the admin fetch-on-demand screens exist to avoid.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/ride_model.dart';
import '../../services/hero_task_recovery_service.dart';
import '../../services/service_request_service.dart';
import 'hero_home_screen.dart' show HeroTaskDetailScreen;
import 'hero_ride_screen.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFFFFF7FB);
const Color _card = Colors.white;
const Color _pink = Color(0xFFFF4FA3);
const Color _text = Color(0xFF1A1A2E);
const Color _muted = Color(0xFF8F5A78);
const Color _red = Color(0xFFFF5252);
const Color _green = Color(0xFF00C853);
const Color _amber = Color(0xFFFFB347);

/// Ride statuses that count as "still on this hero's plate" for THIS
/// screen. Deliberately broader than hero_home_screen's
/// `_restorableRideStatuses` (['accepted','in_progress']) — 'arrived' is
/// a real intermediate state a ride can be stuck in too, and this hub
/// has no time cutoff, unlike the home screen's 24h inline card.
const List<String> kStuckRideStatuses = <String>[
  'accepted',
  'arrived',
  'in_progress',
];

/// service_requests statuses that count as active for a hero. Mirrors
/// kServiceRequestAdvanceOrder minus 'completed'/'admin_review'.
const List<String> kStuckServiceRequestStatuses = <String>[
  'hero_assigned',
  'in_progress',
  'nearing_completion',
];

class HeroIncompleteTasksScreen extends StatefulWidget {
  const HeroIncompleteTasksScreen({super.key});

  @override
  State<HeroIncompleteTasksScreen> createState() =>
      _HeroIncompleteTasksScreenState();
}

class _HeroIncompleteTasksScreenState
    extends State<HeroIncompleteTasksScreen> {
  String? _busyId;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: Text(
          'Incomplete / Stuck Tasks',
          style: GoogleFonts.outfit(
            color: _text,
            fontWeight: FontWeight.w800,
            fontSize: 17,
          ),
        ),
      ),
      body: uid == null
          ? const Center(child: Text('Not signed in'))
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 24),
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 14),
                  decoration: BoxDecoration(
                    color: _pink.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _pink.withValues(alpha: 0.25)),
                  ),
                  child: Text(
                    'Any ride or service task still assigned to you shows '
                    'here, even old ones. Resume to keep working on it, or '
                    'Release to send it to admin — Release also '
                    'immediately frees you up to receive new job pings.',
                    style: GoogleFonts.outfit(
                      color: _muted,
                      fontSize: 12,
                      height: 1.4,
                    ),
                  ),
                ),
                Text(
                  'RIDES',
                  style: GoogleFonts.outfit(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                _buildRidesSection(uid),
                const SizedBox(height: 20),
                Text(
                  'SERVICE TASKS',
                  style: GoogleFonts.outfit(
                    color: _muted,
                    fontSize: 11,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.1,
                  ),
                ),
                const SizedBox(height: 8),
                _buildServiceRequestsSection(uid),
              ],
            ),
    );
  }

  Widget _buildRidesSection(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .where('heroId', isEqualTo: uid)
          .where('status', whereIn: kStuckRideStatuses)
          .trackedSnapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(color: _pink),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return _emptyRow('No stuck rides.');
        }
        return Column(
          children: [for (final doc in docs) _rideRow(doc)],
        );
      },
    );
  }

  Widget _buildServiceRequestsSection(String uid) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .where('assignedHeroId', isEqualTo: uid)
          .where('status', whereIn: kStuckServiceRequestStatuses)
          .trackedSnapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 8),
            child: SizedBox(
              height: 3,
              child: LinearProgressIndicator(color: _pink),
            ),
          );
        }
        final docs = snapshot.data!.docs;
        if (docs.isEmpty) {
          return _emptyRow('No stuck service tasks.');
        }
        return Column(
          children: [for (final doc in docs) _serviceRequestRow(doc)],
        );
      },
    );
  }

  Widget _emptyRow(String label) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _pink.withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          const Icon(Icons.check_circle_rounded, color: _green, size: 18),
          const SizedBox(width: 8),
          Text(label,
              style: GoogleFonts.outfit(color: _muted, fontSize: 12.5)),
        ],
      ),
    );
  }

  // ── Rides ────────────────────────────────────────────────────
  Widget _rideRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final status = (d['status'] as String?) ?? '';
    final pickup = (d['pickupAddress'] as String?) ?? '';
    final drop = (d['dropAddress'] as String?) ?? '';
    final busy = _busyId == doc.id;

    return _taskCard(
      title: _prettyCategory((d['category'] as String?) ?? 'bike'),
      subtitle: pickup.isEmpty && drop.isEmpty
          ? 'No address on file'
          : '$pickup → $drop',
      status: status,
      busy: busy,
      onResume: () => _resumeRide(doc.id, d),
      onRelease: () => _confirmAndReleaseRide(doc.id),
    );
  }

  Future<void> _resumeRide(String rideId, Map<String, dynamic> d) async {
    final ride = RideModel(
      id: rideId,
      rideId: rideId,
      customerId: d['customerId'] as String?,
      heroId: d['heroId'] as String?,
      pickupAddress: d['pickupAddress'] as String?,
      dropAddress: d['dropAddress'] as String?,
      pickupLatitude: (d['pickupLat'] as num?)?.toDouble(),
      pickupLongitude: (d['pickupLng'] as num?)?.toDouble(),
      dropLatitude: (d['dropLat'] as num?)?.toDouble(),
      dropLongitude: (d['dropLng'] as num?)?.toDouble(),
      fare: (d['fare'] as num?)?.toDouble(),
      estimatedFare: (d['estimatedFare'] as num?)?.toDouble(),
      distanceKm: (d['distanceKm'] as num?)?.toDouble(),
      status: (d['status'] as String?) ?? 'accepted',
      vehicleType:
          (d['category'] as String?) ?? (d['vehicleType'] as String?),
      heroName: d['heroName'] as String?,
      heroPhone: d['heroPhone'] as String?,
      heroVehicleNumber: d['heroVehicleNumber'] as String?,
    );
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => CaptainRideScreen(ride: ride, rideDocId: rideId),
      ),
    );
  }

  Future<void> _confirmAndReleaseRide(String rideId) async {
    final confirmed = await _confirmRelease(context);
    if (!confirmed || !mounted) return;
    setState(() => _busyId = rideId);
    try {
      await HeroTaskRecoveryService.instance.releaseRide(rideId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _pink,
          content: Text('Ride released — sent to admin, you can now '
              'receive new pings.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: _red, content: Text('Could not release: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ── Service requests ────────────────────────────────────────
  Widget _serviceRequestRow(QueryDocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data();
    final status = (d['status'] as String?) ?? '';
    final busy = _busyId == doc.id;

    // FIX (Sep 2 2026 — service-booking flow audit, same class of bug as
    // hero_home_screen.dart's ping-dialog fixes): every skill trade
    // (electrician, plumber, ..., acting_driver) shares requestType
    // 'electronics_service', so _prettyCategory() showed the literal
    // "electronics service" for every one of them here — a hero with
    // three open skill tasks saw three identically-labeled cards with
    // no way to tell which was which without opening each one. The
    // actual trade name is on `details.categoryLabel` (written by
    // skilled_services_screen.dart), so prefer that when present.
    final requestType = (d['requestType'] as String?) ?? '';
    final details = d['details'] as Map?;
    final categoryLabel = requestType == 'electronics_service'
        ? (details?['categoryLabel'] as String?)?.trim()
        : null;
    final title = (categoryLabel != null && categoryLabel.isNotEmpty)
        ? categoryLabel
        : _prettyCategory(requestType);

    return _taskCard(
      title: title,
      subtitle: (d['customerName'] as String?)?.isNotEmpty ?? false
          ? d['customerName'] as String
          : 'Customer task',
      status: status,
      busy: busy,
      onResume: () => Navigator.push<void>(
        context,
        MaterialPageRoute<void>(
          builder: (_) => HeroTaskDetailScreen(requestId: doc.id),
        ),
      ),
      onRelease: () => _confirmAndReleaseServiceRequest(doc.id),
    );
  }

  Future<void> _confirmAndReleaseServiceRequest(String requestId) async {
    final confirmed = await _confirmRelease(context);
    if (!confirmed || !mounted) return;
    setState(() => _busyId = requestId);
    try {
      await ServiceRequestService().releaseServiceRequest(requestId);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          backgroundColor: _pink,
          content: Text('Task released — sent to admin, you can now '
              'receive new pings.'),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(backgroundColor: _red, content: Text('Could not release: $e')),
      );
    } finally {
      if (mounted) setState(() => _busyId = null);
    }
  }

  // ── Shared card + confirm dialog ───────────────────────────────
  Widget _taskCard({
    required String title,
    required String subtitle,
    required String status,
    required bool busy,
    required VoidCallback onResume,
    required Future<void> Function() onRelease,
  }) {
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(13),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(13),
        border: Border.all(color: _pink.withValues(alpha: 0.15)),
        boxShadow: [
          BoxShadow(
            color: _pink.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: _text,
                    fontSize: 13.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _amber.withValues(alpha: 0.16),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: Text(
                  status,
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFB8860B),
                    fontSize: 10.5,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            subtitle,
            style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
          ),
          const SizedBox(height: 10),
          if (busy)
            const Center(
              child: SizedBox(
                height: 18,
                width: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _pink),
              ),
            )
          else
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _pink,
                      side: const BorderSide(color: _pink),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onResume,
                    icon: const Icon(Icons.play_arrow_rounded, size: 17),
                    label: const Text('Resume'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: _red,
                      side: const BorderSide(color: _red),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    onPressed: onRelease,
                    icon: const Icon(Icons.undo_rounded, size: 17),
                    label: const Text('Release'),
                  ),
                ),
              ],
            ),
        ],
      ),
    );
  }

  Future<bool> _confirmRelease(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: Colors.white,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Text(
          'Release this task?',
          style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w800),
        ),
        content: Text(
          'It will be sent to admin for review and you will immediately '
          'be free to receive new job pings again.',
          style: GoogleFonts.outfit(color: _muted, fontSize: 13, height: 1.4),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Release', style: TextStyle(color: _red)),
          ),
        ],
      ),
    );
    return result ?? false;
  }

  static String _prettyCategory(String key) {
    switch (key) {
      case 'bike':
        return 'Bike Taxi';
      case 'auto':
        return 'Auto';
      case 'car':
        return 'Cab / Car';
      case 'parcel':
        return 'Parcel';
      case 'mini_truck':
        return 'Mini Truck';
      case 'lorry':
        return 'Lorry';
      case 'emergency_manpower':
      case 'manpower':
        return 'Emergency Manpower';
      case 'hero_booking':
        return 'Hero Booking';
      case 'custom_order':
        return 'Custom Order';
      case 'custom_food_order':
        return 'Food Order';
      case 'grocery_order':
        return 'Grocery Order';
      case 'catalog_food_order':
        return 'Catalog Food Order';
      case 'custom_hotel_order':
        return 'Hotel Order';
      case 'catalog_grocery_order':
        return 'Catalog Grocery Order';
      default:
        return key.isEmpty ? 'Task' : key.replaceAll('_', ' ');
    }
  }
}
