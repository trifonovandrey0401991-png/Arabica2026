/**
 * Arabica Admin Bot — мониторинг и управление сервером через Telegram
 *
 * Запуск: pm2 start ecosystem.config.js
 * Зависимости: node-telegram-bot-api, pg (из родительского loyalty-proxy)
 */

const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const http = require('http');
const https = require('https');
const { Pool } = require('pg');
const fs = require('fs');
const path = require('path');

// ============================================
// КОНФИГУРАЦИЯ
// ============================================

const BOT_TOKEN = process.env.BOT_TOKEN;
const ADMIN_ID = parseInt(process.env.ADMIN_ID || '840309879', 10);
const CHECK_INTERVAL = 2 * 60 * 1000; // Проверка каждые 2 минуты
const LOYALTY_URL = 'http://127.0.0.1:3000/health';
const OCR_URL = 'http://127.0.0.1:5001/health';
const SSL_DOMAIN = 'arabica26.ru';
const DANGEROUS_COMMANDS = ['rm -rf', 'mkfs', 'dd if=', 'shutdown', 'reboot', 'halt', '> /dev/', 'chmod -R 777'];

if (!BOT_TOKEN) {
  console.error('[Admin Bot] BOT_TOKEN не задан! Укажите в ecosystem.config.js');
  process.exit(1);
}

// ============================================
// ПОДКЛЮЧЕНИЕ К БД
// ============================================

const pool = new Pool({
  user: process.env.DB_USER || 'arabica_app',
  password: process.env.DB_PASSWORD || undefined, // peer auth на сервере, пароль из env
  host: process.env.DB_HOST || 'localhost',
  database: process.env.DB_NAME || 'arabica_db',
  port: parseInt(process.env.DB_PORT, 10) || 5432,
  max: 2, // минимум соединений — бот не нагружает БД
});

// ============================================
// ИНИЦИАЛИЗАЦИЯ БОТА
// ============================================

const bot = new TelegramBot(BOT_TOKEN, { polling: true });

function isAdmin(msg) {
  return msg.from.id === ADMIN_ID;
}

function send(text, options = {}) {
  return bot.sendMessage(ADMIN_ID, text, { parse_mode: 'HTML', ...options }).catch(err => {
    console.error('[Admin Bot] Ошибка отправки:', err.message);
  });
}

function escapeHtml(text) {
  return text.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');
}

// ============================================
// УТИЛИТЫ
// ============================================

function execCmd(cmd, timeout = 10000) {
  return new Promise((resolve) => {
    exec(cmd, { timeout }, (err, stdout, stderr) => {
      if (err) resolve(`Error: ${err.message}`);
      else resolve(stdout || stderr || '');
    });
  });
}

function httpCheck(url) {
  return new Promise((resolve) => {
    const req = http.get(url, { timeout: 5000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try { resolve({ ok: res.statusCode === 200, data: JSON.parse(data) }); }
        catch { resolve({ ok: res.statusCode === 200, data: null }); }
      });
    });
    req.on('error', (err) => resolve({ ok: false, error: err.message }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, error: 'timeout' }); });
  });
}

function formatBytes(bytes) {
  if (bytes < 1024) return bytes + ' B';
  if (bytes < 1048576) return (bytes / 1024).toFixed(1) + ' KB';
  if (bytes < 1073741824) return (bytes / 1048576).toFixed(1) + ' MB';
  return (bytes / 1073741824).toFixed(1) + ' GB';
}

// Проверка SSL-сертификата — возвращает дней до истечения
function checkSSL(domain) {
  return new Promise((resolve) => {
    const req = https.request({ hostname: domain, port: 443, method: 'HEAD', timeout: 10000 }, (res) => {
      const cert = res.socket.getPeerCertificate();
      if (cert && cert.valid_to) {
        const expiryDate = new Date(cert.valid_to);
        const daysLeft = Math.floor((expiryDate - Date.now()) / 86400000);
        resolve({ ok: true, daysLeft, expiryDate: expiryDate.toLocaleDateString('ru-RU') });
      } else {
        resolve({ ok: false, error: 'no certificate' });
      }
      res.destroy();
    });
    req.on('error', (err) => resolve({ ok: false, error: err.message }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, error: 'timeout' }); });
    req.end();
  });
}

// HTTP-запрос с замером времени ответа (в мс)
function httpCheckTimed(url) {
  return new Promise((resolve) => {
    const start = Date.now();
    const req = http.get(url, { timeout: 10000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const ms = Date.now() - start;
        try { resolve({ ok: res.statusCode === 200, ms, data: JSON.parse(data) }); }
        catch { resolve({ ok: res.statusCode === 200, ms, data: null }); }
      });
    });
    req.on('error', () => resolve({ ok: false, ms: -1 }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, ms: -1 }); });
  });
}

function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}д ${h}ч ${m}м`;
  if (h > 0) return `${h}ч ${m}м`;
  return `${m}м`;
}

// ============================================
// ЛОГИРОВАНИЕ ВСЕХ СООБЩЕНИЙ (для отладки)
// ============================================

bot.on('message', (msg) => {
  console.log(`[Admin Bot] Сообщение от ${msg.from.first_name} (ID: ${msg.from.id}): ${msg.text}`);
});

// ============================================
// КОМАНДЫ
// ============================================

// /start и /help
bot.onText(/\/(start|help)/, (msg) => {
  if (!isAdmin(msg)) return;
  send(`🤖 <b>Arabica Admin Bot</b>

<b>Мониторинг:</b>
/status — процессы, RAM, диск
/db — статистика БД + пул соединений
/logs — последние 25 строк логов
/errors — ошибки из логов
/schedulers — статус всех планировщиков
/memory — память Node.js (heap, тренд)
/errstat — статистика ошибок (дни/тренд)
/connectivity — внешние сервисы (Firebase, Telegram)
/dbslow — медленные SQL-запросы
/diskfiles — файлы в директориях /var/www

<b>Управление:</b>
/restart — перезапуск процесса
/deploy — деплой (git pull + restart + тест)
/tests — запуск API тестов
/backup — бэкап базы данных

<b>ИИ обучение:</b>
/ai_status — статус модели YOLO
/ai_train — запустить обучение
/ai_train_status — ход обучения

<b>Управление (продвинутое):</b>
/cmd &lt;команда&gt; — выполнить команду на сервере
/dbf — статус DBF синхронизации магазинов
/ssl — проверить SSL-сертификат

<b>Автоматически:</b>
• Оповещение если сервис упал
• Оповещение при ошибках 500
• Оповещение если магазин отключился от DBF
• Crash-loop детектор (5+ перезапусков)
• SSL-сертификат истекает &lt; 14 дней
• Замедление API &gt; 500ms
• RAM &gt; 85% / Диск &gt; 90%
• Планировщик завис (&gt; 15 мин без запуска)
• Утечка памяти (heap растёт 1ч)
• API-маршруты сломаны (500 на ключевых)
• Firebase/Telegram недоступны
• Медленный SQL (&gt; 10 сек)
• Накопление файлов (&gt; 500 в директории)
• Бэкап БД каждую ночь в 3:00
• Отчёт каждый день в 22:00 МСК`);
});

// /status — полный статус сервера
bot.onText(/\/status/, async (msg) => {
  if (!isAdmin(msg)) return;

  const [pm2Raw, loyalty, ocr, ramStr, diskStr] = await Promise.all([
    execCmd('pm2 jlist'),
    httpCheck(LOYALTY_URL),
    httpCheck(OCR_URL),
    execCmd("free -m | awk '/^Mem:/ {printf \"%s %s\", $3, $2}'"),
    execCmd("df -h / | awk 'NR==2 {printf \"%s/%s (%s)\", $3, $2, $5}'"),
  ]);

  // pm2 процессы
  let pm2Info = '';
  try {
    const processes = JSON.parse(pm2Raw);
    for (const p of processes) {
      const icon = p.pm2_env.status === 'online' ? '🟢' : '🔴';
      const mem = formatBytes(p.monit?.memory || 0);
      const cpu = p.monit?.cpu || 0;
      const restarts = p.pm2_env.restart_time || 0;
      pm2Info += `${icon} <b>${p.name}</b> — ${mem}, CPU ${cpu}%`;
      if (restarts > 0) pm2Info += `, ↻${restarts}`;
      pm2Info += '\n';
    }
  } catch {
    pm2Info = '⚠️ Не удалось получить pm2 list\n';
  }

  // Uptime loyalty-proxy
  let uptime = '';
  if (loyalty.ok && loyalty.data?.uptime) {
    uptime = ` (uptime: ${formatUptime(Math.floor(loyalty.data.uptime))})`;
  }

  // RAM
  let ramLine = ramStr.trim();
  const ramParts = ramLine.split(' ');
  if (ramParts.length === 2) {
    const used = parseInt(ramParts[0]);
    const total = parseInt(ramParts[1]);
    const pct = ((used / total) * 100).toFixed(0);
    ramLine = `${used}/${total} MB (${pct}%)`;
  }

  send(`📊 <b>Статус сервера</b>

