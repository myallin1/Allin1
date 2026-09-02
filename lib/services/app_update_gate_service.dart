// ================================================================
// app_update_gate_service.dart — "a newer build exists" check
// ================================================================
// NEW (Aug 17 2026 — Nizam: "hero app and pwa button um ipaye update
// pannu bcoz namma app launch panitom heros join panitrukanga and innum
// namma hero app la bug um iruku so intha update sytem iruntha than
// namma atha solve pannamudiyum").
//
// THE PROBLEM
// Heroes are already using the live app, and fixes cannot reach them.
// The native "Check for Updates" button opens the GitHub APK link
// BLINDLY — it has no idea whether a newer build actually exists, so it
// cannot tell a hero "there is a fix waiting", and a hero has no reason
// to ever tap it. On web, WebVersionChecker already solves this properly
// (it diffs /version.json). Native had no equivalent.
//
// ── DATABASE COST (deliberate, and different from MigrationGateService)
// ONE Firestore .get() per app launch. NOT a .snapshots() listener.
//
// MigrationGateService intentionally uses a live listener because it is
// a KILL SWITCH — if the app must stop, it must stop within seconds. An
// update notice has no such urgency: a hero learning about a new build
// on their next app open is completely acceptable, and a permanent
// listener per hero per session is a standing cost for information that
// changes maybe once a week. Cheapest correct tool, not the most
// powerful one.
//
// The result is cached in memory for the process lifetime, so opening
// and closing screens costs nothing further.
//
// ── HOW THE CURRENT BUILD NUMBER IS KNOWN
// From AppKnowledge.version, which tools/gen_app_knowledge.dart stamps
// out of pubspec.yaml on every deploy (e.g. '1.0.9+222'). No
// package_info_plus dependency needed, and it cannot drift from the
// build it shipped with — deploy_web.ps1 bumps pubspec and regenerates
// that file in the same run.
//
// ── FIRESTORE SHAPE
//   system_settings/app_versions
//     hero_build:      222        <- integer, compared numerically
//     hero_notes:      'Fixes login + earnings total'
//     hero_apk_url:    ''         <- optional override; blank = GitHub latest
//     customer_build:  222
//     ...same three keys per flavor (customer / hero / seller / admin)
//
// Publish an update by editing ONE number in the Firebase console after
// the APK is uploaded. Nothing is auto-detected, on purpose: a build
// existing on GitHub is not the same as a build you have decided to
// push to a live fleet.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import '../config/app_knowledge.dart';
import 'update_service.dart';
import './firestore_usage_tracking.dart';

class AppUpdateGateService {
  AppUpdateGateService._();
  static final AppUpdateGateService instance = AppUpdateGateService._();

  bool _checked = false;
  int _latestBuild = 0;
  String _notes = '';
  String _apkUrlOverride = '';

  /// The build number this binary was compiled as, parsed out of
  /// AppKnowledge.version ('1.0.9+222' -> 222).
  ///
  /// Returns 0 if it cannot be parsed, and [updateAvailable] treats 0 as
  /// "unknown" rather than "very old" — a parse failure must never nag
  /// every hero to reinstall.
  static int get currentBuild {
    final v = AppKnowledge.version;
    final plus = v.lastIndexOf('+');
    if (plus < 0 || plus == v.length - 1) return 0;
    return int.tryParse(v.substring(plus + 1).trim()) ?? 0;
  }

  int get latestBuild => _latestBuild;
  String get notes => _notes;

  /// True only when we positively know a newer build exists.
  ///
  /// Fails CLOSED in every ambiguous case (not checked yet, unparseable
  /// local version, missing/zero remote value). A false "update
  /// available" is worse than none: it sends a working hero off to
  /// reinstall an identical APK mid-shift.
  bool get updateAvailable {
    if (!_checked) return false;
    final cur = currentBuild;
    if (cur == 0 || _latestBuild == 0) return false;
    return _latestBuild > cur;
  }

  /// Where to send the hero. An override in Firestore wins so a specific
  /// build can be pinned; otherwise the flavor's GitHub "latest" link.
  String apkUrlFor(String flavor) => _apkUrlOverride.isNotEmpty
      ? _apkUrlOverride
      : UpdateService().fallbackApkUrl(flavor);

  /// ONE read, once per process. Safe to call from several screens.
  ///
  /// [flavor] is 'hero' | 'customer' | 'seller' | 'admin'.
  Future<void> checkOnce(String flavor) async {
    if (_checked) return;
    // Marked BEFORE the await so two screens racing on startup cannot
    // both fire the read.
    _checked = true;
    try {
      final snap = await FirebaseFirestore.instance
          .collection('system_settings')
          .doc('app_versions')
          .trackedGet();
      final d = snap.data();
      if (d == null) return;
      _latestBuild = (d['${flavor}_build'] as num?)?.toInt() ?? 0;
      _notes = (d['${flavor}_notes'] as String?)?.trim() ?? '';
      _apkUrlOverride = (d['${flavor}_apk_url'] as String?)?.trim() ?? '';
    } catch (e) {
      // Non-fatal and silent to the user. An update check that fails
      // must never surface as an error to a hero trying to work.
      debugPrint('[AppUpdateGate] check failed (non-fatal): $e');
    }
  }

  /// Test/debug hook — lets a screen re-ask after the admin publishes.
  void resetForRecheck() {
    _checked = false;
    _latestBuild = 0;
    _notes = '';
    _apkUrlOverride = '';
  }
}
