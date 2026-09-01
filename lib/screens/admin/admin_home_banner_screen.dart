// ================================================================
// AdminHomeBannerScreen — manage the sliding banner offers shown
// directly below EconomicVisionBanner on the customer home page.
// ================================================================
// NEW (Aug 19 2026 — Nizam's "home page banner offer" request). This
// is a SEPARATE feature from AdminErodeOffersScreen / erode_offers:
// its own Firestore collection (`home_banner_offers`), its own admin
// screen, its own publish counter (homeBannerVersion on the shared
// system_settings/app_status doc — see migration_gate_service.dart).
// Nothing here touches erode_offers or its screen.
//
// Data shape: shopName, imageUrl, videoUrl (optional YouTube link),
// description, address, phone, isActive, createdAt. Modelled closely
// on erode_offers_management_screen.dart (same Cloudinary upload
// pattern, same VideoLinkField widget) so this screen behaves exactly
// like the one Nizam already knows.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;

import '../../models/mobile_models.dart' show isValidYoutubeUrl;
import '../../services/cloudinary_upload_service.dart';
import '../../widgets/video_link_field.dart';
import '../../services/firestore_usage_tracking.dart';

const Color _bg = Color(0xFF0F0B14);
const Color _surface = Color(0xFF1B1524);
const Color _text = Colors.white;
const Color _pink = Color(0xFFFF4FA3);
const Color _purple = Color(0xFFB21FFF);

const String kHomeBannerCollection = 'home_banner_offers';

class AdminHomeBannerScreen extends StatelessWidget {
  const AdminHomeBannerScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        iconTheme: const IconThemeData(color: _text),
        title: const Text('Home Page Banner Offers',
            style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
        actions: [
          TextButton.icon(
            onPressed: () => _publish(context),
            icon: const Icon(Icons.publish_rounded, color: _pink, size: 20),
            label: const Text('Publish',
                style: TextStyle(color: _pink, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: _pink,
        onPressed: () => _showDialog(context),
        child: const Icon(Icons.add_rounded, color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection(kHomeBannerCollection)
            .orderBy('createdAt', descending: true)
            .trackedSnapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _pink));
          }
          final docs = snapshot.data?.docs ?? [];
          if (docs.isEmpty) {
            return const Center(
              child: Text('No banner offers yet. Tap + to add one.',
                  style: TextStyle(color: Colors.white54)),
            );
          }
          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _BannerAdminCard(offerId: doc.id, data: doc.data());
            },
          );
        },
      ),
    );
  }

  // Same "publish once, everyone gets it" mechanism as
  // AdminErodeOffersScreen._publishRewards — bumps its own
  // homeBannerVersion counter on the same already-watched doc, so this
  // costs zero extra Firestore connections. See migration_gate_service.dart.
  static Future<void> _publish(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Publish banner offers to customers?',
            style: TextStyle(color: _text, fontWeight: FontWeight.w800)),
        content: const Text(
          'Every customer will see the current banner offers — including '
          'any you removed — the next time their app checks, or straight '
          'away if they have it open.',
          style: TextStyle(color: Colors.white70),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel', style: TextStyle(color: Colors.white54)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _pink, foregroundColor: Colors.white),
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
          'homeBannerVersion': FieldValue.increment(1),
          'homeBannerPublishedAt': FieldValue.serverTimestamp(),
        },
        SetOptions(merge: true),
      );
      messenger.showSnackBar(
        const SnackBar(
          content: Text('Published — customers will see the latest banner offers.'),
          backgroundColor: Color(0xFF00C853),
        ),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('Could not publish: $e'), backgroundColor: const Color(0xFFFF5252)),
      );
    }
  }

  static void _showDialog(BuildContext context, {String? offerId, Map<String, dynamic>? existing}) {
    showDialog(
      context: context,
      builder: (context) => _BannerFormDialog(offerId: offerId, existing: existing),
    );
  }
}

class _BannerAdminCard extends StatelessWidget {
  final String offerId;
  final Map<String, dynamic> data;

  const _BannerAdminCard({required this.offerId, required this.data});

  @override
  Widget build(BuildContext context) {
    final shopName = (data['shopName'] as String?) ?? '';
    final isActive = (data['isActive'] as bool?) ?? true;
    final imageUrl = data['imageUrl'] as String?;
    final hasVideo = (data['videoUrl'] as String?)?.isNotEmpty ?? false;

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
                : const Icon(Icons.image_rounded, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(shopName.isEmpty ? '(no name)' : shopName,
                    style: const TextStyle(color: _text, fontWeight: FontWeight.w800, fontSize: 15)),
                if (hasVideo) ...[
                  const SizedBox(height: 3),
                  const Row(children: [
                    Icon(Icons.play_circle_fill_rounded, size: 12, color: _pink),
                    SizedBox(width: 4),
                    Text('Has video', style: TextStyle(color: _pink, fontSize: 10.5)),
                  ]),
                ],
              ],
            ),
          ),
          Switch(
            value: isActive,
            activeThumbColor: _pink,
            onChanged: (v) => FirebaseFirestore.instance
                .collection(kHomeBannerCollection)
                .doc(offerId)
                .update({'isActive': v}),
          ),
          IconButton(
            icon: const Icon(Icons.edit_rounded, color: Colors.white70, size: 20),
            onPressed: () => AdminHomeBannerScreen._showDialog(context, offerId: offerId, existing: data),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded, color: Color(0xFFFF5252), size: 20),
            onPressed: () => _confirmDelete(context),
          ),
        ],
      ),
    );
  }

  void _confirmDelete(BuildContext context) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: _surface,
        title: const Text('Delete this banner offer?', style: TextStyle(color: _text)),
        content: const Text('This cannot be undone.', style: TextStyle(color: Colors.white70)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance.collection(kHomeBannerCollection).doc(offerId).delete();
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

class _BannerFormDialog extends StatefulWidget {
  final String? offerId;
  final Map<String, dynamic>? existing;

  const _BannerFormDialog({this.offerId, this.existing});

  @override
  State<_BannerFormDialog> createState() => _BannerFormDialogState();

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties.add(StringProperty('offerId', offerId));
    properties.add(DiagnosticsProperty<Map<String, dynamic>?>('existing', existing));
  }
}

