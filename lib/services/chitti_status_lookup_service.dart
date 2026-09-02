// ================================================================
// ChittiStatusLookupService — read-only Firestore lookups for Chitti
// Allin1 (Aug 25 2026 — "Priority 1: Read-Only Tools")
// ================================================================
// Two tools: wallet balance and "what's currently happening with my
// stuff" (active ride + active service_requests). Both are pure reads
// — no Firestore write anywhere in this file — which is exactly why
// they need none of the human-confirmation gating book_transport/
// create_service_request carry: there is nothing here for a wrong
// tool call to damage. Worst case is a wrong ANSWER, not a wrong
// ACTION, and a wrong answer here is just "the number/status is off",
// immediately checkable by the customer against the real screen.
//
// Every query here replicates an EXISTING query shape already used by
// a real customer-facing screen, rather than guessing at field names:
//   - wallet:  same `users/{uid}.walletBalance` field payment_screen.dart
//              already reads before showing the "pay from wallet" option.
//   - rides:   same `rides` collection + `customerId` + the exact
//              `_restorableCustomerRideStatuses` whitelist
//              bike_booking_screen.dart already uses to decide whether
//              to resume an active ride on cold start.
//   - orders:  same `service_requests` collection + `customerId` query
//              service_request_service.dart's streamCustomerRequests()
//              uses for "My Orders", done here as a one-shot `.get()`
//              instead of a live `.snapshots()` listener since a chat
//              reply only needs one point-in-time answer.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'chitti/chitti_local_read.dart';

class ChittiStatusLookupService {
  ChittiStatusLookupService._();

  // Same whitelist as bike_booking_screen.dart's
  // _restorableCustomerRideStatuses — kept as a literal copy rather than
  // importing that screen's private static const (it's private to that
  // State class), matching the "known active statuses" contract exactly.
  static const List<String> _activeRideStatuses = <String>[
    'searching',
    'assigned',
    'accepted',
    'arriving',
    'started',
    'in_progress',
  ];

  // service_requests has no fixed "active" whitelist the way rides
  // does — kServiceRequestStatuses (service_request_service.dart) is
  // the full progression ending in 'completed', and 'cancelled' is
  // used dynamically outside that constant. Simplest correct rule:
  // active = not finished, not cancelled.
  static const Set<String> _terminalRequestStatuses = <String>{
    'completed',
    'cancelled',
  };

