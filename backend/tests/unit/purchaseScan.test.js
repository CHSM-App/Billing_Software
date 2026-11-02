// The Anthropic SDK is never called here: only the pure helpers are exercised,
// and the SDK is mocked so an accidental call fails loudly instead of billing.
jest.mock('@anthropic-ai/sdk', () => jest.fn(() => {
  throw new Error('unit tests must not construct an Anthropic client');
}));

const {
  normalizeDraft, checkDraft, sniffMediaType, countPdfPages, aliasText, vendorKey, BILL_SCHEMA,
} = require('../../src/purchaseScan');

describe('BILL_SCHEMA', () => {
  // The API rejects a structured-output schema with more than 16 union-typed
  // parameters (400 "too many parameters with union types") — every scan failed.
  test('stays under the API limit of 16 nullable/union parameters', () => {
    let unions = 0;
    const walk = (node) => {
      if (!node || typeof node !== 'object') return;
      if (Array.isArray(node.anyOf) || Array.isArray(node.type)) unions += 1;
      Object.values(node).forEach(walk);
    };
    walk(BILL_SCHEMA);
    expect(unions).toBeLessThanOrEqual(16);
  });
});

const line = (over = {}) => ({
  name: 'Amul Butter 100g', quantity: 10, free_quantity: 0, total_quantity: null,
  unit: 'pcs', amount: 500, tax_rate: 12, cgst: 30, sgst: 30, igst: null, cess: null,
  hsn_code: '0405', ...over,
});

const header = (over = {}) => ({
  vendor_name: 'Shree Traders', vendor_gstin: '27ABCDE1234F1Z5', invoice_number: 'ST/101',
  invoice_date: '2026-10-05', is_interstate: false, subtotal: 500, discount_amount: null,
  total_tax: 60, round_off: null, other_charges: null, total: 560, ...over,
});

describe('normalizeDraft', () => {
  test('keeps a clean bill as-is and records the vendor wording', () => {
    const d = normalizeDraft({ header: header(), lines: [line()] });
    expect(d.header.vendor_gstin).toBe('27ABCDE1234F1Z5');
    expect(d.header.invoice_date).toBe('2026-10-05');
    expect(d.lines).toHaveLength(1);
    expect(d.lines[0].vendor_text).toBe('Amul Butter 100g');
  });

  test('invalid GSTIN becomes null; spaced/lower-case valid one is cleaned', () => {
    expect(normalizeDraft({ header: header({ vendor_gstin: '27ABCDE1234' }) }).header.vendor_gstin).toBeNull();
    expect(normalizeDraft({ header: header({ vendor_gstin: ' 27abcde 1234f1z5 ' }) }).header.vendor_gstin)
      .toBe('27ABCDE1234F1Z5');
  });

  test('schema placeholders read as "not printed": "" text, yes/no/unknown', () => {
    const d = normalizeDraft({
      header: header({ vendor_gstin: '', invoice_number: '', is_interstate: 'unknown' }),
      lines: [line({ unit: '', hsn_code: '' })],
    });
    expect(d.header.vendor_gstin).toBeNull();
    expect(d.header.invoice_number).toBeNull();
    expect(d.header.is_interstate).toBeNull();
    expect(d.lines[0].unit).toBeNull();
    expect(d.lines[0].hsn_code).toBeNull();
    expect(normalizeDraft({ header: header({ is_interstate: 'yes' }) }).header.is_interstate).toBe(true);
    expect(normalizeDraft({ header: header({ is_interstate: 'no' }) }).header.is_interstate).toBe(false);
  });

  test('invalid or impossible dates become null', () => {
    expect(normalizeDraft({ header: header({ invoice_date: '05/10/2026' }) }).header.invoice_date).toBeNull();
    expect(normalizeDraft({ header: header({ invoice_date: '2026-02-30' }) }).header.invoice_date).toBeNull();
  });

  test('null values stay null — nothing is invented', () => {
    const d = normalizeDraft({
      header: header({ total: null, total_tax: null }),
      lines: [line({ amount: null, tax_rate: null, cgst: null, sgst: null })],
    });
    expect(d.header.total).toBeNull();
    expect(d.lines[0].amount).toBeNull();
    expect(d.lines[0].tax_rate).toBeNull();
  });

  test('drops lines with zero, negative or missing quantity, or no name', () => {
    const d = normalizeDraft({
      header: header(),
      lines: [line({ quantity: 0 }), line({ quantity: -3 }), line({ quantity: null }),
        line({ name: '  ' }), line({ quantity: '4' })],
    });
    expect(d.lines).toHaveLength(1);
    expect(d.lines[0].quantity).toBe(4);
  });

  test('keeps valid free quantity; negative free becomes 0', () => {
    const d = normalizeDraft({ lines: [line({ free_quantity: 2 }), line({ free_quantity: -1 })] });
    expect(d.lines[0].free_quantity).toBe(2);
    expect(d.lines[1].free_quantity).toBe(0);
  });

  test('negative money values become null, round-off may be negative', () => {
    const d = normalizeDraft({ header: header({ total: -5, round_off: -0.4 }), lines: [line({ amount: -1 })] });
    expect(d.header.total).toBeNull();
    expect(d.header.round_off).toBe(-0.4);
    expect(d.lines[0].amount).toBeNull();
  });

  test('parses numbers printed with commas and the rupee sign', () => {
    const d = normalizeDraft({ header: header({ total: '₹1,234.50' }) });
    expect(d.header.total).toBe(1234.5);
  });

  test('tax rate outside 0–100 becomes null', () => {
    expect(normalizeDraft({ lines: [line({ tax_rate: 180 })] }).lines[0].tax_rate).toBeNull();
  });

  test('cuts long strings to their column widths', () => {
    const d = normalizeDraft({
      header: header({ vendor_name: 'V'.repeat(500), invoice_number: 'N'.repeat(80) }),
      lines: [line({ name: 'X'.repeat(300), unit: 'U'.repeat(40), hsn_code: '1'.repeat(20) })],
    });
    expect(d.header.vendor_name).toHaveLength(200);
    expect(d.header.invoice_number).toHaveLength(50);
    expect(d.lines[0].name).toHaveLength(200);
    expect(d.lines[0].unit).toHaveLength(20);
    expect(d.lines[0].hsn_code).toHaveLength(10);
  });

  test('malformed model output gives an empty draft, never a throw', () => {
    for (const bad of [null, undefined, 'text', 42, [], { header: 'x', lines: 'y' }, { lines: [null, 7] }]) {
      const d = normalizeDraft(bad);
      expect(d.lines).toEqual([]);
      expect(d.header.vendor_name).toBeNull();
    }
  });
});

