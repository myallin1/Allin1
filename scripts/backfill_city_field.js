// ================================================================
// One-Time Migration: Backfill `city` field on legacy documents
// ================================================================
//
// WHY THIS EXISTS
// Multi-city rollout (Plan 3) added a `city` string field to
// sellers/heroes/service_requests going forward. Documents created
// BEFORE that change have no `city` field at all. This script finds
// every such doc and sets city: 'erode' (our only city so far, so
// this is a safe default for all pre-existing data).
//
// NOTE: this is NOT a required fix for the "seller invisible /
// customer can't order" bug — that was root-caused separately to a
// missing Firestore composite index in loadCategoryData() (fixed in
// category_gateway_service.dart) and is unrelated to this field. No
// live query in the food-ordering path currently filters by city, so
// skipping this script does not currently break anything. Run it
// anyway as good data hygiene before city-based filtering queries
// (e.g. hero dispatch, service request broadcast) go further.
//
// HOW TO RUN (from your own machine, not this sandbox):
//   1. cd functions   (or anywhere you keep a service account key)
//   2. Download a Firebase service account key JSON:
//      Firebase Console → Project Settings → Service Accounts →
//      Generate new private key
//   3. Save it as serviceAccountKey.json next to this script
//      (DO NOT commit this file — it's already covered by .gitignore
//      patterns for *.json service account keys; double check before
//      pushing)
//   4. node scripts/backfill_city_field.js
//
// The script is idempotent — safe to run more than once. It only
// touches docs missing the `city` field; docs that already have one
// (even a different city) are left untouched.
//
// Add --dry-run to only print what WOULD change without writing:
//   node scripts/backfill_city_field.js --dry-run

const admin = require('firebase-admin');
const path = require('path');

const DRY_RUN = process.argv.includes('--dry-run');
const DEFAULT_CITY = 'erode';
const COLLECTIONS = ['sellers', 'heroes', 'service_requests'];
const BATCH_SIZE = 400; // Firestore batch write limit is 500; stay safely under it

let serviceAccount;
try {
  serviceAccount = require(path.join(__dirname, 'serviceAccountKey.json'));
} catch (e) {
  console.error(
    '\n❌ Could not find scripts/serviceAccountKey.json.\n' +
    'Download it from Firebase Console → Project Settings → Service Accounts\n' +
    '→ Generate new private key, save it as scripts/serviceAccountKey.json, then re-run.\n',
  );
  process.exit(1);
}

admin.initializeApp({
  credential: admin.credential.cert(serviceAccount),
});

const db = admin.firestore();

async function backfillCollection(collectionName) {
  console.log(`\n── ${collectionName} ──`);

  const snapshot = await db.collection(collectionName).get();
  const missing = snapshot.docs.filter((doc) => !doc.data().city);

  console.log(`Total docs: ${snapshot.size}. Missing 'city': ${missing.length}.`);

  if (missing.length === 0) {
    console.log('Nothing to do.');
    return { total: snapshot.size, updated: 0 };
  }

  if (DRY_RUN) {
    console.log(`[DRY RUN] Would set city: '${DEFAULT_CITY}' on ${missing.length} docs:`);
    missing.slice(0, 20).forEach((doc) => console.log(`  - ${collectionName}/${doc.id}`));
    if (missing.length > 20) console.log(`  ... and ${missing.length - 20} more`);
    return { total: snapshot.size, updated: 0 };
  }

  let updatedCount = 0;
  for (let i = 0; i < missing.length; i += BATCH_SIZE) {
    const chunk = missing.slice(i, i + BATCH_SIZE);
    const batch = db.batch();
    chunk.forEach((doc) => {
      batch.update(doc.ref, { city: DEFAULT_CITY });
    });
    await batch.commit();
    updatedCount += chunk.length;
    console.log(`  Committed batch: ${updatedCount}/${missing.length}`);
  }

  return { total: snapshot.size, updated: updatedCount };
}

async function main() {
  console.log('================================================');
  console.log(`City Backfill Migration${DRY_RUN ? ' (DRY RUN — no writes)' : ''}`);
  console.log(`Default city: '${DEFAULT_CITY}'`);
  console.log('================================================');

  const results = {};
  for (const collectionName of COLLECTIONS) {
    results[collectionName] = await backfillCollection(collectionName);
  }

  console.log('\n================================================');
  console.log('Summary');
  console.log('================================================');
  for (const [name, r] of Object.entries(results)) {
    console.log(`${name}: ${r.updated}/${r.total} docs updated`);
  }
  if (DRY_RUN) {
    console.log('\nThis was a dry run. Re-run without --dry-run to actually write changes.');
  }

  process.exit(0);
}

main().catch((err) => {
  console.error('Migration failed:', err);
  process.exit(1);
});
