import React from 'react'
import { Zap, WifiOff, ChevronDown } from 'lucide-react'
import { DownloadButtons } from '../components/DownloadButtons'

/* ── Mini billing mockup ─────────────────────────── */
function BillingMockup() {
  const items = [
    { name: 'Maggi Noodles 70g',  price: 14, qty: 2 },
    { name: 'Amul Milk 500ml',    price: 28, qty: 1 },
    { name: 'Lays Chips 26g',     price: 20, qty: 3 },
  ]
  const total = items.reduce((s, i) => s + i.price * i.qty, 0)

  return (
    <div className="rounded-2xl overflow-hidden shadow-screen bg-white">
      {/* Title bar */}
      <div className="h-8 flex items-center px-4 gap-2 bg-navy-900">
        <span className="w-2.5 h-2.5 rounded-full bg-red-400" />
        <span className="w-2.5 h-2.5 rounded-full bg-yellow-400" />
        <span className="w-2.5 h-2.5 rounded-full bg-green-400" />
        <span className="mx-auto text-[11px] font-mono text-white/30">Vittam</span>
      </div>

      {/* Body */}
      <div className="p-4 bg-slate-50 space-y-2">
        <div className="flex justify-between items-center mb-3">
          <span className="text-[11px] font-semibold text-navy-900">Ganesh General Store</span>
          <span className="text-[10px] px-2 py-0.5 rounded-full bg-teal/10 text-teal-dim font-semibold">
            Active Order
          </span>
        </div>

        {items.map((item, i) => (
          <div
            key={i}
            className="flex items-center justify-between bg-white rounded-xl px-3 py-2 border border-black/5"
          >
            <div>
              <p className="text-[11px] font-medium text-navy-900">{item.name}</p>
              <p className="text-[10px] text-slate-400">₹{item.price} × {item.qty}</p>
            </div>
            <span className="text-sm font-bold text-navy-900">₹{item.price * item.qty}</span>
          </div>
        ))}

        {/* Total bar */}
        <div className="rounded-xl px-4 py-3 flex items-center justify-between bg-navy-900 mt-3">
          <div>
            <p className="text-[10px] text-white/40">Total</p>
            <p className="text-lg font-bold text-white font-display">₹{total}.00</p>
          </div>
          <span className="px-4 py-2 rounded-lg text-sm font-bold bg-teal text-navy-900">
            Generate Bill
          </span>
        </div>
      </div>
    </div>
  )
}

/* ── Mini reports mockup ─────────────────────────── */
function ReportsMockup() {
  return (
    <div className="rounded-2xl overflow-hidden shadow-screen bg-white">
      <div className="h-8 flex items-center px-4 gap-2 bg-navy-900">
        <span className="w-2.5 h-2.5 rounded-full bg-red-400" />
        <span className="w-2.5 h-2.5 rounded-full bg-yellow-400" />
        <span className="w-2.5 h-2.5 rounded-full bg-green-400" />
        <span className="mx-auto text-[11px] font-mono text-white/30">Reports</span>
      </div>

      <div className="p-4 bg-slate-50 space-y-2">
        <div className="grid grid-cols-2 gap-2">
          <div className="rounded-xl p-3 bg-gradient-to-br from-navy-900 to-navy-700">
            <p className="text-[10px] text-white/50 mb-1">Revenue</p>
            <p className="text-base font-bold font-display text-teal">₹4,948</p>
            <p className="text-[10px] text-white/30">8 bills</p>
          </div>
          <div className="rounded-xl p-3 bg-red-50">
            <p className="text-[10px] text-red-400 mb-1">Expenses</p>
            <p className="text-base font-bold font-display text-red-700">₹3,000</p>
            <p className="text-[10px] text-red-300">1 category</p>
          </div>
        </div>

        {/* Bar chart mini */}
        <div className="bg-white rounded-xl p-3 border border-black/5">
          <p className="text-[10px] font-semibold text-navy-900 mb-2">Daily Breakdown</p>
          <div className="flex items-end gap-1 h-10">
            {[55, 40, 80, 60, 90, 70, 100].map((h, i) => (
              <div
                key={i}
                className="flex-1 rounded-t-sm"
                style={{
                  height: `${h}%`,
                  background: i === 6 ? '#00e5c0' : 'rgba(0,229,192,0.28)',
                }}
              />
            ))}
          </div>
        </div>
      </div>
    </div>
  )
}

