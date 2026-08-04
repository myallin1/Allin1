// ================================================================
// nj_tech_store_screen.dart
// All In One Electronic Services — NJ Tech Store
// Premium Grid UI + Category Modal + WhatsApp Enquiry
// ================================================================

import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';

import '../services/service_request_cache_service.dart';
import '../services/service_request_service.dart';
import '../utils/service_request_labels.dart';
import '../widgets/location_capture_field.dart';
import 'service_request_tracking_screen.dart';

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

// NJ Tech contact number (used for the direct "Call Now" actions —
// the enquiry form itself now goes through the Broadcast Order System
// instead of a WhatsApp deep link; see _submitRequest()).
const String _kNJPhone = '+919597879191';

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
// MAIN SCREEN — now a Scaffold with its own bottom nav (Book /
// Status), matching dashboard_screen.dart's _buildBottomNav style
// exactly (Row of InkWell icon+label items, easy to extend with more
// tabs later — same convention as the main app's 5-item bottom bar).
// ================================================================
class NJTechStoreScreen extends StatefulWidget {
  const NJTechStoreScreen({super.key});

  @override
  State<NJTechStoreScreen> createState() => _NJTechStoreScreenState();
}

class _NJTechStoreScreenState extends State<NJTechStoreScreen> {
  int _tabIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _kBg,
      body: IndexedStack(
        index: _tabIndex,
        children: [
          _buildBookTab(context),
          _buildStatusTab(context),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ── Bottom Nav — 2 items today (Book / Status), same visual
  // convention as dashboard_screen.dart's _buildBottomNav so this page
  // reads as part of the same app. The `items` list is written so
  // adding a 3rd tab later (e.g. "Warranty") is a one-line addition.
  Widget _buildBottomNav() {
    const items = [
      {'icon': Icons.grid_view_rounded, 'label': 'Book'},
      {'icon': Icons.timeline_rounded, 'label': 'Status'},
    ];
    return DecoratedBox(
      decoration: BoxDecoration(
        color: _kBg,
        border: const Border(top: BorderSide(color: _kBorder)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 16,
              offset: const Offset(0, -4),),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: List.generate(items.length, (i) {
            final active = _tabIndex == i;
            final icon = items[i]['icon']! as IconData;
            final label = items[i]['label']! as String;
            return Expanded(
              child: InkWell(
                onTap: () => setState(() => _tabIndex = i),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    Icon(icon, color: active ? _kPink : _kMuted, size: 24),
                    const SizedBox(height: 3),
                    Text(label,
                        style: TextStyle(
                            fontSize: 9.5,
                            color: active ? _kPink : _kMuted,
                            fontWeight:
                                active ? FontWeight.w700 : FontWeight.w400,),),
                  ],),
                ),
              ),
            );
          }),
        ),
      ),
    );
  }

  // ── Book tab — the original category grid + banners, unchanged
  // content, just moved into its own tab body.
  Widget _buildBookTab(BuildContext context) {
    return CustomScrollView(
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
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
          sliver: SliverToBoxAdapter(child: _buildCallBanner(context)),
        ),
      ],
    );
  }

  // ── Status tab — full-page version of "My Enquiries": every
  // request this customer sent, newest first. Completed requests read
  // straight from ServiceRequestCacheService's local Hive cache with
  // NO Firestore listener attached (see _StatusEnquiryCard below) —
  // only requests still in progress stay on a live snapshot listener,
  // since only those can still change.
  Widget _buildStatusTab(BuildContext context) {
    return SafeArea(
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(),
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            sliver: SliverToBoxAdapter(
              child: Text('Service Status',
                  style: GoogleFonts.outfit(
                      color: _kText,
                      fontSize: 22,
                      fontWeight: FontWeight.w900,),),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 100),
            sliver: SliverToBoxAdapter(child: _buildMyEnquiries(context)),
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
            color: Colors.white, size: 20,),
        onPressed: () => Navigator.pop(context),
      ),
      flexibleSpace: FlexibleSpaceBar(
        background: DecoratedBox(
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
                          horizontal: 8, vertical: 3,),
                      decoration: BoxDecoration(
                        color: _kPink.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(
                            color: _kPink.withValues(alpha: 0.5),),
                      ),
                      child: Text('NJ TECH',
                          style: GoogleFonts.outfit(
                              color: _kPink,
                              fontSize: 9,
                              fontWeight: FontWeight.w900,
                              letterSpacing: 1.2,),),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3,),
                      decoration: BoxDecoration(
                        color: _kGreen.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        Container(
                          width: 5, height: 5,
                          decoration: const BoxDecoration(
                              color: _kGreen, shape: BoxShape.circle,),
                        ),
                        const SizedBox(width: 4),
                        Text('Open Now',
                            style: GoogleFonts.outfit(
                                color: _kGreen,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,),),
                      ],),
                    ),
                  ],),
                  const SizedBox(height: 8),
                  Text('All In One\nElectronic Services',
                      style: GoogleFonts.outfit(
                          color: Colors.white,
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          height: 1.2,),),
                  const SizedBox(height: 4),
                  Text('Erode · Sales · Service · Installation',
                      style: GoogleFonts.outfit(
                          color: Colors.white54, fontSize: 11,),),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ── My Enquiries ───────────────────────────────────────────────
  // Database-efficient by design:
  //  - COMPLETED requests: once this device has seen a request reach
  //    'completed', it's written to ServiceRequestCacheService's local
  //    Hive box (see _StatusEnquiryLive below) and every later render
  //    reads that cached copy — no Firestore listener stays attached
  //    to a request whose data will never change again.
  //  - IN-PROGRESS requests (pending/hero_assigned/in_progress/
  //    nearing_completion/admin_review): kept on a live Firestore
  //    listener, since only these can still change.
  // The two sources are combined into one list, newest first.
  Widget _buildMyEnquiries(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('My Enquiries',
            style: GoogleFonts.outfit(
                color: _kText, fontSize: 16, fontWeight: FontWeight.w800,),),
        const SizedBox(height: 12),
        _EnquiriesList(customerId: user.uid),
      ],
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
              color: _kPink, size: 26,),
        ),
        const SizedBox(width: 14),
        Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('Free Diagnosis for First Visit!',
              style: GoogleFonts.outfit(
                  color: _kText, fontSize: 13,
                  fontWeight: FontWeight.w800,),),
          const SizedBox(height: 2),
          Text('Tap any category to book or send an enquiry',
              style: GoogleFonts.outfit(
                  color: _kMuted, fontSize: 11,),),
        ],),),
      ],),
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
                fontSize: 15, fontWeight: FontWeight.w800, color: _kText,),),
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
                      color: _kText,),),
            ),
          ],),).toList(),
        ),
      ],),
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
                    fontWeight: FontWeight.w800,),),
            Text('+91 95978 79191 · Mon–Sat 9am–8pm',
                style: GoogleFonts.outfit(
                    color: Colors.white54, fontSize: 10,),),
          ],),),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: _kPink, borderRadius: BorderRadius.circular(12),),
            child: const Icon(Icons.arrow_forward_rounded,
                color: Colors.white, size: 18,),
          ),
        ],),
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_ServiceCategory>('category', category));
    properties.add(ObjectFlagProperty<VoidCallback>.has('onTap', onTap));
  }
}

