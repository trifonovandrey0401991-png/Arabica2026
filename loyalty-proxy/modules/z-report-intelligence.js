/**
 * Z-Report Intelligence Module
 * Предсказание ожидаемых значений Z-отчётов по историческим данным.
 *
 * Аналог buildMachineIntelligence() из coffee_machine_api.js,
 * но адаптирован для Z-отчётов:
 * - Счётчик кофемашины растёт монотонно → предсказание через линейный рост
 * - Выручка Z-отчёта сбрасывается ежедневно → предсказание через avg ± stddev
 * - 4 поля вместо 1: totalSum, cashSum, ofdNotSent, resourceKeys
 */

const fsp = require('fs').promises;
const path = require('path');
const { writeJsonFile } = require('../utils/async_fs');
const { fileExists } = require('../utils/file_helpers');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_Z_REPORT === 'true' || process.env.USE_DB_ENVELOPE === 'true';
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const INTELLIGENCE_FILE = path.join(DATA_DIR, 'z-report-intelligence.json');

// Минимум отчётов для формирования диапазона
const MIN_REPORTS_FOR_RANGE = 5;

/**
 * Построить intelligence по всем магазинам из истории envelope_reports
 * Вызывается фоново после сохранения отчёта или training sample
 */
// Debounce: если rebuild вызван повторно в течение 10 секунд — пропускаем
let _lastRebuildTime = 0;

async function buildZReportIntelligence() {
  const now = Date.now();
  if (now - _lastRebuildTime < 10000) {
    return null; // Пропускаем — недавно перестроили
  }
  _lastRebuildTime = now;

  try {
    const reports = await loadAllReports();
    if (!reports || reports.length === 0) {
      console.log('[Z-Report Intelligence] Нет отчётов для анализа');
      return {};
    }

    // Группируем по магазину
    const byShop = {};
    for (const r of reports) {
      const shop = r.shopAddress || r.shop_address;
      if (!shop) continue;
      if (!byShop[shop]) byShop[shop] = [];
      byShop[shop].push(r);
    }

    const shopProfiles = {};

    for (const [shopAddress, shopReports] of Object.entries(byShop)) {
      if (shopReports.length < 2) continue;

      const profile = {
        totalSum: buildFieldStats(shopReports, 'totalSum'),
        cashSum: buildFieldStats(shopReports, 'cashSum'),
        ofdNotSent: buildFieldStats(shopReports, 'ofdNotSent'),
        resourceKeys: buildResourceKeysStats(shopReports),
        totalReports: shopReports.length,
        updatedAt: new Date().toISOString(),
      };

      // Статистика точности из training samples
      profile.accuracy = await buildAccuracyStats(shopAddress);

      shopProfiles[shopAddress] = profile;
    }

    const data = { shopProfiles, updatedAt: new Date().toISOString() };

    // Dual-write: JSON + DB
    await writeJsonFile(INTELLIGENCE_FILE, data);

    if (USE_DB) {
      try {
        await db.upsert('app_settings', {
          key: 'z_report_intelligence',
          data: data,
          updated_at: new Date().toISOString(),
        }, 'key');
      } catch (e) {
        console.error('[Z-Report Intelligence] DB save error:', e.message);
      }
    }

    console.log(`[Z-Report Intelligence] Обновлён: ${Object.keys(shopProfiles).length} магазинов, ${reports.length} отчётов`);
    return data;
  } catch (error) {
    console.error('[Z-Report Intelligence] Ошибка build:', error.message);
    return {};
  }
}

/**
 * Статистика по одному числовому полю (totalSum, cashSum, ofdNotSent)
 * Сбрасывается ежедневно → используем avg ± stddev
 * Дополнительно: коэффициенты по дням недели (0=Вс..6=Сб)
 */
