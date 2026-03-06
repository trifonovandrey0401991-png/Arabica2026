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
const { isPaginationRequested, createPaginatedResponse, createDbPaginatedResponse } = require('../utils/pagination');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');
const { getMoscowTime } = require('../utils/moscow_time');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const USE_DB = process.env.USE_DB_BONUS_PENALTIES === 'true';
const BONUS_PENALTIES_DIR = `${DATA_DIR}/bonus-penalties`;

// Dedup: prevent double-creation within 10 seconds (same employee + type + amount)
const _recentCreations = new Map(); // key → timestamp
const DEDUP_WINDOW = 10000; // 10 seconds

function isDuplicateRequest(employeeId, type, amount) {
  const key = `${employeeId}_${type}_${amount}`;
  const now = Date.now();
  const lastTime = _recentCreations.get(key);
  if (lastTime && (now - lastTime) < DEDUP_WINDOW) {
    return true;
  }
  _recentCreations.set(key, now);
  return false;
}

// Cleanup old dedup entries every 2 minutes
setInterval(() => {
  const now = Date.now();
  for (const [key, ts] of _recentCreations) {
    if ((now - ts) > DEDUP_WINDOW) _recentCreations.delete(key);
  }
}, 2 * 60 * 1000);

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

// Вспомогательная функция для получения месяца в формате YYYY-MM (московское время)
function getCurrentMonth() {
  const now = getMoscowTime();
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

// Вспомогательная функция для получения прошлого месяца (московское время)
function getPreviousMonth() {
  const now = getMoscowTime();
  now.setUTCMonth(now.getUTCMonth() - 1);
  const year = now.getUTCFullYear();
  const month = String(now.getUTCMonth() + 1).padStart(2, '0');
  return `${year}-${month}`;
}

function setupBonusPenaltiesAPI(app, { sendPushToPhone } = {}) {
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

          const where = conditions.join(' AND ');

          // SQL-level pagination
          if (isPaginationRequested(req.query)) {
            const [paginatedResult, totalResult] = await Promise.all([
              db.findAllPaginated('bonus_penalties', {
                where,
                whereParams: params,
                orderBy: 'created_at',
                orderDir: 'DESC',
                page: parseInt(req.query.page) || 1,
                pageSize: Math.min(parseInt(req.query.limit) || 50, 200),
              }),
              db.query(
                `SELECT COALESCE(SUM(CASE WHEN type = 'bonus' THEN amount ELSE -amount END), 0) AS total FROM bonus_penalties WHERE ${where}`,
                params
              ),
            ]);
            const response = createDbPaginatedResponse(paginatedResult, 'records', dbToCamel);
            response.total = parseFloat(totalResult.rows[0].total);
            return res.json(response);
          }

          const sql = `SELECT * FROM bonus_penalties WHERE ${where} ORDER BY created_at DESC LIMIT 5000`;
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
  app.post('/api/bonus-penalties', requireAdmin, async (req, res) => {
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

      // Dedup: reject if same employee+type+amount within 10 seconds
      if (isDuplicateRequest(employeeId, type, amount)) {
        console.log(`⚠️ Duplicate bonus/penalty rejected: ${type} ${amount} for ${employeeName}`);
        return res.status(409).json({
          success: false,
          error: 'Повторный запрос. Такая же запись была создана несколько секунд назад.'
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
        id: `bp_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
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

      // Отправляем push-уведомление сотруднику
      if (sendPushToPhone) {
        try {
          // Получаем телефон сотрудника по employeeId
          const empResult = await db.query('SELECT phone FROM employees WHERE id = $1', [employeeId]);
          const empPhone = empResult.rows.length > 0 ? empResult.rows[0].phone : null;

          if (empPhone && empPhone.length >= 10) {
            const isBonus = type === 'bonus';
            const pushTitle = isBonus ? 'Премия' : 'Штраф';
            const pushBody = isBonus
              ? `Вам начислена премия ${amount} руб.${comment ? ' — ' + comment : ''}`
              : `Вам начислен штраф ${amount} руб.${comment ? ' — ' + comment : ''}`;

            await sendPushToPhone(empPhone, pushTitle, pushBody, {
              type: 'bonus_penalty',
              bonusType: type,
              amount: amount
            });
            console.log(`📱 Push отправлен: ${pushTitle} → ${empPhone.slice(0, 4)}***`);
          }
        } catch (pushErr) {
          console.error('Push bonus/penalty error (не критично):', pushErr.message);
        }
      }

      res.json({ success: true, record: newRecord });
    } catch (error) {
      console.error('❌ Ошибка создания премии/штрафа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/bonus-penalties/:id - удалить премию/штраф
  app.delete('/api/bonus-penalties/:id', requireAdmin, async (req, res) => {
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