<b>Процессы:</b>
${pm2Info}
<b>Сервисы:</b>
API: ${loyalty.ok ? '🟢 online' : '🔴 OFFLINE'}${uptime}
OCR: ${ocr.ok ? '🟢 online' : '🔴 OFFLINE'}

<b>Система:</b>
RAM: ${ramLine}
Диск: ${diskStr.trim()}`);
});

// /restart — перезапуск процесса (выбор какого)
bot.onText(/\/restart$/, (msg) => {
  if (!isAdmin(msg)) return;
  send('Какой процесс перезапустить?', {
    reply_markup: {
      inline_keyboard: [
        [
          { text: '🔄 loyalty-proxy', callback_data: 'restart:loyalty-proxy' },
          { text: '🔄 ocr-server', callback_data: 'restart:ocr-server' },
        ],
        [{ text: '❌ Отмена', callback_data: 'restart:cancel' }],
      ]
    }
  });
});

// Обработка нажатий на кнопки
bot.on('callback_query', async (query) => {
  if (query.from.id !== ADMIN_ID) return;
  const data = query.data;

  if (data.startsWith('restart:')) {
    const process_name = data.replace('restart:', '');

    if (process_name === 'cancel') {
      await bot.answerCallbackQuery(query.id, { text: 'Отменено' });
      await bot.editMessageText('❌ Перезапуск отменён', {
        chat_id: ADMIN_ID, message_id: query.message.message_id,
      });
      return;
    }

    await bot.answerCallbackQuery(query.id, { text: 'Перезапускаю...' });
    await bot.editMessageText(`⏳ Перезапускаю ${process_name}...`, {
      chat_id: ADMIN_ID, message_id: query.message.message_id,
    });

    await execCmd(`pm2 restart ${process_name}`);

    // Ждём 3 сек для запуска
    await new Promise(r => setTimeout(r, 3000));

    const checkUrl = process_name === 'ocr-server' ? OCR_URL : LOYALTY_URL;
    const health = await httpCheck(checkUrl);

    const status = health.ok
      ? `✅ ${process_name} перезапущен и работает`
      : `⚠️ ${process_name} перезапущен, но не отвечает на /health`;

    await bot.editMessageText(status, {
      chat_id: ADMIN_ID, message_id: query.message.message_id,
    });
  }

  // Deploy
  if (data === 'deploy:cancel') {
    await bot.answerCallbackQuery(query.id, { text: 'Отменено' });
    await bot.editMessageText('❌ Деплой отменён', {
      chat_id: ADMIN_ID, message_id: query.message.message_id,
    });
  }

  if (data === 'deploy:confirm') {
    await bot.answerCallbackQuery(query.id, { text: 'Деплою...' });
    const msgId = query.message.message_id;

    // Шаг 1: git pull
    await bot.editMessageText('⏳ 1/4 — git pull...', { chat_id: ADMIN_ID, message_id: msgId });
    const pullResult = await execCmd('cd /root/arabica_app && git pull origin refactoring/full-restructure 2>&1', 30000);
    const pullOk = !pullResult.includes('error') && !pullResult.includes('CONFLICT');

    if (!pullOk) {
      await bot.editMessageText(`❌ git pull failed:\n<pre>${escapeHtml(pullResult.slice(0, 1000))}</pre>`, {
        chat_id: ADMIN_ID, message_id: msgId, parse_mode: 'HTML',
      });
      return;
    }

    // Шаг 2: npm install (если нужно)
    await bot.editMessageText('⏳ 2/4 — npm install...', { chat_id: ADMIN_ID, message_id: msgId });
    await execCmd('cd /root/arabica_app/loyalty-proxy && npm install --production 2>&1', 60000);

    // Шаг 3: pm2 restart
    await bot.editMessageText('⏳ 3/4 — pm2 restart...', { chat_id: ADMIN_ID, message_id: msgId });
    await execCmd('pm2 restart loyalty-proxy');
    await new Promise(r => setTimeout(r, 3000));

    // Шаг 4: health check
    await bot.editMessageText('⏳ 4/4 — health check...', { chat_id: ADMIN_ID, message_id: msgId });
    const health = await httpCheck(LOYALTY_URL);

    if (health.ok) {
      // Получаем текущий коммит
      const commit = await execCmd('cd /root/arabica_app && git log --oneline -1');
      await bot.editMessageText(
        `✅ <b>Деплой успешен!</b>\n\n📌 ${escapeHtml(commit.trim())}\n🟢 Health check OK`,
        { chat_id: ADMIN_ID, message_id: msgId, parse_mode: 'HTML' }
      );
    } else {
      await bot.editMessageText(
        '⚠️ <b>Деплой завершён, но health check не прошёл!</b>\n\nИспользуйте /logs для проверки',
        { chat_id: ADMIN_ID, message_id: msgId, parse_mode: 'HTML' }
      );
    }
  }

  // AI Train
  if (data === 'ai_train:cancel') {
    await bot.answerCallbackQuery(query.id, { text: 'Отменено' });
    await bot.editMessageText('❌ Обучение отменено', {
      chat_id: ADMIN_ID, message_id: query.message.message_id,
    });
  }

  if (data === 'ai_train:confirm') {
    await bot.answerCallbackQuery(query.id, { text: 'Запускаю...' });
    const msgId = query.message.message_id;
    await bot.editMessageText('⏳ Запускаю обучение YOLO (50 эпох)...', {
      chat_id: ADMIN_ID, message_id: msgId, parse_mode: 'HTML',
    });

    // POST к loyalty-proxy для запуска обучения
    try {
      const body = JSON.stringify({ epochs: 50 });
      const result = await new Promise((resolve) => {
        const req = http.request({
          hostname: '127.0.0.1', port: 3000,
          path: '/api/internal/trigger-recount-training',
          method: 'POST',
          headers: { 'Content-Type': 'application/json', 'Content-Length': Buffer.byteLength(body) },
          timeout: 10000,
        }, (res) => {
          let data = '';
          res.on('data', chunk => data += chunk);
          res.on('end', () => {
            try { resolve(JSON.parse(data)); } catch { resolve({ success: false }); }
          });
        });
        req.on('error', () => resolve({ success: false, error: 'Не удалось связаться с API' }));
        req.write(body);
        req.end();
      });

      if (result.success) {
        await bot.editMessageText(
          '🚀 <b>Обучение запущено!</b>\n\n🔄 50 эпох\n⏱ Займёт ~5-10 минут\n\nИспользуйте /ai_train_status для проверки хода.\nПо завершении придёт уведомление.',
          { chat_id: ADMIN_ID, message_id: msgId, parse_mode: 'HTML' }
        );
      } else {
        const errText = result.error === 'already_running' ? 'Обучение уже запущено!' : (result.error || 'Неизвестная ошибка');
        await bot.editMessageText(
          `❌ <b>Не удалось запустить:</b> ${escapeHtml(errText)}`,
          { chat_id: ADMIN_ID, message_id: msgId, parse_mode: 'HTML' }
        );
      }
    } catch (err) {
      await bot.editMessageText(
        `❌ Ошибка: ${escapeHtml(err.message)}`,
        { chat_id: ADMIN_ID, message_id: msgId, parse_mode: 'HTML' }
      );
    }
  }
});

// /logs — последние строки логов
bot.onText(/\/logs/, async (msg) => {
  if (!isAdmin(msg)) return;
  const logs = await execCmd('pm2 logs loyalty-proxy --lines 25 --nostream 2>&1');
  const truncated = logs.length > 3800 ? '...\n' + logs.slice(-3800) : logs;
  send(`📋 <b>Логи loyalty-proxy:</b>\n\n<pre>${escapeHtml(truncated)}</pre>`);
});

// /errors — ошибки из логов
bot.onText(/\/errors/, async (msg) => {
  if (!isAdmin(msg)) return;
  const errors = await execCmd(
    "pm2 logs loyalty-proxy --lines 200 --nostream 2>&1 | grep -iE 'error|ERR|fail|WARN|crash|uncaught' | tail -20"
  );
  if (!errors.trim()) {
    send('✅ Ошибок в последних 200 строках логов не найдено');
    return;
  }
  const truncated = errors.length > 3800 ? '...\n' + errors.slice(-3800) : errors;
  send(`⚠️ <b>Ошибки из логов:</b>\n\n<pre>${escapeHtml(truncated)}</pre>`);
});

// /db — статистика базы данных
bot.onText(/\/db/, async (msg) => {
  if (!isAdmin(msg)) return;
  try {
    const [sizeRes, tablesRes, connRes, poolStats] = await Promise.all([
      pool.query("SELECT pg_database_size('arabica_db') as size"),
      pool.query(`
        SELECT tablename, n_live_tup as rows
        FROM pg_stat_user_tables
        ORDER BY n_live_tup DESC LIMIT 10
      `),
      pool.query("SELECT count(*) as cnt FROM pg_stat_activity WHERE datname = 'arabica_db'"),
      getPoolStats(),
    ]);

    const dbSize = formatBytes(parseInt(sizeRes.rows[0].size));
    const connections = connRes.rows[0].cnt;

    let tablesList = '';
    for (const t of tablesRes.rows) {
      tablesList += `  ${t.tablename}: ${t.rows}\n`;
    }

    send(`🗄 <b>База данных</b>

