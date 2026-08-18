// ================================================================
// AdminErodeOffersScreen — manage local shop offers shown in the
// customer app's Rewards > Erode Offers tab.
// ================================================================
// CRUD screen: add / edit / delete / toggle-active offers stored in
// the `erode_offers` Firestore collection. Each offer has: shopName,
// offerPercent, validTill (date), address, phone, lat, lng, active.
// Customer app reads these live via a StreamBuilder, so any change
// here reflects immediately in the customer Rewards screen.
// ================================================================
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:latlong2/latlong.dart';

import '../../models/mobile_models.dart' show isValidYoutubeUrl;
import '../../services/cloudinary_upload_service.dart';
import '../../widgets/video_link_field.dart';
import '../location_picker_screen.dart';

const Color _bg = Color(0xFF0F0B14);
const Color _surface = Color(0xFF1B1524);
const Color _text = Colors.white;
const Color _pink = Color(0xFFFF4FA3);
const Color _purple = Color(0xFFB21FFF);

class AdminErodeOffersScreen extends StatelessWidget {
  const AdminErodeOffersScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: const Text('Erode Offers', style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
            onPressed: () => _publishRewards(context),
            icon: const Icon(Icons.publish_rounded, color: _pink, size: 20),
            label: const Text(
              'Publish',
              style: TextStyle(color: _pink, fontWeight: FontWeight.w800),
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _pink,
        onPressed: () => _showOfferDialog(context),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('erode_offers')
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _pink));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No offers yet. Tap + to add one.', style: TextStyle(color: Colors.white54)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              return _OfferAdminCard(offerId: doc.id, data: data);
            },
          );
        },
      ),
    );
  }

  // ================================================================
  // PUBLISH REWARDS  (Aug 18 2026 — Nizam's "admin ping", CTO-approved)
  // ================================================================
  // Bumps `rewardsVersion` on system_settings/app_status. Every open
  // customer app already watches that document (MigrationGateService's
  // kill-switch listener), so this single write is what makes edits
  // appear — and removals disappear — on phones that already have the
  // app open, with no polling and no per-customer listener.
  //
  // WHY THIS IS A BUTTON AND NOT AUTOMATIC ON EVERY OFFER SAVE:
  // each CHANGE to that doc costs 1 Firestore read on every currently
  // connected app. Bumping per-edit would mean editing 10 offers costs
  // 10 x (every online customer) reads for zero added benefit. Batching
  // an editing session behind one explicit Publish keeps that at
  // exactly 1 x (online customers), which is the whole cost argument.
  //
  // Uses FieldValue.increment(1) rather than a client timestamp so it
  // is immune to device clock skew and to two admins publishing in the
  // same second. set(merge: true) so it works even if the doc has never
  // been created.
  static Future<void> _publishRewards(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Publish offers to customers?',
            style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
        content: const Text(
          'Every customer will see the current offers — including any you '
          'removed — the next time their app checks, or straight away if '
          'they have it open.\n\nPress this once after you finish editing, '
          'not after every change.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: _pink, foregroundColor: Colors.white),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Publish'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('system_settings')
          .doc('app_status')
          .set(
        <String, dynamic>{
          'rewardsVersion': FieldValue.increment(1),
          'rewardsPublishedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Published — customers will see the latest offers.'),
          backgroundColor: Color(0xFF00C853),
        ),
      );
    } catch (e) {
      // Never silent: a failed publish means customers keep seeing the
      // OLD offers, which is exactly the kind of thing that looks like
      // "the app is broken" if we swallow it.
      messenger.showSnackBar(
        SnackBar(
          content: Text('Could not publish: $e'),
          backgroundColor: const Color(0xFFFF5252),
        ),
      );
    }
  }

  static void _showOfferDialog(BuildContext context, {String? offerId, Map<String, dynamic>? existing}) {
    showDialog(
      context: context,
      builder: (context) => _OfferFormDialog(offerId: offerId, existing: existing),
    );
  }
}

