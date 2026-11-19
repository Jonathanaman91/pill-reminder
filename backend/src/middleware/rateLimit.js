import { HttpError } from '../errors.js';

/**
 * A small in-memory limit: at most `max` requests per `windowMs` from one IP
 * address. Enough for one server on a free plan; a restart simply resets it.
 * (`app.set('trust proxy', 1)` in app.js makes req.ip the phone's address,
 * not Render's proxy.)
 */
export function limitPerIp({ max, windowMs }) {
  const hits = new Map(); // ip → { count, resetAt }

  // Forget old entries now and then, so the map can't grow forever.
  const sweep = setInterval(() => {
    const now = Date.now();
    for (const [ip, entry] of hits) if (entry.resetAt <= now) hits.delete(ip);
  }, windowMs);
  sweep.unref(); // never keeps the process (or a test) alive

  return (req, res, next) => {
    const now = Date.now();
    const key = req.ip ?? 'unknown';
    let entry = hits.get(key);
    if (!entry || entry.resetAt <= now) {
      entry = { count: 0, resetAt: now + windowMs };
      hits.set(key, entry);
    }
    entry.count += 1;
    if (entry.count > max) {
      res.set('Retry-After', String(Math.ceil((entry.resetAt - now) / 1000)));
      throw new HttpError(429, 'Too many searches. Please wait a few minutes and try again.');
    }
    next();
  };
}
