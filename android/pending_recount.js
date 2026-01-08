
// ========== API для непройденных пересчётов ==========
const PENDING_RECOUNT_DIR = '/var/www/pending-recount-reports';
const RECOUNT_REPORTS_DIR = '/var/www/recount-reports';
if (!fs.existsSync(PENDING_RECOUNT_DIR)) {
  fs.mkdirSync(PENDING_RECOUNT_DIR, { recursive: true });
}

// Используем тот же список магазинов
const SHOPS_FOR_RECOUNTS = SHOPS_FOR_SHIFTS;

// Генерация непройденных пересчётов на день
async function generateDailyPendingRecounts() {
  const today = new Date().toISOString().split('T')[0];

  // Удаляем файлы за предыдущие дни
  if (fs.existsSync(PENDING_RECOUNT_DIR)) {
    const files = fs.readdirSync(PENDING_RECOUNT_DIR).filter(f => f.endsWith('.json'));
    for (const file of files) {
      try {
        const content = fs.readFileSync(path.join(PENDING_RECOUNT_DIR, file), 'utf8');
        const report = JSON.parse(content);
        if (report.date && report.date !== today) {
          fs.unlinkSync(path.join(PENDING_RECOUNT_DIR, file));
          console.log('Удален старый pending recount: ' + file);
        }
      } catch (e) {
        console.error('Ошибка при очистке файла ' + file + ':', e.message);
      }
    }
  }

  console.log('Генерация непройденных пересчётов на ' + today);

  for (const shopAddress of SHOPS_FOR_RECOUNTS) {
    const pendingId = 'pending_recount_' + shopAddress.replace(/[^a-zA-Zа-яА-ЯёЁ0-9]/g, '_') + '_' + today;
    const pendingFile = path.join(PENDING_RECOUNT_DIR, pendingId + '.json');
    if (!fs.existsSync(pendingFile)) {
      const pendingReport = {
        id: pendingId,
        shopAddress: shopAddress,
        date: today,
        status: 'pending',
        completedBy: null,
        createdAt: new Date().toISOString()
      };
      fs.writeFileSync(pendingFile, JSON.stringify(pendingReport, null, 2), 'utf8');
    }
  }

  console.log('Сгенерировано пересчётов: ' + SHOPS_FOR_RECOUNTS.length);
}

// Cron job - каждый день в 00:00
cron.schedule('0 0 * * *', () => {
  console.log('Cron: Генерация непройденных пересчётов');
  generateDailyPendingRecounts();
}, {
  timezone: 'Europe/Moscow'
});

