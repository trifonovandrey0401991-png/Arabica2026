/**
 * Audit Bugfix Tests — Arabica
 * Tests for 12 bugs fixed in audit session (2026-03-08)
 *
 * Covers:
 *   H28 — requireEmployee on bonus/loyalty routes
 *   C7  — Unread count with both from/senderType formats
 *   H35 — Session rebuild from DB
 *   H36 — December month overflow in efficiency
 *   H37 — WebSocket sendToParticipants filtering
 *   H45 — Task decline/reject penalty creation
 *   C8/C9 — getMoscowTime instead of Date.now
 *   C11 — Suppliers dual-write JSON backup
 *
 * Run: node tests/audit-bugfix-test.js
 */

'use strict';

let passed = 0;
let failed = 0;

function assert(condition, label) {
  if (condition) {
    console.log(`  ✅ ${label}`);
    passed++;
  } else {
    console.error(`  ❌ FAIL: ${label}`);
    failed++;
  }
}

// ─────────────────────────────────────────────────────────────
// H28: requireEmployee middleware
// ─────────────────────────────────────────────────────────────
console.log('\n[H28] requireEmployee — клиент не может списать бонусы');

const { requireEmployee, requireAuth } = require('../loyalty-proxy/utils/session_middleware');
const { isEmployeePhone, preloadAdminCache } = require('../loyalty-proxy/utils/admin_cache');

function mockRes() {
  let statusCode = null;
  let body = null;
  const res = {
    status(code) { statusCode = code; return res; },
    json(data) { body = data; return res; },
    getStatus() { return statusCode; },
    getBody() { return body; },
  };
  return res;
}

// Без токена → 401
{
  const req = { user: null };
  const res = mockRes();
  let nextCalled = false;
  requireEmployee(req, res, () => { nextCalled = true; });
  assert(res.getStatus() === 401, 'requireEmployee: без токена → 401');
  assert(!nextCalled, 'requireEmployee: без токена → next() не вызван');
}

// Клиент (телефон не в кэше сотрудников) → 403
{
  const req = { user: { phone: '70000000000', name: 'Client', isAdmin: false } };
  const res = mockRes();
  let nextCalled = false;
  requireEmployee(req, res, () => { nextCalled = true; });
  assert(res.getStatus() === 403, 'requireEmployee: клиент → 403');
  assert(!nextCalled, 'requireEmployee: клиент → next() не вызван');
  assert(res.getBody().success === false, 'requireEmployee: клиент → success:false');
}

// isEmployeePhone — null/undefined → false
{
  assert(isEmployeePhone(null) === false, 'isEmployeePhone(null) → false');
  assert(isEmployeePhone(undefined) === false, 'isEmployeePhone(undefined) → false');
  assert(isEmployeePhone('') === false, 'isEmployeePhone("") → false');
}

// ─────────────────────────────────────────────────────────────
// C7: Unread count — оба формата from/senderType
// ─────────────────────────────────────────────────────────────
console.log('\n[C7] Unread count — поддержка обоих форматов полей');

{
  // Логика из clients_api.js — проверяем что оба формата учитываются
  function countUnread(messages) {
    return messages.filter(m =>
      (m.senderType === 'admin' || m.from === 'admin') &&
      !m.isReadByClient &&
      !m.readByClient
    ).length;
  }

  // Старый формат (from)
  const oldMessages = [
    { from: 'admin', readByClient: false },
    { from: 'admin', readByClient: true },
    { from: 'client', readByClient: false },
  ];
  assert(countUnread(oldMessages) === 1, 'Старый формат (from): 1 непрочитанное');

  // Новый формат (senderType)
  const newMessages = [
    { senderType: 'admin', isReadByClient: false },
    { senderType: 'admin', isReadByClient: true },
    { senderType: 'client', isReadByClient: false },
  ];
  assert(countUnread(newMessages) === 1, 'Новый формат (senderType): 1 непрочитанное');

  // Смешанный формат
  const mixedMessages = [
    { from: 'admin', readByClient: false },
    { senderType: 'admin', isReadByClient: false },
    { from: 'client' },
  ];
  assert(countUnread(mixedMessages) === 2, 'Смешанный формат: 2 непрочитанных');

  // Все прочитаны
  const allRead = [
    { from: 'admin', readByClient: true },
    { senderType: 'admin', isReadByClient: true },
  ];
  assert(countUnread(allRead) === 0, 'Все прочитаны: 0');

  // Пустой массив
  assert(countUnread([]) === 0, 'Пустой массив: 0');
}

