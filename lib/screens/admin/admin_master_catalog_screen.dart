// ================================================================
// admin_master_catalog_screen.dart — admin CRUD for the shared
// universal product catalog (master_catalog_model.dart).
// ================================================================
// Sep 2026 — universal catalog build. One photo/name/unit per SKU
// here serves EVERY seller who carries it (see that model's header),
// which is the whole cost win over each seller uploading their own
// photo for the same common item.
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../../models/master_catalog_model.dart';
import '../../services/cloudinary_upload_service.dart';
import '../../services/master_catalog_service.dart';
import '../../widgets/cached_cloud_image.dart';

const Color _bg = Color(0xFFF7FAF8);
const Color _card = Colors.white;
const Color _teal = Color(0xFF11998E);
const Color _text = Color(0xFF1A1A1A);
const Color _muted = Color(0xFF6B7280);
const Color _red = Color(0xFFD64545);

class AdminMasterCatalogScreen extends StatefulWidget {
  final String department;
  const AdminMasterCatalogScreen({this.department = 'grocery', super.key});

  @override
  State<AdminMasterCatalogScreen> createState() => _AdminMasterCatalogScreenState();
}

class _AdminMasterCatalogScreenState extends State<AdminMasterCatalogScreen> {
  bool _loading = true;
  List<MasterCatalogItemModel> _items = [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      _items = await MasterCatalogService.instance.listAllForAdmin(widget.department);
    } catch (e) {
      debugPrint('[AdminMasterCatalog] load failed: $e');
    }
    if (mounted) setState(() => _loading = false);
  }

  Future<void> _openEditor({MasterCatalogItemModel? existing}) async {
    final saved = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => _CatalogItemEditorSheet(department: widget.department, existing: existing),
    );
    if (saved == true) _load();
  }

  Future<void> _toggleActive(MasterCatalogItemModel item) async {
    await MasterCatalogService.instance.upsertItem(
      MasterCatalogItemModel(
        id: item.id,
        name: item.name,
        department: item.department,
        category: item.category,
        unit: item.unit,
        imageUrl: item.imageUrl,
        isActive: !item.isActive,
      ),
    );
    _load();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _card,
        elevation: 0,
        title: Text('${widget.department[0].toUpperCase()}${widget.department.substring(1)} Catalog',
            style: GoogleFonts.outfit(color: _text, fontWeight: FontWeight.w700),),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(),
        backgroundColor: _teal,
        icon: const Icon(Icons.add, color: Colors.white),
        label: const Text('Add Item', style: TextStyle(color: Colors.white)),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator(color: _teal))
          : _items.isEmpty
              ? Center(
                  child: Text('No items yet — tap "+ Add Item" to start.',
                      style: GoogleFonts.outfit(color: _muted),),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(16),
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return Container(
                      margin: const EdgeInsets.only(bottom: 8),
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: _card,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: item.isActive ? _teal.withValues(alpha: 0.2) : _red.withValues(alpha: 0.2)),
                      ),
                      child: Row(
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(8),
                            child: item.imageUrl != null
                                ? CachedCloudImage(item.imageUrl!, width: 48, height: 48, cacheWidth: 96, fit: BoxFit.cover)
                                : Container(width: 48, height: 48, color: _bg, child: const Icon(Icons.image_outlined, color: _muted)),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(item.name, style: GoogleFonts.outfit(fontWeight: FontWeight.w700, fontSize: 13)),
                                Text('${item.category} · ${item.unit}', style: GoogleFonts.outfit(color: _muted, fontSize: 11)),
                              ],
                            ),
                          ),
                          Switch(value: item.isActive, activeThumbColor: _teal, onChanged: (_) => _toggleActive(item)),
                          IconButton(
                            icon: const Icon(Icons.edit_outlined, size: 18, color: _muted),
                            onPressed: () => _openEditor(existing: item),
                          ),
                        ],
                      ),
                    );
                  },
                ),
    );
  }
}