function buildFieldStats(reports, fieldName) {
  // Собираем значения из обеих юрлиц (ООО и ИП) с привязкой к дню недели
  const values = [];
  const byDow = { 0: [], 1: [], 2: [], 3: [], 4: [], 5: [], 6: [] }; // 0=Sun..6=Sat

  for (const r of reports) {
    const date = r.date || (r.createdAt ? r.createdAt.slice(0, 10) : null);
    // Добавляем T12:00:00 чтобы избежать UTC-сдвига на предыдущий день
    const dow = date ? new Date(date + 'T12:00:00').getDay() : null; // 0=Sun..6=Sat

    // ООО
    const oooVal = extractFieldValue(r, 'ooo', fieldName);
    if (oooVal !== null && oooVal > 0) {
      values.push(oooVal);
      if (dow !== null && !isNaN(dow)) byDow[dow].push(oooVal);
    }

    // ИП
    const ipVal = extractFieldValue(r, 'ip', fieldName);
    if (ipVal !== null && ipVal > 0) {
      values.push(ipVal);
      if (dow !== null && !isNaN(dow)) byDow[dow].push(ipVal);
    }
  }

  if (values.length === 0) return null;

  const avg = values.reduce((s, v) => s + v, 0) / values.length;
  const variance = values.reduce((s, v) => s + (v - avg) ** 2, 0) / values.length;
  const stddev = Math.sqrt(variance);

  // Коэффициенты по дням недели: avgDay / avgAll
  // Если данных мало (<3 для дня) — коэффициент 1.0
  const dowCoefficients = {};
  for (let d = 0; d < 7; d++) {
    if (byDow[d].length >= 3) {
      const dayAvg = byDow[d].reduce((s, v) => s + v, 0) / byDow[d].length;
      // Clamp to [0.3, 3.0] — extreme values indicate too little data, not real patterns
      dowCoefficients[d] = Math.min(3.0, Math.max(0.3, Math.round((dayAvg / avg) * 1000) / 1000));
    } else {
      dowCoefficients[d] = 1.0;
    }
  }

  return {
    avg: Math.round(avg * 100) / 100,
    stddev: Math.round(stddev * 100) / 100,
    min: Math.min(...values),
    max: Math.max(...values),
    count: values.length,
    dowCoefficients, // {0: 0.85, 1: 0.95, ..., 5: 1.25, 6: 1.10}
  };
}

/**
 * Статистика для resourceKeys — убывает со временем (как обратный счётчик)
 */
function buildResourceKeysStats(reports) {
  const entries = [];

  for (const r of reports) {
    const date = r.date || (r.createdAt ? r.createdAt.slice(0, 10) : null);
    // resourceKeys пока может быть в отчёте или в training samples
    const oooKeys = r.oooResourceKeys || r.ooo_resource_keys;
    const ipKeys = r.ipResourceKeys || r.ip_resource_keys;

    if (oooKeys != null && oooKeys > 0 && date) {
      entries.push({ value: Number(oooKeys), date });
    }
    if (ipKeys != null && ipKeys > 0 && date) {
      entries.push({ value: Number(ipKeys), date });
    }
  }

  if (entries.length === 0) return null;

  entries.sort((a, b) => a.date.localeCompare(b.date));

  const values = entries.map(e => e.value);
  const lastKnown = values[values.length - 1];
  const lastDate = entries[entries.length - 1].date;

  // Тренд (дневное убывание) — медиана попарных наклонов (устойчива к выбросам)
  let trend = 0;
  if (entries.length >= 2) {
    const slopes = [];
    for (let i = 1; i < entries.length; i++) {
      const daysDiff = (new Date(entries[i].date) - new Date(entries[i - 1].date)) / (1000 * 60 * 60 * 24);
      if (daysDiff > 0) {
        slopes.push((entries[i].value - entries[i - 1].value) / daysDiff);
      }
    }
    if (slopes.length > 0) {
      slopes.sort((a, b) => a - b);
      const mid = Math.floor(slopes.length / 2);
      const medianSlope = slopes.length % 2 === 0
        ? (slopes[mid - 1] + slopes[mid]) / 2
        : slopes[mid];
      trend = Math.round(medianSlope * 100) / 100; // обычно отрицательный
    }
  }

  return {
    lastKnown,
    lastDate,
    trend,
    min: Math.min(...values),
    max: Math.max(...values),
    count: values.length,
  };
}

