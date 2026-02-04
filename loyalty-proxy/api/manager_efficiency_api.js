/**
 * Manager Efficiency API
 *
 * Эффективность управляющего (admin) состоит из двух компонентов:
 * - Эффективность магазинов (50%) — агрегация баллов по shopAddress
 * - Эффективность отчётов (50%) — баллы за проверку отчётов + задачи
 *
 * Использует тот же подход что и Flutter клиент (efficiency_data_service.dart):
 * - Загружает все отчёты через те же источники
 * - Фильтрует по managedShopIds (адресам)
 * - Агрегирует по магазинам
 */

const fs = require('fs');
const path = require('path');

// Directories
const SHOPS_DIR = '/var/www/shops';
const SHIFT_REPORTS_DIR = '/var/www/shift-reports';
const RECOUNT_REPORTS_DIR = '/var/www/recount-reports';
const SHIFT_HANDOVER_DIR = '/var/www/shift-handover-reports';
const ATTENDANCE_DIR = '/var/www/attendance';
const EFFICIENCY_PENALTIES_DIR = '/var/www/efficiency-penalties';
const POINTS_SETTINGS_DIR = '/var/www/points-settings';
const SHOP_MANAGERS_FILE = '/var/www/shop-managers.json';

// Import efficiency calculation settings
const efficiencyCalc = require('../efficiency_calc.js');

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
 * Get manager data by phone (with managedShopIds from shop-managers.json)
 */
function getManagerByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[\s+]/g, '');

    // Load shop-managers.json to get managedShopIds
    const shopManagersData = loadJsonFile(SHOP_MANAGERS_FILE);
    if (!shopManagersData) {
      console.log('shop-managers.json not found');
      return null;
    }

    // Check if user is a manager in shop-managers.json
    const managerEntry = shopManagersData.managers?.find(m => {
      const mPhone = (m.phone || '').replace(/[\s+]/g, '');
      return mPhone === normalizedPhone;
    });

    if (managerEntry) {
      return {
        phone: normalizedPhone,
        name: managerEntry.name,
        managedShopIds: managerEntry.managedShops || [],
        employees: managerEntry.employees || []
      };
    }

    return null;
  } catch (e) {
    console.error('Error finding manager by phone:', e.message);
  }
  return null;
}

/**
 * Load reports from directory for a specific month
 * Handles both single-object files and array files
 */
function loadReportsForMonth(dir, month, dateField = 'date') {
  const reports = [];
  try {
    if (!fs.existsSync(dir)) return reports;

    const files = fs.readdirSync(dir);
    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      // Check if filename contains the month (e.g., 2026-02-01.json)
      if (file.startsWith(month)) {
        const data = loadJsonFile(path.join(dir, file));
        if (!data) continue;

        // Handle array of reports (shift-reports, shift-handover-reports)
        if (Array.isArray(data)) {
          for (const report of data) {
            reports.push(report);
          }
        } else {
          reports.push(data);
        }
        continue;
      }

      // For files not named by date, check content
      const data = loadJsonFile(path.join(dir, file));
      if (!data) continue;

      // Handle array of reports
      if (Array.isArray(data)) {
        for (const report of data) {
          const reportDate = report[dateField] || report.createdAt || report.handoverDate || report.recountDate;
          if (reportDate && reportDate.startsWith(month)) {
            reports.push(report);
          }
        }
      } else {
        const reportDate = data[dateField] || data.createdAt || data.handoverDate || data.recountDate;
        if (reportDate && reportDate.startsWith(month)) {
          reports.push(data);
        }
      }
    }
  } catch (e) {
    console.error(`Error loading reports from ${dir}:`, e.message);
  }
  return reports;
}

/**
 * Load penalties for month
 */
