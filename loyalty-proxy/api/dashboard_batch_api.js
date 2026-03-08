/**
 * Dashboard Batch API
 * Объединяет множественные запросы MainMenuPage в один batch-запрос
 *
 * Вместо ~30 отдельных HTTP запросов при загрузке главного меню,
 * Flutter может сделать один GET /api/dashboard/counters
 */

const fsp = require('fs').promises;
const path = require('path');
const { maskPhone, fileExists } = require('../utils/file_helpers');
const { requireEmployee } = require('../utils/session_middleware');
const db = require('../utils/db');
const USE_DB_ORDERS = process.env.USE_DB_ORDERS === 'true';
const USE_DB_TASKS = process.env.USE_DB_TASKS === 'true';
const USE_DB_RECURRING_TASKS = process.env.USE_DB_RECURRING_TASKS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

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

// Count pending task assignments (regular + recurring) for a specific employee
async function countActiveTasksForEmployee(employeeId, phone) {
  let regularCount = 0;
  let recurringCount = 0;
  const normalizedPhone = phone ? phone.replace(/[^\d]/g, '') : null;

  // === Regular task assignments ===
  if (USE_DB_TASKS) {
    try {
      const result = await db.query(
        'SELECT COUNT(*)::int AS cnt FROM task_assignments WHERE (assignee_id = $1 OR assignee_phone = $2) AND status = $3',
        [employeeId || '', phone || '', 'pending']
      );
      regularCount = result.rows[0]?.cnt || 0;
    } catch (e) { /* fallback to JSON */ }
  }
  if (regularCount === 0 && !USE_DB_TASKS) {
    try {
      const dir = `${DATA_DIR}/task-assignments`;
      if (await fileExists(dir)) {
        const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const data = JSON.parse(await fsp.readFile(path.join(dir, file), 'utf8'));
            const assignments = data.assignments || data || [];
            if (Array.isArray(assignments)) {
              regularCount += assignments.filter(a =>
                (a.assigneeId === employeeId || a.assigneePhone === phone) &&
                a.status === 'pending'
              ).length;
            }
          } catch (e) { /* skip */ }
        }
      }
    } catch (e) { /* skip */ }
  }

  // === Recurring task instances ===
  if (USE_DB_RECURRING_TASKS) {
    try {
      const result = await db.query(
        'SELECT COUNT(*)::int AS cnt FROM recurring_task_instances WHERE assignee_phone = $1 AND status = $2',
        [phone || '', 'pending']
      );
      recurringCount = result.rows[0]?.cnt || 0;
    } catch (e) { /* fallback to JSON */ }
  }
  if (recurringCount === 0 && !USE_DB_RECURRING_TASKS) {
    try {
      const dir = `${DATA_DIR}/recurring-task-instances`;
      if (await fileExists(dir)) {
        const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
        for (const file of files) {
          try {
            const data = JSON.parse(await fsp.readFile(path.join(dir, file), 'utf8'));
            const instances = Array.isArray(data) ? data : (data.instances || []);
            recurringCount += instances.filter(i => {
              const iPhone = i.assigneePhone ? i.assigneePhone.replace(/[^\d]/g, '') : '';
              return (iPhone === normalizedPhone) && i.status === 'pending';
            }).length;
          } catch (e) { /* skip */ }
        }
      }
    } catch (e) { /* skip */ }
  }

  return regularCount + recurringCount;
}

