// ================================================================
// App Variant — Allin1 Super App
// ================================================================
// FIX (Aug 8 2026 — audit finding, notifications_screen.dart hardcoded
// 'customer' fallback): this codebase is shared across 4 flavors
// (customer/hero/admin/seller) via separate main_X.dart entrypoints,
// but until now there was NO runtime way for a widget/screen shared
// across all 4 (like notifications_screen.dart) to know which flavor
// it's actually running as. That forced such shared code to either
// hardcode a guess (wrong for 3 of 4 flavors) or require every call
// site to pass its own flavor string explicitly (easy to forget/copy
// wrong, which is exactly how the hardcoded-'customer'-fallback bug
// happened).
//
// currentAppVariant is set ONCE, at the very top of each main_X.dart's
// main(), before runApp() — see the FIX comment at each entrypoint.
// Any shared widget/service can now import this file and read the
// correct 'customer' | 'hero' | 'admin' | 'seller' value at runtime
// instead of guessing.
// ================================================================

String currentAppVariant = 'customer';