Размер: <b>${dbSize}</b>
Подключения: <b>${connections}</b>
Пул: ${poolStats.total} соед. (${poolStats.active} активных, ${poolStats.idle} idle)

<b>Топ-10 таблиц (по кол-ву записей):</b>
<pre>${tablesList}</pre>`);
  } catch (err) {
    send(`❌ Ошибка БД: <pre>${escapeHtml(err.message)}</pre>`);
  }
});

// /backup — бэкап базы данных
bot.onText(/\/backup/, async (msg) => {
  if (!isAdmin(msg)) return;
  send('⏳ Создаю бэкап...');

  const date = new Date().toISOString().slice(0, 19).replace(/[T:]/g, '-');
  const backupPath = `/root/backups/arabica_db_${date}.sql`;

  await execCmd('mkdir -p /root/backups');
  const result = await execCmd(
    `sudo -u postgres pg_dump arabica_db > ${backupPath} 2>&1`,
    30000 // 30 сек таймаут для pg_dump
  );

  if (!result.trim() || result.trim() === 'OK') {
    const sizeStr = await execCmd(`ls -lh ${backupPath} | awk '{print $5}'`);
    send(`✅ <b>Бэкап создан</b>\n\n📁 <code>${backupPath}</code>\n📦 Размер: ${sizeStr.trim()}`);
  } else {
    send(`❌ Ошибка бэкапа:\n<pre>${escapeHtml(result)}</pre>`);
  }
});

// ============================================
// /tests — запуск API тестов
// ============================================

bot.onText(/\/tests/, async (msg) => {
  if (!isAdmin(msg)) return;
  send('⏳ Запускаю API тесты...');

  const result = await execCmd(
    'cd /root/arabica_app && node tests/api-test.js 2>&1',
    120000 // 2 мин таймаут
  );

  // Парсим результат
  const lines = result.split('\n');
  const passMatch = result.match(/(\d+)\s*(passed|✓|ok)/i);
  const failMatch = result.match(/(\d+)\s*(failed|✗|fail)/i);
  const totalMatch = result.match(/(\d+)\s*total/i);

  // Ищем строки с FAIL для детального отчёта
  const failedLines = lines.filter(l => /fail|✗|error|❌/i.test(l) && !/node_modules/.test(l));

  let summary;
  if (failMatch && parseInt(failMatch[1]) > 0) {
    summary = `❌ <b>Тесты: есть ошибки!</b>\n\n`;
    if (passMatch) summary += `✅ Passed: ${passMatch[1]}\n`;
    summary += `❌ Failed: ${failMatch[1]}\n`;
    if (failedLines.length > 0) {
      summary += `\n<b>Ошибки:</b>\n<pre>${escapeHtml(failedLines.slice(0, 10).join('\n'))}</pre>`;
    }
  } else if (passMatch) {
    summary = `✅ <b>Все тесты пройдены: ${passMatch[1]}</b>`;
    if (totalMatch) summary += ` / ${totalMatch[1]}`;
  } else {
    // Не удалось распарсить — отправляем последние строки
    const tail = lines.slice(-15).join('\n');
    summary = `📋 <b>Результат тестов:</b>\n\n<pre>${escapeHtml(tail)}</pre>`;
  }

  send(summary);
});

// ============================================
// /deploy — деплой из Telegram
// ============================================

bot.onText(/\/deploy$/, (msg) => {
  if (!isAdmin(msg)) return;
  // Показываем последний коммит перед деплоем
  execCmd('cd /root/arabica_app && git log --oneline -3 origin/refactoring/full-restructure 2>&1')
    .then(log => {
      send(`📦 <b>Деплой</b>\n\nПоследние коммиты на сервере:\n<pre>${escapeHtml(log.trim())}</pre>`, {
        reply_markup: {
          inline_keyboard: [
            [{ text: '🚀 Деплоить (git pull + restart)', callback_data: 'deploy:confirm' }],
            [{ text: '❌ Отмена', callback_data: 'deploy:cancel' }],
          ]
        }
      });
    });
});

// ============================================
// /cmd — выполнение произвольных команд на сервере
// ============================================

bot.onText(/\/cmd (.+)/, async (msg, match) => {
  if (!isAdmin(msg)) return;
  const command = match[1].trim();

  // Проверка на опасные команды
  const isDangerous = DANGEROUS_COMMANDS.some(dc => command.includes(dc));
  if (isDangerous) {
    send(`🚫 <b>Команда заблокирована!</b>\n\n<code>${escapeHtml(command)}</code>\n\nЭта команда может уничтожить данные.`);
    return;
  }

  send(`⏳ Выполняю: <code>${escapeHtml(command)}</code>`);
  const result = await execCmd(command, 30000);
  const output = result.trim() || '(пустой вывод)';
  const truncated = output.length > 3500 ? output.slice(0, 3500) + '\n...(обрезано)' : output;
  send(`💻 <b>Результат:</b>\n\n<pre>${escapeHtml(truncated)}</pre>`);
});

// /dbf — статус DBF синхронизации магазинов
bot.onText(/\/dbf/, async (msg) => {
  if (!isAdmin(msg)) return;

  let files;
  try {
    files = fs.readdirSync(DBF_SYNC_DIR).filter(f => f.endsWith('.json'));
  } catch {
    send('⚠️ Нет данных о синхронизации DBF (директория не найдена)');
    return;
  }

  if (files.length === 0) {
    send('⚠️ Нет магазинов с DBF синхронизацией');
    return;
  }

  const shopNames = await loadShopNames();
  const now = Date.now();
  const threshold = DBF_STALE_MINUTES * 60 * 1000;
  const lines = [];

  for (const file of files) {
    const shopId = file.replace('.json', '');
    try {
      const data = JSON.parse(fs.readFileSync(path.join(DBF_SYNC_DIR, file), 'utf8'));
      const lastSync = data.lastSync ? new Date(data.lastSync).getTime() : 0;
      const shopName = shopNames[shopId] || shopId;
      const productCount = data.productCount || 0;

      if (lastSync === 0) {
        lines.push(`⚪ ${shopName} — нет данных`);
      } else {
        const minutesAgo = Math.floor((now - lastSync) / 60000);
        const isConnected = (now - lastSync) < threshold;
        const icon = isConnected ? '🟢' : '🔴';
        const timeStr = minutesAgo < 60
          ? `${minutesAgo} мин назад`
          : `${Math.floor(minutesAgo / 60)}ч ${minutesAgo % 60}м назад`;
        lines.push(`${icon} ${shopName} — ${timeStr} (${productCount} товаров)`);
      }
    } catch {
      lines.push(`⚠️ ${shopId} — ошибка чтения`);
    }
  }

  send(`📡 <b>DBF синхронизация магазинов</b>\n\n${lines.join('\n')}\n\n⏱ Порог отключения: ${DBF_STALE_MINUTES} мин`);
});

// /ssl — проверка SSL-сертификата
bot.onText(/\/ssl/, async (msg) => {
  if (!isAdmin(msg)) return;
  const ssl = await checkSSL(SSL_DOMAIN);
  if (ssl.ok) {
    const icon = ssl.daysLeft > 30 ? '🟢' : ssl.daysLeft > 14 ? '🟡' : '🔴';
    send(`🔒 <b>SSL-сертификат ${SSL_DOMAIN}</b>\n\n${icon} Осталось дней: <b>${ssl.daysLeft}</b>\n📅 Истекает: ${ssl.expiryDate}`);
  } else {
    send(`🔴 <b>Не удалось проверить SSL!</b>\n\nОшибка: ${ssl.error}`);
  }
});

// ============================================
// РАСШИРЕННЫЙ МОНИТОРИНГ — КОМАНДЫ
// ============================================

// /schedulers — статус всех планировщиков
bot.onText(/\/schedulers/, (msg) => {
  if (!isAdmin(msg)) return;
  const states = readSchedulerStates();
  let text = '⏰ <b>Статус планировщиков</b>\n\n';
  for (const s of states) {
    let icon, timeStr;
    if (s.lastCheck === null) {
      icon = '⚪';
      timeStr = 'нет данных';
    } else if (s.noStaleAlert) {
      icon = '🔵';
      timeStr = formatMinutesAgo(s.minutesAgo);
    } else if (s.minutesAgo <= 10) {
      icon = '🟢';
      timeStr = formatMinutesAgo(s.minutesAgo);
    } else if (s.minutesAgo <= SCHEDULER_STALE_MINUTES) {
      icon = '🟡';
      timeStr = formatMinutesAgo(s.minutesAgo);
    } else {
      icon = '🔴';
      timeStr = formatMinutesAgo(s.minutesAgo);
    }
    text += `${icon} ${s.name}: ${timeStr}\n`;
  }
  text += `\n⚠️ Порог зависания: ${SCHEDULER_STALE_MINUTES} мин (интервал: 5 мин)`;
  send(text);
});

// /memory — память Node.js с трендом
bot.onText(/\/memory/, async (msg) => {
  if (!isAdmin(msg)) return;
  const health = await httpCheck(LOYALTY_URL);
  const mem = health.ok && health.data?.memory;

  if (!mem) {
    send('❌ Не удалось получить данные о памяти (loyalty-proxy не отвечает)');
    return;
  }

  const current = mem.heapUsed;
  const heapTotal = mem.heapTotal;
  const rss = mem.rss;

  let text = `🧠 <b>Память Node.js</b>\n\n`;
  text += `Heap Used: <b>${formatBytes(current)}</b> / ${formatBytes(heapTotal)}\n`;
  text += `RSS: <b>${formatBytes(rss)}</b>\n`;

  if (heapHistory.length >= 2) {
    const values = heapHistory.map(h => h.heapUsed);
    const min = Math.min(...values);
    const max = Math.max(...values);
    const period = Math.round((Date.now() - heapHistory[0].time.getTime()) / 60000);
    text += `\nMin/Max за ${period} мин: ${formatBytes(min)} / ${formatBytes(max)}\n`;

    // Text trend chart (last 20 readings)
    const bars = '▁▂▃▄▅▆▇█';
    const recent = values.slice(-20);
    const rMin = Math.min(...recent);
    const rMax = Math.max(...recent);
    const range = rMax - rMin || 1;
    let chart = '';
    for (const v of recent) {
      const idx = Math.min(Math.floor(((v - rMin) / range) * 7), 7);
      chart += bars[idx];
    }
    text += `\nТренд: <code>${chart}</code>\n`;
    text += `        ${formatBytes(rMin)} → ${formatBytes(recent[recent.length - 1])}`;
  } else {
    text += `\n<i>Недостаточно данных для тренда (нужно ~4 мин)</i>`;
  }

  send(text);
});

// /errstat — статистика ошибок
bot.onText(/\/errstat/, async (msg) => {
  if (!isAdmin(msg)) return;
  const stats = await getErrorCounts();
  const trend = stats.today > stats.weekAvg * 1.5 ? '📈 выше нормы'
    : stats.today < stats.weekAvg * 0.5 ? '📉 ниже нормы' : '➡️ в норме';
  send(`📊 <b>Статистика ошибок</b>

