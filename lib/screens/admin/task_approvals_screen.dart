// ================================================================
// TaskApprovalsScreen — Admin Task Approval & Hero Report
// Allin1 Super App v1.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../services/app_palette.dart';
import '../../services/firestore_usage_tracking.dart';

class TaskApprovalsScreen extends StatefulWidget {
  const TaskApprovalsScreen({super.key});

  @override
  State<TaskApprovalsScreen> createState() => _TaskApprovalsScreenState();
}

class _TaskApprovalsScreenState extends State<TaskApprovalsScreen> {
  // ── Theme ────────────────────────────────────────────────────
// Theme colors are now sourced from shared app_palette.dart via syncAppPalette(context);
  static const Color _border = Color(0x1AFFFFFF);

  int _selectedTab = 0;

  @override
  Widget build(BuildContext context) {
    syncAppPalette(context);
    return Scaffold(
      backgroundColor: kBg,
      appBar: _buildAppBar(),
      body: _selectedTab == 0 ? _buildCustomerTasks() : _buildHeroReport(),
    );
  }

  // ── App Bar ─────────────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: kSurface,
      title: Row(
        children: [
          const Text('📋', style: TextStyle(fontSize: 18)),
          const SizedBox(width: 8),
          Text(
            'Task Approvals',
            style: GoogleFonts.outfit(
              color: kText,
              fontWeight: FontWeight.w800,
              fontSize: 18, // FIX (UI standardization, Aug 11 2026): app-bar titles are 18sp app-wide
            ),
          ),
        ],
      ),
      bottom: PreferredSize(
        preferredSize: const Size.fromHeight(50),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            children: [
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = 0),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _selectedTab == 0
                          ? kPink.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '🛒 Customer Tasks',
                        style: TextStyle(
                          color: _selectedTab == 0 ? kPink : kMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _selectedTab = 1),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    decoration: BoxDecoration(
                      color: _selectedTab == 1
                          ? kGreen.withValues(alpha: 0.2)
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(
                      child: Text(
                        '🏍️ Hero Report',
                        style: TextStyle(
                          color: _selectedTab == 1 ? kGreen : kMuted,
                          fontWeight: FontWeight.w700,
                          fontSize: 13,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================================================
  // TAB 1: CUSTOMER TASK APPROVALS
  // ================================================================
  Widget _buildCustomerTasks() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('task_completions')
          .where('status', isEqualTo: 'pending')
          .orderBy('submittedAt', descending: true)
          .trackedSnapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: kPink),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        if (docs.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('✅', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'No pending tasks!',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: kText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'All caught up. Great job!',
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          itemBuilder: (context, i) {
            final doc = docs[i];
            final data = doc.data()! as Map<String, dynamic>;
            final userId = data['userId'] as String? ?? '';
            final userName = data['userName'] as String? ?? 'Unknown';
            final userEmail = data['userEmail'] as String? ?? '';
            final adTitle = data['adTitle'] as String? ?? 'Task';
            final coinsReward = data['coinsReward'] as int? ?? 0;
            final submittedAt = data['submittedAt'] as Timestamp?;

            final time = submittedAt != null
                ? _formatTime(submittedAt.toDate())
                : 'Unknown';

            return Container(
              margin: const EdgeInsets.only(bottom: 12),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: kCard,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: kGold.withValues(alpha: 0.3)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // User info
                  Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: kPink.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Center(
                          child: Text(
                            userName.isNotEmpty
                                ? userName[0].toUpperCase()
                                : 'U',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w800,
                              color: kPink,
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
                              userName,
                              style: TextStyle(
                                fontSize: 14,
                                color: kText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            Text(
                              userEmail,
                              style: TextStyle(
                                fontSize: 11,
                                color: kMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),

                  // Task info
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: kSurface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: kBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                adTitle,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: kText,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              const SizedBox(height: 4),
                              Text(
                                '🪙 $coinsReward coins',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: kGold,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ],
                          ),
                        ),
                        Text(
                          time,
                          style: TextStyle(
                            fontSize: 10,
                            color: kMuted,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Action buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kGreen,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon:
                              const Icon(Icons.check_circle_outline, size: 18),
                          label: const Text(
                            'Approve',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () =>
                              _approveTask(doc.id, userId, coinsReward),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ElevatedButton.icon(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kRed,
                            foregroundColor: Colors.white,
                            minimumSize: const Size(0, 42),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(8),
                            ),
                          ),
                          icon: const Icon(Icons.cancel_outlined, size: 18),
                          label: const Text(
                            'Reject',
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          onPressed: () =>
                              _rejectTask(doc.id, userId, coinsReward),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ── Approve Task ────────────────────────────────────────────
  Future<void> _approveTask(
    String docId,
    String userId,
    int coinsReward,
  ) async {
    try {
      final db = FirebaseFirestore.instance;
      
      await db.runTransaction((transaction) async {
        final taskRef = db.collection('task_completions').doc(docId);
        final taskSnap = await transaction.get(taskRef);
        
        if (!taskSnap.exists || taskSnap.data()?['status'] != 'pending') {
          throw Exception('Task already processed');
        }

        final userRef = db.collection('users').doc(userId);
        final userSnap = await transaction.get(userRef);
        
        final currentPending =
            (userSnap.data()?['pending_coins'] as num? ?? 0).toInt();

        if (currentPending < coinsReward) {
          throw Exception('Pending coins insufficient!');
        }

        // Safe to proceed - move from pending to verified
        transaction.update(userRef, {
          'pending_coins': FieldValue.increment(-coinsReward),
          'verified_coins': FieldValue.increment(coinsReward),
        });

        // Update task status
        transaction.update(taskRef, {
          'status': 'approved',
          'approvedAt': FieldValue.serverTimestamp(),
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Approved! $coinsReward coins moved!'),
            backgroundColor: const Color(0xFF00C853),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    }
  }

  // ── Reject Task ─────────────────────────────────────────────
  Future<void> _rejectTask(
    String docId,
    String userId,
    int coinsReward,
  ) async {
    try {
      final db = FirebaseFirestore.instance;
      
      await db.runTransaction((transaction) async {
        final taskRef = db.collection('task_completions').doc(docId);
        final taskSnap = await transaction.get(taskRef);
        
        if (!taskSnap.exists || taskSnap.data()?['status'] != 'pending') {
          throw Exception('Task already processed');
        }

        final userRef = db.collection('users').doc(userId);

        transaction.update(taskRef, {
          'status': 'rejected',
          'rejectedAt': FieldValue.serverTimestamp(),
        });

        // Refund pending coins (remove what was added on submission)
        transaction.update(userRef, {
          'pending_coins': FieldValue.increment(-coinsReward),
        });
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text('❌ Task rejected. Coins refunded.'),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Error: $e'),
            backgroundColor: kRed,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // ================================================================
  // TAB 2: HERO DAILY REPORT
  // ================================================================
  Widget _buildHeroReport() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('rides')
          .orderBy('createdAt', descending: true)
          .trackedSnapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return Center(
            child: CircularProgressIndicator(color: kGreen),
          );
        }

        final docs = snapshot.data?.docs ?? [];
        final today = DateTime.now();
        final startOfDay = DateTime(today.year, today.month, today.day);

        // Group rides by captainId
        final Map<String, List<Map<String, dynamic>>> heroRides = {};
        for (final doc in docs) {
          final data = doc.data()! as Map<String, dynamic>;
          final captainId = data['captainId'] as String?;
          final createdAt = data['createdAt'] as Timestamp?;

          if (captainId != null &&
              createdAt != null &&
              createdAt.toDate().isAfter(startOfDay)) {
            if (!heroRides.containsKey(captainId)) {
              heroRides[captainId] = [];
            }
            heroRides[captainId]!.add({
              'fare': data['fare'] as num? ?? 0,
              'status': data['status'] as String? ?? '',
            });
          }
        }

        if (heroRides.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Text('🏍️', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'No rides today',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: kText,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Heroes will appear here once they start riding',
                  style: TextStyle(fontSize: 12, color: kMuted),
                ),
              ],
            ),
          );
        }

        return ListView.builder(
          padding: const EdgeInsets.all(16),
          itemCount: heroRides.length,
          itemBuilder: (context, i) {
            final captainId = heroRides.keys.elementAt(i);
            final rides = heroRides[captainId]!;

            final totalRides = rides.length;
            final totalEarnings = rides.fold<num>(
              0,
              (sum, ride) =>
                  sum + (ride['fare'] as num),
            );

            return FutureBuilder<DocumentSnapshot>(
              future: FirebaseFirestore.instance
                  .collection('captains')
                  .doc(captainId)
                  .get(),
              builder: (context, captainSnap) {
                final captainData =
                    captainSnap.data?.data() as Map<String, dynamic>?;
                final captainName =
                    captainData?['captainName'] as String? ?? 'Hero';
                final captainEmail = captainData?['email'] as String? ?? '';
                // FIX: this used to read `captainData['status']` from
                // the Firestore `captains` doc — a field the hero app no
                // longer writes at all (see hero_home_screen.dart's
                // WhatsApp-model presence migration), so this card would
                // always show "OFFLINE" regardless of reality. Switched
                // to the same RTDB online_heroes/{uid} presence node
                // every other admin screen uses, trusting node existence
                // alone (CTO architecture decision — presence is
                // governed entirely by onDisconnect() + the
                // `.info/connected` reconnect watcher, no staleness
                // cross-check needed).
                return StreamBuilder<DatabaseEvent>(
                  stream: FirebaseDatabase.instance
                      .ref('online_heroes/$captainId')
                      .onValue,
                  builder: (context, presenceSnap) {
                    final rawPresence = presenceSnap.data?.snapshot.value;
                    final isOnline = rawPresence is Map;

                    return Container(
                  margin: const EdgeInsets.only(bottom: 12),
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: kCard,
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: isOnline ? kGreen.withValues(alpha: 0.3) : kBorder,
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Hero info
                      Row(
                        children: [
                          Container(
                            width: 40,
                            height: 40,
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? kGreen.withValues(alpha: 0.15)
                                  : kMuted.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Center(
                              child: Text(
                                captainName.isNotEmpty
                                    ? captainName[0].toUpperCase()
                                    : 'H',
                                style: TextStyle(
                                  fontSize: 18,
                                  fontWeight: FontWeight.w800,
                                  color: isOnline ? kGreen : kMuted,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Row(
                                  children: [
                                    Text(
                                      captainName,
                                      style: TextStyle(
                                        fontSize: 14,
                                        color: kText,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Container(
                                      width: 8,
                                      height: 8,
                                      decoration: BoxDecoration(
                                        color: isOnline ? kGreen : kMuted,
                                        shape: BoxShape.circle,
                                      ),
                                    ),
                                  ],
                                ),
                                Text(
                                  captainEmail,
                                  style: TextStyle(
                                    fontSize: 10,
                                    color: kMuted,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 4,
                            ),
                            decoration: BoxDecoration(
                              color: isOnline
                                  ? kGreen.withValues(alpha: 0.15)
                                  : kMuted.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              isOnline ? '🟢 ONLINE' : '⚫ OFFLINE',
                              style: TextStyle(
                                fontSize: 9,
                                fontWeight: FontWeight.w800,
                                color: isOnline ? kGreen : kMuted,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),

                      // Stats
                      Row(
                        children: [
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kSurface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _border),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '🏍️ $totalRides',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kGreen,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Rides Today',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: kMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Container(
                              padding: const EdgeInsets.all(10),
                              decoration: BoxDecoration(
                                color: kSurface,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: _border),
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    '₹${totalEarnings.toInt()}',
                                    style: TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.w800,
                                      color: kGold,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Earnings Today',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: kMuted,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                    );
                  },
                );
              },
            );
          },
        );
      },
    );
  }

  // ── Helper: Format time ─────────────────────────────────────
  String _formatTime(DateTime dt) {
    final now = DateTime.now();
    final diff = now.difference(dt);

    if (diff.inMinutes < 1) {
      return 'Just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${dt.day}/${dt.month} ${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
    }
  }
}
