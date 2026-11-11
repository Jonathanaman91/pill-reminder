/**
 * The database stores photo paths like "/uploads/<id>.jpg"; clients get a
 * full URL built from the address THEY used, so it works for the emulator
 * (10.0.2.2), a phone on Wi-Fi, the admin panel, and the hosted server alike.
 * `app.set('trust proxy', 1)` makes req.protocol "https" behind Render.
 */
export function publicUrl(req, relative) {
  if (!relative || /^https?:\/\//.test(relative)) return relative ?? null;
  return `${req.protocol}://${req.get('host')}${relative}`;
}
