// ================================================================
// Admin Dashboard Screen
// Allin1 Super App v1.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/session_service.dart';

// ── Theme Colors ─────────────────────────────────────────────
const Color kBg = Color(0xFF0A0A1A);
const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kRed = Color(0xFFE05555);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  int _totalUsers = 0;
  int _totalRiders = 0;
  int _pendingVerifications = 0;
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  Future<void> _loadStats() async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('userType', isEqualTo: 1) // Regular users
          .get();

      final ridersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('userType', isEqualTo: 0) // Riders
          .get();

      final pendingSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where('userType', isEqualTo: 0)
          .where('isVerified', isEqualTo: false)
          .get();

      if (mounted) {
        setState(() {
          _totalUsers = usersSnapshot.docs.length;
          _totalRiders = ridersSnapshot.docs.length;
          _pendingVerifications = pendingSnapshot.docs.length;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(
          'Admin Panel',
          style: GoogleFonts.poppins(color: kText),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout, color: kText),
            onPressed: _showLogoutDialog,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: kPurple))
          : SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Welcome Card ─────────────────────────────────
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(20),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        colors: [kOrange, kOrange.withAlpha(179)],
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Icon(
                          Icons.admin_panel_settings,
                          color: Colors.white,
                          size: 40,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Welcome, Admin!',
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        const Text(
                          'Manage your platform from here',
                          style: TextStyle(color: Colors.white70),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 24),

                  // ── Stats Grid ────────────────────────────────────
                  Text(
                    'Platform Statistics',
                    style: GoogleFonts.poppins(
                      color: kText,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          icon: Icons.people,
                          label: 'Total Users',
                          value: '$_totalUsers',
                          color: kPurple,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          icon: Icons.directions_car,
                          label: 'Total Riders',
                          value: '$_totalRiders',
                          color: kGreen,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 12),

                  Row(
                    children: [
                      Expanded(
                        child: _statCard(
                          icon: Icons.pending_actions,
                          label: 'Pending Verify',
                          value: '$_pendingVerifications',
                          color: kOrange,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _statCard(
                          icon: Icons.check_circle,
                          label: 'Active Riders',
                          value: '${_totalRiders - _pendingVerifications}',
                          color: kGreen,
                        ),
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),

                  // ── Admin Actions ─────────────────────────────────
                  Text(
                    'Management',
                    style: GoogleFonts.poppins(
                      color: kText,
                      fontSize: 18,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(height: 12),

                  _actionTile(
                    icon: Icons.verified_user,
                    title: 'Verify Riders',
                    subtitle: 'Review and approve rider applications',
                    color: kGreen,
                    onTap: _navigateToRiderVerification,
                  ),

                  _actionTile(
                    icon: Icons.people_outline,
                    title: 'Manage Users',
                    subtitle: 'View and manage registered users',
                    color: kPurple,
                    onTap: _showComingSoon,
                  ),

                  _actionTile(
                    icon: Icons.analytics,
                    title: 'Analytics',
                    subtitle: 'View platform analytics',
                    color: kOrange,
                    onTap: _showComingSoon,
                  ),

                  _actionTile(
                    icon: Icons.settings,
                    title: 'Settings',
                    subtitle: 'Configure platform settings',
                    color: kMuted,
                    onTap: _showComingSoon,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _statCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: GoogleFonts.poppins(
              color: kText,
              fontSize: 24,
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            label,
            style: const TextStyle(color: kMuted, fontSize: 12),
          ),
        ],
      ),
    );
  }

  Widget _actionTile({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: ListTile(
        onTap: onTap,
        tileColor: kCard,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
        ),
        leading: Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: color.withAlpha(51),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: color),
        ),
        title: Text(title, style: const TextStyle(color: kText)),
        subtitle:
            Text(subtitle, style: const TextStyle(color: kMuted, fontSize: 12)),
        trailing: const Icon(Icons.chevron_right, color: kMuted),
      ),
    );
  }

  void _navigateToRiderVerification() {
    // Navigate to rider verification screen
    Navigator.push(
      context,
      MaterialPageRoute<void>(builder: (_) => const RiderVerificationScreen()),
    );
  }

  void _showLogoutDialog() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Logout', style: TextStyle(color: kText)),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              await SessionService().clearSession();
              if (context.mounted) {
                await Navigator.of(context).pushNamedAndRemoveUntil(
                  '/login',
                  (route) => false,
                );
              }
            },
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showComingSoon() {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Coming soon!')),
    );
  }
}

// ================================================================
// Rider Verification Screen
// ================================================================
class RiderVerificationScreen extends StatelessWidget {
  const RiderVerificationScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: const Text('Verify Riders', style: TextStyle(color: kText)),
        centerTitle: true,
      ),
      body: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .where('userType', isEqualTo: 0)
            .where('isVerified', isEqualTo: false)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(
              child: CircularProgressIndicator(color: kPurple),
            );
          }

          if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.check_circle, color: kGreen, size: 64),
                  SizedBox(height: 16),
                  Text(
                    'No pending verifications!',
                    style: TextStyle(color: kText, fontSize: 18),
                  ),
                  SizedBox(height: 8),
                  Text(
                    'All rider applications have been reviewed',
                    style: TextStyle(color: kMuted),
                  ),
                ],
              ),
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: snapshot.data!.docs.length,
            itemBuilder: (context, index) {
              final rider = snapshot.data!.docs[index];
              return _riderCard(context, rider);
            },
          );
        },
      ),
    );
  }

  Widget _riderCard(BuildContext context, QueryDocumentSnapshot rider) {
    final username = (rider['username'] as String?) ?? 'Unknown';
    final email = (rider['email'] as String?) ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: kPurple.withAlpha(51),
                child: Text(
                  username.isNotEmpty ? username[0].toUpperCase() : 'U',
                  style: const TextStyle(color: kPurple),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      username,
                      style: const TextStyle(
                        color: kText,
                        fontWeight: FontWeight.w600,
                        fontSize: 16,
                      ),
                    ),
                    Text(
                      email,
                      style: const TextStyle(color: kMuted, fontSize: 12),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _rejectRider(context, rider.id),
                  icon: const Icon(Icons.close, color: kRed),
                  label: const Text('Reject', style: TextStyle(color: kRed)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: kRed),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _approveRider(context, rider.id),
                  icon: const Icon(Icons.check),
                  label: const Text('Approve'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: kGreen,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Future<void> _approveRider(BuildContext context, String riderId) async {
    try {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(riderId)
          .update({'isVerified': true});
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Rider approved!'),
            backgroundColor: kGreen,
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Error: $e'),
            backgroundColor: kRed,
          ),
        );
      }
    }
  }

  Future<void> _rejectRider(BuildContext context, String riderId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: kCard,
        title: const Text('Reject Rider', style: TextStyle(color: kText)),
        content: const Text(
          'Are you sure you want to reject this rider?',
          style: TextStyle(color: kMuted),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: kRed),
            child: const Text('Reject'),
          ),
        ],
      ),
    );

    if ((confirmed ?? false) && context.mounted) {
      try {
        await FirebaseFirestore.instance
            .collection('users')
            .doc(riderId)
            .delete();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Rider rejected and removed'),
              backgroundColor: kOrange,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Error: $e'),
              backgroundColor: kRed,
            ),
          );
        }
      }
    }
  }
}
