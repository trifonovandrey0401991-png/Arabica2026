/**
 * Z-Report Templates Module
 * Управление шаблонами распознавания Z-отчётов
 */

const fs = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');
const { writeJsonFile } = require('../utils/async_fs');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_Z_REPORT === 'true';

// Путь к файлу с шаблонами
const TEMPLATES_FILE = path.join(__dirname, '../data/z-report-templates.json');
const SAMPLES_FILE = path.join(__dirname, '../data/z-report-training-samples.json');
const LEARNED_PATTERNS_FILE = path.join(__dirname, '../data/z-report-learned-patterns.json');

// Убедимся что директория data существует
async function ensureDataDir() {
  const dataDir = path.join(__dirname, '../data');
  try {
    await fs.access(dataDir);
  } catch {
    await fs.mkdir(dataDir, { recursive: true });
  }
}

/**
 * Нормализация типичных OCR-ошибок в Z-отчётах
 * Исправляет частые ошибки распознавания: М↔Н, Ф↔О, и т.д.
 * @param {string} text - Текст для нормализации
 * @returns {string} - Нормализованный текст
 */
function normalizeOcrErrors(text) {
  if (!text) return text;

  return text
    // СУННА/СУМНА/СУНМА → СУММА (любые комбинации Н↔М)
    .replace(/СУ[НМM][НМM]А/gi, 'СУММА')
    // ОД → ФД, ОА → ФА (О вместо Ф) - для "НЕПЕРЕДАННЫХ ФД"
    // \b не работает с кириллицей, используем пробел/границу
    .replace(/(\s)ОД(\s|:|$)/g, '$1ФД$2')
    .replace(/(\s)ОА(\s|:|$)/g, '$1ФА$2')
    // СНЕНУ → СМЕНУ (Н вместо М)
    .replace(/СНЕНУ/gi, 'СМЕНУ');
}

/**
 * Загрузить шаблоны из файла
 */
async function loadTemplates() {
  if (USE_DB) {
    try {
      const rows = await db.findAll('z_report_templates', { orderBy: 'created_at', orderDir: 'ASC' });
      return { templates: rows.map(r => r.data) };
    } catch (e) {
      console.error('[Z-Report] DB loadTemplates error:', e.message);
      // fallback to JSON
    }
  }
  try {
    await ensureDataDir();
    const data = await fs.readFile(TEMPLATES_FILE, 'utf-8');
    return JSON.parse(data);
  } catch (e) {
    return { templates: [] };
  }
}

/**
 * Сохранить шаблоны в файл
 */
async function saveTemplates(data) {
  await ensureDataDir();
  await writeJsonFile(TEMPLATES_FILE, data);

  if (USE_DB) {
    try {
      for (const template of (data.templates || [])) {
        await db.upsert('z_report_templates', {
          id: template.id,
          data: template,
          created_at: template.createdAt || new Date().toISOString(),
          updated_at: template.updatedAt || new Date().toISOString(),
        });
      }
    } catch (e) {
      console.error('[Z-Report] DB saveTemplates error:', e.message);
    }
  }
}

/**
 * Получить все шаблоны
 */
async function getTemplates(shopId = null) {
  const data = await loadTemplates();
  let templates = data.templates || [];

  if (shopId) {
    templates = templates.filter(t => t.shopId === shopId || !t.shopId);
  }

  // Сортируем по успешности и частоте использования
  templates.sort((a, b) => {
    const scoreA = (a.successRate || 0) * (a.usageCount || 1);
    const scoreB = (b.successRate || 0) * (b.usageCount || 1);
    return scoreB - scoreA;
  });

  return templates;
}

/**
 * Получить шаблон по ID
 */
async function getTemplate(id) {
  const data = await loadTemplates();
  return (data.templates || []).find(t => t.id === id);
}

/**
 * Сохранить шаблон
 */
async function saveTemplate(template, sampleImage = null) {
  const data = await loadTemplates();
  const templates = data.templates || [];

  // Генерируем ID если новый
  if (!template.id) {
    template.id = uuidv4();
    template.createdAt = new Date().toISOString();
  }
  template.updatedAt = new Date().toISOString();

  // Ищем существующий
  const existingIndex = templates.findIndex(t => t.id === template.id);

  if (existingIndex >= 0) {
    // Сохраняем статистику
    template.usageCount = templates[existingIndex].usageCount || 0;
    template.successRate = templates[existingIndex].successRate || 0;
    templates[existingIndex] = template;
  } else {
    template.usageCount = 0;
    template.successRate = 0;
    templates.push(template);
  }

  // Сохраняем образец изображения если есть
  if (sampleImage) {
    const imagesDir = path.join(__dirname, '../data/template-images');
    try {
      await fs.mkdir(imagesDir, { recursive: true });
      await fs.writeFile(
        path.join(imagesDir, `${template.id}.jpg`),
        Buffer.from(sampleImage, 'base64')
      );
    } catch (e) {
      console.error('Ошибка сохранения образца:', e);
    }
  }

  await saveTemplates({ templates });
  return template;
}

