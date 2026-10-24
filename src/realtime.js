'use strict';
// Basic WebSocket layer for real-time cross-device updates.
//
// One WS server attached to the existing HTTP server. Each socket authenticates
// with the same JWT access token (passed as ?token=... on the connect URL) and
// is grouped by business_id. Any route can call broadcast(businessId, event) to
// push a tiny JSON message to every device of that business, e.g.:
//   { type: 'kitchen' }  -> clients refresh the kitchen queue
//   { type: 'tables' }   -> clients refresh the tables screen
//   { type: 'drafts' }   -> clients refresh the open-orders list
//
// This replaces FCM for in-app real-time; it needs no external service and works
// on the LAN. FCM is no longer used to drive refreshes.

const { WebSocketServer } = require('ws');
const { verifyAccessToken } = require('./auth');
const logger = require('./logger');

// business_id -> Set<WebSocket>
const clients = new Map();

let wss = null;

function attach(server) {
  // noServer: we handle the upgrade ourselves so we can authenticate first.
  wss = new WebSocketServer({ noServer: true });

  server.on('upgrade', (req, socket, head) => {
    // Only handle our path; leave anything else alone.
    let url;
    try {
      url = new URL(req.url, 'http://localhost');
    } catch (_) {
      socket.destroy();
      return;
    }
    if (url.pathname !== '/ws') {
      socket.destroy();
      return;
    }

    const token = url.searchParams.get('token');
    let user;
    try {
      user = verifyAccessToken(token || '');
    } catch (_) {
      // 401 then close — client will retry with a fresh token.
      socket.write('HTTP/1.1 401 Unauthorized\r\n\r\n');
      socket.destroy();
      return;
    }

    wss.handleUpgrade(req, socket, head, (ws) => {
      ws.businessId = user.business_id;
      register(ws);
      wss.emit('connection', ws, req);
    });
  });

  // Heartbeat: drop dead sockets so the client set doesn't leak.
  wss.on('connection', (ws) => {
    ws.isAlive = true;
    ws.on('pong', () => { ws.isAlive = true; });
    ws.on('close', () => unregister(ws));
    ws.on('error', () => unregister(ws));
  });

  const interval = setInterval(() => {
    if (!wss) return;
    for (const ws of wss.clients) {
      if (ws.isAlive === false) { ws.terminate(); continue; }
      ws.isAlive = false;
      try { ws.ping(); } catch (_) {}
    }
  }, 30000);
  interval.unref?.();

  logger.info('websocket server attached at /ws');
}

function register(ws) {
  const set = clients.get(ws.businessId) || new Set();
  set.add(ws);
  clients.set(ws.businessId, set);
}

function unregister(ws) {
  const set = clients.get(ws.businessId);
  if (!set) return;
  set.delete(ws);
  if (set.size === 0) clients.delete(ws.businessId);
}

/**
 * Broadcast a small JSON event to every connected device of a business.
 * Safe to call even if no one is connected or WS is not attached (no-op).
 *
 * @param {string} businessId
 * @param {object} event  e.g. { type: 'kitchen' }
 */
function broadcast(businessId, event) {
  const set = clients.get(businessId);
  if (!set || set.size === 0) return;
  const payload = JSON.stringify(event);
  for (const ws of set) {
    // 1 === WebSocket.OPEN
    if (ws.readyState === 1) {
      try { ws.send(payload); } catch (_) {}
    }
  }
}

module.exports = { attach, broadcast };
