/**
 * Single source of truth for per-route SEO metadata.
 *
 * Consumed by:
 *   - prerender.js  → injects <title>/<meta>/JSON-LD into each static HTML file
 *   - prerender.js  → generates public sitemap.xml from ROUTES
 *
 * Adding a page? Add it here AND to App.jsx, or it will 404 on a hard refresh
 * (the Express catch-all only serves prerendered files — see backend/src/server.js).
 */

import { FAQS } from './data/faqs.js'
import { STEPS } from './data/steps.js'

export const SITE_URL = 'https://vittam.vengurlatech.com'
export const SITE_NAME = 'Vittam'
export const OG_IMAGE = `${SITE_URL}/og-image.png`
export const TWITTER_HANDLE = ''

/**
 * Titles are kept to 60 characters and descriptions to 150-160 so Google renders
 * them whole instead of truncating mid-sentence. `npm run build` fails the build
 * if either drifts outside those bounds — see prerender.js.
 */
export const TITLE_MAX = 60
export const DESCRIPTION_MIN = 150
export const DESCRIPTION_MAX = 160

export const ROUTES = [
  {
    path: '/',
    file: 'index.html',
    changefreq: 'weekly',
    priority: '1.0',
    title: 'Vittam – GST Billing Software for Indian Small Business',
    description:
      'Offline-first GST billing software for kirana stores, cafes and restaurants. Fast billing, inventory, thermal printing and WhatsApp bills. Free for 1 month.',
    keywords:
      'billing software, GST billing software India, kirana store billing, restaurant billing software, inventory management software, offline billing app, POS software for small business, thermal printer billing, WhatsApp bill sharing, retail billing software',
  },
  {
    path: '/help',
    file: 'help.html',
    changefreq: 'monthly',
    priority: '0.7',
    title: 'Help Center & Support – Vittam Billing Software',
    description:
      'Setup guides, thermal printer help and billing FAQs for Vittam. Get answers fast, or reach our support team on WhatsApp and email. We reply the same day.',
    keywords:
      'Vittam help, billing software support, POS setup guide, thermal printer setup, billing software FAQ',
  },
  {
    path: '/privacy',
    file: 'privacy.html',
    changefreq: 'yearly',
    priority: '0.4',
    title: 'Privacy Policy – Vittam Billing Software',
    description:
      'How Vittam collects, stores and protects your business and billing data, who it is shared with, and how you can access, export or delete it at any time.',
    keywords: 'Vittam privacy policy, billing data privacy, data protection, data deletion',
  },
  {
    path: '/delete-account',
    file: 'delete-account.html',
    changefreq: 'yearly',
    priority: '0.3',
    title: 'Delete Your Account & Data – Vittam',
    description:
      'Request permanent deletion of your Vittam account and all business, billing and inventory data. See exactly what is removed and cancel before it is processed.',
    keywords: 'delete Vittam account, remove account data, account deletion request',
    noindex: false,
  },
  {
    path: '/404',
    file: '404.html',
    title: 'Page Not Found – Vittam',
    description:
      'This page does not exist or has moved. Head back to the Vittam home page to explore billing, inventory, reporting and offline features built for your shop.',
    keywords: '',
    noindex: true,
    sitemap: false,
  },
]

/** Routes React Router must handle client-side (everything except the 404 stub). */
export const SPA_ROUTES = ROUTES.filter((r) => r.sitemap !== false).map((r) => r.path)

/**
 * Structured data. SoftwareApplication tells Google this is a downloadable
 * product; Organization + WebSite establish the brand entity and sitelinks.
 */
export function structuredData() {
  return [
    {
      '@context': 'https://schema.org',
      '@type': 'SoftwareApplication',
      name: 'Vittam',
      applicationCategory: 'BusinessApplication',
      applicationSubCategory: 'Billing & Point of Sale Software',
      operatingSystem: 'Windows, Android',
      url: SITE_URL,
      downloadUrl: `${SITE_URL}/#download`,
      installUrl:
        'https://play.google.com/store/apps/details?id=com.vengurlatech.Vittam',
      softwareVersion: '1.0',
      description:
        'Offline-first billing, inventory, table-order and expense management software for Indian kirana stores, supermarkets, cafes and restaurants.',
      inLanguage: 'en-IN',
      featureList: [
        'Fast counter billing',
        'GST-ready invoices',
        'Inventory management with barcode support',
        'QR code table ordering',
        'Reports and analytics',
        'Expense and recurring-expense tracking',
        'Staff accounts and role-based access',
        'Offline-first with automatic cloud sync',
        'Thermal receipt printing',
        'WhatsApp bill sharing',
      ],
      publisher: { '@id': `${SITE_URL}/#organization` },
    },
    {
      '@context': 'https://schema.org',
      '@type': 'Organization',
      '@id': `${SITE_URL}/#organization`,
      name: 'Vengurla Tech',
      alternateName: 'Vittam',
      url: SITE_URL,
      logo: `${SITE_URL}/logo.png`,
      email: 'support@vengurlatech.com',
      telephone: '+91-94222-29951',
      areaServed: 'IN',
      contactPoint: {
        '@type': 'ContactPoint',
        telephone: '+91-94222-29951',
        email: 'support@vengurlatech.com',
        contactType: 'customer support',
        areaServed: 'IN',
        availableLanguage: ['en', 'hi', 'mr'],
      },
    },
    {
      '@context': 'https://schema.org',
      '@type': 'WebSite',
      '@id': `${SITE_URL}/#website`,
      url: SITE_URL,
      name: SITE_NAME,
      publisher: { '@id': `${SITE_URL}/#organization` },
      inLanguage: 'en-IN',
    },
    {
      // Built from the same FAQS array the page renders — Google requires the
      // schema answers to match visible copy, so they share one source.
      '@context': 'https://schema.org',
      '@type': 'FAQPage',
      '@id': `${SITE_URL}/#faq`,
      mainEntity: FAQS.map(({ q, a }) => ({
        '@type': 'Question',
        name: q,
        acceptedAnswer: { '@type': 'Answer', text: a },
      })),
    },
    {
      // Mirrors the "How It Works" section, and is eligible for the how-to
      // treatment on mobile results.
      '@context': 'https://schema.org',
      '@type': 'HowTo',
      '@id': `${SITE_URL}/#howto`,
      name: 'How to set up billing for your shop with Vittam',
      description:
        'Get a shop billing from scratch: create the store profile, start issuing bills, then track revenue and expenses.',
      totalTime: 'PT5M',
      supply: [],
      tool: [{ '@type': 'HowToTool', name: 'A Windows PC or Android phone' }],
      step: STEPS.map((s, i) => ({
        '@type': 'HowToStep',
        position: i + 1,
        name: s.title,
        text: s.desc,
        url: `${SITE_URL}/#how-it-works`,
      })),
    },
  ]
}

/**
 * Breadcrumbs for sub-pages. The home page is its own root, so it gets none —
 * a single-item trail carries no information and Google ignores it.
 */
export function breadcrumbs(route) {
  if (route.path === '/' || route.sitemap === false) return null

  return {
    '@context': 'https://schema.org',
    '@type': 'BreadcrumbList',
    itemListElement: [
      { '@type': 'ListItem', position: 1, name: 'Home', item: `${SITE_URL}/` },
      {
        '@type': 'ListItem',
        position: 2,
        name: route.breadcrumb || route.title.split(/[–—|]/)[0].trim(),
        item: `${SITE_URL}${route.path}`,
      },
    ],
  }
}
