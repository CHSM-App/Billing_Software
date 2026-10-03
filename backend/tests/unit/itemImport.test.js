const { makeDbMock } = require('../helpers/db');
const { mockPool } = makeDbMock();
jest.mock('../../src/db', () => mockPool);

const { parseImportRows } = require('../../src/routes/admin');

test('groups variant rows into one item, keeps plain items', () => {
  const { items, errors } = parseImportRows([
    { row: 2, name: 'Paneer Tikka', unit: 'plate', price: 220, tax_rate: 5, price_inclusive_tax: 'No' },
    { row: 3, name: 'Chicken 65', unit: 'plate', price: 999, barcode: 'X', variant_label: 'Half', variant_price: 180 },
    { row: 4, name: 'chicken 65 ', variant_label: 'Full', variant_price: 280, variant_barcode: '111', variant_stock: 5 },
    { row: 5, name: 'Rice', unit: 'KG', price: '95', price_inclusive_tax: 'Yes', barcode: 8901000000024 },
  ]);
  expect(errors).toEqual([]);
  expect(items).toHaveLength(3);
  const c = items.find((i) => i.name === 'Chicken 65');
  expect(c.price).toBeNull();
  expect(c.barcode).toBeNull();
  expect(c.variants.map((v) => [v.label, v.price, v.sort_order])).toEqual([['Half', 180, 0], ['Full', 280, 1]]);
  const rice = items.find((i) => i.name === 'Rice');
  expect(rice).toMatchObject({ unit: 'kg', price: 95, price_inclusive_tax: true, barcode: '8901000000024', low_stock_threshold: 50 });
});

test('reports row-level errors', () => {
  const { errors } = parseImportRows([
    { row: 2, name: 'A' },                                             // no price
    { row: 3, name: 'B', price: 10, unit: 'cup' },                     // bad unit
    { row: 4, name: 'C', price: 10 }, { row: 5, name: 'C', price: 12 }, // duplicate plain
    { row: 6, name: 'D', variant_label: 'S', variant_price: 1 },
    { row: 7, name: 'D', variant_price: 2 },                           // missing variant name
    { row: 8, name: 'E', price: 1, barcode: '9' }, { row: 9, name: 'F', price: 1, barcode: '9' },
    { row: 10, price: 5 },
  ]);
  expect(errors.map((e) => e.split(':')[0]).sort()).toEqual(
    ['Row 10', 'Row 2', 'Row 3', 'Row 5', 'Row 7', 'Row 9'].sort());
});
