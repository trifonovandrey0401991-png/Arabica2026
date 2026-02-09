/**
 * Tasks API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { sendPushToPhone, sendPushNotification } = require('./report_notifications_api');
const { getTaskPointsConfig } = require('./task_points_settings_api');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');

const dataCache = require('../utils/data_cache');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const TASKS_DIR = `${DATA_DIR}/tasks`;
const TASK_ASSIGNMENTS_DIR = `${DATA_DIR}/task-assignments`;
const EMPLOYEES_DIR = `${DATA_DIR}/employees`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directories exist
async function ensureDir(dir) {
  if (!(await fileExists(dir))) {
    await fsp.mkdir(dir, { recursive: true });
  }
}

// Get month key from date (YYYY-MM)
function getMonthKey(date) {
  if (!date) {
    const now = new Date();
    return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
  }
  if (date instanceof Date) {
    return `${date.getFullYear()}-${String(date.getMonth() + 1).padStart(2, '0')}`;
  }
  return date.substring(0, 7);
}

// Generate unique ID
function generateId(prefix = 'task') {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
}

// Get employee phone by ID (uses cache for O(1) lookup instead of scanning all files)
async function getEmployeePhoneById(employeeId) {
  try {
    // 1. Прямой файл по ID (быстрый путь)
    const filePath = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
    if (await fileExists(filePath)) {
      const data = await fsp.readFile(filePath, 'utf8');
      const employee = JSON.parse(data);
      return employee.phone || null;
    }
    // 2. Поиск через кэш (вместо сканирования всех файлов)
    const employees = await dataCache.getEmployees();
    if (Array.isArray(employees)) {
      const found = employees.find(emp => emp.name === employeeId || emp.id === employeeId);
      if (found) return found.phone || null;
    }
  } catch (e) {
    console.error('Error getting employee phone:', e);
  }
  return null;
}

// Get employee name by phone
async function getEmployeeNameByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[\s\+]/g, '');
    if (await fileExists(EMPLOYEES_DIR)) {
      const files = (await fsp.readdir(EMPLOYEES_DIR)).filter(f => f.endsWith('.json'));
      for (const file of files) {
        const empData = await fsp.readFile(path.join(EMPLOYEES_DIR, file), 'utf8');
        const emp = JSON.parse(empData);
        const empPhone = (emp.phone || '').replace(/[\s\+]/g, '');
        if (empPhone === normalizedPhone) {
          return emp.name || null;
        }
      }
    }
  } catch (e) {
    console.error('Error getting employee name:', e);
  }
  return null;
}

// Save penalty to efficiency-penalties
// Поддерживает два формата: массив [] и объект {penalties: []}
async function savePenalty(penalty) {
  try {
    await ensureDir(EFFICIENCY_PENALTIES_DIR);
    const monthKey = penalty.date.substring(0, 7); // YYYY-MM
    const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);

    let penalties = [];
    if (await fileExists(filePath)) {
      const fileContent = JSON.parse(await fsp.readFile(filePath, 'utf8'));
      // Поддержка обоих форматов
      if (Array.isArray(fileContent)) {
        penalties = fileContent;
      } else if (fileContent.penalties && Array.isArray(fileContent.penalties)) {
        penalties = fileContent.penalties;
      }
    }

    penalties.push(penalty);
    // Сохраняем в формате массива (как используется в других частях системы)
    await fsp.writeFile(filePath, JSON.stringify(penalties, null, 2), 'utf8');

    console.log(`✅ Penalty saved: ${penalty.employeeName}, ${penalty.points} points, reason: ${penalty.reason}`);
    return true;
  } catch (e) {
    console.error('Error saving penalty:', e);
    return false;
  }
}

// Load tasks for a month
async function loadMonthTasks(monthKey) {
  await ensureDir(TASKS_DIR);
  const filePath = path.join(TASKS_DIR, `${monthKey}.json`);

  if (await fileExists(filePath)) {
    try {
      const data = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(data);
    } catch (e) {
      console.error(`Error reading tasks for ${monthKey}:`, e);
      return { monthKey, tasks: [] };
    }
  }
  return { monthKey, tasks: [] };
}

// Save tasks for a month
async function saveMonthTasks(monthKey, data) {
  await ensureDir(TASKS_DIR);
  const filePath = path.join(TASKS_DIR, `${monthKey}.json`);
  data.updatedAt = new Date().toISOString();
  await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
}

// Load assignments for a month
async function loadMonthAssignments(monthKey) {
  await ensureDir(TASK_ASSIGNMENTS_DIR);
  const filePath = path.join(TASK_ASSIGNMENTS_DIR, `${monthKey}.json`);

  if (await fileExists(filePath)) {
    try {
      const data = await fsp.readFile(filePath, 'utf8');
      return JSON.parse(data);
    } catch (e) {
      console.error(`Error reading assignments for ${monthKey}:`, e);
      return { monthKey, assignments: [] };
    }
  }
  return { monthKey, assignments: [] };
}

// Save assignments for a month
async function saveMonthAssignments(monthKey, data) {
  await ensureDir(TASK_ASSIGNMENTS_DIR);
  const filePath = path.join(TASK_ASSIGNMENTS_DIR, `${monthKey}.json`);
  data.updatedAt = new Date().toISOString();
  await fsp.writeFile(filePath, JSON.stringify(data, null, 2), 'utf8');
}

// Get all tasks (across months)
async function getAllTasks(fromMonth, toMonth) {
  await ensureDir(TASKS_DIR);
  const files = (await fsp.readdir(TASKS_DIR)).filter(f => f.endsWith('.json'));
  let allTasks = [];

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    if (fromMonth && monthKey < fromMonth) continue;
    if (toMonth && monthKey > toMonth) continue;

    const data = await loadMonthTasks(monthKey);
    allTasks.push(...(data.tasks || []));
  }

  return allTasks;
}

// Get all assignments (across months)
async function getAllAssignments(fromMonth, toMonth) {
  await ensureDir(TASK_ASSIGNMENTS_DIR);
  const files = (await fsp.readdir(TASK_ASSIGNMENTS_DIR)).filter(f => f.endsWith('.json'));
  let allAssignments = [];

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    if (fromMonth && monthKey < fromMonth) continue;
    if (toMonth && monthKey > toMonth) continue;

    const data = await loadMonthAssignments(monthKey);
    allAssignments.push(...(data.assignments || []));
  }

  return allAssignments;
}

// Парсит дедлайн как московское время (UTC+3)
function parseDeadlineAsMoscow(deadlineStr) {
  if (!deadlineStr) return new Date();
  if (deadlineStr.endsWith('Z')) return new Date(deadlineStr);
  if (/[+-]\d{2}:\d{2}$/.test(deadlineStr)) return new Date(deadlineStr);
  // Время без timezone = московское время (UTC+3)
  return new Date(deadlineStr + '+03:00');
}

// Check and update expired tasks with penalties and push notifications
async function checkExpiredTasks() {
  const now = new Date();
  await ensureDir(TASK_ASSIGNMENTS_DIR);
  const files = (await fsp.readdir(TASK_ASSIGNMENTS_DIR)).filter(f => f.endsWith('.json'));
  const tasks = await getAllTasks();
  const tasksMap = {};
  for (const t of tasks) {
    tasksMap[t.id] = t;
  }

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    const data = await loadMonthAssignments(monthKey);
    let updated = false;

    for (const assignment of data.assignments) {
      if (assignment.status === 'pending') {
        const deadline = parseDeadlineAsMoscow(assignment.deadline);
        if (deadline < now) {
          assignment.status = 'expired';
          assignment.expiredAt = now.toISOString();
          updated = true;

          const task = tasksMap[assignment.taskId];
          const taskTitle = task ? task.title : 'Неизвестная задача';

          console.log(`Task assignment ${assignment.id} expired: ${taskTitle}`);

          // 1. Создаём штраф
          const config = await getTaskPointsConfig();
          const penalty = {
            id: `task_expired_${Date.now()}_${Math.random().toString(36).substr(2, 5)}`,
            employeeName: assignment.assigneeName,
            category: 'regular_task_penalty',
            categoryName: 'Просроченная задача',
            points: config.regularTasks.penaltyPoints,
            reason: `Задача "${taskTitle}" не выполнена в срок`,
            date: now.toISOString().split('T')[0],
            createdAt: now.toISOString(),
            taskId: assignment.taskId,
            assignmentId: assignment.id
          };
          await savePenalty(penalty);

          // 2. Push сотруднику
          const employeePhone = await getEmployeePhoneById(assignment.assigneeId);
          if (employeePhone) {
            await sendPushToPhone(
              employeePhone,
              'Задача просрочена',
              `Вы не выполнили задачу "${taskTitle}" в срок. Начислен штраф ${config.regularTasks.penaltyPoints} баллов.`,
              { type: 'task_expired', assignmentId: assignment.id, taskId: assignment.taskId }
            );
          }

          // 3. Push админам
          await sendPushNotification(
            'Задача не выполнена',
            `${assignment.assigneeName} не выполнил задачу "${taskTitle}"`,
            { type: 'task_expired_admin', assignmentId: assignment.id, taskId: assignment.taskId }
          );
        }
      }
    }

    if (updated) {
      await saveMonthAssignments(monthKey, data);
    }
  }
}

// Check for reminders (1 hour before deadline)
async function checkTaskReminders() {
  const now = new Date();
  const oneHourLater = new Date(now.getTime() + 60 * 60 * 1000);
  await ensureDir(TASK_ASSIGNMENTS_DIR);
  const files = (await fsp.readdir(TASK_ASSIGNMENTS_DIR)).filter(f => f.endsWith('.json'));
  const tasks = await getAllTasks();
  const tasksMap = {};
  for (const t of tasks) {
    tasksMap[t.id] = t;
  }

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    const data = await loadMonthAssignments(monthKey);
    let updated = false;

    for (const assignment of data.assignments) {
      // Только pending задачи без отправленного напоминания
      if (assignment.status === 'pending' && !assignment.reminderSent) {
        const deadline = new Date(assignment.deadline);
        // Напоминание за 1 час до дедлайна
        if (deadline > now && deadline <= oneHourLater) {
          const task = tasksMap[assignment.taskId];
          const taskTitle = task ? task.title : 'Задача';

          // Отправляем напоминание
          const employeePhone = await getEmployeePhoneById(assignment.assigneeId);
          if (employeePhone) {
            await sendPushToPhone(
              employeePhone,
              'Напоминание о задаче',
              `До дедлайна задачи "${taskTitle}" осталось менее 1 часа!`,
              { type: 'task_reminder', assignmentId: assignment.id, taskId: assignment.taskId }
            );
            assignment.reminderSent = true;
            assignment.reminderSentAt = now.toISOString();
            updated = true;
            console.log(`⏰ Reminder sent for task ${assignment.id}: ${taskTitle}`);
          }
        }
      }
    }

    if (updated) {
      await saveMonthAssignments(monthKey, data);
    }
  }
}

function setupTasksAPI(app) {
  // ===== TASKS =====

  // POST /api/tasks - Create a task
  app.post('/api/tasks', async (req, res) => {
    try {
      const task = req.body;
      console.log('POST /api/tasks:', task.title);

      // Validate required fields
      if (!task.title || !task.responseType || !task.deadline || !task.recipients || task.recipients.length === 0) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: title, responseType, deadline, recipients'
        });
      }

      const taskId = generateId('task');
      const now = new Date().toISOString();
      const monthKey = getMonthKey();

      // Create task
      const newTask = {
        id: taskId,
        title: task.title,
        description: task.description || '',
        responseType: task.responseType, // 'photo', 'photoAndText', 'text'
        deadline: task.deadline,
        createdBy: task.createdBy || 'admin',
        createdAt: now,
      };

      // Save task
      const tasksData = await loadMonthTasks(monthKey);
      tasksData.tasks.push(newTask);
      await saveMonthTasks(monthKey, tasksData);

      // Create assignments for each recipient
      const assignmentsData = await loadMonthAssignments(monthKey);
      const newAssignments = [];

      for (const recipient of task.recipients) {
        const assignment = {
          id: generateId('assign'),
          taskId: taskId,
          assigneeId: recipient.id,
          assigneeName: recipient.name,
          assigneeRole: recipient.role || 'employee',
          status: 'pending',
          deadline: task.deadline,
          createdAt: now,
          responseText: null,
          responsePhotos: [],
          respondedAt: null,
          reviewedBy: null,
          reviewedAt: null,
          reviewComment: null,
        };
        assignmentsData.assignments.push(assignment);
        newAssignments.push(assignment);
      }

      await saveMonthAssignments(monthKey, assignmentsData);

      console.log(`  Created task ${taskId} with ${newAssignments.length} assignments`);

      // Отправляем push-уведомления всем исполнителям
      for (const assignment of newAssignments) {
        const employeePhone = await getEmployeePhoneById(assignment.assigneeId);
        if (employeePhone) {
          await sendPushToPhone(
            employeePhone,
            'У Вас Новая Задача',
            newTask.title,
            { type: 'new_task', taskId: taskId, assignmentId: assignment.id }
          );
          console.log(`  Push sent to ${assignment.assigneeName} (${employeePhone})`);
        } else {
          console.log(`  No phone found for ${assignment.assigneeName} (${assignment.assigneeId})`);
        }
      }

      res.json({
        success: true,
        task: newTask,
        assignments: newAssignments,
      });
    } catch (error) {
      console.error('Error creating task:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/tasks - Get all tasks
  app.get('/api/tasks', async (req, res) => {
    try {
      const { month, createdBy } = req.query;
      console.log('GET /api/tasks', { month, createdBy });

      let tasks;
      if (month) {
        const data = await loadMonthTasks(month);
        tasks = data.tasks || [];
      } else {
        tasks = await getAllTasks();
      }

      if (createdBy) {
        tasks = tasks.filter(t => t.createdBy === createdBy);
      }

      // Sort by creation date descending
      tasks.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      if (isPaginationRequested(req.query)) {
        res.json(createPaginatedResponse(tasks, req.query, 'tasks'));
      } else {
        res.json({ success: true, tasks });
      }
    } catch (error) {
      console.error('Error getting tasks:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/tasks/:id - Get a single task with its assignments
  app.get('/api/tasks/:id', async (req, res) => {
    try {
      const { id } = req.params;
      console.log('GET /api/tasks/:id', id);

      const tasks = await getAllTasks();
      const task = tasks.find(t => t.id === id);

      if (!task) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }

      const allAssignments = await getAllAssignments();
      const assignments = allAssignments.filter(a => a.taskId === id);

      res.json({ success: true, task, assignments });
    } catch (error) {
      console.error('Error getting task:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== TASK ASSIGNMENTS =====

  // GET /api/task-assignments - Get assignments (filtered)
  app.get('/api/task-assignments', async (req, res) => {
    try {
      const { assigneeId, status, month, taskId } = req.query;
      console.log('GET /api/task-assignments', { assigneeId, status, month, taskId });

      // Check for expired tasks first
      await checkExpiredTasks();

      let assignments;
      if (month) {
        const data = await loadMonthAssignments(month);
        assignments = data.assignments || [];
      } else {
        assignments = await getAllAssignments();
      }

      if (assigneeId) {
        assignments = assignments.filter(a => a.assigneeId === assigneeId);
      }
      if (status) {
        const statuses = status.split(',');
        assignments = assignments.filter(a => statuses.includes(a.status));
      }
      if (taskId) {
        assignments = assignments.filter(a => a.taskId === taskId);
      }

      // Load task info for each assignment
      const tasks = await getAllTasks();
      const tasksMap = {};
      for (const t of tasks) {
        tasksMap[t.id] = t;
      }

      const enrichedAssignments = assignments.map(a => ({
        ...a,
        task: tasksMap[a.taskId] || null,
      }));

      // Sort by deadline ascending (most urgent first)
      enrichedAssignments.sort((a, b) => new Date(a.deadline) - new Date(b.deadline));

      res.json({ success: true, assignments: enrichedAssignments });
    } catch (error) {
      console.error('Error getting task assignments:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/task-assignments/:id/respond - Respond to a task
  app.post('/api/task-assignments/:id/respond', async (req, res) => {
    try {
      const { id } = req.params;
      const { responseText, responsePhotos } = req.body;
      console.log('POST /api/task-assignments/:id/respond', id);

      // Find the assignment
      await ensureDir(TASK_ASSIGNMENTS_DIR);
      const files = (await fsp.readdir(TASK_ASSIGNMENTS_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        const monthKey = file.replace('.json', '');
        const data = await loadMonthAssignments(monthKey);
        const assignment = data.assignments.find(a => a.id === id);

        if (assignment) {
          if (assignment.status !== 'pending') {
            return res.status(400).json({
              success: false,
              error: `Cannot respond: assignment status is '${assignment.status}'`
            });
          }

          // Check if deadline passed
          if (new Date(assignment.deadline) < new Date()) {
            assignment.status = 'expired';
            assignment.expiredAt = new Date().toISOString();
            await saveMonthAssignments(monthKey, data);
            return res.status(400).json({
              success: false,
              error: 'Cannot respond: deadline has passed'
            });
          }

          assignment.responseText = responseText || null;
          assignment.responsePhotos = responsePhotos || [];
          assignment.respondedAt = new Date().toISOString();
          assignment.status = 'submitted';

          await saveMonthAssignments(monthKey, data);

          // Get task info
          const tasks = await getAllTasks();
          const task = tasks.find(t => t.id === assignment.taskId);

          return res.json({
            success: true,
            assignment: { ...assignment, task },
          });
        }
      }

      res.status(404).json({ success: false, error: 'Assignment not found' });
    } catch (error) {
      console.error('Error responding to task:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/task-assignments/:id/decline - Decline a task
  app.post('/api/task-assignments/:id/decline', async (req, res) => {
    try {
      const { id } = req.params;
      const { reason } = req.body;
      console.log('POST /api/task-assignments/:id/decline', id);

      // Find the assignment
      await ensureDir(TASK_ASSIGNMENTS_DIR);
      const files = (await fsp.readdir(TASK_ASSIGNMENTS_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        const monthKey = file.replace('.json', '');
        const data = await loadMonthAssignments(monthKey);
        const assignment = data.assignments.find(a => a.id === id);

        if (assignment) {
          if (assignment.status !== 'pending') {
            return res.status(400).json({
              success: false,
              error: `Cannot decline: assignment status is '${assignment.status}'`
            });
          }

          assignment.status = 'declined';
          assignment.declinedAt = new Date().toISOString();
          assignment.declineReason = reason || null;

          await saveMonthAssignments(monthKey, data);

          // Get task info
          const tasks = await getAllTasks();
          const task = tasks.find(t => t.id === assignment.taskId);

          return res.json({
            success: true,
            assignment: { ...assignment, task },
          });
        }
      }

      res.status(404).json({ success: false, error: 'Assignment not found' });
    } catch (error) {
      console.error('Error declining task:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/task-assignments/:id/review - Review a task (admin)
  app.post('/api/task-assignments/:id/review', async (req, res) => {
    try {
      const { id } = req.params;
      const { approved, reviewedBy, reviewComment } = req.body;
      console.log('POST /api/task-assignments/:id/review', id, { approved, reviewedBy });

      // Find the assignment
      await ensureDir(TASK_ASSIGNMENTS_DIR);
      const files = (await fsp.readdir(TASK_ASSIGNMENTS_DIR)).filter(f => f.endsWith('.json'));

      for (const file of files) {
        const monthKey = file.replace('.json', '');
        const data = await loadMonthAssignments(monthKey);
        const assignment = data.assignments.find(a => a.id === id);

        if (assignment) {
          if (assignment.status !== 'submitted') {
            return res.status(400).json({
              success: false,
              error: `Cannot review: assignment status is '${assignment.status}', expected 'submitted'`
            });
          }

          assignment.status = approved ? 'approved' : 'rejected';
          assignment.reviewedBy = reviewedBy || 'admin';
          assignment.reviewedAt = new Date().toISOString();
          assignment.reviewComment = reviewComment || null;

          await saveMonthAssignments(monthKey, data);

          // Get task info
          const tasks = await getAllTasks();
          const task = tasks.find(t => t.id === assignment.taskId);

          return res.json({
            success: true,
            assignment: { ...assignment, task },
          });
        }
      }

      res.status(404).json({ success: false, error: 'Assignment not found' });
    } catch (error) {
      console.error('Error reviewing task:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/task-assignments/stats - Get statistics for reports
  app.get('/api/task-assignments/stats', async (req, res) => {
    try {
      const { month } = req.query;
      console.log('GET /api/task-assignments/stats', { month });

      // Check for expired tasks first
      await checkExpiredTasks();

      let assignments;
      if (month) {
        const data = await loadMonthAssignments(month);
        assignments = data.assignments || [];
      } else {
        assignments = await getAllAssignments();
      }

      const stats = {
        total: assignments.length,
        pending: assignments.filter(a => a.status === 'pending').length,
        submitted: assignments.filter(a => a.status === 'submitted').length,
        approved: assignments.filter(a => a.status === 'approved').length,
        rejected: assignments.filter(a => a.status === 'rejected').length,
        expired: assignments.filter(a => a.status === 'expired').length,
        declined: assignments.filter(a => a.status === 'declined').length,
      };

      res.json({ success: true, stats });
    } catch (error) {
      console.error('Error getting task stats:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/task-assignments/unviewed-expired-count - Count unviewed expired tasks
  app.get('/api/task-assignments/unviewed-expired-count', async (req, res) => {
    try {
      console.log('GET /api/task-assignments/unviewed-expired-count');

      // Check for expired tasks first
      await checkExpiredTasks();

      const assignments = await getAllAssignments();
      // Непросмотренные - у которых viewedByAdmin !== true и статус expired, rejected или declined
      const unviewedExpired = assignments.filter(a =>
        (a.status === 'expired' || a.status === 'rejected' || a.status === 'declined') &&
        a.viewedByAdmin !== true
      );

      res.json({ success: true, count: unviewedExpired.length });
    } catch (error) {
      console.error('Error getting unviewed expired count:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/task-assignments/mark-expired-viewed - Mark all expired tasks as viewed
  app.post('/api/task-assignments/mark-expired-viewed', async (req, res) => {
    try {
      console.log('POST /api/task-assignments/mark-expired-viewed');

      await ensureDir(TASK_ASSIGNMENTS_DIR);
      const files = (await fsp.readdir(TASK_ASSIGNMENTS_DIR)).filter(f => f.endsWith('.json'));
      let markedCount = 0;

      for (const file of files) {
        const monthKey = file.replace('.json', '');
        const data = await loadMonthAssignments(monthKey);
        let updated = false;

        for (const assignment of data.assignments) {
          if ((assignment.status === 'expired' || assignment.status === 'rejected' || assignment.status === 'declined') &&
              assignment.viewedByAdmin !== true) {
            assignment.viewedByAdmin = true;
            assignment.viewedByAdminAt = new Date().toISOString();
            updated = true;
            markedCount++;
          }
        }

        if (updated) {
          await saveMonthAssignments(monthKey, data);
        }
      }

      console.log(`Marked ${markedCount} expired tasks as viewed`);
      res.json({ success: true, markedCount });
    } catch (error) {
      console.error('Error marking expired tasks as viewed:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // Запускаем планировщик проверки просроченных задач и напоминаний
  console.log('Starting task scheduler (every 5 minutes)...');

  // Проверка при старте
  setTimeout(async () => {
    await checkExpiredTasks();
    await checkTaskReminders();
  }, 10000); // Через 10 секунд после старта

  // Каждые 5 минут
  setInterval(async () => {
    await checkExpiredTasks();
    await checkTaskReminders();
  }, 5 * 60 * 1000);

  console.log('Tasks API initialized');
}

module.exports = { setupTasksAPI, checkExpiredTasks, checkTaskReminders };