class _BannerFormDialogState extends State<_BannerFormDialog> {
  late final TextEditingController _shopNameCtrl;
  late final TextEditingController _descriptionCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _videoUrlCtrl;
  bool _saving = false;
  bool _uploadingPhoto = false;

  String? _imageUrl;
  Uint8List? _pickedImageBytes;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _shopNameCtrl = TextEditingController(text: e?['shopName'] as String? ?? '');
    _descriptionCtrl = TextEditingController(text: e?['description'] as String? ?? '');
    _addressCtrl = TextEditingController(text: e?['address'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: e?['phone'] as String? ?? '');
    _videoUrlCtrl = TextEditingController(text: e?['videoUrl'] as String? ?? '');
    _imageUrl = e?['imageUrl'] as String?;
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _descriptionCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _videoUrlCtrl.dispose();
    super.dispose();
  }

  Uint8List? _compress(Uint8List bytes) {
    try {
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final resized = decoded.width > 1200 ? img.copyResize(decoded, width: 1200) : decoded;
      return Uint8List.fromList(img.encodeJpg(resized, quality: 82));
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

  Future<void> _save() async {
    if (_shopNameCtrl.text.trim().isEmpty) return;
    if (_pickedImageBytes == null && (_imageUrl == null || _imageUrl!.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Please add a banner image.'), backgroundColor: Color(0xFFFF5252)),
      );
      return;
    }

    final video = _videoUrlCtrl.text.trim();
    if (video.isNotEmpty && !isValidYoutubeUrl(video)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('That is not a valid YouTube link.'), backgroundColor: Color(0xFFFF5252)),
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
          fileName: 'home_banner_${DateTime.now().millisecondsSinceEpoch}.jpg',
          folder: 'home_banner_offers',
        );
        if (mounted) setState(() => _uploadingPhoto = false);
      }
      final data = <String, dynamic>{
        'shopName': _shopNameCtrl.text.trim(),
        'description': _descriptionCtrl.text.trim(),
        'address': _addressCtrl.text.trim(),
        'phone': _phoneCtrl.text.trim(),
        'imageUrl': imageUrl,
        'videoUrl': video,
        'isActive': widget.existing?['isActive'] as bool? ?? true,
      };
      if (widget.offerId != null) {
        await FirebaseFirestore.instance.collection(kHomeBannerCollection).doc(widget.offerId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection(kHomeBannerCollection).add(data);
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not save banner offer: $e'), backgroundColor: const Color(0xFFFF5252)),
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
      title: Text(widget.offerId != null ? 'Edit Banner Offer' : 'Add Banner Offer',
          style: const TextStyle(color: _text)),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _photoPicker(),
            const SizedBox(height: 14),
            _field(_shopNameCtrl, 'Shop Name'),
            _field(_descriptionCtrl, 'Description', maxLines: 2),
            _field(_addressCtrl, 'Address'),
            _field(_phoneCtrl, 'Phone Number', keyboardType: TextInputType.phone),
            VideoLinkField(
              controller: _videoUrlCtrl,
              onChanged: () => setState(() {}),
              label: 'Banner video',
              helper: 'Optional. Paste a YouTube share link and customers '
                  'get a WATCH badge to play it inside the app.',
              fillColor: const Color(0xFF241C2F),
              textColor: _text,
              mutedColor: Colors.white54,
              borderColor: Colors.white24,
              accentColor: _pink,
            ),
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
              ? DecorationImage(image: MemoryImage(_pickedImageBytes!), fit: BoxFit.contain)
              : (_imageUrl != null && _imageUrl!.isNotEmpty)
                  ? DecorationImage(image: NetworkImage(_imageUrl!), fit: BoxFit.contain)
                  : null,
        ),
        alignment: Alignment.center,
        child: (_pickedImageBytes == null && (_imageUrl == null || _imageUrl!.isEmpty))
            ? Column(
                mainAxisSize: MainAxisSize.min,
                children: const [
                  Icon(Icons.add_photo_alternate_rounded, color: Colors.white54, size: 28),
                  SizedBox(height: 6),
                  Text('Add banner image (any size/shape)', style: TextStyle(color: Colors.white54, fontSize: 12)),
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

  Widget _field(TextEditingController ctrl, String label, {TextInputType? keyboardType, int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextField(
        controller: ctrl,
        keyboardType: keyboardType,
        maxLines: maxLines,
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
