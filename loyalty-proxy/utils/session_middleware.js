/**
 * Session Middleware
 * Неблокирующий middleware для извлечения пользователя из session token
 *
 * НЕ блокирует запросы без токена - просто устанавливает req.user = null
 * Это подготовка для будущей авторизации по ролям
 *
 * Использует in-memory индекс token -> session для O(1) lookup
 */

const fs = require('fs');
const fsp = fs.promises;
const path = require('path');
const { isAdminPhone, normalizePhone } = require('./admin_cache');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SESSIONS_DIR = path.join(DATA_DIR, 'auth-sessions');

// In-memory index: sessionToken -> { phone, name, expiresAt }
const tokenIndex = new Map();

// Время последней перестройки индекса
let lastIndexBuild = 0;
const INDEX_REBUILD_INTERVAL_MS = 5 * 60 * 1000; // 5 минут

/**
 * Построить/обновить индекс token -> session
 */
async function rebuildTokenIndex() {
  try {
    if (!fs.existsSync(SESSIONS_DIR)) return;

    const files = await fsp.readdir(SESSIONS_DIR);
    const jsonFiles = files.filter(f => f.endsWith('.json'));
    const now = Date.now();

    // Очищаем старый индекс
    tokenIndex.clear();

    for (const file of jsonFiles) {
      try {
        const content = await fsp.readFile(path.join(SESSIONS_DIR, file), 'utf8');
        const session = JSON.parse(content);

        if (session.sessionToken && session.expiresAt > now) {
          tokenIndex.set(session.sessionToken, {
            phone: session.phone,
            name: session.name,
            expiresAt: session.expiresAt,
          });
        }
      } catch (e) { /* skip invalid files */ }
    }

    lastIndexBuild = now;
    console.log(`[SessionMiddleware] Token index rebuilt: ${tokenIndex.size} active sessions`);
  } catch (e) {
    console.error('[SessionMiddleware] Error rebuilding token index:', e.message);
  }
}

/**
 * Добавить токен в индекс (вызывать при логине)
 */
function addTokenToIndex(sessionToken, phone, name, expiresAt) {
  if (!sessionToken) return;
  tokenIndex.set(sessionToken, { phone, name, expiresAt });
}

/**
 * Удалить токен из индекса (вызывать при логауте)
 */
function removeTokenFromIndex(sessionToken) {
  if (!sessionToken) return;
  tokenIndex.delete(sessionToken);
}

/**
 * Удалить все токены для телефона (вызывать при логауте по телефону)
 */
function removePhoneFromIndex(phone) {
  if (!phone) return;
  const normalized = normalizePhone(phone);
  for (const [token, data] of tokenIndex.entries()) {
    if (normalizePhone(data.phone) === normalized) {
      tokenIndex.delete(token);
    }
  }
}

/**
 * Express middleware - извлекает пользователя из Authorization header
 * НЕ блокирует запросы - только добавляет req.user
 */
function sessionMiddleware(req, res, next) {
  req.user = null;

  // Извлекаем токен из Authorization header
  const authHeader = req.headers['authorization'];
  if (!authHeader || !authHeader.startsWith('Bearer ')) {
    return next();
  }

  const token = authHeader.substring(7);
  if (!token) {
    return next();
  }

  // O(1) lookup в индексе
  const session = tokenIndex.get(token);
  if (!session) {
    return next();
  }

  // Проверяем не истёк ли токен
  if (session.expiresAt <= Date.now()) {
    tokenIndex.delete(token);
    return next();
  }

  // Устанавливаем req.user
  req.user = {
    phone: session.phone,
    name: session.name,
    isAdmin: isAdminPhone(session.phone),
  };

  next();
}

/**
 * Проверить token и вернуть данные сессии (или null)
 * Используется для WebSocket аутентификации
 */
function verifyToken(token) {
  if (!token) return null;
  const session = tokenIndex.get(token);
  if (!session) return null;
  if (session.expiresAt <= Date.now()) {
    tokenIndex.delete(token);
    return null;
  }
  return {
    phone: session.phone,
    name: session.name,
    isAdmin: isAdminPhone(session.phone),
  };
}

/**
 * Инициализация: построить индекс при старте сервера
 */
async function initSessionMiddleware() {
  await rebuildTokenIndex();

  // Периодически перестраиваем индекс (для подхватывания новых сессий)
  setInterval(() => {
    rebuildTokenIndex().catch(e => {
      console.error('[SessionMiddleware] Periodic rebuild error:', e.message);
    });
  }, INDEX_REBUILD_INTERVAL_MS);
}

/**
 * Middleware: требует авторизацию (любой залогиненный пользователь)
 * Возвращает 401 если req.user не установлен
 */
function requireAuth(req, res, next) {
  if (!req.user) {
    return res.status(401).json({
      success: false,
      error: 'Требуется авторизация. Войдите в приложение.'
    });
  }
  next();
}

/**
 * Middleware: требует права администратора
 * Возвращает 401 если не авторизован, 403 если не админ
 */
function requireAdmin(req, res, next) {
  if (!req.user) {
    return res.status(401).json({
      success: false,
      error: 'Требуется авторизация. Войдите в приложение.'
    });
  }
  if (!req.user.isAdmin) {
    return res.status(403).json({
      success: false,
      error: 'Недостаточно прав. Требуется администратор.'
    });
  }
  next();
}

module.exports = {
  sessionMiddleware,
  initSessionMiddleware,
  addTokenToIndex,
  removeTokenFromIndex,
  removePhoneFromIndex,
  rebuildTokenIndex,
  verifyToken,
  requireAuth,
  requireAdmin,
};