/**
 * Извлечь значение поля из отчёта (поддерживает camelCase и snake_case)
 */
function extractFieldValue(report, entity, fieldName) {
  // Маппинг: fieldName → ключи в объекте отчёта
  const mapping = {
    totalSum: { ooo: ['oooRevenue', 'ooo_revenue'], ip: ['ipRevenue', 'ip_revenue'] },
    cashSum: { ooo: ['oooCash', 'ooo_cash'], ip: ['ipCash', 'ip_cash'] },
    ofdNotSent: { ooo: ['oooOfdNotSent', 'ooo_ofd_not_sent'], ip: ['ipOfdNotSent', 'ip_ofd_not_sent'] },
  };

  const keys = mapping[fieldName]?.[entity];
  if (!keys) return null;

  for (const key of keys) {
    const val = report[key];
    if (val !== null && val !== undefined) return Number(val);
  }
  return null;
}

/**
 * Статистика точности из training samples
 */
async function buildAccuracyStats(shopAddress) {
  const defaults = {
    totalSum: { total: 0, correct: 0, rate: 0 },
    cashSum: { total: 0, correct: 0, rate: 0 },
    ofdNotSent: { total: 0, correct: 0, rate: 0 },
    resourceKeys: { total: 0, correct: 0, rate: 0 },
  };

  try {
    let samples = [];
    if (USE_DB) {
      const result = await db.query(
        'SELECT data FROM z_report_training_samples WHERE shop_id = $1',
        [shopAddress]
      );
      samples = (result?.rows || []).map(r => r.data);
    } else {
      const samplesFile = path.join(DATA_DIR, 'z-report-training-samples.json');
      if (await fileExists(samplesFile)) {
        const all = JSON.parse(await fsp.readFile(samplesFile, 'utf8'));
        samples = Array.isArray(all) ? all.filter(s => s.shopId === shopAddress) : [];
      }
    }

    if (samples.length === 0) return defaults;

    for (const sample of samples) {
      const correct = sample.correctData || {};
      const recognized = sample.recognizedData || {};
      const correctedFields = sample.correctedFields || [];

      for (const field of ['totalSum', 'cashSum', 'ofdNotSent', 'resourceKeys']) {
        if (correct[field] !== undefined && correct[field] !== null) {
          defaults[field].total++;
          // Если поле НЕ в списке исправленных → ИИ угадал
          if (!correctedFields.includes(field)) {
            defaults[field].correct++;
          }
        }
      }
    }

    // Вычисляем rate
    for (const field of Object.keys(defaults)) {
      if (defaults[field].total > 0) {
        defaults[field].rate = Math.round((defaults[field].correct / defaults[field].total) * 1000) / 1000;
      }
    }

    return defaults;
  } catch (e) {
    console.error('[Z-Report Intelligence] Accuracy stats error:', e.message);
    return defaults;
  }
}

/**
 * Получить ожидаемые диапазоны для конкретного магазина
 * Возвращает { totalSum: {min, max}, cashSum: {min, max}, ofdNotSent: {min, max}, resourceKeys: {min, max} }
 * @param {object} intelligence
 * @param {string} shopAddress
 * @param {Date} [forDate] - дата, для которой считаем (default: сегодня)
 */
