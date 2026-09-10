/*
 * Where the landing page's fetch calls go.
 *
 * Empty by default, i.e. same-origin relative URLs — which is correct in BOTH
 * places this runs:
 *   production — `vite build` emits into backend/public and Express serves it,
 *                so the page and /api are literally the same server.
 *   development — vite.config.js proxies /api to the backend.
 *
 * Neither needs an absolute URL, and using one is what caused a dev page to
 * post to the live API and get refused by CORS. Set VITE_API_URL only if the
 * API ever moves to a different host than the page.
 */
export const API_BASE = import.meta.env.VITE_API_URL || ''
