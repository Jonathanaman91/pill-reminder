import react from '@vitejs/plugin-react';
import { defineConfig } from 'vite';

export default defineConfig({
  plugins: [react()],
  // The backend only accepts browser requests from the addresses listed in
  // CORS_ORIGINS (http://localhost:5173 by default), so never drift to 5174.
  server: { port: 5173, strictPort: true },
  preview: { port: 5173, strictPort: true },
});
