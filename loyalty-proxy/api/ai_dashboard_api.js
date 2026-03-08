/**
 * AI Dashboard API
 * Единый эндпоинт для метрик всех AI-систем:
 * - Z-Report OCR (accuracy, training samples, dow coefficients)
 * - Coffee Machine OCR (accuracy, predictions vs confirmed)
 * - Cigarette Vision YOLO (error stats, recognition stats)
 * - Shift AI Verification (annotations approved/rejected)
 */

const path = require('path');
const fsp = require('fs').promises;
const { fileExists } = require('../utils/file_helpers');
const { requireEmployee } = require('../utils/session_middleware');
const db = require('../utils/db');

const USE_DB_Z = process.env.USE_DB_Z_REPORT === 'true' || process.env.USE_DB_ENVELOPE === 'true';
const USE_DB_CM = process.env.USE_DB_COFFEE_MACHINE === 'true';
const USE_DB_CIG = process.env.USE_DB_CIGARETTE_VISION === 'true';
const USE_DB_SHIFT = process.env.USE_DB_SHIFT_AI === 'true';
const DATA_DIR = process.env.DATA_DIR || '/var/www';

// ============ RECOUNT TRAINING STATE ============

// Состояние фонового обучения (in-memory, сбрасывается при рестарте)
let _recountTrainState = {
  status: 'idle',       // 'idle' | 'running' | 'done' | 'error'
  startedAt: null,
  finishedAt: null,
  epochs: 30,
  result: null,
  error: null,
  retryCount: 0,
};

// Расписание ежедневного обучения — "HH:mm" или null
let _scheduleTime = null;
let _scheduleTimer = null; // текущий setTimeout

/**
 * Вычисляет миллисекунды до следующего наступления HH:mm по Москве.
 * Если время уже прошло сегодня — считаем до завтра.
 */
function _msUntilMoscow(timeStr) {
  const [h, m] = timeStr.split(':').map(Number);
  const now = new Date();
  const moscow = new Date(now.toLocaleString('en-US', { timeZone: 'Europe/Moscow' }));
  const target = new Date(moscow);
  target.setHours(h, m, 0, 0);
  if (target <= moscow) target.setDate(target.getDate() + 1); // уже прошло — завтра
  return target - moscow; // разница в мс
}

/**
 * Планирует одиночный setTimeout на нужное время.
 * После срабатывания планирует следующий (через 24 часа).
 */
function _scheduleNextRun(timeStr) {
  if (_scheduleTimer) { clearTimeout(_scheduleTimer); _scheduleTimer = null; }
  if (!timeStr) return;

  const ms = _msUntilMoscow(timeStr);
  const hm = new Date(Date.now() + ms).toLocaleTimeString('ru-RU', { timeZone: 'Europe/Moscow', hour: '2-digit', minute: '2-digit' });
  console.log(`[Recount Scheduler] Следующий запуск через ${Math.round(ms / 60000)} мин (в ${hm} МСК)`);

  _scheduleTimer = setTimeout(() => {
    if (_recountTrainState.status !== 'running') {
      console.log(`[Recount Scheduler] Автозапуск по расписанию ${timeStr}...`);
      _startRecountTraining(30);
    }
    _scheduleNextRun(timeStr); // планируем следующий день
  }, ms);
}

// Загружаем расписание из БД при старте и сразу планируем
(async () => {
  try {
    const row = await db.findById('app_settings', 'recount_train_schedule', 'key');
    if (row?.data?.time) {
      _scheduleTime = row.data.time;
      console.log(`[Recount Scheduler] Расписание загружено: ${_scheduleTime}`);
      _scheduleNextRun(_scheduleTime);
    }
  } catch (e) { /* ignore — таблица может быть пустой */ }
})();

/**
 * Отправить уведомление в Telegram через API напрямую.
 * Использует BOT_TOKEN и ADMIN_ID из env.
 */
function _sendTelegramNotification(text) {
  const botToken = process.env.BOT_TOKEN;
  const adminId = process.env.ADMIN_ID || '840309879';
  if (!botToken) return;

  const https = require('https');
  const body = JSON.stringify({ chat_id: adminId, text, parse_mode: 'HTML' });
  const req = https.request({
    hostname: 'api.telegram.org',
    path: `/bot${botToken}/sendMessage`,
    method: 'POST',
    headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
    timeout: 10000,
  });
  req.on('error', (e) => console.error('[Telegram Notify] Error:', e.message));
  req.write(body);
  req.end();
}

