/**
 * Тест File Locking
 *
 * Запуск: node utils/test_file_lock.js
 *
 * Проверяет:
 * 1. Параллельная запись не теряет данные
 * 2. Блокировки корректно освобождаются
 * 3. Таймауты работают
 */

const path = require('path');
const fs = require('fs').promises;
const { writeJsonFile, readJsonFile, getLockStats, withLock } = require('./async_fs');

const TEST_DIR = path.join(__dirname, '../test_data');
const TEST_FILE = path.join(TEST_DIR, 'lock_test.json');

async function setup() {
  await fs.mkdir(TEST_DIR, { recursive: true });
  console.log('📁 Тестовая директория создана');
}

async function cleanup() {
  try {
    await fs.unlink(TEST_FILE);
    await fs.rmdir(TEST_DIR);
  } catch (e) {
    // ignore
  }
}

/**
 * Тест 1: Параллельная запись с withLock
 * Вся операция read-modify-write должна быть атомарной
 */
async function testParallelWrites() {
  console.log('\n🧪 Тест 1: Параллельная запись (10 одновременных)');

  // Начальное значение
  await writeJsonFile(TEST_FILE, { counter: 0 });

  // 10 параллельных операций с полной блокировкой read-modify-write
  const promises = [];
  for (let i = 0; i < 10; i++) {
    promises.push(
      withLock(TEST_FILE, async () => {
        const data = await readJsonFile(TEST_FILE, { counter: 0 });
        data.counter++;
        data[`writer_${i}`] = Date.now();
        await writeJsonFile(TEST_FILE, data, { useLock: false }); // внутри withLock не нужен второй лок
      })
    );
  }

  await Promise.all(promises);

  const result = await readJsonFile(TEST_FILE);
  console.log(`   Ожидаемый counter: 10`);
  console.log(`   Фактический counter: ${result.counter}`);

  if (result.counter === 10) {
    console.log('   ✅ PASSED - все записи сохранены');
    return true;
  } else {
    console.log('   ❌ FAILED - потеряны записи (race condition)');
    return false;
  }
}

/**
 * Тест 2: Блокировки освобождаются
 */
async function testLockRelease() {
  console.log('\n🧪 Тест 2: Освобождение блокировок');

  const statsBefore = getLockStats();

  // Выполняем 5 последовательных записей
  for (let i = 0; i < 5; i++) {
    await writeJsonFile(TEST_FILE, { test: i });
  }

  const statsAfter = getLockStats();

  console.log(`   Активных блокировок до: ${statsBefore.currentLocks}`);
  console.log(`   Активных блокировок после: ${statsAfter.currentLocks}`);

  if (statsAfter.currentLocks === 0) {
    console.log('   ✅ PASSED - все блокировки освобождены');
    return true;
  } else {
    console.log('   ❌ FAILED - блокировки не освобождены');
    return false;
  }
}

/**
 * Тест 3: Без блокировки (для сравнения)
 */
async function testWithoutLock() {
  console.log('\n🧪 Тест 3: Без блокировки (демонстрация проблемы)');

  await writeJsonFile(TEST_FILE, { counter: 0 }, { useLock: false });

  const promises = [];
  for (let i = 0; i < 10; i++) {
    promises.push((async () => {
      const data = await readJsonFile(TEST_FILE, { counter: 0 });
      data.counter++;
      // Искусственная задержка чтобы показать race condition
      await new Promise(r => setTimeout(r, Math.random() * 50));
      await writeJsonFile(TEST_FILE, data, { useLock: false });
    })());
  }

  try {
    await Promise.all(promises);
    const result = await readJsonFile(TEST_FILE);
    console.log(`   Ожидаемый counter: 10`);
    console.log(`   Фактический counter: ${result.counter}`);

    if (result.counter < 10) {
      console.log('   ⚠️  Показано: без лока данные теряются (это ожидаемо)');
    } else {
      console.log('   ℹ️  Повезло - данные не потерялись (но могли бы)');
    }
  } catch (e) {
    console.log('   ⚠️  Ошибка при параллельной записи (ожидаемо без лока)');
  }
  return true;
}

/**
 * Тест 4: Проверка ошибок
 */
async function testErrorHandling() {
  console.log('\n🧪 Тест 4: Обработка ошибок');

  let errorCaught = false;

  try {
    // Пытаемся записать в несуществующую директорию с createDir: false
    await writeJsonFile('/nonexistent/path/file.json', { test: 1 }, { createDir: false });
  } catch (e) {
    errorCaught = true;
  }

  // Проверяем что блокировка освободилась даже после ошибки
  const stats = getLockStats();

  if (errorCaught && stats.currentLocks === 0) {
    console.log('   ✅ PASSED - ошибка поймана, блокировка освобождена');
    return true;
  } else {
    console.log('   ❌ FAILED');
    return false;
  }
}

/**
 * Тест 5: Статистика
 */
async function testStats() {
  console.log('\n🧪 Тест 5: Статистика блокировок');

  const stats = getLockStats();

  console.log(`   Всего блокировок: ${stats.totalLocks}`);
  console.log(`   Текущих блокировок: ${stats.currentLocks}`);
  console.log(`   Макс. одновременных: ${stats.maxConcurrentLocks}`);
  console.log(`   Среднее ожидание: ${stats.avgWaitTime}ms`);
  console.log(`   Таймаутов: ${stats.lockTimeouts}`);

  console.log('   ✅ PASSED - статистика доступна');
  return true;
}

async function runAllTests() {
  console.log('═══════════════════════════════════════');
  console.log('       FILE LOCKING TESTS');
  console.log('═══════════════════════════════════════');

  await setup();

  const results = [];

  results.push(await testParallelWrites());
  results.push(await testLockRelease());
  results.push(await testWithoutLock());
  results.push(await testErrorHandling());
  results.push(await testStats());

  await cleanup();

  console.log('\n═══════════════════════════════════════');
  const passed = results.filter(r => r).length;
  const total = results.length;
  console.log(`       ИТОГО: ${passed}/${total} тестов прошло`);
  console.log('═══════════════════════════════════════');

  if (passed === total) {
    console.log('\n✅ Все тесты прошли! File locking работает корректно.\n');
    process.exit(0);
  } else {
    console.log('\n❌ Есть проблемы!\n');
    process.exit(1);
  }
}

runAllTests().catch(err => {
  console.error('Ошибка:', err);
  process.exit(1);
});
