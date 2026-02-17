/**
 * Migration Wave 5: Tasks, Recurring Tasks, Work Schedule
 * Monthly JSON files → PostgreSQL
 *
 * Run: node scripts/migrate_wave5_tasks_schedule.js
 * Safe for re-run (upsert by id)
 *
 * IMPORTANT: tasks must be inserted BEFORE task_assignments (FK constraint)
 *
 * Sources:
 *   /var/www/tasks/YYYY-MM.json              → tasks
 *   /var/www/task-assignments/YYYY-MM.json   → task_assignments
 *   /var/www/recurring-tasks/all.json        → recurring_tasks
 *   /var/www/recurring-task-instances/YYYY-MM.json → recurring_task_instances
 *   /var/www/work-schedules/YYYY-MM.json     → work_schedule_entries
 */

const fsp = require('fs').promises;
const path = require('path');
const db = require('../utils/db');
const { fileExists } = require('../utils/file_helpers');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

// ======================== SCHEMA PATCHES ========================

async function patchSchema() {
  // Add missing columns to task_assignments (used in code but not in original schema)
  const patches = [
    `ALTER TABLE task_assignments ADD COLUMN IF NOT EXISTS declined_at TIMESTAMPTZ`,
    `ALTER TABLE task_assignments ADD COLUMN IF NOT EXISTS decline_reason TEXT`,
    `ALTER TABLE task_assignments ADD COLUMN IF NOT EXISTS reminder_sent BOOLEAN DEFAULT false`,
    `ALTER TABLE task_assignments ADD COLUMN IF NOT EXISTS reminder_sent_at TIMESTAMPTZ`,
    // work_schedule_entries might need shop_name
    `ALTER TABLE work_schedule_entries ADD COLUMN IF NOT EXISTS shop_name TEXT`,
  ];

  for (const sql of patches) {
    try {
      await db.query(sql);
    } catch (e) {
      // Ignore "already exists" errors
      if (!e.message.includes('already exists')) {
        console.error('  Schema patch error:', e.message);
      }
    }
  }
  console.log('  Schema patches applied\n');
}

// ======================== CONVERTERS ========================

function taskToDb(t, month) {
  return {
    id: t.id,
    title: t.title || '',
    description: t.description || null,
    response_type: t.responseType || null,
    deadline: t.deadline || null,
    created_by: t.createdBy || null,
    attachments: t.attachments || null,
    month: month || t.month || null,
    created_at: t.createdAt || new Date().toISOString()
  };
}

function assignmentToDb(a) {
  return {
    id: a.id,
    task_id: a.taskId || null,
    assignee_id: a.assigneeId || null,
    assignee_name: a.assigneeName || null,
    assignee_phone: a.assigneePhone || null,
    assignee_role: a.assigneeRole || null,
    status: a.status || 'pending',
    deadline: a.deadline || null,
    response_text: a.responseText || null,
    response_photos: a.responsePhotos || null,
    responded_at: a.respondedAt || null,
    reviewed_by: a.reviewedBy || null,
    reviewed_at: a.reviewedAt || null,
    review_comment: a.reviewComment || null,
    expired_at: a.expiredAt || null,
    viewed_by_admin: a.viewedByAdmin || false,
    viewed_by_admin_at: a.viewedByAdminAt || null,
    declined_at: a.declinedAt || null,
    decline_reason: a.declineReason || null,
    reminder_sent: a.reminderSent || false,
    reminder_sent_at: a.reminderSentAt || null,
    created_at: a.createdAt || new Date().toISOString()
  };
}