Сегодня: <b>${stats.today}</b> ${trend}
Вчера: ${stats.yesterday}
Среднее за 7 дней: ${stats.weekAvg}/день
Всего за неделю: ${stats.weekTotal}`);
});

// /connectivity — внешние сервисы
bot.onText(/\/connectivity/, async (msg) => {
  if (!isAdmin(msg)) return;
  send('⏳ Проверяю внешние сервисы...');
  const ext = await checkExternalServices();
  send(`🌐 <b>Внешние сервисы</b>

Firebase FCM: ${ext.firebase.ok ? '🟢 доступен' : '🔴 НЕДОСТУПЕН'}${ext.firebase.error ? ` (${ext.firebase.error})` : ''}
Telegram API: ${ext.telegram.ok ? '🟢 доступен' : '🔴 НЕДОСТУПЕН'}${ext.telegram.error ? ` (${ext.telegram.error})` : ''}`);
});

// /dbslow — медленные SQL-запросы
bot.onText(/\/dbslow/, async (msg) => {
  if (!isAdmin(msg)) return;
  try {
    const [slowQueries, poolStats] = await Promise.all([
      checkSlowQueries(),
      getPoolStats(),
    ]);

    let text = `🐌 <b>Медленные запросы БД</b>\n\n`;
    text += `<b>Пул:</b> ${poolStats.total} соед. (${poolStats.active} активных, ${poolStats.idle} idle)\n\n`;

    if (slowQueries.length === 0) {
      text += '✅ Нет запросов дольше 10 секунд';
    } else {
      text += `⚠️ <b>Запросы &gt; 10 сек (${slowQueries.length}):</b>\n\n`;
      for (const q of slowQueries) {
        text += `⏱ ${q.duration}\n<pre>${escapeHtml(q.query_text)}</pre>\n\n`;
      }
    }
    send(text);
  } catch (err) {
    send(`❌ Ошибка: <pre>${escapeHtml(err.message)}</pre>`);
  }
});

// /diskfiles — файлы в директориях
bot.onText(/\/diskfiles/, async (msg) => {
  if (!isAdmin(msg)) return;
  send('⏳ Считаю файлы...');
  const dirs = await countDirFiles();
  let text = '📂 <b>Файлы в директориях</b>\n\n';
  for (const d of dirs) {
    const icon = d.count < 0 ? '⚪' : d.count > DIR_FILE_ALERT_THRESHOLD ? '🔴' : d.count > 200 ? '🟡' : '🟢';
    const countStr = d.count < 0 ? 'ошибка' : d.count.toString();
    text += `${icon} ${d.name}: <b>${countStr}</b>\n`;
  }
  text += `\n⚠️ Порог: ${DIR_FILE_ALERT_THRESHOLD} файлов`;
  send(text);
});

// ============================================
// ИИ ОБУЧЕНИЕ — КОМАНДЫ
// ============================================

const YOLO_SERVER_URL = 'http://127.0.0.1:5002';
const LOYALTY_API_URL = 'http://127.0.0.1:3000';

// /ai_status — статус модели и данных
bot.onText(/\/ai_status/, async (msg) => {
  if (!isAdmin(msg)) return;
  send('⏳ Проверяю статус ИИ...');

  const [yoloHealth, modelInfo, trainStatus] = await Promise.all([
    httpCheck(`${YOLO_SERVER_URL}/health`),
    execCmd('ls -lh /root/arabica_app/loyalty-proxy/ml/models/cigarette_detector.pt 2>/dev/null | awk \'{print $5, $6, $7}\''),
    httpCheck(`${LOYALTY_API_URL}/api/internal/recount-train-status`),
  ]);

  // Количество данных
  const [trainingCount, pendingCount, labelCount] = await Promise.all([
    execCmd('ls /root/arabica_app/loyalty-proxy/data/cigarette-training-images/*.jpg 2>/dev/null | wc -l'),
    execCmd('ls /root/arabica_app/loyalty-proxy/data/counting-pending/images/*.jpg 2>/dev/null | wc -l'),
    execCmd('ls /root/arabica_app/loyalty-proxy/data/counting-training/labels/*.txt 2>/dev/null | wc -l'),
  ]);

  const yoloOk = yoloHealth.ok && yoloHealth.data?.modelLoaded;
  const classCount = yoloHealth.data?.classCount || '?';
  const modelSize = modelInfo.trim() || 'нет модели';

  // Последнее обучение
  let lastTrain = '—';
  if (trainStatus.ok && trainStatus.data?.finishedAt) {
    const d = new Date(trainStatus.data.finishedAt);
    lastTrain = d.toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' });
  }

  const trainState = trainStatus.data?.status || 'unknown';
  const stateIcon = { idle: '💤', running: '⏳', done: '✅', error: '🔴' }[trainState] || '❓';

  send(`🤖 <b>Статус ИИ (YOLO)</b>

<b>Модель:</b>
${yoloOk ? '🟢' : '🔴'} yolo_server: ${yoloOk ? 'загружена' : 'не загружена'}
📦 Размер: ${modelSize}
🏷 Классов: ${classCount}
${stateIcon} Статус обучения: ${trainState}
📅 Последнее обучение: ${lastTrain}

