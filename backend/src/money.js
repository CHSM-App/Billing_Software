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

module.exports = { computeRoundOff };
