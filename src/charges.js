// Additional charges on a bill — delivery, packaging, service, etc.
//
// Storage model (see migration 035):
//   bills.additional_charges  NVARCHAR(MAX) JSON: [{ "name": "Delivery", "amount": 30 }, ...]
//   bills.charges_amount      DECIMAL(10,2)  the sum of those amounts
//
// Reconciliation: charges are folded INTO bills.total —
//   total = subtotal + tax_amount + charges_amount
// so the existing payable identity (total − discount_amount + round_off) and
// every report/credit query built on it keep working unchanged. Charges are
// NOT part of the taxable base: no GST is applied to them and the discount
// (which is clamped to the item subtotal) never reduces them.

const MAX_CHARGES = 10;
const MAX_NAME_LEN = 100;
// DECIMAL(10,2) ceiling — a single charge beyond this can't be stored anyway.
const MAX_AMOUNT = 99999999.99;

/**
 * Validate and normalise the `additional_charges` array from a request body.
 *
 * Returns `{ charges, chargesAmount }` on success, where `charges` is the clean
 * list to persist (names trimmed, amounts rounded to 2 dp) and `chargesAmount`
 * their sum; or `{ error }` with a client-facing message.
 *
 * `undefined`/`null` means "no charges" — callers decide whether that clears
 * an existing value (update) or simply defaults to none (create).
 */
function parseAdditionalCharges(raw) {
  if (raw === undefined || raw === null) return { charges: [], chargesAmount: 0 };
  if (!Array.isArray(raw)) {
    return { error: 'additional_charges must be an array of { name, amount }' };
  }
  if (raw.length > MAX_CHARGES) {
    return { error: `additional_charges may contain at most ${MAX_CHARGES} entries` };
  }
  const charges = [];
  for (const c of raw) {
    if (!c || typeof c !== 'object' || Array.isArray(c)) {
      return { error: 'each additional charge must be an object with name and amount' };
    }
    const name = typeof c.name === 'string' ? c.name.trim() : '';
    if (!name) return { error: 'additional charge name is required' };
    if (name.length > MAX_NAME_LEN) {
      return { error: `additional charge name must be at most ${MAX_NAME_LEN} characters` };
    }
    const amount = typeof c.amount === 'number' ? c.amount : Number(c.amount);
    if (!Number.isFinite(amount) || amount <= 0 || amount > MAX_AMOUNT) {
      return { error: `additional charge "${name}" must have an amount greater than 0` };
    }
    charges.push({ name, amount: parseFloat(amount.toFixed(2)) });
  }
  const chargesAmount = parseFloat(
    charges.reduce((s, c) => s + c.amount, 0).toFixed(2));
  return { charges, chargesAmount };
}

/** JSON to persist in bills.additional_charges — NULL when there are none. */
function serializeCharges(charges) {
  return charges && charges.length > 0 ? JSON.stringify(charges) : null;
}

/**
 * Normalise a bills row for API output: parse the stored JSON into an array
 * (always present, possibly empty) and default charges_amount to 0. Mutates and
 * returns the row so it can be used inline in a `.map()`.
 */
function attachCharges(row) {
  if (!row) return row;
  let list = [];
  const raw = row.additional_charges;
  if (typeof raw === 'string' && raw.trim()) {
    try {
      const parsed = JSON.parse(raw);
      if (Array.isArray(parsed)) list = parsed;
    } catch (_) { /* corrupt JSON → treat as no charges rather than 500 */ }
  } else if (Array.isArray(raw)) {
    list = raw;
  }
  row.additional_charges = list;
  if (row.charges_amount === undefined || row.charges_amount === null) {
    row.charges_amount = 0;
  }
  return row;
}

module.exports = { parseAdditionalCharges, serializeCharges, attachCharges, MAX_CHARGES };
