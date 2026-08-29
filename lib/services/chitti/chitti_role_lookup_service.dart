// ================================================================
// chitti_role_lookup_service.dart — read-only lookups for the Hero
// and Seller apps.
// ================================================================
// NEW (Aug 27 2026 — Nizam: Chitti must work A-Z in every app, not
// just for customers).
//
// GuruApiService already backed the Hero and Seller builds through
// GlobalGuruFab, and Chitti already had a Hero persona describing
// itself as their "manager, accountant, coach and ride tracker". It
// had no tools at all in those builds — the persona promised precise
// numbers while the only thing the model could do was talk. The
// persona itself says "NEVER invent one", which left it stuck saying
// "I don't have that figure" to every question it was written for.
// These four reads are what make that persona honest.
//
// Same rules as ChittiStatusLookupService, deliberately:
//   • pure `.get()` reads, no writes anywhere in this file, so no
//     confirmation gate is needed — a wrong call yields a wrong
//     answer, never a wrong action;
//   • every query copies a shape a real screen already uses, rather
//     than a guess at field names;
//   • each returns a finished sentence, so the model relays a real
//     number instead of paraphrasing a data structure into a wrong one.
//
// The one place that discipline bends is date filtering: "today" is
// applied in Dart after a bounded fetch rather than as a Firestore
// range. A range filter on `timestamp` combined with the `heroId`
// equality filter needs a composite index, and on the Spark plan a
// missing index is a hard query failure at runtime, not a slow query.
// A bounded read plus a local filter cannot fail that way.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import 'chitti_enquiry_service.dart';
import 'chitti_local_read.dart';

class ChittiRoleLookupService {
  ChittiRoleLookupService._();

  /// Ceiling on every admin counting read.
  ///
  /// An admin queue is unbounded by nature. Counting it exactly would
  /// mean reading every document, and on the Spark plan's 50,000
  /// reads/day one impatient owner asking "how many pending?" a few
  /// times could spend a meaningful slice of the whole platform's
  /// daily budget. A capped count plus an honest "or more" is the right
  /// trade: the answer an owner acts on is "a lot" or "none".
  static const int _adminCountCap = 100;

  /// Renders a possibly-capped count without ever overstating it.
  static String _countLabel(int n) => n >= _adminCountCap ? '$n or more' : '$n';

  // Same restorable-status family hero_home_screen.dart uses to decide
  // whether a hero has a live job to resume on cold start.
  static const List<String> _activeHeroRideStatuses = <String>[
    'accepted',
    'arrived',
    'started',
    'in_progress',
    'ongoing',
  ];

  // Exactly the whereIn list seller_dashboard_screen.dart's two
  // order listeners use — an order is "pending" for the seller until
  // it leaves this set.
  static const List<String> _openSellerOrderStatuses = <String>[
    'pending',
    'admin_review',
    'hero_assigned',
    'in_progress',
    'nearing_completion',
  ];

  // ── HERO ────────────────────────────────────────────────────────