/** Запускает обучение в фоне, обновляет _recountTrainState. retryCount для auto-retry. */
function _startRecountTraining(epochs, retryCount = 0) {
  const cv = require('../modules/cigarette-vision');
  _recountTrainState = {
    status: 'running',
    startedAt: new Date().toISOString(),
    finishedAt: null,
    epochs,
    result: null,
    error: null,
    retryCount,
  };

  if (retryCount > 0) {
    console.log(`[Recount Scheduler] Retry ${retryCount}/2...`);
  }

  cv.triggerFullTraining(epochs)
    .then(result => {
      _recountTrainState = {
        ..._recountTrainState,
        status: result.success ? 'done' : 'error',
        finishedAt: new Date().toISOString(),
        result: result.success ? {
          totalImages: result.exportResult?.total_images,
          modelReloaded: result.reloadResult?.success,
          message: result.message,
          metrics: result.trainResult?.metrics || null,
        } : null,
        error: result.success ? null : (result.error || 'Ошибка обучения'),
      };
      console.log(`[Recount Scheduler] Обучение завершено: ${_recountTrainState.status}`);

      // Уведомление в Telegram
      if (result.success) {
        const imgs = result.exportResult?.total_images || '?';
        _sendTelegramNotification(
          `✅ <b>Обучение YOLO завершено</b>\n\n📸 Образцов: ${imgs}\n🔄 Эпох: ${epochs}\n🤖 Модель перезагружена: ${result.reloadResult?.success ? 'да' : 'нет'}`
        );
      } else {
        // Ошибка — retry или уведомление
        if (retryCount < 2) {
          const nextRetry = retryCount + 1;
          console.log(`[Recount Scheduler] Ошибка обучения, retry ${nextRetry}/2 через 5 мин...`);
          _sendTelegramNotification(
            `⚠️ <b>Обучение YOLO: ошибка</b>\n\n${result.error || 'Неизвестная ошибка'}\n\n🔄 Автоповтор ${nextRetry}/2 через 5 мин...`
          );
          setTimeout(() => _startRecountTraining(epochs, nextRetry), 5 * 60 * 1000);
        } else {
          _sendTelegramNotification(
            `🔴 <b>Обучение YOLO провалилось!</b>\n\n${result.error || 'Неизвестная ошибка'}\n\nВсе ${retryCount} попытки исчерпаны. Модель восстановлена из бэкапа.`
          );
        }
      }
    })
    .catch(err => {
      _recountTrainState = {
        ..._recountTrainState,
        status: 'error',
        finishedAt: new Date().toISOString(),
        error: err.message,
      };

      // Retry при исключении
      if (retryCount < 2) {
        const nextRetry = retryCount + 1;
        console.log(`[Recount Scheduler] Exception, retry ${nextRetry}/2 через 5 мин...`);
        _sendTelegramNotification(
          `⚠️ <b>Обучение YOLO: исключение</b>\n\n${err.message}\n\n🔄 Автоповтор ${nextRetry}/2 через 5 мин...`
        );
        setTimeout(() => _startRecountTraining(epochs, nextRetry), 5 * 60 * 1000);
      } else {
        _sendTelegramNotification(
          `🔴 <b>Обучение YOLO провалилось!</b>\n\n${err.message}\n\nВсе ${retryCount} попытки исчерпаны.`
        );
      }
    });
}

