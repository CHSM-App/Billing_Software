# Vittam landing page

Vite + React marketing site for https://vittam.vengurlatech.com. It is
**prerendered at build time**, so crawlers and link-preview bots get complete
HTML instead of an empty SPA shell.

## Build

```bash
npm install
npm run build      # → ../backend/public/
```

`npm run build` runs three steps:

| Step | Command | Output |
| --- | --- | --- |
| 1. Client | `vite build` | JS/CSS bundle + `index.html` template |
| 2. SSR | `vite build --ssr src/entry-server.jsx` | `.ssr/entry-server.js` (build-time only) |
| 3. Prerender | `node prerender.js` | one HTML file per route + `sitemap.xml` |

`npm run dev` is unchanged — the dev server renders client-side as before.

## Adding a page

1. Add the route to `src/App.jsx`.
2. Add a matching entry to `ROUTES` in `src/seo.js` (path, output filename,
   title, description, keywords).

Both are required. Express serves prerendered files by name, so a route missing
from `src/seo.js` will 404 on a hard refresh even though client-side navigation
to it works.

## Where the SEO pieces live

| Concern | File |
| --- | --- |
| Titles, descriptions, keywords, canonical, OG/Twitter, JSON-LD | `src/seo.js` |
| Head injection, per-route HTML, `sitemap.xml` | `prerender.js` |
| `robots.txt`, `logo.png`, `og-image.png`, `site.webmanifest` | `public/` |
| FAQ copy (page **and** FAQPage schema) | `src/data/faqs.js` |
| Onboarding steps (page **and** HowTo schema) | `src/data/steps.js` |
| Canonical-host redirect, 404 status, static serving | `../backend/src/server.js` |

### Enforced metadata limits

`prerender.js` **fails the build** if any route in `src/seo.js` has a title over
60 characters, a description outside 150–160 characters, or a title/description
duplicated across pages. Those are the bounds Google renders without truncating,
and they are easy to regress by hand — so the build checks instead of trusting.

### Structured data

Home page carries `SoftwareApplication`, `Organization`, `WebSite`, `FAQPage`
and `HowTo`. Sub-pages carry `BreadcrumbList` instead — repeating the brand
entities everywhere adds bytes without adding meaning.

Note there is deliberately **no `AggregateRating`/`Review` schema**. Those need
real, verifiable customer ratings; inventing them is a manual-action risk. Add
them once you have genuine reviews to point at.

## Environment variables

| Variable | Where | Effect if unset |
| --- | --- | --- |
| `GA_MEASUREMENT_ID` | build (CI) | No analytics tag is emitted |
| `CANONICAL_HOST` | backend runtime | No host-canonicalisation redirect |
| `VITE_API_URL` | build | Delete-account form posts to a same-origin `/api` |

Set `CANONICAL_HOST=vittam.vengurlatech.com` in `backend/.env` so requests
arriving on the bare server IP 301 to the real domain. API, `/order`, `/receipt`,
`/uploads`, `/admin` and `/health` traffic is never redirected.

`GA_MEASUREMENT_ID` is read by `prerender.js` at build time and injects a GA4
tag into every page. Adding it means the site starts collecting visitor data —
update `src/components/privacyPolicy.jsx` to disclose it before switching it on.

## Notes

- `public/og-image.png` is currently the 512×512 square logo. Social platforms
  prefer a 1200×630 landscape banner; replacing that one file is enough.
- `src/images/logo.png` (2400px, 2.9 MB) and `logo.jpg` (6.7 MB) are no longer
  imported — `public/logo.png` (512px, 79 KB) is used instead.
