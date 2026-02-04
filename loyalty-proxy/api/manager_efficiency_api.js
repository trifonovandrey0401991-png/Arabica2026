/**
 * Manager Efficiency API
 *
 * Эффективность управляющего (admin) состоит из двух компонентов:
 * - Эффективность магазинов (50%) — агрегация баллов сотрудников по managedShopIds
 * - Эффективность отчётов (50%) — баллы за проверку отчётов + задачи
 */

const fs = require('fs');
const path = require('path');

// Directories
const SHOPS_DIR = '/var/www/shops';
const EMPLOYEES_DIR = '/var/www/employees';
const SHIFT_REPORTS_DIR = '/var/www/shift_handover_reports';
const RECOUNT_REPORTS_DIR = '/var/www/recount_reports';
const SHIFT_HANDOVER_DIR = '/var/www/shift_handover_reports';
const TASKS_DIR = '/var/www/tasks';
const RECURRING_TASKS_DIR = '/var/www/recurring-tasks';
const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const EFFICIENCY_DIR = '/var/www/efficiency';

// Default manager category settings
const DEFAULT_MANAGER_CATEGORY_SETTINGS = {
  confirmedPoints: 1.0,
  rejectedPenalty: -2.0
};

/**
 * Load JSON file safely
 */
function loadJsonFile(filePath) {
  try {
    if (fs.existsSync(filePath)) {
      const content = fs.readFileSync(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error(`Error loading ${filePath}:`, e.message);
  }
  return null;
}

/**
 * Get manager points settings
 */
function getManagerPointsSettings() {
  const settingsPath = path.join(POINTS_SETTINGS_DIR, 'manager_points_settings.json');
  const settings = loadJsonFile(settingsPath);

  if (!settings) {
    return {
      shiftSettings: { ...DEFAULT_MANAGER_CATEGORY_SETTINGS },
      recountSettings: { ...DEFAULT_MANAGER_CATEGORY_SETTINGS },
      shiftHandoverSettings: { ...DEFAULT_MANAGER_CATEGORY_SETTINGS }
    };
  }

  return settings;
}

/**
 * Get all shops
 */
function getAllShops() {
  const shops = [];
  try {
    if (!fs.existsSync(SHOPS_DIR)) return shops;

    const files = fs.readdirSync(SHOPS_DIR);
    for (const file of files) {
      if (file.startsWith('shop_') && file.endsWith('.json')) {
        const shop = loadJsonFile(path.join(SHOPS_DIR, file));
        if (shop) {
          shops.push(shop);
        }
      }
    }
  } catch (e) {
    console.error('Error loading shops:', e.message);
  }
  return shops;
}

/**
 * Get employees for a specific shop
 */
function getEmployeesForShop(shopId) {
  const employees = [];
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return employees;

    const files = fs.readdirSync(EMPLOYEES_DIR);
    for (const file of files) {
      if (file.endsWith('.json')) {
        const emp = loadJsonFile(path.join(EMPLOYEES_DIR, file));
        if (emp && emp.shopId === shopId && emp.role === 'employee') {
          employees.push(emp);
        }
      }
    }
  } catch (e) {
    console.error('Error loading employees for shop:', e.message);
  }
  return employees;
}

/**
 * Get manager data by phone
 */
function getManagerByPhone(phone) {
  try {
    if (!fs.existsSync(EMPLOYEES_DIR)) return null;

    const normalizedPhone = phone.replace(/[\s+]/g, '');
    const files = fs.readdirSync(EMPLOYEES_DIR);

    for (const file of files) {
      if (file.endsWith('.json')) {
        const emp = loadJsonFile(path.join(EMPLOYEES_DIR, file));
        if (emp) {
          const empPhone = (emp.phone || '').replace(/[\s+]/g, '');
          if (empPhone === normalizedPhone && emp.role === 'admin') {
            return emp;
          }
        }
      }
    }
  } catch (e) {
    console.error('Error finding manager by phone:', e.message);
  }
  return null;
}

/**
 * Load efficiency data for an employee
 */
function getEmployeeEfficiency(employeePhone, month) {
  const efficiencyPath = path.join(EFFICIENCY_DIR, `${month}.json`);
  const efficiencyData = loadJsonFile(efficiencyPath);

  if (!efficiencyData) return 0;

  const normalizedPhone = employeePhone.replace(/[\s+]/g, '');

  // Find employee data
  const empData = efficiencyData.employees?.find(e => {
    const ePhone = (e.phone || '').replace(/[\s+]/g, '');
    return ePhone === normalizedPhone;
  });

  return empData?.totalPoints || 0;
}

/**
 * Count reports by status for a manager's shops
 */
function countReportsByStatus(reportsDir, shopIds, month, categoryName) {
  let confirmed = 0;
  let rejected = 0;
  let failed = 0;
  let total = 0;

  try {
    if (!fs.existsSync(reportsDir)) return { confirmed, rejected, failed, total };

    const files = fs.readdirSync(reportsDir);

    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      const report = loadJsonFile(path.join(reportsDir, file));
      if (!report) continue;

      // Check if report belongs to one of manager's shops
      if (!shopIds.includes(report.shopId)) continue;

      // Check if report is from the specified month
      const reportDate = report.date || report.createdAt;
      if (!reportDate || !reportDate.startsWith(month)) continue;

      total++;

      // Count by status
      const status = report.status || 'pending';
      if (status === 'confirmed' || status === 'approved') {
        confirmed++;
      } else if (status === 'rejected') {
        rejected++;
      } else if (status === 'failed') {
        failed++;
      }
    }
  } catch (e) {
    console.error(`Error counting ${categoryName} reports:`, e.message);
  }

  return { confirmed, rejected, failed, total };
}