describe('checkDraft', () => {
  const draft = (h, ls) => normalizeDraft({ header: h, lines: ls });

  test('a consistent bill produces no warnings', () => {
    expect(checkDraft(draft(header(), [line()]))).toEqual([]);
  });

  test('handles multiple GST rates on one bill', () => {
    const d = draft(header({ subtotal: 700, total_tax: 70, total: 770 }), [
      line(), // 500 @12% = 60
      line({ name: 'Rice', amount: 200, tax_rate: 5, cgst: 5, sgst: 5 }), // 200 @5% = 10
    ]);
    expect(checkDraft(d)).toEqual([]);
  });

  test('flags a line whose printed tax disagrees with its rate', () => {
    const w = checkDraft(draft(header({ total_tax: 90, total: 590 }), [line({ cgst: 45, sgst: 45 })]));
    expect(w.map((x) => x.code)).toContain('line_tax_mismatch');
  });

  test('flags IGST on an intrastate bill', () => {
    const w = checkDraft(draft(header(), [line({ cgst: null, sgst: null, igst: 60 })]));
    expect(w.map((x) => x.code)).toContain('tax_type_mismatch');
  });

  test('flags a wrong printed total without changing any value', () => {
    const d = draft(header({ total: 600 }), [line()]);
    const before = JSON.stringify(d);
    const w = checkDraft(d);
    expect(w).toContainEqual({ code: 'total_mismatch', printed: 600, computed: 560 });
    expect(JSON.stringify(d)).toBe(before);
  });

  test('missing line amount is flagged and skips the total checks', () => {
    const w = checkDraft(draft(header({ total: 9999 }), [line({ amount: null })]));
    expect(w.map((x) => x.code)).toEqual(['line_amount_missing']);
  });

  test('missing tax values are not flagged as mismatches', () => {
    const d = draft(header({ total_tax: null }), [line({ cgst: null, sgst: null })]);
    expect(checkDraft(d)).toEqual([]);
  });

  test('discount, other charges and round-off feed the total check', () => {
    // 500 net, 50 discount -> tax 60 * 450/500 = 54; +20 other +0.5 round
    const d = draft(header({ discount_amount: 50, total_tax: 54, other_charges: 20,
      round_off: 0.5, total: 524.5 }), [line()]);
    expect(checkDraft(d)).toEqual([]);
  });

  test('free quantity does not change the cost', () => {
    const d = draft(header(), [line({ free_quantity: 2 })]);
    expect(checkDraft(d)).toEqual([]);
  });

  test('flags printed cess as unsupported', () => {
    const w = checkDraft(draft(header(), [line({ cess: 5 })]));
    expect(w.map((x) => x.code)).toContain('cess_not_supported');
  });
});

describe('file checks', () => {
  test('sniffs real signatures and rejects others', () => {
    expect(sniffMediaType(Buffer.from([0xFF, 0xD8, 0xFF, 0xE0]))).toBe('image/jpeg');
    expect(sniffMediaType(Buffer.from([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]))).toBe('image/png');
    expect(sniffMediaType(Buffer.from('RIFF\0\0\0\0WEBPVP8 '))).toBe('image/webp');
    expect(sniffMediaType(Buffer.from('%PDF-1.7\n'))).toBe('application/pdf');
    expect(sniffMediaType(Buffer.from('<html>'))).toBeNull();
    expect(sniffMediaType({})).toBeNull();
  });

  test('counts PDF page objects, not the /Pages tree', () => {
    const pdf = Buffer.from('%PDF-1.4 /Type /Pages /Count 2 /Type /Page /Type/Page');
    expect(countPdfPages(pdf)).toBe(2);
  });
});

describe('alias keys', () => {
  test('wording match ignores case and spacing', () => {
    expect(aliasText('  AMUL  Butter 100G ')).toBe('amul butter 100g');
  });

  test('vendor is the GSTIN when known, else the normalised name', () => {
    expect(vendorKey('27abcde1234f1z5', 'Shree')).toBe('27ABCDE1234F1Z5');
    expect(vendorKey(null, ' Shree  Traders ')).toBe('shree traders');
  });
});
