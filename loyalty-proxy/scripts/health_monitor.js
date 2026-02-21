#!/usr/bin/env node
/**
 * Health Monitor — arabica26.ru
 *
 * Проверяет: /health endpoint, PM2 процессы, RAM, disk.
 * При проблеме отправляет алерт в Telegram.
 *
 * Запуск: node scripts/health_monitor.js
 * Cron (каждые 5 минут, добавить через: crontab -e):
 *   *\/5 * * * * cd /root/arabica_app/loyalty-proxy && node scripts/health_monitor.js >> /var/log/arabica-health.log 2>&1
 */

const https = require('https');
const { execSync } = require('child_process');

// ── Конфигурация ─────────────────────────────────────────────────────────────
const CONFIG = {
  healthUrl: 'https://arabica26.ru/health',
  healthTimeoutMs: 10_000,
  ramThresholdPercent: 85,    // алерт если RAM > 85%
  diskThresholdPercent: 90,   // алерт если диск > 90%
  // Telegram: admin-bot используется для алертов мониторинга
  telegramBotToken: process.env.ARABICA_TG_TOKEN || '8451674364:AAFZDuvG-9wncMXTzt2CHM973YsQnrIHQPI',
  telegramChatId:   process.env.ARABICA_TG_CHAT_ID || '840309879',
};

const PM2_PROCESSES = ['loyalty-proxy', 'ocr-server', 'arabica-admin-bot'];

// ── Утилиты ──────────────────────────────────────────────────────────────────
function timestamp() {
  return new Date().toLocaleString('ru-RU', { timeZone: 'Europe/Moscow' });
}

function log(msg) {
  console.log(`[${timestamp()}] ${msg}`);
}

async function httpGet(url, timeoutMs) {
  return new Promise((resolve, reject) => {
    const req = https.get(url, { timeout: timeoutMs }, (res) => {
      let body = '';
      res.on('data', (chunk) => { body += chunk; });
      res.on('end', () => resolve({ status: res.statusCode, body }));
    });
    req.on('timeout', () => { req.destroy(); reject(new Error('timeout')); });
    req.on('error', reject);
  });
}

async function sendTelegramAlert(message) {
  if (!CONFIG.telegramBotToken || !CONFIG.telegramChatId) {
    log(`[ALERT] Telegram не настроен. Сообщение: ${message}`);
    return;
  }

  const text = encodeURIComponent(`🚨 *Arabica Monitor*\n\n${message}\n\n⏰ ${timestamp()}`);
  const url = `https://api.telegram.org/bot${CONFIG.telegramBotToken}/sendMessage?chat_id=${CONFIG.telegramChatId}&text=${text}&parse_mode=Markdown`;

  try {
    await httpGet(url, 5_000);
    log(`[ALERT] Telegram уведомление отправлено`);
  } catch (e) {
    log(`[ALERT] Ошибка отправки Telegram: ${e.message}`);
  }
}

// ── Проверки ─────────────────────────────────────────────────────────────────

/** Проверка /health endpoint */
async function checkHealth() {
  try {
    const { status, body } = await httpGet(CONFIG.healthUrl, CONFIG.healthTimeoutMs);
    if (status !== 200) {
      return { ok: false, reason: `/health вернул HTTP ${status}` };
    }
    try {
      const json = JSON.parse(body);
      if (json.status !== 'ok' && json.status !== 'healthy') {
        return { ok: false, reason: `/health: статус "${json.status}"` };
      }
    } catch (_) {
      // /health вернул не JSON — но статус 200, считаем живым
    }
    return { ok: true };
  } catch (e) {
    return { ok: false, reason: `/health недоступен: ${e.message}` };
  }
}

/** Проверка PM2 процессов */
function checkPm2() {
  const problems = [];
  try {
    const output = execSync('pm2 jlist 2>/dev/null', { encoding: 'utf8', timeout: 10_000 });
    const list = JSON.parse(output);
    const byName = {};
    for (const p of list) { byName[p.name] = p; }

    for (const name of PM2_PROCESSES) {
      if (!byName[name]) {
        problems.push(`PM2: процесс "${name}" не найден`);
      } else if (byName[name].pm2_env?.status !== 'online') {
        problems.push(`PM2: процесс "${name}" в статусе "${byName[name].pm2_env?.status}"`);
      }
    }
  } catch (e) {
    problems.push(`PM2: не удалось получить список процессов: ${e.message}`);
  }
  return problems;
}

/** Проверка использования RAM */
function checkRam() {
  try {
    const output = execSync('free -m', { encoding: 'utf8', timeout: 5_000 });
    const lines = output.trim().split('\n');
    // Формат: Mem:  total  used  free  shared  buff/cache  available
    const parts = lines[1].trim().split(/\s+/);
    const total = parseInt(parts[1]);
    const used  = parseInt(parts[2]);
    const percent = Math.round((used / total) * 100);
    if (percent >= CONFIG.ramThresholdPercent) {
      return { ok: false, reason: `RAM: ${percent}% используется (${used}MB / ${total}MB)` };
    }
    return { ok: true, info: `RAM: ${percent}% (${used}/${total}MB)` };
  } catch (e) {
    return { ok: true, info: `RAM: не удалось проверить` }; // не критично
  }
}

/** Проверка дискового пространства */
function checkDisk() {
  try {
    const output = execSync("df -h / | tail -1", { encoding: 'utf8', timeout: 5_000 });
    const parts = output.trim().split(/\s+/);
    const usePercent = parseInt(parts[4]); // "85%"
    if (usePercent >= CONFIG.diskThresholdPercent) {
      return { ok: false, reason: `Диск: ${parts[4]} заполнен (${parts[2]} из ${parts[1]})` };
    }
    return { ok: true, info: `Диск: ${parts[4]} (${parts[2]}/${parts[1]})` };
  } catch (e) {
    return { ok: true, info: `Диск: не удалось проверить` };
  }
}

// ── Главная функция ───────────────────────────────────────────────────────────
async function main() {
  const problems = [];

  // 1. HTTP health check
  const health = await checkHealth();
  if (!health.ok) {
    problems.push(health.reason);
    log(`❌ ${health.reason}`);
  } else {
    log(`✅ /health OK`);
  }

  // 2. PM2 процессы
  const pm2Problems = checkPm2();
  for (const p of pm2Problems) {
    problems.push(p);
    log(`❌ ${p}`);
  }
  if (pm2Problems.length === 0) log(`✅ PM2: все процессы online`);

  // 3. RAM
  const ram = checkRam();
  if (!ram.ok) {
    problems.push(ram.reason);
    log(`❌ ${ram.reason}`);
  } else {
    log(`✅ ${ram.info}`);
  }

  // 4. Диск
  const disk = checkDisk();
  if (!disk.ok) {
    problems.push(disk.reason);
    log(`❌ ${disk.reason}`);
  } else {
    log(`✅ ${disk.info}`);
  }

  // Отправляем алерт если есть проблемы
  if (problems.length > 0) {
    const msg = `Обнаружено ${problems.length} проблем(ы):\n\n` +
      problems.map((p, i) => `${i + 1}. ${p}`).join('\n');
    await sendTelegramAlert(msg);
    process.exit(1); // Сигнал для cron что проверка провалена
  } else {
    log(`✅ Всё в порядке`);
  }
}

main().catch((e) => {
  log(`FATAL: ${e.message}`);
  process.exit(2);
});
