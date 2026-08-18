// ================================================================
// video_link_field.dart — the one YouTube-link input, shared by the
// seller app (mobile listings) and the admin app (Erode offers).
// ================================================================
// NEW (Aug 18 2026 — Founder's brief: "the UI where sellers/admins
// input the videoUrl must be equally polished ... immediate
// validation").
//
// Shared deliberately. Two hand-rolled copies would inevitably accept
// slightly different URL shapes, and the failure mode is invisible to
// us and infuriating to the seller: they paste a perfectly good link,
// it silently isn't accepted, and they conclude the app is broken.
// One field, one parser (youtubeVideoId), one set of rules.
//
// VALIDATION IS LIVE, NOT ON-SUBMIT. A seller pasting from the YouTube
// share sheet gets a green tick the instant it lands, and — more
// usefully — the actual video thumbnail. Seeing the right phone appear
// is far stronger confirmation than any tick mark, because it also
// catches "valid link, wrong video", which no validator can.
//
// Supports light (admin/seller dark surfaces pass their own colours)
// so it drops into either app without a second implementation.

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../models/mobile_models.dart' show youtubeVideoId;
import 'premium_theme.dart';

class VideoLinkField extends StatelessWidget {
  final TextEditingController controller;

  /// Called on every keystroke so the parent can rebuild and refresh
  /// the live preview. Parent owns the state; this widget stays dumb.
  final VoidCallback onChanged;

  final String label;
  final String helper;

  // Theming hooks — the admin/seller shells are dark, the customer app
  // is light, and this field is used on dark surfaces today.
  final Color fillColor;
  final Color textColor;
  final Color mutedColor;
  final Color borderColor;
  final Color accentColor;

  const VideoLinkField({
    super.key,
    required this.controller,
    required this.onChanged,
    this.label = 'YouTube video link',
    this.helper =
        'Paste the share link from the YouTube app. Optional — but a short '
        'clip sells far better than photos alone.',
    this.fillColor = const Color(0xFF141420),
    this.textColor = const Color(0xFFEEEEF5),
    this.mutedColor = const Color(0xFF7777A0),
    this.borderColor = const Color(0x267B6FE0),
    this.accentColor = kPremiumPink,
  });

  @override
  Widget build(BuildContext context) {
    final raw = controller.text.trim();
    final videoId = youtubeVideoId(raw);
    final hasText = raw.isNotEmpty;
    final isValid = videoId != null;

    // Border reflects state: neutral when empty, green when the link
    // resolves, red once there's text that clearly won't work.
    final stateColor = !hasText
        ? borderColor
        : (isValid ? kPremiumGreen : const Color(0xFFFF5252));

    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: kVideoRed.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(7),
                ),
                child: const Icon(Icons.smart_display_rounded,
                    color: kVideoRed, size: 15),
              ),
              const SizedBox(width: 8),
              Text(
                label,
                style: GoogleFonts.outfit(
                  color: textColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(width: 6),
              Text(
                'optional',
                style: GoogleFonts.outfit(
                  color: mutedColor,
                  fontSize: 10.5,
                  fontStyle: FontStyle.italic,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(helper,
              style: GoogleFonts.outfit(color: mutedColor, fontSize: 11)),
          const SizedBox(height: 10),
          TextField(
            controller: controller,
            onChanged: (_) => onChanged(),
            keyboardType: TextInputType.url,
            style: GoogleFonts.outfit(color: textColor, fontSize: 14),
            decoration: InputDecoration(
              hintText: 'https://youtu.be/...',
              hintStyle:
                  GoogleFonts.outfit(color: mutedColor, fontSize: 12.5),
              filled: true,
              fillColor: fillColor,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              suffixIcon: !hasText
                  ? null
                  : Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: Icon(
                        isValid
                            ? Icons.check_circle_rounded
                            : Icons.error_outline_rounded,
                        color: stateColor,
                        size: 20,
                      ),
                    ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusSm),
                borderSide: BorderSide(color: stateColor),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusSm),
                borderSide: BorderSide(color: stateColor),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(kRadiusSm),
                borderSide: BorderSide(
                    color: hasText ? stateColor : accentColor, width: 1.6),
              ),
            ),
          ),

          // Live preview. Confirms not just "this parses" but "this is
          // the right video" — the failure a validator can't catch.
          if (isValid) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: SizedBox(
                    width: 108,
                    height: 61, // 16:9
                    child: Image.network(
                      'https://img.youtube.com/vi/$videoId/hqdefault.jpg',
                      fit: BoxFit.cover,
                      errorBuilder: (_, __, ___) => Container(
                        color: fillColor,
                        alignment: Alignment.center,
                        child: Icon(Icons.videocam_off_rounded,
                            color: mutedColor, size: 18),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          const Icon(Icons.check_circle_rounded,
                              color: kPremiumGreen, size: 14),
                          const SizedBox(width: 5),
                          Text(
                            'Video linked',
                            style: GoogleFonts.outfit(
                              color: kPremiumGreen,
                              fontSize: 12,
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'Customers will see a VIDEO badge and can watch '
                        'without leaving the app.',
                        style: GoogleFonts.outfit(
                            color: mutedColor, fontSize: 10.5, height: 1.3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ] else if (hasText) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                const Icon(Icons.error_outline_rounded,
                    color: Color(0xFFFF5252), size: 14),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    "That doesn't look like a YouTube link yet.",
                    style: GoogleFonts.outfit(
                      color: const Color(0xFFFF5252),
                      fontSize: 11,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