<b>Данные:</b>
📸 Тренировочных фото: ${trainingCount.trim()}
📝 С аннотациями (labels): ${labelCount.trim()}
⏳ Ожидают проверки: ${pendingCount.trim()}`);
});

// /ai_train — запуск обучения с подтверждением
bot.onText(/\/ai_train$/, async (msg) => {
  if (!isAdmin(msg)) return;

  // Проверяем нет ли уже запущенного обучения
  const status = await httpCheck(`${LOYALTY_API_URL}/api/ai-dashboard/recount-train-status`);
  if (status.ok && status.data?.status === 'running') {
    send('⚠️ Обучение уже запущено! Используйте /ai_train_status для проверки хода.');
    return;
  }

  const imgCount = await execCmd('ls /root/arabica_app/loyalty-proxy/data/cigarette-training-images/*.jpg 2>/dev/null | wc -l');
  send(`🤖 <b>Запуск обучения YOLO</b>\n\n📸 Тренировочных фото: ${imgCount.trim()}\n🔄 Эпох: 50\n\nЗапустить обучение?`, {
    reply_markup: {
      inline_keyboard: [
        [{ text: '🚀 Запустить обучение', callback_data: 'ai_train:confirm' }],
        [{ text: '❌ Отмена', callback_data: 'ai_train:cancel' }],
      ]
    }
  });
});

// /ai_train_status — статус текущего обучения
bot.onText(/\/ai_train_status/, async (msg) => {
  if (!isAdmin(msg)) return;

  const status = await httpCheck(`${LOYALTY_API_URL}/api/ai-dashboard/recount-train-status`);
  if (!status.ok) {
    send('❌ Не удалось получить статус обучения. loyalty-proxy не отвечает.');
    return;
  }

  const s = status.data;
  const stateIcon = { idle: '💤', running: '⏳', done: '✅', error: '🔴' }[s.status] || '❓';
  const stateText = { idle: 'ожидание', running: 'идёт обучение', done: 'завершено', error: 'ошибка' }[s.status] || s.status;

  let text = `🤖 <b>Статус обучения</b>\n\n${stateIcon} <b>${stateText}</b>`;

  if (s.startedAt) {
    const started = new Date(s.startedAt).toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' });
    text += `\n📅 Начато: ${started}`;
  }
  if (s.epochs) {
    text += `\n🔄 Эпох: ${s.epochs}`;
  }
  if (s.retryCount > 0) {
    text += `\n🔁 Попытка: ${s.retryCount + 1}/3`;
  }
  if (s.finishedAt) {
    const finished = new Date(s.finishedAt).toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' });
    text += `\n🏁 Завершено: ${finished}`;
  }
  if (s.result) {
    text += `\n\n<b>Результат:</b>`;
    if (s.result.totalImages) text += `\n📸 Образцов: ${s.result.totalImages}`;
    if (s.result.modelReloaded !== undefined) text += `\n🤖 Модель загружена: ${s.result.modelReloaded ? 'да' : 'нет'}`;
  }
  if (s.error) {
    text += `\n\n❌ <b>Ошибка:</b> ${escapeHtml(s.error)}`;
  }

  send(text);
});

// ============================================
// РАСШИРЕННЫЙ МОНИТОРИНГ — КОНФИГУРАЦИЯ
// ============================================

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SCHEDULER_STALE_MINUTES = 15; // Планировщики работают каждые 5 мин, >15 мин = зависание
const HEAP_MAX_READINGS = 60; // 2 часа при 2-мин интервале
const HEAP_GROWTH_THRESHOLD = 0.5; // 50% рост = алерт
const HEAP_GROWTH_WINDOW = 30; // 30 замеров = 1 час
const DIR_FILE_ALERT_THRESHOLD = 500;

const SCHEDULER_DEFS = [
  { name: 'Пересменки',      file: `${DATA_DIR}/shift-automation-state/state.json`,              key: 'lastCheck' },
  { name: 'Пересчёты',       file: `${DATA_DIR}/recount-automation-state/state.json`,            key: 'lastCheck' },
  { name: 'РКО',             file: `${DATA_DIR}/rko-automation-state/state.json`,                key: 'lastCheck' },
  { name: 'Сдача смены',     file: `${DATA_DIR}/shift-handover-automation-state/state.json`,     key: 'lastCheck' },
  { name: 'Посещаемость',    file: `${DATA_DIR}/attendance-automation-state/state.json`,         key: 'lastCheck' },
  { name: 'Конверты',        file: `${DATA_DIR}/envelope-automation-state/state.json`,           key: 'lastCheck' },
  { name: 'Кофемашины',      file: `${DATA_DIR}/coffee-machine-automation-state/state.json`,     key: 'lastCheck' },
  { name: 'Вопросы товаров', file: `${DATA_DIR}/product-question-penalty-state/processed.json`,  key: 'lastCheckTime' },
  { name: 'YOLO обучение',   file: `${DATA_DIR}/yolo-retrain-state.json`,                       key: 'lastTrainedAt', noStaleAlert: true },
];

const CRITICAL_ENDPOINTS = [
  { path: '/api/dev/health?key=arabica-dev-2026', name: 'Dev Health' },
  { path: '/api/shops', name: 'Магазины' },
  { path: '/api/employees', name: 'Сотрудники' },
];

const MONITORED_DIRS = [
  { path: `${DATA_DIR}/shift-reports`,           name: 'Пересменки' },
  { path: `${DATA_DIR}/recount-reports`,         name: 'Пересчёты' },
  { path: `${DATA_DIR}/shift-handover-reports`,  name: 'Сдача смены' },
  { path: `${DATA_DIR}/envelope-reports`,        name: 'Конверты' },
  { path: `${DATA_DIR}/pending-shift-reports`,   name: 'Pending пересменки' },
  { path: `${DATA_DIR}/pending-recount-reports`, name: 'Pending пересчёты' },
  { path: `${DATA_DIR}/shift-handover-pending`,  name: 'Pending сдачи смены' },
  { path: `${DATA_DIR}/envelope-pending`,        name: 'Pending конверты' },
  { path: `${DATA_DIR}/rko-pending`,             name: 'Pending РКО' },
  { path: `${DATA_DIR}/attendance-pending`,      name: 'Pending посещаемость' },
  { path: `${DATA_DIR}/shift-photos`,            name: 'Фото пересменок' },
  { path: `${DATA_DIR}/employee-photos`,         name: 'Фото сотрудников' },
];

// In-memory tracking
const heapHistory = []; // { time, heapUsed }

// ============================================
// РАСШИРЕННЫЙ МОНИТОРИНГ — ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
// ============================================

function formatMinutesAgo(minutes) {
  if (minutes < 1) return 'только что';
  if (minutes < 60) return `${minutes} мин назад`;
  const h = Math.floor(minutes / 60);
  const m = minutes % 60;
  if (h < 24) return `${h}ч ${m}м назад`;
  const d = Math.floor(h / 24);
  return `${d}д ${h % 24}ч назад`;
}

function readSchedulerStates() {
  const results = [];
  for (const def of SCHEDULER_DEFS) {
    try {
      const data = JSON.parse(fs.readFileSync(def.file, 'utf8'));
      const timestamp = data[def.key];
      if (!timestamp) {
        results.push({ name: def.name, lastCheck: null, minutesAgo: -1, isStale: false, noStaleAlert: def.noStaleAlert });
        continue;
      }
      const lastCheck = new Date(timestamp);
      const minutesAgo = Math.floor((Date.now() - lastCheck.getTime()) / 60000);
      const isStale = !def.noStaleAlert && minutesAgo > SCHEDULER_STALE_MINUTES;
      results.push({ name: def.name, lastCheck, minutesAgo, isStale, noStaleAlert: def.noStaleAlert });
    } catch {
      results.push({ name: def.name, lastCheck: null, minutesAgo: -1, isStale: false, noStaleAlert: def.noStaleAlert });
    }
  }
  return results;
}

async function getErrorCounts() {
  const days = [];
  for (let i = 0; i < 7; i++) {
    days.push(new Date(Date.now() - i * 86400000).toISOString().slice(0, 10));
  }
  const promises = days.map(d =>
    execCmd(`grep -c "^${d}" ${ERROR_LOG_PATH} 2>/dev/null || echo 0`)
  );
  const counts = await Promise.all(promises);
  const dayCounts = counts.map(s => parseInt(s.trim()) || 0);
  const weekTotal = dayCounts.reduce((a, b) => a + b, 0);
  return {
    today: dayCounts[0],
    yesterday: dayCounts[1],
    weekTotal,
    weekAvg: Math.round(weekTotal / 7),
  };
}

function httpCheckStatus(url) {
  return new Promise((resolve) => {
    const start = Date.now();
    const req = http.get(url, { timeout: 10000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        const ms = Date.now() - start;
        // 2xx, 3xx, 401, 403 = alive; only 5xx = broken
        resolve({ alive: res.statusCode < 500, statusCode: res.statusCode, ms });
      });
    });
    req.on('error', () => resolve({ alive: false, statusCode: 0, ms: -1 }));
    req.on('timeout', () => { req.destroy(); resolve({ alive: false, statusCode: 0, ms: -1 }); });
  });
}

async function checkCriticalEndpoints() {
  const results = [];
  for (const ep of CRITICAL_ENDPOINTS) {
    const result = await httpCheckStatus(`http://127.0.0.1:3000${ep.path}`);
    results.push({ ...ep, ...result });
  }
  return results;
}

