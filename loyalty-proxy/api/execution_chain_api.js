/**
 * Execution Chain API
 *
 * Цепочка выполнений — обязательная последовательность действий для сотрудников.
 * Админ настраивает порядок, сотрудник не может пропустить шаг.
 *
 * Endpoints:
 *   GET  /api/execution-chain/config  — получить конфиг цепочки
 *   PUT  /api/execution-chain/config  — сохранить конфиг цепочки
 *   GET  /api/execution-chain/status  — статус выполнения для сотрудника
 */

const fsp = require('fs').promises;
const path = require('path');
const { fileExists } = require('../utils/file_helpers');
const DATA_DIR = process.env.DATA_DIR || '/var/www';

const CONFIG_DIR = path.join(DATA_DIR, 'execution-chain');
const CONFIG_FILE = path.join(CONFIG_DIR, 'config.json');

// ═══════════════════════════════════════════════════
// Доступные модули для цепочки
// ═══════════════════════════════════════════════════
const AVAILABLE_MODULES = [
  { id: 'attendance', name: 'Я на работе' },
  { id: 'testing', name: 'Тестирование' },
  { id: 'shift', name: 'Пересменка' },
  { id: 'recount', name: 'Пересчёт' },
  { id: 'shift_handover', name: 'Сдать смену' },
  { id: 'coffee_machine', name: 'Счётчик кофемашин' },
  { id: 'envelope', name: 'Конверт' },
  { id: 'rko', name: 'РКО' },
];