class _CatalogItemEditorSheet extends StatefulWidget {
  final String department;
  final MasterCatalogItemModel? existing;
  const _CatalogItemEditorSheet({required this.department, this.existing});

  @override
  State<_CatalogItemEditorSheet> createState() => _CatalogItemEditorSheetState();
}

class _CatalogItemEditorSheetState extends State<_CatalogItemEditorSheet> {
  late final TextEditingController _nameCtrl;
  late final TextEditingController _categoryCtrl;
  late final TextEditingController _unitCtrl;
  String? _imageUrl;
  Uint8List? _pendingBytes;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.existing?.name ?? '');
    _categoryCtrl = TextEditingController(text: widget.existing?.category ?? '');
    _unitCtrl = TextEditingController(text: widget.existing?.unit ?? 'kg');
    _imageUrl = widget.existing?.imageUrl;
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _categoryCtrl.dispose();
    _unitCtrl.dispose();
    super.dispose();
  }

  Future<void> _pickImage() async {
    final result = await FilePicker.platform.pickFiles(type: FileType.image, withData: true);
    final bytes = result?.files.first.bytes;
    if (bytes == null) return;
    setState(() => _pendingBytes = bytes);
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    final category = _categoryCtrl.text.trim();
    final unit = _unitCtrl.text.trim();
    if (name.isEmpty || category.isEmpty || unit.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Name, category, and unit are all required'), backgroundColor: _red),
      );
      return;
    }
    setState(() => _saving = true);
    try {
      String? imageUrl = _imageUrl;
      if (_pendingBytes != null) {
        imageUrl = await CloudinaryUploadService().uploadImageBytes(
          _pendingBytes!,
          fileName: 'catalog_${DateTime.now().millisecondsSinceEpoch}.jpg',
          folder: 'master_catalog',
        );
      }
      final id = widget.existing?.id ??
          FirebaseFirestore.instance.collection('master_catalog').doc().id;
      await MasterCatalogService.instance.upsertItem(
        MasterCatalogItemModel(
          id: id,
          name: name,
          department: widget.department,
          category: category,
          unit: unit,
          imageUrl: imageUrl,
          isActive: widget.existing?.isActive ?? true,
        ),
      );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Save failed: $e'), backgroundColor: _red),
        );
      }
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 20,
        bottom: MediaQuery.of(context).viewInsets.bottom + 20,
      ),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(widget.existing == null ? 'Add Catalog Item' : 'Edit Catalog Item',
                style: GoogleFonts.outfit(fontWeight: FontWeight.w800, fontSize: 16),),
            const SizedBox(height: 16),
            GestureDetector(
              onTap: _pickImage,
              child: Container(
                width: 80, height: 80,
                decoration: BoxDecoration(color: _bg, borderRadius: BorderRadius.circular(10), border: Border.all(color: _muted.withValues(alpha: 0.3))),
                child: _pendingBytes != null
                    ? ClipRRect(borderRadius: BorderRadius.circular(10), child: Image.memory(_pendingBytes!, fit: BoxFit.cover))
                    : _imageUrl != null
                        ? ClipRRect(borderRadius: BorderRadius.circular(10), child: CachedCloudImage(_imageUrl!, cacheWidth: 160, fit: BoxFit.cover))
                        : const Icon(Icons.add_a_photo_outlined, color: _muted),
              ),
            ),
            const SizedBox(height: 16),
            TextField(controller: _nameCtrl, decoration: const InputDecoration(labelText: 'Item name (e.g. Sunflower Oil 1L)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _categoryCtrl, decoration: const InputDecoration(labelText: 'Category (e.g. Oils)', border: OutlineInputBorder())),
            const SizedBox(height: 12),
            TextField(controller: _unitCtrl, decoration: const InputDecoration(labelText: 'Unit (e.g. kg, litre, pack)', border: OutlineInputBorder())),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              height: 48,
              child: ElevatedButton(
                onPressed: _saving ? null : _save,
                style: ElevatedButton.styleFrom(backgroundColor: _teal),
                child: _saving
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Text('Save', style: TextStyle(color: Colors.white)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
