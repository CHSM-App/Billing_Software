const request = require('supertest');

const { makeDbMock } = require('../helpers/db');
const { mockPool } = makeDbMock();

jest.mock('../../src/db', () => mockPool);

// Rate limiters would otherwise warn about IPv6 key generation under supertest.
jest.mock('../../src/middleware/rateLimiter', () => ({
  globalLimiter: (req, res, next) => next(),
  loginLimiter: (req, res, next) => next(),
  registerLimiter: (req, res, next) => next(),
  refreshLimiter: (req, res, next) => next(),
  deletionLimiter: (req, res, next) => next(),
}));

// CANONICAL_HOST is read at module load, so it must be set before requiring the app.
process.env.CANONICAL_HOST = 'vittam.vengurlatech.com';

const app = require('../../src/server');

// The prerendered HTML lives in backend/public/, which CI generates from
// landingPage/. Skip the file-backed assertions when it has not been built yet
// so a fresh clone does not fail on missing build output.
const fs = require('fs');
const path = require('path');
const PUBLIC_DIR = path.join(__dirname, '..', '..', 'public');
const built = fs.existsSync(path.join(PUBLIC_DIR, '404.html'));
const ifBuilt = built ? describe : describe.skip;

describe('canonical host redirect', () => {
  it('301s page requests arriving on a non-canonical host (e.g. the bare IP)', async () => {
    const res = await request(app).get('/').set('Host', '180.179.212.43');

    expect(res.status).toBe(301);
    expect(res.headers.location).toBe('https://vittam.vengurlatech.com/');
  });

  it('preserves the path and query string when redirecting', async () => {
    const res = await request(app).get('/help?utm_source=x').set('Host', '180.179.212.43');

    expect(res.status).toBe(301);
    expect(res.headers.location).toBe('https://vittam.vengurlatech.com/help?utm_source=x');
  });

  it('leaves API traffic alone so clients pinned to another host keep working', async () => {
    const res = await request(app).get('/api/health').set('Host', '180.179.212.43');

    expect(res.status).not.toBe(301);
  });

  it('does not redirect requests already on the canonical host', async () => {
    const res = await request(app).get('/').set('Host', 'vittam.vengurlatech.com');

    expect(res.status).not.toBe(301);
  });

  it('leaves localhost alone so local development is unaffected', async () => {
    const res = await request(app).get('/').set('Host', 'localhost');

    expect(res.status).not.toBe(301);
  });

});

// Config resolution is unit tested against the module directly: re-requiring
// server.js with NODE_ENV=production would start a real listener and hang jest.
describe('resolveCanonicalHost', () => {
  const { resolveCanonicalHost, PRODUCTION_HOST } = require('../../src/canonicalHost');

  it('defaults to the live domain in production so the fix applies on deploy', () => {
    expect(resolveCanonicalHost({ NODE_ENV: 'production' })).toBe(PRODUCTION_HOST);
  });

  it('stays off outside production', () => {
    expect(resolveCanonicalHost({ NODE_ENV: 'development' })).toBe('');
    expect(resolveCanonicalHost({ NODE_ENV: 'test' })).toBe('');
  });

  it('lets an explicit value override the production default', () => {
    expect(resolveCanonicalHost({ NODE_ENV: 'production', CANONICAL_HOST: 'staging.example.com' }))
      .toBe('staging.example.com');
  });

  it('treats an explicit empty string as "disabled"', () => {
    expect(resolveCanonicalHost({ NODE_ENV: 'production', CANONICAL_HOST: '' })).toBe('');
  });
});

