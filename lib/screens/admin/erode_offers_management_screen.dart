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
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

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

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _pink.withOpacity(0.18)),
      ),
      child: Row(
        children: [
          Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: [_pink, _purple]),
              borderRadius: BorderRadius.circular(14),
            ),
            alignment: Alignment.center,
            child: Text(
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
              ],
            ),
          ),
          Switch(
            value: active,
            activeColor: _pink,
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

  String _formatValidTill(dynamic validTill) {
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
}

class _OfferFormDialog extends StatefulWidget {
  final String? offerId;
  final Map<String, dynamic>? existing;

  const _OfferFormDialog({this.offerId, this.existing});

  @override
  State<_OfferFormDialog> createState() => _OfferFormDialogState();
}

class _OfferFormDialogState extends State<_OfferFormDialog> {
  late final TextEditingController _shopNameCtrl;
  late final TextEditingController _offerPercentCtrl;
  late final TextEditingController _validTillCtrl;
  late final TextEditingController _addressCtrl;
  late final TextEditingController _phoneCtrl;
  late final TextEditingController _latCtrl;
  late final TextEditingController _lngCtrl;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _shopNameCtrl = TextEditingController(text: e?['shopName'] as String? ?? '');
    _offerPercentCtrl = TextEditingController(text: e?['offerPercent']?.toString() ?? '');
    _validTillCtrl = TextEditingController(text: e?['validTill'] is String ? e!['validTill'] as String : '');
    _addressCtrl = TextEditingController(text: e?['address'] as String? ?? '');
    _phoneCtrl = TextEditingController(text: e?['phone'] as String? ?? '');
    _latCtrl = TextEditingController(text: e?['lat']?.toString() ?? '');
    _lngCtrl = TextEditingController(text: e?['lng']?.toString() ?? '');
  }

  @override
  void dispose() {
    _shopNameCtrl.dispose();
    _offerPercentCtrl.dispose();
    _validTillCtrl.dispose();
    _addressCtrl.dispose();
    _phoneCtrl.dispose();
    _latCtrl.dispose();
    _lngCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_shopNameCtrl.text.trim().isEmpty) return;
    setState(() => _saving = true);
    final data = <String, dynamic>{
      'shopName': _shopNameCtrl.text.trim(),
      'offerPercent': num.tryParse(_offerPercentCtrl.text.trim()),
      'validTill': _validTillCtrl.text.trim(),
      'address': _addressCtrl.text.trim(),
      'phone': _phoneCtrl.text.trim(),
      'lat': double.tryParse(_latCtrl.text.trim()),
      'lng': double.tryParse(_lngCtrl.text.trim()),
      'active': widget.existing?['active'] as bool? ?? true,
    };
    try {
      if (widget.offerId != null) {
        await FirebaseFirestore.instance.collection('erode_offers').doc(widget.offerId).update(data);
      } else {
        data['createdAt'] = FieldValue.serverTimestamp();
        await FirebaseFirestore.instance.collection('erode_offers').add(data);
      }
      if (mounted) Navigator.pop(context);
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
            _field(_shopNameCtrl, 'Shop Name'),
            _field(_offerPercentCtrl, 'Offer %', keyboardType: TextInputType.number),
            _field(_validTillCtrl, 'Valid Till (e.g. 31 Aug 2026)'),
            _field(_addressCtrl, 'Address'),
            _field(_phoneCtrl, 'Phone Number', keyboardType: TextInputType.phone),
            _field(_latCtrl, 'Latitude', keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
            _field(_lngCtrl, 'Longitude', keyboardType: const TextInputType.numberWithOptions(decimal: true, signed: true)),
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
          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white.withOpacity(0.2))),
          focusedBorder: const OutlineInputBorder(borderSide: BorderSide(color: _pink)),
        ),
      ),
    );
  }
}
