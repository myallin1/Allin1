// ================================================================
// master_catalog_model.dart — one shared, admin-managed product SKU,
// reused across every seller who carries it.
// ================================================================
// Sep 2026 — universal catalog build. Firestore-hosted revival of the
// idea seller_menu_setup_screen.dart already proved out with a
// hardcoded Dart list (DefaultMenuData): a seller doesn't author their
// own "Sunflower Oil 1L" — they toggle ON an item that already exists
// once, centrally, with one shared photo. Every seller who carries that
// item points at the SAME imageUrl, so Cloudinary storage/bandwidth
// doesn't scale with (sellers × items) the way per-seller photo
// uploads would.
//
// `department` makes this genuinely universal rather than
// grocery-only — the exact same collection/model/admin screen can host
// an 'electronics' or 'general' catalog later without any new
// infrastructure, just a different department value.
import 'package:cloud_firestore/cloud_firestore.dart';

class MasterCatalogItemModel {
  final String id;
  final String name;
  final String department; // 'grocery' (initially), extensible later
  final String category; // e.g. 'Rice & Grains', 'Oils', 'Snacks'
  final String unit; // e.g. 'kg', 'litre', 'pack', 'piece'
  final String? imageUrl;
  final bool isActive;
  final DateTime? createdAt;
  final DateTime? updatedAt;

  const MasterCatalogItemModel({
    required this.id,
    required this.name,
    required this.department,
    required this.category,
    required this.unit,
    this.imageUrl,
    this.isActive = true,
    this.createdAt,
    this.updatedAt,
  });

  factory MasterCatalogItemModel.fromFirestore(
    Map<String, dynamic> data,
    String id,
  ) {
    return MasterCatalogItemModel(
      id: id,
      name: (data['name'] as String?) ?? '',
      department: (data['department'] as String?) ?? 'grocery',
      category: (data['category'] as String?) ?? 'General',
      unit: (data['unit'] as String?) ?? 'piece',
      imageUrl: data['imageUrl'] as String?,
      isActive: (data['isActive'] as bool?) ?? true,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      updatedAt: (data['updatedAt'] as Timestamp?)?.toDate(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'department': department,
      'category': category,
      'unit': unit,
      'imageUrl': imageUrl,
      'isActive': isActive,
      'updatedAt': FieldValue.serverTimestamp(),
    };
  }
}
