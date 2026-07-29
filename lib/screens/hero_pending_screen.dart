// ================================================================
// HeroPendingScreen — Real-time Status Listener
// Allin1 Super App — Crash-free, Production-grade Implementation
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart' as rtdb;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:google_sign_in/google_sign_in.dart';

import 'bike_taxi/hero_dashboard_shell.dart';
import 'hero_login_screen.dart';

// THEME FIX (merge duplicate registration/status flows): this screen used
// to be dark theme and only showed a generic hourglass card. It's now the
// single post-registration status screen (hero_register_screen.dart routes
// straight here after submit, replacing the old one-shot, non-live
// HeroVerificationPendingScreen), repainted light pink/white to match the
// registration form, and showing a 3-step tracker per Nizam's request:
// Step 1 Onboarding (complete on submit), Step 2 Verify KYC + Step 3
// Waiting for HR Approval (both flip together the moment admin approves —
// there's only one approvalStatus field in Firestore, so 2 and 3 always
// change state as a pair). All the real-time listener / notification /
// auto-redirect logic below is unchanged.
const Color kBg = Color(0xFFFFF6FA);
const Color kSurface = Color(0xFFFFFFFF);
const Color kCard = Color(0xFFFFEAF3);
const Color kPurple = Color(0xFFFF4FA3);
const Color kPurple2 = Color(0xFFBE2A7A);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF00A84A);
const Color kGold = Color(0xFFB8860B);
const Color kRed = Color(0xFFE0245E);
const Color kText = Color(0xFF201A22);
const Color kMuted = Color(0xFF8C7A88);

class HeroPendingScreen extends StatefulWidget {
  const HeroPendingScreen({super.key});

  @override
  State<HeroPendingScreen> createState() => _HeroPendingScreenState();
}

