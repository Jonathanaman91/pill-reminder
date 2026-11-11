/**
 * Saves OpenStreetMap places into the facilities table. Used by both the
 * import command and the Nearby route (which saves every successful live
 * search, so each area only ever needs to be looked up once).
 *
 * Places are matched on their OpenStreetMap id ("node/123"), so saving the
 * same place twice updates it instead of creating a duplicate. Places added
 * by admins have no osm_id and are never touched.
 */
export async function saveOsmPlaces(db, places) {
  let added = 0;
  let updated = 0;
  for (const p of places) {
    const osmId = p.id.replace(/^osm:/, '');
    const { rows } = await db.query(
      `INSERT INTO facilities
         (name, type, ownership, is_24_hours, latitude, longitude, address, phone,
          opening_hours, source, osm_id)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8, $9, 'osm', $10)
       ON CONFLICT (osm_id) DO UPDATE SET
         name = EXCLUDED.name, type = EXCLUDED.type, ownership = EXCLUDED.ownership,
         is_24_hours = EXCLUDED.is_24_hours, latitude = EXCLUDED.latitude,
         longitude = EXCLUDED.longitude, address = EXCLUDED.address, phone = EXCLUDED.phone,
         opening_hours = EXCLUDED.opening_hours
       RETURNING (xmax = 0) AS inserted`,
      [p.name.slice(0, 150), p.type, p.ownership, p.is24Hours, p.latitude, p.longitude,
        p.address?.slice(0, 255) ?? null, p.phone?.slice(0, 20) ?? null,
        p.openingHours?.slice(0, 120) ?? null, osmId],
    );
    if (rows[0].inserted) added++;
    else updated++;
  }
  return { added, updated };
}
