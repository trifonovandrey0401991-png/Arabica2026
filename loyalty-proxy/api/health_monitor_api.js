/**
 * Health Monitor API — full server diagnostics (dev-only)
 *
 * GET /api/dev/health?key=DEV_HEALTH_KEY
 *
 * Returns: server status, DB, disk, memory, pm2 processes, recent errors, WS connections
 * Protected by DEV_HEALTH_KEY env variable.
 */

const { exec } = require('child_process');
const { getMoscowTime } = require('../utils/moscow_time');
const db = require('../utils/db');

const DEV_HEALTH_KEY = process.env.DEV_HEALTH_KEY || 'arabica-dev-2026';

function execAsync(cmd, timeoutMs = 5000) {
  return new Promise((resolve) => {
    exec(cmd, { timeout: timeoutMs }, (err, stdout, stderr) => {
      if (err) resolve({ ok: false, error: err.message });
      else resolve({ ok: true, stdout: stdout.trim(), stderr: stderr.trim() });
    });
  });
}

function setupHealthMonitorAPI(app) {
  app.get('/api/dev/health', async (req, res) => {
    if (req.query.key !== DEV_HEALTH_KEY) {
      return res.status(403).json({ error: 'Invalid key' });
    }

    const startTime = Date.now();
    const results = {};

    // 1. Server basics
    const uptime = process.uptime();
    const mem = process.memoryUsage();
    results.server = {
      status: 'ok',
      uptime_hours: Math.round(uptime / 3600 * 10) / 10,
      uptime_human: formatUptime(uptime),
      memory_mb: {
        rss: Math.round(mem.rss / 1024 / 1024),
        heap_used: Math.round(mem.heapUsed / 1024 / 1024),
        heap_total: Math.round(mem.heapTotal / 1024 / 1024),
      },
      moscow_time: getMoscowTime().toISOString().replace('T', ' ').slice(0, 19),
      node_version: process.version,
    };

    // 2-5: Run checks in parallel
    const [dbResult, diskResult, pm2Result, errorsResult] = await Promise.all([
      checkDatabase(),
      checkDisk(),
      checkPm2(),
      checkRecentErrors(),
    ]);

    results.database = dbResult;
    results.disk = diskResult;
    results.pm2 = pm2Result;
    results.recent_errors = errorsResult;

    // 6. Overall status
    const allOk = results.database.status === 'ok' && results.pm2.status === 'ok';
    results.check_ms = Date.now() - startTime;

    res.json({
      overall: allOk ? 'OK' : 'PROBLEMS DETECTED',
      ...results,
    });
  });
}

async function checkDatabase() {
  try {
    const start = Date.now();
    const result = await db.query('SELECT 1 AS ping');
    const ms = Date.now() - start;

    // Get table count and DB size
    const [tables, size] = await Promise.all([
      db.query("SELECT count(*) FROM information_schema.tables WHERE table_schema = 'public'"),
      db.query("SELECT pg_size_pretty(pg_database_size(current_database())) AS size"),
    ]);

    return {
      status: 'ok',
      ping_ms: ms,
      tables: parseInt(tables.rows[0].count),
      db_size: size.rows[0].size,
    };
  } catch (e) {
    return { status: 'error', error: e.message };
  }
}

async function checkDisk() {
  const result = await execAsync("df -h / | tail -1 | awk '{print $2, $3, $4, $5}'");
  if (!result.ok) return { status: 'error', error: result.error };

  const parts = result.stdout.split(/\s+/);
  return {
    status: 'ok',
    total: parts[0] || '?',
    used: parts[1] || '?',
    available: parts[2] || '?',
    percent: parts[3] || '?',
  };
}

async function checkPm2() {
  const result = await execAsync('pm2 jlist');
  if (!result.ok) return { status: 'error', error: result.error };

  try {
    const processes = JSON.parse(result.stdout);
    const summary = processes.map(p => ({
      name: p.name,
      status: p.pm2_env?.status || 'unknown',
      uptime_hours: p.pm2_env?.pm_uptime
        ? Math.round((Date.now() - p.pm2_env.pm_uptime) / 3600000 * 10) / 10
        : null,
      restarts: p.pm2_env?.restart_time || 0,
      memory_mb: p.monit?.memory ? Math.round(p.monit.memory / 1024 / 1024) : null,
      cpu: p.monit?.cpu != null ? `${p.monit.cpu}%` : null,
    }));

    const allOnline = summary.every(p => p.status === 'online');
    return {
      status: allOnline ? 'ok' : 'warning',
      processes: summary,
    };
  } catch (e) {
    return { status: 'error', error: 'Failed to parse pm2 output' };
  }
}

async function checkRecentErrors() {
  // Read last 30 lines of pm2 error log
  const result = await execAsync(
    "pm2 logs loyalty-proxy --err --nostream --lines 30 2>/dev/null | tail -30"
  );
  if (!result.ok) return { status: 'unknown', error: result.error };

  const lines = result.stdout.split('\n').filter(l => l.trim());
  return {
    count: lines.length,
    last_errors: lines.slice(-10), // show last 10
  };
}

function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}d ${h}h ${m}m`;
  if (h > 0) return `${h}h ${m}m`;
  return `${m}m`;
}

module.exports = { setupHealthMonitorAPI };