/**
 * Удалить шаблон
 */
async function deleteTemplate(id) {
  const data = await loadTemplates();
  const templates = (data.templates || []).filter(t => t.id !== id);
  await saveTemplates({ templates });

  if (USE_DB) {
    try { await db.deleteById('z_report_templates', id); }
    catch (e) { console.error('[Z-Report] DB deleteTemplate error:', e.message); }
  }

  // Удаляем образец изображения
  try {
    await fs.unlink(path.join(__dirname, '../data/template-images', `${id}.jpg`));
  } catch (e) {
    // Файл может не существовать
  }

  return true;
}

/**
 * Найти подходящий шаблон для магазина
 */
async function findTemplateForShop(shopId) {
  const templates = await getTemplates(shopId);

  // Приоритет: шаблон для конкретного магазина > общий с высокой успешностью
  const shopTemplate = templates.find(t => t.shopId === shopId);
  if (shopTemplate) return shopTemplate;

  // Возвращаем самый успешный общий шаблон
  return templates.find(t => !t.shopId && (t.successRate || 0) > 0.5);
}

/**
 * Обновить статистику шаблона
 */
async function updateTemplateStats(templateId, wasSuccessful) {
  const data = await loadTemplates();
  const template = (data.templates || []).find(t => t.id === templateId);

  if (template) {
    template.usageCount = (template.usageCount || 0) + 1;
    // EMA (Exponential Moving Average) для successRate
    // alpha уменьшается с ростом usageCount: 1/1, 1/2, ... 1/50 (минимум 0.02)
    const oldRate = template.successRate || 0;
    const alpha = Math.max(0.02, 1 / Math.min(template.usageCount, 50));
    template.successRate = oldRate * (1 - alpha) + (wasSuccessful ? 1 : 0) * alpha;

    await saveTemplates(data);
  }
}

// ============ Образцы для обучения ============

/**
 * Загрузить образцы
 */
async function loadTrainingSamples() {
  if (USE_DB) {
    try {
      const rows = await db.findAll('z_report_training_samples', { orderBy: 'created_at', orderDir: 'ASC' });
      return { samples: rows.map(r => r.data) };
    } catch (e) {
      console.error('[Z-Report] DB loadTrainingSamples error:', e.message);
    }
  }
  try {
    await ensureDataDir();
    const data = await fs.readFile(SAMPLES_FILE, 'utf-8');
    return JSON.parse(data);
  } catch (e) {
    return { samples: [] };
  }
}

/**
 * Сохранить образцы (JSON + полный DB sync при ротации)
 * @param {Object} data - { samples: [...] }
 * @param {boolean} fullDbSync - true при ротации (удалены старые), false при обычном добавлении
 */
async function saveTrainingSamples(data, fullDbSync = true) {
  await ensureDataDir();
  await writeJsonFile(SAMPLES_FILE, data);

  if (USE_DB && fullDbSync) {
    try {
      for (const sample of (data.samples || [])) {
        await db.upsert('z_report_training_samples', {
          id: sample.id,
          shop_id: sample.shopId || null,
          template_id: sample.templateId || null,
          data: sample,
          created_at: sample.createdAt || new Date().toISOString(),
        });
      }
    } catch (e) {
      console.error('[Z-Report] DB saveTrainingSamples error:', e.message);
    }
  }
}

/**
 * Upsert одного образца в DB (вместо полного sync)
 */
async function upsertSingleSampleToDB(sample) {
  if (!USE_DB) return;
  try {
    await db.upsert('z_report_training_samples', {
      id: sample.id,
      shop_id: sample.shopId || null,
      template_id: sample.templateId || null,
      data: sample,
      created_at: sample.createdAt || new Date().toISOString(),
    });
  } catch (e) {
    console.error('[Z-Report] DB upsertSingleSample error:', e.message);
  }
}

// Максимальное количество образцов для хранения
const MAX_TRAINING_SAMPLES = 150;
// Минимальное количество образцов на магазин при ротации
const MIN_SAMPLES_PER_SHOP = 5;

/**
 * Удалить файл изображения образца
 */
async function deleteSampleImage(sampleId) {
  try {
    const imagePath = path.join(__dirname, '../data/training-images', `${sampleId}.jpg`);
    await fs.unlink(imagePath);
  } catch (e) {
    // Файл может не существовать - это нормально
  }
}

/**
 * Ротация образцов - удаляет старые при превышении лимита
 * Сохраняет минимум MIN_SAMPLES_PER_SHOP образцов на каждый магазин
 */
