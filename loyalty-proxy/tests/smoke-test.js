/**
 * API Smoke Test - Comprehensive
 * ===========================================================
 * Goes through every known endpoint and checks for server errors.
 * GET endpoints: expects non-5xx response.
 * POST endpoints: sends minimal valid data, expects non-5xx response
 *   (400 Bad Request is acceptable -- it means the endpoint works).
 *
 * Usage:
 *   node tests/smoke-test.js                        # localhost:3000
 *   node tests/smoke-test.js https://arabica26.ru   # production
 *   BASE_URL=http://localhost:3000 API_KEY=xxx node tests/smoke-test.js
 *
 * Environment variables:
 *   BASE_URL       - Server URL (default: http://localhost:3000)
 *   API_KEY        - X-API-Key header value (optional)
 *   SESSION_TOKEN  - Bearer token for authenticated requests (optional)
 *   TIMEOUT_MS     - Per-request timeout in ms (default: 15000)
 *   SAVE_RESULTS   - Set to "true" to save JSON results to file (default: true)
 */

'use strict';

const http = require('http');
const https = require('https');
const fs = require('fs');
const path = require('path');
const { URL } = require('url');

// ============================================
// Configuration
// ============================================

const BASE_URL = process.argv[2] || process.env.BASE_URL || 'http://localhost:3000';
const API_KEY = process.env.API_KEY || '';
const SESSION_TOKEN = process.env.SESSION_TOKEN || '';
const TIMEOUT_MS = parseInt(process.env.TIMEOUT_MS, 10) || 15000;
const SAVE_RESULTS = process.env.SAVE_RESULTS !== 'false';

// ============================================
// Endpoint Definitions
// ============================================

/**
 * All GET endpoints to test.
 * Each entry: { path, description, category }
 */
