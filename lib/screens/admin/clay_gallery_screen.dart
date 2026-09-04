// ================================================================
// clay_gallery_screen.dart — see the clay in all five themes
// ================================================================
// NEW (Sep 5 2026 — the 3D Claymorphism pass).
//
// WHY THIS SCREEN EXISTS AT ALL
// The whole argument for building the icons on the live theme instead
// of on constants is that they have to survive a theme change. That
// claim is untestable by reading the code and tedious to test by
// restarting the app five times, which is exactly how premium_theme's
// dark-mode gap survived unnoticed for months. So: every theme, every
// state, one screen, switched live.
//
// It doubles as the reference for anyone adding a clay icon later —
// what the sizes look like next to each other, what selected and
// disabled actually do — so nobody has to guess and invent a sixth
// variant.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../services/theme_context_extensions.dart';
import '../../services/theme_service.dart';
import '../../widgets/clay_icon.dart';
import '../../widgets/clay_theme.dart';
import '../../widgets/premium_theme.dart';

class ClayGalleryScreen extends StatelessWidget {
  const ClayGalleryScreen({super.key});

  /// One representative colour per theme key, matching the swatch row in
  /// auth_gate_sheet. Kept as a lookup rather than building five
  /// ThemeData objects just to read a seed colour back off them.
  static const Map<String, ({Color color, String label})> _themes = {
    'pink_white': (color: Color(0xFFFF4FA3), label: 'Pink'),
    'dark_purple': (color: Color(0xFF6A1B9A), label: 'Purple'),
    'system_dark': (color: Color(0xFF2B2B2B), label: 'Dark'),
    'system_light': (color: Color(0xFFECECEC), label: 'Light'),
    'multicolor': (color: Color(0xFF00B8A9), label: 'Multi'),
  };

  static const List<({IconData icon, String label})> _sample = [
    (icon: Icons.local_taxi_rounded, label: 'Taxi'),
    (icon: Icons.restaurant_rounded, label: 'Food'),
    (icon: Icons.handyman_rounded, label: 'Hero'),
    (icon: Icons.storefront_rounded, label: 'Shops'),
    (icon: Icons.smartphone_rounded, label: 'Mobiles'),
    (icon: Icons.card_giftcard_rounded, label: 'Rewards'),
    (icon: Icons.local_grocery_store_rounded, label: 'Grocery'),
    (icon: Icons.medical_services_rounded, label: 'Medical'),
  ];

  @override
  Widget build(BuildContext context) {
    final clay = context.clay;

    return Scaffold(
      backgroundColor: context.colors.background,
      appBar: AppBar(title: const Text('Clay icons')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          _section(context, 'Switch theme — the clay follows'),
          const _ThemeSwitcher(),
          const SizedBox(height: 8),
          Text(
            clay.isDark
                ? 'Dark: the rim light drops to a whisper and the shadow '
                    'carries the depth. A full-strength white rim here '
                    'would read as a scratch, not as light.'
                : 'Light: the shadow is tinted with the brand pink, not '
                    'grey — that tint is what keeps Hot Pink and White the '
                    'star even in the shadows.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.mutedText,
                  height: 1.4,
                ),
          ),

          _section(context, 'The set'),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              for (final s in _sample)
                ClayIcon(icon: s.icon, label: s.label, onTap: () {}),
            ],
          ),

          _section(context, 'States'),
          Wrap(
            spacing: 18,
            runSpacing: 18,
            children: [
              ClayIcon(
                icon: Icons.favorite_rounded,
                label: 'Normal',
                onTap: () {},
              ),
              ClayIcon(
                icon: Icons.favorite_rounded,
                label: 'Selected',
                selected: true,
                onTap: () {},
              ),
              const ClayIcon(
                icon: Icons.favorite_rounded,
                label: 'Disabled',
                enabled: false,
              ),
              ClayIcon(
                icon: Icons.check_rounded,
                label: 'Own colour',
                color: kPremiumGreen,
                onTap: () {},
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            'Press and hold one — it sinks INTO the page rather than just '
            'darkening. That is the affordance; a ripple would flatten the '
            'light and undo the effect.',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: context.colors.mutedText,
                  height: 1.4,
                ),
          ),

          _section(context, 'Sizes'),
          Wrap(
            spacing: 16,
            runSpacing: 16,
            crossAxisAlignment: WrapCrossAlignment.end,
            children: [
              for (final size in <double>[36, 48, 56, 72, 88])
                ClayIcon(
                  icon: Icons.bolt_rounded,
                  size: size,
                  onTap: () {},
                ),
            ],
          ),

          _section(context, 'Same material, card scale'),
          ClaySurface(
            padding: const EdgeInsets.all(16),
            onTap: () {},
            child: Row(
              children: [
                const ClayIcon(icon: Icons.receipt_long_rounded, size: 44),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('ClaySurface', style: premiumTitle(context)),
                      const SizedBox(height: 3),
                      Text(
                        'The panel and the icon are lit from the same place, '
                        'because they read the same tokens.',
                        style: premiumBody(context, size: 11.5),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          PremiumCard(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('PremiumCard', style: premiumTitle(context)),
                const SizedBox(height: 3),
                Text(
                  'The Mobile Hub / Rewards card. Until today this was a '
                  'hardcoded white slab with black text and stayed white in '
                  'both dark themes. Flip to Purple or Dark above — it '
                  'follows now.',
                  style: premiumBody(context, size: 11.5),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _section(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.only(top: 24, bottom: 12),
        child: Text(
          title,
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                fontWeight: FontWeight.w800,
                color: context.colors.text,
              ),
        ),
      );
}

/// Live theme switcher. Deliberately the same five keys and colours the
/// customer's own picker uses, so what he sees here is what they get.
class _ThemeSwitcher extends StatelessWidget {
  const _ThemeSwitcher();

  @override
  Widget build(BuildContext context) {
    final themeService = context.watch<ThemeService>();
    final selected = themeService.themeKey;

    return Wrap(
      spacing: 14,
      runSpacing: 12,
      children: [
        for (final entry in ClayGalleryScreen._themes.entries)
          ClayIcon(
            icon: entry.key == selected
                ? Icons.check_rounded
                : Icons.circle_outlined,
            label: entry.value.label,
            color: entry.value.color,
            size: 46,
            selected: entry.key == selected,
            onTap: () => unawaited(themeService.setTheme(entry.key)),
          ),
      ],
    );
  }
}
