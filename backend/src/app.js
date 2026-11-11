import cors from 'cors';
import express from 'express';
import helmet from 'helmet';
import { config } from './config.js';
import { errorHandler, notFound } from './errors.js';
import { authRouter } from './routes/auth.routes.js';
import { facilitiesRouter } from './routes/facilities.routes.js';
import { medicationsRouter, photosRouter } from './routes/medications.routes.js';
import { syncRouter } from './routes/sync.routes.js';

export function createApp() {
  const app = express();

  // Behind Render's (or any host's) HTTPS proxy: trust it, so req.protocol is
  // "https" and photo links are built as https:// (Android release builds
  // refuse plain http).
  app.set('trust proxy', 1);

  // cross-origin: lets the admin panel (another port) show uploaded photos.
  app.use(helmet({ crossOriginResourcePolicy: { policy: 'cross-origin' } }));
  // The phone app does not need CORS; only the browser-based admin panel does.
  app.use(cors({ origin: config.corsOrigins }));
  app.use(express.json({ limit: '1mb' }));

  app.get('/api/v1/health', (req, res) => res.json({ ok: true }));
  app.use('/api/v1/auth', authRouter);
  app.use('/api/v1', syncRouter);
  app.use('/api/v1', medicationsRouter);
  app.use('/api/v1', facilitiesRouter);
  app.use(photosRouter); // GET /uploads/<id>.jpg
  // Next step: /api/v1/admin/*

  app.use(notFound);
  app.use(errorHandler);
  return app;
}
