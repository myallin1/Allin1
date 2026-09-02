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
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/hero_onboarding_cache.dart';
import '../services/theme_service.dart';
import 'hero_login_screen.dart';
import 'hero_welcome_screen.dart';
import '../services/firestore_usage_tracking.dart';

// NEW (Aug 12 2026 — Nizam: "register page la kaatura mariye whatsapp
// admin to raise ur onboarding reuest nu whatsapp button kaatanum"):
// same placeholder pattern as hero_register_screen.dart's
// _adminWhatsApp — replace with the real number before release.
const String _kAdminWhatsApp = '91XXXXXXXXXX';

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
// NOTE: kPurple/kPurple2 here are actually the PRIMARY/SECONDARY brand
// colors (not a decorative purple accent) -- this screen's palette
// predates a rename and was never touched. That's why this file gets
// its own local sync function below instead of importing the shared
// app_palette.dart (whose kPurple means something different: a fixed
// decorative accent, not the theme's primary color).
Color kBg      = const Color(0xFFFFF6FA);
Color kSurface = const Color(0xFFFFFFFF);
Color kCard    = const Color(0xFFFFEAF3);
Color kPurple  = const Color(0xFFFF4FA3);
Color kPurple2 = const Color(0xFFBE2A7A);
Color kText    = const Color(0xFF201A22);
Color kMuted   = const Color(0xFF8C7A88);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen  = Color(0xFF00A84A);
const Color kGold   = Color(0xFFB8860B);
const Color kRed    = Color(0xFFE0245E);

/// Refreshes this screen's palette from the active ThemeService theme
/// (per Nizam's full Option 2 rollout). Safe no-op if ThemeService
/// isn't found in the tree (this screen is only reached from the Hero
/// app flow, where it is provided, but this stays defensive).
void _syncHeroPendingPalette(BuildContext context) {
  ThemeService ts;
  try {
    ts = Provider.of<ThemeService>(context);
  } catch (_) {
    return;
  }
  final theme = ts.currentTheme;
  final cs = theme.colorScheme;
  kPurple = cs.primary;
  kPurple2 = cs.secondary;
  kBg = theme.scaffoldBackgroundColor;
  kSurface = cs.surface;
  kCard = Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface);
  kText = cs.onSurface;
  kMuted = cs.onSurface.withValues(alpha: 0.55);
}

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
        ),);
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
        .trackedSnapshots()
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
        // Sync the local boot-routing cache the moment we learn about
        // approval, so the NEXT app boot on this device skips straight
        // to HeroDashboardShell with zero Firestore read (see
        // hero_onboarding_cache.dart / main_hero.dart's _HeroSetupGate).
        unawaited(HeroOnboardingCache.setApproved());
        // UPDATED (Aug 12 2026 — Nizam: "admin kuduthathum onboarding
        // animation la irunthu 'welcome to allin1' nu screen la
        // kaatanum"): used to jump straight to HeroDashboardShell here.
        // Now routes through HeroWelcomeScreen first, which plays a
        // short celebratory animation and then continues into the
        // dashboard on its own — same "no need to reopen/tap anything"
        // guarantee, just with the welcome moment in between.
        _triggerNavigation(() {
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute<void>(builder: (_) => const HeroWelcomeScreen()),
            );
          }
        });
      } else if (approvalStatus == 'rejected' || approvalStatus == 'blocked') {
        // Clear the local cache so a stale 'pending' flag can never block
        // a legitimate future re-registration attempt after sign-out.
        unawaited(HeroOnboardingCache.clear());
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

  bool _manualChecking = false;

  // NEW (Aug 12 2026 — Nizam: "a manual 'Check Approval Status' refresh
  // button"): a one-off .get() distinct from the always-on .snapshots()
  // stream above — purely a reassurance affordance for the hero (the
  // live listener already reacts instantly; this just lets them
  // confirm nothing is stuck).
  Future<void> _checkApprovalNow() async {
    if (_manualChecking) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null) return;
    setState(() => _manualChecking = true);
    try {
      final snap = await FirebaseFirestore.instance
          .collection('heroes')
          .doc(currentUser.uid)
          .trackedGet();
      final status = snap.data()?['approvalStatus']?.toString().trim().toLowerCase();
      if (!mounted) return;
      if (status != null && status != _approvalStatus) {
        setState(() => _approvalStatus = status);
      }
      if (status != 'approved') {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Still pending admin approval. We\'ll auto-open your dashboard the moment it\'s approved.')),
        );
      }
      // approved/rejected transitions are handled by the live listener
      // above, which will fire independently of this manual check.
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Could not check status right now. Please try again.')),
      );
    } finally {
      if (mounted) setState(() => _manualChecking = false);
    }
  }

  Future<void> _launchWhatsAppFollowUp() async {
    final message = Uri.encodeComponent(
      'I have submitted my registration. Please check and verify my proof '
      'details, then approve soon.',
    );
    final url = Uri.parse('https://wa.me/$_kAdminWhatsApp?text=$message');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Unable to open WhatsApp')),
      );
    }
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
    _syncHeroPendingPalette(context);
    // NEW (Aug 12 2026 — Nizam: "antha page vittu hero app again
    // register page ku pogakudathu... onboarding waiting page laye
    // irukanum"): blocks back navigation off this screen entirely while
    // still pending — the only ways out are the live approval listener
    // above (pushReplacement into HeroWelcomeScreen) or the
    // rejected/blocked branch (which explicitly signs out first). A
    // hero can never back-button their way into a stale registration
    // form or a half-set-up state.
    return PopScope(
      canPop: false,
      child: Scaffold(
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
                          ? [kGreen, const Color(0xFF00873C)]
                          : [kPurple, kPurple2],
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
                if (!_isApproved) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _manualChecking ? null : _checkApprovalNow,
                      icon: _manualChecking
                          ? SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2, color: kPurple),
                            )
                          : Icon(Icons.refresh_rounded, color: kPurple, size: 20),
                      label: Text(
                        _manualChecking ? 'Checking…' : 'Check Approval Status',
                        style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: BorderSide(color: kPurple),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),
                  // NEW (Aug 12 2026 — Nizam: "register page la kaatura
                  // mariye whatsapp admin to raise ur onboarding reuest
                  // nu whatsapp button kaatanum"): same fallback pattern
                  // as the registration form's WhatsApp card, so a hero
                  // waiting on approval can nudge admin directly instead
                  // of just staring at the tracker.
                  SizedBox(
                    width: double.infinity,
                    child: OutlinedButton.icon(
                      onPressed: _launchWhatsAppFollowUp,
                      icon: const Icon(Icons.chat_rounded, color: Color(0xFF25D366), size: 20),
                      label: Text(
                        'Raise Onboarding Request via WhatsApp',
                        style: GoogleFonts.outfit(color: kText, fontWeight: FontWeight.w700, fontSize: 13),
                      ),
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: Color(0xFF25D366)),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                ],
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
      ),
    );
  }
}
