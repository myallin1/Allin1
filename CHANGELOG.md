# Changelog

All notable changes to the Allin1 Super App are recorded here.

## [Unreleased]

### Fixed
- **patch** — Customer app no longer gets stuck on the Payment screen after the Hero marks payment as received. `payment_screen.dart`'s `paymentStatus` gate (both the live listener and the lifecycle-resume poll) was missing the `'settled'` and `'confirmed'` values that the Hero-side `_markPaymentReceived()` flow writes, so the customer never unlocked into the rating screen. Added `onError` handling to the ride-status stream listener so a failed snapshot subscription surfaces in logs instead of failing silently.
- **patch** — Same root cause on the Hero side: `hero_history_screen.dart`'s `paymentSettled` getter and `hero_home_screen.dart`'s one-time "payment received" notification trigger were also missing `'settled'`/`'confirmed'`, so a Hero could still see "Report Payment Issue" as available on an already-settled ride, and never saw the in-app payment-confirmation banner after using the newer `_markPaymentReceived()` flow.
