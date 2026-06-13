// ================================================================
// Cart Provider - State Management for Shopping Cart
// Allin1 Super App - Allin1
// ================================================================

import 'package:flutter/foundation.dart';
import '../services/platform_settings_service.dart';

class CartItem {
  final String id;
  final String name;
  final String emoji;
  final String category;
  final double price;
  int quantity;

  CartItem({
    required this.id,
    required this.name,
    required this.emoji,
    required this.category,
    required this.price,
    this.quantity = 1,
  });

  double get total => price * quantity;

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'emoji': emoji,
        'category': category,
        'price': price,
        'quantity': quantity,
      };

  factory CartItem.fromJson(Map<String, dynamic> json) => CartItem(
        id: json['id'] as String,
        name: json['name'] as String,
        emoji: json['emoji'] as String,
        category: json['category'] as String,
        price: (json['price'] as num?)?.toDouble() ?? 0,
        quantity: (json['quantity'] as num?)?.toInt() ?? 1,
      );
}

class CartProvider extends ChangeNotifier {
  final List<CartItem> _items = [];
  final PlatformSettingsService _settingsService = PlatformSettingsService();

  // Default values (fallback if settings not loaded)
  double _freeDeliveryThreshold = 200;
  double _deliveryFee = 30;
  bool _settingsLoaded = false;

  // Getters
  List<CartItem> get items => List.unmodifiable(_items);

  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0, (sum, item) => sum + item.total);

  /// Calculate delivery fee dynamically based on platform settings
  double get deliveryFee {
    // If subtotal is above threshold, delivery is free
    if (subtotal >= _freeDeliveryThreshold) {
      return 0;
    }
    return _deliveryFee;
  }

  double get total => subtotal + deliveryFee;

  bool get isEmpty => _items.isEmpty;

  bool get hasFreeDelivery => subtotal >= _freeDeliveryThreshold;

  // Load settings from platform
  Future<void> loadDeliverySettings() async {
    try {
      final settings = await _settingsService.getSettings();
      _freeDeliveryThreshold = settings.deliverySettings.freeDeliveryThreshold;
      _deliveryFee = settings.deliverySettings.baseDeliveryFee;
      _settingsLoaded = true;
      notifyListeners();
    } catch (e) {
      // Use default values if settings fail to load
      _freeDeliveryThreshold = 200;
      _deliveryFee = 30;
      _settingsLoaded = true;
    }
  }

  /// Get the current free delivery threshold
  double get freeDeliveryThreshold => _freeDeliveryThreshold;

  /// Get the current base delivery fee
  double get baseDeliveryFee => _deliveryFee;

  /// Check if settings have been loaded
  bool get isSettingsLoaded => _settingsLoaded;

  // Add item to cart
  void addItem(CartItem item) {
    final existingIndex = _items.indexWhere((i) => i.id == item.id);

    if (existingIndex >= 0) {
      // Item exists, increment quantity
      _items[existingIndex].quantity += item.quantity;
    } else {
      // New item
      _items.add(item);
    }

    notifyListeners();
  }

  // Remove item from cart
  void removeItem(String id) {
    _items.removeWhere((item) => item.id == id);
    notifyListeners();
  }

  // Update quantity
  void updateQuantity(String id, int quantity) {
    if (quantity <= 0) {
      removeItem(id);
      return;
    }

    final index = _items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _items[index].quantity = quantity;
      notifyListeners();
    }
  }

  // Increment quantity
  void incrementQuantity(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      _items[index].quantity++;
      notifyListeners();
    }
  }

  // Decrement quantity
  void decrementQuantity(String id) {
    final index = _items.indexWhere((item) => item.id == id);
    if (index >= 0) {
      if (_items[index].quantity > 1) {
        _items[index].quantity--;
      } else {
        removeItem(id);
        return;
      }
      notifyListeners();
    }
  }

  // Clear cart
  void clearCart() {
    _items.clear();
    notifyListeners();
  }

  // Check if item exists
  bool hasItem(String id) => _items.any((item) => item.id == id);

  // Get item by id
  CartItem? getItem(String id) {
    try {
      return _items.firstWhere((item) => item.id == id);
    } catch (_) {
      return null;
    }
  }
}
