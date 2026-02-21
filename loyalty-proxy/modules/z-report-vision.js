/**
 * Z-Report Vision Module
 * Распознавание Z-отчётов с помощью EasyOCR + Tesseract (ранее Google Cloud Vision)
 * OCR → z-report-ocr.js, парсинг текста → здесь
 */

const { extractZReportText, extractZReportTextFromRegion } = require('./z-report-ocr');

// Кэш для выученных паттернов
let learnedPatternsCache = null;
let learnedPatternsCacheTime = 0;
const CACHE_TTL = 60000; // 1 минута

/** Инвалидировать кэш выученных паттернов (вызывается после обучения) */
function invalidateLearnedPatternsCache() {
  learnedPatternsCache = null;
  learnedPatternsCacheTime = 0;
}

/**
 * Улучшенная нормализация OCR текста
 * Исправляет типичные ошибки распознавания перед парсингом
 * @param {string} text - Исходный текст с чека
 * @returns {string} - Нормализованный текст
 */
function enhancedOcrNormalize(text) {
  let normalized = text;

  // 1. Исправляем типичные ошибки в ключевых словах (СУННА → СУММА, СУМНА → СУММА)
  normalized = normalized.replace(/СУ[МН]+[АН]А?/gi, 'СУММА');
  normalized = normalized.replace(/ИТАГО/gi, 'ИТОГО');
  normalized = normalized.replace(/ВСЕГА/gi, 'ВСЕГО');
  normalized = normalized.replace(/НАЛИЧН[ЫА]?Е?/gi, 'НАЛИЧН');
  normalized = normalized.replace(/НЕПЕРЕДАНН?Ы?Х?/gi, 'НЕПЕРЕДАННЫХ');

  // 2. Исправляем O (буква) → 0 (цифра) в контексте чисел
  // О перед цифрами: "О12345" → "012345"
  normalized = normalized.replace(/([^А-Яа-яA-Za-z])О(\d)/g, '$10$2');
  normalized = normalized.replace(/^О(\d)/gm, '0$1');
  // О после цифр: "1234О" → "12340"
  normalized = normalized.replace(/(\d)О([^А-Яа-яA-Za-z]|$)/g, '$10$2');
  // О между цифрами: "12О34" → "12034"
  normalized = normalized.replace(/(\d)О(\d)/g, '$10$2');

  // 3. Исправляем l (маленькая L) → 1 перед цифрами
  normalized = normalized.replace(/([^A-Za-zА-Яа-я])l(\d)/g, '$11$2');
  normalized = normalized.replace(/^l(\d)/gm, '1$1');

  // 4. Исправляем I (большая i) → 1 между цифрами
  normalized = normalized.replace(/(\d)I(\d)/g, '$11$2');

  // 5. Исправляем S → 5 между цифрами (только если окружено цифрами)
  normalized = normalized.replace(/(\d)S(\d)/g, '$15$2');

  // 6. Убираем случайные символы между цифрами в суммах
  // "14.0 95.00" → "14095.00" (пробел перед десятичной точкой)
  normalized = normalized.replace(/(\d+)\s+(\d{2})\.(\d{2})/g, '$1$2.$3');

  // 7. Исправляем запятую на точку в десятичных числах
  normalized = normalized.replace(/(\d),(\d{2})(?!\d)/g, '$1.$2');

  // 8. Исправляем "АН." → " AH." для ресурса ключей (унификация)
  normalized = normalized.replace(/(\d+)\s*[АA][НH]\.?/gi, '$1 AH.');

  // 9. Исправляем опечатки в "СМЕНЫ" / "СНЕНЫ"
  normalized = normalized.replace(/СНЕНЫ/gi, 'СМЕНЫ');
  normalized = normalized.replace(/СНЕНУ/gi, 'СМЕНУ');

  // 10. Убираем мусорные символы в начале строк ($ перед числами от OCR)
  normalized = normalized.replace(/^\$(\d)/gm, '$1');

  console.log('[Z-Report OCR Normalize] Применена нормализация');

  return normalized;
}

// OCR теперь через EasyOCR + Tesseract (см. z-report-ocr.js)

/**
 * Извлекает данные из Z-отчёта
 * @param {string} imageBase64 - Base64 изображения
 * @returns {Object} - Распознанные данные
 */
