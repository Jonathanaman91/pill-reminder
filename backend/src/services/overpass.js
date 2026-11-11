/**
 * Looks up pharmacies, clinics and hospitals from OpenStreetMap through the
 * Overpass API, and classifies each place as government (public) or private.
 *
 * Results are cached in memory for a few hours per ~1 km grid square, so the
 * public Overpass server is not asked again for every user and every refresh
 * (its usage policy asks for this).
 */

// Public Overpass servers are free but often overloaded (HTTP 502/504) or
// slow, so we try several. Live lookups (while a user waits) use short
// timeouts; the one-off import script uses long ones.
const DEFAULT_SERVERS = [
  'https://overpass-api.de/api/interpreter',
  'https://overpass.private.coffee/api/interpreter',
  'https://maps.mail.ru/osm/tools/overpass/api/interpreter',
  'https://overpass.kumi.systems/api/interpreter',
];
export const OVERPASS_URLS = (process.env.OVERPASS_URL ?? DEFAULT_SERVERS.join(','))
  .split(',').map((u) => u.trim()).filter(Boolean);

/** Live lookup: 3 servers × 8 s = 24 s at most, under the app's 30 s wait. */
const LIVE_SERVERS = 3;
const LIVE_TIMEOUT_MS = 8_000;
const CACHE_TTL_MS = 6 * 60 * 60 * 1000; // 6 hours
const CACHE_MAX = 300;
const cache = new Map(); // key → { at, places }

export function buildQuery(lat, lng, radius, { timeoutSeconds = 8, limit = 200 } = {}) {
  const around = `around:${Math.round(radius)},${lat},${lng}`;
  return `[out:json][timeout:${timeoutSeconds}];
(
  nwr["amenity"~"^(pharmacy|clinic|doctors|hospital)$"](${around});
  nwr["healthcare"~"^(pharmacy|clinic|doctor|hospital)$"](${around});
);
out center tags ${limit};`;
}

/**
 * Every pharmacy/clinic/hospital inside a named region, e.g. "Sarawak" (a
 * state, admin_level 4) or "Malaysia" (a country, admin_level 2).
 */