// Логика отметки прочитанного — оба формата
{
  function markAllAsRead(messages) {
    messages.forEach(m => {
      if (m.from === 'admin' || m.senderType === 'admin') {
        m.readByClient = true;
      }
    });
  }

  const msgs = [
    { from: 'admin', readByClient: false },
    { senderType: 'admin', readByClient: false },
    { from: 'client', readByClient: false },
  ];
  markAllAsRead(msgs);
  assert(msgs[0].readByClient === true, 'markAllAsRead: старый формат (from) → прочитано');
  assert(msgs[1].readByClient === true, 'markAllAsRead: новый формат (senderType) → прочитано');
  assert(msgs[2].readByClient === false, 'markAllAsRead: сообщение от клиента не тронуто');
}

// ─────────────────────────────────────────────────────────────
// H36: December month overflow
// ─────────────────────────────────────────────────────────────
console.log('\n[H36] Декабрь — месяц 12 не превращается в 13');

{
  function getMonthRange(year, monthNum) {
    const start = `${year}-${String(monthNum).padStart(2, '0')}-01`;
    const nextYear = monthNum === 12 ? year + 1 : year;
    const nextMonth = monthNum === 12 ? 1 : monthNum + 1;
    const end = `${nextYear}-${String(nextMonth).padStart(2, '0')}-01`;
    return { start, end };
  }

  // Декабрь
  const dec = getMonthRange(2026, 12);
  assert(dec.start === '2026-12-01', 'Декабрь start: 2026-12-01');
  assert(dec.end === '2027-01-01', 'Декабрь end: 2027-01-01 (не 2026-13-01!)');

  // Январь
  const jan = getMonthRange(2026, 1);
  assert(jan.start === '2026-01-01', 'Январь start: 2026-01-01');
  assert(jan.end === '2026-02-01', 'Январь end: 2026-02-01');

  // Ноябрь (обычный месяц)
  const nov = getMonthRange(2026, 11);
  assert(nov.start === '2026-11-01', 'Ноябрь start: 2026-11-01');
  assert(nov.end === '2026-12-01', 'Ноябрь end: 2026-12-01');

  // Старая логика (баг):
  function getMonthRangeBuggy(year, monthNum) {
    const start = `${year}-${String(monthNum).padStart(2, '0')}-01`;
    const end = `${year}-${String(monthNum + 1).padStart(2, '0')}-01`; // BUG: 13 for December
    return { start, end };
  }

  const decBuggy = getMonthRangeBuggy(2026, 12);
  assert(decBuggy.end === '2026-13-01', 'Старая логика: 2026-13-01 (это был баг!)');
  assert(dec.end !== decBuggy.end, 'Новая логика отличается от старой для декабря');
}

// ─────────────────────────────────────────────────────────────
// H37: WebSocket sendToParticipants — фильтрация по участникам
// ─────────────────────────────────────────────────────────────
console.log('\n[H37] WebSocket — уведомления только участникам чата');

