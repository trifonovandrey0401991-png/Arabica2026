/**
 * WebSocket module for live counter/badge updates
 *
 * Lightweight channel: server pushes counter updates to connected clients
 * when data changes (new report, new order, etc.).
 * Client never needs to poll — counters refresh instantly.
 *
 * Pattern: same as employee_chat_websocket.js / messenger_websocket.js
 */

const WebSocket = require('ws');
const { maskPhone } = require('../utils/file_helpers');

let sessionMiddleware;
try {
  sessionMiddleware = require('../utils/session_middleware');
} catch (e) {
  sessionMiddleware = null;
}

// Connections: Map<phone, Set<WebSocket>>
const connections = new Map();

// Role cache: Map<phone, { role: string, shopAddresses: string[] }>
// So we know who should receive which counter updates
const roleCache = new Map();

const CLEANUP_INTERVAL = 30000;
const CONNECTION_TIMEOUT = 60000;
const MAX_CONNECTIONS_PER_PHONE = 3;

/**
 * Initialize counters WebSocket server
 */
function setupCountersWebSocket(server) {
  const wss = new WebSocket.Server({ noServer: true });

  console.log('✅ Counters WebSocket initialized (noServer mode, path: /ws/counters)');

  wss.on('connection', (ws, req) => {
    let userPhone = null;
    let pingInterval = null;
    let lastPong = Date.now();

    const url = new URL(req.url, `http://${req.headers.host}`);
    userPhone = url.searchParams.get('phone');
    const authToken = url.searchParams.get('token');
    const role = url.searchParams.get('role') || 'employee';

    if (!userPhone) {
      ws.close(4001, 'Phone required');
      return;
    }

    if (!authToken) {
      ws.close(4002, 'Auth token required');
      return;
    }

    if (!sessionMiddleware) {
      ws.close(4003, 'Auth service unavailable');
      return;
    }

    const tokenUser = sessionMiddleware.verifyToken(authToken);
    if (!tokenUser) {
      ws.close(4003, 'Invalid session token');
      return;
    }

    userPhone = tokenUser.phone || userPhone;
    const normalizedPhone = userPhone.replace(/[^\d]/g, '');

    // Register connection
    if (!connections.has(normalizedPhone)) {
      connections.set(normalizedPhone, new Set());
    }
    const phoneSockets = connections.get(normalizedPhone);

    // Limit connections per phone — close oldest
    if (phoneSockets.size >= MAX_CONNECTIONS_PER_PHONE) {
      const oldest = phoneSockets.values().next().value;
      oldest.close(4004, 'Too many connections');
      phoneSockets.delete(oldest);
    }

    phoneSockets.add(ws);

    // Cache role for targeted updates
    roleCache.set(normalizedPhone, { role });

    // Confirmation
    sendToSocket(ws, {
      type: 'connected',
      phone: normalizedPhone,
      timestamp: new Date().toISOString()
    });

    console.log(`📊 Counters WS: ${maskPhone(normalizedPhone)} connected (role: ${role}, total: ${getConnectionsCount()})`);

    // Ping keepalive
    pingInterval = setInterval(() => {
      if (Date.now() - lastPong > CONNECTION_TIMEOUT) {
        ws.terminate();
        return;
      }
      if (ws.readyState === WebSocket.OPEN) {
        ws.ping();
      }
    }, 30000);

    ws.on('pong', () => {
      lastPong = Date.now();
    });

    ws.on('message', (data) => {
      try {
        const message = JSON.parse(data.toString());
        if (message.type === 'ping') {
          sendToSocket(ws, { type: 'pong', timestamp: new Date().toISOString() });
        }
      } catch (e) {
        // ignore parse errors
      }
    });

    ws.on('close', () => {
      clearInterval(pingInterval);

      if (connections.has(normalizedPhone)) {
        connections.get(normalizedPhone).delete(ws);
        if (connections.get(normalizedPhone).size === 0) {
          connections.delete(normalizedPhone);
          roleCache.delete(normalizedPhone);
        }
      }
    });

    ws.on('error', (error) => {
      console.error(`[Counters WS] error for ${maskPhone(normalizedPhone)}:`, error.message);
    });
  });

  // Periodic cleanup
  setInterval(() => cleanupStaleConnections(), CLEANUP_INTERVAL);

  return wss;
}

