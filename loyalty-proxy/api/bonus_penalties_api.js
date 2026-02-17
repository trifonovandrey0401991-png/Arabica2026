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

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const BONUS_PENALTIES_DIR = `${DATA_DIR}/bonus-penalties`;

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
  app.get('/api/bonus-penalties', async (req, res) => {
    try {
      const month = req.query.month || getCurrentMonth();
      const employeeId = req.query.employeeId;

      console.log(`📥 GET /api/bonus-penalties month=${month}, employeeId=${employeeId || 'all'}`);

      // Создаем директорию, если её нет
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
  app.post('/api/bonus-penalties', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
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

      console.log(`✅ Создана запись ${type}: ${amount} для ${employeeName}`);
      res.json({ success: true, record: newRecord });
    } catch (error) {
      console.error('❌ Ошибка создания премии/штрафа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/bonus-penalties/:id - удалить премию/штраф
  app.delete('/api/bonus-penalties/:id', async (req, res) => {
    try {
      if (!req.user) return res.status(401).json({ error: 'Unauthorized' });
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

      console.log(`✅ Запись ${id} удалена`);
      res.json({ success: true });
    } catch (error) {
      console.error('❌ Ошибка удаления премии/штрафа:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/bonus-penalties/summary/:employeeId - получить сводку для сотрудника
  app.get('/api/bonus-penalties/summary/:employeeId', async (req, res) => {
    try {
      const { employeeId } = req.params;

      console.log(`📊 GET /api/bonus-penalties/summary/${employeeId}`);

      if (!await fileExists(BONUS_PENALTIES_DIR)) {
        return res.json({
          success: true,
          currentMonth: { total: 0, records: [] },
          previousMonth: { total: 0, records: [] }
        });
      }

      const currentMonth = getCurrentMonth();
      const previousMonth = getPreviousMonth();

      // Функция для чтения и суммирования по месяцу
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