// GET - получить непройденные пересчёты
app.get('/api/pending-recount-reports', async (req, res) => {
  try {
    const today = new Date().toISOString().split('T')[0];
    const reports = [];

    if (fs.existsSync(PENDING_RECOUNT_DIR)) {
      const files = fs.readdirSync(PENDING_RECOUNT_DIR).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = fs.readFileSync(path.join(PENDING_RECOUNT_DIR, file), 'utf8');
          const report = JSON.parse(content);
          if (report.date === today && report.status === 'pending') {
            reports.push(report);
          }
        } catch (e) {
          console.error('Ошибка чтения ' + file + ':', e);
        }
      }
    }

    reports.sort((a, b) => a.shopAddress.localeCompare(b.shopAddress));
    res.json({ success: true, reports: reports });
  } catch (error) {
    console.error('Ошибка получения непройденных пересчётов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// POST - сгенерировать пересчёты (ручной вызов)
app.post('/api/pending-recount-reports/generate', async (req, res) => {
  try {
    await generateDailyPendingRecounts();
    res.json({ success: true, message: 'Пересчёты сгенерированы' });
  } catch (error) {
    console.error('Ошибка генерации пересчётов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Функция для закрытия pending при сдаче отчёта
function completePendingRecount(shopAddress, reportId) {
  const today = new Date().toISOString().split('T')[0];
  const pendingId = 'pending_recount_' + shopAddress.replace(/[^a-zA-Zа-яА-ЯёЁ0-9]/g, '_') + '_' + today;
  const pendingFile = path.join(PENDING_RECOUNT_DIR, pendingId + '.json');

  if (fs.existsSync(pendingFile)) {
    try {
      const content = fs.readFileSync(pendingFile, 'utf8');
      const report = JSON.parse(content);
      report.status = 'completed';
      report.completedBy = reportId;
      report.completedAt = new Date().toISOString();
      fs.writeFileSync(pendingFile, JSON.stringify(report, null, 2), 'utf8');
      console.log('Pending пересчёт закрыт: ' + pendingId);
      return true;
    } catch (e) {
      console.error('Ошибка закрытия pending recount:', e);
    }
  }
  return false;
}

// Проверка просроченных пересчётов
async function checkExpiredRecountReports() {
  console.log('Проверка просроченных отчётов пересчёта...');

  if (!fs.existsSync(RECOUNT_REPORTS_DIR)) {
    console.log('Директория пересчётов не существует');
    return;
  }

  const now = new Date();
  const moscowOffset = 3 * 60 * 60 * 1000;
  const moscowNow = new Date(now.getTime() + moscowOffset);
  const todayStr = moscowNow.toISOString().split('T')[0];

  const files = fs.readdirSync(RECOUNT_REPORTS_DIR).filter(f => f.endsWith('.json'));
  let expiredCount = 0;
  let deletedCount = 0;

  for (const file of files) {
    try {
      const filePath = path.join(RECOUNT_REPORTS_DIR, file);
      const content = fs.readFileSync(filePath, 'utf8');
      const report = JSON.parse(content);

      if (report.adminRating || report.ratedAt || report.status === 'expired') {
        if (report.status === 'expired' && report.expiredAt) {
          const expiredDate = new Date(report.expiredAt);
          const daysSinceExpired = (now - expiredDate) / (1000 * 60 * 60 * 24);
          if (daysSinceExpired > 90) {
            fs.unlinkSync(filePath);
            console.log('Удалён просроченный пересчёт старше 90 дней: ' + file);
            deletedCount++;
          }
        }
        continue;
      }

      const completedAt = new Date(report.completedAt);
      const completedMoscow = new Date(completedAt.getTime() + moscowOffset);
      const completedDateStr = completedMoscow.toISOString().split('T')[0];

      if (completedDateStr < todayStr) {
        report.status = 'expired';
        report.expiredAt = now.toISOString();
        fs.writeFileSync(filePath, JSON.stringify(report, null, 2), 'utf8');
        console.log('Пересчёт просрочен: ' + file);
        expiredCount++;
      }
    } catch (e) {
      console.error('Ошибка обработки файла ' + file + ':', e.message);
    }
  }

  console.log('Проверка пересчётов завершена. Просрочено: ' + expiredCount + ', удалено: ' + deletedCount);
}

// Cron job - в 00:00 по Москве
cron.schedule('0 0 * * *', () => {
  console.log('Cron: Проверка просроченных пересчётов');
  checkExpiredRecountReports();
}, {
  timezone: 'Europe/Moscow'
});

// GET - получить просроченные пересчёты
app.get('/api/recount-reports/expired', async (req, res) => {
  try {
    console.log('GET /api/recount-reports/expired');
    const reports = [];

    if (fs.existsSync(RECOUNT_REPORTS_DIR)) {
      const files = fs.readdirSync(RECOUNT_REPORTS_DIR).filter(f => f.endsWith('.json'));
      for (const file of files) {
        try {
          const content = fs.readFileSync(path.join(RECOUNT_REPORTS_DIR, file), 'utf8');
          const report = JSON.parse(content);
          if (report.status === 'expired') {
            reports.push(report);
          }
        } catch (e) {
          console.error('Ошибка чтения ' + file + ':', e);
        }
      }
    }

    reports.sort((a, b) => new Date(b.expiredAt) - new Date(a.expiredAt));
    console.log('Найдено просроченных пересчётов: ' + reports.length);
    res.json({ success: true, reports: reports });
  } catch (error) {
    console.error('Ошибка получения просроченных пересчётов:', error);
    res.status(500).json({ success: false, error: error.message });
  }
});

// Запускаем при старте
generateDailyPendingRecounts();
checkExpiredRecountReports();
