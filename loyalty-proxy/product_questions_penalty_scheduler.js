const fs = require('fs');
const path = require('path');

// Directories
const PRODUCT_QUESTIONS_DIR = '/var/www/product-questions';
const PRODUCT_QUESTION_DIALOGS_DIR = '/var/www/product-question-dialogs';
const EFFICIENCY_PENALTIES_DIR = '/var/www/efficiency-penalties';
const WORK_SCHEDULES_DIR = '/var/www/work-schedules';
const PENALTY_STATE_DIR = '/var/www/product-question-penalty-state';
const STATE_FILE = path.join(PENALTY_STATE_DIR, 'processed.json');
const POINTS_SETTINGS_DIR = '/var/www/points-settings';

// Settings
const PENALTY_POINTS = -1;
const CATEGORY_CODE = 'product_question_penalty';
const CATEGORY_NAME = 'Неотвеченный вопрос о товаре';

// ============================================
// Dynamic Timeout from Settings
// ============================================
function getTimeoutMinutes() {
  const settingsFile = path.join(POINTS_SETTINGS_DIR, 'product_search_points_settings.json');
  if (fs.existsSync(settingsFile)) {
    try {
      const settings = JSON.parse(fs.readFileSync(settingsFile, 'utf8'));
      return settings.answerTimeoutMinutes || 30;
    } catch (e) {
      console.error('Error loading timeout settings:', e.message);
    }
  }
  return 30; // Default timeout
}

