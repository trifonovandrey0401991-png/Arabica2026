/**
 * Data Cleanup API
 *
 * REFACTORED: Converted from sync to async I/O (2026-02-05)
 */

const fsp = require('fs').promises;
const path = require('path');
const { execSync } = require('child_process');
const { fileExists } = require('../utils/file_helpers');
const DATA_DIR = process.env.DATA_DIR || '/var/www';


// Категории данных, которые можно очищать
// Разделены на группы: отчёты, фото, история операций
const CLEANUP_CATEGORIES = [
  // === ОТЧЁТЫ ===
  {
    id: 'recount-reports',
    name: 'Отчёты пересчётов',
    directory: `${DATA_DIR}/recount-reports`,
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'shift-reports',
    name: 'Отчёты смен',
    directory: `${DATA_DIR}/shift-reports`,
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'shift-handover-reports',
    name: 'Отчёты пересменок',
    directory: `${DATA_DIR}/shift-handover-reports`,
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'envelope-reports',
    name: 'Отчёты конвертов',
    directory: `${DATA_DIR}/envelope-reports`,
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'rko-reports',
    name: 'РКО отчёты',
    directory: `${DATA_DIR}/rko-reports`,
    dateField: 'createdAt',
    isDirectory: true
  },

  // === ФОТО ===
  {
    id: 'shift-photos',
    name: 'Фото смен',
    directory: `${DATA_DIR}/shift-photos`,
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'shift-handover-question-photos',
    name: 'Фото вопросов пересменок',
    directory: `${DATA_DIR}/shift-handover-question-photos`,
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'product-question-photos',
    name: 'Фото вопросов товаров',
    directory: `${DATA_DIR}/product-question-photos`,
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'employee-photos',
    name: 'Фото сотрудников',
    directory: `${DATA_DIR}/employee-photos`,
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'recipe-photos',
    name: 'Фото рецептов',
    directory: `${DATA_DIR}/recipe-photos`,
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'chat-media',
    name: 'Медиа чатов',
    directory: `${DATA_DIR}/chat-media`,
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },

  // === ИСТОРИЯ ОПЕРАЦИЙ ===
  {
    id: 'orders',
    name: 'Заказы',
    directory: `${DATA_DIR}/orders`,
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'withdrawals',
    name: 'Выемки',
    directory: `${DATA_DIR}/withdrawals`,
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'attendance',
    name: 'Посещаемость',
    directory: `${DATA_DIR}/attendance`,
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'test-results',
    name: 'Результаты тестов',
    directory: `${DATA_DIR}/test-results`,
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'reviews',
    name: 'Отзывы',
    directory: `${DATA_DIR}/reviews`,
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'efficiency-penalties',
    name: 'Штрафы эффективности',
    directory: `${DATA_DIR}/efficiency-penalties`,
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'bonus-penalties',
    name: 'Премии/Штрафы',
    directory: `${DATA_DIR}/bonus-penalties`,
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'employee-registrations',
    name: 'Заявки на регистрацию',
    directory: `${DATA_DIR}/employee-registrations`,
    dateField: 'createdAt',
    isDirectory: true
  },

  // === ЛОГИ ===
  {
    id: 'app-logs',
    name: 'Логи приложения',
    directory: `${DATA_DIR}/app-logs`,
    dateField: 'timestamp',
    isDirectory: true
  },
  {
    id: 'fcm-tokens',
    name: 'FCM токены',
    directory: `${DATA_DIR}/fcm-tokens`,
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true  // Используем mtime для файлов
  }
];

// Получить размер директории рекурсивно
async function getDirectorySize(dirPath) {
  let totalSize = 0;

  try {
    if (!(await fileExists(dirPath))) return 0;

    const items = await fsp.readdir(dirPath);
    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = await fsp.stat(itemPath);

      if (stat.isDirectory()) {
        totalSize += await getDirectorySize(itemPath);
      } else {
        totalSize += stat.size;
      }
    }
  } catch (err) {
    console.error(`Error getting size of ${dirPath}:`, err.message);
  }

  return totalSize;
}

// Получить количество файлов в директории
async function getFileCount(dirPath) {
  try {
    if (!(await fileExists(dirPath))) return 0;

    let count = 0;
    const items = await fsp.readdir(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = await fsp.stat(itemPath);

      if (stat.isDirectory()) {
        count += await getFileCount(itemPath);
      } else if (item.endsWith('.json') || item.endsWith('.jpg') || item.endsWith('.png')) {
        count++;
      }
    }

    return count;
  } catch (err) {
    console.error(`Error counting files in ${dirPath}:`, err.message);
    return 0;
  }
}

