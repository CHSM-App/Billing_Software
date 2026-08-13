// Money helpers shared across billing screens & receipt/PDF rendering.
//
// The round-off is computed on the FINAL payable (total - discount), never on
// the individual subtotal/tax/discount values, which stay exactly as calculated.
// "Round half up" to the nearest whole rupee, matching the backend
// (src/money.js computeRoundOff):
//   125.22 -> 125.00  (round_off -0.22)
//   125.60 -> 126.00  (round_off +0.40)
//   125.50 -> 126.00  (round_off +0.50)

/// Signed round-off for [payable], rounding half up to the nearest rupee.
/// Returns 0 when [enabled] is false so callers can always add it.
double computeRoundOff(double payable, bool enabled) {
  if (!enabled) return 0.0;
  final amt = payable.isFinite ? payable : 0.0;
  // (amt + 0.5).floor() is round-half-up for the non-negative payable
  // (125.50 -> 126). Bill payables are always >= 0.
  final rounded = (amt + 0.5).floorToDouble();
  return double.parse((rounded - amt).toStringAsFixed(2));
}
