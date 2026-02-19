/**
 * Bonus/Penalties API
 * Премии и штрафы сотрудников
 *
 * EXTRACTED from index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sanitizeId, fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const db = require('../utils/db');
const { requireAuth } = require('../utils/session_middleware');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const USE_DB = process.env.USE_DB_BONUS_PENALTIES === 'true';
const BONUS_PENALTIES_DIR = `${DATA_DIR}/bonus-penalties`;

// DB conversion helpers
function camelToDb(r) {
  return {
    id: r.id,
    employee_id: r.employeeId || null,
    employee_name: r.employeeName || null,
    type: r.type || 'bonus',
    amount: r.amount != null ? r.amount : 0,
    comment: r.comment || null,
    admin_name: r.adminName || null,
    month: r.month || null,
    created_at: r.createdAt || new Date().toISOString()
  };
}

function dbToCamel(row) {
  return {
    id: row.id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    type: row.type,
    amount: row.amount != null ? parseFloat(row.amount) : 0,
    comment: row.comment,
    adminName: row.admin_name,
    month: row.month,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null
  };
}

// Вспомогательная функция для получения месяца в формате YYYY-MM
function getCurrentMonth() {
  const now = new Date();
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

// Вспомогательная функция для получения прошлого месяца
function getPreviousMonth() {
  const now = new Date();
  now.setMonth(now.getMonth() - 1);
  const year = now.getFullYear();
  const month = String(now.getMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

function setupBonusPenaltiesAPI(app) {
  // GET /api/bonus-penalties - получить премии/штрафы за месяц
  app.get('/api/bonus-penalties', requireAuth, async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      const employeeId = req.query.employeeId;

      console.log(`📥 GET /api/bonus-penalties month=${month}, employeeId=${employeeId || 'all'}`);

      // DB path
      if (USE_DB) {
        try {
          const conditions = ['month = $1'];
          const params = [month];
          let paramIdx = 2;

          if (employeeId) {
            conditions.push(`employee_id = $${paramIdx++}`);
            params.push(employeeId);
          }

          const sql = `SELECT * FROM bonus_penalties WHERE ${conditions.join(' AND ')} ORDER BY created_at DESC`;
          const result = await db.query(sql, params);
          const records = result.rows.map(dbToCamel);

          let total = 0;
          records.forEach(r => {
            if (r.type === 'bonus') {
              total += r.amount;
            } else {
              total -= r.amount;
            }
          });

          if (isPaginationRequested(req.query)) {
            const paginated = createPaginatedResponse(records, req.query, 'records');
            paginated.total = total;
            return res.json(paginated);
          }
          return res.json({ success: true, records, total });
        } catch (dbErr) {
          console.error('DB bonus-penalties read error:', dbErr.message);
        }
      }

      // File path
      if (!await fileExists(BONUS_PENALTIES_DIR)) {
        await fsp.mkdir(BONUS_PENALTIES_DIR, { recursive: true });
      }

      const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);

      if (!await fileExists(filePath)) {
        return res.json({ success: true, records: [], total: 0 });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const data = JSON.parse(content);
      let records = data.records || [];

      // Фильтрация по сотруднику, если указан
      if (employeeId) {
        records = records.filter(r => r.employeeId === employeeId);
      }

      // Подсчет общей суммы
      let total = 0;
      records.forEach(r => {
        if (r.type === 'bonus') {
          total += r.amount;
        } else {
          total -= r.amount;
        }
      });

      if (isPaginationRequested(req.query)) {
        const paginated = createPaginatedResponse(records, req.query, 'records');
        paginated.total = total;
        return res.json(paginated);
      }
      res.json({ success: true, records, total });
    } catch (error) {
      console.error('❌ Ошибка получения премий/штрафов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/bonus-penalties - создать премию/штраф
  app.post('/api/bonus-penalties', requireAuth, async (req, res) => {
    try {
      const { employeeId, employeeName, type, amount, comment, adminName } = req.body;

      console.log(`📤 POST /api/bonus-penalties: ${type} ${amount} для ${employeeName}`);

      // Валидация
      if (!employeeId || !employeeName || !type || !amount) {
        return res.status(400).json({
          success: false,
          error: 'Обязательные поля: employeeId, employeeName, type, amount'
        });
      }

      if (type !== 'bonus' && type !== 'penalty') {
        return res.status(400).json({
          success: false,
          error: 'type должен быть "bonus" или "penalty"'
        });
      }

      if (amount <= 0) {
        return res.status(400).json({
          success: false,
          error: 'amount должен быть положительным числом'
        });
      }

      // Создаем директорию, если её нет
      if (!await fileExists(BONUS_PENALTIES_DIR)) {
        await fsp.mkdir(BONUS_PENALTIES_DIR, { recursive: true });
      }

      const month = getCurrentMonth();
      const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);

      // Читаем существующие данные или создаем новый файл
      let data = { records: [] };
      if (await fileExists(filePath)) {
        const content = await fsp.readFile(filePath, 'utf8');
        data = JSON.parse(content);
      }

      // Создаем новую запись
      const newRecord = {
        id: `bp_${Date.now()}`,
        employeeId,
        employeeName,
        type,
        amount: parseFloat(amount),
        comment: comment || '',
        adminName: adminName || 'Администратор',
        createdAt: new Date().toISOString(),
        month
      };

      data.records.push(newRecord);

      // Сохраняем
      await writeJsonFile(filePath, data);
      // DB dual-write
      if (USE_DB) {
        try {
          await db.upsert('bonus_penalties', camelToDb(newRecord));
        } catch (dbErr) {
          console.error('DB bonus-penalties insert error:', dbErr.message);
        }
      }

      console.log(`✅ Создана запись ${type}: ${amount} для ${employeeName}`);
      res.json({ success: true, record: newRecord });
    } catch (error) {
      console.error('❌ Ошибка создания премии/штрафа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/bonus-penalties/:id - удалить премию/штраф
  app.delete('/api/bonus-penalties/:id', requireAuth, async (req, res) => {
    try {
      const id = sanitizeId(req.params.id);
      const month = req.query.month || getCurrentMonth();

      console.log(`🗑️ DELETE /api/bonus-penalties/${id} month=${month}`);

      const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);

      if (!await fileExists(filePath)) {
        return res.status(404).json({ success: false, error: 'Записи не найдены' });
      }

      const content = await fsp.readFile(filePath, 'utf8');
      const data = JSON.parse(content);

      const index = data.records.findIndex(r => r.id === id);
      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Запись не найдена' });
      }

      data.records.splice(index, 1);
      await writeJsonFile(filePath, data);
      // DB dual-write
      if (USE_DB) {
        try {
          await db.deleteById('bonus_penalties', id);
        } catch (dbErr) {
          console.error('DB bonus-penalties delete error:', dbErr.message);
        }
      }

      console.log(`✅ Запись ${id} удалена`);
      res.json({ success: true });
    } catch (error) {
      console.error('❌ Ошибка удаления премии/штрафа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/bonus-penalties/summary/:employeeId - получить сводку для сотрудника
  app.get('/api/bonus-penalties/summary/:employeeId', requireAuth, async (req, res) => {
    try {
      const { employeeId } = req.params;

      console.log(`📊 GET /api/bonus-penalties/summary/${employeeId}`);

      const currentMonth = getCurrentMonth();
      const previousMonth = getPreviousMonth();

      // DB path
      if (USE_DB) {
        try {
          const getMonthDataDb = async (month) => {
            const result = await db.query(
              'SELECT * FROM bonus_penalties WHERE month = $1 AND employee_id = $2 ORDER BY created_at DESC',
              [month, employeeId]
            );
            const records = result.rows.map(dbToCamel);
            let total = 0;
            records.forEach(r => {
              if (r.type === 'bonus') total += r.amount;
              else total -= r.amount;
            });
            return { total, records };
          };

          return res.json({
            success: true,
            currentMonth: await getMonthDataDb(currentMonth),
            previousMonth: await getMonthDataDb(previousMonth)
          });
        } catch (dbErr) {
          console.error('DB bonus-penalties summary error:', dbErr.message);
        }
      }

      // File path
      if (!await fileExists(BONUS_PENALTIES_DIR)) {
        return res.json({
          success: true,
          currentMonth: { total: 0, records: [] },
          previousMonth: { total: 0, records: [] }
        });
      }

      const getMonthData = async (month) => {
        const filePath = path.join(BONUS_PENALTIES_DIR, `${month}.json`);
        if (!await fileExists(filePath)) {
          return { total: 0, records: [] };
        }

        const content = await fsp.readFile(filePath, 'utf8');
        const data = JSON.parse(content);
        const records = (data.records || []).filter(r => r.employeeId === employeeId);

        let total = 0;
        records.forEach(r => {
          if (r.type === 'bonus') {
            total += r.amount;
          } else {
            total -= r.amount;
          }
        });

        return { total, records };
      };

      res.json({
        success: true,
        currentMonth: await getMonthData(currentMonth),
        previousMonth: await getMonthData(previousMonth)
      });
    } catch (error) {
      console.error('❌ Ошибка получения сводки:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Bonus/Penalties API initialized');
}

module.exports = { setupBonusPenaltiesAPI };
