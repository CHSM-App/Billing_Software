// =============================================================================
// /api/warranty-field-templates — per-category custom warranty fields.
//
// "Retail & Warranty" shops sell very different kinds of product under one
// roof (a tyre needs "KM reading"/"vehicle number"; an electronics item needs
// "serial number"/"IMEI"). Rather than hard-code a fixed set of fields, each
// business defines its own list once per item category (items.category, the
// existing free-text grouping) — see migration 063.
//
// Templates are read whenever the Warranty screen knows a record's category,
// to render the right inputs. Editing a template never rewrites past
// records — their filled values already live on warranties.extra_data.
// =============================================================================

const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');
const { validateText } = require('../validate');

const router = express.Router();

const VALID_FIELD_TYPES = ['text', 'number', 'date'];
// Becomes a lookup key inside warranties.extra_data — kept to a safe,
// predictable charset rather than whatever the owner types as a label.
const KEY_RE = /^[a-z0-9_]+$/;
const MAX_FIELDS = 20;

function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can manage warranty field templates' });
  }
  next();
}

router.use(requireAuth, ownerOnly);

/// Validates the `fields` array of a template. Returns an error string, or
/// null when every entry is well-formed.
function validateFields(fields) {
  if (!Array.isArray(fields)) return 'fields must be an array';
  if (fields.length > MAX_FIELDS) return `At most ${MAX_FIELDS} fields are allowed`;
  const seenKeys = new Set();
  for (const f of fields) {
    if (!f || typeof f !== 'object') return 'each field must be an object';
    const { key, label, type } = f;
    if (typeof key !== 'string' || !KEY_RE.test(key)) {
      return 'each field key must be lowercase letters, numbers or underscores';
    }
    if (seenKeys.has(key)) return `field key "${key}" is used more than once`;
    seenKeys.add(key);
    const labelInvalid = validateText(label, 'Field label', 100, { required: true });
    if (labelInvalid) return labelInvalid;
    if (!VALID_FIELD_TYPES.includes(type)) {
      return `field type must be one of: ${VALID_FIELD_TYPES.join(', ')}`;
    }
  }
  return null;
}

// GET /api/warranty-field-templates — every template for this business.
router.get('/', async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .query(`
        SELECT category, fields
        FROM warranty_field_templates
        WHERE business_id = @business_id
        ORDER BY category ASC
      `);
    return res.json(result.recordset.map((r) => ({
      category: r.category,
      fields: JSON.parse(r.fields),
    })));
  } catch (err) {
    logger.error({ err }, 'List warranty field templates error');
    return res.status(500).json({ error: 'Failed to fetch warranty field templates' });
  }
});

// PUT /api/warranty-field-templates/:category — upsert (replace-whole).
// Body: { fields: [{ key, label, type }] }
router.put('/:category', async (req, res) => {
  const category = String(req.params.category || '').trim();
  if (!category) return res.status(400).json({ error: 'category is required' });

  const invalid = validateFields(req.body.fields);
  if (invalid) return res.status(400).json({ error: invalid });

  try {
    await poolConnect;
    await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('category', sql.NVarChar(100), category)
      .input('fields', sql.NVarChar(sql.MAX), JSON.stringify(req.body.fields))
      .query(`
        MERGE warranty_field_templates AS target
        USING (SELECT @business_id AS business_id, @category AS category) AS src
          ON target.business_id = src.business_id AND target.category = src.category
        WHEN MATCHED THEN
          UPDATE SET fields = @fields, updated_at = GETUTCDATE()
        WHEN NOT MATCHED THEN
          INSERT (business_id, category, fields)
          VALUES (@business_id, @category, @fields);
      `);
    return res.json({ category, fields: req.body.fields });
  } catch (err) {
    logger.error({ err }, 'Upsert warranty field template error');
    return res.status(500).json({ error: 'Failed to save warranty field template' });
  }
});

// DELETE /api/warranty-field-templates/:category
router.delete('/:category', async (req, res) => {
  try {
    await poolConnect;
    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('category', sql.NVarChar(100), String(req.params.category || '').trim())
      .query(`
        DELETE FROM warranty_field_templates
        WHERE business_id = @business_id AND category = @category
      `);
    if (result.rowsAffected[0] === 0) {
      return res.status(404).json({ error: 'Template not found' });
    }
    return res.json({ success: true });
  } catch (err) {
    logger.error({ err }, 'Delete warranty field template error');
    return res.status(500).json({ error: 'Failed to delete warranty field template' });
  }
});

module.exports = router;
