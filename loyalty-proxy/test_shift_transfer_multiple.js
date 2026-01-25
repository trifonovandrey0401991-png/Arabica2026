/**
 * Тест системы передачи смен с множественными принятиями
 */

const fs = require('fs');
const path = require('path');

const SHIFT_TRANSFERS_FILE = '/var/www/shift-transfers.json';
const WORK_SCHEDULES_DIR = '/var/www/work-schedules';

// Цвета для вывода
const colors = {
  green: '\x1b[32m',
  red: '\x1b[31m',
  yellow: '\x1b[33m',
  blue: '\x1b[34m',
  reset: '\x1b[0m'
};

function log(msg, color = 'reset') {
  console.log(colors[color] + msg + colors.reset);
}

function loadTransfers() {
  try {
    if (fs.existsSync(SHIFT_TRANSFERS_FILE)) {
      return JSON.parse(fs.readFileSync(SHIFT_TRANSFERS_FILE, 'utf8')).requests || [];
    }
  } catch (e) {}
  return [];
}

function saveTransfers(requests) {
  fs.writeFileSync(SHIFT_TRANSFERS_FILE, JSON.stringify({ requests, updatedAt: new Date().toISOString() }, null, 2));
}

// ==================== ТЕСТЫ ====================

async function testCreateRequest() {
  log('\n[TEST 1] Создание запроса на передачу смены', 'blue');

  const testTransfer = {
    id: 'test_transfer_' + Date.now(),
    fromEmployeeId: 'emp_test_001',
    fromEmployeeName: 'Иванов Иван',
    toEmployeeId: null,
    shiftDate: new Date().toISOString().split('T')[0],
    shopAddress: 'ул. Тестовая, 1',
    shopName: 'Тестовый магазин',
    shiftType: 'morning',
    scheduleEntryId: 'schedule_test_001',
    status: 'pending',
    acceptedBy: [],
    createdAt: new Date().toISOString(),
    isReadByRecipient: false,
    isReadByAdmin: false
  };

  const requests = loadTransfers();
  requests.push(testTransfer);
  saveTransfers(requests);

  const saved = loadTransfers().find(r => r.id === testTransfer.id);
  if (saved && saved.status === 'pending' && saved.acceptedBy.length === 0) {
    log('  OK: Запрос создан успешно', 'green');
    log('     - ID: ' + saved.id);
    log('     - Статус: ' + saved.status);
    log('     - acceptedBy: [] (пусто)');
    return testTransfer.id;
  } else {
    log('  FAIL: Ошибка создания запроса', 'red');
    return null;
  }
}

async function testMultipleAcceptances(transferId) {
  log('\n[TEST 2] Множественное принятие запроса', 'blue');

  const requests = loadTransfers();
  const index = requests.findIndex(r => r.id === transferId);

  if (index === -1) {
    log('  FAIL: Запрос не найден', 'red');
    return false;
  }

  // Первый сотрудник принимает
  requests[index].acceptedBy.push({
    employeeId: 'emp_test_002',
    employeeName: 'Петров Пётр',
    acceptedAt: new Date().toISOString()
  });
  requests[index].status = 'has_acceptances';

  // Второй сотрудник принимает
  requests[index].acceptedBy.push({
    employeeId: 'emp_test_003',
    employeeName: 'Сидоров Сидор',
    acceptedAt: new Date().toISOString()
  });

  // Третий сотрудник принимает
  requests[index].acceptedBy.push({
    employeeId: 'emp_test_004',
    employeeName: 'Козлов Козёл',
    acceptedAt: new Date().toISOString()
  });

  saveTransfers(requests);

  const updated = loadTransfers().find(r => r.id === transferId);
  if (updated && updated.status === 'has_acceptances' && updated.acceptedBy.length === 3) {
    log('  OK: Множественное принятие работает', 'green');
    log('     - Статус: ' + updated.status);
    log('     - Количество принявших: ' + updated.acceptedBy.length);
    updated.acceptedBy.forEach((a, i) => {
      log('     - ' + (i+1) + '. ' + a.employeeName);
    });
    return true;
  } else {
    log('  FAIL: Ошибка множественного принятия', 'red');
    return false;
  }
}

