/*
 * SMSala WhatsApp Messaging Service
 * Docs: https://api2.smsala.com
 *
 * Sends OTP messages via WhatsApp for business registration verification
 * and forgot-PIN flow.
 *
 * Set WHATSAPP_ENABLED=true in .env to activate.
 * Failures are logged but never throw — they must not break the main request flow.
 *
 * All sends (sent / failed / skipped) are recorded in whatsapp_otp_log.
 */

const https  = require('https')
const crypto = require('crypto')
const { pool, poolConnect, sql } = require('./db')
const logger = require('./logger')

const API_TOKEN           = process.env.WHATSAPP_API_TOKEN        || ''
const ENABLED             = process.env.WHATSAPP_ENABLED === 'true'
const OTP_TEMPLATE        = process.env.WHATSAPP_TPL_OTP           || ''
const BILL_TEMPLATE       = process.env.WHATSAPP_TPL_BILL          || ''
const ONBOARDING_TEMPLATE = process.env.WHATSAPP_TPL_ONBOARDING    || ''
const ADMIN_PHONE         = process.env.WHATSAPP_ADMIN_PHONE        || ''

// OTP config
const OTP_EXPIRY_MINUTES = 10
const OTP_LENGTH         = 6

// ─────────────────────────────────────────────────────────────────────────────
// HTTP helper — JSON POST to api2.smsala.com
// ─────────────────────────────────────────────────────────────────────────────

