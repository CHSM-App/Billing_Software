const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const { purchaseScanLimiter } = require('../middleware/rateLimiter');
const { GSTIN_RE, computeTotals } = require('../vendorBillMath');
const {
  PRIVATE_DIR, EXT, MAX_IMAGE_BYTES, MONTH_START_UTC_SQL,
  scanConfig, sniffMediaType, countPdfPages,
  extractPurchaseBill, normalizeDraft, checkDraft, aliasText, vendorKey,
} = require('../purchaseScan');
const audit = require('../audit');
const logger = require('../logger');

const router = express.Router();

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can access vendor bills' });
  }
  next();
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/**
 * Validate the line array. Returns an error string, or null when valid.
 *
 * A line may target an item, a variant, a raw material, or NOTHING — a freight
 * or service charge carries real ITC but has no stock to receive, and refusing
 * it would force the recorded invoice total to differ from the vendor's.
 */
function validateLines(lines) {
  if (!Array.isArray(lines) || lines.length === 0) {
    return 'At least one line item is required';
  }
  for (let i = 0; i < lines.length; i++) {
    const l = lines[i];
    const at = `Line ${i + 1}`;
    const targets = [l.item_id, l.variant_id, l.raw_material_id].filter(Boolean);
    if (targets.length > 1) {
      return `${at}: choose only one of item, variant or raw material`;
    }
    if (!targets.length && !String(l.name || '').trim()) {
      return `${at}: a description is required when no item is selected`;
    }
    const qty = parseFloat(l.quantity);
    if (!Number.isFinite(qty) || qty <= 0) {
      return `${at}: quantity must be greater than 0`;
    }
    const price = parseFloat(l.unit_price);
    if (!Number.isFinite(price) || price < 0) {
      return `${at}: rate must be 0 or more`;
    }
    if (l.tax_rate != null && l.tax_rate !== '') {
      const rate = parseFloat(l.tax_rate);
      if (!Number.isFinite(rate) || rate < 0 || rate > 100) {
        return `${at}: GST rate must be between 0 and 100`;
      }
    }
    // Scheme goods ("10 + 2 free"): received into stock, never charged.
    if (l.free_quantity != null && l.free_quantity !== '') {
      const free = parseFloat(l.free_quantity);
      if (!Number.isFinite(free) || free < 0) {
        return `${at}: free quantity must be 0 or more`;
      }
    }
  }
  return null;
}

/** Batch-resolve the item / variant / raw-material ids a bill's lines refer to. */
async function resolveTargets(transaction, businessId, lines) {
  const itemIds = [...new Set(lines.map((l) => l.item_id).filter(Boolean))];
  const varIds = [...new Set(lines.map((l) => l.variant_id).filter(Boolean))];
  const rawIds = [...new Set(lines.map((l) => l.raw_material_id).filter(Boolean))];

  const fetch = async (ids, query) => {
    const found = new Set();
    for (const id of ids) {
      const r = await transaction.request()
        .input('id', sql.UniqueIdentifier, id)
        .input('business_id', sql.UniqueIdentifier, businessId)
        .query(query);
      if (r.recordset.length) found.add(id);
    }
    return found;
  };

  const items = await fetch(itemIds,
    `SELECT id FROM items WHERE id = @id AND business_id = @business_id`);
  // Variants are scoped through their parent item's business.
  const variants = await fetch(varIds,
    `SELECT v.id FROM item_variants v
     INNER JOIN items i ON i.id = v.item_id
     WHERE v.id = @id AND i.business_id = @business_id`);
  const raws = await fetch(rawIds,
    `SELECT id FROM raw_materials WHERE id = @id AND business_id = @business_id`);

  for (const id of itemIds) if (!items.has(id)) return `Unknown item: ${id}`;
  for (const id of varIds) if (!variants.has(id)) return `Unknown size/variant: ${id}`;
  for (const id of rawIds) if (!raws.has(id)) return `Unknown raw material: ${id}`;
  return null;
}

/**
 * Move a line's stock. [sign] is +1 when receiving goods, -1 when reversing an
 * edit or delete.
 *
 * The `stock_quantity IS NOT NULL` guard is load-bearing: NULL means the owner
 * opted OUT of tracking that target, and receiving a purchase must not silently
 * opt them back in. Mirrors restoreLineStock in routes/bills.js.
 *
 * Unlike the sale-side decrement there is no `>= @qty` guard, so rowsAffected 0
 * means "untracked", NOT a failure — never treat it as one.
 *
 * Free (scheme) goods are received too: 10 bought + 2 free puts 12 on the shelf.
 */
