// ================================================================
// ApprovedHeroesScreen — Admin Panel
// View all approved heroes (captains with status == 'approved')
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/hero_service_access.dart';
import '../../widgets/admin/hero_service_access_sheet.dart';
import '../../config/city_config.dart';
import 'package:url_launcher/url_launcher.dart';

import 'admin_hero_details_screen.dart';
import '../../services/firestore_usage_tracking.dart';

// ── Theme (matches admin dashboard) ────────────────────────────
const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _green = Color(0xFF00C853);
const Color _gold = Color(0xFFFFBB00);
const Color _red = Color(0xFFFF5252);
const Color _purple = Color(0xFF6C63FF);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class ApprovedHeroesScreen extends StatefulWidget {
  const ApprovedHeroesScreen({super.key});

  @override
  State<ApprovedHeroesScreen> createState() => _ApprovedHeroesScreenState();
}

class _ApprovedHeroesScreenState extends State<ApprovedHeroesScreen> {
  String _searchQuery = '';
  final TextEditingController _searchController = TextEditingController();

  List<QueryDocumentSnapshot> _sortByTimestampDesc(
    Iterable<QueryDocumentSnapshot> docs,
    String field,
  ) {
    final sorted = docs.toList();
    sorted.sort((a, b) {
      final aData = a.data()! as Map<String, dynamic>;
      final bData = b.data()! as Map<String, dynamic>;
      final aTs = aData[field] as Timestamp?;
      final bTs = bData[field] as Timestamp?;
      final aMs = aTs?.millisecondsSinceEpoch ?? 0;
      final bMs = bTs?.millisecondsSinceEpoch ?? 0;
      return bMs.compareTo(aMs);
    });
    return sorted;
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            const Text('🦸', style: TextStyle(fontSize: 18)),
            const SizedBox(width: 8),
            Text(
              'Approved Heroes',
              style: GoogleFonts.outfit(
                color: _text,
                fontWeight: FontWeight.w800,
                fontSize: 18, // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
              ),
            ),
          ],
        ),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1),
          child: Container(height: 1, color: _border),
        ),
      ),
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.all(16),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: _text),
              decoration: InputDecoration(
                hintText: '🔍 Search by name, phone, or vehicle no...',
                hintStyle: const TextStyle(color: _muted, fontSize: 13),
                filled: true,
                fillColor: _card,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _border),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(14),
                  borderSide: const BorderSide(color: _gold),
                ),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: _muted),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
              ),
              onChanged: (value) => setState(() => _searchQuery = value.trim().toLowerCase()),
            ),
          ),
          // Hero list
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: FirebaseFirestore.instance
                  .collection('heroes')
                  .where('approvalStatus', isEqualTo: 'approved')
                  .trackedSnapshots(),
              builder: (context, snap) {
                if (snap.connectionState == ConnectionState.waiting) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(40),
                      child: CircularProgressIndicator(
                        color: _gold,
                        strokeWidth: 2,
                      ),
                    ),
                  );
                }
                if (snap.hasError) {
                  return Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        'Error loading approved heroes: ${snap.error}',
                        style: const TextStyle(color: _red, fontSize: 13),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  );
                }

                final docs = _sortByTimestampDesc(
                  snap.data?.docs ?? const [],
                  'approvedAt',
                );

                // Apply client-side search filter
                final filtered = docs.where((doc) {
                  if (_searchQuery.isEmpty) return true;
                  final data = doc.data()! as Map<String, dynamic>;
                  final name = (data['captainName'] as String? ?? data['name'] as String? ?? '').toLowerCase();
                  final phone = (data['phone'] as String? ?? '').toLowerCase();
                  final vehicle = (data['vehicleNumber'] as String? ?? '').toLowerCase();
                  return name.contains(_searchQuery) ||
                      phone.contains(_searchQuery) ||
                      vehicle.contains(_searchQuery);
                }).toList();

                if (filtered.isEmpty) {
                  return Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text('📋', style: TextStyle(fontSize: 56)),
                        const SizedBox(height: 16),
                        Text(
                          _searchQuery.isEmpty
                              ? 'No approved heroes yet'
                              : 'No heroes match "$_searchQuery"',
                          style: GoogleFonts.outfit(
                            fontSize: 16,
                            fontWeight: FontWeight.w600,
                            color: _text,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          _searchQuery.isEmpty
                              ? 'Approved heroes will appear here'
                              : 'Try a different search term',
                          style: GoogleFonts.notoSansTamil(
                            fontSize: 12,
                            color: _muted,
                          ),
                        ),
                      ],
                    ),
                  );
                }

                // Summary count
                return Column(
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Row(
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: _green,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            '${filtered.length} approved hero${filtered.length == 1 ? '' : 's'}',
                            style: GoogleFonts.outfit(
                              fontSize: 13,
                              color: _muted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (_searchQuery.isNotEmpty) ...[
                            const SizedBox(width: 8),
                            Text(
                              '(filtered from ${docs.length})',
                              style: const TextStyle(fontSize: 11, color: _muted),
                            ),
                          ],
                        ],
                      ),
                    ),
                    const SizedBox(height: 12),
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: filtered.length,
                        itemBuilder: (context, i) {
                          final doc = filtered[i];
                          final data = doc.data()! as Map<String, dynamic>;
                          return _ApprovedHeroCard(
                            uid: doc.id,
                            data: data,
                            onView: () => _showDetailDialog(doc.id, data),
                          );
                        },
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  // ── Mirror Navigation (T3) ─────────────────────────────────────
  // Opens the full verification style detail screen for approved heroes.
  void _showDetailDialog(String uid, Map<String, dynamic> data) {
    Navigator.push<void>(
      context,
      MaterialPageRoute<void>(
        builder: (_) => AdminHeroDetailsScreen(
          uid: uid,
          data: data,
          getCityLabel: cityLabelFor,
          onCall: () async {
            final phone = data['phone'] as String? ?? '';
            if (phone.isNotEmpty) {
              final uri = Uri.parse('tel:$phone');
              if (await canLaunchUrl(uri)) {
                await launchUrl(uri);
              }
            }
          },
          onApprove: () {},
          onReject: () {},
        ),
      ),
    );
  }
}

