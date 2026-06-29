import React, { useEffect } from 'react'
import { Link } from 'react-router-dom'
import Logo from './Logo'
import { ArrowLeft, Shield, Mail } from 'lucide-react'

/* ─────────────────────────────────────────────────────────────────────────────
   OLD SECTIONS (commented out — replaced by Termly-style policy below)
─────────────────────────────────────────────────────────────────────────────
const OLD_SECTIONS = [
  {
    title: '1. Information We Collect',
    content: [
      {
        subtitle: '1.1 Account Information',
        text: 'When you create a Vittam account, we collect your name, phone number, email address (optional), business name, business type, and GSTIN (if applicable). This information is required to set up your store profile and provide you with our billing and business management services.',
      },
      {
        subtitle: '1.2 Business & Transaction Data',
        text: 'We collect data you enter into the app, including item names, prices, categories, GST rates, barcode values, bill records, expense entries, and customer details (if you choose to add them). This data belongs entirely to you and is stored to deliver the core billing, inventory, reporting, and expense-tracking features of Vittam.',
      },
      {
        subtitle: '1.3 Device & Usage Information',
        text: 'We automatically collect certain technical information when you use our app, including device model, operating system version, app version, and general usage patterns. This helps us diagnose issues, ensure stability, and improve the Vittam experience over time.',
      },
    ],
  },
  {
    title: '2. How We Use Your Information',
    content: [
      {
        subtitle: '2.1 Providing the Service',
        text: 'Your data is used to operate Vittam — to generate bills, manage inventory, track expenses, display reports, handle table orders, and sync data across your devices. Your business profile is used to personalise your experience and display your business details on generated receipts.',
      },
      {
        subtitle: '2.2 Customer Support',
        text: 'When you contact us for help, we may access your account and transaction data to diagnose and resolve the issue you are facing. We only access this data with your consent and only to the extent needed to assist you.',
      },
      {
        subtitle: '2.3 Service Improvements',
        text: 'Aggregated and anonymised usage data helps us understand how Vittam is being used, identify common pain points, and prioritise new features. We do not use individual-level data for this purpose.',
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
        text: 'Your data is stored on secure servers. Vittam supports offline billing — data created offline is stored locally on your device and automatically synced to our servers when your internet connection is restored. You can use Vittam on Android, Windows.',
      },
      {
        subtitle: '3.2 Security Measures',
        text: 'We implement industry-standard security measures including encrypted data transmission (HTTPS/TLS), PIN-based authentication, and strict access controls. However, no system is completely secure, and we encourage you to use a strong PIN for your Vittam account and keep it confidential.',
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
        text: 'Vittam does not sell, rent, or trade your personal information or business data to third parties for their marketing or any other purposes. Your business data is yours — we are custodians of it, not owners.',
      },
      {
        subtitle: '4.2 Service Providers',
        text: 'We share data with trusted third-party service providers who assist us in operating Vittam — such as cloud hosting providers and payment processors. These providers are contractually bound to protect your data and may only use it to provide services on our behalf.',
      },
      {
        subtitle: '4.3 Legal Requirements',
        text: 'We may disclose your information if required to do so by law, court order, or government authority, or if we believe disclosure is necessary to protect the rights, property, or safety of Vittam, our users, or the public.',
      },
    ],
  },
  {
    title: '5. Your Rights',
    content: [
      {
        subtitle: '5.1 Access & Correction',
        text: 'You may access and update your account information at any time through the Settings section of the Vittam app. You can edit your business profile, contact details, GSTIN, and preferences directly without contacting support.',
      },
      {
        subtitle: '5.2 Data Export',
        text: 'You may request an export of your business data — bills, items, expenses, and reports — by contacting our support team at support@vengurlatech.com. You can also export reports directly from within the app in CSV or PDF format.',
      },
      {
        subtitle: '5.3 Account Deletion',
        text: 'You have the right to request deletion of your Vittam account and all associated data at any time. To submit a deletion request, contact us at support@vengurlatech.com or reach out via WhatsApp support. Deletion is processed within 30 days of a verified request.',
      },
    ],
  },
  {
    title: "6. Children's Privacy",
    content: [
      {
        subtitle: '',
        text: 'Vittam is a business management tool intended for adults operating businesses. We do not knowingly collect personal information from individuals under the age of 18. If you believe a minor has provided us with personal information, please contact us immediately and we will promptly delete it.',
      },
    ],
  },
  {
    title: '7. Changes to This Policy',
    content: [
      {
        subtitle: '',
        text: 'We may update this Privacy Policy from time to time to reflect changes in our practices, features, or applicable laws. When we make significant changes, we will notify you through the app or via your registered contact method. Continued use of Vittam after changes are published constitutes your acceptance of the updated policy.',
      },
    ],
  },
  {
    title: '8. Contact Us',
    content: [
      {
        subtitle: '',
        text: 'If you have questions, concerns, or requests relating to this Privacy Policy or your data, please contact us at support@vengurlatech.com or through the Help Center. You can also reach us via WhatsApp support for faster responses. We aim to respond to all privacy-related inquiries within 48 hours.',
      },
    ],
  },
]
───────────────────────────────────────────────────────────────────────────── */

