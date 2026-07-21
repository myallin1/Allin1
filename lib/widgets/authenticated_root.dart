// lib/widgets/authenticated_root.dart
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import '../screens/dashboard_screen.dart';

/// A wrapper for the Dashboard that intercepts the back button 
/// to prevent logging out unintentionally.
class AuthenticatedRoot extends StatelessWidget {
  const AuthenticatedRoot({super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) {
          return;
        }

        // Show exit confirmation instead of going to login
        showDialog<bool>(
          context: context,
          builder: (_) => AlertDialog(
            backgroundColor: const Color(0xFF1A1A2A),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Text(
              'Close the app?',
              style: TextStyle(
                color: Color(0xFFEEEEF5),
                fontSize: 16,
                fontWeight: FontWeight.w700,
              ),
            ),
            content: const Text(
              'Are you sure you want to exit Allin1?',
              style: TextStyle(color: Color(0xFF7777A0), fontSize: 13),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  'No',
                  style: TextStyle(color: Color(0xFF7777A0)),
                ),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5252),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
                onPressed: () {
                  Navigator.pop(context, true);
                  SystemNavigator.pop(); // Close app
                },
                child: const Text(
                  'Exit',
                  style: TextStyle(color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
      child: const DashboardScreen(),
    );
  }
}
