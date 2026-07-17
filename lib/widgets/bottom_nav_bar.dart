// ================================================================
// Bottom Navigation Bar - Allin1 Super App
// ================================================================
// Cross-platform bottom navigation for mobile users.
// Provides quick access to main sections: Home, Orders, Cart, Profile
// ================================================================

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

const Color kBg = Color(0xFF08080F);
const Color kSurface = Color(0xFF111118);
const Color kCard = Color(0xFF1A1A26);
const Color kPurple = Color(0xFF7B6FE0);
const Color kPurple2 = Color(0xFF9B8FF0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

/// Main shell with bottom navigation for mobile
class MobileShell extends StatefulWidget {
  final int initialIndex;
  final String userType; // 'customer', 'rider', 'seller', 'admin'

  const MobileShell({
    required this.userType,
    super.key,
    this.initialIndex = 0,
  });

  @override
  State<MobileShell> createState() => _MobileShellState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('initialIndex', initialIndex))
      ..add(StringProperty('userType', userType));
  }
}

class _MobileShellState extends State<MobileShell> {
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
  }

  // Get navigation items based on user type
  List<_NavItem> _getNavItems() {
    switch (widget.userType) {
      case 'rider':
        return [
          _NavItem(
            icon: Icons.directions_bike,
            label: 'Rides',
            route: '/rider-portal',
          ),
          _NavItem(icon: Icons.wallet, label: 'Earnings', route: '/wallet'),
          _NavItem(
            icon: Icons.history,
            label: 'History',
            route: '/ride-history',
          ),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
      case 'seller':
        return [
          _NavItem(icon: Icons.store, label: 'Orders', route: '/seller-portal'),
          _NavItem(
            icon: Icons.inventory,
            label: 'Products',
            route: '/products',
          ),
          _NavItem(
            icon: Icons.analytics,
            label: 'Analytics',
            route: '/analytics',
          ),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
      case 'admin':
        return [
          _NavItem(
            icon: Icons.dashboard,
            label: 'Dashboard',
            route: '/admin-panel',
          ),
          _NavItem(icon: Icons.people, label: 'Users', route: '/admin/users'),
          _NavItem(icon: Icons.settings, label: 'Settings', route: '/settings'),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
      default: // customer
        return [
          _NavItem(icon: Icons.home, label: 'Home', route: '/dashboard'),
          _NavItem(icon: Icons.shopping_bag, label: 'Orders', route: '/orders'),
          _NavItem(icon: Icons.shopping_cart, label: 'Cart', route: '/cart'),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
    }
  }

  void _onItemTapped(int index) {
    if (index != _currentIndex) {
      setState(() => _currentIndex = index);
      final route = _getNavItems()[index].route;
      Navigator.pushReplacementNamed(context, route);
    }
  }

  @override
  Widget build(BuildContext context) {
    final navItems = _getNavItems();

    return Scaffold(
      body: Navigator(
        onGenerateRoute: (settings) {
          return MaterialPageRoute<void>(
            builder: (_) => _buildBody(),
            settings: settings,
          );
        },
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: const BoxDecoration(
          color: kSurface,
          border: Border(
            top: BorderSide(color: kBorder),
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceAround,
              children: List.generate(navItems.length, (index) {
                final isSelected = index == _currentIndex;
                final item = navItems[index];

                return _NavBarItem(
                  icon: item.icon,
                  label: item.label,
                  isSelected: isSelected,
                  onTap: () => _onItemTapped(index),
                );
              }),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    // This will be replaced by the actual screen content
    // when navigation happens
    return const SizedBox.shrink();
  }
}

class _NavItem {
  final IconData icon;
  final String label;
  final String route;

  _NavItem({
    required this.icon,
    required this.label,
    required this.route,
  });
}

class _NavBarItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;

  const _NavBarItem({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color:
              isSelected ? kPurple.withValues(alpha: 0.15) : Colors.transparent,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 24,
              color: isSelected ? kPurple : kMuted,
            ),
            const SizedBox(height: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: isSelected ? FontWeight.w600 : FontWeight.w400,
                color: isSelected ? kPurple : kMuted,
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
    properties
      ..add(DiagnosticsProperty<IconData>('icon', icon))
      ..add(StringProperty('label', label))
      ..add(DiagnosticsProperty<bool>('isSelected', isSelected))
      ..add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

/// Standalone bottom navigation bar widget for embedding in screens
class BottomNavBar extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;
  final String userType;

  const BottomNavBar({
    required this.currentIndex,
    required this.onTap,
    super.key,
    this.userType = 'customer',
  });

  @override
  Widget build(BuildContext context) {
    final navItems = _getNavItems();

    return DecoratedBox(
      decoration: const BoxDecoration(
        color: kSurface,
        border: Border(
          top: BorderSide(color: kBorder),
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(navItems.length, (index) {
              final isSelected = index == currentIndex;
              final item = navItems[index];

              return _NavBarItem(
                icon: item.icon,
                label: item.label,
                isSelected: isSelected,
                onTap: () => onTap(index),
              );
            }),
          ),
        ),
      ),
    );
  }

  List<_NavItem> _getNavItems() {
    switch (userType) {
      case 'rider':
        return [
          _NavItem(
            icon: Icons.directions_bike,
            label: 'Rides',
            route: '/rider-portal',
          ),
          _NavItem(icon: Icons.wallet, label: 'Earnings', route: '/wallet'),
          _NavItem(
            icon: Icons.history,
            label: 'History',
            route: '/ride-history',
          ),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
      case 'seller':
        return [
          _NavItem(icon: Icons.store, label: 'Orders', route: '/seller-portal'),
          _NavItem(
            icon: Icons.inventory,
            label: 'Products',
            route: '/products',
          ),
          _NavItem(
            icon: Icons.analytics,
            label: 'Analytics',
            route: '/analytics',
          ),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
      case 'admin':
        return [
          _NavItem(
            icon: Icons.dashboard,
            label: 'Dashboard',
            route: '/admin-panel',
          ),
          _NavItem(icon: Icons.people, label: 'Users', route: '/admin/users'),
          _NavItem(icon: Icons.settings, label: 'Settings', route: '/settings'),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
      default:
        return [
          _NavItem(icon: Icons.home, label: 'Home', route: '/dashboard'),
          _NavItem(icon: Icons.shopping_bag, label: 'Orders', route: '/orders'),
          _NavItem(icon: Icons.shopping_cart, label: 'Cart', route: '/cart'),
          _NavItem(icon: Icons.person, label: 'Profile', route: '/profile'),
        ];
    }
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(IntProperty('currentIndex', currentIndex))
      ..add(ObjectFlagProperty<void Function(int)>.has('onTap', onTap))
      ..add(StringProperty('userType', userType));
  }
}