async function applyLineStock(transaction, businessId, li, sign) {
  const qty = sign * (Number(li.quantity) + (Number(li.free_quantity) || 0));
  if (li.variant_id) {
    await transaction.request()
      .input('id', sql.UniqueIdentifier, li.variant_id)
      .input('qty', sql.Decimal(10, 2), qty)
      .query(`UPDATE item_variants SET stock_quantity = stock_quantity + @qty
              WHERE id = @id AND stock_quantity IS NOT NULL`);
  } else if (li.item_id) {
    await transaction.request()
      .input('id', sql.UniqueIdentifier, li.item_id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('qty', sql.Decimal(10, 2), qty)
      .query(`UPDATE items SET stock_quantity = stock_quantity + @qty
              WHERE id = @id AND business_id = @business_id
                AND stock_quantity IS NOT NULL`);
  } else if (li.raw_material_id) {
    await transaction.request()
      .input('id', sql.UniqueIdentifier, li.raw_material_id)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('qty', sql.Decimal(10, 2), qty)
      .query(`UPDATE raw_materials SET stock_quantity = stock_quantity + @qty
              WHERE id = @id AND business_id = @business_id
                AND stock_quantity IS NOT NULL`);
  }
  // No target -> a service/freight line; nothing to move.
}

const HEADER_COLS = `
  vb.id, vb.vendor_name, vb.vendor_gstin, vb.vendor_state,
  vb.invoice_number, vb.invoice_date,
  vb.subtotal, vb.tax_amount, vb.cgst_amount, vb.sgst_amount,
  vb.igst_amount, vb.cess_amount, vb.discount_amount, vb.round_off, vb.total,
  vb.is_interstate, vb.itc_eligible, vb.reverse_charge,
  vb.payment_mode, vb.payment_status, vb.amount_paid, vb.notes,
  vb.stock_applied, vb.scan_id, vb.created_at, vb.updated_at`;

function shapeHeader(row) {
  return {
    id: row.id,
    vendor_name: row.vendor_name,
    vendor_gstin: row.vendor_gstin,
    vendor_state: row.vendor_state,
    invoice_number: row.invoice_number,
    invoice_date: row.invoice_date.toISOString().slice(0, 10),
    subtotal: parseFloat(row.subtotal),
    tax_amount: parseFloat(row.tax_amount),
    cgst_amount: parseFloat(row.cgst_amount),
    sgst_amount: parseFloat(row.sgst_amount),
    igst_amount: parseFloat(row.igst_amount),
    cess_amount: parseFloat(row.cess_amount),
    discount_amount: parseFloat(row.discount_amount),
    round_off: parseFloat(row.round_off),
    total: parseFloat(row.total),
    is_interstate: !!row.is_interstate,
    itc_eligible: !!row.itc_eligible,
    reverse_charge: !!row.reverse_charge,
    payment_mode: row.payment_mode,
    payment_status: row.payment_status,
    amount_paid: parseFloat(row.amount_paid),
    notes: row.notes,
    stock_applied: !!row.stock_applied,
    scan_id: row.scan_id ?? null,
    // Only the single-bill read computes it; list rows report false.
    has_attachment: !!row.has_attachment,
    created_at: row.created_at,
    created_by_name: row.created_by_name,
    line_count: row.line_count != null ? Number(row.line_count) : undefined,
  };
}

async function fetchVendorBill(id, businessId) {
  const head = await pool.request()
    .input('id', sql.UniqueIdentifier, id)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT ${HEADER_COLS}, u.name AS created_by_name,
                   (SELECT CASE WHEN ps.file_path IS NOT NULL THEN 1 ELSE 0 END
                    FROM purchase_scans ps
                    WHERE ps.id = vb.scan_id AND ps.business_id = vb.business_id
                   ) AS has_attachment
            FROM vendor_bills vb
            LEFT JOIN users u ON u.id = vb.created_by_user_id
            WHERE vb.id = @id AND vb.business_id = @business_id`);
  if (!head.recordset.length) return null;

  const lines = await pool.request()
    .input('id', sql.UniqueIdentifier, id)
    .query(`SELECT id, item_id, variant_id, raw_material_id, item_name,
                   quantity, free_quantity, unit, unit_price, tax_rate, hsn_code,
                   line_total, sort_order
            FROM vendor_bill_items
            WHERE vendor_bill_id = @id ORDER BY sort_order`);

  return {
    ...shapeHeader(head.recordset[0]),
    lines: lines.recordset.map((l) => ({
      id: l.id,
      item_id: l.item_id,
      variant_id: l.variant_id,
      raw_material_id: l.raw_material_id,
      item_name: l.item_name,
      quantity: parseFloat(l.quantity),
      free_quantity: parseFloat(l.free_quantity) || 0,
      unit: l.unit,
      unit_price: parseFloat(l.unit_price),
      tax_rate: l.tax_rate != null ? parseFloat(l.tax_rate) : null,
      hsn_code: l.hsn_code,
      line_total: parseFloat(l.line_total),
      sort_order: l.sort_order,
    })),
  };
}

/** Read the business flags a purchase depends on. Called INSIDE the transaction
 *  so inventory/GST cannot be toggled between the read and the write. */
async function readBusinessFlags(transaction, businessId) {
  const r = await transaction.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT inventory_enabled, gst_enabled, gst_number, state
            FROM businesses WHERE id = @business_id`);
  const b = r.recordset[0] || {};
  return {
    inventoryEnabled: !!b.inventory_enabled,
    gstEnabled: !!b.gst_enabled,
    gstin: b.gst_number || '',
    state: b.state || '',
  };
}

const UUID_RE = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;

/**
 * A bill may name the AI scan it was made from (its original file). Only a
 * finished scan of THIS business qualifies — never another shop's file.
 * Returns an error string, or null when there is no scan_id or it is valid.
 */
