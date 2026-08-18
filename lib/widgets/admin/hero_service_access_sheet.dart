// ================================================================
// hero_service_access_sheet.dart — admin per-hero work permissions
// ================================================================
// NEW (Aug 17 2026 — Nizam: "some heros correcta 3 work kum pappanga...
// avanga service accept ah particular serviceko ila full service um
// atten pannamudiyama pandrathuku access irukanum apo than avanga work
// pannuna atha control pannamudiyum").
//
// One bottom sheet, opened from the approved-heroes list, with a switch
// per service bucket. Writes heroes/{uid}.serviceAccess — see
// lib/config/hero_service_access.dart for the model and for why an
// absent key means "allowed".
//
// Writes an EXPLICIT true/false for every bucket, not just the denials.
//
// The first cut of this file wrote only the `false` entries, on the
// reasoning that an untouched hero should keep an entirely absent field.
// That was wrong in one important case Nizam spotted immediately: an
// auto/cab hero can never be GRANTED parcel work that way. Absent
// already reads as "allowed", so an absent key cannot distinguish
// "nobody has decided" from "admin said yes" — and parcel dispatch needs
// exactly that distinction, because the vehicle-category rules only ever
// hand parcel jobs to bike heroes on their own. See
// isServiceExplicitlyGranted() in config/hero_service_access.dart.
//
// Heroes nobody has ever opened this sheet for still have no field at
// all, so the feature remains invisible until an admin uses it.
// ================================================================
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../config/hero_service_access.dart';

const Color _surface = Color(0xFF141420);
const Color _text = Color(0xFFEEEEF5);
const Color _muted = Color(0xFF7777A0);
const Color _green = Color(0xFF00C853);
const Color _red = Color(0xFFFF5252);
const Color _border = Color(0x1AFFFFFF);

/// Opens the editor for [uid]. [heroData] is the hero's current Firestore
/// document map, used to seed the switches.
Future<void> showHeroServiceAccessSheet(
  BuildContext context, {
  required String uid,
  required Map<String, dynamic> heroData,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => _HeroServiceAccessSheet(uid: uid, heroData: heroData),
  );
}

class _HeroServiceAccessSheet extends StatefulWidget {
  const _HeroServiceAccessSheet({required this.uid, required this.heroData});

  final String uid;
  final Map<String, dynamic> heroData;

  @override
  State<_HeroServiceAccessSheet> createState() =>
      _HeroServiceAccessSheetState();
}

class _HeroServiceAccessSheetState extends State<_HeroServiceAccessSheet> {
  late Map<String, bool> _allowed;
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _allowed = {
      for (final key in HeroServiceKeys.all)
        key: isServiceAllowed(widget.heroData, key),
    };
  }

  Future<void> _save() async {
    if (_saving) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      // Explicit boolean per bucket — see the file header for why this
      // is not "denials only". An explicit `true` is what lets an
      // auto/cab hero be granted parcel work.
      final access = <String, dynamic>{
        for (final entry in _allowed.entries) entry.key: entry.value,
      };
      final deniedCount = _allowed.values.where((v) => !v).length;

      await FirebaseFirestore.instance
          .collection('heroes')
          .doc(widget.uid)
          .set({
        kHeroServiceAccessField: access,
        'serviceAccessUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      if (!mounted) return;
      Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            deniedCount == 0
                ? 'All services enabled for this hero'
                : '$deniedCount service(s) disabled for this hero',
          ),
          backgroundColor: deniedCount == 0 ? _green : _red,
          behavior: SnackBarBehavior.floating,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final name = (widget.heroData['name'] as String?)?.trim();
    final deniedCount = _allowed.values.where((v) => !v).length;

    return Container(
      decoration: const BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
      ),
      child: SafeArea(
        top: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 42,
                  height: 4,
                  decoration: BoxDecoration(
                    color: _border,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Text(
                'Work permissions',
                style: GoogleFonts.outfit(
                  color: _text,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                name != null && name.isNotEmpty ? name : widget.uid,
                style: GoogleFonts.outfit(color: _muted, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text(
                'Turn a service off and this hero stops receiving that kind '
                'of job. Turning "Parcel & courier" ON also lets an auto or '
                'cab hero take parcel jobs, which they never get otherwise. '
                'Takes effect immediately, even if they are online right now.',
                style: GoogleFonts.outfit(
                    color: _muted, fontSize: 12, height: 1.45),
              ),
              const SizedBox(height: 16),

              for (final key in HeroServiceKeys.all) ...[
                Container(
                  margin: const EdgeInsets.only(bottom: 8),
                  padding: const EdgeInsets.fromLTRB(14, 10, 8, 10),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.03),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _allowed[key]!
                          ? _border
                          : _red.withValues(alpha: 0.45),
                    ),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              HeroServiceKeys.labels[key] ?? key,
                              style: GoogleFonts.outfit(
                                color: _text,
                                fontSize: 14,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              HeroServiceKeys.descriptions[key] ?? '',
                              style: GoogleFonts.outfit(
                                  color: _muted, fontSize: 11.5, height: 1.35),
                            ),
                          ],
                        ),
                      ),
                      Switch(
                        value: _allowed[key]!,
                        activeColor: _green,
                        inactiveThumbColor: _red,
                        onChanged: _saving
                            ? null
                            : (v) => setState(() => _allowed[key] = v),
                      ),
                    ],
                  ),
                ),
              ],

              if (_error != null) ...[
                const SizedBox(height: 6),
                Text(
                  _error!,
                  style: GoogleFonts.outfit(color: _red, fontSize: 12.5),
                ),
              ],
              const SizedBox(height: 10),

              SizedBox(
                height: 48,
                child: ElevatedButton(
                  onPressed: _saving ? null : _save,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: deniedCount == 0 ? _green : _red,
                    disabledBackgroundColor: _muted,
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(14),
                    ),
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.4,
                            color: Colors.white,
                          ),
                        )
                      : Text(
                          deniedCount == 0
                              ? 'Save — all services on'
                              : 'Save — $deniedCount service(s) off',
                          style: GoogleFonts.outfit(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15,
                          ),
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
