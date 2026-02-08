/**
 * Points Settings API
 * Настройки баллов для всех категорий эффективности
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const POINTS_SETTINGS_DIR = `${DATA_DIR}/points-settings`;
const TEST_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'test_points_settings.json');
const ATTENDANCE_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'attendance_points_settings.json');
const SHIFT_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'shift_points_settings.json');
const RECOUNT_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'recount_points_settings.json');
const RKO_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'rko_points_settings.json');
const SHIFT_HANDOVER_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'shift_handover_points_settings.json');
const REVIEWS_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'reviews_points_settings.json');
const PRODUCT_SEARCH_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'product_search_points_settings.json');
const ORDERS_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'orders_points_settings.json');
const ENVELOPE_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'envelope_points_settings.json');
const COFFEE_MACHINE_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'coffee_machine_points_settings.json');
const MANAGER_POINTS_FILE = path.join(POINTS_SETTINGS_DIR, 'manager_points_settings.json');

// Async helper
async function fileExists(filePath) {
  try {
    await fsp.access(filePath);
    return true;
  } catch {
    return false;
  }
}

// Ensure directory exists (async)
async function ensureDir() {
  try {
    await fsp.mkdir(POINTS_SETTINGS_DIR, { recursive: true });
  } catch (e) {
    // Directory might already exist
  }
}

// Default settings for test
const DEFAULT_TEST_POINTS_SETTINGS = {
  id: 'test_points',
  category: 'testing',
  minPoints: -2,        // Points for 0-1 correct answers
  zeroThreshold: 15,    // Correct answers that give 0 points
  maxPoints: 1,         // Points for perfect score (20/20)
  totalQuestions: 20,   // Fixed: total questions
  passingScore: 16,     // Fixed: minimum passing score
  createdAt: null,
  updatedAt: null
};

// Default settings for attendance
const DEFAULT_ATTENDANCE_POINTS_SETTINGS = {
  id: 'attendance_points',
  category: 'attendance',
  onTimePoints: 0.5,    // Points for arriving on time
  latePoints: -1,       // Points for being late
  // Временные окна для посещаемости
  morningStartTime: '07:00',   // Начало утренней смены
  morningEndTime: '09:00',     // Дедлайн утренней отметки
  eveningStartTime: '19:00',   // Начало вечерней смены
  eveningEndTime: '21:00',     // Дедлайн вечерней отметки
  // Штраф за пропуск отметки
  missedPenalty: -2,           // Баллы за пропуск
  createdAt: null,
  updatedAt: null
};

// Default settings for shift (пересменка)
const DEFAULT_SHIFT_POINTS_SETTINGS = {
  id: 'shift_points',
  category: 'shift',
  minPoints: -3,        // Points for rating 1 (worst)
  zeroThreshold: 7,     // Rating that gives 0 points
  maxPoints: 2,         // Points for rating 10 (best)
  minRating: 1,         // Fixed: minimum rating
  maxRating: 10,        // Fixed: maximum rating
  // Временные окна для пересменок
  morningStartTime: '07:00',   // Начало утренней смены
  morningEndTime: '13:00',     // Дедлайн утренней пересменки
  eveningStartTime: '14:00',   // Начало вечерней смены
  eveningEndTime: '23:00',     // Дедлайн вечерней пересменки
  // Штраф за пропуск пересменки
  missedPenalty: -3,           // Баллы за пропуск
  // Время на проверку админом (в часах: 1, 2 или 3)
  adminReviewTimeout: 2,       // Дефолт: 2 часа
  createdAt: null,
  updatedAt: null
};

// Default settings for recount (пересчет)
const DEFAULT_RECOUNT_POINTS_SETTINGS = {
  id: 'recount_points',
  category: 'recount',
  minPoints: -3,        // Points for rating 1 (worst)
  zeroThreshold: 7,     // Rating that gives 0 points
  maxPoints: 1,         // Points for rating 10 (best)
  minRating: 1,         // Fixed: minimum rating
  maxRating: 10,        // Fixed: maximum rating
  // Временные окна для пересчёта
  morningStartTime: '08:00',   // Начало утренней смены
  morningEndTime: '14:00',     // Дедлайн утреннего пересчёта
  eveningStartTime: '14:00',   // Начало вечерней смены
  eveningEndTime: '23:00',     // Дедлайн вечернего пересчёта
  // Штраф за пропуск пересчёта
  missedPenalty: -3,           // Баллы за пропуск
  // Время на проверку админом (в часах: 1-24)
  adminReviewTimeout: 2,       // Дефолт: 2 часа
  createdAt: null,
  updatedAt: null
};

// Default settings for RKO (РКО)
const DEFAULT_RKO_POINTS_SETTINGS = {
  id: 'rko_points',
  category: 'rko',
  hasRkoPoints: 1,      // Points when RKO exists
  noRkoPoints: -3,      // Points when no RKO
  // Временные окна для РКО
  morningStartTime: '07:00',   // Начало утренней смены
  morningEndTime: '14:00',     // Дедлайн утреннего РКО
  eveningStartTime: '14:00',   // Начало вечерней смены
  eveningEndTime: '23:00',     // Дедлайн вечернего РКО
  // Штраф за пропуск РКО
  missedPenalty: -3,           // Баллы за пропуск
  createdAt: null,
  updatedAt: null
};

// Default settings for shift handover (Сдать смену)
const DEFAULT_SHIFT_HANDOVER_POINTS_SETTINGS = {
  id: 'shift_handover_points',
  category: 'shift_handover',
  minPoints: -3,        // Points for rating 1 (worst)
  zeroThreshold: 7,     // Rating that gives 0 points
  maxPoints: 1,         // Points for rating 10 (best)
  minRating: 1,         // Fixed: minimum rating
  maxRating: 10,        // Fixed: maximum rating
  // Временные окна для сдачи смены
  morningStartTime: '07:00',   // Начало утренней смены
  morningEndTime: '14:00',     // Дедлайн утренней сдачи смены
  eveningStartTime: '14:00',   // Начало вечерней смены
  eveningEndTime: '23:00',     // Дедлайн вечерней сдачи смены
  // Штраф за пропуск сдачи смены
  missedPenalty: -3,           // Баллы за пропуск
  // Время на проверку админом (часы)
  adminReviewTimeout: 4,       // По умолчанию 4 часа
  createdAt: null,
  updatedAt: null
};

// Default settings for reviews (Отзывы)
const DEFAULT_REVIEWS_POINTS_SETTINGS = {
  id: 'reviews_points',
  category: 'reviews',
  positivePoints: 3,    // Points for positive review
  negativePoints: -5,   // Points for negative review
  createdAt: null,
  updatedAt: null
};

// Default settings for product search (Поиск товара)
const DEFAULT_PRODUCT_SEARCH_POINTS_SETTINGS = {
  id: 'product_search_points',
  category: 'product_search',
  answeredPoints: 0.2,    // Points for answering on time
  notAnsweredPoints: -3,  // Points for not answering
  answerTimeoutMinutes: 30, // Timeout in minutes for answering
  createdAt: null,
  updatedAt: null
};

// Default settings for orders (Заказы клиентов)
const DEFAULT_ORDERS_POINTS_SETTINGS = {
  id: 'orders_points',
  category: 'orders',
  acceptedPoints: 0.2,    // Points for accepting order
  rejectedPoints: -3,     // Points for rejecting order
  createdAt: null,
  updatedAt: null
};

// Default settings for envelope (Конверт)
const DEFAULT_ENVELOPE_POINTS_SETTINGS = {
  id: 'envelope_points',
  category: 'envelope',
  submittedPoints: 1.0,     // Points for submitted envelope
  notSubmittedPoints: -3.0, // Points for not submitted envelope
  createdAt: null,
  updatedAt: null
};

// Default settings for coffee machine (Счётчик кофемашин)
const DEFAULT_COFFEE_MACHINE_POINTS_SETTINGS = {
  id: 'coffee_machine_points',
  category: 'coffee_machine',
  submittedPoints: 1.0,       // Points for submitted counter report
  notSubmittedPoints: -3.0,   // Points for not submitted counter report
  morningStartTime: '07:00',
  morningEndTime: '12:00',
  morningDeadline: '12:00',
  eveningStartTime: '14:00',
  eveningEndTime: '22:00',
  eveningDeadline: '22:00',
  adminReviewTimeoutHours: 4,
  createdAt: null,
  updatedAt: null
};

// Default category settings for managers (simplified)
// confirmedPoints - баллы за проверенный отчёт
// rejectedPenalty - штраф за непроверенный отчёт
const DEFAULT_MANAGER_CATEGORY_SETTINGS = {
  confirmedPoints: 1.0,     // Points for confirmed/reviewed report
  rejectedPenalty: -2.0     // Penalty for rejected/failed report
};

// Default settings for managers (Управляющие)
const DEFAULT_MANAGER_POINTS_SETTINGS = {
  id: 'manager_points',
  category: 'manager',
  shiftSettings: { ...DEFAULT_MANAGER_CATEGORY_SETTINGS },
  recountSettings: { ...DEFAULT_MANAGER_CATEGORY_SETTINGS },
  shiftHandoverSettings: { ...DEFAULT_MANAGER_CATEGORY_SETTINGS },
  createdAt: null,
  updatedAt: null
};

// Linear interpolation calculation for test
function calculateTestPoints(score, settings) {
  const { minPoints, zeroThreshold, maxPoints, totalQuestions } = settings;

  if (score <= 0) return minPoints;
  if (score >= totalQuestions) return maxPoints;

  if (score <= zeroThreshold) {
    // Interpolate from minPoints to 0 (score: 0 -> zeroThreshold)
    return minPoints + (0 - minPoints) * (score / zeroThreshold);
  } else {
    // Interpolate from 0 to maxPoints (score: zeroThreshold -> totalQuestions)
    const range = totalQuestions - zeroThreshold;
    return 0 + (maxPoints - 0) * ((score - zeroThreshold) / range);
  }
}

// Linear interpolation calculation for shift (rating 1-10)
function calculateShiftPoints(rating, settings) {
  const { minPoints, zeroThreshold, maxPoints, minRating, maxRating } = settings;

  if (rating <= minRating) return minPoints;
  if (rating >= maxRating) return maxPoints;

  if (rating <= zeroThreshold) {
    // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
    const range = zeroThreshold - minRating;
    return minPoints + (0 - minPoints) * ((rating - minRating) / range);
  } else {
    // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
    const range = maxRating - zeroThreshold;
    return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
  }
}

// Linear interpolation calculation for recount (rating 1-10)
function calculateRecountPoints(rating, settings) {
  const { minPoints, zeroThreshold, maxPoints, minRating, maxRating } = settings;

  if (rating <= minRating) return minPoints;
  if (rating >= maxRating) return maxPoints;

  if (rating <= zeroThreshold) {
    // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
    const range = zeroThreshold - minRating;
    return minPoints + (0 - minPoints) * ((rating - minRating) / range);
  } else {
    // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
    const range = maxRating - zeroThreshold;
    return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
  }
}

// Linear interpolation calculation for shift handover (rating 1-10)
function calculateShiftHandoverPoints(rating, settings) {
  const { minPoints, zeroThreshold, maxPoints, minRating, maxRating } = settings;

  if (rating <= minRating) return minPoints;
  if (rating >= maxRating) return maxPoints;

  if (rating <= zeroThreshold) {
    // Interpolate from minPoints to 0 (rating: 1 -> zeroThreshold)
    const range = zeroThreshold - minRating;
    return minPoints + (0 - minPoints) * ((rating - minRating) / range);
  } else {
    // Interpolate from 0 to maxPoints (rating: zeroThreshold -> 10)
    const range = maxRating - zeroThreshold;
    return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
  }
}

function setupPointsSettingsAPI(app) {
  // GET /api/points-settings/test - Get test points settings
  app.get('/api/points-settings/test', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(TEST_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_TEST_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(TEST_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting test points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/test - Save test points settings
  app.post('/api/points-settings/test', async (req, res) => {
    try {
      await ensureDir();

      const { minPoints, zeroThreshold, maxPoints } = req.body;

      // Validation
      if (minPoints === undefined || zeroThreshold === undefined || maxPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: minPoints, zeroThreshold, maxPoints'
        });
      }

      if (minPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'minPoints must be <= 0'
        });
      }

      if (maxPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'maxPoints must be >= 0'
        });
      }

      if (zeroThreshold < 0 || zeroThreshold > 19) {
        return res.status(400).json({
          success: false,
          error: 'zeroThreshold must be between 0 and 19'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_TEST_POINTS_SETTINGS };
      if (await fileExists(TEST_POINTS_FILE)) {
        const content = await fsp.readFile(TEST_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.minPoints = parseFloat(minPoints);
      settings.zeroThreshold = parseInt(zeroThreshold);
      settings.maxPoints = parseFloat(maxPoints);
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(TEST_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Test points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving test points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/points-settings/test/calculate - Calculate points for a score
  app.get('/api/points-settings/test/calculate', async (req, res) => {
    try {
      const score = parseInt(req.query.score) || 0;

      await ensureDir();

      let settings = { ...DEFAULT_TEST_POINTS_SETTINGS };
      if (await fileExists(TEST_POINTS_FILE)) {
        const content = await fsp.readFile(TEST_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      }

      const points = calculateTestPoints(score, settings);

      res.json({
        success: true,
        score,
        points: Math.round(points * 100) / 100, // Round to 2 decimals
        settings: {
          minPoints: settings.minPoints,
          zeroThreshold: settings.zeroThreshold,
          maxPoints: settings.maxPoints
        }
      });
    } catch (error) {
      console.error('Error calculating points:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ATTENDANCE POINTS SETTINGS =====

  // GET /api/points-settings/attendance - Get attendance points settings
  app.get('/api/points-settings/attendance', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(ATTENDANCE_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_ATTENDANCE_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(ATTENDANCE_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting attendance points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/attendance - Save attendance points settings
  app.post('/api/points-settings/attendance', async (req, res) => {
    try {
      await ensureDir();

      const {
        onTimePoints, latePoints,
        morningStartTime, morningEndTime, eveningStartTime, eveningEndTime,
        missedPenalty
      } = req.body;

      // Validation
      if (onTimePoints === undefined || latePoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: onTimePoints, latePoints'
        });
      }

      if (onTimePoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'onTimePoints must be >= 0'
        });
      }

      if (latePoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'latePoints must be <= 0'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_ATTENDANCE_POINTS_SETTINGS };
      if (await fileExists(ATTENDANCE_POINTS_FILE)) {
        const content = await fsp.readFile(ATTENDANCE_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.onTimePoints = parseFloat(onTimePoints);
      settings.latePoints = parseFloat(latePoints);

      // Update time windows if provided
      if (morningStartTime !== undefined) settings.morningStartTime = morningStartTime;
      if (morningEndTime !== undefined) settings.morningEndTime = morningEndTime;
      if (eveningStartTime !== undefined) settings.eveningStartTime = eveningStartTime;
      if (eveningEndTime !== undefined) settings.eveningEndTime = eveningEndTime;
      if (missedPenalty !== undefined) settings.missedPenalty = parseFloat(missedPenalty);

      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(ATTENDANCE_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Attendance points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving attendance points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SHIFT POINTS SETTINGS (Пересменка) =====

  // GET /api/points-settings/shift - Get shift points settings
  app.get('/api/points-settings/shift', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(SHIFT_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_SHIFT_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(SHIFT_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting shift points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/shift - Save shift points settings
  app.post('/api/points-settings/shift', async (req, res) => {
    try {
      await ensureDir();

      const {
        minPoints, zeroThreshold, maxPoints,
        morningStartTime, morningEndTime, eveningStartTime, eveningEndTime,
        missedPenalty, adminReviewTimeout
      } = req.body;

      // Validation
      if (minPoints === undefined || zeroThreshold === undefined || maxPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: minPoints, zeroThreshold, maxPoints'
        });
      }

      if (minPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'minPoints must be <= 0'
        });
      }

      if (maxPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'maxPoints must be >= 0'
        });
      }

      if (zeroThreshold < 2 || zeroThreshold > 9) {
        return res.status(400).json({
          success: false,
          error: 'zeroThreshold must be between 2 and 9'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_SHIFT_POINTS_SETTINGS };
      if (await fileExists(SHIFT_POINTS_FILE)) {
        const content = await fsp.readFile(SHIFT_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.minPoints = parseFloat(minPoints);
      settings.zeroThreshold = parseInt(zeroThreshold);
      settings.maxPoints = parseFloat(maxPoints);

      // Update time windows if provided
      if (morningStartTime !== undefined) settings.morningStartTime = morningStartTime;
      if (morningEndTime !== undefined) settings.morningEndTime = morningEndTime;
      if (eveningStartTime !== undefined) settings.eveningStartTime = eveningStartTime;
      if (eveningEndTime !== undefined) settings.eveningEndTime = eveningEndTime;
      if (missedPenalty !== undefined) settings.missedPenalty = parseFloat(missedPenalty);
      if (adminReviewTimeout !== undefined) settings.adminReviewTimeout = parseInt(adminReviewTimeout);

      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(SHIFT_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Shift points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving shift points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/points-settings/shift/calculate - Calculate points for a rating
  app.get('/api/points-settings/shift/calculate', async (req, res) => {
    try {
      const rating = parseInt(req.query.rating) || 1;

      await ensureDir();

      let settings = { ...DEFAULT_SHIFT_POINTS_SETTINGS };
      if (await fileExists(SHIFT_POINTS_FILE)) {
        const content = await fsp.readFile(SHIFT_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      }

      const points = calculateShiftPoints(rating, settings);

      res.json({
        success: true,
        rating,
        points: Math.round(points * 100) / 100, // Round to 2 decimals
        settings: {
          minPoints: settings.minPoints,
          zeroThreshold: settings.zeroThreshold,
          maxPoints: settings.maxPoints
        }
      });
    } catch (error) {
      console.error('Error calculating shift points:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== RECOUNT POINTS SETTINGS (Пересчет) =====

  // GET /api/points-settings/recount - Get recount points settings
  app.get('/api/points-settings/recount', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(RECOUNT_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_RECOUNT_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(RECOUNT_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting recount points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/recount - Save recount points settings
  app.post('/api/points-settings/recount', async (req, res) => {
    try {
      await ensureDir();

      const {
        minPoints, zeroThreshold, maxPoints,
        morningStartTime, morningEndTime, eveningStartTime, eveningEndTime,
        missedPenalty, adminReviewTimeout
      } = req.body;

      // Validation
      if (minPoints === undefined || zeroThreshold === undefined || maxPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: minPoints, zeroThreshold, maxPoints'
        });
      }

      if (minPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'minPoints must be <= 0'
        });
      }

      if (maxPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'maxPoints must be >= 0'
        });
      }

      if (zeroThreshold < 2 || zeroThreshold > 9) {
        return res.status(400).json({
          success: false,
          error: 'zeroThreshold must be between 2 and 9'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_RECOUNT_POINTS_SETTINGS };
      if (await fileExists(RECOUNT_POINTS_FILE)) {
        const content = await fsp.readFile(RECOUNT_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.minPoints = parseFloat(minPoints);
      settings.zeroThreshold = parseInt(zeroThreshold);
      settings.maxPoints = parseFloat(maxPoints);

      // Update time windows if provided
      if (morningStartTime !== undefined) settings.morningStartTime = morningStartTime;
      if (morningEndTime !== undefined) settings.morningEndTime = morningEndTime;
      if (eveningStartTime !== undefined) settings.eveningStartTime = eveningStartTime;
      if (eveningEndTime !== undefined) settings.eveningEndTime = eveningEndTime;
      if (missedPenalty !== undefined) settings.missedPenalty = parseFloat(missedPenalty);
      if (adminReviewTimeout !== undefined) settings.adminReviewTimeout = parseInt(adminReviewTimeout);

      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(RECOUNT_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Recount points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving recount points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/points-settings/recount/calculate - Calculate points for a rating
  app.get('/api/points-settings/recount/calculate', async (req, res) => {
    try {
      const rating = parseInt(req.query.rating) || 1;

      await ensureDir();

      let settings = { ...DEFAULT_RECOUNT_POINTS_SETTINGS };
      if (await fileExists(RECOUNT_POINTS_FILE)) {
        const content = await fsp.readFile(RECOUNT_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      }

      const points = calculateRecountPoints(rating, settings);

      res.json({
        success: true,
        rating,
        points: Math.round(points * 100) / 100, // Round to 2 decimals
        settings: {
          minPoints: settings.minPoints,
          zeroThreshold: settings.zeroThreshold,
          maxPoints: settings.maxPoints
        }
      });
    } catch (error) {
      console.error('Error calculating recount points:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== RKO POINTS SETTINGS (РКО) =====

  // GET /api/points-settings/rko - Get RKO points settings
  app.get('/api/points-settings/rko', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(RKO_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_RKO_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(RKO_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting RKO points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/rko - Save RKO points settings
  app.post('/api/points-settings/rko', async (req, res) => {
    try {
      await ensureDir();

      const {
        hasRkoPoints,
        noRkoPoints,
        morningStartTime,
        morningEndTime,
        eveningStartTime,
        eveningEndTime,
        missedPenalty
      } = req.body;

      // Validation
      if (hasRkoPoints === undefined || noRkoPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: hasRkoPoints, noRkoPoints'
        });
      }

      if (hasRkoPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'hasRkoPoints must be >= 0'
        });
      }

      if (noRkoPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'noRkoPoints must be <= 0'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_RKO_POINTS_SETTINGS };
      if (await fileExists(RKO_POINTS_FILE)) {
        const content = await fsp.readFile(RKO_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.hasRkoPoints = parseFloat(hasRkoPoints);
      settings.noRkoPoints = parseFloat(noRkoPoints);

      // Update time window settings if provided
      if (morningStartTime !== undefined) settings.morningStartTime = morningStartTime;
      if (morningEndTime !== undefined) settings.morningEndTime = morningEndTime;
      if (eveningStartTime !== undefined) settings.eveningStartTime = eveningStartTime;
      if (eveningEndTime !== undefined) settings.eveningEndTime = eveningEndTime;
      if (missedPenalty !== undefined) settings.missedPenalty = parseFloat(missedPenalty);

      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(RKO_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('RKO points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving RKO points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== SHIFT HANDOVER POINTS SETTINGS (Сдать смену) =====

  // GET /api/points-settings/shift-handover - Get shift handover points settings
  app.get('/api/points-settings/shift-handover', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(SHIFT_HANDOVER_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_SHIFT_HANDOVER_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(SHIFT_HANDOVER_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting shift handover points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/shift-handover - Save shift handover points settings
  app.post('/api/points-settings/shift-handover', async (req, res) => {
    try {
      await ensureDir();

      const {
        minPoints, zeroThreshold, maxPoints,
        morningStartTime, morningEndTime, eveningStartTime, eveningEndTime,
        missedPenalty, adminReviewTimeout
      } = req.body;

      // Validation
      if (minPoints === undefined || zeroThreshold === undefined || maxPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: minPoints, zeroThreshold, maxPoints'
        });
      }

      if (minPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'minPoints must be <= 0'
        });
      }

      if (maxPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'maxPoints must be >= 0'
        });
      }

      if (zeroThreshold < 2 || zeroThreshold > 9) {
        return res.status(400).json({
          success: false,
          error: 'zeroThreshold must be between 2 and 9'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_SHIFT_HANDOVER_POINTS_SETTINGS };
      if (await fileExists(SHIFT_HANDOVER_POINTS_FILE)) {
        const content = await fsp.readFile(SHIFT_HANDOVER_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.minPoints = parseFloat(minPoints);
      settings.zeroThreshold = parseInt(zeroThreshold);
      settings.maxPoints = parseFloat(maxPoints);

      // Update time windows if provided
      if (morningStartTime !== undefined) settings.morningStartTime = morningStartTime;
      if (morningEndTime !== undefined) settings.morningEndTime = morningEndTime;
      if (eveningStartTime !== undefined) settings.eveningStartTime = eveningStartTime;
      if (eveningEndTime !== undefined) settings.eveningEndTime = eveningEndTime;
      if (missedPenalty !== undefined) settings.missedPenalty = parseFloat(missedPenalty);
      if (adminReviewTimeout !== undefined) settings.adminReviewTimeout = parseInt(adminReviewTimeout);

      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(SHIFT_HANDOVER_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Shift handover points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving shift handover points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/points-settings/shift-handover/calculate - Calculate points for a rating
  app.get('/api/points-settings/shift-handover/calculate', async (req, res) => {
    try {
      const rating = parseInt(req.query.rating) || 1;

      await ensureDir();

      let settings = { ...DEFAULT_SHIFT_HANDOVER_POINTS_SETTINGS };
      if (await fileExists(SHIFT_HANDOVER_POINTS_FILE)) {
        const content = await fsp.readFile(SHIFT_HANDOVER_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      }

      const points = calculateShiftHandoverPoints(rating, settings);

      res.json({
        success: true,
        rating,
        points: Math.round(points * 100) / 100, // Round to 2 decimals
        settings: {
          minPoints: settings.minPoints,
          zeroThreshold: settings.zeroThreshold,
          maxPoints: settings.maxPoints
        }
      });
    } catch (error) {
      console.error('Error calculating shift handover points:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== REVIEWS POINTS SETTINGS (Отзывы) =====

  // GET /api/points-settings/reviews - Get reviews points settings
  app.get('/api/points-settings/reviews', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(REVIEWS_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_REVIEWS_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(REVIEWS_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting reviews points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/reviews - Save reviews points settings
  app.post('/api/points-settings/reviews', async (req, res) => {
    try {
      await ensureDir();

      const { positivePoints, negativePoints } = req.body;

      // Validation
      if (positivePoints === undefined || negativePoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: positivePoints, negativePoints'
        });
      }

      if (positivePoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'positivePoints must be >= 0'
        });
      }

      if (negativePoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'negativePoints must be <= 0'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_REVIEWS_POINTS_SETTINGS };
      if (await fileExists(REVIEWS_POINTS_FILE)) {
        const content = await fsp.readFile(REVIEWS_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.positivePoints = parseFloat(positivePoints);
      settings.negativePoints = parseFloat(negativePoints);
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(REVIEWS_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Reviews points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving reviews points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== PRODUCT SEARCH POINTS SETTINGS (Поиск товара) =====

  // GET /api/points-settings/product-search - Get product search points settings
  app.get('/api/points-settings/product-search', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(PRODUCT_SEARCH_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_PRODUCT_SEARCH_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(PRODUCT_SEARCH_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting product search points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/product-search - Save product search points settings
  app.post('/api/points-settings/product-search', async (req, res) => {
    try {
      await ensureDir();

      const { answeredPoints, notAnsweredPoints, answerTimeoutMinutes } = req.body;

      // Validation
      if (answeredPoints === undefined || notAnsweredPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: answeredPoints, notAnsweredPoints'
        });
      }

      if (answeredPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'answeredPoints must be >= 0'
        });
      }

      if (notAnsweredPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'notAnsweredPoints must be <= 0'
        });
      }

      if (answerTimeoutMinutes !== undefined && (answerTimeoutMinutes < 5 || answerTimeoutMinutes > 60)) {
        return res.status(400).json({
          success: false,
          error: 'answerTimeoutMinutes must be between 5 and 60'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_PRODUCT_SEARCH_POINTS_SETTINGS };
      if (await fileExists(PRODUCT_SEARCH_POINTS_FILE)) {
        const content = await fsp.readFile(PRODUCT_SEARCH_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.answeredPoints = parseFloat(answeredPoints);
      settings.notAnsweredPoints = parseFloat(notAnsweredPoints);
      settings.answerTimeoutMinutes = answerTimeoutMinutes !== undefined ? parseInt(answerTimeoutMinutes) : (settings.answerTimeoutMinutes || 30);
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(PRODUCT_SEARCH_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Product search points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving product search points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ORDERS POINTS SETTINGS (Заказы клиентов) =====

  // GET /api/points-settings/orders - Get orders points settings
  app.get('/api/points-settings/orders', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(ORDERS_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_ORDERS_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(ORDERS_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting orders points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/orders - Save orders points settings
  app.post('/api/points-settings/orders', async (req, res) => {
    try {
      await ensureDir();

      const { acceptedPoints, rejectedPoints } = req.body;

      // Validation
      if (acceptedPoints === undefined || rejectedPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: acceptedPoints, rejectedPoints'
        });
      }

      if (acceptedPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'acceptedPoints must be >= 0'
        });
      }

      if (rejectedPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'rejectedPoints must be <= 0'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_ORDERS_POINTS_SETTINGS };
      if (await fileExists(ORDERS_POINTS_FILE)) {
        const content = await fsp.readFile(ORDERS_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.acceptedPoints = parseFloat(acceptedPoints);
      settings.rejectedPoints = parseFloat(rejectedPoints);
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(ORDERS_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Orders points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving orders points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== ENVELOPE POINTS SETTINGS (Конверт) =====

  // GET /api/points-settings/envelope - Get envelope points settings
  app.get('/api/points-settings/envelope', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(ENVELOPE_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_ENVELOPE_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(ENVELOPE_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting envelope points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/envelope - Save envelope points settings
  app.post('/api/points-settings/envelope', async (req, res) => {
    try {
      await ensureDir();

      const { submittedPoints, notSubmittedPoints } = req.body;

      // Validation
      if (submittedPoints === undefined || notSubmittedPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: submittedPoints, notSubmittedPoints'
        });
      }

      if (submittedPoints < 0) {
        return res.status(400).json({
          success: false,
          error: 'submittedPoints must be >= 0'
        });
      }

      if (notSubmittedPoints > 0) {
        return res.status(400).json({
          success: false,
          error: 'notSubmittedPoints must be <= 0'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_ENVELOPE_POINTS_SETTINGS };
      if (await fileExists(ENVELOPE_POINTS_FILE)) {
        const content = await fsp.readFile(ENVELOPE_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.submittedPoints = parseFloat(submittedPoints);
      settings.notSubmittedPoints = parseFloat(notSubmittedPoints);
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(ENVELOPE_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Envelope points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving envelope points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== COFFEE MACHINE POINTS SETTINGS (Счётчик кофемашин) =====

  // GET /api/points-settings/coffee-machine - Get coffee machine points settings
  app.get('/api/points-settings/coffee-machine', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(COFFEE_MACHINE_POINTS_FILE))) {
        return res.json({
          success: true,
          settings: { ...DEFAULT_COFFEE_MACHINE_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(COFFEE_MACHINE_POINTS_FILE, 'utf8');
      const settings = JSON.parse(content);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting coffee machine points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/coffee-machine - Save coffee machine points settings
  app.post('/api/points-settings/coffee-machine', async (req, res) => {
    try {
      await ensureDir();

      const { submittedPoints, notSubmittedPoints, morningStartTime, morningEndTime,
              morningDeadline, eveningStartTime, eveningEndTime, eveningDeadline,
              adminReviewTimeoutHours } = req.body;

      // Validation
      if (submittedPoints === undefined || notSubmittedPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: submittedPoints, notSubmittedPoints'
        });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_COFFEE_MACHINE_POINTS_SETTINGS };
      if (await fileExists(COFFEE_MACHINE_POINTS_FILE)) {
        const content = await fsp.readFile(COFFEE_MACHINE_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings
      settings.submittedPoints = parseFloat(submittedPoints);
      settings.notSubmittedPoints = parseFloat(notSubmittedPoints);
      if (morningStartTime) settings.morningStartTime = morningStartTime;
      if (morningEndTime) settings.morningEndTime = morningEndTime;
      if (morningDeadline) settings.morningDeadline = morningDeadline;
      if (eveningStartTime) settings.eveningStartTime = eveningStartTime;
      if (eveningEndTime) settings.eveningEndTime = eveningEndTime;
      if (eveningDeadline) settings.eveningDeadline = eveningDeadline;
      if (adminReviewTimeoutHours !== undefined) settings.adminReviewTimeoutHours = parseInt(adminReviewTimeoutHours);
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(COFFEE_MACHINE_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Coffee machine points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving coffee machine points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ===== MANAGER POINTS SETTINGS (Управляющие) =====

  // GET /api/points-settings/manager - Get manager points settings
  // With migration from old format (subordinateQuality/reviewPercentage -> confirmed/rejected)
  app.get('/api/points-settings/manager', async (req, res) => {
    try {
      await ensureDir();

      if (!(await fileExists(MANAGER_POINTS_FILE))) {
        // Return default settings if none exist
        return res.json({
          success: true,
          settings: { ...DEFAULT_MANAGER_POINTS_SETTINGS, createdAt: new Date().toISOString() }
        });
      }

      const content = await fsp.readFile(MANAGER_POINTS_FILE, 'utf8');
      let settings = JSON.parse(content);

      // Migration: check if old format (subordinateQualityMinPoints exists)
      const migrateCategory = (cat) => {
        if (cat && cat.subordinateQualityMinPoints !== undefined) {
          return { ...DEFAULT_MANAGER_CATEGORY_SETTINGS };
        }
        return cat || { ...DEFAULT_MANAGER_CATEGORY_SETTINGS };
      };

      let needsMigration = false;
      if (settings.shiftSettings?.subordinateQualityMinPoints !== undefined) {
        needsMigration = true;
      }

      if (needsMigration) {
        settings.shiftSettings = migrateCategory(settings.shiftSettings);
        settings.recountSettings = migrateCategory(settings.recountSettings);
        settings.shiftHandoverSettings = migrateCategory(settings.shiftHandoverSettings);
        settings.updatedAt = new Date().toISOString();

        // Save migrated settings
        await fsp.writeFile(MANAGER_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');
        console.log('Manager points settings migrated to new format');
      }

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error getting manager points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/points-settings/manager - Save manager points settings
  // Simplified: confirmedPoints (>=0), rejectedPenalty (<=0)
  app.post('/api/points-settings/manager', async (req, res) => {
    try {
      await ensureDir();

      const { shiftSettings, recountSettings, shiftHandoverSettings } = req.body;

      // Validation
      if (!shiftSettings || !recountSettings || !shiftHandoverSettings) {
        return res.status(400).json({
          success: false,
          error: 'Missing required fields: shiftSettings, recountSettings, shiftHandoverSettings'
        });
      }

      // Validate each category settings (simplified)
      const validateCategorySettings = (settings, name) => {
        if (settings.confirmedPoints === undefined || settings.rejectedPenalty === undefined) {
          return `${name} is missing required fields: confirmedPoints, rejectedPenalty`;
        }
        if (settings.confirmedPoints < 0) {
          return `${name}.confirmedPoints must be >= 0`;
        }
        if (settings.rejectedPenalty > 0) {
          return `${name}.rejectedPenalty must be <= 0`;
        }
        return null;
      };

      const shiftError = validateCategorySettings(shiftSettings, 'shiftSettings');
      if (shiftError) {
        return res.status(400).json({ success: false, error: shiftError });
      }

      const recountError = validateCategorySettings(recountSettings, 'recountSettings');
      if (recountError) {
        return res.status(400).json({ success: false, error: recountError });
      }

      const shiftHandoverError = validateCategorySettings(shiftHandoverSettings, 'shiftHandoverSettings');
      if (shiftHandoverError) {
        return res.status(400).json({ success: false, error: shiftHandoverError });
      }

      // Load existing or create new
      let settings = { ...DEFAULT_MANAGER_POINTS_SETTINGS };
      if (await fileExists(MANAGER_POINTS_FILE)) {
        const content = await fsp.readFile(MANAGER_POINTS_FILE, 'utf8');
        settings = JSON.parse(content);
      } else {
        settings.createdAt = new Date().toISOString();
      }

      // Update settings (simplified structure)
      settings.shiftSettings = {
        confirmedPoints: parseFloat(shiftSettings.confirmedPoints),
        rejectedPenalty: parseFloat(shiftSettings.rejectedPenalty)
      };
      settings.recountSettings = {
        confirmedPoints: parseFloat(recountSettings.confirmedPoints),
        rejectedPenalty: parseFloat(recountSettings.rejectedPenalty)
      };
      settings.shiftHandoverSettings = {
        confirmedPoints: parseFloat(shiftHandoverSettings.confirmedPoints),
        rejectedPenalty: parseFloat(shiftHandoverSettings.rejectedPenalty)
      };
      settings.updatedAt = new Date().toISOString();

      await fsp.writeFile(MANAGER_POINTS_FILE, JSON.stringify(settings, null, 2), 'utf8');

      console.log('Manager points settings saved:', settings);

      res.json({ success: true, settings });
    } catch (error) {
      console.error('Error saving manager points settings:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('   Points Settings API loaded');
}

module.exports = { setupPointsSettingsAPI, calculateTestPoints, calculateShiftPoints, calculateRecountPoints, calculateShiftHandoverPoints };