async function verifyScan(transaction, businessId, scanId) {
  if (scanId == null || scanId === '') return null;
  if (!UUID_RE.test(String(scanId))) return 'Unknown bill scan';
  const r = await transaction.request()
    .input('scan_id', sql.UniqueIdentifier, scanId)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT id FROM purchase_scans
            WHERE id = @scan_id AND business_id = @business_id AND status = 'ok'`);
  return r.recordset.length ? null : 'Unknown bill scan';
}

/**
 * Learn "this vendor's wording means this stock target" from lines the owner
 * has just SAVED — a confirmed mapping, not an AI guess. Runs inside the save
 * transaction, so a failed save learns nothing. Only scanned lines carry
 * vendor_text; hand-typed lines are skipped.
 */
async function saveVendorAliases(transaction, businessId, head, lines) {
  const key = vendorKey(head.gstin, head.vendorName);
  if (!key) return;
  for (const l of lines) {
    const text = aliasText(l.vendor_text);
    const targets = [l.item_id, l.variant_id, l.raw_material_id].filter(Boolean);
    if (!text || targets.length !== 1) continue;
    await transaction.request()
      .input('business_id', sql.UniqueIdentifier, businessId)
      .input('vendor_key', sql.NVarChar(200), key)
      .input('vendor_text', sql.NVarChar(200), text)
      .input('item_id', sql.UniqueIdentifier, l.item_id || null)
      .input('variant_id', sql.UniqueIdentifier, l.variant_id || null)
      .input('raw_material_id', sql.UniqueIdentifier, l.raw_material_id || null)
      .input('in_packs', sql.Bit, l.in_packs ? 1 : 0)
      .query(`
        MERGE vendor_item_aliases WITH (HOLDLOCK) AS t
        USING (SELECT @business_id AS business_id, @vendor_key AS vendor_key,
                      @vendor_text AS vendor_text) AS s
          ON t.business_id = s.business_id AND t.vendor_key = s.vendor_key
             AND t.vendor_text = s.vendor_text
        WHEN MATCHED THEN UPDATE SET
          item_id = @item_id, variant_id = @variant_id,
          raw_material_id = @raw_material_id, in_packs = @in_packs,
          updated_at = SYSUTCDATETIME()
        WHEN NOT MATCHED THEN INSERT
          (business_id, vendor_key, vendor_text, item_id, variant_id,
           raw_material_id, in_packs)
          VALUES (@business_id, @vendor_key, @vendor_text, @item_id, @variant_id,
                  @raw_material_id, @in_packs);`);
  }
}

/** Normalise + validate the header fields shared by POST and PUT. */
function readHeader(body) {
  const vendorName = String(body.vendor_name || '').trim();
  if (!vendorName) return { error: 'Vendor name is required' };

  const invoiceNumber = String(body.invoice_number || '').trim();
  if (!invoiceNumber) return { error: 'Invoice number is required' };

  const invoiceDate = String(body.invoice_date || '').trim();
  if (!/^\d{4}-\d{2}-\d{2}$/.test(invoiceDate)) {
    return { error: 'Invoice date must be YYYY-MM-DD' };
  }

  let gstin = body.vendor_gstin ? String(body.vendor_gstin).trim().toUpperCase() : null;
  if (gstin) {
    // Reject a malformed GSTIN outright: it silently breaks GSTR-2B matching
    // later, which is far more expensive to debug than a form error now.
    if (!GSTIN_RE.test(gstin)) return { error: 'Vendor GSTIN is not valid' };
  } else {
    gstin = null;
  }

  const status = String(body.payment_status || 'paid');
  if (!['paid', 'unpaid', 'partial'].includes(status)) {
    return { error: 'Payment status must be paid, unpaid or partial' };
  }

  return {
    vendorName: vendorName.slice(0, 200),
    gstin,
    vendorState: body.vendor_state ? String(body.vendor_state).trim().slice(0, 100) : null,
    invoiceNumber: invoiceNumber.slice(0, 50),
    invoiceDate,
    paymentMode: String(body.payment_mode || 'cash').slice(0, 20),
    paymentStatus: status,
    amountPaid: parseFloat(body.amount_paid) || 0,
    notes: body.notes ? String(body.notes).trim().slice(0, 500) : null,
    itcEligible: body.itc_eligible === undefined ? true : !!body.itc_eligible,
    reverseCharge: !!body.reverse_charge,
  };
}

/** True when a duplicate-key violation tripped the unique invoice index. */
const isDuplicateKey = (err) => err && (err.number === 2601 || err.number === 2627);

// ---------------------------------------------------------------------------
// GET /api/vendor-bills/vendors
//
// Declared BEFORE '/:id' — otherwise "vendors" is parsed as a bill id and the
// UniqueIdentifier bind throws.
// ---------------------------------------------------------------------------
router.get('/vendors', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT vendor_name AS name,
               MAX(vendor_gstin) AS gstin,
               MAX(vendor_state) AS state,
               COUNT(*) AS bill_count
        FROM vendor_bills
        WHERE business_id = @business_id
        GROUP BY vendor_name
        ORDER BY COUNT(*) DESC, vendor_name ASC`);
    return res.json(result.recordset.map((r) => ({
      name: r.name,
      gstin: r.gstin,
      state: r.state,
      bill_count: Number(r.bill_count),
    })));
  } catch (err) {
    logger.error({ err }, 'List vendors error');
    return res.status(500).json({ error: 'Failed to load vendors' });
  }
});

// ---------------------------------------------------------------------------
// AI bill scanning (purchaseScan.js). The scan only returns a DRAFT for the
// owner to review — saving still goes through POST / below. Declared BEFORE
// '/:id' for the same reason as '/vendors'.
// ---------------------------------------------------------------------------

// Scoped to the scan route, like jpegBody in businesses.js; the global JSON
// parser is untouched. Anything else leaves req.body as {} and fails the sniff.
const scanBody = express.raw({ type: Object.keys(EXT), limit: scanConfig().maxFileBytes });

/** Absolute path of a stored bill file, refusing anything outside PRIVATE_DIR. */
function scanFilePath(rel) {
  const root = path.resolve(PRIVATE_DIR);
  const abs = path.resolve(root, String(rel || ''));
  return rel && abs.startsWith(root + path.sep) ? abs : null;
}

