/**
 * Load Test Script for Arabica Loyalty Proxy
 * ===========================================================
 * Tests server performance under concurrent load using only
 * standard Node.js modules (no external dependencies).
 *
 * Usage:
 *   node tests/load-test.js
 *   node tests/load-test.js http://arabica26.ru:3000
 *   BASE_URL=http://localhost:3000 SESSION_TOKEN=abc123 node tests/load-test.js
 *
 * Environment variables:
 *   BASE_URL       - Server URL (default: http://localhost:3000)
 *   SESSION_TOKEN  - Bearer token for authenticated requests (optional)
 *   API_KEY        - X-API-Key header value (optional)
 *   TIMEOUT_MS     - Per-request timeout in ms (default: 30000)
 *   VERBOSE        - Set to "true" for per-request logging
 */

'use strict';

const http = require('http');
const https = require('https');
const { URL } = require('url');

// ============================================
// Configuration
// ============================================

const BASE_URL = process.argv[2] || process.env.BASE_URL || 'http://localhost:3000';
const SESSION_TOKEN = process.env.SESSION_TOKEN || '';
const API_KEY = process.env.API_KEY || '';
const TIMEOUT_MS = parseInt(process.env.TIMEOUT_MS, 10) || 30000;
const VERBOSE = process.env.VERBOSE === 'true';

// ============================================
// Utility functions
// ============================================

/**
 * Calculate the p-th percentile from a sorted array of numbers.
 */
function percentile(sortedArr, p) {
  if (sortedArr.length === 0) return 0;
  const index = Math.ceil((p / 100) * sortedArr.length) - 1;
  return sortedArr[Math.max(0, index)];
}

/**
 * Format milliseconds for display.
 */
function fmtMs(ms) {
  if (ms >= 1000) return (ms / 1000).toFixed(2) + 's';
  return ms.toFixed(0) + 'ms';
}

/**
 * Build standard request headers.
 */
function buildHeaders(extra) {
  const headers = {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
  };
  if (SESSION_TOKEN) {
    headers['Authorization'] = `Bearer ${SESSION_TOKEN}`;
  }
  if (API_KEY) {
    headers['X-API-Key'] = API_KEY;
  }
  return Object.assign(headers, extra || {});
}

/**
 * Perform a single HTTP request and return timing/status information.
 */
function makeRequest(method, urlPath, body) {
  return new Promise((resolve) => {
    const startTime = Date.now();
    const fullUrl = `${BASE_URL}${urlPath}`;
    let urlObj;
    try {
      urlObj = new URL(fullUrl);
    } catch (e) {
      resolve({ status: 0, duration: 0, error: `Invalid URL: ${fullUrl}`, size: 0 });
      return;
    }
    const lib = urlObj.protocol === 'https:' ? https : http;
    const bodyStr = body ? JSON.stringify(body) : null;

    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
      path: urlObj.pathname + urlObj.search,
      method: method,
      headers: buildHeaders(bodyStr ? { 'Content-Length': Buffer.byteLength(bodyStr) } : {}),
      timeout: TIMEOUT_MS,
      rejectUnauthorized: false,
    };

    const req = lib.request(options, (res) => {
      let responseSize = 0;
      res.on('data', (chunk) => { responseSize += chunk.length; });
      res.on('end', () => {
        const duration = Date.now() - startTime;
        if (VERBOSE) {
          console.log(`  [${method}] ${urlPath} -> ${res.statusCode} (${fmtMs(duration)})`);
        }
        resolve({
          status: res.statusCode,
          duration: duration,
          error: null,
          size: responseSize,
        });
      });
    });

    req.on('error', (e) => {
      const duration = Date.now() - startTime;
      resolve({ status: 0, duration: duration, error: e.message, size: 0 });
    });

    req.on('timeout', () => {
      req.destroy();
      const duration = Date.now() - startTime;
      resolve({ status: 0, duration: duration, error: 'TIMEOUT', size: 0 });
    });

    if (bodyStr) {
      req.write(bodyStr);
    }
    req.end();
  });
}

