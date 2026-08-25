import React from 'react'
import { HelpCircle } from 'lucide-react'
import { FAQS } from '../data/faqs'

/**
 * Plain <details> rather than useState: the answers are open-able in the
 * prerendered HTML before hydration, and every answer stays in the DOM for
 * crawlers. src/seo.js turns the same FAQS array into FAQPage structured data.
 */

export default function FAQ() {
  return (
    <section id="faq" className="py-24 px-6 bg-slate-50">
      <div className="max-w-3xl mx-auto">
        <div className="text-center mb-14">
          <span className="badge mb-4">
            <HelpCircle size={11} />
            Common Questions
          </span>
          <h2 className="font-display text-4xl font-extrabold text-navy-900 mb-4">
            Billing software questions, answered
          </h2>
          <p className="text-slate-500 max-w-md mx-auto leading-relaxed">
            Everything shop owners ask us before switching from a paper register.
          </p>
        </div>

        <div className="space-y-3">
          {FAQS.map(({ q, a }) => (
            <details
              key={q}
              className="group glass rounded-2xl px-6 py-5 [&[open]]:shadow-sm transition-shadow"
            >
              <summary className="flex items-start justify-between gap-4 cursor-pointer list-none">
                <h3 className="font-display font-semibold text-navy-900 text-[15px] leading-snug">
                  {q}
                </h3>
                <span
                  className="mt-0.5 flex-shrink-0 w-5 h-5 rounded-full flex items-center justify-center
                             text-teal-dim text-lg leading-none transition-transform group-open:rotate-45"
                  style={{ background: 'rgba(0,229,192,0.12)' }}
                  aria-hidden="true"
                >
                  +
                </span>
              </summary>
              <p className="text-sm text-slate-500 leading-relaxed mt-3 pr-9">{a}</p>
            </details>
          ))}
        </div>
      </div>
    </section>
  )
}
