/**
 * Telegram Bot Service для авторизации
 *
 * Функции:
 * - Отправка OTP-кодов для сброса PIN
 * - Верификация номера телефона
 */

const TelegramBot = require('node-telegram-bot-api');
const crypto = require('crypto');
const fs = require('fs').promises;
const path = require('path');

// Конфигурация
const BOT_TOKEN = process.env.TELEGRAM_BOT_TOKEN || '8525076367:AAFIM8T8xcIB3XWGdXqak5-Yek8zq_iX2yA';
const DATA_DIR = process.env.DATA_DIR || '/var/www';
const OTP_DIR = path.join(DATA_DIR, 'auth-otp');

// Время жизни OTP кода (5 минут)
const OTP_LIFETIME_MS = 5 * 60 * 1000;
// Максимум попыток ввода кода
const MAX_OTP_ATTEMPTS = 3;
// Cooldown между запросами кода (60 секунд)
const OTP_COOLDOWN_MS = 60 * 1000;

let bot = null;

/**
 * Инициализация бота
 */
async function initBot() {
  if (bot) return bot;

  try {
    // Создаём директорию для OTP если не существует
    await fs.mkdir(OTP_DIR, { recursive: true });

    bot = new TelegramBot(BOT_TOKEN, { polling: true });

    // Обработчик /start
    bot.onText(/\/start/, async (msg) => {
      const chatId = msg.chat.id;
      await bot.sendMessage(chatId,
        '👋 Добро пожаловать в Arabica Auth Bot!\n\n' +
        'Этот бот используется для сброса PIN-кода в приложении Arabica.\n\n' +
        '📱 Нажмите кнопку ниже, чтобы поделиться номером телефона и получить код подтверждения.',
        {
          reply_markup: {
            keyboard: [[{
              text: '📲 Получить код подтверждения',
              request_contact: true
            }]],
            resize_keyboard: true,
            one_time_keyboard: true
          }
        }
      );
    });

    // Обработчик получения контакта (номера телефона)
    bot.on('contact', async (msg) => {
      const chatId = msg.chat.id;
      const contact = msg.contact;

      // Проверяем, что пользователь поделился своим номером
      if (contact.user_id !== msg.from.id) {
        await bot.sendMessage(chatId, '❌ Пожалуйста, поделитесь своим номером телефона, а не чужим.');
        return;
      }

      let phone = contact.phone_number;
      // Нормализуем номер (убираем +, пробелы)
      phone = phone.replace(/[\s+]/g, '');
      // Если начинается с 8, меняем на 7
      if (phone.startsWith('8') && phone.length === 11) {
        phone = '7' + phone.substring(1);
      }

      try {
        // Проверяем cooldown
        const existingOtp = await getOtpByPhone(phone);
        if (existingOtp && !isOtpExpired(existingOtp)) {
          const remainingSeconds = Math.ceil((existingOtp.expiresAt - Date.now()) / 1000);
          if (remainingSeconds > (OTP_LIFETIME_MS / 1000 - OTP_COOLDOWN_MS / 1000)) {
            await bot.sendMessage(chatId,
              `⏳ Код уже отправлен. Подождите ${remainingSeconds} секунд перед повторным запросом.`
            );
            return;
          }
        }

        // Генерируем и сохраняем OTP
        const otp = generateOtp();
        await saveOtp(phone, otp, chatId);

        await bot.sendMessage(chatId,
          `✅ Ваш код подтверждения:\n\n` +
          `🔐 *${otp}*\n\n` +
          `Введите этот код в приложении Arabica.\n` +
          `⏱ Код действителен 5 минут.`,
          { parse_mode: 'Markdown' }
        );

        // Убираем клавиатуру
        await bot.sendMessage(chatId,
          '👆 Скопируйте код выше и вставьте в приложение.',
          {
            reply_markup: {
              remove_keyboard: true
            }
          }
        );

      } catch (error) {
        console.error('Error processing contact:', error);
        await bot.sendMessage(chatId, '❌ Произошла ошибка. Попробуйте позже.');
      }
    });

    // Обработчик команды /code (альтернативный способ)
    bot.onText(/\/code (.+)/, async (msg, match) => {
      const chatId = msg.chat.id;
      let phone = match[1].trim();

      // Нормализуем номер
      phone = phone.replace(/[\s+\-()]/g, '');
      if (phone.startsWith('8') && phone.length === 11) {
        phone = '7' + phone.substring(1);
      }
      if (!phone.startsWith('7')) {
        phone = '7' + phone;
      }

      if (phone.length !== 11) {
        await bot.sendMessage(chatId, '❌ Неверный формат номера. Пример: /code 79001234567');
        return;
      }

      try {
        const otp = generateOtp();
        await saveOtp(phone, otp, chatId);

        await bot.sendMessage(chatId,
          `✅ Код подтверждения для ${formatPhone(phone)}:\n\n` +
          `🔐 *${otp}*\n\n` +
          `⏱ Код действителен 5 минут.`,
          { parse_mode: 'Markdown' }
        );
      } catch (error) {
        console.error('Error generating code:', error);
        await bot.sendMessage(chatId, '❌ Произошла ошибка. Попробуйте позже.');
      }
    });

    console.log('✅ Telegram bot initialized');
    return bot;

  } catch (error) {
    console.error('❌ Failed to initialize Telegram bot:', error);
    throw error;
  }
}

