'use strict';

// =============================================================================
// logger.js — singleton Pino logger
//
// Environments:
//   development — pretty-printed, colourised output to stdout
//   production  — JSON to stdout + daily-rotating JSON file in logs/
//   test        — silent (no output during test runs)
//
// Usage anywhere in the app:
//   const logger = require('./logger');
//   logger.info('server started');
//   logger.error({ err }, 'request failed');
//   logger.warn({ userId }, 'suspicious login attempt');
//
// Child loggers (add context to every line from a module):
//   const log = require('./logger').child({ module: 'bills' });
//   log.info({ billId }, 'bill created');
// =============================================================================

const pino = require('pino');
const path = require('path');
const fs   = require('fs');

const env     = process.env.NODE_ENV || 'development';
const isProd  = env === 'production';
const isTest  = env === 'test';
const logsDir = path.join(__dirname, '..', 'logs');

// Ensure logs/ directory exists in production
if (isProd) {
  fs.mkdirSync(logsDir, { recursive: true });
}

// ---------------------------------------------------------------------------
// Transport configuration
// ---------------------------------------------------------------------------

function buildTransport() {
  if (isTest) {
    // level: 'silent' already suppresses all output; no transport needed.
    return undefined;
  }

  if (!isProd) {
    // Development: human-readable colourised output via pino-pretty
    return pino.transport({
      target: 'pino-pretty',
      options: {
        colorize:        true,
        translateTime:   'SYS:HH:MM:ss.l',
        ignore:          'pid,hostname',
        messageFormat:   '{msg}',
        errorLikeObjectKeys: ['err', 'error'],
      },
    });
  }

  // Production: two destinations in parallel
  //   1. stdout  — plain JSON (for container log aggregators, PM2, systemd)
  //   2. logs/app-YYYY-MM-DD.log — daily-rotating JSON file via pino-roll
  return pino.transport({
    targets: [
      {
        target: 'pino/file',
        level:  'info',
        options: { destination: 1 }, // fd 1 = stdout
      },
      {
        target:  'pino-roll',
        level:   'info',
        options: {
          file:      path.join(logsDir, 'app'),
          frequency: 'daily',
          extension: '.log',
          // Keep 30 days of logs; each file is named app.YYYY-MM-DD.log
          limit: { count: 30 },
          mkdir: true,
          sync:  false,
        },
      },
    ],
  });
}

// ---------------------------------------------------------------------------
// Logger instance
// ---------------------------------------------------------------------------

const transportOrUndefined = buildTransport();

const logger = pino(
  {
    level: isTest ? 'silent' : (isProd ? 'info' : 'debug'),

    // Rename pino's "msg" → "message" in JSON output so log aggregators
    // (Datadog, Elastic, Loki) pick it up without extra configuration.
    messageKey: 'message',

    // Standard error serialiser — captures err.message, err.stack, err.code
    serializers: {
      err:   pino.stdSerializers.err,
      error: pino.stdSerializers.err,
      req:   pino.stdSerializers.req,
      res:   pino.stdSerializers.res,
    },

    // Base fields on every log line
    base: {
      env,
      pid: process.pid,
    },

    // ISO 8601 timestamp
    timestamp: pino.stdTimeFunctions.isoTime,
  },
  ...(transportOrUndefined ? [transportOrUndefined] : []),
);

module.exports = logger;