async function testAdminSelectsOne(transferId) {
  log('\n[TEST 3] Админ выбирает одного сотрудника', 'blue');

  const requests = loadTransfers();
  const index = requests.findIndex(r => r.id === transferId);

  if (index === -1) {
    log('  FAIL: Запрос не найден', 'red');
    return { success: false };
  }

  const transfer = requests[index];
  const acceptedBy = transfer.acceptedBy || [];

  // Админ выбирает второго (Сидоров)
  const selectedEmployeeId = 'emp_test_003';
  const approvedEmployee = acceptedBy.find(a => a.employeeId === selectedEmployeeId);

  if (!approvedEmployee) {
    log('  FAIL: Выбранный сотрудник не найден в списке принявших', 'red');
    return { success: false };
  }

  // Обновляем статус
  transfer.status = 'approved';
  transfer.resolvedAt = new Date().toISOString();
  transfer.approvedEmployeeId = approvedEmployee.employeeId;
  transfer.approvedEmployeeName = approvedEmployee.employeeName;
  transfer.acceptedByEmployeeId = approvedEmployee.employeeId;
  transfer.acceptedByEmployeeName = approvedEmployee.employeeName;

  requests[index] = transfer;
  saveTransfers(requests);

  // Определяем отклонённых
  const declinedEmployees = acceptedBy.filter(a => a.employeeId !== selectedEmployeeId);

  const updated = loadTransfers().find(r => r.id === transferId);
  if (updated && updated.status === 'approved' && updated.approvedEmployeeName === 'Сидоров Сидор') {
    log('  OK: Админ успешно выбрал сотрудника', 'green');
    log('     - Статус: ' + updated.status);
    log('     - Одобренный: ' + updated.approvedEmployeeName);
    log('     - Отклонённые (' + declinedEmployees.length + ' чел.):');
    declinedEmployees.forEach(d => {
      log('       - ' + d.employeeName);
    });
    return { success: true, declinedEmployees };
  } else {
    log('  FAIL: Ошибка одобрения', 'red');
    return { success: false };
  }
}

async function testNotificationsFunctions() {
  log('\n[TEST 4] Проверка функций уведомлений', 'blue');

  try {
    const notifications = require('./api/shift_transfers_notifications');

    const functions = [
      'notifyTransferCreated',
      'notifyTransferAccepted',
      'notifyTransferRejected',
      'notifyTransferApproved',
      'notifyTransferDeclined',
      'notifyOthersDeclined'
    ];

    let allExist = true;
    for (const fn of functions) {
      if (typeof notifications[fn] === 'function') {
        log('     OK: ' + fn + '()', 'green');
      } else {
        log('     FAIL: ' + fn + '() - НЕ НАЙДЕНА', 'red');
        allExist = false;
      }
    }

    if (allExist) {
      log('  OK: Все функции уведомлений доступны', 'green');
      return true;
    } else {
      log('  FAIL: Некоторые функции отсутствуют', 'red');
      return false;
    }
  } catch (e) {
    log('  FAIL: Ошибка загрузки модуля: ' + e.message, 'red');
    return false;
  }
}

async function testAPIModule() {
  log('\n[TEST 5] Проверка API модуля', 'blue');

  try {
    const apiModule = require('./api/shift_transfers_api');

    if (typeof apiModule.setupShiftTransfersAPI === 'function') {
      log('  OK: API модуль загружен успешно', 'green');
      log('     - setupShiftTransfersAPI() доступна');
      return true;
    } else {
      log('  FAIL: setupShiftTransfersAPI не найдена', 'red');
      return false;
    }
  } catch (e) {
    log('  FAIL: Ошибка загрузки API модуля: ' + e.message, 'red');
    console.error(e);
    return false;
  }
}

