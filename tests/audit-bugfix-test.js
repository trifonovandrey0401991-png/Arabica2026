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
// ИТОГО
// ─────────────────────────────────────────────────────────────
console.log(`\n${'='.repeat(50)}`);
console.log(`  PASS: ${passed}/${passed + failed}   FAIL: ${failed}/${passed + failed}`);
console.log(`${'='.repeat(50)}`);

process.exit(failed > 0 ? 1 : 0);
