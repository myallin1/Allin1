import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_ringtone_player/flutter_ringtone_player.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/auth_service.dart';
import '../services/firestore_usage_tracking.dart';
import '../services/offline_sos_mesh_service.dart';
import 'sos_kyc_verification_screen.dart';

class SosScreen extends StatefulWidget {
  const SosScreen({super.key});

  @override
  State<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends State<SosScreen> {
  static const Color _red = Color(0xFFFF1744);
  static const Color _darkRed = Color(0xFFB00020);
  static const Color _navy = Color(0xFF071A35);
  static const Color _pink = Color(0xFFFF4FA3);

  final List<DateTime> _sosTapTimes = <DateTime>[];
  bool _sending = false;

  Future<void> _handleSosTap() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please login before sending SOS.'),
          backgroundColor: _darkRed,
        ),
      );
      return;
    }

    final now = DateTime.now();
    _sosTapTimes
      ..removeWhere((tap) => now.difference(tap).inSeconds > 3)
      ..add(now);

    if (_sosTapTimes.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Tap SOS ${3 - _sosTapTimes.length} more time(s) within 3 seconds.',
          ),
          backgroundColor: _darkRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    _sosTapTimes.clear();
    final shouldSend = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _SosCountdownDialog(),
    );
    if (shouldSend != true || !mounted) {
      return;
    }
    await _createSosAlert(user);
  }

  Future<void> _createSosAlert(User user) async {
    if (_sending) {
      return;
    }
    setState(() => _sending = true);

    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please enable GPS to send an SOS alert.'),
            backgroundColor: _darkRed,
          ),
        );
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
            backgroundColor: _darkRed,
          ),
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 8),
        ),
      );

      // FIX (audit: customer/hero number wiring — SOS is life-safety, so
      // this matters more than most): user.phoneNumber is only populated
      // by real phone-OTP auth, not a Google-Sign-In customer's typed-in
      // signup number (which lives in Firestore users/{uid}.phoneNumber).
      final resolvedUserPhone = await AuthService().resolveCustomerPhone(user);
      await FirebaseFirestore.instance.collection('sos_alerts').add({
        'userId': user.uid,
        'userName': user.displayName ?? user.email ?? 'Customer',
        'userPhone': resolvedUserPhone,
        'location': GeoPoint(position.latitude, position.longitude),
        'status': 'active',
        'timestamp': FieldValue.serverTimestamp(),
      });

      // Broadcast via 300m Offline SOS Mesh (Zero network beacon)
      unawaited(
        OfflineSosMeshService.instance.startBroadcasting(
          userId: user.uid,
          latitude: position.latitude,
          longitude: position.longitude,
          batteryLevel: 100,
          userName: user.displayName ?? 'Customer',
          userPhone: resolvedUserPhone,
        ),
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS Alert sent to nearby Heroes and NJ Tech 24/7 Safety Grid.'),
          backgroundColor: _darkRed,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (error) {
      debugPrint('[SosScreen] SOS failed: $error');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('SOS could not be sent. Please try again.'),
          backgroundColor: _darkRed,
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _sending = false);
      }
    }
  }

  bool _isSirenActive = false;

  Future<void> _toggleSiren() async {
    setState(() => _isSirenActive = !_isSirenActive);
    if (_isSirenActive) {
      FlutterRingtonePlayer().playAlarm();
    } else {
      FlutterRingtonePlayer().stop();
    }
  }

  Future<void> _callEmergency112() async {
    final uri = Uri.parse('tel:112');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open dialer for Emergency 112.'),
          backgroundColor: _darkRed,
        ),
      );
    }
  }

  Future<void> _callPolice() async {
    final uri = Uri.parse('tel:100');
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open dialer for Police 100.'),
          backgroundColor: _darkRed,
        ),
      );
    }
  }

  @override
  void dispose() {
    if (_isSirenActive) {
      FlutterRingtonePlayer().stop();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFFFFFFFF), Color(0xFFFFF2F8), Color(0xFFEAF3FF)],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
      ),
      child: SafeArea(
        top: false,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 28),
          children: [
            _buildTrustHeader(),
            const SizedBox(height: 28),
            _buildSosGateOrCard(),
            const SizedBox(height: 22),
            _buildOfflineEmergencyToolkit(),
            const SizedBox(height: 18),
            _buildPoliceButton(),
            const SizedBox(height: 18),
            _buildSafetyNotes(),
          ],
        ),
      ),
    );
  }

  Widget _buildOfflineEmergencyToolkit() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF131422),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: Colors.red.withValues(alpha: 0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.offline_bolt_rounded, color: Colors.amber, size: 20),
              const SizedBox(width: 8),
              Text(
                'Offline Emergency Arsenal (டவர் இல்லாத இடத்திலும்)',
                style: GoogleFonts.outfit(
                  color: Colors.white,
                  fontSize: 13.5,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: _callEmergency112,
                  icon: const Icon(Icons.emergency_rounded, color: Colors.redAccent, size: 18),
                  label: const Text('112 Help'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.white,
                    side: const BorderSide(color: Colors.redAccent),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _toggleSiren,
                  icon: Icon(_isSirenActive ? Icons.volume_off_rounded : Icons.campaign_rounded, size: 18),
                  label: Text(_isSirenActive ? 'Stop Siren' : 'Loud Siren'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _isSirenActive ? Colors.red : Colors.orangeAccent.shade700,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildTrustHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_navy, Color(0xFF102A63), _pink],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: _pink.withValues(alpha: 0.22),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.16),
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            ),
            child: const Icon(
              Icons.health_and_safety_rounded,
              color: Colors.white,
              size: 32,
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              '🛡️ NJ Tech 24/7 Safety Grid is Active. You are not alone. We are monitoring.',
              style: GoogleFonts.notoSansTamil(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.w900,
                height: 1.28,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // NEW (per Nizam's request): the SOS button used to fire instantly on
  // a 3-tap gesture with zero verification — easy to trigger by
  // accident/misuse, wasting a safety feature meant for real
  // emergencies. Now gated behind a one-time KYC verification
  // (sos_kyc_requests/{uid}), reviewed by admin's Cus SOS Approval tab.
  // Real-time listener so the button unlocks the instant admin
  // approves, without the customer needing to reopen the app.
  // NEW (Aug 11 2026 — Nizam's request): legal-deterrent banner shown
  // ABOVE the KYC gate, so the consequence of misuse is the first thing
  // a customer reads on this screen rather than something buried after
  // they've already verified.
  //
  // NOTE FOR REVIEW: the specific figures below (₹50,000 / 3 months) were
  // supplied by Nizam and are stated here verbatim at his explicit
  // instruction. I could not verify them against a specific Indian
  // statute — worth a lawyer's confirmation before/soon after launch,
  // since this is customer-facing text asserting a legal penalty. The
  // surrounding claims (identity/location/time are logged, account ban)
  // are all factually true of this app's own behaviour.
  Widget _buildMisuseWarning() {
    return Container(
      width: double.infinity,
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF4F6),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: const Color(0xFFFFB3C6), width: 1.5),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.gavel_rounded, color: Color(0xFFD11A4A), size: 26),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'WARNING: SOS Misuse is a Punishable Offence',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFFD11A4A),
                    fontSize: 14.5,
                    fontWeight: FontWeight.w900,
                    height: 1.25,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  'This emergency network is strictly for real emergencies. '
                  'Raising a false SOS alert can lead to a penalty of '
                  '₹50,000 and imprisonment of up to 3 months, along with a '
                  'permanent ban from this app.\n\n'
                  'Your identity, live location and the exact time are '
                  'recorded with every SOS you send.',
                  style: GoogleFonts.outfit(
                    color: const Color(0xFF7A2138),
                    fontSize: 12.5,
                    height: 1.45,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSosGateOrCard() {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return _buildSosCard();

    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_kyc_requests')
          .doc(user.uid)
          .trackedSnapshots(),
      builder: (context, snap) {
        if (snap.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Center(child: CircularProgressIndicator(color: _red)),
          );
        }
        final data = snap.data?.data();
        final status = data?['status'] as String?;

        if (status == 'approved') {
          return _buildSosCard();
        }
        // Every not-yet-approved state shows the misuse warning above the
        // card. Deliberately NOT shown once approved: at that point the
        // customer has already read and accepted it during verification,
        // and someone in a real emergency should see the SOS button
        // immediately, not a wall of legal text.
        if (status == 'pending') {
          return Column(children: [
            _buildMisuseWarning(),
            _buildKycStatusCard(
            icon: Icons.hourglass_top_rounded,
            color: _darkRed,
            title: 'Verification Pending',
            message: 'Your SOS KYC details are with admin for review. '
                'This is a one-time check — once approved, your SOS button '
                'activates permanently.',
            ),
          ],);
        }
        if (status == 'rejected') {
          final reason = data?['rejectionReason'] as String? ?? '';
          return Column(children: [
            _buildMisuseWarning(),
            _buildKycStatusCard(
              icon: Icons.error_outline_rounded,
              color: _red,
              title: 'Verification Rejected',
              message: reason.isNotEmpty
                  ? 'Reason: $reason\n\nPlease correct and resubmit.'
                  : 'Please correct your details and resubmit.',
              actionLabel: 'Resubmit KYC',
            ),
          ],);
        }
        // Not submitted yet.
        return Column(children: [
          _buildMisuseWarning(),
          _buildKycStatusCard(
            icon: Icons.verified_user_outlined,
            color: _pink,
            title: 'Verify KYC to Activate SOS',
            message: 'For your safety and to prevent misuse of this emergency '
                'network, please verify your identity once before using SOS.',
            actionLabel: 'Start Verification',
          ),
        ],);
      },
    );
  }

  Widget _buildKycStatusCard({
    required IconData icon,
    required Color color,
    required String title,
    required String message,
    String? actionLabel,
  }) {
    return Container(
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFFFD2E6)),
        boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.14), blurRadius: 28, offset: const Offset(0, 14)),
        ],
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 56),
          const SizedBox(height: 14),
          Text(title,
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _navy, fontSize: 18, fontWeight: FontWeight.w900),),
          const SizedBox(height: 8),
          Text(message,
              textAlign: TextAlign.center,
              style: GoogleFonts.notoSansTamil(color: const Color(0xFF7A4B63), fontSize: 13, height: 1.4),),
          if (actionLabel != null) ...[
            const SizedBox(height: 18),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: () => Navigator.push(context,
                    MaterialPageRoute<void>(builder: (_) => const SosKycVerificationScreen()),),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pink,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                ),
                child: Text(actionLabel,
                    style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.w700),),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildSosCard() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 28, 20, 28),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: const Color(0xFFFFD2E6)),
        boxShadow: [
          BoxShadow(
            color: _red.withValues(alpha: 0.14),
            blurRadius: 28,
            offset: const Offset(0, 14),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(
            'Emergency SOS',
            style: GoogleFonts.outfit(
              color: _navy,
              fontSize: 24,
              fontWeight: FontWeight.w900,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Tap the button 3 times within 3 seconds.',
            textAlign: TextAlign.center,
            style: GoogleFonts.notoSansTamil(
              color: const Color(0xFF7A4B63),
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 24),
          GestureDetector(
            onTap: _sending ? null : () => unawaited(_handleSosTap()),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 210,
              height: 210,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [_red, _darkRed],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(color: Colors.white, width: 6),
                boxShadow: [
                  BoxShadow(
                    color: _red.withValues(alpha: 0.45),
                    blurRadius: 34,
                    spreadRadius: 6,
                  ),
                  BoxShadow(
                    color: _darkRed.withValues(alpha: 0.25),
                    blurRadius: 18,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Center(
                child: _sending
                    ? const SizedBox(
                        width: 42,
                        height: 42,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 4,
                        ),
                      )
                    : Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(
                            Icons.sos_rounded,
                            color: Colors.white,
                            size: 64,
                          ),
                          Text(
                            'SOS',
                            style: GoogleFonts.outfit(
                              color: Colors.white,
                              fontSize: 40,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 2,
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildPoliceButton() {
    return SizedBox(
      width: double.infinity,
      height: 58,
      child: FilledButton.icon(
        onPressed: () => unawaited(_callPolice()),
        icon: const Icon(Icons.local_police_rounded),
        label: const Text('Call Police (100)'),
        style: FilledButton.styleFrom(
          backgroundColor: _navy,
          foregroundColor: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(18),
          ),
          textStyle: GoogleFonts.outfit(
            fontSize: 17,
            fontWeight: FontWeight.w900,
          ),
        ),
      ),
    );
  }

  Widget _buildSafetyNotes() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF7FB),
        borderRadius: BorderRadius.circular(22),
        border: Border.all(color: const Color(0xFFFFD2E6)),
      ),
      child: Text(
        'When SOS is triggered, nearby Heroes and NJ Tech Call Center receive the alert. Stay where you are if safe, and call Police 100 for immediate emergency help.',
        style: GoogleFonts.notoSansTamil(
          color: const Color(0xFF5C2845),
          fontWeight: FontWeight.w700,
          height: 1.45,
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
      backgroundColor: const Color(0xFFB00020),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(26)),
      title: const Text(
        'SOS Triggered!',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white,
          fontSize: 24,
          fontWeight: FontWeight.w900,
        ),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sos_rounded, color: Colors.white, size: 58),
          const SizedBox(height: 14),
          Text(
            'Cancelling in ${_secondsLeft}s...',
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 20,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Nearby Heroes and NJ Tech Call Center will be alerted.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, height: 1.35),
          ),
        ],
      ),
      actionsAlignment: MainAxisAlignment.center,
      actions: [
        FilledButton(
          onPressed: () => Navigator.of(context).pop(false),
          style: FilledButton.styleFrom(
            backgroundColor: Colors.white,
            foregroundColor: const Color(0xFFB00020),
            padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 14),
          ),
          child: const Text(
            'Cancel',
            style: TextStyle(fontWeight: FontWeight.w900),
          ),
        ),
      ],
    );
  }
}
