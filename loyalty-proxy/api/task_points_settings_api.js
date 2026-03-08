/**
 * API для настроек баллов за задачи
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');
const { requireEmployee, requireAdmin } = require('../utils/session_middleware');

const USE_DB = process.env.USE_DB_TASK_POINTS === 'true';

const DATA_DIR = process.env.DATA_DIR || '/var/www';

const CONFIG_FILE = `${DATA_DIR}/task-points-config.json`;

// Дефолтные настройки
const DEFAULT_CONFIG = {
  regularTasks: {
    completionPoints: 1,
    penaltyPoints: -3
  },
  recurringTasks: {
    completionPoints: 2,
    penaltyPoints: -3
  },
  updatedAt: null,
  updatedBy: null
};

// ==================== УТИЛИТЫ ====================

async function loadConfig() {
  try {
    if (USE_DB) {
      const row = await db.findById('app_settings', 'task_points_config', 'key');
      if (row) return row.data;
      return { ...DEFAULT_CONFIG };
    }
    if (await fileExists(CONFIG_FILE)) {
      const data = await fsp.readFile(CONFIG_FILE, 'utf8');
      return JSON.parse(data);
    }
  } catch (e) {
    console.error('Error loading task points config:', e);
  }
  return { ...DEFAULT_CONFIG };
}

async function saveConfig(config) {
  try {
    await writeJsonFile(CONFIG_FILE, config);

    if (USE_DB) {
      try { await db.upsert('app_settings', { key: 'task_points_config', data: config, updated_at: config.updatedAt || new Date().toISOString() }, 'key'); }
      catch (dbErr) { console.error('DB save task_points_config error:', dbErr.message); }
    }

    console.log('Task points config saved');
  } catch (e) {
    console.error('Error saving task points config:', e);
    throw e;
  }
}

function validatePoints(points) {
  const num = parseFloat(points);
  if (isNaN(num)) {
    throw new Error('Points must be a valid number');
  }
  if (num < -100 || num > 100) {
    throw new Error('Points must be between -100 and 100');
  }
  return num;
}

// ==================== SETUP FUNCTION ====================

function setupTaskPointsSettingsAPI(app) {
  console.log('Setting up Task Points Settings API...');

  // GET /api/points-settings/regular-tasks - Настройки обычных задач
  app.get('/api/points-settings/regular-tasks', requireEmployee, async (req, res) => {
    try {
      const config = await loadConfig();
      res.json({
        success: true,
        settings: config.regularTasks
      });
    } catch (e) {
      console.error('Error getting regular task points settings:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/points-settings/regular-tasks - Сохранить настройки обычных задач
  app.post('/api/points-settings/regular-tasks', requireAdmin, async (req, res) => {
    try {
      const { completionPoints, penaltyPoints } = req.body;

      if (completionPoints === undefined || penaltyPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'completionPoints and penaltyPoints are required'
        });
      }

      const validCompletion = validatePoints(completionPoints);
      const validPenalty = validatePoints(penaltyPoints);

      const config = await loadConfig();
      config.regularTasks = {
        completionPoints: validCompletion,
        penaltyPoints: validPenalty
      };
      config.updatedAt = new Date().toISOString();
      config.updatedBy = req.body.updatedBy || 'admin';

      await saveConfig(config);

      console.log('Regular task points updated:', config.regularTasks);
      res.json({
        success: true,
        settings: config.regularTasks
      });
    } catch (e) {
      console.error('Error saving regular task points settings:', e);
      res.status(400).json({ success: false, error: e.message });
    }
  });

  // GET /api/points-settings/recurring-tasks - Настройки циклических задач
  app.get('/api/points-settings/recurring-tasks', requireEmployee, async (req, res) => {
    try {
      const config = await loadConfig();
      res.json({
        success: true,
        settings: config.recurringTasks
      });
    } catch (e) {
      console.error('Error getting recurring task points settings:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  // POST /api/points-settings/recurring-tasks - Сохранить настройки циклических задач
  app.post('/api/points-settings/recurring-tasks', requireAdmin, async (req, res) => {
    try {
      const { completionPoints, penaltyPoints } = req.body;

      if (completionPoints === undefined || penaltyPoints === undefined) {
        return res.status(400).json({
          success: false,
          error: 'completionPoints and penaltyPoints are required'
        });
      }

      const validCompletion = validatePoints(completionPoints);
      const validPenalty = validatePoints(penaltyPoints);

      const config = await loadConfig();
      config.recurringTasks = {
        completionPoints: validCompletion,
        penaltyPoints: validPenalty
      };
      config.updatedAt = new Date().toISOString();
      config.updatedBy = req.body.updatedBy || 'admin';

      await saveConfig(config);

      console.log('Recurring task points updated:', config.recurringTasks);
      res.json({
        success: true,
        settings: config.recurringTasks
      });
    } catch (e) {
      console.error('Error saving recurring task points settings:', e);
      res.status(400).json({ success: false, error: e.message });
    }
  });

  // GET /api/points-settings/tasks - Получить все настройки сразу
  app.get('/api/points-settings/tasks', requireEmployee, async (req, res) => {
    try {
      const config = await loadConfig();
      res.json({
        success: true,
        settings: {
          regular: config.regularTasks,
          recurring: config.recurringTasks
        }
      });
    } catch (e) {
      console.error('Error getting task points settings:', e);
      res.status(500).json({ success: false, error: e.message });
    }
  });

  console.log('Task Points Settings API initialized');
}

// ==================== ЭКСПОРТ ФУНКЦИИ ДЛЯ ИСПОЛЬЗОВАНИЯ ====================

/**
 * Получить настройки баллов за задачи (для использования в других модулях)
 * NOTE: Now async - callers must use await
 */
async function getTaskPointsConfig() {
  return await loadConfig();
}

module.exports = {
  setupTaskPointsSettingsAPI,
  getTaskPointsConfig
};