/* ── Hero ────────────────────────────────────────── */
export default function Hero() {
  return (
    <section className="hero-bg relative overflow-clip pt-32 pb-24 px-6" id="home">
      {/* Decorative blobs */}
      <div
        className="absolute top-10 right-0 w-[500px] h-[500px] rounded-full pointer-events-none"
        style={{
          background: 'radial-gradient(circle, rgba(0,229,192,0.12), transparent 65%)',
          filter: 'blur(40px)',
        }}
      />
      <div
        className="absolute -bottom-20 -left-20 w-80 h-80 rounded-full pointer-events-none"
        style={{
          background: 'radial-gradient(circle, rgba(13,27,62,0.08), transparent 65%)',
          filter: 'blur(60px)',
        }}
      />

      <div className="max-w-6xl mx-auto">
        <div className="grid lg:grid-cols-2 gap-14 items-center">

          {/* ── Left ── */}
          <div>
            <span className="badge mb-6 animate-fadeUp delay-100 anim-init">
              <Zap size={11} />
              Built for Indian Small Businesses
            </span>

            <h1
              className="font-display text-5xl lg:text-[3.6rem] font-extrabold leading-[1.08] mb-6
                         animate-fadeUp delay-200 anim-init text-navy-900"
            >
              Smart Billing,<br />
              <span className="text-teal-dark">Zero Hassle</span>
            </h1>

            <p className="text-lg text-slate-500 leading-relaxed mb-8 max-w-lg
                          animate-fadeUp delay-300 anim-init">
              Vittam brings fast billing, inventory management, table orders,
              expense tracking, and offline sync — all in one lightweight app built for
              Indian shopkeepers.
            </p>

            <div className="animate-fadeUp delay-400 anim-init">
              <DownloadButtons size="md" />
            </div>

            {/* Tagline chips */}
            <div className="flex flex-wrap gap-2 mt-8 animate-fadeUp delay-400 anim-init">
              {['Offline-first', 'GST Ready', 'WhatsApp Sharing', 'Thermal Printing'].map(tag => (
                <span
                  key={tag}
                  className="text-xs px-3 py-1.5 rounded-full bg-white border border-slate-200
                             text-slate-500 font-medium shadow-sm"
                >
                  {tag}
                </span>
              ))}
            </div>
          </div>

          {/* ── Right – stacked mockups ── */}
          <div className="relative hidden lg:block">
            {/* Main billing mockup */}
            <div className="relative z-10">
              <BillingMockup />
            </div>

            {/* Reports mockup — offset bottom-right */}
            <div className="absolute -bottom-8 -right-6 w-60 z-20">
              <ReportsMockup />
            </div>

            {/* Floating offline badge */}
            <div className="absolute -left-8 top-16 z-30 glass rounded-2xl px-4 py-3 shadow-teal flex items-center gap-3">
              <WifiOff size={16} className="text-teal-dark flex-shrink-0" />
              <div>
                <p className="text-[11px] font-bold text-navy-900 leading-none">Offline Mode</p>
                <p className="text-[10px] text-slate-400 mt-0.5">Bills continue, sync later</p>
              </div>
            </div>
          </div>
        </div>
      </div>

      {/* Scroll hint */}
      <div className="flex justify-center mt-20">
        <a
          href="#features"
          className="flex flex-col items-center gap-1.5 text-slate-400 hover:text-slate-600
                     transition-colors animate-bounce2"
        >
          <span className="text-xs tracking-wide">Explore features</span>
          <ChevronDown size={17} />
        </a>
      </div>
    </section>
  )
}