// Получить даты самого старого и нового файла
async function getDateRange(dirPath, dateField) {
  let oldestDate = null;
  let newestDate = null;

  try {
    if (!(await fileExists(dirPath))) return { oldestDate, newestDate };

    const items = await fsp.readdir(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = await fsp.stat(itemPath);

      if (stat.isDirectory()) {
        const subRange = await getDateRange(itemPath, dateField);
        if (subRange.oldestDate) {
          if (!oldestDate || subRange.oldestDate < oldestDate) {
            oldestDate = subRange.oldestDate;
          }
        }
        if (subRange.newestDate) {
          if (!newestDate || subRange.newestDate > newestDate) {
            newestDate = subRange.newestDate;
          }
        }
      } else if (item.endsWith('.json')) {
        try {
          const content = await fsp.readFile(itemPath, 'utf8');
          const data = JSON.parse(content);
          const dateValue = data[dateField];

          if (dateValue) {
            const date = new Date(dateValue);
            if (!isNaN(date.getTime())) {
              if (!oldestDate || date < oldestDate) oldestDate = date;
              if (!newestDate || date > newestDate) newestDate = date;
            }
          }
        } catch (e) {
          // Skip files that can't be parsed
        }
      } else if (dateField === 'mtime') {
        // For photos, use file modification time
        const mtime = stat.mtime;
        if (!oldestDate || mtime < oldestDate) oldestDate = mtime;
        if (!newestDate || mtime > newestDate) newestDate = mtime;
      }
    }
  } catch (err) {
    console.error(`Error getting date range for ${dirPath}:`, err.message);
  }

  return { oldestDate, newestDate };
}

// Получить файлы для удаления до определённой даты
async function getFilesToDelete(dirPath, dateField, beforeDate, isPhotos = false) {
  const filesToDelete = [];

  try {
    if (!(await fileExists(dirPath))) return filesToDelete;

    const items = await fsp.readdir(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = await fsp.stat(itemPath);

      if (stat.isDirectory()) {
        const subFiles = await getFilesToDelete(itemPath, dateField, beforeDate, isPhotos);
        filesToDelete.push(...subFiles);
      } else if (item.endsWith('.json')) {
        try {
          const content = await fsp.readFile(itemPath, 'utf8');
          const data = JSON.parse(content);
          const dateValue = data[dateField];

          if (dateValue) {
            const fileDate = new Date(dateValue);
            if (!isNaN(fileDate.getTime()) && fileDate < beforeDate) {
              filesToDelete.push(itemPath);
            }
          }
        } catch (e) {
          // Skip files that can't be parsed
        }
      } else if (isPhotos && (item.endsWith('.jpg') || item.endsWith('.png'))) {
        // For photos, use file modification time
        if (stat.mtime < beforeDate) {
          filesToDelete.push(itemPath);
        }
      }
    }
  } catch (err) {
    console.error(`Error finding files to delete in ${dirPath}:`, err.message);
  }

  return filesToDelete;
}

// Удалить файлы
async function deleteFiles(filePaths) {
  let deletedCount = 0;
  let freedBytes = 0;

  for (const filePath of filePaths) {
    try {
      const stat = await fsp.stat(filePath);
      freedBytes += stat.size;
      await fsp.unlink(filePath);
      deletedCount++;
    } catch (err) {
      console.error(`Error deleting ${filePath}:`, err.message);
    }
  }

  return { deletedCount, freedBytes };
}

// Удалить пустые директории
async function removeEmptyDirectories(dirPath) {
  try {
    if (!(await fileExists(dirPath))) return;

    const items = await fsp.readdir(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = await fsp.stat(itemPath);

      if (stat.isDirectory()) {
        await removeEmptyDirectories(itemPath);

        // Check if directory is now empty
        const remaining = await fsp.readdir(itemPath);
        if (remaining.length === 0) {
          await fsp.rmdir(itemPath);
        }
      }
    }
  } catch (err) {
    console.error(`Error removing empty directories in ${dirPath}:`, err.message);
  }
}

// Получить информацию о дисковом пространстве
function getDiskInfo() {
  try {
    // Для Linux используем df команду
    const output = execSync('df -B1 /var/www', { encoding: 'utf8' });
    const lines = output.trim().split('\n');

    if (lines.length >= 2) {
      // Парсим вторую строку (данные)
      const parts = lines[1].split(/\s+/);
      // Формат: Filesystem 1B-blocks Used Available Use% Mounted
      const totalBytes = parseInt(parts[1], 10);
      const usedBytes = parseInt(parts[2], 10);
      const availableBytes = parseInt(parts[3], 10);

      return {
        totalBytes,
        usedBytes,
        availableBytes,
        usedPercent: Math.round((usedBytes / totalBytes) * 100)
      };
    }
  } catch (err) {
    console.error('Error getting disk info:', err.message);
  }

  // Fallback значения если не удалось получить
  return {
    totalBytes: 10 * 1024 * 1024 * 1024, // 10 GB
    usedBytes: 0,
    availableBytes: 10 * 1024 * 1024 * 1024,
    usedPercent: 0
  };
}