async function rotateSamples(samples) {
  if (samples.length <= MAX_TRAINING_SAMPLES) {
    return { samples, deleted: 0 };
  }

  console.log(`[Training] Ротация образцов: ${samples.length} > ${MAX_TRAINING_SAMPLES}`);

  // Группируем по магазинам
  const byShop = {};
  for (const sample of samples) {
    const key = sample.shopId || '_no_shop_';
    if (!byShop[key]) byShop[key] = [];
    byShop[key].push(sample);
  }

  // Сортируем образцы в каждой группе по дате (новые первые)
  for (const key of Object.keys(byShop)) {
    byShop[key].sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));
  }

  // Собираем образцы для сохранения
  const toKeep = [];
  const toDelete = [];

  // Сначала берём минимум от каждого магазина
  for (const key of Object.keys(byShop)) {
    const shopSamples = byShop[key];
    const keep = shopSamples.slice(0, MIN_SAMPLES_PER_SHOP);
    const rest = shopSamples.slice(MIN_SAMPLES_PER_SHOP);
    toKeep.push(...keep);
    toDelete.push(...rest);
  }

  // Если ещё есть место - добавляем остальные по дате
  if (toKeep.length < MAX_TRAINING_SAMPLES) {
    // Сортируем оставшиеся по дате (новые первые)
    toDelete.sort((a, b) => new Date(b.createdAt) - new Date(a.createdAt));

    const available = MAX_TRAINING_SAMPLES - toKeep.length;
    const additional = toDelete.splice(0, available);
    toKeep.push(...additional);
  }

  // Удаляем изображения и DB-записи удалённых образцов
  for (const sample of toDelete) {
    await deleteSampleImage(sample.id);
    if (USE_DB) {
      try { await db.deleteById('z_report_training_samples', sample.id); } catch { /* ignore */ }
    }
  }

  console.log(`[Training] Удалено ${toDelete.length} старых образцов, осталось ${toKeep.length}`);

  return { samples: toKeep, deleted: toDelete.length };
}

/**
 * Добавить образец для обучения
 */
async function addTrainingSample({
  imageBase64,
  rawText,
  correctData,
  recognizedData,
  shopId,
  templateId,
  fieldRegions, // { totalSum: {x,y,width,height}, cashSum: {...}, ... }
}) {
  const data = await loadTrainingSamples();
  let samples = data.samples || [];

  const sample = {
    id: uuidv4(),
    createdAt: new Date().toISOString(),
    rawText,
    correctData,
    recognizedData,
    shopId,
    templateId,
    fieldRegions: fieldRegions || null,
    // Вычисляем какие поля были исправлены (только если есть recognizedData для сравнения)
    correctedFields: recognizedData
      ? Object.keys(correctData).filter(key => correctData[key] !== recognizedData[key])
      : []
  };

  samples.push(sample);

  // Автоматическая ротация при превышении лимита
  const rotationResult = await rotateSamples(samples);
  samples = rotationResult.samples;
  const hadRotation = rotationResult.deleted > 0;

  // Сохраняем изображение
  if (imageBase64) {
    const imagesDir = path.join(__dirname, '../data/training-images');
    try {
      await fs.mkdir(imagesDir, { recursive: true });
      await fs.writeFile(
        path.join(imagesDir, `${sample.id}.jpg`),
        Buffer.from(imageBase64.replace(/^data:image\/\w+;base64,/, ''), 'base64')
      );
    } catch (e) {
      console.error('Ошибка сохранения образца:', e);
    }
  }

  // JSON всегда пишем полностью, DB — оптимизированно
  await saveTrainingSamples({ samples }, hadRotation);
  if (!hadRotation) {
    // Без ротации — upsert только новый sample (O(1) вместо O(n))
    await upsertSingleSampleToDB(sample);
  }

  // Анализируем образцы для улучшения паттернов
  const learningResult = await analyzeAndImprovePatterns(samples);

  // Обновляем выученные регионы если указаны
  if (fieldRegions && shopId) {
    updateLearnedRegions(shopId).catch(e =>
      console.error('[Training] Ошибка обновления регионов:', e.message)
    );
  }

  // Возвращаем образец вместе с результатом обучения
  return {
    sample,
    learningResult
  };
}

/**
 * Загрузить выученные паттерны
 */
async function loadLearnedPatterns() {
  if (USE_DB) {
    try {
      const row = await db.findById('app_settings', 'z_report_learned_patterns', 'key');
      if (row && row.data) return row.data;
    } catch (e) {
      console.error('[Z-Report] DB loadLearnedPatterns error:', e.message);
    }
  }
  try {
    await ensureDataDir();
    const data = await fs.readFile(LEARNED_PATTERNS_FILE, 'utf-8');
    return JSON.parse(data);
  } catch (e) {
    return {
      patterns: {
        totalSum: [],
        cashSum: [],
        ofdNotSent: [],
        resourceKeys: []
      },
      lastUpdated: null,
      samplesAnalyzed: 0
    };
  }
}

/**
 * Сохранить выученные паттерны
 */
