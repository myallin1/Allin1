// ================================================================
// Verification Pending Screen
// Allin1 Super App - Hero Verification Status
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

class HeroVerificationPendingScreen extends StatefulWidget {
  final String heroId;

  const HeroVerificationPendingScreen({super.key, required this.heroId});

  @override
  State<HeroVerificationPendingScreen> createState() =>
      _HeroVerificationPendingScreenState();
}

class _HeroVerificationPendingScreenState
    extends State<HeroVerificationPendingScreen> {
  static const String _adminWhatsApp = '919597879191';
  static const String _adminPhone = '+919597879191';

  Future<void> _launchWhatsApp() async {
    final message = Uri.encodeComponent(
        'Hi Admin, this is ${widget.heroId}. I have submitted my documents and am ready for verification. Please approve my Hero account when possible.');
    final url =
        Uri.parse('https://wa.me/$_adminWhatsApp?text=$message');

    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open WhatsApp'),
          backgroundColor: Color(0xFF25D366),
        ),
      );
    }
  }

  Future<void> _launchCall() async {
    final url = Uri.parse('tel:$_adminPhone');

    if (await canLaunchUrl(url)) {
      await launchUrl(url);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open phone dialer'),
          backgroundColor: Colors.blue,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A12),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A0A12),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: Text(
          'Verification Pending',
          style: GoogleFonts.outfit(
            color: Colors.white,
            fontSize: 22,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Hero Icon with Status
            Container(
              width: 120,
              height: 120,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  // T1: was [Color(0xFFFFBB00), Color(0xFFFF6B35)] — orange eradicated
                  colors: [Color(0xFFFF4FA3), Color(0xFFBE2A7A)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                boxShadow: const [
                  BoxShadow(
                    // T1: shadow now matches NJ Pink
                    color: Color(0x4AFF4FA3),
                    blurRadius: 20,
                    offset: Offset(0, 10),
                  ),
                ],
              ),
              child: const Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.verified_user,
                    color: Colors.white,
                    size: 48,
                  ),
                  SizedBox(height: 8),
                  Text(
                    'Pending Review',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),

            // Status Message
            const Text(
              'Your registration has been submitted and is awaiting admin approval.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Color(0xFFEEEEF5),
                fontSize: 16,
                height: 1.5,
              ),
            ),
            const SizedBox(height: 32),

            // Instructions
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFFFBB00).withValues(alpha: 0.3),
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'To Speed Up Approval:',
                    style: TextStyle(
                      color: Color(0xFFFFBB00),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text(
                    '• Send your documents (Aadhar, PAN, License) to Admin via WhatsApp\n• Call for immediate verification\n• Keep your phone available for confirmation',
                    style: TextStyle(
                      color: Color(0xFFEEEEF5),
                      fontSize: 14,
                      height: 1.8,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // Action Buttons
            const Text(
              'Quick Actions',
              style: TextStyle(
                color: Color(0xFFEEEEF5),
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _launchWhatsApp,
                    icon: const Icon(
                      Icons.chat,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'WhatsApp Admin',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF25D366),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _launchCall,
                    icon: const Icon(
                      Icons.call,
                      color: Colors.white,
                    ),
                    label: const Text(
                      'Call Admin',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: ElevatedButton.styleFrom(
                      // T3: was Colors.blue — NJ Pink brand fix
                      backgroundColor: const Color(0xFFFF4FA3),
                      foregroundColor: Colors.white,
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 40),

            // Auto-check suggestion
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2A),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                  color: const Color(0xFF00C853).withValues(alpha: 0.3),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Color(0xFF00C853),
                    size: 20,
                  ),
                  SizedBox(width: 12),
                  Expanded(
                     child: Text(
                       "Tip: You can check back in 2-4 hours for approval status, or we'll notify you via SMS once approved.",
                       style: TextStyle(
                         color: Color(0xFFBBBBBB),
                         fontSize: 14,
                       ),
                     ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}