class _OfferAdminCard extends StatelessWidget {
  final String offerId;
  final Map<String, dynamic> data;

  const _OfferAdminCard({required this.offerId, required this.data});

  @override
  Widget build(BuildContext context) {
    final shopName = (data['shopName'] as String?) ?? '';
    final offerPercent = data['offerPercent'];
    final active = (data['active'] as bool?) ?? true;
    final validTill = data['validTill'];
    final imageUrl = data['imageUrl'] as String?;
    final hasLocation = data['lat'] != null && data['lng'] != null;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pink.withValues(alpha: 0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_pink, _purple]),
              borderRadius: BorderRadius.circular(14),
              image: (imageUrl != null && imageUrl.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(imageUrl), fit: BoxFit.cover)
                  : null,
            ),
            alignment: Alignment.center,
            child: (imageUrl != null && imageUrl.isNotEmpty)
                ? null
                : Text(
                    offerPercent != null ? '$offerPercent%' : '—',
                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 12),
                  ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shopName, style: const TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 15)),
                const SizedBox(height: 3),
                Text(
                  _formatValidTill(validTill),
                  style: const TextStyle(color: Colors.white54, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Row(
                  children: [
                    Icon(
                      hasLocation ? Icons.location_on_rounded : Icons.location_off_rounded,
                      size: 12,
                      color: hasLocation ? const Color(0xFF00C853) : Colors.white38,
                    ),
                    const SizedBox(width: 4),
                    Text(
                      hasLocation ? 'Map pin set' : 'No map pin',
                      style: TextStyle(color: hasLocation ? const Color(0xFF00C853) : Colors.white38, fontSize: 10.5),
                    ),
                  ],
                ),
              ],
            ),
          ),
          Switch(
            value: active,
            activeThumbColor: _pink,
            onChanged: (v) => FirebaseFirestore.instance.collection('erode_offers').doc(offerId).update({'active': v}),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 20),
            onPressed: () => AdminErodeOffersScreen._showOfferDialog(context, offerId: offerId, existing: data),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252), size: 20),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  String _formatValidTill(validTill) {
    if (validTill is Timestamp) {
      final d = validTill.toDate();
      return 'Valid till ${d.day}/${d.month}/${d.year}';
    }
    if (validTill is String && validTill.isNotEmpty) return 'Valid till $validTill';
    return 'No expiry set';
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Delete this offer?', style: TextStyle(color: _text)),
        content: const Text('This cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection('erode_offers').doc(offerId).delete();
              Navigator.pop(context);
            },
            child: const Text('Delete', style: TextStyle(color: Color(0xFFFF5252))),
          ),
        ],
      ),
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('offerId', offerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>>('data', data));
  }
}

class _OfferFormDialog extends StatefulWidget {
  final String? offerId;
  final Map<String, dynamic>? existing;

  const _OfferFormDialog({this.offerId, this.existing});

  @override
  State<_OfferFormDialog> createState() => _OfferFormDialogState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('offerId', offerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>?>('existing', existing));
  }
}

class _OfferFormDialogState extends State<_OfferFormDialog> {
  late final TextEditingController _shopNameCtrl;
  late final TextEditingController _offerPercentCtrl;
  late final TextEditingController _validTillCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  bool _saving = false;
  bool _uploadingPhoto = false;