class _CategoryTileState extends State<_CategoryTile>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  int _iconIndex = 0;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(seconds: 3),)
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
          ),],
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
                    ),],
                  ),
                  padding: const EdgeInsets.all(12),
                  child: AnimatedSwitcher(
                    duration: const Duration(milliseconds: 500),
                    transitionBuilder: (child, anim) => ScaleTransition(
                      scale: CurvedAnimation(
                          parent: anim, curve: Curves.elasticOut,),
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
          ],),
          // Tap hint arrow
          Positioned(
            bottom: 0, right: 0,
            child: Icon(Icons.arrow_forward_ios_rounded,
                size: 10, color: cat.color.withValues(alpha: 0.5),),
          ),
        ],),
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

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<_ServiceCategory>('category', category));
  }
}

class _CategoryModalState extends State<_CategoryModal> {
  final _nameCtrl    = TextEditingController();
  final _phoneCtrl   = TextEditingController();
  final _issueCtrl   = TextEditingController();
  final _formKey     = GlobalKey<FormState>();
  // NEW (per Nizam's request): pickup/inspection location, same
  // Use-My-Location + Select-on-Map pattern as every other order form.
  final _addressCtrl = TextEditingController();
  double? _addressLat;
  double? _addressLng;
  bool _sending      = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _phoneCtrl.dispose();
    _issueCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  // Submits the enquiry as a real service_requests doc (same Broadcast
  // Order System used by Hero Booking / Food / Grocery — see
  // service_request_service.dart) instead of launching a visible
  // wa.me link. The category the customer tapped (widget.category) is
  // carried straight into `details.category` — the customer never has
  // to re-select it. After creation, this pushes into
  // ServiceRequestTrackingScreen, the SAME graphical step tracker
  // Hero Booking and Food Genie already use, requestType:
  // 'electronics_service'.
  //
  // NOTE: sending an admin-side WhatsApp/push alert for this request
  // type is a separate, not-yet-built piece (needs either a WhatsApp
  // Business API/Twilio account, or an admin FCM push — neither exists
  // in this codebase yet). For now the request simply appears in the
  // admin dashboard's live service_requests list like every other
  // Broadcast Order System request.
  Future<void> _submitRequest() async {
    if (!(_formKey.currentState?.validate() ?? false)) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Please sign in to send an enquiry.'),
            backgroundColor: _kRed,
          ),
        );
      }
      return;
    }

    setState(() => _sending = true);

    final name  = _nameCtrl.text.trim();
    final phone = _phoneCtrl.text.trim();
    final issue = _issueCtrl.text.trim();

    try {
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'electronics_service',
        customerId: user.uid,
        customerName: name.isNotEmpty ? name : (user.displayName ?? 'Customer'),
        customerPhone: phone.isNotEmpty ? phone : (user.phoneNumber ?? ''),
        details: {
          'category': widget.category.id,
          'categoryLabel': widget.category.title,
          'issue': issue,
          if (_addressCtrl.text.trim().isNotEmpty)
            'address': _addressCtrl.text.trim(),
          if (_addressLat != null) 'locationLat': _addressLat,
          if (_addressLng != null) 'locationLng': _addressLng,
        },
      );

      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'electronics_service',
          ),
        ),
      );
      if (mounted) Navigator.pop(context); // close this bottom sheet
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to send enquiry: $e'),
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
          left: 12, right: 12, top: 60, bottom: bottom + 12,),
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
                            fontWeight: FontWeight.w900,),),
                    Text(cat.subtitle,
                        style: GoogleFonts.outfit(
                            color: Colors.white70, fontSize: 11,),),
                  ],),),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      width: 32, height: 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.close_rounded,
                          color: Colors.white70, size: 18,),
                    ),
                  ),
                ],),
              ],),
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
                          colors: [_kGreen, Color(0xFF009624)],),
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [BoxShadow(
                        color: _kGreen.withValues(alpha: 0.35),
                        blurRadius: 14, offset: const Offset(0, 5),
                      ),],
                    ),
                    child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                      const Icon(Icons.phone_rounded,
                          color: Colors.white, size: 20,),
                      const SizedBox(width: 10),
                      Text('Call for Enquiry / Booking',
                          style: GoogleFonts.outfit(
                              color: Colors.white, fontSize: 14,
                              fontWeight: FontWeight.w800,),),
                    ],),
                  ),
                ),

                const SizedBox(height: 16),

                // ── Divider ──────────────────────────────────────
                Row(children: [
                  const Expanded(child: Divider(color: _kBorder)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    child: Text('or send an enquiry',
                        style: GoogleFonts.outfit(
                            color: _kMuted, fontSize: 11,),),
                  ),
                  const Expanded(child: Divider(color: _kBorder)),
                ],),

                const SizedBox(height: 16),

                // ── Enquiry Form ─────────────────────────────────
                Form(
                  key: _formKey,
                  child: Column(children: [

                    // Service (auto-filled display)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 12,),
                      decoration: BoxDecoration(
                        color: cat.color.withValues(alpha: 0.08),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: cat.color.withValues(alpha: 0.25),),
                      ),
                      child: Row(children: [
                        Icon(cat.icon, color: cat.color, size: 18),
                        const SizedBox(width: 8),
                        Text('Service: ${cat.title}',
                            style: GoogleFonts.outfit(
                                color: cat.color, fontSize: 13,
                                fontWeight: FontWeight.w700,),),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 6, vertical: 2,),
                          decoration: BoxDecoration(
                            color: cat.color.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text('Auto',
                              style: GoogleFonts.outfit(
                                  color: cat.color, fontSize: 8,
                                  fontWeight: FontWeight.w800,),),
                        ),
                      ],),
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
                          color: _kText, fontSize: 14,),
                      decoration: InputDecoration(
                        hintText: 'Describe your issue or service needed...',
                        hintStyle: GoogleFonts.outfit(
                            color: _kMuted, fontSize: 13,),
                        prefixIcon: const Padding(
                          padding: EdgeInsets.only(bottom: 40),
                          child: Icon(Icons.edit_note_rounded,
                              color: _kMuted, size: 20,),
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
                              color: cat.color.withValues(alpha: 0.5),),
                        ),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 14,),
                      ),
                      validator: (v) => (v?.trim().isEmpty ?? true)
                          ? 'Please describe your issue' : null,
                    ),

                    const SizedBox(height: 10),

                    // Pickup/inspection address — NEW (per Nizam's
                    // request): this form previously collected zero
                    // location data, so a hero assigned to pick up the
                    // device or inspect it on-site had nowhere to
                    // navigate to. Optional (not validated) since some
                    // enquiries are drop-off-at-shop only.
                    TextFormField(
                      controller: _addressCtrl,
                      maxLines: 2,
                      style: GoogleFonts.outfit(color: _kText, fontSize: 14),
                      decoration: InputDecoration(
                        hintText: 'Pickup / inspection address (optional)',
                        hintStyle: GoogleFonts.outfit(color: _kMuted, fontSize: 13),
                        filled: true,
                        fillColor: _kSurface,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide.none,
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                      ),
                    ),
                    const SizedBox(height: 8),
                    LocationCaptureField(
                      addressController: _addressCtrl,
                      pickerTitle: 'Pickup / inspection location',
                      accentColor: cat.color,
                      onLocationPicked: (lat, lng) {
                        setState(() {
                          _addressLat = lat;
                          _addressLng = lng;
                        });
                      },
                    ),

                    const SizedBox(height: 16),

                    // Submit Button — creates a trackable service request
                    GestureDetector(
                      onTap: _sending ? null : _submitRequest,
                      child: Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: _sending
                                ? [_kMuted, _kMuted]
                                : [_kPink, _kPinkDark],
                          ),
                          borderRadius: BorderRadius.circular(14),
                          boxShadow: _sending ? [] : [
                            BoxShadow(
                              color: _kPink.withValues(alpha: 0.4),
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
                                  color: Colors.white, strokeWidth: 2,),
                            )
                          else ...[
                            const Icon(Icons.send_rounded,
                                color: Colors.white, size: 20,),
                            const SizedBox(width: 10),
                            Text('Send Enquiry',
                                style: GoogleFonts.outfit(
                                    color: Colors.white, fontSize: 14,
                                    fontWeight: FontWeight.w800,),),
                          ],
                        ],),
                      ),
                    ),

                    const SizedBox(height: 8),
                    Text(
                      "Track your request's progress right after submitting",
                      textAlign: TextAlign.center,
                      style: GoogleFonts.outfit(
                          color: _kMuted, fontSize: 10,),
                    ),
                  ],),
                ),
              ],),
            ),
          ],),
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
            horizontal: 14, vertical: 14,),
      ),
      validator: validator,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<TextEditingController>('controller', controller));
    properties.add(StringProperty('hint', hint));
    properties.add(DiagnosticsProperty<IconData>('icon', icon));
    properties.add(DiagnosticsProperty<TextInputType?>('keyboardType', keyboardType));
    properties.add(IterableProperty<TextInputFormatter>('inputFormatters', inputFormatters));
    properties.add(ObjectFlagProperty<String? Function(String?)?>.has('validator', validator));
  }
}

