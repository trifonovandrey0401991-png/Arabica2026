/**
 * Efficiency Penalties API
 * Штрафы/бонусы эффективности + batch загрузка отчётов
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 * REFACTORED: Added PostgreSQL support (2026-02-17)
 * Utility functions (addPenalty, penaltyExists, loadMonthPenalties, dbInsertPenalty) preserved for other modules.
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const USE_DB = process.env.USE_DB_EFFICIENCY === 'true';
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

  // DB dual-write
  await dbInsertPenalty(penalty);

  return penalty;
}

async function penaltyExists(date, shiftType, shopAddress, type) {
  // DB check first
  if (USE_DB) {
    try {
      const result = await db.query(
        'SELECT COUNT(*) as cnt FROM efficiency_penalties WHERE date = $1 AND shift_type = $2 AND shop_address = $3 AND type = $4',
        [date, shiftType, shopAddress, type]
      );
      if (parseInt(result.rows[0].cnt) > 0) return true;
    } catch (e) {
      console.error('DB penaltyExists error:', e.message);
    }
  }

  const monthKey = getMonthKey(date);
  const data = await loadMonthPenalties(monthKey);

  return data.penalties.some(p =>
    p.date === date &&
    p.shiftType === shiftType &&
    p.shopAddress === shopAddress &&
    p.type === type
  );
}

// ===== DB helpers (used by all 11 penalty writer modules) =====

function camelToDbPenalty(p) {
  return {
    id: p.id,
    type: p.type || 'employee',
    entity_id: p.entityId || null,
    entity_name: p.entityName || null,
    shop_address: p.shopAddress || null,
    employee_name: p.employeeName || null,
    employee_phone: p.employeePhone || null,
    employee_id: p.employeeId || null,
    category: p.category,
    category_name: p.categoryName || null,
    date: p.date || null,
    shift_type: p.shiftType || null,
    points: p.points != null ? p.points : 0,
    reason: p.reason || null,
    source_id: p.sourceId || null,
    source_type: p.sourceType || null,
    late_minutes: p.lateMinutes != null ? p.lateMinutes : null,
    task_id: p.taskId || null,
    assignment_id: p.assignmentId || null,
    created_at: p.createdAt || new Date().toISOString(),
    updated_at: new Date().toISOString()
  };
}

function dbPenaltyToCamel(row) {
  return {
    id: row.id,
    type: row.type,
    entityId: row.entity_id,
    entityName: row.entity_name,
    shopAddress: row.shop_address,
    employeeName: row.employee_name,
    employeePhone: row.employee_phone,
    employeeId: row.employee_id,
    category: row.category,
    categoryName: row.category_name,
    date: row.date,
    shiftType: row.shift_type,
    points: row.points != null ? parseFloat(row.points) : 0,
    reason: row.reason,
    sourceId: row.source_id,
    sourceType: row.source_type,
    lateMinutes: row.late_minutes,
    taskId: row.task_id,
    assignmentId: row.assignment_id,
    createdAt: row.created_at
  };
}

/**
 * DB dual-write helper — used by ALL penalty writer modules.
 * Call after JSON write to also insert into PostgreSQL.
 * Safe to call when USE_DB is false (no-op).
 */
async function dbInsertPenalty(penalty) {
  if (!USE_DB) return;
  try {
    await db.upsert('efficiency_penalties', camelToDbPenalty(penalty));
  } catch (e) {
    console.error('DB penalty insert error:', e.message);
  }
}

/**
 * DB bulk insert helper — for batch penalty writers.
 */