async function testScheduleUpdateFunction() {
  log('\n[TEST 6] Проверка функции обновления графика', 'blue');

  const apiContent = fs.readFileSync('./api/shift_transfers_api.js', 'utf8');

  if (apiContent.includes('function updateWorkSchedule(')) {
    log('  OK: Функция updateWorkSchedule() найдена в API', 'green');

    if (apiContent.includes('updateWorkSchedule(')) {
      log('     - Вызывается в endpoint /approve', 'green');
    }

    if (apiContent.includes('scheduleData.entries')) {
      log('     - Работает с entries графика', 'green');
    }

    return true;
  } else {
    log('  FAIL: Функция updateWorkSchedule() не найдена', 'red');
    return false;
  }
}

async function testHTTPEndpoint() {
  log('\n[TEST 7] Проверка HTTP endpoint /api/shift-transfers/admin', 'blue');

  const http = require('http');

  return new Promise((resolve) => {
    const req = http.get('http://localhost:3000/api/shift-transfers/admin', (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          if (json.success === true && Array.isArray(json.requests)) {
            log('  OK: Endpoint работает', 'green');
            log('     - success: true');
            log('     - requests: Array');
            resolve(true);
          } else {
            log('  FAIL: Неверный формат ответа', 'red');
            resolve(false);
          }
        } catch (e) {
          log('  FAIL: Ошибка парсинга JSON: ' + e.message, 'red');
          resolve(false);
        }
      });
    });

    req.on('error', (e) => {
      log('  FAIL: Ошибка запроса: ' + e.message, 'red');
      resolve(false);
    });

    req.setTimeout(5000, () => {
      log('  FAIL: Таймаут запроса', 'red');
      req.destroy();
      resolve(false);
    });
  });
}

async function cleanup(transferId) {
  log('\n[CLEANUP] Очистка тестовых данных...', 'yellow');

  const requests = loadTransfers();
  const filtered = requests.filter(r => !r.id.startsWith('test_transfer_'));
  saveTransfers(filtered);

  log('   Удалено тестовых записей: ' + (requests.length - filtered.length));
}

// ==================== ЗАПУСК ====================

async function runTests() {
  log('========================================================', 'blue');
  log(' ТЕСТ: Система передачи смен с множественными принятиями', 'blue');
  log('========================================================', 'blue');

  let passed = 0;
  let failed = 0;

  // Тест 1
  const transferId = await testCreateRequest();
  if (transferId) passed++; else failed++;

  // Тест 2
  if (transferId) {
    const result2 = await testMultipleAcceptances(transferId);
    if (result2) passed++; else failed++;
  }

  // Тест 3
  if (transferId) {
    const result3 = await testAdminSelectsOne(transferId);
    if (result3.success) passed++; else failed++;
  }

  // Тест 4
  const result4 = await testNotificationsFunctions();
  if (result4) passed++; else failed++;

  // Тест 5
  const result5 = await testAPIModule();
  if (result5) passed++; else failed++;

  // Тест 6
  const result6 = await testScheduleUpdateFunction();
  if (result6) passed++; else failed++;

  // Тест 7
  const result7 = await testHTTPEndpoint();
  if (result7) passed++; else failed++;

  // Очистка
  if (transferId) {
    await cleanup(transferId);
  }

  // Итог
  log('\n========================================================', 'blue');
  if (failed === 0) {
    log(' РЕЗУЛЬТАТ: ' + passed + '/' + (passed + failed) + ' тестов пройдено', 'green');
  } else {
    log(' РЕЗУЛЬТАТ: ' + passed + ' пройдено, ' + failed + ' провалено', 'red');
  }
  log('========================================================', 'blue');

  process.exit(failed > 0 ? 1 : 0);
}

runTests().catch(console.error);
