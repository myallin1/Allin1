// ================================================================
// nj_tech_store_screen.dart
// All In One Electronic Services — NJ Tech Store
// Premium Grid UI + Category Modal + WhatsApp Enquiry
// ================================================================

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

// ── Brand Colors (matches dashboard theme) ───────────────────────
const Color _kPink     = Color(0xFFFF4FA3);
const Color _kPinkDark = Color(0xFFBE2A7A);
const Color _kNJDark   = Color(0xFF130B28);
const Color _kNJDark2  = Color(0xFF2A1060);
const Color _kBg       = Color(0xFFFFFFFF);
const Color _kSurface  = Color(0xFFF8F8FF);
const Color _kText     = Color(0xFF1A1A2E);
const Color _kMuted    = Color(0xFF9999BB);
const Color _kBorder   = Color(0xFFEEEEF5);
const Color _kGold     = Color(0xFFFFBB00);
const Color _kGreen    = Color(0xFF00C853);
const Color _kRed      = Color(0xFFFF5252);
const Color _kBlue     = Color(0xFF1565C0);
const Color _kTeal     = Color(0xFF00BFA5);
const Color _kPurple   = Color(0xFF7B6FE0);
const Color _kOrange   = Color(0xFFFF6B35);

// NJ Tech WhatsApp number
const String _kNJPhone    = '+919597879191';
const String _kNJWhatsApp = '919597879191';

// ── Service Category Model ────────────────────────────────────────
class _ServiceCategory {
  final String id;
  final String title;
  final String subtitle;
  final IconData icon;
  final IconData icon2;
  final IconData icon3;
  final Color color;

  const _ServiceCategory({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.icon2,
    required this.icon3,
    required this.color,
  });
}

const _categories = [
  _ServiceCategory(
    id: 'mobile',
    title: 'Mobile',
    subtitle: 'Repair · Service · Unlocking',
    icon: Icons.smartphone_rounded,
    icon2: Icons.phonelink_setup_rounded,
    icon3: Icons.phone_android_rounded,
    color: _kPink,
  ),
  _ServiceCategory(
    id: 'laptop',
    title: 'Laptop',
    subtitle: 'Repair · Upgrade · Data Recovery',
    icon: Icons.laptop_rounded,
    icon2: Icons.laptop_chromebook_rounded,
    icon3: Icons.memory_rounded,
    color: _kBlue,
  ),
  _ServiceCategory(
    id: 'pc',
    title: 'PC / Desktop',
    subtitle: 'Build · Repair · Upgrade',
    icon: Icons.desktop_windows_rounded,
    icon2: Icons.computer_rounded,
    icon3: Icons.developer_board_rounded,
    color: _kPurple,
  ),
  _ServiceCategory(
    id: 'cctv',
    title: 'CCTV',
    subtitle: 'Installation · Maintenance · DVR',
    icon: Icons.videocam_rounded,
    icon2: Icons.camera_outdoor_rounded,
    icon3: Icons.monitor_rounded,
    color: _kTeal,
  ),
  _ServiceCategory(
    id: 'hometheatre',
    title: 'Home Theatre',
    subtitle: 'Setup · Wiring · Surround Sound',
    icon: Icons.surround_sound_rounded,
    icon2: Icons.speaker_rounded,
    icon3: Icons.home_rounded,
    color: _kOrange,
  ),
  _ServiceCategory(
    id: 'tv',
    title: 'TV',
    subtitle: 'LED · Smart TV · Panel Repair',
    icon: Icons.tv_rounded,
    icon2: Icons.cast_rounded,
    icon3: Icons.settings_input_antenna_rounded,
    color: _kGold,
  ),
  _ServiceCategory(
    id: 'gadgets',
    title: 'Gadgets',
    subtitle: 'Earbuds · Tablets · Accessories',
    icon: Icons.headphones_rounded,
    icon2: Icons.tablet_rounded,
    icon3: Icons.watch_rounded,
    color: _kGreen,
  ),
];

