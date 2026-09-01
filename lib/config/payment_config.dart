// ================================================================
// Payment Config — Allin1 Super App
// ================================================================
// FIX (Aug 9 2026 — infrastructure audit, Step 1 of 2 — UPI payment
// routing): centralizes the company's UPI VPA (Virtual Payment
// Address) so it's defined in exactly ONE place instead of being
// hardcoded inline wherever a payment screen builds a `upi://pay`
// deeplink. Before this fix:
//   - `payment_screen.dart`'s `_launchUpi()` already built a CORRECT,
//     fully-parameterized UPI intent (pa/pn/mc/tr/tn/am/cu) — but with
//     the VPA as an inline string literal, so changing it later meant
//     hunting down every call site.
//   - `ride_tracking_screen.dart`'s `_openGenericUpi()` launched a
//     completely BARE `upi://pay` with NO parameters at all — no
//     payee, no amount — which just opens whatever UPI app is
//     installed with nothing pre-filled, forcing the customer to scan
//     the hero's own personal QR code manually. That's the real
//     "payment doesn't route to the company account" bug: money never
//     had a wrong destination baked into the code, there was simply no
//     destination in the intent at all for that screen's flow.
//
// Both screens now build their `upi://pay` URI through
// `PaymentConfig.buildUpiUri(...)` below, so there is exactly one
// place that knows the company's VPA and exactly one place that
// assembles the parameter string.
//
// NOTE (per the audit's own Medium-priority suggestion): ideally this
// value would come from a remote-config/Firestore
// `platformSettings`-style doc so it's changeable without a redeploy.
// Deliberately NOT done in this pass — Nizam asked for Step 1 to be
// the UPI-routing fix only, and swapping a hardcoded Dart constant for
// a Firestore-fetched one is a bigger, separate change (adds a network
// dependency + loading-state handling to a MONEY-COLLECTION screen,
// which needs its own careful review, not bundled silently into an
// "also refactor this" pass). This constant is at least now a single
// change point for that future step.
import 'package:flutter/foundation.dart';

class PaymentConfig {
  PaymentConfig._();

  /// Company UPI VPA — every ride/order payment collected via the
  /// generic "Open UPI App" flow goes here. This is the ONLY place
  /// this value is defined; change it here and every caller updates.
  static const String companyUpiId = '919597879191@ybl';

  /// Payee display name shown inside the customer's UPI app.
  static const String companyPayeeName = 'NJTECH';

  /// Merchant category code — '0000' (generic/unclassified), matches
  /// what payment_screen.dart's already-correct implementation used.
  static const String merchantCategoryCode = '0000';

  /// Builds a fully-parameterized `upi://pay` deeplink — payee VPA,
  /// payee name, merchant category, a transaction reference (derived
  /// from [referenceId] if given, otherwise a timestamp), a note, the
  /// amount, and currency. Mirrors the exact parameter set
  /// payment_screen.dart's `_launchUpi()` already built correctly, so
  /// both payment entry points now produce an identical URI shape.
  static Uri buildUpiUri({
    required double amount,
    String? referenceId,
    String note = 'RidePayment',
  }) {
    final safeRef = (referenceId ?? '').replaceAll(RegExp('[^A-Za-z0-9]'), '');
    final transactionRef =
        'NJTECH${safeRef.isNotEmpty ? safeRef : DateTime.now().millisecondsSinceEpoch}';
    return Uri.parse(
      'upi://pay?pa=$companyUpiId'
      '&pn=$companyPayeeName'
      '&mc=$merchantCategoryCode'
      '&tr=$transactionRef'
      '&tn=$note'
      '&am=${amount.toStringAsFixed(2)}'
      '&cu=INR',
    );
  }

  // FIX (Aug 10 2026 — root cause of "customer avanga upi app la manual-a
  // pay pannanum, romba suththal": PWA/web showed only the raw UPI
  // number to copy-paste instead of the app-chooser-with-amount-prefilled
  // experience the plan called for): a bare `upi://pay?...` URI (the
  // buildUpiUri() method above) is an Android APP-to-APP intent scheme.
  // Browsers have NO handler for arbitrary custom URI schemes like
  // `upi://` — `launchUrl()` on Flutter Web (url_launcher_web) simply
  // cannot open it, so on the deployed PWA that flow ALWAYS silently
  // failed and fell back to the manual "copy this number and paste into
  // your UPI app" UI — that fallback UI is not broken, it was working
  // exactly as designed as a LAST-RESORT path, but it was being hit on
  // every single web payment instead of only rare edge cases.
  //
  // The real fix: Android's Chrome browser (and Chromium-based browsers)
  // DOES support navigating to a special `intent://` URL, which asks
  // the Android OS itself to resolve an intent — this is a genuinely
  // different mechanism from a bare custom scheme, and it's exactly how
  // real UPI collection links (Razorpay, PhonePe merchant links, etc.)
  // work from a mobile browser. Navigating to this URL makes Android
  // show its native "Pay with" app chooser (GPay/PhonePe/Paytm/etc,
  // whichever the customer has installed) with pa/pn/am/etc already
  // filled in — the exact "customer taps Pay, sees their installed UPI
  // apps, taps one, enters PIN" flow Nizam described.
  //
  // `S.browser_fallback_url` inside the intent URL is the standard
  // Android convention: if NO app on the device can handle the `upi`
  // scheme at all (rare, but possible on a device with zero UPI apps
  // installed), Chrome falls back to opening that URL instead of
  // failing silently — pointed at NPCI's own generic UPI info page so
  // the customer at least understands what's being asked for, rather
  // than a dead end.
  //
  // iOS Safari and desktop browsers do NOT support `intent://` at all
  // (it's an Android-Chrome-specific mechanism) — for those, callers
  // should keep the existing manual copy-number UI as the fallback,
  // exactly as payment_screen.dart's dispute-recovery banner already
  // does. This method is additive, not a replacement for that safety
  // net.
  static Uri buildUpiIntentUri({
    required double amount,
    String? referenceId,
    String note = 'RidePayment',
  }) {
    final safeRef = (referenceId ?? '').replaceAll(RegExp('[^A-Za-z0-9]'), '');
    final transactionRef =
        'NJTECH${safeRef.isNotEmpty ? safeRef : DateTime.now().millisecondsSinceEpoch}';
    final encodedPn = Uri.encodeComponent(companyPayeeName);
    final encodedTn = Uri.encodeComponent(note);
    final fallback = Uri.encodeComponent('https://www.npci.org.in/what-we-do/upi/product-overview');
    return Uri.parse(
      'intent://pay?pa=$companyUpiId'
      '&pn=$encodedPn'
      '&mc=$merchantCategoryCode'
      '&tr=$transactionRef'
      '&tn=$encodedTn'
      '&am=${amount.toStringAsFixed(2)}'
      '&cu=INR'
      '#Intent;scheme=upi;action=android.intent.action.VIEW;'
      'S.browser_fallback_url=$fallback;end',
    );
  }

  @visibleForTesting
  static void debugAssertConfigured() {
    assert(companyUpiId.contains('@'), 'companyUpiId must be a valid VPA');
  }
}