/**
 * Calculate review efficiency points
 */
function calculateReviewPoints(reportCounts, settings) {
  const { confirmed, rejected, failed, total } = reportCounts;
  const { confirmedPoints, rejectedPenalty } = settings;

  let points = 0;

  // Points for confirmed reports
  points += confirmed * confirmedPoints;

  // Penalty for rejected and failed reports
  points += (rejected + failed) * rejectedPenalty;

  return points;
}

/**
 * Count manager's tasks for the month
 */
function countManagerTasks(managerPhone, shopIds, month) {
  let completed = 0;
  let total = 0;

  try {
    // Regular tasks
    if (fs.existsSync(TASKS_DIR)) {
      const files = fs.readdirSync(TASKS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        const task = loadJsonFile(path.join(TASKS_DIR, file));
        if (!task) continue;

        // Check if task belongs to one of manager's shops
        if (!shopIds.includes(task.shopId)) continue;

        // Check if task is from the specified month
        const taskDate = task.dueDate || task.createdAt;
        if (!taskDate || !taskDate.startsWith(month)) continue;

        total++;
        if (task.status === 'completed') {
          completed++;
        }
      }
    }

    // Recurring tasks
    if (fs.existsSync(RECURRING_TASKS_DIR)) {
      const files = fs.readdirSync(RECURRING_TASKS_DIR);
      for (const file of files) {
        if (!file.endsWith('.json')) continue;

        const task = loadJsonFile(path.join(RECURRING_TASKS_DIR, file));
        if (!task) continue;

        // Check if task belongs to one of manager's shops
        if (!shopIds.includes(task.shopId)) continue;

        // Count completions for the month
        const completions = task.completions || [];
        for (const completion of completions) {
          if (completion.date?.startsWith(month)) {
            total++;
            if (completion.status === 'completed') {
              completed++;
            }
          }
        }
      }
    }
  } catch (e) {
    console.error('Error counting manager tasks:', e.message);
  }

  return { completed, total };
}

/**
 * Calculate manager efficiency
 */
