import React from 'react'
import ReactDOM from 'react-dom/client'
import { BrowserRouter } from 'react-router-dom'
import App from './App.jsx'
import './index.css'

const root = document.getElementById('root')

const tree = (
  <React.StrictMode>
    <BrowserRouter>
      <App />
    </BrowserRouter>
  </React.StrictMode>
)

// Production HTML is prerendered (see prerender.js), so attach to the existing
// markup instead of throwing it away — that keeps the crawler-visible content on
// screen through first paint.
//
// Test firstElementChild, not hasChildNodes(): the dev server still serves the
// literal <!--ssr-outlet--> comment inside #root, and a comment node is enough to
// make hasChildNodes() true — which would hydrate against empty markup in dev.
if (root.firstElementChild) {
  ReactDOM.hydrateRoot(root, tree)
} else {
  ReactDOM.createRoot(root).render(tree)
}
