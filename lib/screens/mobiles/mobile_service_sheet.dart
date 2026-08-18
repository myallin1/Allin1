// ================================================================
// Mobile repair booking sheet
// ================================================================
// Collects phone + issue + pickup address, then creates a standard
// 'electronics_service' request with category 'mobile'. No new
// requestType — see mobile_service_tab.dart's header for why that
// matters in a live app.
// ================================================================

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../services/auth_prompt_service.dart';
import '../../services/auth_service.dart';
import '../../services/service_request_service.dart';
import '../../widgets/location_capture_field.dart';
import '../service_request_tracking_screen.dart';
import 'mobile_hub_screen.dart';

Future<void> showMobileServiceSheet(
  BuildContext context, {
  required String issueId,
  required String issueTitle,
}) {
  return showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (_) => _MobileServiceSheet(
      issueId: issueId,
      issueTitle: issueTitle,
    ),
  );
}

class _MobileServiceSheet extends StatefulWidget {
  final String issueId;
  final String issueTitle;

  const _MobileServiceSheet({required this.issueId, required this.issueTitle});

  @override
  State<_MobileServiceSheet> createState() => _MobileServiceSheetState();
}

class _MobileServiceSheetState extends State<_MobileServiceSheet> {
  final _phoneModelCtrl = TextEditingController();
  final _issueCtrl = TextEditingController();
  final _nameCtrl = TextEditingController();
  final _contactCtrl = TextEditingController();
  final _addressCtrl = TextEditingController();

  double? _lat;
  double? _lng;
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    _prefill();
  }

  Future<void> _prefill() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    _nameCtrl.text = user.displayName ?? '';
    try {
      final phone = await AuthService().resolveCustomerPhone(user);
      if (mounted && phone.isNotEmpty) _contactCtrl.text = phone;
    } catch (_) {
      // Prefill is a convenience only — a failure here just means the
      // customer types their number, never a blocked booking.
    }
  }

  @override
  void dispose() {
    _phoneModelCtrl.dispose();
    _issueCtrl.dispose();
    _nameCtrl.dispose();
    _contactCtrl.dispose();
    _addressCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (_phoneModelCtrl.text.trim().isEmpty) {
      _toast('Please enter your phone model');
      return;
    }
    if (_contactCtrl.text.trim().length < 10) {
      _toast('Please enter a valid contact number');
      return;
    }
    if (!await requireRealAuth(context,
        reason: 'Sign in to book a mobile repair')) {
      return;
    }
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !mounted) return;

    setState(() => _sending = true);
    try {
      final requestId = await ServiceRequestService().createServiceRequest(
        requestType: 'electronics_service',
        customerId: user.uid,
        customerName: _nameCtrl.text.trim().isNotEmpty
            ? _nameCtrl.text.trim()
            : (user.displayName ?? 'Customer'),
        customerPhone: _contactCtrl.text.trim(),
        details: <String, dynamic>{
          'category': 'mobile',
          'categoryLabel': 'Mobile',
          'intent': 'mobile_repair',
          'issueType': widget.issueId,
          'phoneModel': _phoneModelCtrl.text.trim(),
          'issue': '${widget.issueTitle} — ${_phoneModelCtrl.text.trim()}'
              '${_issueCtrl.text.trim().isEmpty ? '' : '\n${_issueCtrl.text.trim()}'}',
          if (_addressCtrl.text.trim().isNotEmpty)
            'address': _addressCtrl.text.trim(),
          if (_lat != null) 'locationLat': _lat,
          if (_lng != null) 'locationLng': _lng,
        },
      );

      if (!mounted) return;
      Navigator.pop(context);
      await Navigator.push(
        context,
        MaterialPageRoute<void>(
          builder: (_) => ServiceRequestTrackingScreen(
            requestId: requestId,
            requestType: 'electronics_service',
          ),
        ),
      );
    } catch (e) {
      if (mounted) _toast('Could not book: $e');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _toast(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: kMobRed),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom),
      child: DraggableScrollableSheet(
        initialChildSize: 0.85,
        minChildSize: 0.5,
        maxChildSize: 0.95,
        expand: false,
        builder: (context, scrollController) {
          return Container(
            decoration: const BoxDecoration(
              color: kMobBg,
              borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
            ),
            child: Column(
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.symmetric(vertical: 10),
                  decoration: BoxDecoration(
                    color: kMobBorder,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                Expanded(
                  child: ListView(
                    controller: scrollController,
                    padding: const EdgeInsets.fromLTRB(18, 4, 18, 18),
                    children: [
                      Text(
                        widget.issueTitle,
                        style: GoogleFonts.outfit(
                          color: kMobText,
                          fontSize: 19,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'A hero will collect your phone and bring it back after repair.',
                        style:
                            GoogleFonts.outfit(color: kMobMuted, fontSize: 12),
                      ),
                      const SizedBox(height: 18),
                      _field(_phoneModelCtrl, 'Phone model *',
                          'e.g. Redmi Note 13 5G'),
                      _field(_issueCtrl, 'Describe the problem',
                          'Optional — more detail helps us quote faster',
                          maxLines: 3),
                      _field(_nameCtrl, 'Your name', 'Optional'),
                      _field(_contactCtrl, 'Contact number *', '9XXXXXXXXX',
                          keyboard: TextInputType.phone),
                      const SizedBox(height: 4),
                      Text(
                        'Pickup address',
                        style: GoogleFonts.outfit(
                          color: kMobText,
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                      const SizedBox(height: 6),
                      LocationCaptureField(
                        addressController: _addressCtrl,
                        pickerTitle: 'Select pickup location',
                        accentColor: kMobPink,
                        onLocationPicked: (lat, lng) {
                          _lat = lat;
                          _lng = lng;
                        },
                      ),
                      const SizedBox(height: 22),
                      SizedBox(
                        width: double.infinity,
                        height: 50,
                        child: ElevatedButton(
                          style: ElevatedButton.styleFrom(
                            backgroundColor: kMobPink,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                            ),
                          ),
                          onPressed: _sending ? null : _submit,
                          child: _sending
                              ? const SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    color: Colors.white,
                                    strokeWidth: 2,
                                  ),
                                )
                              : Text(
                                  'Book Repair',
                                  style: GoogleFonts.outfit(
                                    color: Colors.white,
                                    fontSize: 15,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _field(
    TextEditingController ctrl,
    String label,
    String hint, {
    int maxLines = 1,
    TextInputType? keyboard,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: GoogleFonts.outfit(
              color: kMobText,
              fontSize: 12.5,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          TextField(
            controller: ctrl,
            maxLines: maxLines,
            keyboardType: keyboard,
            style: GoogleFonts.outfit(color: kMobText, fontSize: 14),
            decoration: InputDecoration(
              hintText: hint,
              hintStyle: GoogleFonts.outfit(color: kMobMuted, fontSize: 12.5),
              filled: true,
              fillColor: kMobSurface,
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kMobBorder),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kMobBorder),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: kMobPink),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
