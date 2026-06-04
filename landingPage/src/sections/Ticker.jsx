import React from 'react'

const ITEMS = [
  'Fast Billing', 'Offline Support', 'Table Management', 'Thermal Printing',
  'Inventory Control', 'Expense Tracking', 'WhatsApp Bills', 'Staff Roles',
  'Daily Reports', 'Barcode Ready', 'GST Ready', 'Cloud Sync',
]

export default function Ticker() {
  return (
    <div className="py-4 overflow-hidden bg-navy-900" aria-hidden="true">
      <div className="ticker-wrap">
        <div className="ticker-track">
          {/* Duplicate array so the loop looks seamless */}
          {[...ITEMS, ...ITEMS].map((item, i) => (
            <div key={i} className="flex items-center gap-6 px-4">
              <span className="text-sm font-medium whitespace-nowrap text-white/65">{item}</span>
              <span className="w-1.5 h-1.5 rounded-full bg-teal/60 flex-shrink-0" />
            </div>
          ))}
        </div>
      </div>
    </div>
  )
}
