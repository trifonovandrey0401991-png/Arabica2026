/**
 * Модуль OCR для распознавания чисел со счётчиков кофемашин
 *
 * Использует Tesseract OCR (локальный, бесплатный)
 * Автоматический fallback: если регион не сработал — пробует полное изображение
 *
 * Пресеты:
 *   - standard: тёмный текст на светлом фоне (Thermoplan BW3)
 *   - standard_resize: standard + увеличение (Thermoplan BW4)
 *   - invert_lcd: инверсия для LCD, светлый текст на тёмном фоне (WMF)
 */

const { exec } = require('child_process');
const util = require('util');
const fsp = require('fs').promises;
const path = require('path');
const sharp = require('sharp');

const execPromise = util.promisify(exec);

const TEMP_DIR = '/tmp/counter-ocr';

// Пресеты предобработки
const PRESETS = {
  standard: {
    negate: false, resize: null, threshold: 128,
    psm: 7, parseStrategy: 'direct',
  },
  standard_resize: {
    negate: false, resize: 1200, threshold: 128,
    psm: 7, parseStrategy: 'direct',
  },
  invert_lcd: {
    negate: true, resize: 1200, threshold: false,
    psm: 6, parseStrategy: 'largest_number',
  },
};

async function fileExists(fp) {
  try { await fsp.access(fp); return true; } catch { return false; }
}

(async () => {
  if (!(await fileExists(TEMP_DIR))) {
    await fsp.mkdir(TEMP_DIR, { recursive: true });
  }
})();

/**
 * Одна попытка OCR с заданным пресетом и регионом
 */
async function singleAttempt(inputPath, metadata, region, presetConfig) {
  const ts = Date.now() + '_' + Math.random().toString(36).slice(2, 6);
  const processedPath = path.join(TEMP_DIR, `ocr_${ts}_proc.png`);
  const outputBasePath = path.join(TEMP_DIR, `ocr_${ts}_out`);

  try {
    let s = sharp(inputPath);

    // Обрезка по региону
    if (region && region.x !== undefined) {
      const left = Math.round(region.x * metadata.width);
      const top = Math.round(region.y * metadata.height);
      const width = Math.round(region.width * metadata.width);
      const height = Math.round(region.height * metadata.height);
      const safeLeft = Math.max(0, Math.min(left, metadata.width - 1));
      const safeTop = Math.max(0, Math.min(top, metadata.height - 1));
      const safeWidth = Math.min(width, metadata.width - safeLeft);
      const safeHeight = Math.min(height, metadata.height - safeTop);
      if (safeWidth > 0 && safeHeight > 0) {
        s = s.extract({ left: safeLeft, top: safeTop, width: safeWidth, height: safeHeight });
      }
    }

    // Предобработка
    s = s.greyscale();
    if (presetConfig.negate) {
      s = s.negate();
    } else {
      s = s.normalise().sharpen();
    }
    if (presetConfig.threshold) {
      s = s.threshold(presetConfig.threshold);
    }
    if (presetConfig.resize) {
      s = s.resize({ width: presetConfig.resize, fit: 'inside' });
    }

    await s.png().toFile(processedPath);

    // Tesseract
    const cmd = `tesseract "${processedPath}" "${outputBasePath}" --psm ${presetConfig.psm} -c tessedit_char_whitelist=0123456789 2>/dev/null`;
    await execPromise(cmd, { timeout: 10000 });

    const rawText = (await fsp.readFile(`${outputBasePath}.txt`, 'utf8')).trim();

    // Парсинг
    let number = null;
    if (presetConfig.parseStrategy === 'largest_number') {
      const matches = rawText.match(/\d+/g);
      if (matches) {
        const numbers = matches.map(n => parseInt(n, 10)).filter(n => n > 100);
        numbers.sort((a, b) => b - a);
        number = numbers.length > 0 ? numbers[0] : null;
      }
    } else {
      const cleaned = rawText.replace(/[^0-9]/g, '');
      number = cleaned.length > 0 ? parseInt(cleaned, 10) : null;
    }

    await cleanupTempFiles([processedPath, `${outputBasePath}.txt`]);
    return { number, rawText };
  } catch (e) {
    await cleanupTempFiles([processedPath, `${outputBasePath}.txt`]);
    return { number: null, rawText: '' };
  }
}

