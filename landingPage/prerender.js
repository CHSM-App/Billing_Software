/**
 * Build-time prerendering (SSG).
 *
 * The site is a client-rendered SPA, so a crawler fetching it saw a 935-byte
 * shell: no headings, no links, no copy — which is exactly what the SEO audit
 * reported (0 H1-H6, 5% text/HTML ratio, 0 in-page links, mobile score 0/100).
 *
 * This script runs after `vite build` and writes one fully-rendered HTML file
 * per route, each with its own <title>, meta description, canonical, Open Graph
 * / Twitter tags and JSON-LD. The client bundle then hydrates that markup, so
 * behaviour in the browser is unchanged.
 *
 * Run order (see package.json "build"):
 *   1. vite build                       → client bundle + index.html template
 *   2. vite build --ssr entry-server    → node-runnable render() into .ssr/
 *   3. node prerender.js                → this file
 */
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'

import {
  ROUTES,
  SITE_URL,
  SITE_NAME,
  OG_IMAGE,
  TWITTER_HANDLE,
  TITLE_MAX,
  DESCRIPTION_MIN,
  DESCRIPTION_MAX,
  structuredData,
  breadcrumbs,
} from './src/seo.js'

const __dirname = path.dirname(fileURLToPath(import.meta.url))
const OUT_DIR = path.resolve(__dirname, '../backend/public')
const SSR_ENTRY = path.resolve(__dirname, '.ssr/entry-server.js')
const TEMPLATE = path.join(OUT_DIR, 'index.html')
const TEMPLATE_CACHE = path.resolve(__dirname, '.ssr/template.html')

/** Google Analytics 4 is opt-in: set GA_MEASUREMENT_ID (or VITE_GA_ID) to enable. */
const GA_ID = process.env.GA_MEASUREMENT_ID || process.env.VITE_GA_ID || ''

const esc = (s) =>
  String(s)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')

const absolute = (routePath) =>
  routePath === '/' ? `${SITE_URL}/` : `${SITE_URL}${routePath}`

/** Everything that belongs between the SEO:START / SEO:END markers. */
function headTags(route) {
  const url = absolute(route.path)
  const tags = [
    `<title>${esc(route.title)}</title>`,
    `<meta name="description" content="${esc(route.description)}" />`,
  ]

  if (route.keywords) {
    tags.push(`<meta name="keywords" content="${esc(route.keywords)}" />`)
  }

  tags.push(
    `<link rel="canonical" href="${esc(url)}" />`,
    route.noindex
      ? `<meta name="robots" content="noindex, follow" />`
      : `<meta name="robots" content="index, follow, max-image-preview:large, max-snippet:-1, max-video-preview:-1" />`,
    `<meta name="author" content="Vengurla Tech" />`,

    // Open Graph — Facebook, LinkedIn, WhatsApp link previews
    `<meta property="og:type" content="website" />`,
    `<meta property="og:site_name" content="${esc(SITE_NAME)}" />`,
    `<meta property="og:locale" content="en_IN" />`,
    `<meta property="og:url" content="${esc(url)}" />`,
    `<meta property="og:title" content="${esc(route.title)}" />`,
    `<meta property="og:description" content="${esc(route.description)}" />`,
    `<meta property="og:image" content="${esc(OG_IMAGE)}" />`,
    `<meta property="og:image:alt" content="Vittam billing software" />`,

    // Twitter / X card
    `<meta name="twitter:card" content="summary_large_image" />`,
    `<meta name="twitter:title" content="${esc(route.title)}" />`,
    `<meta name="twitter:description" content="${esc(route.description)}" />`,
    `<meta name="twitter:image" content="${esc(OG_IMAGE)}" />`
  )

  if (TWITTER_HANDLE) {
    tags.push(`<meta name="twitter:site" content="${esc(TWITTER_HANDLE)}" />`)
  }

  // The product/brand entities go on the home page only — repeating them
  // everywhere adds bytes without adding meaning. Sub-pages instead carry a
  // breadcrumb trail, which is what Google renders above their result.
  const jsonLd = route.path === '/' ? structuredData() : [breadcrumbs(route)].filter(Boolean)

  for (const node of jsonLd) {
    tags.push(
      `<script type="application/ld+json">${JSON.stringify(node).replace(/</g, '\\u003c')}</script>`
    )
  }

  return tags.map((t) => `    ${t}`).join('\n')
}

function analyticsSnippet() {
  if (!GA_ID) return ''
  return `
    <script async src="https://www.googletagmanager.com/gtag/js?id=${esc(GA_ID)}"></script>
    <script>
      window.dataLayer = window.dataLayer || [];
      function gtag(){dataLayer.push(arguments);}
      gtag('js', new Date());
      gtag('config', '${esc(GA_ID)}', { anonymize_ip: true });
    </script>`
}