// ═══════════════════════════════════════════════════
// Загрузка / сохранение конфига
// ═══════════════════════════════════════════════════
async function loadConfig() {
  try {
    if (await fileExists(CONFIG_FILE)) {
      const data = await fsp.readFile(CONFIG_FILE, 'utf8');
      return JSON.parse(data);
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка загрузки конфига:', e.message);
  }
  // Дефолтный конфиг — цепочка выключена
  return { enabled: false, steps: [] };
}

async function saveConfig(config) {
  await fsp.mkdir(CONFIG_DIR, { recursive: true });
  await fsp.writeFile(CONFIG_FILE, JSON.stringify(config, null, 2), 'utf8');
}

// ═══════════════════════════════════════════════════
// Проверка выполнения каждого шага
// ═══════════════════════════════════════════════════

/**
 * Проверяет, отметился ли сотрудник на работе сегодня
 */
async function checkAttendance(employeeName, shopAddress, date) {
  try {
    const attendanceDir = path.join(DATA_DIR, 'attendance');
    if (!(await fileExists(attendanceDir))) return false;

    const files = await fsp.readdir(attendanceDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const data = JSON.parse(await fsp.readFile(path.join(attendanceDir, file), 'utf8'));
        if (data.employeeName === employeeName && (!shopAddress || data.shopAddress === shopAddress)) {
          // Проверяем дату
          const ts = data.timestamp || data.date;
          if (ts && ts.startsWith(date)) return true;
        }
      } catch { /* skip broken files */ }
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки attendance:', e.message);
  }
  return false;
}

/**
 * Проверяет, прошёл ли сотрудник тестирование сегодня
 */
async function checkTesting(employeeName, shopAddress, date) {
  try {
    const testsDir = path.join(DATA_DIR, 'test-results');
    if (!(await fileExists(testsDir))) return false;

    const files = await fsp.readdir(testsDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const data = JSON.parse(await fsp.readFile(path.join(testsDir, file), 'utf8'));
        if (data.employeeName === employeeName && (!shopAddress || data.shopAddress === shopAddress)) {
          const ts = data.completedAt || data.date;
          if (ts && ts.startsWith(date)) return true;
        }
      } catch { /* skip broken files */ }
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки testing:', e.message);
  }
  return false;
}

/**
 * Проверяет, сдал ли сотрудник пересменку сегодня
 */
async function checkShift(employeeName, shopAddress, date) {
  try {
    const reportsDir = path.join(DATA_DIR, 'shift-reports');
    if (!(await fileExists(reportsDir))) return false;

    // Shift reports: файлы YYYY-MM-DD.json (массив отчётов за день)
    const dayFile = path.join(reportsDir, `${date}.json`);
    if (await fileExists(dayFile)) {
      const reports = JSON.parse(await fsp.readFile(dayFile, 'utf8'));
      if (Array.isArray(reports)) {
        return reports.some(r => r.employeeName === employeeName && (!shopAddress || r.shopAddress === shopAddress));
      }
    }

    // Также проверяем индивидуальные файлы (если есть)
    const files = await fsp.readdir(reportsDir);
    const jsonFiles = files.filter(f => f.endsWith('.json') && f !== `${date}.json`);

    for (const file of jsonFiles) {
      try {
        const data = JSON.parse(await fsp.readFile(path.join(reportsDir, file), 'utf8'));
        // Индивидуальный отчёт
        if (data.employeeName === employeeName && (!shopAddress || data.shopAddress === shopAddress)) {
          const ts = data.createdAt || data.date || data.timestamp;
          if (ts && ts.startsWith(date)) return true;
        }
        // Массив отчётов
        if (Array.isArray(data)) {
          if (data.some(r => r.employeeName === employeeName &&
              (!shopAddress || r.shopAddress === shopAddress) &&
              (r.createdAt || r.date || '').startsWith(date))) return true;
        }
      } catch { /* skip */ }
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки shift:', e.message);
  }
  return false;
}

/**
 * Проверяет, прошёл ли сотрудник пересчёт сегодня
 */
async function checkRecount(employeeName, shopAddress, date) {
  try {
    const reportsDir = path.join(DATA_DIR, 'recount-reports');
    if (!(await fileExists(reportsDir))) return false;

    const files = await fsp.readdir(reportsDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const data = JSON.parse(await fsp.readFile(path.join(reportsDir, file), 'utf8'));
        if (data.employeeName === employeeName && (!shopAddress || data.shopAddress === shopAddress)) {
          const ts = data.createdAt || data.date;
          if (ts && ts.startsWith(date)) return true;
        }
      } catch { /* skip */ }
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки recount:', e.message);
  }
  return false;
}

/**
 * Проверяет, сдал ли сотрудник смену сегодня
 */
async function checkShiftHandover(employeeName, shopAddress, date) {
  try {
    const reportsDir = path.join(DATA_DIR, 'shift-handover-reports');
    if (!(await fileExists(reportsDir))) return false;

    const files = await fsp.readdir(reportsDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const data = JSON.parse(await fsp.readFile(path.join(reportsDir, file), 'utf8'));
        if (data.employeeName === employeeName && (!shopAddress || data.shopAddress === shopAddress)) {
          const ts = data.createdAt || data.date;
          if (ts && ts.startsWith(date)) return true;
        }
      } catch { /* skip */ }
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки shift_handover:', e.message);
  }
  return false;
}

/**
 * Проверяет, сдал ли сотрудник счётчик кофемашин сегодня
 */
async function checkCoffeeMachine(employeeName, shopAddress, date) {
  try {
    const reportsDir = path.join(DATA_DIR, 'coffee-machine-reports');
    if (!(await fileExists(reportsDir))) return false;

    const files = await fsp.readdir(reportsDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const data = JSON.parse(await fsp.readFile(path.join(reportsDir, file), 'utf8'));
        if (data.employeeName === employeeName && (!shopAddress || data.shopAddress === shopAddress)) {
          const ts = data.date || data.createdAt;
          if (ts && ts.startsWith(date)) return true;
        }
      } catch { /* skip */ }
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки coffee_machine:', e.message);
  }
  return false;
}

/**
 * Проверяет, сдал ли сотрудник конверт сегодня
 */
async function checkEnvelope(employeeName, shopAddress, date) {
  try {
    const reportsDir = path.join(DATA_DIR, 'envelope-reports');
    if (!(await fileExists(reportsDir))) return false;

    const files = await fsp.readdir(reportsDir);
    const jsonFiles = files.filter(f => f.endsWith('.json'));

    for (const file of jsonFiles) {
      try {
        const data = JSON.parse(await fsp.readFile(path.join(reportsDir, file), 'utf8'));
        if (data.employeeName === employeeName && (!shopAddress || data.shopAddress === shopAddress)) {
          const ts = data.createdAt || data.date;
          if (ts && ts.startsWith(date)) return true;
        }
      } catch { /* skip */ }
    }
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки envelope:', e.message);
  }
  return false;
}

/**
 * Проверяет, сдал ли сотрудник РКО сегодня
 */
async function checkRko(employeeName, shopAddress, date) {
  try {
    const metadataFile = path.join(DATA_DIR, 'rko-reports', 'rko_metadata.json');
    if (!(await fileExists(metadataFile))) return false;

    const metadata = JSON.parse(await fsp.readFile(metadataFile, 'utf8'));
    // rko_metadata.json — массив или объект с записями
    const entries = Array.isArray(metadata) ? metadata : (metadata.reports || []);

    return entries.some(entry => {
      if (entry.employeeName !== employeeName) return false;
      if (shopAddress && entry.shopAddress !== shopAddress) return false;
      const ts = entry.date || entry.createdAt;
      return ts && ts.startsWith(date);
    });
  } catch (e) {
    console.error('[ExecutionChain] Ошибка проверки rko:', e.message);
  }
  return false;
}

// Маппинг ID → функция проверки
const CHECK_FUNCTIONS = {
  attendance: checkAttendance,
  testing: checkTesting,
  shift: checkShift,
  recount: checkRecount,
  shift_handover: checkShiftHandover,
  coffee_machine: checkCoffeeMachine,
  envelope: checkEnvelope,
  rko: checkRko,
};

// ═══════════════════════════════════════════════════
// API Setup
// ═══════════════════════════════════════════════════
function setupExecutionChainAPI(app) {
  console.log('[ExecutionChain] Setting up Execution Chain API...');

  // GET /api/execution-chain/config — получить конфиг
  app.get('/api/execution-chain/config', async (req, res) => {
    try {
      const config = await loadConfig();
      res.json({ success: true, ...config, availableModules: AVAILABLE_MODULES });
    } catch (error) {
      console.error('[ExecutionChain] GET config error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // PUT /api/execution-chain/config — сохранить конфиг
  app.put('/api/execution-chain/config', async (req, res) => {
    try {
      const { enabled, steps } = req.body;

      if (typeof enabled !== 'boolean') {
        return res.status(400).json({ success: false, error: 'enabled must be boolean' });
      }
      if (!Array.isArray(steps)) {
        return res.status(400).json({ success: false, error: 'steps must be array' });
      }

      // Валидация шагов
      const validIds = AVAILABLE_MODULES.map(m => m.id);
      for (const step of steps) {
        if (!step.id || !validIds.includes(step.id)) {
          return res.status(400).json({ success: false, error: `Invalid step id: ${step.id}` });
        }
      }

      // Нумеруем шаги по порядку
      const config = {
        enabled,
        steps: steps.map((s, i) => ({
          id: s.id,
          name: s.name || AVAILABLE_MODULES.find(m => m.id === s.id)?.name || s.id,
          order: i + 1,
        })),
      };

      await saveConfig(config);
      console.log(`[ExecutionChain] Config saved: enabled=${enabled}, steps=${config.steps.length}`);
      res.json({ success: true, ...config });
    } catch (error) {
      console.error('[ExecutionChain] PUT config error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/execution-chain/status — статус выполнения
  app.get('/api/execution-chain/status', async (req, res) => {
    try {
      const { employeeName, shopAddress } = req.query;
      // Дата — сегодня (серверное время)
      const date = req.query.date || new Date().toISOString().split('T')[0];

      if (!employeeName) {
        return res.status(400).json({ success: false, error: 'employeeName required' });
      }

      const config = await loadConfig();

      if (!config.enabled || !config.steps || config.steps.length === 0) {
        return res.json({ success: true, enabled: false, steps: [] });
      }

      // Проверяем каждый шаг параллельно
      const stepResults = await Promise.all(
        config.steps.map(async (step) => {
          const checkFn = CHECK_FUNCTIONS[step.id];
          let completed = false;
          if (checkFn) {
            completed = await checkFn(employeeName, shopAddress || '', date);
          }
          return {
            id: step.id,
            name: step.name,
            order: step.order,
            completed,
          };
        })
      );

      res.json({
        success: true,
        enabled: true,
        steps: stepResults,
      });
    } catch (error) {
      console.error('[ExecutionChain] GET status error:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[ExecutionChain] Execution Chain API ready');
}

module.exports = { setupExecutionChainAPI };
