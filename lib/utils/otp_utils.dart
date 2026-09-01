// lib/utils/otp_utils.dart
// Shared local-deterministic OTP generator for bike-taxi rides.
//
// Extracted from three previously-duplicated copies (ride_search_screen.dart,
// hero_ride_screen.dart, ride_tracking_screen.dart) after a real-world bug
// where one copy silently drifted to use String.hashCode instead of this
// rolling checksum, causing customer- and hero-side OTPs to mismatch for
// the same ride doc ID. String.hashCode is NOT guaranteed identical
// between native VM/AOT and web (dart2js/dart2wasm) builds — this
// implementation avoids that by computing a platform-stable rolling
// checksum over UTF-16 code units, masked to a non-negative 31-bit int
// on every iteration.
//
// Deterministic: given the same Firestore ride doc ID, always produces
// the same 4-digit OTP, on any platform, with no database round-trip.
String generateLocalOtp(String docId) {
  final cleanId = docId.trim().replaceAll(RegExp(r'\s+'), '');
  if (cleanId.isEmpty) return '1234';
  int checksum = 0;
  for (int i = 0; i < cleanId.length; i++) {
    checksum = (checksum * 31 + cleanId.codeUnitAt(i)) & 0x7FFFFFFF;
  }
  return (1000 + (checksum % 9000)).toString();
}
