// ================================================================
// chitti_local_read.dart — read from the phone, not from the bill.
// ================================================================
// NEW (Aug 28 2026 — Nizam's WhatsApp model: "customer ovvoru
// interaction um 2 place ah record agum ... but athukapram customer app
// avanga details ah avanga phone-laye vachuklam ... summa adikadi
// database disturb pannakudathu. Wallet mattum Firestore valiya manage
// panniklam, apo than hack panna mudiyathu — but customer app la wallet
// la change nadantha than database ah read pannanum").
//
// So the rule this file enforces:
//   • an activity is WRITTEN once, when it happens (admin's history);
//   • everything the customer is then SHOWN comes off their own device;
//   • the wallet is the one exception, because it is money and must
//     stay server-authoritative — and even then it is read on change,
//     not on every glance.
//
// ── WHY THIS WAS URGENT ─────────────────────────────────────────────
// The Chitti lookups shipped reading Firestore live on every question.
// Measured against the free tier:
//   "how much did I earn today"  -> 200 document reads
//   "today sales"                -> 100
//   "pending orders"             ->  50
//   "my past orders"             ->  40
//   "any notifications"          ->  30
//   "where is my order"          ->  23
// A hundred heroes asking about earnings twice a day is 40,000 reads
// for that ONE question, against a 50,000/day free quota. Chitti was
// on course to be the most expensive thing in the app while being the
// part that was supposed to cost nothing.
//
// ── HOW A CACHE READ IS FREE ────────────────────────────────────────
// Firestore's offline cache is already enabled app-wide (50MB, see
// main_customer.dart). A get() with Source.cache is served from that
// local copy and is NOT billed — and it works with no network at all,
// which is the same thing as "offline la full speed". The pattern is
// already used in bike_booking_screen.dart; this generalises it.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

class ChittiLocalRead {
  ChittiLocalRead._();

  /// Runs [query] against the device cache, falling back to the server
  /// only when the cache has nothing.
  ///
  /// The fallback matters on a first run — a customer who has never
  /// opened My Orders has no cached orders, and answering "you have no
  /// orders" would be wrong rather than merely stale. After that first
  /// fetch the answer comes off the device and costs nothing.
  ///
  /// [forceServer] is for the wallet and anything else that must be
  /// authoritative at the moment it is asked.
  static Future<QuerySnapshot<Map<String, dynamic>>?> query(
    Query<Map<String, dynamic>> query, {
    bool forceServer = false,
  }) async {
    if (!forceServer) {
      try {
        final cached = await query.get(
          const GetOptions(source: Source.cache),
        );
        if (cached.docs.isNotEmpty) return cached;
      } catch (e) {
        // An empty or unavailable cache is normal, not an error.
        debugPrint('[ChittiLocalRead] cache miss: $e');
      }
    }
    try {
      return await query.get(
        const GetOptions(source: Source.server),
      );
    } catch (e) {
      debugPrint('[ChittiLocalRead] server read failed: $e');
      // Offline with a cold cache. A null answer lets the caller say
      // "I could not check" instead of claiming the customer has
      // nothing — a wrong zero is worse than an honest gap.
      return null;
    }
  }

  /// Same for a single document.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> doc(
    DocumentReference<Map<String, dynamic>> ref, {
    bool forceServer = false,
  }) async {
    if (!forceServer) {
      try {
        final cached = await ref.get(const GetOptions(source: Source.cache));
        if (cached.exists) return cached;
      } catch (e) {
        debugPrint('[ChittiLocalRead] cache miss: $e');
      }
    }
    try {
      return await ref.get(const GetOptions(source: Source.server));
    } catch (e) {
      debugPrint('[ChittiLocalRead] server read failed: $e');
      return null;
    }
  }

  /// The wallet, which is deliberately different.
  ///
  /// Nizam: "wallet mattum Firestore valiya manage panniklam, apo than
  /// hack panna mudiyathu — but customer app la wallet la change
  /// nadantha than database ah read pannanum".
  ///
  /// So: served from the device like everything else, and re-fetched
  /// from the server only when something has actually moved. Call
  /// [markWalletChanged] from any code path that spends, credits or
  /// tops up, and the next read will be authoritative.
  static bool _walletDirty = true;

  /// Marks the balance as needing a fresh server read.
  ///
  /// Starts true so the first read of a session is always accurate —
  /// a balance could have changed on another device since the app was
  /// last open, and there is no cheap way to know.
  static void markWalletChanged() => _walletDirty = true;

  @visibleForTesting
  static bool get walletNeedsServerRead => _walletDirty;

  /// Reads a wallet document, from the server only when it is dirty.
  static Future<DocumentSnapshot<Map<String, dynamic>>?> wallet(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    final snap = await doc(ref, forceServer: _walletDirty);
    // Only clear the flag on a read that actually reached the server —
    // clearing it after a cache fallback would leave a stale balance
    // looking authoritative for the rest of the session.
    if (snap != null && _walletDirty && !snap.metadata.isFromCache) {
      _walletDirty = false;
    }
    return snap;
  }

  @visibleForTesting
  static void resetForTesting() => _walletDirty = true;
}