/**
 * The admin's switch, this business's monthly allowance, and how much of it is
 * used: successful scans this (IST) month plus in-flight ones. Failed scans
 * never count. With [lock], the subscription row is held (UPDLOCK, HOLDLOCK)
 * until the caller's transaction ends, so two simultaneous scans by one shop
 * queue on it and cannot both take the last free scan.
 */
async function readScanAllowance(newRequest, businessId, lock) {
  const sub = await newRequest()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT allow_purchase_scan, purchase_scan_limit
            FROM subscriptions ${lock ? 'WITH (UPDLOCK, HOLDLOCK)' : ''}
            WHERE business_id = @business_id`);
  const s = sub.recordset[0] || {};
  const count = await newRequest()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT COUNT(*) AS used FROM purchase_scans
            WHERE business_id = @business_id
              AND created_at >= ${MONTH_START_UTC_SQL}
              AND (status = 'ok' OR (status = 'pending'
                   AND created_at > DATEADD(minute, -10, SYSUTCDATETIME())))`);
  return {
    // NULL = never enabled: scanning costs money, so it is opt-in per shop.
    enabled: !!s.allow_purchase_scan,
    limit: s.purchase_scan_limit ?? scanConfig().monthlyLimit,
    used: Number(count.recordset[0]?.used) || 0,
  };
}

/** Delete a scan's stored file (if any) and forget its path. Business-scoped. */
async function removeScanFile(businessId, scanId, knownPath) {
  let rel = knownPath;
  if (rel === undefined) {
    const r = await pool.request()
      .input('id', sql.UniqueIdentifier, scanId)
      .input('business_id', sql.UniqueIdentifier, businessId)
      .query(`SELECT file_path FROM purchase_scans
              WHERE id = @id AND business_id = @business_id`);
    rel = r.recordset[0]?.file_path;
  }
  const abs = scanFilePath(rel);
  if (abs) {
    await fs.promises.unlink(abs).catch((err) => { if (err.code !== 'ENOENT') throw err; });
  }
  await pool.request()
    .input('id', sql.UniqueIdentifier, scanId)
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`UPDATE purchase_scans SET file_path = NULL
            WHERE id = @id AND business_id = @business_id`);
}

// ponytail: abandoned files (scanned, never saved as a bill) are swept on the
// shop's NEXT scan rather than by a scheduler — the backend has none. A shop
// that stops scanning keeps its last week's files; add a daily job if that
// disk use ever matters.
async function cleanupAbandonedScans(businessId) {
  const r = await pool.request()
    .input('business_id', sql.UniqueIdentifier, businessId)
    .query(`SELECT ps.id, ps.file_path FROM purchase_scans ps
            WHERE ps.business_id = @business_id AND ps.file_path IS NOT NULL
              AND ps.created_at < DATEADD(day, -7, SYSUTCDATETIME())
              AND NOT EXISTS (SELECT 1 FROM vendor_bills vb
                              WHERE vb.business_id = @business_id AND vb.scan_id = ps.id)`);
  for (const row of r.recordset) {
    await removeScanFile(businessId, row.id, row.file_path);
  }
}

async function finishScan(scanId, status, { usage = {}, reason = null, keepFile = true } = {}) {
  await pool.request()
    .input('id', sql.UniqueIdentifier, scanId)
    .input('status', sql.NVarChar(10), status)
    .input('model', sql.NVarChar(100), usage.model || null)
    .input('input_tokens', sql.Int, usage.input_tokens || 0)
    .input('output_tokens', sql.Int, usage.output_tokens || 0)
    .input('failure_reason', sql.NVarChar(500), reason ? String(reason).slice(0, 500) : null)
    .query(`UPDATE purchase_scans SET status = @status,
              model = COALESCE(@model, model),
              input_tokens = @input_tokens, output_tokens = @output_tokens,
              failure_reason = @failure_reason
              ${keepFile ? '' : ', file_path = NULL'}
            WHERE id = @id`);
}

// GET /api/vendor-bills/scan/status — whether to offer "Scan bill", and usage.
router.get('/scan/status', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const cfg = scanConfig();
    const a = await readScanAllowance(() => pool.request(), req.user.business_id, false);
    return res.json({
      // A server without a key/model can't scan, whatever the admin allowed.
      enabled: a.enabled && !!cfg.apiKey && !!cfg.model,
      used: a.used,
      limit: a.limit,
    });
  } catch (err) {
    logger.error({ err }, 'Scan status error');
    return res.status(500).json({ error: 'Failed to load scan status' });
  }
});

