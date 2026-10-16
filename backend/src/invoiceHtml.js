// The A4/A5 tax-invoice receipt page — an HTML twin of the app's printed
// invoice (frontend/lib/services/invoice_pdf.dart). A bill shared over
// WhatsApp from a device set to A4/A5 links here (?p=a4|a5), so the customer
// sees the same invoice the shop prints instead of the thermal-style card.
// Keep the two in step: same sections, same order, same "Rs." money.

const { stripBillPrefix } = require('./billNumber');

const ONES = ['', 'One', 'Two', 'Three', 'Four', 'Five', 'Six', 'Seven', 'Eight', 'Nine',
  'Ten', 'Eleven', 'Twelve', 'Thirteen', 'Fourteen', 'Fifteen', 'Sixteen',
  'Seventeen', 'Eighteen', 'Nineteen'];
const TENS = ['', '', 'Twenty', 'Thirty', 'Forty', 'Fifty', 'Sixty', 'Seventy', 'Eighty', 'Ninety'];

function threeDigits(n) {
  const parts = [];
  if (n >= 100) parts.push(`${ONES[Math.floor(n / 100)]} Hundred`);
  const rest = n % 100;
  if (rest > 0 && rest < 20) parts.push(ONES[rest]);
  else if (rest >= 20) parts.push(rest % 10 ? `${TENS[Math.floor(rest / 10)]} ${ONES[rest % 10]}` : TENS[rest / 10]);
  return parts.join(' ');
}

function indianWords(n) {
  if (n === 0) return 'Zero';
  const crore = Math.floor(n / 10000000);
  const lakh = Math.floor(n / 100000) % 100;
  const thousand = Math.floor(n / 1000) % 100;
  const rest = n % 1000;
  return [
    crore && `${indianWords(crore)} Crore`,
    lakh && `${threeDigits(lakh)} Lakh`,
    thousand && `${threeDigits(thousand)} Thousand`,
    rest && threeDigits(rest),
  ].filter(Boolean).join(' ');
}

// Same wording as amountToWords() in frontend/lib/utils/amount_words.dart.
function amountToWords(amount) {
  const totalPaise = Math.round(Math.abs(Number(amount)) * 100);
  const rupees = Math.floor(totalPaise / 100);
  const paise = totalPaise % 100;
  return `${amount < 0 ? 'Minus ' : ''}${indianWords(rupees)} Rupees` +
    `${paise ? ` and ${indianWords(paise)} Paise` : ''} only`;
}

const esc = (s) => String(s).replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
const money = (v) => `Rs.${Number(v).toFixed(2)}`;
const qtyStr = (q) => (Number(q) % 1 === 0 ? String(Number(q)) : Number(q).toFixed(2));
const trimRate = (r) => String(Number(r));
const titleCase = (m) => (m ? m.charAt(0).toUpperCase() + m.slice(1) : '');

// Page widths in CSS px (96dpi) — the viewport is pinned to the page so a
// phone shows the whole sheet zoomed to fit, exactly like the PDF viewer.
const PAGES = { a4: { css: '210mm', px: 794, size: 'A4' }, a5: { css: '148mm', px: 559, size: 'A5' } };