function sendToSocket(ws, data) {
  if (ws.readyState === WebSocket.OPEN) {
    try {
      ws.send(JSON.stringify(data));
    } catch (e) {
      // ignore send errors
    }
  }
}

function cleanupStaleConnections() {
  for (const [phone, sockets] of connections.entries()) {
    for (const socket of sockets) {
      if (socket.readyState !== WebSocket.OPEN) {
        sockets.delete(socket);
      }
    }
    if (sockets.size === 0) {
      connections.delete(phone);
      roleCache.delete(phone);
    }
  }
}

// ===== PUBLIC FUNCTIONS FOR REST API INTEGRATION =====

/**
 * Notify all connected admin/manager clients about a counter change.
 * Called from REST APIs when data changes (new report, new order, etc.)
 *
 * @param {string} counter - Counter name (e.g. 'pendingShiftReports', 'pendingOrders')
 * @param {object} [options] - Optional targeting
 * @param {number} [options.delta] - Change amount (+1 or -1)
 * @param {string} [options.role] - Target role ('admin', 'manager', 'employee', or null for all)
 * @param {string} [options.excludePhone] - Don't notify this phone (e.g. the person who made the change)
 */
function notifyCounterUpdate(counter, options = {}) {
  const { delta, role: targetRole, excludePhone } = options;

  const notification = {
    type: 'counter_update',
    counter,
    delta: delta || null,
    timestamp: new Date().toISOString()
  };

  let sent = 0;
  for (const [phone, sockets] of connections.entries()) {
    if (excludePhone && phone === excludePhone.replace(/[^\d]/g, '')) continue;

    // If targetRole specified, only send to matching role
    if (targetRole) {
      const cached = roleCache.get(phone);
      if (cached && cached.role !== targetRole && cached.role !== 'developer') continue;
    }

    for (const socket of sockets) {
      sendToSocket(socket, notification);
      sent++;
    }
  }

  if (sent > 0) {
    console.log(`📊 Counters WS: ${counter} (delta: ${delta || '?'}) → ${sent} clients`);
  }
}

/**
 * Notify a specific employee about their counter change.
 * E.g. when a task is assigned to them.
 *
 * @param {string} phone - Employee phone
 * @param {string} counter - Counter name
 * @param {number} [delta] - Change amount
 */
function notifyEmployeeCounter(phone, counter, delta) {
  const normalizedPhone = phone.replace(/[^\d]/g, '');
  const sockets = connections.get(normalizedPhone);
  if (!sockets || sockets.size === 0) return;

  const notification = {
    type: 'counter_update',
    counter,
    delta: delta || null,
    timestamp: new Date().toISOString()
  };

  for (const socket of sockets) {
    sendToSocket(socket, notification);
  }
}

/**
 * Broadcast to all connected clients (regardless of role).
 * Use sparingly — for rare events like bulk data changes.
 */
function notifyAllCounters(counter, delta) {
  const notification = {
    type: 'counter_update',
    counter,
    delta: delta || null,
    timestamp: new Date().toISOString()
  };

  for (const sockets of connections.values()) {
    for (const socket of sockets) {
      sendToSocket(socket, notification);
    }
  }
}

function getConnectionsCount() {
  let count = 0;
  for (const sockets of connections.values()) {
    count += sockets.size;
  }
  return count;
}

module.exports = {
  setupCountersWebSocket,
  notifyCounterUpdate,
  notifyEmployeeCounter,
  notifyAllCounters,
  getConnectionsCount
};
