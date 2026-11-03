'use strict';
// =============================================================================
// Paying off credit (udhaari) bills, in part or in full — migration 051.
//
// A credit bill owes its CREDIT PART: credit_amount for a split bill with a
// credit part (migration 050), else its whole Net Payable. Every payment made
// against it is a credit_payments row — from the Credit tab, or collected along
// with a later bill (paid_in_bill_id). What it still owes is the credit part
// less those rows; when that reaches 0 the bill flips to payment_status 'paid'.
//
// Used by routes/bills.js (dues collected at finalize) and routes/credit.js
// (the Credit tab's settle).
// =============================================================================

const { pool, sql } = require('./db');

const CREDIT_PART = 'ISNULL(b.credit_amount, b.total - b.discount_amount + ISNULL(b.round_off, 0))';
const PAID_SO_FAR = '(SELECT ISNULL(SUM(cp.amount), 0) FROM credit_payments cp WHERE cp.bill_id = b.id)';
/** SQL for what bill `b` still owes. */
const DUE = `(${CREDIT_PART} - ${PAID_SO_FAR})`;

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const MAX_COLLECTIONS = 50;

const round2 = (n) => Math.round(Number(n) * 100) / 100;
const key = (id) => String(id).toLowerCase();

/**
 * Validates a request's `[{ bill_id, amount }]`: UUIDs, each bill once,
 * amounts > 0. Returns { list } or { error }. An absent value is no
 * collections at all.
 */
function parseCollections(raw) {
  if (raw === undefined || raw === null) return { list: [] };
  if (!Array.isArray(raw) || raw.length > MAX_COLLECTIONS) {
    return { error: `collect must be a list of up to ${MAX_COLLECTIONS} bills` };
  }
  const list = [];
  for (const c of raw) {
    const billId = c && c.bill_id;
    const amount = round2(c && c.amount);
    if (typeof billId !== 'string' || !UUID_RE.test(billId)) {
      return { error: 'Each collected bill needs a valid bill_id' };
    }
    if (list.some((x) => key(x.bill_id) === key(billId))) {
      return { error: 'A bill is listed twice' };
    }
    if (!Number.isFinite(amount) || amount <= 0) {
      return { error: 'Each collected amount must be greater than 0' };
    }
    list.push({ bill_id: billId, amount });
  }
  return { list };
}

/**
 * Locks and reads what each listed bill still owes, then checks every
 * collection against it. Only this business's finalized, unpaid bills count —
 * an id that is not one cannot be paid. An entry whose amount is null is
 * filled in with everything that bill owes. Returns { list } with each
 * entry's bill_number added, or { error }.
 */
async function checkCollections(request, businessId, collections) {
  request.input('cp_business_id', sql.UniqueIdentifier, businessId);
  const names = collections.map((c, i) => {
    request.input(`cp_id${i}`, sql.UniqueIdentifier, c.bill_id);
    return `@cp_id${i}`;
  });
  const result = await request.query(`
    SELECT b.id, b.bill_number, ${DUE} AS due
    FROM bills b WITH (UPDLOCK, ROWLOCK)
    WHERE b.business_id = @cp_business_id
      AND b.id IN (${names.join(',')})
      AND b.status = 'finalized'
      AND b.payment_status = 'unpaid'
  `);
  const dues = new Map(result.recordset.map((r) => [key(r.id), r]));
  const list = [];
  for (const c of collections) {
    const bill = dues.get(key(c.bill_id));
    if (!bill) return { error: 'A credit bill was already paid or not found — refresh and try again' };
    const due = round2(bill.due);
    const amount = c.amount == null ? due : c.amount;
    if (amount > due + 0.005) {
      return { error: `Bill ${bill.bill_number} owes ₹${due.toFixed(2)} — less than ₹${amount.toFixed(2)}` };
    }
    if (amount > 0) list.push({ ...c, amount, bill_number: bill.bill_number });
  }
  return { list };
}

/**
 * Pours the money tenders ({mode, amount}; credit parts are skipped — credit
 * cannot pay credit) into the collections ({bill_id, amount}): biggest
 * collection first, each from the mode with the most left, spilling into the
 * next mode when one runs dry — so one old bill can be paid partly in cash and
 * partly by UPI.
 *
 * Returns the credit_payments rows ({bill_id, mode, amount}) and `left`, what
 * each mode still holds for the bill being settled — or { error } when the
 * money tenders cannot cover the collections.
 */