async function saveLearnedPatterns(data) {
  await ensureDataDir();
  await writeJsonFile(LEARNED_PATTERNS_FILE, data);

  if (USE_DB) {
    try {
      await db.upsert('app_settings', {
        key: 'z_report_learned_patterns',
        data: data,
        updated_at: new Date().toISOString(),
      }, 'key');
    } catch (e) {
      console.error('[Z-Report] DB saveLearnedPatterns error:', e.message);
    }
  }
}

/**
 * Извлекает паттерн из текста для заданного значения
 * @param {string} rawText - Полный текст чека
 * @param {number|string} value - Правильное значение
 * @param {string} fieldType - Тип поля (totalSum, cashSum, ofdNotSent, resourceKeys)
 * @returns {Object|null} - Найденный паттерн или null
 */
function extractPatternFromText(rawText, value, fieldType) {
  // Функция логирования причин неудачи
  const logReason = (reason) => {
    console.log(`[Training] ${fieldType}: паттерн не найден - ${reason}`);
  };

  if (!rawText || rawText.trim().length < 50) {
    logReason('текст слишком короткий');
    return null;
  }
  if (value === null || value === undefined) {
    logReason('значение пустое');
    return null;
  }

  const valueStr = String(value);
  const lines = rawText.split('\n');

  // Форматы числа для поиска
  let searchFormats = [];

  if (fieldType === 'ofdNotSent') {
    // Для ОФД: ищем только если есть контекст (не просто 0 в случайном месте)
    // Пропускаем значение 0, т.к. оно встречается слишком часто
    if (parseInt(value) === 0) {
      // Для 0 ищем специфичные паттерны ОФД
      const ofdKeywords = ['НЕПЕРЕДАНН', 'НЕ ПЕРЕДАН', 'ОФД', 'ФД:', 'ФА:'];
      for (const line of lines) {
        const upperLine = line.toUpperCase();
        for (const keyword of ofdKeywords) {
          if (upperLine.includes(keyword) && line.includes('0')) {
            // Нашли строку с ключевым словом и 0
            const cleanPrefix = line.replace(/[:\s]*0.*$/, '').trim();
            if (cleanPrefix.length >= 5) {  // Снижено с 10 до 5
              const escapedPrefix = cleanPrefix
                .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                .replace(/\s+/g, '\\s*');
              return {
                context: cleanPrefix,
                lineExample: line.trim(),
                pattern: escapedPrefix,
                foundValue: '0',
                confidence: 'high'
              };
            }
          }
        }
      }
      return null;
    }
    searchFormats = [valueStr];
  } else if (fieldType === 'resourceKeys') {
    // Для ресурса ключей: ищем целое число
    searchFormats = [valueStr];
  } else {
    // Для сумм ищем разные форматы
    const num = parseFloat(value);
    if (isNaN(num) || num <= 0) return null;

    searchFormats = [
      '=' + num.toFixed(2),  // АТОЛ формат: =14095.00
      num.toFixed(2),
      num.toFixed(2).replace('.', ','),
      // С пробелами в тысячах
      num.toLocaleString('ru-RU', { minimumFractionDigits: 2 }),
    ];
  }

  // Ключевые слова для разных полей
  const fieldKeywords = {
    totalSum: ['ИТОГО', 'ВСЕГО', 'ВЫРУЧКА', 'СУММА ПРИХ', 'СУМНА ПРИХ', 'СУННА ПРИХ'],
    cashSum: ['НАЛИЧН', 'НАЛИЧ', 'НАЛ.'],
    ofdNotSent: ['НЕПЕРЕДАНН', 'НЕ ПЕРЕДАН', 'ОФД'],
    resourceKeys: ['РЕСУРС КЛЮЧ', 'РЕСУРС КЛ', 'РЕС. КЛЮЧ', 'КЛЮЧЕЙ', 'КЛЮЧИ']
  };

  // Слова-исключения (если строка содержит их - пропускаем)
  const fieldExclusions = {
    totalSum: ['БЕЗНАЛИЧ', 'НАЛИЧН'],  // totalSum не должен содержать наличные
    cashSum: ['БЕЗНАЛИЧ'],  // cashSum не должен содержать БЕЗналичные
    ofdNotSent: [],
    resourceKeys: []
  };

  const keywords = fieldKeywords[fieldType] || [];
  const exclusions = fieldExclusions[fieldType] || [];

  // Первый проход: ищем значение на той же строке с ключевым словом
  for (let i = 0; i < lines.length; i++) {
    const line = lines[i];
    const upperLine = line.toUpperCase();

    // Проверяем что строка содержит релевантные ключевые слова
    const hasKeyword = keywords.length === 0 || keywords.some(kw => upperLine.includes(kw));
    if (!hasKeyword) continue;

    // Проверяем исключения
    const hasExclusion = exclusions.some(ex => upperLine.includes(ex));
    if (hasExclusion) continue;

    for (const format of searchFormats) {
      const idx = line.indexOf(format);
      if (idx !== -1) {
        // Нашли значение в строке, извлекаем контекст
        const prefix = line.substring(0, idx).trim();

        // Убираем цифры из префикса (могут быть номера строк и т.п.)
        const cleanPrefix = prefix.replace(/^\d+[\s.:)]*/, '').trim();

        if (cleanPrefix.length >= 5) {
          // Экранируем спецсимволы regex
          const escapedPrefix = cleanPrefix
            .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
            .replace(/\s+/g, '\\s*');

          return {
            context: cleanPrefix,
            lineExample: line.trim(),
            pattern: escapedPrefix,
            foundValue: format,
            confidence: cleanPrefix.length > 15 ? 'high' : 'medium'
          };
        }
      }
    }
  }

  // Второй проход: ищем значение на отдельной строке, контекст на предыдущей
  // (OCR часто разбивает метку и значение на разные строки)
  for (let i = 1; i < lines.length; i++) {
    const line = lines[i].trim();
    const prevLine = lines[i - 1].trim();
    const upperPrevLine = prevLine.toUpperCase();

    // Проверяем что предыдущая строка содержит ключевое слово
    const hasKeyword = keywords.some(kw => upperPrevLine.includes(kw));
    if (!hasKeyword) continue;

    // Проверяем исключения
    const hasExclusion = exclusions.some(ex => upperPrevLine.includes(ex));
    if (hasExclusion) continue;

    for (const format of searchFormats) {
      // Значение должно быть в начале строки или вся строка
      if (line === format || line.startsWith(format) || line.startsWith('=' + format)) {
        // Используем предыдущую строку как контекст
        const cleanPrefix = prevLine.replace(/[:\s=]*$/, '').trim();

        if (cleanPrefix.length >= 5) {
          const escapedPrefix = cleanPrefix
            .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
            .replace(/\s+/g, '\\s*');

          return {
            context: cleanPrefix,
            lineExample: prevLine + ' ' + line,
            pattern: escapedPrefix,
            foundValue: format,
            confidence: cleanPrefix.length > 15 ? 'high' : 'medium'
          };
        }
      }
    }
  }

  // Третий проход: АТОЛ блочный формат
  // Метки идут в одном блоке, значения в другом, порядок совпадает
  // Ищем строку с ключевым словом, вычисляем её позицию в блоке меток
  // Затем ищем блок значений и берём значение на той же позиции

  // Общий паттерн для суффиксов (AH., ОД., дн., дней, шт.)
  const suffixPattern = /\s*([АA][НH]|[ОO]Д|дн|дней|шт)\.?\s*$/i;
  // Паттерн для числа с возможным суффиксом
  const numberWithSuffixPattern = /^=?\d+([.,]\d+)?(\s*([АA][НH]|[ОO]Д|дн|дней|шт)\.?)?\s*$/i;

  // АТОЛ блочный алгоритм работает для ВСЕХ полей
  // Для счётчиков (resourceKeys, ofdNotSent) - блок после "ЧЕКОВ ЗА СМЕНУ"
  // Для сумм (totalSum, cashSum) - блок после "СУММА ПРИХ. ВСЕГО"

  // Определяем маркеры блока для разных типов полей
  const blockMarkers = {
    // Для счётчиков
    resourceKeys: ['ЧЕКОВ ЗА СМЕНУ', 'ЧЕКОВ ЗА СНЕНУ'],
    ofdNotSent: ['ЧЕКОВ ЗА СМЕНУ', 'ЧЕКОВ ЗА СНЕНУ'],
    // Для сумм - начало блока сумм
    totalSum: ['СУММА ПРИХ', 'СУМНА ПРИХ', 'СУННА ПРИХ', 'ПРИХОД'],
    cashSum: ['СУММА ПРИХ', 'СУМНА ПРИХ', 'СУННА ПРИХ', 'ПРИХОД']
  };

  const markers = blockMarkers[fieldType] || [];

  // Ищем метку поля и первую метку блока
  let labelLineIdx = -1;
  let firstLabelIdx = -1;

  for (let i = 0; i < lines.length; i++) {
    const upperLine = lines[i].toUpperCase();

    // Первая метка блока
    if (firstLabelIdx === -1) {
      for (const marker of markers) {
        if (upperLine.includes(marker)) {
          firstLabelIdx = i;
          break;
        }
      }
    }

    // Метка нашего поля
    if (labelLineIdx === -1 && keywords.some(kw => upperLine.includes(kw))) {
      // Для cashSum проверяем что это именно НАЛИЧНЫЕ, не БЕЗНАЛИЧНЫЕ
      if (fieldType === 'cashSum') {
        if (upperLine.includes('БЕЗНАЛИЧ')) continue;
      }
      // Для totalSum проверяем что это ВСЕГО, не НАЛИЧНЫЕ/БЕЗНАЛИЧНЫЕ
      if (fieldType === 'totalSum') {
        if (upperLine.includes('НАЛИЧН') || upperLine.includes('БЕЗНАЛИЧ')) continue;
      }
      labelLineIdx = i;
    }

    if (firstLabelIdx !== -1 && labelLineIdx !== -1) break;
  }

  if (labelLineIdx !== -1 && firstLabelIdx !== -1) {
    const labelOffset = labelLineIdx - firstLabelIdx;
    console.log(`[Training] АТОЛ блок для ${fieldType}: firstLabel=${firstLabelIdx}, fieldLabel=${labelLineIdx}, offset=${labelOffset}`);

    // Ищем блок значений
    // ВАЖНО: блок значений может быть далеко от меток, ищем от первой метки блока
    let valuesStartIdx = -1;

    // Ищем начало блока значений - это первое число после первой метки блока
    // Увеличиваем диапазон поиска до 30 строк
    for (let i = firstLabelIdx + 1; i < Math.min(firstLabelIdx + 30, lines.length); i++) {
      const line = lines[i].trim();
      // Число (возможно с суффиксом или знаком =)
      if (line.match(numberWithSuffixPattern)) {
        valuesStartIdx = i;
        break;
      }
    }

    if (valuesStartIdx !== -1) {
      // Ищем значение на позиции offset от начала блока значений
      const valueLineIdx = valuesStartIdx + labelOffset;
      console.log(`[Training] АТОЛ блок: valuesStart=${valuesStartIdx}, valueLineIdx=${valueLineIdx}`);

      if (valueLineIdx < lines.length) {
        let valueLine = lines[valueLineIdx].trim();
        // Убираем суффикс и знак =
        let cleanValue = valueLine.replace(suffixPattern, '').replace(/^=/, '').trim();

        for (const format of searchFormats) {
          // Сравниваем без = для АТОЛ формата
          const formatNoEquals = format.replace(/^=/, '');
          if (cleanValue === format || cleanValue === formatNoEquals || valueLine.startsWith(format)) {
            const labelLine = lines[labelLineIdx].trim();
            const cleanPrefix = labelLine.replace(/[:\s=]*$/, '').trim();

            if (cleanPrefix.length >= 5) {
              const escapedPrefix = cleanPrefix
                .replace(/[.*+?^${}()|[\]\\]/g, '\\$&')
                .replace(/\s+/g, '\\s*');

              console.log(`[Training] Найден АТОЛ паттерн для ${fieldType}: "${cleanPrefix}" -> ${cleanValue}`);

              return {
                context: cleanPrefix,
                lineExample: labelLine + ' ... ' + valueLine,
                pattern: escapedPrefix,
                foundValue: cleanValue,
                confidence: 'high'
              };
            }
          }
        }
      }
    }
  }

  logReason('ни один из 3 проходов не нашёл совпадение');
  return null;
}