// POST /api/vendor-bills/scan — body: the bill's bytes (JPEG/PNG/WebP/PDF).
router.post('/scan', requireAuth, ownerOnly, purchaseScanLimiter, scanBody, async (req, res) => {
  const cfg = scanConfig();
  const buf = req.body;
  const declared = String(req.headers['content-type'] || '').split(';')[0].trim().toLowerCase();
  const mediaType = sniffMediaType(buf);
  if (!mediaType || mediaType !== declared) {
    return res.status(400).json({ error: 'Upload a JPG, PNG, WebP or PDF file' });
  }
  if (mediaType !== 'application/pdf' && buf.length > Math.min(MAX_IMAGE_BYTES, cfg.maxFileBytes)) {
    return res.status(400).json({ error: 'This photo is too large. Use a photo under 5 MB.' });
  }
  let pageCount = null;
  if (mediaType === 'application/pdf') {
    pageCount = countPdfPages(buf);
    if (pageCount > cfg.maxPdfPages) {
      return res.status(400).json({
        error: `This PDF has ${pageCount} pages; bills of up to ${cfg.maxPdfPages} pages can be scanned.`,
      });
    }
  }
  if (!cfg.apiKey || !cfg.model) {
    return res.status(503).json({ error: 'Bill scanning is not set up on this server' });
  }

  const businessId = req.user.business_id;
  const scanId = crypto.randomUUID();
  // Generated name only — nothing from the client reaches the file system.
  const relPath = `${businessId}/${scanId}.${EXT[mediaType]}`;

  try {
    await poolConnect;

    // ── Reserve one scan of the allowance, atomically ─────────────────────
    let allowance;
    const tx = pool.transaction();
    await tx.begin();
    try {
      allowance = await readScanAllowance(() => tx.request(), businessId, true);
      if (!allowance.enabled) {
        await tx.rollback();
        return res.status(403).json({
          error: "Bill scanning isn't enabled for your shop. Contact Vittam to enable it.",
        });
      }
      if (allowance.used >= allowance.limit) {
        await tx.rollback();
        return res.status(429).json({
          error: `Monthly scan limit reached (${allowance.limit}). It resets on the 1st.`,
        });
      }
      await tx.request()
        .input('id', sql.UniqueIdentifier, scanId)
        .input('business_id', sql.UniqueIdentifier, businessId)
        .input('user_id', sql.UniqueIdentifier, req.user.user_id)
        .input('model', sql.NVarChar(100), cfg.model)
        .input('file_path', sql.NVarChar(500), relPath)
        .input('media_type', sql.NVarChar(50), mediaType)
        .input('page_count', sql.Int, pageCount)
        .query(`INSERT INTO purchase_scans
                  (id, business_id, user_id, model, status, file_path, media_type, page_count)
                VALUES
                  (@id, @business_id, @user_id, @model, 'pending', @file_path, @media_type, @page_count)`);
      await tx.commit();
    } catch (err) {
      await tx.rollback();
      throw err;
    }

    cleanupAbandonedScans(businessId)
      .catch((err) => logger.error({ err }, 'purchase scan cleanup failed'));

    // ── Store the original, then read it ──────────────────────────────────
    const abs = scanFilePath(relPath);
    let draft, warnings;
    try {
      await fs.promises.mkdir(path.dirname(abs), { recursive: true });
      await fs.promises.writeFile(abs, buf);
      const out = await extractPurchaseBill(buf, mediaType);
      draft = normalizeDraft(out.raw);
      warnings = checkDraft(draft);
      await finishScan(scanId, 'ok', { usage: out.usage });
    } catch (err) {
      logger.warn({ err, scanId }, 'purchase scan failed');
      await fs.promises.unlink(abs).catch(() => {});
      await finishScan(scanId, 'failed', { usage: err.usage, reason: err.message, keepFile: false })
        .catch((e) => logger.error({ err: e }, 'mark purchase scan failed'));
      return res.status(502).json({
        error: "Couldn't read this bill. Try a clearer, well-lit photo of the whole bill.",
      });
    }

    // ── Lines this vendor's wording has been mapped before ────────────────
    // Best effort: the scan already succeeded (and counted), so a lookup
    // failure only means the owner links lines by hand.
    try {
      const key = vendorKey(draft.header.vendor_gstin, draft.header.vendor_name);
      if (key && draft.lines.length) {
        const r = await pool.request()
          .input('business_id', sql.UniqueIdentifier, businessId)
          .input('vendor_key', sql.NVarChar(200), key)
          .query(`SELECT vendor_text, item_id, variant_id, raw_material_id, in_packs
                  FROM vendor_item_aliases
                  WHERE business_id = @business_id AND vendor_key = @vendor_key`);
        const byText = new Map(r.recordset.map((a) => [a.vendor_text, a]));
        for (const l of draft.lines) {
          const a = byText.get(aliasText(l.vendor_text));
          if (a) {
            l.match = {
              item_id: a.item_id || null,
              variant_id: a.variant_id || null,
              raw_material_id: a.raw_material_id || null,
              in_packs: !!a.in_packs,
            };
          }
        }
      }
    } catch (err) {
      logger.error({ err }, 'purchase scan alias lookup failed');
    }

    return res.json({
      scan_id: scanId,
      draft,
      warnings,
      scans_used: allowance.used + 1,
      scans_limit: allowance.limit,
    });
  } catch (err) {
    logger.error({ err }, 'Purchase scan error');
    return res.status(500).json({ error: 'Failed to scan the bill' });
  }
});