function setupAiDashboardAPI(app) {
  console.log('[AI Dashboard] Инициализация...');

  // GET /api/ai-dashboard/metrics — все метрики одним запросом
  app.get('/api/ai-dashboard/metrics', requireEmployee, async (req, res) => {
    try {
      const [zReport, coffeeMachine, cigaretteVision, shiftAi] = await Promise.all([
        getZReportMetrics(),
        getCoffeeMachineMetrics(),
        getCigaretteVisionMetrics(),
        getShiftAiMetrics(),
      ]);

      res.json({
        success: true,
        updatedAt: new Date().toISOString(),
        systems: {
          zReport,
          coffeeMachine,
          cigaretteVision,
          shiftAi,
        },
      });
    } catch (error) {
      console.error('[AI Dashboard] Metrics error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // GET /api/ai-dashboard/retrain-status — статус YOLO авто-обучения
  app.get('/api/ai-dashboard/retrain-status', requireEmployee, async (req, res) => {
    try {
      const { getRetrainStatus } = require('./yolo_retrain_scheduler');
      const status = await getRetrainStatus();
      res.json({ success: true, ...status });
    } catch (error) {
      console.error('[AI Dashboard] Retrain status error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/ai-dashboard/retrain — ручной запуск обучения YOLO
  app.post('/api/ai-dashboard/retrain', requireEmployee, async (req, res) => {
    try {
      const { triggerManualRetrain } = require('./yolo_retrain_scheduler');
      const result = await triggerManualRetrain();
      res.json(result);
    } catch (error) {
      console.error('[AI Dashboard] Manual retrain error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/ai-dashboard/trigger-recount-training — запуск обучения в фоне (async)
  app.post('/api/ai-dashboard/trigger-recount-training', requireEmployee, (req, res) => {
    if (_recountTrainState.status === 'running') {
      return res.json({ success: false, error: 'already_running', state: _recountTrainState });
    }
    const epochs = req.body?.epochs || 30;
    console.log(`[AI Dashboard] Ручной запуск обучения пересчёта (${epochs} эпох) в фоне...`);
    _startRecountTraining(epochs);
    res.json({ success: true, started: true, state: _recountTrainState });
  });

  // GET /api/ai-dashboard/recount-train-status — статус текущего/последнего обучения
  app.get('/api/ai-dashboard/recount-train-status', requireEmployee, (req, res) => {
    res.json({ success: true, ..._recountTrainState });
  });

  // GET /api/ai-dashboard/recount-train-schedule — получить расписание
  app.get('/api/ai-dashboard/recount-train-schedule', requireEmployee, (req, res) => {
    res.json({ success: true, scheduledTime: _scheduleTime });
  });

  // POST /api/ai-dashboard/recount-train-schedule — сохранить/удалить расписание
  app.post('/api/ai-dashboard/recount-train-schedule', requireEmployee, async (req, res) => {
    try {
      const { time } = req.body; // "HH:mm" или null для отключения
      _scheduleTime = time || null;
      await db.upsert('app_settings', { key: 'recount_train_schedule', data: { time: _scheduleTime } }, 'key');
      _scheduleNextRun(_scheduleTime); // перепланируем (или отменяем если null)
      console.log(`[Recount Scheduler] Расписание ${_scheduleTime ? 'установлено: ' + _scheduleTime : 'отключено'}`);
      res.json({ success: true, scheduledTime: _scheduleTime });
    } catch (error) {
      console.error('[AI Dashboard] Schedule save error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // ============ INTERNAL ENDPOINTS (localhost only, no auth) ============
  // Используются Telegram-ботом для управления обучением

  function requireLocalhost(req, res, next) {
    const ip = req.ip || req.connection.remoteAddress;
    if (ip === '127.0.0.1' || ip === '::1' || ip === '::ffff:127.0.0.1') {
      return next();
    }
    res.status(403).json({ success: false, error: 'Internal only' });
  }

  // GET /api/internal/recount-train-status — статус обучения (без auth)
  app.get('/api/internal/recount-train-status', requireLocalhost, (req, res) => {
    res.json({ success: true, ..._recountTrainState });
  });

  // POST /api/internal/trigger-recount-training — запуск обучения (без auth)
  app.post('/api/internal/trigger-recount-training', requireLocalhost, (req, res) => {
    if (_recountTrainState.status === 'running') {
      return res.json({ success: false, error: 'already_running', state: _recountTrainState });
    }
    const epochs = req.body?.epochs || 50;
    console.log(`[AI Dashboard] Запуск обучения из Telegram бота (${epochs} эпох)...`);
    _startRecountTraining(epochs);
    res.json({ success: true, started: true, state: _recountTrainState });
  });

  // GET /api/ai-dashboard/ai-toggles — получить состояние переключателей ИИ
  app.get('/api/ai-dashboard/ai-toggles', requireEmployee, async (req, res) => {
    try {
      const row = await db.findById('app_settings', 'ai_toggles', 'key');
      const defaults = { zReport: true, coffeeMachine: true, cigaretteVision: true, shiftAi: true };
      const toggles = row?.data || defaults;
      res.json({ success: true, toggles: { ...defaults, ...toggles } });
    } catch (error) {
      console.error('[AI Dashboard] AI toggles GET error:', error.message);
      res.json({ success: true, toggles: { zReport: true, coffeeMachine: true, cigaretteVision: true, shiftAi: true } });
    }
  });

  // PUT /api/ai-dashboard/ai-toggles — обновить переключатели ИИ
  app.put('/api/ai-dashboard/ai-toggles', requireEmployee, async (req, res) => {
    try {
      const { toggles } = req.body;
      if (!toggles || typeof toggles !== 'object') {
        return res.status(400).json({ success: false, error: 'toggles object required' });
      }
      // Merge with defaults
      const row = await db.findById('app_settings', 'ai_toggles', 'key');
      const current = row?.data || {};
      const updated = { ...current, ...toggles };
      await db.upsert('app_settings', { key: 'ai_toggles', data: updated }, 'key');
      console.log(`[AI Dashboard] AI toggles updated:`, updated);
      res.json({ success: true, toggles: updated });
    } catch (error) {
      console.error('[AI Dashboard] AI toggles PUT error:', error.message);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  console.log('[AI Dashboard] Инициализация завершена');
}

// ============ Z-REPORT OCR ============

async function getZReportMetrics() {
  try {
    // Загружаем intelligence (содержит accuracy и dowCoefficients)
    const intelligenceFile = path.join(DATA_DIR, 'z-report-intelligence.json');
    let intelligence = null;

    if (USE_DB_Z) {
      try {
        const row = await db.findById('app_settings', 'z_report_intelligence', 'key');
        if (row?.data) intelligence = row.data;
      } catch (e) { /* fallback to JSON */ }
    }
    if (!intelligence && await fileExists(intelligenceFile)) {
      intelligence = JSON.parse(await fsp.readFile(intelligenceFile, 'utf8'));
    }

    // Training samples count
    let trainingSamplesCount = 0;
    if (USE_DB_Z) {
      try {
        const rows = await db.query('SELECT COUNT(*) as count FROM z_report_training_samples');
        trainingSamplesCount = rows?.[0]?.count || 0;
      } catch (e) { /* ignore */ }
    } else {
      const samplesFile = path.join(DATA_DIR, 'z-report-training-samples.json');
      if (await fileExists(samplesFile)) {
        const samples = JSON.parse(await fsp.readFile(samplesFile, 'utf8'));
        trainingSamplesCount = Array.isArray(samples) ? samples.length : 0;
      }
    }

    // Accuracy по магазинам
    const profiles = intelligence?.shopProfiles || {};
    const shopCount = Object.keys(profiles).length;

    // Агрегируем overall accuracy
    const overall = { totalSum: { total: 0, correct: 0 }, cashSum: { total: 0, correct: 0 } };
    const dowSample = {}; // пример dow коэффициентов из первого магазина с данными

    for (const [, profile] of Object.entries(profiles)) {
      if (profile.accuracy) {
        for (const field of ['totalSum', 'cashSum']) {
          if (profile.accuracy[field]) {
            overall[field].total += profile.accuracy[field].total || 0;
            overall[field].correct += profile.accuracy[field].correct || 0;
          }
        }
      }
      // Берём dowCoefficients из первого магазина с данными
      if (!dowSample.totalSum && profile.totalSum?.dowCoefficients) {
        dowSample.totalSum = profile.totalSum.dowCoefficients;
      }
    }

    const accuracy = {};
    for (const [field, stats] of Object.entries(overall)) {
      accuracy[field] = stats.total > 0
        ? Math.round((stats.correct / stats.total) * 1000) / 10
        : null;
    }

    return {
      name: 'Z-Report OCR',
      status: shopCount > 0 ? 'active' : 'no_data',
      shopCount,
      trainingSamples: trainingSamplesCount,
      accuracy, // { totalSum: 85.7, cashSum: 90.2 } — проценты
      dowCoefficients: dowSample.totalSum || null,
      updatedAt: intelligence?.updatedAt || null,
    };
  } catch (e) {
    console.error('[AI Dashboard] Z-Report metrics error:', e.message);
    return { name: 'Z-Report OCR', status: 'error', error: e.message };
  }
}

// ============ COFFEE MACHINE OCR ============

async function getCoffeeMachineMetrics() {
  try {
    // Загружаем intelligence
    const intelligenceFile = path.join(DATA_DIR, 'coffee-machine-intelligence.json');
    let intelligence = null;

    if (USE_DB_CM) {
      try {
        const row = await db.findById('app_settings', 'coffee_machine_intelligence', 'key');
        if (row?.data) intelligence = row.data;
      } catch (e) { /* fallback */ }
    }
    if (!intelligence && await fileExists(intelligenceFile)) {
      intelligence = JSON.parse(await fsp.readFile(intelligenceFile, 'utf8'));
    }

    // Training samples count
    const trainingFile = path.join(DATA_DIR, 'coffee-machine-training', 'samples.json');
    let trainingSamples = 0;
    if (await fileExists(trainingFile)) {
      const data = JSON.parse(await fsp.readFile(trainingFile, 'utf8'));
      trainingSamples = Array.isArray(data) ? data.length : 0;
    }

    // Считаем accuracy из отчётов: OCR value vs confirmed value
    let totalReadings = 0;
    let correctReadings = 0; // OCR совпал с confirmed
    let avgError = 0;
    let totalError = 0;

    // Читаем последние отчёты
    const reports = [];
    if (USE_DB_CM) {
      try {
        const rows = await db.query(
          'SELECT readings FROM coffee_machine_reports ORDER BY created_at DESC LIMIT 200'
        );
        if (rows) {
          for (const row of rows) {
            if (row.readings) {
              const parsed = typeof row.readings === 'string' ? JSON.parse(row.readings) : row.readings;
              reports.push({ readings: parsed });
            }
          }
        }
      } catch (e) { /* ignore */ }
    }
    if (reports.length === 0) {
      const reportsDir = path.join(DATA_DIR, 'coffee-machine-reports');
      if (await fileExists(reportsDir)) {
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json')).slice(-200);
        for (const file of files) {
          try {
            reports.push(JSON.parse(await fsp.readFile(path.join(reportsDir, file), 'utf8')));
          } catch (e) { /* skip */ }
        }
      }
    }

    // A/B: OCR vs confirmed
    for (const report of reports) {
      if (!report.readings || !Array.isArray(report.readings)) continue;
      for (const reading of report.readings) {
        if ((reading.aiReadNumber !== undefined || reading.ocrNumber !== undefined) && reading.confirmedNumber !== undefined) {
          totalReadings++;
          const ocrVal = parseFloat(reading.aiReadNumber ?? reading.ocrNumber) || 0;
          const confVal = parseFloat(reading.confirmedNumber) || 0;
          const diff = Math.abs(ocrVal - confVal);
          if (diff < 1) correctReadings++; // OCR точен
          totalError += diff;
        }
      }
    }

    if (totalReadings > 0) {
      avgError = Math.round((totalError / totalReadings) * 10) / 10;
    }

    const machineCount = intelligence ? Object.keys(intelligence).filter(k => k !== 'updatedAt').length : 0;

    return {
      name: 'Coffee Machine OCR',
      status: totalReadings > 0 ? 'active' : 'no_data',
      machineCount,
      trainingSamples,
      totalReadings,
      accuracy: totalReadings > 0
        ? Math.round((correctReadings / totalReadings) * 1000) / 10
        : null,
      avgError,
      totalReports: reports.length,
      updatedAt: intelligence?.updatedAt || null,
    };
  } catch (e) {
    console.error('[AI Dashboard] Coffee Machine metrics error:', e.message);
    return { name: 'Coffee Machine OCR', status: 'error', error: e.message };
  }
}

// ============ CIGARETTE VISION YOLO ============

async function getCigaretteVisionMetrics() {
  try {
    // Recognition stats
    const statsFile = path.join(DATA_DIR, 'cigarette-recognition-stats.json');
    let recognitionStats = null;
    if (await fileExists(statsFile)) {
      recognitionStats = JSON.parse(await fsp.readFile(statsFile, 'utf8'));
    }

    // AI error stats
    const errorsFile = path.join(DATA_DIR, 'cigarette-ai-errors.json');
    let errorStats = null;
    if (await fileExists(errorsFile)) {
      errorStats = JSON.parse(await fsp.readFile(errorsFile, 'utf8'));
    }

    // Model status
    const modelPath = path.join(__dirname, '../ml/models/cigarette_detector.pt');
    const modelExists = await fileExists(modelPath);

    // Count training images
    let trainingImages = 0;
    const trainingDirs = [
      path.join(DATA_DIR, 'display-training/images'),
      path.join(DATA_DIR, 'counting-training/images'),
      path.join(DATA_DIR, 'cigarette-training-images'),
    ];
    for (const dir of trainingDirs) {
      if (await fileExists(dir)) {
        try {
          const files = await fsp.readdir(dir);
          trainingImages += files.filter(f => f.endsWith('.jpg') || f.endsWith('.png')).length;
        } catch (e) { /* ignore */ }
      }
    }

    // Агрегируем error stats по продуктам
    const products = errorStats?.products || {};
    let totalErrors = 0;
    let totalDecisions = 0;
    let aiCorrectDecisions = 0;

    for (const [, product] of Object.entries(products)) {
      totalErrors += product.totalErrors || 0;
      const decisions = product.adminDecisions || [];
      totalDecisions += decisions.length;
      // Если админ решил "ai_correct" → ИИ был прав
      aiCorrectDecisions += decisions.filter(d => d.decision === 'ai_correct').length;
    }

    // Counting (пересчёт) stats
    let countingPendingSamples = 0;
    let countingTrainingSamples = 0;
    let countingAnnotatedSamples = 0;
    try {
      const cv = require('../modules/cigarette-vision');
      const cStats = await cv.getTypedTrainingStats(cv.TRAINING_TYPES.COUNTING);
      countingTrainingSamples = cStats.totalSamples || 0;
      countingAnnotatedSamples = cStats.samplesWithAnnotations || 0;

      const pendingFile = path.join(DATA_DIR, 'counting-pending/samples.json');
      if (await fileExists(pendingFile)) {
        const pending = JSON.parse(await fsp.readFile(pendingFile, 'utf8'));
        countingPendingSamples = Array.isArray(pending) ? pending.length : 0;
      }
    } catch (e) { /* ignore — модуль мог не инициализироваться */ }

    return {
      name: 'Cigarette Vision (YOLO)',
      status: modelExists ? 'active' : 'model_missing',
      modelExists,
      trainingImages,
      productsTracked: Object.keys(products).length,
      totalErrors,
      totalDecisions,
      accuracy: totalDecisions > 0
        ? Math.round((aiCorrectDecisions / totalDecisions) * 1000) / 10
        : null,
      recognitionStats: recognitionStats
        ? {
            totalDetections: recognitionStats.totalDetections || 0,
            successfulDetections: recognitionStats.successfulDetections || 0,
            failedDetections: recognitionStats.failedDetections || 0,
          }
        : null,
      countingPendingSamples,
      countingTrainingSamples,
      countingAnnotatedSamples,
    };
  } catch (e) {
    console.error('[AI Dashboard] Cigarette Vision metrics error:', e.message);
    return { name: 'Cigarette Vision (YOLO)', status: 'error', error: e.message };
  }
}

// ============ SHIFT AI VERIFICATION ============

async function getShiftAiMetrics() {
  try {
    // Загружаем аннотации
    let annotations = [];
    const annotationsDir = path.join(DATA_DIR, 'shift-ai-annotations');

    if (USE_DB_SHIFT) {
      try {
        const rows = await db.query(
          'SELECT data FROM shift_ai_annotations ORDER BY created_at DESC LIMIT 500'
        );
        if (rows) {
          for (const row of rows) {
            if (row.data) annotations.push(row.data);
          }
        }
      } catch (e) { /* fallback to JSON */ }
    }

    if (annotations.length === 0 && await fileExists(annotationsDir)) {
      const files = (await fsp.readdir(annotationsDir)).filter(f => f.endsWith('.json'));
      for (const file of files.slice(-500)) {
        try {
          annotations.push(JSON.parse(await fsp.readFile(path.join(annotationsDir, file), 'utf8')));
        } catch (e) { /* skip */ }
      }
    }

    const total = annotations.length;
    const approved = annotations.filter(a => a.status === 'approved').length;
    const rejected = annotations.filter(a => a.status === 'rejected').length;
    const pending = annotations.filter(a => a.status === 'pending' || !a.status).length;

    // Shortages: когда AI обнаружил нехватку товара
    let totalShortagesDetected = 0;
    let shortagesConfirmed = 0; // approved → AI был прав
    for (const a of annotations) {
      if (a.detectedShortages && Array.isArray(a.detectedShortages)) {
        totalShortagesDetected += a.detectedShortages.length;
      }
      if (a.status === 'approved' && a.detectedShortages) {
        shortagesConfirmed += a.detectedShortages.length;
      }
    }

    return {
      name: 'Shift AI Verification',
      status: total > 0 ? 'active' : 'no_data',
      totalAnnotations: total,
      approved,
      rejected,
      pending,
      accuracy: (approved + rejected) > 0
        ? Math.round((approved / (approved + rejected)) * 1000) / 10
        : null,
      totalShortagesDetected,
      shortagesConfirmed,
    };
  } catch (e) {
    console.error('[AI Dashboard] Shift AI metrics error:', e.message);
    return { name: 'Shift AI Verification', status: 'error', error: e.message };
  }
}

module.exports = { setupAiDashboardAPI };
