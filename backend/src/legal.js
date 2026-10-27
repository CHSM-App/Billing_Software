'use strict';

/**
 * legal.js — the one authoritative version of the legal bundle a business owner
 * agrees to: Terms of Service + Acceptable Use Policy + Privacy Policy
 * (docs/legal/). Recorded in terms_acceptances (migration 072).
 *
 * null = the consent flow is OFF: /register records nothing, /license never
 * asks for acceptance, POST /account/accept-terms refuses. Set it only after
 * the advocate has approved the text — to the version printed in the header
 * of docs/legal/TERMS_OF_SERVICE.md (e.g. '2026-11-01') — and bump it for
 * every MATERIAL change, which makes every owner accept again.
 * See docs/legal/DEPLOYMENT.md.
 *
 * ponytail: one version for all three documents; split per document if they
 * ever need to change independently.
 */
module.exports = { TERMS_VERSION: '2026-10-01' };