// ================================================================
// _EnquiriesList — merges cached-completed + live in-progress
// requests. Terminal statuses ('completed') never listen on
// Firestore beyond confirming the terminal state once; everything
// else stays live. See ServiceRequestCacheService for the local
// storage layer this reads/writes.
// ================================================================
class _EnquiriesList extends StatefulWidget {
  final String customerId;
  const _EnquiriesList({required this.customerId});

  @override
  State<_EnquiriesList> createState() => _EnquiriesListState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('customerId', customerId));
  }
}

class _EnquiriesListState extends State<_EnquiriesList> {
  // One-time discovery query (not a live listener) — finds every
  // electronics_service request id this customer has ever sent, plus
  // that request's status as of right now. Requests already known
  // completed (in the Hive cache) skip straight to the cached render
  // path below and never get a live listener attached; requests NOT
  // yet completed get one via _LiveEnquiryCard.
  late Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _discoverFuture;

  @override
  void initState() {
    super.initState();
    _discoverFuture = _discover();
  }

  Future<List<QueryDocumentSnapshot<Map<String, dynamic>>>> _discover() async {
    final snapshot = await FirebaseFirestore.instance
        .collection('service_requests')
        .where('customerId', isEqualTo: widget.customerId)
        .where('requestType', isEqualTo: 'electronics_service')
        .orderBy('createdAt', descending: true)
        .get();
    return snapshot.docs;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<QueryDocumentSnapshot<Map<String, dynamic>>>>(
      future: _discoverFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(
                child: CircularProgressIndicator(color: _kPink, strokeWidth: 2),),
          );
        }
        if (snapshot.hasError) {
          return const Text('Could not load your enquiries.',
              style: TextStyle(color: _kMuted, fontSize: 12),);
        }
        final docs = snapshot.data ?? [];
        if (docs.isEmpty) {
          return Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _kSurface,
              borderRadius: BorderRadius.circular(16),
            ),
            child: const Text(
              'No enquiries yet. Tap any category above to send one! 🔧',
              style: TextStyle(color: _kMuted, fontSize: 13),
            ),
          );
        }
        return ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, i) => _EnquiryCardRouter(doc: docs[i]),
        );
      },
    );
  }
}