function setupDashboardBatchAPI(app) {
  /**
   * GET /api/dashboard/counters?phone={phone}&employeeId={id}
   * Возвращает все счётчики для бейджей главного меню одним запросом
   */
  app.get('/api/dashboard/counters', requireEmployee, async (req, res) => {
    try {
      const { phone, employeeId, employeeName } = req.query;
      console.log(`📊 GET /api/dashboard/counters phone=${maskPhone(phone)}`);
      const startTime = Date.now();

      // Count shift-transfer unread for this employee from the single JSON file
      async function countShiftTransferUnread(empId) {
        if (!empId) return 0;
        try {
          const filePath = `${DATA_DIR}/shift-transfers.json`;
          if (!await fileExists(filePath)) return 0;
          const raw = await fsp.readFile(filePath, 'utf8');
          const requests = JSON.parse(raw);
          if (!Array.isArray(requests)) return 0;
          return requests.filter(r => {
            if (r.fromEmployeeId === empId) return false;
            if (r.toEmployeeId && r.toEmployeeId !== empId) return false;
            if (r.status !== 'pending' && r.status !== 'has_acceptances') return false;
            if (r.isReadByRecipient) return false;
            const acceptedBy = r.acceptedBy || [];
            if (acceptedBy.some(a => a.employeeId === empId)) return false;
            const rejectedBy = r.rejectedBy || [];
            if (rejectedBy.some(a => a.employeeId === empId)) return false;
            return true;
          }).length;
        } catch (e) { return 0; }
      }

      // Count unviewed report notifications
      async function countReportNotifications() {
        try {
          const dir = `${DATA_DIR}/report-notifications`;
          if (!await fileExists(dir)) return 0;
          const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
          let count = 0;
          for (const file of files) {
            try {
              const raw = await fsp.readFile(path.join(dir, file), 'utf8');
              const notifs = JSON.parse(raw);
              if (Array.isArray(notifs)) {
                count += notifs.filter(n => !n.viewedAt).length;
              }
            } catch (e) { /* skip */ }
          }
          return count;
        } catch (e) { return 0; }
      }

      // Параллельно загружаем все счётчики
      const [
        pendingShiftReports,
        pendingRecountReports,
        pendingHandoverReports,
        unconfirmedWithdrawals,
        unconfirmedEnvelopes,
        pendingOrders,
        wholesalePendingOrders,
        unreadReviews,
        activeTaskAssignments,
        coffeeMachineReports,
        unreadProductQuestions,
        shiftTransferRequests,
        jobApplications,
        reportNotifications,
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
        USE_DB_ORDERS
          ? db.query('SELECT COUNT(*)::int AS cnt FROM orders WHERE status = $1', ['pending']).then(r => r.rows[0]?.cnt || 0).catch(() => 0)
          : countJsonFiles(`${DATA_DIR}/orders`, d => d.status === 'pending'),
        // Wholesale pending orders
        USE_DB_ORDERS
          ? db.query('SELECT COUNT(*)::int AS cnt FROM orders WHERE status = $1 AND is_wholesale_order = true', ['pending']).then(r => r.rows[0]?.cnt || 0).catch(() => 0)
          : countJsonFiles(`${DATA_DIR}/orders`, d => d.status === 'pending' && d.isWholesaleOrder === true),
        // Unread reviews
        countJsonFiles(`${DATA_DIR}/reviews`, d => !d.isRead),
        // Active task assignments for employee (regular + recurring)
        countActiveTasksForEmployee(employeeId, phone),
        // Coffee machine reports pending (per-shop subdirs)
        countInSubdirs(`${DATA_DIR}/coffee-machine-reports`, d => d.status === 'pending' || d.status === 'review'),
        // Unanswered product questions (hasUnreadFromClient or unanswered shop)
        countJsonFiles(`${DATA_DIR}/product-questions`, d =>
          d.hasUnreadFromClient || (d.shops && d.shops.some(s => !s.isAnswered))),
        // Shift transfer unread count for this employee
        countShiftTransferUnread(employeeId),
        // Pending job applications (status 'new')
        countJsonFiles(`${DATA_DIR}/job-applications`, d => d.status === 'new' || !d.status),
        // Unviewed report notifications
        countReportNotifications(),
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
          wholesalePendingOrders,
          unreadReviews,
          activeTaskAssignments,
          // 5 counters that were previously missing (showed 0 on startup)
          coffeeMachineReports,
          unreadProductQuestions,
          shiftTransferRequests,
          jobApplications,
          reportNotifications,
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
