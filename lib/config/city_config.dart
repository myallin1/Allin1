// lib/config/city_config.dart
// ================================================================
// Multi-city expansion — Plan 3 (locked): single shared Firebase
// project, single Firestore/RTDB database, city partitioned via a
// plain `city` field on every hero/store/ride/service_request doc.
// No per-city Firebase projects (rejected: breaks cross-city travel,
// 10x infra to maintain). No backend migration to Supabase/Mongo
// (rejected: full rewrite risk for zero proven cost problem yet).
//
// `city` values are lowercase slugs (e.g. 'erode', 'coimbatore') so
// they compare cleanly regardless of display casing. Every existing
// document created before this field existed has NO `city` key —
// treat that as kDefaultCity everywhere you read it, so the current
// single-city (Erode) operation keeps working exactly as before.
// ================================================================

const String kDefaultCity = 'erode';

class CityOption {
  final String slug; // stored in Firestore/RTDB, lowercase
  final String label; // shown in UI
  const CityOption(this.slug, this.label);
}

// Start with Erode (live) + placeholders for the next rollout wave.
// Add a new city here the day its franchise/local admin is ready to
// onboard heroes/sellers — no other code change needed, every
// query/filter in the app reads from this list.
const List<CityOption> kSupportedCities = [
  CityOption('erode', 'Erode'),
  CityOption('coimbatore', 'Coimbatore'),
  CityOption('salem', 'Salem'),
  CityOption('tiruppur', 'Tiruppur'),
  CityOption('namakkal', 'Namakkal'),
];

String cityLabelFor(String slug) {
  for (final c in kSupportedCities) {
    if (c.slug == slug) return c.label;
  }
  return slug.isEmpty ? cityLabelFor(kDefaultCity) : slug;
}