  // NEW (CTO mandate — Erode Offers image + map pin): lat/lng are no
  // longer hand-typed text fields — they're set by LocationPickerScreen
  // (the same "drag map, drop pin" widget already used for hero
  // bookings/custom hotel checkout elsewhere in the app), and the offer
  // photo is uploaded via Cloudinary, same pattern as
  // seller_custom_hotel_builder_screen.dart's item photos.
  double? _lat;
  double? _lng;
  String? _imageUrl;
  Uint8List? _pickedImageBytes;
  // SCHEMA PREP (Aug 18 2026): optional YouTube link per offer.
  // Stored now, rendered later — the customer side deliberately
  // ignores it until the Rewards video work lands, so shipping this
  // early lets admins start collecting links with zero UI risk.
  late final TextEditingController _videoUrlCtrl;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _shopNameCtrl = TextEditingController(text: e?['shopName'] as String? ?? '');
    _offerPercentCtrl = TextEditingController(text: e?['offerPercent']?.toString() ?? '');
    _validTillCtrl = TextEditingController(text: e?['validTill'] is String ? e!['validTill'] as String : '');
    _addressCtrl = TextEditingController(text: e?['address'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: e?['phone'] as String? ?? '');
    _lat = (e?['lat'] as num?)?.toDouble();
    _lng = (e?['lng'] as num?)?.toDouble();
    _imageUrl = e?['imageUrl'] as String?;
    _videoUrlCtrl =
        TextEditingController(text: e?['videoUrl'] as String? ?? '');
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _offerPercentCtrl.dispose();
    _validTillCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _videoUrlCtrl.dispose();
    super.dispose();
  }

