// ================================================================
// EarningsHubScreen — Allin1 Super App
// Smart Earnings Hub - Phase 1.5 (Provider Architecture + Modular Widgets)
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../providers/task_provider.dart';
import '../../providers/wallet_provider.dart';
import '../../widgets/tasks/daily_streak_tracker.dart';
import '../../widgets/tasks/nj_coins_balance_card.dart';
import '../../widgets/tasks/task_list_item.dart';

class EarningsHubScreen extends StatelessWidget {
  const EarningsHubScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        ChangeNotifierProvider(
          create: (_) => TaskProvider()..fetchActiveTasks(),
        ),
        ChangeNotifierProvider(
          create: (_) => WalletProvider()..initialize('current_user_id'),
        ),
      ],
      child: const _EarningsHubContent(),
    );
  }
}

class _EarningsHubContent extends StatelessWidget {
  const _EarningsHubContent();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      body: SafeArea(
        child: CustomScrollView(
          slivers: [
            // App Bar
            SliverAppBar(
              floating: true,
              backgroundColor: const Color(0xFF12121E),
              title: Text(
                '💰 Smart Earnings Hub',
                style: GoogleFonts.outfit(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFFEEEEF5),
                ),
              ),
              actions: [
                IconButton(
                  icon:
                      const Icon(Icons.info_outline, color: Color(0xFF7777A0)),
                  onPressed: () => _showHowItWorks(context),
                ),
              ],
            ),

            // Content
            SliverToBoxAdapter(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // NJ Coins Balance Card (from Provider)
                  Consumer<WalletProvider>(
                    builder: (context, walletProvider, child) {
                      return NJCoinsBalanceCard(
                        balance: walletProvider.njCoinsBalance,
                        expiring: walletProvider.wallet.njCoinsExpiring,
                        pending: walletProvider.wallet.njCoinsPending,
                        onSpendTap: () => _onSpendTap(context),
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Free Ride Progress Bar
                  Consumer<WalletProvider>(
                    builder: (context, walletProvider, child) {
                      return _buildProgressBanner(
                        walletProvider.njCoinsBalance,
                        walletProvider.levelProgress,
                        walletProvider.levelGoal,
                      );
                    },
                  ),
                  const SizedBox(height: 16),

                  // Daily Streak Tracker (from Provider)
                  Consumer<WalletProvider>(
                    builder: (context, walletProvider, child) {
                      return DailyStreakTracker(
                        currentStreak: walletProvider.currentStreak,
                        longestStreak: walletProvider.longestStreak,
                      );
                    },
                  ),
                  const SizedBox(height: 20),

                  // Task Categories (from Provider)
                  _buildCategoryFilter(context),
                  const SizedBox(height: 16),
                ],
              ),
            ),

            // Task List (Sliver)
            Consumer<TaskProvider>(
              builder: (context, taskProvider, child) {
                if (taskProvider.isLoading) {
                  return const SliverToBoxAdapter(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.all(32),
                        child:
                            CircularProgressIndicator(color: Color(0xFFFFBB00)),
                      ),
                    ),
                  );
                }

                if (taskProvider.error != null) {
                  return SliverToBoxAdapter(
                    child: _buildErrorState(
                      taskProvider.error!,
                      () => taskProvider.refresh(),
                    ),
                  );
                }

                return _buildTaskList(context, taskProvider);
              },
            ),

            // Bottom Spacer
            const SliverToBoxAdapter(
              child: SizedBox(height: 80),
            ),
          ],
        ),
      ),
    );
  }

  // ── Free Ride Progress Banner ───────────────────────────────
  Widget _buildProgressBanner(int balance, int progress, int goal) {
    const rideCost = 100;
    final percent = (progress / goal * 100).clamp(0.0, 100.0);
    final remaining = rideCost - balance;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            const Color(0xFF00C853).withValues(alpha: 0.15),
            const Color(0xFF0A1E0E),
          ],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFF00C853).withValues(alpha: 0.3),
          width: 1.5,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Text('🏍️', style: TextStyle(fontSize: 20)),
              const SizedBox(width: 8),
              const Text(
                'Free Bike Ride Goal',
                style: TextStyle(
                  fontSize: 14,
                  color: Color(0xFFEEEEF5),
                  fontWeight: FontWeight.w700,
                ),
              ),
              const Spacer(),
              Text(
                '₹$rideCost',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  color: const Color(0xFF00C853),
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: LinearProgressIndicator(
              value: percent / 100,
              backgroundColor: const Color(0xFF00C853).withValues(alpha: 0.2),
              valueColor:
                  const AlwaysStoppedAnimation<Color>(Color(0xFF00C853)),
              minHeight: 8,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                '₹$balance / ₹$rideCost',
                style: const TextStyle(
                  fontSize: 11,
                  color: Color(0xFF7777A0),
                ),
              ),
              if (remaining > 0)
                Text(
                  '🎯 Earn ₹$remaining more → Get Free Ride!',
                  style: const TextStyle(
                    fontSize: 11,
                    color: Color(0xFF00C853),
                    fontWeight: FontWeight.w600,
                  ),
                )
              else
                const Text(
                  '✅ Ready to redeem!',
                  style: TextStyle(
                    fontSize: 11,
                    color: Color(0xFF00C853),
                    fontWeight: FontWeight.w600,
                  ),
                ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Category Filter ─────────────────────────────────────────
  Widget _buildCategoryFilter(BuildContext context) {
    final categories = [
      {'name': 'All', 'icon': '🎯'},
      {'name': 'Quick', 'icon': '⚡'},
      {'name': 'Food', 'icon': '🍔'},
      {'name': 'Finance', 'icon': '💰'},
      {'name': 'Flash', 'icon': '⏰'},
    ];

    return SizedBox(
      height: 50,
      child: Consumer<TaskProvider>(
        builder: (context, taskProvider, child) {
          return ListView.builder(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            itemCount: categories.length,
            itemBuilder: (context, index) {
              final category = categories[index];
              final isSelected = category['name']!.toLowerCase() ==
                  taskProvider.selectedCategory;

              return Container(
                margin: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        category['icon']!,
                        style: const TextStyle(fontSize: 14),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        category['name']!,
                        style: const TextStyle(fontSize: 12),
                      ),
                    ],
                  ),
                  selected: isSelected,
                  selectedColor: const Color(0xFFFFBB00).withValues(alpha: 0.2),
                  checkmarkColor: const Color(0xFFFFBB00),
                  backgroundColor: const Color(0xFF1A1A2A),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(20),
                    side: BorderSide(
                      color: isSelected
                          ? const Color(0xFFFFBB00)
                          : const Color(0xFF7777A0),
                    ),
                  ),
                  onSelected: (selected) {
                    taskProvider.setCategory(category['name']!.toLowerCase());
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }

  // ── Task List ───────────────────────────────────────────────
  Widget _buildTaskList(BuildContext context, TaskProvider taskProvider) {
    final tasks = taskProvider.filteredTasks;

    if (tasks.isEmpty) {
      return SliverToBoxAdapter(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Center(
            child: Column(
              children: [
                const Text('📭', style: TextStyle(fontSize: 48)),
                const SizedBox(height: 16),
                Text(
                  'No tasks available',
                  style: GoogleFonts.outfit(
                    fontSize: 16,
                    color: const Color(0xFFEEEEF5),
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Check back later for new opportunities!',
                  style: TextStyle(
                    fontSize: 12,
                    color: Color(0xFF7777A0),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return SliverPadding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      sliver: SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final task = tasks[index];
            return TaskListItem(
              task: task,
            );
          },
          childCount: tasks.length,
        ),
      ),
    );
  }

  // ── Error State ─────────────────────────────────────────────
  Widget _buildErrorState(String error, VoidCallback onRetry) {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Center(
        child: Column(
          children: [
            const Text('❌', style: TextStyle(fontSize: 48)),
            const SizedBox(height: 16),
            Text(
              'Failed to load tasks',
              style: GoogleFonts.outfit(
                fontSize: 16,
                color: const Color(0xFFEEEEF5),
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              error,
              style: const TextStyle(
                fontSize: 12,
                color: Color(0xFF7777A0),
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: onRetry,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFFFBB00),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }

  // ── Event Handlers ──────────────────────────────────────────
  void _onSpendTap(BuildContext context) {
    // Phase 2: Navigate to spend screen
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('🚧 Spend NJ Coins feature coming soon in Phase 2!'),
        backgroundColor: Color(0xFFFFBB00),
      ),
    );
  }

  // ── How It Works Dialog ─────────────────────────────────────
  void _showHowItWorks(BuildContext context) {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1A1A2A),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
        ),
        title: const Text(
          'How NJ Coins Work',
          style: TextStyle(
            color: Color(0xFFEEEEF5),
            fontWeight: FontWeight.w700,
          ),
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _HowItWorksStep(
              number: '1',
              title: 'Complete Tasks',
              description: 'Download apps, register, or make purchases',
            ),
            SizedBox(height: 12),
            _HowItWorksStep(
              number: '2',
              title: 'Earn NJ Coins',
              description: 'Get 40% of affiliate commission as NJ Coins',
            ),
            SizedBox(height: 12),
            _HowItWorksStep(
              number: '3',
              title: 'Spend in App',
              description: 'Use NJ Coins for Bike Taxi, Food, Grocery',
            ),
            SizedBox(height: 12),
            _HowItWorksStep(
              number: '4',
              title: 'Save Real Money',
              description: 'Every NJ Coin = ₹1 off your next order',
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text(
              'Close',
              style: TextStyle(color: Color(0xFF7777A0)),
            ),
          ),
        ],
      ),
    );
  }
}

// ── How It Works Step Widget ──────────────────────────────────
class _HowItWorksStep extends StatelessWidget {
  final String number;
  final String title;
  final String description;

  const _HowItWorksStep({
    required this.number,
    required this.title,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          width: 28,
          height: 28,
          decoration: BoxDecoration(
            color: const Color(0xFFFFBB00).withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(8),
          ),
          child: Center(
            child: Text(
              number,
              style: const TextStyle(
                color: Color(0xFFFFBB00),
                fontWeight: FontWeight.w800,
                fontSize: 14,
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
                title,
                style: const TextStyle(
                  color: Color(0xFFEEEEF5),
                  fontWeight: FontWeight.w600,
                  fontSize: 13,
                ),
              ),
              Text(
                description,
                style: const TextStyle(
                  color: Color(0xFF7777A0),
                  fontSize: 11,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('number', number));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('description', description));
  }
}