const GET_ENDPOINTS = [
  // Health
  { path: '/health', description: 'Health check', category: 'System' },

  // Employees
  { path: '/api/employees', description: 'List all employees', category: 'Employees' },

  // Shops
  { path: '/api/shops', description: 'List all shops', category: 'Shops' },

  // Shift Reports
  { path: '/api/shift-reports', description: 'List shift reports', category: 'Shifts' },
  { path: '/api/shift-questions', description: 'Shift questions', category: 'Shifts' },
  { path: '/api/pending-shift-reports', description: 'Pending shift reports', category: 'Shifts' },

  // Shift Handover
  { path: '/api/shift-handover-questions', description: 'Shift handover questions', category: 'Shift Handover' },
  { path: '/api/shift-handover-reports', description: 'Shift handover reports', category: 'Shift Handover' },
  { path: '/api/shift-handover/pending', description: 'Pending shift handovers', category: 'Shift Handover' },
  { path: '/api/shift-handover/failed', description: 'Failed shift handovers', category: 'Shift Handover' },

  // Recount
  { path: '/api/recount-reports', description: 'Recount reports', category: 'Recount' },
  { path: '/api/recount-reports/expired', description: 'Expired recount reports', category: 'Recount' },
  { path: '/api/pending-recount-reports', description: 'Pending recount reports', category: 'Recount' },
  { path: '/api/recount-questions', description: 'Recount questions', category: 'Recount' },

  // Envelope
  { path: '/api/envelope-questions', description: 'Envelope questions', category: 'Envelope' },
  { path: '/api/envelope-reports', description: 'Envelope reports', category: 'Envelope' },
  { path: '/api/envelope-reports/expired', description: 'Expired envelope reports', category: 'Envelope' },
  { path: '/api/envelope-pending', description: 'Pending envelopes', category: 'Envelope' },
  { path: '/api/envelope-failed', description: 'Failed envelopes', category: 'Envelope' },

  // Attendance
  { path: '/api/attendance', description: 'Attendance records', category: 'Attendance' },
  { path: '/api/attendance/pending', description: 'Pending attendance', category: 'Attendance' },
  { path: '/api/attendance/failed', description: 'Failed attendance', category: 'Attendance' },

  // RKO
  { path: '/api/rko/all', description: 'All RKO reports', category: 'RKO' },
  { path: '/api/rko/pending', description: 'Pending RKO', category: 'RKO' },
  { path: '/api/rko/failed', description: 'Failed RKO', category: 'RKO' },

  // Work Schedule
  { path: '/api/work-schedule', description: 'Work schedule', category: 'Work Schedule' },
  { path: '/api/work-schedule/template', description: 'Schedule template', category: 'Work Schedule' },

  // Withdrawals
  { path: '/api/withdrawals', description: 'Withdrawal records', category: 'Withdrawals' },

  // Coffee Machine
  { path: '/api/coffee-machine/templates', description: 'Coffee machine templates', category: 'Coffee Machine' },
  { path: '/api/coffee-machine/reports', description: 'Coffee machine reports', category: 'Coffee Machine' },

  // Efficiency
  { path: '/api/efficiency/reports-batch', description: 'Efficiency reports batch', category: 'Efficiency' },
  { path: '/api/efficiency-penalties', description: 'Efficiency penalties', category: 'Efficiency' },

  // Training
  { path: '/api/training-articles', description: 'Training articles', category: 'Training' },

  // Tests
  { path: '/api/test-questions', description: 'Test questions', category: 'Tests' },
  { path: '/api/test-results', description: 'Test results', category: 'Tests' },

  // Tasks
  { path: '/api/tasks', description: 'Tasks list', category: 'Tasks' },
  { path: '/api/recurring-tasks', description: 'Recurring tasks', category: 'Tasks' },

  // Reviews
  { path: '/api/reviews', description: 'Reviews', category: 'Reviews' },

  // Product Questions
  { path: '/api/product-questions', description: 'Product questions', category: 'Product Questions' },

  // Recipes
  { path: '/api/recipes', description: 'Recipes', category: 'Recipes' },

  // Menu
  { path: '/api/menu', description: 'Menu items', category: 'Menu' },

  // Orders
  { path: '/api/orders', description: 'Orders', category: 'Orders' },
  { path: '/api/orders/unviewed-count', description: 'Unviewed orders count', category: 'Orders' },

  // Clients
  { path: '/api/clients', description: 'Clients', category: 'Clients' },

  // Bonus / Penalties
  { path: '/api/bonus-penalties', description: 'Bonus and penalties', category: 'Bonus/Penalties' },

  // Loyalty
  { path: '/api/loyalty-promo', description: 'Loyalty promo', category: 'Loyalty' },
  { path: '/api/fortune-wheel/settings', description: 'Fortune wheel settings', category: 'Loyalty' },
  { path: '/api/referrals/stats', description: 'Referrals statistics', category: 'Loyalty' },
  { path: '/api/referrals', description: 'Referrals list', category: 'Loyalty' },

  // Suppliers
  { path: '/api/suppliers', description: 'Suppliers', category: 'Suppliers' },

  // Job Applications
  { path: '/api/job-applications', description: 'Job applications', category: 'Job Applications' },

  // Admin / System
  { path: '/api/admin/disk-info', description: 'Disk info', category: 'Admin' },
  { path: '/api/admin/data-stats', description: 'Data statistics', category: 'Admin' },
  { path: '/api/app-version', description: 'App version', category: 'System' },

  // Points Settings
  { path: '/api/points-settings', description: 'Points settings', category: 'Settings' },
  { path: '/api/task-points-settings', description: 'Task points settings', category: 'Settings' },

  // Shift Transfers
  { path: '/api/shift-transfers', description: 'Shift transfers', category: 'Shift Transfers' },

  // Geofence
  { path: '/api/geofence/zones', description: 'Geofence zones', category: 'Geofence' },

  // Employee Chat
  { path: '/api/employee-chat/chats', description: 'Employee chats', category: 'Chat' },

  // Shop Managers
  { path: '/api/shop-managers', description: 'Shop managers', category: 'Shops' },

  // Master Catalog
  { path: '/api/master-catalog', description: 'Master catalog', category: 'Catalog' },
  { path: '/api/shop-products', description: 'Shop products', category: 'Catalog' },

  // Z-Report & Cigarette Vision
  { path: '/api/z-report/templates', description: 'Z-report templates', category: 'AI/Vision' },
  { path: '/api/cigarette-vision/stats', description: 'Cigarette vision stats', category: 'AI/Vision' },
];

/**
 * POST endpoints tested with minimal valid bodies.
 * These should NOT cause server errors (5xx). A 400 (bad request) or 401/403 is fine.
 * We avoid endpoints that create real data where possible, or use clearly fake test data.
 */
