/**
 * Auth API - Система аутентификации Arabica
 *
 * Endpoints:
 * - POST /api/auth/register - Регистрация с PIN (без OTP)
 * - POST /api/auth/login - Вход с PIN
 * - POST /api/auth/request-otp - Запрос OTP через Telegram (для сброса PIN)
 * - POST /api/auth/verify-otp - Проверка OTP кода
 * - POST /api/auth/reset-pin - Сброс PIN после верификации OTP
 * - POST /api/auth/validate-session - Проверка сессии
 * - POST /api/auth/logout - Выход
 */

const express = require('express');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');

const router = express.Router();
const { addTokenToIndex, removeTokenFromIndex, removePhoneFromIndex, requireAuth, requireAdmin } = require('../utils/session_middleware');
const { withLock } = require('../utils/file_lock');
const { writeJsonFile } = require('../utils/async_fs');
const { maskPhone } = require('../utils/file_helpers');
const { isAdminPhone } = require('../utils/admin_cache');
const dataCache = require('../utils/data_cache');
const db = require('../utils/db');

const USE_DB = process.env.USE_DB_AUTH === 'true';

// Конфигурация
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SESSIONS_DIR = path.join(DATA_DIR, 'auth-sessions');
const PINS_DIR = path.join(DATA_DIR, 'auth-pins');
const OTP_DIR = path.join(DATA_DIR, 'auth-otp');

// Время жизни сессии (7 дней)
const SESSION_LIFETIME_MS = 7 * 24 * 60 * 60 * 1000;
// Максимум неудачных попыток PIN
const MAX_PIN_ATTEMPTS = 5;
// Время блокировки (15 минут)
const LOCKOUT_DURATION_MS = 15 * 60 * 1000;

// Инициализация директорий
async function initDirs() {
  await fs.mkdir(SESSIONS_DIR, { recursive: true });
  await fs.mkdir(PINS_DIR, { recursive: true });
  await fs.mkdir(OTP_DIR, { recursive: true });
}
initDirs().catch(console.error);

// Bcrypt (опциональный - если не установлен, используем SHA-256)
let bcrypt;
try {
  bcrypt = require('bcryptjs');
  console.log('[Auth] bcryptjs loaded - secure PIN hashing enabled');
} catch (e) {
  bcrypt = null;
  console.warn('[Auth] bcryptjs not installed - using SHA-256 fallback. Run: npm install bcryptjs');
}
const BCRYPT_ROUNDS = 10;

/**
 * Генерирует хеш PIN-кода (SHA-256 - legacy)
 */
function hashPinSha256(pin, salt) {
  return crypto.createHash('sha256').update(pin + salt).digest('hex');
}

/**
 * Генерирует хеш PIN-кода (bcrypt или SHA-256 fallback)
 */
async function hashPinSecure(pin) {
  if (bcrypt) {
    return await bcrypt.hash(pin, BCRYPT_ROUNDS);
  }
  // Fallback: SHA-256
  const salt = generateSalt();
  return { pinHash: hashPinSha256(pin, salt), salt, hashType: 'sha256' };
}

/**
 * Проверяет PIN против хеша (поддержка bcrypt и SHA-256)
 * Возвращает { valid: boolean, needsMigration: boolean }
 */
async function verifyPin(pin, pinData) {
  if (pinData.hashType === 'bcrypt' && bcrypt) {
    // Bcrypt проверка
    const valid = await bcrypt.compare(pin, pinData.pinHash);
    return { valid, needsMigration: false };
  }

  // SHA-256 проверка (legacy или если bcrypt недоступен)
  const inputHash = hashPinSha256(pin, pinData.salt);
  const valid = inputHash === pinData.pinHash;
  // Нужна миграция если bcrypt доступен и хэш пока SHA-256
  return { valid, needsMigration: valid && bcrypt !== null && pinData.hashType !== 'bcrypt' };
}

/**
 * Мигрирует PIN на bcrypt (вызывается после успешного логина)
 */
