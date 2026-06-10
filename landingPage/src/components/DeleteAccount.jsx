import React, { useState, useEffect } from 'react'
import { Link } from 'react-router-dom'
import Logo from './Logo'
import { ArrowLeft, AlertTriangle, Phone, KeyRound, FileText, CheckCircle, XCircle, Loader2 } from 'lucide-react'

const API_BASE = 'https://Vittam.vengurlatech.com' || ''

// ── Helpers ──────────────────────────────────────────────────────────────────

async function apiPost(path, body) {
  const res = await fetch(`${API_BASE}${path}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json' },
    body: JSON.stringify(body),
  })
  const raw = await res.text()
  let data = null

  try {
    data = raw ? JSON.parse(raw) : null
  } catch (_) {
    data = null
  }

  if (!res.ok) {
    throw new Error(data?.error || data?.message || 'Something went wrong.')
  }

  if (!data || typeof data !== 'object') {
    throw new Error('Something went wrong.')
  }

  return data
}

// ── Step indicators ──────────────────────────────────────────────────────────

function StepDot({ n, active, done }) {
  return (
    <div className="flex flex-col items-center gap-1">
      <div
        className="w-8 h-8 rounded-full flex items-center justify-center text-xs font-bold transition-all"
        style={
          done
            ? { background: '#00e5c0', color: '#0d1b3e' }
            : active
            ? { background: '#0d1b3e', color: '#fff', boxShadow: '0 0 0 3px rgba(0,229,192,0.3)' }
            : { background: '#e2e8f0', color: '#94a3b8' }
        }
      >
        {done ? '✓' : n}
      </div>
    </div>
  )
}

function Steps({ current }) {
  const labels = ['Phone', 'Verify OTP', 'Confirm']
  return (
    <div className="flex items-center gap-0 mb-8">
      {labels.map((label, i) => (
        <React.Fragment key={i}>
          <div className="flex flex-col items-center gap-1 flex-shrink-0">
            <StepDot n={i + 1} active={current === i} done={current > i} />
            <span className="text-xs font-medium" style={{ color: current >= i ? '#0d1b3e' : '#94a3b8' }}>
              {label}
            </span>
          </div>
          {i < labels.length - 1 && (
            <div
              className="flex-1 h-0.5 mx-2 mb-4"
              style={{ background: current > i ? '#00e5c0' : '#e2e8f0' }}
            />
          )}
        </React.Fragment>
      ))}
    </div>
  )
}

// ── Main component ───────────────────────────────────────────────────────────

export default function DeleteAccount() {
  const [step, setStep]         = useState(0)   // 0=phone, 1=otp, 2=confirm, 3=done
  const [phone, setPhone]       = useState('')
  const [otp, setOtp]           = useState('')
  const [reason, setReason]     = useState('')
  const [loading, setLoading]   = useState(false)
  const [error, setError]       = useState('')
  const [scheduled, setScheduled] = useState(null)

  // Cancel flow state
  const [showCancel, setShowCancel]           = useState(false)
  const [cancelPhone, setCancelPhone]         = useState('')
  const [cancelOtp, setCancelOtp]             = useState('')
  const [cancelStep, setCancelStep]           = useState(0)  // 0=phone, 1=otp
  const [cancelLoading, setCancelLoading]     = useState(false)
  const [cancelError, setCancelError]         = useState('')
  const [cancelSuccess, setCancelSuccess]     = useState(false)

  useEffect(() => { window.scrollTo(0, 0) }, [])

  function clearError() { setError('') }

  // ── Step 0 → send OTP ────────────────────────────────────────────────────

  async function handleSendOtp(e) {
    e.preventDefault()
    clearError()
    if (!/^\d{10}$/.test(phone)) {
      setError('Enter a valid 10-digit phone number.')
      return
    }
    setLoading(true)
    try {
      await apiPost('/api/account/deletion/request', { phone })
      setStep(1)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  // ── Step 1 → verify OTP (move to confirm screen) ─────────────────────────

  function handleOtpNext(e) {
    e.preventDefault()
    clearError()
    if (!/^\d{6}$/.test(otp)) {
      setError('OTP must be exactly 6 digits.')
      return
    }
    setStep(2)
  }

  // ── Step 2 → confirm deletion ────────────────────────────────────────────

  async function handleConfirm(e) {
    e.preventDefault()
    clearError()
    setLoading(true)
    try {
      const data = await apiPost('/api/account/deletion/confirm', { phone, otp, reason: reason.trim() || undefined })
      setScheduled(new Date(data.scheduled_for))
      setStep(3)
    } catch (err) {
      // If OTP was wrong/expired, send them back to OTP step
      if (err.message.toLowerCase().includes('otp')) {
        setStep(1)
        setOtp('')
      }
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  // ── Cancel flow ──────────────────────────────────────────────────────────

  async function handleCancelSendOtp(e) {
    e.preventDefault()
    setCancelError('')
    if (!/^\d{10}$/.test(cancelPhone)) {
      setCancelError('Enter a valid 10-digit phone number.')
      return
    }
    setCancelLoading(true)
    try {
      await apiPost('/api/account/deletion/request', { phone: cancelPhone })
      setCancelStep(1)
    } catch (err) {
      setCancelError(err.message)
    } finally {
      setCancelLoading(false)
    }
  }

  async function handleCancelConfirm(e) {
    e.preventDefault()
    setCancelError('')
    if (!/^\d{6}$/.test(cancelOtp)) {
      setCancelError('OTP must be exactly 6 digits.')
      return
    }
    setCancelLoading(true)
    try {
      await apiPost('/api/account/deletion/cancel', { phone: cancelPhone, otp: cancelOtp })
      setCancelSuccess(true)
    } catch (err) {
      setCancelError(err.message)
    } finally {
      setCancelLoading(false)
    }
  }

  // ── Shared input style ───────────────────────────────────────────────────

  const inputCls = `w-full px-4 py-3 rounded-xl text-sm border outline-none transition-all
    focus:ring-2 bg-white text-slate-800 placeholder-slate-400`
  const inputStyle = { borderColor: '#e2e8f0', focusRingColor: '#00e5c0' }

  const btnPrimary = (disabled) => ({
    background: disabled ? '#94a3b8' : 'linear-gradient(135deg, #0d1b3e, #1a3272)',
    cursor: disabled ? 'not-allowed' : 'pointer',
  })

  // ── Render ───────────────────────────────────────────────────────────────

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
          style={{ background: 'rgba(239,68,68,0.15)', color: '#fca5a5' }}
        >
          <AlertTriangle size={11} />
          Permanent Action
        </div>
        <h1 className="font-display text-4xl font-extrabold text-white mb-3">
          Delete Account
        </h1>
        <p className="text-white/45 max-w-sm mx-auto text-sm leading-relaxed">
          Permanently delete your Vittam account and all associated business data.
          This action cannot be undone after the 30-day grace period.
        </p>
      </div>

      <div className="max-w-xl mx-auto px-6 py-12">

        {/* ── Done state ────────────────────────────────────────────────── */}
        {step === 3 && (
          <div className="rounded-2xl p-8 text-center border border-slate-200 bg-white shadow-sm">
            <div
              className="w-14 h-14 rounded-full flex items-center justify-center mx-auto mb-4"
              style={{ background: 'rgba(239,68,68,0.08)' }}
            >
              <CheckCircle size={28} style={{ color: '#ef4444' }} />
            </div>
            <h2 className="font-display font-bold text-navy-900 text-xl mb-2">Request Received</h2>
            <p className="text-sm text-slate-500 leading-relaxed mb-2">
              Your account is scheduled for permanent deletion on:
            </p>
            <p className="font-bold text-navy-900 text-lg mb-5">
              {scheduled ? scheduled.toDateString() : '—'}
            </p>
            <div
              className="rounded-xl p-4 text-left text-sm text-slate-600 leading-relaxed mb-6"
              style={{ background: 'rgba(0,229,192,0.06)', border: '1px solid rgba(0,229,192,0.2)' }}
            >
              <strong className="text-navy-900">Changed your mind?</strong> You can cancel this request
              any time before the scheduled date using the cancellation form below.
            </div>
            <Link
              to="/"
              className="inline-block text-xs font-bold px-5 py-2.5 rounded-xl text-white"
              style={{ background: 'linear-gradient(135deg, #0d1b3e, #1a3272)' }}
            >
              Back to Home
            </Link>
          </div>
        )}

        {/* ── Multi-step deletion form ───────────────────────────────────── */}
        {step < 3 && (
          <div className="rounded-2xl border border-slate-200 bg-white shadow-sm overflow-hidden">

            {/* Warning banner */}
            <div
              className="px-6 py-4 flex items-start gap-3"
              style={{ background: 'rgba(239,68,68,0.06)', borderBottom: '1px solid rgba(239,68,68,0.12)' }}
            >
              <AlertTriangle size={18} className="flex-shrink-0 mt-0.5" style={{ color: '#ef4444' }} />
              <p className="text-xs text-slate-600 leading-relaxed">
                <strong className="text-red-600">All data will be permanently deleted</strong> — bills,
                items, expenses, staff accounts, and reports. You have 30 days to cancel after submitting.
              </p>
            </div>

            <div className="p-6">
              <Steps current={step} />

              {error && (
                <div
                  className="flex items-center gap-2 rounded-xl px-4 py-3 mb-5 text-sm"
                  style={{ background: 'rgba(239,68,68,0.08)', color: '#b91c1c' }}
                >
                  <XCircle size={15} className="flex-shrink-0" />
                  {error}
                </div>
              )}

              {/* Step 0 — Phone */}
              {step === 0 && (
                <form onSubmit={handleSendOtp} className="space-y-4">
                  <div>
                    <label className="block text-xs font-semibold text-slate-600 mb-1.5">
                      Registered Phone Number
                    </label>
                    <div className="relative">
                      <Phone size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
                      <input
                        type="tel"
                        inputMode="numeric"
                        maxLength={10}
                        placeholder="10-digit mobile number"
                        value={phone}
                        onChange={e => setPhone(e.target.value.replace(/\D/g, '').slice(0, 10))}
                        className={`${inputCls} pl-10`}
                        style={inputStyle}
                        required
                      />
                    </div>
                    <p className="text-xs text-slate-400 mt-1.5">
                      We'll send a one-time verification code to this number via WhatsApp.
                    </p>
                  </div>
                  <button
                    type="submit"
                    disabled={loading || phone.length !== 10}
                    className="w-full py-3 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2 transition-opacity"
                    style={btnPrimary(loading || phone.length !== 10)}
                  >
                    {loading && <Loader2 size={15} className="animate-spin" />}
                    {loading ? 'Sending OTP…' : 'Send Verification Code'}
                  </button>
                </form>
              )}

              {/* Step 1 — OTP */}
              {step === 1 && (
                <form onSubmit={handleOtpNext} className="space-y-4">
                  <div>
                    <label className="block text-xs font-semibold text-slate-600 mb-1.5">
                      Enter the 6-digit code sent to +91 {phone}
                    </label>
                    <div className="relative">
                      <KeyRound size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
                      <input
                        type="tel"
                        inputMode="numeric"
                        maxLength={6}
                        placeholder="6-digit OTP"
                        value={otp}
                        onChange={e => setOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
                        className={`${inputCls} pl-10 tracking-widest text-center font-mono text-lg`}
                        style={inputStyle}
                        autoFocus
                        required
                      />
                    </div>
                    <p className="text-xs text-slate-400 mt-1.5">
                      The code expires in 10 minutes.{' '}
                      <button
                        type="button"
                        className="font-semibold hover:opacity-70 transition-opacity"
                        style={{ color: '#00a88a' }}
                        onClick={() => { setOtp(''); setStep(0); clearError() }}
                      >
                        Change number
                      </button>
                    </p>
                  </div>
                  <button
                    type="submit"
                    disabled={otp.length !== 6}
                    className="w-full py-3 rounded-xl text-sm font-bold text-white transition-opacity"
                    style={btnPrimary(otp.length !== 6)}
                  >
                    Continue
                  </button>
                </form>
              )}

              {/* Step 2 — Final confirmation */}
              {step === 2 && (
                <form onSubmit={handleConfirm} className="space-y-5">
                  <div
                    className="rounded-xl p-4 text-sm leading-relaxed"
                    style={{ background: 'rgba(239,68,68,0.06)', border: '1px solid rgba(239,68,68,0.15)' }}
                  >
                    <p className="font-semibold text-red-700 mb-1">You are about to delete:</p>
                    <ul className="text-slate-600 space-y-0.5 list-disc list-inside text-xs">
                      <li>All bills and bill history</li>
                      <li>All items and inventory data</li>
                      <li>All expenses and reports</li>
                      <li>All staff accounts</li>
                      <li>Your business profile and settings</li>
                    </ul>
                  </div>

                  <div>
                    <label className="block text-xs font-semibold text-slate-600 mb-1.5">
                      Reason for leaving <span className="font-normal text-slate-400">(optional)</span>
                    </label>
                    <div className="relative">
                      <FileText size={15} className="absolute left-3.5 top-3.5 text-slate-400 pointer-events-none" />
                      <textarea
                        rows={3}
                        placeholder="Help us improve Vittam…"
                        value={reason}
                        onChange={e => setReason(e.target.value.slice(0, 500))}
                        className={`${inputCls} pl-10 resize-none`}
                        style={inputStyle}
                      />
                    </div>
                  </div>

                  <button
                    type="submit"
                    disabled={loading}
                    className="w-full py-3 rounded-xl text-sm font-bold flex items-center justify-center gap-2 transition-opacity"
                    style={{
                      background: loading ? '#fca5a5' : '#ef4444',
                      color: '#fff',
                      cursor: loading ? 'not-allowed' : 'pointer',
                    }}
                  >
                    {loading && <Loader2 size={15} className="animate-spin" />}
                    {loading ? 'Submitting…' : 'Yes, Delete My Account'}
                  </button>
                  <button
                    type="button"
                    className="w-full py-2.5 rounded-xl text-sm font-semibold border border-slate-200 text-slate-500 hover:border-slate-300 transition-colors bg-white"
                    onClick={() => { setStep(0); setOtp(''); setPhone(''); clearError() }}
                  >
                    Cancel — Keep My Account
                  </button>
                </form>
              )}
            </div>
          </div>
        )}

        {/* ── Cancel existing request ────────────────────────────────────── */}
        <div className="mt-10">
          <button
            type="button"
            className="text-sm font-semibold w-full text-center transition-colors hover:opacity-70"
            style={{ color: '#00a88a' }}
            onClick={() => { setShowCancel(v => !v); setCancelError(''); setCancelSuccess(false) }}
          >
            {showCancel ? 'Hide cancellation form ▲' : 'Already submitted a request? Cancel it here ▼'}
          </button>

          {showCancel && (
            <div className="mt-4 rounded-2xl border border-slate-200 bg-white shadow-sm overflow-hidden">
              <div className="px-6 py-4 border-b border-slate-100">
                <h3 className="font-display font-bold text-navy-900 text-sm">Cancel Deletion Request</h3>
                <p className="text-xs text-slate-400 mt-0.5">Verify your identity to cancel the pending request.</p>
              </div>
              <div className="p-6">
                {cancelSuccess ? (
                  <div className="flex items-center gap-3 text-sm" style={{ color: '#00a88a' }}>
                    <CheckCircle size={18} />
                    <span className="font-semibold">Your deletion request has been cancelled. Your account is safe.</span>
                  </div>
                ) : (
                  <>
                    {cancelError && (
                      <div
                        className="flex items-center gap-2 rounded-xl px-4 py-3 mb-4 text-sm"
                        style={{ background: 'rgba(239,68,68,0.08)', color: '#b91c1c' }}
                      >
                        <XCircle size={15} className="flex-shrink-0" />
                        {cancelError}
                      </div>
                    )}

                    {cancelStep === 0 && (
                      <form onSubmit={handleCancelSendOtp} className="space-y-4">
                        <div className="relative">
                          <Phone size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
                          <input
                            type="tel"
                            inputMode="numeric"
                            maxLength={10}
                            placeholder="Registered phone number"
                            value={cancelPhone}
                            onChange={e => setCancelPhone(e.target.value.replace(/\D/g, '').slice(0, 10))}
                            className={`${inputCls} pl-10`}
                            style={inputStyle}
                          />
                        </div>
                        <button
                          type="submit"
                          disabled={cancelLoading || cancelPhone.length !== 10}
                          className="w-full py-3 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2 transition-opacity"
                          style={btnPrimary(cancelLoading || cancelPhone.length !== 10)}
                        >
                          {cancelLoading && <Loader2 size={15} className="animate-spin" />}
                          {cancelLoading ? 'Sending OTP…' : 'Send Verification Code'}
                        </button>
                      </form>
                    )}

                    {cancelStep === 1 && (
                      <form onSubmit={handleCancelConfirm} className="space-y-4">
                        <div className="relative">
                          <KeyRound size={15} className="absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none" />
                          <input
                            type="tel"
                            inputMode="numeric"
                            maxLength={6}
                            placeholder="6-digit OTP"
                            value={cancelOtp}
                            onChange={e => setCancelOtp(e.target.value.replace(/\D/g, '').slice(0, 6))}
                            className={`${inputCls} pl-10 tracking-widest text-center font-mono text-lg`}
                            style={inputStyle}
                            autoFocus
                          />
                        </div>
                        <button
                          type="submit"
                          disabled={cancelLoading || cancelOtp.length !== 6}
                          className="w-full py-3 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2 transition-opacity"
                          style={btnPrimary(cancelLoading || cancelOtp.length !== 6)}
                        >
                          {cancelLoading && <Loader2 size={15} className="animate-spin" />}
                          {cancelLoading ? 'Cancelling…' : 'Cancel My Deletion Request'}
                        </button>
                      </form>
                    )}
                  </>
                )}
              </div>
            </div>
          )}
        </div>

        {/* Footer nav */}
        <div className="flex flex-wrap justify-center gap-6 mt-12 pt-8 border-t border-slate-200 text-xs text-slate-400">
          <Link to="/" className="hover:text-navy-900 transition-colors">Home</Link>
          <Link to="/help" className="hover:text-navy-900 transition-colors">Help Center</Link>
          <Link to="/privacy" className="hover:text-navy-900 transition-colors">Privacy Policy</Link>
          <a href="mailto:support@vengurlatech.com" className="hover:text-navy-900 transition-colors">Contact</a>
        </div>
      </div>
    </div>
  )
}