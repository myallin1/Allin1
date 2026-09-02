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
import 'package:flutter/services.dart' as flutter_services;
import 'package:shared_preferences/shared_preferences.dart';
import './firestore_usage_tracking.dart';

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

  /// Call once on mobile app boot (Aug 16 2026 - Clipboard tracking).
  /// Checks the system clipboard for a referral code left behind by the 
  /// landing page's APK download button.
  Future<void> captureRefFromClipboard() async {
    if (kIsWeb) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.containsKey(kPendingCodeKey)) return; // Already have one
      
      final clipboardData = await flutter_services.Clipboard.getData('text/plain');
      final text = clipboardData?.text ?? '';
      
      if (text.startsWith('allin1_ref:')) {
        final parts = text.split(':');
        if (parts.length >= 3) {
          final code = parts[1];
          final type = parts[2];
          if (code.isNotEmpty) {
            await prefs.setString(kPendingCodeKey, code);
            if (type.isNotEmpty) {
              await prefs.setString(kPendingTypeKey, type);
            }
            // Clear clipboard so we don't attribute again if they reinstall later
            await flutter_services.Clipboard.setData(const flutter_services.ClipboardData(text: ''));
          }
        }
      }
    } catch (e) {
      debugPrint('[AffiliateService] clipboard capture failed: $e');
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

  // ================================================================
  // CUSTOM (readable) CAMPAIGN SLUGS
  // ================================================================
  // NEW (Aug 17 2026 — Nizam: "antha link customer panic aackuramari
  // text back la varuthu so ovvoru affilate qr generate link ku kum
  // decentana extension words naane customize pandramari link venum").
  //
  // _generateCode() produces things like K7M2XQ, so a printed poster
  // read ".../q/?c=K7M2XQ". To a customer about to scan an unfamiliar
  // code, a random uppercase token is indistinguishable from a phishing
  // link — which is exactly the reaction reported. A human-readable slug
  // (".../q/?c=erode-hotels") reads like something a local business
  // would actually print.
  //
  // The random generator is KEPT as the fallback: an admin who doesn't
  // want to think of a name still gets a working code, and every code
  // already printed keeps resolving unchanged.

  /// Words that must never become a campaign slug — they either collide
  /// with real paths on this origin or actively invite the suspicion
  /// this feature exists to remove.
  static const Set<String> _reservedSlugs = {
    'q', 'admin', 'api', 'login', 'signin', 'signup', 'auth', 'assets',
    'index', 'app', 'web', 'null', 'undefined', 'test',
    // Deliberately blocked: a slug that claims to be a security or
    // payment action is the classic phishing shape, and printing one on
    // our own posters would train customers to trust exactly the sort of
    // link they should distrust.
    'verify', 'secure', 'account', 'password', 'otp', 'kyc', 'payment',
    'refund', 'bank', 'upi',
  };

  /// Normalises admin free-text into a safe URL slug, or returns null if
  /// it cannot become one.
  ///
  /// Lowercase because URLs are copied by hand off posters and mixed
  /// case is a transcription error waiting to happen; hyphens rather
  /// than spaces or underscores because a hyphen survives being read
  /// aloud and typed.
  static String? normalizeCustomCode(String input) {
    final slug = input
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[\s_]+'), '-')
        .replaceAll(RegExp(r'[^a-z0-9-]'), '')
        .replaceAll(RegExp(r'-{2,}'), '-')
        .replaceAll(RegExp(r'^-+|-+$'), '');

    if (slug.length < 3 || slug.length > 32) return null;
    if (_reservedSlugs.contains(slug)) return null;
    // Must contain at least one letter — an all-digit slug reads as an
    // account number, which is the opposite of reassuring.
    if (!RegExp(r'[a-z]').hasMatch(slug)) return null;
    return slug;
  }

  /// True if [code] is still free. Checks BOTH collections a code lives
  /// in — affiliate_codes (admin metadata + counters) and qr_links (the
  /// public redirect mirror) — because a code present in only one of
  /// them is still taken, and reusing it would silently repoint or
  /// double-count an existing campaign.
  Future<bool> isCodeAvailable(String code) async {
    try {
      final results = await Future.wait([
        _codesRef.doc(code).trackedGet(),
        _linksRef.doc(code).trackedGet(),
      ]);
      return !results[0].exists && !results[1].exists;
    } catch (e) {
      debugPrint('[AffiliateService] availability check failed: $e');
      // Fail CLOSED — reporting "available" on a network error could
      // hand an admin a code that silently overwrites a live campaign.
      return false;
    }
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

    /// Admin-chosen readable slug, e.g. 'erode-hotels'. Already
    /// normalised and availability-checked by the caller (the admin
    /// screen does both so it can show inline feedback as you type).
    /// Null/empty falls back to the random generator, so nothing about
    /// the existing flow changes for an admin who doesn't use this.
    String? customCode,
  }) async {
    final code = (customCode != null && customCode.trim().isNotEmpty)
        ? customCode.trim()
        : _generateCode();
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
    await _codesRef.doc(code).trackedSet({'active': active}, SetOptions(merge: true));
    await _linksRef.doc(code).trackedSet({'active': active}, SetOptions(merge: true));
  }

  // ================================================================
  // DELETE A CAMPAIGN (Aug 17 2026)
  // ================================================================
  // Nizam: "admin create pannuna oru wrong affilate qr ah namma admin
  // nala delete pannamudila".
  //
  // firestore.rules has allowed `allow delete: if isAdminAny()` on both
  // affiliate_codes and qr_links since they were created — the gap was
  // purely that no UI or service method ever called it. An admin who
  // mistyped a campaign was stuck with it in the list forever.
  //
  // WHY DELETE IS THE RARE CASE, NOT THE DEFAULT:
  // A printed QR outlives the database row. Deleting the code of a
  // poster that is already on a wall does NOT un-print the poster — the
  // /q/ page simply finds nothing and falls back to the app root (see
  // web/q/index.html), so the scanner still lands somewhere sane, but
  // that scan is attributed to nobody. For a campaign that was really
  // used, setActive(false) is almost always the right call: it keeps
  // every scan/signup number intact for reporting while retiring the
  // link. Delete is for codes created BY MISTAKE that were never
  // printed. The UI says so, and makes the destructive path the harder
  // of the two.
  //
  // Deletes BOTH docs. Leaving qr_links behind would keep a live public
  // redirect for a campaign that no longer exists in the admin list —
  // an invisible working link nobody can see or manage.
  Future<void> deleteAffiliateCode(
    String code, {
    /// Also delete this code's rows in affiliate_scans. Off by default:
    /// scan rows are the raw analytics record, and an admin deleting a
    /// mistaken code usually wants the code gone, not the history of
    /// every other report rewritten. Bounded to [scanDeleteLimit] so a
    /// hugely-scanned code can never build an unbounded batch.
    bool alsoDeleteScans = false,
    int scanDeleteLimit = 400,
  }) async {
    // Order matters: kill the PUBLIC redirect first. If the second
    // delete fails halfway, the worst outcome is an orphaned admin row
    // (visible, manageable, deletable again) rather than an orphaned
    // live redirect (invisible and unmanageable).
    await _linksRef.doc(code).trackedDelete();
    await _codesRef.doc(code).trackedDelete();

    if (!alsoDeleteScans) return;
    try {
      final snap = await _fs
          .collection('affiliate_scans')
          .where('code', isEqualTo: code)
          .limit(scanDeleteLimit)
          .trackedGet();
      if (snap.docs.isEmpty) return;
      final batch = _fs.batch();
      for (final d in snap.docs) {
        batch.delete(d.reference);
      }
      await batch.commit();
    } catch (e) {
      // Non-fatal: the campaign itself is already gone, which is what
      // the admin asked for. Orphaned scan rows are invisible in the UI
      // and harmless.
      debugPrint('[AffiliateService] scan cleanup failed (non-fatal): $e');
    }
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
    await _codesRef.doc(code).trackedSet(data, SetOptions(merge: true));
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

  /// Hero-refers-hero (Aug 17 2026). Separate type so admin reporting can
  /// tell fleet growth apart from customer growth — they are different
  /// businesses and a single "referrals" number would hide which one is
  /// actually working.
  static const String kHeroReferralType = 'hero_referral';

  /// Where a hero referral must send the scanner. A would-be hero landing
  /// in the CUSTOMER app is a dead end — there is no hero registration
  /// there — so this is pinned separately from kAppBaseUrl and matched
  /// by firestore.rules.
  static const String kHeroAppBaseUrl = 'https://hero-allin1.web.app';

  /// Returns this customer's personal referral code, creating it on
  /// first use. Idempotent — safe to call on every drawer open.
  /// EXTENDED (Aug 17 2026 — Nizam: "heros avanga innoru heros ah refer
  /// panna antha particular hero app la irunthu hero referral qr and
  /// link generation").
  ///
  /// Was customer-only and hardcoded three things: the 'customer_referral'
  /// type, the customer app as the destination, and users/{uid} as the
  /// place to cache the code. A hero referring another hero needs all
  /// three to differ — most importantly the DESTINATION, because sending
  /// a would-be hero to the customer app is a dead end: they land in the
  /// wrong app with no way to register as a hero.
  ///
  /// [referralType] and [destination] are pinned by firestore.rules to
  /// an allowed pair, so a client cannot mint a code pointing anywhere
  /// it likes — see the affiliate_codes create rule.
  Future<String?> ensureMyReferralCode({
    String? displayName,
    String referralType = kCustomerReferralType,

    /// Where a scanner of THIS code should land. Defaults to the
    /// customer app, preserving the original behaviour exactly.
    String? destination,

    /// Which profile document caches the generated code. Heroes are in
    /// heroes/{uid}; customers in users/{uid}. Caching it on the profile
    /// is what makes this idempotent — without it every screen open
    /// would mint a new code.
    String profileCollection = 'users',
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.isAnonymous) return null;

    final dest = (destination == null || destination.trim().isEmpty)
        ? '$kAppBaseUrl/'
        : destination.trim();

    final userRef = _fs.collection(profileCollection).doc(user.uid);
    try {
      final snap = await userRef.get();
      final existing = snap.data()?['referralCode'] as String?;
      if (existing != null && existing.isNotEmpty) return existing;

      // We do NOT read the affiliate_codes collection first, because
      // firestore.rules strictly forbids customers from reading it.
      // Instead, we directly attempt to create the document. If it
      // collides with an existing code, the tight security rules will
      // reject it as an unauthorized "update", which we catch and retry.
      for (var attempt = 0; attempt < 3; attempt++) {
        final code = _generateCode();
        final codeRef = _codesRef.doc(code);

        final name = (displayName ?? user.displayName ?? '').trim();
        
        try {
          await codeRef.set({
            'code': code,
            'type': referralType,
            'label': name.isEmpty
                ? (referralType == kHeroReferralType
                    ? 'Hero referral'
                    : 'Customer referral')
                : name,
            'ownerUid': user.uid,
            'createdBy': user.uid,
            'createdAt': FieldValue.serverTimestamp(),
            'scans': 0,
            'signups': 0,
            'destination': dest,
            'active': true,
          });

          await _linksRef.doc(code).set({
            'destination': dest,
            'active': true,
          });

          await userRef.set({'referralCode': code}, SetOptions(merge: true));
          return code;
        } catch (e) {
          // If we hit permission-denied here, it means the code likely
          // already exists (update denied), so we just try again.
          debugPrint('[AffiliateService] code generation collision/error: $e');
          continue;
        }
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
    return _codesRef.orderBy('createdAt', descending: true).trackedSnapshots();
  }
}
