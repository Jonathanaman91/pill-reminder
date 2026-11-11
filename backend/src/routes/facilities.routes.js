import { Router } from 'express';
import { z } from 'zod';
import { query } from '../db.js';
import { HttpError } from '../errors.js';
import { requireAuth } from '../middleware/auth.js';
import { saveOsmPlaces } from '../services/facilityStore.js';
import { distanceMeters, fetchNearby } from '../services/overpass.js';

export const facilitiesRouter = Router();

const nearbyQuery = z.object({
  lat: z.coerce.number().min(-90).max(90),
  lng: z.coerce.number().min(-180).max(180),
  radius: z.coerce.number().int().min(500).max(30_000).default(10_000),
});

/** An OSM place within this distance of an admin-added place of the same type is a duplicate. */
const DUPLICATE_METERS = 60;
const MAX_RESULTS = 80;
/** With at least this many saved places in range, don't wait on the live OpenStreetMap servers. */
const ENOUGH_SAVED = 5;

/**
 * GET /api/v1/facilities/nearby?lat=2.29&lng=111.83&radius=10000
 *
 * 1. Places saved in our database: added by admins, or imported once from
 *    OpenStreetMap with `npm run facilities:import`. Fast and always available.
 * 2. Only if fewer than ENOUGH_SAVED are in range: ask OpenStreetMap live,
 *    and SAVE what it returns. Each area therefore needs only one successful
 *    live search, ever; after that it is served from the database.
 *    If the live search fails, the saved places are still returned (`partial`
 *    is true only when nothing at all could be found).
 */
facilitiesRouter.get('/facilities/nearby', requireAuth, async (req, res) => {
  const parsed = nearbyQuery.safeParse(req.query);
  if (!parsed.success) throw new HttpError(422, 'lat and lng must be valid coordinates.');
  const { lat, lng, radius } = parsed.data;

  // Cheap rectangle filter in SQL, exact circle filter below.
  const dLat = radius / 111_320;
  const dLng = radius / (111_320 * Math.max(Math.cos((lat * Math.PI) / 180), 0.01));
  const { rows } = await query(
    `SELECT id, name, type, ownership, is_24_hours, latitude, longitude, address, phone,
            opening_hours, source
     FROM facilities
     WHERE is_active
       AND latitude BETWEEN $1 AND $2
       AND longitude BETWEEN $3 AND $4`,
    [lat - dLat, lat + dLat, lng - dLng, lng + dLng],
  );
  const saved = rows.map((f) => ({
    id: f.id,
    name: f.name,
    type: f.type,
    ownership: f.ownership,
    is24Hours: f.is_24_hours,
    latitude: Number(f.latitude),
    longitude: Number(f.longitude),
    address: f.address,
    phone: f.phone,
    openingHours: f.opening_hours,
    source: f.source ?? 'admin',
  })).filter((f) => distanceMeters(lat, lng, f.latitude, f.longitude) <= radius);

  const admin = saved.filter((f) => f.source === 'admin');
  const nearAdmin = (o) =>
    admin.some((a) => a.type === o.type &&
      distanceMeters(a.latitude, a.longitude, o.latitude, o.longitude) < DUPLICATE_METERS);
  // Admin-added places win over imported copies of the same place.
  const local = [...admin, ...saved.filter((f) => f.source !== 'admin' && !nearAdmin(f))];

  let live = [];
  let liveFailed = false;
  if (local.length < ENOUGH_SAVED) {
    try {
      const found = await fetchNearby(lat, lng, radius);
      // Remember them for next time (and for every other user). Don't make
      // this user wait on it, and never fail the request because of it.
      saveOsmPlaces({ query }, found)
        .then(({ added }) => added && console.log(`Saved ${added} new places from OpenStreetMap.`))
        .catch((err) => console.warn(`Could not save OpenStreetMap places: ${err.message}`));

      const nearLocal = (o) =>
        local.some((l) => l.type === o.type &&
          distanceMeters(l.latitude, l.longitude, o.latitude, o.longitude) < DUPLICATE_METERS);
      live = found.filter((o) => !nearLocal(o));
    } catch (err) {
      console.warn(`OpenStreetMap lookup failed: ${err.message}`);
      liveFailed = true;
    }
  }

  const facilities = [...local, ...live]
    .map((f) => ({ ...f, distanceMeters: Math.round(distanceMeters(lat, lng, f.latitude, f.longitude)) }))
    .filter((f) => f.distanceMeters <= radius)
    .sort((a, b) => a.distanceMeters - b.distanceMeters)
    .slice(0, MAX_RESULTS);

  const usesOsm = facilities.some((f) => f.source === 'osm');
  res.json({
    facilities,
    partial: liveFailed && local.length === 0,
    attribution: usesOsm ? '© OpenStreetMap contributors' : null,
  });
});
