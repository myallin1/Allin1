// ================================================================
// hero_presence_utils.dart — shared staleness check for RTDB
// `online_heroes/{uid}` presence nodes.
// ================================================================
// FIX (per Nizam's request — "admin ku exacta ah theriyanum yaru
// real ah online"): RTDB's onDisconnect().remove() (armed in
// hero_home_screen.dart's _syncOnlineStatus/_startGlobalLocationTracking)
// is the primary defense against a hero's node lingering after they
// close the app — but Firebase's own docs describe onDisconnect as
// best-effort, not an instant guarantee: an ungraceful OS-level kill,
// aggressive battery/doze restrictions, or a bad network moment right
// when the hook was being registered can all mean the server-side
// cleanup never fires, or fires much later than expected.
//
// This is the second, independent line of defense: every
// online_heroes/{uid} write includes a `lastUpdated` server timestamp,
// refreshed periodically (see hero_home_screen.dart's heartbeat write)
// even while the hero is stationary. Any screen displaying "who's
// online" should treat a node as truly online only if `lastUpdated` is
// recent — a node that still exists but hasn't been touched in
// several minutes almost certainly belongs to a hero whose app closed
// without the disconnect hook completing, not someone actually active
// right now.
import 'package:firebase_database/firebase_database.dart';

/// How stale a `lastUpdated` timestamp can be before a presence node
/// is no longer trusted as "really online". Set comfortably above the
/// hero app's heartbeat interval (90s) to absorb normal network
/// jitter without flickering a genuinely-online hero to "offline".
const Duration kHeroPresenceStaleAfter = Duration(minutes: 3);

/// Returns true if `lastUpdated` (expected to be a millis-since-epoch
/// int, as written by `ServerValue.timestamp`) is recent enough to
/// trust. Missing/malformed timestamps are treated as stale rather
/// than trusted, since a legitimate write always includes one.
bool isHeroPresenceFresh(dynamic lastUpdated, {DateTime? now}) {
  if (lastUpdated is! int) return false;
  final updatedAt = DateTime.fromMillisecondsSinceEpoch(lastUpdated);
  final reference = now ?? DateTime.now();
  return reference.difference(updatedAt) <= kHeroPresenceStaleAfter;
}

/// Convenience wrapper for a raw `online_heroes/{uid}` RTDB map value
/// (as read off a DataSnapshot) — returns true only if the node
/// exists AND its `lastUpdated` is fresh.
bool isHeroPresenceMapFresh(Object? rawValue) {
  if (rawValue is! Map) return false;
  return isHeroPresenceFresh(rawValue['lastUpdated']);
}
