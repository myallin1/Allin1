// ================================================================
// food_categories.dart
// Single source of truth for food seller sub-categories (e.g.
// 'biriyani', 'home_made'). Used by BOTH seller_onboarding_screen.dart
// (so a hotel/home-cook picks their sub-category at registration) AND
// custom_food_order_screen.dart's left sidebar (so a customer can
// browse sellers filtered by that same sub-category).
//
// Add new sub-categories here only — both the registration form and
// the customer sidebar read from this single list, so a new entry
// here automatically appears in both places.
// ================================================================

class FoodSubCategory {
  final String key;
  final String label;
  final String emoji;

  const FoodSubCategory({
    required this.key,
    required this.label,
    required this.emoji,
  });
}

const List<FoodSubCategory> kFoodSubCategories = [
  FoodSubCategory(key: 'biriyani', label: 'Biriyani & Rice', emoji: '🍛'),
  FoodSubCategory(key: 'home_made', label: 'Home Made Foods', emoji: '🍲'),
  FoodSubCategory(key: 'parotta', label: 'Parotta & Breads', emoji: '🫓'),
  FoodSubCategory(key: 'south_indian', label: 'South Indian Meals', emoji: '🥘'),
  FoodSubCategory(key: 'fast_food', label: 'Fast Food & Snacks', emoji: '🍟'),
  FoodSubCategory(key: 'multi_cuisine', label: 'Multi-Cuisine', emoji: '🍽️'),
];

// Sub-categories shown as quick-browse icons on the customer-facing
// food page's left sidebar. A subset of kFoodSubCategories — kept as
// a separate list (rather than a bool flag on FoodSubCategory) so the
// sidebar's icon set/order can be curated independently of the full
// registration list, without needing to touch both call sites.
const List<String> kFoodSidebarCategoryKeys = ['biriyani', 'home_made'];

FoodSubCategory? foodSubCategoryByKey(String key) {
  for (final c in kFoodSubCategories) {
    if (c.key == key) return c;
  }
  return null;
}
