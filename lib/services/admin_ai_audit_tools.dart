// ================================================================
// AdminAiAuditTools — read-only helpers for the Admin AI Co-Pilot
// ================================================================
// NEW (CTO mandate — Full UI Section Audit + Task 3: Automated KYC
// Report Generator). Every method in this file is READ-ONLY: aggregate
// .count() queries and .get() reads only — zero .set()/.update()/
// .delete() calls anywhere in this file. That is deliberate: the
// "audit" and "KYC report" capabilities are allowed to roam and read
// broadly per the CTO's mandate, but writing/approving stays
// exclusively behind admin_quick_task_service.dart's confirmation gate
// (and even there, only as an audit-log entry — see that file's header
// comment for the full read/write boundary explanation). This file
// never imports or references that gate; it only returns data.
import 'package:cloud_firestore/cloud_firestore.dart';

class AdminAiAuditTools {
  AdminAiAuditTools._();

  // ---- Goal 1: Full UI Section Audit --------------------------------
  // Mirrors the EXACT status filter each real admin approval screen
  // runs (see hero_approvals_screen.dart's `approvalStatus == pending`,
  // admin_seller_approval_screen.dart's `status == pending`,
  // admin_sos_kyc_approvals_screen.dart's `status == pending`), then
  // compares total documents in the collection against the sum of
  // every KNOWN status bucket for it. Any gap is a literal, concrete
  // finding: documents that exist in the database but that no admin
  // screen's filter would ever surface — i.e. genuinely invisible to
  // the UI, exactly what "DB leakage / unused nodes" means in
  // practice for this app.
  static const List<_SectionAudit> _sections = [
    _SectionAudit(
      label: 'Hero Approvals',
      collection: 'heroes',
      statusField: 'approvalStatus',
      knownStatuses: ['pending', 'approved', 'rejected'],
    ),
    _SectionAudit(
      label: 'Seller Approvals',
      collection: 'sellers',
      statusField: 'status',
      knownStatuses: ['pending', 'active', 'rejected'],
    ),
    _SectionAudit(
      label: 'SOS/KYC Approvals',
      collection: 'sos_kyc_requests',
      statusField: 'status',
      knownStatuses: ['pending', 'approved', 'rejected'],
    ),
  ];

  static Future<String> auditUiSections() async {
    final firestore = FirebaseFirestore.instance;
    final lines = <String>['UI Section Audit — DB vs. what each admin screen shows:'];
    for (final section in _sections) {
      try {
        final col = firestore.collection(section.collection);
        final totalAgg = await col.count().get();
        final total = totalAgg.count ?? 0;

        var accountedFor = 0;
        final bucketParts = <String>[];
        for (final status in section.knownStatuses) {
          final agg = await col.where(section.statusField, isEqualTo: status).count().get();
          final c = agg.count ?? 0;
          accountedFor += c;
          bucketParts.add('$status=$c');
        }
        final unaccounted = total - accountedFor;
        final finding = unaccounted > 0
            ? 'Finding: $unaccounted doc(s) have a missing/unknown "${section.statusField}" '
                'value — NOT visible in any admin screen filter for this section.'
            : 'OK — every document is accounted for by a known UI filter.';
        lines.add('- ${section.label} (${section.collection}): total=$total, ${bucketParts.join(', ')}. $finding');
      } catch (e) {
        lines.add('- ${section.label} (${section.collection}): audit read failed — $e');
      }
    }
    return lines.join('\n');
  }

  // ---- Goal 2 / Task 3: Automated KYC Report Generator --------------
  // Field names below are taken directly from the existing approval
  // screens' own rendering code (hero_approvals_screen.dart lines
  // ~223-238, admin_seller_approval_screen.dart lines ~181-191) so the
  // report is checking the SAME data the human admin already sees
  // there — not a guessed schema.
  static Future<KycReportResult?> generateHeroKycReport({String? targetUid}) async {
    final firestore = FirebaseFirestore.instance;
    if (targetUid != null && targetUid.trim().isNotEmpty) {
      final snap = await firestore.collection('heroes').doc(targetUid.trim()).get();
      if (!snap.exists) return null;
      return _buildHeroReport(snap.id, snap.data()!);
    }
    // No orderBy on purpose — a single equality filter needs no
    // composite Firestore index, matching this codebase's existing
    // convention (hero_approvals_screen.dart sorts client-side too via
    // its own _sortByTimestampDesc helper) rather than risking a
    // "requires an index" runtime failure for a brand-new query shape.
    final query = await firestore
        .collection('heroes')
        .where('approvalStatus', isEqualTo: 'pending')
        .limit(10)
        .get();
    if (query.docs.isEmpty) return null;
    final sorted = query.docs.toList()
      ..sort((a, b) {
        final at = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bt = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return at.compareTo(bt);
      });
    final oldest = sorted.first;
    return _buildHeroReport(oldest.id, oldest.data());
  }

