import { defineConfig } from 'vite'
import react from '@vitejs/plugin-react'
import path from 'path'

export default defineConfig({
  plugins: [react()],
  build: {
    // Output directly into backend/public so the Express server can serve it
    outDir: path.resolve(__dirname, '../backend/public'),
    emptyOutDir: true,
  },
})