const POST_ENDPOINTS = [
  // Auth endpoints (expect 400 without valid data)
  {
    path: '/api/auth/request-otp',
    description: 'Request OTP (empty body)',
    category: 'Auth',
    body: {},
  },
  {
    path: '/api/auth/verify-otp',
    description: 'Verify OTP (empty body)',
    category: 'Auth',
    body: {},
  },
  {
    path: '/api/auth/login',
    description: 'Login (empty body)',
    category: 'Auth',
    body: {},
  },

  // Employee registration (expects validation error, not crash)
  {
    path: '/api/employee-registration',
    description: 'Employee registration (empty body)',
    category: 'Employees',
    body: {},
  },

  // Attendance check-in (mock data, should validate and return error or success)
  {
    path: '/api/attendance',
    description: 'Attendance check-in (test data)',
    category: 'Attendance',
    body: {
      phone: '+70000000000',
      shopAddress: '__smoke_test__',
      type: 'check-in',
      timestamp: new Date().toISOString(),
    },
  },

  // Attendance GPS check
  {
    path: '/api/attendance/gps-check',
    description: 'GPS check (test data)',
    category: 'Attendance',
    body: {
      phone: '+70000000000',
      latitude: 44.0,
      longitude: 43.0,
    },
  },

  // Geofence client check
  {
    path: '/api/geofence/client-check',
    description: 'Geofence client check (test coords)',
    category: 'Geofence',
    body: {
      latitude: 44.0,
      longitude: 43.0,
    },
  },

  // QR scan (test data)
  {
    path: '/api/qr-scan',
    description: 'QR scan (invalid code)',
    category: 'Loyalty',
    body: {
      qrCode: 'SMOKE_TEST_INVALID',
      shopAddress: '__smoke_test__',
    },
  },

  // Review (minimal)
  {
    path: '/api/reviews',
    description: 'Create review (empty body)',
    category: 'Reviews',
    body: {},
  },

  // Order (minimal)
  {
    path: '/api/orders',
    description: 'Create order (empty body)',
    category: 'Orders',
    body: {},
  },

  // Loyalty add points (minimal)
  {
    path: '/api/loyalty/add-points',
    description: 'Add loyalty points (empty body)',
    category: 'Loyalty',
    body: {},
  },

  // Loyalty spend points (minimal)
  {
    path: '/api/loyalty/spend-points',
    description: 'Spend loyalty points (empty body)',
    category: 'Loyalty',
    body: {},
  },

  // Recount questions (minimal)
  {
    path: '/api/recount-questions',
    description: 'Create recount question (empty body)',
    category: 'Recount',
    body: {},
  },

  // Envelope questions (minimal)
  {
    path: '/api/envelope-questions',
    description: 'Create envelope question (empty body)',
    category: 'Envelope',
    body: {},
  },
];

// ============================================
// HTTP Request Utility
// ============================================

function buildHeaders(hasBody) {
  const headers = {
    'Accept': 'application/json',
  };
  if (hasBody) {
    headers['Content-Type'] = 'application/json';
  }
  if (API_KEY) {
    headers['X-API-Key'] = API_KEY;
  }
  if (SESSION_TOKEN) {
    headers['Authorization'] = `Bearer ${SESSION_TOKEN}`;
  }
  return headers;
}

function makeRequest(method, urlPath, body) {
  return new Promise((resolve) => {
    const startTime = Date.now();
    const fullUrl = `${BASE_URL}${urlPath}`;
    let urlObj;
    try {
      urlObj = new URL(fullUrl);
    } catch (e) {
      resolve({ status: 0, duration: 0, error: `Invalid URL: ${fullUrl}`, body: '' });
      return;
    }
    const lib = urlObj.protocol === 'https:' ? https : http;
    const bodyStr = body ? JSON.stringify(body) : null;

    const options = {
      hostname: urlObj.hostname,
      port: urlObj.port || (urlObj.protocol === 'https:' ? 443 : 80),
      path: urlObj.pathname + urlObj.search,
      method: method,
      headers: buildHeaders(!!bodyStr),
      timeout: TIMEOUT_MS,
      rejectUnauthorized: false,
    };

    if (bodyStr) {
      options.headers['Content-Length'] = Buffer.byteLength(bodyStr);
    }

    const req = lib.request(options, (res) => {
      let responseBody = '';
      res.on('data', (chunk) => { responseBody += chunk; });
      res.on('end', () => {
        const duration = Date.now() - startTime;
        resolve({
          status: res.statusCode,
          duration: duration,
          error: null,
          body: responseBody.substring(0, 300),
        });
      });
    });

    req.on('error', (e) => {
      const duration = Date.now() - startTime;
      resolve({ status: 0, duration: duration, error: e.message, body: '' });
    });

    req.on('timeout', () => {
      req.destroy();
      const duration = Date.now() - startTime;
      resolve({ status: 0, duration: duration, error: 'TIMEOUT', body: '' });
    });

    if (bodyStr) {
      req.write(bodyStr);
    }
    req.end();
  });
}

// ============================================
// Test Runner
// ============================================

function classifyResult(status, error) {
  if (error) return 'ERROR';
  if (status === 0) return 'ERROR';
  if (status >= 500) return 'BROKEN';
  return 'OK';
}