// ── Approved Hero Card ───────────────────────────────────────────
class _ApprovedHeroCard extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final VoidCallback onView;
  const _ApprovedHeroCard({
    required this.uid,
    required this.data,
    required this.onView,
  });

  @override
  Widget build(BuildContext context) {
    final approvedAt = data['approvedAt'] as Timestamp?;

    // FIX (WhatsApp-model presence migration, CTO mandate): this used to
    // read data['status'] from the Firestore heroes doc — a field that's
    // no longer written at all (see hero_home_screen.dart's
    // _syncOnlineStatus and services/auth_service.dart's
    // completeProfileSetup). RTDB's online_heroes/{uid} node, backed by
    // onDisconnect(), is now the ONLY source of truth for whether this
    // hero is currently online, so this card now listens to it live
    // instead of trusting a Firestore field that would otherwise sit
    // stale forever.
    return StreamBuilder<DatabaseEvent>(
      stream: FirebaseDatabase.instance.ref('online_heroes/$uid').onValue,
      builder: (context, rtdbSnapshot) {
        final rawRtdbValue = rtdbSnapshot.data?.snapshot.value;
        final rtdbMap = rawRtdbValue is Map ? rawRtdbValue : null;
        // Node existence = online (CTO architecture decision): presence
        // is governed entirely by onDisconnect() + the `.info/connected`
        // reconnect watcher in hero_home_screen.dart, no staleness
        // cross-check needed here.
        final isOnline = rtdbMap != null;
        final isActiveRide = rtdbMap != null &&
            (rtdbMap['isAvailable'] as bool? ?? true) == false;
        return _buildCard(context, isOnline: isOnline, isActiveRide: isActiveRide, approvedAt: approvedAt);
      },
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required bool isOnline,
    required bool isActiveRide,
    required Timestamp? approvedAt,
  }) {
    // How many work types an admin has switched off for this hero.
    // Zero for every hero nobody has touched — see hero_service_access.dart.
    final restrictedCount = deniedServices(data).length;
    final name = data['captainName'] as String? ?? data['name'] as String? ?? 'Unknown';
    final phone = data['phone'] as String? ?? '';
    final vehicleNumber = data['vehicleNumber'] as String? ?? '';
    final vehicleType = data['vehicleType'] as String? ?? '';
    final email = data['email'] as String? ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isOnline
              ? _green.withValues(alpha: 0.4)
              : const Color(0x33FFBB00),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: isOnline
                        ? [_green, const Color(0xFF00E676)]
                        : [_gold, const Color(0xFFFF6B35)],
                  ),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Center(
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: const TextStyle(
                      fontSize: 18,
                      color: Colors.white,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      name,
                      style: const TextStyle(
                        fontSize: 15,
                        color: _text,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    if (phone.isNotEmpty)
                      Text(
                        phone,
                        style: const TextStyle(fontSize: 11, color: _muted),
                      ),
                  ],
                ),
              ),
              // Status badge
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isOnline
                      ? _green.withValues(alpha: 0.15)
                      : _gold.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  isActiveRide
                      ? '🚀 ON RIDE'
                      : isOnline
                          ? '🟢 ONLINE'
                          : '✅ APPROVED',
                  style: TextStyle(
                    fontSize: 9,
                    fontWeight: FontWeight.w800,
                    color: isOnline ? _green : _gold,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Vehicle info
          Row(
            children: [
              const Icon(Icons.directions_bike, size: 14, color: _purple),
              const SizedBox(width: 6),
              Text(
                vehicleType.isNotEmpty ? vehicleType : 'N/A',
                style: const TextStyle(fontSize: 11, color: _muted),
              ),
              const SizedBox(width: 12),
              const Icon(Icons.pin, size: 14, color: _muted),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  vehicleNumber.isNotEmpty ? vehicleNumber : 'N/A',
                  style: const TextStyle(fontSize: 11, color: _muted),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          if (email.isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              email,
              style: const TextStyle(fontSize: 10, color: _muted),
              overflow: TextOverflow.ellipsis,
            ),
          ],
          if (approvedAt != null) ...[
            const SizedBox(height: 4),
            Text(
              'Approved: ${approvedAt.toDate().day}/${approvedAt.toDate().month}/${approvedAt.toDate().year}',
              style: const TextStyle(fontSize: 10, color: _muted),
            ),
          ],
          const SizedBox(height: 14),
          // Action buttons
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: onView,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _muted,
                    side: const BorderSide(color: _border),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  child: const Text(
                    'View Details',
                    style:
                        TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              // NEW (Aug 17 2026 — per-hero work permissions). Sits on
              // the APPROVED list on purpose: this is post-registration
              // fleet management ("heros ah handle panna admin ku innum
              // freedoms"), not part of the approval decision itself.
              // The label reports the current state so an admin can see
              // at a glance which heroes are restricted, without opening
              // each one.
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => showHeroServiceAccessSheet(
                    context,
                    uid: uid,
                    heroData: data,
                  ),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: restrictedCount == 0 ? _muted : _red,
                    side: BorderSide(
                      color: restrictedCount == 0 ? _border : _red,
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                  ),
                  icon: Icon(
                    restrictedCount == 0
                        ? Icons.tune_rounded
                        : Icons.block_rounded,
                    size: 14,
                  ),
                  label: Text(
                    restrictedCount == 0
                        ? 'Services'
                        : '$restrictedCount off',
                    style: const TextStyle(
                        fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('uid', uid));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onView', onView));
  }
}