function pourIntoModes(collections, tenders) {
  const left = new Map();
  for (const t of tenders) {
    if (t.mode !== 'credit') left.set(t.mode, round2((left.get(t.mode) || 0) + t.amount));
  }
  const rows = [];
  const biggestFirst = [...collections].sort((a, b) => b.amount - a.amount);
  for (const c of biggestFirst) {
    let need = round2(c.amount);
    while (need > 0.004) {
      let mode = null;
      for (const [m, v] of left) {
        if (v > 0.004 && (mode === null || v > left.get(mode))) mode = m;
      }
      if (mode === null) {
        return { error: 'Old credit has to be paid now — it cannot go on credit again' };
      }
      const take = round2(Math.min(need, left.get(mode)));
      rows.push({ bill_id: c.bill_id, mode, amount: take });
      left.set(mode, round2(left.get(mode) - take));
      need = round2(need - take);
    }
  }
  return { rows, left };
}

/**
 * Records `rows` ({bill_id, mode, amount}) against their credit bills inside
 * `transaction`, then settles every bill left owing nothing. `paidInBillId` is
 * the bill they were collected with, or null for the Credit tab.
 * `settlementId` groups a Credit-tab payment's rows under one receipt
 * (migration 052); omitted for dues collected with a bill.
 */
async function recordCreditPayments(transaction, businessId, rows, paidInBillId, settlementId = null) {
  if (rows.length === 0) return;
  const ins = transaction.request()
    .input('cp_business_id', sql.UniqueIdentifier, businessId)
    .input('cp_paid_in', sql.UniqueIdentifier, paidInBillId || null);
  // Only named when set, so a DB without migration 052 keeps working for the
  // collect-with-a-bill path.
  if (settlementId) ins.input('cp_settlement', sql.UniqueIdentifier, settlementId);
  const values = rows.map((r, i) => {
    ins
      .input(`cp_bill${i}`, sql.UniqueIdentifier, r.bill_id)
      .input(`cp_mode${i}`, sql.NVarChar(20), r.mode)
      .input(`cp_amount${i}`, sql.Decimal(10, 2), r.amount);
    return `(@cp_business_id, @cp_bill${i}, @cp_paid_in, @cp_mode${i}, @cp_amount${i}${settlementId ? ', @cp_settlement' : ''})`;
  });
  await ins.query(`
    INSERT INTO credit_payments (business_id, bill_id, paid_in_bill_id, mode, amount${settlementId ? ', settlement_id' : ''})
    VALUES ${values.join(', ')}
  `);

  // Paid off → settled. settled_payment_mode keeps its meaning for older
  // readers: the one mode the bill was paid in, else 'split'.
  const ids = [...new Map(rows.map((r) => [key(r.bill_id), r.bill_id])).values()];
  const up = transaction.request().input('cp_business_id', sql.UniqueIdentifier, businessId);
  const names = ids.map((id, i) => {
    up.input(`cp_settle${i}`, sql.UniqueIdentifier, id);
    return `@cp_settle${i}`;
  });
  await up.query(`
    UPDATE b
    SET payment_status = 'paid',
        settled_at = GETUTCDATE(),
        settled_payment_mode = (
          SELECT CASE WHEN COUNT(DISTINCT cp.mode) = 1 THEN MIN(cp.mode) ELSE 'split' END
          FROM credit_payments cp WHERE cp.bill_id = b.id)
    FROM bills b
    WHERE b.business_id = @cp_business_id
      AND b.id IN (${names.join(',')})
      AND ${DUE} <= 0.004
  `);
}

/**
 * Undoes the old dues a bill collected, inside `transaction` — for when that
 * bill is voided. Its credit_payments rows go, and every old bill that now
 * owes something again is reopened (unpaid, no settled date or mode), exactly
 * as if the money had never come in.
 */
