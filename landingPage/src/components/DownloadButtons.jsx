import React from 'react'
import { Monitor, Smartphone, Globe } from 'lucide-react'

/**
 * Drop your installer files into the `public/downloads/` folder:
 *   public/downloads/Vittam-Setup.exe   → Windows installer
 *   public/downloads/Vittam.apk         → Android APK
 *
 * The web app link can be an external URL — update WEB_URL below.
 */
const WIN_URL = '/downloads/Vittam-windows.zip'
const APK_URL = '/downloads/Vittam.apk'
const WEB_URL = 'https://app.Vittam.in'   // ← update to your web app URL

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

      {/* Android APK */}
      <a
        href={APK_URL}
        download
        className={`${base} ${pad} btn-navy`}
      >
        <Smartphone size={size === 'lg' ? 20 : 18} className="flex-shrink-0" />
        <span className="flex flex-col text-left leading-tight">
          <span className="text-[10px] opacity-50 font-normal -mb-0.5">Download</span>
          <span>Android APK</span>
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
