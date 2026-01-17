const fs = require('fs');
const path = require('path');
const { sendPushToPhone, sendPushNotification } = require('./report_notifications_api');
const { getTaskPointsConfig } = require('./api/task_points_settings_api');

const TASKS_DIR = '/var/www/tasks';
const TASK_ASSIGNMENTS_DIR = '/var/www/task-assignments';
const EMPLOYEES_DIR = '/var/www/employees';
const EFFICIENCY_PENALTIES_DIR = '/var/www/efficiency-penalties';

// Ensure directories exist
function ensureDir(dir) {
  if (!fs.existsSync(dir)) {
    fs.mkdirSync(dir, { recursive: true });
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

// Get employee phone by ID
function getEmployeePhoneById(employeeId) {
  try {
    const filePath = path.join(EMPLOYEES_DIR, `${employeeId}.json`);
    if (fs.existsSync(filePath)) {
      const employee = JSON.parse(fs.readFileSync(filePath, 'utf8'));
      return employee.phone || null;
    }
    // Попробуем найти по имени (если id - это имя)
    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));
    for (const file of files) {
      const emp = JSON.parse(fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8'));
      if (emp.name === employeeId || emp.id === employeeId) {
        return emp.phone || null;
      }
    }
  } catch (e) {
    console.error('Error getting employee phone:', e);
  }
  return null;
}

// Get employee name by phone
function getEmployeeNameByPhone(phone) {
  try {
    const normalizedPhone = phone.replace(/[\s\+]/g, '');
    const files = fs.readdirSync(EMPLOYEES_DIR).filter(f => f.endsWith('.json'));
    for (const file of files) {
      const emp = JSON.parse(fs.readFileSync(path.join(EMPLOYEES_DIR, file), 'utf8'));
      const empPhone = (emp.phone || '').replace(/[\s\+]/g, '');
      if (empPhone === normalizedPhone) {
        return emp.name || null;
      }
    }
  } catch (e) {
    console.error('Error getting employee name:', e);
  }
  return null;
}

// Save penalty to efficiency-penalties
function savePenalty(penalty) {
  try {
    ensureDir(EFFICIENCY_PENALTIES_DIR);
    const monthKey = penalty.date.substring(0, 7); // YYYY-MM
    const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);

    let data = { monthKey, penalties: [] };
    if (fs.existsSync(filePath)) {
      data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    }

    data.penalties.push(penalty);
    data.updatedAt = new Date().toISOString();
    fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');

    console.log(`✅ Penalty saved: ${penalty.employeeName}, ${penalty.points} points, reason: ${penalty.reason}`);
    return true;
  } catch (e) {
    console.error('Error saving penalty:', e);
    return false;
  }
}

// Load tasks for a month
function loadMonthTasks(monthKey) {
  ensureDir(TASKS_DIR);
  const filePath = path.join(TASKS_DIR, `${monthKey}.json`);

  if (fs.existsSync(filePath)) {
    try {
      return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (e) {
      console.error(`Error reading tasks for ${monthKey}:`, e);
      return { monthKey, tasks: [] };
    }
  }
  return { monthKey, tasks: [] };
}

// Save tasks for a month
function saveMonthTasks(monthKey, data) {
  ensureDir(TASKS_DIR);
  const filePath = path.join(TASKS_DIR, `${monthKey}.json`);
  data.updatedAt = new Date().toISOString();
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
}

// Load assignments for a month
function loadMonthAssignments(monthKey) {
  ensureDir(TASK_ASSIGNMENTS_DIR);
  const filePath = path.join(TASK_ASSIGNMENTS_DIR, `${monthKey}.json`);

  if (fs.existsSync(filePath)) {
    try {
      return JSON.parse(fs.readFileSync(filePath, 'utf8'));
    } catch (e) {
      console.error(`Error reading assignments for ${monthKey}:`, e);
      return { monthKey, assignments: [] };
    }
  }
  return { monthKey, assignments: [] };
}

// Save assignments for a month
function saveMonthAssignments(monthKey, data) {
  ensureDir(TASK_ASSIGNMENTS_DIR);
  const filePath = path.join(TASK_ASSIGNMENTS_DIR, `${monthKey}.json`);
  data.updatedAt = new Date().toISOString();
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), 'utf8');
}

// Get all tasks (across months)
function getAllTasks(fromMonth, toMonth) {
  ensureDir(TASKS_DIR);
  const files = fs.readdirSync(TASKS_DIR).filter(f => f.endsWith('.json'));
  let allTasks = [];

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    if (fromMonth && monthKey < fromMonth) continue;
    if (toMonth && monthKey > toMonth) continue;

    const data = loadMonthTasks(monthKey);
    allTasks.push(...(data.tasks || []));
  }

  return allTasks;
}

// Get all assignments (across months)
function getAllAssignments(fromMonth, toMonth) {
  ensureDir(TASK_ASSIGNMENTS_DIR);
  const files = fs.readdirSync(TASK_ASSIGNMENTS_DIR).filter(f => f.endsWith('.json'));
  let allAssignments = [];

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    if (fromMonth && monthKey < fromMonth) continue;
    if (toMonth && monthKey > toMonth) continue;

    const data = loadMonthAssignments(monthKey);
    allAssignments.push(...(data.assignments || []));
  }

  return allAssignments;
}

