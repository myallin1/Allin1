// ================================================================
// service_request_live_map_screen.dart — Customer-facing "Open in
// Maps" live tracking view for a Hero Booking (or other
// service_requests category) task.
//
// Reuses the exact same building blocks as ride_tracking_screen.dart's
// live map (Allin1MapWidget, MapMarker, MapRoute) and the exact same
// RTDB path convention (`live_locations/{id}`) the ride flow already
// uses — just keyed by the service_requests requestId instead of a
// rideDocId. The hero side writes to this path only while a task is
// 'in_progress' (see hero_home_screen.dart's _startLocationUpdates
// wiring), so before that this screen shows a "waiting" state instead
// of a stale/absent marker.
// ================================================================
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../widgets/allin1_map_widget.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
const Color _kBorder = Color(0xFFEEEEF5);
const Color _kGreen = Color(0xFF00C853);

class ServiceRequestLiveMapScreen extends StatefulWidget {
  final String requestId;
  const ServiceRequestLiveMapScreen({super.key, required this.requestId});

  @override
  State<ServiceRequestLiveMapScreen> createState() =>
      _ServiceRequestLiveMapScreenState();
}

class _ServiceRequestLiveMapScreenState
    extends State<ServiceRequestLiveMapScreen> {
  rtdb.DatabaseReference? _liveLocationRef;
  StreamSubscription<rtdb.DatabaseEvent>? _liveLocationSub;

  double? _heroLat;
  double? _heroLng;
  double? _heroHeading;
  String? _heroVehicleType;

  @override
  void initState() {
    super.initState();
    _liveLocationRef =
        rtdb.FirebaseDatabase.instance.ref('live_locations/${widget.requestId}');
    _liveLocationSub = _liveLocationRef!.onValue.listen((event) {
      if (!mounted) return;
      final data = event.snapshot.value;
      if (data is! Map) return;
      final lat = (data['lat'] as num?)?.toDouble();
      final lng = (data['lng'] as num?)?.toDouble();
      if (lat == null || lng == null) return;
      setState(() {
        _heroLat = lat;
        _heroLng = lng;
        _heroHeading = (data['heading'] as num?)?.toDouble();
        _heroVehicleType = data['vehicleType']?.toString();
      });
    });
  }

  @override
  void dispose() {
    _liveLocationSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded,
              color: _kText, size: 20,),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Track Your Hero',
            style: GoogleFonts.outfit(
                color: _kText, fontWeight: FontWeight.w800, fontSize: 18,),),
        centerTitle: true,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('service_requests')
            .doc(widget.requestId)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
                child: CircularProgressIndicator(color: _kPink),);
          }
          if (!snapshot.hasData || !snapshot.data!.exists) {
            return const Center(
                child: Text('Task not found.',
                    style: TextStyle(color: _kMuted),),);
          }

          final data = snapshot.data!.data()!;
          final details =
              (data['details'] as Map<String, dynamic>?) ?? const {};
          final fromLat = (details['fromLocationLat'] as num?)?.toDouble();
          final fromLng = (details['fromLocationLng'] as num?)?.toDouble();
          final toLat = (details['locationLat'] as num?)?.toDouble();
          final toLng = (details['locationLng'] as num?)?.toDouble();

          final markers = <MapMarker>[];
          if (fromLat != null && fromLng != null) {
            markers.add(
              MapMarker(
                point: LatLng(fromLat, fromLng),
                label: 'Pickup',
                icon: Icons.trip_origin_rounded,
                color: const Color(0xFF6C63FF),
              ),
            );
          }
          if (toLat != null && toLng != null) {
            markers.add(
              MapMarker(
                point: LatLng(toLat, toLng),
                label: 'Drop',
                icon: Icons.place_rounded,
                color: _kPink,
              ),
            );
          }
          final hasHeroLocation = _heroLat != null && _heroLng != null;
          if (hasHeroLocation) {
            markers.add(
              MapMarker(
                point: LatLng(_heroLat!, _heroLng!),
                label: 'Your Hero',
                icon: Icons.two_wheeler_rounded,
                color: _kGreen,
                bearingDegrees: _heroHeading,
              ),
            );
          }

          // No saved coordinates at all (customer typed free text and
          // never picked a suggestion/current-location) — nothing
          // meaningful to plot yet.
          if (markers.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Text(
                  'No location details were saved for this task, so a '
                  'map view isn\'t available. Check the task details '
                  'above for the addresses instead.',
                  style: TextStyle(color: _kMuted, fontSize: 13),
                  textAlign: TextAlign.center,
                ),
              ),
            );
          }

          final center = hasHeroLocation
              ? LatLng(_heroLat!, _heroLng!)
              : markers.first.point;

          return Stack(
            children: [
              Allin1MapWidget(
                center: center,
                zoom: 15,
                markers: markers,
              ),
              if (!hasHeroLocation)
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10,),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: _kBorder),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const SizedBox(
                          width: 12,
                          height: 12,
                          child: CircularProgressIndicator(
                              strokeWidth: 2, color: _kPink,),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            'Your Hero\'s live location will appear here '
                            'once they start the task.',
                            style: GoogleFonts.outfit(
                                color: _kText,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}
