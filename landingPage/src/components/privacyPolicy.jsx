import React, { useEffect } from 'react'
import { Link } from 'react-router-dom'
import Logo from './Logo'
import { ArrowLeft, Shield, Mail } from 'lucide-react'

const SECTIONS = [
  {
    title: '1. Information We Collect',
    content: [
      {
        subtitle: '1.1 Account Information',
        text: 'When you create a BillMate account, we collect your name, phone number, email address (optional), business name, business type, and GSTIN (if applicable). This information is required to set up your store profile and provide you with our billing and business management services.',
      },
      {
        subtitle: '1.2 Business & Transaction Data',
        text: 'We collect data you enter into the app, including item names, prices, categories, GST rates, barcode values, bill records, expense entries, and customer details (if you choose to add them). This data belongs entirely to you and is stored to deliver the core billing, inventory, reporting, and expense-tracking features of BillMate.',
      },
      {
        subtitle: '1.3 Device & Usage Information',
        text: 'We automatically collect certain technical information when you use our app, including device model, operating system version, app version, and general usage patterns. This helps us diagnose issues, ensure stability, and improve the BillMate experience over time.',
      },
      {
        subtitle: '1.4 Payment Information',
        text: 'If you subscribe to BillMate Pro, payment processing is handled entirely by our third-party payment provider. We do not store your card details, UPI credentials, or any sensitive payment information on our servers.',
      },
    ],
  },
  {
    title: '2. How We Use Your Information',
    content: [
      {
        subtitle: '2.1 Providing the Service',
        text: 'Your data is used to operate BillMate — to generate bills, manage inventory, track expenses, display reports, handle table orders, and sync data across your devices. Your business profile is used to personalise your experience and display your business details on generated receipts.',
      },
      {
        subtitle: '2.2 Customer Support',
        text: 'When you contact us for help, we may access your account and transaction data to diagnose and resolve the issue you are facing. We only access this data with your consent and only to the extent needed to assist you.',
      },
      {
        subtitle: '2.3 Service Improvements',
        text: 'Aggregated and anonymised usage data helps us understand how BillMate is being used, identify common pain points, and prioritise new features. We do not use individual-level data for this purpose.',
      },
      {
        subtitle: '2.4 Communication',
        text: 'We may contact you via SMS, WhatsApp, or email to send important service announcements, security alerts, or information about app updates. We do not send promotional messages without your explicit consent.',
      },
    ],
  },
  {
    title: '3. Data Storage & Security',
    content: [
      {
        subtitle: '3.1 Data Storage',
        text: 'Your data is stored on secure servers. BillMate supports offline billing — data created offline is stored locally on your device and automatically synced to our servers when your internet connection is restored. You can use BillMate on Android, Windows, and the web at app.billmate.in.',
      },
      {
        subtitle: '3.2 Security Measures',
        text: 'We implement industry-standard security measures including encrypted data transmission (HTTPS/TLS), PIN-based authentication, and strict access controls. However, no system is completely secure, and we encourage you to use a strong PIN for your BillMate account and keep it confidential.',
      },
      {
        subtitle: '3.3 Data Retention',
        text: 'We retain your data for as long as your account remains active. If you request deletion of your account, we will delete your personal data and business records within 30 days of the request, except where retention is required by applicable law (such as GST record-keeping requirements).',
      },
    ],
  },
  {
    title: '4. Sharing of Information',
    content: [
      {
        subtitle: '4.1 We Do Not Sell Your Data',
        text: 'BillMate does not sell, rent, or trade your personal information or business data to third parties for their marketing or any other purposes. Your business data is yours — we are custodians of it, not owners.',
      },
      {
        subtitle: '4.2 Service Providers',
        text: 'We share data with trusted third-party service providers who assist us in operating BillMate — such as cloud hosting providers and payment processors. These providers are contractually bound to protect your data and may only use it to provide services on our behalf.',
      },
      {
        subtitle: '4.3 Legal Requirements',
        text: 'We may disclose your information if required to do so by law, court order, or government authority, or if we believe disclosure is necessary to protect the rights, property, or safety of BillMate, our users, or the public.',
      },
    ],
  },
  {
    title: '5. Your Rights',
    content: [
      {
        subtitle: '5.1 Access & Correction',
        text: 'You may access and update your account information at any time through the Settings section of the BillMate app. You can edit your business profile, contact details, GSTIN, and preferences directly without contacting support.',
      },
      {
        subtitle: '5.2 Data Export',
        text: 'You may request an export of your business data — bills, items, expenses, and reports — by contacting our support team at support@vengurlatech.com. You can also export reports directly from within the app in CSV or PDF format.',
      },
      {
        subtitle: '5.3 Account Deletion',
        text: 'You have the right to request deletion of your BillMate account and all associated data at any time. To submit a deletion request, contact us at support@vengurlatech.com or reach out via WhatsApp support. Deletion is processed within 30 days of a verified request.',
      },
    ],
  },
  {
    title: "6. Children's Privacy",
    content: [
      {
        subtitle: '',
        text: 'BillMate is a business management tool intended for adults operating businesses. We do not knowingly collect personal information from individuals under the age of 18. If you believe a minor has provided us with personal information, please contact us immediately and we will promptly delete it.',
      },
    ],
  },
  {
    title: '7. Changes to This Policy',
    content: [
      {
        subtitle: '',
        text: 'We may update this Privacy Policy from time to time to reflect changes in our practices, features, or applicable laws. When we make significant changes, we will notify you through the app or via your registered contact method. Continued use of BillMate after changes are published constitutes your acceptance of the updated policy.',
      },
    ],
  },
  {
    title: '8. Contact Us',
    content: [
      {
        subtitle: '',
        text: 'If you have questions, concerns, or requests relating to this Privacy Policy or your data, please contact us at privacy@billmate.in or through the Help Center. You can also reach us via WhatsApp support for faster responses. We aim to respond to all privacy-related inquiries within 48 hours.',
      },
    ],
  },
]

