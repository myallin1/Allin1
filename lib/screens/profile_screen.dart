// ================================================================
// Profile Screen - User Profile Management
// Allin1 Super App - Allin1
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:provider/provider.dart';

import '../services/hive_cache.dart';
import '../services/local_sync_service.dart';
import '../services/theme_service.dart';
import '../services/firestore_usage_tracking.dart';

// NOTE (Nizam's full Option 2 rollout): kPurple/kPurple2 here are this
// screen's PRIMARY/SECONDARY brand color (not a decorative accent), so
// they get their own local sync rather than the shared app_palette.dart.
Color kSurface = const Color(0xFF0D0D18);
Color kCard    = const Color(0xFF141420);
Color kCard2   = const Color(0xFF1A1A28);
Color kPurple  = const Color(0xFF7B6FE0);
Color kPurple2 = const Color(0xFF7B6FE0);
Color kText    = const Color(0xFFEEEEF5);
Color kMuted   = const Color(0xFF7777A0);
Color kBorder  = const Color(0x267B6FE0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen  = Color(0xFF3DBA6F);
const Color kGold   = Color(0xFFF5C542);
const Color kRed    = Color(0xFFE05555);

void _syncProfilePalette(BuildContext context) {
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
  kSurface = cs.surface;
  kCard = cs.surface;
  kCard2 = Color.alphaBlend(cs.primary.withValues(alpha: 0.06), cs.surface);
  kText = cs.onSurface;
  kMuted = cs.onSurface.withValues(alpha: 0.55);
  kBorder = theme.dividerColor;
}

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _emailController = TextEditingController();

  bool _isLoading = false;
  bool _isEditing = false;

  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _loadUserData();
  }

  void _loadUserData() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user != null) {
      _currentUser = user;
      
      // Zero Database Wastage: Try local cache first
      final cachedProfile = await HiveCache.getCachedUserProfile();
      if (cachedProfile != null) {
        if (mounted) {
          setState(() {
            _nameController.text = cachedProfile['name']?.toString() ?? user.displayName ?? '';
            _emailController.text = cachedProfile['email']?.toString() ?? user.email ?? '';
            _phoneController.text = cachedProfile['phone']?.toString() ?? user.phoneNumber ?? '';
          });
        }
      } else {
        // Fallback to Auth + Firestore if cache is totally empty
        if (mounted) {
          setState(() {
            _nameController.text = user.displayName ?? '';
            _emailController.text = user.email ?? '';
            _phoneController.text = user.phoneNumber ?? '';
          });
        }
        unawaited(_loadProfileFromFirestore(user.uid));
      }
    }
  }

  Future<void> _loadProfileFromFirestore(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).trackedGet();
      final data = doc.data() ?? {};
      final phone = (data['phoneNumber'] as String?)?.trim();
      final phoneAlt = (data['phone'] as String?)?.trim();
      final resolvedPhone = (phone != null && phone.isNotEmpty)
          ? phone
          : (phoneAlt != null && phoneAlt.isNotEmpty ? phoneAlt : null);
          
      final name = data['name'] as String? ?? _currentUser?.displayName ?? '';
      final email = data['email'] as String? ?? _currentUser?.email ?? '';

      if (mounted) {
        setState(() {
          if (resolvedPhone != null) _phoneController.text = resolvedPhone;
          if (name.isNotEmpty) _nameController.text = name;
          if (email.isNotEmpty) _emailController.text = email;
        });
      }
      
      // Warm up the cache for next time
      await HiveCache.cacheUserProfile({
        'name': name,
        'email': email,
        'phone': resolvedPhone ?? '',
      });
    } catch (_) {
      // Non-fatal fallback
    }
  }

  Future<void> _saveProfile() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      if (_currentUser != null) {
        final newName = _nameController.text.trim();
        await _currentUser!.updateDisplayName(newName);
        
        // Write to Firestore
        await FirebaseFirestore.instance
            .collection('users')
            .doc(_currentUser!.uid)
            .set({
          'name': newName,
          'email': _emailController.text.trim(),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));

        // Update Local Cache immediately (Zero Wastage)
        await HiveCache.cacheUserProfile({
          'name': newName,
          'email': _emailController.text.trim(),
          'phone': _phoneController.text.trim(),
        });
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Profile updated successfully!',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kGreen,
            behavior: SnackBarBehavior.floating,
          ),
        );
        setState(() => _isEditing = false);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Failed to update profile: $e',
              style: GoogleFonts.notoSansTamil(color: Colors.white),
            ),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    _syncProfilePalette(context);
    return Scaffold(
      key: const Key('profile_screen_scaffold'),
      backgroundColor: kSurface,
      appBar: AppBar(
        backgroundColor: kSurface,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back_ios_new, color: kText),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(
          'Profile',
          style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: kText),
        ),
        actions: [
          if (!_isEditing)
            TextButton(
              onPressed: () => setState(() => _isEditing = true),
              child: Text(
                'Edit',
                style: GoogleFonts.outfit(
                  color: kGold,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildProfileHeader(),
              const SizedBox(height: 30),
              _buildInfoCard(),
              const SizedBox(height: 20),
              // FIX (audit cleanup): removed — this "Activity Stats"
              // card showed hardcoded fake numbers (24 rides, 156 km,
              // ₹120 saved) for literally every customer, never backed
              // by any real query. Misleading fabricated data is worse
              // than no card at all; removed rather than left dummy.
              // _buildStatsCard() and its _statItem() helper are left
              // in place below, unused, in case a future mandate wants
              // to wire them to real order-history counts.
              _buildAccountSection(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Center(
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [kGold, Color(0xFFD4961A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: kGold.withValues(alpha: 0.3),
                      blurRadius: 20,
                      offset: const Offset(0, 8),
                    ),
                  ],
                ),
                child: Center(
                  child: Text(
                    _nameController.text.isNotEmpty
                        ? _nameController.text[0].toUpperCase()
                        : 'U',
                    style: GoogleFonts.outfit(
                      fontSize: 40,
                      fontWeight: FontWeight.bold,
                      color: Colors.white,
                    ),
                  ),
                ),
              ),
              if (_isEditing)
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: kPurple,
                      shape: BoxShape.circle,
                      border: Border.all(color: kSurface, width: 2),
                    ),
                    child: const Icon(
                      Icons.camera_alt,
                      size: 16,
                      color: Colors.white,
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 16),
          if (!_isEditing)
            Text(
              _nameController.text.isNotEmpty
                  ? _nameController.text
                  : 'NJ Tech User',
              style: GoogleFonts.outfit(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: kText,
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildInfoCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.person_outline, color: kGold, size: 20),
              const SizedBox(width: 8),
              Text(
                'Personal Information',
                style: GoogleFonts.outfit(
                  color: kText,
                  fontSize: 16,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _buildTextField(
            controller: _nameController,
            label: 'Full Name',
            icon: Icons.badge_outlined,
            enabled: _isEditing,
            validator: (v) => v!.isEmpty ? 'Name is required' : null,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _phoneController,
            label: 'Phone Number',
            icon: Icons.phone_outlined,
            enabled: _isEditing,
            keyboardType: TextInputType.phone,
          ),
          const SizedBox(height: 16),
          _buildTextField(
            controller: _emailController,
            label: 'Email Address',
            icon: Icons.email_outlined,
            enabled: false, // Email cannot be changed
          ),
          if (_isEditing) ...[
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isLoading ? null : _saveProfile,
                style: ElevatedButton.styleFrom(
                  backgroundColor: kGreen,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  elevation: 0,
                ),
                child: _isLoading
                    ? const SizedBox(
                        width: 24,
                        height: 24,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        'Save Changes',
                        style: GoogleFonts.outfit(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                        ),
                      ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    bool enabled = true,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      enabled: enabled,
      keyboardType: keyboardType,
      validator: validator,
      style: GoogleFonts.outfit(color: kText),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.outfit(color: kMuted),
        prefixIcon: Icon(icon, color: kMuted, size: 20),
        filled: true,
        fillColor: enabled ? kCard : kCard.withValues(alpha: 0.5),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: kBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kGold, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: kRed),
        ),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _buildAccountSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Account',
          style: GoogleFonts.outfit(
            color: kMuted,
            fontSize: 12,
            fontWeight: FontWeight.w600,
            letterSpacing: 1,
          ),
        ),
        const SizedBox(height: 12),
        // FIX (audit: "athulla iruka option dummy and unwanted ah
        // iruku" — customer-reported cleanup request): removed 5 menu
        // items. Payment Methods / Saved Addresses had dead no-op
        // onTap: () {} handlers and don't correspond to any real
        // feature anywhere in this app (not even the side drawer) —
        // pure placeholders. Help & Support was also a no-op, but DOES
        // duplicate a real, working drawer item (dashboard_screen.dart
        // — WhatsApp support link). Ride History navigated to
        // '/ride-history', a route never registered in
        // main_customer.dart (would throw at runtime) — also a
        // duplicate, since the drawer's real "Activity" item already
        // opens RideHistoryScreen correctly. Captain Documents
        // navigated to another unregistered route, '/captain-docs' —
        // and is a Hero-app concept (DL/RC/Aadhaar upload) that had no
        // business being in the Customer app's profile at all, looks
        // like leftover copy-paste from a Hero screen. Kept Settings
        // (real, working route) and Sign Out (real, fully wired) below
        // — the only two that actually did something.
        _buildMenuItem(
          icon: Icons.settings_outlined,
          title: 'Settings',
          subtitle: 'App preferences',
          onTap: () => Navigator.pushNamed(context, '/settings'),
        ),
        _buildMenuItem(
          icon: Icons.logout,
          title: 'Sign Out',
          subtitle: 'Log out of your account',
          color: kRed,
          onTap: () async {
            final confirm = await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                backgroundColor: kCard2,
                title:
                    Text('Sign Out?', style: GoogleFonts.outfit(color: kText)),
                content: Text(
                  'Are you sure you want to sign out?',
                  style: GoogleFonts.outfit(color: kMuted),
                ),
                actions: [
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, false),
                    child: Text(
                      'Cancel',
                      style: GoogleFonts.outfit(color: kMuted),
                    ),
                  ),
                  TextButton(
                    onPressed: () => Navigator.pop(ctx, true),
                    child: Text(
                      'Sign Out',
                      style: GoogleFonts.outfit(color: kRed),
                    ),
                  ),
                ],
              ),
            );
            if (confirm ?? false) {
              // ── Local-First: wipe cache before signing out ──
              await LocalSyncService.instance.clearAll();
              await FirebaseAuth.instance.signOut();
              if (mounted) {
                Navigator.of(context).popUntil((route) => route.isFirst);
              }
            }
          },
        ),
      ],
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? color,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Material(
        color: kCard2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: (color ?? kPurple).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color ?? kPurple, size: 20),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        title,
                        style: GoogleFonts.outfit(
                          color: color ?? kText,
                          fontSize: 15,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      Text(
                        subtitle,
                        style: GoogleFonts.outfit(
                          color: kMuted,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right, color: kMuted, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
    super.dispose();
  }
}
