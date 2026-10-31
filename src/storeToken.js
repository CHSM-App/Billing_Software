/**
 * Readable public store links: a business's own name, slugified, used as the
 * token in /store/<token>.
 *
 * Replaces the 32-hex-char random token for businesses created (or renamed)
 * from here on. Businesses that already hold a random token keep it — those
 * links are out in the world on printed QR posters, and re-slugging them would
 * 404 every one.
 *
 * NOTE ON GUESSABILITY. The old token was deliberately unguessable; a slug is
 * not. Anyone can try /store/big-bazaar and find out whether such a shop exists
 * and has its store switched on. That is an accepted trade for a link a shop
 * can read out over the phone — but it means the token is now an IDENTIFIER,
 * not a secret, so it must never be the only thing gating anything private.
 * It isn't today: resolveStore() in routes/public_store.js still checks
 * store_enabled and the allow_online_store entitlement, and every customer
 * action behind it goes through the OTP session token (signStoreToken), which
 * stays random. Keep it that way.
 */

const sql = require('mssql');

/** Longest slug we will store. The column is NVARCHAR(32) and the numeric
 *  suffix needs room, so the name part is capped below this. */
const MAX_TOKEN_LEN = 32;
const MAX_BASE_LEN = 24; // leaves room for '-9999' and then some

/**
 * Path segments a slug may never take, because something else already answers
 * on that URL. Nothing under /store/ is served statically today, but
 * public_store.js has sub-routes (/:token/menu, /:token/orders, …) and a shop
 * literally named "Menu" must not be able to shadow one.
 */
const RESERVED = new Set([
  'menu', 'orders', 'send-otp', 'verify-otp',
  'store', 'api', 'admin', 'uploads', 'assets', 'static',
  'index', 'health', 'login', 'order', 'receipt',
]);

/**
 * "Vengurla Tech & Co." -> "vengurla-tech-co"
 *
 * Accents are folded to ASCII first (NFD then strip combining marks) so "Café"
 * becomes "cafe" rather than losing the letter. Devanagari and other
 * non-Latin scripts have no ASCII form and drop out entirely — a shop named
 * only in Marathi slugifies to '', which is why uniqueStoreToken falls back to
 * a random token rather than storing an empty one.
 */
function slugify(name) {
  return String(name || '')
    .normalize('NFD')
    .replace(/[\u0300-\u036f]/g, '')   // strip accents left by NFD
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')       // everything else becomes a separator
    .replace(/^-+|-+$/g, '')           // no leading/trailing hyphens
    .replace(/-{2,}/g, '-')            // collapse runs
    .slice(0, MAX_BASE_LEN)
    .replace(/-+$/g, '');              // slice may have left a trailing hyphen
}

/** A random 32-hex token, the pre-slug format. Used when a name yields no
 *  usable slug at all (e.g. a purely Devanagari name), so such a business
 *  still gets a working link rather than a NULL one. */
function randomToken() {
  return require('crypto').randomBytes(16).toString('hex');
}

/**
 * The store token for [name], guaranteed not to collide with any token already
 * in the businesses table.
 *
 * Duplicates get a numeric suffix: vengurla-tech, vengurla-tech-2,
 * vengurla-tech-3 … The first shop with a name keeps the bare slug.
 *
 * [request] is an mssql Request (pool.request() or transaction.request()) so
 * the caller decides which transaction this reads in. [excludeBusinessId] is
 * the business being renamed — it must not collide with its own current token,
 * or a no-op rename would bump the suffix every time.
 *
 * Races: two businesses with the same name registering in the same instant can
 * both compute the same suffix. The filtered unique index on store_token is the
 * backstop — the loser's INSERT fails and its transaction rolls back, so it
 * errors rather than silently duplicating. Same exposure the GSTIN duplicate
 * check in this codebase already carries.
 */
async function uniqueStoreToken(request, name, excludeBusinessId = null) {
  const base = slugify(name);
  if (!base || RESERVED.has(base)) {
    // No usable slug (non-Latin name) or one that would shadow a real route.
    // Fall back rather than inventing a name the owner never chose.
    return base ? `${base}-store` : randomToken();
  }

  const r = await request
    .input('slug_base', sql.NVarChar(MAX_TOKEN_LEN), base)
    .input('slug_like', sql.NVarChar(MAX_TOKEN_LEN), `${base}-%`)
    .input('slug_exclude', sql.UniqueIdentifier, excludeBusinessId)
    .query(`
      SELECT store_token FROM businesses
      WHERE (store_token = @slug_base OR store_token LIKE @slug_like)
        AND (@slug_exclude IS NULL OR id <> @slug_exclude)
    `);

  const taken = new Set(
    r.recordset.map((row) => String(row.store_token).toLowerCase()));
  if (!taken.has(base)) return base;

  // Start at 2 so the second "Vengurla Tech" reads vengurla-tech-2 — there is
  // no vengurla-tech-1, because the first one holds the bare slug.
  for (let i = 2; i < 10000; i++) {
    const candidate = `${base}-${i}`;
    if (!taken.has(candidate)) return candidate;
  }
  return randomToken(); // 9999 shops sharing a name; give up gracefully
}

