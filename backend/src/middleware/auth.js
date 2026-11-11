import jwt from 'jsonwebtoken';
import { config } from '../config.js';
import { HttpError } from '../errors.js';

/**
 * Reads "Authorization: Bearer <access token>" and puts { id, role } on
 * req.user. Answers 401 when missing, expired or forged, which tells the app
 * to use its refresh token.
 */
export function requireAuth(req, res, next) {
  const header = req.get('authorization') ?? '';
  const [scheme, token] = header.split(' ');
  if (scheme !== 'Bearer' || !token) throw new HttpError(401, 'Not logged in.');

  try {
    const payload = jwt.verify(token, config.jwtAccessSecret);
    req.user = { id: payload.sub, role: payload.role };
    next();
  } catch {
    throw new HttpError(401, 'Session expired. Please log in again.');
  }
}

/** Use after requireAuth on every /admin route. */
export function requireAdmin(req, res, next) {
  if (req.user?.role !== 'admin') throw new HttpError(403, 'Admins only.');
  next();
}