async function checkExternalServices() {
  const results = {};

  // Firebase FCM
  results.firebase = await new Promise((resolve) => {
    const req = https.request({
      hostname: 'fcm.googleapis.com', port: 443, path: '/', method: 'HEAD', timeout: 10000,
    }, (res) => {
      resolve({ ok: res.statusCode < 500, statusCode: res.statusCode });
      res.destroy();
    });
    req.on('error', (err) => resolve({ ok: false, error: err.message }));
    req.on('timeout', () => { req.destroy(); resolve({ ok: false, error: 'timeout' }); });
    req.end();
  });

  // Telegram API (via admin bot's own token)
  results.telegram = await new Promise((resolve) => {
    https.get(`https://api.telegram.org/bot${BOT_TOKEN}/getMe`, { timeout: 10000 }, (res) => {
      let data = '';
      res.on('data', chunk => data += chunk);
      res.on('end', () => {
        try {
          const json = JSON.parse(data);
          resolve({ ok: json.ok === true, statusCode: res.statusCode });
        } catch {
          resolve({ ok: false, statusCode: res.statusCode });
        }
      });
    }).on('error', (err) => resolve({ ok: false, error: err.message }));
  });

  return results;
}

async function checkSlowQueries() {
  try {
    const result = await pool.query(`
      SELECT pid, state, now() - query_start AS duration,
             left(query, 200) AS query_text
      FROM pg_stat_activity
      WHERE datname = 'arabica_db'
        AND state = 'active'
        AND query_start < now() - interval '10 seconds'
        AND query NOT LIKE '%pg_stat_activity%'
      ORDER BY query_start ASC
      LIMIT 5
    `);
    return result.rows;
  } catch (err) {
    console.error('[SlowQuery] Error:', err.message);
    return [];
  }
}

async function getPoolStats() {
  try {
    const result = await pool.query(
      "SELECT count(*) as total, count(*) FILTER (WHERE state = 'active') as active, count(*) FILTER (WHERE state = 'idle') as idle FROM pg_stat_activity WHERE datname = 'arabica_db'"
    );
    return result.rows[0];
  } catch {
    return { total: '?', active: '?', idle: '?' };
  }
}

async function countDirFiles() {
  const results = [];
  for (const dir of MONITORED_DIRS) {
    try {
      const count = await execCmd(`find "${dir.path}" -maxdepth 1 -type f 2>/dev/null | wc -l`);
      results.push({ ...dir, count: parseInt(count.trim()) || 0 });
    } catch {
      results.push({ ...dir, count: -1 });
    }
  }
  return results;
}

// ============================================
// АВТОМАТИЧЕСКИЙ МОНИТОРИНГ
// ============================================

const ERROR_LOG_PATH = '/root/.pm2/logs/loyalty-proxy-error.log';
let lastErrorLogSize = 0;

// Инициализируем размер лога (не отправляем старые ошибки)
try { lastErrorLogSize = fs.statSync(ERROR_LOG_PATH).size; } catch {}

const lastState = {
  loyalty: true,
  ocr: true,
  ramAlert: false,
  diskAlert: false,
  sslAlert: false,
  slowApiAlert: false,
  lastRestartCount: -1, // -1 = ещё не проверяли
  crashLoopAlert: false,
  // Feature 1: Schedulers
  staleSchedulerNames: new Set(),
  // Feature 2: Memory leak
  heapLeakAlert: false,
  // Feature 4: Critical endpoints
  criticalEndpointAlert: false,
  // Feature 5: External services
  firebaseAlert: false,
  telegramApiAlert: false,
  // Feature 6: Slow queries
  slowQueryAlert: false,
  // Feature 7: Directory file counts (dynamic keys: dirAlert_<path>)
};

// ============================================
// DBF МОНИТОРИНГ — подключение магазинов
// ============================================

const DBF_SYNC_DIR = (process.env.DATA_DIR || '/var/www') + '/shop-products';
const DBF_STALE_MINUTES = 15; // Магазин считается отключённым если синхронизация > 15 мин назад

// Состояние DBF подключений: shopId → { connected: bool, lastSync: number }
const dbfShopStates = new Map();

// Кэш названий магазинов из БД
let shopNamesCache = {};
let shopNamesCacheTime = 0;

async function loadShopNames() {
  if (Date.now() - shopNamesCacheTime < 3600000 && Object.keys(shopNamesCache).length > 0) {
    return shopNamesCache;
  }
  try {
    const res = await pool.query('SELECT id, address FROM shops');
    const names = {};
    for (const row of res.rows) {
      names[row.id] = row.address || row.id;
    }
    shopNamesCache = names;
    shopNamesCacheTime = Date.now();
    return names;
  } catch (err) {
    console.error('[DBF Monitor] Ошибка загрузки названий магазинов:', err.message);
    return shopNamesCache;
  }
}

async function checkDbfSync() {
  try {
    let files;
    try {
      files = fs.readdirSync(DBF_SYNC_DIR).filter(f => f.endsWith('.json'));
    } catch {
      return; // Директория не существует
    }

    if (files.length === 0) return;

    const shopNames = await loadShopNames();
    const now = Date.now();
    const threshold = DBF_STALE_MINUTES * 60 * 1000;

    for (const file of files) {
      const shopId = file.replace('.json', '');

      try {
        const data = JSON.parse(fs.readFileSync(path.join(DBF_SYNC_DIR, file), 'utf8'));
        const lastSync = data.lastSync ? new Date(data.lastSync).getTime() : 0;
        const isConnected = lastSync > 0 && (now - lastSync) < threshold;
        const shopName = shopNames[shopId] || shopId;

        const prevState = dbfShopStates.get(shopId);

        if (prevState === undefined) {
          // Первая проверка — запоминаем состояние, не шлём алерт
          dbfShopStates.set(shopId, { connected: isConnected, lastSync });
          continue;
        }

        if (prevState.connected && !isConnected) {
          const minutesAgo = Math.floor((now - lastSync) / 60000);
          send(`🔴 <b>DBF: магазин отключился!</b>\n\n🏪 ${escapeHtml(shopName)}\n⏱ Последняя синхронизация: ${minutesAgo} мин назад`);
        } else if (!prevState.connected && isConnected) {
          send(`🟢 <b>DBF: магазин подключился!</b>\n\n🏪 ${escapeHtml(shopName)}`);
        }

        dbfShopStates.set(shopId, { connected: isConnected, lastSync });
      } catch (err) {
        console.error(`[DBF Monitor] Ошибка чтения ${file}:`, err.message);
      }
    }
  } catch (err) {
    console.error('[DBF Monitor] Error:', err.message);
  }
}

// Средняя скорость API (скользящее среднее)
let apiResponseTimes = [];
let monitorCycleCount = 0;

