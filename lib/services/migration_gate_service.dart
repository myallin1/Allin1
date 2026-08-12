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
        .snapshots()
        .listen(
      (snap) {
        final raw = snap.data()?['migrationUrl'] as String?;
        final next = (raw == null || raw.trim().isEmpty) ? null : raw.trim();
        if (next == _migrationUrl) return;
        _migrationUrl = next;
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
