/**
 * Efficiency Penalties API
 * Штрафы/бонусы эффективности + batch загрузка отчётов
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 * Utility functions (addPenalty, penaltyExists, loadMonthPenalties) preserved for other modules.
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const SHIFT_REPORTS_DIR = `${DATA_DIR}/shift-reports`;
const SHIFT_HANDOVER_REPORTS_DIR = `${DATA_DIR}/shift-handover-reports`;

// ===== Utility functions (used by other modules like pending_api.js) =====

function getMonthKey(date) {
  if (!date) {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  }
  return date.substring(0, 7);
}

function generateId() {
  return `penalty_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

async function loadMonthPenalties(monthKey) {
  if (!(await fileExists(EFFICIENCY_PENALTIES_DIR))) {
    await fsp.mkdir(EFFICIENCY_PENALTIES_DIR, { recursive: true });
  }
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);

  if (await fileExists(filePath)) {
    try {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    } catch (e) {
      console.error(`Error reading penalties for ${monthKey}:`, e);
      return { monthKey, penalties: [] };
    }
  }
  return { monthKey, penalties: [] };
}

async function saveMonthPenalties(monthKey, data) {
  const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
  data.updatedAt = new Date().toISOString();
  await writeJsonFile(filePath, data);
}

async function addPenalty(penalty) {
  const monthKey = getMonthKey(penalty.date);
  const data = await loadMonthPenalties(monthKey);

  if (!penalty.id) {
    penalty.id = generateId();
  }
  penalty.createdAt = new Date().toISOString();

  data.penalties.push(penalty);
  await saveMonthPenalties(monthKey, data);

  return penalty;
}

async function penaltyExists(date, shiftType, shopAddress, type) {
  const monthKey = getMonthKey(date);
  const data = await loadMonthPenalties(monthKey);

  return data.penalties.some(p =>
    p.date === date &&
    p.shiftType === shiftType &&
    p.shopAddress === shopAddress &&
    p.type === type
  );
}

// ===== Helper functions for reports-batch (from inline code) =====

async function loadShiftReportsForPeriod(startDate, endDate) {
  const reports = [];

  if (!await fileExists(SHIFT_REPORTS_DIR)) {
    return reports;
  }

  const files = (await fsp.readdir(SHIFT_REPORTS_DIR)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(SHIFT_REPORTS_DIR, file), 'utf8');
      const report = JSON.parse(content);

      // Проверяем период
      const reportDate = new Date(report.createdAt || report.timestamp);
      if (reportDate >= startDate && reportDate <= endDate) {
        reports.push(report);
      }
    } catch (e) {
      console.error(`Ошибка чтения shift report ${file}:`, e.message);
    }
  }

  return reports;
}

async function loadRecountReportsForPeriod(startDate, endDate) {
  const reports = [];
  const reportsDir = `${DATA_DIR}/recount-reports`;

  if (!await fileExists(reportsDir)) {
    return reports;
  }

  const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(reportsDir, file), 'utf8');
      const report = JSON.parse(content);

      // Проверяем период
      const reportDate = new Date(report.completedAt || report.createdAt);
      if (reportDate >= startDate && reportDate <= endDate) {
        reports.push(report);
      }
    } catch (e) {
      console.error(`Ошибка чтения recount report ${file}:`, e.message);
    }
  }

  return reports;
}

async function loadShiftHandoverReportsForPeriod(startDate, endDate) {
  const reports = [];

  if (!await fileExists(SHIFT_HANDOVER_REPORTS_DIR)) {
    return reports;
  }

  const files = (await fsp.readdir(SHIFT_HANDOVER_REPORTS_DIR)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(SHIFT_HANDOVER_REPORTS_DIR, file), 'utf8');
      const report = JSON.parse(content);

      // Проверяем период
      const reportDate = new Date(report.createdAt);
      if (reportDate >= startDate && reportDate <= endDate) {
        reports.push(report);
      }
    } catch (e) {
      console.error(`Ошибка чтения shift handover report ${file}:`, e.message);
    }
  }

  return reports;
}

async function loadAttendanceForPeriod(startDate, endDate) {
  const records = [];
  const attendanceDir = `${DATA_DIR}/attendance`;

  if (!await fileExists(attendanceDir)) {
    return records;
  }

  const files = (await fsp.readdir(attendanceDir)).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const content = await fsp.readFile(path.join(attendanceDir, file), 'utf8');
      const record = JSON.parse(content);

      // Проверяем период
      const recordDate = new Date(record.timestamp || record.createdAt);
      if (recordDate >= startDate && recordDate <= endDate) {
        records.push(record);
      }
    } catch (e) {
      console.error(`Ошибка чтения attendance record ${file}:`, e.message);
    }
  }

  return records;
}

// ===== Routes =====

function setupEfficiencyPenaltiesAPI(app) {
  /**
   * GET /api/efficiency/reports-batch
   * Batch endpoint для загрузки всех отчётов за месяц одним запросом
   */
  app.get('/api/efficiency/reports-batch', async (req, res) => {
    try {
      const { month } = req.query;

      // Валидация формата месяца
      if (!month || !month.match(/^\d{4}-\d{2}$/)) {
        return res.status(400).json({
          success: false,
          error: 'Неверный формат месяца. Используйте YYYY-MM (например 2025-01)'
        });
      }

      console.log(`📊 GET /api/efficiency/reports-batch?month=${month}`);

      // Парсим год и месяц
      const [year, monthNum] = month.split('-').map(Number);

      // Дополнительная валидация месяца
      if (monthNum < 1 || monthNum > 12) {
        return res.status(400).json({
          success: false,
          error: 'Неверный номер месяца. Используйте месяц от 01 до 12'
        });
      }

      // Создаём границы периода
      const startDate = new Date(year, monthNum - 1, 1, 0, 0, 0);
      const endDate = new Date(year, monthNum, 0, 23, 59, 59);

      console.log(`  📅 Период: ${startDate.toISOString()} - ${endDate.toISOString()}`);

      // Загружаем все типы отчётов параллельно
      const startTime = Date.now();

      const [shifts, recounts, handovers, attendance] = await Promise.all([
        loadShiftReportsForPeriod(startDate, endDate),
        loadRecountReportsForPeriod(startDate, endDate),
        loadShiftHandoverReportsForPeriod(startDate, endDate),
        loadAttendanceForPeriod(startDate, endDate),
      ]);

      const loadTime = Date.now() - startTime;

      console.log(`  ✅ Загружено за ${loadTime}ms:`);
      console.log(`     - shifts: ${shifts.length}`);
      console.log(`     - recounts: ${recounts.length}`);
      console.log(`     - handovers: ${handovers.length}`);
      console.log(`     - attendance: ${attendance.length}`);
      console.log(`     - ИТОГО: ${shifts.length + recounts.length + handovers.length + attendance.length} записей`);

      res.json({
        success: true,
        month,
        shifts,
        recounts,
        handovers,
        attendance
      });
    } catch (error) {
      console.error('❌ Ошибка загрузки batch отчётов:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  /**
   * GET /api/efficiency-penalties
   * Получить штрафы эффективности за месяц
   */
  app.get('/api/efficiency-penalties', async (req, res) => {
    try {
      const { month } = req.query;

      // Валидация формата месяца
      if (!month || !month.match(/^\d{4}-\d{2}$/)) {
        return res.status(400).json({
          success: false,
          error: 'Неверный формат месяца. Используйте YYYY-MM (например 2026-02)'
        });
      }

      console.log(`📊 GET /api/efficiency-penalties?month=${month}`);

      const penaltiesDir = `${DATA_DIR}/efficiency-penalties`;
      const penaltiesFile = path.join(penaltiesDir, `${month}.json`);

      let penalties = [];
      if (await fileExists(penaltiesFile)) {
        const content = await fsp.readFile(penaltiesFile, 'utf8');
        penalties = JSON.parse(content);
        if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
      }

      console.log(`  ✅ Загружено ${penalties.length} штрафов за ${month}`);

      res.json({
        success: true,
        month,
        penalties
      });
    } catch (error) {
      console.error('❌ Ошибка загрузки штрафов:', error);
      res.status(500).json({
        success: false,
        error: error.message
      });
    }
  });

  console.log('✅ Efficiency Penalties API initialized');
}

module.exports = { setupEfficiencyPenaltiesAPI, addPenalty, penaltyExists, loadMonthPenalties };
