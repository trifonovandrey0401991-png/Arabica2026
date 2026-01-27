// Тест расчёта рейтинга с милестоунами для рефералов
// Проверяет что функция getReferralPoints() правильно использует милестоуны

const { calculateReferralPointsWithMilestone } = require('./referrals_api');

console.log('=== ТЕСТ РАСЧЁТА БАЛЛОВ ЗА РЕФЕРАЛОВ С МИЛЕСТОУНАМИ ===\n');

// Тест 1: Старый формат (милестоуны отключены)
console.log('ТЕСТ 1: Старый формат (threshold=0)');
const test1 = calculateReferralPointsWithMilestone(10, 1, 0, 3);
console.log(`  10 клиентов, base=1, threshold=0, milestone=3`);
console.log(`  Результат: ${test1} баллов`);
console.log(`  Ожидается: 10 баллов (10 * 1)`);
console.log(`  ${test1 === 10 ? '✅ PASS' : '❌ FAIL'}\n`);

// Тест 2: Каждый 5-й клиент получает бонус
console.log('ТЕСТ 2: Милестоуны включены (каждый 5-й)');
const test2 = calculateReferralPointsWithMilestone(10, 1, 5, 3);
console.log(`  10 клиентов, base=1, threshold=5, milestone=3`);
console.log(`  Клиенты 1,2,3,4 = 4*1 = 4`);
console.log(`  Клиент 5 = 1*3 = 3 (МИЛЕСТОУН)`);
console.log(`  Клиенты 6,7,8,9 = 4*1 = 4`);
console.log(`  Клиент 10 = 1*3 = 3 (МИЛЕСТОУН)`);
console.log(`  Результат: ${test2} баллов`);
console.log(`  Ожидается: 14 баллов (4+3+4+3)`);
console.log(`  ${test2 === 14 ? '✅ PASS' : '❌ FAIL'}\n`);

// Тест 3: Высокие милестоуны (каждый 10-й)
console.log('ТЕСТ 3: Каждый 10-й клиент');
const test3 = calculateReferralPointsWithMilestone(20, 2, 10, 5);
console.log(`  20 клиентов, base=2, threshold=10, milestone=5`);
console.log(`  Клиенты 1-9,11-19 = 18*2 = 36`);
console.log(`  Клиенты 10,20 = 2*5 = 10 (МИЛЕСТОУНЫ)`);
console.log(`  Результат: ${test3} баллов`);
console.log(`  Ожидается: 46 баллов (36+10)`);
console.log(`  ${test3 === 46 ? '✅ PASS' : '❌ FAIL'}\n`);

// Тест 4: Частые милестоуны (каждый 3-й)
console.log('ТЕСТ 4: Частые милестоуны (каждый 3-й)');
const test4 = calculateReferralPointsWithMilestone(9, 1, 3, 10);
console.log(`  9 клиентов, base=1, threshold=3, milestone=10`);
console.log(`  Клиенты 1,2,4,5,7,8 = 6*1 = 6`);
console.log(`  Клиенты 3,6,9 = 3*10 = 30 (МИЛЕСТОУНЫ)`);
console.log(`  Результат: ${test4} баллов`);
console.log(`  Ожидается: 36 баллов (6+30)`);
console.log(`  ${test4 === 36 ? '✅ PASS' : '❌ FAIL'}\n`);

// Тест 5: Нет клиентов
console.log('ТЕСТ 5: Нет клиентов');
const test5 = calculateReferralPointsWithMilestone(0, 1, 5, 3);
console.log(`  0 клиентов, base=1, threshold=5, milestone=3`);
console.log(`  Результат: ${test5} баллов`);
console.log(`  Ожидается: 0 баллов`);
console.log(`  ${test5 === 0 ? '✅ PASS' : '❌ FAIL'}\n`);

// Тест 6: Один клиент (не достигает милестоуна)
console.log('ТЕСТ 6: Один клиент (не достигает милестоуна)');
const test6 = calculateReferralPointsWithMilestone(1, 1, 5, 3);
console.log(`  1 клиент, base=1, threshold=5, milestone=3`);
console.log(`  Клиент 1 = 1*1 = 1`);
console.log(`  Результат: ${test6} баллов`);
console.log(`  Ожидается: 1 балл`);
console.log(`  ${test6 === 1 ? '✅ PASS' : '❌ FAIL'}\n`);

// Итоги
const allTests = [test1 === 10, test2 === 14, test3 === 46, test4 === 36, test5 === 0, test6 === 1];
const passed = allTests.filter(t => t).length;
const total = allTests.length;

console.log('=== ИТОГОВЫЕ РЕЗУЛЬТАТЫ ===');
console.log(`Пройдено тестов: ${passed}/${total}`);
console.log(passed === total ? '✅ ВСЕ ТЕСТЫ ПРОЙДЕНЫ' : '❌ ЕСТЬ ОШИБКИ');

// Демонстрация разницы между старым и новым подходом
console.log('\n=== СРАВНЕНИЕ СТАРОГО И НОВОГО ПОДХОДА ===');
console.log('Сотрудник привлёк 10 клиентов за месяц:');
console.log(`  Старый подход (1 балл за клиента):         ${calculateReferralPointsWithMilestone(10, 1, 0, 3)} баллов`);
console.log(`  Новый подход (каждый 5-й = 3 балла):       ${calculateReferralPointsWithMilestone(10, 1, 5, 3)} баллов`);
console.log(`  Прирост мотивации:                         +${calculateReferralPointsWithMilestone(10, 1, 5, 3) - calculateReferralPointsWithMilestone(10, 1, 0, 3)} балла (+40%)`);
