/**
 * Pending Reports API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const PENDING_RECOUNT_DIR = `${DATA_DIR}/pending-recount-reports`;
const PENDING_SHIFT_DIR = `${DATA_DIR}/pending-shift-reports`;
const PENDING_SHIFT_HANDOVER_FILE = `${DATA_DIR}/pending-shift-handover-reports.json`;
const SHOPS_DIR = `${DATA_DIR}/shops`;
const ATTENDANCE_DIR = `${DATA_DIR}/attendance`;
const WORK_SCHEDULE_DIR = `${DATA_DIR}/work-schedules`;
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;

// Import efficiency penalties functions
let efficiencyPenalties = null;
try {
  efficiencyPenalties = require('./efficiency_penalties_api.js');
} catch (e) {
  console.log('Note: efficiency_penalties_api not loaded yet');
}

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist (async IIFE)
(async () => {
  for (const dir of [PENDING_RECOUNT_DIR, PENDING_SHIFT_DIR]) {
    if (!(await fileExists(dir))) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// Helper function to get today's date string
function getTodayStr() {
  const now = new Date();
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

// Helper function to get yesterday's date string
function getYesterdayStr() {
  const now = new Date();
  now.setDate(now.getDate() - 1);
  return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}-${String(now.getDate()).padStart(2, '0')}`;
}

// Helper function to sanitize string for ID
function sanitizeForId(str) {
  return str.replace(/[^a-zA-Zа-яА-ЯёЁ0-9]/g, '_');
}

// Load shops from directory
async function loadShops() {
  const shops = [];
  if (await fileExists(SHOPS_DIR)) {
    const files = (await fsp.readdir(SHOPS_DIR)).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const content = await fsp.readFile(path.join(SHOPS_DIR, file), 'utf8');
        const shop = JSON.parse(content);
        if (shop && shop.address) {
          shops.push(shop);
        }
      } catch (e) {
        console.error(`Error reading shop file ${file}:`, e.message);
      }
    }
  }
  return shops;
}

// Load shift points settings
async function loadShiftPointsSettings() {
  const defaultSettings = {
    minPoints: -3,
    zeroThreshold: 7,
    maxPoints: 2
  };

  const filePath = path.join(POINTS_SETTINGS_DIR, 'shift_points_settings.json');
  if (await fileExists(filePath)) {
    try {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    } catch (e) {
      console.error('Error reading shift points settings:', e.message);
    }
  }
  return defaultSettings;
}

// Load attendance records for a specific date
async function loadAttendanceForDate(date) {
  const records = [];
  if (!(await fileExists(ATTENDANCE_DIR))) return records;

  const files = (await fsp.readdir(ATTENDANCE_DIR)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    // Check if file matches the date pattern (ends with _YYYY-MM-DD.json)
    if (!file.includes(date)) continue;

    try {
      const content = await fsp.readFile(path.join(ATTENDANCE_DIR, file), 'utf8');
      const attendance = JSON.parse(content);

      if (attendance.records && Array.isArray(attendance.records)) {
        for (const record of attendance.records) {
          records.push({
            employeeName: record.employeeName || attendance.identifier,
            shopAddress: record.shopAddress,
            timestamp: record.timestamp,
            shiftType: record.shiftType || determineShiftType(record.timestamp)
          });
        }
      } else if (attendance.employeeName && attendance.shopAddress) {
        records.push({
          employeeName: attendance.employeeName,
          shopAddress: attendance.shopAddress,
          timestamp: attendance.timestamp,
          shiftType: attendance.shiftType || determineShiftType(attendance.timestamp)
        });
      }
    } catch (e) {
      console.error(`Error reading attendance file ${file}:`, e.message);
    }
  }

  return records;
}

// Determine shift type from timestamp (morning < 14:00, evening >= 14:00)
function determineShiftType(timestamp) {
  if (!timestamp) return null;
  const hour = new Date(timestamp).getHours();
  return hour < 14 ? 'morning' : 'evening';
}

// Load work schedule for a date
// New loadWorkScheduleForDate function
async function loadWorkScheduleForDate(date) {
  const schedules = [];
  if (!(await fileExists(WORK_SCHEDULE_DIR))) return schedules;

  // Get month from date (YYYY-MM)
  const monthKey = date.substring(0, 7);
  const monthFile = path.join(WORK_SCHEDULE_DIR, monthKey + '.json');

  if (!(await fileExists(monthFile))) {
    console.log('  Work schedule file not found:', monthFile);
    return schedules;
  }

  try {
    const content = await fsp.readFile(monthFile, 'utf8');
    const data = JSON.parse(content);

    if (data.entries && Array.isArray(data.entries)) {
      // Filter entries for the specific date
      for (const entry of data.entries) {
        if (entry.date === date && entry.employeeName && entry.shopAddress) {
          schedules.push({
            employeeName: entry.employeeName,
            shopAddress: entry.shopAddress,
            date: entry.date,
            shiftType: entry.shiftType
          });
        }
      }
    }

    console.log('  Loaded', schedules.length, 'schedule entries for', date);
  } catch (e) {
    console.error('Error reading work schedule file:', e.message);
  }

  return schedules;
}

// Find employee for a shift from attendance
function findEmployeeFromAttendance(attendanceRecords, shopAddress, shiftType) {
  for (const record of attendanceRecords) {
    if (record.shopAddress === shopAddress && record.shiftType === shiftType) {
      return record.employeeName;
    }
  }
  return null;
}

// Find employee for a shift from work schedule
function findEmployeeFromSchedule(schedules, shopAddress, shiftType) {
  for (const schedule of schedules) {
    if (schedule.shopAddress === shopAddress && schedule.shiftType === shiftType && schedule.employeeName) {
      return schedule.employeeName;
    }
  }
  return null;
}

// Process unfinished shifts and create penalties
async function processUnfinishedShifts(date) {
  console.log(`📊 Processing unfinished shifts for ${date}...`);

  if (!efficiencyPenalties) {
    try {
      efficiencyPenalties = require('./efficiency_penalties_api.js');
    } catch (e) {
      console.log('❌ Cannot load efficiency_penalties_api, skipping penalties');
      return { processed: 0, penalties: 0 };
    }
  }

  // Load pending shift reports for the date
  const files = (await fsp.readdir(PENDING_SHIFT_DIR)).filter(f => f.endsWith('.json'));
  const unfinishedReports = [];

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(PENDING_SHIFT_DIR, file), 'utf8');
      const report = JSON.parse(content);

      if (report.date === date && report.status === 'pending') {
        unfinishedReports.push(report);
      }
    } catch (e) {
      console.error(`Error reading ${file}:`, e.message);
    }
  }

  if (unfinishedReports.length === 0) {
    console.log('  No unfinished shifts found');
    return { processed: 0, penalties: 0 };
  }

  console.log(`  Found ${unfinishedReports.length} unfinished shifts`);

  // Load attendance and work schedule for the date
  const attendanceRecords = await loadAttendanceForDate(date);
  const workSchedules = await loadWorkScheduleForDate(date);

  // Load shift points settings
  const settings = await loadShiftPointsSettings();
  const penaltyPoints = settings.minPoints; // -3 by default

  console.log(`  Penalty points: ${penaltyPoints}`);
  console.log(`  Attendance records: ${attendanceRecords.length}`);
  console.log(`  Work schedules: ${workSchedules.length}`);

  const penalties = [];

  for (const report of unfinishedReports) {
    // Penalty for shop
    const shopPenalty = {
      type: 'shop',
      entityId: report.shopAddress,
      entityName: report.shopAddress,
      shopAddress: report.shopAddress,
      category: 'shift_penalty',
      categoryName: 'Штраф за пересменку',
      date: report.date,
      shiftType: report.shiftType,
      shiftLabel: report.shiftLabel,
      points: penaltyPoints,
      reason: 'not_completed'
    };

    // Check if penalty already exists
    if (!(await efficiencyPenalties.penaltyExists(report.date, report.shiftType, report.shopAddress, 'shop'))) {
      await efficiencyPenalties.addPenalty(shopPenalty);
      penalties.push(shopPenalty);
      console.log(`  + Shop penalty: ${report.shopAddress} (${report.shiftLabel})`);
    }

    // Find employee
    let employee = findEmployeeFromAttendance(attendanceRecords, report.shopAddress, report.shiftType);

    if (!employee) {
      employee = findEmployeeFromSchedule(workSchedules, report.shopAddress, report.shiftType);
    }

    if (employee) {
      const employeePenalty = {
        type: 'employee',
        entityId: employee,
        entityName: employee,
        shopAddress: report.shopAddress,
        employeeName: employee,
        category: 'shift_penalty',
        categoryName: 'Штраф за пересменку',
        date: report.date,
        shiftType: report.shiftType,
        shiftLabel: report.shiftLabel,
        points: penaltyPoints,
        reason: 'not_completed'
      };

      // Check if penalty already exists
      if (!(await efficiencyPenalties.penaltyExists(report.date, report.shiftType, report.shopAddress, 'employee'))) {
        await efficiencyPenalties.addPenalty(employeePenalty);
        penalties.push(employeePenalty);
        console.log(`  + Employee penalty: ${employee} (${report.shiftLabel})`);
      }
    } else {
      console.log(`  ! No employee found for ${report.shopAddress} (${report.shiftLabel})`);
    }
  }

  console.log(`✅ Processed: ${unfinishedReports.length}, Penalties created: ${penalties.length}`);
  return { processed: unfinishedReports.length, penalties: penalties.length };
}

// Generate pending shift reports for today
async function generateDailyPendingShifts() {
  const todayStr = getTodayStr();
  console.log(`📋 Generating pending shifts for ${todayStr}...`);

  // Load shops from directory
  const shops = await loadShops();

  if (shops.length === 0) {
    console.log('❌ No shops found in /var/www/shops');
    return { generated: 0, skipped: 0 };
  }

  console.log(`📍 Found ${shops.length} shops`);

  let generated = 0;
  let skipped = 0;

  for (const shop of shops) {
    const shopKey = sanitizeForId(shop.address);

    // Generate morning shift
    const morningId = `pending_${shopKey}_${todayStr}_morning`;
    const morningFile = path.join(PENDING_SHIFT_DIR, `${morningId}.json`);

    if (!(await fileExists(morningFile))) {
      const morningReport = {
        id: morningId,
        shopAddress: shop.address,
        shiftType: 'morning',
        shiftLabel: 'Утро',
        date: todayStr,
        deadline: '10:00',
        status: 'pending',
        completedBy: null,
        createdAt: new Date().toISOString()
      };
      await fsp.writeFile(morningFile, JSON.stringify(morningReport, null, 2), 'utf8');
      generated++;
    } else {
      skipped++;
    }

    // Generate evening shift
    const eveningId = `pending_${shopKey}_${todayStr}_evening`;
    const eveningFile = path.join(PENDING_SHIFT_DIR, `${eveningId}.json`);

    if (!(await fileExists(eveningFile))) {
      const eveningReport = {
        id: eveningId,
        shopAddress: shop.address,
        shiftType: 'evening',
        shiftLabel: 'Вечер',
        date: todayStr,
        deadline: '22:00',
        status: 'pending',
        completedBy: null,
        createdAt: new Date().toISOString()
      };
      await fsp.writeFile(eveningFile, JSON.stringify(eveningReport, null, 2), 'utf8');
      generated++;
    } else {
      skipped++;
    }
  }

  console.log(`✅ Generated: ${generated}, Skipped: ${skipped}`);
  return { generated, skipped };
}

function setupPendingAPI(app) {
  // ===== PENDING RECOUNT REPORTS =====

  app.get('/api/pending-recount-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-recount-reports');
      const { shopAddress, employeeName } = req.query;
      const reports = [];

      if (await fileExists(PENDING_RECOUNT_DIR)) {
        const files = (await fsp.readdir(PENDING_RECOUNT_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(PENDING_RECOUNT_DIR, file), 'utf8');
            const report = JSON.parse(content);

            if (shopAddress && report.shopAddress !== shopAddress) continue;
            if (employeeName && report.employeeName !== employeeName) continue;

            reports.push(report);
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      reports.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
      res.json({ success: true, reports });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/pending-recount-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/pending-recount-reports:', report.shopAddress);

      if (!report.id) {
        report.id = `pending_recount_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      report.createdAt = report.createdAt || new Date().toISOString();
      report.status = report.status || 'pending';

      const filePath = path.join(PENDING_RECOUNT_DIR, `${report.id}.json`);
      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/pending-recount-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_RECOUNT_DIR, `${reportId}.json`);

      if (await fileExists(filePath)) {
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        res.json({ success: true, report });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/pending-recount-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const updates = req.body;
      const filePath = path.join(PENDING_RECOUNT_DIR, `${reportId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      const updated = { ...report, ...updates, updatedAt: new Date().toISOString() };

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, report: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/pending-recount-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_RECOUNT_DIR, `${reportId}.json`);

      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== PENDING SHIFT REPORTS =====

  // Get pending shift reports - auto-generates for today if needed
  app.get('/api/pending-shift-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-shift-reports');
      const todayStr = getTodayStr();

      // Auto-generate for today if not exists
      await generateDailyPendingShifts();

      const { shopAddress, employeeName, date } = req.query;
      const reports = [];

      if (await fileExists(PENDING_SHIFT_DIR)) {
        const files = (await fsp.readdir(PENDING_SHIFT_DIR)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const content = await fsp.readFile(path.join(PENDING_SHIFT_DIR, file), 'utf8');
            const report = JSON.parse(content);

            // Filter by date - default to today only
            if (date) {
              if (report.date !== date) continue;
            } else {
              if (report.date !== todayStr) continue;
            }

            if (shopAddress && report.shopAddress !== shopAddress) continue;
            if (employeeName && report.employeeName !== employeeName) continue;

            // Only return pending reports
            if (report.status === 'pending') {
              reports.push(report);
            }
          } catch (e) {
            console.error(`Error reading ${file}:`, e);
          }
        }
      }

      reports.sort((a, b) => {
        // Sort by shop, then by shift type (morning first)
        const shopCompare = a.shopAddress.localeCompare(b.shopAddress);
        if (shopCompare !== 0) return shopCompare;
        return a.shiftType === 'morning' ? -1 : 1;
      });

      res.json({ success: true, reports, date: todayStr });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Generate pending shifts for today (manual trigger)
  // UPDATED: Now processes penalties for yesterday before generating new shifts
  app.post('/api/pending-shift-reports/generate', async (req, res) => {
    try {
      console.log('POST /api/pending-shift-reports/generate');

      // First, process penalties for yesterday's unfinished shifts
      const yesterdayStr = getYesterdayStr();
      let penaltyResult = { processed: 0, penalties: 0 };

      try {
        penaltyResult = await processUnfinishedShifts(yesterdayStr);
      } catch (e) {
        console.error('Error processing penalties:', e.message);
      }

      // Then generate new shifts for today
      const result = await generateDailyPendingShifts();

      res.json({
        success: true,
        ...result,
        penaltiesProcessed: penaltyResult.processed,
        penaltiesCreated: penaltyResult.penalties
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // NEW: Manual endpoint to process penalties for a specific date
  app.post('/api/pending-shift-reports/process-penalties', async (req, res) => {
    try {
      const { date } = req.body;
      const targetDate = date || getYesterdayStr();

      console.log('POST /api/pending-shift-reports/process-penalties for', targetDate);

      const result = await processUnfinishedShifts(targetDate);

      res.json({
        success: true,
        date: targetDate,
        ...result
      });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/pending-shift-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/pending-shift-reports:', report.shopAddress);

      if (!report.id) {
        report.id = `pending_shift_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }

      report.createdAt = report.createdAt || new Date().toISOString();
      report.status = report.status || 'pending';

      const filePath = path.join(PENDING_SHIFT_DIR, `${report.id}.json`);
      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.get('/api/pending-shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_SHIFT_DIR, `${reportId}.json`);

      if (await fileExists(filePath)) {
        const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
        res.json({ success: true, report });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.put('/api/pending-shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const updates = req.body;
      const filePath = path.join(PENDING_SHIFT_DIR, `${reportId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      const updated = { ...report, ...updates, updatedAt: new Date().toISOString() };

      await fsp.writeFile(filePath, JSON.stringify(updated, null, 2), 'utf8');
      res.json({ success: true, report: updated });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Mark shift as completed
  app.post('/api/pending-shift-reports/:reportId/complete', async (req, res) => {
    try {
      const { reportId } = req.params;
      const { completedBy } = req.body;
      const filePath = path.join(PENDING_SHIFT_DIR, `${reportId}.json`);

      if (!(await fileExists(filePath))) {
        return res.status(404).json({ success: false, error: 'Report not found' });
      }

      const report = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      report.status = 'completed';
      report.completedBy = completedBy;
      report.completedAt = new Date().toISOString();

      await fsp.writeFile(filePath, JSON.stringify(report, null, 2), 'utf8');
      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/pending-shift-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      const filePath = path.join(PENDING_SHIFT_DIR, `${reportId}.json`);

      if (await fileExists(filePath)) {
        await fsp.unlink(filePath);
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== PENDING SHIFT HANDOVER REPORTS =====

  app.get('/api/pending-shift-handover-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-shift-handover-reports');

      let data = { reports: [] };
      if (await fileExists(PENDING_SHIFT_HANDOVER_FILE)) {
        data = JSON.parse(await fsp.readFile(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
      }

      res.json({ success: true, reports: data.reports || [] });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.post('/api/pending-shift-handover-reports', async (req, res) => {
    try {
      const report = req.body;
      console.log('POST /api/pending-shift-handover-reports');

      let data = { reports: [] };
      if (await fileExists(PENDING_SHIFT_HANDOVER_FILE)) {
        data = JSON.parse(await fsp.readFile(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
      }

      if (!report.id) {
        report.id = `pending_handover_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
      }
      report.createdAt = report.createdAt || new Date().toISOString();

      data.reports.push(report);
      await fsp.writeFile(PENDING_SHIFT_HANDOVER_FILE, JSON.stringify(data, null, 2), 'utf8');

      res.json({ success: true, report });
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  app.delete('/api/pending-shift-handover-reports/:reportId', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log('DELETE /api/pending-shift-handover-reports:', reportId);

      let data = { reports: [] };
      if (await fileExists(PENDING_SHIFT_HANDOVER_FILE)) {
        data = JSON.parse(await fsp.readFile(PENDING_SHIFT_HANDOVER_FILE, 'utf8'));
      }

      const index = data.reports.findIndex(r => r.id === reportId);
      if (index !== -1) {
        data.reports.splice(index, 1);
        await fsp.writeFile(PENDING_SHIFT_HANDOVER_FILE, JSON.stringify(data, null, 2), 'utf8');
        res.json({ success: true });
      } else {
        res.status(404).json({ success: false, error: 'Report not found' });
      }
    } catch (error) {
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Pending Reports API initialized (with penalty support)');
}

module.exports = { setupPendingAPI };
