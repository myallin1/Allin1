// ================================================================
// mobile_market_intelligence_service.dart — Dealer Group Parser & Market Rates
// ================================================================
// Extracts and aggregates second-hand & new mobile prices from WhatsApp
// dealer group posts, storing intelligence into Firestore and feeding
// Chitti AI's market price quoting brain.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

@immutable
class MobileMarketEntry {
  const MobileMarketEntry({
    required this.id,
    required this.brand,
    required this.model,
    required this.price,
    this.storage,
    this.ram,
    this.batteryHealth,
    this.condition = 'Good',
    this.rawText = '',
    this.dealerName,
    this.dealerPhone,
    this.timestamp,
    this.isNew = false,
  });

  final String id;
  final String brand;
  final String model;
  final double price;
  final String? storage;
  final String? ram;
  final int? batteryHealth;
  final String condition;
  final String rawText;
  final String? dealerName;
  final String? dealerPhone;
  final DateTime? timestamp;
  final bool isNew;

  Map<String, dynamic> toMap() {
    return {
      'brand': brand,
      'model': model,
      'normalizedModel': '${brand.toLowerCase()} ${model.toLowerCase()}',
      'price': price,
      'storage': storage,
      'ram': ram,
      'batteryHealth': batteryHealth,
      'condition': condition,
      'rawText': rawText,
      'dealerName': dealerName,
      'dealerPhone': dealerPhone,
      'timestamp': timestamp != null
          ? Timestamp.fromDate(timestamp!)
          : FieldValue.serverTimestamp(),
      'isNew': isNew,
    };
  }

  factory MobileMarketEntry.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};
    final ts = data['timestamp'];
    DateTime? dt;
    if (ts is Timestamp) {
      dt = ts.toDate();
    } else if (ts is String) {
      dt = DateTime.tryParse(ts);
    }

    return MobileMarketEntry(
      id: doc.id,
      brand: data['brand']?.toString() ?? 'Other',
      model: data['model']?.toString() ?? '',
      price: (data['price'] as num?)?.toDouble() ?? 0.0,
      storage: data['storage']?.toString(),
      ram: data['ram']?.toString(),
      batteryHealth: (data['batteryHealth'] as num?)?.toInt(),
      condition: data['condition']?.toString() ?? 'Good',
      rawText: data['rawText']?.toString() ?? '',
      dealerName: data['dealerName']?.toString(),
      dealerPhone: data['dealerPhone']?.toString(),
      timestamp: dt,
      isNew: data['isNew'] == true,
    );
  }
}

class MobileMarketIntelligenceService {
  MobileMarketIntelligenceService._();

  static const String kCollection = 'market_mobile_intelligence';

  static final List<String> _knownBrands = [
    'Apple',
    'iPhone',
    'Samsung',
    'OnePlus',
    'Vivo',
    'Oppo',
    'Realme',
    'Redmi',
    'Xiaomi',
    'POCO',
    'iQOO',
    'Motorola',
    'Moto',
    'Nothing',
    'Google Pixel',
    'Pixel',
    'Infinix',
    'Tecno',
    'Honor',
  ];

  /// Parses a multi-line or single-line WhatsApp group broadcast message
  /// into a list of structured MobileMarketEntry objects.
  static List<MobileMarketEntry> parseDealerPost(
    String rawText, {
    String? dealerName,
    String? dealerPhone,
  }) {
    final lines = rawText.split('\n');
    final List<MobileMarketEntry> results = [];

    for (final line in lines) {
      final trimmed = line.trim();
      if (trimmed.isEmpty || trimmed.length < 5) continue;

      final entry = _parseSingleLine(
        trimmed,
        dealerName: dealerName,
        dealerPhone: dealerPhone,
      );
      if (entry != null) {
        results.add(entry);
      }
    }
    return results;
  }

