// ================================================================
// Master Default Menu — Predefined Food Catalog
// Allin1 Super App — Sellers toggle ON items they stock & set price
// ================================================================

class DefaultMenuItem {
  final String id;
  final String name;
  final String category;
  final String emoji;
  final bool isVeg;
  final List<String> tags;
  final List<String> suggestedVariants;

  const DefaultMenuItem({
    required this.id,
    required this.name,
    required this.category,
    required this.emoji,
    this.isVeg = true,
    this.tags = const [],
    this.suggestedVariants = const [],
  });
}

class DefaultMenuData {
  static const List<DefaultMenuItem> items = [
    // ── Biriyani & Rice ────────────────────────────────────────
    DefaultMenuItem(
      id: 'chicken_biriyani',
      name: 'Chicken Biriyani',
      category: 'biriyani_rice',
      emoji: '🍗',
      isVeg: false,
      tags: ['bestseller', 'popular'],
    ),
    DefaultMenuItem(
      id: 'mutton_biriyani',
      name: 'Mutton Biriyani',
      category: 'biriyani_rice',
      emoji: '🐐',
      isVeg: false,
      tags: ['bestseller', 'premium'],
    ),
    DefaultMenuItem(
      id: 'egg_biriyani',
      name: 'Egg Biriyani',
      category: 'biriyani_rice',
      emoji: '🥚',
      isVeg: false,
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'veg_biriyani',
      name: 'Veg Biriyani',
      category: 'biriyani_rice',
      emoji: '🥕',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'chicken_fried_rice',
      name: 'Chicken Fried Rice',
      category: 'biriyani_rice',
      emoji: '🍚',
      isVeg: false,
    ),
    DefaultMenuItem(
      id: 'veg_fried_rice',
      name: 'Veg Fried Rice',
      category: 'biriyani_rice',
      emoji: '🍚',
    ),
    DefaultMenuItem(
      id: 'ghee_rice',
      name: 'Ghee Rice',
      category: 'biriyani_rice',
      emoji: '🍚',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'lemon_rice',
      name: 'Lemon Rice',
      category: 'biriyani_rice',
      emoji: '🍋',
    ),
    DefaultMenuItem(
      id: 'curd_rice',
      name: 'Curd Rice',
      category: 'biriyani_rice',
      emoji: '🥣',
    ),
    DefaultMenuItem(
      id: 'tamarind_rice',
      name: 'Tamarind Rice / Puliyodharai',
      category: 'biriyani_rice',
      emoji: '🍛',
    ),

    // ── Parotta & Breads ────────────────────────────────────────
    DefaultMenuItem(
      id: 'plain_parotta',
      name: 'Plain Parotta',
      category: 'parotta_bread',
      emoji: '🫓',
      tags: ['bestseller'],
    ),
    DefaultMenuItem(
      id: 'malai_parotta',
      name: 'Malai Parotta',
      category: 'parotta_bread',
      emoji: '🫓',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'chilli_parotta',
      name: 'Chilli Parotta',
      category: 'parotta_bread',
      emoji: '🌶️',
      isVeg: false,
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'kothu_parotta',
      name: 'Kothu Parotta (Chicken)',
      category: 'parotta_bread',
      emoji: '🍛',
      isVeg: false,
      tags: ['bestseller'],
    ),
    DefaultMenuItem(
      id: 'kothu_parotta_veg',
      name: 'Kothu Parotta (Veg)',
      category: 'parotta_bread',
      emoji: '🍛',
    ),
    DefaultMenuItem(
      id: 'chapati',
      name: 'Chapati',
      category: 'parotta_bread',
      emoji: '🫓',
    ),
    DefaultMenuItem(
      id: 'naan_butter',
      name: 'Butter Naan',
      category: 'parotta_bread',
      emoji: '🫓',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'naan_garlic',
      name: 'Garlic Naan',
      category: 'parotta_bread',
      emoji: '🫓',
    ),
    DefaultMenuItem(
      id: 'poori',
      name: 'Poori',
      category: 'parotta_bread',
      emoji: '🫓',
    ),

    // ── Curries & Gravies ───────────────────────────────────────
    DefaultMenuItem(
      id: 'chicken_gravy',
      name: 'Chicken Gravy',
      category: 'curry_gravy',
      emoji: '🍗',
      isVeg: false,
      tags: ['bestseller', 'popular'],
    ),
    DefaultMenuItem(
      id: 'mutton_gravy',
      name: 'Mutton Gravy',
      category: 'curry_gravy',
      emoji: '🥩',
      isVeg: false,
      tags: ['premium'],
    ),
    DefaultMenuItem(
      id: 'chicken_65',
      name: 'Chicken 65',
      category: 'curry_gravy',
      emoji: '🍗',
      isVeg: false,
      tags: ['bestseller', 'popular'],
    ),
    DefaultMenuItem(
      id: 'chilli_chicken',
      name: 'Chilli Chicken',
      category: 'curry_gravy',
      emoji: '🌶️',
      isVeg: false,
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'pepper_chicken',
      name: 'Pepper Chicken',
      category: 'curry_gravy',
      emoji: '🌶️',
      isVeg: false,
    ),
    DefaultMenuItem(
      id: 'fish_fry',
      name: 'Fish Fry / Meen Fry',
      category: 'curry_gravy',
      emoji: '🐟',
      isVeg: false,
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'prawn_fry',
      name: 'Prawn Fry',
      category: 'curry_gravy',
      emoji: '🦐',
      isVeg: false,
      tags: ['premium'],
    ),
    DefaultMenuItem(
      id: 'dal_tadka',
      name: 'Dal Tadka',
      category: 'curry_gravy',
      emoji: '🥘',
    ),
    DefaultMenuItem(
      id: 'paneer_butter_masala',
      name: 'Paneer Butter Masala',
      category: 'curry_gravy',
      emoji: '🧈',
      tags: ['bestseller', 'popular'],
    ),
    DefaultMenuItem(
      id: 'mushroom_gravy',
      name: 'Mushroom Gravy',
      category: 'curry_gravy',
      emoji: '🍄',
    ),
    DefaultMenuItem(
      id: 'veg_kurma',
      name: 'Veg Kurma',
      category: 'curry_gravy',
      emoji: '🥕',
    ),
    DefaultMenuItem(
      id: 'sambar',
      name: 'Sambar',
      category: 'curry_gravy',
      emoji: '🥘',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'rasam',
      name: 'Rasam',
      category: 'curry_gravy',
      emoji: '🍲',
    ),

    // ── Starters & Snacks ──────────────────────────────────────
    DefaultMenuItem(
      id: 'chicken_lollipop',
      name: 'Chicken Lollipop',
      category: 'starter_snack',
      emoji: '🍗',
      isVeg: false,
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'chicken_tikka',
      name: 'Chicken Tikka',
      category: 'starter_snack',
      emoji: '🥩',
      isVeg: false,
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'paneer_tikka',
      name: 'Paneer Tikka',
      category: 'starter_snack',
      emoji: '🧀',
    ),
    DefaultMenuItem(
      id: 'gobi_manchurian',
      name: 'Gobi Manchurian',
      category: 'starter_snack',
      emoji: '🥦',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'chilli_gobi',
      name: 'Chilli Gobi',
      category: 'starter_snack',
      emoji: '🌶️',
    ),
    DefaultMenuItem(
      id: 'baby_corn_manchurian',
      name: 'Baby Corn Manchurian',
      category: 'starter_snack',
      emoji: '🌽',
    ),
    DefaultMenuItem(
      id: 'samosa',
      name: 'Samosa',
      category: 'starter_snack',
      emoji: '🥟',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'cutlet',
      name: 'Cutlet (Veg)',
      category: 'starter_snack',
      emoji: '🥟',
    ),
    DefaultMenuItem(
      id: 'bajji_mixture',
      name: 'Bajji / Mixture',
      category: 'starter_snack',
      emoji: '🍟',
    ),

    // ── Beverages ───────────────────────────────────────────────
    DefaultMenuItem(
      id: 'tea',
      name: 'Tea / Chai',
      category: 'beverage',
      emoji: '☕',
      tags: ['bestseller'],
    ),
    DefaultMenuItem(
      id: 'coffee',
      name: 'Coffee',
      category: 'beverage',
      emoji: '☕',
      tags: ['bestseller'],
    ),
    DefaultMenuItem(
      id: 'butter_milk',
      name: 'Butter Milk / Neer Mor',
      category: 'beverage',
      emoji: '🥛',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'lassi',
      name: 'Lassi (Sweet / Salt)',
      category: 'beverage',
      emoji: '🥤',
    ),
    DefaultMenuItem(
      id: 'soda',
      name: 'Soda / Lime Soda',
      category: 'beverage',
      emoji: '🥤',
    ),
    DefaultMenuItem(
      id: 'fruit_juice',
      name: 'Fruit Juice',
      category: 'beverage',
      emoji: '🧃',
    ),
    DefaultMenuItem(
      id: 'water_bottle',
      name: 'Water Bottle',
      category: 'beverage',
      emoji: '💧',
      tags: ['popular'],
    ),

    // ── Desserts ────────────────────────────────────────────────
    DefaultMenuItem(
      id: 'payasam',
      name: 'Payasam / Kheer',
      category: 'dessert',
      emoji: '🍮',
      tags: ['popular'],
    ),
    DefaultMenuItem(
      id: 'gulab_jamun',
      name: 'Gulab Jamun',
      category: 'dessert',
      emoji: '🍡',
      tags: ['bestseller'],
    ),
    DefaultMenuItem(
      id: 'ice_cream',
      name: 'Ice Cream',
      category: 'dessert',
      emoji: '🍦',
    ),
    DefaultMenuItem(
      id: 'jigarthanda',
      name: 'Jigarthanda',
      category: 'dessert',
      emoji: '🥤',
    ),
  ];

  // ── Category buckets for display ─────────────────────────────
  static const categoryLabels = {
    'biriyani_rice': 'Biriyani & Rice',
    'parotta_bread': 'Parotta & Breads',
    'curry_gravy': 'Curries & Gravies',
    'starter_snack': 'Starters & Snacks',
    'beverage': 'Beverages',
    'dessert': 'Desserts',
  };

  static const categoryOrder = [
    'biriyani_rice',
    'parotta_bread',
    'curry_gravy',
    'starter_snack',
    'beverage',
    'dessert',
  ];

  static Map<String, List<DefaultMenuItem>> get groupedByCategory {
    final map = <String, List<DefaultMenuItem>>{};
    for (final item in items) {
      map.putIfAbsent(item.category, () => []);
      map[item.category]!.add(item);
    }
    return map;
  }

  /// Filter items by hotelType ('veg', 'non-veg', 'both')
  static List<DefaultMenuItem> filterByHotelType(String hotelType) {
    if (hotelType == 'both') return items;
    if (hotelType == 'veg') {
      return items.where((item) => item.isVeg).toList();
    }
    return items;
  }
}
