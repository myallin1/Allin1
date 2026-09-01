// ================================================================
// SellerPendingScreen — Real-time Approval Status Listener
// Allin1 Super App — mirrors hero_pending_screen.dart's pattern
// ================================================================
//
// WHY THIS EXISTS: per Nizam/CTO's explicit request, sellers can no
// longer go live the instant they finish onboarding — a franchise
// model across 5 cities means an unverified/fake seller going live
// instantly is a brand risk. seller_onboarding_screen.dart now writes
// status: 'pending' (was 'active') and routes here instead of
// straight to the menu-authoring screen. This screen listens live to
// sellers/{uid}.status and auto-navigates the moment admin approves
// (status -> 'active') or signs the seller out if rejected — same
// mechanics as HeroPendingScreen, just teal-themed to match the
// seller app instead of the hero app's pink.

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/session_service.dart';
import 'login_screen.dart';
import 'seller_home_kitchen_menu_screen.dart';
import '../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFFF7FAF8);
const Color _surface = Color(0xFFFFFFFF);
const Color _card = Color(0xFFFFFFFF);
const Color _teal = Color(0xFF11998E);
const Color _tealLight = Color(0xFF38EF7D);
const Color _green = Color(0xFF2E9E63);
const Color _red = Color(0xFFD64545);
const Color _text = Color(0xFF1A1A1A);
const Color _muted = Color(0xFF6B7280);
const Color _border = Color(0x1A11998E);

class SellerPendingScreen extends StatefulWidget {
  final String sellerId;
  final String sellerName;
  final String categoryName;

  const SellerPendingScreen({
    required this.sellerId,
    required this.sellerName,
    required this.categoryName,
    super.key,
  });

  @override
  State<SellerPendingScreen> createState() => _SellerPendingScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('sellerId', sellerId));
    properties.add(StringProperty('sellerName', sellerName));
    properties.add(StringProperty('categoryName', categoryName));
  }
}

class _SellerPendingScreenState extends State<SellerPendingScreen> {
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _statusSub;
  bool _isNavigating = false;
  String _status = 'pending';

  @override
  void initState() {
    super.initState();
    _listen();
  }

  void _listen() {
    _statusSub = FirebaseFirestore.instance
        .collection('sellers')
        .doc(widget.sellerId)
        .trackedSnapshots()
        .listen((snap) {
      if (_isNavigating || !mounted) return;

      if (!snap.exists) return;
      final status = (snap.data()?['status'] as String?)?.trim().toLowerCase() ?? 'pending';
      if (status != _status) setState(() => _status = status);

      if (status == 'active') {
        _isNavigating = true;
        _statusSub?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          Navigator.pushReplacement(
            context,
            MaterialPageRoute<void>(
              builder: (_) => SellerHomeKitchenMenuScreen(
                sellerId: widget.sellerId,
                title: 'My Menu',
                categoryName: widget.categoryName,
              ),
            ),
          );
        });
      } else if (status == 'rejected') {
        _isNavigating = true;
        _statusSub?.cancel();
        WidgetsBinding.instance.addPostFrameCallback((_) async {
          if (!mounted) return;
          final reason = snap.data()?['rejectionReason'] as String?;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Registration rejected${(reason?.trim().isNotEmpty ?? false) ? ': ${reason!.trim()}' : '. Contact Admin.'}',
              ),
              backgroundColor: _red,
              behavior: SnackBarBehavior.floating,
            ),
          );
          await FirebaseAuth.instance.signOut();
          if (!mounted) return;
          Navigator.pushAndRemoveUntil(
            context,
            MaterialPageRoute<void>(
              builder: (_) => const LoginScreen(
                presetUserType: UserType.customer,
                lockUserType: true,
                title: 'Seller Login',
                subtitle: 'Manage your Allin1 store',
                lockedUserLabel: 'Seller',
                postLoginRoute: '/seller-home',
              ),
            ),
            (route) => false,
          );
        });
      }
    });
  }

  @override
  void dispose() {
    _statusSub?.cancel();
    super.dispose();
  }

  bool get _isApproved => _status == 'active';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
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
                      colors: _isApproved ? const [_green, _tealLight] : const [_teal, Color(0xFF0D7A6E)],
                    ),
                    borderRadius: BorderRadius.circular(40),
                    boxShadow: [
                      BoxShadow(
                        color: (_isApproved ? _green : _teal).withValues(alpha: 0.28),
                        blurRadius: 20,
                        offset: const Offset(0, 10),
                      ),
                    ],
                  ),
                  child: Icon(
                    _isApproved ? Icons.verified_rounded : Icons.hourglass_top_rounded,
                    size: 40,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  _isApproved ? 'Approved! Taking you in…' : 'Registration Submitted',
                  style: GoogleFonts.outfit(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: _text,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  _isApproved
                      ? 'Your shop is approved. Opening your menu dashboard…'
                      : 'Our team is verifying "${widget.sellerName}". You\'ll be taken in automatically once approved — usually within a few hours.',
                  textAlign: TextAlign.center,
                  style: GoogleFonts.outfit(fontSize: 13.5, color: _muted, height: 1.5),
                ),
                const SizedBox(height: 28),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: _surface,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: _border),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: (_isApproved ? _green : _teal).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Icon(
                          _isApproved ? Icons.check_circle : Icons.fact_check_outlined,
                          color: _isApproved ? _green : _teal,
                          size: 22,
                        ),
                      ),
                      const SizedBox(width: 14),
                      Expanded(
                        child: Text(
                          _isApproved
                              ? 'Verification complete'
                              : 'Admin is reviewing your shop name, category and city before you go live to customers.',
                          style: GoogleFonts.outfit(color: _text, fontSize: 12.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                Container(
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: _card,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.info_outline, color: _muted, size: 18),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Text(
                          'This screen updates itself — no need to reopen the app once approved.',
                          style: GoogleFonts.outfit(color: _muted, fontSize: 11.5),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                CircularProgressIndicator(color: _isApproved ? _green : _teal, strokeWidth: 2),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