async function dbInsertPenalties(penalties) {
  if (!USE_DB || !penalties || penalties.length === 0) return;
  for (const p of penalties) {
    try {
      await db.upsert('efficiency_penalties', camelToDbPenalty(p));
    } catch (e) {
      console.error(`DB penalty insert error (${p.id}):`, e.message);
    }
  }
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

      let penalties = [];

      if (USE_DB) {
        // PostgreSQL path
        const [year, monthNum] = month.split('-').map(Number);
        const startDate = `${month}-01`;
        const endDate = `${year}-${String(monthNum).padStart(2, '0')}-${new Date(year, monthNum, 0).getDate()}`;
        const result = await db.query(
          'SELECT * FROM efficiency_penalties WHERE date >= $1 AND date <= $2 ORDER BY created_at',
          [startDate, endDate]
        );
        penalties = result.rows.map(dbPenaltyToCamel);
      } else {
        // File path
        const penaltiesFile = path.join(EFFICIENCY_PENALTIES_DIR, `${month}.json`);
        if (await fileExists(penaltiesFile)) {
          const content = await fsp.readFile(penaltiesFile, 'utf8');
          penalties = JSON.parse(content);
          if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
        }
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

  /**
   * GET /api/efficiency/supplementary-batch
   * Batch endpoint для загрузки дополнительных данных эффективности за месяц
   * (штрафы, задачи, отзывы, товарные вопросы, заказы, РКО)
   * Заменяет ~12 отдельных запросов MyEfficiencyPage одним
   */
  app.get('/api/efficiency/supplementary-batch', async (req, res) => {
    try {
      const { month } = req.query;

      if (!month || !month.match(/^\d{4}-\d{2}$/)) {
        return res.status(400).json({
          success: false,
          error: 'Неверный формат месяца. Используйте YYYY-MM'
        });
      }

      console.log(`📊 GET /api/efficiency/supplementary-batch?month=${month}`);
      const startTime = Date.now();

      const [year, monthNum] = month.split('-').map(Number);
      const startDate = new Date(year, monthNum - 1, 1, 0, 0, 0);
      const endDate = new Date(year, monthNum, 0, 23, 59, 59);

      const isInPeriod = (dateStr) => {
        if (!dateStr) return false;
        const d = new Date(dateStr);
        return d >= startDate && d <= endDate;
      };

      // Загружаем penalties
      let penalties = [];
      if (USE_DB) {
        const [year, monthNum] = month.split('-').map(Number);
        const startDate = `${month}-01`;
        const endDate = `${year}-${String(monthNum).padStart(2, '0')}-${new Date(year, monthNum, 0).getDate()}`;
        const result = await db.query(
          'SELECT * FROM efficiency_penalties WHERE date >= $1 AND date <= $2 ORDER BY created_at',
          [startDate, endDate]
        );
        penalties = result.rows.map(dbPenaltyToCamel);
      } else {
        const penaltiesFile = path.join(`${DATA_DIR}/efficiency-penalties`, `${month}.json`);
        if (await fileExists(penaltiesFile)) {
          try {
            const content = await fsp.readFile(penaltiesFile, 'utf8');
            penalties = JSON.parse(content);
            if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
          } catch (e) { /* skip */ }
        }
      }

      // Загружаем остальные данные параллельно
      const loadDir = async (dirPath, dateField) => {
        const results = [];
        try {
          if (!await fileExists(dirPath)) return results;
          const files = (await fsp.readdir(dirPath)).filter(f => f.endsWith('.json'));
          for (const file of files) {
            try {
              const content = await fsp.readFile(path.join(dirPath, file), 'utf8');
              const data = JSON.parse(content);
              if (isInPeriod(data[dateField])) results.push(data);
            } catch (e) { /* skip */ }
          }
        } catch (e) { /* skip */ }
        return results;
      };

      // Загрузка task-assignments: агрегатные месячные файлы (не индивидуальные)
      const loadTaskAssignments = async () => {
        const results = [];
        try {
          const filePath = path.join(`${DATA_DIR}/task-assignments`, `${month}.json`);
          if (await fileExists(filePath)) {
            const content = await fsp.readFile(filePath, 'utf8');
            const data = JSON.parse(content);
            const assignments = data.assignments || [];
            for (const a of assignments) {
              // Проверяем по reviewedAt, respondedAt или deadline
              const dateToCheck = a.reviewedAt || a.respondedAt || a.deadline;
              if (isInPeriod(dateToCheck)) results.push(a);
            }
          }
        } catch (e) { /* skip */ }
        return results;
      };

      // Загрузка RKO: единый metadata файл (не директория)
      const loadRkoMetadata = async () => {
        const results = [];
        try {
          const filePath = `${DATA_DIR}/rko-reports/rko_metadata.json`;
          if (await fileExists(filePath)) {
            const content = await fsp.readFile(filePath, 'utf8');
            const parsed = JSON.parse(content);
            // Поддержка обоих форматов: {items: [...]} и [...]
            const items = Array.isArray(parsed) ? parsed : (parsed.items || []);
            for (const item of items) {
              if (isInPeriod(item.date)) results.push(item);
            }
          }
        } catch (e) { /* skip */ }
        return results;
      };

      const [tasks, reviews, productQuestions, orders, rko] = await Promise.all([
        loadTaskAssignments(),
        loadDir(`${DATA_DIR}/reviews`, 'createdAt'),
        loadDir(`${DATA_DIR}/product-questions`, 'timestamp'),
        loadDir(`${DATA_DIR}/orders`, 'createdAt'),
        loadRkoMetadata(),
      ]);

      const elapsed = Date.now() - startTime;
      console.log(`  ✅ Supplementary batch за ${elapsed}ms: penalties=${penalties.length}, tasks=${tasks.length}, reviews=${reviews.length}`);

      res.json({
        success: true,
        month,
        penalties,
        tasks,
        reviews,
        productQuestions,
        orders,
        rko,
        loadTimeMs: elapsed,
      });
    } catch (error) {
      console.error('❌ Ошибка supplementary batch:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log(`✅ Efficiency Penalties API initialized (DB: ${USE_DB ? 'ON' : 'OFF'})`);
}

module.exports = { setupEfficiencyPenaltiesAPI, addPenalty, penaltyExists, loadMonthPenalties, dbInsertPenalty, dbInsertPenalties };