// GET /api/vendor-bills/:id/attachment — the original invoice, owner only.
router.get('/:id/attachment', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    if (!UUID_RE.test(req.params.id)) {
      return res.status(404).json({ error: 'No original bill stored' });
    }
    // Joined on business_id at BOTH tables: another shop's bill id finds nothing.
    const r = await pool.request()
      .input('id', sql.UniqueIdentifier, req.params.id)
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`SELECT ps.file_path, ps.media_type
              FROM vendor_bills vb
              INNER JOIN purchase_scans ps
                ON ps.id = vb.scan_id AND ps.business_id = vb.business_id
              WHERE vb.id = @id AND vb.business_id = @business_id`);
    const row = r.recordset[0];
    const abs = row && scanFilePath(row.file_path);
    if (!abs) return res.status(404).json({ error: 'No original bill stored' });
    res.set('Cache-Control', 'private, no-store');
    res.type(row.media_type);
    return res.sendFile(abs, (err) => {
      if (err && !res.headersSent) res.status(404).json({ error: 'No original bill stored' });
    });
  } catch (err) {
    logger.error({ err }, 'Vendor bill attachment error');
    return res.status(500).json({ error: 'Failed to load the original bill' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/vendor-bills?from&to&vendor&payment_status
// ---------------------------------------------------------------------------
router.get('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const { from, to, vendor, payment_status } = req.query;

    let query = `
      SELECT ${HEADER_COLS}, u.name AS created_by_name,
             (SELECT COUNT(*) FROM vendor_bill_items vbi
              WHERE vbi.vendor_bill_id = vb.id) AS line_count
      FROM vendor_bills vb
      LEFT JOIN users u ON u.id = vb.created_by_user_id
      WHERE vb.business_id = @business_id`;

    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id);

    if (from) { query += ` AND vb.invoice_date >= @from`; request.input('from', sql.Date, from); }
    if (to) { query += ` AND vb.invoice_date <= @to`; request.input('to', sql.Date, to); }
    if (vendor) {
      query += ` AND vb.vendor_name LIKE @vendor`;
      request.input('vendor', sql.NVarChar(200), `%${vendor}%`);
    }
    if (payment_status) {
      query += ` AND vb.payment_status = @payment_status`;
      request.input('payment_status', sql.NVarChar(20), payment_status);
    }
    query += ` ORDER BY vb.invoice_date DESC, vb.created_at DESC`;

    const result = await request.query(query);
    return res.json(result.recordset.map(shapeHeader));
  } catch (err) {
    logger.error({ err }, 'List vendor bills error');
    return res.status(500).json({ error: 'Failed to load vendor bills' });
  }
});

// ---------------------------------------------------------------------------
// GET /api/vendor-bills/:id
// ---------------------------------------------------------------------------
router.get('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;
    const bill = await fetchVendorBill(req.params.id, req.user.business_id);
    if (!bill) return res.status(404).json({ error: 'Vendor bill not found' });
    return res.json(bill);
  } catch (err) {
    logger.error({ err }, 'Get vendor bill error');
    return res.status(500).json({ error: 'Failed to load vendor bill' });
  }
});

// ---------------------------------------------------------------------------
// POST /api/vendor-bills
// ---------------------------------------------------------------------------
router.post('/', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const head = readHeader(req.body);
    if (head.error) return res.status(400).json({ error: head.error });

    const lineError = validateLines(req.body.lines);
    if (lineError) return res.status(400).json({ error: lineError });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      const flags = await readBusinessFlags(transaction, req.user.business_id);

      const targetError = await resolveTargets(
        transaction, req.user.business_id, req.body.lines)
        || await verifyScan(transaction, req.user.business_id, req.body.scan_id);
      if (targetError) {
        await transaction.rollback();
        return res.status(400).json({ error: targetError });
      }

      // Interstate is derived from the state codes that lead each GSTIN, with
      // an explicit client value winning (bill-to / ship-to cases differ).
      const derivedInterstate = !!(head.gstin && flags.gstin
        && head.gstin.slice(0, 2) !== flags.gstin.slice(0, 2));
      const isInterstate = req.body.is_interstate === undefined
        ? derivedInterstate
        : !!req.body.is_interstate;

      const totals = computeTotals(req.body.lines, {
        isInterstate,
        discountAmount: req.body.discount_amount,
        roundOff: req.body.round_off,
      });

      const inserted = await transaction.request()
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('vendor_name', sql.NVarChar(200), head.vendorName)
        .input('vendor_gstin', sql.NVarChar(15), head.gstin)
        .input('vendor_state', sql.NVarChar(100), head.vendorState)
        .input('invoice_number', sql.NVarChar(50), head.invoiceNumber)
        .input('invoice_date', sql.Date, head.invoiceDate)
        .input('subtotal', sql.Decimal(12, 2), totals.subtotal)
        .input('tax_amount', sql.Decimal(12, 2), totals.taxAmount)
        .input('cgst_amount', sql.Decimal(12, 2), totals.cgst)
        .input('sgst_amount', sql.Decimal(12, 2), totals.sgst)
        .input('igst_amount', sql.Decimal(12, 2), totals.igst)
        .input('discount_amount', sql.Decimal(12, 2), totals.discount)
        .input('round_off', sql.Decimal(10, 2), totals.roundOff)
        .input('total', sql.Decimal(12, 2), totals.total)
        .input('is_interstate', sql.Bit, isInterstate ? 1 : 0)
        .input('itc_eligible', sql.Bit, head.itcEligible ? 1 : 0)
        .input('reverse_charge', sql.Bit, head.reverseCharge ? 1 : 0)
        .input('payment_mode', sql.NVarChar(20), head.paymentMode)
        .input('payment_status', sql.NVarChar(20), head.paymentStatus)
        .input('amount_paid', sql.Decimal(12, 2), head.amountPaid)
        .input('notes', sql.NVarChar(500), head.notes)
        .input('stock_applied', sql.Bit, flags.inventoryEnabled ? 1 : 0)
        .input('created_by_user_id', sql.UniqueIdentifier, req.user.user_id)
        .input('scan_id', sql.UniqueIdentifier, req.body.scan_id || null)
        .query(`
          INSERT INTO vendor_bills (
            business_id, vendor_name, vendor_gstin, vendor_state,
            invoice_number, invoice_date, subtotal, tax_amount,
            cgst_amount, sgst_amount, igst_amount,
            discount_amount, round_off, total,
            is_interstate, itc_eligible, reverse_charge,
            payment_mode, payment_status, amount_paid, notes,
            stock_applied, created_by_user_id, scan_id)
          OUTPUT INSERTED.id
          VALUES (
            @business_id, @vendor_name, @vendor_gstin, @vendor_state,
            @invoice_number, @invoice_date, @subtotal, @tax_amount,
            @cgst_amount, @sgst_amount, @igst_amount,
            @discount_amount, @round_off, @total,
            @is_interstate, @itc_eligible, @reverse_charge,
            @payment_mode, @payment_status, @amount_paid, @notes,
            @stock_applied, @created_by_user_id, @scan_id)`);

      const billId = inserted.recordset[0].id;

      // mssql requests are single-use: a fresh one per statement.
      for (const li of totals.lines) {
        await transaction.request()
          .input('vendor_bill_id', sql.UniqueIdentifier, billId)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('variant_id', sql.UniqueIdentifier, li.variant_id)
          .input('raw_material_id', sql.UniqueIdentifier, li.raw_material_id)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('free_quantity', sql.Decimal(10, 2), li.free_quantity)
          .input('unit', sql.NVarChar(20), li.unit)
          .input('unit_price', sql.Decimal(12, 4), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('hsn_code', sql.NVarChar(10), li.hsn_code)
          .input('line_total', sql.Decimal(12, 2), li.line_total)
          .input('sort_order', sql.Int, li.sort_order)
          .query(`
            INSERT INTO vendor_bill_items (
              vendor_bill_id, item_id, variant_id, raw_material_id, item_name,
              quantity, free_quantity, unit, unit_price, tax_rate, hsn_code,
              line_total, sort_order)
            VALUES (
              @vendor_bill_id, @item_id, @variant_id, @raw_material_id, @item_name,
              @quantity, @free_quantity, @unit, @unit_price, @tax_rate, @hsn_code,
              @line_total, @sort_order)`);
      }

      if (flags.inventoryEnabled) {
        for (const li of totals.lines) {
          await applyLineStock(transaction, req.user.business_id, li, +1);
        }
      }

      await saveVendorAliases(transaction, req.user.business_id, head, req.body.lines);

      await transaction.commit();

      const bill = await fetchVendorBill(billId, req.user.business_id);
      audit.logVendorBillCreated(
        req.user,
        { ...bill, business_id: req.user.business_id },
        totals.lines.length,
      ).catch((err) => logger.error({ err }, 'audit vendor_bill_created failed'));

      return res.status(201).json(bill);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    if (isDuplicateKey(err)) {
      return res.status(409).json({
        error: 'This invoice number is already recorded for this vendor',
      });
    }
    logger.error({ err }, 'Create vendor bill error');
    return res.status(500).json({ error: 'Failed to save vendor bill' });
  }
});