function getExpectedRanges(intelligence, shopAddress, forDate) {
  if (!intelligence?.shopProfiles?.[shopAddress]) return null;

  const profile = intelligence.shopProfiles[shopAddress];
  const ranges = {};

  // День недели для корректировки (0=Sun..6=Sat)
  const targetDate = forDate || new Date();
  const dow = targetDate.getDay();

  // totalSum: avg * dowCoeff ± 2*stddev
  if (profile.totalSum && profile.totalSum.count >= MIN_REPORTS_FOR_RANGE) {
    const s = profile.totalSum;
    const coeff = s.dowCoefficients?.[dow] ?? 1.0;
    const adjustedAvg = Math.round(s.avg * coeff * 100) / 100;
    ranges.totalSum = {
      min: Math.max(0, Math.round(adjustedAvg - 2 * s.stddev)),
      max: Math.round(adjustedAvg + 2 * s.stddev),
      avg: adjustedAvg,
      dowCoefficient: coeff,
    };
  }

  // cashSum: avg * dowCoeff ± 2*stddev, ограничен totalSum.max
  if (profile.cashSum && profile.cashSum.count >= MIN_REPORTS_FOR_RANGE) {
    const s = profile.cashSum;
    const coeff = s.dowCoefficients?.[dow] ?? 1.0;
    const adjustedAvg = Math.round(s.avg * coeff * 100) / 100;
    ranges.cashSum = {
      min: Math.max(0, Math.round(adjustedAvg - 2 * s.stddev)),
      max: Math.round(adjustedAvg + 2 * s.stddev),
      avg: adjustedAvg,
      dowCoefficient: coeff,
    };
    // cashSum не может быть больше totalSum
    if (ranges.totalSum) {
      ranges.cashSum.max = Math.min(ranges.cashSum.max, ranges.totalSum.max);
    }
  }

  // ofdNotSent: обычно 0-5, максимум из истории + запас (без dowCoeff — нерелевантно)
  if (profile.ofdNotSent && profile.ofdNotSent.count >= MIN_REPORTS_FOR_RANGE) {
    ranges.ofdNotSent = {
      min: 0,
      max: Math.max(10, profile.ofdNotSent.max + 2),
      avg: profile.ofdNotSent.avg,
    };
  }

  // resourceKeys: убывает со временем, предсказываем по тренду
  if (profile.resourceKeys && profile.resourceKeys.count >= 3) {
    const rk = profile.resourceKeys;
    if (rk.lastKnown && rk.lastDate) {
      const daysSince = Math.max(0, (Date.now() - new Date(rk.lastDate).getTime()) / (1000 * 60 * 60 * 24));
      const expected = rk.lastKnown + Math.round(rk.trend * daysSince);
      ranges.resourceKeys = {
        min: Math.max(0, expected - 20),
        max: expected + 10,
        avg: expected,
      };
    } else {
      ranges.resourceKeys = {
        min: Math.max(0, rk.min - 20),
        max: rk.max + 10,
        avg: Math.round((rk.min + rk.max) / 2),
      };
    }
  }

  return Object.keys(ranges).length > 0 ? ranges : null;
}

/**
 * Загрузить intelligence (JSON → DB fallback)
 */
async function loadZReportIntelligence() {
  try {
    // Сначала JSON
    if (await fileExists(INTELLIGENCE_FILE)) {
      return JSON.parse(await fsp.readFile(INTELLIGENCE_FILE, 'utf8'));
    }

    // Fallback: DB
    if (USE_DB) {
      const row = await db.findById('app_settings', 'z_report_intelligence', 'key');
      if (row?.data) return row.data;
    }

    return null;
  } catch (e) {
    console.error('[Z-Report Intelligence] Load error:', e.message);
    return null;
  }
}

/**
 * Загрузить все отчёты конвертов (DB или JSON)
 */
async function loadAllReports() {
  if (USE_DB) {
    try {
      return await db.findAll('envelope_reports', {
        orderBy: 'created_at',
        orderDir: 'DESC',
        limit: 500, // последние 500 для анализа
      });
    } catch (e) {
      console.error('[Z-Report Intelligence] DB load error:', e.message);
    }
  }

  // Fallback: JSON
  const reportsDir = path.join(DATA_DIR, 'envelope-reports');
  if (!(await fileExists(reportsDir))) return [];

  const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));
  const reports = [];
  for (const file of files) {
    try {
      const data = JSON.parse(await fsp.readFile(path.join(reportsDir, file), 'utf8'));
      reports.push(data);
    } catch (e) { /* skip */ }
  }
  return reports;
}

module.exports = {
  buildZReportIntelligence,
  loadZReportIntelligence,
  getExpectedRanges,
};
