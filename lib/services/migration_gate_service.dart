// ================================================================
// MigrationGateService — the "Zero-Budget Escape Hatch"
// ================================================================
// NEW (Aug 12 2026 — CTO mandate, "In-App Migration Notice Board"): a
// single global kill-switch shared by all 4 apps (customer/hero/seller/
// admin). Firestore doc `system_settings/app_status`, field
// `migrationUrl` (String, absent/empty by default). The instant that
// field is ever populated from the Admin app, every app instance
// currently open — mid-session, not just on next launch — locks its UI
// behind MigrationNoticeOverlay and points the customer at wherever the
// business has moved.
//
// WHY THIS EXISTS: the whole point is business continuity if this
// Firebase project is ever abandoned/deleted/replaced (the CTO's own
// framing — "we never lose our customer base even if we abandon this
// Firebase project later"). That means it has to work with ZERO other
// infrastructure — no Cloud Functions, no push notification, nothing
// beyond a single Firestore doc read this project already pays for.
//
// WHY A LIVE .snapshots() LISTENER, NOT A ONE-TIME .get(): a kill-switch
// that only checks at boot would strand every customer who already has
// the app open when the CTO flips it — they'd have to fully close and
// reopen to ever see the notice. A snapshot listener costs exactly one
// read at subscribe time and one more read only if/when the doc
// actually changes (Firestore's realtime-listener billing model, not
// polling) — this is the cheap, correct tool for "push an instant
// global lock," unlike the DB Monitor's own deliberate avoidance of
// live listeners for analytics elsewhere in this app (a different
// problem: that was about not running heavy, continuously-updating
// list queries, not about a single lightweight doc watch like this one).
//
// FAIL-OPEN BY DESIGN: any listener error (permission denied, offline,
// whatever) leaves `migrationUrl` exactly as it already was — almost
// always null — so a Firestore hiccup can NEVER accidentally lock a
// healthy app out. The only way this ever locks anyone out is an
// explicit admin write.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import './firestore_usage_tracking.dart';

class MigrationGateService extends ChangeNotifier {
  MigrationGateService._();
  static final MigrationGateService instance = MigrationGateService._();

  static const String _collection = 'system_settings';
  static const String _docId = 'app_status';

  String? _migrationUrl;

  /// Null/empty = normal operation. Non-empty = every app-root overlay
  /// should be showing MigrationNoticeOverlay right now, pointed here.
  String? get migrationUrl => _migrationUrl;

  bool get isMigrating => _migrationUrl != null && _migrationUrl!.isNotEmpty;

  // ================================================================
  // REWARDS PUBLISH SIGNAL  (Aug 18 2026 — Nizam's "admin ping" idea)
  // ================================================================
  // Piggybacks on the listener this service ALREADY runs. That is the
  // entire point, and it is worth stating plainly:
  //
  //   This service already holds one live snapshot listener on
  //   system_settings/app_status in all four apps. Firestore bills a
  //   realtime listener 1 read at attach and 1 read per change of the
  //   watched document — NOT per second, and NOT per field. So reading
  //   an additional field off the SAME document adds exactly ZERO
  //   reads and ZERO connections. The transport is already paid for.
  //
  // WHY NOT RTDB (the original proposal): Firebase RTDB on the Spark
  // plan caps at 100 SIMULTANEOUS CONNECTIONS. A live rewards listener
  // per customer would hold one connection each and break at ~100
  // concurrent users, with the 101st simply refused — a hard growth
  // ceiling on a live app. Firestore has no such concurrent-connection
  // cap, which is why the same "instant push" behaviour is safe here
  // and was not there.
  //
  // WHY A COUNTER AND NOT A TIMESTAMP: an int bumped by
  // FieldValue.increment(1) is immune to client clock skew and to two
  // admins publishing in the same second.
  //
  // COST DISCIPLINE — read this before wiring any new caller: every
  // CHANGE to this doc costs 1 read on every currently-connected app.
  // That is why the admin bumps this ONCE from an explicit "Publish
  // Rewards" button, never automatically on each individual offer
  // edit. Editing 10 offers with per-edit bumping would cost
  // 10 x (every online user) reads for zero user benefit.
  int _rewardsVersion = 0;

  /// Monotonically increasing counter bumped by the admin's "Publish
  /// Rewards" action. Consumers cache content locally and only refetch
  /// when this value differs from the one they cached against.
  ///
  /// 0 means "never published, or unknown" — treat that as 'no forced
  /// refresh', never as 'invalidate everything'.
  int get rewardsVersion => _rewardsVersion;

  // NEW (Aug 19 2026 — Home Page Banner Offers). Exact same
  // zero-extra-cost piggyback as rewardsVersion above: same doc, same
  // already-open listener, bumped once by the admin's own "Publish"
  // action in admin_home_banner_screen.dart. Kept as its own counter
  // (not reusing rewardsVersion) so publishing a banner change never
  // forces every customer to also refetch the unrelated Erode Offers
  // list, and vice versa.
  int _homeBannerVersion = 0;

  int get homeBannerVersion => _homeBannerVersion;

  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _sub;
  bool _started = false;

  /// Fire-and-forget, non-blocking — every main_*.dart calls this once,
  /// AFTER runApp(), same "never delay the first frame" discipline as
  /// every other post-boot warm-up in this codebase. Idempotent: safe to
  /// call more than once (e.g. a hot restart in dev), only the first
  /// call actually subscribes.
  void start() {
    if (_started) return;
    _started = true;
    _sub = FirebaseFirestore.instance
        .collection(_collection)
        .doc(_docId)
        .trackedSnapshots()
        .listen(
      (snap) {
        final data = snap.data();

        // ── Kill-switch (unchanged, and deliberately evaluated FIRST).
        final raw = data?['migrationUrl'] as String?;
        final next = (raw == null || raw.trim().isEmpty) ? null : raw.trim();

        // ── Rewards publish signal. Parsed defensively and in its own
        // try/catch so a malformed rewardsVersion (wrong type, hand-
        // edited in the console, whatever) can NEVER throw inside this
        // handler and take the kill-switch down with it. The kill-
        // switch is business-continuity insurance; a promo-refresh hint
        // must never be able to compromise it.
        var nextVersion = _rewardsVersion;
        try {
          final v = data?['rewardsVersion'];
          if (v is int) {
            nextVersion = v;
          } else if (v is num) {
            nextVersion = v.toInt();
          }
        } catch (e) {
          debugPrint('[MigrationGateService] bad rewardsVersion, ignoring: $e');
        }

        var nextBannerVersion = _homeBannerVersion;
        try {
          final v = data?['homeBannerVersion'];
          if (v is int) {
            nextBannerVersion = v;
          } else if (v is num) {
            nextBannerVersion = v.toInt();
          }
        } catch (e) {
          debugPrint('[MigrationGateService] bad homeBannerVersion, ignoring: $e');
        }

        final urlChanged = next != _migrationUrl;
        final versionChanged = nextVersion != _rewardsVersion;
        final bannerVersionChanged = nextBannerVersion != _homeBannerVersion;
        if (!urlChanged && !versionChanged && !bannerVersionChanged) return;

        _migrationUrl = next;
        _rewardsVersion = nextVersion;
        _homeBannerVersion = nextBannerVersion;
        notifyListeners();
      },
      onError: (Object e) {
        debugPrint('[MigrationGateService] listener error (fail-open, no lock applied): $e');
      },
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    super.dispose();
  }
}
