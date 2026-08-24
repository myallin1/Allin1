// GENERATED FILE — DO NOT EDIT BY HAND.
// Produced by tools/gen_app_knowledge.dart, which is run
// automatically by deploy_web.ps1 on every deploy.
//
// Editing this by hand will work until the next deploy and
// then be silently overwritten. Change the GENERATOR instead.
//
// Generated: 2026-08-21T15:49:51.234568Z
// ignore_for_file: lines_longer_than_80_chars

/// Machine-generated description of this app, injected into
/// every AI persona so the assistant is briefed on the real,
/// current system rather than a stale hand-written summary.
class AppKnowledge {
  AppKnowledge._();

  static const String version = '1.0.9+252';
  static const String generatedAt = '2026-08-21T15:49:51.234568Z';

  /// Firestore collections this codebase actually reads/writes.
  static const List<String> firestoreCollections = <String>[
    'adminCredentials',
    'admin_ai_actions',
    'admins',
    'ads',
    'affiliate_codes',
    'affiliate_leads',
    'affiliate_scans',
    'affiliate_tasks',
    'app_bug_reports',
    'app_usage_stats',
    'cancellation_analytics',
    'captains',
    'coin_transactions',
    'company_payments_received',
    'credentialAccess',
    'credentialCategories',
    'credentials',
    'custom_hotel_orders',
    'custom_hotels',
    'db_usage_stats',
    'documents',
    'erode_offers',
    'food_orders',
    'guru_analytics',
    'hero_sessions',
    'hero_wallets',
    'heroes',
    'heroes_pending',
    'home_banner_offers',
    'items',
    'location_search_logs',
    'menu_items',
    'notifications',
    'orders',
    'platformSettings',
    'qr_links',
    'quiz_participants',
    'rides',
    'sellerOverrides',
    'sellers',
    'service_requests',
    'settings',
    'sos_alerts',
    'sos_kyc_requests',
    'system_settings',
    'task_completions',
    'transactions',
    'users',
    'ux_audit_reports',
    'wallet_recharge_requests',
    'wallet_transactions',
    'withdrawal_requests',
  ];

  /// Realtime Database top-level nodes in use.
  static const List<String> realtimeNodes = <String>[
    'active_ride_requests',
    'active_rides',
    'active_service_requests',
    'hero_pings',
    'hero_service_pings',
    'hero_status_updates',
    'live_locations',
    'online_heroes',
    'sos_alerts',
  ];

  /// Named routes registered across the four app flavors.
  static const List<String> routes = <String>[
    '/',
    '/admin-home',
    '/admin/ads',
    '/admin/credentials',
    '/admin/fares',
    '/admin/tasks',
    '/ai-assistant',
    '/ai-settings',
    '/checkout',
    '/dashboard',
    '/guru-offer',
    '/hero-home',
    '/hero-ride',
    '/login',
    '/rider',
    '/seller',
    '/seller-home',
    '/seller-onboarding',
    '/seller-store',
    '/settings',
  ];

