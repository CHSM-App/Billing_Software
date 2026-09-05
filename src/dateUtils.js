'use strict';

/**
 * dateUtils.js — timezone-safe date helpers for MSSQL parameter binding
 *
 * The database stores all timestamps as DATETIME2 in UTC (GETUTCDATE()).
 * All date-range queries must therefore compare against DATETIME2 values,
 * not against DATE strings, to remain sargable (index-usable) and correct.
 *
 * Key design decisions:
 *
 *   • Never use CAST(created_at AS DATE) on the left side of a WHERE clause —
 *     that is non-sargable: SQL Server cannot use an index on `created_at`
 *     when a function wraps the column.
 *
 *   • Always express a "day" range as:
 *       created_at >= startOfDayUtc  AND  created_at < startOfNextDayUtc
 *     This is fully sargable and matches every timestamp in the day regardless
 *     of sub-second precision.
 *
 *   • Client supplies the local date string (YYYY-MM-DD). The server treats
 *     that string as a UTC calendar date boundary.  If the business is in a
 *     timezone other than UTC, the Flutter app should pass the local date, not
 *     rely on the server computing "today" from UTC time.
 */

// ---------------------------------------------------------------------------
// Validation
// ---------------------------------------------------------------------------

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

/**
 * Returns true when `s` is a valid YYYY-MM-DD string representing a real date.
 */
function isValidDateString(s) {
  if (typeof s !== 'string' || !DATE_RE.test(s)) return false;
  const d = new Date(s + 'T00:00:00.000Z');
  return !isNaN(d.getTime());
}

/**
 * Parse and validate a YYYY-MM-DD query param.
 * Returns the string unchanged if valid, throws a user-facing Error if not.
 */
function requireDateParam(value, paramName) {
  if (!value) throw new Error(`${paramName} is required`);
  if (!isValidDateString(value)) {
    throw new Error(`${paramName} must be a valid date in YYYY-MM-DD format`);
  }
  return value;
}

// ---------------------------------------------------------------------------
// UTC day boundary helpers
// ---------------------------------------------------------------------------

/**
 * Given a YYYY-MM-DD string, return a JS Date representing the start of that
 * calendar day in UTC (i.e. YYYY-MM-DDT00:00:00.000Z).
 *
 * Treating the input as UTC ensures consistent behaviour regardless of the
 * Node.js process timezone.
 */
// IST is UTC+5:30 = 330 minutes ahead of UTC.
// The client sends a local (IST) date string. To query the DB correctly
// (which stores UTC timestamps), we convert the IST day boundaries to UTC.
const IST_OFFSET_MS = 5.5 * 60 * 60 * 1000; // 19800000 ms

function utcDayStart(dateStr) {
  // Start of day in IST = YYYY-MM-DDT00:00:00+05:30 = YYYY-MM-DDT(00:00 - 5:30)Z
  const istMidnight = new Date(dateStr + 'T00:00:00.000Z');
  return new Date(istMidnight.getTime() - IST_OFFSET_MS);
}

/**
 * Given a YYYY-MM-DD string, return a JS Date representing the exclusive upper
 * bound for that day in IST — i.e. the start of the NEXT calendar day in IST,
 * converted to UTC.
 */
function utcDayEnd(dateStr) {
  const d = new Date(dateStr + 'T00:00:00.000Z');
  d.setUTCDate(d.getUTCDate() + 1);
  return new Date(d.getTime() - IST_OFFSET_MS);
}

/**
 * Return today's date as a YYYY-MM-DD string in UTC.
 * Callers that need local-date accuracy should pass ?date= from the client.
 */
function todayUtc() {
  // Return today's date in IST (client timezone) as YYYY-MM-DD
  const now = new Date(Date.now() + IST_OFFSET_MS);
  return now.toISOString().slice(0, 10);
}

/**
 * Convenience: return { start, end } as Date objects for a single day.
 * start is inclusive (>=), end is exclusive (<).
 */
function dayRange(dateStr) {
  return { start: utcDayStart(dateStr), end: utcDayEnd(dateStr) };
}

/**
 * Convenience: return { start, end } as Date objects spanning from the
 * beginning of `fromStr` to the end of `toStr` (inclusive of all timestamps
 * on the to-date).
 * start is inclusive (>=), end is exclusive (<).
 */
function dateRange(fromStr, toStr) {
  return { start: utcDayStart(fromStr), end: utcDayEnd(toStr) };
}

module.exports = {
  isValidDateString,
  requireDateParam,
  utcDayStart,
  utcDayEnd,
  todayUtc,
  dayRange,
  dateRange,
};
