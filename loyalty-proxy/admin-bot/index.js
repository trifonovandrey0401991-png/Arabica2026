/**
 * Arabica Admin Bot — мониторинг и управление сервером через Telegram
 *
 * Запуск: pm2 start ecosystem.config.js
 * Зависимости: node-telegram-bot-api, pg (из родительского loyalty-proxy)
 */

const TelegramBot = require('node-telegram-bot-api');
const { exec } = require('child_process');
const http = require('http');
const { Pool } = require('pg');

// ============================================
// КОНФИГУРАЦИЯ
// ============================================

const BOT_TOKEN = process.env.BOT_TOKEN;
const ADMIN_ID = parseInt(process.env.ADMIN_ID || '600938652', 10);
const CHECK_INTERVAL = 2 * 60 * 1000; // Проверка каждые 2 минуты
const LOYALTY_URL = 'http://127.0.0.1:3000/health';
const OCR_URL = 'http://127.0.0.1:5001/health';

if (!BOT_TOKEN) {
  console.error('[Admin Bot] BOT_TOKEN не задан! Укажите в ecosystem.config.js');
  process.exit(1);
}

// ============================================
// ПОДКЛЮЧЕНИЕ К БД
// ============================================

const pool = new Pool({
  user: process.env.DB_USER || 'arabica_app',
  password: process.env.DB_PASSWORD || 'arabica2026secure',
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

function formatUptime(seconds) {
  const d = Math.floor(seconds / 86400);
  const h = Math.floor((seconds % 86400) / 3600);
  const m = Math.floor((seconds % 3600) / 60);
  if (d > 0) return `${d}д ${h}ч ${m}м`;
  if (h > 0) return `${h}ч ${m}м`;
  return `${m}м`;
}

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
/backup — бэкап базы данных

Бот автоматически оповестит если:
• loyalty-proxy или OCR упадёт
• RAM > 85%
• Диск > 90%`);
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
// АВТОМАТИЧЕСКИЙ МОНИТОРИНГ
// ============================================

const lastState = {
  loyalty: true,
  ocr: true,
  ramAlert: false,
  diskAlert: false,
};

async function monitorLoop() {
  try {
    const [loyalty, ocr, ramStr, diskStr] = await Promise.all([
      httpCheck(LOYALTY_URL),
      httpCheck(OCR_URL),
      execCmd("free -m | awk '/^Mem:/ {print $3, $2}'"),
      execCmd("df / | awk 'NR==2 {print $5}' | tr -d '%'"),
    ]);

    // loyalty-proxy
    if (!loyalty.ok && lastState.loyalty) {
      send('🔴 <b>ALERT: loyalty-proxy НЕ ОТВЕЧАЕТ!</b>\n\nИспользуйте /restart для перезапуска');
      lastState.loyalty = false;
    } else if (loyalty.ok && !lastState.loyalty) {
      send('🟢 loyalty-proxy снова онлайн');
      lastState.loyalty = true;
    }

    // ocr-server
    if (!ocr.ok && lastState.ocr) {
      send('🔴 <b>ALERT: OCR-сервер НЕ ОТВЕЧАЕТ!</b>\n\nИспользуйте /restart для перезапуска');
      lastState.ocr = false;
    } else if (ocr.ok && !lastState.ocr) {
      send('🟢 OCR-сервер снова онлайн');
      lastState.ocr = true;
    }

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
  } catch (err) {
    console.error('[Monitor] Error:', err.message);
  }
}

// Запуск мониторинга
setInterval(monitorLoop, CHECK_INTERVAL);

// Первая проверка через 10 сек после старта
setTimeout(monitorLoop, 10000);

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