async function migratePinToBcrypt(phone, pin, pinData) {
  if (!bcrypt) return;
  try {
    const bcryptHash = await bcrypt.hash(pin, BCRYPT_ROUNDS);
    pinData.pinHash = bcryptHash;
    pinData.hashType = 'bcrypt';
    pinData.salt = ''; // Bcrypt включает соль в хэш
    pinData.migratedAt = new Date().toISOString();
    await savePinData(phone, pinData);
    console.log(`[Auth] PIN migrated to bcrypt for: ${maskPhone(phone)}`);
  } catch (e) {
    console.error(`[Auth] bcrypt migration error for ${maskPhone(phone)}:`, e.message);
  }
}

// Legacy alias (для совместимости если где-то используется)
function hashPin(pin, salt) {
  return hashPinSha256(pin, salt);
}

/**
 * Генерирует случайную соль
 */
function generateSalt() {
  return crypto.randomBytes(16).toString('hex');
}

/**
 * Генерирует токен сессии
 */
function generateSessionToken() {
  return crypto.randomBytes(32).toString('hex');
}

/**
 * Нормализует номер телефона
 * M-11: Унифицировано — сначала только цифры, затем 8→7 конверсия
 */
function normalizePhone(phone) {
  let normalized = phone.replace(/[^\d]/g, '');
  if (normalized.startsWith('8') && normalized.length === 11) {
    normalized = '7' + normalized.substring(1);
  }
  if (!normalized.startsWith('7') && normalized.length === 10) {
    normalized = '7' + normalized;
  }
  return normalized;
}

/**
 * Получает данные PIN по номеру телефона
 */
