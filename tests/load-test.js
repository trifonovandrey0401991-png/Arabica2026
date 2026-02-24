/**
 * Load Test — Arabica API
 * Tests concurrency levels: 5, 10, 20, 30, 50
 * Measures: response time, throughput, errors, memory
 * Run on server: node /tmp/load-test.js
 */
const http = require('http');

const API_KEY = '58c4d46b9bb324d03c5d96781223821f3528c5efa4604090a8e95ac540173585';
const AUTH_TOKEN = 'b20781bfd2837fc2b71941e7138dec26100db899afa1d6cbbfa907962810e812';
const TIMEOUT_MS = 30000;

// Key endpoints that represent real user activity
const ENDPOINTS = [
  // HIGH FREQUENCY — every employee hits these on app open
  { path: '/api/dashboard/counters', name: 'Dashboard', weight: 5 },
  { path: '/api/employees', name: 'Employees', weight: 4 },
  { path: '/api/shops', name: 'Shops', weight: 4 },
  { path: '/api/menu', name: 'Menu', weight: 3 },
  { path: '/api/tasks', name: 'Tasks', weight: 3 },
  { path: '/api/work-schedule?month=2026-02', name: 'Schedule', weight: 3 },
  // MEDIUM FREQUENCY — managers check these often
  { path: '/api/shift-reports', name: 'Shift reports', weight: 2 },
  { path: '/api/orders', name: 'Orders', weight: 2 },
  { path: '/api/attendance', name: 'Attendance', weight: 2 },
  { path: '/api/clients', name: 'Clients', weight: 2 },
  { path: '/api/recount-reports', name: 'Recount reports', weight: 2 },
  { path: '/api/efficiency/reports-batch?month=2026-02', name: 'Efficiency', weight: 2 },
  { path: '/api/bonus-penalties', name: 'Bonuses', weight: 1 },
  { path: '/api/envelope-reports', name: 'Envelope', weight: 1 },
  { path: '/api/rko/all?month=2026-02', name: 'RKO', weight: 1 },
  // LOW FREQUENCY — occasional
  { path: '/api/training-articles', name: 'Training', weight: 1 },
  { path: '/api/test-questions', name: 'Tests', weight: 1 },
  { path: '/api/recipes', name: 'Recipes', weight: 1 },
  { path: '/api/reviews', name: 'Reviews', weight: 1 },
  { path: '/api/coffee-machine/reports', name: 'Coffee machine', weight: 1 },
  { path: '/api/messenger/conversations?phone=79001234567', name: 'Messenger', weight: 2 },
  { path: '/api/report-notifications', name: 'Notifications', weight: 2 },
  { path: '/api/master-catalog', name: 'Master catalog', weight: 1 },
  { path: '/api/shift-questions', name: 'Shift questions', weight: 1 },
  { path: '/api/suppliers', name: 'Suppliers', weight: 1 },
];

function makeRequest(endpoint) {
  return new Promise((resolve) => {
    const start = Date.now();
    const options = {
      hostname: '127.0.0.1',
      port: 3000,
      path: endpoint.path,
      method: 'GET',
      headers: {
        'Content-Type': 'application/json',
        'Accept': 'application/json',
        'X-API-Key': API_KEY,
        'Authorization': `Bearer ${AUTH_TOKEN}`,
      },
      timeout: TIMEOUT_MS,
    };

    const req = http.request(options, (res) => {
      let size = 0;
      res.on('data', chunk => { size += chunk.length; });
      res.on('end', () => {
        resolve({
          name: endpoint.name,
          path: endpoint.path,
          status: res.statusCode,
          duration: Date.now() - start,
          size,
          ok: res.statusCode === 200,
        });
      });
    });

    req.on('timeout', () => {
      req.destroy();
      resolve({ name: endpoint.name, path: endpoint.path, status: 0, duration: Date.now() - start, size: 0, ok: false, error: 'TIMEOUT' });
    });

    req.on('error', (err) => {
      resolve({ name: endpoint.name, path: endpoint.path, status: 0, duration: Date.now() - start, size: 0, ok: false, error: err.message });
    });

    req.end();
  });
}

function buildWeightedList() {
  const list = [];
  for (const ep of ENDPOINTS) {
    for (let i = 0; i < ep.weight; i++) list.push(ep);
  }
  return list;
}