// ---------------------------------------------------------------------------
// Owner-chosen links
// ---------------------------------------------------------------------------

/** Shortest link we accept. Two characters is not a name, it is a typo, and
 *  short slugs are the ones worth reserving. */
const MIN_TOKEN_LEN = 3;

/**
 * Whether [slug] is a shape we are willing to put in a URL, INDEPENDENT of
 * whether anyone has taken it. Returns null when fine, otherwise a message
 * written for the shop owner to read.
 *
 * Deliberately stricter than slugify(): slugify CLEANS a name we generated,
 * whereas this JUDGES something a human typed, and silently rewriting their
 * input to something else is worse than telling them what is wrong.
 */
function validateSlug(slug) {
  const s = String(slug ?? '');
  if (!s.trim()) return 'Enter a link';
  if (s !== s.toLowerCase()) return 'Use lowercase letters only';
  if (s.length < MIN_TOKEN_LEN) {
    return `Link must be at least ${MIN_TOKEN_LEN} characters`;
  }
  if (s.length > MAX_TOKEN_LEN) {
    return `Link must be ${MAX_TOKEN_LEN} characters or fewer`;
  }
  if (!/^[a-z0-9-]+$/.test(s)) {
    return 'Use only letters, numbers and hyphens';
  }
  if (s.startsWith('-') || s.endsWith('-')) {
    return 'Link cannot start or end with a hyphen';
  }
  if (s.includes('--')) return 'Link cannot contain two hyphens in a row';
  // A 32-hex string is the shape of an auto-generated token; letting an owner
  // type one invites confusion with another shop's random link.
  if (/^[0-9a-f]{32}$/.test(s)) return 'That link is not available';
  if (RESERVED.has(s)) return 'That link is reserved';
  return null;
}

/**
 * Whether [slug] is free, ignoring [excludeBusinessId] (the shop asking — its
 * own current link must read as available, or the UI would tell an owner their
 * existing link is taken).
 *
 * Case-insensitive on purpose: SQL Server's default collation is, so
 * /store/Big-Bazaar already resolves the same row as /store/big-bazaar. If this
 * check were case-sensitive it would hand out a "free" slug that then collided.
 */
async function isSlugAvailable(request, slug, excludeBusinessId = null) {
  const r = await request
    .input('slug', sql.NVarChar(MAX_TOKEN_LEN), String(slug).toLowerCase())
    .input('slug_exclude', sql.UniqueIdentifier, excludeBusinessId)
    .query(`
      SELECT TOP 1 1 AS taken FROM businesses
      WHERE LOWER(store_token) = @slug
        AND (@slug_exclude IS NULL OR id <> @slug_exclude)
    `);
  return r.recordset.length === 0;
}

/**
 * Whether [token] is one WE generated from [name], rather than one the owner
 * chose for themselves.
 *
 * This is what stops a rename from trampling a custom link. An owner who set
 * their link to "coastal-kitchen" and later fixes a typo in the shop name
 * expects the link to stay put; an owner who never touched it expects the link
 * to follow along. Derived from the data rather than stored in a new column —
 * an auto token is by construction either slugify(name) or slugify(name)-N.
 *
 * A random fallback token (32 hex, from an unslugifiable name) also counts as
 * auto: nobody chose it, so a later rename to something slugifiable should
 * upgrade it to a real slug.
 */
function looksAutoDerived(token, name) {
  if (!token) return true;
  const t = String(token).toLowerCase();
  if (/^[0-9a-f]{32}$/.test(t)) return true;
  const base = slugify(name);
  if (!base) return false;
  return t === base || new RegExp(`^${base}-\\d+$`).test(t);
}

module.exports = {
  slugify,
  uniqueStoreToken,
  randomToken,
  validateSlug,
  isSlugAvailable,
  looksAutoDerived,
  RESERVED,
  MAX_TOKEN_LEN,
  MIN_TOKEN_LEN,
};