/**
 * Run N parallel requests and collect results.
 */
async function runParallel(label, count, method, urlPath, bodyFn) {
  const promises = [];
  for (let i = 0; i < count; i++) {
    const body = bodyFn ? bodyFn(i) : null;
    promises.push(makeRequest(method, urlPath, body));
  }

  const startTime = Date.now();
  const results = await Promise.all(promises);
  const wallTime = Date.now() - startTime;

  // Compute metrics
  const durations = results.map(r => r.duration).sort((a, b) => a - b);
  const errors = results.filter(r => r.error || r.status >= 500);
  const successes = results.filter(r => !r.error && r.status < 500);
  const totalBytes = results.reduce((sum, r) => sum + r.size, 0);

  const statusCounts = {};
  for (const r of results) {
    const key = r.error ? `ERR:${r.error}` : String(r.status);
    statusCounts[key] = (statusCounts[key] || 0) + 1;
  }

  return {
    label,
    method,
    path: urlPath,
    concurrency: count,
    wallTimeMs: wallTime,
    totalRequests: results.length,
    successCount: successes.length,
    errorCount: errors.length,
    statusCounts,
    minMs: durations[0] || 0,
    maxMs: durations[durations.length - 1] || 0,
    avgMs: durations.length > 0 ? durations.reduce((a, b) => a + b, 0) / durations.length : 0,
    p95Ms: percentile(durations, 95),
    throughputRps: wallTime > 0 ? (count / (wallTime / 1000)).toFixed(1) : '0',
    totalBytes,
  };
}

/**
 * Test WebSocket connections (basic TCP-level test using raw HTTP upgrade).
 * Uses only the standard http module -- no 'ws' dependency.
 */
function testWebSocket(count) {
  return new Promise((resolve) => {
    const label = `WebSocket ${count} connections`;
    const startTime = Date.now();
    let connected = 0;
    let failed = 0;
    let completed = 0;
    const durations = [];

    const urlObj = new URL(BASE_URL);
    const isHttps = urlObj.protocol === 'https:';
    const lib = isHttps ? https : http;
    const wsPath = '/ws/employee-chat';

    function checkDone() {
      if (completed < count) return;
      const wallTime = Date.now() - startTime;
      durations.sort((a, b) => a - b);

      resolve({
        label,
        method: 'WS',
        path: wsPath,
        concurrency: count,
        wallTimeMs: wallTime,
        totalRequests: count,
        successCount: connected,
        errorCount: failed,
        statusCounts: { 'connected': connected, 'failed': failed },
        minMs: durations[0] || 0,
        maxMs: durations[durations.length - 1] || 0,
        avgMs: durations.length > 0 ? durations.reduce((a, b) => a + b, 0) / durations.length : 0,
        p95Ms: percentile(durations, 95),
        throughputRps: wallTime > 0 ? (count / (wallTime / 1000)).toFixed(1) : '0',
        totalBytes: 0,
      });
    }

    for (let i = 0; i < count; i++) {
      const connStart = Date.now();

      // Generate a random WebSocket key (16 bytes base64-encoded)
      const wsKeyBytes = Buffer.alloc(16);
      for (let b = 0; b < 16; b++) wsKeyBytes[b] = Math.floor(Math.random() * 256);
      const wsKey = wsKeyBytes.toString('base64');

      const options = {
        hostname: urlObj.hostname,
        port: urlObj.port || (isHttps ? 443 : 80),
        path: wsPath,
        method: 'GET',
        headers: {
          'Connection': 'Upgrade',
          'Upgrade': 'websocket',
          'Sec-WebSocket-Version': '13',
          'Sec-WebSocket-Key': wsKey,
        },
        timeout: TIMEOUT_MS,
        rejectUnauthorized: false,
      };

      if (SESSION_TOKEN) {
        options.headers['Authorization'] = `Bearer ${SESSION_TOKEN}`;
      }
      if (API_KEY) {
        options.headers['X-API-Key'] = API_KEY;
      }

      const req = lib.request(options);

      req.on('upgrade', (res, socket) => {
        const duration = Date.now() - connStart;
        durations.push(duration);
        connected++;
        completed++;
        // Immediately close the connection
        socket.end();
        socket.destroy();
        if (VERBOSE) {
          console.log(`  [WS] Connection ${i + 1} established (${fmtMs(duration)})`);
        }
        checkDone();
      });

      req.on('response', (res) => {
        // Server responded with a regular HTTP response instead of upgrading
        const duration = Date.now() - connStart;
        durations.push(duration);
        if (res.statusCode === 101) {
          connected++;
        } else {
          failed++;
        }
        completed++;
        res.resume(); // drain the response
        checkDone();
      });

      req.on('error', () => {
        const duration = Date.now() - connStart;
        durations.push(duration);
        failed++;
        completed++;
        checkDone();
      });

      req.on('timeout', () => {
        req.destroy();
        const duration = Date.now() - connStart;
        durations.push(duration);
        failed++;
        completed++;
        checkDone();
      });

      req.end();
    }
  });
}

