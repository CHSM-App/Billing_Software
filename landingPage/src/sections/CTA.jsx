import React from 'react'
import { DownloadButtons } from '../components/DownloadButtons'

export default function CTA() {
  return (
    <section
      id="download"
      className="py-24 px-6 relative overflow-hidden"
      style={{
        background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 55%, #0d2d5e 100%)',
      }}
    >
      {/* Glow */}
      <div
        className="absolute inset-0 pointer-events-none"
        style={{
          background:
            'radial-gradient(ellipse 50% 60% at 80% 50%, rgba(0,229,192,0.09), transparent)',
        }}
      />

      <div className="max-w-3xl mx-auto text-center relative z-10">
        <h2
          className="font-display text-4xl lg:text-5xl font-extrabold text-white mb-5 leading-tight"
        >
          Ready to simplify<br />your billing?
        </h2>
        <p className="text-white/60 text-base lg:text-lg leading-relaxed max-w-xl mx-auto mb-10">
          Billing software built for shopkeepers. Setup takes under 5 minutes, and
          your billing keeps working even when the internet does not.
        </p>
        {/* Buttons – centred */}
        <div className="flex flex-wrap justify-center gap-3">
          {/* Windows */}
          <a
            href="https://github.com/CHSM-App/Billing_Software/releases/latest/download/VittamSetup.exe"
            className="btn-teal inline-flex items-center gap-3 px-6 py-4 rounded-2xl text-sm font-bold"
          >
            <svg className="w-5 h-5 flex-shrink-0" viewBox="0 0 24 24" fill="currentColor">
              <path d="M3 12V6.75l6-1.32v6.57H3zm0 .5h6v6.42L3 17.42V12.5zm6.75-7.45L21 3v9H9.75V5.05zm0 7.95H21v9L9.75 19.26V13z"/>
            </svg>
            <span className="flex flex-col text-left leading-tight">
              <span className="text-[10px] font-normal opacity-60 -mb-0.5">Download for</span>
              <span>Windows</span>
            </span>
          </a>

          {/* Play Store */}
          <a
            href="https://play.google.com/store/apps/details?id=com.vengurlatech.Vittam"
            target="_blank"
            rel="noopener noreferrer"
            className="btn-teal inline-flex items-center gap-3 px-6 py-4 rounded-2xl text-sm font-bold"
          >
            <svg className="w-5 h-5 flex-shrink-0" viewBox="0 0 24 24" fill="currentColor">
              <path d="M3.18 23.76c.3.17.64.2.96.1l11.2-11.2-2.56-2.56L3.18 23.76zM20.5 10.2l-2.46-1.4-2.86 2.86 2.86 2.86 2.48-1.42A1.5 1.5 0 0 0 20.5 10.2zM2.01 1.05A1.5 1.5 0 0 0 2 1.5v21a1.5 1.5 0 0 0 .01.45l11.73-11.73L2.01 1.05zM4.14.14A1.5 1.5 0 0 0 3.18.24l11.6 11.6 2.56-2.56L4.14.14z"/>
            </svg>
            <span className="flex flex-col text-left leading-tight">
              <span className="text-[10px] font-normal opacity-60 -mb-0.5">Get it on</span>
              <span>Google Play</span>
            </span>
          </a>
        </div>

        <p className="text-white/25 text-xs mt-8">
          Windows and Android · Free for 1 month · No card needed to start
        </p>
      </div>
    </section>
  )
}