export default function PrivacyPolicy() {
  useEffect(() => {
    window.scrollTo(0, 0)
  }, [])

  return (
    <div className="min-h-screen bg-slate-50">

      {/* Top bar */}
      <div className="bg-navy-900 px-6 py-4">
        <div className="max-w-4xl mx-auto flex items-center justify-between">
          <Logo size={32} />
          <Link
            to="/"
            className="flex items-center gap-2 text-sm text-white/50 hover:text-white transition-colors"
          >
            <ArrowLeft size={15} />
            Back to Home
          </Link>
        </div>
      </div>

      {/* Hero */}
      <div
        className="px-6 py-14 text-center"
        style={{ background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 100%)' }}
      >
        <div
          className="inline-flex items-center gap-2 px-4 py-1.5 rounded-full text-xs font-semibold mb-5"
          style={{ background: 'rgba(0,229,192,0.14)', color: '#00e5c0' }}
        >
          <Shield size={11} />
          Legal Document
        </div>
        <h1 className="font-display text-4xl font-extrabold text-white mb-3">
          Privacy Policy
        </h1>
        <p className="text-white/45 max-w-md mx-auto text-sm leading-relaxed">
          This policy explains how BillMate collects, uses, and protects the
          information you provide when using our app and services.
        </p>
        <p className="text-white/25 text-xs mt-4">
          Last updated: June 2026 &nbsp;·&nbsp; Effective: June 2026
        </p>
      </div>

      {/* Content */}
      <div className="max-w-4xl mx-auto px-6 py-14">

        {/* Intro box */}
        <div
          className="rounded-2xl p-6 mb-10 border"
          style={{ background: 'rgba(0,229,192,0.06)', borderColor: 'rgba(0,229,192,0.2)' }}
        >
          <p className="text-sm text-slate-600 leading-relaxed">
            <span className="font-semibold text-navy-900">Summary:</span> BillMate ("we", "our", "us")
            is a billing and business management app built for small shops, retailers, and restaurants
            across India. We collect only the information needed to run the app — billing data, inventory,
            expenses, and your business profile. We do not sell your data, and you can request deletion of
            your account and all associated data at any time. Read on for the full details.
          </p>
        </div>

        {/* Sections */}
        <div className="space-y-10">
          {SECTIONS.map((section, si) => (
            <div key={si}>
              <h2
                className="font-display text-xl font-bold text-navy-900 mb-5 pb-3"
                style={{ borderBottom: '2px solid rgba(0,229,192,0.25)' }}
              >
                {section.title}
              </h2>
              <div className="space-y-5">
                {section.content.map((block, bi) => (
                  <div key={bi}>
                    {block.subtitle && (
                      <h3 className="font-semibold text-navy-900 text-sm mb-1.5">
                        {block.subtitle}
                      </h3>
                    )}
                    <p className="text-sm text-slate-600 leading-relaxed">{block.text}</p>
                  </div>
                ))}
              </div>
            </div>
          ))}
        </div>

        {/* Contact card */}
        <div
          className="mt-14 rounded-2xl p-7 text-center"
          style={{ background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 100%)' }}
        >
          <Mail size={28} className="text-teal mx-auto mb-3" style={{ color: '#00e5c0' }} />
          <h3 className="font-display font-bold text-white text-lg mb-2">
            Questions about your privacy?
          </h3>
          <p className="text-white/45 text-sm mb-4">
            We're here to help. Reach out and we'll respond within 48 hours.
          </p>
          <a
            href="mailto:privacy@billmate.in"
            className="inline-block px-6 py-3 rounded-xl text-sm font-bold"
            style={{ background: '#00e5c0', color: '#0d1b3e' }}
          >
            privacy@billmate.in
          </a>
        </div>

        {/* Footer nav */}
        <div className="flex flex-wrap justify-center gap-6 mt-10 pt-8 border-t border-slate-200 text-xs text-slate-400">
          <Link to="/" className="hover:text-navy-900 transition-colors">Home</Link>
          <Link to="/help" className="hover:text-navy-900 transition-colors">Help Center</Link>
          <Link to="/delete-account" className="hover:text-navy-900 transition-colors">Delete Account</Link>
          <a href="mailto:support@vengurlatech.com" className="hover:text-navy-900 transition-colors">Contact</a>
        </div>
      </div>
    </div>
  )
}
