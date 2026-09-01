import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../config/hero_skill_catalog.dart';
import '../../widgets/cached_cloud_image.dart';
import '../../services/cloudinary_upload_service.dart';

const _bg = Color(0xFF121212);
const _surface = Color(0xFF1E1E1E);
const _text = Colors.white;
const _muted = Color(0xFF9E9E9E);
const _pink = Color(0xFFFF4FA3);
const _green = Color(0xFF00C853);
const _red = Color(0xFFFF5252);

class AdminHeroDetailsScreen extends StatelessWidget {
  final String uid;
  final Map<String, dynamic> data;
  final VoidCallback onApprove;
  final VoidCallback onReject;
  final VoidCallback onCall;
  final String Function(String) getCityLabel;

  const AdminHeroDetailsScreen({
    super.key,
    required this.uid,
    required this.data,
    required this.onApprove,
    required this.onReject,
    required this.onCall,
    required this.getCityLabel,
  });

  String _val(String key, [String fallback = 'N/A']) {
    final val = data[key];
    if (val == null || val.toString().trim().isEmpty) return fallback;
    return val.toString();
  }

  List<String> get _skills => heroSkillsOf(data);

  void _showFullImage(BuildContext context, String label, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        backgroundColor: Colors.black,
        insetPadding: EdgeInsets.zero,
        child: Stack(
          fit: StackFit.expand,
          children: [
            InteractiveViewer(
              child: CachedCloudImage(
                // Do not optimize, admin needs high-res for verification
                url,
                fit: BoxFit.contain,
              ),
            ),
            Positioned(
              top: 40,
              left: 16,
              child: IconButton(
                icon: const Icon(Icons.close, color: Colors.white, size: 32),
                onPressed: () => Navigator.pop(ctx),
              ),
            ),
            Positioned(
              bottom: 40,
              left: 0,
              right: 0,
              child: Text(
                label,
                textAlign: TextAlign.center,
                style: GoogleFonts.outfit(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFieldRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(label, style: GoogleFonts.outfit(color: _muted, fontSize: 13, fontWeight: FontWeight.w500)),
          ),
          Expanded(
            flex: 3,
            child: Text(value, style: GoogleFonts.outfit(color: _text, fontSize: 14, fontWeight: FontWeight.w600)),
          ),
        ],
      ),
    );
  }

  Widget _buildDocumentCard(BuildContext context, String label, String numberLabel, String numberValue, String urlKey) {
    final url = data[urlKey] as String?;
    final hasPhoto = url != null && url.isNotEmpty;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _muted.withValues(alpha: 0.1)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(label, style: GoogleFonts.outfit(color: _text, fontSize: 16, fontWeight: FontWeight.bold)),
                if (numberValue != 'N/A' && numberValue.isNotEmpty)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _pink.withValues(alpha: 0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      numberValue,
                      style: GoogleFonts.outfit(color: _pink, fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                  ),
              ],
            ),
          ),
          if (hasPhoto)
            GestureDetector(
              onTap: () => _showFullImage(context, label, url),
              child: ClipRRect(
                borderRadius: const BorderRadius.only(bottomLeft: Radius.circular(16), bottomRight: Radius.circular(16)),
                child: SizedBox(
                  width: double.infinity,
                  height: 200,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CachedCloudImage(
                        CloudinaryUploadService.optimizedUrl(url, width: 600),
                        fit: BoxFit.cover,
                      ),
                      Positioned(
                        bottom: 8,
                        right: 8,
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black.withValues(alpha: 0.7),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(Icons.zoom_in, color: Colors.white, size: 20),
                        ),
                      )
                    ],
                  ),
                ),
              ),
            )
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: _muted.withValues(alpha: 0.2), style: BorderStyle.solid),
                ),
                child: Center(
                  child: Column(
                    children: [
                      const Icon(Icons.image_not_supported_rounded, color: _muted, size: 32),
                      const SizedBox(height: 8),
                      Text('No photo uploaded', style: GoogleFonts.outfit(color: _muted, fontSize: 12)),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final selfieUrl = data['selfieUrl'] as String?;
    final hasSelfie = selfieUrl != null && selfieUrl.isNotEmpty;

    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios_new, color: _text, size: 18),
          onPressed: () => Navigator.pop(context),
        ),
        title: Text('Hero Verification', style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.bold, fontSize: 18)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Header Profile Section
            Center(
              child: GestureDetector(
                onTap: hasSelfie ? () => _showFullImage(context, 'Live Selfie', selfieUrl) : null,
                child: Container(
                  width: 120,
                  height: 120,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    border: Border.all(color: _pink, width: 3),
                    // FIX (Aug 18 2026 bandwidth audit): raw NetworkImage
                    // re-downloaded this hero's selfie from Cloudinary
                    // every time admin opened their profile — every
                    // re-review during the same approval, every repeat
                    // visit. CachedNetworkImageProvider is the same
                    // disk-persistent cache CachedCloudImage uses
                    // elsewhere in this screen, so a hero's selfie now
                    // costs Cloudinary bandwidth exactly once.
                    image: hasSelfie
                        ? DecorationImage(
                            image: CachedNetworkImageProvider(
                              CloudinaryUploadService.optimizedUrl(selfieUrl, width: 256),
                            ),
                            fit: BoxFit.cover,
                          )
                        : null,
                  ),
                  child: !hasSelfie ? const Icon(Icons.person, size: 50, color: _muted) : null,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              _val('name'),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _text, fontSize: 24, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 4),
            Text(
              _val('phone'),
              textAlign: TextAlign.center,
              style: GoogleFonts.outfit(color: _muted, fontSize: 16),
            ),
            const SizedBox(height: 16),
            Center(
              child: ElevatedButton.icon(
                onPressed: onCall,
                icon: const Icon(Icons.call, color: Colors.white, size: 18),
                label: const Text('Call Hero'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: _pink,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
                  textStyle: GoogleFonts.outfit(fontWeight: FontWeight.bold),
                ),
              ),
            ),
            const SizedBox(height: 32),

            // Personal & Vehicle Info Section
            Text('REGISTRATION DETAILS', style: GoogleFonts.outfit(color: _muted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _surface,
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                children: [
                  _buildFieldRow('Email', _val('email')),
                  const Divider(color: Colors.black26),
                  // FIX (Aug 29 2026 — Nizam: "admin ku send pannavendiya
                  // proof and needed column mis aagirukku"). dob and
                  // address are mandatory on the registration form — a
                  // hero cannot submit without them — but this, admin's
                  // own full-KYC review screen, never showed either.
                  _buildFieldRow('Date of Birth', _val('dob')),
                  const Divider(color: Colors.black26),
                  _buildFieldRow('Address', _val('address')),
                  const Divider(color: Colors.black26),
                  _buildFieldRow('City', getCityLabel(_val('city', 'erode'))),
                  const Divider(color: Colors.black26),
                  _buildFieldRow('Preferred Area', _val('preferredWorkLocation', 'Anywhere')),
                  const Divider(color: Colors.black26),
                  // SKILL HEROES (Aug 29 2026, found on re-audit). A trade
                  // applicant's own vehicleType is literally the
                  // placeholder 'skill_worker' (see hero_skill_catalog.dart
                  // — that value exists so ride dispatch never matches
                  // it), so showing it here read as a data-entry error
                  // rather than the deliberate value it is. Showing the
                  // actual trades instead is what admin needs to approve
                  // an electrician correctly.
                  if (_skills.isNotEmpty) ...[
                    _buildFieldRow(
                      'Trades',
                      _skills.map(heroSkillLabel).join(', '),
                    ),
                  ] else ...[
                    _buildFieldRow('Vehicle Type', _val('vehicleType')),
                    const Divider(color: Colors.black26),
                    _buildFieldRow('Vehicle No.', _val('vehicleNumber')),
                  ],
                  const Divider(color: Colors.black26),
                  _buildFieldRow('Onboarding', _val('onboardingMethod')),
                ],
              ),
            ),
            const SizedBox(height: 32),

            // KYC Documents Section
            Text('KYC DOCUMENTS', style: GoogleFonts.outfit(color: _muted, fontSize: 12, fontWeight: FontWeight.bold, letterSpacing: 1.2)),
            const SizedBox(height: 12),
            _buildDocumentCard(context, 'Aadhaar Card', 'Aadhaar No.', _val('aadhaarNumber'), 'aadhaarDocUrl'),
            _buildDocumentCard(context, 'PAN Card', 'PAN No.', _val('panNumber'), 'panDocUrl'),
            // Skill heroes never upload one — the registration form
            // doesn't even ask (see hero_register_screen.dart). Showing
            // an always-empty "Driving License: N/A" card here made a
            // correctly-submitted electrician application look
            // incomplete.
            if (_skills.isEmpty)
              _buildDocumentCard(context, 'Driving License', 'License No.', _val('licenseNumber'), 'licenseDocUrl'),
          ],
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerDocked,
      floatingActionButton: (data['approvalStatus'] == 'pending')
          ? Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: _bg,
                boxShadow: [
                  BoxShadow(color: Colors.black.withValues(alpha: 0.5), blurRadius: 10, offset: const Offset(0, -5)),
                ],
              ),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onReject();
                      },
                      style: OutlinedButton.styleFrom(
                        side: const BorderSide(color: _red, width: 2),
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                      child: Text('Reject', style: GoogleFonts.outfit(color: _red, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        onApprove();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _green,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 0,
                      ),
                      child: Text('Approve', style: GoogleFonts.outfit(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            )
          : null,
    );
  }
}
