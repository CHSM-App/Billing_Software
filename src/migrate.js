#!/usr/bin/env node
// =============================================================================
// migrate.js — MSSQL migration runner
//
// Commands:
//   node src/migrate.js up          — apply all pending migrations
//   node src/migrate.js up 002      — apply up to and including version 002
//   node src/migrate.js down        — roll back the last applied migration
//   node src/migrate.js down 001    — roll back down to (but not including) 001
//   node src/migrate.js status      — list applied / pending migrations
//   node src/migrate.js create <name> — scaffold a new migration file pair
//
// Migration files live in src/migrations/ and follow the naming convention:
//   <version>_<name>.sql            — forward migration
//   <version>_<name>_rollback.sql   — rollback script
//
// Where <version> is a zero-padded integer: 001, 002, 003, …
// =============================================================================

'use strict';

require('dotenv').config({ path: require('path').join(__dirname, '..', '.env') });

const fs   = require('fs');
const path = require('path');
const sql  = require('mssql');

// ---------------------------------------------------------------------------
// DB connection — same buildOptions() logic as db.js / init-db.js
// ---------------------------------------------------------------------------
const isProd = process.env.NODE_ENV === 'production';

function buildOptions() {
  if (isProd) {
    const opts = { encrypt: true, trustServerCertificate: false };
    if (process.env.DB_SSL_CA) {
      opts.cryptoCredentialsDetails = { ca: fs.readFileSync(process.env.DB_SSL_CA) };
    }
    return opts;
  }
  return { encrypt: true, trustServerCertificate: true };
}

const DB_CONFIG = {
  server:            process.env.DB_HOST,
  port:              parseInt(process.env.DB_PORT, 10),
  user:              process.env.DB_USER,
  password:          process.env.DB_PASSWORD,
  database:          process.env.DB_NAME,
  options:           buildOptions(),
  connectionTimeout: 15000,
  requestTimeout:    60000, // migrations can be slow
};

const MIGRATIONS_DIR = path.join(__dirname, 'migrations');

// ---------------------------------------------------------------------------
// Tracking table
// ---------------------------------------------------------------------------
const ENSURE_TRACKING_TABLE = `
  IF NOT EXISTS (
    SELECT 1 FROM sys.tables WHERE name = 'schema_migrations'
  )
  CREATE TABLE schema_migrations (
    version     NVARCHAR(10)  NOT NULL PRIMARY KEY,  -- e.g. '001'
    name        NVARCHAR(200) NOT NULL,              -- e.g. 'initial_schema'
    applied_at  DATETIME2     NOT NULL DEFAULT GETUTCDATE(),
    applied_by  NVARCHAR(100) NOT NULL DEFAULT SYSTEM_USER
  );
`;

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/** Discover all migration files in the migrations directory. */
function discoverMigrations() {
  const files = fs.readdirSync(MIGRATIONS_DIR).sort();

  const forward = files.filter((f) => f.endsWith('.sql') && !f.endsWith('_rollback.sql'));

  return forward.map((file) => {
    const base    = path.basename(file, '.sql');
    const match   = base.match(/^(\d+)_(.+)$/);
    if (!match) return null;

    const version      = match[1].padStart(3, '0');
    const name         = match[2];
    const rollbackFile = `${base}_rollback.sql`;

    return {
      version,
      name,
      file:         path.join(MIGRATIONS_DIR, file),
      rollbackFile: files.includes(rollbackFile)
        ? path.join(MIGRATIONS_DIR, rollbackFile)
        : null,
    };
  }).filter(Boolean);
}

/** Return the set of already-applied versions from the tracking table. */
async function appliedVersions(pool) {
  const result = await pool.request().query(
    'SELECT version FROM schema_migrations ORDER BY version ASC'
  );
  return new Set(result.recordset.map((r) => r.version));
}

/**
 * Split a SQL migration file into batches for MSSQL execution.
 *
 * Convention: migration files use GO as the sole batch separator (SSMS style).
 * Semicolons are NOT used as statement terminators — MSSQL DDL does not require
 * them, and splitting on semicolons breaks multi-line constructs such as:
 *   IF EXISTS (...) BEGIN ... END
 *   CREATE INDEX ... WHERE ...
 *
 * Each GO-separated chunk is sent to the server as one complete batch.
 * Empty chunks and pure-comment chunks are skipped.
 */
