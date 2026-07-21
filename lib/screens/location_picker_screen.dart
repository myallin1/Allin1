// ================================================================
// location_picker_screen.dart
//
// "Select on map" — the customer drags the map under a fixed centre
// pin, the address underneath updates as they go, and Confirm returns
// both the readable address AND its coordinates.
//
// Why a fixed centre pin instead of tap-to-drop: on a phone, the
// customer's own thumb covers the exact spot they're trying to tap.
// A pin locked to the middle of the screen is always visible, always
// precise, and is what every mainstream ride app settles on.
//
// Returns a PickedLocation via Navigator.pop, or null if cancelled.
// ================================================================
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart' show MapController;
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';

import '../services/location_service.dart';
import '../services/map_service.dart';
import '../widgets/allin1_map_widget.dart';

class PickedLocation {
  final String name;
  final double lat;
  final double lng;

  const PickedLocation({
    required this.name,
    required this.lat,
    required this.lng,
  });
}

class LocationPickerScreen extends StatefulWidget {
  /// Where to open the map. Pass the field's existing coordinates if it
  /// already has some, so re-opening the picker resumes where the
  /// customer left off instead of jumping back to the city centre.
  final LatLng? initialCenter;

  /// Shown in the app bar — "Pickup location" / "Drop location".
  final String title;

  const LocationPickerScreen({
    this.initialCenter,
    this.title = 'Select location',
    super.key,
  });

  @override
  State<LocationPickerScreen> createState() => _LocationPickerScreenState();
}

class _LocationPickerScreenState extends State<LocationPickerScreen> {
  static const Color _kPink = Color(0xFFFF4FA3);
  static const Color _kPinkDark = Color(0xFF4A1236);
  static const Color _kText = Color(0xFF2B2B36);
  static const Color _kMuted = Color(0xFF8A4E72);

  final _mapService = MapService();
  final _mapController = MapController();

  LatLng _center = kErodeCenter;
  String _address = '';
  bool _resolving = false;
  bool _locating = false;

  // Reverse-geocode is a network call, so it must not fire on every
  // frame of a pan gesture. Only the settled position is looked up.
  Timer? _addressDebounce;

  @override
  void initState() {
    super.initState();
    if (widget.initialCenter != null) {
      _center = widget.initialCenter!;
      unawaited(_resolveAddress(_center));
    } else {
      // No starting point given — open on the customer's own location
      // rather than a hardcoded city centre, so the pin usually starts
      // within a street or two of where they mean.
      unawaited(_jumpToCurrentLocation(moveMap: true));
    }
  }

  @override
  void dispose() {
    _addressDebounce?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  void _onCenterChanged(LatLng center, bool gestureFinished) {
    _center = center;
    _addressDebounce?.cancel();
    if (mounted && !_resolving) {
      setState(() => _resolving = true);
    }
    _addressDebounce = Timer(
      const Duration(milliseconds: 600),
      () => unawaited(_resolveAddress(center)),
    );
  }

  Future<void> _resolveAddress(LatLng point) async {
    if (mounted) setState(() => _resolving = true);
    try {
      final result = await _mapService.reverseGeocode(point);
      if (!mounted) return;
      // Ignore a late reply for a position the customer has already
      // panned away from.
      if (point != _center) return;
      setState(() {
        _address = (result?['full'] as String?) ??
            (result?['name'] as String?) ??
            '';
        _resolving = false;
      });
    } catch (e) {
      debugPrint('[LocationPicker] reverse geocode failed: $e');
      if (mounted) setState(() => _resolving = false);
    }
  }

  Future<void> _jumpToCurrentLocation({bool moveMap = true}) async {
    if (mounted) setState(() => _locating = true);
    try {
      final position = await LocationService().getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Could not get your location. Check that location permission is allowed.',
              ),
            ),
          );
        }
        return;
      }
      final point = LatLng(position.latitude, position.longitude);
      _center = point;
      if (moveMap) {
        // Guarded: move() throws if the map hasn't finished building.
        try {
          _mapController.move(point, 17);
        } catch (e) {
          debugPrint('[LocationPicker] map not ready for move yet: $e');
        }
      }
      await _resolveAddress(point);
    } catch (e) {
      debugPrint('[LocationPicker] current location failed: $e');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  void _confirm() {
    Navigator.of(context).pop(
      PickedLocation(
        // An empty address is still usable — the hero navigates by the
        // coordinates, which are always exact here. Falling back to a
        // readable lat/lng beats handing back a blank field.
        name: _address.trim().isNotEmpty
            ? _address.trim()
            : '${_center.latitude.toStringAsFixed(5)}, '
                '${_center.longitude.toStringAsFixed(5)}',
        lat: _center.latitude,
        lng: _center.longitude,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        foregroundColor: _kPinkDark,
        elevation: 0,
        title: Text(
          widget.title,
          style: GoogleFonts.outfit(
            color: _kPinkDark,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
      ),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Allin1MapWidget(
                    center: _center,
                    zoom: 16,
                    mapController: _mapController,
                    onCenterChanged: _onCenterChanged,
                  ),
                ),
                // Fixed centre pin. IgnorePointer so it never eats a
                // drag gesture meant for the map underneath it.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Padding(
                        // Lifts the icon so its tip, not its middle,
                        // sits on the true centre of the map.
                        padding: EdgeInsets.only(bottom: 36),
                        child: Icon(
                          Icons.place_rounded,
                          color: _kPink,
                          size: 44,
                        ),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  right: 14,
                  bottom: 14,
                  child: FloatingActionButton.small(
                    heroTag: 'picker_locate',
                    backgroundColor: Colors.white,
                    foregroundColor: _kPink,
                    onPressed:
                        _locating ? null : () => _jumpToCurrentLocation(),
                    child: _locating
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: _kPink,
                            ),
                          )
                        : const Icon(Icons.my_location_rounded, size: 20),
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 18),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [
                BoxShadow(
                  color: Color(0x14000000),
                  blurRadius: 18,
                  offset: Offset(0, -6),
                ),
              ],
            ),
            child: SafeArea(
              top: false,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Move the map to adjust the pin',
                    style: GoogleFonts.outfit(
                      color: _kMuted,
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Icon(
                        Icons.place_rounded,
                        color: _kPink,
                        size: 18,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: _resolving
                            ? Text(
                                'Finding address...',
                                style: GoogleFonts.outfit(
                                  color: _kMuted,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              )
                            : Text(
                                _address.isEmpty
                                    ? '${_center.latitude.toStringAsFixed(5)}, '
                                        '${_center.longitude.toStringAsFixed(5)}'
                                    : _address,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GoogleFonts.outfit(
                                  color: _kText,
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _confirm,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _kPink,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      child: Text(
                        'Confirm this location',
                        style: GoogleFonts.outfit(
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
