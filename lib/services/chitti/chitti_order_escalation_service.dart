// ================================================================
// chitti_order_escalation_service.dart — the order that must not wait
// for the admin to pick up their phone.
// ================================================================
// NEW (Aug 28 2026 — Nizam: "admin mobile attend pannalainalum new
// orders and customer ku kidaikama admin app ku varra booking, orders
// ah hero ku assign panni customer ku message anupuravaraikkum").
//
// THE PROBLEM
// Customer self-service orders already dispatch themselves:
// ServiceRequestService.createServiceRequest() broadcasts to every
// eligible hero the moment it is created. The orders that DON'T are
// the ones parked in `admin_review` — call-centre bookings and
// anything routed for a human decision. Those sit until an admin looks
// at the app. At 11pm on a Sunday that is nobody, and the customer is
// simply never served while believing they have ordered.
//
// WHO RUNS IT, AND WHY IT IS NOT A SERVER
// We are on the Spark plan: no Cloud Functions, no cron, no server.
// A timer on the admin's own phone was the obvious answer and is the
// wrong one — it cannot run when that phone is off, which is precisely
// the situation this exists for.
//
// So the HERO phones do it. They are already open, already online, and
// already listening for pings; a hero staring at an empty queue is the
// one person in the system with both the motive and the connection to
// notice a stranded order. This also needs no new infrastructure: once
// escalated, the order joins the SAME broadcast/atomic-accept path
// every other job uses, so the tested hero-side accept UI picks it up
// with zero changes.
//
// THE RACE THIS MUST SURVIVE
// Ten hero phones can notice the same stale order in the same second,
// and an admin may be tapping "assign" by hand at that exact moment.
// So escalation is a Firestore TRANSACTION that re-reads status inside
// the transaction and gives up unless the order is still unattended.
// Exactly one escalation wins; the other nine are no-ops, not errors.
// Getting this wrong would double-dispatch a customer's order — two
// heroes arriving, one unpaid.
//
// WHAT IT DELIBERATELY DOES NOT DO
// It never picks a specific hero. Choosing "the best" hero from a
// phone means every phone would choose differently, and the loser has
// already been told they have a job. Escalation only makes the order
// CLAIMABLE; the existing atomic accept decides who gets it. Nor does
// it touch money, pricing, or the customer's payment.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import '../firestore_usage_tracking.dart';
import '../service_request_service.dart';

/// How the escalation ended, so callers can say something true.
enum EscalationOutcome {
  /// This call escalated the order. Heroes are being pinged.
  escalated,

  /// Somebody else got there first — another hero's phone, or the
  /// admin. Not an error.
  alreadyHandled,

  /// The order is not old enough yet.
  tooSoon,

  /// Could not reach Firestore.
  failed,
}

class ChittiOrderEscalationService {
  ChittiOrderEscalationService._();
  static final ChittiOrderEscalationService instance =
      ChittiOrderEscalationService._();

  /// How long an order may sit unattended before any hero may release
  /// it.
  ///
  /// Ten minutes is a deliberate compromise. Shorter, and an admin who
  /// is genuinely mid-decision gets the order yanked out from under
  /// them. Longer, and a customer waiting on a meal has already given
  /// up and called somewhere else.
  static const Duration graceperiod = Duration(minutes: 10);

  /// The status an order sits in while it waits for a human.
  static const String pendingAdminStatus = 'admin_review';

  /// Where it goes once released — the same status a normal
  /// self-service order carries while heroes are being pinged.
  static const String releasedStatus = 'pending';

  static final FirebaseFirestore _db = FirebaseFirestore.instance;

  /// Orders old enough that any hero may release them.
  ///
  /// Equality filter only, aged in Dart. A `where` on status plus a
  /// range on timestamp needs a composite index, and on the Spark plan
  /// a missing index is a hard query failure rather than a slow one —
  /// which here would mean the safety net silently not existing.
  Stream<List<StrandedOrder>> watchStranded({int limit = 20}) {
    return _db
        .collection('service_requests')
        .where('status', isEqualTo: pendingAdminStatus)
        .limit(limit)
        .trackedSnapshots()
        .map((snap) {
      final now = DateTime.now();
      final items = snap.docs
          .map(StrandedOrder.fromDoc)
          .where((o) => o.isStrandedAt(now))
          .toList()
        ..sort((a, b) {
          final at = a.createdAt, bt = b.createdAt;
          if (at == null || bt == null) return 0;
          // Oldest first: the customer who has waited longest is the
          // one closest to giving up.
          return at.compareTo(bt);
        });
      return items;
    });
  }