// Decides, per request, whether to render from the permanent local
// cache (completed — zero Firestore reads) or attach a live listener
// (still in progress — status can still change).
class _EnquiryCardRouter extends StatefulWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  const _EnquiryCardRouter({required this.doc});

  @override
  State<_EnquiryCardRouter> createState() => _EnquiryCardRouterState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(DiagnosticsProperty<QueryDocumentSnapshot<Map<String, dynamic>>>('doc', doc));
  }
}

class _EnquiryCardRouterState extends State<_EnquiryCardRouter> {
  late Future<Map<String, dynamic>?> _cachedFuture;

  @override
  void initState() {
    super.initState();
    _cachedFuture =
        ServiceRequestCacheService().getCachedRequest(widget.doc.id);
  }

  @override
  Widget build(BuildContext context) {
    final initialData = widget.doc.data();
    final initialStatus = initialData['status'] as String? ?? 'pending';

    return FutureBuilder<Map<String, dynamic>?>(
      future: _cachedFuture,
      builder: (context, snapshot) {
        final cached = snapshot.data;
        if (cached != null) {
          // Already cached as completed on this device — render
          // straight from Hive, no Firestore listener at all.
          return _EnquiryCardView(
            requestId: widget.doc.id,
            data: cached,
            fromCache: true,
          );
        }
        if (initialStatus == 'completed') {
          // Completed (seen via the discovery query) but not cached
          // yet on this device (e.g. completed on another device, or
          // the cache write below hasn't finished) — cache it now so
          // future opens skip Firestore entirely for this request.
          unawaited(ServiceRequestCacheService()
              .cacheCompletedRequest(widget.doc.id, _withMillis(initialData)),);
          return _EnquiryCardView(
            requestId: widget.doc.id,
            data: initialData,
            fromCache: false,
          );
        }
        // Still in progress — live listener, since status can change.
        return _LiveEnquiryCard(requestId: widget.doc.id, initialData: initialData);
      },
    );
  }
}