async function getPinData(phone) {
  if (USE_DB) {
    const row = await db.findById('auth_pins', phone, 'phone');
    return row ? row.data : null;
  }

  const filePath = path.join(PINS_DIR, `${phone}.json`);
  try {
    const data = await fs.readFile(filePath, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

/**
 * Сохраняет данные PIN
 */
async function savePinData(phone, data) {
  const filePath = path.join(PINS_DIR, `${phone}.json`);
  await writeJsonFile(filePath, data);

  if (USE_DB) {
    try { await db.upsert('auth_pins', { phone: phone, data: data, updated_at: new Date().toISOString() }, 'phone'); }
    catch (dbErr) { console.error('DB save auth_pin error:', dbErr.message); }
  }
}

/**
 * Получает сессию по токену
 */
async function getSessionByToken(token) {
  try {
    if (USE_DB) {
      const result = await db.query('SELECT data FROM auth_sessions WHERE data->>\'sessionToken\' = $1 LIMIT 1', [token]);
      if (result.rows && result.rows.length > 0) {
        return result.rows[0].data;
      }
      return null;
    }

    const files = await fs.readdir(SESSIONS_DIR);
    for (const file of files) {
      if (file.endsWith('.json')) {
        const data = await fs.readFile(path.join(SESSIONS_DIR, file), 'utf8');
        const session = JSON.parse(data);
        if (session.sessionToken === token) {
          return session;
        }
      }
    }
  } catch (error) {
    console.error('Error getting session:', error);
  }
  return null;
}

/**
 * Сохраняет сессию
 */
async function saveSession(phone, session) {
  const filePath = path.join(SESSIONS_DIR, `${phone}.json`);
  await writeJsonFile(filePath, session);

  if (USE_DB) {
    try { await db.upsert('auth_sessions', { phone: phone, session_token: session.sessionToken || '', data: session, updated_at: new Date().toISOString() }, 'phone'); }
    catch (dbErr) { console.error('DB save auth_session error:', dbErr.message); }
  }
}

/**
 * Удаляет сессию
 */
async function deleteSession(phone) {
  const filePath = path.join(SESSIONS_DIR, `${phone}.json`);
  try {
    await fs.unlink(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }

  if (USE_DB) {
    try { await db.query('DELETE FROM auth_sessions WHERE phone = $1', [phone]); }
    catch (dbErr) { console.error('DB delete auth_session error:', dbErr.message); }
  }
}

/**
 * POST /api/auth/register
 * Простая регистрация с PIN (без OTP)
 */
router.post('/register', async (req, res) => {
  try {
    const { phone, name, pin, deviceId, deviceName } = req.body;

    if (!phone || !name || !pin) {
      return res.status(400).json({ error: 'Требуются phone, name и pin' });
    }

    const normalizedPhone = normalizePhone(phone);

    if (normalizedPhone.length !== 11) {
      return res.status(400).json({ error: 'Неверный формат номера телефона' });
    }

    if (pin.length < 4 || pin.length > 6) {
      return res.status(400).json({ error: 'PIN должен быть от 4 до 6 цифр' });
    }

    // SECURITY: Регистрация только для известных пользователей (сотрудники или клиенты)
    const employees = dataCache.getEmployees();
    let phoneKnown = false;

    // 1. Проверяем в списке сотрудников
    if (employees) {
      phoneKnown = employees.some(e => {
        const empPhone = (e.phone || '').replace(/[^\d]/g, '');
        return empPhone === normalizedPhone;
      });
    }

    // 2. Если не сотрудник — проверяем в клиентах (они регистрируются через RegistrationPage)
    if (!phoneKnown) {
      try {
        if (USE_DB) {
          const row = await db.findById('clients', normalizedPhone, 'phone');
          if (row) phoneKnown = true;
        }
        if (!phoneKnown) {
          const clientFile = path.join(DATA_DIR, 'clients', `${normalizedPhone}.json`);
          try { await fs.access(clientFile); phoneKnown = true; } catch (_) {}
        }
      } catch (e) {
        console.error('[Auth] Error checking clients:', e.message);
      }
    }

    if (!phoneKnown) {
      return res.status(403).json({ error: 'Сначала пройдите регистрацию в приложении.' });
    }

    // Проверяем, не зарегистрирован ли уже пользователь
    const existingPin = await getPinData(normalizedPhone);
    if (existingPin) {
      return res.status(409).json({ error: 'Пользователь уже зарегистрирован. Используйте функцию входа.' });
    }

    // Создаём PIN (bcrypt если доступен, иначе SHA-256)
    let pinHash, salt, hashType;
    if (bcrypt) {
      pinHash = await bcrypt.hash(pin, BCRYPT_ROUNDS);
      salt = '';
      hashType = 'bcrypt';
    } else {
      salt = generateSalt();
      pinHash = hashPinSha256(pin, salt);
      hashType = 'sha256';
    }

    const pinData = {
      phone: normalizedPhone,
      name,
      pinHash,
      salt,
      hashType,
      biometricEnabled: false,
      failedAttempts: 0,
      lockedUntil: null,
      createdAt: Date.now(),
      updatedAt: Date.now()
    };

    await savePinData(normalizedPhone, pinData);

    // Создаём сессию
    const sessionToken = generateSessionToken();
    const session = {
      sessionToken,
      phone: normalizedPhone,
      name,
      deviceId: deviceId || 'unknown',
      deviceName: deviceName || 'Unknown Device',
      createdAt: Date.now(),
      expiresAt: Date.now() + SESSION_LIFETIME_MS,
      isVerified: true
    };

    await saveSession(normalizedPhone, session);
    addTokenToIndex(sessionToken, normalizedPhone, name, session.expiresAt);

    console.log(`✅ User registered: ${normalizedPhone}`);

    res.json({
      success: true,
      message: 'Регистрация успешна',
      // pinHash и salt НЕ отправляем клиенту (безопасность)
      // Flutter создаёт локальные credentials через createCredentials(pin)
      session: {
        sessionToken,
        phone: normalizedPhone,
        name,
        deviceId: deviceId || 'unknown',
        deviceName: deviceName || 'Unknown Device',
        createdAt: session.createdAt,
        expiresAt: session.expiresAt,
        isVerified: true
      }
    });

  } catch (error) {
    console.error('Registration error:', error);
    res.status(500).json({ error: 'Ошибка регистрации' });
  }
});

/**
 * POST /api/auth/login
 * Вход с PIN-кодом
 */
router.post('/login', async (req, res) => {
  try {
    const { phone, pin, deviceId, deviceName } = req.body;

    if (!phone || !pin) {
      return res.status(400).json({ error: 'Требуются phone и pin' });
    }

    const normalizedPhone = normalizePhone(phone);

    // File lock для атомарности PIN-проверки (защита от race condition при brute-force)
    const pinLockPath = path.join(PINS_DIR, `${normalizedPhone}.lock`);
    const result = await withLock(pinLockPath, async () => {
      const pinData = await getPinData(normalizedPhone);

      if (!pinData) {
        return { status: 404, body: { error: 'Пользователь не найден. Необходима регистрация.' } };
      }

      // Проверяем блокировку
      if (pinData.lockedUntil && Date.now() < pinData.lockedUntil) {
        const remainingMinutes = Math.ceil((pinData.lockedUntil - Date.now()) / 60000);
        return { status: 423, body: { error: `Аккаунт заблокирован. Попробуйте через ${remainingMinutes} мин.`, lockedUntil: pinData.lockedUntil } };
      }

      // Проверяем PIN (поддержка bcrypt и SHA-256)
      const { valid, needsMigration } = await verifyPin(pin, pinData);
      if (!valid) {
        pinData.failedAttempts++;

        if (pinData.failedAttempts >= MAX_PIN_ATTEMPTS) {
          pinData.lockedUntil = Date.now() + LOCKOUT_DURATION_MS;
          pinData.failedAttempts = 0;
          await savePinData(normalizedPhone, pinData);
          return { status: 423, body: { error: 'Превышено количество попыток. Аккаунт заблокирован на 15 минут.', lockedUntil: pinData.lockedUntil } };
        }

        await savePinData(normalizedPhone, pinData);
        const remaining = MAX_PIN_ATTEMPTS - pinData.failedAttempts;
        return { status: 401, body: { error: `Неверный PIN-код. Осталось попыток: ${remaining}`, attemptsRemaining: remaining } };
      }

      // PIN верный - сбрасываем счётчик попыток
      pinData.failedAttempts = 0;
      pinData.lockedUntil = null;
      await savePinData(normalizedPhone, pinData);

      // Автомиграция на bcrypt
      if (needsMigration) {
        migratePinToBcrypt(normalizedPhone, pin, pinData).catch(() => {});
      }

      return { status: 200, pinData };
    });

    // Обработка результата из lock-блока
    if (result.status !== 200) {
      return res.status(result.status).json(result.body);
    }

    // Создаём или обновляем сессию
    const sessionToken = generateSessionToken();
    const session = {
      sessionToken,
      phone: normalizedPhone,
      name: result.pinData.name,
      deviceId: deviceId || 'unknown',
      deviceName: deviceName || 'Unknown Device',
      createdAt: Date.now(),
      expiresAt: Date.now() + SESSION_LIFETIME_MS,
      isVerified: true
    };

    await saveSession(normalizedPhone, session);
    addTokenToIndex(sessionToken, normalizedPhone, result.pinData.name, session.expiresAt);

    console.log(`✅ User logged in: ${normalizedPhone}`);

    res.json({
      success: true,
      sessionToken,
      expiresAt: session.expiresAt,
      name: result.pinData.name,
      biometricEnabled: result.pinData.biometricEnabled
    });

  } catch (error) {
    console.error('Login error:', error);
    res.status(500).json({ error: 'Ошибка входа' });
  }
});

/**
 * POST /api/auth/request-otp
 * Запрос OTP через Telegram (для сброса PIN)
 */
router.post('/request-otp', async (req, res) => {
  try {
    const { phone } = req.body;

    if (!phone) {
      return res.status(400).json({ error: 'Требуется phone' });
    }

    const normalizedPhone = normalizePhone(phone);

    // Проверяем, зарегистрирован ли пользователь
    const pinData = await getPinData(normalizedPhone);
    if (!pinData) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    // Возвращаем инструкции для Telegram-бота
    // Реальный OTP будет отправлен через Telegram-бота
    res.json({
      success: true,
      message: 'Откройте Telegram-бота @ArabicaAuthBot26_bot и нажмите "Получить код"',
      telegramBotUrl: 'https://t.me/ArabicaAuthBot26_bot',
      phone: normalizedPhone
    });

  } catch (error) {
    console.error('Request OTP error:', error);
    res.status(500).json({ error: 'Ошибка запроса OTP' });
  }
});

/**
 * POST /api/auth/verify-otp
 * Проверка OTP кода
 */
router.post('/verify-otp', async (req, res) => {
  try {
    const { phone, code } = req.body;

    if (!phone || !code) {
      return res.status(400).json({ error: 'Требуются phone и code' });
    }

    const normalizedPhone = normalizePhone(phone);

    // Используем telegram_bot_service для верификации
    const telegramService = require('../services/telegram_bot_service');
    const result = await telegramService.verifyOtp(normalizedPhone, code);

    if (!result.success) {
      return res.status(400).json({ error: result.error });
    }

    res.json({
      success: true,
      registrationToken: result.registrationToken,
      message: 'Код подтверждён'
    });

  } catch (error) {
    console.error('Verify OTP error:', error);
    res.status(500).json({ error: 'Ошибка проверки кода' });
  }
});

/**
 * POST /api/auth/reset-pin
 * Сброс PIN после верификации OTP
 */
router.post('/reset-pin', async (req, res) => {
  try {
    const { phone, pin, registrationToken, deviceId, deviceName } = req.body;

    if (!phone || !pin || !registrationToken) {
      return res.status(400).json({ error: 'Требуются phone, pin и registrationToken' });
    }

    const normalizedPhone = normalizePhone(phone);

    // Проверяем токен регистрации
    const telegramService = require('../services/telegram_bot_service');
    const isValidToken = await telegramService.verifyRegistrationToken(normalizedPhone, registrationToken);

    if (!isValidToken) {
      return res.status(401).json({ error: 'Недействительный или истёкший токен' });
    }

    // Получаем существующие данные пользователя
    const pinData = await getPinData(normalizedPhone);
    if (!pinData) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    // Обновляем PIN (bcrypt если доступен)
    if (bcrypt) {
      pinData.pinHash = await bcrypt.hash(pin, BCRYPT_ROUNDS);
      pinData.salt = '';
      pinData.hashType = 'bcrypt';
    } else {
      const salt = generateSalt();
      pinData.pinHash = hashPinSha256(pin, salt);
      pinData.salt = salt;
      pinData.hashType = 'sha256';
    }
    pinData.failedAttempts = 0;
    pinData.lockedUntil = null;
    pinData.updatedAt = Date.now();

    await savePinData(normalizedPhone, pinData);

    // Удаляем OTP после использования
    await telegramService.deleteOtp(normalizedPhone);

    // Создаём новую сессию
    const sessionToken = generateSessionToken();
    const session = {
      sessionToken,
      phone: normalizedPhone,
      name: pinData.name,
      deviceId: deviceId || 'unknown',
      deviceName: deviceName || 'Unknown Device',
      createdAt: Date.now(),
      expiresAt: Date.now() + SESSION_LIFETIME_MS,
      isVerified: true
    };

    await saveSession(normalizedPhone, session);
    addTokenToIndex(sessionToken, normalizedPhone, pinData.name, session.expiresAt);

    console.log(`✅ PIN reset for: ${normalizedPhone}`);

    res.json({
      success: true,
      sessionToken,
      expiresAt: session.expiresAt,
      message: 'PIN-код успешно изменён'
    });

  } catch (error) {
    console.error('Reset PIN error:', error);
    res.status(500).json({ error: 'Ошибка сброса PIN' });
  }
});

/**
 * POST /api/auth/validate-session
 * Проверка действительности сессии
 */
router.post('/validate-session', async (req, res) => {
  try {
    const { sessionToken } = req.body;

    if (!sessionToken) {
      return res.status(400).json({ error: 'Требуется sessionToken' });
    }

    const session = await getSessionByToken(sessionToken);

    if (!session) {
      return res.status(401).json({ valid: false, error: 'Сессия не найдена' });
    }

    if (Date.now() > session.expiresAt) {
      return res.status(401).json({ valid: false, error: 'Сессия истекла' });
    }

    // Получаем данные пользователя
    const pinData = await getPinData(session.phone);

    res.json({
      valid: true,
      phone: session.phone,
      name: pinData?.name || session.name,
      expiresAt: session.expiresAt,
      biometricEnabled: pinData?.biometricEnabled || false
    });

  } catch (error) {
    console.error('Validate session error:', error);
    res.status(500).json({ error: 'Ошибка проверки сессии' });
  }
});

/**
 * POST /api/auth/logout
 * Выход из системы
 * SECURITY: Logout by sessionToken — token is proof of ownership (secure).
 * Logout by phone — requires caller to authenticate via Authorization header
 * and be the same user or admin (prevents forced logout of other users).
 */
router.post('/logout', async (req, res) => {
  try {
    const { sessionToken, phone } = req.body;

    if (sessionToken) {
      // Logout by sessionToken — token itself is proof of ownership
      const session = await getSessionByToken(sessionToken);
      if (session) {
        removeTokenFromIndex(sessionToken);
        await deleteSession(session.phone);
        console.log(`✅ User logged out: ${maskPhone(session.phone)}`);
      }
      return res.json({ success: true, message: 'Выход выполнен' });
    }

    if (phone) {
      // Logout by phone — requires caller authentication
      const authHeader = req.headers['authorization'];
      const callerToken = authHeader && authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;

      if (!callerToken) {
        return res.status(401).json({ error: 'Требуется авторизация для выхода по номеру телефона' });
      }

      const callerSession = await getSessionByToken(callerToken);
      if (!callerSession || (callerSession.expiresAt && Date.now() > callerSession.expiresAt)) {
        return res.status(401).json({ error: 'Недействительная сессия' });
      }

      const normalizedPhone = normalizePhone(phone);

      // Only allow: logout yourself OR admin can logout anyone
      if (callerSession.phone !== normalizedPhone && !isAdminPhone(callerSession.phone)) {
        return res.status(403).json({ error: 'Можно выйти только из своего аккаунта' });
      }

      removePhoneFromIndex(normalizedPhone);
      await deleteSession(normalizedPhone);
      console.log(`✅ User logged out by ${callerSession.phone === normalizedPhone ? 'self' : 'admin'}: ${maskPhone(normalizedPhone)}`);
      return res.json({ success: true, message: 'Выход выполнен' });
    }

    res.json({ success: true, message: 'Выход выполнен' });

  } catch (error) {
    console.error('Logout error:', error);
    res.status(500).json({ error: 'Ошибка выхода' });
  }
});

/**
 * POST /api/auth/enable-biometric
 * Включение/выключение биометрии
 * SECURITY: Требуем авторизацию — только владелец аккаунта или админ
 */
router.post('/enable-biometric', requireAuth, async (req, res) => {
  try {
    const { phone, enabled } = req.body;

    if (!phone || enabled === undefined) {
      return res.status(400).json({ error: 'Требуются phone и enabled' });
    }

    const normalizedPhone = normalizePhone(phone);

    // SECURITY: Только владелец аккаунта или админ может менять биометрию
    const userPhone = normalizePhone(req.user.phone);
    if (userPhone !== normalizedPhone && !req.user.isAdmin) {
      return res.status(403).json({ error: 'Нельзя менять настройки чужого аккаунта' });
    }

    const pinData = await getPinData(normalizedPhone);

    if (!pinData) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }

    pinData.biometricEnabled = enabled;
    pinData.updatedAt = Date.now();

    await savePinData(normalizedPhone, pinData);

    console.log(`✅ Biometric ${enabled ? 'enabled' : 'disabled'} for: ${normalizedPhone}`);

    res.json({
      success: true,
      biometricEnabled: enabled,
      message: enabled ? 'Биометрия включена' : 'Биометрия выключена'
    });

  } catch (error) {
    console.error('Enable biometric error:', error);
    res.status(500).json({ error: 'Ошибка изменения настроек биометрии' });
  }
});

/**
 * GET /api/auth/session/:phone
 * Получить информацию о сессии пользователя (только для админов)
 */
router.get('/session/:phone', requireAdmin, async (req, res) => {
  try {
    const normalizedPhone = normalizePhone(req.params.phone);
    const filePath = path.join(SESSIONS_DIR, `${normalizedPhone}.json`);

    try {
      const data = await fs.readFile(filePath, 'utf8');
      const session = JSON.parse(data);

      // Скрываем токен для безопасности
      res.json({
        phone: session.phone,
        name: session.name,
        deviceName: session.deviceName,
        createdAt: session.createdAt,
        expiresAt: session.expiresAt,
        isVerified: session.isVerified,
        isActive: Date.now() < session.expiresAt
      });
    } catch (error) {
      if (error.code === 'ENOENT') {
        return res.status(404).json({ error: 'Сессия не найдена' });
      }
      throw error;
    }

  } catch (error) {
    console.error('Get session error:', error);
    res.status(500).json({ error: 'Ошибка получения сессии' });
  }
});

// ============================================
// POST /api/auth/refresh-session
// Обновляет lastActivity сессии (вызывается Flutter при каждом входе)
// ============================================
router.post('/refresh-session', async (req, res) => {
  try {
    // Получаем токен из Authorization header или body
    const authHeader = req.headers['authorization'];
    const tokenFromHeader = authHeader && authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
    const tokenFromBody = req.body && req.body.sessionToken;
    const sessionToken = tokenFromHeader || tokenFromBody;

    if (!sessionToken) {
      return res.status(401).json({ error: 'Токен сессии не указан' });
    }

    // Ищем сессию по токену
    const session = await getSessionByToken(sessionToken);
    if (!session) {
      return res.status(404).json({ error: 'Сессия не найдена' });
    }

    // Проверяем истечение
    if (session.expiresAt && Date.now() > session.expiresAt) {
      return res.status(401).json({ error: 'Сессия истекла' });
    }

    // Обновляем lastActivity
    session.lastActivity = Date.now();
    await saveSession(session.phone, session);

    res.json({
      success: true,
      message: 'Сессия обновлена',
      expiresAt: session.expiresAt
    });

  } catch (error) {
    console.error('Refresh session error:', error);
    res.status(500).json({ error: 'Ошибка обновления сессии' });
  }
});

/**
 * POST /api/auth/change-pin
 * Смена PIN-кода (требуется авторизация + старый PIN)
 */
router.post('/change-pin', requireAuth, async (req, res) => {
  try {
    const { oldPin, newPin } = req.body;

    if (!oldPin || !newPin) {
      return res.status(400).json({ error: 'Требуются oldPin и newPin' });
    }

    const normalizedPhone = normalizePhone(req.user.phone);

    // File lock для атомарности
    const pinLockPath = path.join(PINS_DIR, `${normalizedPhone}.lock`);
    const result = await withLock(pinLockPath, async () => {
      const pinData = await getPinData(normalizedPhone);

      if (!pinData) {
        return { status: 404, body: { error: 'Пользователь не найден' } };
      }

      // Проверяем блокировку
      if (pinData.lockedUntil && Date.now() < pinData.lockedUntil) {
        const remainingMinutes = Math.ceil((pinData.lockedUntil - Date.now()) / 60000);
        return { status: 423, body: { error: `Аккаунт заблокирован. Попробуйте через ${remainingMinutes} мин.` } };
      }

      // Проверяем старый PIN
      const { valid } = await verifyPin(oldPin, pinData);
      if (!valid) {
        pinData.failedAttempts++;
        if (pinData.failedAttempts >= MAX_PIN_ATTEMPTS) {
          pinData.lockedUntil = Date.now() + LOCKOUT_DURATION_MS;
          pinData.failedAttempts = 0;
          await savePinData(normalizedPhone, pinData);
          return { status: 423, body: { error: 'Превышено количество попыток. Аккаунт заблокирован на 15 минут.' } };
        }
        await savePinData(normalizedPhone, pinData);
        const remaining = MAX_PIN_ATTEMPTS - pinData.failedAttempts;
        return { status: 401, body: { error: `Неверный старый PIN-код. Осталось попыток: ${remaining}` } };
      }

      // Старый PIN верный — обновляем на новый
      pinData.failedAttempts = 0;
      pinData.lockedUntil = null;

      if (bcrypt) {
        pinData.pinHash = await bcrypt.hash(newPin, BCRYPT_ROUNDS);
        pinData.salt = '';
        pinData.hashType = 'bcrypt';
      } else {
        const salt = generateSalt();
        pinData.pinHash = hashPinSha256(newPin, salt);
        pinData.salt = salt;
        pinData.hashType = 'sha256';
      }
      pinData.updatedAt = Date.now();

      await savePinData(normalizedPhone, pinData);
      return { status: 200 };
    });

    if (result.status !== 200) {
      return res.status(result.status).json(result.body);
    }

    console.log(`✅ PIN changed for: ${normalizedPhone}`);
    res.json({ success: true, message: 'PIN-код успешно изменён' });

  } catch (error) {
    console.error('Change PIN error:', error);
    res.status(500).json({ error: 'Ошибка смены PIN' });
  }
});

module.exports = router;
