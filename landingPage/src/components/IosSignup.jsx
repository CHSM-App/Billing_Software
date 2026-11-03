import React, { useState } from 'react'
import { Link } from 'react-router-dom'
import Logo from './Logo'
import {
  ArrowLeft, Store, Phone, MapPin, User, Lock, Receipt, CreditCard, ShieldCheck,
  KeyRound, CheckCircle, XCircle, Loader2,
} from 'lucide-react'

import { API_BASE } from '../apiBase'

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

  return data || {}
}

// Mirrors register_screen.dart's validators so the server never rejects what
// this form already accepted.
const PHONE_RE = /^\d{10}$/
const PIN_RE = /^\d{4}$/
const GST_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z]{1}[1-9A-Z]{1}Z[0-9A-Z]{1}$/
const PAN_RE = /^[A-Z]{5}[0-9]{4}[A-Z]{1}$/
const FSSAI_RE = /^\d{14}$/

// ── Step indicator ───────────────────────────────────────────────────────────

function StepDot({ n, active, done }) {
  return (
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
  )
}

function Steps({ current }) {
  const labels = ['Business Details', 'Verify OTP', 'Done']
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

export default function IosSignup() {
  const [step, setStep] = useState(0) // 0=details, 1=otp, 2=done
  const [loading, setLoading] = useState(false)
  const [error, setError] = useState('')
  const [otp, setOtp] = useState('')

  const [form, setForm] = useState({
    businessName: '',
    businessType: 'retail',
    businessPhone: '',
    address: '',
    ownerName: '',
    ownerPhone: '',
    pin: '',
    confirmPin: '',
    gstNumber: '',
    panNumber: '',
    fssaiNumber: '',
    inventoryEnabled: false,
    acceptTerms: false,
  })

  function set(field, value) {
    setForm(f => ({ ...f, [field]: value }))
  }

  const isRestaurant = form.businessType === 'restaurant'

  function validateDetails() {
    if (!form.businessName.trim()) return 'Business name is required.'
    if (!PHONE_RE.test(form.businessPhone)) return 'Enter a valid 10-digit business phone number.'
    if (!form.ownerName.trim()) return 'Owner name is required.'
    if (!PHONE_RE.test(form.ownerPhone)) return 'Enter a valid 10-digit owner phone number.'
    if (!PIN_RE.test(form.pin)) return 'PIN must be exactly 4 digits.'
    if (form.confirmPin !== form.pin) return 'PINs do not match.'
    if (form.gstNumber && !GST_RE.test(form.gstNumber)) return 'Enter a valid GST number.'
    if (form.panNumber && !PAN_RE.test(form.panNumber)) return 'Enter a valid PAN number.'
    if (isRestaurant && form.fssaiNumber && !FSSAI_RE.test(form.fssaiNumber)) {
      return 'Enter a valid 14-digit FSSAI number.'
    }
    if (!form.acceptTerms) return 'Please accept the Terms of Service to continue.'
    return ''
  }

  // ── Step 0 → send OTP to owner phone ─────────────────────────────────────

  async function handleDetailsSubmit(e) {
    e.preventDefault()
    const v = validateDetails()
    if (v) { setError(v); return }
    setError('')
    setLoading(true)
    try {
      await apiPost('/api/send-otp', { phone: form.ownerPhone, purpose: 'register' })
      setStep(1)
    } catch (err) {
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  // ── Step 1 → verify OTP, then submit registration ────────────────────────

  async function handleOtpSubmit(e) {
    e.preventDefault()
    if (!/^\d{6}$/.test(otp)) { setError('OTP must be exactly 6 digits.'); return }
    setError('')
    setLoading(true)
    try {
      const { verified_token } = await apiPost('/api/verify-otp', {
        phone: form.ownerPhone, otp, purpose: 'register',
      })
      await apiPost('/api/register', {
        business_name: form.businessName.trim(),
        business_type: isRestaurant ? 'restaurant_with_tables' : form.businessType,
        address: form.address.trim() || undefined,
        phone: form.businessPhone,
        inventory_enabled: form.inventoryEnabled,
        has_barcode_scanner: true,
        owner_name: form.ownerName.trim(),
        owner_phone: form.ownerPhone,
        pin: form.pin,
        gst_number: form.gstNumber || undefined,
        pan_number: form.panNumber || undefined,
        fssai_number: isRestaurant ? (form.fssaiNumber || undefined) : undefined,
        verified_token,
        accept_terms: true,
      })
      setStep(2)
    } catch (err) {
      if (err.message.toLowerCase().includes('otp')) {
        setOtp('')
      }
      setError(err.message)
    } finally {
      setLoading(false)
    }
  }

  // ── Shared styles ─────────────────────────────────────────────────────────

  const inputCls = `w-full px-4 py-3 rounded-xl text-sm border outline-none transition-all
    focus:ring-2 bg-white text-slate-800 placeholder-slate-400`
  const inputStyle = { borderColor: '#e2e8f0', focusRingColor: '#00e5c0' }

  const btnPrimary = (disabled) => ({
    background: disabled ? '#94a3b8' : 'linear-gradient(135deg, #0d1b3e, #1a3272)',
    cursor: disabled ? 'not-allowed' : 'pointer',
  })

  const field = (label, icon, input) => (
    <div>
      <label className="block text-xs font-semibold text-slate-600 mb-1.5">{label}</label>
      <div className="relative">
        {React.createElement(icon, {
          size: 15,
          className: 'absolute left-3.5 top-1/2 -translate-y-1/2 text-slate-400 pointer-events-none',
        })}
        {input}
      </div>
    </div>
  )

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
        <h1 className="font-display text-4xl font-extrabold text-white mb-3">
          Create Your Business Account
        </h1>
        <p className="text-white/45 max-w-sm mx-auto text-sm leading-relaxed">
          Set up your shop's billing account. Once created, log in from the Vittam iOS app
          using the owner phone number and PIN you set here.
        </p>
      </div>

      <div className="max-w-xl mx-auto px-6 py-12">
        {/* ── Done state ──────────────────────────────────────────────────── */}
        {step === 2 && (
          <div className="rounded-2xl p-8 text-center border border-slate-200 bg-white shadow-sm">
            <div
              className="w-14 h-14 rounded-full flex items-center justify-center mx-auto mb-4"
              style={{ background: 'rgba(0,229,192,0.1)' }}
            >
              <CheckCircle size={28} style={{ color: '#00a88a' }} />
            </div>
            <h2 className="font-display font-bold text-navy-900 text-xl mb-2">Account Created</h2>
            <p className="text-sm text-slate-500 leading-relaxed mb-6">
              Open the Vittam app on your iPhone and log in with your owner phone number
              (+91 {form.ownerPhone}) and the 4-digit PIN you just set.
            </p>
            <Link
              to="/"
              className="inline-block text-xs font-bold px-5 py-2.5 rounded-xl text-white"
              style={{ background: 'linear-gradient(135deg, #0d1b3e, #1a3272)' }}
            >
              Back to Home
            </Link>
          </div>
        )}

        {/* ── Multi-step signup form ─────────────────────────────────────── */}
        {step < 2 && (
          <div className="rounded-2xl border border-slate-200 bg-white shadow-sm overflow-hidden">
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

              {/* Step 0 — Business & owner details */}
              {step === 0 && (
                <form onSubmit={handleDetailsSubmit} className="space-y-4">
                  {field('Business Name', Store,
                    <input
                      type="text"
                      placeholder="e.g. Sharma General Store"
                      value={form.businessName}
                      onChange={e => set('businessName', e.target.value)}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                      required
                    />
                  )}

                  {field('Business Phone', Phone,
                    <input
                      type="tel"
                      inputMode="numeric"
                      maxLength={10}
                      placeholder="10-digit mobile number"
                      value={form.businessPhone}
                      onChange={e => set('businessPhone', e.target.value.replace(/\D/g, '').slice(0, 10))}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                      required
                    />
                  )}

                  {field('Address (optional)', MapPin,
                    <input
                      type="text"
                      placeholder="Shop address"
                      value={form.address}
                      onChange={e => set('address', e.target.value)}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                    />
                  )}

                  <div>
                    <label className="block text-xs font-semibold text-slate-600 mb-1.5">Business Type</label>
                    <div className="flex gap-2">
                      {[['retail', 'Retail'], ['restaurant', 'Restaurant']].map(([val, label]) => (
                        <button
                          key={val}
                          type="button"
                          onClick={() => set('businessType', val)}
                          className="flex-1 py-2.5 rounded-xl text-sm font-semibold border transition-colors"
                          style={
                            form.businessType === val
                              ? { background: 'rgba(0,229,192,0.1)', borderColor: '#00a88a', color: '#0d1b3e' }
                              : { background: '#fff', borderColor: '#e2e8f0', color: '#64748b' }
                          }
                        >
                          {label}
                        </button>
                      ))}
                    </div>
                  </div>

                  <label className="flex items-center gap-2 text-xs text-slate-600">
                    <input
                      type="checkbox"
                      checked={form.inventoryEnabled}
                      onChange={e => set('inventoryEnabled', e.target.checked)}
                    />
                    Enable inventory tracking
                  </label>

                  <div className="pt-2 border-t border-slate-100" />

                  {field('Owner Name', User,
                    <input
                      type="text"
                      placeholder="Owner's full name"
                      value={form.ownerName}
                      onChange={e => set('ownerName', e.target.value)}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                      required
                    />
                  )}

                  {field('Owner Phone', Phone,
                    <input
                      type="tel"
                      inputMode="numeric"
                      maxLength={10}
                      placeholder="10-digit mobile number (used to log in)"
                      value={form.ownerPhone}
                      onChange={e => set('ownerPhone', e.target.value.replace(/\D/g, '').slice(0, 10))}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                      required
                    />
                  )}

                  <div className="grid grid-cols-2 gap-3">
                    {field('PIN', Lock,
                      <input
                        type="password"
                        inputMode="numeric"
                        maxLength={4}
                        placeholder="4-digit PIN"
                        value={form.pin}
                        onChange={e => set('pin', e.target.value.replace(/\D/g, '').slice(0, 4))}
                        className={`${inputCls} pl-10`}
                        style={inputStyle}
                        required
                      />
                    )}
                    {field('Confirm PIN', Lock,
                      <input
                        type="password"
                        inputMode="numeric"
                        maxLength={4}
                        placeholder="Re-enter PIN"
                        value={form.confirmPin}
                        onChange={e => set('confirmPin', e.target.value.replace(/\D/g, '').slice(0, 4))}
                        className={`${inputCls} pl-10`}
                        style={inputStyle}
                        required
                      />
                    )}
                  </div>

                  <div className="pt-2 border-t border-slate-100" />
                  <p className="text-xs text-slate-400">Tax details (optional)</p>

                  {field('GST Number', Receipt,
                    <input
                      type="text"
                      maxLength={15}
                      placeholder="GSTIN"
                      value={form.gstNumber}
                      onChange={e => set('gstNumber', e.target.value.toUpperCase().slice(0, 15))}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                    />
                  )}

                  {field('PAN Number', CreditCard,
                    <input
                      type="text"
                      maxLength={10}
                      placeholder="PAN"
                      value={form.panNumber}
                      onChange={e => set('panNumber', e.target.value.toUpperCase().slice(0, 10))}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                    />
                  )}

                  {isRestaurant && field('FSSAI Number', ShieldCheck,
                    <input
                      type="text"
                      inputMode="numeric"
                      maxLength={14}
                      placeholder="14-digit FSSAI licence"
                      value={form.fssaiNumber}
                      onChange={e => set('fssaiNumber', e.target.value.replace(/\D/g, '').slice(0, 14))}
                      className={`${inputCls} pl-10`}
                      style={inputStyle}
                    />
                  )}

                  <label className="flex items-start gap-2 text-xs text-slate-600 pt-2">
                    <input
                      type="checkbox"
                      className="mt-0.5"
                      checked={form.acceptTerms}
                      onChange={e => set('acceptTerms', e.target.checked)}
                    />
                    <span>
                      I agree to the{' '}
                      <Link to="/terms" target="_blank" className="font-semibold" style={{ color: '#00a88a' }}>
                        Terms of Service
                      </Link>{' '}
                      and{' '}
                      <Link to="/privacy" target="_blank" className="font-semibold" style={{ color: '#00a88a' }}>
                        Privacy Policy
                      </Link>.
                    </span>
                  </label>

                  <button
                    type="submit"
                    disabled={loading}
                    className="w-full py-3 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2 transition-opacity"
                    style={btnPrimary(loading)}
                  >
                    {loading && <Loader2 size={15} className="animate-spin" />}
                    {loading ? 'Sending OTP…' : 'Continue'}
                  </button>
                </form>
              )}

              {/* Step 1 — OTP */}
              {step === 1 && (
                <form onSubmit={handleOtpSubmit} className="space-y-4">
                  {field(`Enter the 6-digit code sent to +91 ${form.ownerPhone}`, KeyRound,
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
                  )}
                  <p className="text-xs text-slate-400 -mt-2">
                    The code expires in 10 minutes.{' '}
                    <button
                      type="button"
                      className="font-semibold hover:opacity-70 transition-opacity"
                      style={{ color: '#00a88a' }}
                      onClick={() => { setOtp(''); setStep(0); setError('') }}
                    >
                      Change details
                    </button>
                  </p>
                  <button
                    type="submit"
                    disabled={loading || otp.length !== 6}
                    className="w-full py-3 rounded-xl text-sm font-bold text-white flex items-center justify-center gap-2 transition-opacity"
                    style={btnPrimary(loading || otp.length !== 6)}
                  >
                    {loading && <Loader2 size={15} className="animate-spin" />}
                    {loading ? 'Creating account…' : 'Verify & Create Account'}
                  </button>
                </form>
              )}
            </div>
          </div>
        )}

        {/* Footer nav */}
        <div className="flex flex-wrap justify-center gap-6 mt-12 pt-8 border-t border-slate-200 text-xs text-slate-400">
          <Link to="/" className="hover:text-navy-900 transition-colors">Home</Link>
          <Link to="/help" className="hover:text-navy-900 transition-colors">Help Center</Link>
          <a href="mailto:support@vengurlatech.com" className="hover:text-navy-900 transition-colors">Contact</a>
        </div>
      </div>
    </div>
  )
}