function postJson(path, body) {
  return new Promise((resolve, reject) => {
    const payload = JSON.stringify(body)
    const options = {
      hostname: 'api2.smsala.com',
      path,
      method: 'POST',
      headers: {
        'Content-Type':   'application/json',
        'Content-Length': Buffer.byteLength(payload),
      },
    }
    const req = https.request(options, res => {
      let data = ''
      res.on('data', chunk => { data += chunk })
      res.on('end', () => {
        try { resolve(JSON.parse(data)) }
        catch { resolve({ raw: data }) }
      })
    })
    req.on('error', reject)
    req.write(payload)
    req.end()
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// Phone normaliser — returns "91XXXXXXXXXX" or null
// ─────────────────────────────────────────────────────────────────────────────

function normalisePhone(raw) {
  if (!raw) return null
  const digits = String(raw).replace(/\D/g, '')
  if (digits.length === 10)                                return `91${digits}`
  if (digits.length === 12 && digits.startsWith('91'))     return digits
  if (digits.length === 11 && digits.startsWith('0'))      return `91${digits.slice(1)}`
  return null
}

// ─────────────────────────────────────────────────────────────────────────────
// OTP generator
// ─────────────────────────────────────────────────────────────────────────────

function generateOtp() {
  // Cryptographically random 6-digit OTP (000000 – 999999)
  const buf = crypto.randomBytes(4)
  const num = buf.readUInt32BE(0) % 1_000_000
  return String(num).padStart(OTP_LENGTH, '0')
}

// ─────────────────────────────────────────────────────────────────────────────
// DB helpers
// ─────────────────────────────────────────────────────────────────────────────

async function saveOtp(phone, otpCode, purpose) {
  await poolConnect
  const otpHash  = crypto.createHash('sha256').update(otpCode).digest('hex')
  const expiresAt = new Date(Date.now() + OTP_EXPIRY_MINUTES * 60 * 1000)

  // Invalidate any previous unused OTPs for this phone+purpose
  await pool.request()
    .input('phone',   sql.NVarChar(20), phone)
    .input('purpose', sql.NVarChar(20), purpose)
    .query(`
      UPDATE whatsapp_otp_log
      SET used = 1
      WHERE phone = @phone AND purpose = @purpose AND used = 0
    `)

  await pool.request()
    .input('phone',      sql.NVarChar(20),  phone)
    .input('purpose',    sql.NVarChar(20),  purpose)
    .input('otp_hash',   sql.NVarChar(64),  otpHash)
    .input('expires_at', sql.DateTime2,     expiresAt)
    .query(`
      INSERT INTO whatsapp_otp_log (phone, purpose, otp_hash, expires_at)
      VALUES (@phone, @purpose, @otp_hash, @expires_at)
    `)
}

async function logSendResult(phone, purpose, status, campaignId, errorDetail) {
  try {
    await pool.request()
      .input('phone',        sql.NVarChar(20),   phone        || null)
      .input('purpose',      sql.NVarChar(20),   purpose      || null)
      .input('status',       sql.NVarChar(20),   status       || 'sent')
      .input('campaign_id',  sql.NVarChar(100),  campaignId   ? String(campaignId) : null)
      .input('error_detail', sql.NVarChar(500),  errorDetail  || null)
      .query(`
        UPDATE TOP(1) whatsapp_otp_log
        SET status = @status, campaign_id = @campaign_id, error_detail = @error_detail
        WHERE phone = @phone AND purpose = @purpose
          AND created_at = (
            SELECT MAX(created_at) FROM whatsapp_otp_log
            WHERE phone = @phone AND purpose = @purpose
          )
      `)
  } catch (e) {
    logger.warn({ err: e }, '[WhatsApp] DB log update failed')
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// sendOtp — generates, stores, and delivers the OTP via WhatsApp
//
// purpose: 'register' | 'forgot_pin'
// Returns: { sent: true } on success, throws on hard failure
// ─────────────────────────────────────────────────────────────────────────────

async function sendOtp(phone, purpose) {
  const normPhone = normalisePhone(phone)
  if (!normPhone) throw new Error('Invalid phone number.')

  if (!ENABLED) {
    // In dev/test mode, still generate + store the OTP so verify works,
    // just skip the actual WhatsApp delivery.
    const otpCode = generateOtp()
    await saveOtp(normPhone, otpCode, purpose)
    logger.info(`[WhatsApp] Disabled — OTP for ${normPhone} (${purpose}): ${otpCode}`)
    // Return the OTP in dev so it can be used without a real phone
    return { sent: false, dev_otp: process.env.NODE_ENV !== 'production' ? otpCode : undefined }
  }

  if (!API_TOKEN || API_TOKEN.startsWith('REPLACE')) {
    throw new Error('WhatsApp API token not configured.')
  }

  const otpCode = generateOtp()
  await saveOtp(normPhone, otpCode, purpose)

  let result
  try {
    result = await postJson('/whatsapp/SendOtp', {
      PhoneNumber: normPhone,
      OtpCode:     otpCode,
      ApiToken:    API_TOKEN,
      TemplateId:  OTP_TEMPLATE || undefined,
    })
  } catch (err) {
    await logSendResult(normPhone, purpose, 'failed', null, err.message)
    throw new Error('Failed to send OTP. Please try again.')
  }

  const success = result.IsSuccess === true || result.ErrorCode === 0
  await logSendResult(
    normPhone, purpose,
    success ? 'sent' : 'failed',
    result.ReturnData,
    success ? null : (result.ErrorDescription || JSON.stringify(result)),
  )

  if (!success) {
    throw new Error(result.ErrorDescription || 'OTP delivery failed.')
  }

  logger.info(`[WhatsApp] OTP sent to ${normPhone} (${purpose}) — CampaignId: ${result.ReturnData}`)
  return { sent: true }
}

// ─────────────────────────────────────────────────────────────────────────────
// verifyOtp — checks OTP and marks it used on success
//
// Returns true if valid, false if wrong/expired/already-used
// ─────────────────────────────────────────────────────────────────────────────

async function verifyOtp(phone, otpCode, purpose) {
  const normPhone = normalisePhone(phone)
  if (!normPhone) return false

  await poolConnect
  const otpHash = crypto.createHash('sha256').update(String(otpCode)).digest('hex')

  const result = await pool.request()
    .input('phone',      sql.NVarChar(20), normPhone)
    .input('purpose',    sql.NVarChar(20), purpose)
    .input('otp_hash',   sql.NVarChar(64), otpHash)
    .input('now',        sql.DateTime2,    new Date())
    .query(`
      SELECT id FROM whatsapp_otp_log
      WHERE phone     = @phone
        AND purpose   = @purpose
        AND otp_hash  = @otp_hash
        AND used      = 0
        AND expires_at > @now
    `)

  if (result.recordset.length === 0) return false

  // Mark as used
  await pool.request()
    .input('id', sql.UniqueIdentifier, result.recordset[0].id)
    .query(`UPDATE whatsapp_otp_log SET used = 1 WHERE id = @id`)

  return true
}

// ─────────────────────────────────────────────────────────────────────────────
// HTTP helper — form-encoded POST (used by SendMessage)
// ─────────────────────────────────────────────────────────────────────────────

function postForm(path, body) {
  return new Promise((resolve, reject) => {
    const payload = Object.entries(body)
      .map(([k, v]) => `${encodeURIComponent(k)}=${encodeURIComponent(v)}`)
      .join('&')
    const options = {
      hostname: 'api2.smsala.com',
      path,
      method: 'POST',
      headers: {
        'Content-Type':   'application/x-www-form-urlencoded',
        'Content-Length': Buffer.byteLength(payload),
      },
    }
    const req = https.request(options, res => {
      let data = ''
      res.on('data', chunk => { data += chunk })
      res.on('end', () => {
        try { resolve(JSON.parse(data)) }
        catch { resolve({ raw: data }) }
      })
    })
    req.on('error', reject)
    req.write(payload)
    req.end()
  })
}

// ─────────────────────────────────────────────────────────────────────────────
// sendBillLink — sends a receipt URL to a customer via WhatsApp template
//
// Template variables: {1} shop_name  {2} bill_number  {3} receipt_url
//
// Never throws — failures are logged and returned as { sent: false, error }.
// ─────────────────────────────────────────────────────────────────────────────

async function sendBillLink({ phone, shopName, billNumber, receiptUrl }) {
  const normPhone = normalisePhone(phone)
  if (!normPhone) return { sent: false, error: 'Invalid phone number' }

  if (!ENABLED) {
    logger.info(`[WhatsApp] Disabled — would send receipt link for #${billNumber} to ${normPhone}`)
    return { sent: false, skipped: true }
  }

  if (!API_TOKEN || API_TOKEN.startsWith('REPLACE')) {
    logger.warn('[WhatsApp] API token not configured — skipping bill send')
    return { sent: false, error: 'API token not configured' }
  }

  if (!BILL_TEMPLATE || BILL_TEMPLATE.startsWith('REPLACE')) {
    logger.warn('[WhatsApp] Bill template ID not configured — skipping')
    return { sent: false, error: 'Bill template not configured' }
  }

  // Sample: comma-separated values matching template placeholders in order.
  const clean = (v) => String(v).replace(/,/g, '')
  const sample = [clean(shopName), clean(billNumber), receiptUrl].join(',')

  let result
  try {
    result = await postForm('/whatsapp/SendMessage', {
      ApiToken:     API_TOKEN,
      TemplateId:   BILL_TEMPLATE,
      QuickNumber:  normPhone,
      Sample:       sample,
      CampaignName: 'bill_receipt',
    })
  } catch (err) {
    logger.error({ err }, `[WhatsApp] Network error sending receipt link for #${billNumber}`)
    return { sent: false, error: err.message }
  }

  const success = result.IsSuccess === true || result.ErrorCode === 0
  if (success) {
    logger.info(`[WhatsApp] Receipt link for #${billNumber} sent to ${normPhone} — CampaignId: ${result.ReturnData}`)
  } else {
    logger.warn({ result }, `[WhatsApp] Receipt link send failed for #${billNumber}`)
  }

  return success
    ? { sent: true, campaignId: result.ReturnData }
    : { sent: false, error: result.ErrorDescription || JSON.stringify(result) }
}

// ─────────────────────────────────────────────────────────────────────────────
// sendOnboardingAlert — notifies admin when a new business registers
//
// Template variables: {1} business_name  {2} owner_name  {3} phone  {4} business_type
//
// Never throws — failures are only logged.
// ─────────────────────────────────────────────────────────────────────────────

async function sendOnboardingAlert({ businessName, ownerName, phone, businessType }) {
  if (!ENABLED) {
    logger.info(`[WhatsApp] Disabled — onboarding alert for "${businessName}" skipped`)
    return { sent: false, skipped: true }
  }

  if (!API_TOKEN || API_TOKEN.startsWith('REPLACE')) {
    logger.warn('[WhatsApp] API token not configured — skipping onboarding alert')
    return { sent: false, error: 'API token not configured' }
  }

  if (!ONBOARDING_TEMPLATE || ONBOARDING_TEMPLATE.startsWith('REPLACE')) {
    logger.warn('[WhatsApp] Onboarding template ID not configured — skipping')
    return { sent: false, error: 'Onboarding template not configured' }
  }

  const normAdmin = normalisePhone(ADMIN_PHONE)
  if (!normAdmin) {
    logger.warn('[WhatsApp] WHATSAPP_ADMIN_PHONE not set — skipping onboarding alert')
    return { sent: false, error: 'Admin phone not configured' }
  }

  const clean = (v) => String(v).replace(/,/g, '')
  const sample = [
    clean(businessName),
    clean(ownerName),
    clean(phone),
    clean(businessType),
  ].join(',')

  let result
  try {
    result = await postForm('/whatsapp/SendMessage', {
      ApiToken:     API_TOKEN,
      TemplateId:   ONBOARDING_TEMPLATE,
      QuickNumber:  normAdmin,
      Sample:       sample,
      CampaignName: 'onboarding_alert',
    })
  } catch (err) {
    logger.error({ err }, `[WhatsApp] Network error sending onboarding alert for "${businessName}"`)
    return { sent: false, error: err.message }
  }

  const success = result.IsSuccess === true || result.ErrorCode === 0
  if (success) {
    logger.info(`[WhatsApp] Onboarding alert sent for "${businessName}" — CampaignId: ${result.ReturnData}`)
  } else {
    logger.warn({ result }, `[WhatsApp] Onboarding alert failed for "${businessName}"`)
  }

  return success
    ? { sent: true, campaignId: result.ReturnData }
    : { sent: false, error: result.ErrorDescription || JSON.stringify(result) }
}

module.exports = { sendOtp, verifyOtp, normalisePhone, sendBillLink, sendOnboardingAlert }
