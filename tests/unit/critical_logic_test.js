/**
 * Critical Logic Unit Tests
 * Tests pure logic functions extracted from fixes in Phase 1-3 + items #1-#8
 *
 * Run with: node tests/unit/critical_logic_test.js
 */

const assert = require('assert');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ✗ ${name}`);
    console.error(`    ${e.message}`);
    failed++;
  }
}

function describe(groupName, fn) {
  console.log(`\n${groupName}`);
  fn();
}

// ====== A1: Array normalization from DB (master_catalog_api fix) ======
describe('Array normalization (fix #1 — findIndex production bug)', () => {
  function normalizeDbArray(rawData) {
    if (Array.isArray(rawData)) return rawData;
    if (typeof rawData === 'string') {
      try {
        const parsed = JSON.parse(rawData);
        return Array.isArray(parsed) ? parsed : [];
      } catch { return []; }
    }
    return [];
  }

  test('возвращает массив если rawData — уже массив', () => {
    assert.deepStrictEqual(normalizeDbArray([1, 2, 3]), [1, 2, 3]);
  });

  test('парсит JSON-строку в массив', () => {
    assert.deepStrictEqual(normalizeDbArray('[1,2,3]'), [1, 2, 3]);
  });

  test('возвращает [] если rawData — объект (не массив)', () => {
    assert.deepStrictEqual(normalizeDbArray({ data: [] }), []);
  });

  test('возвращает [] если rawData — null', () => {
    assert.deepStrictEqual(normalizeDbArray(null), []);
  });

  test('возвращает [] если rawData — undefined', () => {
    assert.deepStrictEqual(normalizeDbArray(undefined), []);
  });

  test('возвращает [] если JSON-строка невалидна', () => {
    assert.deepStrictEqual(normalizeDbArray('{invalid json}'), []);
  });

  test('возвращает [] если JSON-строка — объект (не массив)', () => {
    assert.deepStrictEqual(normalizeDbArray('{"key":"val"}'), []);
  });

  test('сохраняет элементы при парсинге JSON-строки', () => {
    const data = [{ id: 'test', name: 'Test' }];
    assert.deepStrictEqual(normalizeDbArray(JSON.stringify(data)), data);
  });
});

// ====== Fix #3: Image size limit (5MB check) ======
describe('Image size validation (fix #3 — 5MB limit)', () => {
  const MAX_BASE64_SIZE = 5 * 1024 * 1024;

  function isImageTooLarge(base64String) {
    return base64String.length > MAX_BASE64_SIZE;
  }

  test('принимает изображение < 5MB', () => {
    const smallImage = 'A'.repeat(4 * 1024 * 1024);
    assert.strictEqual(isImageTooLarge(smallImage), false);
  });

  test('отклоняет изображение > 5MB', () => {
    const largeImage = 'A'.repeat(5 * 1024 * 1024 + 1);
    assert.strictEqual(isImageTooLarge(largeImage), true);
  });

  test('граничное значение ровно 5MB — принять', () => {
    const exactLimit = 'A'.repeat(5 * 1024 * 1024);
    assert.strictEqual(isImageTooLarge(exactLimit), false);
  });

  test('пустая строка — не слишком большая', () => {
    assert.strictEqual(isImageTooLarge(''), false);
  });
});

// ====== Fix #5: Batch insert chunking logic ======
describe('Batch insert chunking (fix #5 — N+1 → batch)', () => {
  function chunkArray(arr, size) {
    const chunks = [];
    for (let i = 0; i < arr.length; i += size) {
      chunks.push(arr.slice(i, i + size));
    }
    return chunks;
  }

  test('250 записей → 3 чанка [100, 100, 50]', () => {
    const arr = Array.from({ length: 250 }, (_, i) => i);
    const chunks = chunkArray(arr, 100);
    assert.strictEqual(chunks.length, 3);
    assert.strictEqual(chunks[0].length, 100);
    assert.strictEqual(chunks[1].length, 100);
    assert.strictEqual(chunks[2].length, 50);
  });

  test('10 записей → 1 чанк из 10', () => {
    const arr = Array.from({ length: 10 }, (_, i) => i);
    const chunks = chunkArray(arr, 100);
    assert.strictEqual(chunks.length, 1);
    assert.strictEqual(chunks[0].length, 10);
  });

  test('пустой массив → 0 чанков', () => {
    const chunks = chunkArray([], 100);
    assert.strictEqual(chunks.length, 0);
  });

  test('ровно 100 записей → 1 чанк из 100', () => {
    const arr = Array.from({ length: 100 }, (_, i) => i);
    const chunks = chunkArray(arr, 100);
    assert.strictEqual(chunks.length, 1);
    assert.strictEqual(chunks[0].length, 100);
  });

  test('101 запись → 2 чанка [100, 1]', () => {
    const arr = Array.from({ length: 101 }, (_, i) => i);
    const chunks = chunkArray(arr, 100);
    assert.strictEqual(chunks.length, 2);
    assert.strictEqual(chunks[1].length, 1);
  });

  test('все элементы сохраняются после чанкинга', () => {
    const arr = Array.from({ length: 250 }, (_, i) => i);
    const chunks = chunkArray(arr, 100);
    const flattened = chunks.flat();
    assert.deepStrictEqual(flattened, arr);
  });
});

// ====== Fix A5: Report ID uniqueness ======
describe('Report ID uniqueness (fix A5 — Date.now() + random suffix)', () => {
  function generateReportId() {
    return `report_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`;
  }

  test('ID начинается с "report_"', () => {
    assert(generateReportId().startsWith('report_'));
  });

  test('100 быстро сгенерированных ID — все уникальные', () => {
    const ids = new Set();
    for (let i = 0; i < 100; i++) {
      ids.add(generateReportId());
    }
    assert.strictEqual(ids.size, 100);
  });

  test('содержит числовую часть (timestamp)', () => {
    const id = generateReportId();
    const parts = id.split('_');
    assert.strictEqual(parts.length, 3); // report, timestamp, random
    assert(/^\d+$/.test(parts[1])); // timestamp — только цифры
  });
});

// ====== D1: Barcode validation format ======
describe('Barcode validation format (fix D1)', () => {
  // Имитирует логику validateAnswerBarcodes из recount_api.js
  function validateBarcodes(answers, catalog) {
    const missing = [];
    for (const answer of answers) {
      if (!answer.barcode) continue;
      const found = catalog.find(p => p.barcode === answer.barcode);
      if (!found) missing.push(answer.barcode);
    }
    return missing;
  }

  const catalog = [
    { barcode: '4600000001', name: 'Товар А' },
    { barcode: '4600000002', name: 'Товар Б' },
  ];

  test('валидный штрихкод → пустой массив ошибок', () => {
    const answers = [{ barcode: '4600000001', quantity: 5 }];
    assert.deepStrictEqual(validateBarcodes(answers, catalog), []);
  });

  test('несуществующий штрихкод → в массиве ошибок', () => {
    const answers = [{ barcode: '9999999999', quantity: 5 }];
    const missing = validateBarcodes(answers, catalog);
    assert.strictEqual(missing.length, 1);
    assert.strictEqual(missing[0], '9999999999');
  });

  test('смешанные штрихкоды → только несуществующие в ошибках', () => {
    const answers = [
      { barcode: '4600000001', quantity: 5 },
      { barcode: '9999999999', quantity: 3 },
    ];
    const missing = validateBarcodes(answers, catalog);
    assert.strictEqual(missing.length, 1);
    assert.strictEqual(missing[0], '9999999999');
  });

  test('ответ без штрихкода — пропускается', () => {
    const answers = [{ quantity: 5 }]; // нет barcode
    assert.deepStrictEqual(validateBarcodes(answers, catalog), []);
  });
});

// ====== C4: Feedback loop — AI accuracy decision ======
describe('Feedback loop logic (fix C4 — rating → AI training signal)', () => {
  function decideFeedback(aiQuantity, actualBalance, rating) {
    if (aiQuantity === undefined || actualBalance === undefined) return null;
    const isCorrect = Math.abs(aiQuantity - actualBalance) <= 1;
    if (isCorrect && rating >= 8) return 'positive';
    if (!isCorrect && rating <= 4) return 'error';
    return null; // Неопределённость — не обучаем
  }

  test('ИИ угадал (±1) + рейтинг ≥8 → positive', () => {
    assert.strictEqual(decideFeedback(10, 10, 9), 'positive');
    assert.strictEqual(decideFeedback(10, 11, 8), 'positive'); // разница 1 — допустимо
  });

  test('ИИ ошибся + рейтинг ≤4 → error', () => {
    assert.strictEqual(decideFeedback(5, 10, 3), 'error');
    assert.strictEqual(decideFeedback(15, 10, 4), 'error'); // разница 5
  });

  test('ИИ угадал но рейтинг низкий → null (не обучаем)', () => {
    assert.strictEqual(decideFeedback(10, 10, 3), null);
  });

  test('ИИ ошибся но рейтинг высокий → null (неопределённость)', () => {
    assert.strictEqual(decideFeedback(5, 10, 9), null);
  });

  test('нет данных ИИ → null', () => {
    assert.strictEqual(decideFeedback(undefined, 10, 8), null);
    assert.strictEqual(decideFeedback(10, undefined, 8), null);
  });

  test('средний рейтинг (5-7) → null при любом результате', () => {
    assert.strictEqual(decideFeedback(5, 10, 6), null); // ошибка + средний
    assert.strictEqual(decideFeedback(10, 10, 6), null); // верно + средний
  });
});

// ====== Summary ======
console.log(`\n${'='.repeat(50)}`);
console.log(`Результат: ${passed} прошло, ${failed} провалено`);
if (failed > 0) {
  console.error(`\nОШИБКА: ${failed} тест(ов) провалено`);
  process.exit(1);
} else {
  console.log('\nВсе тесты прошли ✓');
}
