/**
 * API для циклических задач
 * Файл для размещения на сервере: /root/arabica_app/loyalty-proxy/api/recurring_tasks_api.js
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists, loadJsonFile } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const { getMoscowTime, getMoscowDateString } = require('../utils/moscow_time');
const { getTaskPointsConfig } = require('./task_points_settings_api');
const { sendPushToPhone, sendPushNotification } = require('./report_notifications_api');
const { dbInsertPenalties } = require('./efficiency_penalties_api');
const db = require('../utils/db');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');
const { requireAuth } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_RECURRING_TASKS === 'true';

// Директории хранения
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const RECURRING_TASKS_DIR = `${DATA_DIR}/recurring-tasks`;
const RECURRING_INSTANCES_DIR = `${DATA_DIR}/recurring-task-instances`;
const EFFICIENCY_DIR = `${DATA_DIR}/efficiency-penalties`;

// DB conversion helpers
function templateToDb(t) {
  return {
    id: t.id,
    title: t.title || '',
    description: t.description || null,
    response_type: t.responseType || null,
    days_of_week: t.daysOfWeek || null,
    start_time: t.startTime || null,
    end_time: t.endTime || null,
    reminder_times: t.reminderTimes || null,
    assignees: t.assignees ? JSON.stringify(t.assignees) : null,
    is_paused: t.isPaused || false,
    created_by: t.createdBy || null,
    supplier_id: t.supplierId || null,
    shop_id: t.shopId || null,
    supplier_name: t.supplierName || null,
    created_at: t.createdAt || new Date().toISOString(),
    updated_at: t.updatedAt || new Date().toISOString()
  };
}

function dbTemplateToCamel(row) {
  return {
    id: row.id,
    title: row.title,
    description: row.description,
    responseType: row.response_type,
    daysOfWeek: row.days_of_week,
    startTime: row.start_time,
    endTime: row.end_time,
    reminderTimes: row.reminder_times,
    assignees: typeof row.assignees === 'string' ? JSON.parse(row.assignees) : row.assignees,
    isPaused: row.is_paused || false,
    createdBy: row.created_by,
    supplierId: row.supplier_id,
    shopId: row.shop_id,
    supplierName: row.supplier_name,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
    updatedAt: row.updated_at ? new Date(row.updated_at).toISOString() : null
  };
}

function instanceToDb(i) {
  return {
    id: i.id,
    recurring_task_id: i.recurringTaskId || null,
    assignee_id: i.assigneeId || null,
    assignee_name: i.assigneeName || null,
    assignee_phone: i.assigneePhone || null,
    date: i.date || null,
    deadline: i.deadline || null,
    reminder_times: i.reminderTimes || null,
    status: i.status || 'pending',
    response_text: i.responseText || null,
    response_photos: i.responsePhotos || null,
    completed_at: i.completedAt || null,
    expired_at: i.expiredAt || null,
    is_recurring: i.isRecurring != null ? i.isRecurring : true,
    title: i.title || null,
    description: i.description || null,
    response_type: i.responseType || null,
    created_at: i.createdAt || new Date().toISOString()
  };
}

function dbInstanceToCamel(row) {
  let dateStr = row.date;
  if (dateStr instanceof Date) {
    dateStr = dateStr.toISOString().split('T')[0];
  }
  return {
    id: row.id,
    recurringTaskId: row.recurring_task_id,
    assigneeId: row.assignee_id,
    assigneeName: row.assignee_name,
    assigneePhone: row.assignee_phone,
    date: dateStr,
    deadline: row.deadline ? new Date(row.deadline).toISOString() : null,
    reminderTimes: row.reminder_times,
    status: row.status,
    responseText: row.response_text,
    responsePhotos: row.response_photos || [],
    completedAt: row.completed_at ? new Date(row.completed_at).toISOString() : null,
    expiredAt: row.expired_at ? new Date(row.expired_at).toISOString() : null,
    isRecurring: row.is_recurring != null ? row.is_recurring : true,
    title: row.title,
    description: row.description,
    responseType: row.response_type,
    createdAt: row.created_at ? new Date(row.created_at).toISOString() : null
  };
}

// Создаем директории если не существуют
(async () => {
  for (const dir of [RECURRING_TASKS_DIR, RECURRING_INSTANCES_DIR, EFFICIENCY_DIR]) {
    if (!await fileExists(dir)) {
      await fsp.mkdir(dir, { recursive: true });
    }
  }
})();

// ==================== УТИЛИТЫ ====================

function generateId() {
  return 'recurring_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9);
}

function generateInstanceId(recurringTaskId, date, assigneeId) {
  return 'instance_' + date + '_' + recurringTaskId + '_' + assigneeId;
}

// Boy Scout: use Moscow time (UTC+3) instead of UTC
function getToday() {
  return getMoscowDateString();
}

function getYearMonth(date) {
  return date.substring(0, 7); // YYYY-MM
}

// loadJsonFile imported from file_helpers (removed local duplicate)


// ==================== ШАБЛОНЫ ЗАДАЧ ====================

const TEMPLATES_FILE = path.join(RECURRING_TASKS_DIR, 'all.json');
const SCHEDULER_STATE_FILE = path.join(RECURRING_TASKS_DIR, 'scheduler-state.json');
const REMINDERS_SENT_FILE = path.join(RECURRING_TASKS_DIR, 'reminders-sent.json');

async function loadTemplates() {
  // DB path
  if (USE_DB) {
    try {
      const result = await db.query('SELECT * FROM recurring_tasks ORDER BY created_at DESC');
      return result.rows.map(dbTemplateToCamel);
    } catch (dbErr) {
      console.error('DB recurring_tasks read error:', dbErr.message);
    }
  }
  return await loadJsonFile(TEMPLATES_FILE, []);
}

async function saveTemplates(templates) {
  await writeJsonFile(TEMPLATES_FILE, templates);

  // DB dual-write: sync all templates
  if (USE_DB) {
    try {
      for (const t of templates) {
        await db.upsert('recurring_tasks', templateToDb(t));
      }
    } catch (dbErr) {
      console.error('DB recurring_tasks sync error:', dbErr.message);
    }
  }
}

async function loadSchedulerState() {
  return await loadJsonFile(SCHEDULER_STATE_FILE, {
    lastGenerationDate: null,
    lastExpiredCheck: null
  });
}

async function saveSchedulerState(state) {
  await writeJsonFile(SCHEDULER_STATE_FILE, state);
}

// ==================== ЭКЗЕМПЛЯРЫ ЗАДАЧ ====================

async function loadInstances(yearMonth) {
  // DB path
  if (USE_DB) {
    try {
      const result = await db.query(
        `SELECT * FROM recurring_task_instances WHERE date >= ($1 || '-01')::date AND date < (($1 || '-01')::date + interval '1 month') ORDER BY created_at DESC`,
        [yearMonth]
      );
      return result.rows.map(dbInstanceToCamel);
    } catch (dbErr) {
      console.error('DB recurring_task_instances read error:', dbErr.message);
    }
  }
  const filePath = path.join(RECURRING_INSTANCES_DIR, yearMonth + '.json');
  return await loadJsonFile(filePath, []);
}

async function saveInstances(yearMonth, instances) {
  const filePath = path.join(RECURRING_INSTANCES_DIR, yearMonth + '.json');
  await writeJsonFile(filePath, instances);

  // DB dual-write: sync all instances for this month
  if (USE_DB) {
    try {
      for (const i of instances) {
        await db.upsert('recurring_task_instances', instanceToDb(i));
      }
    } catch (dbErr) {
      console.error('DB recurring_task_instances sync error:', dbErr.message);
    }
  }
}

// ==================== ГЕНЕРАЦИЯ ЗАДАЧ ====================

// Генерация экземпляров для одного шаблона (при создании)
async function generateInstancesForTemplate(template, date) {
  const yearMonth = getYearMonth(date);
  let instances = await loadInstances(yearMonth);
  let generatedCount = 0;
  const newInstances = []; // Для отправки push после сохранения

  for (const assignee of template.assignees) {
    const instanceId = generateInstanceId(template.id, date, assignee.id || assignee.phone);

    // Проверяем, не существует ли уже
    if (instances.some(i => i.id === instanceId)) {
      continue;
    }

    const deadline = date + 'T' + template.endTime + ':00.000Z';

    const newInstance = {
      id: instanceId,
      recurringTaskId: template.id,
      assigneeId: assignee.id || assignee.phone,
      assigneeName: assignee.name,
      assigneePhone: assignee.phone,
      date,
      deadline,
      reminderTimes: template.reminderTimes,
      status: 'pending',
      responseText: null,
      responsePhotos: [],
      completedAt: null,
      expiredAt: null,
      isRecurring: true,
      title: template.title,
      description: template.description,
      responseType: template.responseType,
      createdAt: new Date().toISOString()
    };

    instances.push(newInstance);
    newInstances.push(newInstance);
    generatedCount++;
  }

  if (generatedCount > 0) {
    await saveInstances(yearMonth, instances);
    console.log('Generated', generatedCount, 'instances for new template:', template.id);

    // Отправляем push-уведомления о новой задаче
    for (const instance of newInstances) {
      if (instance.assigneePhone) {
        try {
          await sendPushToPhone(
            instance.assigneePhone,
            'Новая циклическая задача',
            instance.title,
            { type: 'new_recurring_task', instanceId: instance.id, recurringTaskId: instance.recurringTaskId }
          );
          console.log('Sent push for new recurring task to:', instance.assigneePhone);
        } catch (pushErr) {
          console.error('Failed to send push for new recurring task:', pushErr.message);
        }
      }
    }
  }

  return generatedCount;
}

async function generateDailyTasks(date) {
  console.log('Generating recurring tasks for date:', date);

  const templates = await loadTemplates();
  const dayOfWeek = new Date(date + 'T00:00:00').getDay(); // 0-6 (Вс-Сб)
  const yearMonth = getYearMonth(date);
  let instances = await loadInstances(yearMonth);

  let generatedCount = 0;
  const newInstances = []; // Для отправки push после сохранения

  for (const template of templates) {
    // Пропускаем приостановленные
    if (template.isPaused) continue;

    // Проверяем день недели
    if (!template.daysOfWeek.includes(dayOfWeek)) continue;

    // Генерируем для каждого получателя
    for (const assignee of template.assignees) {
      const instanceId = generateInstanceId(template.id, date, assignee.id || assignee.phone);

      // Проверяем, не существует ли уже
      if (instances.some(i => i.id === instanceId)) {
        continue;
      }

      const deadline = date + 'T' + template.endTime + ':00.000Z';

      const newInstance = {
        id: instanceId,
        recurringTaskId: template.id,
        assigneeId: assignee.id || assignee.phone,
        assigneeName: assignee.name,
        assigneePhone: assignee.phone,
        date,
        deadline,
        reminderTimes: template.reminderTimes,
        status: 'pending',
        responseText: null,
        responsePhotos: [],
        completedAt: null,
        expiredAt: null,
        isRecurring: true,
        title: template.title,
        description: template.description,
        responseType: template.responseType,
        createdAt: new Date().toISOString()
      };

      instances.push(newInstance);
      newInstances.push(newInstance);
      generatedCount++;
    }
  }

  await saveInstances(yearMonth, instances);
  console.log('Generated', generatedCount, 'recurring task instances for', date);

  // Отправляем push-уведомления для новых задач
  for (const instance of newInstances) {
    if (instance.assigneePhone) {
      await sendPushToPhone(
        instance.assigneePhone,
        'У Вас Новая Задача',
        instance.title,
        { type: 'new_recurring_task', instanceId: instance.id, recurringTaskId: instance.recurringTaskId }
      );
      console.log(`  Push sent for recurring task to ${instance.assigneeName}`);
    }
  }

  return generatedCount;
}

async function checkExpiredTasks() {
  const now = new Date();
  const today = getToday();
  const yearMonth = getYearMonth(today);
  let instances = await loadInstances(yearMonth);

  let expiredCount = 0;
  const penalties = [];
  const expiredInstances = []; // Для отправки push после сохранения

  // Получаем настройки баллов
  const config = await getTaskPointsConfig();
  const penaltyPoints = config.recurringTasks.penaltyPoints;

  for (const instance of instances) {
    if (instance.status !== 'pending') continue;

    const deadline = new Date(instance.deadline);
    if (now > deadline) {
      instance.status = 'expired';
      instance.expiredAt = now.toISOString();
      expiredCount++;
      expiredInstances.push(instance);

      // Создаем штраф с настраиваемыми баллами
      penalties.push({
        id: 'penalty_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9),
        type: 'employee',
        entityId: instance.assigneeId,
        entityName: instance.assigneeName,
        category: 'recurring_task_penalty',
        categoryName: 'Штраф за циклическую задачу',
        date: instance.date,
        points: penaltyPoints,
        reason: `Задача "${instance.title}" не выполнена в срок`,
        sourceId: instance.id,
        createdAt: now.toISOString()
      });
    }
  }

  if (expiredCount > 0) {
    await saveInstances(yearMonth, instances);

    // Сохраняем штрафы
    const penaltiesFile = path.join(EFFICIENCY_DIR, yearMonth + '.json');
    let existingPenalties = await loadJsonFile(penaltiesFile, []);
    existingPenalties = existingPenalties.concat(penalties);
    await writeJsonFile(penaltiesFile, existingPenalties);
    // DB dual-write
    await dbInsertPenalties(penalties);

    console.log('Expired', expiredCount, 'recurring task instances, created', penalties.length, 'penalties');

    // Отправляем push-уведомления
    for (const instance of expiredInstances) {
      // Push сотруднику
      if (instance.assigneePhone) {
        await sendPushToPhone(
          instance.assigneePhone,
          'Задача просрочена',
          `Вы не выполнили задачу "${instance.title}" в срок. Начислен штраф ${penaltyPoints} баллов.`,
          { type: 'recurring_task_expired', instanceId: instance.id }
        );
        console.log(`  Push sent to employee ${instance.assigneeName} for expired recurring task`);
      }

      // Push админам
      await sendPushNotification(
        'Задача не выполнена',
        `${instance.assigneeName} не выполнил циклическую задачу "${instance.title}"`,
        { type: 'recurring_task_expired_admin', instanceId: instance.id }
      );
    }
  }

  return expiredCount;
}

// ==================== НАПОМИНАНИЯ ====================

async function loadRemindersSent() {
  return await loadJsonFile(REMINDERS_SENT_FILE, {});
}

async function saveRemindersSent(data) {
  await writeJsonFile(REMINDERS_SENT_FILE, data);
}

// Boy Scout: use imported getMoscowTime instead of manual offset calculation
function getCurrentTime() {
  const moscowNow = getMoscowTime();
  const hours = moscowNow.getUTCHours().toString().padStart(2, '0');
  const minutes = moscowNow.getUTCMinutes().toString().padStart(2, '0');
  return `${hours}:${minutes}`;
}

// Проверить, попадает ли текущее время в окно напоминания (±3 минуты)
function isTimeInWindow(currentTime, reminderTime) {
  const [curH, curM] = currentTime.split(':').map(Number);
  const [remH, remM] = reminderTime.split(':').map(Number);

  const curMinutes = curH * 60 + curM;
  const remMinutes = remH * 60 + remM;

  // Окно ±3 минуты (для 5-минутного интервала планировщика)
  return Math.abs(curMinutes - remMinutes) <= 3;
}

async function sendScheduledReminders() {
  const today = getToday();
  const yearMonth = getYearMonth(today);

  // Загружаем задачи за сегодня
  const instances = await loadInstances(yearMonth);
  const todayInstances = instances.filter(i => i.date === today && i.status === 'pending');

  // Ранний выход если нет активных задач - без логирования
  if (todayInstances.length === 0) {
    return 0;
  }

  const currentTime = getCurrentTime();
  console.log(`Checking ${todayInstances.length} pending tasks for reminders at ${currentTime} Moscow...`);

  // Загружаем отправленные напоминания
  let remindersSent = await loadRemindersSent();

  // Очищаем старые записи (старше 2 дней)
  const twoDaysAgo = new Date(Date.now() - 2 * 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  Object.keys(remindersSent).forEach(key => {
    if (key < twoDaysAgo) {
      delete remindersSent[key];
    }
  });

  // Инициализируем сегодняшний день
  if (!remindersSent[today]) {
    remindersSent[today] = {};
  }

  let sentCount = 0;

  for (const instance of todayInstances) {
    const reminderTimes = instance.reminderTimes || [];

    for (let i = 0; i < reminderTimes.length; i++) {
      const reminderTime = reminderTimes[i];
      const reminderKey = `${instance.id}_${i}`;

      // Пропускаем если уже отправлено
      if (remindersSent[today][reminderKey]) {
        continue;
      }

      // Проверяем, попадает ли текущее время в окно напоминания
      if (isTimeInWindow(currentTime, reminderTime)) {
        // Отправляем push
        if (instance.assigneePhone) {
          await sendPushToPhone(
            instance.assigneePhone,
            '⏰ Напоминание о задаче',
            `"${instance.title}" - нужно выполнить до ${instance.deadline.split('T')[1].substring(0, 5)}`,
            { type: 'recurring_task_reminder', instanceId: instance.id, reminderIndex: i }
          );

          console.log(`  📢 Reminder ${i + 1} sent to ${instance.assigneeName} for task "${instance.title}"`);
          sentCount++;
        }

        // Отмечаем как отправленное
        remindersSent[today][reminderKey] = new Date().toISOString();
      }
    }
  }

  // Сохраняем состояние
  await saveRemindersSent(remindersSent);

  if (sentCount > 0) {
    console.log(`Sent ${sentCount} reminders`);
  }

  return sentCount;
}

// ==================== ПЛАНИРОВЩИК ====================

function startScheduler() {
  console.log('Starting recurring tasks scheduler...');

  let isRunning = false;

  const schedulerTick = async () => {
    if (isRunning) { console.log('[RecurringTasks] Previous run still active, skipping'); return; }
    isRunning = true;
    try {
      const today = getToday();
      const state = await loadSchedulerState();

      // Генерация задач в новый день
      if (state.lastGenerationDate !== today) {
        await generateDailyTasks(today);
        state.lastGenerationDate = today;
        await writeJsonFile(SCHEDULER_STATE_FILE, state);
      }

      // Проверка expired каждые 5 минут
      await checkExpiredTasks();
      state.lastExpiredCheck = new Date().toISOString();
      await writeJsonFile(SCHEDULER_STATE_FILE, state);

      // Отправка напоминаний по расписанию
      await sendScheduledReminders();
    } catch (e) {
      console.error('Scheduler error:', e);
    } finally {
      isRunning = false;
    }
  };

  // Каждые 5 минут
  setInterval(schedulerTick, 5 * 60 * 1000);

  // Первый запуск через 1 секунду
  setTimeout(schedulerTick, 1000);
}

// ==================== SETUP FUNCTION ====================

function setupRecurringTasksAPI(app) {
  console.log('Setting up Recurring Tasks API...');

  // GET /api/recurring-tasks - Список всех шаблонов
  app.get('/api/recurring-tasks', requireAuth, async (req, res) => {
    try {
      const templates = await loadTemplates();
      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(templates, req.query, 'tasks'));
      }
      res.json({ success: true, tasks: templates });
    } catch (e) {
      console.error('Error getting recurring tasks:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/recurring-tasks/instances/list - Список экземпляров
  app.get('/api/recurring-tasks/instances/list', requireAuth, async (req, res) => {
    try {
      const { assigneeId, assigneePhone, date, status, yearMonth } = req.query;

      // Определяем месяц для загрузки
      const month = yearMonth || getYearMonth(date || getToday());
      let instances = await loadInstances(month);

      // Фильтрация
      if (assigneeId) {
        instances = instances.filter(i => i.assigneeId === assigneeId);
      }
      if (assigneePhone) {
        instances = instances.filter(i => i.assigneePhone === assigneePhone);
      }
      if (date) {
        instances = instances.filter(i => i.date === date);
      }
      if (status) {
        instances = instances.filter(i => i.status === status);
      }

      if (isPaginationRequested(req.query)) {
        return res.json(createPaginatedResponse(instances, req.query, 'instances'));
      }
      res.json({ success: true, instances });
    } catch (e) {
      console.error('Error getting instances:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/recurring-tasks/instances/:id/complete - Выполнить задачу
  app.post('/api/recurring-tasks/instances/:id/complete', requireAuth, async (req, res) => {
    try {
      const { responseText, responsePhotos } = req.body;
      const instanceId = req.params.id;

      // Ищем экземпляр во всех месяцах (последние 2)
      const today = getToday();
      const currentMonth = getYearMonth(today);
      const prevMonth = getYearMonth(new Date(Date.now() - 31*24*60*60*1000).toISOString().split('T')[0]);

      let foundMonth = null;
      let instances = null;
      let index = -1;

      for (const month of [currentMonth, prevMonth]) {
        instances = await loadInstances(month);
        index = instances.findIndex(i => i.id === instanceId);
        if (index !== -1) {
          foundMonth = month;
          break;
        }
      }

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Instance not found' });
      }

      if (instances[index].status !== 'pending') {
        return res.status(400).json({ success: false, error: 'Task already processed' });
      }

      instances[index].status = 'completed';
      instances[index].responseText = responseText || null;
      instances[index].responsePhotos = responsePhotos || [];
      instances[index].completedAt = new Date().toISOString();

      await saveInstances(foundMonth, instances);
      console.log('Completed recurring task instance:', instanceId);
      res.json({ success: true, instance: instances[index] });
    } catch (e) {
      console.error('Error completing instance:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/recurring-tasks/:id - Шаблон по ID (должен быть после instances/list!)
  app.get('/api/recurring-tasks/:id', requireAuth, async (req, res) => {
    try {
      const templates = await loadTemplates();
      const task = templates.find(t => t.id === req.params.id);
      if (!task) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }
      res.json({ success: true, task });
    } catch (e) {
      console.error('Error getting recurring task:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/recurring-tasks - Создать шаблон
  app.post('/api/recurring-tasks', requireAuth, async (req, res) => {
    try {
      const {
        title,
        description,
        responseType,
        daysOfWeek,
        startTime,
        endTime,
        reminderTimes,
        assignees,
        createdBy,
        // Поля для связи с поставщиком
        supplierId,
        shopId,
        supplierName
      } = req.body;

      if (!title || !daysOfWeek || !daysOfWeek.length || !assignees || !assignees.length) {
        return res.status(400).json({ success: false, error: 'Missing required fields' });
      }

      const templates = await loadTemplates();
      const now = new Date().toISOString();

      const newTask = {
        id: generateId(),
        title,
        description: description || '',
        responseType: responseType || 'text',
        daysOfWeek,
        startTime: startTime || '08:00',
        endTime: endTime || '18:00',
        reminderTimes: reminderTimes || ['09:00', '12:00', '17:00'],
        assignees,
        isPaused: false,
        createdBy: createdBy || 'admin',
        createdAt: now,
        updatedAt: now
      };

      // Добавляем поля поставщика если переданы
      if (supplierId) newTask.supplierId = supplierId;
      if (shopId) newTask.shopId = shopId;
      if (supplierName) newTask.supplierName = supplierName;

      templates.push(newTask);
      await saveTemplates(templates);

      console.log('Created recurring task:', newTask.id);

      // Сразу генерируем экземпляры на сегодня если день совпадает
      const today = getToday();
      const dayOfWeek = new Date(today + 'T00:00:00').getDay();
      if (newTask.daysOfWeek.includes(dayOfWeek)) {
        await generateInstancesForTemplate(newTask, today);
      }

      res.json({ success: true, task: newTask });
    } catch (e) {
      console.error('Error creating recurring task:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // PUT /api/recurring-tasks/:id - Обновить шаблон
  app.put('/api/recurring-tasks/:id', requireAuth, async (req, res) => {
    try {
      const templates = await loadTemplates();
      const index = templates.findIndex(t => t.id === req.params.id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }

      const {
        title,
        description,
        responseType,
        daysOfWeek,
        startTime,
        endTime,
        reminderTimes,
        assignees,
        // Поля для связи с поставщиком
        supplierId,
        shopId,
        supplierName
      } = req.body;

      templates[index] = {
        ...templates[index],
        title: title !== undefined ? title : templates[index].title,
        description: description !== undefined ? description : templates[index].description,
        responseType: responseType !== undefined ? responseType : templates[index].responseType,
        daysOfWeek: daysOfWeek !== undefined ? daysOfWeek : templates[index].daysOfWeek,
        startTime: startTime !== undefined ? startTime : templates[index].startTime,
        endTime: endTime !== undefined ? endTime : templates[index].endTime,
        reminderTimes: reminderTimes !== undefined ? reminderTimes : templates[index].reminderTimes,
        assignees: assignees !== undefined ? assignees : templates[index].assignees,
        supplierId: supplierId !== undefined ? supplierId : templates[index].supplierId,
        shopId: shopId !== undefined ? shopId : templates[index].shopId,
        supplierName: supplierName !== undefined ? supplierName : templates[index].supplierName,
        updatedAt: new Date().toISOString()
      };

      await saveTemplates(templates);
      console.log('Updated recurring task:', req.params.id);
      res.json({ success: true, task: templates[index] });
    } catch (e) {
      console.error('Error updating recurring task:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // PUT /api/recurring-tasks/:id/toggle-pause - Пауза/возобновить
  app.put('/api/recurring-tasks/:id/toggle-pause', requireAuth, async (req, res) => {
    try {
      const templates = await loadTemplates();
      const index = templates.findIndex(t => t.id === req.params.id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }

      templates[index].isPaused = !templates[index].isPaused;
      templates[index].updatedAt = new Date().toISOString();

      await saveTemplates(templates);
      console.log('Toggled pause for recurring task:', req.params.id, 'isPaused:', templates[index].isPaused);
      res.json({ success: true, task: templates[index] });
    } catch (e) {
      console.error('Error toggling pause:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // DELETE /api/recurring-tasks/:id - Удалить шаблон
  app.delete('/api/recurring-tasks/:id', requireAuth, async (req, res) => {
    try {
      const templates = await loadTemplates();
      const index = templates.findIndex(t => t.id === req.params.id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }

      templates.splice(index, 1);
      await saveTemplates(templates);

      // DB delete (saveTemplates only upserts remaining, doesn't delete removed)
      if (USE_DB) {
        try {
          await db.deleteById('recurring_tasks', req.params.id);
        } catch (dbErr) {
          console.error('DB recurring_tasks delete error:', dbErr.message);
        }
      }

      console.log('Deleted recurring task:', req.params.id);
      res.json({ success: true });
    } catch (e) {
      console.error('Error deleting recurring task:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/recurring-tasks/generate-daily - Ручная генерация (для тестирования)
  app.post('/api/recurring-tasks/generate-daily', requireAuth, async (req, res) => {
    try {
      const date = req.body.date || getToday();
      const count = await generateDailyTasks(date);
      res.json({ success: true, generatedCount: count, date });
    } catch (e) {
      console.error('Error generating daily tasks:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/recurring-tasks/check-expired - Ручная проверка expired
  app.post('/api/recurring-tasks/check-expired', requireAuth, async (req, res) => {
    try {
      const count = await checkExpiredTasks();
      res.json({ success: true, expiredCount: count });
    } catch (e) {
      console.error('Error checking expired:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/recurring-tasks/send-reminders - Ручная отправка напоминаний (для тестирования)
  app.post('/api/recurring-tasks/send-reminders', requireAuth, async (req, res) => {
    try {
      const count = await sendScheduledReminders();
      res.json({ success: true, sentCount: count, currentTime: getCurrentTime() });
    } catch (e) {
      console.error('Error sending reminders:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // Запускаем планировщик
  startScheduler();

  console.log('Recurring Tasks API setup complete');
}

// Экспортируем
module.exports = { setupRecurringTasksAPI };
