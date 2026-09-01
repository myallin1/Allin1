// ================================================================
// Platform Settings Service - Commission & Fee Management
// Allin1 Super App v1.0
// ================================================================

import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/platform_settings.dart';
import './firestore_usage_tracking.dart';

class PlatformSettingsService {
  static final PlatformSettingsService _instance =
      PlatformSettingsService._internal();
  factory PlatformSettingsService() => _instance;
  PlatformSettingsService._internal();

  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Cache for settings
  PlatformSettings? _cachedSettings;
  bool _isCacheValid = false;

  // Collection references
  CollectionReference get _settingsRef =>
      _firestore.collection('platformSettings');
  CollectionReference get _sellerOverridesRef =>
      _firestore.collection('sellerOverrides');

  /// Get current platform settings (with caching)
  Future<PlatformSettings> getSettings({bool forceRefresh = false}) async {
    if (!forceRefresh && _isCacheValid && _cachedSettings != null) {
      return _cachedSettings!;
    }

    try {
      final doc = await _settingsRef.doc('global').get();
      if (doc.exists && doc.data() != null) {
        _cachedSettings = PlatformSettings.fromMap(
          doc.data()! as Map<String, dynamic>,
        );
        _isCacheValid = true;
        return _cachedSettings!;
      }
    } catch (e) {
      // If error, return defaults
    }

    // Return defaults if not found
    _cachedSettings = PlatformSettings.defaults();
    _isCacheValid = true;
    return _cachedSettings!;
  }

  /// Update platform settings (admin only)
  Future<void> updateSettings(
    PlatformSettings settings, {
    required String adminId,
  }) async {
    final updatedSettings = settings.copyWith(
      updatedAt: DateTime.now(),
      updatedBy: adminId,
    );

    await _settingsRef.doc('global').set(
          updatedSettings.toMap(),
          SetOptions(merge: true),
        );

    // Invalidate cache
    _cachedSettings = updatedSettings;
    _isCacheValid = true;
  }

  /// Reset settings to defaults
  Future<void> resetToDefaults({required String adminId}) async {
    final defaultSettings = PlatformSettings.defaults().copyWith(
      updatedAt: DateTime.now(),
      updatedBy: adminId,
    );

    await _settingsRef.doc('global').set(defaultSettings.toMap());

    // Invalidate cache
    _cachedSettings = defaultSettings;
    _isCacheValid = true;
  }

  /// Get seller-specific override if exists
  Future<SellerOverride?> getSellerOverride(String storeId) async {
    try {
      final doc = await _sellerOverridesRef.doc(storeId).get();
      if (doc.exists && doc.data() != null) {
        return SellerOverride.fromMap(
          doc.data()! as Map<String, dynamic>,
        );
      }
    } catch (e) {
      // Return null if not found
    }
    return null;
  }

  /// Set seller-specific override
  Future<void> setSellerOverride(
    SellerOverride override, {
    required String adminId,
  }) async {
    await _sellerOverridesRef.doc(override.storeId).set(
          override.toMap(),
          SetOptions(merge: true),
        );
  }

  /// Remove seller override
  Future<void> removeSellerOverride(String storeId) async {
    await _sellerOverridesRef.doc(storeId).delete();
  }

  /// Get all seller overrides
  Future<List<SellerOverride>> getAllSellerOverrides() async {
    try {
      final snapshot = await _sellerOverridesRef.get();
      return snapshot.docs
          .map(
            (doc) =>
                SellerOverride.fromMap(doc.data()! as Map<String, dynamic>),
          )
          .toList();
    } catch (e) {
      return [];
    }
  }

  /// Invalidate cache (call when settings change)
  void invalidateCache() {
    _isCacheValid = false;
    _cachedSettings = null;
  }

  /// Calculate rider earnings after commission
  Future<double> calculateRiderEarnings({
    required double fare,
    required String serviceType,
    required bool isPeakHour,
  }) async {
    final settings = await getSettings();
    final commissionPercent =
        settings.riderCommission.getCommissionForType(serviceType);

    double earnings = fare * (1 - (commissionPercent / 100));

    // Apply minimum guarantee
    if (earnings < settings.riderCommission.minimumEarning) {
      earnings = settings.riderCommission.minimumEarning;
    }

    // Apply peak hour multiplier
    if (isPeakHour) {
      earnings *= settings.riderCommission.peakHourMultiplier;
    }

    return earnings;
  }

  /// Calculate seller payout after commission
  Future<double> calculateSellerPayout({
    required double orderTotal,
    required String category,
  }) async {
    final settings = await getSettings();
    final commissionPercent =
        settings.sellerCommission.getCommissionForCategory(category);

    // Check for minimum order threshold
    if (settings.sellerCommission.minimumOrder != null &&
        orderTotal < settings.sellerCommission.minimumOrder! &&
        settings.sellerCommission.flatFeeBelowMin != null) {
      return orderTotal - settings.sellerCommission.flatFeeBelowMin!;
    }

    return orderTotal * (1 - (commissionPercent / 100));
  }

  /// Calculate delivery fee
  double calculateDeliveryFee({
    required double distanceKm,
    required double subtotal,
    String deliveryType = 'standard',
  }) {
    // Use cached settings synchronously if available
    if (_cachedSettings != null) {
      return _cachedSettings!.deliverySettings.calculateDeliveryFee(
        distanceKm: distanceKm,
        subtotal: subtotal,
        deliveryType: deliveryType,
      );
    }

    // Fallback to defaults
    return DeliverySettings.defaults().calculateDeliveryFee(
      distanceKm: distanceKm,
      subtotal: subtotal,
      deliveryType: deliveryType,
    );
  }

  /// Calculate platform fee for a transaction
  Future<double> calculatePlatformFee({
    required double amount,
    required String paymentMethod,
  }) async {
    final settings = await getSettings();

    if (paymentMethod.toLowerCase() == 'upi' &&
        settings.platformFee.upiZeroFee) {
      return 0.0;
    }

    return amount * (settings.platformFee.paymentGatewayFee / 100);
  }

  /// Listen to real-time settings changes
  Stream<PlatformSettings> watchSettings() {
    return _settingsRef.doc('global').trackedSnapshots().map((doc) {
      if (doc.exists && doc.data() != null) {
        final settings = PlatformSettings.fromMap(
          doc.data()! as Map<String, dynamic>,
        );
        _cachedSettings = settings;
        return settings;
      }
      return PlatformSettings.defaults();
    });
  }
}
