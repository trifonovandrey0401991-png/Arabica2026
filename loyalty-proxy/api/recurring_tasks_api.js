/**
 * API для циклических задач
 * Файл для размещения на сервере: /root/arabica_app/loyalty-proxy/api/recurring_tasks_api.js
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

// Директории хранения
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const RECURRING_TASKS_DIR = `${DATA_DIR}/recurring-tasks`;
const RECURRING_INSTANCES_DIR = `${DATA_DIR}/recurring-task-instances`;
const EFFICIENCY_DIR = `${DATA_DIR}/efficiency-penalties`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Создаем директории если не существуют (async IIFE)
(async () => {
  for (const dir of [RECURRING_TASKS_DIR, RECURRING_INSTANCES_DIR, EFFICIENCY_DIR]) {
    if (!(await fileExists(dir))) {
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

function getToday() {
  const now = new Date();
  return now.toISOString().split('T')[0]; // YYYY-MM-DD
}

function getYearMonth(date) {
  return date.substring(0, 7); // YYYY-MM
}

async function loadJsonFile(filePath, defaultValue = []) {
  try {
    if (await fileExists(filePath)) {
      const content = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(content);
    }
  } catch (e) {
    console.error('Error loading file:', filePath, e);
  }
  return defaultValue;
}

async function saveJsonFile(filePath, data) {
  await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
}

// ==================== ШАБЛОНЫ ЗАДАЧ ====================

const TEMPLATES_FILE = path.join(RECURRING_TASKS_DIR, 'all.json');
const SCHEDULER_STATE_FILE = path.join(RECURRING_TASKS_DIR, 'scheduler-state.json');

async function loadTemplates() {
  return await loadJsonFile(TEMPLATES_FILE, []);
}

async function saveTemplates(templates) {
  await saveJsonFile(TEMPLATES_FILE, templates);
}

async function loadSchedulerState() {
  return await loadJsonFile(SCHEDULER_STATE_FILE, {
    lastGenerationDate: null,
    lastExpiredCheck: null
  });
}

async function saveSchedulerState(state) {
  await saveJsonFile(SCHEDULER_STATE_FILE, state);
}

// ==================== ЭКЗЕМПЛЯРЫ ЗАДАЧ ====================

async function loadInstances(yearMonth) {
  const filePath = path.join(RECURRING_INSTANCES_DIR, yearMonth + '.json');
  return await loadJsonFile(filePath, []);
}

async function saveInstances(yearMonth, instances) {
  const filePath = path.join(RECURRING_INSTANCES_DIR, yearMonth + '.json');
  await saveJsonFile(filePath, instances);
}

// ==================== ГЕНЕРАЦИЯ ЗАДАЧ ====================

// Генерация экземпляров для одного шаблона (при создании)
async function generateInstancesForTemplate(template, date) {
  const yearMonth = getYearMonth(date);
  let instances = await loadInstances(yearMonth);
  let generatedCount = 0;

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
    generatedCount++;
  }

  if (generatedCount > 0) {
    await saveInstances(yearMonth, instances);
    console.log('Generated', generatedCount, 'instances for new template:', template.id);
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
      generatedCount++;
    }
  }

  await saveInstances(yearMonth, instances);
  console.log('Generated', generatedCount, 'recurring task instances for', date);
  return generatedCount;
}

async function checkExpiredTasks() {
  const now = new Date();
  const today = getToday();
  const yearMonth = getYearMonth(today);
  let instances = await loadInstances(yearMonth);

  let expiredCount = 0;
  const penalties = [];

  for (const instance of instances) {
    if (instance.status !== 'pending') continue;

    const deadline = new Date(instance.deadline);
    if (now > deadline) {
      instance.status = 'expired';
      instance.expiredAt = now.toISOString();
      expiredCount++;

      // Создаем штраф
      penalties.push({
        id: 'penalty_' + Date.now() + '_' + Math.random().toString(36).substr(2, 9),
        type: 'employee',
        entityId: instance.assigneeId,
        entityName: instance.assigneeName,
        category: 'recurring_task_penalty',
        categoryName: 'Штраф за циклическую задачу',
        date: instance.date,
        points: -3,
        reason: 'expired',
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
    await saveJsonFile(penaltiesFile, existingPenalties);

    console.log('Expired', expiredCount, 'recurring task instances, created', penalties.length, 'penalties');
  }

  return expiredCount;
}

// ==================== ПЛАНИРОВЩИК ====================

function startScheduler() {
  console.log('Starting recurring tasks scheduler...');

  // Каждые 5 минут
  setInterval(async () => {
    try {
      const today = getToday();
      const state = await loadSchedulerState();

      // Генерация задач в новый день
      if (state.lastGenerationDate !== today) {
        await generateDailyTasks(today);
        state.lastGenerationDate = today;
        await saveSchedulerState(state);
      }

      // Проверка expired каждые 5 минут
      await checkExpiredTasks();
      state.lastExpiredCheck = new Date().toISOString();
      await saveSchedulerState(state);

    } catch (e) {
      console.error('Scheduler error:', e);
    }
  }, 5 * 60 * 1000); // 5 минут

  // Первый запуск сразу
  setTimeout(async () => {
    try {
      const today = getToday();
      const state = await loadSchedulerState();

      if (state.lastGenerationDate !== today) {
        await generateDailyTasks(today);
        state.lastGenerationDate = today;
        await saveSchedulerState(state);
      }
      await checkExpiredTasks();
    } catch (e) {
      console.error('Initial scheduler run error:', e);
    }
  }, 1000);
}

// ==================== SETUP FUNCTION ====================

function setupRecurringTasksAPI(app) {
  console.log('Setting up Recurring Tasks API...');

  // GET /api/recurring-tasks - Список всех шаблонов
  app.get('/api/recurring-tasks', async (req, res) => {
    try {
      const templates = await loadTemplates();
      res.json({ success: true, tasks: templates });
    } catch (e) {
      console.error('Error getting recurring tasks:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // GET /api/recurring-tasks/instances/list - Список экземпляров
  app.get('/api/recurring-tasks/instances/list', async (req, res) => {
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

      res.json({ success: true, instances });
    } catch (e) {
      console.error('Error getting instances:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/recurring-tasks/instances/:id/complete - Выполнить задачу
  app.post('/api/recurring-tasks/instances/:id/complete', async (req, res) => {
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
  app.get('/api/recurring-tasks/:id', async (req, res) => {
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
  app.post('/api/recurring-tasks', async (req, res) => {
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
        createdBy
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
  app.put('/api/recurring-tasks/:id', async (req, res) => {
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
        assignees
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
  app.put('/api/recurring-tasks/:id/toggle-pause', async (req, res) => {
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
  app.delete('/api/recurring-tasks/:id', async (req, res) => {
    try {
      const templates = await loadTemplates();
      const index = templates.findIndex(t => t.id === req.params.id);

      if (index === -1) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }

      templates.splice(index, 1);
      await saveTemplates(templates);

      console.log('Deleted recurring task:', req.params.id);
      res.json({ success: true });
    } catch (e) {
      console.error('Error deleting recurring task:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/recurring-tasks/generate-daily - Ручная генерация (для тестирования)
  app.post('/api/recurring-tasks/generate-daily', async (req, res) => {
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
  app.post('/api/recurring-tasks/check-expired', async (req, res) => {
    try {
      const count = await checkExpiredTasks();
      res.json({ success: true, expiredCount: count });
    } catch (e) {
      console.error('Error checking expired:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // Запускаем планировщик
  startScheduler();

  console.log('Recurring Tasks API setup complete');
}

// Экспортируем
module.exports = { setupRecurringTasksAPI };