// ---------------------------------------------------------------------------
// PUT /api/vendor-bills/:id — full replace (header + lines)
// ---------------------------------------------------------------------------
router.put('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const head = readHeader(req.body);
    if (head.error) return res.status(400).json({ error: head.error });

    const lineError = validateLines(req.body.lines);
    if (lineError) return res.status(400).json({ error: lineError });

    const before = await fetchVendorBill(req.params.id, req.user.business_id);
    if (!before) return res.status(404).json({ error: 'Vendor bill not found' });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      const flags = await readBusinessFlags(transaction, req.user.business_id);

      const targetError = await resolveTargets(
        transaction, req.user.business_id, req.body.lines)
        || await verifyScan(transaction, req.user.business_id, req.body.scan_id);
      if (targetError) {
        await transaction.rollback();
        return res.status(400).json({ error: targetError });
      }

      // Reverse whatever stock this bill previously added, but only if it was
      // actually applied — inventory may have been off when it was created.
      if (before.stock_applied) {
        for (const li of before.lines) {
          await applyLineStock(transaction, req.user.business_id, li, -1);
        }
      }

      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .query(`DELETE FROM vendor_bill_items WHERE vendor_bill_id = @id`);

      const derivedInterstate = !!(head.gstin && flags.gstin
        && head.gstin.slice(0, 2) !== flags.gstin.slice(0, 2));
      const isInterstate = req.body.is_interstate === undefined
        ? derivedInterstate
        : !!req.body.is_interstate;

      const totals = computeTotals(req.body.lines, {
        isInterstate,
        discountAmount: req.body.discount_amount,
        roundOff: req.body.round_off,
      });

      await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .input('vendor_name', sql.NVarChar(200), head.vendorName)
        .input('vendor_gstin', sql.NVarChar(15), head.gstin)
        .input('vendor_state', sql.NVarChar(100), head.vendorState)
        .input('invoice_number', sql.NVarChar(50), head.invoiceNumber)
        .input('invoice_date', sql.Date, head.invoiceDate)
        .input('subtotal', sql.Decimal(12, 2), totals.subtotal)
        .input('tax_amount', sql.Decimal(12, 2), totals.taxAmount)
        .input('cgst_amount', sql.Decimal(12, 2), totals.cgst)
        .input('sgst_amount', sql.Decimal(12, 2), totals.sgst)
        .input('igst_amount', sql.Decimal(12, 2), totals.igst)
        .input('discount_amount', sql.Decimal(12, 2), totals.discount)
        .input('round_off', sql.Decimal(10, 2), totals.roundOff)
        .input('total', sql.Decimal(12, 2), totals.total)
        .input('is_interstate', sql.Bit, isInterstate ? 1 : 0)
        .input('itc_eligible', sql.Bit, head.itcEligible ? 1 : 0)
        .input('reverse_charge', sql.Bit, head.reverseCharge ? 1 : 0)
        .input('payment_mode', sql.NVarChar(20), head.paymentMode)
        .input('payment_status', sql.NVarChar(20), head.paymentStatus)
        .input('amount_paid', sql.Decimal(12, 2), head.amountPaid)
        .input('notes', sql.NVarChar(500), head.notes)
        .input('stock_applied', sql.Bit, flags.inventoryEnabled ? 1 : 0)
        .input('scan_id', sql.UniqueIdentifier, req.body.scan_id || null)
        .query(`
          UPDATE vendor_bills SET
            vendor_name = @vendor_name, vendor_gstin = @vendor_gstin,
            vendor_state = @vendor_state, invoice_number = @invoice_number,
            invoice_date = @invoice_date, subtotal = @subtotal,
            tax_amount = @tax_amount, cgst_amount = @cgst_amount,
            sgst_amount = @sgst_amount, igst_amount = @igst_amount,
            discount_amount = @discount_amount, round_off = @round_off,
            total = @total, is_interstate = @is_interstate,
            itc_eligible = @itc_eligible, reverse_charge = @reverse_charge,
            payment_mode = @payment_mode, payment_status = @payment_status,
            amount_paid = @amount_paid, notes = @notes,
            stock_applied = @stock_applied,
            -- An edit that doesn't send one keeps the bill's original file.
            scan_id = COALESCE(@scan_id, scan_id),
            updated_at = GETUTCDATE()
          WHERE id = @id AND business_id = @business_id`);

      for (const li of totals.lines) {
        await transaction.request()
          .input('vendor_bill_id', sql.UniqueIdentifier, req.params.id)
          .input('item_id', sql.UniqueIdentifier, li.item_id)
          .input('variant_id', sql.UniqueIdentifier, li.variant_id)
          .input('raw_material_id', sql.UniqueIdentifier, li.raw_material_id)
          .input('item_name', sql.NVarChar(200), li.item_name)
          .input('quantity', sql.Decimal(10, 2), li.quantity)
          .input('free_quantity', sql.Decimal(10, 2), li.free_quantity)
          .input('unit', sql.NVarChar(20), li.unit)
          .input('unit_price', sql.Decimal(12, 4), li.unit_price)
          .input('tax_rate', sql.Decimal(5, 2), li.tax_rate)
          .input('hsn_code', sql.NVarChar(10), li.hsn_code)
          .input('line_total', sql.Decimal(12, 2), li.line_total)
          .input('sort_order', sql.Int, li.sort_order)
          .query(`
            INSERT INTO vendor_bill_items (
              vendor_bill_id, item_id, variant_id, raw_material_id, item_name,
              quantity, free_quantity, unit, unit_price, tax_rate, hsn_code,
              line_total, sort_order)
            VALUES (
              @vendor_bill_id, @item_id, @variant_id, @raw_material_id, @item_name,
              @quantity, @free_quantity, @unit, @unit_price, @tax_rate, @hsn_code,
              @line_total, @sort_order)`);
      }

      if (flags.inventoryEnabled) {
        for (const li of totals.lines) {
          await applyLineStock(transaction, req.user.business_id, li, +1);
        }
      }

      await saveVendorAliases(transaction, req.user.business_id, head, req.body.lines);

      await transaction.commit();

      const after = await fetchVendorBill(req.params.id, req.user.business_id);
      audit.logVendorBillUpdated(
        req.user,
        before,
        { ...after, business_id: req.user.business_id },
      ).catch((err) => logger.error({ err }, 'audit vendor_bill_updated failed'));

      return res.json(after);
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    if (isDuplicateKey(err)) {
      return res.status(409).json({
        error: 'This invoice number is already recorded for this vendor',
      });
    }
    logger.error({ err }, 'Update vendor bill error');
    return res.status(500).json({ error: 'Failed to update vendor bill' });
  }
});

