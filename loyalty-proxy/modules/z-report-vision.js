/**
 * Z-Report Vision Module
 * Распознавание Z-отчётов с помощью Google Cloud Vision API
 */

const vision = require('@google-cloud/vision');
const path = require('path');

// Кэш для выученных паттернов
let learnedPatternsCache = null;
let learnedPatternsCacheTime = 0;
const CACHE_TTL = 60000; // 1 минута

// Инициализация клиента Vision API
const client = new vision.ImageAnnotatorClient({
  keyFilename: path.join(__dirname, '../credentials/vision-key.json')
});

/**
 * Извлекает данные из Z-отчёта
 * @param {string} imageBase64 - Base64 изображения
 * @returns {Object} - Распознанные данные
 */
async function parseZReport(imageBase64) {
  try {
    // Убираем префикс data:image/... если есть
    const base64Data = imageBase64.replace(/^data:image\/\w+;base64,/, '');

    // Распознаём текст на изображении
    const [result] = await client.textDetection({
      image: { content: base64Data }
    });

    const detections = result.textAnnotations;

    if (!detections || detections.length === 0) {
      return {
        success: false,
        error: 'Текст не распознан на изображении'
      };
    }

    // Полный текст с чека
    const fullText = detections[0].description;
    console.log('[Z-Report] Распознанный текст:', fullText);

    // Парсим нужные поля (теперь async)
    const parsed = await extractZReportData(fullText);

    return {
      success: true,
      rawText: fullText,
      data: parsed
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
async function extractZReportData(text, learnedPatterns = null) {
  const lines = text.split('\n').map(l => l.trim());

  const result = {
    totalSum: null,        // Общая сумма
    cashSum: null,         // Сумма наличных
    ofdNotSent: null,      // Чеки не переданные в ОФД
    resourceKeys: null,    // Ресурс ключей
    confidence: {}
  };

  // Загружаем выученные паттерны если не переданы
  if (!learnedPatterns) {
    learnedPatterns = await getLearnedPatternsWithCache();
  }

  // Нормализуем текст для лучшего поиска
  const normalizedText = text
    .replace(/\s+/g, ' ')
    .replace(/[—–-]/g, '-');

  // ============ ОБЩАЯ СУММА / ВЫРУЧКА ============

  // Сначала пробуем выученные паттерны
  if (learnedPatterns.totalSum && learnedPatterns.totalSum.length > 0) {
    for (const learned of learnedPatterns.totalSum) {
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

  // Сначала пробуем выученные паттерны
  if (learnedPatterns.cashSum && learnedPatterns.cashSum.length > 0) {
    for (const learned of learnedPatterns.cashSum) {
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

  // Сначала пробуем выученные паттерны
  if (learnedPatterns.ofdNotSent && learnedPatterns.ofdNotSent.length > 0) {
    for (const learned of learnedPatterns.ofdNotSent) {
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

  // ============ БЛОЧНЫЙ АЛГОРИТМ ДЛЯ OFD (АТОЛ) ============
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

  // Сначала пробуем выученные паттерны
  if (learnedPatterns.resourceKeys && learnedPatterns.resourceKeys.length > 0) {
    for (const learned of learnedPatterns.resourceKeys) {
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
        result.resourceKeys = parseInt(match[1], 10);
        result.confidence.resourceKeys = 'high';
        console.log('[Z-Report] Найден ресурс ключей:', result.resourceKeys);
        break;
      }
    }
  }

  // Помечаем не найденные поля
  if (result.totalSum === null) result.confidence.totalSum = 'not_found';
  if (result.cashSum === null) result.confidence.cashSum = 'not_found';
  if (result.ofdNotSent === null) result.confidence.ofdNotSent = 'not_found';
  if (result.resourceKeys === null) result.confidence.resourceKeys = 'not_found';

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

    // Распознаём текст в области
    const [result] = await client.textDetection({
      image: { content: croppedBuffer.toString('base64') }
    });

    const detections = result.textAnnotations;
    if (!detections || detections.length === 0) {
      return null;
    }

    return detections[0].description.trim();
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
      const base64Data = imageBase64.replace(/^data:image\/\w+;base64,/, '');
      const [ocrResult] = await client.textDetection({
        image: { content: base64Data }
      });
      if (ocrResult.textAnnotations && ocrResult.textAnnotations.length > 0) {
        rawText = ocrResult.textAnnotations[0].description;
        console.log('[Z-Report] Получен rawText для обучения, длина:', rawText.length);
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
    return fieldName === 'ofdNotSent' ? 0 : null; // Для ОФД возвращаем 0, для ключей null
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
  tryRegionSet
};
