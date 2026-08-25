import React from 'react'
import { Routes, Route } from 'react-router-dom'
import Navbar       from './components/Navbar'
import Footer       from './components/Footer'
import Hero         from './sections/Hero'
import Ticker       from './sections/Ticker'
import Features     from './sections/Features'
import HowItWorks   from './sections/HowItWorks'
import WhoItsFor    from './sections/WhoItsFor'
import AppPreview   from './sections/AppPreview'
import FAQ          from './sections/FAQ'
import CTA          from './sections/CTA'
import HelpCenter    from './components/helpcenter'
import PrivacyPolicy  from './components/privacyPolicy'
import DeleteAccount  from './components/DeleteAccount'
import NotFound       from './components/NotFound'

function Landing() {
  return (
    <>
      <Navbar />
      <main>
        <Hero />
        <Ticker />
        <Features />
        <HowItWorks />
        <WhoItsFor />
        <AppPreview />
        <FAQ />
        <CTA />
      </main>
      <Footer />
    </>
  )
}

export default function App() {
  return (
    <Routes>
      <Route path="/" element={<Landing />} />
      <Route path="/help" element={<HelpCenter />} />
      <Route path="/privacy" element={<PrivacyPolicy />} />
      <Route path="/delete-account" element={<DeleteAccount />} />
      <Route path="*" element={<NotFound />} />
    </Routes>
  )
}