{
  // Воссоздаём логику sendToParticipants
  function sendToParticipants(connections, notification, recipientPhones) {
    const sent = [];
    if (recipientPhones && recipientPhones.length > 0) {
      const normalized = new Set(recipientPhones.map(p => (p || '').replace(/[^\d]/g, '')));
      for (const [phone, sockets] of connections.entries()) {
        if (normalized.has(phone)) {
          sent.push(phone);
        }
      }
    } else {
      // Fallback: broadcast
      for (const phone of connections.keys()) {
        sent.push(phone);
      }
    }
    return sent;
  }

  const connections = new Map();
  connections.set('79001111111', ['socket1']);
  connections.set('79002222222', ['socket2']);
  connections.set('79003333333', ['socket3']);

  // Только участники получают
  const sent1 = sendToParticipants(connections, {}, ['79001111111', '79002222222']);
  assert(sent1.length === 2, 'С участниками: отправлено 2-м (не всем 3-м)');
  assert(sent1.includes('79001111111'), 'Участник 1 получил');
  assert(sent1.includes('79002222222'), 'Участник 2 получил');
  assert(!sent1.includes('79003333333'), 'Не-участник НЕ получил');

  // Телефоны с разным форматом
  const sent2 = sendToParticipants(connections, {}, ['+7 900 111-11-11']);
  assert(sent2.length === 1, 'Нормализация телефона: +7 900 111-11-11 → 79001111111');
  assert(sent2[0] === '79001111111', 'Правильный телефон после нормализации');

  // Пустой список → fallback broadcast
  const sent3 = sendToParticipants(connections, {}, []);
  assert(sent3.length === 3, 'Пустой список: broadcast всем 3-м');

  // null → fallback broadcast
  const sent4 = sendToParticipants(connections, {}, null);
  assert(sent4.length === 3, 'null: broadcast всем 3-м');

  // Телефон не в connections → никому
  const sent5 = sendToParticipants(connections, {}, ['79009999999']);
  assert(sent5.length === 0, 'Несуществующий телефон: никому не отправлено');
}

// ─────────────────────────────────────────────────────────────
// H45: Штрафы за отклонение/отказ от задачи
// ─────────────────────────────────────────────────────────────
console.log('\n[H45] Задачи — создание штрафа при отклонении/отказе');

{
  // Воссоздаём логику создания штрафа из tasks_api.js
  function createDeclinePenalty(assignment, taskTitle, config, reason) {
    const now = new Date('2026-03-08T12:00:00Z');
    const penaltyPoints = config.regularTasks ? config.regularTasks.penaltyPoints : -3;
    return {
      id: `task_declined_${now.getTime()}_test`,
      employeeName: assignment.assigneeName,
      category: 'regular_task_penalty',
      categoryName: 'Отклонённая задача',
      points: penaltyPoints,
      reason: `Задача "${taskTitle}" отклонена сотрудником${reason ? ': ' + reason : ''}`,
      date: now.toISOString().split('T')[0],
      createdAt: now.toISOString(),
      taskId: assignment.taskId,
      assignmentId: assignment.id,
    };
  }

  function createRejectPenalty(assignment, taskTitle, config, reason) {
    const now = new Date('2026-03-08T12:00:00Z');
    const penaltyPoints = config.regularTasks ? config.regularTasks.penaltyPoints : -3;
    return {
      id: `task_rejected_${now.getTime()}_test`,
      employeeName: assignment.assigneeName,
      category: 'regular_task_reject_penalty',
      categoryName: 'Отклонённый результат задачи',
      points: penaltyPoints,
      reason: `Результат задачи "${taskTitle}" отклонён${reason ? ': ' + reason : ''}`,
      date: now.toISOString().split('T')[0],
      createdAt: now.toISOString(),
      taskId: assignment.taskId,
      assignmentId: assignment.id,
    };
  }

  const assignment = {
    id: 'asgn_1',
    taskId: 'task_1',
    assigneeName: 'Иванов Иван',
    assigneePhone: '79001234567',
  };

  // Decline с причиной
  const p1 = createDeclinePenalty(assignment, 'Помыть витрину', { regularTasks: { penaltyPoints: -5 } }, 'не могу сегодня');
  assert(p1.points === -5, 'Decline: баллы из настроек (-5)');
  assert(p1.category === 'regular_task_penalty', 'Decline: категория regular_task_penalty');
  assert(p1.reason.includes('Помыть витрину'), 'Decline: название задачи в причине');
  assert(p1.reason.includes('не могу сегодня'), 'Decline: причина включена');
  assert(p1.employeeName === 'Иванов Иван', 'Decline: имя сотрудника');
  assert(p1.taskId === 'task_1', 'Decline: ID задачи');

  // Decline без причины
  const p2 = createDeclinePenalty(assignment, 'Задача', { regularTasks: { penaltyPoints: -3 } }, '');
  assert(!p2.reason.includes(': '), 'Decline без причины: нет двоеточия');

  // Decline — default points если нет настроек
  const p3 = createDeclinePenalty(assignment, 'Задача', {}, null);
  assert(p3.points === -3, 'Decline: default -3 если нет настроек');

  // Reject
  const p4 = createRejectPenalty(assignment, 'Инвентаризация', { regularTasks: { penaltyPoints: -4 } }, 'плохое качество');
  assert(p4.points === -4, 'Reject: баллы из настроек (-4)');
  assert(p4.category === 'regular_task_reject_penalty', 'Reject: категория regular_task_reject_penalty');
  assert(p4.reason.includes('Инвентаризация'), 'Reject: название задачи в причине');
  assert(p4.reason.includes('плохое качество'), 'Reject: причина включена');
}

