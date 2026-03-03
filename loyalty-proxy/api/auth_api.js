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
const DEVICE_BINDING_ENABLED = process.env.DEVICE_BINDING_ENABLED === 'true';

// Конфигурация
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SESSIONS_DIR = path.join(DATA_DIR, 'auth-sessions');
const PINS_DIR = path.join(DATA_DIR, 'auth-pins');
const OTP_DIR = path.join(DATA_DIR, 'auth-otp');
const TRUSTED_DEVICES_DIR = path.join(DATA_DIR, 'trusted-devices');
const DEVICE_APPROVAL_DIR = path.join(DATA_DIR, 'device-approval-requests');

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
  await fs.mkdir(TRUSTED_DEVICES_DIR, { recursive: true });
  await fs.mkdir(DEVICE_APPROVAL_DIR, { recursive: true });
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
 * Ищет имя пользователя по номеру телефона (сотрудники → клиенты → JSON pin file)
 */
async function resolveUserName(phone) {
  // 1. Сотрудники (из кэша в памяти — быстро)
  const employees = dataCache.getEmployees();
  if (employees) {
    const emp = employees.find(e => (e.phone || '').replace(/[^\d]/g, '') === phone);
    if (emp && emp.name) return emp.name;
  }
  // 2. Клиенты (из базы)
  try {
    const client = await db.findById('clients', phone, 'phone');
    if (client && client.name) return client.name;
  } catch (_) {}
  // 3. JSON pin file (хранит name с регистрации)
  try {
    const filePath = path.join(PINS_DIR, `${phone}.json`);
    const data = await fs.readFile(filePath, 'utf8');
    const json = JSON.parse(data);
    if (json.name) return json.name;
  } catch (_) {}
  return null;
}

/**
 * Получает данные PIN по номеру телефона
 */
async function getPinData(phone) {
  if (USE_DB) {
    const row = await db.findById('auth_pins', phone, 'phone');
    if (!row) return null;
    // Name is not stored in auth_pins table, resolve it separately
    const name = await resolveUserName(phone);
    // Map real DB columns to the expected JSON format used throughout auth_api.js
    return {
      pinHash: row.pin_hash,
      hashType: row.hash_type || 'bcrypt',
      salt: row.salt || null,
      name,
      failedAttempts: row.failed_attempts || 0,
      lockedUntil: row.locked_until ? new Date(row.locked_until).getTime() : null,
    };
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
    // Map JSON fields to real DB column names (auth_pins table)
    try {
      await db.upsert('auth_pins', {
        phone: phone,
        pin_hash: data.pinHash || data.pin_hash || '',
        hash_type: data.hashType || data.hash_type || 'bcrypt',
        salt: data.salt || null,
        failed_attempts: data.failedAttempts || data.failed_attempts || 0,
        locked_until: data.lockedUntil ? new Date(data.lockedUntil).toISOString() : null,
      }, 'phone');
    }
    catch (dbErr) { console.error('DB save auth_pin error:', dbErr.message); }
  }
}

/**
 * Получает сессию по токену
 */
