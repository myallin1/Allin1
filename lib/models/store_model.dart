// ================================================================
// StoreModel — Local-First edge cache model
// Allin1 Super App — Multi-Store Architecture
// Backed by Hive (works on Android, iOS & PWA Web)
// ================================================================

import 'package:hive_flutter/hive_flutter.dart';

part 'store_model.g.dart';

@HiveType(typeId: 10)
class StoreModel extends HiveObject {
  @HiveField(0)
  final String id;

  @HiveField(1)
  final String name;

  @HiveField(2)
  final String category; // e.g. 'grocery', 'pharmacy', 'fashion'

  @HiveField(3)
  final String city;

  @HiveField(4)
  final String? address;

  @HiveField(5)
  final double? latitude;

  @HiveField(6)
  final double? longitude;

  @HiveField(7)
  final String? logoUrl;

  @HiveField(8)
  final bool isOpen;

  @HiveField(9)
  final double? rating;

  @HiveField(10)
  final int? deliveryTimeMinutes;

  /// ISO-8601 string — when TrailBase last updated this record
  @HiveField(11)
  final String updatedAt;

  /// When we last cached this record locally
  @HiveField(12)
  final DateTime lastSynced;

  StoreModel({
    required this.id,
    required this.name,
    required this.category,
    required this.city,
    required this.updatedAt,
    required this.lastSynced,
    this.address,
    this.latitude,
    this.longitude,
    this.logoUrl,
    this.isOpen = true,
    this.rating,
    this.deliveryTimeMinutes,
  });

  factory StoreModel.fromJson(Map<String, dynamic> json) => StoreModel(
        id: json['id'] as String,
        name: json['name'] as String,
        category: (json['category'] as String?) ?? 'general',
        city: (json['city'] as String?) ?? '',
        address: json['address'] as String?,
        latitude: (json['latitude'] as num?)?.toDouble(),
        longitude: (json['longitude'] as num?)?.toDouble(),
        logoUrl: json['logo_url'] as String?,
        isOpen: (json['is_open'] as bool?) ?? true,
        rating: (json['rating'] as num?)?.toDouble(),
        deliveryTimeMinutes: json['delivery_time_minutes'] as int?,
        updatedAt:
            (json['updated_at'] as String?) ?? DateTime.now().toIso8601String(),
        lastSynced: DateTime.now(),
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'category': category,
        'city': city,
        'address': address,
        'latitude': latitude,
        'longitude': longitude,
        'logo_url': logoUrl,
        'is_open': isOpen,
        'rating': rating,
        'delivery_time_minutes': deliveryTimeMinutes,
        'updated_at': updatedAt,
      };
}