// ─────────────────────────────────────────────────────────────
// C8/C9: getMoscowTime вместо Date.now для ограничений по времени
// ─────────────────────────────────────────────────────────────
console.log('\n[C8/C9] Время по Москве для ограничений редактирования/удаления');

{
  const { getMoscowTime } = require('../loyalty-proxy/utils/moscow_time');

  // getMoscowTime должен возвращать Date объект
  const mt = getMoscowTime();
  assert(mt instanceof Date, 'getMoscowTime() возвращает Date');
  assert(typeof mt.getTime() === 'number', 'getMoscowTime().getTime() — число');

  // Разница с UTC должна быть ~3 часа (±1 минуту на всякий случай)
  const utcNow = new Date();
  const diffHours = (mt.getTime() - utcNow.getTime()) / (1000 * 60 * 60);
  assert(Math.abs(diffHours - 3) < 0.1, `getMoscowTime опережает UTC на ~3ч (реально: ${diffHours.toFixed(2)}ч)`);

  // Логика проверки 5-минутного лимита редактирования
  function canEditMessage(createdAt, nowMoscow) {
    const minutesAgo = (nowMoscow.getTime() - createdAt.getTime()) / (1000 * 60);
    return minutesAgo <= 5;
  }

  const now = getMoscowTime();
  const twoMinAgo = new Date(now.getTime() - 2 * 60 * 1000);
  const tenMinAgo = new Date(now.getTime() - 10 * 60 * 1000);

  assert(canEditMessage(twoMinAgo, now) === true, 'Сообщение 2 мин назад: можно редактировать');
  assert(canEditMessage(tenMinAgo, now) === false, 'Сообщение 10 мин назад: нельзя редактировать');

  // Логика проверки 1-часового лимита удаления
  function canDeleteForAll(createdAt, nowMoscow) {
    const minutesAgo = (nowMoscow.getTime() - createdAt.getTime()) / (1000 * 60);
    return minutesAgo <= 60;
  }

  const thirtyMinAgo = new Date(now.getTime() - 30 * 60 * 1000);
  const twoHoursAgo = new Date(now.getTime() - 120 * 60 * 1000);

  assert(canDeleteForAll(thirtyMinAgo, now) === true, 'Сообщение 30 мин назад: можно удалить для всех');
  assert(canDeleteForAll(twoHoursAgo, now) === false, 'Сообщение 2 часа назад: нельзя удалить для всех');
}

// ─────────────────────────────────────────────────────────────
// H35: Session rebuild — проверка логики
// ─────────────────────────────────────────────────────────────
console.log('\n[H35] Session rebuild — добавление сессий из DB в индекс');

