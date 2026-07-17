import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:google_fonts/google_fonts.dart';

const Color kBg = Color(0xFF08080F);
const Color kSurface = Color(0xFF0D0D18);
const Color kCard = Color(0xFF141420);
const Color kCard2 = Color(0xFF1A1A28);
const Color kPurple = Color(0xFF7B6FE0);
const Color kOrange = Color(0xFFE07C6F);
const Color kGreen = Color(0xFF3DBA6F);
const Color kGold = Color(0xFFF5C542);
const Color kText = Color(0xFFEEEEF5);
const Color kMuted = Color(0xFF7777A0);
const Color kBorder = Color(0x267B6FE0);

class RiderScreen extends StatelessWidget {
  const RiderScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: kBg,
      appBar: AppBar(
        backgroundColor: kSurface,
        title: Text(
          'Rider Dashboard',
          style: GoogleFonts.spaceGrotesk(color: kText),
        ),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _Hero().animate().fadeIn(duration: 350.ms).slideY(begin: 0.05),
            const SizedBox(height: 20),
            _EarningsCard(),
            const SizedBox(height: 20),
            _FeatureList(),
            const SizedBox(height: 24),
            _CTA(),
          ],
        ),
      ),
    );
  }
}

class _Hero extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: kBorder),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Rider command center',
            style: GoogleFonts.spaceGrotesk(
              color: kText,
              fontSize: 24,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Receive ride and delivery requests instantly with navigation, '
            'tips, and faster payouts.',
            style: GoogleFonts.outfit(color: kMuted, fontSize: 13),
          ),
          const SizedBox(height: 14),
          const Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              _Pill(text: 'Live Requests', color: kGreen),
              _Pill(text: 'Wallet Payouts', color: kGold),
              _Pill(text: 'Ride + Delivery', color: kOrange),
            ],
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  final String text;
  final Color color;

  const _Pill({required this.text, required this.color});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        text,
        style: GoogleFonts.outfit(color: color, fontSize: 12),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(StringProperty('text', text))
      ..add(ColorProperty('color', color));
  }
}

class _EarningsCard extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [kGreen.withValues(alpha: 0.25), kSurface],
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.directions_bike, color: kGreen, size: 28),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Daily Earnings',
                  style: GoogleFonts.outfit(color: kMuted, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  'Track rides, tips, and bonuses',
                  style: GoogleFonts.outfit(color: kText, fontSize: 13),
                ),
              ],
            ),
          ),
          Text(
            '₹ 1,250',
            style: GoogleFonts.spaceGrotesk(
              color: kGold,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureList extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final items = [
      'Instant ride and delivery requests',
      'In‑app navigation with live route tracking',
      'Wallet balance and instant payouts',
      'Customer chat for pickup clarity',
      'Verified rider profile with documents',
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Rider Features',
          style: GoogleFonts.spaceGrotesk(
            color: kText,
            fontSize: 18,
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: 10),
        ...items.map(
          (i) => Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: kCard,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: kBorder),
            ),
            child: Row(
              children: [
                const Icon(Icons.check_circle, color: kGreen, size: 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    i,
                    style: GoogleFonts.outfit(color: kText, fontSize: 12),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _CTA extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: kCard2,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kBorder),
      ),
      child: Row(
        children: [
          const Icon(Icons.badge, color: kPurple),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              'Quick actions',
              style: GoogleFonts.outfit(color: kText, fontSize: 13),
            ),
          ),
          OutlinedButton(
            onPressed: () {},
            style: OutlinedButton.styleFrom(
              foregroundColor: kText,
              side: const BorderSide(color: kBorder),
            ),
            child: const Text('Go Online'),
          ),
          const SizedBox(width: 8),
          ElevatedButton(
            onPressed: () {},
            style: ElevatedButton.styleFrom(backgroundColor: kGreen),
            child: const Text('View Trips'),
          ),
        ],
      ),
    );
  }
}
