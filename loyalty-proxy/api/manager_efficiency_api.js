/**
 * Manager Efficiency API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
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

const fsp = require('fs').promises;
const path = require('path');
const { maskPhone, fileExists } = require('../utils/file_helpers');
const { requireAuth } = require('../utils/session_middleware');
const db = require('../utils/db');

// Feature flags
const USE_DB_SHIFTS = process.env.USE_DB_SHIFTS === 'true';
const USE_DB_RECOUNT = process.env.USE_DB_RECOUNT === 'true';
const USE_DB_EFFICIENCY = process.env.USE_DB_EFFICIENCY === 'true';

// Directories
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const SHOPS_DIR = `${DATA_DIR}/shops`;
const SHIFT_REPORTS_DIR = `${DATA_DIR}/shift-reports`;
const RECOUNT_REPORTS_DIR = `${DATA_DIR}/recount-reports`;
const SHIFT_HANDOVER_DIR = `${DATA_DIR}/shift-handover-reports`;
const ATTENDANCE_DIR = `${DATA_DIR}/attendance`;
const REVIEWS_DIR = `${DATA_DIR}/reviews`;
const RKO_DIR = `${DATA_DIR}/rko`;
const COFFEE_MACHINE_REPORTS_DIR = `${DATA_DIR}/coffee-machine-reports`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const SHOP_MANAGERS_FILE = `${DATA_DIR}/shop-managers.json`;

/** Month range helper: '2026-02' → { start: '2026-02-01', end: '2026-03-01' } */
function getMonthRange(month) {
  const [year, mon] = month.split('-').map(Number);
  const start = `${month}-01`;
  const nextMon = mon === 12 ? 1 : mon + 1;
  const nextYear = mon === 12 ? year + 1 : year;
  const end = `${nextYear}-${String(nextMon).padStart(2, '0')}-01`;
  return { start, end };
}


/**
 * Load JSON file safely
 */