// ---------------------------------------------------------------------------
// DELETE /api/vendor-bills/:id
// ---------------------------------------------------------------------------
router.delete('/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const before = await fetchVendorBill(req.params.id, req.user.business_id);
    if (!before) return res.status(404).json({ error: 'Vendor bill not found' });

    const transaction = pool.transaction();
    await transaction.begin();
    try {
      const flags = await readBusinessFlags(transaction, req.user.business_id);

      // Reversal can drive stock negative when the goods were already sold.
      // That is allowed on purpose — a purchase entered in error must stay
      // correctable — but it is worth a log line when it happens.
      if (before.stock_applied && flags.inventoryEnabled) {
        for (const li of before.lines) {
          await applyLineStock(transaction, req.user.business_id, li, -1);
        }
      }

      const del = await transaction.request()
        .input('id', sql.UniqueIdentifier, req.params.id)
        .input('business_id', sql.UniqueIdentifier, req.user.business_id)
        .query(`DELETE FROM vendor_bills
                WHERE id = @id AND business_id = @business_id`);

      if (del.rowsAffected[0] === 0) {
        await transaction.rollback();
        return res.status(404).json({ error: 'Vendor bill not found' });
      }

      await transaction.commit();

      // The original invoice file goes with the bill (its scan row stays as
      // the usage record). After commit: a failed delete must keep its file.
      if (before.scan_id) {
        removeScanFile(req.user.business_id, before.scan_id)
          .catch((err) => logger.error({ err }, 'remove vendor bill attachment failed'));
      }

      audit.logVendorBillDeleted(
        req.user,
        { ...before, business_id: req.user.business_id },
      ).catch((err) => logger.error({ err }, 'audit vendor_bill_deleted failed'));

      return res.json({ ok: true });
    } catch (err) {
      await transaction.rollback();
      throw err;
    }
  } catch (err) {
    logger.error({ err }, 'Delete vendor bill error');
    return res.status(500).json({ error: 'Failed to delete vendor bill' });
  }
});

module.exports = router;
