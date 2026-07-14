# Changelog

All notable changes to the Allin1 Super App are recorded here.

## [Unreleased]

### Fixed
- **patch** — Customer app's Recent Activity screen (`ride_history_screen.dart`, dashboard drawer → "Activity") always showed "No rides yet!" for every customer, on every ride. The query filtered on a `userId` field that the `rides` schema never consistently writes (only `customerId` is guaranteed present on every ride document); fixed to filter on `customerId`. Also fixed the card display, which read stale/nonexistent field names (`pickup`, `drop`, `rideType`) instead of the actual schema fields (`pickupAddress`, `dropAddress`, `category`) — the ride-type icon now matches against the canonical category keys (`bike`/`auto`/`car`/`parcel`/`mini_truck`/`lorry`/`emergency_manpower`) per AGENTS.md Section 3, instead of the old capitalized `'Auto'`/`'Parcel'` strings that never matched actual data.
