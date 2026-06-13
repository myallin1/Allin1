// ================================================================
// CategoryScreen — Allin1 Super App
// Universal category screen with dynamic UI adaptation
// ================================================================

import 'package:flutter/foundation.dart' hide Category;
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../services/category_gateway_service.dart';
import '../widgets/empty_state.dart';
import '../widgets/seller_card.dart';
import 'seller_detail_screen.dart';

class CategoryScreen extends StatefulWidget {
  final Category category;
  final List<Map<String, dynamic>> sellers;

  const CategoryScreen({
    required this.category,
    required this.sellers,
    super.key,
  });

  @override
  State<CategoryScreen> createState() => _CategoryScreenState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(EnumProperty<Category>('category', category));
    properties.add(IterableProperty<Map<String, dynamic>>('sellers', sellers));
  }
}

class _CategoryScreenState extends State<CategoryScreen> {
  late List<Map<String, dynamic>> _sellers;
  bool _isRefreshing = false;

  @override
  void initState() {
    super.initState();
    _sellers = widget.sellers;
  }

  // ── Category Configuration ───────────────────────────────────
  _CategoryConfig get _config {
    switch (widget.category) {
      case Category.food:
        return const _CategoryConfig(
          title: 'Food Delivery',
          subtitle: 'Hot meals from local restaurants',
          emoji: '🍔',
          primaryColor: Color(0xFFFF5252),
          bgColor: Color(0xFF1E0E0E),
          emptyMessage: 'No restaurants in your area yet!',
          emptySubmessage: "We're bringing Food Delivery to Erode soon!",
        );
      case Category.grocery:
        return const _CategoryConfig(
          title: 'Fresh Groceries',
          subtitle: 'Daily essentials delivered',
          emoji: '🛒',
          primaryColor: Color(0xFF00C853),
          bgColor: Color(0xFF0A1E0E),
          emptyMessage: 'No grocery stores nearby!',
          emptySubmessage: 'Fresh Groceries coming to your area soon!',
        );
      case Category.tech:
        return const _CategoryConfig(
          title: 'Tech Store',
          subtitle: 'NJ TECH gadgets & accessories',
          emoji: '📱',
          primaryColor: Color(0xFF6C63FF),
          bgColor: Color(0xFF10102A),
          emptyMessage: 'Tech Store is under construction!',
          emptySubmessage: 'Browse NJ TECH products coming soon!',
        );
      case Category.pharmacy:
        return const _CategoryConfig(
          title: 'Pharmacy',
          subtitle: 'Medicines & healthcare products',
          emoji: '💊',
          primaryColor: Color(0xFFFF6B35),
          bgColor: Color(0xFF1E1008),
          emptyMessage: 'Pharmacy services unavailable!',
          emptySubmessage: 'Medicine delivery coming to Erode soon!',
        );
      case Category.bikeTaxi:
        return const _CategoryConfig(
          title: 'Bike Taxi',
          subtitle: 'Fast rides in Erode',
          emoji: '🏍️',
          primaryColor: Color(0xFFFFBB00),
          bgColor: Color(0xFF1E1A08),
          emptyMessage: 'No bike taxi captains available!',
          emptySubmessage: 'More captains joining soon!',
        );
      case Category.carTaxi:
        return const _CategoryConfig(
          title: 'Car Taxi',
          subtitle: 'Comfortable rides for groups',
          emoji: '🚗',
          primaryColor: Color(0xFF00BCD4),
          bgColor: Color(0xFF081A1E),
          emptyMessage: 'Car Taxi not available yet!',
          emptySubmessage: 'Book comfortable car rides soon!',
        );
    }
  }

  // ── Pull-to-Refresh Handler ──────────────────────────────────
  Future<void> _handleRefresh() async {
    setState(() => _isRefreshing = true);

    try {
      // Force refresh via CategoryGatewayService
      final freshSellers =
          await CategoryGatewayService().forceRefreshCategory(widget.category);

      if (mounted) {
        setState(() {
          _sellers = freshSellers;
          _isRefreshing = false;
        });

        // Show success feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('✅ Updated ${_sellers.length} sellers'),
            backgroundColor: _config.primaryColor,
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isRefreshing = false);

        // Show error feedback
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('❌ Failed to refresh: ${e.toString()}'),
            backgroundColor: const Color(0xFFFF5252),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: _buildAppBar(),
      body: RefreshIndicator(
        onRefresh: _handleRefresh,
        color: _config.primaryColor,
        backgroundColor: _config.bgColor,
        child: _sellers.isEmpty
            ? EmptyState(category: widget.category)
            : ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: _sellers.length,
                itemBuilder: (context, i) {
                  final seller = _sellers[i];
                  return SellerCard(
                    seller: seller,
                    category: widget.category,
                    onTap: () => _navigateToSellerDetail(seller),
                  );
                },
              ),
      ),
    );
  }

  // ── Dynamic AppBar ───────────────────────────────────────────
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: _config.bgColor,
      elevation: 0,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back, color: Color(0xFFEEEEF5)),
        onPressed: () => Navigator.pop(context),
      ),
      title: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            '${_config.emoji} ${_config.title}',
            style: GoogleFonts.outfit(
              fontSize: 18,
              fontWeight: FontWeight.w800,
              color: const Color(0xFFEEEEF5),
            ),
          ),
          Text(
            _config.subtitle,
            style: GoogleFonts.outfit(
              fontSize: 12,
              color: Colors.white70,
            ),
          ),
        ],
      ),
    );
  }

  // ── Navigate to Seller Detail ───────────────────────────────
  void _navigateToSellerDetail(Map<String, dynamic> seller) {
    Navigator.push(
      context,
      MaterialPageRoute<void>(
        builder: (_) => SellerDetailScreen(
          seller: seller,
          category: widget.category,
        ),
      ),
    );
  }
}

// ── Category Configuration Model ───────────────────────────────
class _CategoryConfig {
  final String title;
  final String subtitle;
  final String emoji;
  final Color primaryColor;
  final Color bgColor;
  final String emptyMessage;
  final String emptySubmessage;

  const _CategoryConfig({
    required this.title,
    required this.subtitle,
    required this.emoji,
    required this.primaryColor,
    required this.bgColor,
    required this.emptyMessage,
    required this.emptySubmessage,
  });
}