/**
 * Анализ образцов для улучшения распознавания
 * ТЕПЕРЬ РЕАЛЬНО ОБУЧАЕТСЯ!
 */
async function analyzeAndImprovePatterns(samples) {
  console.log('[Training] Начинаю анализ', samples.length, 'образцов...');

  // Загружаем текущие паттерны
  const learnedData = await loadLearnedPatterns();
  const patterns = learnedData.patterns;

  // Убедимся что все поля инициализированы (для обратной совместимости)
  if (!patterns.resourceKeys) {
    patterns.resourceKeys = [];
  }

  let newPatternsCount = 0;

  // Анализируем каждый образец с исправлениями
  for (const sample of samples) {
    if (!sample.rawText || !sample.correctData) continue;

    // Проходим по исправленным полям
    for (const field of (sample.correctedFields || [])) {
      const correctValue = sample.correctData[field];

      if (correctValue === null || correctValue === undefined) continue;

      // Пробуем извлечь паттерн
      const extracted = extractPatternFromText(sample.rawText, correctValue, field);

      if (extracted) {
        // Нормализуем OCR-ошибки в контексте (СУННА→СУММА, ОД→ФД)
        const normalizedContext = normalizeOcrErrors(extracted.context);
        const normalizedPattern = normalizeOcrErrors(extracted.pattern);

        // Проверяем что такого паттерна ещё нет (с учётом нормализации)
        const exists = patterns[field]?.some(p => {
          const pNormContext = normalizeOcrErrors(p.context);
          const pNormPattern = normalizeOcrErrors(p.pattern);
          return pNormPattern === normalizedPattern || pNormContext === normalizedContext;
        });

        if (!exists && patterns[field]) {
          patterns[field].push({
            pattern: normalizedPattern,
            context: normalizedContext,
            lineExample: extracted.lineExample,
            confidence: extracted.confidence,
            learnedAt: new Date().toISOString(),
            sampleId: sample.id
          });
          newPatternsCount++;
          console.log(`[Training] Новый паттерн для ${field}:`, normalizedContext);
        }
      }
    }
  }

  // Ограничиваем количество паттернов (макс 50 на поле)
  // ВАЖНО: защищённые паттерны (protected: true) никогда не удаляются
  for (const field of Object.keys(patterns)) {
    if (patterns[field].length > 50) {
      // Разделяем защищённые и обычные паттерны
      const protectedPatterns = patterns[field].filter(p => p.protected);
      const normalPatterns = patterns[field].filter(p => !p.protected);

      // Сортируем обычные по уверенности и дате
      normalPatterns.sort((a, b) => {
        if (a.confidence === 'high' && b.confidence !== 'high') return -1;
        if (b.confidence === 'high' && a.confidence !== 'high') return 1;
        return new Date(b.learnedAt) - new Date(a.learnedAt);
      });

      // Оставляем все защищённые + столько обычных сколько влезет
      const maxNormal = 50 - protectedPatterns.length;
      patterns[field] = [...protectedPatterns, ...normalPatterns.slice(0, maxNormal)];
    }
  }

  // Сохраняем обновлённые паттерны
  learnedData.patterns = patterns;
  learnedData.lastUpdated = new Date().toISOString();
  learnedData.samplesAnalyzed = samples.length;

  await saveLearnedPatterns(learnedData);

  // Инвалидируем кэш в vision-модуле чтобы новые паттерны применились сразу
  try {
    const { invalidateLearnedPatternsCache } = require('./z-report-vision');
    invalidateLearnedPatternsCache();
  } catch { /* vision module may not be loaded */ }

  console.log('[Training] Анализ завершён. Новых паттернов:', newPatternsCount);
  console.log('[Training] Всего паттернов:', {
    totalSum: patterns.totalSum.length,
    cashSum: patterns.cashSum.length,
    ofdNotSent: patterns.ofdNotSent.length,
    resourceKeys: patterns.resourceKeys?.length || 0
  });

  return {
    newPatterns: newPatternsCount,
    totalPatterns: {
      totalSum: patterns.totalSum.length,
      cashSum: patterns.cashSum.length,
      ofdNotSent: patterns.ofdNotSent.length,
      resourceKeys: patterns.resourceKeys?.length || 0
    }
  };
}