function setupDataCleanupAPI(app) {
  // SECURITY: Middleware для проверки админских прав на всех /api/admin/* маршрутах
  app.use('/api/admin', (req, res, next) => {
    if (!req.user || !req.user.isAdmin) {
      return res.status(403).json({
        success: false,
        error: 'Доступ запрещён. Требуются права администратора.'
      });
    }
    next();
  });

  // GET /api/admin/disk-info - информация о дисковом пространстве
  app.get('/api/admin/disk-info', (req, res) => {
    try {
      const diskInfo = getDiskInfo();
      res.json({
        success: true,
        ...diskInfo
      });
    } catch (error) {
      console.error('Error getting disk info:', error);
      res.status(500).json({
        success: false,
        error: 'Ошибка получения информации о диске'
      });
    }
  });

  // GET /api/admin/data-stats - статистика по категориям данных
  app.get('/api/admin/data-stats', async (req, res) => {
    try {
      const categories = [];
      for (const cat of CLEANUP_CATEGORIES) {
        const size = await getDirectorySize(cat.directory);
        const count = await getFileCount(cat.directory);
        const { oldestDate, newestDate } = await getDateRange(cat.directory, cat.dateField);

        categories.push({
          id: cat.id,
          name: cat.name,
          count,
          sizeBytes: size,
          oldestDate: oldestDate ? oldestDate.toISOString().split('T')[0] : null,
          newestDate: newestDate ? newestDate.toISOString().split('T')[0] : null
        });
      }

      // Filter out categories with no data
      const nonEmptyCategories = categories.filter(c => c.count > 0 || c.sizeBytes > 0);

      res.json({
        success: true,
        categories: nonEmptyCategories
      });
    } catch (error) {
      console.error('Error getting data stats:', error);
      res.status(500).json({
        success: false,
        error: 'Ошибка получения статистики'
      });
    }
  });

  // GET /api/admin/cleanup-preview - предварительный просмотр удаления
  app.get('/api/admin/cleanup-preview', async (req, res) => {
    try {
      const { category, beforeDate } = req.query;

      if (!category || !beforeDate) {
        return res.status(400).json({
          success: false,
          error: 'Требуются параметры category и beforeDate'
        });
      }

      const cat = CLEANUP_CATEGORIES.find(c => c.id === category);
      if (!cat) {
        return res.status(404).json({
          success: false,
          error: 'Категория не найдена'
        });
      }

      const date = new Date(beforeDate);
      if (isNaN(date.getTime())) {
        return res.status(400).json({
          success: false,
          error: 'Неверный формат даты'
        });
      }

      const filesToDelete = await getFilesToDelete(cat.directory, cat.dateField, date, cat.isPhotos);

      // Calculate total size
      let totalSize = 0;
      for (const filePath of filesToDelete) {
        try {
          const stat = await fsp.stat(filePath);
          totalSize += stat.size;
        } catch (e) {
          // Skip
        }
      }

      res.json({
        success: true,
        count: filesToDelete.length,
        sizeBytes: totalSize
      });
    } catch (error) {
      console.error('Error getting cleanup preview:', error);
      res.status(500).json({
        success: false,
        error: 'Ошибка предварительного просмотра'
      });
    }
  });

  // POST /api/admin/cleanup - выполнить очистку
  app.post('/api/admin/cleanup', async (req, res) => {
    try {
      const { category, beforeDate } = req.body;

      if (!category || !beforeDate) {
        return res.status(400).json({
          success: false,
          error: 'Требуются параметры category и beforeDate'
        });
      }

      const cat = CLEANUP_CATEGORIES.find(c => c.id === category);
      if (!cat) {
        return res.status(404).json({
          success: false,
          error: 'Категория не найдена'
        });
      }

      const date = new Date(beforeDate);
      if (isNaN(date.getTime())) {
        return res.status(400).json({
          success: false,
          error: 'Неверный формат даты'
        });
      }

      console.log(`[Cleanup] Starting cleanup for ${category} before ${beforeDate}`);

      const filesToDelete = await getFilesToDelete(cat.directory, cat.dateField, date, cat.isPhotos);
      const { deletedCount, freedBytes } = await deleteFiles(filesToDelete);

      // Clean up empty directories
      await removeEmptyDirectories(cat.directory);

      console.log(`[Cleanup] Deleted ${deletedCount} files, freed ${freedBytes} bytes`);

      res.json({
        success: true,
        deletedCount,
        freedBytes
      });
    } catch (error) {
      console.error('Error performing cleanup:', error);
      res.status(500).json({
        success: false,
        error: 'Ошибка очистки данных'
      });
    }
  });

  console.log('✅ Data Cleanup API initialized');
}