// ================================================================
// MAIN SCREEN
// ================================================================
class NJTechStoreScreen extends StatelessWidget {
  const NJTechStoreScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          _buildSliverAppBar(context),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(child: _buildTopBanner()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            sliver: SliverToBoxAdapter(
              child: Text(
                'What do you need?',
                style: GoogleFonts.outfit(
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                  color: _kText,
                ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            sliver: SliverGrid(
              delegate: SliverChildBuilderDelegate(
                (context, i) => _CategoryTile(
                  category: _categories[i],
                  onTap: () => _showCategoryModal(context, _categories[i]),
                ),
                childCount: _categories.length,
              ),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: MediaQuery.of(context).size.width > 600 ? 4 : 3,
                childAspectRatio: 1.1,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            sliver: SliverToBoxAdapter(child: _buildWhyNJCard()),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 100),
            sliver: SliverToBoxAdapter(child: _buildCallBanner(context)),
          ),
        ],
      ),
    );
  }

  // ── Sliver AppBar ─────────────────────────────────────────────
  Widget _buildSliverAppBar(BuildContext context) {
    return SliverAppBar(
      expandedHeight: 160,
      pinned: true,
      backgroundColor: _kNJDark,
      leading: IconButton(
        icon: const Icon(Icons.arrow_back_ios_new_rounded,
            color: Colors.white, size: 20),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_kNJDark, _kNJDark2, Color(0xFF3D1560)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 48, 20, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Row(children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kPink.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _kPink.withValues(alpha: 0.5)),
                      ),
                      child: Text('NJ TECH',
                          style: GoogleFonts.outfit(
                              color: _kPink,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2)),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 5, height: 5,
                          decoration: const BoxDecoration(
                              color: _kGreen, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 4),
                        Text('Open Now',
                            style: GoogleFonts.outfit(
                                color: _kGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.w700)),
                      ]),
                    ),
                  ]),
                  const SizedBox(height: 8),
                  Text('All In One\nElectronic Services',
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.2)),
                  const SizedBox(height: 4),
                  Text('Erode · Sales · Service · Installation',
                      style: GoogleFonts.outfit(
                          color: Colors.white54, fontSize: 11)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── Top Banner ────────────────────────────────────────────────
  Widget _buildTopBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            _kPink.withValues(alpha: 0.08),
            _kPurple.withValues(alpha: 0.05),
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kPink.withValues(alpha: 0.15)),
      ),
      child: Row(children: [
        Container(
          width: 48, height: 48,
          decoration: BoxDecoration(
            color: _kPink.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(14),
          ),
          child: const Icon(Icons.electric_bolt_rounded,
              color: _kPink, size: 26),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Free Diagnosis for First Visit!',
              style: GoogleFonts.outfit(
                  color: _kText, fontSize: 13,
                  fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Tap any category to book or enquire via WhatsApp',
              style: GoogleFonts.outfit(
                  color: _kMuted, fontSize: 11)),
        ])),
      ]),
    );
  }

  // ── Why NJ Tech Card ──────────────────────────────────────────
  Widget _buildWhyNJCard() {
    final points = [
      (Icons.verified_rounded, _kGreen, 'Certified Technicians'),
      (Icons.timer_rounded, _kBlue, 'Same Day Service'),
      (Icons.currency_rupee_rounded, _kGold, 'Transparent Pricing'),
      (Icons.shield_rounded, _kPurple, '6 Month Warranty'),
    ];
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _kSurface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _kBorder),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('Why NJ Tech?',
            style: GoogleFonts.outfit(
                fontSize: 15, fontWeight: FontWeight.w800, color: _kText)),
        const SizedBox(height: 12),
        GridView.count(
          crossAxisCount: 2,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          childAspectRatio: 4,
          crossAxisSpacing: 8,
          mainAxisSpacing: 8,
          children: points.map((p) => Row(children: [
            Icon(p.$1, color: p.$2, size: 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(p.$3,
                  style: GoogleFonts.outfit(
                      fontSize: 11, fontWeight: FontWeight.w600,
                      color: _kText)),
            ),
          ])).toList(),
        ),
      ]),
    );
  }

  // ── Bottom Call Banner ────────────────────────────────────────
  Widget _buildCallBanner(BuildContext context) {
    return GestureDetector(
      onTap: () async {
        final uri = Uri.parse('tel:$_kNJPhone');
        if (await canLaunchUrl(uri)) launchUrl(uri);
      },
      child: Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [_kNJDark, _kNJDark2],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(children: [
          Container(
            width: 48, height: 48,
            decoration: BoxDecoration(
              color: _kPink.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.phone_rounded, color: _kPink, size: 24),
          ),
          const SizedBox(width: 14),
          Expanded(child: Column(
              crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Call Us Directly',
                style: GoogleFonts.outfit(
                    color: Colors.white, fontSize: 14,
                    fontWeight: FontWeight.w800)),
            Text('+91 95978 79191 · Mon–Sat 9am–8pm',
                style: GoogleFonts.outfit(
                    color: Colors.white54, fontSize: 10)),
          ])),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kPink, borderRadius: BorderRadius.circular(12)),
            child: const Icon(Icons.arrow_forward_rounded,
                color: Colors.white, size: 18),
          ),
        ]),
      ),
    );
  }

  // ── Show Category Modal ───────────────────────────────────────
  void _showCategoryModal(BuildContext context, _ServiceCategory cat) {
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _CategoryModal(category: cat),
    );
  }
}

