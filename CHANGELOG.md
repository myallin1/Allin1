# Changelog

All notable changes to the Allin1 Super App are recorded here.

## \[Unreleased]

### Fixed

- patch — Customer app no longer gets stuck on the Payment screen after the Hero marks payment as received. `payment_screen.dart`'s `paymentStatus` gate (both the live listener and the lifecycle-resume poll) was missing the `'settled'` and `'confirmed'` values that the Hero-side `_markPaymentReceived()` flow writes, so the customer never unlocked into the rating screen. Added `onError` handling to the ride-status stream listener so a failed snapshot subscription surfaces in logs instead of failing silently.
- patch — Same root cause on the Hero side: `hero_history_screen.dart`'s `paymentSettled` getter and `hero_home_screen.dart`'s one-time "payment received" notification trigger were also missing `'settled'`/`'confirmed'`, so a Hero could still see "Report Payment Issue" as available on an already-settled ride, and never saw the in-app payment-confirmation banner after using the newer `_markPaymentReceived()` flow.
- patch — Customer app's Recent Activity screen (`ride_history_screen.dart`, dashboard drawer → "Activity") always showed "No rides yet!" for every customer, on every ride. The query filtered on a `userId` field that the `rides` schema never consistently writes (only `customerId` is guaranteed present on every ride document); fixed to filter on `customerId`. Also fixed the card display, which read stale/nonexistent field names (`pickup`, `drop`, `rideType`) instead of the actual schema fields (`pickupAddress`, `dropAddress`, `category`) — the ride-type icon now matches against the canonical category keys (`bike`/`auto`/`car`/`parcel`/`mini_truck`/`lorry`/`emergency_manpower`) per AGENTS.md Section 3, instead of the old capitalized `'Auto'`/`'Parcel'` strings that never matched actual data.