// ============================================
// Helper: Load JSON file safely
// ============================================
function loadJsonFile(filePath, defaultValue) {
  if (!fs.existsSync(filePath)) {
    return defaultValue;
  }
  try {
    const data = fs.readFileSync(filePath, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error(`Error loading JSON from ${filePath}:`, e.message);
    return defaultValue;
  }
}

// ============================================
// 1. State Management
// ============================================
function loadState() {
  const defaultState = {
    lastCheckTime: null,
    processedQuestions: [],
    processedDialogs: []
  };

  if (!fs.existsSync(STATE_FILE)) {
    return defaultState;
  }

  try {
    const data = fs.readFileSync(STATE_FILE, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    console.error('Error loading penalty state:', e.message);
    return defaultState;
  }
}

function saveState(state) {
  try {
    if (!fs.existsSync(PENALTY_STATE_DIR)) {
      fs.mkdirSync(PENALTY_STATE_DIR, { recursive: true });
    }

    // Cleanup: keep only last 1000 IDs to prevent unbounded growth
    state.processedQuestions = state.processedQuestions.slice(-1000);
    state.processedDialogs = state.processedDialogs.slice(-1000);

    fs.writeFileSync(STATE_FILE, JSON.stringify(state, null, 2), 'utf8');
  } catch (e) {
    console.error('Error saving penalty state:', e.message);
  }
}

// ============================================
// 2. Shift Time Matching
// ============================================
function getShiftTypeByTime(date) {
  const hour = date.getHours(); // Moscow time assumed

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
function getEmployeesFromSchedule(shopAddress, timestamp) {
  const employees = [];
  const monthKey = timestamp.toISOString().slice(0, 7); // YYYY-MM
  const dateStr = timestamp.toISOString().split('T')[0]; // YYYY-MM-DD

  const scheduleFile = path.join(WORK_SCHEDULES_DIR, `${monthKey}.json`);
  const schedule = loadJsonFile(scheduleFile, null);

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
function findUnreadQuestions(now, state) {
  const unreadQuestions = [];

  if (!fs.existsSync(PRODUCT_QUESTIONS_DIR)) {
    return unreadQuestions;
  }

  const files = fs.readdirSync(PRODUCT_QUESTIONS_DIR).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const filePath = path.join(PRODUCT_QUESTIONS_DIR, file);
      const question = JSON.parse(fs.readFileSync(filePath, 'utf8'));

      // Skip if already processed
      if (state.processedQuestions.includes(question.id)) continue;

      const questionTime = new Date(question.timestamp);
      const elapsedMinutes = (now - questionTime) / (1000 * 60);
      const timeoutMinutes = getTimeoutMinutes();

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
function findUnreadDialogs(now, state) {
  const unreadDialogs = [];

  if (!fs.existsSync(PRODUCT_QUESTION_DIALOGS_DIR)) {
    return unreadDialogs;
  }

  const files = fs.readdirSync(PRODUCT_QUESTION_DIALOGS_DIR).filter(f => f.endsWith('.json'));

  for (const file of files) {
    try {
      const filePath = path.join(PRODUCT_QUESTION_DIALOGS_DIR, file);
      const dialog = JSON.parse(fs.readFileSync(filePath, 'utf8'));

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
      const timeoutMinutes = getTimeoutMinutes();

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
function createPenaltiesForShop(shopAddress, questionTimestamp, sourceType, sourceId) {
  const employees = getEmployeesFromSchedule(shopAddress, new Date(questionTimestamp));
  const penalties = [];
  const now = new Date();
  const timeoutMinutes = getTimeoutMinutes();

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
      points: PENALTY_POINTS,
      reason: `Вопрос не отвечен за ${timeoutMinutes} минут (${sourceType}: ${sourceId})`,
      sourceId: sourceId,
      sourceType: sourceType, // 'question' or 'dialog'
      createdAt: now.toISOString()
    };

    penalties.push(penalty);
    console.log(`    - Penalty for ${employee.name} at ${shopAddress}: ${PENALTY_POINTS} point`);
  }

  return penalties;
}

// ============================================
// 7. Penalty Saving
// ============================================
function savePenalties(penalties) {
  const penaltiesByMonth = {};

  // Group by month
  for (const penalty of penalties) {
    const monthKey = penalty.date.substring(0, 7); // YYYY-MM
    if (!penaltiesByMonth[monthKey]) {
      penaltiesByMonth[monthKey] = [];
    }
    penaltiesByMonth[monthKey].push(penalty);
  }

  // Save to files
  for (const monthKey in penaltiesByMonth) {
    try {
      const filePath = path.join(EFFICIENCY_PENALTIES_DIR, `${monthKey}.json`);
      let existingPenalties = loadJsonFile(filePath, []);

      existingPenalties = existingPenalties.concat(penaltiesByMonth[monthKey]);

      if (!fs.existsSync(EFFICIENCY_PENALTIES_DIR)) {
        fs.mkdirSync(EFFICIENCY_PENALTIES_DIR, { recursive: true });
      }

      fs.writeFileSync(filePath, JSON.stringify(existingPenalties, null, 2), 'utf8');
      console.log(`  Saved ${penaltiesByMonth[monthKey].length} penalties to ${monthKey}.json`);
    } catch (e) {
      console.error(`  Error saving penalties for ${monthKey}:`, e.message);
    }
  }
}

// ============================================
// 8. Main Checker Function
// ============================================
function checkUnreadQuestionsAndDialogs() {
  try {
    console.log(`\n[${new Date().toISOString()}] Checking unread product questions and dialogs...`);

    const now = new Date();
    const state = loadState();
    const newPenalties = [];

    // 1. Check product questions
    const unreadQuestions = findUnreadQuestions(now, state);
    console.log(`  Found ${unreadQuestions.length} unread questions`);

    for (const question of unreadQuestions) {
      if (question.shops) {
        for (const shop of question.shops) {
          if (!shop.isAnswered) {
            const penalties = createPenaltiesForShop(
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
    const unreadDialogs = findUnreadDialogs(now, state);
    console.log(`  Found ${unreadDialogs.length} unread dialogs`);

    for (const dialog of unreadDialogs) {
      if (dialog.hasUnreadFromClient && dialog.messages && dialog.messages.length > 0) {
        const penalties = createPenaltiesForShop(
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
      savePenalties(newPenalties);
    }

    state.lastCheckTime = now.toISOString();
    saveState(state);

    console.log(`  ✓ Created ${newPenalties.length} penalties for unread questions/dialogs\n`);
  } catch (error) {
    console.error('Error in product questions penalty scheduler:', error);
  }
}

// ============================================
// 9. Scheduler Setup
// ============================================
function startScheduler() {
  const timeoutMinutes = getTimeoutMinutes();
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');
  console.log('Product Questions Penalty Scheduler started');
  console.log(`  - Checking every 5 minutes`);
  console.log(`  - Timeout: ${timeoutMinutes} minutes (dynamic)`);
  console.log(`  - Penalty: ${PENALTY_POINTS} points per employee`);
  console.log('━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━');

  // Check every 5 minutes
  setInterval(() => {
    checkUnreadQuestionsAndDialogs();
  }, 5 * 60 * 1000);

  // First check after 1 second
  setTimeout(() => {
    checkUnreadQuestionsAndDialogs();
  }, 1000);
}

function setupProductQuestionsPenaltyScheduler() {
  startScheduler();
}

module.exports = { setupProductQuestionsPenaltyScheduler };
