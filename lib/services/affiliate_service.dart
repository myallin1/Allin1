// ================================================================
// affiliate_service.dart — Affiliate/Referral QR tracking
// ================================================================
// NEW (Aug 12 2026 — Nizam: "oru super affiliate marketing qr generater
// system ah namma app la build pannu... qr monkey ke tough kudukuramari
// irukanum"): backs the new Admin "Affiliate QR Generator" screen.
//
// Design deliberately reuses the EXACT mechanism already proven safe by
// the poster-campaign 'source' tracking in main_customer.dart /
// auth_service.dart (see 'campaign_source' in SharedPreferences) instead
// of inventing a new pipeline:
//   1. On web boot, ?ref=CODE&rtype=hero|customer|seller in the URL is
//      cached to SharedPreferences (captureRefFromUrl()).
//   2. Once the visitor has ANY Firebase Auth session — even the
//      anonymous guest session every customer gets from frame one
//      (AuthService.ensureGuestSession()) — logScanIfPending() writes a
//      single increment to affiliate_codes/{code}.scans. Deduped per
//      device via a SharedPreferences flag so repeat opens/hot-reloads
//      never double-count the same scan.
//   3. When that visitor actually completes a real signup (customer
//      Google sign-in, hero registration, seller onboarding),
//      attributeConversionIfPending() increments
//      affiliate_codes/{code}.signups exactly once and clears the
//      pending code so it can't be double-attributed.
//
// This needed NO new open write surface: scans are written by an
// authenticated session (isAuth() already covers anonymous/guest, see
// firestore.rules), and the affiliate_codes/{code} rule only allows
// touching the 'scans'/'signups' counter fields — never the code's own
// metadata (type/label/createdBy), which only admins can set.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AffiliateService {
  AffiliateService._();
  static final AffiliateService instance = AffiliateService._();

  final FirebaseFirestore _fs = FirebaseFirestore.instance;

  static const String kPendingCodeKey = 'affiliate_pending_ref_code';
  static const String kPendingTypeKey = 'affiliate_pending_ref_type';
  static const String _kScanLoggedPrefix = 'affiliate_scan_logged_';

  CollectionReference<Map<String, dynamic>> get _codesRef =>
      _fs.collection('affiliate_codes');

  /// Call once on web boot (mirrors the existing 'campaign_source'
  /// capture in main_customer.dart). Cheap no-op on native/mobile.
  Future<void> captureRefFromUrl() async {
    if (!kIsWeb) return;
    final code = Uri.base.queryParameters['ref'];
    if (code == null || code.isEmpty) return;
    final type = Uri.base.queryParameters['rtype'];
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(kPendingCodeKey, code);
    if (type != null && type.isNotEmpty) {
      await prefs.setString(kPendingTypeKey, type);
    }
  }

  /// Call once auth (real or guest) is ready. Best-effort — never
  /// throws, never blocks boot; affiliate stats are a nice-to-have, not
  /// something a scan should ever be allowed to slow the app down for.
  Future<void> logScanIfPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(kPendingCodeKey);
      if (code == null || code.isEmpty) return;
      final loggedKey = '$_kScanLoggedPrefix$code';
      if (prefs.getBool(loggedKey) == true) return;
      await _codesRef.doc(code).set(
        {'scans': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      await prefs.setBool(loggedKey, true);
    } catch (e) {
      debugPrint('[AffiliateService] scan log skipped: $e');
    }
  }

  /// Call once, right after a NEW customer/hero/seller account is
  /// actually created — increments the referring code's signup counter
  /// exactly once, then clears the pending code so the same visitor
  /// can never be attributed twice (e.g. customer signs up, then later
  /// also registers as a hero from the same device).
  Future<void> attributeConversionIfPending() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(kPendingCodeKey);
      if (code == null || code.isEmpty) return;
      await _codesRef.doc(code).set(
        {'signups': FieldValue.increment(1)},
        SetOptions(merge: true),
      );
      await prefs.remove(kPendingCodeKey);
      await prefs.remove(kPendingTypeKey);
    } catch (e) {
      debugPrint('[AffiliateService] conversion attribution skipped: $e');
    }
  }

  /// Synchronous-feeling helper for call sites that want to stamp the
  /// referring code onto the new user/hero/seller doc itself (so admins
  /// can also see "who referred this specific person", not just totals).
  Future<String?> peekPendingCode() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(kPendingCodeKey);
  }

  // ── Per-lead capture (NEW, Aug 12 2026) ─────────────────────────
  // Nizam: "mobile number and mail id kuduthu login pandra customers
  // list namma monitor page la venum... pdf and excel export... bcoz
  // namma customer ku mobile number and mail id la offers anuppa."
  //
  // The counters above answer "HOW MANY came through this QR". They
  // cannot answer "WHO came through it", because a counter has no rows.
  // So each real signup now also writes ONE small document to
  // affiliate_leads/{uid}, which is what the Admin leads screen lists,
  // filters and exports.
  //
  // Cost/scale notes (deliberate):
  //   * Keyed by UID, not auto-ID — a person can only ever produce one
  //     lead row, so a retry/re-signup can't duplicate them.
  //   * ONE extra write per signup, on the same path that already
  //     writes the signups counter. No new write on app open/scan —
  //     scans stay counter-only, since an anonymous scanner has no
  //     contact details worth storing anyway.
  //   * Contact fields are stored exactly as the user already gave them
  //     to us at signup (Google email / entered phone). Nothing new is
  //     collected from the user that the app didn't already hold.
  CollectionReference<Map<String, dynamic>> get _leadsRef =>
      _fs.collection('affiliate_leads');

  /// Records WHO signed up through the pending affiliate code.
  /// Best-effort and never throws — a failure here must never break the
  /// signup it is attached to.
  Future<void> recordLeadIfPending({
    required String uid,
    String? name,
    String? phone,
    String? email,
    String? city,
    String? role,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString(kPendingCodeKey);
      if (code == null || code.isEmpty) return;
      final type = prefs.getString(kPendingTypeKey);
      await _leadsRef.doc(uid).set({
        'uid': uid,
        'refCode': code,
        'refType': type ?? role ?? 'customer',
        'role': role ?? 'customer',
        'name': (name ?? '').trim(),
        'phone': (phone ?? '').trim(),
        'email': (email ?? '').trim(),
        'city': (city ?? '').trim(),
        'createdAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('[AffiliateService] lead record skipped: $e');
    }
  }

  /// Convenience: record the lead AND bump the signup counter in one
  /// call, in the correct order (lead first, since
  /// attributeConversionIfPending clears the pending code).
  Future<void> completeConversion({
    required String uid,
    String? name,
    String? phone,
    String? email,
    String? city,
    String? role,
  }) async {
    await recordLeadIfPending(
      uid: uid,
      name: name,
      phone: phone,
      email: email,
      city: city,
      role: role,
    );
    await attributeConversionIfPending();
  }

  /// INCREMENTAL fetch (Nizam's explicit DB-cost requirement: "total
  /// datavum fetch pannama... new va vantha datava mattum fetch
  /// pannuna database usage innum optimised ah irukum").
  ///
  /// Pass the newest createdAt the caller already has cached locally and
  /// this returns ONLY documents newer than it — so re-opening the
  /// monitor screen costs a handful of reads instead of re-downloading
  /// the entire collection every single time. Passing null (first ever
  /// load on this device) does a normal bounded first page.
  Future<QuerySnapshot<Map<String, dynamic>>> fetchLeadsSince(
    DateTime? since, {
    int limit = 300,
  }) {
    Query<Map<String, dynamic>> q =
        _leadsRef.orderBy('createdAt', descending: true);
    if (since != null) {
      q = q.where('createdAt', isGreaterThan: Timestamp.fromDate(since));
    }
    return q.limit(limit).get();
  }

  // ── Admin-side code management ──────────────────────────────────

  String _generateCode() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789'; // no O/0/I/1 confusion
    final rnd = DateTime.now().microsecondsSinceEpoch;
    final buf = StringBuffer();
    var seed = rnd;
    for (var i = 0; i < 6; i++) {
      seed = (seed * 1103515245 + 12345) & 0x7fffffff;
      buf.write(chars[seed % chars.length]);
    }
    return buf.toString();
  }

  /// Admin-only (enforced by firestore.rules) — creates a brand-new
  /// affiliate code doc and returns the code.
  ///
  /// UPDATED (Aug 13 2026 — dynamic QR + campaign management): also
  /// writes the companion qr_links/{code} doc that the public /q/
  /// redirect page reads. Splitting them is what makes the QR DYNAMIC:
  /// the printed code never changes, but [destination] can be edited
  /// forever afterwards via [updateDestination] below.
  Future<String> createAffiliateCode({
    required String type,
    required String label,
    required String createdBy,
    String? destination,
    String? medium,
    int? printRun,
    DateTime? campaignStart,
    DateTime? campaignEnd,
  }) async {
    final code = _generateCode();
    final dest = (destination == null || destination.trim().isEmpty)
        ? '$kAppBaseUrl/'
        : destination.trim();

    await _codesRef.doc(code).set({
      'code': code,
      'type': type,
      'label': label,
      'createdBy': createdBy,
      'createdAt': FieldValue.serverTimestamp(),
      'scans': 0,
      'signups': 0,
      // Campaign metadata (QRCG parity) — purely descriptive, used for
      // grouping/filtering in the admin monitor.
      'destination': dest,
      'medium': medium ?? '',
      'printRun': printRun ?? 0,
      'campaignStart':
          campaignStart == null ? null : Timestamp.fromDate(campaignStart),
      'campaignEnd':
          campaignEnd == null ? null : Timestamp.fromDate(campaignEnd),
      'active': true,
    });

    // Public mirror — ONLY the two fields the redirect page needs.
    await _linksRef.doc(code).set({
      'destination': dest,
      'active': true,
    });

    return code;
  }

  /// The scannable short URL that gets printed. Always /q/?c=CODE so the
  /// destination stays editable — never the destination itself.
  static String shortUrlFor(String code) => '$kAppBaseUrl/q/?c=$code';

  static const String kAppBaseUrl = 'https://my-allin1.web.app';

  CollectionReference<Map<String, dynamic>> get _linksRef =>
      _fs.collection('qr_links');

  CollectionReference<Map<String, dynamic>> get _scansRef =>
      _fs.collection('affiliate_scans');

  /// Repoints an ALREADY-PRINTED QR at a new destination. This is the
  /// whole point of a dynamic QR — posters stay on the wall, the link
  /// changes. Writes both docs so admin's record and the public mirror
  /// can never drift apart.
  Future<void> updateDestination(String code, String destination) async {
    final dest = destination.trim();
    await _codesRef.doc(code).set(
      {'destination': dest},
      SetOptions(merge: true),
    );
    await _linksRef.doc(code).set(
      {'destination': dest},
      SetOptions(merge: true),
    );
  }

  /// Pause/resume a campaign. A paused code still scans, but the /q/
  /// page sends the visitor to the app root instead of the campaign
  /// destination — so a retired poster never 404s.
  Future<void> setActive(String code, bool active) async {
    await _codesRef.doc(code).set({'active': active}, SetOptions(merge: true));
    await _linksRef.doc(code).set({'active': active}, SetOptions(merge: true));
  }

  Future<void> updateCampaignMeta(
    String code, {
    String? label,
    String? medium,
    int? printRun,
    DateTime? campaignStart,
    DateTime? campaignEnd,
  }) async {
    final data = <String, dynamic>{};
    if (label != null) data['label'] = label;
    if (medium != null) data['medium'] = medium;
    if (printRun != null) data['printRun'] = printRun;
    if (campaignStart != null) {
      data['campaignStart'] = Timestamp.fromDate(campaignStart);
    }
    if (campaignEnd != null) {
      data['campaignEnd'] = Timestamp.fromDate(campaignEnd);
    }
    if (data.isEmpty) return;
    await _codesRef.doc(code).set(data, SetOptions(merge: true));
  }

  // ── Customer self-referral (Aug 13 2026) ────────────────────────
  // Nizam: "customer avaroda tray kulla share app via whatsapp button...
  // avar name potta campaign link readya irukum... ovvoru customer
  // moolamagavum namaku yevlo peru app install pandranganu detailed
  // data kidaikkum".
  //
  // Deliberately reuses the SAME affiliate_codes + qr_links + scans +
  // leads pipeline the admin poster campaigns use, with type
  // 'customer_referral'. That means every existing admin screen (QR
  // Leads & Analytics, the campaign insights page) shows customer
  // referrals with zero new plumbing — a referral is just a campaign
  // whose owner happens to be a customer instead of a poster.
  //
  // The generated code is cached on users/{uid}.referralCode so this is
  // a ONE-TIME cost per customer: every later drawer open reads that
  // single field instead of querying anything.
  static const String kCustomerReferralType = 'customer_referral';

  /// Returns this customer's personal referral code, creating it on
  /// first use. Idempotent — safe to call on every drawer open.
  Future<String?> ensureMyReferralCode({String? displayName}) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;

    final userRef = _fs.collection('users').doc(user.uid);
    try {
      final snap = await userRef.get();
      final existing = snap.data()?['referralCode'] as String?;
      if (existing != null && existing.isNotEmpty) return existing;

      // Retry a couple of times in the (very unlikely) event the random
      // code collides with one that already exists.
      for (var attempt = 0; attempt < 3; attempt++) {
        final code = _generateCode();
        final codeRef = _codesRef.doc(code);
        final taken = await codeRef.get();
        if (taken.exists) continue;

        final name = (displayName ?? user.displayName ?? '').trim();
        await codeRef.set({
          'code': code,
          'type': kCustomerReferralType,
          // The customer's NAME is the label, never part of the URL —
          // so admin sees "Ravi Kumar" in the dashboard while the
          // forwarded WhatsApp link stays an anonymous short code.
          'label': name.isEmpty ? 'Customer referral' : name,
          'ownerUid': user.uid,
          'createdBy': user.uid,
          'createdAt': FieldValue.serverTimestamp(),
          'scans': 0,
          'signups': 0,
          'destination': '$kAppBaseUrl/',
          'active': true,
        });

        // Public redirect mirror. SECURITY: the destination written here
        // is PINNED to the app root and firestore.rules enforces exactly
        // that for non-admin writers — see the qr_links rule. Without
        // that pin, any signed-in user could create
        // my-allin1.web.app/q/?c=XXX pointing at an arbitrary site,
        // turning our own domain into an open redirect for phishing.
        await _linksRef.doc(code).set({
          'destination': '$kAppBaseUrl/',
          'active': true,
        });

        await userRef.set({'referralCode': code}, SetOptions(merge: true));
        return code;
      }
      return null;
    } catch (e) {
      debugPrint('[AffiliateService] ensureMyReferralCode failed: $e');
      return null;
    }
  }

  /// How many people actually signed up through this customer's code.
  /// One cheap count query, used for the "you invited N friends" line.
  Future<int> myReferralSignups(String code) async {
    try {
      final agg = await _leadsRef.where('refCode', isEqualTo: code).count().get();
      return agg.count ?? 0;
    } catch (e) {
      debugPrint('[AffiliateService] referral count failed: $e');
      return 0;
    }
  }

  /// Raw scan rows for ONE campaign, newest first. Bounded by [limit]
  /// because this collection grows with every scan — the admin monitor
  /// derives its charts from this page rather than reading the whole
  /// collection (same read-cost discipline as the leads screen).
  Future<QuerySnapshot<Map<String, dynamic>>> fetchScans(
    String code, {
    int limit = 500,
  }) {
    return _scansRef
        .where('code', isEqualTo: code)
        .orderBy('ts', descending: true)
        .limit(limit)
        .get();
  }

  /// Live list for the admin dashboard, newest first.
  Stream<QuerySnapshot<Map<String, dynamic>>> watchAffiliateCodes() {
    return _codesRef.orderBy('createdAt', descending: true).snapshots();
  }
}