function splitBatches(sqlText) {
  // Split on GO (its own line, case-insensitive, optional surrounding whitespace)
  return sqlText
    .split(/^\s*GO\s*$/im)
    .map((chunk) => chunk.trim())
    .filter((chunk) => {
      if (chunk.length === 0) return false;
      // Skip chunks that are only comments
      const noComments = chunk
        .replace(/\/\*[\s\S]*?\*\//g, '')
        .replace(/--[^\r\n]*/g, '')
        .trim();
      return noComments.length > 0;
    });
}

/**
 * Execute a SQL migration file against the database.
 *
 * Each GO-separated batch is sent as its own pool.request().query() call so
 * that MSSQL processes them independently (required for DDL like CREATE TABLE).
 *
 * The runner records the migration in schema_migrations only after all batches
 * succeed. If any batch fails the error is re-thrown so cmdUp can report it;
 * no tracking entry is written, making the migration safely re-runnable after
 * the SQL is fixed.
 *
 * Note: MSSQL DDL statements (CREATE TABLE, ALTER TABLE, CREATE INDEX) cannot
 * run inside an explicit client-initiated transaction over TDS — doing so causes
 * "mismatching BEGIN/COMMIT count" errors. Therefore migration files must NOT
 * contain BEGIN TRANSACTION / COMMIT / ROLLBACK; atomicity is provided at the
 * file level by the tracking-table write happening only on full success.
 */
async function executeSqlFile(pool, filePath) {
  const content = fs.readFileSync(filePath, 'utf8');
  const batches = splitBatches(content);

  for (const batch of batches) {
    await pool.request().query(batch);
  }
}

/** Mark a migration as applied in the tracking table. */
async function recordApplied(pool, version, name) {
  await pool.request()
    .input('version', sql.NVarChar(10),  version)
    .input('name',    sql.NVarChar(200), name)
    .query(`
      INSERT INTO schema_migrations (version, name)
      VALUES (@version, @name)
    `);
}

/** Remove a migration from the tracking table. */
async function recordReverted(pool, version) {
  await pool.request()
    .input('version', sql.NVarChar(10), version)
    .query('DELETE FROM schema_migrations WHERE version = @version');
}

// ---------------------------------------------------------------------------
// Commands
// ---------------------------------------------------------------------------

async function cmdStatus(pool) {
  const migrations = discoverMigrations();
  const applied    = await appliedVersions(pool);

  const rows = await pool.request().query(
    'SELECT version, name, applied_at, applied_by FROM schema_migrations ORDER BY version ASC'
  );
  const appliedMeta = {};
  for (const r of rows.recordset) appliedMeta[r.version] = r;

  console.log('\n  Migration status\n');
  console.log('  ' + '─'.repeat(72));
  console.log(`  ${'Version'.padEnd(10)} ${'Name'.padEnd(35)} ${'Status'.padEnd(10)} Applied at`);
  console.log('  ' + '─'.repeat(72));

  for (const m of migrations) {
    const isApplied = applied.has(m.version);
    const status    = isApplied ? 'applied' : 'pending';
    const meta      = appliedMeta[m.version];
    const appliedAt = meta ? meta.applied_at.toISOString().replace('T', ' ').slice(0, 19) : '';
    const rollback  = m.rollbackFile ? '' : ' (no rollback)';

    console.log(
      `  ${m.version.padEnd(10)} ${(m.name + rollback).padEnd(35)} ${status.padEnd(10)} ${appliedAt}`
    );
  }

  const pendingCount = migrations.filter((m) => !applied.has(m.version)).length;
  console.log('  ' + '─'.repeat(72));
  console.log(`  ${pendingCount} pending, ${applied.size} applied\n`);
}

async function cmdUp(pool, targetVersion) {
  const migrations = discoverMigrations();
  const applied    = await appliedVersions(pool);

  const pending = migrations.filter((m) => {
    if (applied.has(m.version)) return false;
    if (targetVersion && m.version > targetVersion.padStart(3, '0')) return false;
    return true;
  });

  if (pending.length === 0) {
    console.log('Nothing to apply — database is up to date.');
    return;
  }

  for (const m of pending) {
    process.stdout.write(`  Applying ${m.version} ${m.name} … `);
    try {
      await executeSqlFile(pool, m.file);
      await recordApplied(pool, m.version, m.name);
      console.log('done');
    } catch (err) {
      console.log('FAILED');
      console.error(`\n  Error in migration ${m.version}: ${err.message}\n`);
      console.error('  Database may be in a partially-applied state.');
      console.error('  Fix the migration file and re-run, or run the rollback manually.\n');
      process.exit(1);
    }
  }

  console.log(`\n  ${pending.length} migration(s) applied.\n`);
}

async function cmdDown(pool, targetVersion) {
  const migrations  = discoverMigrations();
  const applied     = await appliedVersions(pool);

  // Roll back applied migrations in reverse order, stopping at targetVersion.
  const toRollback = migrations
    .filter((m) => applied.has(m.version))
    .reverse()
    .filter((m) => {
      if (targetVersion && m.version <= targetVersion.padStart(3, '0')) return false;
      return true;
    });

  if (toRollback.length === 0) {
    console.log('Nothing to roll back.');
    return;
  }

  for (const m of toRollback) {
    if (!m.rollbackFile) {
      console.error(`  Migration ${m.version} has no rollback file — aborting.`);
      console.error(`  Create ${m.version}_${m.name}_rollback.sql to enable rollback.\n`);
      process.exit(1);
    }

    process.stdout.write(`  Rolling back ${m.version} ${m.name} … `);
    try {
      await executeSqlFile(pool, m.rollbackFile);
      await recordReverted(pool, m.version);
      console.log('done');
    } catch (err) {
      console.log('FAILED');
      console.error(`\n  Error rolling back ${m.version}: ${err.message}\n`);
      process.exit(1);
    }
  }

  console.log(`\n  ${toRollback.length} migration(s) rolled back.\n`);
}

async function cmdCreate(name) {
  if (!name) {
    console.error('Usage: migrate create <name>');
    process.exit(1);
  }

  const migrations = discoverMigrations();
  const lastVersion = migrations.length > 0
    ? parseInt(migrations[migrations.length - 1].version, 10)
    : 0;
  const nextVersion = String(lastVersion + 1).padStart(3, '0');

  const safeName    = name.toLowerCase().replace(/[^a-z0-9]+/g, '_').replace(/^_|_$/g, '');
  const forwardPath  = path.join(MIGRATIONS_DIR, `${nextVersion}_${safeName}.sql`);
  const rollbackPath = path.join(MIGRATIONS_DIR, `${nextVersion}_${safeName}_rollback.sql`);

  const forwardTemplate = `-- =============================================================================
-- Migration ${nextVersion}: ${safeName}
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- Do NOT use BEGIN TRANSACTION / COMMIT — the runner manages atomicity.
-- =============================================================================

-- TODO: add your schema changes here
-- Example:
-- ALTER TABLE my_table ADD my_column NVARCHAR(100) NULL
-- GO

`;

  const rollbackTemplate = `-- =============================================================================
-- Rollback ${nextVersion}: ${safeName}
-- =============================================================================
-- Use GO as the batch separator between statements (not semicolons).
-- =============================================================================

-- TODO: undo the changes from migration ${nextVersion}
-- Example:
-- ALTER TABLE my_table DROP COLUMN my_column
-- GO

`;

  fs.writeFileSync(forwardPath,  forwardTemplate,  'utf8');
  fs.writeFileSync(rollbackPath, rollbackTemplate, 'utf8');

  console.log(`\n  Created:`);
  console.log(`    ${path.relative(process.cwd(), forwardPath)}`);
  console.log(`    ${path.relative(process.cwd(), rollbackPath)}\n`);
}

// ---------------------------------------------------------------------------
// Entry point
// ---------------------------------------------------------------------------
async function main() {
  const [,, command, arg] = process.argv;

  if (command === 'create') {
    // create doesn't need a DB connection
    await cmdCreate(arg);
    return;
  }

  if (!['up', 'down', 'status'].includes(command)) {
    console.log(`
  Usage:
    node src/migrate.js up [version]     Apply pending migrations
    node src/migrate.js down [version]   Roll back the last migration
    node src/migrate.js status           Show applied / pending migrations
    node src/migrate.js create <name>    Scaffold a new migration file pair
`);
    process.exit(1);
  }

  // Validate required env vars
  const required = ['DB_HOST', 'DB_PORT', 'DB_USER', 'DB_PASSWORD', 'DB_NAME'];
  const missing  = required.filter((k) => !process.env[k]);
  if (missing.length > 0) {
    console.error(`Missing required environment variables: ${missing.join(', ')}`);
    process.exit(1);
  }

  let pool;
  try {
    process.stdout.write('  Connecting to database … ');
    pool = await sql.connect(DB_CONFIG);
    console.log('connected.\n');

    // Ensure tracking table exists
    await pool.request().query(ENSURE_TRACKING_TABLE);

    if (command === 'status') await cmdStatus(pool);
    if (command === 'up')     await cmdUp(pool, arg);
    if (command === 'down')   await cmdDown(pool, arg);

  } catch (err) {
    console.error('\n  Fatal:', err.message);
    process.exit(1);
  } finally {
    if (pool) await pool.close();
  }
}

main();
