/**
 * Messenger Media Cleanup Scheduler
 *
 * Ежедневно в 4:00 по МСК удаляет медиафайлы мессенджера старше N дней,
 * если соответствующее сообщение удалено (is_deleted=true) или файл
 * не привязан ни к одному сообщению.
 *
 * Настраивается через env переменные:
 * - MESSENGER_MEDIA_CLEANUP_ENABLED=true (default: false)
 * - MESSENGER_MEDIA_RETENTION_DAYS=90 (default: 90)
 * - MESSENGER_MEDIA_CLEANUP_HOUR=4 (час МСК, default: 4)
 *
 * Логика безопасная:
 * - Удаляются ТОЛЬКО файлы старше retention_days
 * - Файлы, привязанные к живым сообщениям, НЕ удаляются
 * - Сухой прогон (dry run) логируется первые 5 запусков
 */

const path = require('path');
const fsp = require('fs').promises;
const { getMoscowTime } = require('../utils/moscow_time');
const db = require('../utils/db');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const MEDIA_DIR = path.join(DATA_DIR, 'messenger-media');

const ENABLED = process.env.MESSENGER_MEDIA_CLEANUP_ENABLED === 'true';
const RETENTION_DAYS = parseInt(process.env.MESSENGER_MEDIA_RETENTION_DAYS, 10) || 90;
const CLEANUP_HOUR = parseInt(process.env.MESSENGER_MEDIA_CLEANUP_HOUR, 10) || 4;

let cleanupTimer = null;
let isRunning = false;
let runCount = 0;

/**
 * Запуск планировщика — проверяет каждые 30 минут, не пора ли чистить
 */
function startMessengerMediaCleanupScheduler() {
  if (!ENABLED) {
    console.log('📁 Messenger media cleanup: DISABLED (set MESSENGER_MEDIA_CLEANUP_ENABLED=true)');
    return;
  }

  console.log(`📁 Messenger media cleanup: enabled, retention=${RETENTION_DAYS} days, cleanup at ${CLEANUP_HOUR}:00 MSK`);

  // Проверяем каждые 30 минут
  cleanupTimer = setInterval(() => {
    const now = getMoscowTime();
    if (now.getHours() === CLEANUP_HOUR && now.getMinutes() < 30) {
      runCleanup();
    }
  }, 30 * 60 * 1000);
}

/**
 * Основная функция очистки
 */
async function runCleanup() {
  if (isRunning) return;
  isRunning = true;
  runCount++;

  // Первые 5 запусков — dry run (только логируем, не удаляем)
  const dryRun = runCount <= 5;

  console.log(`📁 Media cleanup: starting${dryRun ? ' (DRY RUN #' + runCount + ')' : ''}...`);

  try {
    // 1. Получаем список всех файлов в директории
    let files;
    try {
      files = await fsp.readdir(MEDIA_DIR);
    } catch (e) {
      console.log('📁 Media cleanup: directory not found, skipping');
      isRunning = false;
      return;
    }

    if (files.length === 0) {
      console.log('📁 Media cleanup: no files, skipping');
      isRunning = false;
      return;
    }

    // 2. Фильтруем файлы старше RETENTION_DAYS по mtime
    const cutoffDate = new Date();
    cutoffDate.setDate(cutoffDate.getDate() - RETENTION_DAYS);

    const oldFiles = [];
    for (const filename of files) {
      try {
        const filePath = path.join(MEDIA_DIR, filename);
        const stat = await fsp.stat(filePath);
        if (stat.isFile() && stat.mtime < cutoffDate) {
          oldFiles.push({ filename, filePath, size: stat.size, mtime: stat.mtime });
        }
      } catch (_) { /* skip unreadable files */ }
    }

    if (oldFiles.length === 0) {
      console.log(`📁 Media cleanup: no files older than ${RETENTION_DAYS} days`);
      isRunning = false;
      return;
    }

    // 3. Проверяем какие из старых файлов ещё используются живыми сообщениями
    const oldFilenames = oldFiles.map(f => f.filename);

    // Строим LIKE-паттерны для проверки media_url
    // media_url хранится как полный URL: https://arabica26.ru/messenger-media/filename
    const usedResult = await db.query(`
      SELECT DISTINCT media_url
      FROM messenger_messages
      WHERE is_deleted = false
        AND media_url IS NOT NULL
        AND media_url != ''
    `);

    const usedFilenames = new Set();
    for (const row of usedResult.rows) {
      // Извлекаем имя файла из URL
      const url = row.media_url || '';
      const parts = url.split('/');
      const fname = parts[parts.length - 1];
      if (fname) usedFilenames.add(fname);
    }

    // 4. Файлы для удаления = старые И не используемые
    const toDelete = oldFiles.filter(f => !usedFilenames.has(f.filename));
    const totalSizeMB = toDelete.reduce((sum, f) => sum + f.size, 0) / (1024 * 1024);

    console.log(`📁 Media cleanup: ${oldFiles.length} old files, ${toDelete.length} orphaned (${totalSizeMB.toFixed(1)}MB)`);

    if (toDelete.length === 0) {
      isRunning = false;
      return;
    }

    if (dryRun) {
      console.log(`📁 DRY RUN: would delete ${toDelete.length} files (${totalSizeMB.toFixed(1)}MB). First 5:`);
      for (const f of toDelete.slice(0, 5)) {
        console.log(`  - ${f.filename} (${(f.size / 1024).toFixed(1)}KB, mtime: ${f.mtime.toISOString().slice(0, 10)})`);
      }
      isRunning = false;
      return;
    }

    // 5. Удаляем файлы
    let deleted = 0;
    let errors = 0;
    for (const f of toDelete) {
      try {
        await fsp.unlink(f.filePath);
        deleted++;
      } catch (e) {
        errors++;
      }
    }

    console.log(`📁 Media cleanup done: ${deleted} deleted, ${errors} errors, freed ${totalSizeMB.toFixed(1)}MB`);
  } catch (error) {
    console.error('📁 Media cleanup error:', error.message);
  } finally {
    isRunning = false;
  }
}

/**
 * Статистика для мониторинга
 */
async function getMediaStats() {
  try {
    let files;
    try {
      files = await fsp.readdir(MEDIA_DIR);
    } catch (_) {
      return { totalFiles: 0, totalSizeMB: 0, oldestFile: null };
    }

    let totalSize = 0;
    let oldestMtime = null;

    for (const filename of files) {
      try {
        const stat = await fsp.stat(path.join(MEDIA_DIR, filename));
        if (stat.isFile()) {
          totalSize += stat.size;
          if (!oldestMtime || stat.mtime < oldestMtime) {
            oldestMtime = stat.mtime;
          }
        }
      } catch (_) {}
    }

    return {
      totalFiles: files.length,
      totalSizeMB: +(totalSize / (1024 * 1024)).toFixed(1),
      oldestFile: oldestMtime ? oldestMtime.toISOString().slice(0, 10) : null,
      retentionDays: RETENTION_DAYS,
      enabled: ENABLED,
      runCount,
    };
  } catch (_) {
    return { error: 'Failed to read media directory' };
  }
}

function stopScheduler() {
  if (cleanupTimer) {
    clearInterval(cleanupTimer);
    cleanupTimer = null;
  }
}

module.exports = {
  startMessengerMediaCleanupScheduler,
  runCleanup,
  getMediaStats,
  stopScheduler,
};