  static MobileMarketEntry? _parseSingleLine(
    String line, {
    String? dealerName,
    String? dealerPhone,
  }) {
    final lower = line.toLowerCase();

    // Extract price
    final priceRegex = RegExp(
      r'(?:₹|rs\.?|inr|rate|price|@|:)?\s*([0-9]{1,2},[0-9]{3}|[0-9]{4,6})(?:\s*\/|\s*k|\s*only|\s*fixed|\s*negotiable|\b)',
      caseSensitive: false,
    );
    final priceMatch = priceRegex.firstMatch(line);
    if (priceMatch == null) return null;

    final rawPriceDigits =
        priceMatch.group(1)?.replaceAll(',', '').replaceAll(' ', '') ?? '';
    final priceVal = double.tryParse(rawPriceDigits);
    if (priceVal == null || priceVal < 1000 || priceVal > 250000) return null;

    // Detect brand
    String detectedBrand = 'Other';
    for (final b in _knownBrands) {
      if (lower.contains(b.toLowerCase())) {
        detectedBrand = b == 'iPhone' ? 'Apple' : b;
        if (detectedBrand == 'Moto') detectedBrand = 'Motorola';
        if (detectedBrand == 'Pixel') detectedBrand = 'Google Pixel';
        break;
      }
    }

    // Extract Battery Health (BH / Battery, e.g. 87% BH or BH 87%)
    int? batteryHealth;
    final bhPrefixMatch = RegExp(r'(?:bh|battery)\s*[:=-]?\s*([0-9]{2,3})\s*%?', caseSensitive: false).firstMatch(line);
    final bhSuffixMatch = RegExp(r'\b([0-9]{2,3})\s*%\s*(?:bh|battery)\b', caseSensitive: false).firstMatch(line);
    if (bhPrefixMatch != null) {
      batteryHealth = int.tryParse(bhPrefixMatch.group(1) ?? '');
    } else if (bhSuffixMatch != null) {
      batteryHealth = int.tryParse(bhSuffixMatch.group(1) ?? '');
    }

    // Extract Storage / RAM
    String? storage;
    String? ram;
    final storageMatch = RegExp(
      r'\b(32|64|128|256|512|1024|1tb)\s*(?:gb|tb)?\b',
      caseSensitive: false,
    ).firstMatch(line);
    if (storageMatch != null) {
      storage = storageMatch.group(1)!.toUpperCase();
      if (!storage.endsWith('GB') && !storage.endsWith('TB')) {
        storage = '$storage${storage == '1TB' ? '' : 'GB'}';
      }
    }

    final ramMatch = RegExp(r'\b(3|4|6|8|12|16)\s*(?:gb|\/|\+)', caseSensitive: false)
        .firstMatch(line);
    if (ramMatch != null) {
      ram = '${ramMatch.group(1)}GB';
    }

    // Detect Condition
    String condition = 'Good';
    if (lower.contains('seal') || lower.contains('brand new') || lower.contains('sealed')) {
      condition = 'Sealed / Brand New';
    } else if (lower.contains('pristine') || lower.contains('mint') || lower.contains('like new') || lower.contains('demo')) {
      condition = 'Like New / Mint';
    } else if (lower.contains('scratch') || lower.contains('minor') || lower.contains('dent')) {
      condition = 'Fair';
    }

    final isNew = condition.contains('New') || lower.contains('new box');

    // Clean model title
    var cleanModel = line
        .replaceAll(priceRegex, '')
        .replaceAll(RegExp(r'(?:bh|battery)\s*[:=-]?\s*[0-9]{2,3}\s*%?', caseSensitive: false), '')
        .replaceAll(RegExp(r'[\(\)\*\-_]+', caseSensitive: false), ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();

    if (cleanModel.length > 40) {
      cleanModel = cleanModel.substring(0, 40).trim();
    }

    final id = 'm_${DateTime.now().microsecondsSinceEpoch}_${priceVal.toInt()}';

    return MobileMarketEntry(
      id: id,
      brand: detectedBrand,
      model: cleanModel.isEmpty ? detectedBrand : cleanModel,
      price: priceVal,
      storage: storage,
      ram: ram,
      batteryHealth: batteryHealth,
      condition: condition,
      rawText: line,
      dealerName: dealerName,
      dealerPhone: dealerPhone,
      timestamp: DateTime.now(),
      isNew: isNew,
    );
  }

  /// Saves a batch of parsed dealer entries to Firestore
  static Future<int> saveEntries(List<MobileMarketEntry> entries) async {
    if (entries.isEmpty) return 0;
    final batch = FirebaseFirestore.instance.batch();
    final col = FirebaseFirestore.instance.collection(kCollection);

    for (final entry in entries) {
      final docRef = col.doc(entry.id);
      batch.set(docRef, entry.toMap());
    }

    try {
      await batch.commit();
      return entries.length;
    } catch (e) {
      debugPrint('[MobileMarketIntelligence] Save error: $e');
      return 0;
    }
  }

  /// Queries market intelligence for a specific phone model query (e.g. "iPhone 13")
  static Future<List<MobileMarketEntry>> queryMarketPrices(String query) async {
    final cleanQuery = query.toLowerCase().trim();
    if (cleanQuery.isEmpty) return [];

    try {
      final snap = await FirebaseFirestore.instance
          .collection(kCollection)
          .orderBy('timestamp', descending: true)
          .limit(100)
          .get();

      final all = snap.docs.map((d) => MobileMarketEntry.fromDoc(d)).toList();
      return all.where((entry) {
        final full = '${entry.brand} ${entry.model} ${entry.storage ?? ''}'.toLowerCase();
        return cleanQuery.split(' ').every((token) => full.contains(token));
      }).toList();
    } catch (e) {
      debugPrint('[MobileMarketIntelligence] Query error: $e');
      return [];
    }
  }

  /// Computes market analysis summary for a model
  static Future<({
    double averagePrice,
    double minPrice,
    double maxPrice,
    double recommendedSellingPrice,
    int totalDeals,
    List<MobileMarketEntry> recentDeals,
  })?> getMarketSummary(String modelQuery) async {
    final deals = await queryMarketPrices(modelQuery);
    if (deals.isEmpty) return null;

    final prices = deals.map((d) => d.price).toList()..sort();
    final total = prices.reduce((a, b) => a + b);
    final avg = total / prices.length;
    final min = prices.first;
    final max = prices.last;

    // NJ Tech recommended selling price with ~10-15% margin
    final margin = avg < 15000 ? 1500.0 : (avg * 0.10);
    final recommended = (avg + margin).roundToDouble();

    return (
      averagePrice: avg,
      minPrice: min,
      maxPrice: max,
      recommendedSellingPrice: recommended,
      totalDeals: deals.length,
      recentDeals: deals.take(5).toList(),
    );
  }
}