async function parseZReport(imageBase64, expectedRanges = null, learnedRegions = null) {
  try {
    // === Попытка 1: OCR по выученным регионам (4 отдельных кропа) ===
    if (learnedRegions && Object.keys(learnedRegions).length >= 2) {
      console.log('[Z-Report] Пробуем OCR по регионам:', Object.keys(learnedRegions).join(', '));
      const regionResult = await parseByRegions(imageBase64, learnedRegions, expectedRanges);
      if (regionResult) {
        console.log('[Z-Report] Регионы: распознано', regionResult.recognizedCount, 'из 4 полей');
        if (regionResult.recognizedCount >= 3) {
          return {
            success: true,
            rawText: regionResult.rawText,
            data: regionResult.data,
            method: 'regions',
          };
        }
        console.log('[Z-Report] Регионы: недостаточно полей, переходим к full-page OCR');
      }
    }

    // === Попытка 2: полностраничный OCR (основной путь) ===
    const ocrResult = await extractZReportText(imageBase64);

    if (!ocrResult.success || !ocrResult.text) {
      return {
        success: false,
        error: ocrResult.error || 'Текст не распознан на изображении'
      };
    }

    const fullText = ocrResult.text;
    console.log('[Z-Report] Распознанный текст (метод:', ocrResult.method, '| символов:', ocrResult.charCount, '):', fullText);

    if (expectedRanges) {
      console.log('[Z-Report] Intelligence ranges:', JSON.stringify(expectedRanges));
    }

    // Парсим нужные поля (теперь async) с intelligence ranges
    const parsed = await extractZReportData(fullText, null, expectedRanges);

    return {
      success: true,
      rawText: fullText,
      data: parsed,
      method: 'fullpage',
    };

  } catch (error) {
    console.error('[Z-Report] Ошибка распознавания:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * OCR по выученным регионам — кропаем 4 области и распознаём каждую отдельно
 * Возвращает null если не удалось
 */
async function parseByRegions(imageBase64, regions, expectedRanges) {
  const fields = ['totalSum', 'cashSum', 'ofdNotSent', 'resourceKeys'];
  const result = {
    totalSum: null,
    cashSum: null,
    ofdNotSent: null,
    resourceKeys: null,
    confidence: {},
    validationWarnings: [],
  };

  let rawTexts = [];
  let recognizedCount = 0;

  // Распознаём каждый регион параллельно
  const regionPromises = fields
    .filter(field => regions[field])
    .map(async (field) => {
      try {
        const ocrResult = await extractZReportTextFromRegion(imageBase64, regions[field]);
        if (!ocrResult.success || !ocrResult.text) return { field, text: null };
        return { field, text: ocrResult.text };
      } catch (e) {
        console.error(`[Z-Report Region] Ошибка OCR для ${field}:`, e.message);
        return { field, text: null };
      }
    });

  const regionResults = await Promise.all(regionPromises);

  for (const { field, text } of regionResults) {
    if (!text) continue;
    rawTexts.push(`[${field}]: ${text}`);

    // Извлекаем число из кропнутого текста
    const value = extractNumberFromRegionText(text, field);
    if (value !== null) {
      result[field] = value;
      result.confidence[field] = 'region';
      recognizedCount++;

      // Проверка по intelligence
      if (expectedRanges && expectedRanges[field]) {
        const range = expectedRanges[field];
        if (value >= range.min && value <= range.max) {
          result.confidence[field] = 'intelligence_confirmed';
        } else {
          result.validationWarnings.push({
            type: `${field}_outside_expected`,
            message: `${field} = ${value}, ожидалось ${range.min}–${range.max}`,
            severity: 'warning',
            expectedRange: range,
          });
        }
      }
    }
  }

  if (recognizedCount === 0) return null;

  return {
    data: result,
    rawText: rawTexts.join('\n'),
    recognizedCount,
  };
}

/**
 * Извлечь число из текста кропнутого региона
 * Регион содержит 1-3 строки текста вокруг нужного числа
 */
function extractNumberFromRegionText(text, fieldType) {
  if (!text) return null;

  const lines = text.trim().split('\n').map(l => l.trim()).filter(l => l);

  if (fieldType === 'ofdNotSent' || fieldType === 'resourceKeys') {
    // Целые числа
    for (const line of lines) {
      // Ищем целое число (возможно с суффиксом AH./дн.)
      const match = line.match(/(\d+)\s*(?:AH|АН|дн|шт)?\.?/i);
      if (match) {
        const val = parseInt(match[1]);
        if (!isNaN(val) && val >= 0 && val < 100000) return val;
      }
    }
  } else {
    // Суммы (дробные)
    for (const line of lines) {
      // Ищем число вида 14095.00 или =14095.00
      const match = line.match(/=?\s*(\d[\d\s]*\d)[.,](\d{2})(?!\d)/);
      if (match) {
        const intPart = match[1].replace(/\s/g, '');
        const val = parseFloat(intPart + '.' + match[2]);
        if (!isNaN(val) && val > 0) return val;
      }
      // Целое число (без копеек)
      const intMatch = line.match(/=?\s*(\d{3,})/);
      if (intMatch) {
        const val = parseFloat(intMatch[1]);
        if (!isNaN(val) && val > 100) return val;
      }
    }
  }

  return null;
}

/**
 * Парсит блочный формат АТОЛ
 * В чеках АТОЛ метки идут одним блоком, а значения — другим блоком
 * Но порядок одинаковый: ВСЕГО, НАЛИЧН., БЕЗНАЛИЧ.
 *
 * @param {string[]} lines - Строки текста
 * @param {number} totalSum - Уже найденная общая сумма (для поиска блока значений)
 * @returns {Object} - { cashSum, ofdNotSent }
 */
function parseAtolBlockFormat(lines, totalSum) {
  const result = { cashSum: null, ofdNotSent: null };

  // Ищем строку с totalSum (=14095.00)
  const totalStr = '=' + totalSum.toFixed(2);
  let totalLineIdx = -1;

  for (let i = 0; i < lines.length; i++) {
    if (lines[i].includes(totalStr)) {
      totalLineIdx = i;
      break;
    }
  }

  if (totalLineIdx === -1) {
    // Попробуем без знака =
    const totalStrNoEq = totalSum.toFixed(2);
    for (let i = 0; i < lines.length; i++) {
      if (lines[i].trim() === totalStrNoEq || lines[i].includes('=' + totalStrNoEq)) {
        totalLineIdx = i;
        break;
      }
    }
  }

  if (totalLineIdx === -1) {
    console.log('[Z-Report] АТОЛ: не найдена строка с totalSum');
    return result;
  }

  console.log('[Z-Report] АТОЛ: totalSum на строке', totalLineIdx, ':', lines[totalLineIdx]);

  // В формате АТОЛ следующая строка после ВСЕГО — это НАЛИЧН.
  // Проверяем, что на следующей строке есть число
  if (totalLineIdx + 1 < lines.length) {
    const nextLine = lines[totalLineIdx + 1].trim();
    // Ищем число с копейками
    const match = nextLine.match(/=?([\d\s]+[.,]\d{2})/);
    if (match) {
      const value = parseFloat(match[1].replace(/\s/g, '').replace(',', '.'));
      // Проверяем что это не то же число что totalSum
      if (value !== totalSum && value > 0 && value < totalSum) {
        result.cashSum = value;
        console.log('[Z-Report] АТОЛ: cashSum на строке', totalLineIdx + 1, ':', value);
      }
    }
  }

  return result;
}

/**
 * Загружает выученные паттерны с кэшированием
 */
async function getLearnedPatternsWithCache() {
  const now = Date.now();
  if (learnedPatternsCache && (now - learnedPatternsCacheTime) < CACHE_TTL) {
    return learnedPatternsCache;
  }

  try {
    // Ленивая загрузка модуля шаблонов
    const templatesModule = require('./z-report-templates');
    learnedPatternsCache = await templatesModule.getLearnedPatterns();
    learnedPatternsCacheTime = now;
    return learnedPatternsCache;
  } catch (e) {
    console.log('[Z-Report] Не удалось загрузить выученные паттерны:', e.message);
    return { totalSum: [], cashSum: [], ofdNotSent: [] };
  }
}

/**
 * Извлекает конкретные поля из текста Z-отчёта
 * Поддерживает АТОЛ, Штрих-М, Эвотор и другие кассы
 * ТЕПЕРЬ ИСПОЛЬЗУЕТ ВЫУЧЕННЫЕ ПАТТЕРНЫ!
 */
async function extractZReportData(originalText, learnedPatterns = null, expectedRanges = null) {
  // ============ УЛУЧШЕННАЯ НОРМАЛИЗАЦИЯ OCR ============
  // Применяем нормализацию для исправления типичных ошибок OCR
  const text = enhancedOcrNormalize(originalText);

  const lines = text.split('\n').map(l => l.trim());

  const result = {
    totalSum: null,        // Общая сумма
    cashSum: null,         // Сумма наличных
    cardSum: null,         // Сумма безналичных (вычисляется)
    ofdNotSent: null,      // Чеки не переданные в ОФД
    resourceKeys: null,    // Ресурс ключей
    confidence: {},
    validationWarnings: [] // Предупреждения перекрёстной валидации
  };

  // Загружаем выученные паттерны если не переданы
  if (!learnedPatterns) {
    learnedPatterns = await getLearnedPatternsWithCache();
  }

  // Нормализуем текст для лучшего поиска (дополнительно к OCR нормализации)
  // Используем normalizedText вместо text для паттерн-матчинга
  text = text
    .replace(/\s+/g, ' ')
    .replace(/[—–-]/g, '-');

  // ============ ОБЩАЯ СУММА / ВЫРУЧКА ============

  // Сначала пробуем выученные паттерны (отсортированы по weight — лучшие первыми)
  if (learnedPatterns.totalSum && learnedPatterns.totalSum.length > 0) {
    const sortedTotalSum = [...learnedPatterns.totalSum].sort((a, b) => (b.weight || 0.5) - (a.weight || 0.5));
    for (const learned of sortedTotalSum) {
      try {
        const regex = new RegExp(learned.pattern + '[^\\d]*(\\d[\\d\\s]*[.,]\\d{2})', 'i');
        const match = text.match(regex);
        if (match) {
          let value = match[1].replace(/\s/g, '').replace(',', '.');
          result.totalSum = parseFloat(value);
          result.confidence.totalSum = 'learned';
          console.log('[Z-Report] Найдена общая сумма (выученный паттерн):', result.totalSum);
          break;
        }
      } catch (e) {
        // Некорректный regex, пропускаем
      }
    }
  }

  // Если не нашли выученными — используем базовые паттерны
  if (result.totalSum === null) {
    const totalPatterns = [
      // АТОЛ: СУММА ПРИХ. ВСЕГО (приоритетный паттерн)
      /СУММ?А?\s*ПРИХ\.?\s*ВСЕГО[^=\d]*=?\s*([\d\s]+[.,]\d{2})/i,
      // АТОЛ: =14095.00 после ИТОГО
      /ИТОГО[^=]*=\s*([\d\s]+[.,]\d{2})/i,
      // Стандарт: ВЫРУЧКА: 14095.00
      /(?:ВЫРУЧКА|ИТОГО|ВСЕГО)[:\s]*=?\s*([\d\s]+[.,]\d{2})/i,
      // СУММА ПРИХ. (без ВСЕГО и НАЛИЧН)
      /СУММ?А?\s*ПРИХ\.?(?!\s*НАЛИЧН)[^=]*=\s*([\d\s]+[.,]\d{2})/i,
      // Просто ИТОГО без символа =
      /ИТОГО[:\s]+([\d\s]+[.,]\d{2})/i
    ];

    for (const pattern of totalPatterns) {
      const match = text.match(pattern);
      if (match) {
        let value = match[1].replace(/\s/g, '').replace(',', '.');
        result.totalSum = parseFloat(value);
        result.confidence.totalSum = 'high';
        console.log('[Z-Report] Найдена общая сумма:', result.totalSum);
        break;
      }
    }
  }

  // ============ НАЛИЧНЫЕ ============

  // Сначала пробуем выученные паттерны (отсортированы по weight)
  if (learnedPatterns.cashSum && learnedPatterns.cashSum.length > 0) {
    const sortedCashSum = [...learnedPatterns.cashSum].sort((a, b) => (b.weight || 0.5) - (a.weight || 0.5));
    for (const learned of sortedCashSum) {
      try {
        const regex = new RegExp(learned.pattern + '[^\\d]*(\\d[\\d\\s]*[.,]\\d{2})', 'i');
        const match = text.match(regex);
        if (match) {
          let value = match[1].replace(/\s/g, '').replace(',', '.');
          result.cashSum = parseFloat(value);
          result.confidence.cashSum = 'learned';
          console.log('[Z-Report] Найдены наличные (выученный паттерн):', result.cashSum);
          break;
        }
      } catch (e) {
        // Некорректный regex, пропускаем
      }
    }
  }

  // Если не нашли выученными — используем базовые паттерны
  if (result.cashSum === null) {
    const cashPatterns = [
      // АТОЛ на одной строке: СУММА ПРИХ. НАЛИЧН. =7890.00
      /СУМ[МНА]+\s*ПРИХ\.?\s*НАЛИЧН\.?\s*=\s*([\d\s]+[.,]\d{2})/i,
      // НАЛИЧН. = 7890.00 (на одной строке, макс 20 символов между)
      /НАЛИЧН\.?\s*[=:]\s*([\d\s]+[.,]\d{2})/i,
      // Стандарт: НАЛИЧНЫМИ: 7890.00
      /(?:НАЛИЧНЫМИ|НАЛИЧНЫЕ)[:\s]*=?\s*([\d\s]+[.,]\d{2})/i,
      // НАЛ. / НАЛ:
      /(?:НАЛ\.?|НАЛ:)[:\s]*=?\s*([\d\s]+[.,]\d{2})/i
    ];

    for (const pattern of cashPatterns) {
      const match = text.match(pattern);
      if (match) {
        let value = match[1].replace(/\s/g, '').replace(',', '.');
        const parsedValue = parseFloat(value);
        // Проверяем что это не totalSum (частая ошибка)
        if (parsedValue !== result.totalSum) {
          result.cashSum = parsedValue;
          result.confidence.cashSum = 'high';
          console.log('[Z-Report] Найдены наличные:', result.cashSum);
          break;
        }
      }
    }
  }

  // ============ БЛОЧНЫЙ АЛГОРИТМ ДЛЯ АТОЛ ============
  // Если не нашли наличные обычными паттернами — пробуем блочный алгоритм
  // В чеках АТОЛ метки и значения в разных блоках, но в одинаковом порядке
  if (result.cashSum === null && result.totalSum !== null) {
    const atolBlockResult = parseAtolBlockFormat(lines, result.totalSum);
    if (atolBlockResult.cashSum !== null) {
      result.cashSum = atolBlockResult.cashSum;
      result.confidence.cashSum = 'atol_block';
      console.log('[Z-Report] Найдены наличные (блочный АТОЛ):', result.cashSum);
    }
  }

  // ============ НЕ ПЕРЕДАНЫ В ОФД ============

  // Сначала пробуем выученные паттерны (отсортированы по weight)
  if (learnedPatterns.ofdNotSent && learnedPatterns.ofdNotSent.length > 0) {
    const sortedOfdNotSent = [...learnedPatterns.ofdNotSent].sort((a, b) => (b.weight || 0.5) - (a.weight || 0.5));
    for (const learned of sortedOfdNotSent) {
      try {
        const regex = new RegExp(learned.pattern + '[^\\d]*(\\d+)', 'i');
        const match = text.match(regex);
        if (match) {
          result.ofdNotSent = parseInt(match[1], 10);
          result.confidence.ofdNotSent = 'learned';
          console.log('[Z-Report] Найдено не передано в ОФД (выученный паттерн):', result.ofdNotSent);
          break;
        }
      } catch (e) {
        // Некорректный regex, пропускаем
      }
    }
  }

  // Если не нашли выученными — используем базовые паттерны
  if (result.ofdNotSent === null) {
    const ofdPatterns = [
      // АТОЛ: НЕПЕРЕДАННЫХ ФД: 0 (число на той же строке)
      /НЕПЕРЕДАННЫХ\s*ФД[:\s]*(\d+)/i,
      // АТОЛ: НЕПЕРЕДАННЫХ ФА: 0
      /НЕПЕРЕДАННЫХ\s*ФА[:\s]*(\d+)/i,
      // Общий паттерн НЕПЕРЕДАННЫХ Ф* : число (на одной строке)
      /НЕПЕРЕДАНН?Ы?Х?\s*Ф[АД]?\s*[:\s]+(\d+)/i,
      // НЕ ПЕРЕДАНО В ОФД: 0
      /НЕ\s*ПЕРЕДАН[ОЫ]?\s*(?:В\s*)?ОФД[:\s]*(\d+)/i,
      // ДОКУМЕНТОВ НЕ ОТПРАВЛЕНО: 0
      /ДОКУМЕНТ.{0,20}НЕ\s*(?:ОТПРАВЛЕН|ПЕРЕДАН).{0,10}(\d+)/i,
    ];

    for (const pattern of ofdPatterns) {
      const match = text.match(pattern);
      if (match) {
        result.ofdNotSent = parseInt(match[1], 10);
        result.confidence.ofdNotSent = 'high';
        console.log('[Z-Report] Найдено не передано в ОФД:', result.ofdNotSent);
        break;
      }
    }
  }

  // ============ ПРЯМОЙ ПОИСК ДЛЯ АТОЛ (приоритетный) ============
  // Формат: метки идут подряд, затем значения идут подряд
  // ЧЕКОВ ЗА СМЕНУ: / ОД ЗА СМЕНУ: / РЕСУРС КЛЮЧЕЙ: / НЕПЕРЕДАННЫХ ОД
  // 100 / 102 / 277 AH. / 0
  if (result.ofdNotSent === null) {
    let ofdLabelIdx = -1;
    let firstValueAfterLabels = -1;

    for (let i = 0; i < lines.length; i++) {
      const upper = lines[i].toUpperCase();
      // Ищем НЕПЕРЕДАННЫХ ФА/ФД/ОД (последняя метка блока)
      if (upper.includes('НЕПЕРЕДАНН') && (upper.includes('ФД') || upper.includes('ФА') || upper.includes('ОД'))) {
        ofdLabelIdx = i;
        // Ищем первое значение сразу после метки НЕПЕРЕДАННЫХ
        for (let j = i + 1; j < Math.min(i + 6, lines.length); j++) {
          let valueLine = lines[j].trim();
          // Пропускаем строки с AH. (это ресурс ключей)
          if (valueLine.match(/\d+\s*[AА][HН]\.?/i)) {
            continue;
          }
          // Ищем простое число (0-9999)
          if (valueLine === 'O' || valueLine === 'o') valueLine = '0';
          const numMatch = valueLine.match(/^(\d{1,4})$/);
          if (numMatch) {
            const num = parseInt(numMatch[1], 10);
            if (num <= 10000) {
              result.ofdNotSent = num;
              result.confidence.ofdNotSent = 'atol_direct';
              console.log('[Z-Report] НЕПЕРЕДАННЫХ найдено напрямую после метки (строка', j, '):', num);
              break;
            }
          }
        }
        break;
      }
    }
  }

  // ============ БЛОЧНЫЙ АЛГОРИТМ ДЛЯ OFD (АТОЛ) — fallback ============
  // Два формата чеков АТОЛ:
  // 1. Значения после "СЧЕТЧИКИ ИТОГОВ ФН/ОН" (формат 1)
  // 2. Значения сразу после "СЧЕТЧИКИ ИТОГОВ СМЕНЫ" (формат 2)
  if (result.ofdNotSent === null) {
    let ofdLabelIdx = -1;
    let firstLabelIdx = -1;

    for (let i = 0; i < lines.length; i++) {
      const upper = lines[i].toUpperCase();
      // Ищем первую метку блока (ЧЕКОВ ЗА СМЕНУ, может быть опечатка СНЕНУ)
      if (firstLabelIdx === -1 && (upper.includes('ЧЕКОВ ЗА СМЕНУ') || upper.includes('ЧЕКОВ ЗА СНЕНУ'))) {
        firstLabelIdx = i;
      }
      // Ищем НЕПЕРЕДАННЫХ ФА/ФД/ОД (разные форматы АТОЛ)
      if (upper.includes('НЕПЕРЕДАНН') && (upper.includes('ФД') || upper.includes('ФА') || upper.includes('ОД'))) {
        ofdLabelIdx = i;
        break;
      }
    }

    if (ofdLabelIdx !== -1 && firstLabelIdx !== -1) {
      const ofdOffset = ofdLabelIdx - firstLabelIdx;
      console.log('[Z-Report] OFD блок: firstLabel=' + firstLabelIdx + ', ofdLabel=' + ofdLabelIdx + ', offset=' + ofdOffset);

      let valuesStartIdx = -1;
      let valuesSearchStart = ofdLabelIdx + 1;
      let format1Idx = -1;
      let format2Idx = -1;

      // Ищем оба формата и выбираем ближайший к метке НЕПЕРЕДАННЫХ
      // Формат 2 (СМЕНЫ) обычно близко к метке, формат 1 (ФН/ОН) может быть дальше
      for (let i = valuesSearchStart; i < Math.min(valuesSearchStart + 20, lines.length); i++) {
        const upper = lines[i].toUpperCase();

        // Формат 2: СЧЕТЧИКИ ИТОГОВ СМЕНЫ (сразу после НЕПЕРЕДАННЫХ, приоритетный)
        if (format2Idx === -1 && upper.includes('СЧЕТЧИКИ ИТОГОВ') && (upper.includes('СМЕНЫ') || upper.includes('СНЕНЫ'))) {
          for (let j = i + 1; j < Math.min(i + 10, lines.length); j++) {
            const line = lines[j].trim();
            if (line.match(/^\d+$/) || line === 'O' || line === 'o') {
              format2Idx = j;
              break;
            }
          }
        }

        // Формат 1: СЧЕТЧИКИ ИТОГОВ ФН/ОН (только если близко, в пределах 15 строк)
        if (format1Idx === -1 && i < valuesSearchStart + 15 && (upper.includes('СЧЕТЧИКИ ИТОГОВ ФН') || upper.includes('СЧЕТЧИКИ ИТОГОВ ОН'))) {
          for (let j = i + 1; j < Math.min(i + 5, lines.length); j++) {
            if (lines[j].trim().match(/^\d+$/)) {
              format1Idx = j;
              break;
            }
          }
        }
      }

      // Выбираем ближайший к метке (формат 2 приоритетнее если оба найдены близко)
      if (format2Idx !== -1 && (format1Idx === -1 || format2Idx < format1Idx)) {
        valuesStartIdx = format2Idx;
        console.log('[Z-Report] OFD блок формат 2 (СМЕНЫ): valuesStart=' + valuesStartIdx);
      } else if (format1Idx !== -1) {
        valuesStartIdx = format1Idx;
        console.log('[Z-Report] OFD блок формат 1 (ФН/ОН): valuesStart=' + valuesStartIdx);
      }

      if (valuesStartIdx !== -1) {
        const ofdValueIdx = valuesStartIdx + ofdOffset;
        if (ofdValueIdx < lines.length) {
          let valueLine = lines[ofdValueIdx].trim();
          console.log('[Z-Report] OFD блок: checking line ' + ofdValueIdx + ': "' + valueLine + '"');

          // OCR может распознать 0 как O
          if (valueLine === 'O' || valueLine === 'o') {
            valueLine = '0';
          }

          const match = valueLine.match(/^(\d+)/);
          if (match) {
            const num = parseInt(match[1], 10);
            if (num <= 100000) {
              result.ofdNotSent = num;
              result.confidence.ofdNotSent = 'atol_block';
              console.log('[Z-Report] Найдено не передано в ОФД (блочный АТОЛ строка', ofdValueIdx, '):', result.ofdNotSent);
            }
          }
        }
      }
    }
  }

  // ============ FALLBACK: Поиск числа рядом с НЕПЕРЕДАННЫХ ============
  // Если блочный алгоритм не сработал, ищем число ПЕРЕД меткой НЕПЕРЕДАННЫХ
  // В некоторых чеках формат: значения идут ДО метки (строки 16-19: 141, 143, 37 AH., $928, затем строка 22: НЕПЕРЕДАННЫХ)
  if (result.ofdNotSent === null) {
    for (let i = 0; i < lines.length; i++) {
      const upper = lines[i].toUpperCase();
      if (upper.includes('НЕПЕРЕДАНН') && (upper.includes('ФД') || upper.includes('ФА') || upper.includes('ОД'))) {
        // Ищем число в пределах 5 строк ПЕРЕД меткой (в обратном порядке от метки)
        for (let j = i - 1; j >= Math.max(0, i - 5); j--) {
          let line = lines[j].trim();
          // OCR может распознать 0 как O или добавить $ перед числом
          if (line === 'O' || line === 'o') line = '0';
          line = line.replace(/^\$/, ''); // Убираем $ в начале
          // Ищем чистое число (не сумму с копейками, не дату)
          if (line.match(/^(\d{1,5})$/)) {
            const num = parseInt(line, 10);
            if (num <= 10000) {
              result.ofdNotSent = num;
              result.confidence.ofdNotSent = 'fallback_before';
              console.log('[Z-Report] Найдено не передано в ОФД (fallback перед меткой, строка', j, '):', result.ofdNotSent);
              break;
            }
          }
        }
        break;
      }
    }
  }

  // ============ FALLBACK 2: Последнее число перед СЧЕТЧИКИ ИТОГОВ после НЕПЕРЕДАННЫХ ============
  // В некоторых чеках значения идут между НЕПЕРЕДАННЫХ и СЧЕТЧИКИ ИТОГОВ СМЕНЫ
  // Ищем последнее чистое число перед СЧЕТЧИКИ
  if (result.ofdNotSent === null) {
    let ofdLabelLine = -1;
    let schetLine = -1;

    for (let i = 0; i < lines.length; i++) {
      const upper = lines[i].toUpperCase();
      if (ofdLabelLine === -1 && upper.includes('НЕПЕРЕДАНН') && (upper.includes('ФД') || upper.includes('ФА') || upper.includes('ОД'))) {
        ofdLabelLine = i;
      }
      if (ofdLabelLine !== -1 && schetLine === -1 && upper.includes('СЧЕТЧИКИ ИТОГОВ')) {
        schetLine = i;
        break;
      }
    }

    if (ofdLabelLine !== -1 && schetLine !== -1 && schetLine > ofdLabelLine) {
      // Ищем последнее чистое число между НЕПЕРЕДАННЫХ и СЧЕТЧИКИ (в обратном порядке)
      for (let j = schetLine - 1; j > ofdLabelLine; j--) {
        let line = lines[j].trim();
        if (line === 'O' || line === 'o') line = '0';
        if (line.match(/^(\d{1,4})$/)) {
          const num = parseInt(line, 10);
          if (num <= 10000) {
            result.ofdNotSent = num;
            result.confidence.ofdNotSent = 'fallback_between';
            console.log('[Z-Report] Найдено не передано в ОФД (fallback между меткой и СЧЕТЧИКИ, строка', j, '):', result.ofdNotSent);
            break;
          }
        }
      }
    }
  }

  // ============ РЕСУРС КЛЮЧЕЙ ============

  // Сначала пробуем выученные паттерны (отсортированы по weight)
  if (learnedPatterns.resourceKeys && learnedPatterns.resourceKeys.length > 0) {
    const sortedResourceKeys = [...learnedPatterns.resourceKeys].sort((a, b) => (b.weight || 0.5) - (a.weight || 0.5));
    for (const learned of sortedResourceKeys) {
      try {
        const regex = new RegExp(learned.pattern + '[^\\d]*(\\d+)', 'i');
        const match = text.match(regex);
        if (match) {
          result.resourceKeys = parseInt(match[1], 10);
          result.confidence.resourceKeys = 'learned';
          console.log('[Z-Report] Найден ресурс ключей (выученный паттерн):', result.resourceKeys);
          break;
        }
      } catch (e) {
        // Некорректный regex, пропускаем
      }
    }
  }

  // Если не нашли выученными — используем базовые паттерны
  if (result.resourceKeys === null) {
    const resourceKeysPatterns = [
      // АТОЛ формат: "РЕСУРС КЛЮЧЕЙ:" в блоке меток, значение "277 AH." ниже
      // Ищем строку с числом и "AH." или "АН." (кириллица/латиница)
      /(\d+)\s*[AА][HН]\.?/i,
      // Типичные форматы для ресурса ключей
      /РЕСУРС\s*КЛЮЧ[ЕА-Я]*[:\s]*(\d+)/i,
      /РЕСУРС\s*КЛ\.?[:\s]*(\d+)/i,
      /РЕС\.?\s*КЛЮЧ[ЕА-Я]*[:\s]*(\d+)/i,
      // Ресурс ключа ФН
      /РЕСУРС\s*КЛЮЧА?\s*ФН[:\s]*(\d+)/i,
      // Просто "КЛЮЧЕЙ:" или "КЛЮЧИ:"
      /КЛЮЧ[ЕИ][ЙЯ]?[:\s]+(\d+)/i,
    ];

    for (const pattern of resourceKeysPatterns) {
      const match = text.match(pattern);
      if (match) {
        const value = parseInt(match[1], 10);
        // Валидация: ресурс ключей от 1 до 2000 (разные модели ФН)
        if (value > 0 && value <= 2000) {
          result.resourceKeys = value;
          result.confidence.resourceKeys = 'high';
          console.log('[Z-Report] Найден ресурс ключей:', result.resourceKeys);
          break;
        }
      }
    }
  }

  // ============ ПЕРЕКРЁСТНАЯ ВАЛИДАЦИЯ РЕЗУЛЬТАТОВ ============

  // 1. Вычисляем cardSum (безналичные) если есть totalSum и cashSum
  if (result.totalSum !== null && result.cashSum !== null) {
    result.cardSum = Math.max(0, result.totalSum - result.cashSum);
    result.confidence.cardSum = 'calculated';
    console.log('[Z-Report] Вычислены безналичные (cardSum):', result.cardSum);
  }

  // 2. Проверка: cashSum не может быть больше totalSum
  if (result.totalSum !== null && result.cashSum !== null) {
    if (result.cashSum > result.totalSum) {
      console.log('[Z-Report] ВАЛИДАЦИЯ: cashSum > totalSum - возможна ошибка OCR');
      result.confidence.cashSum = 'suspicious';
      result.validationWarnings.push({
        type: 'cashSum_exceeds_total',
        message: `Наличные (${result.cashSum}) больше общей суммы (${result.totalSum})`,
        severity: 'warning'
      });
    }
  }

  // 3. Проверка разумности выручки (типичный диапазон для кофейни: 1000-500000 руб)
  if (result.totalSum !== null) {
    if (result.totalSum < 100) {
      console.log('[Z-Report] ВАЛИДАЦИЯ: totalSum подозрительно мал:', result.totalSum);
      result.validationWarnings.push({
        type: 'totalSum_too_low',
        message: `Выручка подозрительно мала: ${result.totalSum} руб`,
        severity: 'info'
      });
    }
    if (result.totalSum > 500000) {
      console.log('[Z-Report] ВАЛИДАЦИЯ: totalSum подозрительно велик:', result.totalSum);
      result.validationWarnings.push({
        type: 'totalSum_too_high',
        message: `Выручка подозрительно велика: ${result.totalSum} руб`,
        severity: 'warning'
      });
      result.confidence.totalSum = 'suspicious';
    }
  }

  // 4. Проверка cashSum не может быть отрицательным
  if (result.cashSum !== null && result.cashSum < 0) {
    console.log('[Z-Report] ВАЛИДАЦИЯ: cashSum отрицательный - ошибка OCR');
    result.cashSum = null;
    result.confidence.cashSum = 'invalid';
  }

  // 5. Проверка соотношения наличные/безналичные (обычно наличные 10-90% от выручки)
  if (result.totalSum !== null && result.cashSum !== null && result.totalSum > 0) {
    const cashPercent = (result.cashSum / result.totalSum) * 100;
    if (cashPercent > 95) {
      console.log('[Z-Report] ВАЛИДАЦИЯ: доля наличных необычно высока:', cashPercent.toFixed(1) + '%');
      result.validationWarnings.push({
        type: 'cash_ratio_high',
        message: `Доля наличных необычно высока: ${cashPercent.toFixed(1)}%`,
        severity: 'info'
      });
    }
  }

  // 6. ofdNotSent не может быть слишком большим (обычно 0-1000)
  if (result.ofdNotSent !== null) {
    if (result.ofdNotSent > 10000) {
      console.log('[Z-Report] ВАЛИДАЦИЯ: ofdNotSent слишком большой:', result.ofdNotSent);
      result.ofdNotSent = null;
      result.confidence.ofdNotSent = 'invalid';
      result.validationWarnings.push({
        type: 'ofd_invalid',
        message: 'Значение "не передано в ОФД" недопустимо велико',
        severity: 'error'
      });
    } else if (result.ofdNotSent > 100) {
      console.log('[Z-Report] ВАЛИДАЦИЯ: ofdNotSent подозрительно велик:', result.ofdNotSent);
      result.validationWarnings.push({
        type: 'ofd_high',
        message: `Много чеков не передано в ОФД: ${result.ofdNotSent}`,
        severity: 'warning'
      });
    }
  }

  // 7. Проверка ресурса ключей (обычно 1-500)
  if (result.resourceKeys !== null) {
    if (result.resourceKeys < 10) {
      console.log('[Z-Report] ВАЛИДАЦИЯ: resourceKeys критически низкий:', result.resourceKeys);
      result.validationWarnings.push({
        type: 'resource_keys_low',
        message: `Ресурс ключей критически низкий: ${result.resourceKeys}`,
        severity: 'warning'
      });
    }
  }

  // 8. Intelligence-валидация: проверяем значения по ожидаемым диапазонам
  if (expectedRanges) {
    for (const field of ['totalSum', 'cashSum', 'ofdNotSent', 'resourceKeys']) {
      const range = expectedRanges[field];
      if (!range || result[field] === null) continue;

      if (result[field] >= range.min && result[field] <= range.max) {
        // Значение в ожидаемом диапазоне — подтверждаем confidence
        if (result.confidence[field] !== 'not_found' && result.confidence[field] !== 'invalid') {
          result.confidence[field] = 'intelligence_confirmed';
          console.log(`[Z-Report] Intelligence: ${field} = ${result[field]} в ожидаемом диапазоне [${range.min}, ${range.max}]`);
        }
      } else {
        // Вне диапазона — предупреждение
        console.log(`[Z-Report] Intelligence: ${field} = ${result[field]} ВНЕ диапазона [${range.min}, ${range.max}]`);
        result.validationWarnings.push({
          type: `${field}_outside_expected`,
          message: `${field} = ${result[field]}, ожидалось ${range.min}–${range.max}`,
          severity: 'warning',
          expectedRange: range,
        });
      }
    }
  }

  // 9. Помечаем не найденные поля
  if (result.totalSum === null) result.confidence.totalSum = 'not_found';
  if (result.cashSum === null) result.confidence.cashSum = 'not_found';
  if (result.ofdNotSent === null) result.confidence.ofdNotSent = 'not_found';
  if (result.resourceKeys === null) result.confidence.resourceKeys = 'not_found';

  // Логируем итоговые предупреждения
  if (result.validationWarnings.length > 0) {
    console.log('[Z-Report] Всего предупреждений валидации:', result.validationWarnings.length);
  }

  return result;
}

/**
 * Распознаёт текст в указанной области изображения
 * @param {string} imageBase64 - Base64 изображения
 * @param {Object} region - Область {x, y, width, height} в относительных координатах (0-1)
 * @returns {string} - Распознанный текст
 */
async function parseRegion(imageBase64, region) {
  try {
    const base64Data = imageBase64.replace(/^data:image\/\w+;base64,/, '');
    const imageBuffer = Buffer.from(base64Data, 'base64');

    // Используем sharp для обрезки изображения
    const sharp = require('sharp');
    const metadata = await sharp(imageBuffer).metadata();

    // Преобразуем относительные координаты в абсолютные
    const left = Math.floor(region.x * metadata.width);
    const top = Math.floor(region.y * metadata.height);
    const width = Math.floor(region.width * metadata.width);
    const height = Math.floor(region.height * metadata.height);

    // Обрезаем изображение
    const croppedBuffer = await sharp(imageBuffer)
      .extract({ left, top, width, height })
      .toBuffer();

    // Распознаём текст в области через EasyOCR
    const ocrResult = await extractZReportText(croppedBuffer.toString('base64'));
    if (!ocrResult.success || !ocrResult.text) {
      return null;
    }

    return ocrResult.text.trim();
  } catch (error) {
    console.error('[Z-Report] Ошибка распознавания области:', error);
    return null;
  }
}

/**
 * Пробует распознать с одним набором областей
 * @param {string} imageBase64 - Base64 изображения
 * @param {Array} regions - Список областей
 * @returns {Object} - Результат распознавания
 */
async function tryRegionSet(imageBase64, regions) {
  const result = {
    totalSum: null,
    cashSum: null,
    ofdNotSent: null,
    resourceKeys: null,
    confidence: {},
    foundCount: 0
  };

  for (const region of regions) {
    const text = await parseRegion(imageBase64, region);
    console.log(`[Z-Report] Область ${region.fieldName}:`, text);

    if (text) {
      const value = extractValueFromText(text, region.fieldName);

      if (value !== null) {
        result[region.fieldName] = value;
        result.confidence[region.fieldName] = 'high';
        result.foundCount++;
        console.log(`[Z-Report] Найдено ${region.fieldName}:`, value);
      }
    }
  }

  return result;
}

/**
 * Распознаёт Z-отчёт используя шаблон с областями
 * Поддерживает несколько наборов областей (regionSets)
 * @param {string} imageBase64 - Base64 изображения
 * @param {Object} template - Шаблон с областями
 * @returns {Object} - Распознанные данные
 */
async function parseZReportWithTemplate(imageBase64, template) {
  try {
    console.log('[Z-Report] Распознавание с шаблоном:', template.name);

    // ВАЖНО: Сначала делаем полное OCR для получения rawText (нужен для обучения!)
    let rawText = '';
    try {
      const ocrResult = await extractZReportText(imageBase64);
      if (ocrResult.success && ocrResult.text) {
        rawText = ocrResult.text;
        console.log('[Z-Report] Получен rawText для обучения, длина:', rawText.length, '| метод:', ocrResult.method);
      }
    } catch (e) {
      console.log('[Z-Report] Не удалось получить rawText:', e.message);
    }

    // Поддержка старого формата (regions) и нового (regionSets)
    let regionSets = [];

    if (template.regionSets && template.regionSets.length > 0) {
      // Новый формат — несколько наборов
      regionSets = template.regionSets;
      console.log(`[Z-Report] Найдено ${regionSets.length} наборов областей`);
    } else if (template.regions && template.regions.length > 0) {
      // Старый формат — один набор
      regionSets = [{ name: 'Формат 1', regions: template.regions }];
    }

    let bestResult = null;
    let bestFoundCount = 0;

    // Пробуем каждый набор областей
    for (const regionSet of regionSets) {
      console.log(`[Z-Report] Пробуем набор: ${regionSet.name || 'без имени'}`);

      const result = await tryRegionSet(imageBase64, regionSet.regions);

      // Если нашли все основные поля — сразу возвращаем
      if (result.totalSum !== null && result.cashSum !== null && result.ofdNotSent !== null) {
        console.log(`[Z-Report] Набор "${regionSet.name}" — найдены все основные поля!`);
        return {
          success: true,
          rawText, // Возвращаем rawText для обучения
          data: {
            totalSum: result.totalSum,
            cashSum: result.cashSum,
            ofdNotSent: result.ofdNotSent,
            resourceKeys: result.resourceKeys,
            confidence: result.confidence
          }
        };
      }

      // Запоминаем лучший результат
      if (result.foundCount > bestFoundCount) {
        bestFoundCount = result.foundCount;
        bestResult = result;
      }
    }

    // Используем лучший результат из наборов
    const result = bestResult || {
      totalSum: null,
      cashSum: null,
      ofdNotSent: null,
      resourceKeys: null,
      confidence: {}
    };

    // Для не найденных полей пробуем обычное распознавание по полному тексту
    if (result.totalSum === null || result.cashSum === null || result.ofdNotSent === null) {
      console.log('[Z-Report] Некоторые поля не найдены по областям, пробуем распознавание по тексту...');

      if (rawText) {
        // Используем уже полученный текст
        const parsedData = await extractZReportData(rawText);

        if (result.totalSum === null && parsedData.totalSum !== null) {
          result.totalSum = parsedData.totalSum;
          result.confidence.totalSum = 'medium';
        }
        if (result.cashSum === null && parsedData.cashSum !== null) {
          result.cashSum = parsedData.cashSum;
          result.confidence.cashSum = 'medium';
        }
        if (result.ofdNotSent === null && parsedData.ofdNotSent !== null) {
          result.ofdNotSent = parsedData.ofdNotSent;
          result.confidence.ofdNotSent = 'medium';
        }
        if (result.resourceKeys === null && parsedData.resourceKeys !== null) {
          result.resourceKeys = parsedData.resourceKeys;
          result.confidence.resourceKeys = 'medium';
        }
      }
    }

    // Помечаем не найденные поля
    if (result.totalSum === null) result.confidence.totalSum = 'not_found';
    if (result.cashSum === null) result.confidence.cashSum = 'not_found';
    if (result.ofdNotSent === null) result.confidence.ofdNotSent = 'not_found';
    if (result.resourceKeys === null) result.confidence.resourceKeys = 'not_found';

    return {
      success: true,
      rawText, // Возвращаем rawText для обучения
      data: {
        totalSum: result.totalSum,
        cashSum: result.cashSum,
        ofdNotSent: result.ofdNotSent,
        resourceKeys: result.resourceKeys,
        confidence: result.confidence
      }
    };

  } catch (error) {
    console.error('[Z-Report] Ошибка распознавания с шаблоном:', error);
    return {
      success: false,
      error: error.message
    };
  }
}

/**
 * Извлекает числовое значение из текста для конкретного поля
 * Улучшенная версия - применяет паттерны из extractZReportData к тексту области
 */
function extractValueFromText(text, fieldName) {
  if (!text || text.trim().length === 0) return null;

  console.log(`[Z-Report] extractValueFromText для ${fieldName}:`, text.substring(0, 100));

  // Сначала пробуем извлечь используя контекстные паттерны (как в полном тексте)
  if (fieldName === 'totalSum') {
    // Паттерны для общей суммы
    const patterns = [
      /СУММ?[АН]?\s*ПРИХ\.?\s*ВСЕГО[^=\d]*=?\s*([\d\s]+[.,]\d{2})/i,
      /ВСЕГО[^=\d]*=?\s*([\d\s]+[.,]\d{2})/i,
      /ИТОГО[^=\d]*=?\s*([\d\s]+[.,]\d{2})/i,
      /=\s*([\d\s]+[.,]\d{2})/,  // Просто =число
    ];
    for (const pattern of patterns) {
      const match = text.match(pattern);
      if (match) {
        const value = match[1].replace(/\s/g, '').replace(',', '.');
        const num = parseFloat(value);
        if (!isNaN(num) && num > 0) {
          console.log(`[Z-Report] totalSum найдено по паттерну:`, num);
          return num;
        }
      }
    }
  }

  if (fieldName === 'cashSum') {
    // Паттерны для наличных
    const patterns = [
      /СУММ?[АН]?\s*ПРИХ\.?\s*НАЛИЧН[^=\d]*=?\s*([\d\s]+[.,]\d{2})/i,
      /НАЛИЧН[^=\d]*=?\s*([\d\s]+[.,]\d{2})/i,
      /НАЛИЧНЫМИ[^=\d]*=?\s*([\d\s]+[.,]\d{2})/i,
      /=\s*([\d\s]+[.,]\d{2})/,  // Просто =число
    ];
    for (const pattern of patterns) {
      const match = text.match(pattern);
      if (match) {
        const value = match[1].replace(/\s/g, '').replace(',', '.');
        const num = parseFloat(value);
        if (!isNaN(num) && num > 0) {
          console.log(`[Z-Report] cashSum найдено по паттерну:`, num);
          return num;
        }
      }
    }
  }

  if (fieldName === 'ofdNotSent') {
    // Паттерны для ОФД - ищем число после ключевых слов
    const patterns = [
      /НЕПЕРЕДАНН?Ы?Х?\s*Ф[АД]?[:\s]*(\d+)/i,
      /НЕ\s*ПЕРЕДАН[^\d]*(\d+)/i,
      // Если просто строка с числом после двоеточия
      /:\s*(\d+)\s*$/,
    ];
    for (const pattern of patterns) {
      const match = text.match(pattern);
      if (match) {
        const num = parseInt(match[1], 10);
        if (!isNaN(num)) {
          console.log(`[Z-Report] ofdNotSent найдено по паттерну:`, num);
          return num;
        }
      }
    }
  }

  if (fieldName === 'resourceKeys') {
    // Паттерны для ресурса ключей
    const patterns = [
      /РЕСУРС\s*КЛЮЧ[ЕА-Я]*[:\s]*(\d+)/i,
      /РЕСУРС\s*КЛ\.?[:\s]*(\d+)/i,
      /КЛЮЧ[ЕИ][ЙЯ]?[:\s]+(\d+)/i,
      // Если просто строка с числом после двоеточия
      /:\s*(\d+)\s*$/,
    ];
    for (const pattern of patterns) {
      const match = text.match(pattern);
      if (match) {
        const num = parseInt(match[1], 10);
        if (!isNaN(num)) {
          console.log(`[Z-Report] resourceKeys найдено по паттерну:`, num);
          return num;
        }
      }
    }
  }

  // Fallback: просто ищем числа в тексте
  const cleanText = text.replace(/[^\d.,\s=-]/g, ' ').trim();

  if (fieldName === 'ofdNotSent' || fieldName === 'resourceKeys') {
    // Для ОФД и ресурса ключей - ищем небольшое целое число
    const numbers = cleanText.match(/\b(\d{1,5})\b/g);
    if (numbers) {
      // Берём последнее число (скорее всего это нужное значение)
      for (let i = numbers.length - 1; i >= 0; i--) {
        const num = parseInt(numbers[i], 10);
        // ОФД обычно 0-1000, ресурс ключей может быть больше (до 99999)
        const maxValue = fieldName === 'ofdNotSent' ? 1000 : 99999;
        if (num <= maxValue) {
          console.log(`[Z-Report] ${fieldName} fallback:`, num);
          return num;
        }
      }
    }
    return null; // Не угадываем значение — пусть пользователь введёт
  } else {
    // Для сумм - ищем число с копейками
    const match = cleanText.match(/([\d\s]+[.,]\d{2})/);
    if (match) {
      const value = match[1].replace(/\s/g, '').replace(',', '.');
      const num = parseFloat(value);
      if (!isNaN(num) && num > 0) {
        console.log(`[Z-Report] ${fieldName} fallback с копейками:`, num);
        return num;
      }
    }
    // Если нет копеек - ищем большое число (сумма обычно > 100)
    const numbers = cleanText.match(/\b(\d{3,})\b/g);
    if (numbers) {
      for (const numStr of numbers) {
        const num = parseFloat(numStr);
        if (!isNaN(num) && num > 100) { // Сумма обычно больше 100
          console.log(`[Z-Report] ${fieldName} fallback целое:`, num);
          return num;
        }
      }
    }
  }

  console.log(`[Z-Report] ${fieldName} не найдено в тексте`);
  return null;
}

/**
 * Сравнивает распознанные данные с введёнными пользователем
 */
function validateZReportData(recognized, userInput) {
  const validation = {
    isValid: true,
    errors: [],
    warnings: []
  };

  // Проверяем общую сумму
  if (recognized.totalSum !== null && userInput.totalSum !== undefined) {
    const diff = Math.abs(recognized.totalSum - userInput.totalSum);
    if (diff > 0.01) {
      validation.isValid = false;
      validation.errors.push({
        field: 'totalSum',
        recognized: recognized.totalSum,
        entered: userInput.totalSum,
        message: 'Общая сумма не совпадает: распознано ' + recognized.totalSum + ', введено ' + userInput.totalSum
      });
    }
  }

  // Проверяем наличные
  if (recognized.cashSum !== null && userInput.cashSum !== undefined) {
    const diff = Math.abs(recognized.cashSum - userInput.cashSum);
    if (diff > 0.01) {
      validation.isValid = false;
      validation.errors.push({
        field: 'cashSum',
        recognized: recognized.cashSum,
        entered: userInput.cashSum,
        message: 'Сумма наличных не совпадает: распознано ' + recognized.cashSum + ', введено ' + userInput.cashSum
      });
    }
  }

  // Проверяем ОФД
  if (recognized.ofdNotSent !== null && userInput.ofdNotSent !== undefined) {
    if (recognized.ofdNotSent !== userInput.ofdNotSent) {
      validation.isValid = false;
      validation.errors.push({
        field: 'ofdNotSent',
        recognized: recognized.ofdNotSent,
        entered: userInput.ofdNotSent,
        message: 'Чеки не переданные в ОФД не совпадают: распознано ' + recognized.ofdNotSent + ', введено ' + userInput.ofdNotSent
      });
    }
  }

  // Проверяем ресурс ключей
  if (recognized.resourceKeys !== null && userInput.resourceKeys !== undefined) {
    if (recognized.resourceKeys !== userInput.resourceKeys) {
      validation.isValid = false;
      validation.errors.push({
        field: 'resourceKeys',
        recognized: recognized.resourceKeys,
        entered: userInput.resourceKeys,
        message: 'Ресурс ключей не совпадает: распознано ' + recognized.resourceKeys + ', введено ' + userInput.resourceKeys
      });
    }
  }

  // Предупреждения о не найденных полях
  for (const [field, confidence] of Object.entries(recognized.confidence)) {
    if (confidence === 'not_found') {
      validation.warnings.push({
        field,
        message: 'Поле ' + field + ' не найдено на чеке - ручная проверка рекомендуется'
      });
    }
  }

  return validation;
}

module.exports = {
  parseZReport,
  extractZReportData,
  validateZReportData,
  parseZReportWithTemplate,
  parseRegion,
  extractValueFromText,
  tryRegionSet,
  invalidateLearnedPatternsCache
};
