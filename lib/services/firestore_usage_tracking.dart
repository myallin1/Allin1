// ================================================================
// firestore_usage_tracking.dart — automatic, accurate Firestore
// read/write attribution for DbUsageTracker.
// ================================================================
// PROBLEM (Nizam, Sep 2026 — "database read monitor system innum
// database read agura yella idathulayum pakkava reads ah monitor
// pannala"): DbUsageTracker existed, but recording a count required a
// developer to remember to call `.recordRead(...)` by hand at every
// single query/listener site. An audit found ~15 instrumented call
// sites against 135 live `.snapshots()` listeners and 61 `.get()`
// reads across the app — the monitor was seeing roughly a tenth of
// the app's real database activity, and the ~15 sites that WERE
// instrumented mostly hardcoded `recordRead(1)` regardless of how many
// documents a query actually returned, which is not what Firestore
// bills — a 50-document snapshot costs 50 reads, not 1.
//
// FIX: these extension methods are near-drop-in replacements for the
// four calls that actually cost money — `.snapshots()`, `.get()`,
// `.set()/.update()/.delete()`, `.add()` — named `trackedX()` instead
// of `x()`. They forward to the real Firestore call, count the ACTUAL
// number of documents involved (snapshot.docs.length for a query,
// 1 for a single document), and auto-derive the collection name for
// attribution from the reference's own path — so migrating a call site
// is a rename, not a rewrite:
//
//   ref.snapshots()   -> ref.trackedSnapshots()
//   ref.get()         -> ref.trackedGet()
//   ref.set(data)     -> ref.trackedSet(data)
//   ref.update(data)  -> ref.trackedUpdate(data)
//   ref.delete()      -> ref.trackedDelete()
//   coll.add(data)    -> coll.trackedAdd(data)
//
// An optional `screen` argument narrows attribution to the widget that
// issued the call, when a caller wants that extra precision (the
// existing 'screen::action' composite key DbUsageTracker/admin_db_
// usage_screen.dart already understand — see db_usage_tracker.dart).
// Omitting it still auto-attributes by COLLECTION, which is the more
// actionable dimension for cost work anyway: you fix a runaway read
// pattern by changing a QUERY, not by renaming a widget.
//
// DOES NOT COVER Realtime Database (`FirebaseDatabase`/`DatabaseReference`)
// — a separate product with its own, very different, bandwidth-based
// pricing model, not a Firestore read/write count. RTDB usage isn't
// part of what this ticket was asked to fix.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'db_usage_tracker.dart';

/// Best-effort collection name for attribution, derived from a
/// Firestore reference's own path — no manual labeling required.
///
/// `CollectionReference.path` is already just the collection name for
/// a root collection ('service_requests') or 'parent/sub' for a
/// subcollection. For a `Query` produced by `.where()`/`.orderBy()`
/// (which does not expose `.path` in the public SDK), this falls back
/// to casting to `CollectionReference` when the query IS an
/// unfiltered collection reference, and to 'query:<runtimeType>'
/// otherwise — still far more useful than the old 'unattributed'
/// bucket, and never blocks a caller who wants to pass an explicit
/// `screen` label instead.
String _autoLabel(Object ref) {
  if (ref is DocumentReference) {
    // 'service_requests/AbC123' -> 'service_requests'
    final path = ref.path;
    final slash = path.indexOf('/');
    return slash == -1 ? path : path.substring(0, slash);
  }
  if (ref is CollectionReference) {
    return ref.path;
  }
  return 'query:${ref.runtimeType}';
}

extension TrackedQuery<T> on Query<T> {
  /// Drop-in replacement for [snapshots] that counts every document in
  /// every emitted snapshot — the real Firestore read cost of a live
  /// listener, not "1 per update" the way the old manual call sites
  /// (that remembered to instrument themselves at all) counted it.
  Stream<QuerySnapshot<T>> trackedSnapshots({String? screen, String? action}) {
    final label = screen ?? _autoLabel(this);
    return snapshots().map((snap) {
      DbUsageTracker.instance.recordRead(snap.docs.length, label, action);
      return snap;
    });
  }

  /// Drop-in replacement for [get].
  Future<QuerySnapshot<T>> trackedGet({
    String? screen,
    String? action,
    GetOptions? options,
  }) async {
    final snap = await get(options);
    DbUsageTracker.instance
        .recordRead(snap.docs.length, screen ?? _autoLabel(this), action);
    return snap;
  }
}

extension TrackedDocumentReference<T> on DocumentReference<T> {
  /// Drop-in replacement for [snapshots]. A document listener always
  /// costs exactly 1 read per emission (whether or not the document
  /// exists), unlike a query listener's variable doc count above.
  Stream<DocumentSnapshot<T>> trackedSnapshots({String? screen, String? action}) {
    final label = screen ?? _autoLabel(this);
    return snapshots().map((snap) {
      DbUsageTracker.instance.recordRead(1, label, action);
      return snap;
    });
  }

  /// Drop-in replacement for [get].
  Future<DocumentSnapshot<T>> trackedGet({
    String? screen,
    String? action,
    GetOptions? options,
  }) async {
    final snap = await get(options);
    DbUsageTracker.instance
        .recordRead(1, screen ?? _autoLabel(this), action);
    return snap;
  }

  /// Drop-in replacement for [set].
  Future<void> trackedSet(T data, [SetOptions? options, String? screen, String? action]) {
    DbUsageTracker.instance.recordWrite(1, screen ?? _autoLabel(this), action);
    return set(data, options);
  }

  /// Drop-in replacement for [update]. NOTE: Firestore's [update]
  /// signature takes `Map<Object, Object?>`, same as the underlying
  /// SDK call — this is a straight pass-through, not a typed [T] write.
  Future<void> trackedUpdate(Map<Object, Object?> data, {String? screen, String? action}) {
    DbUsageTracker.instance.recordWrite(1, screen ?? _autoLabel(this), action);
    return update(data);
  }

  /// Drop-in replacement for [delete].
  Future<void> trackedDelete({String? screen, String? action}) {
    DbUsageTracker.instance.recordWrite(1, screen ?? _autoLabel(this), action);
    return delete();
  }
}

extension TrackedAggregateQuery on AggregateQuery {
  /// Drop-in replacement for [get] on a `.count()`/`.sum()`/`.avg()`
  /// aggregate query — Firestore bills these as exactly ONE read
  /// regardless of how many documents matched, never the matched count.
  Future<AggregateQuerySnapshot> trackedGet({
    String? screen,
    String? action,
    AggregateSource source = AggregateSource.server,
  }) async {
    final snap = await get(source: source);
    DbUsageTracker.instance.recordRead(1, screen ?? _autoLabel(this), action);
    return snap;
  }
}

extension TrackedCollectionReference<T> on CollectionReference<T> {
  /// Drop-in replacement for [add].
  Future<DocumentReference<T>> trackedAdd(T data, {String? screen, String? action}) {
    DbUsageTracker.instance.recordWrite(1, screen ?? _autoLabel(this), action);
    return add(data);
  }
}

extension TrackedWriteBatch on WriteBatch {
  /// A batch is ONE network write regardless of how many operations are
  /// queued in it — Firestore bills per-document-write inside the
  /// batch, so [opCount] (how many .set/.update/.delete calls were
  /// added to this batch before calling this) is required, not
  /// inferred; there is no public API to introspect a WriteBatch's
  /// queued operations.
  Future<void> trackedCommit(int opCount, {String? screen, String? action}) {
    DbUsageTracker.instance.recordWrite(opCount, screen ?? 'batch', action);
    return commit();
  }
}
