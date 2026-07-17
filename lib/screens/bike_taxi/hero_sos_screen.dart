import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../services/location_service.dart';

class HeroSosScreen extends StatefulWidget {
  const HeroSosScreen({super.key});

  @override
  State<HeroSosScreen> createState() => _HeroSosScreenState();
}

class _HeroSosScreenState extends State<HeroSosScreen> {
  bool _sendingSos = false;
  final List<DateTime> _sosTapTimes = <DateTime>[];

  Future<void> _handleSosTap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please login before sending SOS.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
      }
      return;
    }

    final now = DateTime.now();
    _sosTapTimes
      ..removeWhere((tap) => now.difference(tap).inSeconds > 3)
      ..add(now);

    if (_sosTapTimes.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Tap SOS ${3 - _sosTapTimes.length} more time(s) within 3 seconds.',
            ),
            backgroundColor: const Color(0xFFB00020),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
      return;
    }

    _sosTapTimes.clear();
    final shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SosCountdownDialog(),
    );
    if (shouldSend != true || !mounted) return;
    await _sendSosAlert(user);
  }

  Future<void> _sendSosAlert(User user) async {
    if (_sendingSos) return;
    setState(() => _sendingSos = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable GPS to send an SOS alert.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
        setState(() => _sendingSos = false);
        return;
      }

      var permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Location permission is required for SOS.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
        setState(() => _sendingSos = false);
        return;
      }

      final pos = await LocationService().getCurrentLocation();
      if (pos == null) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Could not get current location for SOS.'),
            backgroundColor: Color(0xFFB00020),
          ),
        );
        setState(() => _sendingSos = false);
        return;
      }

      // Send SOS alert to Firestore
      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'heroId': user.uid,
        'heroName': user.displayName ?? 'Hero',
        'heroPhone': user.phoneNumber ?? '',
        'location': GeoPoint(pos.latitude, pos.longitude),
        'address': '',
        'status': 'active',
        'type': 'hero_emergency',
        'createdAt': FieldValue.serverTimestamp(),
      });

      // Log to RTDB for real-time radar
      await FirebaseDatabase.instance.ref('sos_alerts/${user.uid}').set({
        'lat': pos.latitude,
        'lng': pos.longitude,
        'heroName': user.displayName ?? 'Hero',
        'timestamp': ServerValue.timestamp,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('SOS sent! Help is on the way.'),
            backgroundColor: Color(0xFF00C853),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      debugPrint('SOS send error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send SOS: $e'),
            backgroundColor: const Color(0xFFB00020),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sendingSos = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFF7FB), Color(0xFFFFEEF6), Color(0xFFFFFFFF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        child: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 40),
              const Icon(
                Icons.emergency_rounded,
                color: Color(0xFFFF5252),
                size: 80,
              ),
              const SizedBox(height: 16),
              Text(
                'Emergency SOS',
                style: GoogleFonts.outfit(
                  fontSize: 24,
                  fontWeight: FontWeight.w900,
                  color: const Color(0xFF3D1230),
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Tap 3 times within 3 seconds to send',
                style: GoogleFonts.outfit(
                  fontSize: 14,
                  color: const Color(0xFF8F5A78),
                ),
              ),
              const SizedBox(height: 40),
              GestureDetector(
                onTap: _sendingSos ? null : _handleSosTap,
                child: Container(
                  width: 200,
                  height: 200,
                  decoration: const BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: LinearGradient(
                      colors: [Color(0xFFFF5252), Color(0xFFB00020)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    boxShadow: [
                      BoxShadow(
                        color: Color(0x4AFF5252),
                        blurRadius: 30,
                        offset: Offset(0, 15),
                      ),
                    ],
                  ),
                  child: Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          _sendingSos
                              ? Icons.hourglass_top
                              : Icons.emergency_rounded,
                          color: Colors.white,
                          size: 64,
                        ),
                        const SizedBox(height: 8),
                        Text(
                          _sendingSos ? 'SENDING...' : 'SOS',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontSize: 28,
                            fontWeight: FontWeight.w900,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 32),
              if (_sendingSos)
                const Padding(
                  padding: EdgeInsets.symmetric(horizontal: 32),
                  child: LinearProgressIndicator(
                    backgroundColor: Color(0x20FF5252),
                    valueColor:
                        AlwaysStoppedAnimation<Color>(Color(0xFFFF5252)),
                  ),
                ),
              const SizedBox(height: 16),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () async {
                    final uri = Uri.parse('tel:100');
                    if (await canLaunchUrl(uri)) {
                      await launchUrl(uri);
                    }
                  },
                  icon:
                      const Icon(Icons.phone_rounded, color: Color(0xFFFF5252)),
                  label: const Text(
                    'Call Emergency 100',
                    style: TextStyle(
                      color: Color(0xFFFF5252),
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Color(0x40FF5252)),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Only use in genuine emergencies',
                style: GoogleFonts.outfit(
                  fontSize: 12,
                  color: const Color(0xFF8F5A78),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SosCountdownDialog extends StatefulWidget {
  const _SosCountdownDialog();

  @override
  State<_SosCountdownDialog> createState() => _SosCountdownDialogState();
}

class _SosCountdownDialogState extends State<_SosCountdownDialog> {
  int _secondsLeft = 5;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_secondsLeft <= 1) {
        timer.cancel();
        Navigator.of(context).pop(true);
        return;
      }
      setState(() => _secondsLeft--);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: const Color(0xFF0A0A12),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: const BorderSide(color: Color(0x33FF4FA3)),
      ),
      title: const Text(
        'SOS Emergency',
        style: TextStyle(
          color: Color(0xFFFF5252),
          fontWeight: FontWeight.w800,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(
            Icons.warning_amber_rounded,
            color: Color(0xFFFF5252),
            size: 64,
          ),
          const SizedBox(height: 16),
          const Text(
            'Sending emergency alert to all nearby heroes...',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14),
          ),
          const SizedBox(height: 12),
          Text(
            '$_secondsLeft',
            style: const TextStyle(
              color: Color(0xFFFF5252),
              fontSize: 48,
              fontWeight: FontWeight.w900,
            ),
          ),
        ],
      ),
    );
  }
}
