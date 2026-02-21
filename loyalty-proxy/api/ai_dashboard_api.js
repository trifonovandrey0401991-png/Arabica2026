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
const { requireAuth } = require('../utils/session_middleware');
const db = require('../utils/db');

const USE_DB_Z = process.env.USE_DB_Z_REPORT === 'true' || process.env.USE_DB_ENVELOPE === 'true';
const USE_DB_CM = process.env.USE_DB_COFFEE_MACHINE === 'true';
const USE_DB_CIG = process.env.USE_DB_CIGARETTE_VISION === 'true';
const USE_DB_SHIFT = process.env.USE_DB_SHIFT_AI === 'true';
const DATA_DIR = process.env.DATA_DIR || '/var/www';

function setupAiDashboardAPI(app) {
  console.log('[AI Dashboard] Инициализация...');

  // GET /api/ai-dashboard/metrics — все метрики одним запросом
  app.get('/api/ai-dashboard/metrics', requireAuth, async (req, res) => {
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
  app.get('/api/ai-dashboard/retrain-status', requireAuth, async (req, res) => {
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
  app.post('/api/ai-dashboard/retrain', requireAuth, async (req, res) => {
    try {
      const { triggerManualRetrain } = require('./yolo_retrain_scheduler');
      const result = await triggerManualRetrain();
      res.json(result);
    } catch (error) {
      console.error('[AI Dashboard] Manual retrain error:', error.message);
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