const SUMMARY_POINTS = [
  'What personal information do we process? When you visit, use, or navigate our Services, we may process personal information depending on how you interact with us and the Services, the choices you make, and the products and features you use.',
  'Do we process any sensitive personal information? Some of the information may be considered "special" or "sensitive" in certain jurisdictions, for example your racial or ethnic origins, sexual orientation, and religious beliefs. We do not process sensitive personal information.',
  'Do we collect any information from third parties? We do not collect any information from third parties.',
  'How do we process your information? We process your information to provide, improve, and administer our Services, communicate with you, for security and fraud prevention, and to comply with law. We may also process your information for other purposes with your consent. We process your information only when we have a valid legal reason to do so.',
  'In what situations and with which parties do we share personal information? We may share information in specific situations and with specific third parties.',
  'How do we keep your information safe? We have adequate organizational and technical processes and procedures in place to protect your personal information. However, no electronic transmission over the internet or information storage technology can be guaranteed to be 100% secure, so we cannot promise or guarantee that hackers, cybercriminals, or other unauthorized third parties will not be able to defeat our security and improperly collect, access, steal, or modify your information.',
  'What are your rights? Depending on where you are located geographically, the applicable privacy law may mean you have certain rights regarding your personal information.',
  'How do you exercise your rights? The easiest way to exercise your rights is by visiting https://vittam.vengurlatech.com/delete-account, or by contacting us. We will consider and act upon any request in accordance with applicable data protection laws.',
]

const TOC = [
  '1. WHAT INFORMATION DO WE COLLECT?',
  '2. HOW DO WE PROCESS YOUR INFORMATION?',
  '3. WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION?',
  '4. HOW LONG DO WE KEEP YOUR INFORMATION?',
  '5. HOW DO WE KEEP YOUR INFORMATION SAFE?',
  '6. DO WE COLLECT INFORMATION FROM MINORS?',
  '7. WHAT ARE YOUR PRIVACY RIGHTS?',
  '8. CONTROLS FOR DO-NOT-TRACK FEATURES',
  '9. DO WE MAKE UPDATES TO THIS NOTICE?',
  '10. HOW CAN YOU CONTACT US ABOUT THIS NOTICE?',
  '11. HOW CAN YOU REVIEW, UPDATE, OR DELETE THE DATA WE COLLECT FROM YOU?',
]

