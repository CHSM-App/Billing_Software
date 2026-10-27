// ---------------------------------------------------------------------------
// Shared field validation for money and stock columns.
//
// Without these a bad value either reaches SQL Server and surfaces as an opaque
// 500 (a string in a DECIMAL, a value past the column's precision), or is
// silently coerced into something the user never typed — NaN, Infinity, or a
// truncated string on a real invoice.
//
// Every helper returns an error STRING or null, so a route can chain them:
//
//   const invalid = validateText(name, 'Name', 200, { required: true })
//     || validateNumber(price, 'Price');
//   if (invalid) return res.status(400).json({ error: invalid });
// ---------------------------------------------------------------------------

// Largest value DECIMAL(10,2) can hold — prices and stock. Past this SQL Server
// raises an arithmetic overflow.
const MAX_DECIMAL_10_2 = 99999999.99;
// Largest value DECIMAL(12,4) can hold — item_recipes.quantity.
const MAX_DECIMAL_12_4 = 99999999.9999;

/// Validates an optional non-negative number. Returns null when [value] is
/// absent (undefined/null/'') or acceptable.
///
/// Number.isFinite rejects NaN and Infinity explicitly: `parseFloat('abc')` is
/// NaN and `parseFloat('1e999')` is Infinity, and both bind to a DECIMAL column
/// without complaint on some drivers.
function validateNumber(value, label, { max = MAX_DECIMAL_10_2, allowZero = true } = {}) {
  if (value === undefined || value === null || value === '') return null;
  const n = parseFloat(value);
  if (!Number.isFinite(n)) return `${label} must be a number`;
  if (n < 0) return `${label} cannot be negative`;
  if (!allowZero && n === 0) return `${label} must be greater than zero`;
  if (n > max) return `${label} is too large`;
  return null;
}

/// Validates an optional integer. A non-numeric value binds as NaN to sql.Int
/// and fails at the driver as a 500.
function validateInteger(value, label) {
  if (value === undefined || value === null || value === '') return null;
  const n = Number(value);
  if (!Number.isInteger(n)) return `${label} must be a whole number`;
  if (n < 0) return `${label} cannot be negative`;
  return null;
}

/// Validates a string bound for NVARCHAR([len]). Over-length input is silently
/// TRUNCATED by the driver rather than rejected, so a 60-character size label
/// would save as 50 and quietly differ from what the user typed.
function validateText(value, label, len, { required = false } = {}) {
  if (value === undefined || value === null) {
    return required ? `${label} is required` : null;
  }
  const s = String(value).trim();
  if (required && s.length === 0) return `${label} is required`;
  if (s.length > len) return `${label} must be ${len} characters or fewer`;
  return null;
}

/// Validates a value against a fixed set. Guards columns whose meaning depends
/// on the string matching what the app expects (units drive stock conversion).
function validateEnum(value, label, allowed) {
  if (value === undefined || value === null || value === '') return null;
  if (!allowed.includes(String(value))) {
    return `${label} must be one of: ${allowed.join(', ')}`;
  }
  return null;
}

// Largest number of {label, value} pairs an extra_data array may carry —
// shared by routes/warranties.js (a warranty record's own extra_data) and
// routes/bills.js (warranty details captured at billing time, migration 065).
const MAX_EXTRA_DATA = 30;

/// Validates an extra_data array — labeled pairs, e.g. warranty details
/// filled from a category template plus any ad-hoc rows staff added. Values
/// are always stored as strings; any type-specific rendering (number/date)
/// is a UI concern, not a storage concern.
function validateExtraData(extraData) {
  if (extraData === undefined || extraData === null) return null;
  if (!Array.isArray(extraData)) return 'extra_data must be an array';
  if (extraData.length > MAX_EXTRA_DATA) return `At most ${MAX_EXTRA_DATA} extra fields are allowed`;
  for (const e of extraData) {
    if (!e || typeof e !== 'object') return 'each extra_data entry must be an object';
    if (validateText(e.label, 'Extra field label', 100, { required: true })) {
      return 'each extra_data entry needs a label';
    }
    if (e.value != null && String(e.value).length > 500) {
      return 'each extra_data value must be 500 characters or fewer';
    }
  }
  return null;
}

/// Indian mobile number: 10 digits starting 6–9. Login/OTP routes keep the
/// looser /^\d{10}$/ so an account created before this rule still signs in.
/// Mirrors isIndianMobile() in frontend/lib/utils/text_formatters.dart.
const isIndianMobile = (v) => /^[6-9]\d{9}$/.test(String(v ?? ''));

module.exports = {
  isIndianMobile,
  MAX_DECIMAL_10_2,
  MAX_DECIMAL_12_4,
  validateNumber,
  validateInteger,
  validateText,
  validateEnum,
  validateExtraData,
};
