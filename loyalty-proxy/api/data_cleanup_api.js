const fs = require('fs');
const path = require('path');

// Категории данных, которые можно очищать
const CLEANUP_CATEGORIES = [
  {
    id: 'shifts',
    name: 'История смен',
    directory: '/var/www/shifts',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'recount-history',
    name: 'История пересчётов',
    directory: '/var/www/recount-history',
    dateField: 'date',
    isDirectory: true
  },
  {
    id: 'shift-handovers',
    name: 'Пересменки',
    directory: '/var/www/shift-handovers',
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
    id: 'orders',
    name: 'Заказы',
    directory: '/var/www/orders',
    dateField: 'createdAt',
    isDirectory: true
  },
  {
    id: 'app-logs',
    name: 'Логи приложения',
    directory: '/var/www/app-logs',
    dateField: 'timestamp',
    isDirectory: true
  },
  {
    id: 'recount-questions-photos',
    name: 'Фото вопросов пересчёта',
    directory: '/var/www/recount-questions',
    dateField: 'mtime',
    isDirectory: true,
    isPhotos: true
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

function setupDataCleanupAPI(app) {
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
