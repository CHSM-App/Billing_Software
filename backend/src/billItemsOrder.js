// One line order for every read that shows or prints a bill's dishes — the
// Open Orders card, kitchen tickets, receipts, reprints — grouped by menu
// category: major A–Z, then subcategory A–Z, uncategorised last, then name.
// bill_items' primary key is a random NEWID(), so without this the lines come
// back in GUID order. The app's cart sorts the same way (cart_provider.dart).
//
// Both expect bill_items aliased `bi`.
const BILL_ITEMS_JOIN = 'LEFT JOIN items it ON it.id = bi.item_id';
const BILL_ITEMS_ORDER = `ORDER BY
  CASE WHEN NULLIF(LTRIM(it.major_category), '') IS NULL THEN 1 ELSE 0 END, it.major_category,
  CASE WHEN NULLIF(LTRIM(it.category), '') IS NULL THEN 1 ELSE 0 END, it.category,
  bi.item_name`;

module.exports = { BILL_ITEMS_JOIN, BILL_ITEMS_ORDER };
