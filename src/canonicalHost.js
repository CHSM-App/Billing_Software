/**
 * Canonical-host resolution, kept separate from server.js so it can be unit
 * tested without booting the app (requiring server.js outside NODE_ENV=test
 * starts a real listener).
 *
 * The SEO audit flagged that http://180.179.212.43 serves the site directly
 * instead of redirecting, which lets search engines index every page under a
 * second hostname and splits the ranking signals between the two.
 */

const PRODUCTION_HOST = 'vittam.vengurlatech.com';

/** Paths that must never be redirected — clients may be pinned to another host. */
const NO_REDIRECT_PREFIXES = ['/api', '/uploads', '/order', '/store', '/receipt', '/admin', '/health'];

/** Hosts that are legitimately not the canonical one. */
const LOCAL_HOSTS = new Set(['localhost', '127.0.0.1', '[::1]', '::1']);

/**
 * An explicit CANONICAL_HOST always wins — including an empty string, which
 * disables redirecting. Unset falls back to the live domain in production so the
 * fix applies on deploy without a config change, and to off everywhere else.
 */
function resolveCanonicalHost(env = process.env) {
  if (env.CANONICAL_HOST !== undefined) return env.CANONICAL_HOST;
  return env.NODE_ENV === 'production' ? PRODUCTION_HOST : '';
}

/**
 * @returns {string|null} absolute URL to redirect to, or null to serve normally.
 */
function canonicalRedirectTarget(req, canonicalHost) {
  if (!canonicalHost) return null;
  if (req.method !== 'GET' && req.method !== 'HEAD') return null;

  const reqPath = req.path || '';
  if (NO_REDIRECT_PREFIXES.some((p) => reqPath === p || reqPath.startsWith(`${p}/`))) return null;

  const host = (req.hostname || '').toLowerCase();
  if (!host || host === canonicalHost.toLowerCase() || LOCAL_HOSTS.has(host)) return null;

  return `https://${canonicalHost}${req.originalUrl || reqPath}`;
}

module.exports = {
  PRODUCTION_HOST,
  NO_REDIRECT_PREFIXES,
  resolveCanonicalHost,
  canonicalRedirectTarget,
};