  static KycReportResult _buildHeroReport(String uid, Map<String, dynamic> data) {
    final name = (data['name'] as String? ?? '').trim();
    final phone = (data['phone'] as String? ?? '').trim();
    final email = (data['email'] as String? ?? '').trim();
    final aadhaar = (data['aadhaarNumber'] as String? ?? '').trim();
    final pan = (data['panNumber'] as String? ?? '').trim();
    final license = (data['licenseNumber'] as String? ?? '').trim();
    final aadhaarDoc = (data['aadhaarDocUrl'] as String? ?? '').trim();
    final panDoc = (data['panDocUrl'] as String? ?? '').trim();
    final licenseDoc = (data['licenseDocUrl'] as String? ?? '').trim();

    final findings = <String>[];
    if (name.isEmpty) findings.add('Missing name.');
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      findings.add('Phone number looks incomplete ("$phone").');
    }
    if (email.isNotEmpty && !email.contains('@')) {
      findings.add('Email looks malformed ("$email").');
    }
    if (aadhaar.replaceAll(RegExp(r'\s'), '').length != 12) {
      findings.add('Aadhaar number is not 12 digits.');
    }
    if (pan.isNotEmpty && pan.length != 10) {
      findings.add('PAN number is not 10 characters.');
    }
    if (aadhaarDoc.isEmpty) findings.add('Aadhaar document photo is missing.');
    if (panDoc.isEmpty) findings.add('PAN document photo is missing.');
    if (license.isNotEmpty && licenseDoc.isEmpty) {
      findings.add('License number given but no license document photo uploaded.');
    }

    final recommendation = findings.isEmpty
        ? 'Recommendation: APPROVE — all required fields and documents present and plausible.'
        : 'Recommendation: NEEDS REVIEW — ${findings.length} issue(s) found, see above.';

    final report = StringBuffer()
      ..writeln('KYC Report — Hero: ${name.isEmpty ? uid : name} (uid: $uid)')
      ..writeln('Phone: ${phone.isEmpty ? 'N/A' : phone}  |  Email: ${email.isEmpty ? 'N/A' : email}')
      ..writeln('Aadhaar: ${aadhaar.isEmpty ? 'N/A' : aadhaar}  |  PAN: ${pan.isEmpty ? 'N/A' : pan}  |  License: ${license.isEmpty ? 'N/A' : license}')
      ..writeln(findings.isEmpty
          ? 'Findings: none — submission looks complete.'
          : 'Findings:\n- ${findings.join('\n- ')}')
      ..write(recommendation);

