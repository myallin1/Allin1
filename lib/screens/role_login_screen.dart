import 'package:flutter/material.dart';
import '../services/session_service.dart';
import 'login_screen.dart';

class SellerLoginScreen extends StatelessWidget {
  const SellerLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(
      presetUserType: UserType.customer,
      lockUserType: true,
      lockedUserLabel: 'Seller',
      title: 'Seller Login',
      subtitle: 'Access your store dashboard',
      postLoginRoute: '/seller-portal',
    );
  }
}

class RiderLoginScreen extends StatelessWidget {
  const RiderLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(
      presetUserType: UserType.hero,
      lockUserType: true,
      lockedUserLabel: 'Hero',
      title: 'Hero Login',
      subtitle: 'Manage rides, deliveries, and earnings',
      postLoginRoute: '/rider-portal',
    );
  }
}

class AdminLoginScreen extends StatelessWidget {
  const AdminLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(
      presetUserType: UserType.admin,
      lockUserType: true,
      lockedUserLabel: 'Admin',
      title: 'Admin Login',
      subtitle: 'Secure access to operations',
      postLoginRoute: '/admin-panel',
    );
  }
}

class CustomerLoginScreen extends StatelessWidget {
  const CustomerLoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return const LoginScreen(
      presetUserType: UserType.customer,
      lockUserType: true,
      lockedUserLabel: 'Customer',
      title: 'Customer Login',
      subtitle: 'Access orders, wallet, and support',
      postLoginRoute: '/dashboard',
    );
  }
}