async function getSessionByToken(token) {
  try {
    if (USE_DB) {
      // Query real column names (auth_sessions has no 'data' column)
      const result = await db.query(
        'SELECT session_token, phone, is_admin, employee_id, expires_at FROM auth_sessions WHERE session_token = $1 LIMIT 1',
        [token]
      );
      if (result.rows && result.rows.length > 0) {
        const row = result.rows[0];
        return {
          sessionToken: row.session_token,
          phone: row.phone,
          name: null,  // Not stored in DB schema; caller falls back to pinData.name
          isAdmin: row.is_admin || false,
          employeeId: row.employee_id || null,
          expiresAt: row.expires_at ? new Date(row.expires_at).getTime() : 0,
        };
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
    // Map session fields to real DB column names (auth_sessions table)
    try {
      await db.upsert('auth_sessions', {
        phone: phone,
        session_token: session.sessionToken || '',
        employee_id: session.employeeId || null,
        is_admin: session.isAdmin || false,
        expires_at: session.expiresAt ? new Date(session.expiresAt).toISOString() : null,
      }, 'phone');
    }
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

// ============================================
// Device Binding: Trusted Device helpers
// ============================================

/**
 * Получает данные доверенного устройства пользователя
 */
async function getTrustedDevice(phone) {
  if (USE_DB) {
    try {
      const row = await db.findById('trusted_devices', phone, 'phone');
      if (row) return { phone: row.phone, device_id: row.device_id, device_name: row.device_name, trusted_at: row.trusted_at, trusted_via: row.trusted_via };
    } catch (e) {
      console.error('[Auth] DB getTrustedDevice error:', e.message);
    }
  }
  const filePath = path.join(TRUSTED_DEVICES_DIR, `${phone}.json`);
  try {
    const data = await fs.readFile(filePath, 'utf8');
    return JSON.parse(data);
  } catch (e) {
    if (e.code === 'ENOENT') return null;
    throw e;
  }
}

/**
 * Сохраняет доверенное устройство (dual-write: JSON + DB)
 */
async function saveTrustedDevice(phone, deviceId, deviceName, trustedVia = 'auto') {
  const data = {
    phone,
    device_id: deviceId,
    device_name: deviceName || 'Unknown Device',
    trusted_at: new Date().toISOString(),
    trusted_via: trustedVia,
  };
  await writeJsonFile(path.join(TRUSTED_DEVICES_DIR, `${phone}.json`), data);
  if (USE_DB) {
    try { await db.upsert('trusted_devices', data, 'phone'); }
    catch (e) { console.error('[Auth] DB saveTrustedDevice error:', e.message); }
  }
}

/**
 * Получает телефоны разработчиков (для push-уведомлений о новых устройствах)
 */
async function getDeveloperPhones() {
  const phones = [];
  const employees = dataCache.getEmployees();
  if (employees) {
    for (const emp of employees) {
      if (emp.role === 'developer' && emp.phone) {
        phones.push((emp.phone || '').replace(/[^\d]/g, ''));
      }
    }
  }
  return phones;
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

    // Device binding: auto-trust device on registration
    if (DEVICE_BINDING_ENABLED) {
      await saveTrustedDevice(normalizedPhone, deviceId || 'unknown', deviceName || 'Unknown Device', 'auto');
      console.log(`[Auth] Device auto-trusted on registration: ${maskPhone(normalizedPhone)}`);
    }

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

    // === DEVICE BINDING CHECK ===
    if (DEVICE_BINDING_ENABLED) {
      const trustedDevice = await getTrustedDevice(normalizedPhone);
      const currentDeviceId = deviceId || 'unknown';

      if (!trustedDevice) {
        // Migration: first login after feature enabled → auto-trust
        await saveTrustedDevice(normalizedPhone, currentDeviceId, deviceName || 'Unknown Device', 'migration');
        console.log(`[Auth] Device auto-trusted (migration): ${maskPhone(normalizedPhone)}`);
      } else if (trustedDevice.device_id !== currentDeviceId) {
        // NEW DEVICE DETECTED → block login
        console.log(`[Auth] New device detected for ${maskPhone(normalizedPhone)}: expected=${trustedDevice.device_id.substring(0, 8)}..., got=${currentDeviceId.substring(0, 8)}...`);
        return res.status(403).json({
          error: 'Обнаружено новое устройство. Подтвердите вход.',
          code: 'NEW_DEVICE_DETECTED',
          phone: normalizedPhone,
          deviceId: currentDeviceId,
          deviceName: deviceName || 'Unknown Device',
        });
      }
      // else: same device → proceed normally
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

    // Device binding: update trusted device after PIN reset (user proved identity via OTP)
    if (DEVICE_BINDING_ENABLED) {
      await saveTrustedDevice(normalizedPhone, deviceId || 'unknown', deviceName || 'Unknown Device', 'otp');
      console.log(`[Auth] Device trusted after PIN reset: ${maskPhone(normalizedPhone)}`);
    }

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

// ============================================
// Device Binding: New endpoints
// ============================================

/**
 * POST /api/auth/verify-device-otp
 * Подтверждение нового устройства через OTP (Telegram)
 * Body: { phone, code, deviceId, deviceName, pin }
 */
router.post('/verify-device-otp', async (req, res) => {
  try {
    const { phone, code, deviceId, deviceName, pin } = req.body;
    if (!phone || !code || !deviceId || !pin) {
      return res.status(400).json({ error: 'Требуются phone, code, deviceId и pin' });
    }

    const normalizedPhone = normalizePhone(phone);

    // Verify OTP
    const telegramService = require('../services/telegram_bot_service');
    const otpResult = await telegramService.verifyOtp(normalizedPhone, code);
    if (!otpResult.success) {
      return res.status(400).json({ error: otpResult.error });
    }

    // Re-verify PIN (security: don't trust that PIN was valid from a previous request)
    const pinData = await getPinData(normalizedPhone);
    if (!pinData) {
      return res.status(404).json({ error: 'Пользователь не найден' });
    }
    const { valid } = await verifyPin(pin, pinData);
    if (!valid) {
      return res.status(401).json({ error: 'Неверный PIN-код' });
    }

    // Trust the new device
    await saveTrustedDevice(normalizedPhone, deviceId, deviceName || 'Unknown Device', 'otp');

    // Delete OTP after use
    await telegramService.deleteOtp(normalizedPhone);

    // Create session (same as login)
    const sessionToken = generateSessionToken();
    const session = {
      sessionToken,
      phone: normalizedPhone,
      name: pinData.name,
      deviceId,
      deviceName: deviceName || 'Unknown Device',
      createdAt: Date.now(),
      expiresAt: Date.now() + SESSION_LIFETIME_MS,
      isVerified: true
    };

    await saveSession(normalizedPhone, session);
    addTokenToIndex(sessionToken, normalizedPhone, pinData.name, session.expiresAt);

    console.log(`✅ Device trusted via OTP: ${maskPhone(normalizedPhone)}`);

    res.json({
      success: true,
      sessionToken,
      expiresAt: session.expiresAt,
      name: pinData.name,
      biometricEnabled: pinData.biometricEnabled
    });
  } catch (error) {
    console.error('Verify device OTP error:', error);
    res.status(500).json({ error: 'Ошибка верификации устройства' });
  }
});

/**
 * POST /api/auth/request-device-approval
 * Запрос подтверждения нового устройства от разработчика
 * Body: { phone, deviceId, deviceName }
 */
router.post('/request-device-approval', async (req, res) => {
  try {
    const { phone, deviceId, deviceName } = req.body;
    if (!phone || !deviceId) {
      return res.status(400).json({ error: 'Требуются phone и deviceId' });
    }

    const normalizedPhone = normalizePhone(phone);
    const userName = await resolveUserName(normalizedPhone);

    // Check if there's already a pending request for this phone
    if (USE_DB) {
      try {
        const existing = await db.query(
          "SELECT id FROM device_approval_requests WHERE phone = $1 AND status = 'pending' LIMIT 1",
          [normalizedPhone]
        );
        if (existing.rows && existing.rows.length > 0) {
          return res.json({
            success: true,
            requestId: existing.rows[0].id,
            message: 'Запрос уже отправлен. Ожидайте подтверждения.'
          });
        }
      } catch (e) {
        console.error('[Auth] DB check pending request error:', e.message);
      }
    }

    // Fetch old trusted device info to include in request
    const trustedDevice = await getTrustedDevice(normalizedPhone);
    const oldDeviceName = trustedDevice ? trustedDevice.device_name : null;

    const requestId = `devreq_${Date.now()}_${crypto.randomBytes(4).toString('hex')}`;
    const requestData = {
      id: requestId,
      phone: normalizedPhone,
      device_id: deviceId,
      device_name: deviceName || 'Unknown Device',
      old_device_name: oldDeviceName,
      user_name: userName || normalizedPhone,
      status: 'pending',
      created_at: new Date().toISOString(),
    };

    // Dual-write
    await writeJsonFile(path.join(DEVICE_APPROVAL_DIR, `${requestId}.json`), requestData);
    if (USE_DB) {
      try { await db.upsert('device_approval_requests', requestData); }
      catch (e) { console.error('[Auth] DB save device_approval error:', e.message); }
    }

    // Send push notification to developers only
    try {
      const pushService = require('../utils/push_service');
      const devPhones = await getDeveloperPhones();
      for (const devPhone of devPhones) {
        await pushService.sendPushToPhone(
          devPhone,
          'Запрос на новое устройство',
          `${userName || normalizedPhone} хочет войти с нового устройства (${deviceName || 'Unknown'})`,
          { type: 'device_approval_request', requestId, phone: normalizedPhone },
          'default_channel'
        );
      }
    } catch (pushErr) {
      console.error('[Auth] Push to developers error:', pushErr.message);
    }

    console.log(`[Auth] Device approval requested: ${maskPhone(normalizedPhone)}, id=${requestId}`);

    res.json({
      success: true,
      requestId,
      message: 'Запрос отправлен разработчику. Вы получите уведомление.'
    });
  } catch (error) {
    console.error('Request device approval error:', error);
    res.status(500).json({ error: 'Ошибка отправки запроса' });
  }
});

/**
 * GET /api/auth/device-approval-requests
 * Список ожидающих запросов на подтверждение устройства (только для разработчиков)
 */
router.get('/device-approval-requests', requireAuth, async (req, res) => {
  try {
    const { isDeveloper } = require('./shop_managers_api');
    if (!(await isDeveloper(req.user.phone))) {
      return res.status(403).json({ error: 'Только разработчик может просматривать запросы' });
    }

    let requests = [];
    if (USE_DB) {
      try {
        const result = await db.query(
          "SELECT * FROM device_approval_requests WHERE status = 'pending' ORDER BY created_at DESC"
        );
        requests = result.rows || [];
      } catch (e) {
        console.error('[Auth] DB get device_approval_requests error:', e.message);
      }
    }

    // Fallback / supplement from JSON
    if (requests.length === 0) {
      try {
        const files = await fs.readdir(DEVICE_APPROVAL_DIR);
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          try {
            const data = JSON.parse(await fs.readFile(path.join(DEVICE_APPROVAL_DIR, file), 'utf8'));
            if (data.status === 'pending') requests.push(data);
          } catch (_) {}
        }
        requests.sort((a, b) => new Date(b.created_at) - new Date(a.created_at));
      } catch (_) {}
    }

    res.json({ requests });
  } catch (error) {
    console.error('Get device approval requests error:', error);
    res.status(500).json({ error: 'Ошибка получения запросов' });
  }
});

/**
 * POST /api/auth/resolve-device-approval
 * Разработчик одобряет или отклоняет запрос на новое устройство
 * Body: { requestId, action: 'approve' | 'reject' }
 */
router.post('/resolve-device-approval', requireAuth, async (req, res) => {
  try {
    const { requestId, action } = req.body;
    if (!requestId || !['approve', 'reject'].includes(action)) {
      return res.status(400).json({ error: 'Требуются requestId и action (approve/reject)' });
    }

    const { isDeveloper } = require('./shop_managers_api');
    if (!(await isDeveloper(req.user.phone))) {
      return res.status(403).json({ error: 'Только разработчик может обрабатывать запросы' });
    }

    // Load request from DB or JSON
    let requestData;
    if (USE_DB) {
      try {
        const result = await db.query('SELECT * FROM device_approval_requests WHERE id = $1', [requestId]);
        requestData = result.rows && result.rows[0];
      } catch (e) {
        console.error('[Auth] DB load device_approval error:', e.message);
      }
    }
    if (!requestData) {
      try {
        requestData = JSON.parse(await fs.readFile(path.join(DEVICE_APPROVAL_DIR, `${requestId}.json`), 'utf8'));
      } catch (_) {}
    }

    if (!requestData || requestData.status !== 'pending') {
      return res.status(404).json({ error: 'Запрос не найден или уже обработан' });
    }

    // Update request status
    const newStatus = action === 'approve' ? 'approved' : 'rejected';
    const resolvedAt = new Date().toISOString();
    const resolvedBy = req.user.phone;

    requestData.status = newStatus;
    requestData.resolved_at = resolvedAt;
    requestData.resolved_by = resolvedBy;

    // Dual-write update
    await writeJsonFile(path.join(DEVICE_APPROVAL_DIR, `${requestId}.json`), requestData);
    if (USE_DB) {
      try {
        await db.query(
          'UPDATE device_approval_requests SET status=$1, resolved_at=$2, resolved_by=$3 WHERE id=$4',
          [newStatus, resolvedAt, resolvedBy, requestId]
        );
      } catch (e) { console.error('[Auth] DB update device_approval error:', e.message); }
    }

    const pushService = require('../utils/push_service');

    if (action === 'approve') {
      // Trust the device
      await saveTrustedDevice(
        requestData.phone,
        requestData.device_id,
        requestData.device_name,
        'developer_approval'
      );

      // Send push to the user
      await pushService.sendPushToPhone(
        requestData.phone,
        'Устройство подтверждено',
        'Ваше новое устройство подтверждено. Войдите в приложение.',
        { type: 'device_approved', requestId },
        'default_channel'
      );

      console.log(`✅ Device approved by ${maskPhone(req.user.phone)} for ${maskPhone(requestData.phone)}`);
    } else {
      // Send push: rejected
      await pushService.sendPushToPhone(
        requestData.phone,
        'Устройство отклонено',
        'Запрос на новое устройство отклонён. Обратитесь к руководству.',
        { type: 'device_rejected', requestId },
        'default_channel'
      );

      console.log(`❌ Device rejected by ${maskPhone(req.user.phone)} for ${maskPhone(requestData.phone)}`);
    }

    res.json({ success: true, message: action === 'approve' ? 'Устройство подтверждено' : 'Запрос отклонён' });
  } catch (error) {
    console.error('Resolve device approval error:', error);
    res.status(500).json({ error: 'Ошибка обработки запроса' });
  }
});

/**
 * GET /api/auth/device-approval-status/:phone
 * Проверка статуса запроса на подтверждение устройства (для polling)
 * Не требует авторизации — пользователь ещё не залогинен
 */
router.get('/device-approval-status/:phone', async (req, res) => {
  try {
    const normalizedPhone = normalizePhone(req.params.phone);

    let latest = null;
    if (USE_DB) {
      try {
        const result = await db.query(
          'SELECT * FROM device_approval_requests WHERE phone = $1 ORDER BY created_at DESC LIMIT 1',
          [normalizedPhone]
        );
        latest = result.rows && result.rows[0];
      } catch (e) {
        console.error('[Auth] DB device_approval_status error:', e.message);
      }
    }

    if (!latest) {
      try {
        const files = await fs.readdir(DEVICE_APPROVAL_DIR);
        for (const file of files) {
          if (!file.endsWith('.json')) continue;
          try {
            const data = JSON.parse(await fs.readFile(path.join(DEVICE_APPROVAL_DIR, file), 'utf8'));
            if (data.phone === normalizedPhone) {
              if (!latest || new Date(data.created_at) > new Date(latest.created_at)) {
                latest = data;
              }
            }
          } catch (_) {}
        }
      } catch (_) {}
    }

    res.json({ status: latest ? latest.status : 'none' });
  } catch (error) {
    console.error('Device approval status error:', error);
    res.status(500).json({ error: 'Ошибка получения статуса' });
  }
});

module.exports = router;
