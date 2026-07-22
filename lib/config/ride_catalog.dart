import 'package:flutter/material.dart';

/// Single source of truth for the taxi / delivery vehicle catalog.
///
/// Both the entry category chips (bike_booking_screen.dart) and the
/// vehicle selection sheet (vehicle_selection_bottom_sheet.dart) read
/// from [kRideCatalog], so each vehicle is defined exactly once. Adding a
/// vehicle here makes it appear in both the entry chips and the sheet.
@immutable
class RideCatalogEntry {
  /// Canonical booking key, written to rides/{id}.vehicleType.
  final String key;

  /// LocalizationService key for the short chip label.
  final String l10nKey;

  /// Full title shown in the selection sheet.
  final String sheetTitle;
  final String subtitle;
  final String description;
  final String eta;
  final int capacity;

  /// Emoji rendered in the sheet card.
  final String emoji;

  /// Chip / map-marker image. When the asset is absent the UI falls back
  /// to [fallbackIcon] (both the chip and the map marker have an
  /// errorBuilder), so cargo / SOS types can ship without a bundled image.
  final String assetPath;
  final IconData fallbackIcon;

  /// Sheet accent + selected-state background.
  final Color color;
  final Color bgColor;

  /// Normalized category written to rides/{id}.category, matched against
  /// the hero's registered profile category (e.g. cab -> car).
  final String heroCategory;

  /// Extra keys that resolve to this entry (hero profile / legacy values).
  final List<String> aliases;

  const RideCatalogEntry({
    required this.key,
    required this.l10nKey,
    required this.sheetTitle,
    required this.subtitle,
    required this.description,
    required this.eta,
    required this.capacity,
    required this.emoji,
    required this.assetPath,
    required this.fallbackIcon,
    required this.color,
    required this.bgColor,
    required this.heroCategory,
    this.aliases = const <String>[],
  });
}

const Color _kBrandPink = Color(0xFFFF4FA3);
const Color _kBrandPinkBg = Color(0x1AFF4FA3);
const Color _kEmergencyRed = Color(0xFFFF5252);
const Color _kEmergencyRedBg = Color(0x1AFF5252);

/// Ordered catalog. The first four are passenger rides (shown first in the
/// entry chip row); cargo + SOS follow and scroll into view.
const List<RideCatalogEntry> kRideCatalog = <RideCatalogEntry>[
  RideCatalogEntry(
    key: 'bike',
    l10nKey: 'bike_label',
    sheetTitle: 'Bike Taxi',
    subtitle: 'Fast & economical',
    description: 'Perfect for short trips',
    eta: '2-3 mins',
    capacity: 1,
    emoji: '🏍️',
    assetPath: 'assets/images/top_bike.png',
    fallbackIcon: Icons.two_wheeler_rounded,
    color: _kBrandPink,
    bgColor: _kBrandPinkBg,
    heroCategory: 'bike',
  ),
  RideCatalogEntry(
    key: 'auto',
    l10nKey: 'auto_label',
    sheetTitle: 'Auto Rickshaw',
    subtitle: 'Comfortable & reliable',
    description: 'Great for small groups',
    eta: '3-5 mins',
    capacity: 3,
    emoji: '🛺',
    assetPath: 'assets/images/top_auto.png',
    fallbackIcon: Icons.electric_rickshaw_rounded,
    color: _kBrandPink,
    bgColor: _kBrandPinkBg,
    heroCategory: 'auto',
  ),
  RideCatalogEntry(
    key: 'cab',
    l10nKey: 'cab_label',
    sheetTitle: 'Mini Cab',
    subtitle: 'Premium & spacious',
    description: 'Luxury experience',
    eta: '4-6 mins',
    capacity: 4,
    emoji: '🚘',
    assetPath: 'assets/images/top_cab.png',
    fallbackIcon: Icons.local_taxi_rounded,
    color: _kBrandPink,
    bgColor: _kBrandPinkBg,
    heroCategory: 'car',
    aliases: <String>['car', 'mini'],
  ),
  RideCatalogEntry(
    key: 'parcel',
    l10nKey: 'parcel_label',
    sheetTitle: 'Parcel Delivery',
    subtitle: 'Fast package drop',
    description: 'Perfect for local parcel trips',
    eta: '3-5 mins',
    capacity: 1,
    emoji: '📦',
    assetPath: 'assets/images/top_parcel.png',
    fallbackIcon: Icons.inventory_2_rounded,
    color: _kBrandPink,
    bgColor: _kBrandPinkBg,
    heroCategory: 'parcel',
  ),
  RideCatalogEntry(
    key: 'mini_truck',
    l10nKey: 'mini_truck_label',
    sheetTitle: 'Mini Truck',
    subtitle: 'Small cargo & goods',
    description: 'For bulky local deliveries',
    eta: '6-10 mins',
    capacity: 1,
    emoji: '🛻',
    assetPath: 'assets/images/top_mini_truck.png',
    fallbackIcon: Icons.local_shipping_rounded,
    color: _kBrandPink,
    bgColor: _kBrandPinkBg,
    heroCategory: 'mini_truck',
    aliases: <String>['mini-truck', 'truck'],
  ),
  RideCatalogEntry(
    key: 'lorry',
    l10nKey: 'lorry_label',
    sheetTitle: 'Lorry',
    subtitle: 'Heavy cargo transport',
    description: 'For large-scale hauling',
    eta: '8-15 mins',
    capacity: 1,
    emoji: '🚚',
    assetPath: 'assets/images/top_lorry.png',
    fallbackIcon: Icons.local_shipping_rounded,
    color: _kBrandPink,
    bgColor: _kBrandPinkBg,
    heroCategory: 'lorry',
  ),
  RideCatalogEntry(
    key: 'emergency_manpower',
    l10nKey: 'emergency_manpower_label',
    sheetTitle: 'Emergency Manpower',
    subtitle: 'SOS first responder',
    description: 'Urgent on-ground assistance',
    eta: '5-8 mins',
    capacity: 1,
    emoji: '🚨',
    assetPath: 'assets/images/top_sos.png',
    fallbackIcon: Icons.warning_amber_rounded,
    color: _kEmergencyRed,
    bgColor: _kEmergencyRedBg,
    heroCategory: 'emergency_manpower',
    aliases: <String>['manpower'],
  ),
];

/// Resolves any booking key, hero profile category, or legacy alias to a
/// catalog entry. Returns null when nothing matches (callers fall back to
/// bike, preserving previous behaviour).
RideCatalogEntry? rideCatalogLookup(String? vehicleType) {
  final key = vehicleType?.trim().toLowerCase() ?? '';
  if (key.isEmpty) {
    return null;
  }
  for (final entry in kRideCatalog) {
    if (entry.key == key || entry.aliases.contains(key)) {
      return entry;
    }
  }
  return null;
}

/// Booking [vehicleType] -> normalized hero category (cab -> car, etc.).
/// Mirrors the old _normalizeCategoryKey switch, now catalog-driven.
String rideHeroCategory(String vehicleType) {
  return rideCatalogLookup(vehicleType)?.heroCategory ?? 'bike';
}

/// Chip / marker asset for [vehicleType]; bike asset as the fallback.
String rideAssetFor(String vehicleType) {
  return rideCatalogLookup(vehicleType)?.assetPath ??
      'assets/images/top_bike.png';
}

/// Chip / marker fallback icon for [vehicleType].
IconData rideFallbackIcon(String vehicleType) {
  return rideCatalogLookup(vehicleType)?.fallbackIcon ??
      Icons.two_wheeler_rounded;
}
