// Customer-facing bill number formatting.
//
// Bills are stored as '<prefix>-<seq>' ('INV-0007', or 'INV-a7f4-0001' for
// bills numbered offline on a device). Customers only see the part after the
// prefix — on the WhatsApp message and the public receipt page — while the
// full bill_number stays the identifier inside the app and the database.

/**
 * Strips the leading letter prefix and its dash: 'INV-0007' → '0007',
 * 'INV-a7f4-0001' → 'a7f4-0001'. Numbers without such a prefix are returned
 * unchanged.
 * @param {string} billNumber
 * @returns {string}
 */
function stripBillPrefix(billNumber) {
  return String(billNumber ?? '').replace(/^[A-Za-z]+-/, '');
}

module.exports = { stripBillPrefix };
