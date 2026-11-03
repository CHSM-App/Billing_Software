// Money helpers shared across billing routes.
//
// Round-off model: the round-off is computed on the FINAL payable
// (total - discount), never on the individual subtotal/tax/discount values,
// which stay exactly as calculated. Rounding is "round half up" to the nearest
// whole rupee:
//   125.22 -> 125.00  (round_off -0.22)
//   125.60 -> 126.00  (round_off +0.40)
//   125.50 -> 126.00  (round_off +0.50)

/**
 * Compute the signed round-off for a payable amount, rounding half up to the
 * nearest rupee. Returns 0 when [enabled] is false so callers can always add it.
 *
 * @param {number} payable  the calculated total the customer would otherwise pay
 *                          (typically total - discount_amount)
 * @param {boolean} enabled whether rounding is turned on for this business
 * @returns {number} signed round-off, 2-decimal precision (rounded - payable)
 */
function computeRoundOff(payable, enabled) {
  if (!enabled) return 0;
  const amt = Number(payable) || 0;
  // Math.round is round-half-up for positive numbers, which is what we want
  // (125.50 -> 126). Bill payables are always >= 0.
  const rounded = Math.round(amt);
  return parseFloat((rounded - amt).toFixed(2));
}

/**
 * Convert a stored item price into the NET (pre-tax) unit rate used for billing.
 *
 * An item's price is quoted one of two ways (items.price_inclusive_tax):
 *   exclusive — the price IS the net rate; tax is added on top.  20 @5% -> 21.00
 *   inclusive — the price is the GROSS/MRP the customer pays and
 *               already contains the tax.                        20 @5% -> 20.00
 *
 * Billing is uniform on net rates — bill_items.unit_price is always net — so an
 * inclusive price has its tax stripped back out: net = gross / (1 + rate/100).
 * Everything downstream (subtotal, discount-on-net, tax_amount, round-off, the
 * printed tax invoice) then needs no special case for inclusive pricing.
 *
 * Returned at full precision deliberately: rounding the per-unit rate to paise
 * here would make qty x net + tax drift off the MRP. Callers round the line and
 * bill totals as they already do.
 *
 * @param {number} price     the stored price (net or gross per [inclusive])
 * @param {number|null} taxRate  GST percent, or null/0 when untaxed
 * @param {boolean} inclusive    whether [price] already contains the tax
 * @returns {number} the net unit rate
 */
function netUnitPrice(price, taxRate, inclusive) {
  const amt = Number(price) || 0;
  const rate = Number(taxRate) || 0;
  // No tax to extract (untaxed item, or GST off) — the price is net either way.
  if (!inclusive || rate === 0) return amt;
  return amt / (1 + rate / 100);
}

module.exports = { computeRoundOff, netUnitPrice };