// ============================================
// AUTO CLEANUP SCHEDULER
// Ежедневная автоочистка старых данных в 3:00 ночи
// ============================================

// Период хранения по типу данных (в днях)
const RETENTION_DAYS = {
  'app-logs': 30,         // Логи — 30 дней
  'fcm-tokens': 60,       // FCM токены — 60 дней
  'test-results': 90,     // Тесты — 90 дней
  'orders': 180,          // Заказы — 180 дней
  'reviews': 180,         // Отзывы — 180 дней
  'employee-registrations': 90, // Заявки — 90 дней
  'chat-media': 90,       // Медиа чатов — 90 дней
};

// Очистка expired сессий
async function cleanupExpiredSessions() {
  const sessionsDir = `${DATA_DIR}/auth-sessions`;
  let cleaned = 0;
  try {
    if (!(await fileExists(sessionsDir))) return 0;
    const files = (await fsp.readdir(sessionsDir)).filter(f => f.endsWith('.json'));
    const now = Date.now();
    for (const file of files) {
      try {
        const filePath = path.join(sessionsDir, file);
        const content = await fsp.readFile(filePath, 'utf8');
        const session = JSON.parse(content);
        if (session.expiresAt && session.expiresAt < now) {
          await fsp.unlink(filePath);
          cleaned++;
        }
      } catch (e) { /* skip */ }
    }
  } catch (e) {
    console.error('[AutoCleanup] Error cleaning sessions:', e.message);
  }
  return cleaned;
}

async function runAutoCleanup() {
  console.log('[AutoCleanup] Начинаю автоматическую очистку...');
  const startTime = Date.now();
  let totalDeleted = 0;
  let totalFreed = 0;

  // 1. Очистка expired сессий
  const sessionsCleared = await cleanupExpiredSessions();
  totalDeleted += sessionsCleared;
  if (sessionsCleared > 0) {
    console.log(`[AutoCleanup] Очищено expired сессий: ${sessionsCleared}`);
  }

  // 2. Очистка категорий с настроенным retention
  for (const [categoryId, retentionDays] of Object.entries(RETENTION_DAYS)) {
    const cat = CLEANUP_CATEGORIES.find(c => c.id === categoryId);
    if (!cat) continue;

    try {
      const beforeDate = new Date();
      beforeDate.setDate(beforeDate.getDate() - retentionDays);

      const filesToDelete = await getFilesToDelete(cat.directory, cat.dateField, beforeDate, cat.isPhotos);
      if (filesToDelete.length > 0) {
        const { deletedCount, freedBytes } = await deleteFiles(filesToDelete);
        await removeEmptyDirectories(cat.directory);
        totalDeleted += deletedCount;
        totalFreed += freedBytes;
        console.log(`[AutoCleanup] ${cat.name}: удалено ${deletedCount} файлов (${Math.round(freedBytes / 1024)}KB)`);
      }
    } catch (e) {
      console.error(`[AutoCleanup] Ошибка очистки ${categoryId}:`, e.message);
    }
  }

  const elapsed = Date.now() - startTime;
  console.log(`[AutoCleanup] Завершено за ${elapsed}ms. Удалено: ${totalDeleted}, Освобождено: ${Math.round(totalFreed / 1024)}KB`);
}

function startAutoCleanupScheduler() {
  // Запускаем ежедневно в 3:00 ночи
  const now = new Date();
  const target = new Date(now);
  target.setHours(3, 0, 0, 0);
  if (target <= now) {
    target.setDate(target.getDate() + 1);
  }

  const msUntilFirst = target.getTime() - now.getTime();

  setTimeout(() => {
    runAutoCleanup().catch(e => console.error('[AutoCleanup] Error:', e.message));
    // Далее каждые 24 часа
    setInterval(() => {
      runAutoCleanup().catch(e => console.error('[AutoCleanup] Error:', e.message));
    }, 24 * 60 * 60 * 1000);
  }, msUntilFirst);

  console.log(`✅ AutoCleanup scheduler started. First run in ${Math.round(msUntilFirst / 60000)} minutes (at 03:00)`);
}

module.exports = { setupDataCleanupAPI, startAutoCleanupScheduler };