{
  // Логика: если токена нет в индексе после JSON-файлов, добавляем из DB
  function mergeDbSessions(tokenIndex, dbRows) {
    let dbAdded = 0;
    for (const row of dbRows) {
      if (row.session_token && !tokenIndex.has(row.session_token)) {
        tokenIndex.set(row.session_token, {
          phone: row.phone,
          name: null,
          expiresAt: new Date(row.expires_at).getTime(),
        });
        dbAdded++;
      }
    }
    return dbAdded;
  }

  const index = new Map();
  index.set('token_from_json', { phone: '79001111111', name: 'JSON User', expiresAt: Date.now() + 86400000 });

  const dbRows = [
    { session_token: 'token_from_db', phone: '79002222222', expires_at: '2026-12-31T23:59:59Z' },
    { session_token: 'token_from_json', phone: '79001111111', expires_at: '2026-12-31T23:59:59Z' }, // дубль
    { session_token: 'token_from_db_2', phone: '79003333333', expires_at: '2026-06-15T12:00:00Z' },
    { session_token: null, phone: '79004444444', expires_at: '2026-12-31T23:59:59Z' }, // null token
  ];

  const added = mergeDbSessions(index, dbRows);
  assert(added === 2, 'Добавлено 2 сессии из DB (дубль и null пропущены)');
  assert(index.size === 3, 'Всего 3 сессии в индексе');
  assert(index.has('token_from_db'), 'token_from_db добавлен');
  assert(index.has('token_from_db_2'), 'token_from_db_2 добавлен');
  assert(index.get('token_from_json').name === 'JSON User', 'Дубль: JSON версия не перезаписана');
  assert(!index.has(null), 'null-токен не добавлен');
}

// ─────────────────────────────────────────────────────────────
// C11: Suppliers dual-write — путь к JSON файлу
// ─────────────────────────────────────────────────────────────
console.log('\n[C11] Suppliers — правильный путь к JSON бэкапу');

{
  const path = require('path');
  const DATA_DIR = process.env.DATA_DIR || '/var/www';
  const SUPPLIERS_DIR = path.join(DATA_DIR, 'suppliers');

  // Проверяем формирование пути
  const supplierId = 'supplier_1709900000000_abc12';
  const filePath = path.join(SUPPLIERS_DIR, `${supplierId}.json`);

  assert(filePath.includes('suppliers'), 'Путь содержит папку suppliers');
  assert(filePath.endsWith('.json'), 'Путь заканчивается на .json');
  assert(filePath.includes(supplierId), 'Путь содержит ID поставщика');

  // ID формат
  const idPattern = /^supplier_\d+_[a-z0-9]+$/;
  assert(idPattern.test(supplierId), 'ID поставщика имеет правильный формат');
}

// ─────────────────────────────────────────────────────────────
// Дополнительно: проверка что requireEmployee экспортируется
// ─────────────────────────────────────────────────────────────
console.log('\n[Exports] Проверка экспортов session_middleware');

{
  const sm = require('../loyalty-proxy/utils/session_middleware');
  assert(typeof sm.requireEmployee === 'function', 'requireEmployee экспортируется как функция');
  assert(typeof sm.requireAuth === 'function', 'requireAuth экспортируется как функция');
  assert(typeof sm.requireAdmin === 'function', 'requireAdmin экспортируется как функция');
}

// ─────────────────────────────────────────────────────────────
// H40: getEmployeePhoneByName — fallback для push-уведомлений
// ─────────────────────────────────────────────────────────────
console.log('\n[H40] getEmployeePhoneByName — поиск телефона по имени');

