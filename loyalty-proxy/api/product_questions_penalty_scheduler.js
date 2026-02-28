/**
 * Product Questions Penalty Scheduler
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { withLock } = require('../utils/file_lock');
const { fileExists, loadJsonFile } = require('../utils/file_helpers');
const { dbInsertPenalties } = require('./efficiency_penalties_api');

// Directories
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const PRODUCT_QUESTIONS_DIR = `${DATA_DIR}/product-questions`;
const PRODUCT_QUESTION_DIALOGS_DIR = `${DATA_DIR}/product-question-dialogs`;
const EFFICIENCY_PENALTIES_DIR = `${DATA_DIR}/efficiency-penalties`;
const WORK_SCHEDULES_DIR = `${DATA_DIR}/work-schedules`;
const PENALTY_STATE_DIR = `${DATA_DIR}/product-question-penalty-state`;
const STATE_FILE = path.join(PENALTY_STATE_DIR, 'processed.json');
const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;

// Settings
const CATEGORY_CODE = 'product_question_penalty';
const CATEGORY_NAME = 'Неотвеченный вопрос о товаре';
const DEFAULT_PENALTY_POINTS = -3;
const DEFAULT_TIMEOUT_MINUTES = 30;

// ============================================
// Dynamic Settings from File
// ============================================
async function getProductSearchSettings() {
  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'product_search_points_settings.json');
  if (await fileExists(settingsFile)) {
    try {
      const data = await fsp.readFile(settingsFile, 'utf8');
      return JSON.parse(data);
    } catch (e) {
      console.error('Error loading product search settings:', e.message);
    }
  }
  return { answerTimeoutMinutes: DEFAULT_TIMEOUT_MINUTES, notAnsweredPoints: DEFAULT_PENALTY_POINTS };
}

async function getTimeoutMinutes() {
  const settings = await getProductSearchSettings();
  return settings.answerTimeoutMinutes || DEFAULT_TIMEOUT_MINUTES;
}

async function getPenaltyPoints() {
  const settings = await getProductSearchSettings();
  return settings.notAnsweredPoints ?? DEFAULT_PENALTY_POINTS;
}

// ============================================
// 1. State Management
// ============================================
async function loadState() {
  const defaultState = {
    lastCheckTime: null,
    processedQuestions: [],
    processedDialogs: []
  };

  if (!(await fileExists(STATE_FILE))) {
    return defaultState;
  }

  try {
    const data = await fsp.readFile(STATE_FILE, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error('Error loading penalty state:', e.message);
    return defaultState;
  }
}

async function saveState(state) {
  try {
    if (!(await fileExists(PENALTY_STATE_DIR))) {
      await fsp.mkdir(PENALTY_STATE_DIR, { recursive: true });
    }

    // Cleanup: keep only last 1000 IDs to prevent unbounded growth
    state.processedQuestions = state.processedQuestions.slice(-1000);
    state.processedDialogs = state.processedDialogs.slice(-1000);

    await writeJsonFile(STATE_FILE, state);
  } catch (e) {
    console.error('Error saving penalty state:', e.message);
  }
}

// ============================================
// 2. Shift Time Matching
// ============================================
function getShiftTypeByTime(date) {
  // Всегда используем московское время (UTC+3), независимо от TZ сервера
  const hour = (date.getUTCHours() + 3) % 24;

  // Shift definitions:
  // morning: 08:00-16:00
  // day: 12:00-20:00
  // evening: 16:00-00:00

  if (hour >= 0 && hour < 8) return ['evening'];           // 00:00-08:00
  if (hour >= 8 && hour < 12) return ['morning'];          // 08:00-12:00
  if (hour >= 12 && hour < 16) return ['morning', 'day'];  // Overlap
  if (hour >= 16 && hour < 20) return ['day', 'evening'];  // Overlap
  if (hour >= 20 && hour < 24) return ['evening'];         // 20:00-00:00

  return ['day']; // Fallback
}

// ============================================
// 3. Employee Lookup from Work Schedule
// ============================================
async function getEmployeesFromSchedule(shopAddress, timestamp) {
  const employees = [];
  const monthKey = timestamp.toISOString().slice(0, 7); // YYYY-MM
  const dateStr = timestamp.toISOString().split('T')[0]; // YYYY-MM-DD

  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = await loadJsonFile(scheduleFile, null);

  if (!schedule || !schedule.entries) {
    console.log(`  No work schedule found for ${monthKey}`);
    return employees; // Empty array = no penalties
  }

  const shiftTypes = getShiftTypeByTime(timestamp);

  for (const entry of schedule.entries) {
    if (entry.shopAddress !== shopAddress) continue;
    if (entry.date !== dateStr) continue;
    if (!shiftTypes.includes(entry.shiftType)) continue;

    employees.push({
      id: entry.employeeId,
      name: entry.employeeName
    });
  }

  console.log(`  Found ${employees.length} employees for ${shopAddress} at ${timestamp.toISOString()}`);
  return employees;
}

// ============================================
// 4. Unread Questions Detection
// ============================================
async function findUnreadQuestions(now, state) {
  const unreadQuestions = [];

  if (!(await fileExists(PRODUCT_QUESTIONS_DIR))) {
    return unreadQuestions;
  }

  const files = (await fsp.readdir(PRODUCT_QUESTIONS_DIR)).filter(f => f.endsWith('.json'));
  const timeoutMinutes = await getTimeoutMinutes();

  for (const file of files) {
    try {
      const filePath = path.join(PRODUCT_QUESTIONS_DIR, file);
      const data = await fsp.readFile(filePath, 'utf8');
      const question = JSON.parse(data);

      // Skip if already processed
      if (state.processedQuestions.includes(question.id)) continue;

      const questionTime = new Date(question.timestamp);
      const elapsedMinutes = (now - questionTime) / (1000 * 60);

      // Check if timeout exceeded
      if (elapsedMinutes < timeoutMinutes) continue;

      // Check if any shop hasn't answered
      const hasUnanswered = question.shops && question.shops.some(shop => !shop.isAnswered);
      if (hasUnanswered) {
        unreadQuestions.push(question);
      }
    } catch (e) {
      console.error(`  Error reading question ${file}:`, e.message);
    }
  }

  return unreadQuestions;
}

// ============================================
// 5. Unread Dialogs Detection
// ============================================
async function findUnreadDialogs(now, state) {
  const unreadDialogs = [];

  if (!(await fileExists(PRODUCT_QUESTION_DIALOGS_DIR))) {
    return unreadDialogs;
  }

  const files = (await fsp.readdir(PRODUCT_QUESTION_DIALOGS_DIR)).filter(f => f.endsWith('.json'));
  const timeoutMinutes = await getTimeoutMinutes();

  for (const file of files) {
    try {
      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, file);
      const data = await fsp.readFile(filePath, 'utf8');
      const dialog = JSON.parse(data);

      // Skip if already processed
      if (state.processedDialogs.includes(dialog.id)) continue;

      // Skip if no unread from client
      if (!dialog.hasUnreadFromClient) continue;

      // Find first unread client message
      const firstUnreadClientMsg = dialog.messages && dialog.messages.find(
        msg => msg.senderType === 'client' && !msg.isRead
      );

      if (!firstUnreadClientMsg) continue;

      const messageTime = new Date(firstUnreadClientMsg.timestamp);
      const elapsedMinutes = (now - messageTime) / (1000 * 60);

      if (elapsedMinutes >= timeoutMinutes) {
        unreadDialogs.push(dialog);
      }
    } catch (e) {
      console.error(`  Error reading dialog ${file}:`, e.message);
    }
  }

  return unreadDialogs;
}

// ============================================
// 6. Penalty Creation
// ============================================
async function createPenaltiesForShop(shopAddress, questionTimestamp, sourceType, sourceId) {
  const employees = await getEmployeesFromSchedule(shopAddress, new Date(questionTimestamp));
  const penalties = [];
  const now = new Date();
  const timeoutMinutes = await getTimeoutMinutes();
  const penaltyPoints = await getPenaltyPoints();

  if (employees.length === 0) {
    console.log(`  No employees found on schedule for ${shopAddress} at ${questionTimestamp}`);
    return penalties;
  }

  for (const employee of employees) {
    const penalty = {
      id: `penalty_pq_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`,
      type: 'employee',
      entityId: employee.id,
      entityName: employee.name,
      shopAddress: shopAddress,
      employeeName: employee.name,
      category: CATEGORY_CODE,
      categoryName: CATEGORY_NAME,
      date: now.toISOString().split('T')[0],
      points: penaltyPoints,
      reason: `Вопрос не отвечен за ${timeoutMinutes} минут (${sourceType}: ${sourceId})`,
      sourceId: sourceId,
      sourceType: sourceType, // 'question' or 'dialog'
      createdAt: now.toISOString()
    };

    penalties.push(penalty);
    console.log(`    - Penalty for ${employee.name} at ${shopAddress}: ${penaltyPoints} point`);
  }

  return penalties;
}

// ============================================
// 7. Penalty Saving
// ============================================
async function savePenalties(penalties) {
  const penaltiesByMonth = {};

  // Group by month
  for (const penalty of penalties) {
    const monthKey = penalty.date.substring(0, 7); // YYYY-MM
    if (!penaltiesByMonth[monthKey]) {
      penaltiesByMonth[monthKey] = [];
    }
    penaltiesByMonth[monthKey].push(penalty);
  }

  // Save to files (under lock to prevent race condition with parallel runs)
  for (const monthKey in penaltiesByMonth) {
    try {
      const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);

      if (!(await fileExists(EFFICIENCY_PENALTIES_DIR))) {
        await fsp.mkdir(EFFICIENCY_PENALTIES_DIR, { recursive: true });
      }

      await withLock(filePath, async () => {
        let existingPenalties = await loadJsonFile(filePath, []);
        existingPenalties = existingPenalties.concat(penaltiesByMonth[monthKey]);
        await writeJsonFile(filePath, existingPenalties, { useLock: false }); // already in lock
      });
      // DB dual-write (outside lock — DB handles its own concurrency)
      await dbInsertPenalties(penaltiesByMonth[monthKey]);
      console.log(`  Saved ${penaltiesByMonth[monthKey].length} penalties to ${monthKey}.json`);
    } catch (e) {
      console.error(`  Error saving penalties for ${monthKey}:`, e.message);
    }
  }
}

// ============================================
// 8. Main Checker Function
// ============================================
async function checkUnreadQuestionsAndDialogs() {
  try {
    console.log(`\n[${new Date().toISOString()}] Checking unread product questions and dialogs...`);

    const now = new Date();
    const state = await loadState();
    const newPenalties = [];

    // 1. Check product questions
    const unreadQuestions = await findUnreadQuestions(now, state);
    console.log(`  Found ${unreadQuestions.length} unread questions`);

    for (const question of unreadQuestions) {
      if (question.shops) {
        for (const shop of question.shops) {
          if (!shop.isAnswered) {
            const penalties = await createPenaltiesForShop(
              shop.shopAddress,
              question.timestamp,
              'question',
              question.id
            );
            newPenalties.push(...penalties);
          }
        }
      }
      state.processedQuestions.push(question.id);
    }

    // 2. Check personal dialogs
    const unreadDialogs = await findUnreadDialogs(now, state);
    console.log(`  Found ${unreadDialogs.length} unread dialogs`);

    for (const dialog of unreadDialogs) {
      if (dialog.hasUnreadFromClient && dialog.messages && dialog.messages.length > 0) {
        const penalties = await createPenaltiesForShop(
          dialog.shopAddress,
          dialog.messages[0].timestamp,
          'dialog',
          dialog.id
        );
        newPenalties.push(...penalties);
      }
      state.processedDialogs.push(dialog.id);
    }

    // 3. Save penalties and update state
    if (newPenalties.length > 0) {
      await savePenalties(newPenalties);
    }

    state.lastCheckTime = now.toISOString();
    await saveState(state);

    console.log(`  ✓ Created ${newPenalties.length} penalties for unread questions/dialogs\n`);
  } catch (error) {
    console.error('Error in product questions penalty scheduler:', error);
  }
}

// ============================================
// 9. Scheduler Setup
// ============================================
async function startScheduler() {
  const timeoutMinutes = await getTimeoutMinutes();
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Product Questions Penalty Scheduler started');
  console.log(`  - Checking every 5 minutes`);
  console.log(`  - Timeout: ${timeoutMinutes} minutes (dynamic)`);
  const penaltyPoints = await getPenaltyPoints();
  console.log(`  - Penalty: ${penaltyPoints} points per employee (dynamic)`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Check every 5 minutes
  let isRunning = false;
  const guardedCheck = async () => {
    if (isRunning) { console.log('[ProductQuestions] Previous run still active, skipping'); return; }
    isRunning = true;
    try { await checkUnreadQuestionsAndDialogs(); }
    catch (err) { console.error('[ProductQuestions] Scheduler error:', err.message); }
    finally { isRunning = false; }
  };

  setInterval(guardedCheck, 5 * 60 * 1000);

  // First check after 1 second
  setTimeout(guardedCheck, 1000);
}

function setupProductQuestionsPenaltyScheduler() {
  startScheduler().catch(e => console.error('Failed to start product questions penalty scheduler:', e));
}

module.exports = { setupProductQuestionsPenaltyScheduler };