  /// Releases one stranded order to every eligible hero.
  ///
  /// Safe to call from many phones at once — see the race note in the
  /// file header. Only one caller can win.
  Future<EscalationOutcome> escalate(String requestId) async {
    final ref = _db.collection('service_requests').doc(requestId);

    try {
      final outcome = await _db.runTransaction<EscalationOutcome>((tx) async {
        final snap = await tx.get(ref);
        if (!snap.exists) return EscalationOutcome.alreadyHandled;
        final data = snap.data() ?? <String, dynamic>{};

        // Re-checked INSIDE the transaction, not before it. Checking
        // outside would leave a window in which an admin assigns the
        // order by hand between the read and the write, and the
        // customer would get two heroes.
        if ((data['status'] as String?) != pendingAdminStatus) {
          return EscalationOutcome.alreadyHandled;
        }
        if (data['assignedHeroId'] != null) {
          return EscalationOutcome.alreadyHandled;
        }
        if (data['escalatedAt'] != null) {
          return EscalationOutcome.alreadyHandled;
        }

        final created = (data['timestamp'] as Timestamp?)?.toDate();
        if (created != null &&
            DateTime.now().difference(created) < graceperiod) {
          return EscalationOutcome.tooSoon;
        }

        tx.update(ref, <String, dynamic>{
          'status': releasedStatus,
          'escalatedAt': FieldValue.serverTimestamp(),
          // Recorded so the admin can see this was the safety net and
          // not a colleague. An escalation nobody can explain later is
          // indistinguishable from a bug.
          'escalatedBy': 'auto_unattended',
        });
        return EscalationOutcome.escalated;
      });

      if (outcome != EscalationOutcome.escalated) return outcome;

      // Only the winner does the side effects. Both are best-effort
      // and deliberately outside the transaction: a Firestore
      // transaction may be retried, and re-running a broadcast or
      // re-sending the customer a message on every retry would spam
      // both sides.
      //
      // FIX (Sep 2 2026 — audit): this used to call a local
      // _makeClaimable() that only ever flipped
      // active_service_requests/{requestId}'s status — it never wrote a
      // single hero_service_pings/{heroId}/{requestId} node, which is
      // the ONLY thing any hero client actually listens on to discover
      // new work. The banner told the hero "Sent to all heroes" and
      // genuinely notified nobody. rebroadcastForEscalation() is the
      // real fix — see its doc comment in service_request_service.dart
      // for the full story, including why a skill trade needs its
      // requiredSkill/location re-derived, not just a bare status flip.
      try {
        await ServiceRequestService().rebroadcastForEscalation(requestId);
      } catch (e) {
        debugPrint('[ChittiEscalation] rebroadcastForEscalation failed: $e');
      }
      await _tellCustomer(ref);
      return EscalationOutcome.escalated;
    } catch (e) {
      debugPrint('[ChittiEscalation] escalate failed: $e');
      return EscalationOutcome.failed;
    }
  }

  /// Tells the customer their order is moving.
  ///
  /// Nizam's brief ends with "customer ku message anupuravaraikkum" —
  /// the dispatch is only half of it. A customer whose order was
  /// silently rerouted still believes nothing has happened.
  ///
  /// Deliberately says nothing about an admin having missed it. The
  /// customer does not need to know how NJ Tech is staffed, and
  /// "nobody was watching your order" is not a message that builds
  /// confidence.
  Future<void> _tellCustomer(DocumentReference<Map<String, dynamic>> ref) async {
    try {
      final doc = await ref.get();
      final d = doc.data();
      final customerId = d?['customerId'] as String?;
      if (customerId == null || customerId.isEmpty) return;

      await _db.collection('notifications').add(<String, dynamic>{
        'userId': customerId,
        'title': 'Finding a Hero for your order',
        'message': customerMessage,
        'type': 'order_escalated',
        'requestId': ref.id,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'sentBy': 'chitti_auto',
      });
    } catch (e) {
      debugPrint('[ChittiEscalation] tellCustomer failed: $e');
    }
  }

  /// What the customer is told. Exposed so it can be asserted on.
  static const String customerMessage =
      'Good news — we are finding a Hero for your order right now. '
      'You will get an update as soon as someone accepts it.';
}

/// One order that has waited too long for a human.
@immutable
class StrandedOrder {
  const StrandedOrder({
    required this.id,
    required this.requestType,
    required this.customerName,
    this.createdAt,
  });

  factory StrandedOrder.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final d = doc.data();
    return StrandedOrder(
      id: doc.id,
      requestType: (d['requestType'] as String?) ?? '',
      customerName: (d['customerName'] as String?) ?? 'Customer',
      createdAt: (d['timestamp'] as Timestamp?)?.toDate(),
    );
  }

  final String id;
  final String requestType;
  final String customerName;
  final DateTime? createdAt;

  /// Whether this has waited past the grace period at [now].
  ///
  /// An order with no timestamp is NOT treated as stranded. Missing
  /// data is not evidence of age, and assuming it would release every
  /// malformed document the moment a hero opened the app.
  bool isStrandedAt(DateTime now) {
    final at = createdAt;
    if (at == null) return false;
    return now.difference(at) >= ChittiOrderEscalationService.graceperiod;
  }

  /// How long the customer has been waiting, for the hero-side card.
  String waitedLabel({DateTime? now}) {
    final at = createdAt;
    if (at == null) return '';
    final d = (now ?? DateTime.now()).difference(at);
    if (d.inHours >= 1) return '${d.inHours}h waiting';
    return '${d.inMinutes}m waiting';
  }
}