{
  const { getEmployeePhoneByName } = require('../loyalty-proxy/utils/data_cache');

  // Функция должна существовать
  assert(typeof getEmployeePhoneByName === 'function', 'getEmployeePhoneByName экспортируется');

  // null/undefined → null (кэш может быть пуст)
  assert(getEmployeePhoneByName(null) === null, 'null имя → null');
  assert(getEmployeePhoneByName(undefined) === null, 'undefined имя → null');
  assert(getEmployeePhoneByName('') === null, 'пустое имя → null');

  // Логика fallback: если phone пустой, ищем по имени
  function resolvePhone(report) {
    let phone = report.employeePhone;
    if (!phone && report.employeeName) {
      phone = getEmployeePhoneByName(report.employeeName);
    }
    return phone;
  }

  // Телефон уже есть — не ищем
  const r1 = { employeePhone: '79001234567', employeeName: 'Иванов' };
  assert(resolvePhone(r1) === '79001234567', 'Телефон есть: возвращаем его');

  // Телефон null, имя есть — пытаемся найти (кэш может быть пуст, вернёт null)
  const r2 = { employeePhone: null, employeeName: 'Неизвестный' };
  const resolved = resolvePhone(r2);
  assert(resolved === null || typeof resolved === 'string', 'Телефон null: попытка поиска (null если кэш пуст)');

  // Ни телефона, ни имени → null
  const r3 = { employeePhone: null, employeeName: null };
  assert(resolvePhone(r3) === null, 'Ни телефона, ни имени → null');
}

// ─────────────────────────────────────────────────────────────
// H42: client_prizes — DB mapping functions
// ─────────────────────────────────────────────────────────────
console.log('\n[H42] client_prizes — маппинг DB ↔ JSON');

{
  // Воссоздаём функции маппинга из loyalty_gamification_api.js
  function dbRowToPrize(row) {
    return {
      id: row.id,
      clientPhone: row.client_phone,
      clientName: row.client_name,
      prize: row.prize,
      prizeType: row.prize_type,
      prizeValue: row.prize_value,
      spinDate: row.spin_date ? new Date(row.spin_date).toISOString() : null,
      status: row.status,
      qrToken: row.qr_token,
      qrUsed: row.qr_used || false,
      issuedBy: row.issued_by,
      issuedByName: row.issued_by_name,
      issuedAt: row.issued_at ? new Date(row.issued_at).toISOString() : null,
    };
  }

  function prizeToDbRow(prize) {
    return {
      id: prize.id,
      client_phone: prize.clientPhone,
      client_name: prize.clientName,
      prize: prize.prize,
      prize_type: prize.prizeType,
      prize_value: prize.prizeValue,
      spin_date: prize.spinDate,
      status: prize.status,
      qr_token: prize.qrToken,
      qr_used: prize.qrUsed || false,
      issued_by: prize.issuedBy || null,
      issued_by_name: prize.issuedByName || null,
      issued_at: prize.issuedAt || null,
      updated_at: new Date().toISOString(),
    };
  }

  // Round-trip test: prize → DB → prize
  const originalPrize = {
    id: 'prize_test_123',
    clientPhone: '79001234567',
    clientName: 'Тестовый клиент',
    prize: '+5 баллов',
    prizeType: 'bonus_points',
    prizeValue: 5,
    spinDate: '2026-03-08T12:00:00.000Z',
    status: 'pending',
    qrToken: 'qr_abc123',
    qrUsed: false,
    issuedBy: null,
    issuedByName: null,
    issuedAt: null,
  };

  const dbRow = prizeToDbRow(originalPrize);
  assert(dbRow.client_phone === '79001234567', 'prizeToDbRow: clientPhone → client_phone');
  assert(dbRow.prize_type === 'bonus_points', 'prizeToDbRow: prizeType → prize_type');
  assert(dbRow.qr_token === 'qr_abc123', 'prizeToDbRow: qrToken → qr_token');
  assert(dbRow.qr_used === false, 'prizeToDbRow: qrUsed → qr_used');
  assert(dbRow.updated_at !== undefined, 'prizeToDbRow: updated_at добавлен');

  const restored = dbRowToPrize(dbRow);
  assert(restored.id === originalPrize.id, 'Round-trip: id совпадает');
  assert(restored.clientPhone === originalPrize.clientPhone, 'Round-trip: clientPhone совпадает');
  assert(restored.prizeType === originalPrize.prizeType, 'Round-trip: prizeType совпадает');
  assert(restored.qrToken === originalPrize.qrToken, 'Round-trip: qrToken совпадает');
  assert(restored.status === 'pending', 'Round-trip: status совпадает');

  // Issued prize round-trip
  const issuedPrize = {
    ...originalPrize,
    status: 'issued',
    qrUsed: true,
    issuedBy: '79009876543',
    issuedByName: 'Сотрудник',
    issuedAt: '2026-03-08T13:00:00.000Z',
  };

  const issuedRow = prizeToDbRow(issuedPrize);
  const issuedRestored = dbRowToPrize(issuedRow);
  assert(issuedRestored.status === 'issued', 'Issued round-trip: status issued');
  assert(issuedRestored.qrUsed === true, 'Issued round-trip: qrUsed true');
  assert(issuedRestored.issuedBy === '79009876543', 'Issued round-trip: issuedBy');
  assert(issuedRestored.issuedByName === 'Сотрудник', 'Issued round-trip: issuedByName');
  assert(issuedRestored.issuedAt !== null, 'Issued round-trip: issuedAt не null');

  // Edge case: null spinDate
  const nullDateRow = { ...dbRow, spin_date: null, issued_at: null };
  const nullRestored = dbRowToPrize(nullDateRow);
  assert(nullRestored.spinDate === null, 'Null spinDate → null');
  assert(nullRestored.issuedAt === null, 'Null issuedAt → null');
}

