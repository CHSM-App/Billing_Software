import React, { useState, useEffect, useRef } from 'react'
import { X, CalendarCheck, CheckCircle2 } from 'lucide-react'

/* The request is posted to our own API, which sends the team an approved
   WhatsApp template. Same-origin in both dev and prod — see src/apiBase.js. */
import { API_BASE } from '../apiBase'

const BUSINESS_TYPES = [
  'Retail / General Store',
  'Grocery / Kirana',
  'Restaurant / Cafe',
  'Bakery / Sweet Shop',
  'Pharmacy / Medical',
  'Wholesale / Distributor',
  'Services / Salon',
  'Other',
]

const TIME_SLOTS = [
  '10:00 AM – 11:00 AM',
  '11:00 AM – 12:00 PM',
  '12:00 PM – 01:00 PM',
  '02:00 PM – 03:00 PM',
  '03:00 PM – 04:00 PM',
  '04:00 PM – 05:00 PM',
  '05:00 PM – 06:00 PM',
  '06:00 PM – 07:00 PM',
]

const EMPTY = {
  name: '',
  mobile: '',
  businessType: '',
  date: '',
  time: '',
  usingSoftware: '',
}

/* Local YYYY-MM-DD — toISOString() would shift the date backwards in IST. */
function todayStr() {
  const d = new Date()
  const pad = n => String(n).padStart(2, '0')
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`
}

function validate(form) {
  const e = {}
  if (!form.name.trim()) e.name = 'Please enter your name'
  if (!/^[6-9]\d{9}$/.test(form.mobile.trim())) e.mobile = 'Enter a valid 10-digit mobile number'
  if (!form.businessType) e.businessType = 'Please select your business type'
  if (!form.date) e.date = 'Please select a date'
  if (!form.time) e.time = 'Please select a time'
  if (!form.usingSoftware) e.usingSoftware = 'Please select an option'
  return e
}

/* ── Field shell ─────────────────────────────────── */
function Field({ label, error, className = '', children }) {
  return (
    <div className={className}>
      <label className="block text-[13px] font-semibold text-navy-900 mb-1.5">
        {label} <span className="text-red-500">*</span>
      </label>
      {children}
      {error && <p className="text-[11.5px] text-red-500 mt-1">{error}</p>}
    </div>
  )
}

const inputCls = (error) =>
  `w-full rounded-xl border bg-white px-4 py-3 text-sm text-navy-900 placeholder:text-slate-400
   outline-none transition-colors focus:border-teal-dark focus:ring-2 focus:ring-teal/25 ${
     error ? 'border-red-300' : 'border-slate-200'
   }`

export default function BookDemoModal({ open, onClose }) {
  const [form, setForm] = useState(EMPTY)
  const [errors, setErrors] = useState({})
  const [sent, setSent] = useState(false)
  const [sending, setSending] = useState(false)
  const [submitError, setSubmitError] = useState('')
  const firstFieldRef = useRef(null)

  const set = (key) => (ev) => {
    const value = key === 'mobile' ? ev.target.value.replace(/\D/g, '').slice(0, 10) : ev.target.value
    setForm(f => ({ ...f, [key]: value }))
    setErrors(e => ({ ...e, [key]: undefined }))
  }

  /* Esc to close + lock background scroll while open */
  useEffect(() => {
    if (!open) return
    const onKey = ev => ev.key === 'Escape' && onClose()
    window.addEventListener('keydown', onKey)
    const prev = document.body.style.overflow
    document.body.style.overflow = 'hidden'
    // preventScroll matters: focusing an input scrolls it into view inside the
    // nearest scrollable ancestor, which here is the modal's own scroll
    // container — so autofocusing the name field scrolled the card's header off
    // the top the moment the dialog opened, on every screen too short to fit
    // the whole form. The field is already visible; nothing needs scrolling.
    const t = setTimeout(() => firstFieldRef.current?.focus({ preventScroll: true }), 60)
    return () => {
      window.removeEventListener('keydown', onKey)
      document.body.style.overflow = prev
      clearTimeout(t)
    }
  }, [open, onClose])

  /* Reset back to a blank form once the closing animation is out of the way */
  useEffect(() => {
    if (open) return
    const t = setTimeout(
      () => { setForm(EMPTY); setErrors({}); setSent(false); setSubmitError('') }, 250)
    return () => clearTimeout(t)
  }, [open])

  if (!open) return null

  const handleSubmit = async (ev) => {
    ev.preventDefault()
    const found = validate(form)
    setErrors(found)
    if (Object.keys(found).length) return

    setSending(true)
    setSubmitError('')
    try {
      const res = await fetch(`${API_BASE}/api/demo/request`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(form),
      })
      if (!res.ok) {
        const data = await res.json().catch(() => null)
        throw new Error(data?.error || 'Could not send your request. Please try again.')
      }
      setSent(true)
    } catch (err) {
      setSubmitError(err.message || 'Could not send your request. Please try again.')
    } finally {
      setSending(false)
    }
  }

  const closeOnBackdrop = ev => ev.target === ev.currentTarget && onClose()

  return (
    <div
      className="fixed inset-0 z-[100] overflow-y-auto"
      role="dialog"
      aria-modal="true"
      aria-labelledby="book-demo-title"
      onMouseDown={closeOnBackdrop}
    >
      {/* Backdrop */}
      <div className="fixed inset-0 bg-navy-950/60 backdrop-blur-sm" aria-hidden="true" />

      {/* Centring wrapper. min-h-full (NOT items-center on the scroll container
          itself) is what makes this scrollable: a flex item centred inside a
          scroll container overflows EQUALLY in both directions, and overflow
          above a scrollport's top edge cannot be scrolled to — so on a short
          window the card's header was simply unreachable. Growing the wrapper
          with the content instead means centring only applies when it fits. */}
      <div
        className="relative flex min-h-full items-center justify-center p-4 md:p-6"
        onMouseDown={closeOnBackdrop}
      >
        {/* Card */}
        <div className="relative w-full max-w-3xl rounded-3xl bg-white shadow-screen
                        overflow-hidden animate-fadeUp">
        <button
          onClick={onClose}
          aria-label="Close"
          className="absolute top-3.5 right-3.5 z-10 flex items-center justify-center w-10 h-10
                     rounded-full text-white/70 hover:text-white hover:bg-white/10 transition-colors"
        >
          <X size={20} />
        </button>

        {/* Header */}
        <div
          className="px-6 pt-6 pb-5 text-center"
          style={{ background: 'linear-gradient(135deg, #0d1b3e 0%, #1a3272 55%, #0d2d5e 100%)' }}
        >
          <span className="inline-flex items-center gap-1.5 rounded-full px-3 py-1 text-[11px]
                           font-bold tracking-wide text-teal bg-teal/10 border border-teal/25">
            <CalendarCheck size={12} /> BOOK A DEMO
          </span>
          <h2
            id="book-demo-title"
            className="font-display text-2xl sm:text-3xl font-extrabold text-white mt-3 leading-snug"
          >
            Ready for Smarter Billing?
          </h2>
          <p className="text-[13.5px] text-white/50 mt-2 leading-relaxed max-w-md mx-auto">
            Book your Vittam demo and explore a better way to manage your business.
          </p>
        </div>

        {sent ? (
          /* ── Success ── */
          <div className="px-6 py-12 text-center">
            <CheckCircle2 size={52} className="mx-auto text-teal-dark" />
            <h3 className="font-display text-xl font-bold text-navy-900 mt-4">
              Demo request sent!
            </h3>
            <p className="text-sm text-slate-500 mt-2 leading-relaxed max-w-xs mx-auto">
              Thanks {form.name.split(' ')[0]} — our team will contact you on{' '}
              <span className="font-semibold text-navy-900">+91 {form.mobile}</span> to confirm
              your demo.
            </p>
            <button
              onClick={onClose}
              className="btn-navy mt-7 px-6 py-3 rounded-xl text-sm font-semibold"
            >
              Done
            </button>
          </div>
        ) : (
          /* ── Form ── */
          <form onSubmit={handleSubmit} noValidate className="px-6 sm:px-8 py-6">
            <p className="text-[11px] font-bold tracking-widest text-slate-400 uppercase mb-4">
              Fill in your details
            </p>

            <div className="grid sm:grid-cols-2 gap-x-5 gap-y-4">
              <Field label="Name" error={errors.name} className="sm:col-span-2">
                <input
                  ref={firstFieldRef}
                  type="text"
                  value={form.name}
                  onChange={set('name')}
                  placeholder="Enter your name"
                  className={inputCls(errors.name)}
                />
              </Field>

              <Field label="Mobile Number" error={errors.mobile}>
                <div className="relative">
                  <span className="absolute left-4 top-1/2 -translate-y-1/2 text-sm text-slate-400
                                   pointer-events-none">
                    +91
                  </span>
                  <input
                    type="tel"
                    inputMode="numeric"
                    value={form.mobile}
                    onChange={set('mobile')}
                    placeholder="10-digit number"
                    className={`${inputCls(errors.mobile)} pl-14`}
                  />
                </div>
              </Field>

              <Field label="Business Type" error={errors.businessType}>
                <select
                  value={form.businessType}
                  onChange={set('businessType')}
                  className={`${inputCls(errors.businessType)} ${
                    form.businessType ? '' : 'text-slate-400'
                  }`}
                >
                  <option value="">Select your business type</option>
                  {BUSINESS_TYPES.map(t => <option key={t} value={t}>{t}</option>)}
                </select>
              </Field>

              <Field label="Preferred Demo Date" error={errors.date}>
                <input
                  type="date"
                  value={form.date}
                  min={todayStr()}
                  onChange={set('date')}
                  className={`${inputCls(errors.date)} ${form.date ? '' : 'text-slate-400'}`}
                />
              </Field>

              <Field label="Preferred Time" error={errors.time}>
                <select
                  value={form.time}
                  onChange={set('time')}
                  className={`${inputCls(errors.time)} ${form.time ? '' : 'text-slate-400'}`}
                >
                  <option value="">Select time</option>
                  {TIME_SLOTS.map(t => <option key={t} value={t}>{t}</option>)}
                </select>
              </Field>

              <Field
                label="Are you currently using any billing software?"
                error={errors.usingSoftware}
                className="sm:col-span-2 text-center"
              >
                <div className="flex gap-3 max-w-xs mx-auto">
                  {['Yes', 'No'].map(opt => {
                    const active = form.usingSoftware === opt
                    return (
                      <button
                        key={opt}
                        type="button"
                        onClick={() => {
                          setForm(f => ({ ...f, usingSoftware: opt }))
                          setErrors(e => ({ ...e, usingSoftware: undefined }))
                        }}
                        className={`flex-1 min-h-12 rounded-xl border text-sm font-semibold
                                    transition-colors ${
                          active
                            ? 'border-teal-dark bg-teal/10 text-teal-dim'
                            : 'border-slate-200 bg-white text-slate-500 hover:bg-slate-50'
                        }`}
                      >
                        {opt}
                      </button>
                    )
                  })}
                </div>
              </Field>
            </div>

            {submitError && (
              <p role="alert" className="text-center text-[12.5px] text-red-500 mt-5">
                {submitError}
              </p>
            )}

            <button
              type="submit"
              disabled={sending}
              className="btn-teal w-full sm:w-auto sm:min-w-64 sm:mx-auto sm:block mt-6 px-8 py-4
                         rounded-2xl text-sm font-bold tracking-wide
                         disabled:opacity-60 disabled:cursor-not-allowed"
            >
              {sending ? 'SENDING…' : 'BOOK MY DEMO'}
            </button>

            <p className="text-center text-[11.5px] text-slate-400 mt-3.5">
              Our team will contact you to confirm your demo.
            </p>
          </form>
        )}
        </div>
      </div>
    </div>
  )
}
