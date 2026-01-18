/**
 * Z-Report Templates Module
 * Управление шаблонами распознавания Z-отчётов
 */

const fs = require('fs').promises;
const path = require('path');
const { v4: uuidv4 } = require('uuid');

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
  await fs.writeFile(TEMPLATES_FILE, JSON.stringify(data, null, 2));
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
    // Скользящее среднее для successRate
    const oldRate = template.successRate || 0;
    const weight = Math.min(template.usageCount, 100); // Макс вес 100
    template.successRate = (oldRate * (weight - 1) + (wasSuccessful ? 1 : 0)) / weight;

    await saveTemplates(data);
  }
}

// ============ Образцы для обучения ============

/**
 * Загрузить образцы
 */
async function loadTrainingSamples() {
  try {
    await ensureDataDir();
    const data = await fs.readFile(SAMPLES_FILE, 'utf-8');
    return JSON.parse(data);
  } catch (e) {
    return { samples: [] };
  }
}

/**
 * Сохранить образцы
 */
async function saveTrainingSamples(data) {
  await ensureDataDir();
  await fs.writeFile(SAMPLES_FILE, JSON.stringify(data, null, 2));
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
  templateId
}) {
  const data = await loadTrainingSamples();
  const samples = data.samples || [];

  const sample = {
    id: uuidv4(),
    createdAt: new Date().toISOString(),
    rawText,
    correctData,
    recognizedData,
    shopId,
    templateId,
    // Вычисляем какие поля были исправлены
    correctedFields: Object.keys(correctData).filter(
      key => correctData[key] !== recognizedData?.[key]
    )
  };

  samples.push(sample);

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

  await saveTrainingSamples({ samples });

  // Анализируем образцы для улучшения паттернов
  const learningResult = await analyzeAndImprovePatterns(samples);

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
  await fs.writeFile(LEARNED_PATTERNS_FILE, JSON.stringify(data, null, 2));
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
  analyzeAndImprovePatterns
};