describe('canonicalRedirectTarget', () => {
  const { canonicalRedirectTarget, NO_REDIRECT_PREFIXES } = require('../../src/canonicalHost');
  const HOST = 'vittam.vengurlatech.com';
  const req = (over) => ({ method: 'GET', path: '/', originalUrl: '/', hostname: '1.2.3.4', ...over });

  it('returns null when no canonical host is configured', () => {
    expect(canonicalRedirectTarget(req(), '')).toBeNull();
  });

  it('never redirects non-idempotent methods', () => {
    expect(canonicalRedirectTarget(req({ method: 'POST' }), HOST)).toBeNull();
  });

  it.each(NO_REDIRECT_PREFIXES)('never redirects %s traffic', (prefix) => {
    expect(canonicalRedirectTarget(req({ path: prefix, originalUrl: prefix }), HOST)).toBeNull();
    const sub = `${prefix}/thing`;
    expect(canonicalRedirectTarget(req({ path: sub, originalUrl: sub }), HOST)).toBeNull();
  });

  it('does not redirect a path that merely starts with an excluded prefix', () => {
    // "/apidocs" is a page, not the "/api" mount.
    expect(canonicalRedirectTarget(req({ path: '/apidocs', originalUrl: '/apidocs' }), HOST))
      .toBe('https://vittam.vengurlatech.com/apidocs');
  });

  it.each(['localhost', '127.0.0.1', '::1'])('leaves %s alone', (hostname) => {
    expect(canonicalRedirectTarget(req({ hostname }), HOST)).toBeNull();
  });

  it('is case insensitive about the incoming host', () => {
    expect(canonicalRedirectTarget(req({ hostname: 'VITTAM.VENGURLATECH.COM' }), HOST)).toBeNull();
  });
});

describe('trailing slash normalisation', () => {
  it('301s /help/ to /help so the two do not compete as duplicate URLs', async () => {
    const res = await request(app).get('/help/').set('Host', 'vittam.vengurlatech.com');

    expect(res.status).toBe(301);
    expect(res.headers.location).toBe('/help');
  });

  it('leaves the root path alone', async () => {
    const res = await request(app).get('/').set('Host', 'vittam.vengurlatech.com');

    expect(res.status).not.toBe(301);
  });
});

describe('not found handling', () => {
  it('returns a real 404 status for unknown pages instead of a soft 404', async () => {
    const res = await request(app)
      .get('/no-such-page')
      .set('Host', 'vittam.vengurlatech.com');

    expect(res.status).toBe(404);
  });

  it('keeps unknown API routes on JSON', async () => {
    const res = await request(app)
      .get('/api/no-such-endpoint')
      .set('Host', 'vittam.vengurlatech.com');

    expect(res.status).toBe(404);
    expect(res.body).toEqual({ error: 'Not found.' });
  });
});

ifBuilt('prerendered landing pages', () => {
  it('serves fully rendered HTML at / — headings, links and a meta description', async () => {
    const res = await request(app).get('/').set('Host', 'vittam.vengurlatech.com');

    expect(res.status).toBe(200);
    expect(res.text).toMatch(/<h1[ >]/);
    expect(res.text).toMatch(/<meta name="description" content="[^"]{100,300}"/);
    expect(res.text).toMatch(/rel="canonical" href="https:\/\/vittam\.vengurlatech\.com\/"/);
  });

  it('serves /help from help.html without a redirect', async () => {
    const res = await request(app).get('/help').set('Host', 'vittam.vengurlatech.com');

    expect(res.status).toBe(200);
    expect(res.text).toContain('Help Center');
  });

  it('serves the custom 404 page body on unknown pages', async () => {
    const res = await request(app)
      .get('/no-such-page')
      .set('Host', 'vittam.vengurlatech.com');

    expect(res.status).toBe(404);
    expect(res.text).toContain('This page went missing');
  });

  it('exposes robots.txt and sitemap.xml as real files', async () => {
    const robots = await request(app).get('/robots.txt').set('Host', 'vittam.vengurlatech.com');
    expect(robots.status).toBe(200);
    expect(robots.text).toContain('Sitemap: https://vittam.vengurlatech.com/sitemap.xml');

    const sitemap = await request(app).get('/sitemap.xml').set('Host', 'vittam.vengurlatech.com');
    expect(sitemap.status).toBe(200);
    expect(sitemap.text).toContain('<loc>https://vittam.vengurlatech.com/</loc>');
  });
});
