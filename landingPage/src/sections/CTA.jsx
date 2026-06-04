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
        <p className="text-lg text-white/50 mb-10 leading-relaxed">
          Join hundreds of shop owners who replaced paper registers with BillMate.
          Setup takes under 5 minutes.
        </p>

        {/* Buttons – centred */}
        <div className="flex flex-wrap justify-center gap-3">
          {/* Windows */}
          <a
            href="/downloads/BillMate-windows.zip"
            download
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

          {/* Android */}
          <a
            href="/downloads/BillMate.apk"
            download
            className="btn-teal inline-flex items-center gap-3 px-6 py-4 rounded-2xl text-sm font-bold"
          >
            <svg className="w-5 h-5 flex-shrink-0" viewBox="0 0 24 24" fill="currentColor">
              <path d="M6.18 15.64a2.18 2.18 0 0 1-2.18-2.18V9.54a2.18 2.18 0 0 1 4.36 0v3.92a2.18 2.18 0 0 1-2.18 2.18m11.64 0a2.18 2.18 0 0 1-2.18-2.18V9.54a2.18 2.18 0 0 1 4.36 0v3.92a2.18 2.18 0 0 1-2.18 2.18M3.64 7.27a.91.91 0 0 1-.91-.91V4.18a.91.91 0 0 1 1.82 0v2.18a.91.91 0 0 1-.91.91m16.72 0a.91.91 0 0 1-.91-.91V4.18a.91.91 0 0 1 1.82 0v2.18a.91.91 0 0 1-.91.91M12 2.73a9.27 9.27 0 0 0-9.27 9.27v5.45a1.09 1.09 0 0 0 1.09 1.09h16.36a1.09 1.09 0 0 0 1.09-1.09V12A9.27 9.27 0 0 0 12 2.73z"/>
            </svg>
            <span className="flex flex-col text-left leading-tight">
              <span className="text-[10px] font-normal opacity-60 -mb-0.5">Download</span>
              <span>Android APK</span>
            </span>
          </a>

          {/* Web */}
          <a
            href="https://app.billmate.in"
            target="_blank"
            rel="noopener noreferrer"
            className="btn-outline-white inline-flex items-center gap-3 px-6 py-4 rounded-2xl text-sm font-semibold"
          >
            <svg className="w-5 h-5 flex-shrink-0" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2">
              <circle cx="12" cy="12" r="10"/>
              <path d="M2 12h20M12 2a15.3 15.3 0 0 1 4 10 15.3 15.3 0 0 1-4 10 15.3 15.3 0 0 1-4-10 15.3 15.3 0 0 1 4-10z"/>
            </svg>
            <span className="flex flex-col text-left leading-tight">
              <span className="text-[10px] font-normal opacity-50 -mb-0.5">Open in browser</span>
              <span>Web App</span>
            </span>
          </a>
        </div>

        <p className="text-white/25 text-xs mt-8">
          Available on Windows, Android, and Web · No credit card required
        </p>
      </div>
    </section>
  )
}