/**
 * Получить выученные паттерны для использования в распознавании
 */
async function getLearnedPatterns() {
  const data = await loadLearnedPatterns();
  return data.patterns;
}

/**
 * Получить статистику обучения
 */
async function getTrainingStats() {
  const data = await loadTrainingSamples();
  const samples = data.samples || [];
  const templates = await getTemplates();

  // Подсчёт статистики
  const stats = {
    totalSamples: samples.length,
    totalTemplates: templates.length,
    correctionsByField: {
      totalSum: 0,
      cashSum: 0,
      ofdNotSent: 0,
      resourceKeys: 0
    },
    avgSuccessRate: 0,
    recentSamples: samples.slice(-10).reverse()
  };

  for (const sample of samples) {
    for (const field of sample.correctedFields || []) {
      if (stats.correctionsByField[field] !== undefined) {
        stats.correctionsByField[field]++;
      }
    }
  }

  if (templates.length > 0) {
    stats.avgSuccessRate = templates.reduce((sum, t) => sum + (t.successRate || 0), 0) / templates.length;
  }

  return stats;
}

// ============ Обучение регионам (4 поля) ============

const LEARNED_REGIONS_FILE = path.join(__dirname, '../data/z-report-learned-regions.json');

/**
 * Загрузить выученные регионы
 */
