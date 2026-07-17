import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../widgets/allin1_map_widget.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _amber = Color(0xFFFFBB00);

const Color _pink = Color(0xFFFF4FA3);
const LatLng _erodeCenter = LatLng(11.3410, 77.7172);

class AdminRideTrackingDetailScreen extends StatefulWidget {
  final String rideId;
  const AdminRideTrackingDetailScreen({
    required this.rideId,
    super.key,
  });

  @override
  State<AdminRideTrackingDetailScreen> createState() =>
      _AdminRideTrackingDetailScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('rideId', rideId));
  }
}

class _AdminRideTrackingDetailScreenState
    extends State<AdminRideTrackingDetailScreen> {
  LatLng? _heroLocation;
  late final StreamSubscription<DatabaseEvent> _liveLocationSub;

  @override
  void initState() {
    super.initState();
    _liveLocationSub = FirebaseDatabase.instance
        .ref('live_locations/${widget.rideId}')
        .onValue
        .listen(
      (event) {
        final raw = event.snapshot.value;
        if (raw is Map) {
          final lat = (raw['lat'] as num?)?.toDouble();
          final lng = (raw['lng'] as num?)?.toDouble();
          if (lat != null && lng != null && mounted) {
            setState(() => _heroLocation = LatLng(lat, lng));
          }
        }
      },
      onError: (Object e) {
        debugPrint('live_locations stream error: $e');
      },
    );
  }

  @override
  void dispose() {
    _liveLocationSub.cancel();
    super.dispose();
  }

  double? _readCoord(
    Map<String, dynamic> d,
    String primaryKey,
    String aliasKey,
  ) {
    return (d[primaryKey] as num?)?.toDouble() ??
        (d[aliasKey] as num?)?.toDouble();
  }

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

  Future<void> _call(String? phone) async {
    if (phone == null || phone.isEmpty) return;
    final url = Uri.parse('tel:$phone');
    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    }
  }

  Widget _timelineRow(
    String label,
    Timestamp? ts, {
    required bool isLast,
  }) {
    final reached = ts != null;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Column(
          children: [
            Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: reached ? _green : _muted.withValues(alpha: 0.3),
              ),
            ),
            if (!isLast)
              Container(
                width: 2,
                height: 28,
                color: reached
                    ? _green.withValues(alpha: 0.4)
                    : _muted.withValues(alpha: 0.2),
              ),
          ],
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  label,
                  style: TextStyle(
                    color: reached ? _text : _muted,
                    fontSize: 13,
                  ),
                ),
                if (reached)
                  Text(
                    '${ts.toDate().hour.toString().padLeft(2, '0')}:${ts.toDate().minute.toString().padLeft(2, '0')}',
                    style: const TextStyle(color: _muted, fontSize: 11),
                  ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        title: const Text(
          'Ride Tracking',
          style: TextStyle(color: _text, fontWeight: FontWeight.bold),
        ),
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('rides')
            .doc(widget.rideId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Text(
                'Error: ${snapshot.error}',
                style: const TextStyle(color: _muted),
              ),
            );
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
              child: CircularProgressIndicator(color: _pink),
            );
          }
          final d = snapshot.data!.data()!;

          final status = (d['status'] as String?) ?? 'unknown';
          final customerName = (d['customerName'] as String?) ?? 'Customer';
          final customerPhone = (d['customerPhone'] as String?) ?? '';
          final heroName = (d['heroName'] as String?) ?? 'Unassigned';
          final heroPhone = (d['heroPhone'] as String?) ?? '';
          final heroVehicleNumber = (d['heroVehicleNumber'] as String?) ?? '';
          final pickupAddress = (d['pickupAddress'] as String?) ??
              (d['pickupLocation'] as String?) ??
              '-';
          final dropAddress = (d['dropAddress'] as String?) ??
              (d['dropLocation'] as String?) ??
              '-';
          final fare = _readFare(d);

          final pickupLat = _readCoord(d, 'pickupLatitude', 'pickupLat');
          final pickupLng = _readCoord(d, 'pickupLongitude', 'pickupLng');
          final dropLat = _readCoord(d, 'dropLatitude', 'dropLat');
          final dropLng = _readCoord(d, 'dropLongitude', 'dropLng');

          final markers = <MapMarker>[];
          if (pickupLat != null && pickupLng != null) {
            markers.add(
              MapMarker(
                point: LatLng(pickupLat, pickupLng),
                label: 'Pickup',
                icon: Icons.trip_origin_rounded,
                color: _green,
              ),
            );
          }
          if (dropLat != null && dropLng != null) {
            markers.add(
              MapMarker(
                point: LatLng(dropLat, dropLng),
                label: 'Drop',
                icon: Icons.flag_rounded,
                color: _red,
              ),
            );
          }
          if (_heroLocation != null) {
            markers.add(
              MapMarker(
                point: _heroLocation!,
                label: heroName,
                icon: Icons.two_wheeler_rounded,
                color: _amber,
              ),
            );
          }

          final mapCenter = _heroLocation ??
              (pickupLat != null && pickupLng != null
                  ? LatLng(pickupLat, pickupLng)
                  : _erodeCenter);

          return SingleChildScrollView(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  height: 260,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white24),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: markers.isEmpty
                        ? const Center(
                            child: Text(
                              'No location data yet',
                              style: TextStyle(color: _muted),
                            ),
                          )
                        : Allin1MapWidget(
                            center: mapCenter,
                            markers: markers,
                          ),
                  ),
                ),
                if (_heroLocation == null)
                  const Padding(
                    padding: EdgeInsets.only(top: 6),
                    child: Text(
                      'Hero live location not available yet (waiting for GPS ping)',
                      style: TextStyle(color: _muted, fontSize: 11),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: Card(
                        color: _card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Customer',
                                style: TextStyle(color: _muted, fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                customerName,
                                style: const TextStyle(
                                  color: _text,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 8),
                              if (customerPhone.isNotEmpty)
                                InkWell(
                                  onTap: () => _call(customerPhone),
                                  child: Row(
                                    children: [
                                      const Icon(
                                        Icons.call_rounded,
                                        color: _green,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 4),
                                      Expanded(
                                        child: Text(
                                          customerPhone,
                                          style: const TextStyle(
                                            color: _green,
                                            fontSize: 12,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Card(
                        color: _card,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Hero',
                                style: TextStyle(color: _muted, fontSize: 11),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                heroName,
                                style: const TextStyle(
                                  color: _text,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              if (heroVehicleNumber.isNotEmpty)
                                Text(
                                  heroVehicleNumber,
                                  style: const TextStyle(
                                    color: _muted,
                                    fontSize: 11,
                                  ),
                                ),
                              const SizedBox(height: 8),
                              if (heroPhone.isNotEmpty)
                                IconButton(
                                  padding: EdgeInsets.zero,
                                  constraints: const BoxConstraints(),
                                  onPressed: () => _call(heroPhone),
                                  icon: const Icon(
                                    Icons.call_rounded,
                                    color: _green,
                                    size: 18,
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Card(
                  color: _card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(
                              Icons.trip_origin_rounded,
                              color: _green,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                pickupAddress,
                                style: const TextStyle(
                                  color: _text,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Padding(
                          padding: EdgeInsets.symmetric(
                            vertical: 4,
                            horizontal: 8,
                          ),
                          child: SizedBox(
                            height: 10,
                            child: VerticalDivider(color: _muted),
                          ),
                        ),
                        Row(
                          children: [
                            const Icon(
                              Icons.flag_rounded,
                              color: _red,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                dropAddress,
                                style: const TextStyle(
                                  color: _text,
                                  fontSize: 13,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const Divider(color: Colors.white24, height: 24),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'Fare',
                              style: TextStyle(color: _muted, fontSize: 12),
                            ),
                            Text(
                              'Rs.${fare.toStringAsFixed(0)}',
                              style: const TextStyle(
                                color: _text,
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Card(
                  color: _card,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Status: ${status.toUpperCase()}',
                          style: const TextStyle(
                            color: _pink,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                        const SizedBox(height: 12),
                        _timelineRow(
                          'Requested',
                          d['createdAt'] as Timestamp?,
                          isLast: false,
                        ),
                        _timelineRow(
                          'Hero Accepted',
                          d['acceptedAt'] as Timestamp?,
                          isLast: false,
                        ),
                        _timelineRow(
                          'Hero Arrived',
                          d['arrivedAt'] as Timestamp?,
                          isLast: false,
                        ),
                        _timelineRow(
                          'Trip Started',
                          d['startedAt'] as Timestamp?,
                          isLast: false,
                        ),
                        _timelineRow(
                          'Completed',
                          d['completedAt'] as Timestamp?,
                          isLast: true,
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