function getProcessMemory() {
  return new Promise((resolve) => {
    const { exec } = require('child_process');
    exec("pm2 jlist 2>/dev/null", (err, stdout) => {
      if (err) { resolve(0); return; }
      try {
        const procs = JSON.parse(stdout);
        const lp = procs.find(p => p.name === 'loyalty-proxy');
        resolve(lp ? Math.round(lp.monit.memory / 1024 / 1024) : 0);
      } catch { resolve(0); }
    });
  });
}

async function runConcurrencyLevel(concurrency, totalRequests) {
  const weighted = buildWeightedList();
  const requests = [];
  for (let i = 0; i < totalRequests; i++) {
    requests.push(weighted[Math.floor(Math.random() * weighted.length)]);
  }

  const results = [];
  let completed = 0;
  let active = 0;
  let idx = 0;

  const memBefore = await getProcessMemory();
  const startTime = Date.now();

  return new Promise((resolve) => {
    function next() {
      while (active < concurrency && idx < requests.length) {
        const ep = requests[idx++];
        active++;
        makeRequest(ep).then(result => {
          results.push(result);
          completed++;
          active--;
          if (completed === totalRequests) {
            const elapsed = Date.now() - startTime;
            getProcessMemory().then(memAfter => {
              const durations = results.map(r => r.duration).sort((a, b) => a - b);
              const okCount = results.filter(r => r.ok).length;
              const errCount = results.filter(r => !r.ok).length;
              const totalSize = results.reduce((s, r) => s + r.size, 0);

              const perEndpoint = {};
              for (const r of results) {
                if (!perEndpoint[r.name]) perEndpoint[r.name] = { durations: [], errors: 0, sizes: [] };
                perEndpoint[r.name].durations.push(r.duration);
                perEndpoint[r.name].sizes.push(r.size);
                if (!r.ok) perEndpoint[r.name].errors++;
              }

              const p50 = durations[Math.floor(durations.length * 0.5)];
              const p95 = durations[Math.floor(durations.length * 0.95)];
              const p99 = durations[Math.floor(durations.length * 0.99)];
              const max = durations[durations.length - 1];
              const avg = Math.round(durations.reduce((s, d) => s + d, 0) / durations.length);
              const rps = (totalRequests / (elapsed / 1000)).toFixed(1);

              resolve({ concurrency, totalRequests, elapsed, rps, okCount, errCount, avg, p50, p95, p99, max, memBefore, memAfter, totalSizeMB: (totalSize / 1024 / 1024).toFixed(1), perEndpoint });
            });
          } else {
            next();
          }
        });
      }
    }
    next();
  });
}