async function monitorLoop() {
  try {
    monitorCycleCount++;

    // ---- КАЖДЫЙ ЦИКЛ (2 мин) — базовые проверки ----
    const [loyalty, ocr, ramStr, diskStr, pm2Raw] = await Promise.all([
      httpCheckTimed(LOYALTY_URL),
      httpCheck(OCR_URL),
      execCmd("free -m | awk '/^Mem:/ {print $3, $2}'"),
      execCmd("df / | awk 'NR==2 {print $5}' | tr -d '%'"),
      execCmd('pm2 jlist'),
    ]);

    // loyalty-proxy — онлайн/офлайн
    if (!loyalty.ok && lastState.loyalty) {
      send('🔴 <b>ALERT: loyalty-proxy НЕ ОТВЕЧАЕТ!</b>\n\nИспользуйте /restart для перезапуска');
      lastState.loyalty = false;
    } else if (loyalty.ok && !lastState.loyalty) {
      send('🟢 loyalty-proxy снова онлайн');
      lastState.loyalty = true;
    }

    // Скорость API — трекинг и алерт
    if (loyalty.ok && loyalty.ms > 0) {
      apiResponseTimes.push(loyalty.ms);
      if (apiResponseTimes.length > 30) apiResponseTimes.shift();
      const avgMs = apiResponseTimes.reduce((a, b) => a + b, 0) / apiResponseTimes.length;
      if (avgMs > 500 && !lastState.slowApiAlert) {
        send(`🐢 <b>API замедлился!</b>\n\nСредний ответ: <b>${avgMs.toFixed(0)}ms</b> (норма &lt; 100ms)\nВозможна утечка памяти или перегрузка БД`);
        lastState.slowApiAlert = true;
      } else if (avgMs <= 200) {
        lastState.slowApiAlert = false;
      }
    }

    // ocr-server
    if (!ocr.ok && lastState.ocr) {
      send('🔴 <b>ALERT: OCR-сервер НЕ ОТВЕЧАЕТ!</b>\n\nИспользуйте /restart для перезапуска');
      lastState.ocr = false;
    } else if (ocr.ok && !lastState.ocr) {
      send('🟢 OCR-сервер снова онлайн');
      lastState.ocr = true;
    }

    // Crash-loop детектор
    try {
      const processes = JSON.parse(pm2Raw);
      const lp = processes.find(p => p.name === 'loyalty-proxy');
      if (lp) {
        const currentRestarts = lp.pm2_env.restart_time || 0;
        if (lastState.lastRestartCount >= 0) {
          const newRestarts = currentRestarts - lastState.lastRestartCount;
          if (newRestarts >= 5 && !lastState.crashLoopAlert) {
            send(`🔴 <b>CRASH LOOP!</b>\n\nloyalty-proxy перезапустился <b>${newRestarts} раз</b> за 2 мин!\n\nВозможно бесконечный цикл падений.\nИспользуйте /logs для диагностики`);
            lastState.crashLoopAlert = true;
          } else if (newRestarts === 0) {
            lastState.crashLoopAlert = false;
          }
        }
        lastState.lastRestartCount = currentRestarts;
      }
    } catch {}

    // RAM
    const ramParts = ramStr.trim().split(' ');
    if (ramParts.length === 2) {
      const usedMb = parseInt(ramParts[0]);
      const totalMb = parseInt(ramParts[1]);
      const ramPct = (usedMb / totalMb) * 100;
      if (ramPct > 85 && !lastState.ramAlert) {
        send(`⚠️ <b>RAM: ${ramPct.toFixed(0)}%</b> (${usedMb}/${totalMb} MB)`);
        lastState.ramAlert = true;
      } else if (ramPct <= 80) {
        lastState.ramAlert = false;
      }
    }

    // Диск
    const diskPct = parseInt(diskStr.trim());
    if (!isNaN(diskPct)) {
      if (diskPct > 90 && !lastState.diskAlert) {
        send(`⚠️ <b>Диск заполнен на ${diskPct}%!</b>`);
        lastState.diskAlert = true;
      } else if (diskPct <= 85) {
        lastState.diskAlert = false;
      }
    }

    // DBF синхронизация магазинов
    await checkDbfSync();

    // Перехват новых ошибок 500 из лога
    try {
      const stat = fs.statSync(ERROR_LOG_PATH);
      if (stat.size > lastErrorLogSize) {
        const fd = fs.openSync(ERROR_LOG_PATH, 'r');
        const bufSize = Math.min(stat.size - lastErrorLogSize, 8192);
        const buf = Buffer.alloc(bufSize);
        fs.readSync(fd, buf, 0, bufSize, lastErrorLogSize);
        fs.closeSync(fd);

        const newLines = buf.toString('utf8');
        const errorLines = newLines.split('\n').filter(l =>
          /500|Internal Server Error|uncaught|unhandled|ECONNREFUSED|TypeError|ReferenceError/i.test(l)
        );

        if (errorLines.length > 0) {
          const preview = errorLines.slice(0, 5).join('\n');
          send(`🔴 <b>Новые ошибки сервера (${errorLines.length})</b>\n\n<pre>${escapeHtml(preview.slice(0, 2000))}</pre>\n\nПодробнее: /errors`);
        }
        lastErrorLogSize = stat.size;
      }
    } catch {}

    // ---- КАЖДЫЙ ЦИКЛ — Feature 1: Планировщики ----
    try {
      const schedulerStates = readSchedulerStates();
      const currentStale = new Set();
      for (const s of schedulerStates) {
        if (s.isStale) currentStale.add(s.name);
      }
      // Алерт только для НОВЫХ зависших (не повторяем)
      for (const name of currentStale) {
        if (!lastState.staleSchedulerNames.has(name)) {
          const s = schedulerStates.find(x => x.name === name);
          send(`⏰ <b>Планировщик завис!</b>\n\n🔴 ${name}\n⏱ Последний запуск: ${formatMinutesAgo(s.minutesAgo)}\n\nИспользуйте /schedulers для деталей`);
        }
      }
      // Восстановление
      for (const name of lastState.staleSchedulerNames) {
        if (!currentStale.has(name)) {
          send(`🟢 Планировщик <b>${name}</b> снова работает`);
        }
      }
      lastState.staleSchedulerNames = currentStale;
    } catch {}

    // ---- КАЖДЫЙ ЦИКЛ — Feature 2: Heap tracking ----
    if (loyalty.ok && loyalty.data?.memory?.heapUsed) {
      heapHistory.push({ time: new Date(), heapUsed: loyalty.data.memory.heapUsed });
      if (heapHistory.length > HEAP_MAX_READINGS) heapHistory.shift();

      if (heapHistory.length >= HEAP_GROWTH_WINDOW) {
        const windowStart = heapHistory[heapHistory.length - HEAP_GROWTH_WINDOW];
        const windowEnd = heapHistory[heapHistory.length - 1];
        const growthRatio = windowEnd.heapUsed / windowStart.heapUsed;

        // Проверяем монотонный рост (без GC-снижений)
        let isMonotonic = true;
        for (let i = heapHistory.length - HEAP_GROWTH_WINDOW + 1; i < heapHistory.length; i++) {
          if (heapHistory[i].heapUsed < heapHistory[i - 1].heapUsed * 0.95) {
            isMonotonic = false;
            break;
          }
        }

        if (growthRatio > (1 + HEAP_GROWTH_THRESHOLD) && isMonotonic && !lastState.heapLeakAlert) {
          send(`⚠️ <b>Возможная утечка памяти!</b>\n\nHeap рос ${HEAP_GROWTH_WINDOW} замеров подряд (${HEAP_GROWTH_WINDOW * 2} мин)\nНачало: ${formatBytes(windowStart.heapUsed)}\nСейчас: ${formatBytes(windowEnd.heapUsed)}\nРост: +${((growthRatio - 1) * 100).toFixed(0)}%\n\nИспользуйте /memory для деталей`);
          lastState.heapLeakAlert = true;
        } else if (growthRatio <= (1 + HEAP_GROWTH_THRESHOLD * 0.5)) {
          lastState.heapLeakAlert = false;
        }
      }
    }

    // ---- КАЖДЫЙ ЦИКЛ — Feature 6: Медленные SQL-запросы ----
    try {
      const slowQueries = await checkSlowQueries();
      if (slowQueries.length > 0 && !lastState.slowQueryAlert) {
        const first = slowQueries[0];
        send(`🐌 <b>Медленный запрос в БД!</b>\n\n⏱ Длительность: ${first.duration}\n<pre>${escapeHtml(first.query_text)}</pre>\n\nИспользуйте /dbslow для деталей`);
        lastState.slowQueryAlert = true;
      } else if (slowQueries.length === 0) {
        lastState.slowQueryAlert = false;
      }
    } catch {}

    // ---- КАЖДЫЕ 5 ЦИКЛОВ (10 мин) — Feature 4: Критические API ----
    if (monitorCycleCount % 5 === 0 && loyalty.ok) {
      try {
        const epResults = await checkCriticalEndpoints();
        const failed = epResults.filter(r => !r.alive);

        if (failed.length > 0 && !lastState.criticalEndpointAlert) {
          send(`🔴 <b>API маршруты не отвечают!</b>\n\n${failed.map(f => `❌ ${f.name} (${f.path}) — ${f.statusCode || 'нет ответа'}`).join('\n')}\n\nСервер работает, но конкретные функции сломаны.\nИспользуйте /logs для диагностики`);
          lastState.criticalEndpointAlert = true;
        } else if (failed.length === 0) {
          if (lastState.criticalEndpointAlert) {
            send('🟢 Все API маршруты снова работают');
          }
          lastState.criticalEndpointAlert = false;
        }
      } catch {}
    }

    // ---- КАЖДЫЕ 15 ЦИКЛОВ (30 мин) — Feature 5: Внешние сервисы ----
    if (monitorCycleCount % 15 === 7) {
      try {
        const ext = await checkExternalServices();

        if (!ext.firebase.ok && !lastState.firebaseAlert) {
          send(`🔴 <b>Firebase FCM недоступен!</b>\n\nPush-уведомления не доставляются.\n${ext.firebase.error ? 'Ошибка: ' + ext.firebase.error : ''}`);
          lastState.firebaseAlert = true;
        } else if (ext.firebase.ok && lastState.firebaseAlert) {
          send('🟢 Firebase FCM снова доступен');
          lastState.firebaseAlert = false;
        }

        if (!ext.telegram.ok && !lastState.telegramApiAlert) {
          console.error('[Monitor] Telegram API недоступен!');
          send('🔴 <b>Telegram API недоступен!</b>\n\nOTP-коды не отправляются.');
          lastState.telegramApiAlert = true;
        } else if (ext.telegram.ok && lastState.telegramApiAlert) {
          send('🟢 Telegram API снова доступен');
          lastState.telegramApiAlert = false;
        }
      } catch {}
    }

    // ---- КАЖДЫЕ 15 ЦИКЛОВ (30 мин) — Feature 7: Файлы в директориях ----
    if (monitorCycleCount % 15 === 12) {
      try {
        const dirs = await countDirFiles();
        for (const d of dirs) {
          const alertKey = `dirAlert_${d.name}`;
          if (d.count > DIR_FILE_ALERT_THRESHOLD && !lastState[alertKey]) {
            send(`📂 <b>Много файлов!</b>\n\n${d.name}: <b>${d.count} файлов</b>\nПуть: <code>${d.path}</code>\n\nВозможно, накапливаются старые отчёты.\nИспользуйте /diskfiles для деталей`);
            lastState[alertKey] = true;
          } else if (d.count <= DIR_FILE_ALERT_THRESHOLD && lastState[alertKey]) {
            lastState[alertKey] = false;
          }
        }
      } catch {}
    }

    // ---- КАЖДЫЕ 30 ЦИКЛОВ (1 час) — SSL-сертификат ----
    if (monitorCycleCount % 30 === 1) {
      try {
        const ssl = await checkSSL(SSL_DOMAIN);
        if (ssl.ok && ssl.daysLeft <= 14 && !lastState.sslAlert) {
          send(`🔴 <b>SSL-сертификат истекает через ${ssl.daysLeft} дней!</b>\n\n📅 ${ssl.expiryDate}\nНеобходимо продлить сертификат!`);
          lastState.sslAlert = true;
        } else if (ssl.ok && ssl.daysLeft > 14) {
          lastState.sslAlert = false;
        }
      } catch {}
    }

  } catch (err) {
    console.error('[Monitor] Error:', err.message);
  }
}

