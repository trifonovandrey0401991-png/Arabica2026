/**
 * Work Schedule API
 * Графики работы и шаблоны
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, sanitizeId } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireAuth, requireAdmin } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_WORK_SCHEDULE === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;
const WORK_SCHEDULE_TEMPLATES_DIR = `${DATA_DIR}/work-schedule-templates`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;

// DB conversion helpers
function entryToDb(e) {
  return {
    id: e.id,
    employee_id: e.employeeId || null,
    employee_name: e.employeeName || null,
    shop_address: e.shopAddress || null,
    shop_name: e.shopName || null,
    date: e.date || null,
    shift_type: e.shiftType || null,
    month: e.month || null,
    created_at: e.createdAt || new Date().toISOString()
  };
}

function dbEntryToCamel(row) {
  let dateStr = row.date;
  if (dateStr instanceof Date) {
    dateStr = dateStr.toISOString().split('T')[0];
  }
  return {
    id: row.id,
    employeeId: row.employee_id,
    employeeName: row.employee_name,
    shopAddress: row.shop_address,
    shopName: row.shop_name,
    date: dateStr,
    shiftType: row.shift_type,
    month: row.month,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null
  };
}

// Создаем директории, если их нет
(async () => {
  if (!await fileExists(WORK_SCHEDULES_DIR)) {
    await fsp.mkdir(WORK_SCHEDULES_DIR, { recursive: true });
  }
  if (!await fileExists(WORK_SCHEDULE_TEMPLATES_DIR)) {
    await fsp.mkdir(WORK_SCHEDULE_TEMPLATES_DIR, { recursive: true });
  }
})();

// Вспомогательная функция для получения файла графика
function getScheduleFilePath(month) {
  return path.join(WORK_SCHEDULES_DIR, `${month}.json`);
}

// Вспомогательная функция для загрузки графика
async function loadSchedule(month) {
  const filePath = getScheduleFilePath(month);
  if (await fileExists(filePath)) {
    try {
      const data = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(data);
    } catch (error) {
      console.error('Ошибка чтения графика:', error);
      return { month, entries: [] };
    }
  }
  return { month, entries: [] };
}

// Вспомогательная функция для сохранения графика
async function saveSchedule(schedule) {
  const filePath = getScheduleFilePath(schedule.month);
  try {
    await writeJsonFile(filePath, schedule);
    return true;
  } catch (error) {
    console.error('Ошибка сохранения графика:', error);
    return false;
  }
}

function setupWorkScheduleAPI(app, { sendPushToPhone } = {}) {
  // GET /api/work-schedule?month=YYYY-MM - получить график на месяц
  app.get('/api/work-schedule', requireAuth, async (req, res) => {
    try {
      const month = req.query.month;
      if (!month) {
        return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
      }

      // DB path
      if (USE_DB) {
        try {
          const result = await db.query(
            'SELECT * FROM work_schedule_entries WHERE month = $1 ORDER BY date, shift_type',
            [month]
          );
          const entries = result.rows.map(dbEntryToCamel);
          console.log(`📥 Загружен график из DB для ${month}: ${entries.length} записей`);
          return res.json({ success: true, schedule: { month, entries } });
        } catch (dbErr) {
          console.error('DB work-schedule read error:', dbErr.message);
        }
      }

      const schedule = await loadSchedule(month);
      console.log(`📥 Загружен график для ${month}: ${schedule.entries.length} записей`);
      res.json({ success: true, schedule });
    } catch (error) {
      console.error('Ошибка получения графика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/work-schedule/employee/:employeeId?month=YYYY-MM - график сотрудника
  app.get('/api/work-schedule/employee/:employeeId', requireAuth, async (req, res) => {
    try {
      const employeeId = req.params.employeeId;
      const month = req.query.month;
      if (!month) {
        return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
      }

      // DB path
      if (USE_DB) {
        try {
          const result = await db.query(
            'SELECT * FROM work_schedule_entries WHERE month = $1 AND employee_id = $2 ORDER BY date',
            [month, employeeId]
          );
          const entries = result.rows.map(dbEntryToCamel);
          return res.json({ success: true, schedule: { month, entries } });
        } catch (dbErr) {
          console.error('DB work-schedule employee read error:', dbErr.message);
        }
      }

      const schedule = await loadSchedule(month);
      const employeeEntries = schedule.entries.filter(e => e.employeeId === employeeId);
      const employeeSchedule = { month, entries: employeeEntries };

      res.json({ success: true, schedule: employeeSchedule });
    } catch (error) {
      console.error('Ошибка получения графика сотрудника:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/work-schedule - создать/обновить смену
  app.post('/api/work-schedule', requireAuth, async (req, res) => {
    try {
      const entry = req.body;
      if (!entry.month || !entry.employeeId || !entry.date || !entry.shiftType) {
        return res.status(400).json({
          success: false,
          error: 'Не указаны обязательные поля: month, employeeId, date, shiftType'
        });
      }

      const month = entry.month;
      const schedule = await loadSchedule(month);

      // Если есть ID - это обновление существующей записи
      if (entry.id) {
        // Удаляем старую запись по ID
        schedule.entries = schedule.entries.filter(e => e.id !== entry.id);
      } else {
        // Новая запись - генерируем ID
        entry.id = `entry_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        // Удаляем возможные дубликаты для этого сотрудника, даты и типа смены
        schedule.entries = schedule.entries.filter(e =>
          !(e.employeeId === entry.employeeId &&
            e.date === entry.date &&
            e.shiftType === entry.shiftType)
        );
      }

      // Добавляем новую запись
      schedule.entries.push(entry);
      schedule.month = month;

      if (await saveSchedule(schedule)) {
        // DB dual-write
        if (USE_DB) {
          try {
            // Remove conflicting entries from DB (same logic as file filter)
            await db.query(
              'DELETE FROM work_schedule_entries WHERE employee_id = $1 AND date = $2::date AND shift_type = $3 AND id != $4',
              [entry.employeeId, entry.date, entry.shiftType, entry.id]
            );
            await db.upsert('work_schedule_entries', entryToDb(entry));
          } catch (dbErr) {
            console.error('DB work-schedule insert error:', dbErr.message);
          }
        }

        res.json({ success: true, entry });

        // Отправляем push-уведомление сотруднику об изменении в графике
        try {
          const employeeFile = path.join(EMPLOYEES_DIR, `${entry.employeeId}.json`);
          if (await fileExists(employeeFile)) {
            const employeeData = JSON.parse(await fsp.readFile(employeeFile, 'utf8'));
            if (employeeData.phone && sendPushToPhone) {
              const shiftLabels = { morning: 'Утренняя', day: 'Дневная', night: 'Ночная' };
              const shiftLabel = shiftLabels[entry.shiftType] || entry.shiftType;
              const dateFormatted = entry.date; // формат YYYY-MM-DD
              const dateParts = dateFormatted.split('-');
              const displayDate = dateParts.length === 3 ? `${dateParts[2]}.${dateParts[1]}` : dateFormatted;

              await sendPushToPhone(
                employeeData.phone,
                'Изменение в графике',
                `Ваша смена на ${displayDate}: ${shiftLabel}`,
                { type: 'schedule_change', date: entry.date, shiftType: entry.shiftType }
              );
              console.log(`Push-уведомление отправлено сотруднику ${employeeData.name || entry.employeeId} об изменении смены`);
            }
          }
        } catch (pushError) {
          console.error('Ошибка отправки push-уведомления о смене:', pushError.message);
          // Не прерываем работу, уведомление не критично
        }
      } else {
        res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
      }
    } catch (error) {
      console.error('Ошибка сохранения смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/work-schedule/clear - очистить весь месяц
  app.delete('/api/work-schedule/clear', requireAdmin, async (req, res) => {
    try {
      const month = req.query.month;

      if (!month) {
        return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
      }

      console.log(`🗑️ Запрос на очистку графика за месяц: ${month}`);

      const schedule = await loadSchedule(month);
      const entriesCount = schedule.entries.length;

      if (entriesCount === 0) {
        console.log(`ℹ️ График за ${month} уже пуст`);
        return res.json({ success: true, message: 'График уже пуст', deletedCount: 0 });
      }

      // Очищаем все записи
      schedule.entries = [];

      if (await saveSchedule(schedule)) {
        // DB dual-write
        if (USE_DB) {
          try {
            await db.query('DELETE FROM work_schedule_entries WHERE month = $1', [month]);
          } catch (dbErr) {
            console.error('DB work-schedule clear error:', dbErr.message);
          }
        }

        console.log(`✅ График за ${month} очищен. Удалено записей: ${entriesCount}`);
        res.json({
          success: true,
          message: `График очищен. Удалено смен: ${entriesCount}`,
          deletedCount: entriesCount
        });
      } else {
        console.error(`❌ Ошибка сохранения графика при очистке ${month}`);
        res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
      }
    } catch (error) {
      console.error('Ошибка очистки графика:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // DELETE /api/work-schedule/:entryId - удалить смену
  app.delete('/api/work-schedule/:entryId', requireAuth, async (req, res) => {
    try {
      const entryId = sanitizeId(req.params.entryId);
      const month = req.query.month;

      if (!month) {
        return res.status(400).json({ success: false, error: 'Не указан месяц (month)' });
      }

      const schedule = await loadSchedule(month);
      const initialLength = schedule.entries.length;
      schedule.entries = schedule.entries.filter(e => e.id !== entryId);

      if (schedule.entries.length < initialLength) {
        if (await saveSchedule(schedule)) {
          // DB dual-write
          if (USE_DB) {
            try {
              await db.deleteById('work_schedule_entries', entryId);
            } catch (dbErr) {
              console.error('DB work-schedule delete error:', dbErr.message);
            }
          }

          res.json({ success: true, message: 'Смена удалена' });
        } else {
          res.status(500).json({ success: false, error: 'Ошибка сохранения графика' });
        }
      } else {
        res.status(404).json({ success: false, error: 'Смена не найдена' });
      }
    } catch (error) {
      console.error('Ошибка удаления смены:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/work-schedule/bulk - массовое создание смен
  app.post('/api/work-schedule/bulk', requireAuth, async (req, res) => {
    try {
      const entries = req.body.entries;
      if (!Array.isArray(entries) || entries.length === 0) {
        return res.status(400).json({
          success: false,
          error: 'Не указаны записи (entries)'
        });
      }

      console.log(`📥 BULK-создание: получено ${entries.length} записей от клиента`);

      // Проверяем наличие дубликатов во входящих данных
      const duplicatesCheck = {};
      entries.forEach((e, i) => {
        const key = `${e.shopAddress}|${e.date}|${e.shiftType}`;
        if (duplicatesCheck[key]) {
          console.log(`⚠️ ДУБЛИКАТ ВО ВХОДЯЩИХ ДАННЫХ [${i}]: ${e.employeeName} → ${e.shopAddress}, ${e.date}, ${e.shiftType}`);
          console.log(`   Первое вхождение: [${duplicatesCheck[key].index}] ${duplicatesCheck[key].employeeName}`);
        } else {
          duplicatesCheck[key] = { index: i, employeeName: e.employeeName };
        }
      });

      // Группируем по месяцам
      const schedulesByMonth = {};
      for (let index = 0; index < entries.length; index++) {
        const entry = entries[index];
        if (!entry.month) {
          // Извлекаем месяц из даты
          const date = new Date(entry.date);
          entry.month = `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
        }

        if (!schedulesByMonth[entry.month]) {
          schedulesByMonth[entry.month] = await loadSchedule(entry.month);
        }

        // Генерируем уникальный ID, если его нет
        if (!entry.id) {
          entry.id = `entry_${Date.now()}_${index}_${Math.random().toString(36).substr(2, 9)}`;
        }

        // Удаляем старую запись для этого сотрудника, даты и типа смены, если есть
        // КРИТИЧНО: Также удаляем дубликаты по магазину+дате+типу смены (независимо от сотрудника)
        const beforeFilter = schedulesByMonth[entry.month].entries.length;

        schedulesByMonth[entry.month].entries = schedulesByMonth[entry.month].entries.filter(e => {
          // Удаляем если совпадают: сотрудник + дата + тип смены
          const sameEmployeeShift = (e.employeeId === entry.employeeId &&
                                      e.date === entry.date &&
                                      e.shiftType === entry.shiftType);

          // ИЛИ удаляем если совпадают: магазин + дата + тип смены (дубликат слота)
          const sameSlot = (e.shopAddress === entry.shopAddress &&
                            e.date === entry.date &&
                            e.shiftType === entry.shiftType);

          const shouldRemove = (sameEmployeeShift || sameSlot);

          if (shouldRemove) {
            console.log(`🗑️ Удаление дубликата: ${e.employeeName} → ${e.shopAddress}, ${e.date}, ${e.shiftType}`);
            console.log(`   Причина: ${sameEmployeeShift ? 'тот же сотрудник' : ''} ${sameSlot ? 'тот же слот' : ''}`);
          }

          return !shouldRemove;
        });

        const afterFilter = schedulesByMonth[entry.month].entries.length;
        if (beforeFilter !== afterFilter) {
          console.log(`📉 Фильтрация: было ${beforeFilter} записей, осталось ${afterFilter} (удалено ${beforeFilter - afterFilter})`);
        }

        // Добавляем новую запись
        schedulesByMonth[entry.month].entries.push(entry);
      }

      console.log(`📊 Массовое создание: обработано ${entries.length} записей, сохранено в ${Object.keys(schedulesByMonth).length} месяцах`);

      // Сохраняем все графики
      let allSaved = true;
      let totalSaved = 0;
      for (const month in schedulesByMonth) {
        const schedule = schedulesByMonth[month];
        if (await saveSchedule(schedule)) {
          totalSaved += schedule.entries.length;
          console.log(`✅ Сохранен график для ${month}: ${schedule.entries.length} записей`);
        } else {
          allSaved = false;
          console.error(`❌ Ошибка сохранения графика для ${month}`);
        }
      }

      // DB sync after bulk save
      if (USE_DB && allSaved) {
        try {
          for (const m in schedulesByMonth) {
            const sched = schedulesByMonth[m];
            await db.query('DELETE FROM work_schedule_entries WHERE month = $1', [m]);
            for (const e of sched.entries) {
              await db.upsert('work_schedule_entries', entryToDb(e));
            }
          }
        } catch (dbErr) {
          console.error('DB work-schedule bulk sync error:', dbErr.message);
        }
      }

      if (allSaved) {
        console.log(`✅ Всего сохранено записей в графиках: ${totalSaved}`);
        res.json({ success: true, message: `Создано ${entries.length} смен, всего в графиках: ${totalSaved}` });
      } else {
        res.status(500).json({ success: false, error: 'Ошибка сохранения некоторых графиков' });
      }
    } catch (error) {
      console.error('Ошибка массового создания смен:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/work-schedule/template - сохранить/применить шаблон
  app.post('/api/work-schedule/template', requireAuth, async (req, res) => {
    try {
      const action = req.body.action; // 'save' или 'apply'
      const template = req.body.template;

      if (action === 'save') {
        if (!template || !template.name) {
          return res.status(400).json({
            success: false,
            error: 'Не указан шаблон или его название'
          });
        }

        // Генерируем ID, если его нет
        if (!template.id) {
          template.id = `template_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
        }

        const templateFile = path.join(WORK_SCHEDULE_TEMPLATES_DIR, `${template.id}.json`);
        await writeJsonFile(templateFile, template);

        res.json({ success: true, template });
      } else if (action === 'apply') {
        // Применение шаблона обрабатывается на клиенте
        res.json({ success: true, message: 'Шаблон применен' });
      } else {
        res.status(400).json({ success: false, error: 'Неизвестное действие' });
      }
    } catch (error) {
      console.error('Ошибка работы с шаблоном:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/work-schedule/template - получить список шаблонов
  app.get('/api/work-schedule/template', requireAuth, async (req, res) => {
    try {
      const templates = [];

      if (await fileExists(WORK_SCHEDULE_TEMPLATES_DIR)) {
        const files = await fsp.readdir(WORK_SCHEDULE_TEMPLATES_DIR);
        for (const file of files) {
          if (file.endsWith('.json')) {
            try {
              const filePath = path.join(WORK_SCHEDULE_TEMPLATES_DIR, file);
              const data = await fsp.readFile(filePath, 'utf8');
              const template = JSON.parse(data);
              templates.push(template);
            } catch (error) {
              console.error(`Ошибка чтения шаблона ${file}:`, error);
            }
          }
        }
      }

      res.json({ success: true, templates });
    } catch (error) {
      console.error('Ошибка получения шаблонов:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('✅ Work Schedule API initialized');
}

module.exports = { setupWorkScheduleAPI };
