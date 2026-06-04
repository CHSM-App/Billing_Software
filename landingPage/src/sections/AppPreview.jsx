import React from 'react'
import { Receipt, Package, BarChart2, Zap } from 'lucide-react'

/* ── Small screen card ───────────────────────────── */
function ScreenCard({ label, tag, icon, children }) {
  return (
    <div
      className="rounded-2xl overflow-hidden"
      style={{
        background: 'rgba(255,255,255,0.05)',
        border: '1px solid rgba(255,255,255,0.08)',
      }}
    >
      {/* Header */}
      <div
        className="flex items-center justify-between px-4 py-3"
        style={{ borderBottom: '1px solid rgba(255,255,255,0.06)' }}
      >
        <div className="flex items-center gap-2 text-white/55">
          {icon}
          <span className="text-xs font-medium">{label}</span>
        </div>
        <span
          className="text-[10px] px-2 py-0.5 rounded-full font-semibold"
          style={{ background: 'rgba(0,229,192,0.14)', color: '#00e5c0' }}
        >
          {tag}
        </span>
      </div>
      <div className="p-4">{children}</div>
    </div>
  )
}

export default function AppPreview() {
  return (
    <section
      className="py-24 px-6 relative overflow-hidden"
      style={{ background: '#0d1b3e' }}
    >
      {/* Subtle radial glow */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            'radial-gradient(ellipse 55% 50% at 50% 50%, rgba(0,229,192,0.07), transparent)',
        }}
      />

      <div className="max-w-6xl mx-auto relative z-10">
        {/* Heading */}
        <div className="text-center mb-14">
          <span
            className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full text-xs font-semibold mb-4"
            style={{ background: 'rgba(0,229,192,0.12)', color: '#00e5c0' }}
          >
            <Zap size={11} />
            App Preview
          </span>
          <h2 className="font-display text-4xl font-extrabold text-white mb-3">
            Designed for speed at the counter
          </h2>
          <p className="max-w-md mx-auto text-white/45 leading-relaxed">
            Every screen is optimised for fast tapping, minimal reading, and confident billing —
            even during the busiest rush hours.
          </p>
        </div>

        {/* Three preview cards */}
        <div className="grid md:grid-cols-3 gap-5">

          {/* Billing */}
          <ScreenCard label="Billing Screen" tag="Items & Order" icon={<Receipt size={13} />}>
            <div className="space-y-2">
              {[
                { n: 'Kurkure 90g',       p: '₹20' },
                { n: 'Amul Milk 500ml',   p: '₹28' },
                { n: 'Taj Mahal Tea 250g', p: '₹145' },
                { n: 'Parle-G 800g',      p: '₹85' },
              ].map((item, i) => (
                <div
                  key={i}
                  className="flex items-center justify-between px-3 py-2 rounded-xl"
                  style={{ background: 'rgba(255,255,255,0.05)' }}
                >
                  <span className="text-xs text-white/65">{item.n}</span>
                  <div className="flex items-center gap-2">
                    <span className="text-xs font-mono text-teal">{item.p}</span>
                    <div
                      className="w-6 h-6 rounded-lg flex items-center justify-center
                                 text-xs font-bold text-navy-900"
                      style={{ background: '#00e5c0' }}
                    >
                      +
                    </div>
                  </div>
                </div>
              ))}
            </div>
          </ScreenCard>

          {/* Items */}
          <ScreenCard label="Items / Menu" tag="Catalogue" icon={<Package size={13} />}>
            <div className="grid grid-cols-2 gap-2">
              {[
                { n: 'Dove Shampoo', cat: 'Personal',  p: '₹165' },
                { n: 'Chana Dal 1kg', cat: 'Grocery',  p: '₹100' },
                { n: 'Saffola Oil 1L', cat: 'Grocery', p: '₹180' },
                { n: 'Eclairs Toffee', cat: 'Snacks',  p: '₹10' },
              ].map((item, i) => (
                <div
                  key={i}
                  className="rounded-xl p-3"
                  style={{ background: 'rgba(255,255,255,0.05)' }}
                >
                  <p className="text-xs font-medium text-white/80 mb-0.5">{item.n}</p>
                  <p className="text-[10px] text-teal/60">{item.cat}</p>
                  <p className="text-sm font-bold text-white mt-1">{item.p}</p>
                </div>
              ))}
            </div>
          </ScreenCard>

          {/* Reports */}
          <ScreenCard label="Reports" tag="Analytics" icon={<BarChart2 size={13} />}>
            <div className="space-y-3">
              {/* Revenue card */}
              <div
                className="rounded-xl p-3"
                style={{
                  background: 'linear-gradient(135deg, rgba(0,229,192,0.18), rgba(0,229,192,0.04))',
                }}
              >
                <p className="text-[10px] text-white/45 mb-1">Revenue</p>
                <p className="text-xl font-extrabold font-display text-teal">₹4,948</p>
                <p className="text-[10px] text-white/35 mt-0.5">8 bills this month</p>
              </div>

              {/* Bar chart */}
              <div
                className="rounded-xl p-3"
                style={{ background: 'rgba(255,255,255,0.04)' }}
              >
                <p className="text-[10px] text-white/45 mb-2">Daily Breakdown</p>
                <div className="flex items-end gap-1 h-11">
                  {[55, 38, 80, 58, 90, 68, 100].map((h, i) => (
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
          </ScreenCard>
        </div>
      </div>
    </section>
  )
}