// ================================================================
// CATEGORY TILE WIDGET
// ================================================================
class _CategoryTile extends StatefulWidget {
  final _ServiceCategory category;
  final VoidCallback onTap;
  const _CategoryTile({required this.category, required this.onTap});

  @override
  State<_CategoryTile> createState() => _CategoryTileState();
}

class _CategoryTileState extends State<_CategoryTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _iconIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3))
      ..repeat();
    _ctrl.addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted) {
        setState(() => _iconIndex = (_iconIndex + 1) % 3);
        _ctrl.forward(from: 0);
      }
    });
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  IconData get _currentIcon {
    switch (_iconIndex) {
      case 0: return widget.category.icon;
      case 1: return widget.category.icon2;
      default: return widget.category.icon3;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    return GestureDetector(
      onTap: widget.onTap,
      child: Container(
        decoration: BoxDecoration(
          color: cat.color.withValues(alpha: 0.06),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: cat.color.withValues(alpha: 0.15)),
          boxShadow: [BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8, offset: const Offset(0, 3),
          )],
        ),
        padding: const EdgeInsets.only(top: 10, left: 6, right: 6, bottom: 6),
        child: Stack(children: [
          Column(children: [
            // Title
            Text(
              cat.title,
              maxLines: 1,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.outfit(
                fontSize: 11, fontWeight: FontWeight.w800,
                color: _kText, letterSpacing: -0.2,
              ),
            ),
            const SizedBox(height: 8),
            // Animated Icon
            Expanded(
              child: Center(
                child: Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                    boxShadow: [BoxShadow(
                      color: cat.color.withValues(alpha: 0.3),
                      blurRadius: 12, spreadRadius: 2,
                    )],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: CurvedAnimation(
                          parent: anim, curve: Curves.elasticOut),
                      child: FadeTransition(opacity: anim, child: child),
                    ),
                    child: Icon(
                      _currentIcon,
                      key: ValueKey<int>(_iconIndex),
                      size: 32, color: cat.color,
                    ),
                  ),
                ),
              ),
            ),
          ]),
          // Tap hint arrow
          Positioned(
            bottom: 0, right: 0,
            child: Icon(Icons.arrow_forward_ios_rounded,
                size: 10, color: cat.color.withValues(alpha: 0.5)),
          ),
        ]),
      ),
    );
  }
}

// ================================================================
// CATEGORY MODAL BOTTOM SHEET
// ================================================================
class _CategoryModal extends StatefulWidget {
  final _ServiceCategory category;
  const _CategoryModal({required this.category});