function sitemap(lastmod) {
  const urls = ROUTES.filter((r) => r.sitemap !== false && !r.noindex)
    .map(
      (r) => `  <url>
    <loc>${absolute(r.path)}</loc>
    <lastmod>${lastmod}</lastmod>
    <changefreq>${r.changefreq || 'monthly'}</changefreq>
    <priority>${r.priority || '0.5'}</priority>
  </url>`
    )
    .join('\n')

  return `<?xml version="1.0" encoding="UTF-8"?>
<urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9">
${urls}
</urlset>
`
}

const MARKERS = {
  outlet: '<!--ssr-outlet-->',
  seo: /<!--\s*SEO:START[\s\S]*?SEO:END\s*-->/,
}

/**
 * The first route written is index.html — the same file Vite emitted the template
 * to — so a second run would otherwise read its own rendered output back as the
 * template. Stash the pristine copy next to the SSR bundle so re-running this
 * script alone (to flip the GA id, say) still works.
 */
function loadTemplate() {
  if (!fs.existsSync(TEMPLATE)) {
    throw new Error(`Missing ${TEMPLATE} — run \`vite build\` first.`)
  }

  const fresh = fs.readFileSync(TEMPLATE, 'utf8')
  if (fresh.includes(MARKERS.outlet) && MARKERS.seo.test(fresh)) {
    fs.mkdirSync(path.dirname(TEMPLATE_CACHE), { recursive: true })
    fs.writeFileSync(TEMPLATE_CACHE, fresh)
    return fresh
  }

  if (fs.existsSync(TEMPLATE_CACHE)) {
    console.log('  (index.html already prerendered — reusing the cached template)')
    return fs.readFileSync(TEMPLATE_CACHE, 'utf8')
  }

  throw new Error(
    `${TEMPLATE} has no ${MARKERS.outlet} / SEO markers and no cached template exists.\n` +
      'Run `npm run build` so Vite regenerates the template first.'
  )
}

/**
 * Fail the build rather than shipping a title Google truncates mid-word or a
 * description it discards and rewrites. Cheap to check, easy to regress.
 */
function assertMetaLengths() {
  const problems = []

  for (const route of ROUTES) {
    if (route.title.length > TITLE_MAX) {
      problems.push(`${route.path} title is ${route.title.length} chars (max ${TITLE_MAX}): "${route.title}"`)
    }
    const len = route.description.length
    if (len < DESCRIPTION_MIN || len > DESCRIPTION_MAX) {
      problems.push(
        `${route.path} description is ${len} chars (want ${DESCRIPTION_MIN}-${DESCRIPTION_MAX})`
      )
    }
  }

  const dupes = ['title', 'description'].flatMap((field) => {
    const seen = new Map()
    for (const r of ROUTES) seen.set(r[field], (seen.get(r[field]) || 0) + 1)
    return [...seen].filter(([, n]) => n > 1).map(([v]) => `duplicate ${field}: "${v}"`)
  })

  if (problems.length || dupes.length) {
    throw new Error(`SEO metadata problems in src/seo.js:\n  - ${[...problems, ...dupes].join('\n  - ')}`)
  }
}

async function main() {
  if (!fs.existsSync(SSR_ENTRY)) {
    throw new Error(`Missing ${SSR_ENTRY} — run the --ssr build first.`)
  }

  assertMetaLengths()

  const template = loadTemplate()

  const { render } = await import(pathToFileURL(SSR_ENTRY).href)

  for (const route of ROUTES) {
    const appHtml = render(route.path)

    const html = template
      .replace(
        /<!--\s*SEO:START[\s\S]*?SEO:END\s*-->/,
        () => headTags(route).trimStart() + analyticsSnippet()
      )
      .replace('<!--ssr-outlet-->', () => appHtml)

    const dest = path.join(OUT_DIR, route.file)
    fs.mkdirSync(path.dirname(dest), { recursive: true })
    fs.writeFileSync(dest, html)

    const kb = (Buffer.byteLength(html) / 1024).toFixed(1)
    console.log(`  prerendered ${route.path.padEnd(16)} → ${route.file.padEnd(20)} ${kb} KB`)
  }

  const lastmod = new Date().toISOString().slice(0, 10)
  fs.writeFileSync(path.join(OUT_DIR, 'sitemap.xml'), sitemap(lastmod))
  console.log(`  wrote sitemap.xml (${ROUTES.filter((r) => r.sitemap !== false).length} urls)`)

  console.log(GA_ID ? `  analytics: GA4 ${GA_ID}` : '  analytics: disabled (set GA_MEASUREMENT_ID)')
}

main().catch((err) => {
  console.error('\nprerender failed:', err)
  process.exit(1)
})
