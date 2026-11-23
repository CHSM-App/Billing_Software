const express = require('express');
const { pool, poolConnect, sql } = require('../db');
const { requireAuth } = require('../auth');
const logger = require('../logger');

const router = express.Router();

// Only owners may query the audit log
function ownerOnly(req, res, next) {
  if (req.user.role !== 'owner') {
    return res.status(403).json({ error: 'Only owners can view the audit log' });
  }
  next();
}

const VALID_EVENT_TYPES = [
  'bill_created', 'bill_finalized', 'bill_voided',
  'bill_items_added', 'bill_items_updated',
  'item_created', 'item_price_changed', 'item_stock_adjusted', 'item_deleted',
  'staff_added', 'staff_updated', 'staff_deleted',
  'user_login', 'user_login_failed', 'user_locked',
];

const PAGE_SIZE = 50;

/**
 * GET /api/audit
 *
 * Query params (all optional):
 *   event_type   — filter to a single event type
 *   entity_id    — filter to events about a specific entity (bill/item/user id)
 *   user_id      — filter to events performed by a specific actor
 *   from         — ISO date string (inclusive lower bound on created_at)
 *   to           — ISO date string (inclusive upper bound, end of day)
 *   page         — 1-based page number (default 1)
 *
 * Returns:
 *   { data: [...], total: N, page: N, page_size: 50, pages: N }
 */
router.get('/', requireAuth, ownerOnly, async (req, res) => {
  const { event_type, entity_id, user_id, from, to, page } = req.query;

  if (event_type && !VALID_EVENT_TYPES.includes(event_type)) {
    return res.status(400).json({
      error: `Invalid event_type. Must be one of: ${VALID_EVENT_TYPES.join(', ')}`,
    });
  }

  const pageNum = Math.max(1, parseInt(page, 10) || 1);
  const offset  = (pageNum - 1) * PAGE_SIZE;

  try {
    await poolConnect;

    const request = pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('page_size', sql.Int, PAGE_SIZE)
      .input('offset',    sql.Int, offset);

    let where = 'business_id = @business_id';

    if (event_type) {
      request.input('event_type', sql.NVarChar(50), event_type);
      where += ' AND event_type = @event_type';
    }
    if (entity_id) {
      request.input('entity_id', sql.UniqueIdentifier, entity_id);
      where += ' AND entity_id = @entity_id';
    }
    if (user_id) {
      request.input('user_id', sql.UniqueIdentifier, user_id);
      where += ' AND user_id = @user_id';
    }
    if (from) {
      request.input('from', sql.DateTime2, new Date(from));
      where += ' AND created_at >= @from';
    }
    if (to) {
      request.input('to', sql.DateTime2, new Date(to + 'T23:59:59'));
      where += ' AND created_at <= @to';
    }

    // Single query: CTE gives the total count alongside the page of rows.
    const result = await request.query(`
      WITH filtered AS (
        SELECT
          id, user_id, user_name, event_type,
          entity_id, entity_label,
          old_value, new_value, description,
          created_at
        FROM audit_logs
        WHERE ${where}
      )
      SELECT
        (SELECT COUNT(*) FROM filtered) AS total_count,
        id, user_id, user_name, event_type,
        entity_id, entity_label,
        old_value, new_value, description,
        created_at
      FROM filtered
      ORDER BY created_at DESC
      OFFSET @offset ROWS
      FETCH NEXT @page_size ROWS ONLY
    `);

    const total     = result.recordset.length > 0 ? result.recordset[0].total_count : 0;
    const rows      = result.recordset.map(({ total_count, old_value, new_value, ...row }) => ({
      ...row,
      old_value: old_value ? JSON.parse(old_value) : null,
      new_value: new_value ? JSON.parse(new_value) : null,
    }));

    return res.json({
      data:      rows,
      total,
      page:      pageNum,
      page_size: PAGE_SIZE,
      pages:     Math.ceil(total / PAGE_SIZE),
    });
  } catch (err) {
    logger.error({ err }, 'Audit query error');
    return res.status(500).json({ error: 'Failed to fetch audit log' });
  }
});

/**
 * GET /api/audit/entity/:id
 * Convenience shortcut — all events for a specific entity (bill, item, user).
 */
router.get('/entity/:id', requireAuth, ownerOnly, async (req, res) => {
  try {
    await poolConnect;

    const result = await pool.request()
      .input('business_id', sql.UniqueIdentifier, req.user.business_id)
      .input('entity_id',   sql.UniqueIdentifier, req.params.id)
      .query(`
        SELECT
          id, user_id, user_name, event_type,
          entity_id, entity_label,
          old_value, new_value, description,
          created_at
        FROM audit_logs
        WHERE business_id = @business_id AND entity_id = @entity_id
        ORDER BY created_at ASC
      `);

    const rows = result.recordset.map(({ old_value, new_value, ...row }) => ({
      ...row,
      old_value: old_value ? JSON.parse(old_value) : null,
      new_value: new_value ? JSON.parse(new_value) : null,
    }));

    return res.json(rows);
  } catch (err) {
    logger.error({ err }, 'Audit entity query error');
    return res.status(500).json({ error: 'Failed to fetch audit trail for entity' });
  }
});

module.exports = router;