/**
 * Распознать число со снимка с автоматическим fallback
 *
 * Стратегия (до 3 попыток):
 *   1. С регионом + основной пресет
 *   2. Без региона (всё изображение) + основной пресет
 *   3. Без региона + invert_lcd (универсальный для любых экранов)
 *
 * @param {string} imageBase64 - Изображение в base64
 * @param {object} [region] - Область обрезки (относительные координаты 0.0-1.0)
 * @param {string} [preset='standard'] - Пресет предобработки
 * @returns {Promise<{number, confidence, rawText, success, error, method}>}
 */
async function readCounterNumber(imageBase64, region, preset) {
  const mainPreset = PRESETS[preset] || PRESETS.standard;
  const ts = Date.now() + '_' + Math.random().toString(36).slice(2, 6);
  const inputPath = path.join(TEMP_DIR, `counter_${ts}_input.jpg`);

  try {
    const imageBuffer = Buffer.from(imageBase64, 'base64');
    await fsp.writeFile(inputPath, imageBuffer);

    const metadata = await sharp(inputPath).metadata();

    // Попытка 1: с регионом + основной пресет
    if (region && region.x !== undefined) {
      const r1 = await singleAttempt(inputPath, metadata, region, mainPreset);
      if (r1.number !== null && r1.number > 100) {
        await cleanupTempFiles([inputPath]);
        const digitCount = r1.number.toString().length;
        return {
          number: r1.number,
          confidence: Math.min(0.95, 0.5 + (digitCount * 0.1)),
          rawText: r1.rawText,
          success: true,
          error: null,
          method: 'region',
        };
      }
    }

    // Попытка 2: без региона + основной пресет
    const r2 = await singleAttempt(inputPath, metadata, null, mainPreset);
    if (r2.number !== null && r2.number > 100) {
      await cleanupTempFiles([inputPath]);
      const digitCount = r2.number.toString().length;
      return {
        number: r2.number,
        confidence: Math.min(0.85, 0.4 + (digitCount * 0.1)),
        rawText: r2.rawText,
        success: true,
        error: null,
        method: 'full_image',
      };
    }

    // Попытка 3: без региона + invert_lcd (универсальный fallback)
    if (preset !== 'invert_lcd') {
      const r3 = await singleAttempt(inputPath, metadata, null, PRESETS.invert_lcd);
      if (r3.number !== null && r3.number > 100) {
        await cleanupTempFiles([inputPath]);
        const digitCount = r3.number.toString().length;
        return {
          number: r3.number,
          confidence: Math.min(0.70, 0.3 + (digitCount * 0.1)),
          rawText: r3.rawText,
          success: true,
          error: null,
          method: 'fallback_invert',
        };
      }
    }

    // Все попытки провалились
    await cleanupTempFiles([inputPath]);
    return {
      number: null,
      confidence: 0,
      rawText: r2.rawText || '',
      success: false,
      error: 'Не удалось распознать число. Введите вручную.',
      method: 'none',
    };
  } catch (error) {
    console.error('[Counter OCR] Ошибка распознавания:', error.message);
    await cleanupTempFiles([inputPath]);
    return {
      number: null,
      confidence: 0,
      rawText: '',
      success: false,
      error: `Ошибка OCR: ${error.message}`,
      method: 'error',
    };
  }
}

async function cleanupTempFiles(files) {
  for (const file of files) {
    try {
      if (await fileExists(file)) await fsp.unlink(file);
    } catch { /* ignore */ }
  }
}

module.exports = { readCounterNumber, PRESETS };
