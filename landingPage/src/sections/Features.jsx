import React from 'react'
import {
  Zap, Package, Coffee, BarChart2, TrendingUp,
  Users, WifiOff, Printer, MessageCircle,
} from 'lucide-react'

const FEATURES = [
  {
    icon: <Zap size={20} />,
    title: 'Fast GST Billing',
    desc: 'Create GST invoices in seconds. Search an item, set the quantity, pick the payment mode, and the bill is ready — built for busy counters.',
  },
  {
    icon: <Package size={20} />,
    title: 'Inventory Management',
    desc: 'Add items, set categories and prices, and scan barcodes to find products instantly. Know what is running low before your customer asks for it.',
  },
  {
    icon: <Coffee size={20} />,
    title: 'Restaurant Table Billing',
    desc: 'Let customers scan a QR code, browse the menu, and order from their table. Orders go straight to the kitchen and sync with the cashier’s billing system for seamless restaurant billing.',
  },
  {
    icon: <BarChart2 size={20} />,
    title: 'Sales & Business Reports',
    desc: "See today's sales, payment-mode splits and expense summaries in one screen. Know your daily numbers without opening a single register.",
  },
  {
    icon: <TrendingUp size={20} />,
    title: 'Expense Management',
    desc: 'Log one-off and recurring expenses by category — rent, salary, electricity, supplies. At month end you know exactly where the money went.',
  },
  {
    icon: <Users size={20} />,
    title: 'Staff & Cashier Roles',
    desc: 'Add cashiers and give them billing access only. Sales, expenses and reports stay visible to the owner alone.',
  },
  {
    icon: <WifiOff size={20} />,
    title: 'Offline Billing',
    desc: 'Network gone? Billing, item search and printing keep working. Every bill is saved on the device and syncs on its own the moment you are back online.',
  },
  {
    icon: <Printer size={20} />,
    title: 'Thermal Printer Receipts',
    desc: 'Connect a standard thermal printer and print a clean receipt with every bill. Reprint any old bill whenever a customer asks.',
  },
  {
    icon: <MessageCircle size={20} />,
    title: 'WhatsApp Bill Sharing',
    desc: 'Send the bill straight to the customer on WhatsApp. No paper, no lost receipts, and the customer keeps a permanent copy.',
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
