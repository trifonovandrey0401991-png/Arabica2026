const fs = require('fs');
const path = require('path');
const { execSync } = require('child_process');

// Категории данных, которые можно очищать
// Разделены на группы: отчёты, фото, история операций
const CLEANUP_CATEGORIES = [
  // === ОТЧЁТЫ ===
  {
    id: 'recount-reports',
    name: 'Отчёты пересчётов',
    directory: '/var/www/recount-reports',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'shift-reports',
    name: 'Отчёты смен',
    directory: '/var/www/shift-reports',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'shift-handover-reports',
    name: 'Отчёты пересменок',
    directory: '/var/www/shift-handover-reports',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'envelope-reports',
    name: 'Отчёты конвертов',
    directory: '/var/www/envelope-reports',
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'rko-reports',
    name: 'РКО отчёты',
    directory: '/var/www/rko-reports',
    dateField: 'createdAt',
    isDirectory: true
  },

  // === ФОТО ===
  {
    id: 'shift-photos',
    name: 'Фото смен',
    directory: '/var/www/shift-photos',
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'shift-handover-question-photos',
    name: 'Фото вопросов пересменок',
    directory: '/var/www/shift-handover-question-photos',
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'product-question-photos',
    name: 'Фото вопросов товаров',
    directory: '/var/www/product-question-photos',
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'employee-photos',
    name: 'Фото сотрудников',
    directory: '/var/www/employee-photos',
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },
  {
    id: 'recipe-photos',
    name: 'Фото рецептов',
    directory: '/var/www/recipe-photos',
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
  },

  // === ИСТОРИЯ ОПЕРАЦИЙ ===
  {
    id: 'orders',
    name: 'Заказы',
    directory: '/var/www/orders',
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'withdrawals',
    name: 'Выемки',
    directory: '/var/www/withdrawals',
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'attendance',
    name: 'Посещаемость',
    directory: '/var/www/attendance',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'test-results',
    name: 'Результаты тестов',
    directory: '/var/www/test-results',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'reviews',
    name: 'Отзывы',
    directory: '/var/www/reviews',
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'efficiency-penalties',
    name: 'Штрафы эффективности',
    directory: '/var/www/efficiency-penalties',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'bonus-penalties',
    name: 'Премии/Штрафы',
    directory: '/var/www/bonus-penalties',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'employee-registrations',
    name: 'Заявки на регистрацию',
    directory: '/var/www/employee-registrations',
    dateField: 'createdAt',
    isDirectory: true
  },

  // === ЛОГИ ===
  {
    id: 'app-logs',
    name: 'Логи приложения',
    directory: '/var/www/app-logs',
    dateField: 'timestamp',
    isDirectory: true
  },
  {
    id: 'fcm-tokens',
    name: 'FCM токены',
    directory: '/var/www/fcm-tokens',
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true  // Используем mtime для файлов
  }
];

// Получить размер директории рекурсивно
function getDirectorySize(dirPath) {
  let totalSize = 0;

  try {
    if (!fs.existsSync(dirPath)) return 0;

    const items = fs.readdirSync(dirPath);
    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = fs.statSync(itemPath);

      if (stat.isDirectory()) {
        totalSize += getDirectorySize(itemPath);
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
function getFileCount(dirPath) {
  try {
    if (!fs.existsSync(dirPath)) return 0;

    let count = 0;
    const items = fs.readdirSync(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = fs.statSync(itemPath);

      if (stat.isDirectory()) {
        count += getFileCount(itemPath);
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
function getDateRange(dirPath, dateField) {
  let oldestDate = null;
  let newestDate = null;

  try {
    if (!fs.existsSync(dirPath)) return { oldestDate, newestDate };

    const items = fs.readdirSync(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = fs.statSync(itemPath);

      if (stat.isDirectory()) {
        const subRange = getDateRange(itemPath, dateField);
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
          const content = fs.readFileSync(itemPath, 'utf8');
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
function getFilesToDelete(dirPath, dateField, beforeDate, isPhotos = false) {
  const filesToDelete = [];

  try {
    if (!fs.existsSync(dirPath)) return filesToDelete;

    const items = fs.readdirSync(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = fs.statSync(itemPath);

      if (stat.isDirectory()) {
        const subFiles = getFilesToDelete(itemPath, dateField, beforeDate, isPhotos);
        filesToDelete.push(...subFiles);
      } else if (item.endsWith('.json')) {
        try {
          const content = fs.readFileSync(itemPath, 'utf8');
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
function deleteFiles(filePaths) {
  let deletedCount = 0;
  let freedBytes = 0;

  for (const filePath of filePaths) {
    try {
      const stat = fs.statSync(filePath);
      freedBytes += stat.size;
      fs.unlinkSync(filePath);
      deletedCount++;
    } catch (err) {
      console.error(`Error deleting ${filePath}:`, err.message);
    }
  }

  return { deletedCount, freedBytes };
}

// Удалить пустые директории
function removeEmptyDirectories(dirPath) {
  try {
    if (!fs.existsSync(dirPath)) return;

    const items = fs.readdirSync(dirPath);

    for (const item of items) {
      const itemPath = path.join(dirPath, item);
      const stat = fs.statSync(itemPath);

      if (stat.isDirectory()) {
        removeEmptyDirectories(itemPath);

        // Check if directory is now empty
        const remaining = fs.readdirSync(itemPath);
        if (remaining.length === 0) {
          fs.rmdirSync(itemPath);
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
  app.get('/api/admin/data-stats', (req, res) => {
    try {
      const categories = CLEANUP_CATEGORIES.map(cat => {
        const size = getDirectorySize(cat.directory);
        const count = getFileCount(cat.directory);
        const { oldestDate, newestDate } = getDateRange(cat.directory, cat.dateField);

        return {
          id: cat.id,
          name: cat.name,
          count,
          sizeBytes: size,
          oldestDate: oldestDate ? oldestDate.toISOString().split('T')[0] : null,
          newestDate: newestDate ? newestDate.toISOString().split('T')[0] : null
        };
      });

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
  app.get('/api/admin/cleanup-preview', (req, res) => {
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

      const filesToDelete = getFilesToDelete(cat.directory, cat.dateField, date, cat.isPhotos);

      // Calculate total size
      let totalSize = 0;
      for (const filePath of filesToDelete) {
        try {
          const stat = fs.statSync(filePath);
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
  app.post('/api/admin/cleanup', (req, res) => {
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

      const filesToDelete = getFilesToDelete(cat.directory, cat.dateField, date, cat.isPhotos);
      const { deletedCount, freedBytes } = deleteFiles(filesToDelete);

      // Clean up empty directories
      removeEmptyDirectories(cat.directory);

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

module.exports = { setupDataCleanupAPI };