function statusIcon(classification) {
  switch (classification) {
    case 'OK': return '[OK]   ';
    case 'BROKEN': return '[FAIL] ';
    case 'ERROR': return '[ERR]  ';
    default: return '[???]  ';
  }
}

async function runTests() {
  console.log('\n' + '='.repeat(80));
  console.log('  API SMOKE TEST - Comprehensive');
  console.log('  Server: ' + BASE_URL);
  console.log('  Date:   ' + new Date().toISOString());
  console.log('  Auth:   ' + (SESSION_TOKEN ? 'Bearer token set' : 'No token') +
    (API_KEY ? ', API key set' : ', No API key'));
  console.log('  Timeout: ' + TIMEOUT_MS + 'ms');
  console.log('='.repeat(80));

  // Quick connectivity check
  console.log('\nChecking connectivity...');
  const healthRes = await makeRequest('GET', '/health');
  if (healthRes.error) {
    console.error(`\n  FATAL: Cannot connect to ${BASE_URL}`);
    console.error(`  Error: ${healthRes.error}`);
    console.error('\n  Make sure the server is running and accessible.');
    process.exit(1);
  }
  console.log(`  Server responded: ${healthRes.status} (${healthRes.duration}ms)`);

  const results = {
    working: [],
    broken: [],
    errors: [],
  };

  // ---- GET Endpoints ----
  console.log('\n' + '-'.repeat(80));
  console.log('  GET ENDPOINTS (' + GET_ENDPOINTS.length + ' total)');
  console.log('-'.repeat(80) + '\n');

  let currentCategory = '';
  for (const ep of GET_ENDPOINTS) {
    if (ep.category !== currentCategory) {
      currentCategory = ep.category;
      console.log(`  --- ${currentCategory} ---`);
    }

    const res = await makeRequest('GET', ep.path);
    const classification = classifyResult(res.status, res.error);
    const icon = statusIcon(classification);
    const detail = res.error ? res.error : `${res.status}`;
    const durationStr = `${res.duration}ms`;

    console.log(`  ${icon} GET ${ep.path}  ->  ${detail}  (${durationStr})`);

    const entry = {
      method: 'GET',
      path: ep.path,
      description: ep.description,
      category: ep.category,
      status: res.status,
      duration: res.duration,
      error: res.error,
      responsePreview: res.body ? res.body.substring(0, 100) : '',
    };

    if (classification === 'OK') {
      results.working.push(entry);
    } else if (classification === 'BROKEN') {
      results.broken.push(entry);
    } else {
      results.errors.push(entry);
    }
  }

  // ---- POST Endpoints ----
  console.log('\n' + '-'.repeat(80));
  console.log('  POST ENDPOINTS (' + POST_ENDPOINTS.length + ' total)');
  console.log('  (Sending minimal bodies; 400 = OK, 5xx = BROKEN)');
  console.log('-'.repeat(80) + '\n');

  currentCategory = '';
  for (const ep of POST_ENDPOINTS) {
    if (ep.category !== currentCategory) {
      currentCategory = ep.category;
      console.log(`  --- ${currentCategory} ---`);
    }

    const res = await makeRequest('POST', ep.path, ep.body);
    const classification = classifyResult(res.status, res.error);
    const icon = statusIcon(classification);
    const detail = res.error ? res.error : `${res.status}`;
    const durationStr = `${res.duration}ms`;

    console.log(`  ${icon} POST ${ep.path}  ->  ${detail}  (${durationStr})`);

    const entry = {
      method: 'POST',
      path: ep.path,
      description: ep.description,
      category: ep.category,
      status: res.status,
      duration: res.duration,
      error: res.error,
      responsePreview: res.body ? res.body.substring(0, 100) : '',
    };

    if (classification === 'OK') {
      results.working.push(entry);
    } else if (classification === 'BROKEN') {
      results.broken.push(entry);
    } else {
      results.errors.push(entry);
    }
  }

  return results;
}

// ============================================
// Report
// ============================================

