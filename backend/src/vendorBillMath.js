// Pure purchase-bill helpers shared by routes/vendor_bills.js and the AI bill
// scanner (purchaseScan.js). Kept out of the route file so the scanner can use
// the SAME totals and GSTIN rule without a circular require.

const { netUnitPrice } = require('./money');

const GSTIN_RE = /^[0-9]{2}[A-Z]{5}[0-9]{4}[A-Z][0-9A-Z]Z[0-9A-Z]$/;

/** Round to 2dp the way every money figure in this codebase is rounded. */
const r2 = (n) => Math.round((Number(n) || 0) * 100) / 100;

/**
 * Split a tax figure into the CGST/SGST halves, giving the odd paisa to CGST so
 * the two always add back to exactly the original. This is the SAME expression
 * used by the GSTR-1 endpoint and routes/receipt.js — a different rounding here
 * would make the outward and inward returns disagree by paise.
 */
function gstHalves(tax) {
  const paise = Math.round((Number(tax) || 0) * 100);
  return [((paise + 1) >> 1) / 100, (paise >> 1) / 100];
}

/**
 * Price every line and total the bill.
 *
 * `unit_price` may be quoted tax-INCLUSIVE by the vendor, so it is normalised to
 * a net rate with money.js netUnitPrice — the same back-calculation sales use,
 * which keeps a purchase and a sale of the same goods internally consistent.
 *
 * The bill-level discount reduces the taxable base, so tax is scaled by
 * discountedNet/subtotal exactly as routes/bills.js does. Keeping this rule
 * identical on both sides means the P&L never disagrees with itself.
 *
 * `free_quantity` (scheme goods) is carried through untouched: it is received
 * into stock but costs nothing, so it never enters the money math — the rate
 * stays per PAID unit.
 */
function computeTotals(lines, opts) {
  const { isInterstate, discountAmount, roundOff } = opts;

  const priced = lines.map((l, idx) => {
    // A line's rate is honoured whatever the business-wide GST setting says.
    // A shop that bills without GST can still BUY from a registered vendor,
    // and that vendor's tax is a real cost that has to land on the bill; the
    // form asks for it per line, so an absent rate already means 'no tax'.
    const rate = l.tax_rate != null && l.tax_rate !== ''
      ? parseFloat(l.tax_rate)
      : null;
    const qty = parseFloat(l.quantity);
    const net = netUnitPrice(parseFloat(l.unit_price), rate, !!l.price_inclusive_tax);
    const lineNet = net * qty;
    const lineTax = rate ? lineNet * (rate / 100) : 0;
    return {
      item_id: l.item_id || null,
      variant_id: l.variant_id || null,
      raw_material_id: l.raw_material_id || null,
      item_name: String(l.name || '').trim().slice(0, 200),
      quantity: qty,
      free_quantity: parseFloat(l.free_quantity) || 0,
      unit: l.unit ? String(l.unit).slice(0, 20) : null,
      unit_price: net,
      tax_rate: rate,
      hsn_code: l.hsn_code ? String(l.hsn_code).trim().slice(0, 10) : null,
      line_total: r2(lineNet + lineTax),
      sort_order: idx,
      _net: lineNet,
      _tax: lineTax,
    };
  });

  const subtotal = priced.reduce((s, l) => s + l._net, 0);
  const rawTax = priced.reduce((s, l) => s + l._tax, 0);
  const discount = Math.min(Math.max(parseFloat(discountAmount) || 0, 0), subtotal);
  const taxAmount = subtotal > 0 ? rawTax * ((subtotal - discount) / subtotal) : 0;

  let cgst = 0, sgst = 0, igst = 0;
  if (isInterstate) {
    igst = r2(taxAmount);
  } else {
    [cgst, sgst] = gstHalves(taxAmount);
  }

  const round = parseFloat(roundOff) || 0;
  const total = r2(subtotal - discount + r2(taxAmount) + round);

  return {
    lines: priced,
    subtotal: r2(subtotal),
    taxAmount: r2(taxAmount),
    cgst, sgst, igst,
    discount: r2(discount),
    roundOff: round,
    total,
  };
}

module.exports = { GSTIN_RE, r2, gstHalves, computeTotals };
