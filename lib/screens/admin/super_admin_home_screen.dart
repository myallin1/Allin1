import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'commission_settings_screen.dart';

class SuperAdminHomeScreen extends StatelessWidget {
  const SuperAdminHomeScreen({super.key});

  static const Color _bg = Color(0xFF0A0A12);
  static const Color _surface = Color(0xFF12121E);
  static const Color _purple = Color(0xFF6C63FF);
  static const Color _orange = Color(0xFFFF6B35);
  static const Color _green = Color(0xFF00C853);
  static const Color _gold = Color(0xFFFFBB00);
  static const Color _text = Color(0xFFEEEEF5);

  String _todayStart() {
    final now = DateTime.now();
    return DateTime(now.year, now.month, now.day)
        .millisecondsSinceEpoch
        .toString();
  }

  void _showSnack(BuildContext context, String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(msg, style: const TextStyle(color: _text)),
        backgroundColor: _surface,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: _purple.withValues(alpha: 0.4)),
        ),
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    if (context.mounted) {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            SliverToBoxAdapter(child: _buildHeader(context)),
            SliverToBoxAdapter(child: _buildSosCallCenterBanner(context)),
            SliverToBoxAdapter(child: _buildStatsRow()),
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              sliver: SliverGrid(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 2,
                  crossAxisSpacing: 14,
                  mainAxisSpacing: 14,
                  childAspectRatio: 0.92,
                ),
                delegate: SliverChildListDelegate(_buildCards(context)),
              ),
            ),
            SliverToBoxAdapter(child: _buildFooter(context)),
          ],
        ),
      ),
    );
  }

  Widget _buildSosCallCenterBanner(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('sos_alerts')
          .where('status', isEqualTo: 'active')
          .snapshots(),
      builder: (context, snapshot) {
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const SizedBox.shrink();
        }

        final doc = snapshot.data!.docs.first;
        final data = doc.data();
        final userName = data['userName']?.toString().trim();
        final userPhone = data['userPhone']?.toString().trim();

        return Container(
          margin: const EdgeInsets.fromLTRB(16, 14, 16, 0),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            gradient: const LinearGradient(
              colors: [Color(0xFFFF1744), Color(0xFF7A0014)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withValues(alpha: 0.28)),
            boxShadow: [
              BoxShadow(
                color: const Color(0xFFFF1744).withValues(alpha: 0.45),
                blurRadius: 24,
                spreadRadius: 2,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Row(
            children: [
              const Icon(Icons.sos_rounded, color: Colors.white, size: 42),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'LIVE SOS ALERT - CALL CENTER ACTION REQUIRED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 16,
                        fontWeight: FontWeight.w900,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      [
                        if (userName != null && userName.isNotEmpty) userName,
                        if (userPhone != null && userPhone.isNotEmpty)
                          userPhone,
                        'Dispatch support / Police 100 immediately',
                      ].join(' • '),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12.5,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              ElevatedButton.icon(
                onPressed: () async {
                  await doc.reference.update({
                    'status': 'resolved',
                    'resolvedAt': FieldValue.serverTimestamp(),
                    'resolvedBy':
                        FirebaseAuth.instance.currentUser?.uid ?? 'admin',
                  });
                  if (context.mounted) {
                    _showSnack(context, 'SOS resolved and cleared.');
                  }
                },
                icon: const Icon(Icons.check_circle_rounded),
                label: const Text('Resolve SOS'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.white,
                  foregroundColor: const Color(0xFFB00020),
                  textStyle: const TextStyle(fontWeight: FontWeight.w900),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHeader(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
      decoration: BoxDecoration(
        color: _surface,
        border: Border(
          bottom: BorderSide(color: _purple.withValues(alpha: 0.2)),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _purple.withValues(alpha: 0.15),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: _purple.withValues(alpha: 0.3)),
            ),
            child: const Icon(Icons.lock, color: _purple, size: 22),
          ),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '🔐 Allin1 HQ',
                  style: TextStyle(
                    color: _text,
                    fontSize: 22,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 0.4,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'NJ TECH Admin Portal',
                  style: TextStyle(
                    color: _text.withValues(alpha: 0.55),
                    fontSize: 13,
                    letterSpacing: 0.2,
                  ),
                ),
              ],
            ),
          ),
          IconButton(
            onPressed: () {},
            icon: Icon(
              Icons.notifications_outlined,
              color: _text.withValues(alpha: 0.6),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatsRow() {
    final todayMs = int.parse(_todayStart());
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: StreamBuilder<QuerySnapshot>(
        stream: FirebaseFirestore.instance
            .collection('rides')
            .where(
              'createdAt',
              isGreaterThanOrEqualTo:
                  Timestamp.fromMillisecondsSinceEpoch(todayMs),
            )
            .snapshots(),
        builder: (context, snapshot) {
          int totalRides = 0;
          double revenue = 0;
          if (snapshot.hasData) {
            final docs = snapshot.data!.docs;
            totalRides = docs.length;
            for (final doc in docs) {
              final data = doc.data()! as Map<String, dynamic>;
              final finalFare = (data['finalFare'] as num?)?.toDouble();
              final actualFare = (data['actualFare'] as num?)?.toDouble();
              final tipAmount = (data['tipAmount'] as num?)?.toDouble();
              final estFare = (data['fare'] as num?)?.toDouble();
              revenue += finalFare ??
                  ((actualFare ?? 0) + (tipAmount ?? 0)) ??
                  estFare ??
                  0.0;
            }
          }
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 4),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _purple.withValues(alpha: 0.15)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _statChip(
                  icon: Icons.directions_bike,
                  label: 'Rides Today',
                  value: snapshot.hasData ? '$totalRides' : '…',
                  color: _orange,
                ),
                _divider(),
                _activeHeroesChip(),
                _divider(),
                _statChip(
                  icon: Icons.currency_rupee,
                  label: 'Revenue',
                  value:
                      snapshot.hasData ? '₹${revenue.toStringAsFixed(0)}' : '…',
                  color: _gold,
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _activeHeroesChip() {
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('online_heroes').onValue,
      builder: (context, snap) {
        int count = 0;
        if (snap.hasData && snap.data!.snapshot.value != null) {
          final val = snap.data!.snapshot.value;
          if (val is Map) {
            count = val.length;
          }
        }
        return _statChip(
          icon: Icons.flash_on,
          label: 'Active Heroes',
          value: '${snap.hasData ? count : '…'}',
          color: _green,
        );
      },
    );
  }

  Widget _statChip({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 18),
        const SizedBox(height: 4),
        Text(
          value,
          style: TextStyle(
            color: color,
            fontSize: 17,
            fontWeight: FontWeight.w800,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          label,
          style: TextStyle(color: _text.withValues(alpha: 0.5), fontSize: 10.5),
        ),
      ],
    );
  }

  Widget _divider() =>
      Container(height: 36, width: 1, color: _text.withValues(alpha: 0.08));

  List<Widget> _buildCards(BuildContext context) {
    return [
      _ServiceCard(
        title: 'Bike Taxi',
        icon: Icons.electric_moped,
        cardColor: _orange,
        isActive: true,
        onTap: () => Navigator.pushNamed(context, '/admin-home'),
      ),
      _ServiceCard(
        title: 'Food Delivery',
        icon: Icons.fastfood,
        cardColor: const Color(0xFFFF5252),
        isActive: false,
        onTap: () => _showSnack(context, '🍔 Food Delivery launching soon!'),
      ),
      _ServiceCard(
        title: 'Electronics\nShop',
        icon: Icons.devices,
        cardColor: _purple,
        isActive: false,
        onTap: () => _showSnack(context, '📱 Electronics Shop coming soon!'),
      ),
      _ServiceCard(
        title: 'App Settings',
        icon: Icons.admin_panel_settings,
        cardColor: _gold,
        isActive: true,
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute<void>(
            builder: (_) => const CommissionSettingsScreen(),
          ),
        ),
      ),
    ];
  }

  Widget _buildFooter(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      child: Column(
        children: [
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => Navigator.pushReplacement(
                context,
                MaterialPageRoute<void>(
                  builder: (_) => const SuperAdminHomeScreen(),
                ),
              ),
              icon: const Icon(
                Icons.update_rounded,
                color: _purple,
                size: 18,
              ),
              label: const Text(
                'Check for Updates',
                style: TextStyle(
                  color: _purple,
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(
                  color: _purple,
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            width: double.infinity,
            child: OutlinedButton.icon(
              onPressed: () => _logout(context),
              icon: const Icon(
                Icons.logout_rounded,
                color: Color(0xFFFF5252),
                size: 18,
              ),
              label: const Text(
                'Logout',
                style: TextStyle(
                  color: Color(0xFFFF5252),
                  fontWeight: FontWeight.w600,
                  fontSize: 15,
                ),
              ),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 13),
                side: const BorderSide(
                  color: Color(0xFFFF5252),
                  width: 1.2,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
          const SizedBox(height: 14),
          Text(
            'v1.0.0',
            style: TextStyle(
              color: _text.withValues(alpha: 0.3),
              fontSize: 12,
              letterSpacing: 0.5,
            ),
          ),
        ],
      ),
    );
  }
}

class _ServiceCard extends StatelessWidget {
  final String title;
  final IconData icon;
  final Color cardColor;
  final bool isActive;
  final VoidCallback onTap;

  const _ServiceCard({
    required this.title,
    required this.icon,
    required this.cardColor,
    required this.isActive,
    required this.onTap,
  });

  static const Color _text = Color(0xFFEEEEF5);
  static const Color _green = Color(0xFF00C853);

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2A),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cardColor.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: cardColor.withValues(alpha: 0.1),
              blurRadius: 8,
              spreadRadius: 1,
            ),
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: cardColor.withValues(alpha: 0.15),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: cardColor, size: 36),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: _text,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
              decoration: BoxDecoration(
                color: isActive
                    ? _green.withValues(alpha: 0.2)
                    : Colors.grey.withValues(alpha: 0.2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                isActive ? '● LIVE' : 'Coming Soon',
                style: TextStyle(
                  color: isActive ? _green : Colors.grey,
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('title', title));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(ColorProperty('cardColor', cardColor));
    properties.add(DiagnosticsProperty<bool>('isActive', isActive));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
