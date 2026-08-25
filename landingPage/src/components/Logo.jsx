import React from 'react'

/**
 * Served from public/ rather than imported from src/images so the URL stays
 * stable (favicon, manifest and structured data all point at /logo.png) and so
 * the 512px file is used instead of the 2400px, 2.9 MB original.
 *
 * `priority` marks the above-the-fold navbar copy: it loads eagerly and hints
 * high fetch priority, since it is part of the first paint. Every other copy
 * (footer, 404) is below the fold and lazy-loads instead. Explicit width/height
 * on both reserve layout space so the logo cannot shift content (CLS).
 */
export default function Logo({ size = 36, priority = false }) {
  return (
    <div className="flex items-center select-none">
      <img
        src="/logo.png"
        alt="Vittam billing software logo"
        width={size}
        height={size}
        style={{ height: size, width: 'auto' }}
        className="object-contain"
        loading={priority ? 'eager' : 'lazy'}
        fetchpriority={priority ? 'high' : undefined}
        decoding={priority ? 'sync' : 'async'}
      />
    </div>
  )
}
