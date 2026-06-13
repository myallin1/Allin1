import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

const Color _bg = Color(0xFF0A0A1A);
const Color _surface = Color(0xFF12121E);
const Color _card = Color(0xFF1A1A2E);
const Color _gold = Color(0xFFFFBB00);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _border = Color(0x1AFFFFFF);

class AdminHeroMirrorScreen extends StatelessWidget {
  const AdminHeroMirrorScreen({
    required this.heroUid,
    required this.heroData,
    super.key,
  });

  final String heroUid;
  final Map<String, dynamic> heroData;

  String _valueFor(List<String> keys, {String fallback = 'N/A'}) {
    for (final key in keys) {
      final value = heroData[key];
      if (value is String && value.trim().isNotEmpty) {
        return value.trim();
      }
      if (value != null && value.toString().trim().isNotEmpty) {
        return value.toString().trim();
      }
    }
    return fallback;
  }

  String _timestampLabel(List<String> keys) {
    for (final key in keys) {
      final value = heroData[key];
      if (value is Timestamp) {
        final dt = value.toDate();
        return '${dt.day}/${dt.month}/${dt.year} '
            '${dt.hour}:${dt.minute.toString().padLeft(2, '0')}';
      }
    }
    return 'N/A';
  }

  @override
  Widget build(BuildContext context) {
    final name = _valueFor(['name', 'displayName'], fallback: 'Hero');
    final phone = _valueFor(['phone', 'phoneNumber', 'mobile']);
    final email = _valueFor(['email']);
    final vehicleType = _valueFor(['vehicleType', 'heroCategory']);
    final vehicleNumber = _valueFor(['vehicleNumber', 'vehicleNo', 'regNo']);
    final licenseNumber = _valueFor(['licenseNumber', 'licenseNo']);
    final onboardingMethod = _valueFor(['onboardingMethod']);
    final approvalStatus = _valueFor(
      ['approvalStatus', 'status'],
      fallback: 'approved',
    );
    final createdAt = _timestampLabel(['createdAt', 'approvedAt', 'lastUpdated']);

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _surface,
        foregroundColor: _text,
        elevation: 0,
        title: Text(
          'Hero Mirror',
          style: GoogleFonts.outfit(fontWeight: FontWeight.w800),
        ),
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Container(
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: _card,
              borderRadius: BorderRadius.circular(22),
              border: Border.all(color: _border),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 28,
                  backgroundColor: _gold.withValues(alpha: 0.18),
                  child: const Icon(Icons.person, color: _gold, size: 28),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: GoogleFonts.outfit(
                          color: _text,
                          fontSize: 20,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        phone,
                        style: const TextStyle(color: _muted, fontSize: 13),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _green.withValues(alpha: 0.16),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    approvalStatus,
                    style: const TextStyle(
                      color: _green,
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          _MirrorSection(
            title: 'Hero Details',
            children: [
              _MirrorRow(label: 'Email', value: email),
              _MirrorRow(label: 'Vehicle Type', value: vehicleType),
              _MirrorRow(label: 'Vehicle No.', value: vehicleNumber),
              _MirrorRow(label: 'License', value: licenseNumber),
              _MirrorRow(label: 'Onboarding', value: onboardingMethod),
              _MirrorRow(label: 'Created', value: createdAt),
              _MirrorRow(label: 'UID', value: heroUid, mono: true),
            ],
          ),
          const SizedBox(height: 16),
          _MirrorSection(
            title: 'Raw Snapshot',
            children: [
              SelectableText(
                heroData.entries
                    .map((entry) => '${entry.key}: ${entry.value}')
                    .join('\n'),
                style: const TextStyle(
                  color: _muted,
                  fontSize: 12,
                  height: 1.4,
                  fontFamily: 'monospace',
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _MirrorSection extends StatelessWidget {
  const _MirrorSection({
    required this.title,
    required this.children,
  });

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: _border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: GoogleFonts.outfit(
              color: _text,
              fontSize: 15,
              fontWeight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          ...children,
        ],
      ),
    );
  }
}

class _MirrorRow extends StatelessWidget {
  const _MirrorRow({
    required this.label,
    required this.value,
    this.mono = false,
  });

  final String label;
  final String value;
  final bool mono;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 110,
            child: Text(
              label,
              style: const TextStyle(
                color: _muted,
                fontSize: 12,
                fontWeight: FontWeight.w700,
              ),
            ),
          ),
          Expanded(
            child: SelectableText(
              value,
              style: TextStyle(
                color: mono ? _red : _text,
                fontSize: 12,
                fontFamily: mono ? 'monospace' : null,
                fontWeight: mono ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