// Live Firestore listener — used ONLY while a request has not yet
// reached 'completed'. The instant it does, this widget performs the
// single write into ServiceRequestCacheService (the "same time as
// completion" write Nizam asked for) and from then on this specific
// request never needs another Firestore read.
class _LiveEnquiryCard extends StatefulWidget {
  final String requestId;
  final Map<String, dynamic> initialData;
  const _LiveEnquiryCard({required this.requestId, required this.initialData});

  @override
  State<_LiveEnquiryCard> createState() => _LiveEnquiryCardState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('initialData', initialData));
  }
}

class _LiveEnquiryCardState extends State<_LiveEnquiryCard> {
  bool _cachedOnce = false;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('service_requests')
          .doc(widget.requestId)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() ?? widget.initialData;
        final status = data['status'] as String? ?? 'pending';

        if (status == 'completed' && !_cachedOnce) {
          _cachedOnce = true;
          // Fires exactly once, right as this device first observes
          // completion — the same moment triggers both the UI update
          // (this StreamBuilder rebuild) and the local Hive write.
          unawaited(ServiceRequestCacheService()
              .cacheCompletedRequest(widget.requestId, _withMillis(data)),);
        }

        return _EnquiryCardView(
          requestId: widget.requestId,
          data: data,
          fromCache: false,
        );
      },
    );
  }
}

