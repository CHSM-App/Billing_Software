import React from 'react'
import {
  Zap, Package, Coffee, BarChart2, TrendingUp,
  Users, WifiOff, Printer, MessageCircle,
} from 'lucide-react'

const FEATURES = [
  {
    icon: <Zap size={20} />,
    title: 'Fast Billing',
    desc: 'Generate bills in seconds with a clean counter workflow optimised for speed during busy hours.',
  },
  {
    icon: <Package size={20} />,
    title: 'Inventory Management',
    desc: 'Add, categorise, and manage all your items with barcode-ready product handling across departments.',
  },
  {
    icon: <Coffee size={20} />,
    title: 'Table Billing',
    desc: 'Full restaurant table management — open per-table orders, split bills, and check out flexibly.',
  },
  {
    icon: <BarChart2 size={20} />,
    title: 'Reports & Analytics',
    desc: 'Daily breakdowns, revenue by payment mode, and expense category summaries at a glance.',
  },
  {
    icon: <TrendingUp size={20} />,
    title: 'Expense Tracking',
    desc: 'Log regular and recurring expenses. Know exactly where every rupee is going every month.',
  },
  {
    icon: <Users size={20} />,
    title: 'Staff Management',
    desc: 'Add cashiers, assign roles, and control team access — all managed from the owner account.',
  },
  {
    icon: <WifiOff size={20} />,
    title: 'Offline First',
    desc: 'Keep billing running without internet. Data syncs automatically the moment you are back online.',
  },
  {
    icon: <Printer size={20} />,
    title: 'Thermal Printing',
    desc: 'Connect your thermal printer and generate professional printed receipts instantly on every bill.',
  },
  {
    icon: <MessageCircle size={20} />,
    title: 'WhatsApp Sharing',
    desc: 'Send digital bills directly to customers via WhatsApp — fast, paperless, and professional.',
  },
]

function FeatureCard({ icon, title, desc }) {
  return (
    <div className="glass rounded-2xl p-6 card-hover cursor-default">
      <div className="w-10 h-10 rounded-xl flex items-center justify-center mb-4 text-teal-dim bg-teal/10">
        {icon}
      </div>
      <h3 className="font-display font-semibold text-navy-900 text-[15px] mb-2">{title}</h3>
      <p className="text-sm text-slate-500 leading-relaxed">{desc}</p>
    </div>
  )
}

export default function Features() {
  return (
    <section id="features" className="py-24 px-6">
      <div className="max-w-6xl mx-auto">

        {/* Heading */}
        <div className="text-center mb-14">
          <span className="badge mb-4">Everything You Need</span>
          <h2 className="font-display text-4xl font-extrabold text-navy-900 mb-4">
            A full toolkit for your counter
          </h2>
          <p className="text-slate-500 max-w-md mx-auto leading-relaxed">
            From the first item scanned to the final report at day's end —
            Vittam handles every part of your business day.
          </p>
        </div>

        {/* Grid */}
        <div className="grid sm:grid-cols-2 lg:grid-cols-3 gap-5">
          {FEATURES.map((f, i) => (
            <FeatureCard key={i} {...f} />
          ))}
        </div>
      </div>
    </section>
  )
}