// ============================================
// Test Scenarios
// ============================================

function generateAttendanceBody(index) {
  return {
    phone: `+7900000${String(index).padStart(4, '0')}`,
    shopAddress: 'Load Test Shop',
    type: 'check-in',
    timestamp: new Date().toISOString(),
    gps: {
      latitude: 44.0 + (Math.random() * 0.01),
      longitude: 43.0 + (Math.random() * 0.01),
    },
  };
}

async function runAllScenarios() {
  const scenarios = [];

  console.log('\n[1/5] GET /api/employees x50 ...');
  scenarios.push(await runParallel(
    'GET /api/employees',
    50, 'GET', '/api/employees'
  ));

  console.log('[2/5] GET /api/shift-reports x50 ...');
  scenarios.push(await runParallel(
    'GET /api/shift-reports',
    50, 'GET', '/api/shift-reports'
  ));

  console.log('[3/5] POST /api/attendance x20 ...');
  scenarios.push(await runParallel(
    'POST /api/attendance (check-in)',
    20, 'POST', '/api/attendance',
    generateAttendanceBody
  ));

  console.log('[4/5] GET /api/efficiency/reports-batch x10 ...');
  scenarios.push(await runParallel(
    'GET /api/efficiency/reports-batch',
    10, 'GET', '/api/efficiency/reports-batch?month=2026-02'
  ));

  console.log('[5/5] WebSocket /ws/employee-chat x30 ...');
  scenarios.push(await testWebSocket(30));

  return scenarios;
}

// ============================================
// Report Formatting
// ============================================

