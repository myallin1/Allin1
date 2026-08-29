// ================================================================
// EsevaServiceScreen — "E-Seva Online Services"
// ================================================================
// NEW (Aug 12 2026 — Nizam: "designing and printing kum other services
// kum middile E Seva services kondu varaporom... atha thottu ulla
// pona, E seva services la yennenna services pannuvangalo athellathayum
// ullukulla ovvoru tiles optiona kaatalam... ipothikku antha button
// thotta oru action um nadaka kudathu, button ah wire pannama dummy
// vachutu... antha yella tiles kum keela call and whatsapp button
// vachcharlam"):
//
// A lead-generation / contact page, same pattern as
// PrintingServiceScreen and ConstructionScreen — shows the list of
// e-Seva services on offer as icon tiles, then Call + WhatsApp
// buttons so customers can follow up and book directly by phone
// until an in-app booking flow for each service exists. The tiles
// themselves are intentionally NOT wired to any action yet (dummy —
// per explicit instruction) so nothing breaks or dead-ends; only the
// Call/WhatsApp buttons at the bottom are functional today.
// ================================================================
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';
import 'package:erode_superapp/services/localization_service.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kPurple = Color(0xFF7B6FE0);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
// Same shared Allin1 contact number already used by PrintingServiceScreen
// and ConstructionScreen for this exact "call/WhatsApp to book" pattern.
const String _kPhoneNumber = '8825812798';

class _EsevaService {
  final String labelKey;
  final IconData icon;
  final String imageUrl;

  const _EsevaService({required this.labelKey, required this.icon, required this.imageUrl});
}

// NEW (Aug 12 2026 — Nizam: "ovvoru catogory kum athoda image podama
// iruku so antha tile button la neraya gapes iruku, ovvoru tile um
// yenna catogoryo athekeththa image net la irunthu set pannu vidu"):
// each tile now shows a real representative photo (Unsplash, same
// hosting pattern already used for the Construction/Car Wash service
// cards) instead of just a bare icon, so the tiles look full instead
// of empty. The gradient+icon badge is kept as the errorBuilder
// fallback below, so a slow/broken image never leaves a blank tile.
const List<_EsevaService> _kEsevaServices = [
  _EsevaService(
    labelKey: 'eseva_xerox',
    icon: Icons.print_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1598327105666-5b89351cb315?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_voter_id',
    icon: Icons.how_to_vote_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1580128637411-70dfaf5ba591?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_pan',
    icon: Icons.badge_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1580519542036-c47de6196ba5?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_aadhaar',
    icon: Icons.fingerprint_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1614064548237-096d5814680f?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_rental',
    icon: Icons.description_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_employment',
    icon: Icons.work_outline_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_ration',
    icon: Icons.receipt_long_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_birth_death',
    icon: Icons.child_care_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1519689680058-324335c77eba?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_fssai_msme',
    icon: Icons.storefront_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1556761175-4b46a572b786?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_certificate',
    icon: Icons.assignment_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_ayushman',
    icon: Icons.medical_services_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1505751172876-fa1923c5c528?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_eshram',
    icon: Icons.engineering_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1504307651254-35680f356f58?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_laptop',
    icon: Icons.computer_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1496181133206-80ce9b88a853?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_photo_print',
    icon: Icons.photo_camera_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1516035069371-29a1b244cc32?w=200&q=80',
  ),
  _EsevaService(
    labelKey: 'eseva_pvc',
    icon: Icons.credit_card_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1559526324-4b87b5e36e44?w=200&q=80',
  ),
];

class EsevaServiceScreen extends StatelessWidget {
  const EsevaServiceScreen({super.key});

  Future<void> _launchCall() async {
    final uri = Uri(scheme: 'tel', path: _kPhoneNumber);
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  Future<void> _launchWhatsApp() async {
    final uri = Uri.parse(
      'https://wa.me/91$_kPhoneNumber?text=${Uri.encodeComponent("Hi, I want to book an E-Seva service.")}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text(t('eseva_mega_title'),
            style: GoogleFonts.outfit(fontSize: 18, fontWeight: FontWeight.w800, color: _kText),),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t('What we help you with'),
                  style: GoogleFonts.outfit(color: _kMuted, fontSize: 13, fontWeight: FontWeight.w600),),
              const SizedBox(height: 14),
              GridView.builder(
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: _kEsevaServices.length,
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 3,
                  mainAxisSpacing: 14,
                  crossAxisSpacing: 12,
                  childAspectRatio: 0.82,
                ),
                itemBuilder: (context, i) => _EsevaTile(service: _kEsevaServices[i]),
              ),
              const SizedBox(height: 24),
              Text(t('Ready to apply? Reach us directly:'),
                  style: GoogleFonts.outfit(color: _kText, fontSize: 13, fontWeight: FontWeight.w700),),
              const SizedBox(height: 6),
              Text(_kPhoneNumber,
                  style: GoogleFonts.outfit(color: _kPink, fontSize: 20, fontWeight: FontWeight.w900, letterSpacing: 1),),
              const SizedBox(height: 16),
              Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF00C853),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _launchCall,
                        icon: const Icon(Icons.call_rounded, color: Colors.white, size: 20),
                        label: Text(t('Call Now'),
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: SizedBox(
                      height: 54,
                      child: ElevatedButton.icon(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF25D366),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                        ),
                        onPressed: _launchWhatsApp,
                        icon: const Icon(Icons.chat_rounded, color: Colors.white, size: 20),
                        label: Text('WhatsApp',
                            style: GoogleFonts.outfit(color: Colors.white, fontWeight: FontWeight.bold),),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EsevaTile extends StatelessWidget {
  final _EsevaService service;

  const _EsevaTile({required this.service});

  @override
  Widget build(BuildContext context) {
    final t = context.watch<LocalizationService>().t;
    final translatedLabel = t(service.labelKey);

    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () async {
          final uri = Uri.parse(
            'https://wa.me/91$_kPhoneNumber?text=${Uri.encodeComponent("Hi, I want to book an E-Seva service: $translatedLabel")}',
          );
          if (await canLaunchUrl(uri)) {
            await launchUrl(uri, mode: LaunchMode.externalApplication);
          }
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(color: _kPink.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4)),
                ],
              ),
              child: CachedCloudImage(
                service.imageUrl,
                fit: BoxFit.cover,
                loadingBuilder: (_, child, progress) => progress == null
                    ? child
                    : Container(
                        color: _kPink.withValues(alpha: 0.08),
                        child: const Center(
                          child: SizedBox(
                            width: 18, height: 18,
                            child: CircularProgressIndicator(color: _kPink, strokeWidth: 2),
                          ),
                        ),
                      ),
                errorBuilder: (_, __, ___) => Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [_kPink, _kPurple],
                    ),
                  ),
                  child: Icon(service.icon, color: Colors.white, size: 26),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Text(
              translatedLabel,
              textAlign: TextAlign.center,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(color: _kText, fontSize: 10.5, fontWeight: FontWeight.w600, height: 1.2),
            ),
          ],
        ),
      ),
    );
  }
}

