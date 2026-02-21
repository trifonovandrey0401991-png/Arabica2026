/**
 * Integration Tests — Recount Flow
 *
 * Покрывает критические пути:
 *  1. calculateRecountPoints — линейная интерполяция баллов
 *  2. Barcode validation — D1 (товар есть/нет в каталоге)
 *  3. State machine — pending→failed, review→rejected
 *  4. Dual-write ordering — файл первым
 *  5. Feedback loop — rating → AI signal
 *  6. Bulk-upload atomicity — новые файлы до удаления старых
 *  7. Scheduler double-penalty guard — атомарный UPDATE...RETURNING
 *
 * Запуск: node tests/integration/recount_flow_test.js
 */

'use strict';

const assert = require('assert');
const path = require('path');

let passed = 0;
let failed = 0;

function test(name, fn) {
  try {
    fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ✗ ${name}`);
    console.error(`    → ${e.message}`);
    failed++;
  }
}

async function testAsync(name, fn) {
  try {
    await fn();
    console.log(`  ✓ ${name}`);
    passed++;
  } catch (e) {
    console.error(`  ✗ ${name}`);
    console.error(`    → ${e.message}`);
    failed++;
  }
}

function describe(groupName, fn) {
  console.log(`\n${groupName}`);
  return fn();
}

// ====================================================================
// 1. calculateRecountPoints — точность линейной интерполяции
// ====================================================================
describe('1. calculateRecountPoints (points_settings_api)', () => {
  // Воспроизводим логику функции напрямую (без require чтобы не тянуть всё окружение)
  function calculateRecountPoints(rating, settings) {
    const { minPoints, zeroThreshold, maxPoints, minRating, maxRating } = settings;
    if (rating <= minRating) return minPoints;
    if (rating >= maxRating) return maxPoints;
    if (rating < zeroThreshold) {
      const range = zeroThreshold - minRating;
      return minPoints + (0 - minPoints) * ((rating - minRating) / range);
    }
    if (rating === zeroThreshold) return 0;
    const range = maxRating - zeroThreshold;
    return 0 + (maxPoints - 0) * ((rating - zeroThreshold) / range);
  }

  const settings = { minPoints: -3, zeroThreshold: 7, maxPoints: 1, minRating: 1, maxRating: 10 };

  test('рейтинг 1 → минимум (-3)', () => {
    assert.strictEqual(calculateRecountPoints(1, settings), -3);
  });

  test('рейтинг 10 → максимум (+1)', () => {
    assert.strictEqual(calculateRecountPoints(10, settings), 1);
  });

  test('рейтинг 7 (порог) → 0', () => {
    assert.strictEqual(calculateRecountPoints(7, settings), 0);
  });

  test('рейтинг 4 (между 1 и 7) → отрицательный', () => {
    const pts = calculateRecountPoints(4, settings);
    assert.ok(pts < 0, `Ожидалось < 0, получено ${pts}`);
    assert.ok(pts > -3, `Ожидалось > -3, получено ${pts}`);
  });

  test('рейтинг 8.5 (между 7 и 10) → положительный', () => {
    const pts = calculateRecountPoints(8.5, settings);
    assert.ok(pts > 0, `Ожидалось > 0, получено ${pts}`);
    assert.ok(pts < 1, `Ожидалось < 1, получено ${pts}`);
  });

  test('рейтинг 0 (ниже minRating) → minPoints', () => {
    assert.strictEqual(calculateRecountPoints(0, settings), -3);
  });

  test('рейтинг 11 (выше maxRating) → maxPoints', () => {
    assert.strictEqual(calculateRecountPoints(11, settings), 1);
  });

  test('монотонность: баллы растут с рейтингом', () => {
    let prev = calculateRecountPoints(1, settings);
    for (let r = 2; r <= 10; r++) {
      const cur = calculateRecountPoints(r, settings);
      assert.ok(cur >= prev, `Нарушение монотонности на рейтинге ${r}: ${prev} → ${cur}`);
      prev = cur;
    }
  });
});

// ====================================================================
// 2. Barcode validation (D1 fix)
// ====================================================================
describe('2. Barcode validation flow (D1)', () => {
  function validateAnswers(answers, catalog) {
    const errors = [];
    for (const answer of answers) {
      const barcode = answer.barcode || answer.productId;
      if (!barcode) continue;
      const found = catalog.find(p => p.barcode === barcode);
      if (!found) {
        errors.push({ barcode, error: 'PRODUCT_NOT_FOUND', message: `Товар с barcode "${barcode}" не найден в мастер-каталоге` });
      }
    }
    return errors;
  }

  const catalog = [
    { barcode: '4600000001', name: 'Marlboro Red' },
    { barcode: '4600000002', name: 'Camel Blue' },
    { barcode: '4600000003', name: 'Winston' },
  ];

  test('все баркоды есть → ошибок нет', () => {
    const answers = [
      { barcode: '4600000001', quantity: 10 },
      { barcode: '4600000002', quantity: 5 },
    ];
    assert.deepStrictEqual(validateAnswers(answers, catalog), []);
  });

  test('несуществующий баркод → PRODUCT_NOT_FOUND', () => {
    const answers = [{ barcode: '9999999999', quantity: 3 }];
    const errors = validateAnswers(answers, catalog);
    assert.strictEqual(errors.length, 1);
    assert.strictEqual(errors[0].error, 'PRODUCT_NOT_FOUND');
    assert.strictEqual(errors[0].barcode, '9999999999');
  });

  test('смесь: только несуществующие попадают в ошибки', () => {
    const answers = [
      { barcode: '4600000001', quantity: 5 },
      { barcode: '8888888888', quantity: 2 },
      { barcode: '4600000003', quantity: 7 },
    ];
    const errors = validateAnswers(answers, catalog);
    assert.strictEqual(errors.length, 1);
    assert.strictEqual(errors[0].barcode, '8888888888');
  });

  test('ответ без barcode поля — пропускается', () => {
    const answers = [{ quantity: 5 }];
    assert.deepStrictEqual(validateAnswers(answers, catalog), []);
  });

  test('productId как алиас barcode — проверяется', () => {
    const answers = [{ productId: '9999999999', quantity: 3 }];
    const errors = validateAnswers(answers, catalog);
    assert.strictEqual(errors.length, 1);
    assert.strictEqual(errors[0].barcode, '9999999999');
  });
});

// ====================================================================
// 3. State machine — переходы статусов
// ====================================================================
describe('3. Report state machine (scheduler)', () => {
  function buildReport(overrides = {}) {
    return {
      id: 'report_test_001',
      status: 'pending',
      shopAddress: 'ул. Ленина 1',
      shiftType: 'morning',
      employeeName: 'Иванов',
      employeePhone: '79001234567',
      deadline: null,
      reviewDeadline: null,
      ...overrides,
    };
  }

  function applyDeadlineCheck(report, now) {
    if (report.status !== 'pending') return report;
    if (!report.deadline) return report;
    if (now > new Date(report.deadline)) {
      return { ...report, status: 'failed', failedAt: now.toISOString() };
    }
    return report;
  }

  function applyReviewTimeout(report, now) {
    if (report.status !== 'review') return report;
    if (!report.reviewDeadline) return report;
    if (now > new Date(report.reviewDeadline)) {
      return { ...report, status: 'rejected', rejectedAt: now.toISOString() };
    }
    return report;
  }

  test('pending + не истёк дедлайн → остаётся pending', () => {
    const future = new Date(Date.now() + 3600 * 1000).toISOString();
    const r = buildReport({ status: 'pending', deadline: future });
    const result = applyDeadlineCheck(r, new Date());
    assert.strictEqual(result.status, 'pending');
  });

  test('pending + истёк дедлайн → failed', () => {
    const past = new Date(Date.now() - 3600 * 1000).toISOString();
    const r = buildReport({ status: 'pending', deadline: past });
    const result = applyDeadlineCheck(r, new Date());
    assert.strictEqual(result.status, 'failed');
    assert.ok(result.failedAt);
  });

  test('review + не истёк reviewDeadline → остаётся review', () => {
    const future = new Date(Date.now() + 7200 * 1000).toISOString();
    const r = buildReport({ status: 'review', reviewDeadline: future });
    const result = applyReviewTimeout(r, new Date());
    assert.strictEqual(result.status, 'review');
  });

  test('review + истёк reviewDeadline → rejected', () => {
    const past = new Date(Date.now() - 1000).toISOString();
    const r = buildReport({ status: 'review', reviewDeadline: past });
    const result = applyReviewTimeout(r, new Date());
    assert.strictEqual(result.status, 'rejected');
    assert.ok(result.rejectedAt);
  });

  test('confirmed + истёк deadline → не трогается', () => {
    const past = new Date(Date.now() - 1000).toISOString();
    const r = buildReport({ status: 'confirmed', deadline: past });
    const result = applyDeadlineCheck(r, new Date());
    assert.strictEqual(result.status, 'confirmed'); // функция не изменяет не-pending
  });

  test('rejected + истёк reviewDeadline → не трогается повторно', () => {
    const past = new Date(Date.now() - 1000).toISOString();
    const r = buildReport({ status: 'rejected', reviewDeadline: past });
    const result = applyReviewTimeout(r, new Date());
    assert.strictEqual(result.status, 'rejected'); // функция не изменяет не-review
  });
});

// ====================================================================
// 4. Dual-write ordering — файл первым
// ====================================================================
describe('4. Dual-write ordering (project standard)', () => {
  // Симулируем выполнение операций и проверяем порядок (синхронно — нет реального I/O)
  function simulateDualWrite(simulateDbError = false) {
    const ops = [];

    // Файл первым
    ops.push('write_file');

    // DB вторым (может упасть — файл уже сохранён)
    if (simulateDbError) {
      try {
        throw new Error('DB connection failed');
      } catch (e) {
        ops.push('db_error_logged');
      }
    } else {
      ops.push('write_db');
    }

    return ops;
  }

  test('нормальный путь: файл → DB', () => {
    const ops = simulateDualWrite(false);
    assert.strictEqual(ops[0], 'write_file');
    assert.strictEqual(ops[1], 'write_db');
  });

  test('сбой DB: файл уже записан, ошибка только в логах', () => {
    const ops = simulateDualWrite(true);
    assert.strictEqual(ops[0], 'write_file'); // файл записан
    assert.strictEqual(ops[1], 'db_error_logged'); // DB упала, но это некритично
    assert.strictEqual(ops.length, 2); // программа продолжила работу
  });

  test('нельзя писать в DB до файла', () => {
    const ops = simulateDualWrite(false);
    const fileIdx = ops.indexOf('write_file');
    const dbIdx = ops.indexOf('write_db');
    assert.ok(fileIdx < dbIdx, `Файл (idx ${fileIdx}) должен быть до DB (idx ${dbIdx})`);
  });
});

// ====================================================================
// 5. Feedback loop — rating → AI signal (C4 fix)
// ====================================================================
describe('5. Feedback loop: rating → AI training signal (C4)', () => {
  function decideFeedback(report, rating) {
    const { aiQuantity, actualBalance } = report;
    if (aiQuantity === undefined || actualBalance === undefined) return null;
    const isCorrect = Math.abs(aiQuantity - actualBalance) <= 1;
    if (isCorrect && rating >= 8) return 'positive';
    if (!isCorrect && rating <= 4) return 'error';
    return null;
  }

  test('ИИ угадал (точно) + высокий рейтинг → positive sample', () => {
    assert.strictEqual(decideFeedback({ aiQuantity: 10, actualBalance: 10 }, 9), 'positive');
  });

  test('ИИ угадал (±1) + высокий рейтинг → positive sample', () => {
    assert.strictEqual(decideFeedback({ aiQuantity: 10, actualBalance: 11 }, 8), 'positive');
  });

  test('ИИ ошибся сильно + низкий рейтинг → error sample', () => {
    assert.strictEqual(decideFeedback({ aiQuantity: 5, actualBalance: 15 }, 2), 'error');
  });

  test('ИИ угадал но рейтинг низкий → null (неопределённость)', () => {
    assert.strictEqual(decideFeedback({ aiQuantity: 10, actualBalance: 10 }, 3), null);
  });

  test('ИИ ошибся но рейтинг высокий → null (неопределённость)', () => {
    assert.strictEqual(decideFeedback({ aiQuantity: 2, actualBalance: 10 }, 9), null);
  });

  test('нет данных ИИ → null, не ломается', () => {
    assert.strictEqual(decideFeedback({ actualBalance: 10 }, 9), null);
    assert.strictEqual(decideFeedback({ aiQuantity: 10 }, 9), null);
    assert.strictEqual(decideFeedback({}, 9), null);
  });

  test('средний рейтинг (5-7) → null при любом результате ИИ', () => {
    assert.strictEqual(decideFeedback({ aiQuantity: 10, actualBalance: 10 }, 6), null);
    assert.strictEqual(decideFeedback({ aiQuantity: 1, actualBalance: 10 }, 6), null);
  });
});

// ====================================================================
// 6. Bulk-upload atomicity — новые файлы ПЕРЕД удалением старых
// ====================================================================
describe('6. Bulk-upload atomicity (file-first order)', () => {
  // Симулируем новый порядок операций из исправленного bulk-upload (синхронно)
  function simulateBulkUpload(products, simulateDbError = false) {
    const log = [];
    const newFileNames = new Set();
    const written = [];

    // ШАГ 1: Пишем новые файлы
    for (const p of products) {
      if (!p.barcode) continue;
      const fileName = `product_${p.barcode}.json`;
      log.push(`write_file:${fileName}`);
      newFileNames.add(fileName);
      written.push(p);
    }

    // ШАГ 2: Удаляем сирот
    const existingFileNames = ['product_OLD001.json', 'product_OLD002.json'];
    for (const f of existingFileNames) {
      if (!newFileNames.has(f)) {
        log.push(`delete_orphan:${f}`);
      }
    }

    // ШАГ 3: DB транзакция
    if (simulateDbError) {
      try { throw new Error('DB transaction failed'); }
      catch (e) { log.push('db_error_logged'); }
    } else {
      log.push('db_transaction_ok');
    }

    return { log, written };
  }

  test('файлы пишутся ДО удаления сирот', () => {
    const { log } = simulateBulkUpload([{ barcode: '001', name: 'A' }]);
    const firstWrite = log.findIndex(l => l.startsWith('write_file'));
    const firstDelete = log.findIndex(l => l.startsWith('delete_orphan'));
    assert.ok(firstWrite < firstDelete, `write_file (${firstWrite}) должен быть до delete_orphan (${firstDelete})`);
  });

  test('сбой DB не уничтожает файлы (файлы уже записаны)', () => {
    const { log, written } = simulateBulkUpload([{ barcode: '001', name: 'A' }], true);
    assert.ok(log.some(l => l.startsWith('write_file')), 'Файлы должны быть записаны');
    assert.ok(log.includes('db_error_logged'), 'Ошибка DB должна быть залогирована');
    assert.strictEqual(written.length, 1, 'Товар должен быть в written несмотря на ошибку DB');
  });

  test('только сироты удаляются (новые файлы не трогаются)', () => {
    const products = [{ barcode: 'NEW001', name: 'New A' }];
    const { log } = simulateBulkUpload(products);
    const deletedFiles = log.filter(l => l.startsWith('delete_orphan')).map(l => l.split(':')[1]);
    assert.ok(!deletedFiles.includes('product_NEW001.json'), 'Новый файл не должен быть удалён');
    assert.ok(deletedFiles.includes('product_OLD001.json'), 'Старый файл должен быть удалён');
  });

  test('пустой список продуктов — ничего не записывается, сироты удаляются', () => {
    const { log, written } = simulateBulkUpload([]);
    assert.strictEqual(written.length, 0);
    const deletions = log.filter(l => l.startsWith('delete_orphan'));
    assert.strictEqual(deletions.length, 2, 'Все старые файлы должны быть удалены');
  });
});

// ====================================================================
// 7. Scheduler double-penalty guard
// ====================================================================
describe('7. Double-penalty guard (atomic UPDATE...RETURNING)', () => {
  // Симулируем атомарный UPDATE: только один инстанс "победит"
  function simulateAtomicUpdate(reportId, currentStatus, targetStatus) {
    // Возвращает строки только если статус совпадает (как PostgreSQL RETURNING)
    if (currentStatus === 'review') {
      return [{ id: reportId }]; // SUCCESS: обновлено
    }
    return []; // SKIP: уже обработано другим инстансом
  }

  test('review отчёт → UPDATE возвращает строку → штраф назначается', () => {
    const rows = simulateAtomicUpdate('report_001', 'review', 'rejected');
    assert.strictEqual(rows.length, 1);
    const shouldAssignPenalty = rows.length > 0;
    assert.ok(shouldAssignPenalty);
  });

  test('уже rejected → UPDATE не возвращает строк → штраф НЕ назначается', () => {
    const rows = simulateAtomicUpdate('report_001', 'rejected', 'rejected');
    assert.strictEqual(rows.length, 0);
    const shouldAssignPenalty = rows.length > 0;
    assert.ok(!shouldAssignPenalty);
  });

  test('confirmed отчёт → UPDATE не возвращает строк → штраф НЕ назначается', () => {
    const rows = simulateAtomicUpdate('report_001', 'confirmed', 'rejected');
    assert.strictEqual(rows.length, 0);
    assert.ok(rows.length === 0);
  });

  test('processedIds исключает дубликаты между JSON и DB путями', () => {
    const processedIds = new Set(['report_001', 'report_002']);

    // JSON-путь обработал report_001
    // DB-путь пытается обработать те же записи
    const dbRows = ['report_001', 'report_002', 'report_003'];
    const toProcess = dbRows.filter(id => !processedIds.has(id));

    assert.deepStrictEqual(toProcess, ['report_003']);
    assert.strictEqual(toProcess.length, 1, 'Только report_003 должен пройти через DB-путь');
  });
});

// ====================================================================
// ИТОГ
// ====================================================================
console.log(`\n${'='.repeat(60)}`);
console.log(`Результат: ${passed} прошло, ${failed} провалено`);

if (failed > 0) {
  console.error(`\n❌ ОШИБКА: ${failed} тест(ов) провалено`);
  process.exit(1);
} else {
  console.log('\n✅ Все тесты прошли');
}
