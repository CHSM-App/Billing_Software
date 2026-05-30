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
               b.subtotal, b.total, b.payment_mode, b.created_at,
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
          <td class="num">${qty}</td>
          <td class="num">&#8377;${fmt(i.unit_price)}</td>
          <td class="num">&#8377;${fmt(i.line_total)}</td>
        </tr>`;
    }).join('');

    const totalQty = items.reduce((s, i) => s + Number(i.quantity), 0);

    const html = '<!DOCTYPE html>'
      + '<html lang="en"><head>'
      + '<meta charset="UTF-8"/>'
      + '<meta name="viewport" content="width=device-width, initial-scale=1"/>'
      + '<title>Receipt &mdash; ' + esc(bill.bill_number) + '</title>'
      + '<style>'
      + '*{box-sizing:border-box;margin:0;padding:0}'
      + 'body{font-family:"Segoe UI",Arial,sans-serif;background:#f0f2f5;min-height:100vh;padding:12px;color:#1a1a1a}'
      + '.wrap{max-width:480px;margin:0 auto}'
      + '.shop-header{background:#fff;border-radius:10px 10px 0 0;padding:20px 16px 16px;text-align:center;border-bottom:2px dashed #ddd}'
      + '.shop-logo{width:72px;height:72px;object-fit:contain;border-radius:8px;margin-bottom:8px}'
      + '.shop-name{font-size:20px;font-weight:700;letter-spacing:.3px}'
      + '.shop-meta{font-size:12px;color:#555;margin-top:3px;line-height:1.6}'
      + '.shop-meta a{color:#1976d2;text-decoration:none}'
      + '.bill-info{background:#fff;padding:12px 16px;border-bottom:1px dashed #ddd;font-size:13px;display:grid;grid-template-columns:1fr 1fr;gap:6px 12px}'
      + '.bill-info .label{color:#888;font-size:11px;text-transform:uppercase;letter-spacing:.4px;padding-top:2px}'
      + '.bill-info .value{font-weight:600}'
      + '.customer{background:#f8f9ff;padding:10px 16px;border-bottom:1px dashed #ddd;font-size:13px}'
      + '.customer .sec-title{font-size:11px;text-transform:uppercase;letter-spacing:.5px;color:#888;margin-bottom:4px}'
      + '.customer .cname{font-weight:700;font-size:14px}'
      + '.customer .cphone{color:#555;margin-top:2px}'
      + '.items-wrap{background:#fff;overflow-x:auto}'
      + 'table{width:100%;border-collapse:collapse;font-size:13px}'
      + 'thead tr{background:#f5f5f5;border-bottom:2px solid #e0e0e0}'
      + 'th{padding:9px 10px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.4px;color:#555}'
      + 'td{padding:9px 10px;border-bottom:1px solid #f0f0f0}'
      + 'td.item-name{font-weight:500}'
      + '.num{text-align:right}'
      + 'tbody tr:last-child td{border-bottom:none}'
      + '.totals{background:#fff;border-top:2px dashed #ddd;padding:10px 16px}'
      + '.totals .row{display:flex;justify-content:space-between;font-size:13px;padding:4px 0;color:#555}'
      + '.totals .grand{font-size:16px;font-weight:700;color:#1a1a1a;border-top:2px solid #1976d2;margin-top:6px;padding-top:8px}'
      + '.totals .grand span:last-child{color:#1976d2}'
      + '.payment{background:#fff;padding:10px 16px;border-top:1px dashed #ddd;display:flex;justify-content:space-between;align-items:center;font-size:13px}'
      + '.pay-mode{font-weight:600}'
      + '.pay-badge{background:#e8f5e9;color:#2e7d32;padding:3px 12px;border-radius:20px;font-size:11px;font-weight:700;text-transform:uppercase;letter-spacing:.5px}'
      + '.receipt-footer{background:#fff;border-radius:0 0 10px 10px;padding:14px 16px;text-align:center;border-top:2px dashed #ddd;font-size:12px;color:#888;line-height:1.6}'
      + '.receipt-footer .note{color:#444;font-style:italic;margin-bottom:4px}'
      + '.powered{margin-top:8px;font-size:11px;color:#bbb}'
      + '</style></head><body><div class="wrap">'

      // Shop header
      + '<div class="shop-header">'
      + (bill.logo_url ? '<img src="' + esc(bill.logo_url) + '" class="shop-logo" alt="logo"/>' : '')
      + '<div class="shop-name">' + esc(bill.shop_name) + '</div>'
      + '<div class="shop-meta">'
      + (addressLine ? addressLine + '<br/>' : '')
      + (bill.shop_phone ? '&#128222; ' + esc(bill.shop_phone) : '')
      + (bill.shop_phone && bill.shop_email ? ' &nbsp;|&nbsp; ' : '')
      + (bill.shop_email ? '&#9993; <a href="mailto:' + esc(bill.shop_email) + '">' + esc(bill.shop_email) + '</a>' : '')
      + (bill.gst_number ? '<br/>GSTIN: ' + esc(bill.gst_number) : '')
      + '</div></div>'

      // Bill info
      + '<div class="bill-info">'
      + '<div class="label">Bill No</div><div class="value">' + esc(bill.bill_number) + '</div>'
      + '<div class="label">Date &amp; Time</div><div class="value">' + date + '</div>'
      + '</div>'

      // Customer (optional)
      + (bill.customer_name || bill.customer_phone
        ? '<div class="customer"><div class="sec-title">Customer Details</div>'
          + (bill.customer_name ? '<div class="cname">' + esc(bill.customer_name) + '</div>' : '')
          + (bill.customer_phone ? '<div class="cphone">&#128242; ' + esc(bill.customer_phone) + '</div>' : '')
          + '</div>'
        : '')

      // Items table
      + '<div class="items-wrap"><table>'
      + '<thead><tr><th>Description</th><th class="num">Qty</th><th class="num">Rate</th><th class="num">Amount</th></tr></thead>'
      + '<tbody>' + itemRows + '</tbody>'
      + '</table></div>'

      // Totals
      + '<div class="totals">'
      + '<div class="row"><span>Total Items</span><span>' + items.length + ' (Qty: ' + (totalQty % 1 === 0 ? totalQty : fmt(totalQty)) + ')</span></div>'
      + '<div class="row grand"><span>Grand Total</span><span>&#8377;' + fmt(bill.total) + '</span></div>'
      + '</div>'

      // Payment
      + '<div class="payment"><span class="pay-mode">Payment Mode</span><span class="pay-badge">' + esc(payLabel) + '</span></div>'

      // Footer
      + '<div class="receipt-footer">'
      + (bill.bill_footer_note ? '<div class="note">' + esc(bill.bill_footer_note) + '</div>' : '')
      + '<div>Thank you for your purchase!</div>'
      + '<div class="powered">Powered by VengurlaTech Billing</div>'
      + '</div>'

      + '</div></body></html>';

    res.setHeader('Content-Type', 'text/html; charset=utf-8');
    res.setHeader('Cache-Control', 'public, max-age=3600');
    return res.send(html);
  } catch (err) {
    logger.error({ err }, 'receipt page error');
    return res.status(500).send('<h2>Something went wrong</h2>');
  }
});

module.exports = router;
