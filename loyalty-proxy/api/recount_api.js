/**
 * Recount API - Пересчёт товара
 * POST (с TIME_EXPIRED), GET, GET /expired, GET /pending, POST /rating, POST /notify
 *
 * REWRITTEN: Exact match with index.js inline code (2026-02-08)
 */

const fsp = require('fs').promises;
const path = require('path');
const fetch = require('node-fetch');
const { fileExists } = require('../utils/file_helpers');
const { isPaginationRequested, createPaginatedResponse } = require('../utils/pagination');

const DATA_DIR = process.env.DATA_DIR || '/var/www';
const SCRIPT_URL = process.env.SCRIPT_URL || "https://script.google.com/macros/s/AKfycbzaH6AqH8j9E93Tf4SFCie35oeESGfBL6p51cTHl9EvKq0Y5bfzg4UbmsDKB1B82yPS/exec";

function setupRecountAPI(app, { sendPushToPhone, calculateRecountPoints } = {}) {

  // POST /api/recount-reports - создание отчета пересчета с TIME_EXPIRED валидацией
  app.post('/api/recount-reports', async (req, res) => {
    try {
      console.log('POST /api/recount-reports:', JSON.stringify(req.body).substring(0, 200));

      // ============================================
      // TIME_EXPIRED валидация (аналогично пересменкам)
      // ============================================
      const shiftType = req.body.shiftType; // 'morning' | 'evening'

      if (shiftType) {
        // Загружаем настройки пересчёта
        const settingsFile = `${DATA_DIR}/points-settings/recount_points_settings.json`;
        let recountSettings = {
          morningStartTime: '08:00',
          morningEndTime: '14:00',
          eveningStartTime: '14:00',
          eveningEndTime: '23:00'
        };

        if (await fileExists(settingsFile)) {
          try {
            const settingsData = JSON.parse(await fsp.readFile(settingsFile, 'utf8'));
            recountSettings = { ...recountSettings, ...settingsData };
          } catch (e) {
            console.log('Ошибка чтения настроек пересчёта, используем дефолтные');
          }
        }

        // Получаем московское время (UTC+3)
        const now = new Date();
        const moscowTime = new Date(now.getTime() + 3 * 60 * 60 * 1000);
        const currentHours = moscowTime.getUTCHours();
        const currentMinutes = moscowTime.getUTCMinutes();
        const currentTimeMinutes = currentHours * 60 + currentMinutes;

        // Определяем дедлайн для текущей смены
        let deadlineTime;
        if (shiftType === 'morning') {
          deadlineTime = recountSettings.morningEndTime;
        } else {
          deadlineTime = recountSettings.eveningEndTime;
        }

        // Парсим время дедлайна
        const [deadlineHours, deadlineMinutes] = deadlineTime.split(':').map(Number);
        const deadlineTimeMinutes = deadlineHours * 60 + deadlineMinutes;

        // Проверяем, не просрочено ли время
        if (currentTimeMinutes > deadlineTimeMinutes) {
          console.log(`⏰ TIME_EXPIRED: Текущее время ${currentHours}:${currentMinutes}, дедлайн ${deadlineTime}`);
          return res.status(400).json({
            success: false,
            error: 'TIME_EXPIRED',
            message: 'К сожалению вы не успели пройти пересчёт вовремя'
          });
        }
      }

      // ============================================
      // Сохранение отчёта
      // ============================================
      const reportsDir = `${DATA_DIR}/recount-reports`;
      if (!await fileExists(reportsDir)) {
        await fsp.mkdir(reportsDir, { recursive: true });
      }

      const reportId = req.body.id || `report_${Date.now()}`;
      // Санитизируем имя файла: заменяем недопустимые символы на подчеркивания
      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      const reportFile = path.join(reportsDir, `${sanitizedId}.json`);

      // Загружаем настройки для вычисления reviewDeadline
      let adminReviewTimeout = 2; // часы по умолчанию
      const settingsFile = `${DATA_DIR}/points-settings/recount_points_settings.json`;
      if (await fileExists(settingsFile)) {
        try {
          const settings = JSON.parse(await fsp.readFile(settingsFile, 'utf8'));
          adminReviewTimeout = settings.adminReviewTimeout || 2;
        } catch (e) {}
      }

      const now = new Date();
      const reviewDeadline = new Date(now.getTime() + adminReviewTimeout * 60 * 60 * 1000);

      // Сохраняем отчет с временной меткой и статусом
      const reportData = {
        ...req.body,
        status: 'review', // Отчёт сразу идёт на проверку
        createdAt: now.toISOString(),
        savedAt: now.toISOString(),
        submittedAt: now.toISOString(),
        reviewDeadline: reviewDeadline.toISOString()
      };

      try {
        await fsp.writeFile(reportFile, JSON.stringify(reportData, null, 2), 'utf8');
        console.log('✅ Отчет пересчёта сохранен:', reportFile);
      } catch (writeError) {
        console.error('Ошибка записи файла:', writeError);
        throw writeError;
      }

      // Пытаемся также отправить в Google Apps Script (опционально)
      try {
        const response = await fetch(SCRIPT_URL, {
          method: 'post',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({
            action: 'createRecountReport',
            ...req.body
          }),
        });

        const contentType = response.headers.get('content-type');
        if (contentType && contentType.includes('application/json')) {
          const data = await response.json();
          if (data.success) {
            console.log('Отчет также отправлен в Google Apps Script');
          }
        }
      } catch (scriptError) {
        console.log('Google Apps Script не поддерживает это действие, отчет сохранен локально');
      }

      res.json({
        success: true,
        message: 'Отчет успешно сохранен',
        reportId: reportId,
        report: reportData
      });
    } catch (error) {
      console.error('Ошибка создания отчета:', error);
      res.status(500).json({
        success: false,
        error: error.message || 'Ошибка при сохранении отчета'
      });
    }
  });

  // GET /api/recount-reports - получить отчеты пересчета
  app.get('/api/recount-reports', async (req, res) => {
    try {
      console.log('GET /api/recount-reports:', req.query);

      const reportsDir = `${DATA_DIR}/recount-reports`;
      const reports = [];

      // Читаем отчеты из локальной директории
      if (await fileExists(reportsDir)) {
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(reportsDir, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const report = JSON.parse(content);
            reports.push(report);
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }

        // Сортируем по дате создания (новые первыми)
        reports.sort((a, b) => {
          const dateA = new Date(a.createdAt || a.savedAt || 0);
          const dateB = new Date(b.createdAt || b.savedAt || 0);
          return dateB - dateA;
        });

        // Применяем фильтры из query параметров
        let filteredReports = reports;
        if (req.query.shopAddress) {
          filteredReports = filteredReports.filter(r =>
            r.shopAddress && r.shopAddress.includes(req.query.shopAddress)
          );
        }
        if (req.query.employeeName) {
          filteredReports = filteredReports.filter(r =>
            r.employeeName && r.employeeName.includes(req.query.employeeName)
          );
        }
        if (req.query.date) {
          const filterDate = new Date(req.query.date);
          filteredReports = filteredReports.filter(r => {
            const reportDate = new Date(r.completedAt || r.createdAt || r.savedAt);
            return reportDate.toDateString() === filterDate.toDateString();
          });
        }

        if (isPaginationRequested(req.query)) {
          return res.json(createPaginatedResponse(filteredReports, req.query, 'reports'));
        } else {
          return res.json({ success: true, reports: filteredReports });
        }
      }

      // Если директории нет, возвращаем пустой список
      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения отчетов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // GET /api/recount-reports/expired - просроченные/failed/rejected отчеты
  app.get('/api/recount-reports/expired', async (req, res) => {
    try {
      console.log('GET /api/recount-reports/expired');

      const reportsDir = `${DATA_DIR}/recount-reports`;
      const reports = [];

      if (await fileExists(reportsDir)) {
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(reportsDir, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const report = JSON.parse(content);

            // Фильтруем только просроченные статусы: expired, failed, rejected
            const status = report.status;
            if (status === 'expired' || status === 'failed' || status === 'rejected') {
              reports.push(report);
            }
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e.message);
          }
        }

        // Сортируем по дате (новые сначала)
        reports.sort((a, b) => {
          const dateA = new Date(a.expiredAt || a.failedAt || a.rejectedAt || a.completedAt || 0);
          const dateB = new Date(b.expiredAt || b.failedAt || b.rejectedAt || b.completedAt || 0);
          return dateB - dateA;
        });

        console.log(`Найдено просроченных отчетов: ${reports.length}`);
        return res.json({ success: true, reports });
      }

      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения просроченных отчетов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // GET /api/pending-recount-reports - ожидающие (pending) пересчёты
  app.get('/api/pending-recount-reports', async (req, res) => {
    try {
      console.log('GET /api/pending-recount-reports');

      const reportsDir = `${DATA_DIR}/recount-reports`;
      const reports = [];

      if (await fileExists(reportsDir)) {
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));

        for (const file of files) {
          try {
            const filePath = path.join(reportsDir, file);
            const content = await fsp.readFile(filePath, 'utf8');
            const report = JSON.parse(content);

            // Фильтруем только pending отчёты
            if (report.status === 'pending') {
              reports.push(report);
            }
          } catch (e) {
            console.error(`Ошибка чтения файла ${file}:`, e);
          }
        }

        // Сортируем по дате создания (новые первыми)
        reports.sort((a, b) => {
          const dateA = new Date(a.createdAt || 0);
          const dateB = new Date(b.createdAt || 0);
          return dateB - dateA;
        });

        console.log(`Найдено pending пересчётов: ${reports.length}`);
        return res.json({ success: true, reports });
      }

      res.json({ success: true, reports: [] });
    } catch (error) {
      console.error('Ошибка получения pending пересчётов:', error);
      res.json({ success: true, reports: [] });
    }
  });

  // POST /api/recount-reports/:reportId/rating - оценка отчета пересчёта
  app.post('/api/recount-reports/:reportId/rating', async (req, res) => {
    try {
      let { reportId } = req.params;
      const { rating, adminName } = req.body;
      // Декодируем URL-кодированный reportId
      reportId = decodeURIComponent(reportId);
      // Санитизируем имя файла (как при сохранении)
      const sanitizedId = reportId.replace(/[^a-zA-Z0-9_\-]/g, '_');
      console.log(`POST /api/recount-reports/${reportId}/rating:`, req.body);
      console.log(`Санитизированный ID: ${sanitizedId}`);

      const reportsDir = `${DATA_DIR}/recount-reports`;
      let reportFile = path.join(reportsDir, `${sanitizedId}.json`);
      let actualFile = reportFile;

      if (!await fileExists(reportFile)) {
        console.error(`Файл не найден: ${reportFile}`);
        // Попробуем найти файл по частичному совпадению
        const files = (await fsp.readdir(reportsDir)).filter(f => f.endsWith('.json'));
        const matchingFile = files.find(f => f.includes(sanitizedId.substring(0, 20)));
        if (matchingFile) {
          console.log(`Найден файл по частичному совпадению: ${matchingFile}`);
          actualFile = path.join(reportsDir, matchingFile);
        } else {
          return res.status(404).json({ success: false, error: 'Отчет не найден' });
        }
      }

      // Читаем отчет
      const content = await fsp.readFile(actualFile, 'utf8');
      const report = JSON.parse(content);

      // Обновляем оценку и статус
      report.adminRating = rating;
      report.adminName = adminName;
      report.ratedAt = new Date().toISOString();
      report.status = 'confirmed';

      // Сохраняем обновленный отчет
      await fsp.writeFile(actualFile, JSON.stringify(report, null, 2), 'utf8');
      console.log('✅ Оценка сохранена для отчета:', reportId);

      // Загружаем настройки баллов пересчёта
      const settingsFile = `${DATA_DIR}/points-settings/recount_points_settings.json`;
      let settings = {
        minPoints: -3,
        zeroThreshold: 7,
        maxPoints: 1,
        minRating: 1,
        maxRating: 10
      };
      if (await fileExists(settingsFile)) {
        const settingsContent = await fsp.readFile(settingsFile, 'utf8');
        settings = { ...settings, ...JSON.parse(settingsContent) };
      }

      // Рассчитываем баллы эффективности
      const efficiencyPoints = calculateRecountPoints ? calculateRecountPoints(rating, settings) : 0;
      console.log(`📊 Рассчитанные баллы эффективности: ${efficiencyPoints} (оценка: ${rating})`);

      // Сохраняем баллы в efficiency-penalties
      const now = new Date();
      const monthKey = `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
      const today = now.toISOString().split('T')[0];
      const efficiencyDir = `${DATA_DIR}/efficiency-penalties`;

      if (!await fileExists(efficiencyDir)) {
        await fsp.mkdir(efficiencyDir, { recursive: true });
      }

      const penaltiesFile = path.join(efficiencyDir, `${monthKey}.json`);
      let penalties = [];
      if (await fileExists(penaltiesFile)) {
        penalties = JSON.parse(await fsp.readFile(penaltiesFile, 'utf8'));
        if (!Array.isArray(penalties)) penalties = (penalties && penalties.penalties) || [];
      }

      // Проверяем дубликат
      const sourceId = `recount_rating_${reportId}`;
      const exists = penalties.some(p => p.sourceId === sourceId);
      if (!exists) {
        const penalty = {
          id: `ep_${Date.now()}`,
          employeeId: report.employeePhone || report.employeeId,
          employeeName: report.employeeName,
          category: 'recount',
          categoryName: 'Пересчёт товара',
          date: today,
          points: Math.round(efficiencyPoints * 100) / 100,
          reason: `Оценка пересчёта: ${rating}/10`,
          sourceId: sourceId,
          sourceType: 'recount_report',
          createdAt: now.toISOString()
        };

        penalties.push(penalty);
        await fsp.writeFile(penaltiesFile, JSON.stringify(penalties, null, 2), 'utf8');
        console.log(`✅ Баллы эффективности сохранены: ${efficiencyPoints} для ${report.employeeName}`);
      }

      // Отправляем push-уведомление сотруднику
      const employeePhone = report.employeePhone;
      if (employeePhone && sendPushToPhone) {
        try {
          const title = 'Пересчёт оценён';
          const body = `Ваша оценка: ${rating}/10 (${efficiencyPoints > 0 ? '+' : ''}${Math.round(efficiencyPoints * 100) / 100} баллов)`;

          await sendPushToPhone(employeePhone, title, body, {
            type: 'recount_confirmed',
            rating: String(rating),
            points: String(efficiencyPoints)
          });
          console.log(`📱 Push-уведомление отправлено: ${employeePhone}`);
        } catch (pushError) {
          console.error('⚠️ Ошибка отправки push:', pushError.message);
        }
      }

      res.json({
        success: true,
        message: 'Оценка успешно сохранена',
        efficiencyPoints: Math.round(efficiencyPoints * 100) / 100
      });
    } catch (error) {
      console.error('❌ Ошибка оценки отчета:', error);
      res.status(500).json({ success: false, error: error.message });
    }
  });

  // POST /api/recount-reports/:reportId/notify - отправка push-уведомления
  app.post('/api/recount-reports/:reportId/notify', async (req, res) => {
    try {
      const { reportId } = req.params;
      console.log(`POST /api/recount-reports/${reportId}/notify`);

      // Здесь можно добавить логику отправки push-уведомлений
      res.json({ success: true, message: 'Уведомление отправлено' });
    } catch (error) {
      console.error('Ошибка отправки уведомления:', error);
      res.json({ success: true, message: 'Уведомление обработано' });
    }
  });

  console.log('✅ Recount API initialized');
}

module.exports = { setupRecountAPI };