/**
 * Генерирует 6-значный OTP код
 */
function generateOtp() {
  return crypto.randomInt(100000, 999999).toString();
}

/**
 * Сохраняет OTP код
 */
async function saveOtp(phone, code, chatId) {
  const otpData = {
    phone,
    code,
    chatId,
    createdAt: Date.now(),
    expiresAt: Date.now() + OTP_LIFETIME_MS,
    attempts: 0,
    verified: false
  };

  const filePath = path.join(OTP_DIR, `${phone}.json`);
  await fs.writeFile(filePath, JSON.stringify(otpData, null, 2));
  return otpData;
}

/**
 * Получает OTP по номеру телефона
 */
async function getOtpByPhone(phone) {
  const filePath = path.join(OTP_DIR, `${phone}.json`);
  try {
    const data = await fs.readFile(filePath, 'utf8');
    return JSON.parse(data);
  } catch (error) {
    if (error.code === 'ENOENT') return null;
    throw error;
  }
}

/**
 * Проверяет, истёк ли OTP
 */
function isOtpExpired(otp) {
  return Date.now() > otp.expiresAt;
}

/**
 * Верифицирует OTP код
 * @returns {Object} { success: boolean, error?: string, registrationToken?: string }
 */
async function verifyOtp(phone, code) {
  const otp = await getOtpByPhone(phone);

  if (!otp) {
    return { success: false, error: 'Код не найден. Запросите новый код.' };
  }

  if (otp.verified) {
    return { success: false, error: 'Код уже использован. Запросите новый.' };
  }

  if (isOtpExpired(otp)) {
    return { success: false, error: 'Код истёк. Запросите новый код.' };
  }

  if (otp.attempts >= MAX_OTP_ATTEMPTS) {
    return { success: false, error: 'Превышено количество попыток. Запросите новый код.' };
  }

  // Увеличиваем счётчик попыток
  otp.attempts++;
  await saveOtp(otp.phone, otp.code, otp.chatId);

  if (otp.code !== code) {
    const remaining = MAX_OTP_ATTEMPTS - otp.attempts;
    return {
      success: false,
      error: remaining > 0
        ? `Неверный код. Осталось попыток: ${remaining}`
        : 'Неверный код. Запросите новый.'
    };
  }

  // Код верный - помечаем как использованный
  otp.verified = true;
  const filePath = path.join(OTP_DIR, `${phone}.json`);
  await fs.writeFile(filePath, JSON.stringify(otp, null, 2));

  // Генерируем временный токен регистрации
  const registrationToken = crypto.randomBytes(32).toString('hex');

  // Сохраняем токен (действителен 10 минут)
  otp.registrationToken = registrationToken;
  otp.tokenExpiresAt = Date.now() + 10 * 60 * 1000;
  await fs.writeFile(filePath, JSON.stringify(otp, null, 2));

  return { success: true, registrationToken };
}

/**
 * Проверяет токен регистрации
 */
async function verifyRegistrationToken(phone, token) {
  const otp = await getOtpByPhone(phone);

  if (!otp || !otp.registrationToken) {
    return false;
  }

  if (otp.registrationToken !== token) {
    return false;
  }

  if (Date.now() > otp.tokenExpiresAt) {
    return false;
  }

  return true;
}

/**
 * Удаляет OTP после использования
 */
async function deleteOtp(phone) {
  const filePath = path.join(OTP_DIR, `${phone}.json`);
  try {
    await fs.unlink(filePath);
  } catch (error) {
    if (error.code !== 'ENOENT') throw error;
  }
}

/**
 * Форматирует телефон для отображения
 */
function formatPhone(phone) {
  if (phone.length !== 11) return phone;
  return `+${phone[0]} (${phone.substring(1, 4)}) ${phone.substring(4, 7)}-${phone.substring(7, 9)}-${phone.substring(9)}`;
}

/**
 * Отправляет уведомление в Telegram
 */
async function sendNotification(chatId, message) {
  if (!bot) return;
  try {
    await bot.sendMessage(chatId, message);
  } catch (error) {
    console.error('Failed to send Telegram notification:', error);
  }
}

module.exports = {
  initBot,
  generateOtp,
  saveOtp,
  getOtpByPhone,
  verifyOtp,
  verifyRegistrationToken,
  deleteOtp,
  sendNotification,
  BOT_TOKEN
};
