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
/db — статистика базы данных
/logs — последние 25 строк логов
/errors — ошибки из логов

<b>Управление:</b>
/restart — перезапуск процесса
/deploy — деплой (git pull + restart + тест)
/tests — запуск API тестов
/backup — бэкап базы данных

<b>Управление (продвинутое):</b>
/cmd &lt;команда&gt; — выполнить команду на сервере
/ssl — проверить SSL-сертификат

<b>Автоматически:</b>
• Оповещение если сервис упал
• Оповещение при ошибках 500
• Crash-loop детектор (5+ перезапусков)
• SSL-сертификат истекает &lt; 14 дней
• Замедление API &gt; 500ms
• RAM &gt; 85% / Диск &gt; 90%
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
    const [sizeRes, tablesRes, connRes] = await Promise.all([
      pool.query("SELECT pg_database_size('arabica_db') as size"),
      pool.query(`
        SELECT tablename, n_live_tup as rows
        FROM pg_stat_user_tables
        ORDER BY n_live_tup DESC LIMIT 10
      `),
      pool.query("SELECT count(*) as cnt FROM pg_stat_activity WHERE datname = 'arabica_db'"),
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
};

// Средняя скорость API (скользящее среднее)
let apiResponseTimes = [];

async function monitorLoop() {
  try {
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
      if (apiResponseTimes.length > 30) apiResponseTimes.shift(); // храним последние 30 замеров (1 час)
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

  } catch (err) {
    console.error('[Monitor] Error:', err.message);
  }
}

// SSL-проверка — раз в час (каждый 30-й цикл мониторинга)
let monitorCycleCount = 0;
const originalMonitorLoop = monitorLoop;
monitorLoop = async function() {
  await originalMonitorLoop();
  monitorCycleCount++;
  // Каждые 30 циклов (раз в час) проверяем SSL
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
};

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
    const [loyalty, ocr, ramStr, diskStr, pm2Raw, errCount] = await Promise.all([
      httpCheck(LOYALTY_URL),
      httpCheck(OCR_URL),
      execCmd("free -m | awk '/^Mem:/ {printf \"%s/%s\", $3, $2}'"),
      execCmd("df -h / | awk 'NR==2 {printf \"%s/%s (%s)\", $3, $2, $5}'"),
      execCmd('pm2 jlist'),
      execCmd("wc -l < /root/.pm2/logs/loyalty-proxy-error.log 2>/dev/null || echo 0"),
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

    send(`📊 <b>Итоги дня ${date}</b>

<b>Сервисы:</b>
API: ${loyalty.ok ? '🟢' : '🔴'} ${uptime ? `uptime ${uptime}` : ''}
OCR: ${ocr.ok ? '🟢' : '🔴'}

<b>Система:</b>
RAM: ${ramStr.trim()}
Диск: ${diskStr.trim()}
Перезапусков: ${restarts}

<b>База:</b> ${dbSize}
<b>Строк в error.log:</b> ${errCount.trim()}`);
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
