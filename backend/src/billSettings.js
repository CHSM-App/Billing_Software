'use strict';

const { isIndianMobile } = require('./validate');

/**
 * What prints on a bill — businesses.bill_settings (migration 061), JSON text.
 * The only place that knows the shape; frontend/lib/services/bill_settings.dart
 * mirrors it.
 *
 * Defaults reproduce the bill as it printed before this setting existed, so a
 * NULL column (every shop until its owner saves Billing Setup) changes nothing.
 * The logo switch is the older businesses.print_logo column and the terms text
 * is businesses.bill_footer_note — neither is duplicated here.
 */

const FLAGS = {
  show_address: true,
  show_phone: true,
  show_gstin: true,
  show_fssai: true,
  show_cashier: true,
  show_customer: true,
  show_tax_summary: true,
  show_terms: true,
  show_bank: false,
  show_note: false,
  // Warranty details captured at billing time (migration 065) — e.g. a
  // tyre's vehicle KM reading — printed on the receipt. Defaults on: a
  // "Retail & Warranty" shop wants this the moment it exists, and it has no
  // effect on any other business type since bills.warranty_extra_data is
  // only ever filled for a warranty-eligible sale.
  show_warranty_details: true,
};

// The shop-wide note printed on every bill ("Free delivery above Rs.500").
const NOTE_MAX = 300;

const BANK_MAX = {
  account_name: 100,
  account_no: 20,
  bank_name: 100,
  branch: 100,
  ifsc: 11,
  note: 200,
};

const IFSC_RE = /^[A-Z]{4}0[A-Z0-9]{6}$/;
const ACCOUNT_NO_RE = /^[0-9]{6,20}$/;
// What prints before the alternate number ("GPay", "WhatsApp"); empty = none.
const ALT_PHONE_LABEL_MAX = 20;

function defaults() {
  const bank = {};
  for (const k of Object.keys(BANK_MAX)) bank[k] = '';
  return { ...FLAGS, alt_phone: '', alt_phone_label: '', note: '', bank };
}

/** Column text → full settings object. Never throws; bad JSON = defaults. */
function parse(text) {
  const out = defaults();
  let raw;
  try { raw = text ? JSON.parse(text) : null; } catch { raw = null; }
  if (!raw || typeof raw !== 'object') return out;
  for (const k of Object.keys(FLAGS)) {
    if (typeof raw[k] === 'boolean') out[k] = raw[k];
  }
  if (typeof raw.alt_phone === 'string') out.alt_phone = raw.alt_phone;
  if (typeof raw.alt_phone_label === 'string') out.alt_phone_label = raw.alt_phone_label;
  if (typeof raw.note === 'string') out.note = raw.note;
  const bank = raw.bank && typeof raw.bank === 'object' ? raw.bank : {};
  for (const k of Object.keys(BANK_MAX)) {
    if (typeof bank[k] === 'string') out.bank[k] = bank[k];
  }
  return out;
}

/**
 * Validate a settings object from PUT /profile. Returns { value } (JSON text
 * for the column) or { error } (message for a 400). Unknown keys are dropped.
 */
function normalize(input) {
  if (!input || typeof input !== 'object' || Array.isArray(input)) {
    return { error: 'bill_settings must be an object' };
  }
  const out = defaults();
  for (const k of Object.keys(FLAGS)) {
    if (input[k] === undefined) continue;
    if (typeof input[k] !== 'boolean') return { error: `bill_settings.${k} must be true or false` };
    out[k] = input[k];
  }
  if (input.alt_phone != null) {
    if (typeof input.alt_phone !== 'string') return { error: 'bill_settings.alt_phone must be text' };
    out.alt_phone = input.alt_phone.trim();
    if (out.alt_phone && !isIndianMobile(out.alt_phone)) {
      return { error: 'Invalid alternate mobile number' };
    }
  }
  if (input.alt_phone_label != null) {
    if (typeof input.alt_phone_label !== 'string') {
      return { error: 'bill_settings.alt_phone_label must be text' };
    }
    out.alt_phone_label = input.alt_phone_label.trim();
    if (out.alt_phone_label.length > ALT_PHONE_LABEL_MAX) {
      return { error: `Alternate number label must be ${ALT_PHONE_LABEL_MAX} characters or less` };
    }
  }
  if (input.note != null) {
    if (typeof input.note !== 'string') return { error: 'bill_settings.note must be text' };
    out.note = input.note.trim();
    if (out.note.length > NOTE_MAX) return { error: `Note must be ${NOTE_MAX} characters or less` };
  }
  const bank = input.bank ?? {};
  if (typeof bank !== 'object' || Array.isArray(bank)) {
    return { error: 'bill_settings.bank must be an object' };
  }
  for (const [k, max] of Object.entries(BANK_MAX)) {
    const v = bank[k];
    if (v === undefined || v === null) continue;
    if (typeof v !== 'string') return { error: `bill_settings.bank.${k} must be text` };
    const t = v.trim();
    if (t.length > max) return { error: `Bank ${k.replace('_', ' ')} must be ${max} characters or less` };
    out.bank[k] = t;
  }
  out.bank.account_no = out.bank.account_no.replace(/\s/g, '');
  out.bank.ifsc = out.bank.ifsc.toUpperCase();
  if (out.bank.account_no && !ACCOUNT_NO_RE.test(out.bank.account_no)) {
    return { error: 'Account number must be 6–20 digits' };
  }
  if (out.bank.ifsc && !IFSC_RE.test(out.bank.ifsc)) {
    return { error: 'Invalid IFSC code (e.g. SBIN0001234)' };
  }
  return { value: JSON.stringify(out) };
}

/**
 * Bank-detail lines for the printed bill, or [] when the shop has not turned
 * them on or has no account number. Every renderer prints these as-is.
 */
function bankLines(s) {
  const b = s.bank;
  if (!s.show_bank || !b.account_no) return [];
  return [
    b.account_name && `A/c Name: ${b.account_name}`,
    `A/c No: ${b.account_no}`,
    b.bank_name && `Bank: ${b.bank_name}${b.branch ? `, ${b.branch}` : ''}`,
    !b.bank_name && b.branch && `Branch: ${b.branch}`,
    b.ifsc && `IFSC: ${b.ifsc}`,
    b.note,
  ].filter(Boolean);
}

/**
 * The shop's number(s) as printed, one per line: "9876500000\n9822012345", or
 * with a label on the alternate one: "9876500000\nGPay: 9822012345".
 */
function shopPhones(phone, s) {
  const alt = String(s.alt_phone || '').trim();
  const label = String(s.alt_phone_label || '').trim();
  return [String(phone || '').trim(), alt && label ? `${label}: ${alt}` : alt]
    .filter(Boolean).join('\n');
}

/** The shop-wide note to print, or '' when off or empty. */
function noteText(s) {
  return s.show_note ? s.note.trim() : '';
}

module.exports = { parse, normalize, defaults, bankLines, shopPhones, noteText };
