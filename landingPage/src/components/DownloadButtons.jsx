import React from 'react'
import { Monitor, Globe } from 'lucide-react'

/**
 * Drop your installer files into the `public/downloads/` folder:
 *   public/downloads/Vittam-Setup.exe   → Windows installer
 *
 * The web app link can be an external URL — update WEB_URL below.
 */
const WIN_URL = '/downloads/Vittam-windows.zip'
const WEB_URL = 'https://app.Vittam.in'   // ← update to your web app URL
const PLAY_URL = 'https://play.google.com/store/apps/details?id=com.vengurlatech.Vittam'

export function DownloadButtons({ size = 'md', row = false }) {
  const base =
    'inline-flex items-center gap-3 rounded-2xl font-semibold transition-all cursor-pointer'

  const pad = size === 'lg'
    ? 'px-6 py-4 text-sm'
    : 'px-5 py-3.5 text-sm'

  return (
    <div className={`flex flex-wrap gap-3 ${row ? '' : ''}`}>
      {/* Windows */}
      <a
        href={WIN_URL}
        download
        className={`${base} ${pad} btn-navy`}
      >
        <Monitor size={size === 'lg' ? 20 : 18} className="flex-shrink-0" />
        <span className="flex flex-col text-left leading-tight">
          <span className="text-[10px] opacity-50 font-normal -mb-0.5">Download for</span>
          <span>Windows</span>
        </span>
      </a>

      {/* Play Store */}
      <a
        href={PLAY_URL}
        target="_blank"
        rel="noopener noreferrer"
        className={`${base} ${pad} btn-navy`}
      >
        <svg
          viewBox="0 0 24 24"
          fill="currentColor"
          className="flex-shrink-0"
          style={{ width: size === 'lg' ? 20 : 18, height: size === 'lg' ? 20 : 18 }}
        >
          <path d="M3.18 23.76c.3.17.64.2.96.1l11.2-11.2-2.56-2.56L3.18 23.76zM20.5 10.2l-2.46-1.4-2.86 2.86 2.86 2.86 2.48-1.42A1.5 1.5 0 0 0 20.5 10.2zM2.01 1.05A1.5 1.5 0 0 0 2 1.5v21a1.5 1.5 0 0 0 .01.45l11.73-11.73L2.01 1.05zM4.14.14A1.5 1.5 0 0 0 3.18.24l11.6 11.6 2.56-2.56L4.14.14z"/>
        </svg>
        <span className="flex flex-col text-left leading-tight">
          <span className="text-[10px] opacity-50 font-normal -mb-0.5">Get it on</span>
          <span>Google Play</span>
        </span>
      </a>

      {/* Web App */}
      <a
        href={WEB_URL}
        target="_blank"
        rel="noopener noreferrer"
        className={`${base} ${pad} btn-ghost-teal`}
      >
        <Globe size={size === 'lg' ? 20 : 18} className="flex-shrink-0" />
        <span className="flex flex-col text-left leading-tight">
          <span className="text-[10px] opacity-50 font-normal -mb-0.5">Open in browser</span>
          <span>Web App</span>
        </span>
      </a>
    </div>
  )
}