const CSS = `
  *{box-sizing:border-box;margin:0;padding:0}
  body{background:#eef0f4;font-family:Helvetica,Arial,sans-serif;color:#000;-webkit-font-smoothing:antialiased}
  .page{background:#fff;margin:0 auto;padding:24pt 24pt 4mm;display:flex;flex-direction:column}
  h1{text-align:center;font-size:16pt;margin-bottom:8pt}
  table{width:100%;border-collapse:collapse}
  .box td{border:0.8pt solid #000;vertical-align:top}
  .shop{padding:8pt;font-size:9pt;line-height:1.35}
  .shop .wrap{display:flex;gap:8pt;align-items:flex-start}
  .shop .logo{width:60pt;height:60pt;object-fit:contain;flex:none}
  .shop .name{font-size:15pt;font-weight:bold;margin-bottom:3pt}
  .shop div+div{margin-top:3pt}
  .kv{padding:8pt}.kv+.kv{border-top:0.8pt solid #000}
  .k{font-size:9pt;margin-bottom:2pt}.v{font-size:11pt;font-weight:bold}
  .to{border:0.8pt solid #000;border-top:none;padding:8pt;font-size:9pt}
  .to .v{margin-bottom:1pt}
  .grid{font-size:9pt}
  .grid th,.grid td{border:0.6pt solid #000;padding:4pt;text-align:left}
  .grid thead th{background:#e0e0e0}
  .grid .r{text-align:right}.grid .c{text-align:center}
  .grid .b td{font-weight:bold}
  .hsn{font-size:8.5pt}.hsn th,.hsn td{padding:3pt 4pt}
  .sum{display:flex;gap:12pt;margin-top:10pt}
  .sum .words{flex:3;font-size:9pt}
  .sum .words .v{font-size:10pt;margin-bottom:10pt}
  .sum .words .credit{font-size:9pt}
  .tot{flex:2;border:0.6pt solid #000;align-self:flex-start}
  .tr{display:flex;justify-content:space-between;padding:4pt 8pt;font-size:10pt}
  .tr.b{font-size:11pt;font-weight:bold;border-top:0.6pt solid #000}
  .foot{display:flex;justify-content:space-between;align-items:flex-end;margin-top:24pt;font-size:9pt}
  .foot b{display:block}
  .brand{margin-top:auto;padding-top:12pt;text-align:right;font-size:7pt;font-style:italic;color:#757575}
  .actions{text-align:center;padding:16px}
  .actions button{background:#1a1a2e;color:#fff;border:none;border-radius:6px;padding:12px 22px;font:600 14px Helvetica,Arial,sans-serif;cursor:pointer}
  @media print{body{background:#fff}.actions{display:none}}
`;

/**
 * Renders the invoice page. Takes the figures receipt.js already derived for
 * the card receipt so the two views can never disagree on money.
 */
