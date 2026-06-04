import React from 'react'
import { Store, ShoppingBag, Coffee, Receipt, ArrowRight } from 'lucide-react'

const SEGMENTS = [
  {
    icon: <Store size={26} />,
    title: 'Kirana & Retail Shops',
    desc: 'Fast counter billing with full inventory control for the items you sell every day.',
  },
  {
    icon: <ShoppingBag size={26} />,
    title: 'Small Supermarkets',
    desc: 'Manage a large catalogue with categories, barcodes, staff, and detailed reports.',
  },
  {
    icon: <Coffee size={26} />,
    title: 'Cafes & QSR',
    desc: 'Counter billing with quick turnaround designed for high-footfall food businesses.',
  },
  {
    icon: <Receipt size={26} />,
    title: 'Restaurants',
    desc: 'Table billing, per-table orders, and flexible checkout for dine-in operations.',
  },
]

export default function WhoItsFor() {
  return (
    <section id="who" className="py-24 px-6 bg-slate-50">
      <div className="max-w-6xl mx-auto">
        <div className="grid lg:grid-cols-2 gap-16 items-center">

          {/* Left copy */}
          <div>
            <span className="badge mb-5">
              <ShoppingBag size={11} />
              Who It's For
            </span>
            <h2 className="font-display text-4xl font-extrabold text-navy-900 mb-4 leading-tight">
              Built for every kind<br /> of small business
            </h2>
            <p className="text-slate-500 leading-relaxed mb-8 max-w-md">
              Whether you run a neighbourhood kirana store, a busy café, or a restaurant
              with multiple tables — BillMate adapts to your exact workflow, not the other
              way around.
            </p>
            <a
              href="#download"
              className="btn-teal inline-flex items-center gap-2 px-6 py-3.5 rounded-2xl
                         text-sm font-bold"
            >
              Get Started Free
              <ArrowRight size={15} />
            </a>
          </div>

          {/* Right cards grid */}
          <div className="grid grid-cols-2 gap-4">
            {SEGMENTS.map((seg, i) => (
              <div
                key={i}
                className="glass rounded-2xl p-5 card-hover cursor-default"
              >
                <div
                  className="w-12 h-12 rounded-xl flex items-center justify-center mb-3 text-teal"
                  style={{
                    background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 100%)',
                  }}
                >
                  {seg.icon}
                </div>
                <h3 className="font-display font-semibold text-navy-900 text-sm mb-1.5">
                  {seg.title}
                </h3>
                <p className="text-xs text-slate-500 leading-relaxed">{seg.desc}</p>
              </div>
            ))}
          </div>
        </div>
      </div>
    </section>
  )
}
