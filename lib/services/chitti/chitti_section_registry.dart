// ================================================================
// chitti_section_registry.dart — the ONE list of app sections Chitti
// can open, for every app variant.
// ================================================================
// WHY THIS FILE EXISTS (Aug 27 2026 — Nizam: "avanuku taxi and
// transport pathi sonna mattum than pandran ... a to z namma app la
// yenna sonnalum avan panna therila").
//
// Before this, `navigate_to_section` knew about exactly 12 sections,
// hard-coded THREE separate times:
//   1. the tool's `enum` in guru_api_service.dart
//   2. `_screenForSection()` in guru_overlay_service.dart
//   3. `_screenForSection()`/`_sectionLabel()` in guru_chat_screen.dart
// The app has 100+ screens. Anything outside those 12 — My Orders,
// Notifications, Wallet, DMart, Mega Quiz, Invite Friends, the entire
// Hero and Seller apps — could not be opened at all, so Chitti fell
// back to writing a paragraph about it. That is the whole reason the
// agent felt "transport-only".
//
// The fix is structural, not a bigger switch: ONE registry, and the
// tool enum is DERIVED from it. Adding a section here makes it
// instantly reachable by the model, the overlay bubble, and the full
// chat screen at once — there is no second place to remember.
//
// VARIANT SCOPING is part of the design: a Hero must never be offered
// "open Grocery Order" and a customer must never be offered "open Hero
// Earnings", because those screens assume an account type the user
// does not have and would crash or show an empty page. Each entry
// declares which app variants it belongs to, and the enum handed to
// the model is filtered by `currentAppVariant` before the request is
// even built — the model is never shown a section it cannot open.
import 'package:flutter/widgets.dart';

import '../../screens/admin/admin_ai_settings_screen.dart';
import '../../screens/admin/chitti_debug_logs_screen.dart';
import '../../screens/admin/super_admin_home_screen.dart';
import '../../screens/admin/admin_db_usage_screen.dart';
import '../../screens/admin/admin_hero_dispatch_screen.dart';
import '../../screens/admin/admin_new_orders_screen.dart';
import '../../screens/admin/admin_ride_tracking_screen.dart';
import '../../screens/admin/chitti_enquiries_screen.dart';
import '../../screens/admin/admin_seller_approval_screen.dart';
import '../../screens/admin/admin_sos_kyc_approvals_screen.dart';
import '../../screens/admin/admin_wallet_approvals_screen.dart';
import '../../screens/admin/approved_heroes_screen.dart';
import '../../screens/admin/bug_reports_screen.dart';
import '../../screens/admin/erode_offers_management_screen.dart';
import '../../screens/admin/fare_management_screen.dart';
import '../../screens/admin/hero_approvals_screen.dart';
import '../../screens/admin/payments_received_screen.dart';
import '../../screens/admin/admin_dashboard_screen.dart';
import '../../screens/bike_taxi/hero_earnings_screen.dart';
import '../../screens/bike_taxi/hero_history_screen.dart';
import '../../screens/bike_taxi/hero_incomplete_tasks_screen.dart';
import '../../screens/bike_taxi/hero_payment_qr_screen.dart';
import '../../screens/bike_taxi/hero_settings_screen.dart';
import '../../screens/bike_taxi/hero_sos_screen.dart';
import '../../screens/bike_taxi/hero_wallet_screen.dart';
import '../../screens/car_wash_screen.dart';
import '../../screens/cart_screen.dart';
import '../../screens/credentials_screen.dart';
import '../../screens/custom_food_order_screen.dart';
import '../../screens/custom_order_screen.dart';
import '../../screens/dmart_screen.dart';
import '../../screens/earn/earn_dashboard_screen.dart';
import '../../screens/earn/rewards_hub_screen.dart';
import '../../screens/economic_vision_screen.dart';
import '../../screens/eseva_service_screen.dart';
import '../../screens/food_hub_screen.dart';
import '../../screens/grocery_order_screen.dart';
import '../../screens/guru_offer_screen.dart';
import '../../screens/hero_booking_screen.dart';
import '../../screens/invite_friends_screen.dart';
import '../../screens/live_rates_screen.dart';
import '../../screens/mega_quiz_screen.dart';
import '../../screens/mobiles/mobile_hub_screen.dart';
import '../../screens/my_orders_screen.dart';
import '../../screens/nj_tech_service_screen.dart';
import '../../screens/nj_tech_store_screen.dart';
import '../../screens/notifications_screen.dart';
import '../../screens/play_zone_screen.dart';
import '../../screens/printing_service_screen.dart';
import '../../screens/profile_screen.dart';
import '../../screens/rewards/earnings_hub_screen.dart';
import '../../screens/rewards_screen.dart';
import '../../screens/ride_history_screen.dart';
import '../../screens/seller_dashboard_screen.dart';
import '../../screens/seller_settings_screen.dart';
import '../../screens/seller_vertical_picker_screen.dart';
import '../../screens/settings_screen.dart';
import '../../screens/sos_kyc_verification_screen.dart';
import '../../screens/sos_screen.dart';