// Pure rendering widget — identical look whether the data came from
// Firestore or the local cache.
class _EnquiryCardView extends StatelessWidget {
  final String requestId;
  final Map<String, dynamic> data;
  final bool fromCache;
  const _EnquiryCardView({
    required this.requestId,
    required this.data,
    required this.fromCache,
  });

  @override
  Widget build(BuildContext context) {
    final details = (data['details'] as Map)
        .map((k, v) => MapEntry(k.toString(), v));
    final categoryLabel = (details['categoryLabel'] as String?)?.trim();
    final issue = (details['issue'] as String?)?.trim();
    final status = (data['status'] as String?) ?? 'pending';
    final statusColor = serviceRequestStatusColor(status);
    final statusLabel = serviceRequestStatusLabel('electronics_service', status);

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'electronics_service',
          ),
        ),
      ),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _kSurface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _kBorder),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    (categoryLabel != null && categoryLabel.isNotEmpty)
                        ? categoryLabel
                        : 'Electronics enquiry',
                    style: GoogleFonts.outfit(
                        color: _kText, fontSize: 14, fontWeight: FontWeight.w700,),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (issue != null && issue.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    Text(
                      issue,
                      style: const TextStyle(color: _kMuted, fontSize: 12),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: statusColor.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                statusLabel,
                style: TextStyle(
                    color: statusColor, fontSize: 11, fontWeight: FontWeight.w700,),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('requestId', requestId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
    properties.add(DiagnosticsProperty<bool>('fromCache', fromCache));
  }
}

/// Converts Firestore Timestamp fields to plain epoch-millis ints
/// before handing the map to ServiceRequestCacheService, which stores
/// it in Hive (Timestamps don't survive Hive's binary serialization).
Map<String, dynamic> _withMillis(Map<String, dynamic> data) {
  final result = Map<String, dynamic>.from(data);
  for (final key in ['createdAt', 'updatedAt']) {
    final value = result[key];
    if (value is Timestamp) {
      result['${key}Ms'] = value.millisecondsSinceEpoch;
      result.remove(key);
    }
  }
  if (result['createdAtMs'] == null) {
    result['createdAtMs'] = DateTime.now().millisecondsSinceEpoch;
  }
  return result;
}
