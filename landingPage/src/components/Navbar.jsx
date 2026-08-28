import React, { useState, useEffect } from 'react'
import { Menu, X } from 'lucide-react'
import Logo from './Logo'
import BookDemoModal from './BookDemoModal'

const LINKS = [
  { label: 'Features',    href: '#features' },
  { label: 'How It Works', href: '#how-it-works' },
  { label: 'Who It\'s For', href: '#who' },
  { label: 'FAQ',         href: '#faq' },
  { label: 'Download',    href: '#download' },
]

export default function Navbar() {
  const [scrolled, setScrolled] = useState(false)
  const [open, setOpen] = useState(false)
  const [demoOpen, setDemoOpen] = useState(false)

  useEffect(() => {
    const handler = () => setScrolled(window.scrollY > 24)
    window.addEventListener('scroll', handler)
    return () => window.removeEventListener('scroll', handler)
  }, [])

  return (
    <nav
      className={`fixed top-0 left-0 right-0 z-50 transition-all duration-300 ${
        scrolled ? 'nav-blur shadow-sm ' : 'py-2'
      }`}
    >
      <div className="max-w-6xl mx-auto px-6 flex items-center justify-between">
        <Logo size={50} priority />

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
        <button
          onClick={() => setDemoOpen(true)}
          className="hidden md:inline-flex btn-navy text-sm font-semibold px-5 py-2.5 rounded-xl"
        >
          Book Demo
        </button>

        {/* Mobile toggle — min-w/h-12 is 48px, the floor below which mobile
            usability audits flag a target as too small to tap reliably. */}
        <button
          className="md:hidden flex items-center justify-center min-w-12 min-h-12 rounded-lg
                     text-navy-900 hover:bg-slate-100 transition-colors"
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
              className="flex items-center min-h-12 text-base font-medium text-navy-900 px-3
                         rounded-xl hover:bg-slate-50 transition-colors"
            >
              {label}
            </a>
          ))}
          <button
            onClick={() => { setOpen(false); setDemoOpen(true) }}
            className="block w-full btn-teal text-center text-sm font-bold mt-2 px-4 py-3 rounded-xl"
          >
            Book Demo
          </button>
        </div>
      )}

      <BookDemoModal open={demoOpen} onClose={() => setDemoOpen(false)} />
    </nav>
  )
}
