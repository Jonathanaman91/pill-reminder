import { createApp } from './app.js';
import { config } from './config.js';

createApp().listen(config.port, () => {
  console.log(`Pill Reminder API listening on http://localhost:${config.port}/api/v1`);
});