function renderInvoice({ paper, bill, items, parts, grandTotal, billedBy, settledAs, isUnpaidCredit }) {
  const page = PAGES[paper];
  const showGst = !!bill.gst_enabled && Number(bill.tax_amount) > 0;
  const date = new Date(bill.finalized_at || bill.created_at)
    .toLocaleDateString('en-GB', { timeZone: 'Asia/Kolkata', day: '2-digit', month: '2-digit', year: 'numeric' })
    .replace(/\//g, '-');
  const number = esc(stripBillPrefix(bill.bill_number));

  // bill_items store the PRE-discount line tax; the bill's tax is charged on
  // the discounted net, so each line's tax is scaled by discountedNet/subtotal.
  const discountRatio = Number(bill.subtotal) > 0
    ? (Number(bill.subtotal) - Number(bill.discount_amount || 0)) / Number(bill.subtotal)
    : 1;
  const net = (i) => Number(i.quantity) * Number(i.unit_price);
  const lineTax = (i) => (Number(i.line_total) - net(i)) * discountRatio;
  const codeOf = (i) => i.hsn_code || bill.default_sac_code || '';
  const anyHsn = showGst && items.some((i) => codeOf(i));
  const rate = (i) => (Number(i.quantity) > 0
    ? Number(i.unit_price) + Number(i.discount_amount || 0) / Number(i.quantity)
    : Number(i.unit_price));
  const nameOf = (i) => esc(i.item_name) +
    (Number(i.discount_amount) > 0 ? ` (Disc &#8377;${Number(i.discount_amount).toFixed(2)})` : '');

  const itemRows = items.map((i, idx) => `<tr>
      <td class="c">${idx + 1}</td><td>${nameOf(i)}</td>
      ${anyHsn ? `<td class="c">${esc(codeOf(i))}</td>` : ''}
      <td class="r">${qtyStr(i.quantity)}</td><td class="r">${money(rate(i))}</td>
      ${showGst ? `<td class="r">${money(lineTax(i))} (${trimRate(i.tax_rate || 0)}%)</td>` : ''}
      <td class="r">${money(net(i))}</td></tr>`).join('');
  const sum = (f) => items.reduce((s, i) => s + f(i), 0);

  // HSN-wise table: taxable and tax per code, each scaled once by the discount.
  const groups = new Map();
  for (const i of items) {
    const g = groups.get(codeOf(i)) || { rate: Number(i.tax_rate || 0), taxable: 0, tax: 0 };
    g.taxable += net(i) * discountRatio;
    g.tax += lineTax(i);
    groups.set(codeOf(i), g);
  }
  const hsnRows = [...groups].map(([code, g]) => `<tr>
      <td>${esc(code)}</td><td class="r">${money(g.taxable)}</td>
      <td class="r">${trimRate(g.rate / 2)}%</td><td class="r">${money(g.tax / 2)}</td>
      <td class="r">${trimRate(g.rate / 2)}%</td><td class="r">${money(g.tax / 2)}</td>
      <td class="r">${money(g.tax)}</td></tr>`).join('');
  const totTaxable = [...groups.values()].reduce((s, g) => s + g.taxable, 0);
  const totTax = [...groups.values()].reduce((s, g) => s + g.tax, 0);

  const payMode = parts.length
    ? parts.map((p) => `${titleCase(settledAs(p.mode))} ${money(p.amount)}`).join(' + ')
    : titleCase(settledAs(bill.payment_mode));
  const paise = Math.round(Number(bill.tax_amount) * 100);
  const tr = (k, v, b) => `<div class="tr${b ? ' b' : ''}"><span>${k}</span><span>${v}</span></div>`;
  const collected = bill.collected || [];

  return `<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="UTF-8"/>
<meta name="viewport" content="width=${page.px}"/>
<title>${showGst ? 'Tax Invoice' : 'Invoice'} &mdash; ${number}</title>
<style>${CSS}
  .page{width:${page.css};min-height:calc(${page.css} * 1.4142)}
  @page{size:${page.size};margin:0}
</style>
</head>
<body>
<div class="page">
  <h1>${showGst ? 'Tax Invoice' : 'Invoice'}</h1>

  <table class="box"><tr>
    <td class="shop" style="width:60%"><div class="wrap">
      ${bill.logo_url && bill.print_logo ? `<img src="${esc(bill.logo_url)}" class="logo" alt=""/>` : ''}
      <div>
      <div class="name">${esc(bill.shop_name)}</div>
      ${bill.address ? `<div>${esc(bill.address).replace(/\r?\n/g, '<br/>')}</div>` : ''}
      ${bill.shop_phone ? `<div>Ph: ${esc(String(bill.shop_phone).trim())}</div>` : ''}
      ${bill.gst_enabled && bill.gst_number ? `<div>GSTIN: ${esc(bill.gst_number)}</div>` : ''}
      ${bill.fssai_number ? `<div>FSSAI: ${esc(bill.fssai_number)}</div>` : ''}
      </div>
    </div></td>
    <td style="padding:0">
      <div class="kv"><div class="k">Invoice No.</div><div class="v">${number}</div></div>
      <div class="kv"><div class="k">Date</div><div class="v">${date}</div></div>
      ${billedBy ? `<div class="kv"><div class="k">Cashier</div><div class="v">${esc(billedBy)}</div></div>` : ''}
    </td>
  </tr></table>

  ${bill.customer_name || bill.customer_phone || bill.table_number ? `<div class="to">
    <div class="k">Bill To</div>
    ${bill.customer_name ? `<div class="v">${esc(bill.customer_name)}</div>` : ''}
    ${bill.customer_phone ? `<div>Contact No.: ${esc(bill.customer_phone)}</div>` : ''}
    ${bill.table_number ? `<div>Table: ${esc(String(bill.table_number))}</div>` : ''}
  </div>` : '<div style="height:8pt"></div>'}

  <table class="grid">
    <thead><tr>
      <th class="c" style="width:22pt">#</th><th>Item name</th>
      ${anyHsn ? '<th class="c" style="width:52pt">HSN/SAC</th>' : ''}
      <th class="r" style="width:40pt">Qty</th><th class="r">Price/Unit</th>
      ${showGst ? '<th class="r">GST</th>' : ''}<th class="r">Amount</th>
    </tr></thead>
    <tbody>${itemRows}
      <tr class="b"><td></td><td>Total</td>${anyHsn ? '<td></td>' : ''}
        <td class="r">${qtyStr(sum((i) => Number(i.quantity)))}</td><td></td>
        ${showGst ? `<td class="r">${money(sum(lineTax))}</td>` : ''}
        <td class="r">${money(sum(net))}</td></tr>
    </tbody>
  </table>

  <div class="sum">
    <div class="words">
      <div class="k">Invoice Amount in Words</div>
      <div class="v">${amountToWords(grandTotal)}</div>
      <div class="k">Payment mode</div>
      <div class="v" style="margin-bottom:0">${esc(payMode)}</div>
      ${(bill.credit_payments || []).map((p) => `<div class="credit">${p.paid_in_bill_number ? `Paid in Bill ${esc(stripBillPrefix(p.paid_in_bill_number))}` : 'Paid'} &middot; ${esc(titleCase(p.mode))} &middot; ${new Date(p.created_at).toISOString().slice(0, 10)}&nbsp;&nbsp;${money(p.amount)}</div>`).join('')}
      ${isUnpaidCredit ? `<div class="k" style="margin-top:6pt">Balance due</div>
        <div class="v">${money((bill.credit_amount != null ? Number(bill.credit_amount) : grandTotal) - Number(bill.credit_paid || 0))}</div>` : ''}
    </div>
    <div class="tot">
      ${tr('Sub Total', money(bill.subtotal))}
      ${Number(bill.discount_amount) > 0 ? tr('Discount', `- ${money(bill.discount_amount)}`) : ''}
      ${showGst ? tr('CGST', money(((paise + 1) >> 1) / 100)) + tr('SGST', money((paise >> 1) / 100)) : ''}
      ${(bill.additional_charges || []).map((c) => tr(esc(c.name), `+ ${money(c.amount)}`)).join('')}
      ${Number(bill.round_off) ? tr('Round Off', `${Number(bill.round_off) < 0 ? '- ' : '+ '}${money(Math.abs(Number(bill.round_off)))}`) : ''}
      ${tr('Grand Total', money(grandTotal), true)}
      ${collected.length ? collected.map((c) => tr(`Prev. due &middot; Bill ${esc(stripBillPrefix(c.bill_number))}`, `+ ${money(c.amount)}`)).join('') +
        tr('Total', money(grandTotal + Number(bill.credit_collected || 0)), true) : ''}
    </div>
  </div>

  ${showGst ? `<table class="grid hsn" style="margin-top:10pt">
    <thead><tr><th>HSN/SAC</th><th class="r">Taxable amount</th><th class="r">CGST Rate</th>
      <th class="r">CGST Amt</th><th class="r">SGST Rate</th><th class="r">SGST Amt</th><th class="r">Total Tax</th></tr></thead>
    <tbody>${hsnRows}
      <tr class="b"><td>Total</td><td class="r">${money(totTaxable)}</td><td></td>
        <td class="r">${money(totTax / 2)}</td><td></td><td class="r">${money(totTax / 2)}</td>
        <td class="r">${money(totTax)}</td></tr>
    </tbody>
  </table>` : ''}

  <div class="foot">
    <div><b>Terms and conditions</b>${esc(bill.bill_footer_note && bill.bill_footer_note.trim() ? bill.bill_footer_note : 'Thanks for doing business with us!')}</div>
    <b>For: ${esc(bill.shop_name)}</b>
  </div>

  <div class="brand">Powered by Vengurlatech</div>
</div>
<div class="actions"><button type="button" onclick="window.print()">Download Invoice</button></div>
</body>
</html>`;
}

module.exports = { renderInvoice, amountToWords };
