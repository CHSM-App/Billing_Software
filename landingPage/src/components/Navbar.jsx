import React, { useState, useEffect } from 'react'
import { Menu, X } from 'lucide-react'
import Logo from './Logo'

const LINKS = [
  { label: 'Features',    href: '#features' },
  { label: 'How It Works', href: '#how-it-works' },
  { label: 'Who It\'s For', href: '#who' },
  { label: 'Download',    href: '#download' },
]

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [open, setOpen] = useState(false)

  useEffect(() => {
    const handler = () => setScrolled(window.scrollY > 24)
    window.addEventListener('scroll', handler)
    return () => window.removeEventListener('scroll', handler)
  }, [])

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled ? 'nav-blur shadow-sm py-3' : 'py-5'
      }`}
    >
      <div className="max-w-6xl mx-auto px-6 flex items-center justify-between">
        <Logo size={36} />

        {/* Desktop links */}
        <div className="hidden md:flex items-center gap-7">
          {LINKS.map(({ label, href }) => (
            <a
              key={label}
              href={href}
              className="text-sm font-medium text-slate-500 hover:text-navy-900 transition-colors"
            >
              {label}
            </a>
          ))}
        </div>

        {/* Desktop CTA */}
        <a
          href="#download"
          className="hidden md:inline-flex btn-navy text-sm font-semibold px-5 py-2.5 rounded-xl"
        >
          Download Free
        </a>

        {/* Mobile toggle */}
        <button
          className="md:hidden p-2 rounded-lg text-navy-900 hover:bg-slate-100 transition-colors"
          onClick={() => setOpen(!open)}
          aria-label="Toggle menu"
        >
          {open ? <X size={22} /> : <Menu size={22} />}
        </button>
      </div>

      {/* Mobile drawer */}
      {open && (
        <div className="md:hidden mx-4 mt-2 glass rounded-2xl p-4 space-y-1 shadow-lg">
          {LINKS.map(({ label, href }) => (
            <a
              key={label}
              href={href}
              onClick={() => setOpen(false)}
              className="block text-sm font-medium text-navy-900 px-3 py-2.5 rounded-xl hover:bg-slate-50 transition-colors"
            >
              {label}
            </a>
          ))}
          <a
            href="#download"
            onClick={() => setOpen(false)}
            className="block btn-teal text-center text-sm font-bold mt-2 px-4 py-3 rounded-xl"
          >
            Download Free
          </a>
        </div>
      )}
    </nav>
  )
}