async function loadLearnedRegions() {
  if (USE_DB) {
    try {
      const row = await db.findById('app_settings', 'z_report_learned_regions', 'key');
      if (row && row.data) return row.data;
    } catch (e) {
      console.error('[Z-Report] DB loadLearnedRegions error:', e.message);
    }
  }
  try {
    await ensureDataDir();
    const data = await fs.readFile(LEARNED_REGIONS_FILE, 'utf-8');
    return JSON.parse(data);
  } catch {
    return { shops: {}, lastUpdated: null };
  }
}

/**
 * Сохранить выученные регионы
 */
async function saveLearnedRegions(data) {
  await ensureDataDir();
  await writeJsonFile(LEARNED_REGIONS_FILE, data);

  if (USE_DB) {
    try {
      await db.upsert('app_settings', {
        key: 'z_report_learned_regions',
        data: data,
        updated_at: new Date().toISOString(),
      }, 'key');
    } catch (e) {
      console.error('[Z-Report] DB saveLearnedRegions error:', e.message);
    }
  }
}

/**
 * Усреднение координат регионов по магазину для каждого из 4 полей
 * Берёт последние N образцов с регионами и вычисляет среднее
 * @param {string} shopId - ID/адрес магазина
 * @returns {Object|null} - { totalSum: {x,y,width,height}, cashSum: {...}, ... } или null
 */