function loadPenaltiesForMonth(month) {
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${month}.json`);
  const data = loadJsonFile(filePath);
  return Array.isArray(data) ? data : [];
}

/**
 * Load points settings
 */
function loadPointsSettings() {
  return {
    shift: loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'shift_points_settings.json')) || {},
    recount: loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'recount_points_settings.json')) || {},
    handover: loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'shift_handover_points_settings.json')) || {},
    attendance: loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'attendance_points_settings.json')) || {}
  };
}

/**
 * Calculate points based on rating (interpolation)
 */
function calculateRatingPoints(rating, settings) {
  if (!settings || !rating) return 0;

  const minRating = settings.minRating || 1;
  const maxRating = settings.maxRating || 10;
  const minPoints = settings.minPoints || -5;
  const maxPoints = settings.maxPoints || 5;
  const zeroThreshold = settings.zeroThreshold || 5;

  if (rating <= minRating) return minPoints;
  if (rating >= maxRating) return maxPoints;

  if (rating <= zeroThreshold) {
    const range = zeroThreshold - minRating;
    if (range === 0) return 0;
    return minPoints + (0 - minPoints) * ((rating - minRating) / range);
  } else {
    const range = maxRating - zeroThreshold;
    if (range === 0) return maxPoints;
    return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
  }
}

/**
 * Aggregate efficiency data by shop address
 */
function aggregateByShop(records, validAddresses) {
  const byShop = {};

  for (const record of records) {
    const shopAddress = record.shopAddress;
    if (!shopAddress || !validAddresses.has(shopAddress)) continue;

    if (!byShop[shopAddress]) {
      byShop[shopAddress] = {
        shopAddress,
        totalPoints: 0,
        earnedPoints: 0,
        lostPoints: 0,
        recordsCount: 0
      };
    }

    byShop[shopAddress].totalPoints += record.points || 0;
    byShop[shopAddress].recordsCount++;

    if ((record.points || 0) >= 0) {
      byShop[shopAddress].earnedPoints += record.points || 0;
    } else {
      byShop[shopAddress].lostPoints += Math.abs(record.points || 0);
    }
  }

  return Object.values(byShop);
}

/**
 * Calculate manager efficiency
 */
function calculateManagerEfficiency(phone, month) {
  console.log(`\n========== Calculating manager efficiency ==========`);
  console.log(`Phone: ${phone}, Month: ${month}`);

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

  console.log(`Manager has ${managedShopIds.length} managed shops`);

  // Get all shops and filter by managedShopIds
  const allShops = getAllShops();
  const managedShops = allShops.filter(s => managedShopIds.includes(s.id));
  const validAddresses = new Set(managedShops.map(s => s.address));

  console.log(`Valid shop addresses: ${[...validAddresses].join(', ')}`);

  // Load settings
  const settings = loadPointsSettings();

  // Create efficiency records from all sources
  const allRecords = [];

  // 1. Load shift reports
  const shiftReports = loadReportsForMonth(SHIFT_REPORTS_DIR, month, 'handoverDate');
  console.log(`Loaded ${shiftReports.length} shift reports`);
  for (const report of shiftReports) {
    if (!validAddresses.has(report.shopAddress)) continue;

    let points = 0;
    // Note: report uses 'rating' field, not 'adminRating'
    const rating = report.adminRating || report.rating;
    if (report.status === 'confirmed' && rating) {
      points = calculateRatingPoints(rating, settings.shift);
    } else if (report.status === 'failed' || report.status === 'rejected') {
      points = settings.shift?.minPoints || -5;
    }

    allRecords.push({
      shopAddress: report.shopAddress,
      employeeName: report.employeeName || '',
      category: 'shift',
      points,
      status: report.status
    });
  }

  // 2. Load recount reports
  const recountReports = loadReportsForMonth(RECOUNT_REPORTS_DIR, month, 'recountDate');
  console.log(`Loaded ${recountReports.length} recount reports`);
  for (const report of recountReports) {
    if (!validAddresses.has(report.shopAddress)) continue;

    let points = 0;
    const rating = report.adminRating || report.rating;
    if (report.status === 'confirmed' && rating) {
      points = calculateRatingPoints(rating, settings.recount);
    } else if (report.status === 'failed' || report.status === 'rejected') {
      points = settings.recount?.minPoints || -5;
    }

    allRecords.push({
      shopAddress: report.shopAddress,
      employeeName: report.employeeName || '',
      category: 'recount',
      points,
      status: report.status
    });
  }

  // 3. Load shift handover reports
  const handoverReports = loadReportsForMonth(SHIFT_HANDOVER_DIR, month, 'handoverDate');
  console.log(`Loaded ${handoverReports.length} handover reports`);
  for (const report of handoverReports) {
    if (!validAddresses.has(report.shopAddress)) continue;

    let points = 0;
    const rating = report.adminRating || report.rating;
    if (report.status === 'confirmed' && rating) {
      points = calculateRatingPoints(rating, settings.handover);
    } else if (report.status === 'failed' || report.status === 'rejected') {
      points = settings.handover?.minPoints || -5;
    }

    allRecords.push({
      shopAddress: report.shopAddress,
      employeeName: report.employeeName || '',
      category: 'handover',
      points,
      status: report.status
    });
  }

  // 4. Load penalties
  const penalties = loadPenaltiesForMonth(month);
  console.log(`Loaded ${penalties.length} penalties`);
  for (const penalty of penalties) {
    // Map penalty shopAddress to valid addresses if needed
    let shopAddress = penalty.shopAddress || '';

    // Some penalties might have different address format, try to match
    if (!validAddresses.has(shopAddress)) {
      // Try partial match
      for (const validAddr of validAddresses) {
        if (validAddr.includes(shopAddress) || shopAddress.includes(validAddr)) {
          shopAddress = validAddr;
          break;
        }
      }
    }

    if (!validAddresses.has(shopAddress)) continue;

    allRecords.push({
      shopAddress,
      employeeName: penalty.entityName || penalty.employeeName || '',
      category: 'penalty',
      points: penalty.points || 0,
      status: 'penalty'
    });
  }

  console.log(`Total records after filtering: ${allRecords.length}`);

  // Aggregate by shop
  const shopBreakdown = aggregateByShop(allRecords, validAddresses);

  // Calculate totals
  let totalEarned = 0;
  let totalLost = 0;

  for (const shop of shopBreakdown) {
    totalEarned += shop.earnedPoints;
    totalLost += shop.lostPoints;
  }

  const totalPoints = totalEarned - totalLost;

  // Calculate category breakdown
  const categoryBreakdown = {
    shiftPoints: 0,
    recountPoints: 0,
    shiftHandoverPoints: 0,
    tasksPoints: 0
  };

  for (const record of allRecords) {
    switch (record.category) {
      case 'shift':
        categoryBreakdown.shiftPoints += record.points;
        break;
      case 'recount':
        categoryBreakdown.recountPoints += record.points;
        break;
      case 'handover':
        categoryBreakdown.shiftHandoverPoints += record.points;
        break;
      case 'task':
        categoryBreakdown.tasksPoints += record.points;
        break;
    }
  }

  // Format shop breakdown for response
  const formattedShopBreakdown = shopBreakdown.map(shop => {
    const managedShop = managedShops.find(s => s.address === shop.shopAddress);
    return {
      shopId: managedShop?.id || '',
      shopName: managedShop?.name || shop.shopAddress,
      totalPoints: Math.round(shop.totalPoints * 10) / 10,
      earnedPoints: Math.round(shop.earnedPoints * 10) / 10,
      lostPoints: Math.round(shop.lostPoints * 10) / 10,
      recordsCount: shop.recordsCount,
      percentage: 0 // Can be calculated if needed
    };
  });

  // Sort by total points (descending)
  formattedShopBreakdown.sort((a, b) => b.totalPoints - a.totalPoints);

  // Calculate percentages
  // Эффективность = earned / (earned + lost) * 100
  // Если нет записей - 0%
  const shopEfficiencyPercentage = (totalEarned + totalLost) > 0
    ? (totalEarned / (totalEarned + totalLost)) * 100
    : 0;

  // Для отчётов - аналогичная формула по категориям
  const categoryTotal = Math.abs(categoryBreakdown.shiftPoints) +
                        Math.abs(categoryBreakdown.recountPoints) +
                        Math.abs(categoryBreakdown.shiftHandoverPoints) +
                        Math.abs(categoryBreakdown.tasksPoints);
  const categoryEarned = Math.max(0, categoryBreakdown.shiftPoints) +
                         Math.max(0, categoryBreakdown.recountPoints) +
                         Math.max(0, categoryBreakdown.shiftHandoverPoints) +
                         Math.max(0, categoryBreakdown.tasksPoints);
  const reviewEfficiencyPercentage = categoryTotal > 0
    ? (categoryEarned / categoryTotal) * 100
    : 0;

  // Общая эффективность = среднее
  const totalPercentage = (shopEfficiencyPercentage + reviewEfficiencyPercentage) / 2;

  console.log(`\nResults:`);
  console.log(`  Total earned: ${totalEarned}`);
  console.log(`  Total lost: ${totalLost}`);
  console.log(`  Total points: ${totalPoints}`);
  console.log(`  Shops: ${formattedShopBreakdown.length}`);
  console.log(`  Shop efficiency: ${shopEfficiencyPercentage.toFixed(1)}%`);
  console.log(`  Review efficiency: ${reviewEfficiencyPercentage.toFixed(1)}%`);
  console.log(`  Total efficiency: ${totalPercentage.toFixed(1)}%`);

  return {
    totalPercentage: Math.round(totalPercentage * 10) / 10,
    shopEfficiencyPercentage: Math.round(shopEfficiencyPercentage * 10) / 10,
    reviewEfficiencyPercentage: Math.round(reviewEfficiencyPercentage * 10) / 10,
    totalEarned: Math.round(totalEarned * 10) / 10,
    totalLost: Math.round(totalLost * 10) / 10,
    totalPoints: Math.round(totalPoints * 10) / 10,
    shopBreakdown: formattedShopBreakdown,
    categoryBreakdown: {
      shiftPoints: Math.round(categoryBreakdown.shiftPoints * 10) / 10,
      recountPoints: Math.round(categoryBreakdown.recountPoints * 10) / 10,
      shiftHandoverPoints: Math.round(categoryBreakdown.shiftHandoverPoints * 10) / 10,
      tasksPoints: Math.round(categoryBreakdown.tasksPoints * 10) / 10
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