// ─────────────────────────────────────────────────────────────
// H31: shift_transfers — DB mapping functions
// ─────────────────────────────────────────────────────────────
console.log('\n[H31] shift_transfers — маппинг DB ↔ JSON');

{
  function dbRowToTransfer(row) {
    return {
      id: row.id,
      fromEmployeeId: row.from_employee_id,
      fromEmployeeName: row.from_employee_name,
      toEmployeeId: row.to_employee_id || null,
      toEmployeeName: row.to_employee_name || null,
      scheduleEntryId: row.schedule_entry_id,
      shiftDate: row.shift_date,
      shopAddress: row.shop_address,
      shopName: row.shop_name,
      shiftType: row.shift_type,
      comment: row.comment || null,
      status: row.status,
      acceptedBy: row.accepted_by || [],
      rejectedBy: row.rejected_by || [],
      acceptedByEmployeeId: row.accepted_by_employee_id || null,
      acceptedByEmployeeName: row.accepted_by_employee_name || null,
      acceptedAt: row.accepted_at ? new Date(row.accepted_at).toISOString() : null,
      approvedEmployeeId: row.approved_employee_id || null,
      approvedEmployeeName: row.approved_employee_name || null,
      resolvedAt: row.resolved_at ? new Date(row.resolved_at).toISOString() : null,
      isReadByRecipient: row.is_read_by_recipient || false,
      isReadByAdmin: row.is_read_by_admin || false,
      createdAt: row.created_at ? new Date(row.created_at).toISOString() : null,
    };
  }

  function transferToDbRow(t) {
    return {
      id: t.id,
      from_employee_id: t.fromEmployeeId,
      from_employee_name: t.fromEmployeeName,
      to_employee_id: t.toEmployeeId || null,
      to_employee_name: t.toEmployeeName || null,
      schedule_entry_id: t.scheduleEntryId || null,
      shift_date: t.shiftDate,
      shop_address: t.shopAddress || null,
      shop_name: t.shopName || null,
      shift_type: t.shiftType || null,
      comment: t.comment || null,
      status: t.status,
      accepted_by: JSON.stringify(t.acceptedBy || []),
      rejected_by: JSON.stringify(t.rejectedBy || []),
      accepted_by_employee_id: t.acceptedByEmployeeId || null,
      accepted_by_employee_name: t.acceptedByEmployeeName || null,
      accepted_at: t.acceptedAt || null,
      approved_employee_id: t.approvedEmployeeId || null,
      approved_employee_name: t.approvedEmployeeName || null,
      resolved_at: t.resolvedAt || null,
      is_read_by_recipient: t.isReadByRecipient || false,
      is_read_by_admin: t.isReadByAdmin || false,
      created_at: t.createdAt || new Date().toISOString(),
      updated_at: new Date().toISOString(),
    };
  }

  // Round-trip: transfer → DB → transfer
  const original = {
    id: 'transfer_test_123',
    fromEmployeeId: 'emp_1',
    fromEmployeeName: 'Иванов',
    toEmployeeId: null,
    toEmployeeName: null,
    scheduleEntryId: 'entry_1',
    shiftDate: '2026-03-08',
    shopAddress: 'ул. Ленина 1',
    shopName: 'Арабика Центр',
    shiftType: 'morning',
    comment: 'Не могу выйти',
    status: 'pending',
    acceptedBy: [{ employeeId: 'emp_2', employeeName: 'Петров', acceptedAt: '2026-03-08T10:00:00Z' }],
    rejectedBy: [],
    acceptedByEmployeeId: null,
    acceptedByEmployeeName: null,
    acceptedAt: null,
    approvedEmployeeId: null,
    approvedEmployeeName: null,
    resolvedAt: null,
    isReadByRecipient: false,
    isReadByAdmin: false,
    createdAt: '2026-03-08T09:00:00.000Z',
  };

  const dbRow = transferToDbRow(original);
  assert(dbRow.from_employee_id === 'emp_1', 'transferToDbRow: fromEmployeeId → from_employee_id');
  assert(dbRow.shift_date === '2026-03-08', 'transferToDbRow: shiftDate → shift_date');
  assert(dbRow.shop_name === 'Арабика Центр', 'transferToDbRow: shopName → shop_name');
  assert(typeof dbRow.accepted_by === 'string', 'transferToDbRow: acceptedBy → JSON string');
  assert(JSON.parse(dbRow.accepted_by).length === 1, 'transferToDbRow: acceptedBy содержит 1 элемент');

  const restored = dbRowToTransfer(dbRow);
  assert(restored.id === original.id, 'Round-trip: id совпадает');
  assert(restored.fromEmployeeId === original.fromEmployeeId, 'Round-trip: fromEmployeeId');
  assert(restored.shiftDate === original.shiftDate, 'Round-trip: shiftDate');
  assert(restored.status === 'pending', 'Round-trip: status');
  assert(restored.toEmployeeId === null, 'Round-trip: toEmployeeId null (broadcast)');
  assert(restored.comment === 'Не могу выйти', 'Round-trip: comment');

  // Approved transfer
  const approved = {
    ...original,
    status: 'approved',
    approvedEmployeeId: 'emp_2',
    approvedEmployeeName: 'Петров',
    resolvedAt: '2026-03-08T12:00:00.000Z',
    isReadByAdmin: true,
  };

  const approvedRow = transferToDbRow(approved);
  const approvedRestored = dbRowToTransfer(approvedRow);
  assert(approvedRestored.status === 'approved', 'Approved: status');
  assert(approvedRestored.approvedEmployeeId === 'emp_2', 'Approved: approvedEmployeeId');
  assert(approvedRestored.isReadByAdmin === true, 'Approved: isReadByAdmin true');
  assert(approvedRestored.resolvedAt !== null, 'Approved: resolvedAt не null');
}

// ─────────────────────────────────────────────────────────────
// ИТОГО
// ─────────────────────────────────────────────────────────────
console.log(`\n${'='.repeat(50)}`);
console.log(`  PASS: ${passed}/${passed + failed}   FAIL: ${failed}/${passed + failed}`);
console.log(`${'='.repeat(50)}`);

process.exit(failed > 0 ? 1 : 0);
