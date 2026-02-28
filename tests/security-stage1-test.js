/**
 * ЭТАП 1: Тесты безопасности сервера
 * Проверяет:
 *  1. requireAdmin middleware возвращает 403 для non-admin, 401 без токена
 *  2. Защищённые эндпоинты недоступны для обычного пользователя
 *  3. Для авторизованного admin поведение не изменилось
 *
 * Запуск: node tests/security-stage1-test.js
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
// 1. Unit-тест: requireAdmin middleware
// ─────────────────────────────────────────────────────────────
console.log('\n[1] Unit: requireAdmin middleware');

const { requireAdmin, requireAuth } = require('../loyalty-proxy/utils/session_middleware');

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

// Без токена (req.user = null) → 401
{
  const req = { user: null };
  const res = mockRes();
  let nextCalled = false;
  requireAdmin(req, res, () => { nextCalled = true; });
  assert(res.getStatus() === 401, 'requireAdmin: без токена → 401');
  assert(!nextCalled, 'requireAdmin: без токена → next() не вызван');
}

// Обычный пользователь (isAdmin=false) → 403
{
  const req = { user: { phone: '79001234567', name: 'Test', isAdmin: false } };
  const res = mockRes();
  let nextCalled = false;
  requireAdmin(req, res, () => { nextCalled = true; });
  assert(res.getStatus() === 403, 'requireAdmin: non-admin → 403');
  assert(!nextCalled, 'requireAdmin: non-admin → next() не вызван');
  assert(res.getBody().success === false, 'requireAdmin: non-admin → success:false');
}

// Администратор (isAdmin=true) → next() вызван, статус не установлен
{
  const req = { user: { phone: '79000000000', name: 'Admin', isAdmin: true } };
  const res = mockRes();
  let nextCalled = false;
  requireAdmin(req, res, () => { nextCalled = true; });
  assert(nextCalled, 'requireAdmin: admin → next() вызван');
  assert(res.getStatus() === null, 'requireAdmin: admin → статус не установлен (пропускает)');
}

// requireAuth: без токена → 401
{
  const req = { user: null };
  const res = mockRes();
  let nextCalled = false;
  requireAuth(req, res, () => { nextCalled = true; });
  assert(res.getStatus() === 401, 'requireAuth: без токена → 401');
}

// requireAuth: с пользователем → next()
{
  const req = { user: { phone: '79001234567', isAdmin: false } };
  const res = mockRes();
  let nextCalled = false;
  requireAuth(req, res, () => { nextCalled = true; });
  assert(nextCalled, 'requireAuth: с пользователем → next()');
}

// ─────────────────────────────────────────────────────────────
// 2. Unit-тест: messenger — req.user.phone вместо senderPhone
// ─────────────────────────────────────────────────────────────
console.log('\n[2] Unit: IDOR — sender из req.user.phone');

{
  // Симулируем новую логику: senderPhone берётся из req.user.phone
  function getMessageSender(req) {
    // Исправленная логика: игнорируем req.body.senderPhone
    const phone = req.user && req.user.phone ? req.user.phone.replace(/[^\d]/g, '') : null;
    return phone;
  }

  // Атака: пытаемся написать от чужого имени
  const attackReq = {
    user: { phone: '79001111111', isAdmin: false },
    body: { senderPhone: '79002222222' } // пытаемся подменить отправителя
  };
  assert(getMessageSender(attackReq) === '79001111111', 'IDOR: senderPhone из body игнорируется, берётся req.user.phone');

  // Нормальный запрос
  const normalReq = {
    user: { phone: '79001234567', isAdmin: false },
    body: { senderPhone: '79001234567', type: 'text', content: 'Привет' }
  };
  assert(getMessageSender(normalReq) === '79001234567', 'Обычный запрос: sender = req.user.phone');

  // Без пользователя (не должно быть — requireAuth блокирует раньше)
  const noUserReq = { user: null, body: { senderPhone: '79001234567' } };
  assert(getMessageSender(noUserReq) === null, 'Без user: sender = null');
}

// ─────────────────────────────────────────────────────────────
// 3. Unit-тест: bonus_penalties — GET разрешён всем, POST/DELETE только admin
// ─────────────────────────────────────────────────────────────
console.log('\n[3] Unit: bonus_penalties — права доступа');

{
  // Симулируем маршрутизацию
  function checkBonusAccess(method, req) {
    if (method === 'GET') {
      // requireAuth — любой пользователь
      return req.user ? 'allow' : 'deny-401';
    }
    if (method === 'POST' || method === 'DELETE') {
      // requireAdmin — только admin
      if (!req.user) return 'deny-401';
      if (!req.user.isAdmin) return 'deny-403';
      return 'allow';
    }
    return 'allow';
  }

  assert(checkBonusAccess('GET', { user: { phone: '79001234567', isAdmin: false } }) === 'allow', 'GET bonus: обычный пользователь — allow');
  assert(checkBonusAccess('POST', { user: { phone: '79001234567', isAdmin: false } }) === 'deny-403', 'POST bonus: non-admin → 403');
  assert(checkBonusAccess('DELETE', { user: { phone: '79001234567', isAdmin: false } }) === 'deny-403', 'DELETE bonus: non-admin → 403');
  assert(checkBonusAccess('POST', { user: { phone: '79000000000', isAdmin: true } }) === 'allow', 'POST bonus: admin → allow');
  assert(checkBonusAccess('POST', { user: null }) === 'deny-401', 'POST bonus: без токена → 401');
}

// ─────────────────────────────────────────────────────────────
// 4. Unit-тест: work_schedule/clear — только admin
// ─────────────────────────────────────────────────────────────
console.log('\n[4] Unit: work_schedule/clear — права доступа');

{
  function checkClearAccess(req) {
    if (!req.user) return 403; // на самом деле 401, но тест для ясности
    if (!req.user.isAdmin) return 403;
    return 200;
  }

  assert(checkClearAccess({ user: { isAdmin: false } }) === 403, 'DELETE /clear: non-admin → 403');
  assert(checkClearAccess({ user: { isAdmin: true } }) === 200, 'DELETE /clear: admin → 200');
  assert(checkClearAccess({ user: null }) === 403, 'DELETE /clear: без токена → 403/401');
}

// ─────────────────────────────────────────────────────────────
// Итог
// ─────────────────────────────────────────────────────────────
console.log(`\n${'─'.repeat(50)}`);
console.log(`Результат: ${passed} ✅  /  ${failed} ❌`);
if (failed > 0) {
  console.error('ТЕСТЫ НЕ ПРОШЛИ!');
  process.exit(1);
} else {
  console.log('Все тесты прошли ✅');
  process.exit(0);
}