async function main() {
  console.log('=== ARABICA LOAD TEST ===');
  console.log(`Endpoints: ${ENDPOINTS.length}, Weighted pool: ${buildWeightedList().length}`);
  console.log('');

  // Warm-up: single sequential request to each
  console.log('--- Warm-up: 1 request each ---');
  const warmupResults = [];
  for (const ep of ENDPOINTS) {
    const r = await makeRequest(ep);
    warmupResults.push(r);
  }
  const warmupOk = warmupResults.filter(r => r.ok).length;
  const warmupFail = warmupResults.filter(r => !r.ok);
  console.log(`Warm-up: ${warmupOk}/${ENDPOINTS.length} OK`);
  if (warmupFail.length > 0) {
    for (const f of warmupFail) {
      console.log(`  FAIL: ${f.name} (${f.path}) — ${f.error || 'HTTP ' + f.status}`);
    }
  }

  warmupResults.sort((a, b) => b.duration - a.duration);
  console.log('\nSlowest endpoints (warm-up, single request):');
  for (const r of warmupResults.slice(0, 10)) {
    console.log(`  ${r.duration}ms — ${r.name} (${(r.size / 1024).toFixed(0)}KB)`);
  }
  console.log('');

  // Concurrency levels
  const levels = [
    { concurrency: 5, total: 100 },
    { concurrency: 10, total: 200 },
    { concurrency: 20, total: 400 },
    { concurrency: 30, total: 600 },
    { concurrency: 50, total: 500 },
  ];

  console.log('=== CONCURRENCY TESTS ===');
  console.log('Concurrency | Requests | RPS    | Avg(ms) | P50    | P95    | P99    | Max    | Errors | Mem(MB)');
  console.log('------------|----------|--------|---------|--------|--------|--------|--------|--------|--------');

  const allResults = [];
  for (const level of levels) {
    const result = await runConcurrencyLevel(level.concurrency, level.total);
    allResults.push(result);
    console.log(
      `${String(result.concurrency).padStart(11)} | ` +
      `${String(result.totalRequests).padStart(8)} | ` +
      `${String(result.rps).padStart(6)} | ` +
      `${String(result.avg).padStart(7)} | ` +
      `${String(result.p50).padStart(6)} | ` +
      `${String(result.p95).padStart(6)} | ` +
      `${String(result.p99).padStart(6)} | ` +
      `${String(result.max).padStart(6)} | ` +
      `${String(result.errCount).padStart(6)} | ` +
      `${result.memBefore}->${result.memAfter}`
    );
    // Brief pause between levels
    await new Promise(r => setTimeout(r, 2000));
  }

  // Top-10 slowest endpoints across all tests
  console.log('\n=== TOP-10 SLOWEST ENDPOINTS (avg across all tests) ===');
  const merged = {};
  for (const res of allResults) {
    for (const [name, stats] of Object.entries(res.perEndpoint)) {
      if (!merged[name]) merged[name] = { durations: [], errors: 0, sizes: [] };
      merged[name].durations.push(...stats.durations);
      merged[name].errors += stats.errors;
      merged[name].sizes.push(...stats.sizes);
    }
  }
  const sorted = Object.entries(merged).map(([name, stats]) => ({
    name,
    avg: Math.round(stats.durations.reduce((s, d) => s + d, 0) / stats.durations.length),
    max: Math.max(...stats.durations),
    p95: stats.durations.sort((a, b) => a - b)[Math.floor(stats.durations.length * 0.95)],
    errors: stats.errors,
    count: stats.durations.length,
    avgSize: Math.round(stats.sizes.reduce((s, d) => s + d, 0) / stats.sizes.length / 1024),
  })).sort((a, b) => b.avg - a.avg);

  for (const ep of sorted.slice(0, 10)) {
    console.log(`  ${ep.avg}ms avg | ${ep.p95}ms p95 | ${ep.max}ms max | ${ep.errors} err | ${ep.avgSize}KB | ${ep.name} (${ep.count} req)`);
  }

  // Endpoints with errors
  const withErrors = sorted.filter(ep => ep.errors > 0);
  if (withErrors.length > 0) {
    console.log('\n=== ENDPOINTS WITH ERRORS ===');
    for (const ep of withErrors) {
      console.log(`  ${ep.name}: ${ep.errors}/${ep.count} errors (${(ep.errors / ep.count * 100).toFixed(1)}%)`);
    }
  }

  // Summary
  console.log('\n=== SUMMARY ===');
  const first = allResults[0];
  const last = allResults[allResults.length - 1];
  console.log(`Server handles ${first.rps} req/s at concurrency=${first.concurrency}`);
  console.log(`Server handles ${last.rps} req/s at concurrency=${last.concurrency}`);
  console.log(`Memory: ${first.memBefore}MB -> ${last.memAfter}MB (delta: ${last.memAfter - first.memBefore}MB)`);
  console.log(`Total errors: ${allResults.reduce((s, r) => s + r.errCount, 0)}/${allResults.reduce((s, r) => s + r.totalRequests, 0)}`);
  console.log(`Total data transferred: ${allResults.reduce((s, r) => s + parseFloat(r.totalSizeMB), 0).toFixed(1)}MB`);

  const maxRps = Math.max(...allResults.map(r => parseFloat(r.rps)));
  console.log(`Peak throughput: ${maxRps} req/s`);

  const errorRate = allResults.reduce((s, r) => s + r.errCount, 0) / allResults.reduce((s, r) => s + r.totalRequests, 0);
  const lastP95 = last.p95;
  console.log('');
  if (errorRate < 0.01 && lastP95 < 2000) {
    console.log('VERDICT: Server handles load well. No critical bottlenecks found.');
  } else if (errorRate < 0.05 && lastP95 < 5000) {
    console.log('VERDICT: Server handles moderate load but shows strain under high concurrency.');
  } else {
    console.log('VERDICT: Server struggles under load. Optimization needed.');
  }
}

main().catch(console.error);
