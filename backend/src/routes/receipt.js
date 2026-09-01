const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const logger = require('../logger');
const { stripBillPrefix } = require('../billNumber');

const router = express.Router();

// GET /receipt/:token — public, no auth
// Serves a full HTML receipt page for the given token.
router.get('/:token', async (req, res) => {
  try {
    await poolConnect;
    // Strip ALL whitespace that some WhatsApp/link renderers inject mid-token
    // (e.g. "6pWhWmV -Yaf93HJn" → "6pWhWmV-Yaf93HJn"). A valid receipt token is
    // URL-safe base64 and never contains spaces. Cap at 16 so an over-long
    // value returns a clean 404 instead of a SQL "invalid data length" (8016).
    const token = String(req.params.token || '').replace(/\s+/g, '').slice(0, 16);
    if (!token) return res.status(404).send('<h2>Receipt not found</h2>');
    const row = await pool.request()
      .input('token', sql.NVarChar(16), token)
      .query(`
        SELECT b.bill_number, b.customer_name, b.customer_phone,
               b.subtotal, b.tax_amount, b.discount_amount, b.total, b.round_off, b.payment_mode, b.created_at,
               b.payment_status, b.settled_payment_mode,
               t.table_number,
               bs.name AS shop_name, bs.address, bs.phone AS shop_phone,
               bs.email AS shop_email, bs.city, bs.state, bs.pincode,
               bs.gst_number, bs.fssai_number, bs.logo_url, bs.bill_footer_note,
               bs.gst_enabled, bs.default_sac_code
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        LEFT JOIN tables t ON t.id = b.table_id
        WHERE b.receipt_token = @token AND b.status != 'voided'
      `);

    if (row.recordset.length === 0) {
      return res.status(404).send('<h2>Receipt not found</h2>');
    }

    const bill = row.recordset[0];

    const itemsResult = await pool.request()
      .input('token', sql.NVarChar(16), token)
      .query(`
        SELECT bi.item_name, bi.quantity, bi.unit_price, bi.tax_rate, bi.hsn_code, bi.line_total
        FROM bill_items bi
        JOIN bills b ON b.id = bi.bill_id
        WHERE b.receipt_token = @token
        ORDER BY bi.item_name
      `);

    const items = itemsResult.recordset;

    const fmt = (n) => Number(n).toFixed(2);
    // Split a tax figure into the CGST/SGST halves that RENDER, giving the odd
    // paisa to CGST so the two always add back to exactly the original. Naively
    // printing (tax / 2) twice loses or gains a paisa on any odd-paise tax
    // (0.95 -> 0.47 + 0.47 = 0.94), which makes the receipt's Subtotal + CGST +
    // SGST disagree with its Grand Total by 0.01.
    const gstHalves = (tax) => {
      const paise = Math.round(Number(tax) * 100);
      return [((paise + 1) >> 1) / 100, (paise >> 1) / 100];
    };
    const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const date = new Date(bill.created_at).toLocaleString('en-IN', {
      timeZone: 'Asia/Kolkata',
      day: '2-digit', month: 'short', year: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: true,
    });

    const addrParts = [bill.address, bill.city, bill.state, bill.pincode].filter(Boolean);
    const addressLine = addrParts.length ? esc(addrParts.join(', ')) : '';

    // GST tax-invoice extras only render when the business has GST enabled AND
    // the bill actually carries tax. Otherwise the receipt is byte-for-byte as
    // before. CGST/SGST are a display split (each = tax_amount / 2); nothing is
    // recomputed from line items, so totals never drift.
    const gstEnabled = !!bill.gst_enabled && Number(bill.tax_amount) > 0;
    // Final payable = total − discount + round_off, less any tax that must be
    // ignored because the business has GST off. Without the correction a bill
    // whose stored tax_amount predates the toggle would show a grand total
    // higher than the net payable the customer actually paid.
    const grandTotal =
      Number(bill.total)
      - Number(bill.discount_amount || 0)
      + Number(bill.round_off || 0)
      - (bill.gst_enabled ? 0 : Number(bill.tax_amount || 0));
    // Per-line HSN/SAC: the item's own code, else the business default SAC.
    const codeFor = (i) => i.hsn_code || bill.default_sac_code || '';
    const showHsnCol = gstEnabled && items.some((i) => codeFor(i));

    // Rate-wise GST summary rows: group taxable value + tax by tax_rate.
    // taxable = qty×unit_price; lineTax = line_total − taxable; cgst = sgst = lineTax/2.
    //
    // bill_items store the PRE-discount line tax (line_total = qty×price + tax,
    // computed before the bill-level discount is applied), while bills.tax_amount
    // holds the discounted figure. The discount reduces the taxable base, so both
    // the taxable value and the tax here are scaled by discountedNet/subtotal —
    // otherwise this summary would contradict the CGST/SGST totals below it.
    const discountRatio =
      Number(bill.subtotal) > 0
        ? (Number(bill.subtotal) - Number(bill.discount_amount || 0)) / Number(bill.subtotal)
        : 1;
    const gstByRate = {};
    if (gstEnabled) {
      for (const i of items) {
        const rate = i.tax_rate != null ? Number(i.tax_rate) : 0;
        if (rate <= 0) continue;
        const taxable = Number(i.quantity) * Number(i.unit_price);
        const lineTax = Number(i.line_total) - taxable;
        const g = (gstByRate[rate] = gstByRate[rate] || { taxable: 0, tax: 0 });
        g.taxable += taxable * discountRatio;
        g.tax += lineTax * discountRatio;
      }
    }
    const gstSummaryRows = Object.keys(gstByRate)
      .map(Number)
      .sort((a, b) => a - b)
      .map((rate) => {
        const g = gstByRate[rate];
        const half = rate / 2;
        return `<tr>
          <td>${fmt(g.taxable)}</td>
          <td class="r">${half}% &nbsp;&#8377;${fmt(g.tax / 2)}</td>
          <td class="r">${half}% &nbsp;&#8377;${fmt(g.tax / 2)}</td>
        </tr>`;
      }).join('');

    // A settled credit bill (payment_mode='credit', payment_status='paid') was
    // actually collected via settled_payment_mode — show that. Only an UNPAID
    // credit bill still reads "Credit" (and stays red below).
    const isUnpaidCredit =
      bill.payment_mode === 'credit' && bill.payment_status === 'unpaid';
    const effectiveMode =
      bill.payment_mode === 'credit' && bill.payment_status === 'paid' && bill.settled_payment_mode
        ? bill.settled_payment_mode
        : bill.payment_mode;
    const payLabel = effectiveMode.charAt(0).toUpperCase() + effectiveMode.slice(1);

    const itemRows = items.map((i) => {
      const qty = Number(i.quantity) % 1 === 0 ? Number(i.quantity) : fmt(i.quantity);
      return `<tr>
          <td class="item-name">${esc(i.item_name)}${showHsnCol ? '<span class="hsn">' + esc(codeFor(i)) + '</span>' : ''}</td>
          <td class="r col-qty">${qty}</td>
          <td class="r col-rate">&#8377;${fmt(i.unit_price)}</td>
          <td class="r amount col-amt">&#8377;${fmt(i.line_total)}</td>
        </tr>`;
    }).join('');

    const totalQty = items.reduce((s, i) => s + Number(i.quantity), 0);

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Receipt &mdash; ${esc(stripBillPrefix(bill.bill_number))}</title>
<style>
  @import url('https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap');
  *{box-sizing:border-box;margin:0;padding:0}
  body{font-family:'Inter',sans-serif;background:#eef0f4;min-height:100vh;padding:20px 12px;color:#1c1c1e;-webkit-font-smoothing:antialiased}
  .receipt{max-width:500px;margin:0 auto;background:#fff;border-radius:4px;box-shadow:0 1px 4px rgba(0,0,0,.10)}

  /* ── top bar ── */
  .top-bar{background:#1a1a2e;padding:24px 24px 20px;border-radius:4px 4px 0 0;text-align:center}
  .top-bar .logo{width:64px;height:64px;object-fit:contain;border-radius:4px;margin-bottom:12px;display:block;margin-left:auto;margin-right:auto}
  .top-bar .shop-name{font-size:18px;font-weight:700;color:#fff;letter-spacing:.4px}
  .top-bar .shop-sub{font-size:12px;color:#a0a8c0;margin-top:5px;line-height:1.7}
  .top-bar .shop-sub a{color:#a0a8c0;text-decoration:none}

  /* ── section divider ── */
  .divider{height:1px;background:#f0f0f0;margin:0 24px}
  .divider-dashed{border:none;border-top:1px dashed #ddd;margin:0 24px}

  /* ── meta row ── */
  .meta{display:flex;justify-content:space-between;align-items:flex-start;padding:16px 24px;gap:12px;flex-wrap:wrap}
  .meta-item .label{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.6px;color:#9a9aaa;margin-bottom:3px}
  .meta-item .value{font-size:13px;font-weight:600;color:#1c1c1e}
  .badge{display:inline-block;padding:3px 10px;border-radius:3px;font-size:11px;font-weight:600;text-transform:uppercase;letter-spacing:.5px;background:#e8f4ec;color:#1e7e34}
  /* Credit (udhaari): unpaid — flag it red instead of the paid-green. */
  .badge-credit{background:#fdecec;color:#c0392b}

  /* ── customer ── */
  .customer{padding:12px 24px;background:#f9f9fb;border-top:1px solid #f0f0f0;border-bottom:1px solid #f0f0f0}
  .customer .sec-label{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.6px;color:#9a9aaa;margin-bottom:6px}
  .customer .cname{font-size:14px;font-weight:600;color:#1c1c1e}
  .customer .cphone{font-size:12px;color:#666;margin-top:2px}

  /* ── items ── */
  table{width:100%;border-collapse:collapse;font-size:13px;table-layout:fixed}
  .table-head{background:#f4f5f7}
  .table-head th{padding:10px 12px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:#888;text-align:left}
  .table-head th:first-child{padding-left:24px}
  .table-head th:last-child{padding-right:24px}
  .table-head th.r{text-align:right}
  /* Fixed column widths so the amount can never be pushed outside the card */
  th.col-qty,td.col-qty{width:14%}
  th.col-rate,td.col-rate{width:24%}
  th.col-amt,td.col-amt{width:26%}
  tbody td{padding:11px 12px;border-bottom:1px solid #f4f4f6;color:#2c2c2e;vertical-align:middle}
  tbody td:first-child{padding-left:24px}
  tbody td:last-child{padding-right:24px}
  tbody tr:last-child td{border-bottom:none}
  td.r{text-align:right}
  td.item-name{font-weight:500;word-break:break-word;overflow-wrap:anywhere}
  td.item-name .hsn{display:block;font-size:10px;font-weight:500;color:#9a9aaa;margin-top:2px}
  td.amount{font-weight:600}

  /* ── GST summary ── */
  .gst-summary{padding:12px 24px 4px;background:#f9f9fb}
  .gst-summary .gst-label{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.6px;color:#9a9aaa;margin-bottom:6px}
  .gst-summary table{font-size:12px}
  .gst-summary th{padding:4px 0;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.5px;color:#888;text-align:left}
  .gst-summary th.r,.gst-summary td.r{text-align:right}
  .gst-summary td{padding:4px 0;color:#555}

  /* ── totals ── */
  .totals{padding:14px 24px;background:#f9f9fb;border-top:1px solid #eee}
  .totals .t-row{display:flex;justify-content:space-between;font-size:13px;color:#555;padding:3px 0}
  .totals .t-grand{display:flex;justify-content:space-between;font-size:16px;font-weight:700;color:#1a1a2e;padding:12px 0 0;margin-top:8px;border-top:2px solid #1a1a2e}

  /* ── footer ── */
  .footer{padding:16px 24px;text-align:center;border-top:1px solid #eee}
  .footer .note{font-size:12px;color:#444;font-style:italic;margin-bottom:6px}
  .footer .thanks{font-size:13px;font-weight:600;color:#333;letter-spacing:.2px}
  .footer .powered{font-size:11px;color:#bbb;margin-top:8px}

  /* ── download button ── */
  .actions{max-width:500px;margin:16px auto 0;text-align:center}
  .btn-download{display:inline-flex;align-items:center;gap:8px;background:#1a1a2e;color:#fff;border:none;border-radius:6px;padding:12px 22px;font-family:inherit;font-size:14px;font-weight:600;cursor:pointer;box-shadow:0 1px 4px rgba(0,0,0,.15);transition:opacity .15s}
  .btn-download:hover{opacity:.9}
  .btn-download svg{width:16px;height:16px}

  /* When saving/printing: hide the button and neutralise screen chrome */
  @media print{
    body{background:#fff;padding:0}
    .receipt{box-shadow:none;max-width:none}
    .actions{display:none}
  }
</style>
</head>
<body>
<div class="receipt">

  <!-- Header -->
  <div class="top-bar">
    ${bill.logo_url ? '<img src="' + esc(bill.logo_url) + '" class="logo" alt=""/>' : ''}
    <div class="shop-name">${esc(bill.shop_name)}</div>
    <div class="shop-sub">
      ${addressLine ? addressLine + '<br/>' : ''}
      ${bill.shop_phone ? 'Tel: ' + esc(bill.shop_phone) : ''}
      ${bill.shop_phone && bill.shop_email ? '&nbsp;&nbsp;|&nbsp;&nbsp;' : ''}
      ${bill.shop_email ? '<a href="mailto:' + esc(bill.shop_email) + '">' + esc(bill.shop_email) + '</a>' : ''}
      ${bill.gst_number ? '<br/>GSTIN: ' + esc(bill.gst_number) : ''}
      ${bill.fssai_number ? '<br/>FSSAI: ' + esc(bill.fssai_number) : ''}
    </div>
  </div>

  <!-- Bill meta -->
  <div class="meta">
    <div class="meta-item">
      <div class="label">Bill No</div>
      <div class="value">${esc(stripBillPrefix(bill.bill_number))}</div>
    </div>
    ${bill.table_number ? `
    <div class="meta-item">
      <div class="label">Table</div>
      <div class="value">${esc(String(bill.table_number))}</div>
    </div>` : ''}
    <div class="meta-item">
      <div class="label">Date &amp; Time</div>
      <div class="value">${date}</div>
    </div>
    <div class="meta-item">
      <div class="label">Payment</div>
      <div class="value"><span class="badge${isUnpaidCredit ? ' badge-credit' : ''}">${esc(payLabel)}</span></div>
    </div>
  </div>

  ${bill.customer_name || bill.customer_phone ? `
  <!-- Customer -->
  <div class="customer">
    <div class="sec-label">Billed To</div>
    ${bill.customer_name ? '<div class="cname">' + esc(bill.customer_name) + '</div>' : ''}
    ${bill.customer_phone ? '<div class="cphone">Mob: ' + esc(bill.customer_phone) + '</div>' : ''}
  </div>` : ''}

  <!-- Items -->
  <table>
    <thead class="table-head">
      <tr>
        <th>Description</th>
        <th class="r col-qty">Qty</th>
        <th class="r col-rate">Rate</th>
        <th class="r col-amt">Amount</th>
      </tr>
    </thead>
    <tbody>${itemRows}</tbody>
  </table>

  <!-- Totals -->
  <div class="totals">
    <div class="t-row">
      <span>Total Qty</span>
      <span>${totalQty % 1 === 0 ? totalQty : fmt(totalQty)}</span>
    </div>
    <div class="t-row">
      <span>Items</span>
      <span>${items.length}</span>
    </div>
    <div class="t-row">
      <span>Subtotal</span>
      <span>&#8377;${fmt(bill.subtotal)}</span>
    </div>
    ${gstEnabled ? `<div class="t-row">
      <span>CGST</span>
      <span>&#8377;${fmt(gstHalves(bill.tax_amount)[0])}</span>
    </div>
    <div class="t-row">
      <span>SGST</span>
      <span>&#8377;${fmt(gstHalves(bill.tax_amount)[1])}</span>
    </div>` : ''}
    ${Number(bill.discount_amount) > 0 ? `<div class="t-row">
      <span>Discount</span>
      <span>&minus;&#8377;${fmt(bill.discount_amount)}</span>
    </div>` : ''}
    ${Number(bill.round_off) !== 0 ? `<div class="t-row">
      <span>Round Off</span>
      <span>${Number(bill.round_off) < 0 ? '&minus;' : '+'}&#8377;${fmt(Math.abs(Number(bill.round_off)))}</span>
    </div>` : ''}
    <div class="t-grand">
      <span>Grand Total</span>
      <span>&#8377;${fmt(grandTotal)}</span>
    </div>
  </div>

  ${gstSummaryRows ? `
  <!-- GST summary -->
  <div class="gst-summary">
    <div class="gst-label">GST Summary</div>
    <table>
      <thead>
        <tr><th>Taxable Value</th><th class="r">CGST</th><th class="r">SGST</th></tr>
      </thead>
      <tbody>${gstSummaryRows}</tbody>
    </table>
  </div>` : ''}

  <!-- Footer -->
  <div class="footer">
    ${bill.bill_footer_note ? '<div class="note">' + esc(bill.bill_footer_note) + '</div>' : ''}
    <div class="thanks">Thank you for your business.</div>
    <div class="powered">powered by vittam</div>
  </div>

</div>

<div class="actions">
  <button type="button" class="btn-download" onclick="window.print()">
    <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"/><polyline points="7 10 12 15 17 10"/><line x1="12" y1="15" x2="12" y2="3"/></svg>
    Download Receipt
  </button>
</div>

</body>
</html>`;

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    return res.send(html);
  } catch (err) {
    logger.error({ err }, 'receipt page error');
    return res.status(500).send('<h2>Something went wrong</h2>');
  }
});

module.exports = router;
