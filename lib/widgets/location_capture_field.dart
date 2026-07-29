// ================================================================
// LocationCaptureField — reusable "Use my location" / "Select on map"
// address capture widget.
//
// FIX (per Nizam's request): custom_food_order_screen.dart already had
// this exact pattern (Use My Location + Select On Map buttons feeding
// an address text field + lat/lng), but it was hand-written inline
// there and nowhere else — every OTHER order form (electronics service
// enquiry, custom_order, grocery_order, catalog_food_order checkout)
// collected zero location data at all, meaning heroes assigned to
// those tasks had no coordinates to navigate to. Rather than copy-paste
// the same ~60 lines into 4 more screens, it's extracted here once so
// every order form can capture a real, navigable pickup/delivery point
// the same way.
// ================================================================
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';

import '../screens/location_picker_screen.dart';
import '../services/location_service.dart';
import '../services/map_service.dart';

class LocationCaptureField extends StatefulWidget {
  final TextEditingController addressController;
  final String pickerTitle;
  final void Function(double lat, double lng) onLocationPicked;
  final Color accentColor;

  const LocationCaptureField({
    super.key,
    required this.addressController,
    required this.onLocationPicked,
    this.pickerTitle = 'Select location',
    this.accentColor = const Color(0xFFFF4FA3),
  });

  @override
  State<LocationCaptureField> createState() => _LocationCaptureFieldState();
}

class _LocationCaptureFieldState extends State<LocationCaptureField> {
  bool _locating = false;
  double? _lastLat;
  double? _lastLng;

  Future<void> _useMyLocation() async {
    setState(() => _locating = true);
    try {
      final position = await LocationService().getCurrentLocation();
      if (position == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Could not get your location. Check location permission.'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
      final point = LatLng(position.latitude, position.longitude);
      final reverse = await MapService().reverseGeocode(point);
      final address = (reverse?['name'] as String?)?.trim().isNotEmpty == true
          ? reverse!['name'] as String
          : (reverse?['address'] as String?) ?? 'Current location';
      if (!mounted) return;
      setState(() {
        widget.addressController.text = address;
        _lastLat = position.latitude;
        _lastLng = position.longitude;
      });
      widget.onLocationPicked(position.latitude, position.longitude);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not fetch location: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  Future<void> _selectOnMap() async {
    final initialCenter = (_lastLat != null && _lastLng != null)
        ? LatLng(_lastLat!, _lastLng!)
        : null;
    final picked = await Navigator.push<PickedLocation>(
      context,
      MaterialPageRoute(
        builder: (_) => LocationPickerScreen(
          initialCenter: initialCenter,
          title: widget.pickerTitle,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      widget.addressController.text = picked.name;
      _lastLat = picked.lat;
      _lastLng = picked.lng;
    });
    widget.onLocationPicked(picked.lat, picked.lng);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _locating ? null : _useMyLocation,
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accentColor,
              side: BorderSide(color: widget.accentColor),
            ),
            icon: _locating
                ? SizedBox(
                    width: 14,
                    height: 14,
                    child: CircularProgressIndicator(strokeWidth: 2, color: widget.accentColor),
                  )
                : const Icon(Icons.my_location_rounded, size: 16),
            label: const Text('Use my location', style: TextStyle(fontSize: 12)),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: OutlinedButton.icon(
            onPressed: _selectOnMap,
            style: OutlinedButton.styleFrom(
              foregroundColor: widget.accentColor,
              side: BorderSide(color: widget.accentColor),
            ),
            icon: const Icon(Icons.map_rounded, size: 16),
            label: const Text('Select on map', style: TextStyle(fontSize: 12)),
          ),
        ),
      ],
    );
  }
}