async function computeAveragedRegions(shopId) {
  if (!shopId) return null;

  const data = await loadTrainingSamples();
  const samples = (data.samples || [])
    .filter(s => s.shopId === shopId && s.fieldRegions)
    .slice(-10); // Последние 10 с регионами

  if (samples.length < 2) return null; // Минимум 2 образца

  const fields = ['totalSum', 'cashSum', 'ofdNotSent', 'resourceKeys'];
  const result = {};

  for (const field of fields) {
    // Собираем регионы для поля
    const regions = samples
      .filter(s => s.fieldRegions[field] && s.fieldRegions[field].width > 0)
      .map(s => s.fieldRegions[field]);

    if (regions.length < 2) continue;

    // Усредняем координаты
    const avg = { x: 0, y: 0, width: 0, height: 0 };
    for (const r of regions) {
      avg.x += r.x;
      avg.y += r.y;
      avg.width += r.width;
      avg.height += r.height;
    }
    avg.x /= regions.length;
    avg.y /= regions.length;
    avg.width /= regions.length;
    avg.height /= regions.length;

    // Добавляем 10% запас к размерам (чтобы не обрезать)
    avg.x = Math.max(0, avg.x - avg.width * 0.05);
    avg.y = Math.max(0, avg.y - avg.height * 0.05);
    avg.width = Math.min(1 - avg.x, avg.width * 1.1);
    avg.height = Math.min(1 - avg.y, avg.height * 1.1);

    result[field] = avg;
  }

  return Object.keys(result).length > 0 ? result : null;
}

/**
 * Получить выученные регионы для магазина
 * Если есть в кэше — возвращает из кэша, иначе вычисляет
 */
async function getLearnedRegions(shopId) {
  if (!shopId) return null;

  const cached = await loadLearnedRegions();
  if (cached.shops && cached.shops[shopId]) {
    return cached.shops[shopId];
  }

  // Вычисляем и кэшируем
  const regions = await computeAveragedRegions(shopId);
  if (regions) {
    if (!cached.shops) cached.shops = {};
    cached.shops[shopId] = regions;
    cached.lastUpdated = new Date().toISOString();
    await saveLearnedRegions(cached);
    console.log(`[Z-Report] Выучены регионы для ${shopId}:`, Object.keys(regions).join(', '));
  }

  return regions;
}

/**
 * Обновить выученные регионы для магазина (после нового образца)
 */
async function updateLearnedRegions(shopId) {
  if (!shopId) return;

  const regions = await computeAveragedRegions(shopId);
  const cached = await loadLearnedRegions();

  if (regions) {
    if (!cached.shops) cached.shops = {};
    cached.shops[shopId] = regions;
  } else if (cached.shops) {
    delete cached.shops[shopId];
  }

  cached.lastUpdated = new Date().toISOString();
  await saveLearnedRegions(cached);
}

/**
 * Получить список образцов (без изображений), опционально по магазину
 */
async function getTrainingSamplesList(shopId = null) {
  const data = await loadTrainingSamples();
  let samples = data.samples || [];

  if (shopId) {
    samples = samples.filter(s => s.shopId === shopId);
  }

  // Возвращаем без rawText (экономим трафик)
  return samples.map(s => ({
    id: s.id,
    shopId: s.shopId || null,
    templateId: s.templateId || null,
    correctData: s.correctData,
    recognizedData: s.recognizedData,
    correctedFields: s.correctedFields || [],
    fieldRegions: s.fieldRegions || null,
    createdAt: s.createdAt,
  }));
}

/**
 * Удалить конкретный образец по ID
 */
async function deleteTrainingSample(sampleId) {
  const data = await loadTrainingSamples();
  const samples = data.samples || [];
  const index = samples.findIndex(s => s.id === sampleId);

  if (index === -1) return false;

  const deleted = samples.splice(index, 1)[0];

  // Удаляем изображение
  await deleteSampleImage(sampleId);

  // Сохраняем JSON
  await saveTrainingSamples({ samples });

  // Удаляем из DB
  if (USE_DB) {
    try { await db.deleteById('z_report_training_samples', sampleId); }
    catch (e) { console.error('[Z-Report] DB deleteTrainingSample error:', e.message); }
  }

  // Обновляем регионы если был привязан к магазину
  if (deleted.shopId) {
    updateLearnedRegions(deleted.shopId).catch(e =>
      console.error('[Training] Ошибка обновления регионов после удаления:', e.message)
    );
  }

  console.log(`[Training] Удалён образец ${sampleId} (магазин: ${deleted.shopId || 'не указан'})`);
  return true;
}

/**
 * Получить путь к файлу изображения образца
 */
function getTrainingSampleImagePath(sampleId) {
  return path.join(__dirname, '../data/training-images', `${sampleId}.jpg`);
}

module.exports = {
  getTemplates,
  getTemplate,
  saveTemplate,
  deleteTemplate,
  findTemplateForShop,
  updateTemplateStats,
  addTrainingSample,
  getTrainingStats,
  getLearnedPatterns,
  analyzeAndImprovePatterns,
  getLearnedRegions,
  updateLearnedRegions,
  getTrainingSamplesList,
  deleteTrainingSample,
  getTrainingSampleImagePath,
};