function printReport(scenarios) {
  const totalRequests = scenarios.reduce((s, sc) => s + sc.totalRequests, 0);
  const totalErrors = scenarios.reduce((s, sc) => s + sc.errorCount, 0);
  const totalBytes = scenarios.reduce((s, sc) => s + sc.totalBytes, 0);

  console.log('\n');
  console.log('='.repeat(110));
  console.log('  LOAD TEST RESULTS');
  console.log('  Server: ' + BASE_URL);
  console.log('  Date:   ' + new Date().toISOString());
  console.log('  Auth:   ' + (SESSION_TOKEN ? 'Bearer token set' : 'No token') +
    (API_KEY ? ', API key set' : ''));
  console.log('='.repeat(110));

  // Table header
  const cols = [
    { header: 'Scenario', width: 38 },
    { header: 'Reqs', width: 6 },
    { header: 'OK', width: 6 },
    { header: 'Err', width: 5 },
    { header: 'Min', width: 9 },
    { header: 'Avg', width: 9 },
    { header: 'P95', width: 9 },
    { header: 'Max', width: 9 },
    { header: 'RPS', width: 8 },
    { header: 'Wall', width: 9 },
  ];

  const divider = '+' + cols.map(c => '-'.repeat(c.width + 2)).join('+') + '+';

  function padRight(str, len) {
    str = String(str);
    return str.length >= len ? str.substring(0, len) : str + ' '.repeat(len - str.length);
  }
  function padLeft(str, len) {
    str = String(str);
    return str.length >= len ? str.substring(0, len) : ' '.repeat(len - str.length) + str;
  }

  console.log('');
  console.log(divider);
  console.log('| ' + cols.map(c => padRight(c.header, c.width)).join(' | ') + ' |');
  console.log(divider);

  for (const sc of scenarios) {
    const row = [
      padRight(sc.label, cols[0].width),
      padLeft(String(sc.totalRequests), cols[1].width),
      padLeft(String(sc.successCount), cols[2].width),
      padLeft(String(sc.errorCount), cols[3].width),
      padLeft(fmtMs(sc.minMs), cols[4].width),
      padLeft(fmtMs(sc.avgMs), cols[5].width),
      padLeft(fmtMs(sc.p95Ms), cols[6].width),
      padLeft(fmtMs(sc.maxMs), cols[7].width),
      padLeft(sc.throughputRps, cols[8].width),
      padLeft(fmtMs(sc.wallTimeMs), cols[9].width),
    ];
    console.log('| ' + row.join(' | ') + ' |');
  }

  console.log(divider);

  // Status code breakdown
  console.log('\n--- Status Code Breakdown ---\n');
  for (const sc of scenarios) {
    const codes = Object.entries(sc.statusCounts)
      .map(([code, count]) => `${code}:${count}`)
      .join('  ');
    console.log(`  ${sc.label}`);
    console.log(`    ${codes}`);
  }

  // Summary
  console.log('\n' + '='.repeat(110));
  console.log(`  SUMMARY`);
  console.log(`  Total requests:  ${totalRequests}`);
  console.log(`  Total errors:    ${totalErrors}`);
  console.log(`  Total data:      ${(totalBytes / 1024).toFixed(1)} KB`);
  console.log(`  Error rate:      ${totalRequests > 0 ? ((totalErrors / totalRequests) * 100).toFixed(1) : 0}%`);
  console.log('='.repeat(110));

  if (totalErrors > 0) {
    console.log('\n  WARNING: Some requests failed. Check status code breakdown above.');
  } else {
    console.log('\n  All requests completed successfully.');
  }
  console.log('');
}

// ============================================
// Main
// ============================================

async function main() {
  console.log('='.repeat(60));
  console.log('  Arabica Load Test');
  console.log('  Target: ' + BASE_URL);
  console.log('  Timeout: ' + TIMEOUT_MS + 'ms per request');
  console.log('='.repeat(60));

  // Quick connectivity check
  console.log('\nChecking server connectivity...');
  const healthCheck = await makeRequest('GET', '/health');
  if (healthCheck.error) {
    console.error(`\n  ERROR: Cannot connect to ${BASE_URL}`);
    console.error(`  ${healthCheck.error}`);
    console.error('\n  Make sure the server is running and accessible.');
    process.exit(1);
  }
  console.log(`  Server responded with status ${healthCheck.status} (${fmtMs(healthCheck.duration)})`);

  if (healthCheck.status >= 500) {
    console.error('\n  WARNING: Server returned 5xx on /health. Proceeding anyway...');
  }

  console.log('\nStarting load test scenarios...\n');
  const startTime = Date.now();
  const scenarios = await runAllScenarios();
  const totalTime = Date.now() - startTime;

  printReport(scenarios);
  console.log(`  Total test duration: ${fmtMs(totalTime)}\n`);

  // Exit code based on error threshold (>20% = failure)
  const totalRequests = scenarios.reduce((s, sc) => s + sc.totalRequests, 0);
  const totalErrors = scenarios.reduce((s, sc) => s + sc.errorCount, 0);
  const errorRate = totalRequests > 0 ? totalErrors / totalRequests : 0;

  if (errorRate > 0.2) {
    console.log('  EXIT: FAIL (error rate > 20%)');
    process.exit(1);
  } else {
    console.log('  EXIT: PASS');
    process.exit(0);
  }
}

main().catch((err) => {
  console.error('Unhandled error:', err);
  process.exit(1);
});
