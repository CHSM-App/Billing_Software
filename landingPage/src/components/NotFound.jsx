import React from 'react'
import { Link } from 'react-router-dom'
import { Home, LifeBuoy, Download } from 'lucide-react'
import Logo from './Logo'

const DESTINATIONS = [
  { to: '/',      icon: <Home size={18} />,      label: 'Home',        desc: 'Back to the Vittam home page' },
  { to: '/#download', icon: <Download size={18} />, label: 'Download',   desc: 'Get Vittam for Windows or Android' },
  { to: '/help',  icon: <LifeBuoy size={18} />,  label: 'Help Center', desc: 'Setup guides and support' },
]

export default function NotFound() {
  return (
    <div className="min-h-screen flex flex-col" style={{ background: '#0d1b3e' }}>
      <header className="px-6 py-6">
        <Link to="/" aria-label="Vittam home">
          <Logo size={40} />
        </Link>
      </header>

      <main className="flex-1 flex items-center justify-center px-6 py-16">
        <div className="max-w-lg w-full text-center">
          <p className="font-mono text-sm tracking-widest mb-4" style={{ color: '#00e5c0' }}>
            ERROR 404
          </p>

          <h1 className="font-display text-4xl lg:text-5xl font-extrabold text-white mb-4 leading-tight">
            This page went missing
          </h1>

          <p className="text-white/50 leading-relaxed mb-10">
            The link you followed is broken, or the page has moved. Nothing is wrong with
            your account or your data &mdash; pick a destination below to carry on.
          </p>

          <div className="space-y-3 text-left">
            {DESTINATIONS.map(({ to, icon, label, desc }) => (
              <Link
                key={to}
                to={to}
                className="flex items-center gap-4 rounded-2xl px-5 py-4 transition-colors"
                style={{
                  background: 'rgba(255,255,255,0.05)',
                  border: '1px solid rgba(255,255,255,0.08)',
                }}
              >
                <span
                  className="w-10 h-10 rounded-xl flex items-center justify-center flex-shrink-0"
                  style={{ background: 'rgba(0,229,192,0.12)', color: '#00e5c0' }}
                >
                  {icon}
                </span>
                <span>
                  <span className="block font-display font-bold text-white text-sm">{label}</span>
                  <span className="block text-xs text-white/40 mt-0.5">{desc}</span>
                </span>
              </Link>
            ))}
          </div>

          <p className="text-xs text-white/25 mt-10">
            Still stuck? Email{' '}
            <a href="mailto:support@vengurlatech.com" className="text-white/45 hover:text-white/70">
              support@vengurlatech.com
            </a>
          </p>
        </div>
      </main>
    </div>
  )
}
