import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import 'admin_ride_tracking_detail_screen.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _amber = Color(0xFFFFBB00);
const Color _blue = Color(0xFF4FC3F7);
const Color _pink = Color(0xFFFF4FA3);

// Statuses where a hero is assigned and the ride is still moving toward completion.
const List<String> _activeStatuses = [
  'assigned',
  'accepted',
  'arriving',
  'arrived',
  'started',
  'in_progress',
  'active',
];

class AdminRideTrackingScreen extends StatelessWidget {
  const AdminRideTrackingScreen({super.key});

  double _readFare(Map<String, dynamic> d) {
    final finalFare = (d['finalFare'] as num?)?.toDouble();
    if (finalFare != null) return finalFare;
    final actualFare = (d['actualFare'] as num?)?.toDouble();
    if (actualFare != null) return actualFare;
    final lockedFare = (d['lockedFare'] as num?)?.toDouble();
    if (lockedFare != null) return lockedFare;
    final estimatedFare = (d['estimatedFare'] as num?)?.toDouble();
    if (estimatedFare != null) return estimatedFare;
    return (d['fare'] as num?)?.toDouble() ?? 0.0;
  }

  Color _statusColor(String status) {
    switch (status) {
      case 'assigned':
      case 'accepted':
        return _blue;
      case 'arriving':
      case 'arrived':
        return _amber;
      case 'started':
      case 'in_progress':
      case 'active':
        return _green;
      default:
        return _muted;
    }
  }

  String _statusLabel(String status) {
    switch (status) {
      case 'assigned':
        return 'ASSIGNED';
      case 'accepted':
        return 'ACCEPTED';
      case 'arriving':
        return 'HERO ARRIVING';
      case 'arrived':
        return 'HERO ARRIVED';
      case 'started':
      case 'in_progress':
      case 'active':
        return 'ON TRIP';
      default:
        return status.toUpperCase();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text(
          'Active Rides',
          style: TextStyle(color: _text, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('rides')
            .where('status', whereIn: _activeStatuses)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Error loading active rides: ${snapshot.error}',
                  style: const TextStyle(color: _muted),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: _pink),
            );
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const Center(
              child: Text(
                'No active rides right now',
                style: TextStyle(color: _muted),
              ),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(8),
            itemCount: docs.length,
            itemBuilder: (ctx, i) {
              final doc = docs[i];
              final d = doc.data();
              final status = (d['status'] as String?) ?? 'unknown';
              final customerName = (d['customerName'] as String?) ?? 'Customer';
              final heroName = (d['heroName'] as String?) ?? 'Unassigned';
              final fare = _readFare(d);
              final pickupAddress = (d['pickupAddress'] as String?) ??
                  (d['pickupLocation'] as String?) ??
                  'Pickup location';

              return Card(
                color: _card,
                margin: const EdgeInsets.symmetric(vertical: 4),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
                child: ListTile(
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute<void>(
                      builder: (_) =>
                          AdminRideTrackingDetailScreen(rideId: doc.id),
                    ),
                  ),
                  leading: CircleAvatar(
                    backgroundColor: _statusColor(status).withOpacity(0.2),
                    child: Icon(
                      Icons.two_wheeler_rounded,
                      color: _statusColor(status),
                    ),
                  ),
                  title: Text(
                    customerName,
                    style: const TextStyle(
                      color: _text,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 2),
                      Text(
                        pickupAddress,
                        style: const TextStyle(color: _muted, fontSize: 11),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Hero: $heroName',
                        style: const TextStyle(color: _muted, fontSize: 11),
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 4,
                        ),
                        decoration: BoxDecoration(
                          color: _statusColor(status).withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          _statusLabel(status),
                          style: TextStyle(
                            color: _statusColor(status),
                            fontSize: 9,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Rs.${fare.toStringAsFixed(0)}',
                        style: const TextStyle(
                          color: _text,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