  @override
  State<_CategoryModal> createState() => _CategoryModalState();
}

class _CategoryModalState extends State<_CategoryModal> {
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _issueCtrl   = TextEditingController();
  final _formKey     = GlobalKey<FormState>();
  bool _sending      = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _issueCtrl.dispose();
    super.dispose();
  }

  Future<void> _sendWhatsApp() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    setState(() => _sending = true);

    final name    = _nameCtrl.text.trim();
    final phone   = _phoneCtrl.text.trim();
    final issue   = _issueCtrl.text.trim();
    final service = widget.category.title;

    final message = '''🚨 *New NJ Tech Enquiry*

*Customer Name:* $name
*Phone:* $phone
*Device/Service:* $service
*Issue:* $issue

_Please contact me regarding this service._''';

    final encoded = Uri.encodeComponent(message);
    final uri = Uri.parse('https://wa.me/$_kNJWhatsApp?text=$encoded');

    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('WhatsApp not installed. Trying browser...'),
              backgroundColor: _kGold,
            ),
          );
          final webUri = Uri.parse(
              'https://api.whatsapp.com/send?phone=$_kNJWhatsApp&text=$encoded');
          await launchUrl(webUri, mode: LaunchMode.externalApplication);
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Unable to open WhatsApp: $e'),
            backgroundColor: _kRed,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _callNow() async {
    final uri = Uri.parse('tel:$_kNJPhone');
    if (await canLaunchUrl(uri)) await launchUrl(uri);
  }

  @override
  Widget build(BuildContext context) {
    final cat = widget.category;
    final bottom = MediaQuery.viewInsetsOf(context).bottom;

    return Container(
      margin: EdgeInsets.only(
          left: 12, right: 12, top: 60, bottom: bottom + 12),
      decoration: BoxDecoration(
        color: _kBg,
        borderRadius: BorderRadius.circular(28),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.18),
            blurRadius: 40, offset: const Offset(0, -8),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(28),
        child: SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: Column(mainAxisSize: MainAxisSize.min, children: [

            // ── Modal Header ────────────────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [_kNJDark, cat.color.withValues(alpha: 0.8)],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start, children: [
                // Drag handle
                Center(
                  child: Container(
                    width: 40, height: 4,
                    margin: const EdgeInsets.only(bottom: 16),
                    decoration: BoxDecoration(
                      color: Colors.white30,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(children: [
                  Container(
                    width: 52, height: 52,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Icon(cat.icon, color: Colors.white, size: 28),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(cat.title,
                        style: GoogleFonts.outfit(
                            color: Colors.white, fontSize: 20,
                            fontWeight: FontWeight.w900)),
                    Text(cat.subtitle,
                        style: GoogleFonts.outfit(
                            color: Colors.white70, fontSize: 11)),
                  ])),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 18),
                    ),
                  ),
                ]),
              ]),
            ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(children: [

                // ── Call Button ──────────────────────────────────
                GestureDetector(
                  onTap: _callNow,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                          colors: [_kGreen, Color(0xFF009624)]),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                        color: _kGreen.withValues(alpha: 0.35),
                        blurRadius: 14, offset: const Offset(0, 5),
                      )],
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Icon(Icons.phone_rounded,
                          color: Colors.white, size: 20),
                      const SizedBox(width: 10),
                      Text('Call for Enquiry / Booking',
                          style: GoogleFonts.outfit(
                              color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w800)),
                    ]),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Divider ──────────────────────────────────────
                Row(children: [
                  const Expanded(child: Divider(color: _kBorder)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or send enquiry via WhatsApp',
                        style: GoogleFonts.outfit(
                            color: _kMuted, fontSize: 11)),
                  ),
                  const Expanded(child: Divider(color: _kBorder)),
                ]),

                const SizedBox(height: 16),

                // ── Enquiry Form ─────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(children: [

                    // Service (auto-filled display)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: cat.color.withValues(alpha: 0.25)),
                      ),
                      child: Row(children: [
                        Icon(cat.icon, color: cat.color, size: 18),
                        const SizedBox(width: 8),
                        Text('Service: ${cat.title}',
                            style: GoogleFonts.outfit(
                                color: cat.color, fontSize: 13,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: cat.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Auto',
                              style: GoogleFonts.outfit(
                                  color: cat.color, fontSize: 8,
                                  fontWeight: FontWeight.w800)),
                        ),
                      ]),
                    ),

                    const SizedBox(height: 12),

                    // Name field
                    _FormField(
                      controller: _nameCtrl,
                      hint: 'Your Name',
                      icon: Icons.person_outline_rounded,
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Please enter your name' : null,
                    ),

                    const SizedBox(height: 10),

                    // Phone field
                    _FormField(
                      controller: _phoneCtrl,
                      hint: 'Phone Number',
                      icon: Icons.phone_outlined,
                      keyboardType: TextInputType.phone,
                      inputFormatters: [
                        FilteringTextInputFormatter.digitsOnly,
                        LengthLimitingTextInputFormatter(10),
                      ],
                      validator: (v) {
                        final val = v?.trim() ?? '';
                        if (val.isEmpty) return 'Please enter phone number';
                        if (val.length < 10) return 'Enter valid 10-digit number';
                        return null;
                      },
                    ),

                    const SizedBox(height: 10),

                    // Issue field
                    TextFormField(
                      controller: _issueCtrl,
                      maxLines: 3,
                      style: GoogleFonts.outfit(
                          color: _kText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Describe your issue or service needed...',
                        hintStyle: GoogleFonts.outfit(
                            color: _kMuted, fontSize: 13),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.edit_note_rounded,
                              color: _kMuted, size: 20),
                        ),
                        filled: true,
                        fillColor: _kSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(
                              color: cat.color.withValues(alpha: 0.5)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14),
                      ),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Please describe your issue' : null,
                    ),

                    const SizedBox(height: 16),

                    // WhatsApp Submit Button
                    GestureDetector(
                      onTap: _sending ? null : _sendWhatsApp,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _sending
                                ? [_kMuted, _kMuted]
                                : [const Color(0xFF25D366),
                                   const Color(0xFF128C7E)],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _sending ? [] : [
                            BoxShadow(
                              color: const Color(0xFF25D366)
                                  .withValues(alpha: 0.4),
                              blurRadius: 14,
                              offset: const Offset(0, 5),
                            ),
                          ],
                        ),
                        child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                          if (_sending)
                            const SizedBox(
                              width: 20, height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2),
                            )
                          else ...[
                            const Icon(Icons.send_rounded,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text('Send Enquiry on WhatsApp',
                                style: GoogleFonts.outfit(
                                    color: Colors.white, fontSize: 14,
                                    fontWeight: FontWeight.w800)),
                          ],
                        ]),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      'Your enquiry will be sent to NJ Tech via WhatsApp',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: _kMuted, fontSize: 10),
                    ),
                  ]),
                ),
              ]),
            ),
          ]),
        ),
      ),
    );
  }
}

// ================================================================
// REUSABLE FORM FIELD
// ================================================================
class _FormField extends StatelessWidget {
  final TextEditingController controller;
  final String hint;
  final IconData icon;
  final TextInputType? keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final String? Function(String?)? validator;

  const _FormField({
    required this.controller,
    required this.hint,
    required this.icon,
    this.keyboardType,
    this.inputFormatters,
    this.validator,
  });

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: controller,
      keyboardType: keyboardType,
      inputFormatters: inputFormatters,
      style: GoogleFonts.outfit(color: _kText, fontSize: 14),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: GoogleFonts.outfit(color: _kMuted, fontSize: 13),
        prefixIcon: Icon(icon, color: _kMuted, size: 20),
        filled: true,
        fillColor: _kSurface,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kPink, width: 1.5),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: _kRed),
        ),
        contentPadding: const EdgeInsets.symmetric(
            horizontal: 14, vertical: 14),
      ),
      validator: validator,
    );
  }
}
