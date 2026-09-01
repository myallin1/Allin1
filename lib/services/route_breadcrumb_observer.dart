// route_breadcrumb_observer.dart — Aug 19 2026
//
// Cold-start-after-kill UX mitigation (see dashboard_screen.dart
// _restoreLastTab() for the tab-level half of this). Android/iOS can
// kill a backgrounded app's process at any time to reclaim memory; on
// relaunch that is a fresh Dart VM + fresh widget tree, and nothing in
// Flutter can prevent the OS from doing this. What we *can* do is
// remember the last *named* route the customer was on and jump back to
// it after the dashboard is up, instead of always landing on tab 0/last
// tab with no deeper context.
//
// IMPORTANT LIMITATION (documented rather than hidden): most of this
// app's screen-to-screen navigation uses `Navigator.push(context,
// MaterialPageRoute(builder: (_) => SomeScreen(...)))` with NO
// `RouteSettings.name` attached. This observer can only see a route's
// `settings.name`/`settings.arguments` — it has no way to identify or
// reconstruct an unnamed MaterialPageRoute. So today this captures
// deep-restore breadcrumbs only for the app's *named* routes (the
// `routes: {...}` table in main_customer.dart — e.g. '/ai-assistant',
// '/guru-offer'), not for every category/detail screen reachable from
// the dashboard. Widening coverage would mean adding
// `RouteSettings(name: ..., arguments: {...})` to each push site
// individually — a much larger, higher-risk change deliberately left
// out of this pass.
import 'dart:async';

import 'package:flutter/material.dart';

import 'prefs_cache.dart';

/// Route names that must NEVER be restored on cold start, even if they
/// were the last thing captured — anything mid-transaction or
/// mid-verification. Matched as a case-insensitive substring so
/// '/checkout/review', '/otp-verify', etc. are all caught.
const List<String> kBreadcrumbExcludedSubstrings = [
  'payment',
  'checkout',
  'otp',
  'verify',
];

/// Small allowlist of route names that are safe to silently re-open on
/// cold start. Deliberately conservative — content/browse screens only,
/// never anything that mutates state or tracks a live transaction.
///
/// Aug 19 2026 — food-ordering flow additions ('/food_shop_detail',
/// '/partner_shop_detail'): these restore ONLY the point *before*
/// payment — the restaurant/menu/partner-shop browsing screen a
/// customer was looking at. That is deliberate: if the app crashes
/// mid food-order, the useful/safe thing to restore them to is "back
/// browsing the menu", not anything past it. The moment a customer
/// moves on to checkout, payment, an OTP/verify step, or an
/// order-in-progress/tracking screen, the substring excludes above
/// ('payment', 'checkout', 'otp', 'verify') plus the deliberate
/// omission of any order-status/tracking route name from this list
/// take over — those screens are NEVER added here, on purpose, even
/// though they're reachable from the same flow. See
/// SellerDetailScreen / PartnerShopOrderScreen — both are
/// pre-payment/pre-commitment browsing UI, no cart mutation or
/// payment call happens just by viewing them.
const List<String> kBreadcrumbSafeRoutes = [
  '/ai-assistant',
  '/guru-offer',
  '/settings',
  '/ai-settings',
  '/food_shop_detail',
  '/partner_shop_detail',
];

bool isRouteSafeToRestore(String name) {
  final lower = name.toLowerCase();
  for (final bad in kBreadcrumbExcludedSubstrings) {
    if (lower.contains(bad)) return false;
  }
  return kBreadcrumbSafeRoutes.contains(name);
}

class RouteBreadcrumbObserver extends NavigatorObserver {
  void _record(Route<dynamic>? route) {
    try {
      final settings = route?.settings;
      final name = settings?.name;
      if (name == null || name.isEmpty) return;
      // Never persist a breadcrumb for an excluded route — even a
      // failed write attempt is avoided so a leftover safe breadcrumb
      // from earlier in the session isn't overwritten with junk.
      if (!isRouteSafeToRestore(name)) return;

      Map<String, dynamic>? args;
      final rawArgs = settings?.arguments;
      if (rawArgs is Map<String, dynamic>) {
        // Only keep it if every value is a JSON-primitive — this is
        // meant for small ids/flags, not full objects.
        final isPrimitiveMap = rawArgs.values.every(
          (v) => v == null || v is String || v is num || v is bool,
        );
        if (isPrimitiveMap) args = rawArgs;
      }

      unawaited(PrefsCache.saveBreadcrumb(route: name, args: args));
    } catch (_) {
      // Never let breadcrumb bookkeeping affect real navigation.
    }
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    _record(route);
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    _record(newRoute);
  }
}