// Check and update expired tasks with penalties and push notifications
async function checkExpiredTasks() {
  const now = new Date();
  const files = fs.readdirSync(TASK_ASSIGNMENTS_DIR).filter(f => f.endsWith('.json'));
  const tasks = getAllTasks();
  const tasksMap = {};
  for (const t of tasks) {
    tasksMap[t.id] = t;
  }

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    const data = loadMonthAssignments(monthKey);
    let updated = false;

    for (const assignment of data.assignments) {
      if (assignment.status === 'pending') {
        const deadline = new Date(assignment.deadline);
        if (deadline < now) {
          assignment.status = 'expired';
          assignment.expiredAt = now.toISOString();
          updated = true;

          const task = tasksMap[assignment.taskId];
          const taskTitle = task ? task.title : 'Неизвестная задача';

          console.log(`❌ Task assignment ${assignment.id} expired: ${taskTitle}`);

          // 1. Создаём штраф
          const config = getTaskPointsConfig();
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
          savePenalty(penalty);

          // 2. Push сотруднику
          const employeePhone = getEmployeePhoneById(assignment.assigneeId);
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
      saveMonthAssignments(monthKey, data);
    }
  }
}

// Check for reminders (1 hour before deadline)
async function checkTaskReminders() {
  const now = new Date();
  const oneHourLater = new Date(now.getTime() + 60 * 60 * 1000);
  const files = fs.readdirSync(TASK_ASSIGNMENTS_DIR).filter(f => f.endsWith('.json'));
  const tasks = getAllTasks();
  const tasksMap = {};
  for (const t of tasks) {
    tasksMap[t.id] = t;
  }

  for (const file of files) {
    const monthKey = file.replace('.json', '');
    const data = loadMonthAssignments(monthKey);
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
          const employeePhone = getEmployeePhoneById(assignment.assigneeId);
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
      saveMonthAssignments(monthKey, data);
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
      const tasksData = loadMonthTasks(monthKey);
      tasksData.tasks.push(newTask);
      saveMonthTasks(monthKey, tasksData);

      // Create assignments for each recipient
      const assignmentsData = loadMonthAssignments(monthKey);
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

      saveMonthAssignments(monthKey, assignmentsData);

      console.log(`  Created task ${taskId} with ${newAssignments.length} assignments`);

      // Отправляем push-уведомления всем исполнителям
      for (const assignment of newAssignments) {
        const employeePhone = getEmployeePhoneById(assignment.assigneeId);
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
        const data = loadMonthTasks(month);
        tasks = data.tasks || [];
      } else {
        tasks = getAllTasks();
      }

      if (createdBy) {
        tasks = tasks.filter(t => t.createdBy === createdBy);
      }

      // Sort by creation date descending
      tasks.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

      res.json({ success: true, tasks });
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

      const tasks = getAllTasks();
      const task = tasks.find(t => t.id === id);

      if (!task) {
        return res.status(404).json({ success: false, error: 'Task not found' });
      }

      const assignments = getAllAssignments().filter(a => a.taskId === id);

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
      checkExpiredTasks();

      let assignments;
      if (month) {
        const data = loadMonthAssignments(month);
        assignments = data.assignments || [];
      } else {
        assignments = getAllAssignments();
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
      const tasks = getAllTasks();
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
      const files = fs.readdirSync(TASK_ASSIGNMENTS_DIR).filter(f => f.endsWith('.json'));

      for (const file of files) {
        const monthKey = file.replace('.json', '');
        const data = loadMonthAssignments(monthKey);
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
            saveMonthAssignments(monthKey, data);
            return res.status(400).json({
              success: false,
              error: 'Cannot respond: deadline has passed'
            });
          }

          assignment.responseText = responseText || null;
          assignment.responsePhotos = responsePhotos || [];
          assignment.respondedAt = new Date().toISOString();
          assignment.status = 'submitted';

          saveMonthAssignments(monthKey, data);

          // Get task info
          const tasks = getAllTasks();
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
      const files = fs.readdirSync(TASK_ASSIGNMENTS_DIR).filter(f => f.endsWith('.json'));

      for (const file of files) {
        const monthKey = file.replace('.json', '');
        const data = loadMonthAssignments(monthKey);
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

          saveMonthAssignments(monthKey, data);

          // Get task info
          const tasks = getAllTasks();
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
      const files = fs.readdirSync(TASK_ASSIGNMENTS_DIR).filter(f => f.endsWith('.json'));

      for (const file of files) {
        const monthKey = file.replace('.json', '');
        const data = loadMonthAssignments(monthKey);
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

          saveMonthAssignments(monthKey, data);

          // Get task info
          const tasks = getAllTasks();
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
      checkExpiredTasks();

      let assignments;
      if (month) {
        const data = loadMonthAssignments(month);
        assignments = data.assignments || [];
      } else {
        assignments = getAllAssignments();
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

  // Запускаем планировщик проверки просроченных задач и напоминаний
  console.log('Starting task scheduler (every 5 minutes)...');

  // Проверка при старте
  setTimeout(() => {
    checkExpiredTasks();
    checkTaskReminders();
  }, 10000); // Через 10 секунд после старта

  // Каждые 5 минут
  setInterval(() => {
    checkExpiredTasks();
    checkTaskReminders();
  }, 5 * 60 * 1000);

  console.log('Tasks API initialized');
}

module.exports = { setupTasksAPI, checkExpiredTasks, checkTaskReminders };
