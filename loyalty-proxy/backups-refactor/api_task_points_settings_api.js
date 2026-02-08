/**
 * API для настроек баллов за задачи
 */

const fs = require('fs');
const path = require('path');

const CONFIG_FILE = '/var/www/task-points-config.json';

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

function loadConfig() {
  try {
    if (fs.existsSync(CONFIG_FILE)) {
      const data = fs.readFileSync(CONFIG_FILE, 'utf8');
      return JSON.parse(data);
    }
  } catch (e) {
    console.error('Error loading task points config:', e);
  }
  return { ...DEFAULT_CONFIG };
}

function saveConfig(config) {
  try {
    fs.writeFileSync(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
    console.log('✅ Task points config saved');
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
  app.get('/api/points-settings/regular-tasks', (req, res) => {
    try {
      const config = loadConfig();
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
  app.post('/api/points-settings/regular-tasks', (req, res) => {
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

      const config = loadConfig();
      config.regularTasks = {
        completionPoints: validCompletion,
        penaltyPoints: validPenalty
      };
      config.updatedAt = new Date().toISOString();
      config.updatedBy = req.body.updatedBy || 'admin';

      saveConfig(config);

      console.log('✅ Regular task points updated:', config.regularTasks);
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
  app.get('/api/points-settings/recurring-tasks', (req, res) => {
    try {
      const config = loadConfig();
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
  app.post('/api/points-settings/recurring-tasks', (req, res) => {
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

      const config = loadConfig();
      config.recurringTasks = {
        completionPoints: validCompletion,
        penaltyPoints: validPenalty
      };
      config.updatedAt = new Date().toISOString();
      config.updatedBy = req.body.updatedBy || 'admin';

      saveConfig(config);

      console.log('✅ Recurring task points updated:', config.recurringTasks);
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
  app.get('/api/points-settings/tasks', (req, res) => {
    try {
      const config = loadConfig();
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

  console.log('✅ Task Points Settings API initialized');
}

// ==================== ЭКСПОРТ ФУНКЦИИ ДЛЯ ИСПОЛЬЗОВАНИЯ ====================

/**
 * Получить настройки баллов за задачи (для использования в других модулях)
 */
function getTaskPointsConfig() {
  return loadConfig();
}

module.exports = {
  setupTaskPointsSettingsAPI,
  getTaskPointsConfig
};
