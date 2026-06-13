// lib/screens/coming_soon_screen.dart
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

class ComingSoonScreen extends StatelessWidget {
  final String role;
  const ComingSoonScreen({required this.role, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF08080F),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('🚧', style: TextStyle(fontSize: 64)),
            const SizedBox(height: 16),
            Text(
              '$role — Coming Soon!',
              style: const TextStyle(
                color: Color(0xFFEEEEF5),
                fontSize: 18,
                fontWeight: FontWeight.w700,
              ),
            ),
            const SizedBox(height: 24),
            ElevatedButton(
              onPressed: () => Navigator.pushNamedAndRemoveUntil(
                context,
                '/dashboard',
                (r) => false,
              ),
              child: const Text('Go to Dashboard'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('role', role));
  }
}
