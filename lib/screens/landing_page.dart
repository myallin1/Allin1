import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/device_compat_service.dart';

class LandingPage extends StatefulWidget {
  const LandingPage({super.key});

  @override
  State<LandingPage> createState() => _LandingPageState();
}

class _LandingPageState extends State<LandingPage> {
  static const Color _bg = Color(0xFF10051A);
  static const Color _panel = Color(0xFF1A0C29);
  static const Color _pink = Color(0xFFFF4FA3);
  static const Color _pinkSoft = Color(0xFFFF92C8);
  static const Color _text = Color(0xFFFFF5FB);
  static const Color _muted = Color(0xFFDDA8C5);
  static const Color _border = Color(0x33FF92C8);

  late final Future<DeviceCompatProfile> _customerCompatFuture;
  late final Future<DeviceCompatProfile> _heroCompatFuture;

  @override
  void initState() {
    super.initState();
    _customerCompatFuture =
        DeviceCompatService.instance.detectCustomerApkProfile();
    _heroCompatFuture = DeviceCompatService.instance.detectHeroApkProfile();
  }

  Future<void> _launchUrl(String url) async {
    final uri = Uri.parse(url);
    final launched = await launchUrl(uri, mode: LaunchMode.externalApplication);
    if (!launched && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Unable to open the download link right now.'),
          backgroundColor: Colors.redAccent,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      body: SafeArea(
        child: FutureBuilder<List<DeviceCompatProfile>>(
          future: Future.wait<DeviceCompatProfile>([
            _customerCompatFuture,
            _heroCompatFuture,
          ]),
          builder: (context, snapshot) {
            final customerProfile = snapshot.data?[0];
            final heroProfile = snapshot.data?[1];
            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 18),
              child: Column(
                children: [
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(28),
                    child: Image.asset(
                      'assets/images/bapx_nj_logo.gif',
                      width: 112,
                      height: 112,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Container(
                        width: 112,
                        height: 112,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(28),
                        ),
                        child: Center(
                          child: Text(
                            'NJ',
                            style: TextStyle(
                              color: Colors.white.withValues(alpha: 0.22),
                              fontSize: 34,
                              fontWeight: FontWeight.w900,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    'Allin1 Super App',
                    style: TextStyle(
                      color: _text,
                      fontSize: 30,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Smart APK delivery for the best NJ TECH experience',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.68),
                      fontSize: 14,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(999),
                      border: Border.all(color: _pink.withValues(alpha: 0.3)),
                    ),
                    child: const Text(
                      'Starting from Erode',
                      style: TextStyle(
                        color: _pinkSoft,
                        fontSize: 12,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  const SizedBox(height: 26),
                  _buildSmartDownloadCard(
                    profile: customerProfile,
                    connectionState: snapshot.connectionState,
                    cardTitle: 'Customer Smart APK',
                    icon: Icons.shopping_bag_rounded,
                  ),
                  const SizedBox(height: 14),
                  _buildSmartDownloadCard(
                    profile: heroProfile,
                    connectionState: snapshot.connectionState,
                    cardTitle: 'Hero Smart APK',
                    icon: Icons.delivery_dining_rounded,
                  ),
                  const SizedBox(height: 18),
                  _PanelButton(
                    emoji: '🛒',
                    title: "I'm a Customer",
                    subtitle: 'Continue into the customer web experience',
                    gradient: const [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                    onTap: () => Navigator.pushNamed(context, '/login'),
                  ),
                  const SizedBox(height: 14),
                  _PanelButton(
                    emoji: '🏍️',
                    title: "I'm a Hero / Rider",
                    subtitle: 'Deliver orders & drive customers',
                    gradient: const [Color(0xFFFF4FA3), Color(0xFFFF92C8)],
                    onTap: () async {
                      await _launchUrl('https://hero-allin1.web.app');
                    },
                  ),
                  const SizedBox(height: 20),
                  Text(
                    'v1.0.0 • Made with ❤ in Erode',
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.45),
                      fontSize: 11,
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSmartDownloadCard({
    required DeviceCompatProfile? profile,
    required ConnectionState connectionState,
    required String cardTitle,
    required IconData icon,
  }) {
    final resolvedProfile = profile ??
        const DeviceCompatProfile(
          appVariant: 'customer',
          os: DeviceOs.unknown,
          architecture: CpuArchitecture.universal,
          performanceTier: PerformanceTier.unknown,
          deviceMemoryGb: null,
          hardwareConcurrency: null,
          isDetectionConfident: false,
          primaryDownloadUrl:
              'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-armeabi-v7a.apk',
          universalDownloadUrl:
              'https://github.com/myallin1/Allin1-update-release/releases/latest/download/customer-armeabi-v7a.apk',
          primaryFileLabel: 'Customer Universal APK',
        );

    final helperText = resolvedProfile.isAndroidLike
        ? resolvedProfile.isDetectionConfident
            ? 'We detected a compatible Android build for this device.'
            : 'Detection is limited on this browser, so we selected the safest APK.'
        : 'APK downloads are optimized for Android. Use the universal fallback if you are side-loading manually.';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(
        color: _panel,
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: _border),
        boxShadow: const [
          BoxShadow(
            color: Color(0x33FF4FA3),
            blurRadius: 28,
            offset: Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [_pink, _pinkSoft],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(16),
                ),
                child: Icon(icon, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      cardTitle,
                      style: const TextStyle(
                        color: _text,
                        fontSize: 18,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      connectionState == ConnectionState.waiting
                          ? 'Detecting your device profile...'
                          : helperText,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.72),
                        fontSize: 12,
                        height: 1.45,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              _MetaChip(label: resolvedProfile.osLabel),
              _MetaChip(label: resolvedProfile.architectureLabel),
              _MetaChip(label: resolvedProfile.performanceLabel),
              if (resolvedProfile.deviceMemoryGb != null)
                _MetaChip(
                  label:
                      '${resolvedProfile.deviceMemoryGb!.toStringAsFixed(0)}GB RAM',
                ),
              if (resolvedProfile.hardwareConcurrency != null)
                _MetaChip(
                  label: '${resolvedProfile.hardwareConcurrency} cores',
                ),
            ],
          ),
          const SizedBox(height: 18),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () => _launchUrl(resolvedProfile.primaryDownloadUrl),
              style: ElevatedButton.styleFrom(
                backgroundColor: _pink,
                foregroundColor: Colors.white,
                elevation: 0,
                padding:
                    const EdgeInsets.symmetric(vertical: 16, horizontal: 18),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              icon: const Icon(Icons.download_rounded),
              label: Text(
                'Download ${resolvedProfile.primaryFileLabel}',
                style: const TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Center(
            child: TextButton.icon(
              onPressed: () => _launchUrl(resolvedProfile.universalDownloadUrl),
              icon:
                  const Icon(Icons.shield_outlined, size: 18, color: _pinkSoft),
              label: const Text(
                'Download Universal APK',
                style: TextStyle(
                  color: _pinkSoft,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _LandingPageState._border),
      ),
      child: Text(
        label,
        style: TextStyle(
          color: Colors.white.withValues(alpha: 0.86),
          fontSize: 11,
          fontWeight: FontWeight.w700,
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('label', label));
  }
}

class _PanelButton extends StatelessWidget {
  const _PanelButton({
    required this.emoji,
    required this.title,
    required this.subtitle,
    required this.gradient,
    required this.onTap,
  });

  final String emoji;
  final String title;
  final String subtitle;
  final List<Color> gradient;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _LandingPageState._panel,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: _LandingPageState._border),
        ),
        child: Row(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: gradient,
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Center(
                child: Text(
                  emoji,
                  style: const TextStyle(fontSize: 24),
                ),
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      color: _LandingPageState._text,
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    subtitle,
                    style: TextStyle(
                      color: Colors.white.withValues(alpha: 0.62),
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios_rounded,
              color: Colors.white.withValues(alpha: 0.45),
              size: 16,
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('emoji', emoji));
    properties.add(StringProperty('title', title));
    properties.add(StringProperty('subtitle', subtitle));
    properties.add(IterableProperty<Color>('gradient', gradient));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}
