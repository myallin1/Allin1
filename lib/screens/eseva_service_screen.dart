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
import 'package:url_launcher/url_launcher.dart';
import 'package:erode_superapp/widgets/cached_cloud_image.dart';

const Color _kPink = Color(0xFFFF4FA3);
const Color _kPurple = Color(0xFF7B6FE0);
const Color _kBg = Color(0xFFFFFFFF);
const Color _kText = Color(0xFF1A1A2E);
const Color _kMuted = Color(0xFF9999BB);
// Same shared Allin1 contact number already used by PrintingServiceScreen
// and ConstructionScreen for this exact "call/WhatsApp to book" pattern.
const String _kPhoneNumber = '8825812798';

class _EsevaService {
  final String label;
  final IconData icon;
  final String imageUrl;

  const _EsevaService({required this.label, required this.icon, required this.imageUrl});
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
    label: 'New PAN Card & Correction',
    icon: Icons.badge_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1580519542036-c47de6196ba5?w=200&q=80',
  ),
  _EsevaService(
    label: 'Aadhaar Card Update',
    icon: Icons.fingerprint_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1614064548237-096d5814680f?w=200&q=80',
  ),
  _EsevaService(
    label: 'Passport Application',
    icon: Icons.menu_book_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1526778548025-fa2f459cd5c1?w=200&q=80',
  ),
  _EsevaService(
    label: 'Voter ID Card',
    icon: Icons.how_to_vote_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1580128637411-70dfaf5ba591?w=200&q=80',
  ),
  _EsevaService(
    label: 'Driving Licence',
    icon: Icons.directions_car_filled_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1449965408869-eaa3f722e40d?w=200&q=80',
  ),
  _EsevaService(
    label: 'Ration Card',
    icon: Icons.receipt_long_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1542838132-92c53300491e?w=200&q=80',
  ),
  _EsevaService(
    label: 'Birth / Death Certificate',
    icon: Icons.description_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1554224155-6726b3ff858f?w=200&q=80',
  ),
  _EsevaService(
    label: 'Income / Community Certificate',
    icon: Icons.assignment_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1450101499163-c8848c66ca85?w=200&q=80',
  ),
  _EsevaService(
    label: 'Bank Account Opening & KYC',
    icon: Icons.account_balance_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1541354329998-f4d9a9f9297f?w=200&q=80',
  ),
  _EsevaService(
    label: 'Property & Legal Document Services',
    icon: Icons.home_work_rounded,
    imageUrl: 'https://images.unsplash.com/photo-1560518883-ce09059eeffa?w=200&q=80',
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
    return Scaffold(
      backgroundColor: _kBg,
      appBar: AppBar(
        backgroundColor: _kBg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new_rounded, color: _kText, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('E-Seva Online Services',
            style: GoogleFonts.outfit(color: _kText, fontWeight: FontWeight.w800, fontSize: 16),),
        centerTitle: true,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('What we help you with',
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
              Text('Ready to apply? Reach us directly:',
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
                        label: Text('Call Now',
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
    // Deliberately no onTap wired yet — per Nizam's explicit "dummy vachu"
    // instruction, these are placeholder buttons until each service gets
    // its own in-app booking flow. InkWell still gives a tap ripple so it
    // visually reads as a real button, just without a destination yet.
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {},
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
              service.label,
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

