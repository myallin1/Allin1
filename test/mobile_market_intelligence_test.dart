import 'package:erode_superapp/services/whatsapp/mobile_market_intelligence_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MobileMarketIntelligenceService Parser Tests', () {
    test('parses single-line iPhone listing with storage and BH', () {
      const line = 'iPhone 13 128GB Starlight 87% BH pristine condition ₹34,500';
      final results = MobileMarketIntelligenceService.parseDealerPost(line);

      expect(results.length, 1);
      final item = results.first;
      expect(item.brand, 'Apple');
      expect(item.storage, '128GB');
      expect(item.batteryHealth, 87);
      expect(item.price, 34500.0);
      expect(item.condition, 'Like New / Mint');
    });

    test('parses Android listing with RAM/storage and price', () {
      const line = 'OnePlus 11R 8/128 Black box bill included @23000';
      final results = MobileMarketIntelligenceService.parseDealerPost(line);

      expect(results.length, 1);
      final item = results.first;
      expect(item.brand, 'OnePlus');
      expect(item.ram, '8GB');
      expect(item.storage, '128GB');
      expect(item.price, 23000.0);
    });

    test('parses sealed / brand new condition correctly', () {
      const line = 'Redmi Note 13 Pro 8/256 Seal Pack ₹18,500';
      final results = MobileMarketIntelligenceService.parseDealerPost(line);

      expect(results.length, 1);
      final item = results.first;
      expect(item.brand, 'Redmi');
      expect(item.storage, '256GB');
      expect(item.price, 18500.0);
      expect(item.isNew, true);
      expect(item.condition, 'Sealed / Brand New');
    });

    test('parses multi-line dealer broadcast dump', () {
      const post = '''
📱 Today Special Deals - Erode Mobiles 📱
iPhone 14 128GB Blue 94% BH ₹42,000
Vivo V29 8/128 Rose Gold with box ₹16,500
Samsung S23 Ultra 12/256 Cream ₹58,000
Invalid noise line with no price
Realme 11 Pro 8/256 ₹13,000
''';
      final results = MobileMarketIntelligenceService.parseDealerPost(
        post,
        dealerName: 'Erode Mobiles',
      );

      expect(results.length, 4);
      expect(results[0].brand, 'Apple');
      expect(results[0].price, 42000.0);
      expect(results[0].dealerName, 'Erode Mobiles');

      expect(results[1].brand, 'Vivo');
      expect(results[1].price, 16500.0);

      expect(results[2].brand, 'Samsung');
      expect(results[2].price, 58000.0);

      expect(results[3].brand, 'Realme');
      expect(results[3].price, 13000.0);
    });

    test('ignores noise lines without valid phone prices', () {
      const noise = 'Good morning dealers. Please share today requirement.';
      final results = MobileMarketIntelligenceService.parseDealerPost(noise);
      expect(results, isEmpty);
    });
  });
}