/// One openable destination.
///
/// [aliases] are NOT for the model — the model gets [key] and
/// [description]. They exist for the offline keyword fallback in the
/// domain router, so a user typing "bill" or "points" still routes to
/// the right tool group without spending an extra API call.
class ChittiSection {
  const ChittiSection({
    required this.key,
    required this.label,
    required this.description,
    required this.variants,
    required this.builder,
    required this.screenType,
    this.aliases = const <String>[],
  });

  /// Stable snake_case id. This is the value in the tool enum, so
  /// renaming one breaks any in-flight conversation.
  final String key;

  /// Human label used in the reply ("Opening $label for you").
  final String label;

  /// One line telling the model when this section is the right answer.
  /// Kept short on purpose: this text is sent on every request that
  /// includes the navigation domain, so every extra word costs money.
  final String description;

  /// Which app builds this section exists in.
  final Set<String> variants;

  final WidgetBuilder builder;

  /// The widget class [builder] returns.
  ///
  /// NEW (Aug 28 2026 — screen awareness). Chitti needs to answer "what
  /// is this page?" about wherever the CUSTOMER navigated themselves,
  /// not just where Chitti sent them. Navigation happens by pushing a
  /// constructed widget, so a runtimeType is the one thing available at
  /// that moment — this is what turns it back into a section, and with
  /// it a human label and a description.
  ///
  /// Declared rather than derived because a WidgetBuilder cannot be
  /// asked what it returns without building it.
  final Type screenType;

  final List<String> aliases;
}