  /// "How much have I earned today?"
  static Future<String> heroTodayEarningsSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "You don't seem to be signed in, so I can't read your earnings.";
    }
    try {
      // Same collection + heroId filter hero_earnings_screen.dart reads.
      // 200 documents for one question was the single most expensive
      // thing Chitti did — a hundred heroes asking twice a day is
      // 40,000 reads against a 50,000/day free quota, for this alone.
      //
      // Two changes: served from the device cache (not billed, works
      // offline), and 200 -> 60. A hero does not have two hundred
      // transactions in a day; the cap only ever needed to cover one,
      // and everything older is filtered out below anyway.
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('wallet_transactions')
            .where('heroId', isEqualTo: uid)
            .limit(60),
      );
      if (snap == null) {
        return "I couldn't reach your earnings right now — please try again in a moment.";
      }

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      var total = 0.0;
      var count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['timestamp'];
        final when = ts is Timestamp ? ts.toDate() : null;
        if (when == null || when.isBefore(startOfDay)) continue;
        final amount = (data['amount'] as num?)?.toDouble() ?? 0.0;
        // Credits only. Wallet debits (the per-ride platform fee, the
        // monitor-refresh fee) are real transactions on the same
        // collection, and counting them would quietly understate what
        // the hero actually earned.
        if (amount <= 0) continue;
        total += amount;
        count++;
      }

      if (count == 0) {
        return "You haven't earned anything yet today. Go online and the pings "
            'will start coming.';
      }
      return "Today you've earned ₹${total.toStringAsFixed(0)} across $count "
          'payment${count == 1 ? '' : 's'}.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] heroTodayEarnings failed: $e');
      return "I couldn't reach your earnings right now — please try again in a moment.";
    }
  }

  /// "What job am I on?"
  static Future<String> heroActiveJobSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "You don't seem to be signed in, so I can't check your jobs.";
    }
    final lines = <String>[];

    try {
      final rideSnap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('rides')
            .where('heroId', isEqualTo: uid)
            .where('status', whereIn: _activeHeroRideStatuses)
            .limit(3),
      );
      for (final doc in rideSnap?.docs ?? const []) {
        final data = doc.data();
        final vehicle = (data['vehicleType'] as String?) ?? 'ride';
        final status = (data['status'] as String?) ?? 'in progress';
        final pickup = (data['pickupAddress'] as String?)?.trim();
        final drop = (data['dropAddress'] as String?)?.trim();
        final fare = (data['fare'] as num?)?.toDouble();
        final route = <String>[
          if (pickup != null && pickup.isNotEmpty) 'from $pickup',
          if (drop != null && drop.isNotEmpty) 'to $drop',
        ].join(' ');
        final money = fare != null ? ' — ₹${fare.toStringAsFixed(0)}' : '';
        lines.add('$vehicle $route ($status)$money'.replaceAll('  ', ' '));
      }
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] hero active rides failed: $e');
    }

    try {
      final reqSnap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('service_requests')
            .where('heroId', isEqualTo: uid)
            .limit(10),
      );
      for (final doc in reqSnap?.docs ?? const []) {
        final data = doc.data();
        final status = (data['status'] as String?) ?? '';
        if (!_openSellerOrderStatuses.contains(status)) continue;
        final type =
            ((data['requestType'] as String?) ?? 'job').replaceAll('_', ' ');
        final details = data['details'];
        final items = details is Map<String, dynamic>
            ? (details['items'] as String?)?.trim()
            : null;
        lines.add('$type${items != null && items.isNotEmpty ? ' — $items' : ''} ($status)');
      }
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] hero active requests failed: $e');
    }

    if (lines.isEmpty) {
      return 'You have no active job right now.';
    }
    return 'Your active work:\n${lines.join('\n')}';
  }

  /// "What's in my wallet / how much do I owe?"
  ///
  /// Heroes run a PREPAID balance the per-ride platform fee is drawn
  /// from (see hero_wallet_service.dart) — a hero whose balance runs
  /// out stops getting jobs, so this is a question worth answering
  /// before it becomes a problem, not after.
  static Future<String> heroWalletSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "You don't seem to be signed in, so I can't read your wallet.";
    }
    try {
      // Money, so the same rule as the customer wallet: server-read
      // only when something has moved. See ChittiLocalRead.wallet.
      final doc = await ChittiLocalRead.wallet(
        FirebaseFirestore.instance.collection('hero_wallets').doc(uid),
      );
      if (doc == null) {
        return "I couldn't reach your wallet right now — please try again in a moment.";
      }
      if (!doc.exists) {
        return 'You have no wallet balance set up yet — recharge from the '
            'Hero Wallet screen to start taking jobs.';
      }
      final balance = (doc.data()?['balance'] as num?)?.toDouble() ?? 0.0;
      if (balance <= 0) {
        return 'Your hero wallet is empty (₹${balance.toStringAsFixed(2)}). '
            'Recharge it or jobs will stop coming.';
      }
      if (balance < 50) {
        return 'Your hero wallet has ₹${balance.toStringAsFixed(2)} left — '
            'that is running low, worth recharging today.';
      }
      return 'Your hero wallet balance is ₹${balance.toStringAsFixed(2)}.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] heroWalletSummary failed: $e');
      return "I couldn't reach your wallet right now — please try again in a moment.";
    }
  }


  /// "Enna vela bakki iruku?" — what is still open on the Hero's plate.
  ///
  /// Distinct from [heroActiveJobSummary], which answers "what am I
  /// doing RIGHT NOW". This one answers "what is waiting", which is the
  /// question a Hero actually asks between jobs.
  static Future<String> heroPendingWorkSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "You don't seem to be signed in, so I can't check your work.";
    }
    try {
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('service_requests')
            .where('heroId', isEqualTo: uid)
            .limit(50),
      );
      if (snap == null) {
        return "I couldn't reach your jobs right now — please try again in a moment.";
      }
      final open = snap.docs
          .where((d) => _activeHeroRideStatuses.contains(
                d.data()['status'] as String?,
              ))
          .toList();
      if (open.isEmpty) {
        return 'Nothing is pending on you — you are clear. Stay online and '
            'I will tell you the moment a job comes in.';
      }
      final n = open.length;
      return 'You have $n job${n == 1 ? '' : 's'} still open. '
          'Finish ${n == 1 ? 'it' : 'them'} to get paid for the day.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] heroPendingWork failed: $e');
      return "I couldn't reach your jobs right now — please try again in a moment.";
    }
  }

  // ── SELLER ──────────────────────────────────────────────────────

  /// "What orders are waiting on me?"
  static Future<String> sellerPendingOrdersSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "You don't seem to be signed in, so I can't check your orders.";
    }
    try {
      // Equality-only on details.sellerId, with requestType and status
      // filtered locally. seller_dashboard_screen.dart runs two
      // separate indexed listeners for this; a chat answer does not
      // justify depending on those indexes existing, and one read is
      // cheaper than two.
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('service_requests')
            .where('details.sellerId', isEqualTo: uid)
            .limit(50),
      );
      if (snap == null) {
        return "I couldn't reach your orders right now — please try again in a moment.";
      }

      final open = snap.docs
          .where(
            (d) => _openSellerOrderStatuses.contains(
              d.data()['status'] as String?,
            ),
          )
          .toList();

      if (open.isEmpty) {
        return 'No orders are waiting on you right now.';
      }

      final lines = open.take(6).map((doc) {
        final data = doc.data();
        final status = (data['status'] as String?) ?? '';
        final details = data['details'];
        final items = details is Map<String, dynamic>
            ? (details['items'] as String?)?.trim()
            : null;
        return '${items != null && items.isNotEmpty ? items : 'Order'} ($status)';
      }).join('\n');

      final n = open.length;
      return 'You have $n order${n == 1 ? '' : 's'} in progress:\n$lines';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] sellerPendingOrders failed: $e');
      return "I couldn't reach your orders right now — please try again in a moment.";
    }
  }

  /// "How much did the shop make today?"
  static Future<String> sellerTodayEarningsSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "You don't seem to be signed in, so I can't read your earnings.";
    }
    try {
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('service_requests')
            .where('details.sellerId', isEqualTo: uid)
            .limit(100),
      );
      if (snap == null) {
        return "I couldn't reach your earnings right now — please try again in a moment.";
      }

      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);

      var total = 0.0;
      var count = 0;
      for (final doc in snap.docs) {
        final data = doc.data();
        final ts = data['createdAt'];
        final when = ts is Timestamp ? ts.toDate() : null;
        if (when == null || when.isBefore(startOfDay)) continue;
        // Cancelled orders are still documents; counting them would
        // report money the shop never received.
        final status = (data['status'] as String?) ?? '';
        if (status == 'cancelled' || status == 'rejected') continue;
        final details = data['details'];
        final amount = details is Map<String, dynamic>
            ? (details['totalAmount'] as num?)?.toDouble() ??
                (details['amount'] as num?)?.toDouble()
            : null;
        if (amount != null) total += amount;
        count++;
      }

      if (count == 0) {
        return 'No orders have come in today yet.';
      }
      if (total <= 0) {
        return "You've had $count order${count == 1 ? '' : 's'} today. I "
            "couldn't read the amounts — check the Earnings screen for the "
            'exact total.';
      }
      return "Today you've had $count order${count == 1 ? '' : 's'} worth "
          '₹${total.toStringAsFixed(0)}.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] sellerTodayEarnings failed: $e');
      return "I couldn't reach your earnings right now — please try again in a moment.";
    }
  }

  /// "Kadai open ah iruka?" — the shop's own state, read not guessed.
  ///
  /// Sellers ask this after closing up on one device and opening the
  /// app on another. Chitti answering from memory would be worse than
  /// not answering.
  static Future<String> sellerShopStatusSummary() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      return "You don't seem to be signed in, so I can't check your shop.";
    }
    try {
      final doc = await ChittiLocalRead.doc(
        FirebaseFirestore.instance.collection('sellers').doc(uid),
      );
      final data = doc?.data();
      if (data == null) {
        return "I couldn't reach your shop details right now — please try "
            'again in a moment.';
      }
      final isOpen = data['isOpen'] == true;
      final name = (data['shopName'] as String?)?.trim();
      final label = name != null && name.isNotEmpty ? name : 'Your shop';
      final status = (data['status'] as String?) ?? '';
      if (status == 'pending') {
        return '$label is still awaiting admin approval. Once it is '
            'approved you can open for orders.';
      }
      return isOpen
          ? '$label is OPEN — customers can order right now.'
          : '$label is CLOSED. Customers cannot order until you open it.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] sellerShopStatus failed: $e');
      return "I couldn't reach your shop details right now — please try "
          'again in a moment.';
    }
  }

  // ── ADMIN ───────────────────────────────────────────────────────
  //
  // NEW (Aug 28 2026 — Nizam: "admin, seller, hero app la iruka
  // chittikum intha customer app mari power kudu").
  //
  // Admin had three tools, all of them navigation or plumbing, so
  // Chitti could open a screen and then had nothing to say about what
  // was on it. These are the questions an owner actually asks while
  // away from the desk — how much is piling up, and on which pile.
  //
  // Counts, not listings. Admin queues run to hundreds of documents;
  // reading them all to answer "how many" would cost more in one
  // question than a Hero costs in a day. Each is capped, cache-first,
  // and says "or more" rather than pretending a capped count is exact.

  /// "Yaru approval ku wait pandranga?" — both approval queues at once.
  ///
  /// One answer covering heroes and sellers, because an owner checking
  /// in wants the backlog, not a menu of two questions.
  static Future<String> adminPendingApprovalsSummary() async {
    try {
      final heroes = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('heroes')
            .where('approvalStatus', isEqualTo: 'pending')
            .limit(_adminCountCap),
      );
      final sellers = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('sellers')
            .where('status', isEqualTo: 'pending')
            .limit(_adminCountCap),
      );
      if (heroes == null && sellers == null) {
        return "I couldn't reach the approval queues right now — please try "
            'again in a moment.';
      }
      final h = heroes?.docs.length ?? 0;
      final se = sellers?.docs.length ?? 0;
      if (h == 0 && se == 0) {
        return 'Both approval queues are clear — no heroes or sellers are '
            'waiting on you.';
      }
      final parts = <String>[
        if (h > 0) '${_countLabel(h)} hero${h == 1 ? '' : 'es'}',
        if (se > 0) '${_countLabel(se)} seller${se == 1 ? '' : 's'}',
      ];
      return 'Waiting for approval: ${parts.join(' and ')}.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] adminPendingApprovals failed: $e');
      return "I couldn't reach the approval queues right now — please try "
          'again in a moment.';
    }
  }

  /// "Innaiku evlo order?" — today's activity across the platform.
  static Future<String> adminTodayActivitySummary() async {
    try {
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('service_requests')
            .orderBy('timestamp', descending: true)
            .limit(_adminCountCap),
      );
      if (snap == null) {
        return "I couldn't reach today's orders right now — please try again "
            'in a moment.';
      }
      // Date filtering in Dart, for the composite-index reason at the
      // top of this file.
      final now = DateTime.now();
      final today = snap.docs.where((d) {
        final ts = d.data()['timestamp'];
        if (ts is! Timestamp) return false;
        final t = ts.toDate();
        return t.year == now.year && t.month == now.month && t.day == now.day;
      }).toList();
      if (today.isEmpty) {
        return 'No orders have come in today yet.';
      }
      final open = today
          .where((d) => (d.data()['status'] as String?) != 'completed')
          .length;
      final n = today.length;
      return '$n order${n == 1 ? '' : 's'} today, $open still in progress.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] adminTodayActivity failed: $e');
      return "I couldn't reach today's orders right now — please try again "
          'in a moment.';
    }
  }

  /// "Yethachum bug report irukka?" — unresolved bugs, worst first.
  static Future<String> adminOpenBugsSummary() async {
    try {
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection('app_bug_reports')
            .orderBy('createdAt', descending: true)
            .limit(_adminCountCap),
      );
      if (snap == null) {
        return "I couldn't reach the bug reports right now — please try "
            'again in a moment.';
      }
      final open = snap.docs
          .where((d) => (d.data()['status'] as String?) != 'resolved')
          .toList();
      if (open.isEmpty) {
        return 'No open bug reports — everything reported has been resolved.';
      }
      final high =
          open.where((d) => (d.data()['severity'] as String?) == 'high').length;
      final n = open.length;
      return '$n open bug report${n == 1 ? '' : 's'}'
          '${high > 0 ? ', $high marked high severity' : ''}.';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] adminOpenBugs failed: $e');
      return "I couldn't reach the bug reports right now — please try again "
          'in a moment.';
    }
  }

  /// "Customer enna kekuranga?" — open Chitti enquiries needing a price.
  ///
  /// These are leads with a phone number attached, so they are the most
  /// perishable thing in the admin app: a rate question answered
  /// tomorrow has already been answered by somebody else's shop.
  static Future<String> adminOpenEnquiriesSummary() async {
    try {
      final snap = await ChittiLocalRead.query(
        FirebaseFirestore.instance
            .collection(ChittiEnquiryService.collectionPath)
            .where('status', isEqualTo: 'open')
            .limit(_adminCountCap),
      );
      if (snap == null) {
        return "I couldn't reach the enquiries right now — please try again "
            'in a moment.';
      }
      if (snap.docs.isEmpty) {
        return 'No customer enquiries are waiting for a price.';
      }
      final lines = snap.docs.take(5).map((d) {
        final data = d.data();
        final q = ((data['question'] as String?) ?? '').trim();
        final who = ((data['customerName'] as String?) ?? '').trim();
        final short = q.length > 70 ? '${q.substring(0, 70)}…' : q;
        return who.isEmpty ? '• $short' : '• $short — $who';
      }).join('\n');
      final n = snap.docs.length;
      return '${_countLabel(n)} customer${n == 1 ? '' : 's'} waiting for a '
          'price from you:\n$lines';
    } catch (e) {
      debugPrint('[ChittiRoleLookupService] adminOpenEnquiries failed: $e');
      return "I couldn't reach the enquiries right now — please try again "
          'in a moment.';
    }
  }

}