async function loadJsonFile(filePath) {
  try {
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
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
async function getAllShops() {
  const shops = [];
  try {
    if (!(await fileExists(SHOPS_DIR))) return shops;

    const files = await fsp.readdir(SHOPS_DIR);
    for (const file of files) {
      if (file.startsWith('shop_') && file.endsWith('.json')) {
        const shop = await loadJsonFile(path.join(SHOPS_DIR, file));
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
async function getManagerByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[^\d]/g, '');

    // Load shop-managers.json to get managedShopIds
    const shopManagersData = await loadJsonFile(SHOP_MANAGERS_FILE);
    if (!shopManagersData) {
      console.log('shop-managers.json not found');
      return null;
    }

    // Check if user is a manager in shop-managers.json
    const managerEntry = shopManagersData.managers?.find(m => {
      const mPhone = (m.phone || '').replace(/[^\d]/g, '');
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
async function loadReportsForMonth(dir, month, dateField = 'date') {
  const reports = [];
  try {
    if (!(await fileExists(dir))) return reports;

    const files = await fsp.readdir(dir);
    for (const file of files) {
      if (!file.endsWith('.json')) continue;

      // Check if filename contains the month (e.g., 2026-02-01.json)
      if (file.startsWith(month)) {
        const data = await loadJsonFile(path.join(dir, file));
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
      const data = await loadJsonFile(path.join(dir, file));
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
async function loadPenaltiesForMonth(month) {
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${month}.json`);
  const data = await loadJsonFile(filePath);
  return Array.isArray(data) ? data : [];
}

/**
 * Load shift reports for month from PostgreSQL
 */
async function loadShiftReportsDB(month) {
  const result = await db.query(
    'SELECT shop_address, employee_name, status, rating FROM shift_reports WHERE date LIKE $1',
    [month + '%']
  );
  return result.rows.map(r => ({
    shopAddress: r.shop_address,
    employeeName: r.employee_name,
    status: r.status,
    rating: r.rating,
    adminRating: r.rating,
  }));
}

/**
 * Load recount reports for month from PostgreSQL
 */
async function loadRecountReportsDB(month) {
  const result = await db.query(
    'SELECT shop_address, employee_name, status, admin_rating FROM recount_reports WHERE date LIKE $1',
    [month + '%']
  );
  return result.rows.map(r => ({
    shopAddress: r.shop_address,
    employeeName: r.employee_name,
    status: r.status,
    adminRating: r.admin_rating,
    rating: r.admin_rating,
  }));
}

/**
 * Load shift handover reports for month from PostgreSQL
 */
async function loadHandoverReportsDB(month) {
  const result = await db.query(
    'SELECT shop_address, employee_name, status, rating FROM shift_handover_reports WHERE date LIKE $1',
    [month + '%']
  );
  return result.rows.map(r => ({
    shopAddress: r.shop_address,
    employeeName: r.employee_name,
    status: r.status,
    rating: r.rating,
    adminRating: r.rating,
  }));
}

/**
 * Load efficiency penalties for month from PostgreSQL
 */
async function loadPenaltiesDB(month) {
  const [year, monthNum] = month.split('-').map(Number);
  const start = `${month}-01`;
  const end = `${year}-${String(monthNum + 1).padStart(2, '0')}-01`;
  const result = await db.query(
    'SELECT shop_address, entity_name, employee_name, points, category FROM efficiency_penalties WHERE date >= $1::date AND date < $2::date',
    [start, end]
  );
  return result.rows.map(r => ({
    shopAddress: r.shop_address || '',
    entityName: r.entity_name || r.employee_name || '',
    employeeName: r.employee_name || '',
    points: parseFloat(r.points) || 0,
    penaltyCategory: r.category || '',
  }));
}

/**
 * Load points settings
 */
async function loadPointsSettings() {
  const [shift, recount, handover, attendance, reviews, rko, coffeeMachine, referrals] = await Promise.all([
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'shift_points_settings.json')),
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'recount_points_settings.json')),
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'shift_handover_points_settings.json')),
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'attendance_points_settings.json')),
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'reviews_points_settings.json')),
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'rko_points_settings.json')),
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'coffee_machine_points_settings.json')),
    loadJsonFile(path.join(POINTS_SETTINGS_DIR, 'referrals.json')),
  ]);
  return {
    shift: shift || {},
    recount: recount || {},
    handover: handover || {},
    attendance: attendance || {},
    reviews: reviews || {},
    rko: rko || {},
    coffeeMachine: coffeeMachine || { submittedPoints: 1.0, notSubmittedPoints: -3.0 },
    referrals: referrals || { basePoints: 1 },
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
async function calculateManagerEfficiency(phone, month) {
  console.log(`\n========== Calculating manager efficiency ==========`);
  console.log(`Phone: ${maskPhone(phone)}, Month: ${month}`);

  // Find manager
  const manager = await getManagerByPhone(phone);
  if (!manager) {
    console.log(`Manager not found for phone: ${maskPhone(phone)}`);
    return null;
  }

  const managedShopIds = manager.managedShopIds || [];
  if (managedShopIds.length === 0) {
    console.log(`Manager ${maskPhone(phone)} has no managed shops`);
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
  const allShops = await getAllShops();
  const managedShops = allShops.filter(s => managedShopIds.includes(s.id));
  const validAddresses = new Set(managedShops.map(s => s.address));

  console.log(`Valid shop addresses: ${[...validAddresses].join(', ')}`);

  // Load settings
  const settings = await loadPointsSettings();

  // Create efficiency records from all sources
  const allRecords = [];

  // Helper: check if status means "approved/confirmed"
  const isApproved = (status) => status === 'confirmed' || status === 'approved';
  // Helper: check if status means "rejected/failed"
  const isRejected = (status) => status === 'failed' || status === 'rejected';

  // 1. Load shift reports
  let shiftReports;
  if (USE_DB_SHIFTS) {
    try { shiftReports = await loadShiftReportsDB(month); }
    catch (e) { console.error('DB error loading shift reports, falling back to files:', e.message); }
  }
  if (!shiftReports) shiftReports = await loadReportsForMonth(SHIFT_REPORTS_DIR, month, 'handoverDate');
  console.log(`Loaded ${shiftReports.length} shift reports`);
  for (const report of shiftReports) {
    if (!validAddresses.has(report.shopAddress)) continue;

    let points = 0;
    // Note: report uses 'rating' field, not 'adminRating'
    const rating = report.adminRating || report.rating;
    if (isApproved(report.status) && rating) {
      points = calculateRatingPoints(rating, settings.shift);
    } else if (isRejected(report.status)) {
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
  let recountReports;
  if (USE_DB_RECOUNT) {
    try { recountReports = await loadRecountReportsDB(month); }
    catch (e) { console.error('DB error loading recount reports, falling back to files:', e.message); }
  }
  if (!recountReports) recountReports = await loadReportsForMonth(RECOUNT_REPORTS_DIR, month, 'recountDate');
  console.log(`Loaded ${recountReports.length} recount reports`);
  for (const report of recountReports) {
    if (!validAddresses.has(report.shopAddress)) continue;

    let points = 0;
    const rating = report.adminRating || report.rating;
    if (isApproved(report.status) && rating) {
      points = calculateRatingPoints(rating, settings.recount);
    } else if (isRejected(report.status)) {
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
  let handoverReports;
  if (USE_DB_SHIFTS) {
    try { handoverReports = await loadHandoverReportsDB(month); }
    catch (e) { console.error('DB error loading handover reports, falling back to files:', e.message); }
  }
  if (!handoverReports) handoverReports = await loadReportsForMonth(SHIFT_HANDOVER_DIR, month, 'handoverDate');
  console.log(`Loaded ${handoverReports.length} handover reports`);
  for (const report of handoverReports) {
    if (!validAddresses.has(report.shopAddress)) continue;

    let points = 0;
    const rating = report.adminRating || report.rating;
    if (isApproved(report.status) && rating) {
      points = calculateRatingPoints(rating, settings.handover);
    } else if (isRejected(report.status)) {
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
  let penalties;
  if (USE_DB_EFFICIENCY) {
    try { penalties = await loadPenaltiesDB(month); }
    catch (e) { console.error('DB error loading penalties, falling back to files:', e.message); }
  }
  if (!penalties) penalties = await loadPenaltiesForMonth(month);
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

    // Route specific penalty categories to their own buckets
    const pCat = penalty.penaltyCategory || penalty.category || '';
    let effCategory;
    if (pCat === 'envelope_missed_penalty') {
      effCategory = 'envelope';
    } else if (pCat === 'product_question_penalty' || pCat === 'product_question_bonus') {
      effCategory = 'product_search';
    } else if (pCat === 'missed_order') {
      effCategory = 'order';
    } else {
      effCategory = 'penalty';
    }

    allRecords.push({
      shopAddress,
      employeeName: penalty.entityName || penalty.employeeName || '',
      category: effCategory,
      points: penalty.points || 0,
      status: 'penalty'
    });
  }

  // 5. Load attendance records (filtered by shop_address)
  const validAddressesArray = [...validAddresses];
  const { start: mStart, end: mEnd } = getMonthRange(month);
  try {
    if (USE_DB_EFFICIENCY) {
      const attRes = await db.query(
        'SELECT shop_address, is_on_time FROM attendance WHERE shop_address = ANY($1) AND created_at >= $2::timestamptz AND created_at < $3::timestamptz',
        [validAddressesArray, mStart, mEnd]
      );
      const attSettings = settings.attendance;
      for (const row of attRes.rows) {
        const pts = row.is_on_time ? (attSettings.onTimePoints || 1) : (attSettings.latePoints || -1);
        allRecords.push({ shopAddress: row.shop_address, employeeName: '', category: 'attendance', points: pts });
      }
      console.log(`Loaded ${attRes.rows.length} attendance records from DB`);
    } else {
      if (await fileExists(ATTENDANCE_DIR)) {
        const files = await fsp.readdir(ATTENDANCE_DIR);
        const attSettings = settings.attendance;
        let count = 0;
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          try {
            const content = await fsp.readFile(path.join(ATTENDANCE_DIR, file), 'utf8');
            const rec = JSON.parse(content);
            const recDate = rec.timestamp || rec.createdAt || '';
            if (!recDate.startsWith(month)) continue;
            const shopAddr = rec.shopAddress || '';
            if (!validAddresses.has(shopAddr)) continue;
            const pts = rec.isOnTime ? (attSettings.onTimePoints || 1) : (attSettings.latePoints || -1);
            allRecords.push({ shopAddress: shopAddr, employeeName: rec.employeeName || '', category: 'attendance', points: pts });
            count++;
          } catch (e) { /* skip */ }
        }
        console.log(`Loaded ${count} attendance records from files`);
      }
    }
  } catch (e) {
    console.error('Error loading attendance for manager:', e.message);
  }

  // 6. Load reviews (filtered by shop_address)
  try {
    if (USE_DB_EFFICIENCY) {
      const revRes = await db.query(
        'SELECT shop_address, review_type FROM reviews WHERE shop_address = ANY($1) AND created_at >= $2::timestamptz AND created_at < $3::timestamptz',
        [validAddressesArray, mStart, mEnd]
      );
      const revSettings = settings.reviews;
      for (const row of revRes.rows) {
        const pts = row.review_type === 'positive' ? (revSettings.positivePoints || 1) : (revSettings.negativePoints || -1);
        allRecords.push({ shopAddress: row.shop_address, employeeName: '', category: 'review', points: pts });
      }
      console.log(`Loaded ${revRes.rows.length} review records from DB`);
    } else {
      if (await fileExists(REVIEWS_DIR)) {
        const files = await fsp.readdir(REVIEWS_DIR);
        const revSettings = settings.reviews;
        let count = 0;
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          try {
            const content = await fsp.readFile(path.join(REVIEWS_DIR, file), 'utf8');
            const rec = JSON.parse(content);
            if (!(rec.createdAt || '').startsWith(month)) continue;
            const shopAddr = rec.shopAddress || '';
            if (!validAddresses.has(shopAddr)) continue;
            const pts = rec.reviewType === 'positive' ? (revSettings.positivePoints || 1) : (revSettings.negativePoints || -1);
            allRecords.push({ shopAddress: shopAddr, employeeName: '', category: 'review', points: pts });
            count++;
          } catch (e) { /* skip */ }
        }
        console.log(`Loaded ${count} review records from files`);
      }
    }
  } catch (e) {
    console.error('Error loading reviews for manager:', e.message);
  }

  // 7. Load RKO reports (filtered by shop_address)
  try {
    if (USE_DB_EFFICIENCY) {
      const rkoRes = await db.query(
        'SELECT shop_address FROM rko_reports WHERE shop_address = ANY($1) AND date >= $2::date AND date < $3::date',
        [validAddressesArray, mStart, mEnd]
      );
      const rkoSettings = settings.rko;
      for (const row of rkoRes.rows) {
        const pts = rkoSettings.hasRkoPoints || 1;
        allRecords.push({ shopAddress: row.shop_address, employeeName: '', category: 'rko', points: pts });
      }
      console.log(`Loaded ${rkoRes.rows.length} RKO records from DB`);
    } else {
      if (await fileExists(RKO_DIR)) {
        const files = await fsp.readdir(RKO_DIR);
        const rkoSettings = settings.rko;
        let count = 0;
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          try {
            const content = await fsp.readFile(path.join(RKO_DIR, file), 'utf8');
            const rec = JSON.parse(content);
            if (!(rec.date || '').startsWith(month)) continue;
            const shopAddr = rec.shopAddress || '';
            if (!validAddresses.has(shopAddr)) continue;
            const pts = rkoSettings.hasRkoPoints || 1;
            allRecords.push({ shopAddress: shopAddr, employeeName: '', category: 'rko', points: pts });
            count++;
          } catch (e) { /* skip */ }
        }
        console.log(`Loaded ${count} RKO records from files`);
      }
    }
  } catch (e) {
    console.error('Error loading RKO for manager:', e.message);
  }

  // 8. Load coffee machine reports (filtered by shop_address)
  try {
    if (USE_DB_EFFICIENCY) {
      const cmRes = await db.query(
        "SELECT shop_address FROM coffee_machine_reports WHERE shop_address = ANY($1) AND date >= $2::date AND date < $3::date AND status = 'confirmed'",
        [validAddressesArray, mStart, mEnd]
      );
      const cmSettings = settings.coffeeMachine;
      for (const row of cmRes.rows) {
        allRecords.push({ shopAddress: row.shop_address, employeeName: '', category: 'coffee_machine', points: cmSettings.submittedPoints || 1 });
      }
      console.log(`Loaded ${cmRes.rows.length} coffee machine records from DB`);
    } else {
      if (await fileExists(COFFEE_MACHINE_REPORTS_DIR)) {
        const files = await fsp.readdir(COFFEE_MACHINE_REPORTS_DIR);
        const cmSettings = settings.coffeeMachine;
        let count = 0;
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          try {
            const content = await fsp.readFile(path.join(COFFEE_MACHINE_REPORTS_DIR, file), 'utf8');
            const rec = JSON.parse(content);
            if (rec.status !== 'confirmed') continue;
            if (!(rec.date || rec.createdAt || '').startsWith(month)) continue;
            const shopAddr = rec.shopAddress || '';
            if (!validAddresses.has(shopAddr)) continue;
            allRecords.push({ shopAddress: shopAddr, employeeName: rec.employeeName || '', category: 'coffee_machine', points: cmSettings.submittedPoints || 1 });
            count++;
          } catch (e) { /* skip */ }
        }
        console.log(`Loaded ${count} coffee machine records from files`);
      }
    }
  } catch (e) {
    console.error('Error loading coffee machine for manager:', e.message);
  }

  // 9. Load referral points (clients invited by employees of managed shops)
  try {
    if (USE_DB_EFFICIENCY) {
      const refSettings = settings.referrals;
      const basePoints = refSettings.basePoints !== undefined ? refSettings.basePoints : 1;
      // Join employees with clients on referred_by = referral_code::text
      const refRes = await db.query(
        `SELECT e.shop_address, COUNT(*) AS cnt
         FROM employees e
         INNER JOIN clients c ON c.referred_by = e.referral_code::text
         WHERE e.shop_address = ANY($1)
           AND e.referral_code IS NOT NULL
           AND e.referral_code > 0
           AND c.created_at >= $2::timestamptz
           AND c.created_at < $3::timestamptz
         GROUP BY e.shop_address`,
        [validAddressesArray, mStart, mEnd]
      );
      for (const row of refRes.rows) {
        const pts = parseInt(row.cnt, 10) * basePoints;
        allRecords.push({ shopAddress: row.shop_address, employeeName: '', category: 'referral', points: pts });
      }
      console.log(`Loaded ${refRes.rows.length} referral shop groups from DB`);
    }
    // File mode skipped: loading all clients for aggregate referral view is expensive
  } catch (e) {
    console.error('Error loading referrals for manager:', e.message);
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
    tasksPoints: 0,
    attendancePoints: 0,
    reviewsPoints: 0,
    rkoPoints: 0,
    coffeeMachinePoints: 0,
    envelopePoints: 0,
    productSearchPoints: 0,
    orderPoints: 0,
    referralPoints: 0,
  };

  for (const record of allRecords) {
    switch (record.category) {
      case 'shift':          categoryBreakdown.shiftPoints += record.points; break;
      case 'recount':        categoryBreakdown.recountPoints += record.points; break;
      case 'handover':       categoryBreakdown.shiftHandoverPoints += record.points; break;
      case 'task':           categoryBreakdown.tasksPoints += record.points; break;
      case 'attendance':     categoryBreakdown.attendancePoints += record.points; break;
      case 'review':         categoryBreakdown.reviewsPoints += record.points; break;
      case 'rko':            categoryBreakdown.rkoPoints += record.points; break;
      case 'coffee_machine': categoryBreakdown.coffeeMachinePoints += record.points; break;
      case 'envelope':       categoryBreakdown.envelopePoints += record.points; break;
      case 'product_search': categoryBreakdown.productSearchPoints += record.points; break;
      case 'order':          categoryBreakdown.orderPoints += record.points; break;
      case 'referral':       categoryBreakdown.referralPoints += record.points; break;
    }
  }

  // Format shop breakdown for response
  const formattedShopBreakdown = shopBreakdown.map(shop => {
    const managedShop = managedShops.find(s => s.address === shop.shopAddress);
    return {
      shopId: managedShop?.id || shop.shopAddress, // fallback to address so Flutter matching works
      shopName: managedShop?.name || shop.shopAddress,
      shopAddress: shop.shopAddress,
      totalPoints: Math.round(shop.totalPoints * 10) / 10,
      earnedPoints: Math.round(shop.earnedPoints * 10) / 10,
      lostPoints: Math.round(shop.lostPoints * 10) / 10,
      recordsCount: shop.recordsCount,
      percentage: 0 // Can be calculated if needed
    };
  });

  // Sort by total points (descending)
  formattedShopBreakdown.sort((a, b) => b.totalPoints - a.totalPoints);

  // ============ ВАРИАНТ 2: Средний балл за отчёт ============
  // Формула: efficiency% = ((avgPoints - minPoints) / (maxPoints - minPoints)) × 100
  // Где avgPoints = totalPoints / количество_отчётов

  // Подсчитываем количество обработанных отчётов (с баллами != 0)
  const processedRecords = allRecords.filter(r => r.points !== 0);
  const totalRecordsCount = processedRecords.length;

  // Получаем границы баллов из настроек (усреднённые по категориям)
  const avgMinPoints = (
    (settings.shift?.minPoints || -5) +
    (settings.recount?.minPoints || -5) +
    (settings.handover?.minPoints || -5)
  ) / 3;

  const avgMaxPoints = (
    (settings.shift?.maxPoints || 5) +
    (settings.recount?.maxPoints || 5) +
    (settings.handover?.maxPoints || 5)
  ) / 3;

  // Эффективность магазинов: средний балл за отчёт, нормализованный
  let shopEfficiencyPercentage = 0;
  if (totalRecordsCount > 0 && avgMaxPoints !== avgMinPoints) {
    const avgPointsPerRecord = totalPoints / totalRecordsCount;
    // Нормализация: (value - min) / (max - min) * 100
    shopEfficiencyPercentage = ((avgPointsPerRecord - avgMinPoints) / (avgMaxPoints - avgMinPoints)) * 100;
    // Ограничиваем 0-100%
    shopEfficiencyPercentage = Math.max(0, Math.min(100, shopEfficiencyPercentage));
  }

  // Эффективность отчётов: по категориям (shift, recount, handover)
  // Считаем отдельно для каждой категории и усредняем
  const categoryEfficiencies = [];

  // Shift efficiency
  const shiftRecords = allRecords.filter(r => r.category === 'shift' && r.points !== 0);
  if (shiftRecords.length > 0) {
    const shiftAvg = categoryBreakdown.shiftPoints / shiftRecords.length;
    const shiftMin = settings.shift?.minPoints || -5;
    const shiftMax = settings.shift?.maxPoints || 5;
    const shiftEff = ((shiftAvg - shiftMin) / (shiftMax - shiftMin)) * 100;
    categoryEfficiencies.push(Math.max(0, Math.min(100, shiftEff)));
  }

  // Recount efficiency
  const recountRecords = allRecords.filter(r => r.category === 'recount' && r.points !== 0);
  if (recountRecords.length > 0) {
    const recountAvg = categoryBreakdown.recountPoints / recountRecords.length;
    const recountMin = settings.recount?.minPoints || -5;
    const recountMax = settings.recount?.maxPoints || 5;
    const recountEff = ((recountAvg - recountMin) / (recountMax - recountMin)) * 100;
    categoryEfficiencies.push(Math.max(0, Math.min(100, recountEff)));
  }

  // Handover efficiency
  const handoverRecords = allRecords.filter(r => r.category === 'handover' && r.points !== 0);
  if (handoverRecords.length > 0) {
    const handoverAvg = categoryBreakdown.shiftHandoverPoints / handoverRecords.length;
    const handoverMin = settings.handover?.minPoints || -5;
    const handoverMax = settings.handover?.maxPoints || 5;
    const handoverEff = ((handoverAvg - handoverMin) / (handoverMax - handoverMin)) * 100;
    categoryEfficiencies.push(Math.max(0, Math.min(100, handoverEff)));
  }

  // Среднее по категориям (или 0 если нет данных)
  const reviewEfficiencyPercentage = categoryEfficiencies.length > 0
    ? categoryEfficiencies.reduce((a, b) => a + b, 0) / categoryEfficiencies.length
    : 0;

  // Общая эффективность = среднее от магазинов и отчётов
  const totalPercentage = (shopEfficiencyPercentage + reviewEfficiencyPercentage) / 2;

  console.log(`\nResults (Вариант 2 - средний балл):`);
  console.log(`  Total records: ${totalRecordsCount}`);
  console.log(`  Total earned: ${totalEarned}`);
  console.log(`  Total lost: ${totalLost}`);
  console.log(`  Total points: ${totalPoints}`);
  console.log(`  Avg points/record: ${totalRecordsCount > 0 ? (totalPoints / totalRecordsCount).toFixed(2) : 0}`);
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
      shiftPoints:          Math.round(categoryBreakdown.shiftPoints * 10) / 10,
      recountPoints:        Math.round(categoryBreakdown.recountPoints * 10) / 10,
      shiftHandoverPoints:  Math.round(categoryBreakdown.shiftHandoverPoints * 10) / 10,
      tasksPoints:          Math.round(categoryBreakdown.tasksPoints * 10) / 10,
      attendancePoints:     Math.round(categoryBreakdown.attendancePoints * 10) / 10,
      reviewsPoints:        Math.round(categoryBreakdown.reviewsPoints * 10) / 10,
      rkoPoints:            Math.round(categoryBreakdown.rkoPoints * 10) / 10,
      coffeeMachinePoints:  Math.round(categoryBreakdown.coffeeMachinePoints * 10) / 10,
      envelopePoints:       Math.round(categoryBreakdown.envelopePoints * 10) / 10,
      productSearchPoints:  Math.round(categoryBreakdown.productSearchPoints * 10) / 10,
      orderPoints:          Math.round(categoryBreakdown.orderPoints * 10) / 10,
      referralPoints:       Math.round(categoryBreakdown.referralPoints * 10) / 10,
    }
  };
}

/**
 * Setup Manager Efficiency API endpoints
 */
function setupManagerEfficiencyAPI(app) {
  // GET /api/manager-efficiency - Get manager efficiency for a month
  app.get('/api/manager-efficiency', requireAuth, async (req, res) => {
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

      console.log(`Calculating manager efficiency for ${maskPhone(phone)}, month: ${targetMonth}`);

      const efficiency = await calculateManagerEfficiency(phone, targetMonth);

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

  // GET /api/manager-efficiency/team-task-penalties - штрафы команды за задачи за месяц
  app.get('/api/manager-efficiency/team-task-penalties', requireAuth, async (req, res) => {
    try {
      const { month } = req.query;
      const managerPhone = (req.session?.userPhone || req.session?.phone || '').replace(/\D/g, '');

      if (!managerPhone) {
        return res.status(400).json({ success: false, error: 'Manager phone not in session' });
      }

      const targetMonth = month || (() => {
        const now = new Date();
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      })();

      const { start, end } = getMonthRange(targetMonth);

      // 1. Load shop_managers to find this manager's employee list
      let shopManagersData = [];
      try {
        const content = await fsp.readFile(SHOP_MANAGERS_FILE, 'utf8');
        shopManagersData = JSON.parse(content);
      } catch (e) {
        return res.json({ success: true, data: { month: targetMonth, totalCount: 0, totalPoints: 0, employees: [] } });
      }

      const managerEntry = shopManagersData.find(m =>
        (m.phone || m.managerPhone || '').replace(/\D/g, '') === managerPhone
      );

      if (!managerEntry || !Array.isArray(managerEntry.employees) || managerEntry.employees.length === 0) {
        return res.json({ success: true, data: { month: targetMonth, totalCount: 0, totalPoints: 0, employees: [] } });
      }

      const employeePhones = managerEntry.employees.map(p => p.replace(/\D/g, ''));

      // 2. Get entity_ids for these employees from DB
      const empResult = await db.query(
        `SELECT id FROM employees WHERE phone = ANY($1)`,
        [employeePhones]
      );

      if (!empResult.rows || empResult.rows.length === 0) {
        return res.json({ success: true, data: { month: targetMonth, totalCount: 0, totalPoints: 0, employees: [] } });
      }

      const entityIds = empResult.rows.map(r => r.id);

      // 3. Query task penalties grouped by employee
      const penResult = await db.query(
        `SELECT entity_id, entity_name,
                COUNT(*)::int AS count,
                SUM(points)::int AS total_points
         FROM efficiency_penalties
         WHERE entity_id = ANY($1)
           AND category IN ('regular_task_penalty', 'recurring_task_penalty')
           AND date >= $2 AND date < $3
         GROUP BY entity_id, entity_name
         ORDER BY total_points ASC`,
        [entityIds, start, end]
      );

      const employees = (penResult.rows || []).map(r => ({
        entityId: r.entity_id,
        name: r.entity_name,
        count: r.count,
        totalPoints: r.total_points,
      }));

      const totalCount = employees.reduce((s, e) => s + e.count, 0);
      const totalPoints = employees.reduce((s, e) => s + e.totalPoints, 0);

      res.json({
        success: true,
        data: { month: targetMonth, totalCount, totalPoints, employees },
      });
    } catch (error) {
      console.error('Error fetching team task penalties:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('   Manager Efficiency API loaded');
}

module.exports = { setupManagerEfficiencyAPI };
