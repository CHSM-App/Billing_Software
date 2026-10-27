import React, { useEffect } from 'react'
import { Link } from 'react-router-dom'
import { marked } from 'marked'
import { ArrowLeft, Shield } from 'lucide-react'
import Logo from './Logo'

// The documents themselves live in docs/legal/ — one source for this site, the
// advocate's review and the app's "Details" links. Edit the .md, not this file.
import termsMd from '../../../docs/legal/TERMS_OF_SERVICE.md?raw'
import aupMd from '../../../docs/legal/ACCEPTABLE_USE_POLICY.md?raw'
import orderingMd from '../../../docs/legal/CUSTOMER_ORDERING_TERMS.md?raw'

export const LEGAL_DOCS = {
  terms: { title: 'Terms of Service', md: termsMd },
  'acceptable-use': { title: 'Acceptable Use Policy', md: aupMd },
  'ordering-terms': { title: 'Customer Ordering Terms', md: orderingMd },
}

// Markdown → HTML at render time, so the prerendered page carries the full text.
// The input is our own reviewed document, never user content.
const render = (md) => marked.parse(md.replace(/^# .*\r?\n/, ''), { async: false })

export default function LegalPage({ doc }) {
  const { title, md } = LEGAL_DOCS[doc]
  useEffect(() => { window.scrollTo(0, 0) }, [doc])

  return (
    <div className="min-h-screen bg-slate-50">
      {/* Top bar — same as the Privacy Policy page */}
      <div className="bg-[#143b9f]">
        <div className="max-w-4xl mx-auto flex items-center justify-between">
          <Logo size={60} />
          <Link
            to="/"
            className="flex items-center gap-2 text-sm text-white/50 hover:text-white transition-colors"
          >
            <ArrowLeft size={15} />
            Back to Home
          </Link>
        </div>
      </div>

      <div
        className="px-6 py-14 text-center"
        style={{ background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 100%)' }}
      >
        <div
          className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full text-xs font-semibold mb-5"
          style={{ background: 'rgba(0,229,192,0.14)', color: '#00e5c0' }}
        >
          <Shield size={11} />
          Legal Document
        </div>
        <h1 className="font-display text-4xl font-extrabold text-white">{title}</h1>
      </div>

      <article
        className="legal max-w-4xl mx-auto px-6 py-14"
        dangerouslySetInnerHTML={{ __html: render(md) }}
      />

      {/* Footer nav — same as the Privacy Policy page */}
      <div className="max-w-4xl mx-auto px-6 pb-14">
        <div className="flex flex-wrap justify-center gap-6 pt-8 border-t border-slate-200 text-xs text-slate-400">
          <Link to="/" className="hover:text-navy-900 transition-colors">Home</Link>
          <Link to="/terms" className="hover:text-navy-900 transition-colors">Terms of Service</Link>
          <Link to="/acceptable-use" className="hover:text-navy-900 transition-colors">Acceptable Use</Link>
          <Link to="/privacy" className="hover:text-navy-900 transition-colors">Privacy Policy</Link>
          <a href="mailto:support@vengurlatech.com" className="hover:text-navy-900 transition-colors">Contact</a>
        </div>
      </div>
    </div>
  )
}