const SECTIONS = [
  {
    title: '1. WHAT INFORMATION DO WE COLLECT?',
    content: [
      {
        subtitle: 'Personal information you disclose to us',
        text: 'In Short: We collect personal information that you provide to us.\n\nWe collect personal information that you voluntarily provide to us when you register on the Services, express an interest in obtaining information about us or our products and Services, when you participate in activities on the Services, or otherwise when you contact us.\n\nPersonal Information Provided by You. The personal information that we collect depends on the context of your interactions with us and the Services, the choices you make, and the products and features you use. The personal information we collect may include the following:\n• names\n• phone numbers\n• passwords\n• business name\n\nAll personal information that you provide to us must be true, complete, and accurate, and you must notify us of any changes to such personal information.',
      },
      {
        subtitle: 'Sensitive Information',
        text: 'We do not process sensitive information.',
      },
      {
        subtitle: 'Application Data',
        text: 'If you use our application(s), we also may collect the following information if you choose to provide us with access or permission:\n\n• Geolocation Information. We may request access or permission to track location-based information from your mobile device, either continuously or while you are using our mobile application(s), to provide certain location-based services. If you wish to change our access or permissions, you may do so in your device\'s settings.\n\n• Mobile Device Access. We may request access or permission to certain features from your mobile device, including your mobile device\'s bluetooth, and other features. If you wish to change our access or permissions, you may do so in your device\'s settings.\n\n• Push Notifications. We may request to send you push notifications regarding your account or certain features of the application(s). If you wish to opt out from receiving these types of communications, you may turn them off in your device\'s settings.\n\nThis information is primarily needed to maintain the security and operation of our application(s), for troubleshooting, and for our internal analytics and reporting purposes.',
      },
      {
        subtitle: 'Google API',
        text: 'Our use of information received from Google APIs will adhere to Google API Services User Data Policy, including the Limited Use requirements.',
      },
    ],
  },
  {
    title: '2. HOW DO WE PROCESS YOUR INFORMATION?',
    content: [
      {
        subtitle: '',
        text: 'In Short: We process your information to provide, improve, and administer our Services, communicate with you, for security and fraud prevention, and to comply with law. We may also process your information for other purposes with your consent.\n\nWe process your personal information for a variety of reasons, depending on how you interact with our Services, including:\n\n• To facilitate account creation and authentication and otherwise manage user accounts. We may process your information so you can create and log in to your account, as well as keep your account in working order.',
      },
    ],
  },
  {
    title: '3. WHEN AND WITH WHOM DO WE SHARE YOUR PERSONAL INFORMATION?',
    content: [
      {
        subtitle: '',
        text: 'In Short: We may share information in specific situations described in this section and/or with the following third parties.\n\nWe may need to share your personal information in the following situations:\n\n• Business Transfers. We may share or transfer your information in connection with, or during negotiations of, any merger, sale of company assets, financing, or acquisition of all or a portion of our business to another company.',
      },
    ],
  },
  {
    title: '4. HOW LONG DO WE KEEP YOUR INFORMATION?',
    content: [
      {
        subtitle: '',
        text: 'In Short: We keep your information for as long as necessary to fulfill the purposes outlined in this Privacy Notice unless otherwise required by law.\n\nWe will only keep your personal information for as long as it is necessary for the purposes set out in this Privacy Notice, unless a longer retention period is required or permitted by law (such as tax, accounting, or other legal requirements). No purpose in this notice will require us keeping your personal information for longer than the period of time in which users have an account with us.\n\nWhen we have no ongoing legitimate business need to process your personal information, we will either delete or anonymize such information, or, if this is not possible (for example, because your personal information has been stored in backup archives), then we will securely store your personal information and isolate it from any further processing until deletion is possible.',
      },
    ],
  },
  {
    title: '5. HOW DO WE KEEP YOUR INFORMATION SAFE?',
    content: [
      {
        subtitle: '',
        text: 'In Short: We aim to protect your personal information through a system of organizational and technical security measures.\n\nWe have implemented appropriate and reasonable technical and organizational security measures designed to protect the security of any personal information we process. However, despite our safeguards and efforts to secure your information, no electronic transmission over the Internet or information storage technology can be guaranteed to be 100% secure, so we cannot promise or guarantee that hackers, cybercriminals, or other unauthorized third parties will not be able to defeat our security and improperly collect, access, steal, or modify your information. Although we will do our best to protect your personal information, transmission of personal information to and from our Services is at your own risk. You should only access the Services within a secure environment.',
      },
    ],
  },
  {
    title: '6. DO WE COLLECT INFORMATION FROM MINORS?',
    content: [
      {
        subtitle: '',
        text: 'In Short: We do not knowingly collect data from or market to children under 18 years of age.\n\nWe do not knowingly collect, solicit data from, or market to children under 18 years of age, nor do we knowingly sell such personal information. By using the Services, you represent that you are at least 18 or that you are the parent or guardian of such a minor and consent to such minor dependent\'s use of the Services. If we learn that personal information from users less than 18 years of age has been collected, we will deactivate the account and take reasonable measures to promptly delete such data from our records. If you become aware of any data we may have collected from children under age 18, please contact us at support@vengurlatech.com.',
      },
    ],
  },
  {
    title: '7. WHAT ARE YOUR PRIVACY RIGHTS?',
    content: [
      {
        subtitle: '',
        text: 'In Short: You may review, change, or terminate your account at any time, depending on your country, province, or state of residence.\n\nWithdrawing your consent: If we are relying on your consent to process your personal information, which may be express and/or implied consent depending on the applicable law, you have the right to withdraw your consent at any time. You can withdraw your consent at any time by contacting us by using the contact details provided in the section "HOW CAN YOU CONTACT US ABOUT THIS NOTICE?" below.\n\nHowever, please note that this will not affect the lawfulness of the processing before its withdrawal nor, when applicable law allows, will it affect the processing of your personal information conducted in reliance on lawful processing grounds other than consent.',
      },
      {
        subtitle: 'Account Information',
        text: 'If you would at any time like to review or change the information in your account or terminate your account, you can:\n\n• Log in to your account settings and update your user account.\n• Contact us using the contact information provided.\n\nUpon your request to terminate your account, we will deactivate or delete your account and information from our active databases. However, we may retain some information in our files to prevent fraud, troubleshoot problems, assist with any investigations, enforce our legal terms and/or comply with applicable legal requirements.\n\nIf you have questions or comments about your privacy rights, you may email us at support@vengurlatech.com.',
      },
    ],
  },
  {
    title: '8. CONTROLS FOR DO-NOT-TRACK FEATURES',
    content: [
      {
        subtitle: '',
        text: 'Most web browsers and some mobile operating systems and mobile applications include a Do-Not-Track ("DNT") feature or setting you can activate to signal your privacy preference not to have data about your online browsing activities monitored and collected. At this stage, no uniform technology standard for recognizing and implementing DNT signals has been finalized. As such, we do not currently respond to DNT browser signals or any other mechanism that automatically communicates your choice not to be tracked online. If a standard for online tracking is adopted that we must follow in the future, we will inform you about that practice in a revised version of this Privacy Notice.',
      },
    ],
  },
  {
    title: '9. DO WE MAKE UPDATES TO THIS NOTICE?',
    content: [
      {
        subtitle: '',
        text: 'In Short: Yes, we will update this notice as necessary to stay compliant with relevant laws.\n\nWe may update this Privacy Notice from time to time. The updated version will be indicated by an updated "Revised" date at the top of this Privacy Notice. If we make material changes to this Privacy Notice, we may notify you either by prominently posting a notice of such changes or by directly sending you a notification. We encourage you to review this Privacy Notice frequently to be informed of how we are protecting your information.',
      },
    ],
  },
  {
    title: '10. HOW CAN YOU CONTACT US ABOUT THIS NOTICE?',
    content: [
      {
        subtitle: '',
        text: 'If you have questions or comments about this notice, you may email us at support@vengurlatech.com or contact us by post at:\n\nVENGURLA TECH PRIVATE LIMITED\n347, Jivan Kudalkar house\nKhutwalwadi, Adeli\nVENGURLA, Maharashtra 416516\nIndia',
      },
    ],
  },
  {
    title: '11. HOW CAN YOU REVIEW, UPDATE, OR DELETE THE DATA WE COLLECT FROM YOU?',
    content: [
      {
        subtitle: '',
        text: 'Based on the applicable laws of your country, you may have the right to request access to the personal information we collect from you, details about how we have processed it, correct inaccuracies, or delete your personal information. You may also have the right to withdraw your consent to our processing of your personal information. These rights may be limited in some circumstances by applicable law. To request to review, update, or delete your personal information, please visit: https://vittam.vengurlatech.com/delete-account',
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
      <div className="bg-[#143b9f]">
        <div className="max-w-4xl mx-auto flex items-center justify-between">
          <Logo size={60} />
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
          This policy explains how Vittam collects, uses, and protects the
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
            This Privacy Notice for <span className="font-semibold text-navy-900">VENGURLA TECH PRIVATE LIMITED</span> ("we," "us," or "our"), describes how and why we might access, collect, store, use, and/or share ("process") your personal information when you use our services ("Services"), including when you:
          </p>
          <ul className="mt-3 space-y-1 text-sm text-slate-600">
            <li className="flex gap-2"><span style={{ color: '#00e5c0' }}>•</span> Visit our website at https://vittam.vengurlatech.com/ or any website of ours that links to this Privacy Notice</li>
            <li className="flex gap-2"><span style={{ color: '#00e5c0' }}>•</span> Download and use our mobile application (Vittam), or any other application of ours that links to this Privacy Notice</li>
            <li className="flex gap-2"><span style={{ color: '#00e5c0' }}>•</span> Engage with us in other related ways, including any marketing or events</li>
          </ul>
          <p className="mt-3 text-sm text-slate-600 leading-relaxed">
            <span className="font-semibold">Questions or concerns?</span> Reading this Privacy Notice will help you understand your privacy rights and choices. We are responsible for making decisions about how your personal information is processed. If you do not agree with our policies and practices, please do not use our Services. If you still have any questions or concerns, please contact us at{' '}
            <a href="mailto:support@vengurlatech.com" className="underline" style={{ color: '#143b9f' }}>support@vengurlatech.com</a>.
          </p>
        </div>

        {/* Summary of Key Points */}
        <div className="mb-10">
          <h2
            className="font-display text-xl font-bold text-navy-900 mb-5 pb-3"
            style={{ borderBottom: '2px solid rgba(0,229,192,0.25)' }}
          >
            Summary of Key Points
          </h2>
          <p className="text-sm text-slate-600 leading-relaxed mb-4">
            This summary provides key points from our privacy notice, but you can find out more details about any of these topics by clicking the link following each key point or by using our table of contents below to find the section you are looking for.
          </p>
          <ul className="space-y-2">
            {SUMMARY_POINTS.map((point, i) => (
              <li key={i} className="flex gap-2 text-sm text-slate-600 leading-relaxed">
                <span style={{ color: '#00e5c0', flexShrink: 0 }}>•</span>
                <span>{point}</span>
              </li>
            ))}
          </ul>
        </div>

        {/* Table of Contents */}
        <div className="mb-10 rounded-2xl p-6 border" style={{ background: 'rgba(20,59,159,0.04)', borderColor: 'rgba(20,59,159,0.12)' }}>
          <h2 className="font-display text-lg font-bold text-navy-900 mb-4">Table of Contents</h2>
          <ol className="space-y-1.5">
            {TOC.map((item, i) => (
              <li key={i} className="text-sm" style={{ color: '#143b9f' }}>
                {item}
              </li>
            ))}
          </ol>
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
                    <p className="text-sm text-slate-600 leading-relaxed whitespace-pre-line">{block.text}</p>
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
            href="mailto:support@vengurlatech.com"
            className="inline-block px-6 py-3 rounded-xl text-sm font-bold"
            style={{ background: '#00e5c0', color: '#0d1b3e' }}
          >
            support@vengurlatech.com
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
