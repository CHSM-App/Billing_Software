import React from 'react'
import logoSrc from '../images/logo.png'

export default function Logo({ size = 36 }) {
  return (
    <div className="flex items-center select-none">
      <img
        src={logoSrc}
        alt="Vittam"
        style={{ height: size }}
        className="object-contain"
      />
    </div>
  )
}