  static const String screenIndex =
      'admin_affiliate_leads_screen, admin_affiliate_qr_screen, admin_ai_settings_screen, admin_campaign_detail_screen, admin_cloudinary_dashboard_screen, admin_coin_credit_screen, admin_dashboard_screen, admin_dashboard_screen, admin_db_usage_screen, admin_detailed_reports_screen, admin_food_orders_screen, admin_hero_details_screen, admin_hero_dispatch_screen, admin_hero_earnings_screen, admin_hero_mirror_screen, admin_home_banner_screen, admin_location_demand_screen, admin_map_simulation_screen, admin_new_orders_screen, admin_orders_cleanup_screen, admin_qr_generator_screen, admin_ride_tracking_detail_screen, admin_ride_tracking_screen, admin_seller_approval_screen, admin_service_requests_screen, admin_sos_kyc_approvals_screen, admin_taxi_rides_screen, admin_usage_billing_screen, admin_ux_audit_screen, admin_wallet_approvals_screen, ads_management_screen, ai_assistant_screen, ai_settings_screen, app_splash_video_screen, approved_heroes_screen, bike_booking_screen, biriyani_menu_screen, bug_reports_screen, car_wash_screen, cart_screen, category_screen, checkout_screen, coin_tap_screen, coming_soon_screen, commission_settings_screen, construction_screen, credential_detail_screen, credentials_admin_screen, credentials_screen, custom_food_order_screen, custom_hotel_view_screen, custom_order_screen, customer_demand_screen, customer_login_screen, customer_rides_screen, customer_usage_tracking_screen, customer_welcome_login_screen, dashboard_screen, dmart_screen, earn_dashboard_screen, earnings_hub_screen, economic_vision_screen, embedded_shop_screen, erode_offers_management_screen, erode_offers_section, eseva_service_screen, fare_management_screen, food_checkout_screen, food_hub_screen, food_order_status_screen, game_2048_screen, grocery_order_screen, grocery_order_status_screen, guru_chat_screen, guru_offer_screen, hero_approvals_screen, hero_booking_screen, hero_booking_status_screen, hero_booking_tracking_screen, hero_buddy_form_screen, hero_dashboard_shell, hero_document_screen, hero_earnings_screen, hero_history_screen, hero_home_screen, hero_incomplete_tasks_screen, hero_login_screen, hero_payment_qr_screen, hero_pending_screen, hero_profile_tab, hero_promo_screen, hero_register_screen, hero_ride_screen, hero_screen, hero_settings_screen, hero_side_drawer, hero_sos_screen, hero_verification_pending, hero_wallet_screen, hero_welcome_screen, intro_video_screen, invite_friends_screen, landing_page, listing_video_player, live_rates_screen, location_picker_screen, login_screen, mega_quiz_screen, memory_match_screen, mobile_hub_screen, mobile_listings_tab, mobile_service_sheet, mobile_service_tab, mobile_status_tab, my_orders_screen, nj_tech_service_screen, nj_tech_store_screen, notifications_screen, order_tracking_screen, partner_shop_order_screen, payment_screen, payments_received_screen, play_zone_screen, printing_service_screen, profile_screen, profile_setup_screen, registration_screen, rewards_hub_screen, rewards_screen, ride_history_screen, ride_search_screen, ride_tracking_screen, rider_screen, role_login_screen, selfie_capture_screen, sell_your_phone_sheet, seller_custom_hotel_builder_screen, seller_dashboard_screen, seller_detail_screen, seller_electronics_dashboard_screen, seller_electronics_onboarding_screen, seller_grocery_dashboard_screen, seller_grocery_onboarding_screen, seller_home_kitchen_menu_screen, seller_menu_setup_screen, seller_mobile_dashboard_screen, seller_mobile_listing_editor, seller_mobile_onboarding_screen, seller_onboarding_screen, seller_pending_screen, seller_screen, seller_settings_screen, seller_side_drawer, seller_vertical_picker_screen, service_flow_monitor_screen, service_request_live_map_screen, service_request_payment_screen, service_request_tracking_screen, settings_screen, sos_kyc_verification_screen, sos_screen, splash_setup_screen, store_layout_screen, super_admin_home_screen, task_approvals_screen, usage_fee_ledger_screen, video_splash_screen, welcome_screen, whack_a_mole_screen';

  static const String serviceIndex =
      'admin_ai_audit_tools, admin_ai_tools_schema, admin_alert_notification_service, admin_credential_service, admin_deletion_service, admin_foreground_service, admin_kyc_vision_service, admin_kyc_write_service, admin_live_alert_service, admin_quick_task_service, admin_ride_dispatch_service, affiliate_service, ai_activation_service, ai_service, analytics_service, api_contracts, api_service, app_minimizer_service, app_palette, app_update_checker, app_update_gate_service, audio_platform_stub, audio_platform_web, auth_prompt_service, auth_service, cache_service, cart_service, category_gateway_service, chitti_memory_service, chitti_overlay_service, city_service, cloudinary_admin_service, cloudinary_orphan_scanner, cloudinary_upload_service, credential_cache_service, credential_service, crop_source_provider_stub, crop_source_provider_web, csv_export_stub, csv_export_web, custom_hotel_service, daily_quote_service, db_usage_tracker, deepseek_api_service, device_compat_service, device_compat_service_stub, device_compat_service_web, encryption_service, food_seller_service, gemini_api_service, grocery_ai_notes_service, guru_admin_api_service, guru_api_service, guru_overlay_service, guru_suggestion_parser, hero_foreground_service, hero_onboarding_cache, hero_payment_qr_service, hero_ride_notification_service, hero_task_recovery_service, hero_update_service, hero_usage_accumulator_service, hero_wallet_service, hero_web_audio_service, hive_cache, image_compressor_stub, image_compressor_web, local_sync_service, localization_service, location_service, map_provider, map_service, map_simulation_service, migration_gate_service, mobile_catalog_service, mobile_listing_service, ola_maps_provider, osm_provider, permission_service, pickup_memory_service, platform_settings_service, prefs_cache, pwa_cache_platform_stub, pwa_cache_platform_web, pwa_update_platform_stub, pwa_update_platform_web, qa_vision_service, qr_image_saver_stub, qr_image_saver_web, recent_places_service, route_breadcrumb_observer, seller_alert_notification_service, seller_foreground_service, seller_live_alert_service, service_request_cache_service, service_request_service, service_requests_listener, session_service, share_intent_platform_native, share_intent_platform_stub, shared_location_inbox, soundbox_easter_egg_service, task_service, theme_context_extensions, theme_service, update_service, usage_billing_service, usage_tracking_service, voice_booking_intent_service, wallet_service, web_version_checker';
}
