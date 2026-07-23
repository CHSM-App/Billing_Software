const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const logger = require('../logger');

const router = express.Router();

// GET /receipt/:token — public, no auth
// Serves a full HTML receipt page for the given token.
router.get('/:token', async (req, res) => {
  try {
    await poolConnect;
    const row = await pool.request()
      .input('token', sql.NVarChar(16), req.params.token)
      .query(`
        SELECT b.bill_number, b.customer_name, b.customer_phone,
               b.subtotal, b.tax_amount, b.discount_amount, b.total, b.payment_mode, b.created_at,
               bs.name AS shop_name, bs.address, bs.phone AS shop_phone,
               bs.email AS shop_email, bs.city, bs.state, bs.pincode,
               bs.gst_number, bs.logo_url, bs.bill_footer_note
        FROM bills b
        JOIN businesses bs ON bs.id = b.business_id
        WHERE b.receipt_token = @token AND b.status != 'voided'
      `);

    if (row.recordset.length === 0) {
      return res.status(404).send('<h2>Receipt not found</h2>');
    }

    const bill = row.recordset[0];

    const itemsResult = await pool.request()
      .input('token', sql.NVarChar(16), req.params.token)
      .query(`
        SELECT bi.item_name, bi.quantity, bi.unit_price, bi.line_total
        FROM bill_items bi
        JOIN bills b ON b.id = bi.bill_id
        WHERE b.receipt_token = @token
        ORDER BY bi.item_name
      `);

    const items = itemsResult.recordset;

    const fmt = (n) => Number(n).toFixed(2);
    const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
    const date = new Date(bill.created_at).toLocaleString('en-IN', {
      timeZone: 'Asia/Kolkata',
      day: '2-digit', month: 'short', year: 'numeric',
      hour: '2-digit', minute: '2-digit', hour12: true,
    });

    const addrParts = [bill.address, bill.city, bill.state, bill.pincode].filter(Boolean);
    const addressLine = addrParts.length ? esc(addrParts.join(', ')) : '';
    const payLabel = bill.payment_mode.charAt(0).toUpperCase() + bill.payment_mode.slice(1);

    const itemRows = items.map((i) => {
      const qty = Number(i.quantity) % 1 === 0 ? Number(i.quantity) : fmt(i.quantity);
      return `<tr>
          <td class="item-name">${esc(i.item_name)}</td>
          <td class="r">${qty}</td>
          <td class="r">&#8377;${fmt(i.unit_price)}</td>
          <td class="r amount">&#8377;${fmt(i.line_total)}</td>
        </tr>`;
    }).join('');

    const totalQty = items.reduce((s, i) => s + Number(i.quantity), 0);

    const html = `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=device-width,initial-scale=1"/>
<title>Receipt &mdash; ${esc(bill.bill_number)}</title>
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

  /* ── customer ── */
  .customer{padding:12px 24px;background:#f9f9fb;border-top:1px solid #f0f0f0;border-bottom:1px solid #f0f0f0}
  .customer .sec-label{font-size:10px;font-weight:600;text-transform:uppercase;letter-spacing:.6px;color:#9a9aaa;margin-bottom:6px}
  .customer .cname{font-size:14px;font-weight:600;color:#1c1c1e}
  .customer .cphone{font-size:12px;color:#666;margin-top:2px}

  /* ── items ── */
  table{width:100%;border-collapse:collapse;font-size:13px}
  .table-head{background:#f4f5f7}
  .table-head th{padding:10px 24px;font-size:10px;font-weight:700;text-transform:uppercase;letter-spacing:.6px;color:#888;text-align:left}
  .table-head th.r{text-align:right}
  tbody td{padding:11px 24px;border-bottom:1px solid #f4f4f6;color:#2c2c2e;vertical-align:middle}
  tbody tr:last-child td{border-bottom:none}
  td.r{text-align:right}
  td.item-name{font-weight:500}
  td.amount{font-weight:600}

  /* ── totals ── */
  .totals{padding:14px 24px;background:#f9f9fb;border-top:1px solid #eee}
  .totals .t-row{display:flex;justify-content:space-between;font-size:13px;color:#555;padding:3px 0}
  .totals .t-grand{display:flex;justify-content:space-between;font-size:16px;font-weight:700;color:#1a1a2e;padding:12px 0 0;margin-top:8px;border-top:2px solid #1a1a2e}

  /* ── footer ── */
  .footer{padding:16px 24px;text-align:center;border-top:1px solid #eee}
  .footer .note{font-size:12px;color:#444;font-style:italic;margin-bottom:6px}
  .footer .thanks{font-size:13px;font-weight:600;color:#333;letter-spacing:.2px}
  .footer .powered{font-size:11px;color:#bbb;margin-top:8px}
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
    </div>
  </div>

  <!-- Bill meta -->
  <div class="meta">
    <div class="meta-item">
      <div class="label">Bill No</div>
      <div class="value">${esc(bill.bill_number)}</div>
    </div>
    <div class="meta-item">
      <div class="label">Date &amp; Time</div>
      <div class="value">${date}</div>
    </div>
    <div class="meta-item">
      <div class="label">Payment</div>
      <div class="value"><span class="badge">${esc(payLabel)}</span></div>
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
        <th class="r">Qty</th>
        <th class="r">Rate</th>
        <th class="r">Amount</th>
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
    ${Number(bill.tax_amount) > 0 ? `<div class="t-row">
      <span>Tax</span>
      <span>&#8377;${fmt(bill.tax_amount)}</span>
    </div>` : ''}
    ${Number(bill.discount_amount) > 0 ? `<div class="t-row">
      <span>Discount</span>
      <span>&minus;&#8377;${fmt(bill.discount_amount)}</span>
    </div>` : ''}
    <div class="t-grand">
      <span>Grand Total</span>
      <span>&#8377;${fmt(Number(bill.total) - Number(bill.discount_amount || 0))}</span>
    </div>
  </div>

  <!-- Footer -->
  <div class="footer">
    ${bill.bill_footer_note ? '<div class="note">' + esc(bill.bill_footer_note) + '</div>' : ''}
    <div class="thanks">Thank you for your business.</div>
    <div class="powered">Powered by VengurlaTech Billing</div>
  </div>

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
