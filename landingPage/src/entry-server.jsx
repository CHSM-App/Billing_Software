/**
 * SSR entry — used only at build time by prerender.js to turn each route into
 * static HTML. Nothing here ships to the browser.
 *
 * Every browser API in this app is already confined to useEffect (which does not
 * run during renderToString), so the components render server-side unchanged.
 */
import React from 'react'
import { renderToString } from 'react-dom/server'
// v7 dropped the `react-router-dom/server` subpath — StaticRouter now comes
// from the package root.
import { StaticRouter } from 'react-router-dom'
import App from './App.jsx'

export function render(url) {
  return renderToString(
    <StaticRouter location={url}>
      <App />
    </StaticRouter>
  )
}
