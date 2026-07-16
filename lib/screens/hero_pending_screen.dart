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

const Color kBg = Color(0xFF0A0A1A);
const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);

class HeroPendingScreen extends StatefulWidget {
  const HeroPendingScreen({super.key});

  @override
  State<HeroPendingScreen> createState() => _HeroPendingScreenState();
}

class _HeroPendingScreenState extends State<HeroPendingScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSubscription;
  StreamSubscription<rtdb.DatabaseEvent>? _statusUpdateSub;
  bool _isNavigating = false;

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      body: SafeArea(
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 80,
                  height: 80,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [kGold, Color(0xFFD4961A)],
                    ),
                    borderRadius: BorderRadius.circular(40),
                  ),
                  child: const Icon(
                    Icons.hourglass_empty,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  'Approval Pending',
                  style: GoogleFonts.outfit(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: kText,
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  'Your account is under review by our admin team.\nPlease wait for approval.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(
                    fontSize: 14,
                    color: kMuted,
                    height: 1.5,
                  ),
                ),
                const SizedBox(height: 32),
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: const Color(0x337B6FE0)),
                  ),
                  child: Column(
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.info_outline, size: 20, color: kPurple2),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'Real-time Status Active',
                              style: GoogleFonts.outfit(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: kText,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'You will be automatically redirected once your account is approved.',
                        textAlign: TextAlign.center,
                        style: GoogleFonts.outfit(
                          fontSize: 12,
                          color: kMuted,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                const CircularProgressIndicator(
                  color: kGold,
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