class _HeroPendingScreenState extends State<HeroPendingScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSubscription;
  StreamSubscription<rtdb.DatabaseEvent>? _statusUpdateSub;
  bool _isNavigating = false;
  // Drives the 3-step tracker in build() — updated from the live
  // Firestore listener below, not fetched separately.
  String _approvalStatus = 'pending';

  // ── In-app approval/rejection notification ──────────────────────
  // Mirrors the hero_pings notification architecture (RTDB + local
  // notifications, not FCM/Cloud Functions — Blaze billing is off the
  // table). Own minimal channel, separate from
  // hero_ride_notification_service.dart's ride-specific channel, kept
  // self-contained here per scope discipline.
  static const String _approvalChannelId = 'hero_approval_status_v1';
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _notificationsReady = false;
  int _statusListenerAttachedAtMs = 0;

  @override
  void initState() {
    super.initState();
    _statusListenerAttachedAtMs = DateTime.now().toUtc().millisecondsSinceEpoch;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initializeStatusListener();
      unawaited(_initApprovalNotifications());
    });
  }

  Future<void> _initApprovalNotifications() async {
    if (kIsWeb || _notificationsReady) return;
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: DarwinInitializationSettings(),
    );
    await _notifications.initialize(settings: initSettings);

    const channel = AndroidNotificationChannel(
      _approvalChannelId,
      'Hero Approval Status',
      description: 'Notifies when your hero registration is approved or rejected.',
      importance: Importance.high,
    );
    await _notifications
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.createNotificationChannel(channel);
    _notificationsReady = true;
  }

  Future<void> _showApprovalStatusNotification({
    required bool approved,
    String? reason,
  }) async {
    if (kIsWeb) return;
    await _initApprovalNotifications();
    final title = approved ? 'Registration Approved' : 'Registration Rejected';
    final body = approved
        ? 'Your registration was approved!'
        : 'Registration rejected: ${(reason?.trim().isNotEmpty ?? false) ? reason!.trim() : 'No reason provided'}';
    await _notifications.show(
      id: 'hero_approval_status'.hashCode & 0x7fffffff,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _approvalChannelId,
          'Hero Approval Status',
          channelDescription: 'Notifies when your hero registration is approved or rejected.',
          importance: Importance.high,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(presentAlert: true, presentSound: true),
      ),
    );
  }

  void _listenForStatusUpdates(String uid) {
    _statusUpdateSub?.cancel();
    _statusUpdateSub = rtdb.FirebaseDatabase.instance
        .ref('hero_status_updates/$uid')
        .onValue
        .listen((event) {
      final raw = event.snapshot.value;
      if (raw is! Map) return;
      final data = Map<String, dynamic>.from(raw);

      // Stale-event guard: ignore anything written before this
      // listener attached (e.g. a leftover node from a prior
      // approval/rejection cycle), same pattern used for ride pings.
      final eventMs = (data['timestamp'] as num?)?.toInt() ?? 0;
      if (eventMs > 0 && eventMs < _statusListenerAttachedAtMs) {
        return;
      }

      final type = data['type'] as String?;
      if (type == 'approval') {
        unawaited(_showApprovalStatusNotification(approved: true));
      } else if (type == 'rejection') {
        unawaited(_showApprovalStatusNotification(
          approved: false,
          reason: data['reason'] as String?,
        ));
      }
    });
  }

  Future<void> _initializeStatusListener() async {
    final currentUser = FirebaseAuth.instance.currentUser;
    
    if (currentUser == null) {
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute<void>(builder: (_) => const HeroLoginScreen()),
        (route) => false,
      );
      return;
    }

    _listenForStatusUpdates(currentUser.uid);

    _statusSubscription = FirebaseFirestore.instance
        .collection('heroes')
        .doc(currentUser.uid)
        .snapshots()
        .listen((snapshot) async {
      if (_isNavigating) return;

      if (!snapshot.exists) {
        _triggerNavigation(() async {
          await FirebaseAuth.instance.signOut();
          await GoogleSignIn().signOut();
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute<void>(builder: (_) => const HeroLoginScreen()),
              (route) => false,
            );
          }
        });
        return;
      }

      final data = snapshot.data();
      final approvalStatus = data?['approvalStatus']?.toString().trim().toLowerCase();

      if (mounted && approvalStatus != null && approvalStatus != _approvalStatus) {
        setState(() => _approvalStatus = approvalStatus);
      }

      if (approvalStatus == 'approved') {
        _triggerNavigation(() {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(builder: (_) => const HeroDashboardShell()),
            );
          }
        });
      } else if (approvalStatus == 'rejected' || approvalStatus == 'blocked') {
        _triggerNavigation(() async {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Account rejected or blocked. Contact Admin.'),
                backgroundColor: kRed,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
          await FirebaseAuth.instance.signOut();
          await GoogleSignIn().signOut();
          if (mounted) {
            Navigator.pushAndRemoveUntil(
              context,
              MaterialPageRoute<void>(builder: (_) => const HeroLoginScreen()),
              (route) => false,
            );
          }
        });
      }
      // else: remain on pending screen
    });
  }

  void _triggerNavigation(FutureOr<void> Function() navigateAction) {
    if (_isNavigating) return;
    _isNavigating = true;
    _statusSubscription?.cancel();
    _statusUpdateSub?.cancel();
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) return;
      await navigateAction();
    });
  }

  @override
  void dispose() {
    _statusSubscription?.cancel();
    _statusUpdateSub?.cancel();
    super.dispose();
  }

  // Step 2 (Verify KYC) and Step 3 (Waiting HR Approval) are driven by the
  // SAME approvalStatus field — Firestore has no separate KYC-verified
  // state — so per Nizam's instruction they visually complete together
  // the instant admin approves. Only 'pending' vs 'approved' matters here;
  // 'rejected'/'blocked' are handled separately by the listener above
  // (sign-out + redirect), so this screen never needs to render them.
  bool get _isApproved => _approvalStatus == 'approved';

  Widget _stepRow({
    required int number,
    required String title,
    required String subtitle,
    required bool complete,
    required bool active,
  }) {
    final circleColor = complete
        ? kGreen
        : (active ? kPurple : kMuted.withValues(alpha: 0.3));
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 32,
          height: 32,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: circleColor,
          ),
          alignment: Alignment.center,
          child: complete
              ? const Icon(Icons.check_rounded, color: Colors.white, size: 18)
              : Text(
                  '$number',
                  style: GoogleFonts.outfit(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w800,
                  ),
                ),
        ),
        const SizedBox(width: 14),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: GoogleFonts.outfit(
                    color: kText,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  complete
                      ? 'Done'
                      : (active ? subtitle : 'Waiting'),
                  style: GoogleFonts.outfit(
                    color: complete
                        ? kGreen
                        : (active ? kPurple2 : kMuted),
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _stepConnector(bool complete) {
    return Padding(
      padding: const EdgeInsets.only(left: 15),
      child: Container(
        width: 2,
        height: 28,
        color: complete ? kGreen : kMuted.withValues(alpha: 0.25),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: _isApproved
                          ? const [kGreen, Color(0xFF00873C)]
                          : const [kPurple, kPurple2],
                    ),
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: (_isApproved ? kGreen : kPurple)
                            .withValues(alpha: 0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isApproved
                        ? Icons.verified_rounded
                        : Icons.hourglass_top_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isApproved ? 'Approved! Taking you in…' : 'Almost There',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isApproved
                      ? 'Your Hero account is approved. Opening your dashboard…'
                      : 'Your registration is submitted. Track your onboarding below.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: kMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),

                // ── 3-step onboarding tracker ──────────────────────
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: kSurface,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: kCard, width: 1.5),
                    boxShadow: [
                      BoxShadow(
                        color: kPurple.withValues(alpha: 0.08),
                        blurRadius: 24,
                        offset: const Offset(0, 12),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _stepRow(
                        number: 1,
                        title: 'Onboarding',
                        subtitle: 'Details submitted',
                        complete: true,
                        active: false,
                      ),
                      _stepConnector(true),
                      _stepRow(
                        number: 2,
                        title: 'Verify KYC',
                        subtitle: 'Admin is checking your documents',
                        complete: _isApproved,
                        active: !_isApproved,
                      ),
                      _stepConnector(_isApproved),
                      _stepRow(
                        number: 3,
                        title: 'Waiting for HR Approval',
                        subtitle: 'Final review before you go live',
                        complete: _isApproved,
                        active: !_isApproved,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: kPurple.withValues(alpha: 0.25)),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.info_outline, color: kPurple2, size: 20),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          "You'll be taken to your dashboard automatically the moment admin approves — no need to reopen the app.",
                          style: GoogleFonts.outfit(
                            color: kMuted,
                            fontSize: 12,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                CircularProgressIndicator(
                  color: _isApproved ? kGreen : kPurple,
                  strokeWidth: 2,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