// Запуск мониторинга
setInterval(monitorLoop, CHECK_INTERVAL);

// Первая проверка через 10 сек после старта
setTimeout(monitorLoop, 10000);

// ============================================
// ЕЖЕДНЕВНЫЙ ОТЧЁТ В 22:00 (МСК)
// ============================================

let dailyReportTimer = null;

function scheduleDailyReport() {
  const now = new Date();
  // Московское время = UTC+3
  const mskHour = (now.getUTCHours() + 3) % 24;
  const mskMinute = now.getUTCMinutes();

  // Сколько минут до 22:00 МСК
  let minutesUntil22 = (22 * 60) - (mskHour * 60 + mskMinute);
  if (minutesUntil22 <= 0) minutesUntil22 += 24 * 60; // завтра

  console.log(`[Admin Bot] Следующий отчёт через ${Math.floor(minutesUntil22 / 60)}ч ${minutesUntil22 % 60}м`);

  dailyReportTimer = setTimeout(async () => {
    await sendDailyReport();
    // Запланировать следующий через 24ч
    setInterval(sendDailyReport, 24 * 60 * 60 * 1000);
  }, minutesUntil22 * 60 * 1000);
}

async function sendDailyReport() {
  try {
    const [loyalty, ocr, ramStr, diskStr, pm2Raw, errStats] = await Promise.all([
      httpCheck(LOYALTY_URL),
      httpCheck(OCR_URL),
      execCmd("free -m | awk '/^Mem:/ {printf \"%s/%s\", $3, $2}'"),
      execCmd("df -h / | awk 'NR==2 {printf \"%s/%s (%s)\", $3, $2, $5}'"),
      execCmd('pm2 jlist'),
      getErrorCounts(),
    ]);

    const date = new Date().toLocaleDateString('ru-RU', { timeZone: 'Europe/Moscow' });

    // Uptime
    let uptime = '—';
    if (loyalty.ok && loyalty.data?.uptime) {
      uptime = formatUptime(Math.floor(loyalty.data.uptime));
    }

    // Перезапуски за сегодня
    let restarts = 0;
    try {
      const processes = JSON.parse(pm2Raw);
      const lp = processes.find(p => p.name === 'loyalty-proxy');
      if (lp) restarts = lp.pm2_env.restart_time || 0;
    } catch {}

    // БД
    let dbSize = '—';
    try {
      const res = await pool.query("SELECT pg_database_size('arabica_db') as size");
      dbSize = formatBytes(parseInt(res.rows[0].size));
    } catch {}

    // Планировщики
    const schedulerStates = readSchedulerStates();
    const staleCount = schedulerStates.filter(s => s.isStale).length;
    const schedulerLine = staleCount === 0 ? '✅ все работают' : `⚠️ ${staleCount} зависли`;

    // Heap
    let heapLine = '—';
    if (heapHistory.length > 0) {
      const current = heapHistory[heapHistory.length - 1].heapUsed;
      const values = heapHistory.map(h => h.heapUsed);
      const min = Math.min(...values);
      const max = Math.max(...values);
      heapLine = `${formatBytes(current)} (min ${formatBytes(min)}, max ${formatBytes(max)})`;
    }

    // Ошибки — тренд
    const errTrend = errStats.today > errStats.weekAvg * 1.5 ? '📈' :
      errStats.today < errStats.weekAvg * 0.5 ? '📉' : '➡️';

    send(`📊 <b>Итоги дня ${date}</b>

<b>Сервисы:</b>
API: ${loyalty.ok ? '🟢' : '🔴'} ${uptime ? `uptime ${uptime}` : ''}
OCR: ${ocr.ok ? '🟢' : '🔴'}

<b>Система:</b>
RAM: ${ramStr.trim()}
Диск: ${diskStr.trim()}
Перезапусков: ${restarts}
Heap: ${heapLine}

<b>База:</b> ${dbSize}

<b>Ошибки:</b> ${errStats.today} ${errTrend} (ср. ${errStats.weekAvg}/день)
<b>Планировщики:</b> ${schedulerLine}`);
  } catch (err) {
    console.error('[DailyReport] Error:', err.message);
  }
}

scheduleDailyReport();

// ============================================
// АВТОБЭКАП В 3:00 МСК (каждую ночь)
// ============================================

function scheduleAutoBackup() {
  const now = new Date();
  const mskHour = (now.getUTCHours() + 3) % 24;
  const mskMinute = now.getUTCMinutes();

  let minutesUntil3 = (3 * 60) - (mskHour * 60 + mskMinute);
  if (minutesUntil3 <= 0) minutesUntil3 += 24 * 60;

  console.log(`[Admin Bot] Следующий автобэкап через ${Math.floor(minutesUntil3 / 60)}ч ${minutesUntil3 % 60}м`);

  setTimeout(async () => {
    await runAutoBackup();
    setInterval(runAutoBackup, 24 * 60 * 60 * 1000);
  }, minutesUntil3 * 60 * 1000);
}

async function runAutoBackup() {
  try {
    const date = new Date().toISOString().slice(0, 10);
    const backupPath = `/root/backups/auto_arabica_db_${date}.sql`;

    await execCmd('mkdir -p /root/backups');
    const result = await execCmd(`sudo -u postgres pg_dump arabica_db > ${backupPath} 2>&1`, 60000);

    if (!result.trim() || !result.includes('Error')) {
      // Удаляем бэкапы старше 7 дней
      await execCmd('find /root/backups -name "auto_arabica_db_*.sql" -mtime +7 -delete 2>/dev/null');

      const sizeStr = await execCmd(`ls -lh ${backupPath} | awk '{print $5}'`);
      const countStr = await execCmd('ls /root/backups/auto_arabica_db_*.sql 2>/dev/null | wc -l');
      console.log(`[AutoBackup] OK: ${backupPath} (${sizeStr.trim()})`);
      send(`🗄 <b>Автобэкап БД</b>\n\n✅ ${backupPath}\n📦 Размер: ${sizeStr.trim()}\n📁 Бэкапов хранится: ${countStr.trim()}/7`);
    } else {
      console.error('[AutoBackup] Failed:', result);
      send(`❌ <b>Автобэкап провалился!</b>\n\n<pre>${escapeHtml(result.slice(0, 1000))}</pre>`);
    }
  } catch (err) {
    console.error('[AutoBackup] Error:', err.message);
  }
}

scheduleAutoBackup();

// ============================================
// ЗАПУСК
// ============================================

console.log(`[Admin Bot] Запущен. Мониторинг каждые ${CHECK_INTERVAL / 1000} сек`);
console.log(`[Admin Bot] Admin ID: ${ADMIN_ID}`);

// Уведомление о старте через 5 сек (чтобы polling инициализировался)
setTimeout(() => {
  send('🤖 <b>Admin Bot запущен</b>\nОтправьте /help для списка команд');
}, 5000);

// Graceful shutdown
process.on('SIGINT', async () => {
  console.log('[Admin Bot] Завершение...');
  await pool.end();
  process.exit(0);
});

process.on('SIGTERM', async () => {
  console.log('[Admin Bot] Завершение...');
  await pool.end();
  process.exit(0);
});
