import 'package:flutter_test/flutter_test.dart';
import 'package:erode_superapp/models/signature_mobile_models.dart';
import 'package:erode_superapp/services/signature_mobile_service.dart';

void main() {
  group('Signature Mobile Models & Service Tests', () {
    test('SignatureProduct calculations and serialization', () {
      const product = SignatureProduct(
        id: 'p1',
        name: 'iPhone 15 Pro',
        brand: 'Apple',
        category: SignatureCategory.newMobile,
        price: 120000,
        mrp: 134900,
        batteryHealth: 100,
        storage: '256GB',
        warrantyText: '1 Year Apple Warranty',
        imageUrl: 'https://example.com/ip15.jpg',
      );

      expect(product.discountPercent, 11.0);
      final map = product.toMap();
      expect(map['name'], 'iPhone 15 Pro');
      expect(map['category'], 'new_mobile');
      expect(map['price'], 120000);

      final fromMap = SignatureProduct.fromMap('p1', map);
      expect(fromMap.id, 'p1');
      expect(fromMap.brand, 'Apple');
      expect(fromMap.category, SignatureCategory.newMobile);
    });

    test('SignatureOrderItem calculates subtotal correctly', () {
      const item = SignatureOrderItem(
        productId: 'acc_1',
        productName: '65W Fast Charger',
        brand: 'NJ Tech',
        price: 499,
        quantity: 3,
        imageUrl: 'https://example.com/charger.jpg',
      );

      expect(item.total, 1497.0);
      final map = item.toMap();
      expect(map['quantity'], 3);
      expect(map['price'], 499);
    });

    test('SignatureOrder serialization & state transition', () {
      final now = DateTime.now();
      const item = SignatureOrderItem(
        productId: 'used_ip13',
        productName: 'iPhone 13 Mint',
        brand: 'Apple',
        price: 34999,
        imageUrl: 'https://example.com/ip13.jpg',
      );

      final order = SignatureOrder(
        orderId: 'SIG_123',
        customerId: 'cust_001',
        customerName: 'Nizam',
        customerPhone: '9842112233',
        items: const [item],
        subtotal: 34999,
        deliveryFee: 0,
        totalAmount: 34999,
        deliveryAddress: 'Erode Center',
        paymentMethod: 'upi',
        createdAt: now,
        updatedAt: now,
      );

      final map = order.toMap();
      expect(map['customerId'], 'cust_001');
      expect(map['totalAmount'], 34999);
      expect(map['deliveryMode'], 'doorstep');
      expect(map['status'], 'placed');

      final fromMap = SignatureOrder.fromMap('SIG_123', map);
      expect(fromMap.customerName, 'Nizam');
      expect(fromMap.items.length, 1);
      expect(fromMap.items.first.productId, 'used_ip13');
    });

    test('Curated catalog contains New, Used, and Spares categories', () {
      final catalog = SignatureMobileService.kCuratedSignatureCatalog;
      expect(catalog.isNotEmpty, isTrue);

      final newPhones = catalog.where((p) => p.category == SignatureCategory.newMobile).toList();
      final usedPhones = catalog.where((p) => p.category == SignatureCategory.usedMobile).toList();
      final accessories = catalog.where((p) => p.category == SignatureCategory.accessory).toList();
      final spares = catalog.where((p) => p.category == SignatureCategory.sparePart).toList();

      expect(newPhones.isNotEmpty, isTrue);
      expect(usedPhones.isNotEmpty, isTrue);
      expect(accessories.isNotEmpty, isTrue);
      expect(spares.isNotEmpty, isTrue);

      // Verify certified used phones have battery health
      for (final p in usedPhones) {
        expect(p.batteryHealth, isNotNull);
        expect(p.batteryHealth! > 80, isTrue);
      }
    });
  });
}