  /// "What's my wallet balance?" Returns a ready-to-speak sentence, not
  /// a raw number — this is fed straight into a tool-result message for
  /// Groq to relay, per this tool's own description.
  static Future<String> walletBalanceSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "I couldn't check your wallet — you don't seem to be signed in.";
    }
    try {
      // Money, so this one is allowed to hit the server — but only
      // when something has actually moved. See ChittiLocalRead.wallet.
      final doc = await ChittiLocalRead.wallet(
        FirebaseFirestore.instance.collection('users').doc(uid),
      );
      if (doc == null) {
        return "I couldn't reach your wallet balance right now — please try again in a moment.";
      }
      final balance = (doc.data()?['walletBalance'] as num?)?.toDouble() ?? 0.0;
      return 'Your Allin1 wallet balance is ₹${balance.toStringAsFixed(2)}.';
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] walletBalanceSummary failed: $e');
      return "I couldn't reach your wallet balance right now — please try again in a moment.";
    }
  }

  /// "Where's my ride / what's happening with my order?" Checks BOTH an
  /// active ride and active service_requests, since a customer asking
  /// "what's my status" doesn't necessarily know which system their
  /// thing lives in.
  static Future<String> activeOrderStatusSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "I couldn't check your orders — you don't seem to be signed in.";
    }

    final lines = <String>[];

    try {
      final rideSnap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('rides')
            .where('customerId', isEqualTo: uid)
            .where('status', whereIn: _activeRideStatuses)
            .limit(3),
      );
      for (final doc in rideSnap?.docs ?? const []) {
        final data = doc.data();
        final vehicleType = (data['vehicleType'] as String?) ?? 'ride';
        final status = (data['status'] as String?) ?? 'in progress';
        final dropAddress = (data['dropAddress'] as String?)?.trim();
        final destPart = (dropAddress != null && dropAddress.isNotEmpty) ? ' to $dropAddress' : '';
        lines.add('Your $vehicleType$destPart is currently: ${_humanizeStatus(status)}.');
      }
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] ride status lookup failed: $e');
    }

    try {
      // One-shot read, deliberately not the live streamCustomerRequests()
      // listener — a chat reply only needs a single point-in-time
      // answer, not a standing subscription.
      final requestSnap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('service_requests')
            .where('customerId', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(10),
      );
      for (final doc in requestSnap?.docs ?? const []) {
        final data = doc.data();
        final status = (data['status'] as String?) ?? 'pending';
        if (_terminalRequestStatuses.contains(status)) continue;
        final requestType = (data['requestType'] as String?) ?? 'order';
        lines.add('Your ${_humanizeRequestType(requestType, data['details'] as Map?)} is currently: ${_humanizeStatus(status)}.');
        // Only the most recent couple of active orders — enough to be
        // useful without turning the reply into a wall of text.
        if (lines.length >= 5) break;
      }
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] service request status lookup failed: $e');
    }

    if (lines.isEmpty) {
      return "You don't have any active rides or orders right now.";
    }
    return lines.join('\n');
  }

  static String _humanizeStatus(String status) {
    switch (status) {
      case 'searching':
        return 'looking for a nearby Hero';
      case 'assigned':
      case 'hero_assigned':
        return 'a Hero has been assigned';
      case 'accepted':
        return 'accepted, Hero is on the way';
      case 'arriving':
        return 'your Hero is arriving';
      case 'started':
      case 'in_progress':
        return 'in progress';
      case 'nearing_completion':
        return 'almost done';
      case 'pending':
        return 'waiting to be picked up by a Hero';
      case 'admin_review':
        return 'being reviewed by our team';
      default:
        return status.replaceAll('_', ' ');
    }
  }

  // FIX (Sep 2 2026 — service-booking flow audit, same class of bug
  // fixed in hero_home_screen.dart's ping dialog): every skill trade
  // (electrician, plumber, ..., acting_driver — see
  // hero_skill_catalog.dart) shares requestType 'electronics_service',
  // so this fell through to the generic default and told a customer
  // asking "where is my order" that their "electronics service" was
  // in progress, regardless of whether they'd actually booked a
  // plumber or an acting driver. `details` (optional, so every
  // existing call site keeps compiling unchanged) carries
  // `categoryLabel`, written verbatim by skilled_services_screen.dart.
  static String _humanizeRequestType(String requestType, [Map? details]) {
    if (requestType == 'electronics_service') {
      final categoryLabel = (details?['categoryLabel'] as String?)?.trim();
      if (categoryLabel != null && categoryLabel.isNotEmpty) return categoryLabel;
    }
    switch (requestType) {
      case 'grocery_order':
        return 'grocery order';
      case 'custom_food_order':
      case 'catalog_food_order':
        return 'food order';
      case 'hero_booking':
        return 'Hero booking';
      default:
        return requestType.replaceAll('_', ' ');
    }
  }

  // ================================================================
  // Aug 27 2026 — four more read-only lookups.
  // ================================================================
  // Nizam: Chitti could answer "how much is in my wallet" and "where
  // is my hero", and nothing else about the customer's own account.
  // Anything about points, past orders, notifications or their saved
  // profile fell through to a paragraph guess — and a guessed balance
  // is worse than no answer, because the customer believes it.
  //
  // Same safety class as the two above: pure `.get()` reads, no
  // writes, no confirmation gate. Same discipline too — each one
  // mirrors a query shape an existing screen already uses, and each
  // returns a finished sentence rather than raw data, so the model
  // relays a real number instead of inventing one.
  //
  // NOTE on query shapes: several of these deliberately filter on ONE
  // field and sort/filter the rest client-side. That is not sloppiness
  // — a `.where()` on one field combined with `.orderBy()` on another
  // needs a composite index, and my_orders_screen.dart already carries
  // a comment about hitting exactly that. On the Spark plan a missing
  // index is a hard query failure, so a bounded read plus a local sort
  // is both cheaper and safer than a query that works only after
  // someone remembers to deploy an index.

  /// "How many coins/points do I have?"
  static Future<String> rewardsBalanceSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "I couldn't check your rewards — you don't seem to be signed in.";
    }
    try {
      final doc = await ChittiLocalRead.doc(
        FirebaseFirestore.instance.collection('users').doc(uid),
      );
      final data = doc?.data() ?? <String, dynamic>{};
      final coins = (data['njCoinsBalance'] as num?)?.toInt() ?? 0;
      final pending = (data['njCoinsPending'] as num?)?.toInt() ?? 0;
      final expiring = (data['njCoinsExpiring'] as num?)?.toInt() ?? 0;

      final parts = <String>['You have $coins NJ Coins ready to use'];
      if (pending > 0) {
        parts.add('$pending more are still pending validation');
      }
      if (expiring > 0) {
        parts.add('$expiring expire within 7 days, so use those first');
      }
      return '${parts.join(', and ')}.';
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] rewardsBalanceSummary failed: $e');
      return "I couldn't reach your rewards balance right now — please try again in a moment.";
    }
  }

  /// "What did I order recently?" — the last few finished/past items
  /// across both orders and rides.
  static Future<String> recentOrdersSummary({int limit = 5}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "I couldn't check your order history — you don't seem to be signed in.";
    }

    // (timestamp, sentence) so the two collections can be merged and
    // sorted together — a customer asking "what did I order last week"
    // does not care which system the thing lives in.
    final entries = <MapEntry<DateTime, String>>[];

    try {
      final reqSnap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('service_requests')
            .where('customerId', isEqualTo: uid)
            .limit(20),
      );
      for (final doc in reqSnap?.docs ?? const []) {
        final data = doc.data();
        final when = (data['createdAt'] as Timestamp?)?.toDate();
        if (when == null) continue;
        final details = data['details'];
        final type = _humanizeRequestType(
          (data['requestType'] as String?) ?? 'order',
          details is Map ? details : null,
        );
        final items = details is Map<String, dynamic>
            ? (details['items'] as String?)?.trim()
            : null;
        final what = (items != null && items.isNotEmpty) ? ' — $items' : '';
        entries.add(MapEntry(when, '${_shortDate(when)}: $type$what'));
      }
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] recent service_requests failed: $e');
    }

    try {
      final rideSnap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('rides')
            .where('customerId', isEqualTo: uid)
            .limit(20),
      );
      for (final doc in rideSnap?.docs ?? const []) {
        final data = doc.data();
        final when = (data['createdAt'] as Timestamp?)?.toDate();
        if (when == null) continue;
        final vehicle = (data['vehicleType'] as String?) ?? 'ride';
        final drop = (data['dropAddress'] as String?)?.trim();
        final fare = (data['fare'] as num?)?.toDouble();
        final where = (drop != null && drop.isNotEmpty) ? ' to $drop' : '';
        final cost = fare != null ? ' (₹${fare.toStringAsFixed(0)})' : '';
        entries.add(
          MapEntry(when, '${_shortDate(when)}: $vehicle$where$cost'),
        );
      }
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] recent rides failed: $e');
    }

    if (entries.isEmpty) {
      return "I couldn't find any past orders or rides on your account yet.";
    }
    entries.sort((a, b) => b.key.compareTo(a.key));
    final lines = entries.take(limit).map((e) => e.value).join('\n');
    return 'Here are your most recent ones:\n$lines';
  }

  /// "Anything new for me?" — unread notifications.
  static Future<String> unreadNotificationsSummary({int limit = 5}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "I couldn't check your notifications — you don't seem to be signed in.";
    }
    try {
      // userId-only filter, unread + recency applied locally — see the
      // composite-index note at the top of this block.
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('notifications')
            .where('userId', isEqualTo: uid)
            .limit(30),
      );

      final unread = (snap?.docs ?? const [])
          .where((d) => d.data()['read'] != true)
          .map((d) => d.data())
          .toList()
        ..sort((a, b) {
          final at = (a['createdAt'] as Timestamp?)?.toDate();
          final bt = (b['createdAt'] as Timestamp?)?.toDate();
          if (at == null || bt == null) return 0;
          return bt.compareTo(at);
        });

      if (unread.isEmpty) {
        return 'You have no unread notifications right now.';
      }
      final lines = unread.take(limit).map((n) {
        final title = (n['title'] as String?)?.trim();
        final body = (n['message'] as String?)?.trim() ??
            (n['body'] as String?)?.trim() ??
            '';
        return (title != null && title.isNotEmpty) ? '$title — $body' : body;
      }).where((l) => l.isNotEmpty).join('\n');

      final count = unread.length;
      return 'You have $count unread notification${count == 1 ? '' : 's'}:\n$lines';
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] unreadNotificationsSummary failed: $e');
      return "I couldn't reach your notifications right now — please try again in a moment.";
    }
  }

  /// "What's my saved name/number/address, and is my SOS unlocked?"
  ///
  /// The SOS half matters more than it looks: SOS is unusable until
  /// KYC is approved, and a customer who does not know that finds out
  /// during an actual emergency. Chitti being able to answer it
  /// beforehand is the whole point.
  static Future<String> profileSummary() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) {
      return "You don't seem to be signed in, so I can't read your profile.";
    }
    try {
      final doc = await ChittiLocalRead.doc(
        FirebaseFirestore.instance.collection('users').doc(user.uid),
      );
      final data = doc?.data() ?? <String, dynamic>{};

      final name = (data['name'] as String?)?.trim().isNotEmpty ?? false
          ? (data['name'] as String).trim()
          : (user.displayName?.trim() ?? '');
      final phone = (data['phone'] as String?)?.trim().isNotEmpty ?? false
          ? (data['phone'] as String).trim()
          : (user.phoneNumber?.trim() ?? '');
      final address = (data['address'] as String?)?.trim() ?? '';

      final parts = <String>[];
      parts.add(
        name.isNotEmpty
            ? 'Your saved name is $name'
            : 'You have no name saved yet',
      );
      if (phone.isNotEmpty) parts.add('phone $phone');
      if (address.isNotEmpty) parts.add('address $address');

      String kycLine;
      try {
        final kyc = await ChittiLocalRead.doc(
          FirebaseFirestore.instance
              .collection('sos_kyc_requests')
              .doc(user.uid),
        );
        final status = kyc?.data()?['status'] as String?;
        kycLine = switch (status) {
          'approved' => ' Your SOS is verified and ready to use.',
          'pending' => ' Your SOS KYC is submitted and waiting for approval.',
          'rejected' =>
            ' Your SOS KYC was rejected — you can resubmit it from the SOS screen.',
          _ => ' You have not completed SOS KYC yet, so SOS is still locked.',
        };
      } catch (e) {
        debugPrint('[ChittiStatusLookupService] kyc read failed: $e');
        kycLine = '';
      }

      return '${parts.join(', ')}.$kycLine';
    } catch (e) {
      debugPrint('[ChittiStatusLookupService] profileSummary failed: $e');
      return "I couldn't read your profile right now — please try again in a moment.";
    }
  }

  static String _shortDate(DateTime d) {
    const months = <String>[
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${d.day} ${months[d.month - 1]}';
  }
}