function calculateManagerEfficiency(phone, month) {
  // Find manager
  const manager = getManagerByPhone(phone);
  if (!manager) {
    console.log(`Manager not found for phone: ${phone}`);
    return null;
  }

  const managedShopIds = manager.managedShopIds || [];
  if (managedShopIds.length === 0) {
    console.log(`Manager ${phone} has no managed shops`);
    return {
      totalPercentage: 0,
      shopEfficiencyPercentage: 0,
      reviewEfficiencyPercentage: 0,
      shopBreakdown: [],
      categoryBreakdown: {
        shiftPoints: 0,
        recountPoints: 0,
        shiftHandoverPoints: 0,
        tasksPoints: 0
      }
    };
  }

  // Load settings
  const pointsSettings = getManagerPointsSettings();

  // Get all shops info
  const allShops = getAllShops();
  const managedShops = allShops.filter(s => managedShopIds.includes(s.id));

  // ===== PART 1: Shop Efficiency (50%) =====
  let totalShopPoints = 0;
  let totalTheoreticalMax = 0;
  const shopBreakdown = [];

  for (const shop of managedShops) {
    const employees = getEmployeesForShop(shop.id);
    let shopPoints = 0;

    for (const emp of employees) {
      const empPoints = getEmployeeEfficiency(emp.phone, month);
      shopPoints += empPoints;
    }

    // Теоретический максимум = кол-во сотрудников * 100 (или другая формула)
    // Используем простую формулу: каждый сотрудник может заработать max 50 баллов
    const theoreticalMax = employees.length * 50;

    totalShopPoints += shopPoints;
    totalTheoreticalMax += theoreticalMax;

    const percentage = theoreticalMax > 0 ? (shopPoints / theoreticalMax) * 100 : 0;

    shopBreakdown.push({
      shopId: shop.id,
      shopName: shop.name || shop.address || `Магазин ${shop.id}`,
      totalPoints: Math.round(shopPoints * 10) / 10,
      percentage: Math.round(percentage * 10) / 10
    });
  }

  const shopEfficiencyPercentage = totalTheoreticalMax > 0
    ? (totalShopPoints / totalTheoreticalMax) * 100
    : 0;

  // ===== PART 2: Review Efficiency (50%) =====

  // Count shift reports
  const shiftCounts = countReportsByStatus(
    SHIFT_REPORTS_DIR,
    managedShopIds,
    month,
    'shift'
  );
  const shiftPoints = calculateReviewPoints(shiftCounts, pointsSettings.shiftSettings || DEFAULT_MANAGER_CATEGORY_SETTINGS);

  // Count recount reports
  const recountCounts = countReportsByStatus(
    RECOUNT_REPORTS_DIR,
    managedShopIds,
    month,
    'recount'
  );
  const recountPoints = calculateReviewPoints(recountCounts, pointsSettings.recountSettings || DEFAULT_MANAGER_CATEGORY_SETTINGS);

  // Count shift handover reports
  const shiftHandoverCounts = countReportsByStatus(
    SHIFT_HANDOVER_DIR,
    managedShopIds,
    month,
    'shiftHandover'
  );
  const shiftHandoverPoints = calculateReviewPoints(shiftHandoverCounts, pointsSettings.shiftHandoverSettings || DEFAULT_MANAGER_CATEGORY_SETTINGS);

  // Count tasks
  const tasksCounts = countManagerTasks(phone, managedShopIds, month);
  // Tasks give 1 point per completed, -1 per failed
  const tasksPoints = tasksCounts.completed - (tasksCounts.total - tasksCounts.completed);

  const totalReviewPoints = shiftPoints + recountPoints + shiftHandoverPoints + tasksPoints;

  // Теоретический максимум для отчётов:
  // confirmedPoints * количество отчётов для каждой категории
  const shiftMaxPoints = shiftCounts.total * (pointsSettings.shiftSettings?.confirmedPoints || 1);
  const recountMaxPoints = recountCounts.total * (pointsSettings.recountSettings?.confirmedPoints || 1);
  const shiftHandoverMaxPoints = shiftHandoverCounts.total * (pointsSettings.shiftHandoverSettings?.confirmedPoints || 1);
  const tasksMaxPoints = tasksCounts.total; // 1 point per task

  const totalReviewMax = shiftMaxPoints + recountMaxPoints + shiftHandoverMaxPoints + tasksMaxPoints;

  const reviewEfficiencyPercentage = totalReviewMax > 0
    ? (totalReviewPoints / totalReviewMax) * 100
    : 0;

  // ===== TOTAL EFFICIENCY =====
  // Average of shop efficiency and review efficiency (50/50)
  const totalPercentage = (shopEfficiencyPercentage + reviewEfficiencyPercentage) / 2;

  return {
    totalPercentage: Math.round(Math.max(0, totalPercentage) * 10) / 10,
    shopEfficiencyPercentage: Math.round(Math.max(0, shopEfficiencyPercentage) * 10) / 10,
    reviewEfficiencyPercentage: Math.round(Math.max(0, Math.min(100, reviewEfficiencyPercentage)) * 10) / 10,
    shopBreakdown,
    categoryBreakdown: {
      shiftPoints: Math.round(shiftPoints * 10) / 10,
      recountPoints: Math.round(recountPoints * 10) / 10,
      shiftHandoverPoints: Math.round(shiftHandoverPoints * 10) / 10,
      tasksPoints: Math.round(tasksPoints * 10) / 10
    }
  };
}

/**
 * Setup Manager Efficiency API endpoints
 */
function setupManagerEfficiencyAPI(app) {
  // GET /api/manager-efficiency - Get manager efficiency for a month
  app.get('/api/manager-efficiency', async (req, res) => {
    try {
      const { phone, month } = req.query;

      if (!phone) {
        return res.status(400).json({
          success: false,
          error: 'Missing required parameter: phone'
        });
      }

      // Default to current month if not specified
      const targetMonth = month || (() => {
        const now = new Date();
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      })();

      console.log(`Calculating manager efficiency for ${phone}, month: ${targetMonth}`);

      const efficiency = calculateManagerEfficiency(phone, targetMonth);

      if (!efficiency) {
        return res.status(404).json({
          success: false,
          error: 'Manager not found or has no managed shops'
        });
      }

      res.json({
        success: true,
        data: efficiency
      });
    } catch (error) {
      console.error('Error calculating manager efficiency:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  console.log('   Manager Efficiency API loaded');
}

module.exports = { setupManagerEfficiencyAPI };