    return KycReportResult(
      targetType: 'hero',
      uid: uid,
      name: name.isEmpty ? uid : name,
      reportText: report.toString().trim(),
      visionInputs: KycVisionInputs(
        aadhaarNumber: aadhaar,
        aadhaarDocUrl: aadhaarDoc,
        panNumber: pan,
        panDocUrl: panDoc,
        licenseNumber: license,
        licenseDocUrl: licenseDoc,
        selfieUrl: (data['selfieUrl'] as String?)?.trim(),
      ),
    );
  }

  static Future<KycReportResult?> generateSellerKycReport({String? targetUid}) async {
    final firestore = FirebaseFirestore.instance;
    if (targetUid != null && targetUid.trim().isNotEmpty) {
      final snap = await firestore.collection('sellers').doc(targetUid.trim()).get();
      if (!snap.exists) return null;
      return _buildSellerReport(snap.id, snap.data()!);
    }
    final query = await firestore
        .collection('sellers')
        .where('status', isEqualTo: 'pending')
        .limit(10)
        .get();
    if (query.docs.isEmpty) return null;
    final sorted = query.docs.toList()
      ..sort((a, b) {
        final at = (a.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bt = (b.data()['createdAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return at.compareTo(bt);
      });
    final oldest = sorted.first;
    return _buildSellerReport(oldest.id, oldest.data());
  }

  static KycReportResult _buildSellerReport(String uid, Map<String, dynamic> data) {
    final name = (data['name'] as String? ?? '').trim();
    final phone = (data['phone'] as String? ?? '').trim();
    final address = (data['address'] as String? ?? '').trim();
    final category = (data['category'] as String? ?? '').trim();
    final lat = (data['latitude'] as num?)?.toDouble() ?? 0.0;
    final lng = (data['longitude'] as num?)?.toDouble() ?? 0.0;

    final findings = <String>[];
    if (name.isEmpty) findings.add('Missing business name.');
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      findings.add('Phone number looks incomplete ("$phone").');
    }
    if (address.isEmpty) findings.add('Missing address.');
    if (category.isEmpty) findings.add('Missing category.');
    if (lat == 0.0 && lng == 0.0) {
      findings.add('Location coordinates are (0,0) — no real location captured.');
    }

    final recommendation = findings.isEmpty
        ? 'Recommendation: APPROVE — all required fields present and plausible.'
        : 'Recommendation: NEEDS REVIEW — ${findings.length} issue(s) found, see above.';

    final report = StringBuffer()
      ..writeln('KYC Report — Seller: ${name.isEmpty ? uid : name} (uid: $uid)')
      ..writeln('Phone: ${phone.isEmpty ? 'N/A' : phone}  |  Category: ${category.isEmpty ? 'N/A' : category}')
      ..writeln('Address: ${address.isEmpty ? 'N/A' : address}')
      ..writeln(findings.isEmpty
          ? 'Findings: none — submission looks complete.'
          : 'Findings:\n- ${findings.join('\n- ')}')
      ..write(recommendation);

    return KycReportResult(
      targetType: 'seller',
      uid: uid,
      name: name.isEmpty ? uid : name,
      reportText: report.toString().trim(),
    );
  }

  // ---- SOS/KYC report (CTO's "Final Write Execution" mandate names
  // Hero/Seller/SOS explicitly) — mirrors generateHeroKycReport's shape
  // exactly, field names taken from admin_sos_kyc_approvals_screen.dart
  // lines ~173-182.
  static Future<KycReportResult?> generateSosKycReport({String? targetUid}) async {
    final firestore = FirebaseFirestore.instance;
    if (targetUid != null && targetUid.trim().isNotEmpty) {
      final snap = await firestore.collection('sos_kyc_requests').doc(targetUid.trim()).get();
      if (!snap.exists) return null;
      return _buildSosReport(snap.id, snap.data()!);
    }
    final query = await firestore
        .collection('sos_kyc_requests')
        .where('status', isEqualTo: 'pending')
        .limit(10)
        .get();
    if (query.docs.isEmpty) return null;
    final sorted = query.docs.toList()
      ..sort((a, b) {
        final at = (a.data()['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        final bt = (b.data()['submittedAt'] as Timestamp?)?.millisecondsSinceEpoch ?? 0;
        return at.compareTo(bt);
      });
    final oldest = sorted.first;
    return _buildSosReport(oldest.id, oldest.data());
  }

  static KycReportResult _buildSosReport(String uid, Map<String, dynamic> data) {
    final name = (data['name'] as String? ?? '').trim();
    final phone = (data['userPhone'] as String? ?? '').trim();
    final email = (data['userEmail'] as String? ?? '').trim();
    final address = (data['address'] as String? ?? '').trim();
    final aadhaar = (data['aadhaarNumber'] as String? ?? '').trim();
    final pan = (data['panNumber'] as String? ?? '').trim();
    final license = (data['licenseNumber'] as String? ?? '').trim();
    final aadhaarDoc = (data['aadhaarDocUrl'] as String? ?? '').trim();
    final panDoc = (data['panDocUrl'] as String? ?? '').trim();
    final licenseDoc = (data['licenseDocUrl'] as String? ?? '').trim();

    final findings = <String>[];
    if (name.isEmpty) findings.add('Missing name.');
    if (phone.replaceAll(RegExp(r'\D'), '').length < 10) {
      findings.add('Phone number looks incomplete ("$phone").');
    }
    if (email.isNotEmpty && !email.contains('@')) {
      findings.add('Email looks malformed ("$email").');
    }
    if (address.isEmpty) findings.add('Missing address.');
    if (aadhaar.replaceAll(RegExp(r'\s'), '').length != 12) {
      findings.add('Aadhaar number is not 12 digits.');
    }
    if (pan.isNotEmpty && pan.length != 10) {
      findings.add('PAN number is not 10 characters.');
    }
    if (aadhaarDoc.isEmpty) findings.add('Aadhaar document photo is missing.');
    if (panDoc.isEmpty) findings.add('PAN document photo is missing.');
    if (license.isNotEmpty && licenseDoc.isEmpty) {
      findings.add('License number given but no license document photo uploaded.');
    }

    final recommendation = findings.isEmpty
        ? 'Recommendation: APPROVE — all required fields and documents present and plausible.'
        : 'Recommendation: NEEDS REVIEW — ${findings.length} issue(s) found, see above.';

    final report = StringBuffer()
      ..writeln('KYC Report — SOS Activation: ${name.isEmpty ? uid : name} (uid: $uid)')
      ..writeln('Phone: ${phone.isEmpty ? 'N/A' : phone}  |  Email: ${email.isEmpty ? 'N/A' : email}')
      ..writeln('Address: ${address.isEmpty ? 'N/A' : address}')
      ..writeln('Aadhaar: ${aadhaar.isEmpty ? 'N/A' : aadhaar}  |  PAN: ${pan.isEmpty ? 'N/A' : pan}  |  License: ${license.isEmpty ? 'N/A' : license}')
      ..writeln(findings.isEmpty
          ? 'Findings: none — submission looks complete.'
          : 'Findings:\n- ${findings.join('\n- ')}')
      ..write(recommendation);

    return KycReportResult(
      targetType: 'sos',
      uid: uid,
      name: name.isEmpty ? uid : name,
      reportText: report.toString().trim(),
      visionInputs: KycVisionInputs(
        aadhaarNumber: aadhaar,
        aadhaarDocUrl: aadhaarDoc,
        panNumber: pan,
        panDocUrl: panDoc,
        licenseNumber: license,
        licenseDocUrl: licenseDoc,
        selfieUrl: (data['selfieUrl'] as String?)?.trim(),
      ),
    );
  }
}

class _SectionAudit {
  const _SectionAudit({
    required this.label,
    required this.collection,
    required this.statusField,
    required this.knownStatuses,
  });
  final String label;
  final String collection;
  final String statusField;
  final List<String> knownStatuses;
}

class KycReportResult {
  const KycReportResult({
    required this.targetType,
    required this.uid,
    required this.name,
    required this.reportText,
    this.visionInputs,
  });
  final String targetType; // 'hero' | 'seller' | 'sos'
  final String uid;
  final String name;
  final String reportText;
  // NEW (CTO mandate — Advanced KYC & Facial Verification): the raw doc
  // URLs/typed numbers + selfie URL (if any) needed for
  // AdminKycVisionService's OCR/face-match cross-check. Only populated
  // for 'hero' and 'sos' (the two types with Aadhaar/PAN/License doc
  // photos) — sellers have no such documents in this schema, so this
  // stays null for them and the vision step is simply skipped.
  final KycVisionInputs? visionInputs;
}

class KycVisionInputs {
  const KycVisionInputs({
    this.aadhaarNumber,
    this.aadhaarDocUrl,
    this.panNumber,
    this.panDocUrl,
    this.licenseNumber,
    this.licenseDocUrl,
    this.selfieUrl,
  });
  final String? aadhaarNumber;
  final String? aadhaarDocUrl;
  final String? panNumber;
  final String? panDocUrl;
  final String? licenseNumber;
  final String? licenseDocUrl;
  // NOTE: no hero/sos registration flow captures a selfie yet as of
  // this file's creation — `data['selfieUrl']` simply reads null until
  // that capture step is built, at which point this starts populating
  // automatically with zero further changes needed here.
  final String? selfieUrl;
}