/// Every section Chitti can open, across all four apps.
///
/// Ordered by variant then by how often it is asked for, because the
/// enum is emitted in this order and models weight earlier options
/// slightly more.
const List<ChittiSection> kChittiSections = <ChittiSection>[
  // ── CUSTOMER ────────────────────────────────────────────────────
  ChittiSection(
    key: 'food',
    label: 'Food Genie',
    description: 'Order food from Erode hotels.',
    variants: {'customer'},
    builder: _foodHub,
    screenType: FoodHubScreen,
    aliases: ['food', 'hotel', 'biryani', 'restaurant', 'sapadu', 'saapadu'],
  ),
  ChittiSection(
    key: 'grocery',
    label: 'Grocery',
    description: 'Place a grocery/provisions order.',
    variants: {'customer'},
    builder: _groceryOrder,
    screenType: GroceryOrderScreen,
    aliases: ['grocery', 'provision', 'maligai', 'vegetables'],
  ),
  ChittiSection(
    key: 'dmart',
    label: 'DMart Order',
    description: 'Send a DMart cart screenshot order.',
    variants: {'customer'},
    builder: _dmart,
    screenType: DmartScreen,
    aliases: ['dmart', 'd-mart', 'supermarket'],
  ),
  ChittiSection(
    key: 'electronics',
    label: 'Electronics service',
    description: 'NJ Tech mobile/laptop/AC/fridge repair booking.',
    variants: {'customer'},
    builder: _njTechService,
    screenType: NjTechServiceScreen,
    aliases: ['repair', 'service', 'mobile repair', 'laptop', 'ac', 'fridge'],
  ),
  ChittiSection(
    key: 'electronics_store',
    label: 'NJ Tech Store',
    description: 'Buy electronics and accessories from NJ Tech.',
    variants: {'customer'},
    builder: _njTechStore,
    screenType: NJTechStoreScreen,
    aliases: ['store', 'buy', 'shop', 'accessories'],
  ),
  ChittiSection(
    key: 'mobiles',
    label: 'Mobiles',
    description: 'Browse and buy mobile phones.',
    variants: {'customer'},
    builder: _mobileHub,
    screenType: MobileHubScreen,
    aliases: ['mobile', 'phone', 'smartphone'],
  ),
  ChittiSection(
    key: 'cart',
    label: 'your Cart',
    description: 'The shopping cart with items not yet checked out.',
    variants: {'customer'},
    builder: _cart,
    screenType: CartScreen,
    aliases: ['cart', 'basket'],
  ),
  ChittiSection(
    key: 'my_orders',
    label: 'My Orders',
    description: 'The list of all past and current orders.',
    variants: {'customer'},
    builder: _myOrders,
    screenType: MyOrdersScreen,
    aliases: ['orders', 'my orders', 'order list', 'past orders'],
  ),
  ChittiSection(
    key: 'ride_history',
    label: 'Ride History',
    description: 'Past rides and their fares.',
    variants: {'customer'},
    builder: _rideHistory,
    screenType: RideHistoryScreen,
    aliases: ['ride history', 'past rides', 'trips'],
  ),
  ChittiSection(
    key: 'wallet',
    label: 'your Wallet',
    description: 'Wallet balance, coins, and money added.',
    variants: {'customer'},
    builder: _rewardsHub,
    screenType: RewardsHubScreen,
    aliases: ['wallet', 'balance', 'money', 'coins', 'panam'],
  ),
  ChittiSection(
    key: 'earn',
    label: 'Earn',
    description: 'Ways to earn coins and cashback in the app.',
    variants: {'customer'},
    builder: _earnDashboard,
    screenType: EarnDashboardScreen,
    aliases: ['earn', 'cashback', 'earning'],
  ),
  ChittiSection(
    key: 'rewards',
    label: 'Rewards',
    description: 'Rewards, scratch cards, and redeemable points.',
    variants: {'customer'},
    builder: _rewards,
    screenType: RewardsScreen,
    aliases: ['rewards', 'points', 'scratch card', 'redeem'],
  ),
  ChittiSection(
    key: 'offers',
    label: 'Erode Offers',
    description: 'Current local offers and deals in Erode.',
    variants: {'customer'},
    builder: _offers,
    screenType: GuruOfferScreen,
    aliases: ['offers', 'deals', 'discount', 'coupon'],
  ),
  ChittiSection(
    key: 'game_zone',
    label: 'Game Zone',
    description: 'Play games and win coins.',
    variants: {'customer'},
    builder: _playZone,
    screenType: PlayZoneScreen,
    aliases: ['game', 'games', 'play'],
  ),
  ChittiSection(
    key: 'mega_quiz',
    label: 'Mega Quiz',
    description: 'The daily/weekly Mega Quiz.',
    variants: {'customer'},
    builder: _megaQuiz,
    screenType: MegaQuizScreen,
    aliases: ['quiz', 'mega quiz'],
  ),
  ChittiSection(
    key: 'invite_friends',
    label: 'Invite Friends',
    description: 'Referral link and invite rewards.',
    variants: {'customer'},
    builder: _inviteFriends,
    screenType: InviteFriendsScreen,
    aliases: ['invite', 'refer', 'referral', 'share app'],
  ),
  ChittiSection(
    key: 'notifications',
    label: 'Notifications',
    description: 'All app notifications and alerts.',
    variants: {'customer'},
    builder: _notifications,
    screenType: NotificationsScreen,
    aliases: ['notification', 'alerts', 'messages'],
  ),
  ChittiSection(
    key: 'hero_needs',
    label: 'Hero Booking',
    description: 'Book a Hero for an errand, pickup, or custom help.',
    variants: {'customer'},
    builder: _heroBooking,
    screenType: HeroBookingScreen,
    aliases: ['hero', 'errand', 'pickup', 'help'],
  ),
  ChittiSection(
    key: 'custom_order',
    label: 'Custom Order',
    description: 'Order anything not listed, in the shopper own words.',
    variants: {'customer'},
    builder: _customOrder,
    screenType: CustomOrderScreen,
    aliases: ['custom order', 'anything', 'other'],
  ),
  ChittiSection(
    key: 'custom_food_order',
    label: 'Custom Food Order',
    description: 'Order food from a hotel that is not on the app yet.',
    variants: {'customer'},
    builder: _customFoodOrder,
    screenType: CustomFoodOrderScreen,
    aliases: ['custom food', 'other hotel'],
  ),
  ChittiSection(
    key: 'car_wash',
    label: 'Car Wash',
    description: 'Book a car or bike wash.',
    variants: {'customer'},
    builder: _carWash,
    screenType: CarWashScreen,
    aliases: ['car wash', 'wash', 'cleaning'],
  ),
  ChittiSection(
    key: 'printing',
    label: 'Printing',
    description: 'Printing, xerox, and document services.',
    variants: {'customer'},
    builder: _printing,
    screenType: PrintingServiceScreen,
    aliases: ['print', 'xerox', 'photocopy'],
  ),
  ChittiSection(
    key: 'eseva',
    label: 'e-Seva',
    description: 'Government e-Seva certificate and document services.',
    variants: {'customer'},
    builder: _eseva,
    screenType: EsevaServiceScreen,
    aliases: ['eseva', 'e-seva', 'certificate', 'government'],
  ),
  ChittiSection(
    key: 'live_rates',
    label: 'Live Rates',
    description: 'Live gold, silver, and market rates.',
    variants: {'customer'},
    builder: _liveRates,
    screenType: LiveRatesScreen,
    aliases: ['rate', 'rates', 'gold', 'silver', 'price'],
  ),
  ChittiSection(
    key: 'credentials',
    label: 'Credentials',
    description: 'Saved documents and credentials locker.',
    variants: {'customer'},
    builder: _credentials,
    screenType: CredentialsScreen,
    aliases: ['documents', 'locker', 'credentials'],
  ),
  ChittiSection(
    key: 'safety',
    label: 'Safety / SOS',
    description: 'The SOS emergency assistance screen.',
    variants: {'customer'},
    builder: _sos,
    screenType: SosScreen,
    aliases: ['sos', 'emergency', 'help me', 'safety'],
  ),
  ChittiSection(
    key: 'sos_kyc',
    label: 'SOS KYC Verification',
    description: 'Complete the KYC required before SOS can be used.',
    variants: {'customer'},
    builder: _sosKyc,
    screenType: SosKycVerificationScreen,
    aliases: ['kyc', 'sos verification', 'verify'],
  ),
  ChittiSection(
    key: 'economic_vision',
    label: 'Economic Vision',
    description: 'The savings and economic impact vision page.',
    variants: {'customer', 'hero'},
    builder: _economicVision,
    screenType: EconomicVisionScreen,
    aliases: ['savings', 'vision', 'economic'],
  ),
  ChittiSection(
    key: 'profile',
    label: 'your Profile',
    description: 'Name, phone, addresses, and account details.',
    variants: {'customer'},
    builder: _profile,
    screenType: ProfileScreen,
    aliases: ['profile', 'account', 'address', 'my details'],
  ),
  ChittiSection(
    key: 'settings',
    label: 'Settings',
    description: 'App settings, language, and preferences.',
    variants: {'customer'},
    builder: _settings,
    screenType: SettingsScreen,
    aliases: ['settings', 'language', 'preferences'],
  ),

  // ── HERO ────────────────────────────────────────────────────────
  ChittiSection(
    key: 'hero_earnings',
    label: 'Earnings',
    description: 'The Hero earnings breakdown and payouts.',
    variants: {'hero'},
    builder: _heroEarnings,
    screenType: HeroEarningsScreen,
    aliases: ['earnings', 'income', 'sambalam', 'payout'],
  ),
  ChittiSection(
    key: 'hero_wallet',
    label: 'Hero Wallet',
    description: 'The Hero wallet balance and top-ups.',
    variants: {'hero'},
    builder: _heroWallet,
    screenType: HeroWalletScreen,
    aliases: ['wallet', 'balance', 'money'],
  ),
  ChittiSection(
    key: 'hero_history',
    label: 'Job History',
    description: 'Completed rides and jobs for this Hero.',
    variants: {'hero'},
    builder: _heroHistory,
    screenType: HeroHistoryScreen,
    aliases: ['history', 'past jobs', 'completed rides'],
  ),
  ChittiSection(
    key: 'hero_incomplete_tasks',
    label: 'Incomplete Tasks',
    description: 'Jobs the Hero accepted but has not finished.',
    variants: {'hero'},
    builder: _heroIncompleteTasks,
    screenType: HeroIncompleteTasksScreen,
    aliases: ['incomplete', 'pending jobs', 'unfinished'],
  ),
  ChittiSection(
    key: 'hero_payment_qr',
    label: 'Payment QR',
    description: 'The Hero QR code for collecting payment.',
    variants: {'hero'},
    builder: _heroPaymentQr,
    screenType: HeroPaymentQrScreen,
    aliases: ['qr', 'payment qr', 'collect payment', 'scan'],
  ),
  ChittiSection(
    key: 'hero_sos',
    label: 'Hero SOS',
    description: 'Emergency help for the Hero while working.',
    variants: {'hero'},
    builder: _heroSos,
    screenType: HeroSosScreen,
    aliases: ['sos', 'emergency', 'accident'],
  ),
  ChittiSection(
    key: 'hero_settings',
    label: 'Hero Settings',
    description: 'Hero app settings and preferences.',
    variants: {'hero'},
    builder: _heroSettings,
    screenType: HeroSettingsScreen,
    aliases: ['settings', 'preferences'],
  ),

  // ── SELLER ──────────────────────────────────────────────────────
  ChittiSection(
    key: 'seller_dashboard',
    label: 'Seller Dashboard',
    description: 'Incoming orders and shop overview.',
    variants: {'seller'},
    builder: _sellerDashboard,
    screenType: SellerDashboardScreen,
    aliases: ['dashboard', 'orders', 'home'],
  ),
  ChittiSection(
    key: 'seller_earnings',
    label: 'Earnings',
    description: 'The shop earnings and settlements.',
    variants: {'seller'},
    builder: _earningsHub,
    screenType: EarningsHubScreen,
    aliases: ['earnings', 'income', 'settlement', 'payout'],
  ),
  ChittiSection(
    key: 'seller_verticals',
    label: 'Business Type',
    description: 'Pick or switch which business vertical this shop runs.',
    variants: {'seller'},
    builder: _sellerVerticalPicker,
    screenType: SellerVerticalPickerScreen,
    aliases: ['vertical', 'business type', 'category'],
  ),
  ChittiSection(
    key: 'seller_settings',
    label: 'Seller Settings',
    description: 'Shop settings, timings, and preferences.',
    variants: {'seller'},
    builder: _sellerSettings,
    screenType: SellerSettingsScreen,
    aliases: ['settings', 'shop settings', 'timing'],
  ),

  // ── ADMIN ───────────────────────────────────────────────────────
  ChittiSection(
    key: 'admin_home',
    label: 'Allin1 HQ Main Home',
    description: 'The main HQ overview page with all management tabs and SOS dispatch.',
    variants: {'admin'},
    builder: _adminHome,
    screenType: SuperAdminHomeScreen,
    aliases: ['home', 'main page', 'hq', 'admin home', 'main home', 'ஹோம்', 'மெயின்'],
  ),
  ChittiSection(
    key: 'admin_dashboard',
    label: 'Taxi & Transport Dashboard',
    description: 'The taxi and transportation overview dashboard.',
    variants: {'admin'},
    builder: _adminDashboard,
    screenType: AdminDashboardScreen,
    aliases: ['dashboard', 'taxi dashboard', 'transport', 'rides overview', 'taxi manage'],
  ),
  // NEW (Aug 31 2026 — Nizam: "இதை admin app-க்குள்ளயே பாக்க ஒரு detail
  // screen ready பண்ணு"). Reachable both from a direct nav link AND by
  // asking Chitti — "show me the call logs" reaches the same screen a
  // tap would, no separate voice-only code path to drift out of sync.
  ChittiSection(
    key: 'chitti_debug_logs',
    label: 'Chitti Call Debug Logs',
    description: 'Step-by-step logs of what happened on each screened call — '
        'greeting, speech recognition, TTS start/error, in order.',
    variants: {'admin'},
    builder: _chittiDebugLogs,
    screenType: ChittiDebugLogsScreen,
    aliases: [
      'call logs', 'debug logs', 'chitti logs', 'call debug', 'screening logs',
      'call history logs', 'கால் லாக்ஸ்', 'டிபக் லாக்ஸ்',
    ],
  ),
  ChittiSection(
    key: 'admin_new_orders',
    label: 'New Orders',
    description: 'Incoming orders awaiting admin action.',
    variants: {'admin'},
    builder: _adminNewOrders,
    screenType: AdminNewOrdersScreen,
    aliases: ['new orders', 'incoming'],
  ),
  ChittiSection(
    key: 'admin_hero_approvals',
    label: 'Hero Approvals',
    description: 'Heroes waiting for document approval.',
    variants: {'admin'},
    builder: _heroApprovals,
    screenType: HeroApprovalsScreen,
    aliases: ['hero approval', 'pending heroes', 'verify hero'],
  ),
  ChittiSection(
    key: 'admin_approved_heroes',
    label: 'Approved Heroes',
    description: 'The list of already-approved Heroes.',
    variants: {'admin'},
    builder: _approvedHeroes,
    screenType: ApprovedHeroesScreen,
    aliases: ['approved heroes', 'hero list'],
  ),
  ChittiSection(
    key: 'chitti_enquiries',
    label: 'Customer Enquiries',
    // Both apps, deliberately: Nizam's rule is that a price enquiry is
    // monitored on "seller and admin phone", and a seller who cannot
    // open the lead cannot answer it.
    description: 'Customer price questions Chitti could not answer, '
        'waiting for a real quote.',
    variants: {'admin', 'seller'},
    builder: _chittiEnquiries,
    screenType: ChittiEnquiriesScreen,
    aliases: [
      'enquiries', 'enquiry', 'inquiries', 'leads', 'price questions',
      'customer questions', 'என்குயரி',
    ],
  ),
  ChittiSection(
    key: 'admin_seller_approvals',
    label: 'Seller Approvals',
    description: 'Sellers waiting for approval.',
    variants: {'admin'},
    builder: _sellerApprovals,
    screenType: AdminSellerApprovalScreen,
    aliases: ['seller approval', 'pending sellers'],
  ),
  ChittiSection(
    key: 'admin_dispatch',
    label: 'Hero Dispatch',
    description: 'Live dispatch monitoring for Heroes.',
    variants: {'admin'},
    builder: _adminDispatch,
    screenType: AdminHeroDispatchScreen,
    aliases: ['dispatch', 'live heroes', 'assign'],
  ),
  ChittiSection(
    key: 'admin_ride_tracking',
    label: 'Ride Tracking',
    description: 'Live tracking of ongoing rides.',
    variants: {'admin'},
    builder: _adminRideTracking,
    screenType: AdminRideTrackingScreen,
    aliases: ['ride tracking', 'live rides', 'track'],
  ),
  ChittiSection(
    key: 'admin_sos_kyc',
    label: 'SOS KYC Approvals',
    description: 'Customer SOS KYC submissions awaiting approval.',
    variants: {'admin'},
    builder: _adminSosKyc,
    screenType: AdminSosKycApprovalsScreen,
    aliases: ['sos kyc', 'kyc approval'],
  ),
  ChittiSection(
    key: 'admin_wallet_approvals',
    label: 'Wallet Approvals',
    description: 'Wallet top-up requests awaiting approval.',
    variants: {'admin'},
    builder: _adminWalletApprovals,
    screenType: AdminWalletApprovalsScreen,
    aliases: ['wallet approval', 'top up', 'add money requests'],
  ),
  ChittiSection(
    key: 'admin_payments',
    label: 'Payments Received',
    description: 'Payments received across the platform.',
    variants: {'admin'},
    builder: _adminPayments,
    screenType: PaymentsReceivedScreen,
    aliases: ['payments', 'received', 'collections'],
  ),
  ChittiSection(
    key: 'admin_fares',
    label: 'Fare Management',
    description: 'Fare and pricing configuration.',
    variants: {'admin'},
    builder: _adminFares,
    screenType: FareManagementScreen,
    aliases: ['fare', 'pricing', 'rate card'],
  ),
  ChittiSection(
    key: 'admin_offers',
    label: 'Erode Offers Management',
    description: 'Create and manage local offers.',
    variants: {'admin'},
    builder: _adminOffers,
    screenType: AdminErodeOffersScreen,
    aliases: ['offers', 'manage offers', 'deals'],
  ),
  ChittiSection(
    key: 'admin_bug_reports',
    label: 'Bug Reports',
    description: 'Bug reports filed by customers and by Chitti.',
    variants: {'admin'},
    builder: _adminBugReports,
    screenType: BugReportsScreen,
    aliases: ['bugs', 'bug reports', 'issues', 'complaints'],
  ),
  ChittiSection(
    key: 'admin_db_usage',
    label: 'Database Usage',
    description: 'Firestore and RTDB usage and billing risk.',
    variants: {'admin'},
    builder: _adminDbUsage,
    screenType: AdminDbUsageScreen,
    aliases: ['usage', 'database', 'reads', 'billing', 'quota'],
  ),
  ChittiSection(
    key: 'admin_ai_settings',
    label: 'AI Settings',
    description: 'Chitti own configuration and API keys.',
    variants: {'admin'},
    builder: _adminAiSettings,
    screenType: AdminAiSettingsScreen,
    aliases: ['ai settings', 'chitti settings', 'api key'],
  ),
];

