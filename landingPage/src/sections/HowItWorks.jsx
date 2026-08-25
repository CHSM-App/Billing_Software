import React from 'react'
import { Clock } from 'lucide-react'
import { STEPS } from '../data/steps'

export default function HowItWorks() {
  return (
    <section
      id="how-it-works"
      className="py-24 px-6"
      style={{ background: 'linear-gradient(180deg, #f8f9ff 0%, #eef2ff 100%)' }}
    >
      <div className="max-w-4xl mx-auto">

        {/* Heading */}
        <div className="text-center mb-16">
          <span className="badge mb-4">
            <Clock size={11} />
            Getting Started
          </span>
          <h2 className="font-display text-4xl font-extrabold text-navy-900 mb-4">
            Up and running in minutes
          </h2>
          <p className="text-slate-500 max-w-sm mx-auto leading-relaxed">
            Designed for non-technical shop owners. No manual needed.
          </p>
        </div>

        {/* Steps */}
        <div className="grid md:grid-cols-3 gap-10 relative">
          {STEPS.map((step, i) => (
            <div key={i} className="flex flex-col items-center text-center relative">

              {/* Connector line between steps */}
              {i < 2 && (
                <div
                  className="hidden md:block absolute top-8 left-[58%] right-[-42%] h-px"
                  style={{
                    background: 'linear-gradient(90deg, rgba(0,229,192,0.45), rgba(0,229,192,0.08))',
                  }}
                />
              )}

              {/* Number badge */}
              <div
                className="w-16 h-16 rounded-2xl flex items-center justify-center mb-5
                           font-display font-extrabold text-xl relative z-10"
                style={{
                  background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 100%)',
                  color: '#00e5c0',
                }}
              >
                {step.num}
              </div>

              <h3 className="font-display font-bold text-navy-900 text-lg mb-2">
                {step.title}
              </h3>
              <p className="text-sm text-slate-500 leading-relaxed">{step.desc}</p>
            </div>
          ))}
        </div>
      </div>
    </section>
  )
}
