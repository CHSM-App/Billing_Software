import React from 'react'
import { Link } from 'react-router-dom'
import Logo from './Logo'

const LINKS = {
  Product: [
    { label: 'Features',    href: '/#features' },
    { label: 'How It Works', href: '/#how-it-works' },
    { label: 'Download',    href: '/#download' },
    { label: 'Google Play', href: 'https://play.google.com/store/apps/details?id=com.vengurlatech.Vittam' },
  ],
  Support: [
    { label: 'Help Center', href: '/help' },
    { label: 'FAQ',         href: '/#faq' },
  ],
  Legal: [
    { label: 'Privacy Policy', href: '/privacy' },
    { label: 'Delete Account', href: '/delete-account' },
  ],
}

function FooterLink({ href, label }) {
  const cls = "text-white/30 hover:text-white/70 transition-colors"
  if (href.startsWith('/') && !href.startsWith('/#')) {
    return <Link to={href} className={cls}>{label}</Link>
  }
  const isExternal = href.startsWith('http')
  return (
    <a
      href={href}
      className={cls}
      {...(isExternal ? { target: '_blank', rel: 'noopener noreferrer' } : {})}
    >
      {label}
    </a>
  )
}

export default function Footer() {
  return (
    <footer className="px-6 py-14" style={{ background: '#060d1f' }}>
      <div className="max-w-7xl mx-auto">

        {/* Top row */}
        <div className="flex flex-col md:flex-row justify-between gap-10 mb-12">
          {/* Brand blurb */}
          <div className="max-w-xs">
            <Logo size={34} />
            <p className="text-sm mt-4 text-white/35 leading-relaxed">
              A modern billing and business management solution for small shops,
              retailers, and restaurants across India.
            </p>
          </div>

          {/* Link columns */}
          <div className="grid grid-cols-3 md:grid-cols-4 gap-7 text-sm">
            {Object.entries(LINKS).map(([col, items]) => (
              <div key={col}>
                <p className="font-semibold text-white/55 mb-3">{col}</p>
                <ul className="space-y-2">
                  {items.map(item => (
                    <li key={item.label}>
                      <FooterLink href={item.href} label={item.label} />
                    </li>
                  ))}
                </ul>
              </div>
            ))}

            {/* Contact details shown directly */}
            <div>
              <p className="font-semibold text-white/55 mb-3">Contact</p>
              <ul className="space-y-2">
                <li>
                  <a
                    href="tel:+919422229951"
                    className="text-white/30 hover:text-white/70 transition-colors"
                  >
                    +91 94222 29951
                  </a>
                </li>
                <li>
                  <a
                    href="mailto:support@vengurlatech.com"
                    className="text-white/30 hover:text-white/70 transition-colors break-all"
                  >
                    support@vengurlatech.com
                  </a>
                </li>
              </ul>
            </div>
          </div>
        </div>

        {/* Bottom bar */}
        <div
          className="pt-6 flex flex-col md:flex-row items-center justify-between gap-3"
          style={{ borderTop: '1px solid rgba(255,255,255,0.06)' }}
        >
          <p className="text-xs text-white/25">
            © 2026 Vittam. All rights reserved. Made with ♥ for Indian businesses.
          </p>
          <div className="flex items-center gap-2 text-xs text-white/25">
            <span className="w-1.5 h-1.5 rounded-full bg-teal inline-block" />
            All systems operational
          </div>
        </div>
      </div>
    </footer>
  )
}
