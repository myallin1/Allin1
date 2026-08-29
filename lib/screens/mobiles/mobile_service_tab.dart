// ================================================================
// MobileServiceTab — phone repair booking
// ================================================================
// Deliberately thin. Every request here goes into the EXISTING
// 'electronics_service' pipeline with category 'mobile' — the same
// requestType NJ Tech Store already uses and which already has a
// 'mobile' category defined (nj_tech_store_screen.dart: id 'mobile',
// "Repair · Service · Unlocking").
//
// Why reuse instead of adding a 'mobile_service' requestType: a new
// type would have to be registered in FOUR separate places
// (hero_service_access.dart's serviceKeyForRequestType — which returns
// null for unknown types, silently killing dispatch;
// service_request_labels.dart's kTaskTypeRequests; my_orders_screen's
// icon/label maps; firestore.rules) and each omission is a silent
// failure in a LIVE app with real heroes. Reuse gets working dispatch,
// admin visibility and tracking for free, on day one.
// ================================================================

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';

import '../../services/theme_service.dart';
import '../../widgets/auto_image_slider.dart';
import '../../widgets/cached_cloud_image.dart';
import 'mobile_hub_screen.dart';
import 'mobile_service_sheet.dart';

/// Photo Realistic theme's per-issue photo — same CachedCloudImage
/// disk-cache mechanism as dashboard_screen.dart's kSlotPhotoUrl. Covers
/// all 9 issues (unlike pinkSlot above, which only has 5 3D renders
/// today) since a real photo needs no bespoke asset production.
const Map<String, String> kMobileIssuePhotoUrl = {
  'screen': 'https://images.unsplash.com/photo-1601784551446-20c9e07cdbdb?w=200&q=80',
  'battery': 'https://images.unsplash.com/photo-1620825141335-3b3d8c8b2a9c?w=200&q=80',
  'charging': 'https://images.unsplash.com/photo-1583573636023-2b7b8b1a9c9c?w=200&q=80',
  'water': 'https://images.unsplash.com/photo-1614064641938-3bbee52942c7?w=200&q=80',
  'software': 'https://images.unsplash.com/photo-1518770660439-4636190af475?w=200&q=80',
  'camera': 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=200&q=80',
  'speaker': 'https://images.unsplash.com/photo-1558756520-22cfe5d382ca?w=200&q=80',
  'unlock': 'https://images.unsplash.com/photo-1633265486064-086b219458ec?w=200&q=80',
  'other': 'https://images.unsplash.com/photo-1512941937669-90a1b58e7e9c?w=200&q=80',
};

/// The repair categories offered. Free local data — no database.
class _MobileIssue {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final Color color;
  // Slot number in assets/images/pink_icons/mobile_<slot>_a/b.webp — only
  // 5 of the 9 issues have a real 3D render today (same partial-coverage
  // pattern as dashboard_screen.dart's taxi/food/electronics/hero icons).
  final int? pinkSlot;

  const _MobileIssue(
      this.id, this.title, this.subtitle, this.icon, this.color,
      {this.pinkSlot});
}

const List<_MobileIssue> _issues = [
  _MobileIssue('screen', 'Screen / Display', 'Cracked, blank, touch not working',
      Icons.phonelink_setup_rounded, Color(0xFFFF4FA3), pinkSlot: 3),
  _MobileIssue('battery', 'Battery', 'Draining fast, not charging, swollen',
      Icons.battery_alert_rounded, Color(0xFF00C853), pinkSlot: 1),
  _MobileIssue('charging', 'Charging Port', 'Loose, not charging, slow charge',
      Icons.power_rounded, Color(0xFFFFBB00)),
  _MobileIssue('water', 'Water Damage', 'Dropped in water, moisture damage',
      Icons.water_drop_rounded, Color(0xFF1565C0), pinkSlot: 5),
  _MobileIssue('software', 'Software', 'Hang, restart loop, update, format',
      Icons.settings_suggest_rounded, Color(0xFF7B6FE0), pinkSlot: 2),
  _MobileIssue('camera', 'Camera', 'Blur, not opening, glass broken',
      Icons.photo_camera_rounded, Color(0xFF00BFA5)),
  _MobileIssue('speaker', 'Speaker / Mic', 'No sound, call not audible',
      Icons.volume_up_rounded, Color(0xFFFF6B35)),
  _MobileIssue('unlock', 'Unlocking', 'Pattern, FRP, network unlock',
      Icons.lock_open_rounded, Color(0xFFBE2A7A)),
  _MobileIssue('other', 'Other Issue', 'Tell us what happened',
      Icons.help_outline_rounded, Color(0xFF9999BB)),
];