function recurringTaskToDb(t) {
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

function scheduleEntryToDb(e) {
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

// ======================== MIGRATION FUNCTIONS ========================

async function migrateTasks() {
  const dir = `${DATA_DIR}/tasks`;
  if (!await fileExists(dir)) {
    console.log('  No tasks directory, skipping');
    return { count: 0, errors: 0 };
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  console.log(`  Found ${files.length} monthly files`);
  let count = 0, errors = 0;

  for (const file of files) {
    const month = file.replace('.json', '');
    const content = await fsp.readFile(path.join(dir, file), 'utf8');
    const data = JSON.parse(content);
    const tasks = data.tasks || (Array.isArray(data) ? data : []);

    console.log(`  ${file}: ${tasks.length} tasks`);
    for (const t of tasks) {
      if (!t.id) { errors++; continue; }
      try {
        await db.upsert('tasks', taskToDb(t, month));
        count++;
      } catch (e) {
        console.error(`    Error: ${t.id} — ${e.message}`);
        errors++;
      }
    }
  }
  return { count, errors };
}

async function migrateTaskAssignments() {
  const dir = `${DATA_DIR}/task-assignments`;
  if (!await fileExists(dir)) {
    console.log('  No task-assignments directory, skipping');
    return { count: 0, errors: 0 };
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  console.log(`  Found ${files.length} monthly files`);
  let count = 0, errors = 0;

  for (const file of files) {
    const content = await fsp.readFile(path.join(dir, file), 'utf8');
    const data = JSON.parse(content);
    const assignments = data.assignments || (Array.isArray(data) ? data : []);

    console.log(`  ${file}: ${assignments.length} assignments`);
    for (const a of assignments) {
      if (!a.id) { errors++; continue; }
      try {
        await db.upsert('task_assignments', assignmentToDb(a));
        count++;
      } catch (e) {
        console.error(`    Error: ${a.id} — ${e.message}`);
        errors++;
      }
    }
  }
  return { count, errors };
}

async function migrateRecurringTasks() {
  const file = `${DATA_DIR}/recurring-tasks/all.json`;
  if (!await fileExists(file)) {
    console.log('  No recurring-tasks/all.json, skipping');
    return { count: 0, errors: 0 };
  }

  const content = await fsp.readFile(file, 'utf8');
  const data = JSON.parse(content);
  const templates = data.templates || (Array.isArray(data) ? data : []);

  console.log(`  Found ${templates.length} recurring task templates`);
  let count = 0, errors = 0;

  for (const t of templates) {
    if (!t.id) { errors++; continue; }
    try {
      await db.upsert('recurring_tasks', recurringTaskToDb(t));
      count++;
    } catch (e) {
      console.error(`    Error: ${t.id} — ${e.message}`);
      errors++;
    }
  }
  return { count, errors };
}

async function migrateRecurringInstances() {
  const dir = `${DATA_DIR}/recurring-task-instances`;
  if (!await fileExists(dir)) {
    console.log('  No recurring-task-instances directory, skipping');
    return { count: 0, errors: 0 };
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  console.log(`  Found ${files.length} monthly files`);
  let count = 0, errors = 0;

  for (const file of files) {
    const content = await fsp.readFile(path.join(dir, file), 'utf8');
    const data = JSON.parse(content);
    const instances = data.instances || (Array.isArray(data) ? data : []);

    console.log(`  ${file}: ${instances.length} instances`);
    for (const i of instances) {
      if (!i.id) { errors++; continue; }
      try {
        await db.upsert('recurring_task_instances', instanceToDb(i));
        count++;
      } catch (e) {
        console.error(`    Error: ${i.id} — ${e.message}`);
        errors++;
      }
    }
  }
  return { count, errors };
}

async function migrateWorkSchedule() {
  const dir = `${DATA_DIR}/work-schedules`;
  if (!await fileExists(dir)) {
    console.log('  No work-schedules directory, skipping');
    return { count: 0, errors: 0 };
  }

  const files = (await fsp.readdir(dir)).filter(f => f.endsWith('.json'));
  console.log(`  Found ${files.length} monthly files`);
  let count = 0, errors = 0;

  for (const file of files) {
    const content = await fsp.readFile(path.join(dir, file), 'utf8');
    const data = JSON.parse(content);
    const entries = data.entries || (Array.isArray(data) ? data : []);

    console.log(`  ${file}: ${entries.length} entries`);
    for (const e of entries) {
      if (!e.id) {
        e.id = `entry_migrated_${Date.now()}_${Math.random().toString(36).substr(2, 6)}`;
      }
      try {
        await db.upsert('work_schedule_entries', scheduleEntryToDb(e));
        count++;
      } catch (err) {
        console.error(`    Error: ${e.id} — ${err.message}`);
        errors++;
      }
    }
  }
  return { count, errors };
}

// ======================== MAIN ========================

async function main() {
  console.log('=== Wave 5 Migration: Tasks, Recurring Tasks, Work Schedule ===\n');

  try {
    const health = await db.healthCheck();
    console.log(`DB connected: ${health.dbSizeMB} MB, pool: ${JSON.stringify(health.pool)}\n`);

    // Patch schema first
    console.log('--- Schema patches ---');
    await patchSchema();

    // ORDER MATTERS: tasks before assignments (FK)
    // recurring_tasks before instances (FK)

    console.log('--- Tasks ---');
    const r1 = await migrateTasks();
    console.log(`  Result: ${r1.count} migrated, ${r1.errors} errors\n`);

    console.log('--- Task Assignments ---');
    const r2 = await migrateTaskAssignments();
    console.log(`  Result: ${r2.count} migrated, ${r2.errors} errors\n`);

    console.log('--- Recurring Tasks ---');
    const r3 = await migrateRecurringTasks();
    console.log(`  Result: ${r3.count} migrated, ${r3.errors} errors\n`);

    console.log('--- Recurring Task Instances ---');
    const r4 = await migrateRecurringInstances();
    console.log(`  Result: ${r4.count} migrated, ${r4.errors} errors\n`);

    console.log('--- Work Schedule ---');
    const r5 = await migrateWorkSchedule();
    console.log(`  Result: ${r5.count} migrated, ${r5.errors} errors\n`);

    // Verification
    console.log('=== Verification ===');
    for (const table of ['tasks', 'task_assignments', 'recurring_tasks', 'recurring_task_instances', 'work_schedule_entries']) {
      const cnt = await db.count(table);
      console.log(`  ${table}: ${cnt} records`);
    }

  } catch (e) {
    console.error('Migration failed:', e);
    process.exit(1);
  }

  await db.close();
  console.log('\n=== Done ===');
}

main();
