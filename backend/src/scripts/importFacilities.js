// Downloads pharmacies, clinics and hospitals from OpenStreetMap and saves
// them in the facilities table, so the Nearby tab can read them from our own
// database: fast, and it keeps working when the free OpenStreetMap servers
// are busy or down.
//
// A whole state or country (one command, bigger download):
//   npm run facilities:import -- --region Sarawak
//   npm run facilities:import -- --region Sabah
//   npm run facilities:import -- --region Malaysia     (large: may need a quiet hour)
//
// Or around one point:  npm run facilities:import -- <lat> <lng> [radius km]
//   npm run facilities:import -- 2.29 111.83 25          (Sibu)
//
// Safe to run again: places already imported are updated, not duplicated,
// and places added by admins are never touched.
import { pool } from '../db.js';
import { saveOsmPlaces } from '../services/facilityStore.js';
import { askOverpass, buildQuery, buildRegionQuery, OVERPASS_URLS, toPlaces } from '../services/overpass.js';

const args = process.argv.slice(2);
let query;
let description;

if (args[0] === '--region') {
  const region = args.slice(1).join(' ').trim();
  if (!region) {
    console.error('Usage: npm run facilities:import -- --region Sarawak');
    process.exit(1);
  }
  query = buildRegionQuery(region, { timeoutSeconds: 180 });
  description = `in ${region}`;
} else {
  const [lat, lng, radiusKm = 20] = args.map(Number);
  if (!Number.isFinite(lat) || !Number.isFinite(lng) || !(radiusKm > 0 && radiusKm <= 50)) {
    console.error('Usage: npm run facilities:import -- --region Sarawak');
    console.error('   or: npm run facilities:import -- <lat> <lng> [radius km, max 50]');
    process.exit(1);
  }
  query = buildQuery(lat, lng, radiusKm * 1000, { timeoutSeconds: 90, limit: 5000 });
  description = `within ${radiusKm} km of ${lat}, ${lng}`;
}

const ROUNDS = 3; // try every server, up to 3 times
const WAIT_BETWEEN_ROUNDS_MS = 20_000;

async function download() {
  for (let round = 1; round <= ROUNDS; round++) {
    try {
      console.log(`Downloading places ${description} from OpenStreetMap (round ${round} of ${ROUNDS})…`);
      return await askOverpass(query, { servers: OVERPASS_URLS, timeoutMs: 200_000 });
    } catch (err) {
      if (round === ROUNDS) throw err;
      console.log(`All servers busy. Waiting ${WAIT_BETWEEN_ROUNDS_MS / 1000} s before trying again…`);
      await new Promise((r) => setTimeout(r, WAIT_BETWEEN_ROUNDS_MS));
    }
  }
  throw new Error('unreachable');
}

try {
  const json = await download();
  const places = toPlaces(json);
  if (places.length === 0) {
    console.log(`\nOpenStreetMap answered but found no named places ${description}.`);
    if (args[0] === '--region') {
      console.log('Check the spelling of the region; it must match OpenStreetMap, e.g. "Sarawak", "Sabah", "Malaysia".');
    }
  } else {
    console.log(`Saving ${places.length} places…`);
    const { added, updated } = await saveOsmPlaces(pool, places);
    const count = (type, own) => places.filter((p) => p.type === type && (!own || p.ownership === own)).length;
    console.log(`\nDone: ${added} new, ${updated} updated (${places.length} named places ${description}).`);
    console.log(`  Pharmacies:           ${count('pharmacy')}`);
    console.log(`  Government clinics:   ${count('clinic', 'public')}`);
    console.log(`  Private clinics:      ${count('clinic', 'private')}`);
    console.log(`  Government hospitals: ${count('hospital', 'public')}`);
    console.log(`  Private hospitals:    ${count('hospital', 'private')}`);
    console.log('Check names in pgAdmin (facilities table) and fix any government/private labels by hand.');
  }
} catch (err) {
  console.error(`\nImport failed: ${err.message}`);
  console.error('The public OpenStreetMap servers are busy. Try again in a few minutes, or late at night.');
  process.exitCode = 1;
} finally {
  await pool.end();
}
