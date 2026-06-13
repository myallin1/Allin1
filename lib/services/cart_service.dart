// ================================================================
// Cart Service — Allin1 Super App
// Universal cart engine with cross-seller protection
// ================================================================

import 'dart:async';

class CartItem {
  final String id;
  final String sellerId;
  final String name;
  final double price;
  final int quantity;
  final String? image;
  final String? category;

  CartItem({
    required this.id,
    required this.sellerId,
    required this.name,
    required this.price,
    this.quantity = 1,
    this.image,
    this.category,
  });

  CartItem copyWith({int? quantity}) {
    return CartItem(
      id: id,
      sellerId: sellerId,
      name: name,
      price: price,
      quantity: quantity ?? this.quantity,
      image: image,
      category: category,
    );
  }

  double get total => price * quantity;
}

class CartService {
  static final CartService _instance = CartService._internal();
  factory CartService() => _instance;
  CartService._internal();

  final List<CartItem> _items = [];
  final _cartController = StreamController<List<CartItem>>.broadcast();
  String? _currentSellerId;
  String? _currentSellerName;

  // ── Stream for UI Updates ───────────────────────────────────
  Stream<List<CartItem>> get cartStream => _cartController.stream;
  List<CartItem> get items => List.unmodifiable(_items);
  String? get currentSellerId => _currentSellerId;
  String? get currentSellerName => _currentSellerName;

  // ── Cart Statistics ─────────────────────────────────────────
  int get itemCount => _items.fold(0, (sum, item) => sum + item.quantity);

  double get subtotal => _items.fold(0, (sum, item) => sum + item.total);

  bool get isEmpty => _items.isEmpty;

  bool get isNotEmpty => _items.isNotEmpty;

  // ── Add Item (With Cross-Seller Check) ──────────────────────
  Future<bool> addItem(CartItem newItem) async {
    // Check if cart has items from different seller
    if (_currentSellerId != null && newItem.sellerId != _currentSellerId) {
      return false; // Cross-seller conflict - caller should show dialog
    }

    final existingIndex = _items.indexWhere((item) => item.id == newItem.id);

    if (existingIndex >= 0) {
      // Update quantity
      final existingItem = _items[existingIndex];
      _items[existingIndex] = existingItem.copyWith(
        quantity: existingItem.quantity + newItem.quantity,
      );
    } else {
      // Add new item
      _items.add(newItem);
      _currentSellerId = newItem.sellerId;
    }

    _notifyListeners();
    return true;
  }

  // ── Remove Item ─────────────────────────────────────────────
  void removeItem(String itemId) {
    _items.removeWhere((item) => item.id == itemId);

    if (_items.isEmpty) {
      _currentSellerId = null;
      _currentSellerName = null;
    }

    _notifyListeners();
  }

  // ── Update Quantity ─────────────────────────────────────────
  void updateQuantity(String itemId, int quantity) {
    if (quantity <= 0) {
      removeItem(itemId);
      return;
    }

    final index = _items.indexWhere((item) => item.id == itemId);
    if (index >= 0) {
      _items[index] = _items[index].copyWith(quantity: quantity);
      _notifyListeners();
    }
  }

  // ── Clear Cart ──────────────────────────────────────────────
  void clear() {
    _items.clear();
    _currentSellerId = null;
    _currentSellerName = null;
    _notifyListeners();
  }

  // ── Set Current Seller ──────────────────────────────────────
  void setCurrentSeller(String sellerId, String sellerName) {
    _currentSellerId = sellerId;
    _currentSellerName = sellerName;
  }

  // ── Check Cross-Seller Conflict ─────────────────────────────
  bool hasCrossSellerConflict(String sellerId) {
    return _currentSellerId != null && _currentSellerId != sellerId;
  }

  // ── Get Items by Category ───────────────────────────────────
  Map<String, List<CartItem>> getItemsByCategory() {
    final Map<String, List<CartItem>> categorized = {};

    for (final item in _items) {
      final category = item.category ?? 'Other';
      categorized.putIfAbsent(category, () => []);
      categorized[category]!.add(item);
    }

    return categorized;
  }

  // ── Notify Listeners ────────────────────────────────────────
  void _notifyListeners() {
    if (!_cartController.isClosed) {
      _cartController.add(List.unmodifiable(_items));
    }
  }

  // ── Dispose ─────────────────────────────────────────────────
  void dispose() {
    _cartController.close();
  }
}
