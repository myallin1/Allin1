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
// food page's left sidebar.
//
// FIX (root cause of "seller shop is open, has a menu item, but
// customer app shows the hotel nowhere"): this used to hard-code only
// ['biriyani', 'home_made'] — 2 of the 6 categories a seller can
// actually pick at registration (seller_onboarding_screen.dart offers
// all of kFoodSubCategories). A seller who registered under 'parotta',
// 'south_indian', 'fast_food', or 'multi_cuisine' had NO sidebar icon
// a customer could ever tap to reach them — permanently invisible
// regardless of isOpen/menu state, since _FoodSidebar only renders
// whatever keys are listed here. Now mirrors kFoodSubCategories in
// full, restoring the "single source of truth" promise in the comment
// above: every registration category is guaranteed a matching browse
// icon, so this class of gap can't recur when a 7th category is added
// later either.
const List<String> kFoodSidebarCategoryKeys = [
  'biriyani',
  'home_made',
  'parotta',
  'south_indian',
  'fast_food',
  'multi_cuisine',
];

FoodSubCategory? foodSubCategoryByKey(String key) {
  for (final c in kFoodSubCategories) {
    if (c.key == key) return c;
  }
  return null;
}