  Uint8List? _compress(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = decoded.width > 900 ? img.copyResize(decoded, width: 900) : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 78));
    } catch (_) {
      return null;
    }
  }

  Future<void> _pickPhoto() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.single.bytes;
    if (bytes == null) return;
    setState(() => _pickedImageBytes = _compress(bytes) ?? bytes);
  }

  Future<void> _pickLocation() async {
    final picked = await Navigator.of(context).push<PickedLocation>(
      MaterialPageRoute<PickedLocation>(
        builder: (_) => LocationPickerScreen(
          title: 'Pin the shop\'s location',
          initialCenter: (_lat != null && _lng != null) ? LatLng(_lat!, _lng!) : null,
        ),
      ),
    );
    if (picked == null || !mounted) return;
    setState(() {
      _lat = picked.lat;
      _lng = picked.lng;
      // Only auto-fill the address field if the admin hasn't already
      // typed one — never silently overwrite a manually-entered address.
      if (_addressCtrl.text.trim().isEmpty) {
        _addressCtrl.text = picked.name;
      }
    });
  }

  Future<void> _save() async {
    if (_shopNameCtrl.text.trim().isEmpty) return;

    // Reject a bad paste at entry rather than storing a link that
    // renders a dead player once the Rewards video UI ships.
    final video = _videoUrlCtrl.text.trim();
    if (video.isNotEmpty && !isValidYoutubeUrl(video)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('That is not a valid YouTube link.'),
          backgroundColor: Color(0xFFFF5252),
        ),
      );
      return;
    }

    setState(() => _saving = true);
    try {
      var imageUrl = _imageUrl;
      if (_pickedImageBytes != null) {
        setState(() => _uploadingPhoto = true);
        imageUrl = await CloudinaryUploadService().uploadImageBytes(
          _pickedImageBytes!,
          fileName: 'erode_offer_${DateTime.now().millisecondsSinceEpoch}.jpg',
          folder: 'erode_offers',
        );
        if (mounted) setState(() => _uploadingPhoto = false);
      }
      final data = <String, dynamic>{
        'shopName': _shopNameCtrl.text.trim(),
        'offerPercent': num.tryParse(_offerPercentCtrl.text.trim()),
        'validTill': _validTillCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'lat': _lat,
        'lng': _lng,
        'imageUrl': imageUrl,
        // Empty string (not null) when cleared, so an admin removing
        // a link actually clears the stored value on update().
        'videoUrl': video,
        'active': widget.existing?['active'] as bool? ?? true,
      };
      if (widget.offerId != null) {
        await FirebaseFirestore.instance.collection('erode_offers').doc(widget.offerId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('erode_offers').add(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      // FIX (root cause of "Erode Offers don't reach the customer app"):
      // this was a bare try/finally before — any Firestore error
      // (permission-denied being the actual live one) was silently
      // swallowed, the dialog just closed as if it had saved, and
      // Admin had no idea the offer was never written. Now surfaces the
      // real error instead of failing silently.
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save offer: $e'), backgroundColor: const Color(0xFFFF5252)),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: _surface,
      title: Text(widget.offerId != null ? 'Edit Offer' : 'Add Offer', style: const TextStyle(color: _text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _photoPicker(),
            const SizedBox(height: 14),
            _field(_shopNameCtrl, 'Shop Name'),
            _field(_offerPercentCtrl, 'Offer %', keyboardType: TextInputType.number),
            _field(_validTillCtrl, 'Valid Till (e.g. 31 Aug 2026)'),
            _field(_addressCtrl, 'Address'),
            _field(_phoneCtrl, 'Phone Number', keyboardType: TextInputType.phone),
            VideoLinkField(
              controller: _videoUrlCtrl,
              onChanged: () => setState(() {}),
              label: 'Offer video',
              helper: 'Optional. If the shop has a YouTube clip for this '
                  'offer, paste the share link — customers get a WATCH '
                  'OFFER badge and can play it inside the app.',
              fillColor: const Color(0xFF241C2F),
              textColor: _text,
              mutedColor: Colors.white54,
              borderColor: Colors.white24,
              accentColor: _pink,
            ),
            _locationPicker(),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        ElevatedButton(
          style: ElevatedButton.styleFrom(backgroundColor: _pink, foregroundColor: Colors.white),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
              : const Text('Save'),
        ),
      ],
    );
  }

  Widget _photoPicker() {
    return GestureDetector(
      onTap: _uploadingPhoto ? null : _pickPhoto,
      child: Container(
        width: double.infinity,
        height: 120,
        decoration: BoxDecoration(
          color: const Color(0xFF120E18),
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: _pink.withValues(alpha: 0.25)),
          image: _pickedImageBytes != null
              ? DecorationImage(image: MemoryImage(_pickedImageBytes!), fit: BoxFit.cover)
              : (_imageUrl != null && _imageUrl!.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(_imageUrl!), fit: BoxFit.cover)
                  : null,
        ),
        alignment: Alignment.center,
        child: (_pickedImageBytes == null && (_imageUrl == null || _imageUrl!.isEmpty))
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add_photo_alternate_rounded, color: Colors.white54, size: 28),
                  SizedBox(height: 6),
                  Text('Add shop photo', style: TextStyle(color: Colors.white54, fontSize: 12)),
                ],
              )
            : _uploadingPhoto
                ? const CircularProgressIndicator(color: _pink)
                : Align(
                    alignment: Alignment.bottomRight,
                    child: Padding(
                      padding: const EdgeInsets.all(6),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: const BoxDecoration(color: Colors.black54, shape: BoxShape.circle),
                        child: const Icon(Icons.edit_rounded, color: Colors.white, size: 16),
                      ),
                    ),
                  ),
      ),
    );
  }

  Widget _locationPicker() {
    final hasLocation = _lat != null && _lng != null;
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 4),
      child: OutlinedButton.icon(
        onPressed: _pickLocation,
        style: OutlinedButton.styleFrom(
          foregroundColor: hasLocation ? const Color(0xFF00C853) : _pink,
          side: BorderSide(color: hasLocation ? const Color(0xFF00C853) : _pink),
          padding: const EdgeInsets.symmetric(vertical: 12),
        ),
        icon: Icon(hasLocation ? Icons.location_on_rounded : Icons.map_rounded),
        label: Text(
          hasLocation
              ? 'Map pin set (${_lat!.toStringAsFixed(5)}, ${_lng!.toStringAsFixed(5)}) — tap to change'
              : 'Pin shop location on map',
        ),
      ),
    );
  }

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        style: const TextStyle(color: _text),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white54),
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withValues(alpha: 0.2))),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _pink)),
        ),
      ),
    );
  }
}