async function reverseCollections(transaction, businessId, paidInBillId) {
  const removed = await transaction.request()
    .input('cp_business_id', sql.UniqueIdentifier, businessId)
    .input('cp_paid_in', sql.UniqueIdentifier, paidInBillId)
    .query(`
      DELETE FROM credit_payments
      OUTPUT DELETED.bill_id
      WHERE paid_in_bill_id = @cp_paid_in AND business_id = @cp_business_id
    `);
  const ids = [...new Map((removed.recordset || [])
    .filter((r) => r.bill_id)
    .map((r) => [key(r.bill_id), r.bill_id])).values()];
  if (ids.length === 0) return;
  const up = transaction.request().input('cp_business_id', sql.UniqueIdentifier, businessId);
  const names = ids.map((id, i) => {
    up.input(`cp_reopen${i}`, sql.UniqueIdentifier, id);
    return `@cp_reopen${i}`;
  });
  await up.query(`
    UPDATE b
    SET payment_status = 'unpaid', settled_at = NULL, settled_payment_mode = NULL
    FROM bills b
    WHERE b.business_id = @cp_business_id
      AND b.id IN (${names.join(',')})
      AND b.status = 'finalized'
      AND ${DUE} > 0.004
  `);
}

/**
 * Adds the credit side of each bill, in at most two queries:
 *   - a bill that collected old dues (credit_collected > 0) gets
 *     `collected`: [{ bill_id, bill_number, amount }] — one per old bill;
 *   - a credit bill (whole, or split with a credit part) gets
 *     `credit_payments`: [{ amount, mode, created_at, paid_in_bill_number }]
 *     and `credit_paid`, their sum.
 * Bills with neither are left as they were.
 */
async function attachCreditInfo(bills) {
  const collectors = bills.filter((b) => Number(b.credit_collected) > 0);
  const debtors = bills.filter((b) => b.payment_mode === 'credit' || b.credit_amount != null);

  if (collectors.length) {
    const req = pool.request();
    const names = collectors.map((b, i) => {
      req.input(`cc${i}`, sql.UniqueIdentifier, b.id);
      return `@cc${i}`;
    });
    const r = await req.query(`
      SELECT cp.paid_in_bill_id, cp.bill_id, ob.bill_number, cp.mode, SUM(cp.amount) AS amount
      FROM credit_payments cp
      JOIN bills ob ON ob.id = cp.bill_id
      WHERE cp.paid_in_bill_id IN (${names.join(',')})
      GROUP BY cp.paid_in_bill_id, cp.bill_id, ob.bill_number, cp.mode
      ORDER BY ob.bill_number
    `);
    // Per old bill (the receipt's "Prev. due" lines) and per mode (so the
    // receipt can show everything the customer handed over, not just the
    // share this bill kept).
    const perBill = {};
    const perMode = {};
    for (const row of r.recordset) {
      const k = key(row.paid_in_bill_id);
      const bills = (perBill[k] ||= new Map());
      const old = bills.get(key(row.bill_id)) || { bill_id: row.bill_id, bill_number: row.bill_number, amount: 0 };
      old.amount = round2(old.amount + Number(row.amount));
      bills.set(key(row.bill_id), old);
      const modes = (perMode[k] ||= new Map());
      modes.set(row.mode, round2((modes.get(row.mode) || 0) + Number(row.amount)));
    }
    for (const b of collectors) {
      b.collected = [...(perBill[key(b.id)] || new Map()).values()];
      b.collected_by_mode = [...(perMode[key(b.id)] || new Map())]
        .map(([mode, amount]) => ({ mode, amount }));
    }
  }

  if (debtors.length) {
    const req = pool.request();
    const names = debtors.map((b, i) => {
      req.input(`cd${i}`, sql.UniqueIdentifier, b.id);
      return `@cd${i}`;
    });
    const r = await req.query(`
      SELECT cp.bill_id, cp.amount, cp.mode, cp.created_at, pb.bill_number AS paid_in_bill_number
      FROM credit_payments cp
      LEFT JOIN bills pb ON pb.id = cp.paid_in_bill_id
      WHERE cp.bill_id IN (${names.join(',')})
      ORDER BY cp.created_at
    `);
    const by = {};
    for (const row of r.recordset) {
      (by[key(row.bill_id)] ||= []).push({
        amount: round2(row.amount),
        mode: row.mode,
        created_at: row.created_at,
        paid_in_bill_number: row.paid_in_bill_number || null,
      });
    }
    for (const b of debtors) {
      b.credit_payments = by[key(b.id)] || [];
      b.credit_paid = round2(b.credit_payments.reduce((s, p) => s + p.amount, 0));
    }
  }
  return bills;
}

module.exports = {
  DUE,
  CREDIT_PART,
  PAID_SO_FAR,
  round2,
  parseCollections,
  checkCollections,
  pourIntoModes,
  recordCreditPayments,
  reverseCollections,
  attachCreditInfo,
};