class MobileServiceTab extends StatelessWidget {
  const MobileServiceTab({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const MobileHubHeader(
          title: 'Mobile Service',
          subtitle: 'Repair at your doorstep — a hero collects & returns',
        ),
        Expanded(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
            children: [
              _buildPromise(),
              const SizedBox(height: 18),
              Text(
                'What is the problem?',
                style: GoogleFonts.outfit(
                  fontSize: 16,
                  fontWeight: FontWeight.w800,
                  color: kMobText,
                ),
              ),
              const SizedBox(height: 12),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount:
                      MediaQuery.of(context).size.width > 600 ? 4 : 3,
                  childAspectRatio: 0.92,
                  crossAxisSpacing: 10,
                  mainAxisSpacing: 10,
                ),
                itemCount: _issues.length,
                itemBuilder: (context, i) {
                  final issue = _issues[i];
                  final iconTheme = context.watch<ThemeService>().iconThemeKey;
                  final usePink = iconTheme == 'pink_white_3d' && issue.pinkSlot != null;
                  final photoUrl = kMobileIssuePhotoUrl[issue.id];
                  final usePhoto = iconTheme == 'photo_realistic' && photoUrl != null;
                  return InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: () => showMobileServiceSheet(
                      context,
                      issueId: issue.id,
                      issueTitle: issue.title,
                    ),
                    child: Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: kMobBg,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: kMobBorder),
                      ),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          usePhoto
                              ? ClipRRect(
                                  borderRadius: BorderRadius.circular(10),
                                  child: CachedCloudImage(
                                    photoUrl,
                                    width: 42,
                                    height: 42,
                                    fit: BoxFit.cover,
                                    cacheWidth: 168,
                                    errorWidget: Container(
                                      width: 42,
                                      height: 42,
                                      decoration: BoxDecoration(
                                        color: issue.color.withValues(alpha: 0.12),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(issue.icon, color: issue.color, size: 21),
                                    ),
                                  ),
                                )
                              : usePink
                              ? AutoImageSlider(
                                  imagePaths: [
                                    'assets/images/pink_icons/mobile_${issue.pinkSlot}_a.webp',
                                    'assets/images/pink_icons/mobile_${issue.pinkSlot}_b.webp',
                                  ],
                                  width: 42,
                                  height: 42,
                                  fit: BoxFit.contain,
                                  duration: const Duration(seconds: 3),
                                )
                              : Container(
                                  width: 42,
                                  height: 42,
                                  decoration: BoxDecoration(
                                    color: issue.color.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  child: Icon(issue.icon,
                                      color: issue.color, size: 21),
                                ),
                          const SizedBox(height: 8),
                          Text(
                            issue.title,
                            textAlign: TextAlign.center,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: GoogleFonts.outfit(
                              color: kMobText,
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildPromise() {
    const points = [
      ['🛵', 'Free pickup & drop', 'A hero collects your phone'],
      ['💰', 'Price before repair', 'No surprise bills'],
      ['🛡️', 'Warranty on repair', 'Genuine parts only'],
    ];
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: kMobPink.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: kMobPink.withValues(alpha: 0.2)),
      ),
      child: Column(
        children: points.map((p) {
          return Padding(
            padding: const EdgeInsets.symmetric(vertical: 5),
            child: Row(
              children: [
                Text(p[0], style: const TextStyle(fontSize: 20)),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        p[1],
                        style: GoogleFonts.outfit(
                          color: kMobText,
                          fontSize: 13,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      Text(
                        p[2],
                        style: GoogleFonts.outfit(
                            color: kMobMuted, fontSize: 11),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }).toList(),
      ),
    );
  }
}
