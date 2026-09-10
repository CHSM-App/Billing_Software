import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  server: {
    // Reachable from other devices on the LAN (phone testing, 192.168.x.y).
    host: true,
    // Same-origin /api in development. A production build is served BY the
    // backend out of backend/public (see build.outDir), so the page and the API
    // already share an origin there — this makes dev match, which means the
    // fetch calls need no absolute URL and CORS never enters the picture.
    proxy: {
      '/api': {
        target: `http://localhost:${process.env.BACKEND_PORT || 5000}`,
        changeOrigin: true,
      },
    },
  },
  build: {
    // Output directly into backend/public so the Express server can serve it
    outDir: path.resolve(__dirname, '../backend/public'),
    emptyOutDir: true,
  },
})