/// Sections legal for [variant], in registry order.
List<ChittiSection> chittiSectionsFor(String variant) => kChittiSections
    .where((s) => s.variants.contains(variant))
    .toList(growable: false);

/// The section a live screen belongs to, by its widget type.
///
/// Used by the navigation observer to label wherever the customer just
/// went, and by the offline answerer to describe it back to them.
/// Not variant-scoped: a screen that is on the stack is on the stack,
/// whatever build it belongs to.
ChittiSection? chittiSectionForScreen(Object screen) {
  final type = screen.runtimeType;
  for (final s in kChittiSections) {
    if (s.screenType == type) return s;
  }
  return null;
}

/// Lookup by key, variant-scoped so a Hero can never resolve a
/// customer-only section even if the model hallucinates the key.
ChittiSection? chittiSectionByKey(String? key, String variant) {
  if (key == null || key.isEmpty) return null;
  for (final s in kChittiSections) {
    if (s.key == key && s.variants.contains(variant)) return s;
  }
  return null;
}

// Top-level builders. Written out rather than inlined as closures
// because a `const` list cannot hold non-const closures.
Widget _foodHub(BuildContext _) => const FoodHubScreen();
Widget _groceryOrder(BuildContext _) => const GroceryOrderScreen();
Widget _dmart(BuildContext _) => const DmartScreen();
Widget _njTechService(BuildContext _) => const NjTechServiceScreen();
Widget _njTechStore(BuildContext _) => const NJTechStoreScreen();
Widget _mobileHub(BuildContext _) => const MobileHubScreen();
Widget _cart(BuildContext _) => const CartScreen();
Widget _myOrders(BuildContext _) => const MyOrdersScreen();
Widget _rideHistory(BuildContext _) => const RideHistoryScreen();
Widget _rewardsHub(BuildContext _) => const RewardsHubScreen();
Widget _earnDashboard(BuildContext _) => const EarnDashboardScreen();
Widget _rewards(BuildContext _) => const RewardsScreen();
Widget _offers(BuildContext _) => const GuruOfferScreen();
Widget _playZone(BuildContext _) => const PlayZoneScreen();
Widget _megaQuiz(BuildContext _) => const MegaQuizScreen();
Widget _inviteFriends(BuildContext _) => const InviteFriendsScreen();
Widget _notifications(BuildContext _) => const NotificationsScreen();
Widget _heroBooking(BuildContext _) => const HeroBookingScreen();
Widget _customOrder(BuildContext _) => const CustomOrderScreen();
Widget _customFoodOrder(BuildContext _) => const CustomFoodOrderScreen();
Widget _carWash(BuildContext _) => const CarWashScreen();
Widget _printing(BuildContext _) => const PrintingServiceScreen();
Widget _eseva(BuildContext _) => const EsevaServiceScreen();
Widget _liveRates(BuildContext _) => const LiveRatesScreen();
Widget _credentials(BuildContext _) => const CredentialsScreen();
Widget _sos(BuildContext _) => const SosScreen();
Widget _sosKyc(BuildContext _) => const SosKycVerificationScreen();
Widget _economicVision(BuildContext _) => const EconomicVisionScreen();
Widget _profile(BuildContext _) => const ProfileScreen();
Widget _settings(BuildContext _) => const SettingsScreen();