function printSummary(results) {
  const total = results.working.length + results.broken.length + results.errors.length;

  console.log('\n' + '='.repeat(80));
  console.log('  SMOKE TEST RESULTS');
  console.log('='.repeat(80));

  console.log(`\n  Total endpoints tested:  ${total}`);
  console.log(`  Working (non-5xx):       ${results.working.length}`);
  console.log(`  Broken (5xx):            ${results.broken.length}`);
  console.log(`  Connection errors:       ${results.errors.length}`);

  // Working endpoints summary by category
  if (results.working.length > 0) {
    console.log('\n' + '-'.repeat(80));
    console.log('  WORKING ENDPOINTS (' + results.working.length + ')');
    console.log('-'.repeat(80));

    const byCategory = {};
    for (const ep of results.working) {
      if (!byCategory[ep.category]) byCategory[ep.category] = [];
      byCategory[ep.category].push(ep);
    }
    for (const [cat, eps] of Object.entries(byCategory)) {
      console.log(`\n  ${cat}:`);
      for (const ep of eps) {
        console.log(`    [${ep.status}] ${ep.method} ${ep.path} - ${ep.description} (${ep.duration}ms)`);
      }
    }
  }

  // Broken endpoints (detailed)
  if (results.broken.length > 0) {
    console.log('\n' + '-'.repeat(80));
    console.log('  BROKEN ENDPOINTS (' + results.broken.length + ') -- Server errors (5xx)');
    console.log('-'.repeat(80));

    for (const ep of results.broken) {
      console.log(`\n  ${ep.method} ${ep.path}`);
      console.log(`    Description: ${ep.description}`);
      console.log(`    Status:      ${ep.status}`);
      console.log(`    Duration:    ${ep.duration}ms`);
      if (ep.responsePreview) {
        console.log(`    Response:    ${ep.responsePreview}`);
      }
    }
  }

  // Connection errors (detailed)
  if (results.errors.length > 0) {
    console.log('\n' + '-'.repeat(80));
    console.log('  CONNECTION ERRORS (' + results.errors.length + ')');
    console.log('-'.repeat(80));

    for (const ep of results.errors) {
      console.log(`\n  ${ep.method} ${ep.path}`);
      console.log(`    Description: ${ep.description}`);
      console.log(`    Error:       ${ep.error}`);
      console.log(`    Duration:    ${ep.duration}ms`);
    }
  }

  // Timing analysis
  const allEntries = [...results.working, ...results.broken, ...results.errors];
  const durations = allEntries.map(e => e.duration).filter(d => d > 0).sort((a, b) => a - b);

  if (durations.length > 0) {
    const avg = durations.reduce((a, b) => a + b, 0) / durations.length;
    const p95Index = Math.ceil(0.95 * durations.length) - 1;

    console.log('\n' + '-'.repeat(80));
    console.log('  RESPONSE TIME ANALYSIS');
    console.log('-'.repeat(80));
    console.log(`  Min:     ${durations[0]}ms`);
    console.log(`  Avg:     ${avg.toFixed(0)}ms`);
    console.log(`  P95:     ${durations[Math.max(0, p95Index)]}ms`);
    console.log(`  Max:     ${durations[durations.length - 1]}ms`);

    // Slow endpoints (>2s)
    const slow = allEntries.filter(e => e.duration > 2000);
    if (slow.length > 0) {
      console.log(`\n  Slow endpoints (>2s):`);
      for (const ep of slow.sort((a, b) => b.duration - a.duration)) {
        console.log(`    ${ep.duration}ms - ${ep.method} ${ep.path}`);
      }
    }
  }

  console.log('\n' + '='.repeat(80));

  if (results.broken.length === 0 && results.errors.length === 0) {
    console.log('  RESULT: ALL ENDPOINTS PASSED');
  } else if (results.broken.length > 0) {
    console.log(`  RESULT: ${results.broken.length} BROKEN ENDPOINT(S) FOUND`);
  }
  if (results.errors.length > 0) {
    console.log(`  WARNING: ${results.errors.length} CONNECTION ERROR(S)`);
  }

  console.log('='.repeat(80) + '\n');
}

function saveResults(results) {
  const resultsDir = path.resolve(__dirname);
  const fileName = `smoke-results-${Date.now()}.json`;
  const filePath = path.join(resultsDir, fileName);

  const output = {
    date: new Date().toISOString(),
    baseUrl: BASE_URL,
    summary: {
      total: results.working.length + results.broken.length + results.errors.length,
      working: results.working.length,
      broken: results.broken.length,
      errors: results.errors.length,
    },
    working: results.working,
    broken: results.broken,
    errors: results.errors,
  };

  try {
    fs.writeFileSync(filePath, JSON.stringify(output, null, 2));
    console.log(`  Results saved to: ${filePath}`);
  } catch (e) {
    console.error(`  Failed to save results: ${e.message}`);
  }
}

// ============================================
// Main
// ============================================

async function main() {
  const results = await runTests();
  printSummary(results);

  if (SAVE_RESULTS) {
    saveResults(results);
  }

  // Exit code: 0 if no broken, 1 if any broken
  const exitCode = results.broken.length > 0 ? 1 : 0;
  process.exit(exitCode);
}

main().catch((err) => {
  console.error('Unhandled error:', err);
  process.exit(1);
});
