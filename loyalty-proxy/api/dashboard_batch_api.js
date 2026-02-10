/**
 * Dashboard Batch API
 * Объединяет множественные запросы MainMenuPage в один batch-запрос
 *
 * Вместо ~30 отдельных HTTP запросов при загрузке главного меню,
 * Flutter может сделать один GET /api/dashboard/counters
 */

const fsp = require('fs').promises;
const path = require('path');
const { maskPhone } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

async function countJsonFiles(dirPath, filterFn) {
  let count = 0;
  try {
    if (!await fileExists(dirPath)) return 0;
    const files = (await fsp.readdir(dirPath)).filter(f => f.endsWith('.json'));
    if (!filterFn) return files.length;

    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(dirPath, file), 'utf8');
        const data = JSON.parse(content);
        if (filterFn(data)) count++;
      } catch (e) { /* skip */ }
    }
  } catch (e) { /* skip */ }
  return count;
}

async function countInSubdirs(dirPath, filterFn) {
  let count = 0;
  try {
    if (!await fileExists(dirPath)) return 0;
    const dirs = await fsp.readdir(dirPath);
    for (const dir of dirs) {
      const subPath = path.join(dirPath, dir);
      const stat = await fsp.stat(subPath);
      if (stat.isDirectory()) {
        count += await countJsonFiles(subPath, filterFn);
      }
    }
  } catch (e) { /* skip */ }
  return count;
}

function setupDashboardBatchAPI(app) {
  /**
   * GET /api/dashboard/counters?phone={phone}&employeeId={id}
   * Возвращает все счётчики для бейджей главного меню одним запросом
   */
  app.get('/api/dashboard/counters', async (req, res) => {
    try {
      const { phone, employeeId, employeeName } = req.query;
      console.log(`📊 GET /api/dashboard/counters phone=${maskPhone(phone)}`);
      const startTime = Date.now();

      // Параллельно загружаем все счётчики
      const [
        pendingShiftReports,
        pendingRecountReports,
        pendingHandoverReports,
        unconfirmedWithdrawals,
        unconfirmedEnvelopes,
        pendingOrders,
        unreadReviews,
        activeTaskAssignments,
      ] = await Promise.all([
        // Pending shift reports (status = 'pending' or 'review')
        countInSubdirs(`${DATA_DIR}/shift-reports`, d => d.status === 'pending' || d.status === 'review'),
        // Pending recount reports
        countInSubdirs(`${DATA_DIR}/recount-reports`, d => d.status === 'pending' || d.status === 'review'),
        // Pending handover reports
        countJsonFiles(`${DATA_DIR}/shift-handovers`, d => d.status === 'pending' || d.status === 'review'),
        // Unconfirmed withdrawals
        countJsonFiles(`${DATA_DIR}/withdrawals`, d => d.status !== 'confirmed'),
        // Unconfirmed envelopes
        countJsonFiles(`${DATA_DIR}/envelope-reports`, d => d.status === 'pending' || d.status === 'review'),
        // Pending orders
        countJsonFiles(`${DATA_DIR}/orders`, d => d.status === 'pending'),
        // Unread reviews
        countJsonFiles(`${DATA_DIR}/reviews`, d => !d.isRead),
        // Active task assignments for employee
        employeeId
          ? countJsonFiles(`${DATA_DIR}/task-assignments`, d =>
              (d.assigneeId === employeeId || d.assigneePhone === phone) &&
              d.status === 'pending')
          : Promise.resolve(0),
      ]);

      const elapsed = Date.now() - startTime;
      console.log(`  ✅ Dashboard counters за ${elapsed}ms`);

      res.json({
        success: true,
        counters: {
          pendingShiftReports,
          pendingRecountReports,
          pendingHandoverReports,
          unconfirmedWithdrawals,
          unconfirmedEnvelopes,
          pendingOrders,
          unreadReviews,
          activeTaskAssignments,
          // Суммарный счётчик для бейджа "Отчёты"
          totalPendingReports: pendingShiftReports + pendingRecountReports + pendingHandoverReports + unconfirmedWithdrawals + unconfirmedEnvelopes,
        },
        loadTimeMs: elapsed,
      });
    } catch (error) {
      console.error('❌ Dashboard counters error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Dashboard Batch API initialized');
}

module.exports = { setupDashboardBatchAPI };