Widget _heroEarnings(BuildContext _) => const HeroEarningsScreen();
Widget _heroWallet(BuildContext _) => const HeroWalletScreen();
Widget _heroHistory(BuildContext _) => const HeroHistoryScreen();
Widget _heroIncompleteTasks(BuildContext _) => const HeroIncompleteTasksScreen();
Widget _heroPaymentQr(BuildContext _) => const HeroPaymentQrScreen();
Widget _heroSos(BuildContext _) => const HeroSosScreen();
Widget _heroSettings(BuildContext _) => const HeroSettingsScreen();

Widget _sellerDashboard(BuildContext _) => const SellerDashboardScreen();
Widget _earningsHub(BuildContext _) => const EarningsHubScreen();
Widget _sellerVerticalPicker(BuildContext _) => const SellerVerticalPickerScreen();
Widget _sellerSettings(BuildContext _) => const SellerSettingsScreen();

Widget _adminHome(BuildContext _) => const SuperAdminHomeScreen();
Widget _adminDashboard(BuildContext _) => const AdminDashboardScreen();
Widget _chittiDebugLogs(BuildContext _) => const ChittiDebugLogsScreen();
Widget _adminNewOrders(BuildContext _) => const AdminNewOrdersScreen();
Widget _heroApprovals(BuildContext _) => const HeroApprovalsScreen();
Widget _approvedHeroes(BuildContext _) => const ApprovedHeroesScreen();
Widget _chittiEnquiries(BuildContext _) => const ChittiEnquiriesScreen();
Widget _sellerApprovals(BuildContext _) => const AdminSellerApprovalScreen();
Widget _adminDispatch(BuildContext _) => const AdminHeroDispatchScreen();
Widget _adminRideTracking(BuildContext _) => const AdminRideTrackingScreen();
Widget _adminSosKyc(BuildContext _) => const AdminSosKycApprovalsScreen();
Widget _adminWalletApprovals(BuildContext _) => const AdminWalletApprovalsScreen();
Widget _adminPayments(BuildContext _) => const PaymentsReceivedScreen();
Widget _adminFares(BuildContext _) => const FareManagementScreen();
Widget _adminOffers(BuildContext _) => const AdminErodeOffersScreen();
Widget _adminBugReports(BuildContext _) => const BugReportsScreen();
Widget _adminDbUsage(BuildContext _) => const AdminDbUsageScreen();
Widget _adminAiSettings(BuildContext _) => const AdminAiSettingsScreen();
