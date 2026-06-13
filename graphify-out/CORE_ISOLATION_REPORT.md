# Core-Only Isolation Report (Top 50)

Source: `graphify-out/graph.json`
Scope: nodes from `lib/` with degree <= 1
Total isolated lib nodes detected: **1912**
Top 50 split: **30 DROP** / **20 KEEP**

## Recommendation Rules
- DROP: generated adapters, import-path nodes, generic framework/lifecycle symbols, narrow private UI helpers
- KEEP: domain classes/functions in services/models/providers/screens and entrypoint orchestration

## Top 50 Symbols
| # | Degree | Symbol | Source | Recommendation | Why |
|---|---:|---|---|---|---|
| 1 | 1 | `read` | `lib/models/reward_model.g.dart` | **DROP** | generated adapter helper; generic framework/lifecycle symbol; core layer (service/model/provider) |
| 2 | 1 | `read` | `lib/models/store_model.g.dart` | **DROP** | generated adapter helper; generic framework/lifecycle symbol; core layer (service/model/provider) |
| 3 | 1 | `read` | `lib/models/user_balance_model.g.dart` | **DROP** | generated adapter helper; generic framework/lifecycle symbol; core layer (service/model/provider) |
| 4 | 1 | `write` | `lib/models/reward_model.g.dart` | **DROP** | generated adapter helper; generic framework/lifecycle symbol; core layer (service/model/provider) |
| 5 | 1 | `write` | `lib/models/store_model.g.dart` | **DROP** | generated adapter helper; generic framework/lifecycle symbol; core layer (service/model/provider) |
| 6 | 1 | `write` | `lib/models/user_balance_model.g.dart` | **DROP** | generated adapter helper; generic framework/lifecycle symbol; core layer (service/model/provider) |
| 7 | 1 | `AnimatedSwitcher` | `lib/main_hero.dart` | **DROP** | generic framework/lifecycle symbol; entrypoint orchestration |
| 8 | 1 | `Container` | `lib/screens/admin_dashboard_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 9 | 1 | `Container` | `lib/screens/bike_taxi_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 10 | 1 | `Container` | `lib/screens/cart_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 11 | 1 | `Container` | `lib/screens/checkout_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 12 | 1 | `Container` | `lib/screens/dashboard_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 13 | 1 | `Container` | `lib/screens/hero_document_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 14 | 1 | `Container` | `lib/screens/hero_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 15 | 1 | `Container` | `lib/screens/landing_page.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 16 | 1 | `Container` | `lib/screens/live_rates_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 17 | 1 | `Container` | `lib/screens/login_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 18 | 1 | `Container` | `lib/screens/nj_tech_store_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 19 | 1 | `Container` | `lib/screens/notifications_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 20 | 1 | `Container` | `lib/screens/order_tracking_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 21 | 1 | `Container` | `lib/screens/payment_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 22 | 1 | `Container` | `lib/screens/play_zone_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 23 | 1 | `Container` | `lib/screens/profile_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 24 | 1 | `Container` | `lib/screens/rewards_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 25 | 1 | `Container` | `lib/screens/rider_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 26 | 1 | `Container` | `lib/screens/ride_history_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 27 | 1 | `Container` | `lib/screens/seller_detail_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 28 | 1 | `Container` | `lib/screens/seller_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 29 | 1 | `Container` | `lib/screens/settings_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 30 | 1 | `Container` | `lib/screens/admin/admin_dashboard_screen.dart` | **DROP** | generic framework/lifecycle symbol; feature screen symbol |
| 31 | 1 | `_clearCache` | `lib/services/cache_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 32 | 1 | `_detectProfile` | `lib/services/device_compat_service_web.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 33 | 1 | `_ensureAdminUserDoc` | `lib/services/auth_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 34 | 1 | `_getAuthErrorMessage` | `lib/services/auth_service.dart` | **KEEP** | private UI/helper symbol, narrow locality; core layer (service/model/provider); domain-facing class/function |
| 35 | 1 | `_getCachedData` | `lib/services/cache_service.dart` | **KEEP** | private UI/helper symbol, narrow locality; core layer (service/model/provider); domain-facing class/function |
| 36 | 1 | `_getDefaultRideFares` | `lib/services/category_gateway_service.dart` | **KEEP** | private UI/helper symbol, narrow locality; core layer (service/model/provider); domain-facing class/function |
| 37 | 1 | `_getDefaultSettings` | `lib/services/category_gateway_service.dart` | **KEEP** | private UI/helper symbol, narrow locality; core layer (service/model/provider); domain-facing class/function |
| 38 | 1 | `_initializeCache` | `lib/services/api_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 39 | 1 | `_isAdminUserData` | `lib/services/auth_service.dart` | **KEEP** | private UI/helper symbol, narrow locality; core layer (service/model/provider); domain-facing class/function |
| 40 | 1 | `_loadApiKey` | `lib/services/ai_activation_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 41 | 1 | `_requiresProfileSetup` | `lib/services/auth_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 42 | 1 | `_validatedApiKey` | `lib/services/ola_maps_provider.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 43 | 1 | `AiActivationService` | `lib/services/ai_activation_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 44 | 1 | `AIService` | `lib/services/ai_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 45 | 1 | `AnalyticsService` | `lib/services/analytics_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 46 | 1 | `ApiErrorResponse` | `lib/models/api_models.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 47 | 1 | `ApiRequest` | `lib/models/api_models.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 48 | 1 | `ApiResponse` | `lib/models/api_models.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 49 | 1 | `ApiService` | `lib/services/api_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |
| 50 | 1 | `ApiServiceException` | `lib/services/api_service.dart` | **KEEP** | core layer (service/model/provider); domain-facing class/function |