export function buildRegionQuery(region, { timeoutSeconds = 180 } = {}) {
  const name = region.replace(/["\\]/g, '').trim();
  return `[out:json][timeout:${timeoutSeconds}];
area["name"="${name}"]["boundary"="administrative"]["admin_level"~"^(2|3|4)$"]->.region;
(
  nwr["amenity"~"^(pharmacy|clinic|doctors|hospital)$"](area.region);
  nwr["healthcare"~"^(pharmacy|clinic|doctor|hospital)$"](area.region);
);
out center tags;`;
}

// Names of Malaysian Ministry of Health facilities.
const PUBLIC_NAME = /^(klinik kesihatan|klinik desa|klinik komuniti|klinik 1\s?malaysia|pusat kesihatan|kk\s)/i;
const PUBLIC_HOSPITAL_NAME = /^hospital\s+(?!pakar|swasta|specialist)/i;
const PRIVATE_HINT = /(pakar|specialist|medical cent(re|er)|swasta|kpj|columbia asia|sunway|gleneagles|pantai)/i;
const PUBLIC_OPERATOR = /(kementerian kesihatan|ministry of health|jabatan kesihatan|\bkkm\b|\bmoh\b)/i;

function typeOf(tags) {
  const kind = tags.amenity ?? tags.healthcare;
  if (kind === 'pharmacy') return 'pharmacy';
  if (kind === 'hospital') return 'hospital';
  if (kind === 'clinic' || kind === 'doctors' || kind === 'doctor') return 'clinic';
  return null;
}

export function ownershipOf(tags, name) {
  const operatorType = (tags['operator:type'] ?? '').toLowerCase();
  if (operatorType === 'government' || operatorType === 'public') return 'public';
  if (operatorType === 'private') return 'private';
  if (PUBLIC_OPERATOR.test(tags.operator ?? '')) return 'public';
  if (PRIVATE_HINT.test(name)) return 'private';
  if (PUBLIC_NAME.test(name) || PUBLIC_HOSPITAL_NAME.test(name)) return 'public';
  return 'private';
}

/** Turns one Overpass element into our facility shape, or null to skip it. */
export function classify(element) {
  const tags = element.tags ?? {};
  const type = typeOf(tags);
  const name = (tags.name ?? tags['name:en'] ?? tags['name:ms'] ?? '').trim();
  const latitude = element.lat ?? element.center?.lat;
  const longitude = element.lon ?? element.center?.lon;
  // Unnamed places aren't useful to someone looking for their medicine.
  if (!type || !name || latitude == null || longitude == null) return null;

  const address = [
    [tags['addr:housenumber'], tags['addr:street']].filter(Boolean).join(' '),
    tags['addr:city'] ?? tags['addr:town'],
    tags['addr:postcode'],
  ].filter(Boolean).join(', ');

  return {
    id: `osm:${element.type}/${element.id}`,
    name,
    type,
    ownership: ownershipOf(tags, name),
    is24Hours: (tags.opening_hours ?? '').trim() === '24/7',
    latitude,
    longitude,
    address: address || null,
    phone: tags.phone ?? tags['contact:phone'] ?? null,
    openingHours: tags.opening_hours ?? null,
    source: 'osm',
  };
}

export async function fetchNearby(lat, lng, radius) {
  const key = `${lat.toFixed(2)},${lng.toFixed(2)},${radius}`;
  const hit = cache.get(key);
  if (hit && Date.now() - hit.at < CACHE_TTL_MS) return hit.places;

  const json = await askOverpass(buildQuery(lat, lng, radius), {
    servers: OVERPASS_URLS.slice(0, LIVE_SERVERS),
    timeoutMs: LIVE_TIMEOUT_MS,
  });
  const places = toPlaces(json);

  if (cache.size >= CACHE_MAX) cache.delete(cache.keys().next().value); // drop the oldest
  cache.set(key, { at: Date.now(), places });
  return places;
}

/** Classifies every element and drops duplicates (a place mapped as both a point and a building). */
export function toPlaces(json) {
  const seen = new Set();
  const places = [];
  for (const el of json.elements ?? []) {
    const place = classify(el);
    if (!place) continue;
    const dedupeKey = `${place.name.toLowerCase()}|${place.latitude.toFixed(4)}|${place.longitude.toFixed(4)}`;
    if (seen.has(dedupeKey)) continue;
    seen.add(dedupeKey);
    places.push(place);
  }
  return places;
}

export async function askOverpass(query, { servers = OVERPASS_URLS, timeoutMs = LIVE_TIMEOUT_MS } = {}) {
  let lastError;
  for (const url of servers) {
    const started = Date.now();
    try {
      const res = await fetch(url, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/x-www-form-urlencoded',
          'User-Agent': 'PillReminder/0.1 (UTS CSS3344 student project)',
        },
        body: `data=${encodeURIComponent(query)}`,
        signal: AbortSignal.timeout(timeoutMs),
      });
      if (!res.ok) throw new Error(`answered ${res.status}`);
      const json = await res.json();
      console.log(`OpenStreetMap: ${json.elements?.length ?? 0} results in ${Date.now() - started} ms (${new URL(url).host})`);
      return json;
    } catch (err) {
      lastError = new Error(`${new URL(url).host} ${err.name === 'TimeoutError' ? 'timed out' : err.message}`);
      console.warn(`OpenStreetMap: ${lastError.message}, trying next server…`);
    }
  }
  throw lastError ?? new Error('no Overpass server configured');
}

/** Straight-line distance in metres (haversine). */
export function distanceMeters(lat1, lng1, lat2, lng2) {
  const R = 6_371_000;
  const toRad = (d) => (d * Math.PI) / 180;
  const dLat = toRad(lat2 - lat1);
  const dLng = toRad(lng2 - lng1);
  const a = Math.sin(dLat / 2) ** 2 +
    Math.cos(toRad(lat1)) * Math.cos(toRad(lat2)) * Math.sin(dLng / 2) ** 2;
  return 2 * R * Math.asin(Math.sqrt(a));
}

export function clearOverpassCache() {
  cache.clear();
}
