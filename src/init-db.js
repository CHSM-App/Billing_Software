// init-db.js — applies all pending migrations against the target database.
// Kept for backwards compatibility; equivalent to: node src/migrate.js up
//
// Usage:
//   node src/init-db.js          # apply all pending migrations (CI / first run)
//   node src/migrate.js status   # check what is / isn't applied
//   node src/migrate.js down     # roll back last migration

process.argv[1] = require.resolve('./migrate');
process.argv[2] = 'up';
require('./migrate');
